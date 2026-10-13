class_name MKOnlineController
extends MKController
## Partita online in lockstep (come Kingsburg). Tutti i dispositivi creano il motore dalla stessa
## configurazione (con lo stesso seme) pubblicata dall'host e applicano le stesse azioni nello stesso
## ordine: sul database viaggiano solo le azioni, numerate (mageknight/rooms/<codice>/acts/<n>).
## - Le azioni del proprio eroe le decide la persona davanti al dispositivo (submit dalla UI): vengono
##   pubblicate come mossa n e applicate solo quando la scrittura riesce (la prima mossa n scritta vale).
## - Le azioni degli eroi IA (e dei posti rimasti liberi) le decide l'IA sul dispositivo dell'host.
## - Se una persona tace per un minuto, l'host la segna assente e fa giocare l'IA al suo posto finché
##   non torna (il segnale di presenza la riporta in gioco).
## - Chi rientra scarica tutte le mosse e le rigioca ("ricollegamento…").
## - L'host scrive ogni FP_EVERY mosse l'impronta dello stato (fp/<n>); gli altri la confrontano con la
##   propria: se diverge, ricostruiscono la partita rigiocando tutte le mosse (desincronia).
## Nota: in lockstep ogni dispositivo ha lo stato completo, comprese le mani degli altri giocatori
## (l'interfaccia non le mostra, ma non sono segrete per chi smonta il programma).

signal status(msg: String)                     # messaggio di stato per la UI ("" = nessuno)
signal waiting_for(p: int, slow: bool)         # si aspetta la mossa del giocatore p (-1 = nessuno)
signal catching_up(active: bool)               # ricollegamento in corso (si rigiocano le mosse)
signal desync(n: int)                          # impronta diversa da quella dell'host dopo n mosse
signal finished                                # partita finita (stanza chiusa)

const FP_EVERY := 20
const MAX_ACT_LEN := 600

var net: MKNet
var code := ""
var seat := -1                 # giocatore di questo dispositivo
var role := "guest"            # "host" | "guest"
var n := 0                     # mosse applicate = numero della prossima mossa
var backlog: Array = []        # mosse già registrate (rientro)
var catchup := false
var away := {}                 # (host) giocatori umani assenti: gioca l'IA
var alive := true
var desynced := false          # desincronia non risolta rigiocando
var poll_s := 0.8              # attesa tra due letture quando si aspetta un altro giocatore
var away_ms := 60000           # silenzio dopo il quale l'host fa giocare l'IA
var heartbeat_s := 5.0

var _outbox: Array = []        # azioni locali da pubblicare
var _publishing := false
var _pumping := false
var _started := false
var _fp_local := {}            # n -> impronta locale (da confrontare con quella dell'host)
var _fp_checked_at := 0
var _resyncs := 0
var _wait_n := -1
var _wait_t0 := 0
var _seen_val = null
var _seen_t := 0
var _polls := 0
var _away_checked := {}        # giocatore -> ms dell'ultimo controllo del ritorno
var _last_status := ""


## Da chiamare prima di start(): net (già collegato, diventa figlio del controllore), codice della stanza,
## giocatore di questo dispositivo, ruolo, mosse già registrate (per il rientro).
func setup(p_net: MKNet, p_code: String, p_seat: int, p_role: String, p_backlog: Array = []) -> void:
	net = p_net
	code = p_code
	seat = p_seat
	role = p_role
	backlog = p_backlog
	catchup = not backlog.is_empty()
	if net != null and net.get_parent() != self:
		if net.get_parent() != null:
			net.get_parent().remove_child(net)
		add_child(net)
	var t := OS.get_environment("MK_AWAY_MS")
	if t != "":
		away_ms = int(t)


## Crea il motore dalla configurazione pubblicata dall'host (uguale su tutti i dispositivi).
## Una seconda chiamata (es. dalla vista) non fa nulla.
func start(c: Dictionary) -> void:
	if _started:
		return
	_started = true
	MKDB.ensure()
	cfg = MKEngine._intify(c.duplicate(true))
	eng = MKEngine.create(cfg)
	actions = []
	autosave = false
	_seats_from_cfg()
	human_seats = [seat] if seat >= 0 else []
	if catchup:
		catching_up.emit(true)
		_say("Ricollegamento… (%d mosse da rigiocare)" % backlog.size())
	changed.emit()
	if is_inside_tree():
		_begin()


func _enter_tree() -> void:
	if _started:
		_begin.call_deferred()


func _exit_tree() -> void:
	alive = false


func _begin() -> void:
	if _pumping or not is_inside_tree():
		return
	alive = true
	_pump()
	_heartbeat_loop()


func is_host() -> bool:
	return role == "host"


func runs_ai() -> bool:
	return role == "host"


## Il dispositivo può mandare un'azione ora (turno proprio, niente invii in corso, niente ricollegamento).
func is_local_turn() -> bool:
	return super.is_local_turn() and not catchup and not _publishing and _outbox.is_empty()


## Chi gioca quel giocatore sull'host: IA, posti liberi e assenti.
func host_drives(p: int) -> bool:
	if role != "host" or p < 0 or p in human_seats:
		return false
	return p == MKEngine.DUMMY or _seat_is_ai(p) or ai_level.has(p) or away.has(p)


func submit(a: Dictionary) -> void:
	if eng != null and super.is_local_turn() and (_publishing or not _outbox.is_empty()):
		_reject("Attendi: invio della mossa in corso…")
		return
	if catchup:
		_reject("Attendi la fine del ricollegamento")
		return
	super.submit(a)


## Le azioni non si applicano subito: si pubblicano come mossa n e si applicano in ordine.
func _commit(a: Dictionary) -> void:
	var rt = MKEngine.sanitize(JSON.parse_string(JSON.stringify(a)))
	if rt.has("_err") or eng.check(rt) != "":
		_reject("Azione non trasmissibile: " + str(rt.get("_err", eng.check(rt))))
		push_warning("MKOnlineController: azione non valida dopo JSON: " + JSON.stringify(a))
		return
	_outbox.append(a)


## In online l'IA la fa girare il ciclo principale (_pump), non il controllore locale.
func _drive() -> void:
	pass


# ================================================================== ciclo principale

func _pump() -> void:
	_pumping = true
	var k := 0
	while alive and is_inside_tree():
		if eng == null:
			break
		# 1. mosse già registrate (rientro): si rigiocano senza attese
		if n < backlog.size():
			_apply_act(backlog[n])
			k += 1
			if k % 40 == 0 or n == backlog.size():
				_say("Ricollegamento… %d/%d" % [n, backlog.size()])
				await get_tree().process_frame
			continue
		if catchup:
			catchup = false
			backlog = []
			catching_up.emit(false)
			_say("")
			changed.emit()
			continue
		if game_over():
			break
		# 2. azione di questo dispositivo da pubblicare
		if not _outbox.is_empty():
			var a: Dictionary = _outbox.pop_front()
			if eng.check(a) != "" or not super.is_local_turn():
				_reject("La situazione è cambiata: azione annullata")
				continue
			await _publish(a)
			continue
		var p := eng.actor()
		# 3. l'host decide per IA, posti liberi e assenti
		if role == "host" and host_drives(p):
			if away.has(p) and await _back_from_away(p):
				continue
			if not alive:
				break
			waiting_for.emit(-1, false)
			if paused:
				await get_tree().create_timer(0.2).timeout
				continue
			ai_thinking.emit(p)
			var d: float = SPEEDS[speed]
			if d > 0.0:
				await get_tree().create_timer(d).timeout
			if not alive or eng.actor() != p or not _outbox.is_empty():
				continue
			var a := decide_for(p)
			if a.is_empty() or eng.check(a) != "":
				var fb := MKController.fallback_decide(eng)
				if fb.is_empty() or eng.check(fb) != "":
					_say("L'IA non trova una mossa per %s" % eng.pname(p))
					await get_tree().create_timer(2.0).timeout
					continue
				a = fb
			await _publish(a)
			continue
		# 4. si aspetta la mossa n dal database (anche nel proprio turno: l'IA dell'host potrebbe
		#    averla giocata al nostro posto durante un'assenza)
		var act := await net.get_act(code, n)
		if not alive:
			break
		if not act.is_empty() and not act.has("_err"):
			_apply_act(act)
			continue
		if act.has("_err"):
			_say("Rete non raggiungibile, riprovo… (%s)" % net.last_error)
		elif _last_status.begins_with("Rete"):
			_say("")
		var mine := p in human_seats
		if not mine:
			await _watch_wait(p)
		else:
			waiting_for.emit(-1, false)
		await _check_fp()
		await _nap(3.0 if mine else poll_s)
	_pumping = false
	if alive and game_over():
		_finish()


## Dorme fino a t secondi, ma si sveglia subito se arriva un'azione locale.
func _nap(t: float) -> void:
	var left := t
	while left > 0.0 and alive and is_inside_tree() and _outbox.is_empty():
		await get_tree().create_timer(minf(0.1, left)).timeout
		left -= 0.1


## Applica una mossa del registro. Le mosse non valide (giocatore sbagliato o azione illegale) si
## saltano: tutti i dispositivi hanno lo stesso stato, quindi le saltano tutti.
func _apply_act(act: Dictionary) -> void:
	var mine_turn := super.is_local_turn()
	var who := int(act.get("s", -1)) if (act.get("s") is int or act.get("s") is float) else -1
	var parsed = JSON.parse_string(str(act.get("a", "")))
	var a := MKEngine.sanitize(parsed)
	n += 1
	if a.has("_err") or who != eng.actor() or eng.check(a) != "":
		push_warning("MKOnlineController: mossa %d saltata (%s)" % [n - 1, str(act).substr(0, 200)])
		if mine_turn and who == seat:
			_reject("Mossa rifiutata: " + (str(a.get("_err", "")) if a.has("_err") else eng.check(a)))
	else:
		var r := eng.apply(a)
		if r.get("ok", false):
			actions.append(a)
	if n % FP_EVERY == 0:
		var fp := eng.fingerprint()
		if role == "host":
			if not catchup:
				net.put_fp(code, n, fp)
		else:
			_fp_local[n] = fp
	if not catchup:
		changed.emit()


## Pubblica l'azione come mossa n; se un altro dispositivo ha già scritto la mossa n vale quella.
func _publish(a: Dictionary) -> void:
	_publishing = true
	var my_n := n
	var who := eng.actor()
	var body := {"s": who, "a": JSON.stringify(a)}
	if str(body["a"]).length() > MAX_ACT_LEN:
		push_warning("MKOnlineController: azione troppo lunga " + str(body["a"]))
	while alive:
		if await net.post_act(code, my_n, body):
			if _last_status.begins_with("Rete"):
				_say("")
			if n == my_n:
				_apply_act(body)
			break
		if not alive:
			break
		var ex := await net.get_act(code, my_n)
		if not ex.is_empty() and not ex.has("_err"):
			if n == my_n:
				if who == seat and str(ex.get("a", "")) != body["a"]:
					_say("Eri via: l'IA ha giocato al tuo posto.")
				_apply_act(ex)
			break
		_say("Rete non raggiungibile, riprovo… (%s)" % net.last_error)
		await get_tree().create_timer(2.0).timeout
	_publishing = false


## (host) Si aspetta la mossa di una persona: se tace da un minuto, la si segna assente.
func _watch_wait(p: int) -> void:
	var now := Time.get_ticks_msec()
	if _wait_n != n:
		_wait_n = n
		_wait_t0 = now
		_seen_t = now
		_seen_val = null
		_polls = 0
	var slow := now - _wait_t0 > away_ms
	waiting_for.emit(p, slow)
	_polls += 1
	if role != "host" or p < 0 or p == MKEngine.DUMMY or _polls % 4 != 1:
		return
	var st := await net.seat(code, p)
	if not alive or st.is_empty():
		return
	var seen = st.get("seen", null)
	if seen != _seen_val:
		_seen_val = seen
		_seen_t = Time.get_ticks_msec()
	now = Time.get_ticks_msec()
	var silent := now - _seen_t > maxi(away_ms * 3 / 4, 1000) and now - _wait_t0 > away_ms
	if st.get("away", false) or silent:
		await net.set_away(code, p, true)
		away[p] = true
		_away_checked[p] = Time.get_ticks_msec()
		waiting_for.emit(-1, false)
		_say("%s non risponde: per ora gioca l'IA." % eng.pname(p))


## (host) Un assente è tornato? (il suo segnale di presenza toglie il segno "away")
func _back_from_away(p: int) -> bool:
	var now := Time.get_ticks_msec()
	if now - int(_away_checked.get(p, 0)) < 4000:
		return false
	_away_checked[p] = now
	var st := await net.seat(code, p)
	if not st.is_empty() and not st.get("away", false):
		away.erase(p)
		_wait_n = -1
		_say("%s è tornato in partita." % eng.pname(p))
		return true
	return false


## Confronta le impronte con quelle dell'host (al massimo ogni 5 secondi).
func _check_fp() -> void:
	if role == "host" or _fp_local.is_empty() or desynced:
		return
	var now := Time.get_ticks_msec()
	if now - _fp_checked_at < 5000:
		return
	_fp_checked_at = now
	var keys := _fp_local.keys()
	keys.sort()
	for k in keys:
		var theirs := await net.get_fp(code, int(k))
		if not alive:
			return
		if theirs == "_err" or theirs == "":
			return          # rete giù o host ancora indietro: si riprova dopo
		if theirs == _fp_local[k]:
			_fp_local.erase(k)
			continue
		push_warning("MKOnlineController: desincronia alla mossa %d" % int(k))
		desync.emit(int(k))
		await _resync(int(k))
		return


## Ricostruisce la partita dalla configurazione rigiocando tutte le mosse registrate.
func _resync(at: int) -> void:
	_resyncs += 1
	if _resyncs > 2:
		desynced = true
		_fp_local.clear()
		_say("Partita non sincronizzata con l'host (mossa %d): conviene uscire e rientrare." % at)
		return
	_say("Partita non sincronizzata: la ricostruisco…")
	var all := await net.get_acts(code)
	if not alive:
		return
	eng = MKEngine.create(cfg)
	actions = []
	n = 0
	_fp_local.clear()
	backlog = all
	catchup = not backlog.is_empty()
	if catchup:
		catching_up.emit(true)
	changed.emit()


func _heartbeat_loop() -> void:
	while alive and is_inside_tree() and seat >= 0:
		net.heartbeat(code, seat)
		await get_tree().create_timer(heartbeat_s).timeout
		if game_over():
			break


func _finish() -> void:
	waiting_for.emit(-1, false)
	if role == "host":
		await net.set_status(code, "over")
	net.remember_room("")
	finished.emit()


func _say(msg: String) -> void:
	if msg == _last_status:
		return
	_last_status = msg
	status.emit(msg)


## Messaggio di stato corrente (per la UI che si collega dopo).
func status_text() -> String:
	return _last_status


## Esce dalla partita (la stanza resta: si può rientrare con lo stesso codice).
func leave() -> void:
	alive = false
