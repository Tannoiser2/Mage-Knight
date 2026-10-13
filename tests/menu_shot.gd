extends SceneTree
## Screenshot della schermata Nuova partita per ogni scenario (serve xvfb).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-driver opengl3 -s res://tests/menu_shot.gd -- <prefisso> [scenari...]

var out := "/tmp/menu"
var main


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	create_timer(300.0).timeout.connect(func(): quit(1))
	_run.call_deferred(args.slice(1))


func _wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _save(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s_%s.png" % [out, name])
	print("SHOT %s_%s.png" % [out, name])


func _run(which: Array) -> void:
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(8)
	var menu = main.current if "current" in main else null
	if menu == null or not menu is MKMenu:
		for c in main.get_children():
			if c is MKMenu:
				menu = c
	menu.show_new_game()
	await _wait(6)
	await _save("new")
	var ids: Array = []
	for i in menu.scenario_count():
		ids.append(menu.scenario_id(i))
	for i in ids.size():
		if not which.is_empty() and not ids[i] in which:
			continue
		menu.select_scenario(i)
		# prova ad aggiungere tutti i posti consentiti
		for k in 4:
			menu.try_add_seat()
		await _wait(4)
		await _save(ids[i])
		print("SEATS %s on=%d" % [ids[i], menu._n_on()])
	# finestra delle regole complete
	menu.select_scenario(ids.find("mines_liberation"))
	menu._show_scenario_rules()
	await _wait(4)
	await _save("rules")
	# una partita appena iniziata (barra dell'obiettivo dello scenario)
	if OS.get_environment("MENU_GAME") != "":
		MKController.clear_save()
		main.start_game({"scenario": OS.get_environment("MENU_GAME"), "seed": 5, "players": [
			{"hero": "arythea", "ctrl": "human", "name": "Stefano"}, {"hero": "goldyx", "ctrl": "ai", "ai_level": 2, "name": "Goldyx (IA)"}],
			"options": {"content": "base"}})
		await _wait(60)
		await _save("game_" + OS.get_environment("MENU_GAME"))
		MKController.clear_save()
	quit()
