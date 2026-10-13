extends SceneTree
## Prova del gioco online: due istanze headless (host e ospite) giocano una partita intera sul finto
## Firebase (tests/firebase_mock.py, che applica le regole vere) passando dalla sala d'attesa
## (MKOnlineLobby) e dal controllore online (MKOnlineController). Le persone sono simulate dall'IA.
## Lo avvia tests/online_play.sh; variabili d'ambiente:
##   MK_ROLE=host|guest   MK_CODEFILE=file per passarsi il codice della stanza
##   MK_SESSION=file dell'identità (diverso per ogni istanza: user:// è in comune)
##   MK_PHASE=drop (l'ospite esce di colpo alla mossa MK_DROP_AT) | back (rientra con lo stesso codice)
##   MK_CORRUPT_AT=n (l'ospite altera di proposito il proprio stato alla mossa n: deve accorgersi della
##   desincronia e ricostruire la partita)   MK_SPEED=0..3 ritmo dell'IA dell'host   MK_SCEN=scenario
## Partita: Arythea (host), Goldyx (ospite), Tovak (IA facile), Norowas (posto UMANO lasciato libero:
## lo gioca l'IA dell'host). Alla fine ognuno stampa "MKTEST impronta <mosse> <impronta>": devono coincidere.

var lobby: MKOnlineLobby
var ctrl: MKOnlineController
var t0 := 0
var corrupted := false


func _init() -> void:
	t0 = Time.get_ticks_msec()
	_run()


func _wait(s: float) -> void:
	await create_timer(s).timeout


func _out(msg: String) -> void:
	print("MKTEST ", msg)


func _run() -> void:
	await process_frame
	MKDB.ensure()
	var role := OS.get_environment("MK_ROLE")
	var cf := OS.get_environment("MK_CODEFILE")
	var phase := OS.get_environment("MK_PHASE")
	var scen := OS.get_environment("MK_SCEN")
	if scen == "":
		scen = "first_recon"
	lobby = MKOnlineLobby.new()
	var seed := int(OS.get_environment("MK_SEED")) if OS.get_environment("MK_SEED") != "" else 4242
	lobby.cfg = {"scenario": scen, "seed": seed, "options": {"set": "base"}, "players": [
		{"hero": "arythea", "ctrl": "human", "ai_level": 2, "name": "Arythea"},
		{"hero": "goldyx", "ctrl": "human", "ai_level": 2, "name": "Goldyx"},
		{"hero": "tovak", "ctrl": "ai", "ai_level": 1, "name": "Tovak (IA)"},
		{"hero": "norowas", "ctrl": "human", "ai_level": 2, "name": "Norowas"}]}
	root.add_child(lobby)
	lobby.game_started.connect(func(c): ctrl = c)
	await process_frame
	lobby.name_edit.text = "Host" if role == "host" else "Ospite"
	if role == "host":
		await lobby.do_create()
		var code: String = lobby.code
		if code == "":
			_out("ERRORE stanza non creata: " + lobby.net.last_error)
			quit(1)
			return
		_out("stanza " + code)
		var f := FileAccess.open(cf, FileAccess.WRITE)
		f.store_string(code)
		f.close()
		while true:
			var room: Dictionary = await lobby.net.room(code)
			if MKNet._as_dict(room.get("seats", {})).size() >= 2:
				break
			if Time.get_ticks_msec() - t0 > 60000:
				_out("ERRORE nessun ospite")
				quit(1)
				return
			await _wait(0.5)
		await lobby.do_start()
	else:
		var code := ""
		while code == "":
			if FileAccess.file_exists(cf):
				code = FileAccess.get_file_as_string(cf).strip_edges()
			await _wait(0.3)
		lobby.code_edit.text = code
		await lobby.do_join()
		if lobby.seat < 0:
			_out("ERRORE ingresso non riuscito")
			quit(1)
			return
		_out("posto %d, ruolo %s" % [lobby.seat, lobby.role])
	while ctrl == null:
		await process_frame
		if Time.get_ticks_msec() - t0 > 120000:
			_out("ERRORE la partita non parte")
			quit(1)
			return
	ctrl.speed = int(OS.get_environment("MK_SPEED")) if OS.get_environment("MK_SPEED") != "" else 3
	ctrl.status.connect(func(m): if m != "": _out("stato: " + m))
	ctrl.desync.connect(func(k): _out("desincronia rilevata alla mossa %d" % k))
	if phase == "back":
		_out("rientro: %d mosse da rigiocare" % ctrl.backlog.size())
	var drop_at := int(OS.get_environment("MK_DROP_AT")) if OS.get_environment("MK_DROP_AT") != "" else 40
	var corrupt_at := int(OS.get_environment("MK_CORRUPT_AT")) if OS.get_environment("MK_CORRUPT_AT") != "" else -1
	var last_sub := -1
	var rejected := [false]
	ctrl.rejected.connect(func(m):
		_out("rifiutata: " + m)
		rejected[0] = true)
	while true:
		await process_frame
		if Time.get_ticks_msec() - t0 > 900000:
			_out("ERRORE tempo scaduto alla mossa %d" % ctrl.n)
			quit(2)
			return
		if ctrl.game_over() and not ctrl.catchup:
			await _wait(1.0)
			_out("impronta %d %s" % [ctrl.n, ctrl.eng.fingerprint()])
			_out("risultato " + JSON.stringify(ctrl.eng.s.get("result", {})).substr(0, 300))
			quit(0)
			return
		if phase == "drop" and ctrl.n >= drop_at:
			_out("esco di colpo alla mossa %d" % ctrl.n)
			quit(0)
			return
		if corrupt_at >= 0 and not corrupted and ctrl.n >= corrupt_at and not ctrl.catchup:
			corrupted = true
			ctrl.eng.s.players[ctrl.seat]["fame"] = int(ctrl.eng.s.players[ctrl.seat]["fame"]) + 1
			_out("stato alterato di proposito alla mossa %d" % ctrl.n)
		# la "persona" davanti al dispositivo: una mossa alla volta
		if ctrl.is_local_turn() and (last_sub != ctrl.n or rejected[0]):
			var a := MKController.fallback_decide(ctrl.eng) if rejected[0] else ctrl.decide_for(ctrl.seat)
			rejected[0] = false
			last_sub = ctrl.n
			ctrl.submit(a)
