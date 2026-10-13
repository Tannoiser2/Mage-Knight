extends SceneTree
## Screenshot dell'interfaccia: combattimento tra giocatori in hotseat (due umani) e assalto cooperativo
## con un alleato IA. Si premono i veri bottoni dell'HUD.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-driver opengl3 -s res://tests/pvp_ui.gd -- <prefisso>
## Stampa "PVPUI ..." per ogni passo e "PVPUI done errors=N".

var out := "/tmp/pvpui"
var main: MKMain
var view: MKGameView
var errors := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	create_timer(600.0).timeout.connect(func():
		printerr("pvp_ui: tempo scaduto")
		quit(1))
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await _wait(4)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s_%s.png" % [out, name])
	print("SHOT ", name)

func err(msg: String) -> void:
	errors += 1
	print("PVPUI ERRORE: ", msg)

func note(msg: String) -> void:
	print("PVPUI ", msg)

func eng() -> MKEngine:
	return view.ctrl.eng

func _buttons(n: Node, outl: Array) -> void:
	for c in n.get_children():
		if c is Button and c.is_visible_in_tree():
			outl.append(c)
		_buttons(c, outl)

func press(txt: String, required := true) -> bool:
	var l: Array = []
	_buttons(view, l)
	l.reverse()
	for b in l:
		if not b.disabled and b.text.findn(txt) >= 0:
			note("premo '%s'" % b.text.replace("\n", " "))
			b.pressed.emit()
			await _wait(5)
			return true
	if required:
		var t: Array = []
		for b in l:
			t.append(b.text)
		err("bottone '%s' non trovato; visibili: %s" % [txt, str(t)])
	return false

func choose_label(part: String) -> void:
	var e := eng()
	if e.s.pending == null:
		err("nessuna decisione in sospeso (cercavo '%s')" % part)
		return
	await press(part)

func _start(cfg: Dictionary) -> void:
	for c in root.get_children():
		c.queue_free()
	await _wait(2)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(5)
	main.start_game(cfg)
	await _wait(10)
	view = main.current
	view.ctrl.set_speed(3)
	view.table.animate = false

func pass_device() -> void:
	if view.has_modal("pass"):
		await press("SONO IO")

## Sceglie le tattiche (prima tattica disponibile) finché non inizia la fase dei turni.
func tactics() -> void:
	var guard := 0
	while eng().s.phase == "tactics" and guard < 400:
		guard += 1
		await pass_device()
		if view.ctrl.is_local_turn() and eng().s.phase == "tactics":
			var e := eng()
			view.submit({"t": "tactic", "id": e.s.tactics_avail[0]})
			await _wait(4)
			while e.s.pending != null and view.ctrl.is_local_turn():
				view.submit({"t": "choose", "v": [e.s.pending.options[0].v]})
				await _wait(3)
		await _wait(2)

func clear_area(e: MKEngine) -> Array:
	var keys: Array = e.s.map.hex.keys()
	keys.sort()
	for k in keys:
		var good: Array = []
		for nk in MKHex.neighbors(k):
			if e.s.map.hex.has(nk):
				good.append(nk)
		if good.size() >= 5:
			for x in [k] + good:
				var hx: Dictionary = e.s.map.hex[x]
				hx.t = "plains"
				hx.site = ""
				hx.enemies = []
				hx.rampage = false
				hx.mine = ""
				hx.erase("city")
			return [k] + good
	return []

func set_hand(p: int, ids: Array) -> void:
	var pl: Dictionary = eng().s.players[p]
	pl.hand = []
	for id in ids:
		pl.hand.append(eng().new_iid(id))

var which := "all"

func _run() -> void:
	MKController.clear_save()
	var args := OS.get_cmdline_user_args()
	if args.size() > 1:
		which = args[1]
	if which in ["all", "pvp"]:
		await pvp()
	if which in ["all", "coop"]:
		await coop()
	print("PVPUI done errors=%d" % errors)
	quit()

# ------------------------------------------------------------------ combattimento tra giocatori (hotseat)
func pvp() -> void:
	await _start({"scenario": "full_conquest", "seed": 21, "options": {"set": "base", "pvp": true},
		"players": [{"hero": "arythea", "ctrl": "human", "name": "Stefano"}, {"hero": "tovak", "ctrl": "human", "name": "Giulia"}]})
	await tactics()
	await pass_device()
	var e := eng()
	var a := int(e.s.turn.player)
	var b := 1 - a
	var area := clear_area(e)
	e.s.players[b].pos = area[0]
	e.s.players[a].pos = area[1]
	e.s.turn.path = [area[1]]
	e.s.turn.pool.move = 4
	set_hand(a, ["rage", "determination", "swiftness", "march", "stamina"])
	set_hand(b, ["rage", "stamina", "determination", "tranquility", "promise"])
	e.s.players[b].fame = 12
	e.s.players[b].level = 3
	e.s.players[b].armor = 3
	view.refresh()
	view.table.focus_hex(area[0], 10.0)
	await _wait(5)
	view._on_hex_clicked(area[0])
	await _wait(5)
	if view.has_modal("confirm"):
		await press("Conferma")
	if str(e.s.players[a].pos) != str(area[0]):
		view.submit({"t": "move", "to": area[0]})
		await _wait(4)
	await shot("pvp_01_same_space")
	await press("Attacca")
	await shot("pvp_02_confirm")
	await press("Conferma")
	await shot("pvp_03_pass_device")
	await pass_device()
	await shot("pvp_04_defender_mode")
	await choose_label("parzialmente")
	await shot("pvp_05_ranged_defender")
	await press("Passa")
	await pass_device()
	await press("Passa")
	await shot("pvp_06_melee_aggressor")
	# l'aggressore gioca Determinazione (Attacco 2 / Blocco 2) e una carta di lato, poi colpisce
	var iid := ""
	for x in e.s.players[a].hand:
		if e.card_id(x) == "determination":
			iid = x
	view.open_card_menu(iid)
	await _wait(4)
	await shot("pvp_07_card_menu")
	if not await press("Base", false):
		view.close_modal("cardmenu")
		view.submit({"t": "play", "card": iid, "mode": "basic"})
	await _wait(4)
	if e.s.pending != null:
		for o in e.s.pending.options:
			if str(o.label).find("Attacco") >= 0:
				view.submit({"t": "choose", "v": [o.v]})
				break
		await _wait(4)
	e.s.turn.pool.attack["melee:fire"] = 4
	view.refresh()
	await shot("pvp_08_attack_ready")
	await press("ATTACCA")
	await shot("pvp_09_pass_to_blocker")
	await pass_device()
	e.s.turn.pool.block = {"ice": 2}
	view.refresh()
	await shot("pvp_10_block")
	await press("BLOCCA")
	await pass_device()
	await shot("pvp_11_assign_damage")
	if e.s.pending != null:
		await choose_label("Ferisci")
	await _wait(4)
	await shot("pvp_12_after_hit")
	# fino alla fine: il difensore passa, l'aggressore costringe alla ritirata
	var guard := 0
	while e.s.get("pvp") != null and guard < 30:
		guard += 1
		await pass_device()
		if e.s.pending != null and e.s.pending.handler == "pvp:hit":
			var rr := ""
			for o in e.s.pending.options:
				if not e.hex(str(o.v)).is_empty():
					rr = str(o.label)
			await choose_label(rr if rr != "" else "Basta")
			continue
		var pv: Dictionary = e.s.pvp
		if str(pv.step) == "attack" and int(pv.striker) == a:
			e.s.turn.pool.attack = {"melee:phys": 6}
			view.refresh()
			await press("ATTACCA")
		elif str(pv.step) == "attack":
			await press("Passa")
		elif str(pv.step) == "block":
			var done: bool = await press("Subisci", false)
			if not done:
				await press("BLOCCA", false)
		await _wait(3)
	await pass_device()
	await shot("pvp_13_result")
	if e.s.get("pvp") != null:
		err("il combattimento tra giocatori non è finito")

# ------------------------------------------------------------------ assalto cooperativo (umano + IA)
func coop() -> void:
	await _start({"scenario": "coop_conquest", "seed": 33, "options": {"set": "base"},
		"players": [{"hero": "goldyx", "ctrl": "human", "name": "Stefano"}, {"hero": "norowas", "ctrl": "ai", "ai_level": 3, "name": "Norowas (IA)"}]})
	var guard := 0
	while not (eng().s.phase == "turn" and view.ctrl.is_local_turn() and eng().s.pending == null) and guard < 3000:
		guard += 1
		if guard % 50 == 0:
			note("attendo il turno dell'umano: phase=%s actor=%d pending=%s local=%s" % [eng().s.phase, eng().actor(), str(eng().s.pending != null), str(view.ctrl.is_local_turn())])
		if view.ctrl.is_local_turn() and eng().s.phase == "tactics" and eng().s.pending == null:
			var best := ""
			for t in eng().s.tactics_avail:
				if best == "" or eng().tactic_number(t) < eng().tactic_number(best):
					best = t
			var r := eng().check({"t": "tactic", "id": best})
			if r != "":
				note("tattica rifiutata: " + r)
			view.submit({"t": "tactic", "id": best})
		elif view.ctrl.is_local_turn() and eng().s.pending != null:
			view.submit({"t": "choose", "v": [eng().s.pending.options[0].v]})
		await _wait(2)
	var e := eng()
	var a := int(e.s.turn.player)
	var b := 1 - a
	var area := clear_area(e)
	var city: String = area[0]
	var h: Dictionary = e.s.map.hex[city]
	h.site = "city"
	h.conquered = false
	h.owner = -1
	h["city"] = {"color": "green", "level": 5, "shields": [], "leader": -1}
	h.enemies = []
	for i in 3:
		h.enemies.append(e.draw_enemy("gray", true, city))
	e.s.players[a].pos = area[1]
	e.s.players[b].pos = area[3]
	e.s.turn.path = [area[1]]
	set_hand(a, ["rage", "determination", "swiftness", "march", "stamina"])
	set_hand(b, ["rage", "determination", "swiftness", "march", "stamina"])
	view.refresh()
	view.table.focus_hex(city, 10.0)
	await _wait(6)
	await shot("coop_01_adjacent")
	await press("assalto cooperativo")
	await shot("coop_02_invite")
	await choose_label("Invita")
	await shot("coop_03_split")
	await choose_label("tu 2")
	guard = 0
	while e.s.combat == null and guard < 600:
		guard += 1
		await _wait(2)
	await _wait(6)
	await shot("coop_04_my_assault")
	if e.s.combat == null or int(e.s.turn.player) != a:
		err("l'assalto cooperativo non è iniziato per l'umano")
		return
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:phys": 40}
	var tg: Array = []
	for en in e.s.combat.enemies:
		tg.append(str(en.eid))
	view.submit({"t": "attack", "targets": tg})
	await _wait(3)
	await shot("coop_05_ally_fights")
	guard = 0
	while e.s.get("coop") != null and str(e.s.coop.stage) == "combat" and guard < 3000:
		guard += 1
		await _wait(2)
	await _wait(8)
	if view.has_modal("info"):
		await shot("coop_06_summary")
		await press("OK", false)
	await shot("coop_07_after_assault")
	note("città conquistata: %s, scudi %s" % [str(h.conquered), str(h.city.shields)])
	await press("TERMINA IL TURNO", false)
	guard = 0
	while e.s.get("coop") != null and guard < 3000:
		guard += 1
		if view.ctrl.is_local_turn() and e.s.pending != null:
			view.submit({"t": "choose", "v": [e.s.pending.options[0].v]})
		await _wait(2)
	await _wait(10)
	await shot("coop_08_end")
