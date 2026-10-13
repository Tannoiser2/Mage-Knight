class_name MKController
extends Node
## Controllore locale della partita (vedi /home/claude/work/CONTROLLER.md).
## Possiede il motore, riceve le azioni dell'interfaccia (submit), le applica (_commit), fa giocare
## l'IA per i posti non umani (_drive) con un ritmo visibile, e salva automaticamente la partita
## in user:// (Continua partita). La vista non chiama mai eng.apply: passa sempre da submit().
## MKOnlineController (agente NET) estende questa classe e ridefinisce _commit/runs_ai/start.

signal changed                 # dopo ogni azione applicata (la UI si aggiorna da eng.s)
signal rejected(msg: String)   # azione rifiutata (motivo in italiano)
signal ai_thinking(p: int)     # l'IA sta per decidere per il giocatore p (per la UI)

const SAVE_PATH := "user://mk_autosave.json"
const AI_PATH := "res://scripts/core/ai.gd"
## Ritmo dell'IA: secondi di attesa prima di ogni azione (Lento, Normale, Veloce, Istantaneo).
const SPEEDS := [1.1, 0.55, 0.2, 0.0]
const SPEED_NAMES := ["Lento", "Normale", "Veloce", "Istantaneo"]

var eng: MKEngine
var cfg: Dictionary = {}
var human_seats: Array = []        # indici dei giocatori umani SU QUESTO dispositivo
var ai_level: Dictionary = {}      # indice -> livello (1..3) dei posti IA
var actions: Array = []            # azioni applicate (per il salvataggio/replay)
var speed := 1                     # indice in SPEEDS
var autosave := true
var paused := false                # true = l'IA non procede (es. finestra aperta in hotseat)
var last_error := ""

var _AI = null                     # script MKAI caricato dinamicamente (o null)
var _ai_failures := 0              # risposte non valide dell'IA: oltre 3 si usa il ripiego
var _ai_checked := false
var _driving := false
var _drive_serial := 0
var _save_pending := false


# ================================================================== avvio

func start(c: Dictionary) -> void:
	MKDB.ensure()
	cfg = c.duplicate(true)
	eng = MKEngine.create(cfg)
	actions = []
	_seats_from_cfg()
	_after_change()


## Riprende una partita da uno stato salvato (dizionario di save_data()).
func resume(data: Dictionary) -> bool:
	MKDB.ensure()
	var st = data.get("state")
	if not (st is Dictionary):
		return false
	cfg = data.get("cfg", st.get("cfg", {}))
	eng = MKEngine.from_state(st)
	if eng == null:
		return false
	actions = data.get("actions", [])
	speed = int(data.get("speed", speed))
	_seats_from_cfg()
	if data.get("human_seats") is Array:
		human_seats = []
		for x in data["human_seats"]:
			human_seats.append(int(x))
	_after_change()
	return true


func _seats_from_cfg() -> void:
	human_seats = []
	ai_level = {}
	var pl: Array = cfg.get("players", [])
	for i in range(pl.size()):
		var p: Dictionary = pl[i]
		if str(p.get("ctrl", "human")) == "ai":
			ai_level[i] = int(p.get("ai_level", 2))
		else:
			human_seats.append(i)


func _after_change() -> void:
	changed.emit()
	_drive()


# ================================================================== azioni

## Azione di un umano dall'interfaccia.
func submit(a: Dictionary) -> void:
	if eng == null:
		return
	if not is_local_turn():
		_reject("Non è il tuo turno")
		return
	var err := eng.check(a)
	if err != "":
		_reject(err)
		return
	_commit(a)


func _reject(msg: String) -> void:
	last_error = msg
	rejected.emit(msg)


## Applica localmente (l'online lo ridefinisce: pubblica e applica in ordine).
func _commit(a: Dictionary) -> void:
	var r: Dictionary = eng.apply(a)
	if not r.get("ok", false):
		_reject(str(r.get("err", "Azione non valida")))
		return
	actions.append(a)
	_schedule_save()
	_after_change()


func runs_ai() -> bool:
	return true


func is_local_turn() -> bool:
	return eng != null and eng.actor() in human_seats


func is_ai_seat(p: int) -> bool:
	if p < 0:
		return false
	if p == MKEngine.DUMMY:
		return true
	return not (p in human_seats) and (ai_level.has(p) or _seat_is_ai(p))


func _seat_is_ai(p: int) -> bool:
	if eng == null or p >= eng.s.players.size():
		return false
	return str(eng.s.players[p].get("ctrl", "human")) == "ai"


func game_over() -> bool:
	return eng == null or str(eng.s.get("phase", "")) == "game_over"


func set_speed(k: int) -> void:
	speed = clampi(k, 0, SPEEDS.size() - 1)


# ================================================================== IA

func _drive() -> void:
	if eng == null or game_over() or not runs_ai() or paused:
		return
	var p := eng.actor()
	if p < 0 or not is_ai_seat(p):
		return
	if _driving:
		return
	_driving = true
	_drive_serial += 1
	var serial := _drive_serial
	ai_thinking.emit(p)
	var d: float = SPEEDS[speed]
	if d > 0.0 and is_inside_tree():
		await get_tree().create_timer(d).timeout
	elif is_inside_tree():
		await get_tree().process_frame
	_driving = false
	if serial != _drive_serial or eng == null or game_over() or paused or not is_inside_tree():
		return
	if eng.actor() != p or not is_ai_seat(p):
		_drive()
		return
	var a := decide_for(p)
	if a.is_empty():
		push_warning("MKController: nessuna azione per l'IA (giocatore %d)" % p)
		return
	if eng.check(a) != "":
		# azione dell'IA non valida: ripiego
		var fb := fallback_decide(eng)
		if fb.is_empty() or eng.check(fb) != "":
			push_warning("MKController: IA bloccata (%s)" % eng.check(a))
			return
		a = fb
	_commit(a)


## Riprende a far giocare l'IA (dopo una pausa).
func kick() -> void:
	_drive()


func _load_ai() -> void:
	if _ai_checked:
		return
	_ai_checked = true
	if ResourceLoader.exists(AI_PATH):
		var sc = load(AI_PATH)
		if sc is Script and (sc as Script).can_instantiate():
			for m in (sc as Script).get_script_method_list():
				if str(m.get("name", "")) == "decide":
					_AI = sc
					break


func decide_for(p: int) -> Dictionary:
	_load_ai()
	var lvl := int(ai_level.get(p, 2))
	if _AI != null and _ai_failures < 3:
		var a = _AI.call("decide", eng, lvl)
		if a is Dictionary and not a.is_empty() and eng.check(a) == "":
			return a
		_ai_failures += 1
		push_warning("MKController: risposta non valida dell'IA (%d): %s" % [_ai_failures, str(a)])
	return fallback_decide(eng)


## IA di ripiego: prima voce sensata di eng.available() (prima opzione per le decisioni).
static func fallback_decide(e: MKEngine) -> Dictionary:
	var av: Array = e.available()
	if av.is_empty():
		return {}
	if e.s.pending != null or str(e.s.phase) == "tactics":
		return av[0]["a"]
	var by := {}
	for x in av:
		var t := str(x["a"].get("t", ""))
		if not by.has(t):
			by[t] = []
		by[t].append(x["a"])
	if e.s.combat != null:
		for t in ["attack", "block"]:
			if by.has(t):
				return by[t][0]
		if by.has("damage"):
			for a in by["damage"]:
				if str(a.get("to", "")) == "hero":
					return a
			return by["damage"][0]
		if by.has("next"):
			return by["next"][0]
		return av[0]["a"]
	for t in ["announce_end", "end_turn", "rest"]:
		if by.has(t):
			return by[t][0]
	return av[0]["a"]


# ================================================================== salvataggio

func save_data() -> Dictionary:
	return {"v": 1, "cfg": cfg, "state": eng.s if eng != null else {}, "actions": actions,
		"human_seats": human_seats, "speed": speed, "time": Time.get_datetime_string_from_system()}


func _schedule_save() -> void:
	if not autosave or _save_pending or not is_inside_tree():
		return
	_save_pending = true
	await get_tree().create_timer(1.0).timeout
	_save_pending = false
	save_now()


func save_now() -> void:
	if not autosave or eng == null:
		return
	if game_over():
		clear_save()
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify(save_data()))
	f.close()


static func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


static func load_save() -> Dictionary:
	if not FileAccess.file_exists(SAVE_PATH):
		return {}
	var j = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	return j if j is Dictionary else {}


static func clear_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


## Breve descrizione del salvataggio per il menu.
static func save_summary() -> String:
	var d := load_save()
	var st = d.get("state")
	if not (st is Dictionary):
		return ""
	var scn = st.get("scn", {})
	var nm := str(scn.get("name_it", "")) if scn is Dictionary else ""
	var heroes := []
	for p in st.get("players", []):
		heroes.append(MKUI.HERO_NAME.get(str(p.get("hero", "")), str(p.get("hero", ""))))
	return "%s · round %d · %s" % [nm, int(st.get("round", 1)), ", ".join(heroes)]
