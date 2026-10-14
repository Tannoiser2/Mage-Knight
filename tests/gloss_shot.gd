extends SceneTree
## Screenshot delle spiegazioni nei suggerimenti (glossario): suggerimento di un esagono con nemici,
## pannello di combattimento con un nemico dalle molte abilità e suggerimento di un'abilità,
## zoom di un'Unità, menu di gioco e le stesse viste con l'impostazione su No.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-driver opengl3 -s res://tests/gloss_shot.gd -- <prefisso>

var out := "/tmp/gloss"
var main: MKMain
var view: MKGameView


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	create_timer(300.0).timeout.connect(func():
		printerr("gloss_shot: tempo scaduto")
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


func _mouse(pos: Vector2) -> void:
	Input.warp_mouse(pos)
	var ev := InputEventMouseMotion.new()
	ev.position = pos
	ev.global_position = pos
	root.push_input(ev)


## Il nemico con più abilità e resistenze tra quelli di un colore.
func _richest(colors: Array) -> String:
	var best := ""
	var bn := -1
	for id in MKDB.enemies:
		var d: Dictionary = MKDB.enemies[id]
		if not str(d.get("color", "")) in colors:
			continue
		var n: int = d.get("abilities", []).size() + d.get("resist", []).size() + d.get("attacks", []).size()
		if n > bn:
			bn = n
			best = id
	return best


func _find_tip_label(n: Node, prefix: String) -> Control:
	if n is Label and n.get_script() != null and str(n.text).begins_with(prefix) and n.is_visible_in_tree():
		return n
	for c in n.get_children():
		var r := _find_tip_label(c, prefix)
		if r != null:
			return r
	return null


func _hover(ctrl: Control, name: String) -> void:
	if ctrl == null:
		print("GLOSS manca il controllo per ", name)
		return
	_mouse(Vector2(10, 10))
	await _wait(3)
	var r := ctrl.get_global_rect()
	_mouse(r.get_center())
	await create_timer(1.2).timeout
	await _wait(2)
	await _save(name)


func _run() -> void:
	MKController.clear_save()
	MKGloss.set_enabled(true)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(5)
	await _save("home")
	main.start_game({"scenario": "solo_conquest", "seed": 11, "players": [{"hero": "goldyx", "ctrl": "human", "name": "Stefano"}], "options": {"set": "base"}})
	await _wait(10)
	view = main.current
	view.table.animate = false
	var e: MKEngine = view.ctrl.eng
	view.submit({"t": "tactic", "id": e.s.tactics_avail[0]})
	await _wait(3)
	while e.s.pending != null:
		view.submit(e.available()[0]["a"])
		await _wait(1)
	# esagono con un sito fortificato e una guarnigione dalle molte abilità
	var hk := ""
	for k in e.s.map.hex:
		if str(e.s.map.hex[k].get("site", "")) in ["mage_tower", "keep"]:
			hk = k
			break
	if hk == "":
		for k in e.s.map.hex:
			if str(e.s.map.hex[k].get("t", "")) == "hills":
				hk = k
				break
	var types := [_richest(["violet"]), _richest(["red", "white"])]
	print("GLOSS esagono ", hk, " ", e.s.map.hex[hk].get("site", ""), " nemici ", types)
	var eids := []
	for ty in types:
		var eid := e.draw_enemy(str(MKDB.enemies[ty].color), true, "")
		e.s.enemies[eid].type = ty
		e.s.enemies[eid].face_up = true
		eids.append(eid)
	e.s.map.hex[hk].enemies = eids.duplicate()
	view.refresh()
	await _wait(4)
	_mouse(Vector2(900, 360))
	await _wait(2)
	view._show_hex_tip(hk, false)
	await _wait(3)
	view._show_hex_tip(hk, false)
	await _wait(2)
	print("GLOSS tip size ", view.tip_panel.size, " pos ", view.tip_panel.position)
	await _save("hex")
	# combattimento: assalto alla guarnigione
	view.tip_panel.visible = false
	MKCombat.start(e, eids, {"site": hk, "kind": "assault", "assault": true, "defenders": eids})
	e.s.turn.pool.attack["siege:fire"] = 5
	view.refresh()
	await _wait(5)
	await _save("combat")
	var tr := MKHud.enemy_traits(MKCombat.entry(e, str(eids[0])))
	var first := str(tr[0][0]) if not tr.is_empty() else "Attacco"
	await _hover(_find_tip_label(view, first), "combat_tip")
	await _hover(_find_tip_label(view, "Attacco"), "combat_tip_attack")
	await _hover(_find_tip_label(view, "Fortif"), "combat_tip_fort")
	# zoom di un'Unità con resistenze (offerta)
	_mouse(Vector2(10, 10))
	view.show_zoom(MKHud.unit_img("fire_golems"), "[b]Golem di Fuoco[/b]\n" + MKGloss.unit_block(MKDB.units.get("fire_golems", {}), "Esaurita"), Vector2(300, 420))
	await _wait(3)
	await _save("unit_zoom")
	view.hide_zoom()
	MKScreens.game_menu(view)
	await _wait(3)
	await _save("menu")
	view.close_modal("screen")
	# impostazione su No
	MKGloss.set_enabled(false)
	view.refresh()
	await _wait(4)
	await _hover(_find_tip_label(view, first), "off_combat_tip")
	e.s.combat = null
	view.refresh()
	await _wait(4)
	_mouse(Vector2(900, 360))
	await _wait(2)
	view._show_hex_tip(hk, false)
	await _wait(3)
	await _save("off_hex")
	MKGloss.set_enabled(true)
	MKController.clear_save()
	print("GLOSS done")
	quit(0)
