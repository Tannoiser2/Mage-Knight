extends SceneTree
## Screenshot delle espansioni (serve un display: xvfb):
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-driver opengl3 -s res://tests/exp_shot.gd -- /tmp/exp
## Salva <prefisso>_menu.png (Nuova partita con i nuovi eroi e i Contenuti), _map.png (tessere della Legione
## Perduta con mura, Campo Profughi, Dedalo), _camp.png, _combat.png (nemici delle espansioni, Ingombrante),
## _maze.png (scelta del sentiero) e _hero.png (plancia di Braevalar con le sue abilità).

var out := "/tmp/exp"
var main: MKMain
var view: MKGameView


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	create_timer(300.0).timeout.connect(func():
		printerr("exp_shot: tempo scaduto")
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
	print("SHOT ", p)


func _run() -> void:
	MKController.clear_save()
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(8)
	# --- menu: Nuova partita with the expansion heroes and content
	var menu: MKMenu = main.current
	menu.scenario = 2
	menu.content = 2
	menu.seats[0].hero = "wolfhawk"
	menu.seats[1].hero = "krang"
	menu.seats[1].on = true
	menu.seats[1].ai = true
	menu.seats[2].hero = "braevalar"
	menu.seats[2].on = true
	menu.seats[2].ai = true
	menu.show_new_game()
	await _wait(10)
	await _save("menu")
	# --- game with Braevalar and the Lost Legion tiles
	main.start_game({"scenario": "solo_conquest", "seed": 11, "players": [{"hero": "braevalar", "ctrl": "human", "name": "Stefano"}],
		"options": {"content": "tezla"}})
	await _wait(10)
	view = main.current
	view.ctrl.set_speed(3)
	view.table.animate = false
	var e: MKEngine = view.ctrl.eng
	view.submit({"t": "tactic", "id": e.s.tactics_avail[0]})
	await _wait(3)
	while e.s.pending != null:
		view.submit(e.available()[0]["a"])
		await _wait(2)
	for t in [["c12", "4,-5"], ["c13", "2,-6"], ["k10", "6,-4"]]:
		e.s.map.tile_deck.erase(t[0])
		e.s.decks.tiles_spare.erase(t[0])
		e.place_tile(t[0], t[1], -1)
	var p := e.actor()
	var pl: Dictionary = e.s.players[p]
	var camp := ""
	var maze := ""
	for k in e.s.map.hex:
		if e.s.map.hex[k].site == "camp" and camp == "":
			camp = k
		if e.s.map.hex[k].site == "maze" and maze == "":
			maze = k
	pl.pos = camp
	e.s.turn.pool.move = 3
	MKSites.add_skill(e, p, "braevalar_shapeshift")
	MKSites.add_skill(e, p, "braevalar_forked_lightning")
	view.refresh()
	await _wait(6)
	view.table.focus_hex(camp, 13.0)
	view.table.rig.snap()
	await _wait(10)
	await _save("map")
	view._show_hex_tip(camp, false)
	view.tip_panel.position = Vector2(700, 300)
	await _wait(3)
	await _save("hero")
	view.tip_panel.visible = false
	e.s.offers.units = ["scouts", "shocktroops", "magic_familiars", "delphana_masters", "heroes_red"]
	e.s.turn.pool.influence = 9
	view.refresh()
	await _wait(3)
	view.open_site()
	await _wait(4)
	await _save("camp")
	view.close_site()
	# --- combat against expansion enemies (block phase, Cumbersome)
	var eids := []
	for ty in ["orc_tracker", "zombie_horde", "elven_protectors", "vampire"]:
		e.s.eid_seq += 1
		var eid := "x%d" % e.s.eid_seq
		e.s.enemies[eid] = {"type": ty, "color": MKDB.enemies[ty].color, "face_up": true, "hex": ""}
		eids.append(eid)
	e.s.turn.pool.influence = 0
	MKCombat.start(e, eids, {"kind": "challenge"})
	view.refresh()
	await _wait(3)
	view.submit({"t": "next"})
	e.s.turn.pool.move = 2
	e.s.turn.pool.block["phys"] = 3
	view.refresh()
	await _wait(5)
	await _save("combat")
	e.s.combat = null
	e.s.turn = e._fresh_turn(p)
	# --- maze: path choice after generating Move points
	pl.pos = maze
	pl.hand = [e.new_iid("march"), e.new_iid("druidic_paths"), e.new_iid("rage"), e.new_iid("swiftness")]
	view.refresh()
	await _wait(3)
	view.submit({"t": "site"})
	await _wait(3)
	while e.s.pending != null:
		view.submit(e.available()[0]["a"])
		await _wait(2)
	view.submit({"t": "play", "card": pl.hand[0], "mode": "basic"})
	await _wait(2)
	view.submit({"t": "play", "card": pl.hand[0], "mode": "basic"})
	await _wait(4)
	view.table.focus_hex(maze, 12.0)
	view.table.rig.snap()
	await _wait(8)
	await _save("maze")
	print("EXPSHOT done")
	quit()
