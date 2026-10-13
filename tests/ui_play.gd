extends SceneTree
## Prova dell'interfaccia di gioco completa (serve un display: xvfb).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-driver opengl3 -s res://tests/ui_play.gd -- <modo> <prefisso> [w h]
## modi: solo (Conquista in solitario, umano guidato dal test), recon (Prima ricognizione), hotseat (2 umani),
##       ai (partita intera solo IA, nessuno screenshot salvo la fine), all
## Salva i PNG <prefisso>_<nome>.png e stampa "UIPLAY ..." con l'esito; esce da solo.

var mode := "solo"
var out := "/tmp/ui"
var main: MKMain
var view: MKGameView
var rng := RandomNumberGenerator.new()
var shots := {}
var errors := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	if args.size() > 1:
		out = args[1]
	if args.size() > 3:
		DisplayServer.window_set_size(Vector2i(int(args[2]), int(args[3])))
		root.size = Vector2i(int(args[2]), int(args[3]))
	create_timer(900.0).timeout.connect(func():
		printerr("ui_play: tempo scaduto")
		quit(1))
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	var p := "%s_%s.png" % [out, name]
	img.save_png(p)
	shots[name] = true
	print("SHOT ", p)


func _run() -> void:
	MKController.clear_save()
	if mode in ["solo", "all"]:
		await _play("solo_conquest", [{"hero": "arythea", "ctrl": "human", "name": "Stefano"}], "solo", 260)
	if mode in ["recon", "all"]:
		await _play("first_recon", [{"hero": "tovak", "ctrl": "human", "name": "Stefano"}, {"hero": "goldyx", "ctrl": "ai", "ai_level": 2, "name": "Goldyx (IA)"}], "recon", 200)
	if mode in ["hotseat", "all"]:
		await _play("first_recon", [{"hero": "norowas", "ctrl": "human", "name": "Anna"}, {"hero": "arythea", "ctrl": "human", "name": "Bruno"}], "hot", 60)
	if mode in ["ai", "all"]:
		await _play("first_recon", [{"hero": "goldyx", "ctrl": "ai", "ai_level": 2, "name": "Goldyx (IA)"}, {"hero": "tovak", "ctrl": "ai", "ai_level": 1, "name": "Tovak (IA)"}], "ai", 0)
	if mode in ["showcase", "all"]:
		await _showcase()
	if mode in ["end"]:
		await _play("first_recon", [{"hero": "arythea", "ctrl": "human", "name": "Stefano"}], "end", 99999)
	print("UIPLAY done errors=%d shots=%d" % [errors, shots.size()])
	quit()


func _start(scn: String, players: Array) -> void:
	for c in root.get_children():
		c.queue_free()
	await _wait(2)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(5)
	main.start_game({"scenario": scn, "seed": 11, "players": players, "options": {"set": "base"}})
	await _wait(10)
	view = main.current
	view.ctrl.set_speed(3)
	view.table.animate = false


func _eng() -> MKEngine:
	return view.ctrl.eng


func _play(scn: String, players: Array, tag: String, max_actions: int) -> void:
	await _start(scn, players)
	var e := _eng()
	var n := 0
	var t0 := Time.get_ticks_msec()
	var flags := {}
	while e.s.phase != "game_over":
		if Time.get_ticks_msec() - t0 > 600000:
			print("UIPLAY timeout ", tag)
			break
		await _wait(1)
		if not view.ctrl.is_local_turn():
			# IA (o nessuno): aspetta
			continue
		if view._needs_pass():
			if not flags.has("pass"):
				flags["pass"] = true
				await _wait(3)
				await _save(tag + "_pass_device")
			view.confirm_pass()
			continue
		if max_actions > 0 and n >= max_actions:
			break
		n += 1
		# screenshot ai momenti chiave
		if e.s.phase == "tactics" and not flags.has("tactics"):
			flags["tactics"] = true
			await _wait(3)
			await _save(tag + "_tactics")
		if e.s.pending != null and not flags.has("pending") and e.s.phase != "tactics":
			flags["pending"] = true
			await _wait(3)
			await _save(tag + "_pending")
		if e.s.combat != null and not flags.has("combat"):
			flags["combat"] = true
			await _wait(3)
			await _save(tag + "_combat")
		if e.s.combat != null and str(e.s.combat.phase) == "block" and not flags.has("combat_block"):
			flags["combat_block"] = true
			await _wait(2)
			await _save(tag + "_combat_block")
		if e.s.combat == null and e.s.pending == null and e.s.phase == "turn" and view._has_site_menu() and not flags.has("site"):
			flags["site"] = true
			view.open_site()
			await _wait(3)
			await _save(tag + "_site")
			view.close_site()
		if e.s.phase == "turn" and e.s.pending == null and e.s.combat == null and not flags.has("hand"):
			flags["hand"] = true
			await _wait(3)
			await _save(tag + "_hand")
			# zoom di una carta e menu della carta
			var hand: Array = e.s.players[e.actor()].hand
			if not hand.is_empty():
				view.show_zoom(MKHud.card_img(e, hand[0]), "[b]%s[/b]\n%s" % [MKHud.card_name(hand[0]), MKHud.card_text(hand[0])])
				await _wait(2)
				await _save(tag + "_zoom")
				view.hide_zoom()
				view.open_card_menu(hand[0])
				await _wait(3)
				await _save(tag + "_cardmenu")
				view.close_modal("cardmenu")
		var a := _choose(e, flags, tag)
		if a.is_empty():
			print("UIPLAY stuck ", tag, " phase=", e.s.phase)
			errors += 1
			break
		var pre_err := e.check(a)
		view.submit(a)
		if pre_err != "":
			print("UIPLAY rifiutata ", JSON.stringify(a), " ", e.check(a), " pending=", JSON.stringify(e.s.pending).substr(0, 400))
			errors += 1
		if e.s.phase == "turn" and e.s.pending == null and e.s.combat == null and float(e.s.turn.pool.get("move", 0)) >= 2 and not flags.has("move"):
			flags["move"] = true
			await _wait(3)
			await _save(tag + "_move")
	await _wait(5)
	if e.s.phase == "game_over":
		await _wait(5)
		await _save(tag + "_end")
		print("UIPLAY %s finita: %s" % [tag, JSON.stringify(e.s.result).substr(0, 300)])
	else:
		await _save(tag + "_last")
	print("UIPLAY %s actions=%d round=%d phase=%s" % [tag, n, int(e.s.round), e.s.phase])


## Situazioni costruite apposta (con trucchi sullo stato) per vedere ogni pannello.
func _showcase() -> void:
	await _start("solo_conquest", [{"hero": "goldyx", "ctrl": "human", "name": "Stefano"}])
	var e := _eng()
	view.submit({"t": "tactic", "id": e.s.tactics_avail[0]})
	await _wait(3)
	while e.s.pending != null:
		view.submit(e.available()[0]["a"])
		await _wait(1)
	var p := e.actor()
	var pl: Dictionary = e.s.players[p]
	# villaggio: sposta l'eroe e dai Influenza → pannello del sito
	var vk := ""
	for k in e.s.map.hex:
		if str(e.s.map.hex[k].get("site", "")) in ["village", "monastery"]:
			vk = k
			break
	if vk != "":
		pl.pos = vk
		e.s.turn.pool.influence = 14
		e.s.turn.pool.move = 5
		pl.crystals.blue = 2
		pl.crystals.red = 1
		pl.tokens = ["gold", "green"]
		view.refresh()
		await _wait(4)
		await _save("sc_actions")
		view.open_site()
		await _wait(4)
		await _save("sc_site")
		# recluta un'unità per vedere le unità sulla plancia
		for x in e.available():
			if x.a.t == "recruit":
				view.submit(x.a)
				break
		await _wait(2)
		for x in e.available():
			if x.a.t == "recruit":
				view.submit(x.a)
				break
		view.close_site()
		await _wait(3)
		await _save("sc_units")
	# suggerimento su un esagono con nemici
	for k in e.s.map.hex:
		if not e.s.map.hex[k].get("enemies", []).is_empty():
			view._show_hex_tip(k, false)
			view.tip_panel.position = Vector2(700, 300)
			break
	await _wait(3)
	await _save("sc_tooltip")
	view.tip_panel.visible = false
	# schermate
	MKScreens.offers(view)
	await _wait(4)
	await _save("sc_offers")
	view.close_modal("screen")
	MKScreens.rules(view)
	await _wait(3)
	await _save("sc_rules")
	view.close_modal("screen")
	MKScreens.diary(view)
	await _wait(3)
	await _save("sc_diary")
	view.close_modal("screen")
	MKScreens.game_menu(view)
	await _wait(3)
	await _save("sc_menu")
	view.close_modal("screen")
	# salita di livello: decisione con le immagini delle abilità
	MKSites.level_up_skill(e, p)
	view.refresh()
	await _wait(4)
	await _save("sc_levelup")
	while e.s.pending != null:
		view.submit(e.available()[0]["a"])
		await _wait(2)
		if e.s.pending != null and not shots.has("sc_levelup_aa"):
			await _save("sc_levelup_aa")
	# combattimento con più nemici (fase di attacco con selezione)
	var eids := []
	for c in ["gray", "gray", "violet"]:
		var eid := e.draw_enemy(c, true, "")
		if eid != "":
			eids.append(eid)
	MKCombat.start(e, eids, {"kind": "challenge"})
	e.s.turn.pool.attack["ranged:fire"] = 4
	e.s.turn.pool.attack["siege:phys"] = 3
	view.refresh()
	view.combat_sel = [eids[0]]
	view._build_center()
	await _wait(4)
	await _save("sc_combat_ranged")
	view.submit({"t": "next"})
	e.s.turn.pool.block["ice"] = 3
	e.s.turn.pool.block["phys"] = 4
	view.refresh()
	await _wait(4)
	await _save("sc_combat_block")
	view.submit({"t": "next"})
	await _wait(3)
	await _save("sc_combat_damage")
	# salvataggio e ripresa
	var fp := e.fingerprint()
	view.ctrl.save_now()
	var ok := main.resume_game()
	await _wait(10)
	view = main.current
	print("UIPLAY resume ok=%s same=%s" % [ok, view.ctrl.eng.fingerprint() == fp])
	await _save("sc_resumed")


## Scelta dell'umano simulato: progredisce (gioca carte di movimento, esplora, entra nei siti,
## combatte con un aiutino), usando le stesse funzioni della vista.
func _choose(e: MKEngine, flags: Dictionary, tag: String) -> Dictionary:
	var av: Array = e.available()
	if av.is_empty():
		return {}
	if e.s.pending != null or e.s.phase == "tactics":
		return av[rng.randi() % av.size()]["a"]
	var t: Dictionary = e.s.turn
	if e.s.combat != null:
		var c: Dictionary = e.s.combat
		# aiutino: punti per vincere ogni tanto (serve a vedere ricompense, livelli, conquiste)
		if not t.get("_ui_god_" + str(c.phase), false):
			t["_ui_god_" + str(c.phase)] = true
			if c.phase == "ranged" and rng.randf() < 0.5:
				t.pool.attack["siege:phys"] = 12
			elif c.phase == "block":
				t.pool.block["cold"] = 8
			elif c.phase == "attack":
				t.pool.attack["melee:cold"] = 20
		# selezione dal pannello: tutti i bersagli possibili
		var tg := []
		for en in c.enemies:
			if MKCombat.targetable(e, en):
				tg.append(en.eid)
		if not tg.is_empty() and e.check({"t": "attack", "targets": tg}) == "":
			view.combat_sel = tg
			return {"t": "attack", "targets": tg}
		for x in av:
			if x.a.t == "block":
				return x.a
		for x in av:
			if x.a.t == "damage":
				return x.a
		for x in av:
			if x.a.t == "next":
				return x.a
		return av[0]["a"]
	# aiutino nei siti: Influenza per reclutare/comprare (per vedere il pannello del sito)
	if MKSites.can_interact(e, e.actor()) == "" and int(t.pool.influence) < 8 and not t.get("_ui_inf", false):
		t["_ui_inf"] = true
		t.pool.influence = 12
		av = e.available()
	var by := {}
	for x in av:
		var tt := str(x.a.t)
		if not by.has(tt):
			by[tt] = []
		by[tt].append(x.a)
	for k in ["recruit", "site", "explore", "challenge"]:
		if by.has(k) and rng.randf() < 0.7:
			return by[k][rng.randi() % by[k].size()]
	if by.has("buy") and rng.randf() < 0.4:
		return by["buy"][0]
	# muovi verso un esagono raggiungibile (come un clic sulla mappa)
	if int(t.pool.move) > 0 and rng.randf() < 0.8:
		var paths: Dictionary = view.move_paths()
		if not paths.is_empty():
			var ks := paths.keys()
			var k: String = ks[rng.randi() % ks.size()]
			return {"t": "move", "to": paths[k][0]}
	if by.has("play") and int(t.pool.move) < 4 and rng.randf() < 0.75:
		var plays: Array = by["play"]
		# preferisci il movimento
		for a in plays:
			if a.get("mode", "") == "side" and a.get("side", "") == "move":
				return a
		return plays[rng.randi() % plays.size()]
	for k in ["heal", "unit", "skill"]:
		if by.has(k) and rng.randf() < 0.3:
			return by[k][0]
	for k in ["announce_end", "end_turn", "rest"]:
		if by.has(k):
			return by[k][0]
	return av[rng.randi() % av.size()]["a"]
