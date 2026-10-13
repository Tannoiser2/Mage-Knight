extends SceneTree
## Screenshot del tavolo/menu per la verifica visiva (serve un display: xvfb).
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . -s res://tests/shot.gd -- <modo> <prefisso_uscita>
## modi: table (più angoli, giorno e notte), menu, newgame, game (shell con HUD), anim (rivelazione/mosse),
##       hl (evidenziazioni), all
## Esce da solo dopo aver salvato i PNG <prefisso>_<nome>.png.

var mode := "table"
var out := "/tmp/shot"
var frames := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	if args.size() > 1:
		out = args[1]
	root.size = Vector2i(1920, 1080)
	# guardia: se qualcosa si blocca (errori di script) si esce comunque
	create_timer(400.0).timeout.connect(func():
		printerr("shot: tempo scaduto")
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


func _table(state: Dictionary) -> MKTable3D:
	var t := MKTable3D.new()
	t.animate = false
	root.add_child(t)
	t.refresh(state)
	return t


func _run() -> void:
	if mode in ["table", "all"]:
		await _shots_table()
	if mode in ["heroes", "all"]:
		await _shots_heroes()
	if mode in ["input", "all"]:
		await _test_input()
	if mode in ["hl", "all"]:
		await _shots_hl()
	if mode in ["anim", "all"]:
		await _shots_anim()
	if mode in ["menu", "newgame", "game", "all"]:
		await _shots_menu()
	quit()


func _clear() -> void:
	for c in root.get_children():
		c.queue_free()
	await _wait(2)


func _shots_table() -> void:
	var t := _table(MKTableDemo.state(0))
	await _wait(3)
	t.rig.snap()
	await _wait(2)
	await _save("day_home")
	t.rig.yaw = 35
	t.rig.pitch = 32
	t.rig.dist = 9
	t.rig.target = t.hex_pos("3,-4")
	t.rig.snap()
	await _wait(2)
	await _save("day_low")
	t.rig.yaw = 0
	t.rig.pitch = 88
	t.rig.dist = 7
	t.rig.target = t.hex_pos("1,-3")
	t.rig.snap()
	await _wait(2)
	await _save("day_top_tile1")
	t.rig.yaw = -20
	t.rig.pitch = 30
	t.rig.dist = 4.5
	t.rig.target = t.hex_pos("2,-3")
	t.rig.snap()
	await _wait(2)
	await _save("day_hero_close")
	t.refresh(MKTableDemo.state(1))
	t.rig.reset(true)
	await _wait(3)
	await _save("night_home")
	t.rig.yaw = 200
	t.rig.pitch = 38
	t.rig.dist = 10
	t.rig.target = t.hex_pos("4,-5")
	t.rig.snap()
	await _wait(2)
	await _save("night_city")
	await _clear()


func _shots_heroes() -> void:
	var st := MKTableDemo.state(0)
	st["players"] = []
	var hs := ["arythea", "goldyx", "norowas", "tovak"]
	for h in hs:
		st["players"].append({"hero": h, "name": h, "pos": "0,0", "shields": []})
	st["active"] = 2
	var t := _table(st)
	await _wait(3)
	t.rig.yaw = 10
	t.rig.pitch = 25
	t.rig.dist = 3.6
	t.rig.target = t.hex_pos("0,0")
	t.rig.snap()
	await _wait(2)
	await _save("heroes")
	await _clear()


## Prova dell'input: clic su un esagono, trascinamento (panoramica), rotella (zoom).
func _test_input() -> void:
	var t := _table(MKTableDemo.state(0))
	t.set_highlights({"5,-8": "explore", "1,-2": {"kind": "move", "label": "2"}})
	await _wait(3)
	t.rig.snap()
	await _wait(2)
	var got := []
	t.hex_clicked.connect(func(k): got.append(k))
	for k in ["1,-2", "6,-9", "2,-3"]:
		var sp := t.screen_pos(k)
		var ev := InputEventMouseButton.new()
		ev.button_index = MOUSE_BUTTON_LEFT
		ev.position = sp
		ev.pressed = true
		root.push_input(ev)
		var ev2: InputEventMouseButton = ev.duplicate()
		ev2.pressed = false
		root.push_input(ev2)
		await _wait(1)
	print("INPUT clicks: ", got, "  (attesi: 1,-2 / 5,-8 / 2,-3)")
	var before := t.rig.target
	var d := InputEventMouseButton.new()
	d.button_index = MOUSE_BUTTON_LEFT
	d.position = Vector2(900, 500)
	d.pressed = true
	root.push_input(d)
	for i in range(10):
		var m := InputEventMouseMotion.new()
		m.position = Vector2(900 + i * 20, 500)
		m.relative = Vector2(20, 0)
		m.button_mask = MOUSE_BUTTON_MASK_LEFT
		root.push_input(m)
	var u: InputEventMouseButton = d.duplicate()
	u.pressed = false
	u.position = Vector2(1100, 500)
	root.push_input(u)
	await _wait(1)
	print("INPUT pan: ", before, " -> ", t.rig.target)
	var dist0 := t.rig.dist
	var w := InputEventMouseButton.new()
	w.button_index = MOUSE_BUTTON_WHEEL_UP
	w.pressed = true
	w.position = Vector2(960, 540)
	root.push_input(w)
	await _wait(1)
	print("INPUT zoom: ", dist0, " -> ", t.rig.dist)
	await _clear()


func _shots_hl() -> void:
	var t := _table(MKTableDemo.state(0))
	t.set_highlights({"2,-2": {"kind": "move", "label": "2"}, "1,-2": {"kind": "move", "label": "2"},
		"3,-4": {"kind": "target"}, "5,-8": "explore", "0,-2": {"kind": "move", "label": "4"}})
	t._update_hover(Vector2(-1, -1))
	await _wait(3)
	t.rig.yaw = 0
	t.rig.pitch = 60
	t.rig.dist = 12
	t.rig.target = t.hex_pos("2,-4")
	t.rig.snap()
	await _wait(2)
	# puntatore sopra un esagono
	t._update_hover(t.screen_pos("2,-3"))
	await _wait(2)
	await _save("highlights")
	await _clear()


func _shots_anim() -> void:
	var t := MKTable3D.new()
	root.add_child(t)
	t.refresh(MKTableDemo.state(0))
	await _wait(3)
	t.refresh(MKTableDemo.state(1))
	await _wait(12)
	await _save("anim_mid")
	await _wait(120)
	await _save("anim_end")
	await _clear()


func _shots_menu() -> void:
	var main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(20)
	if mode in ["menu", "all"]:
		await _save("menu")
	if mode in ["newgame", "all"]:
		main.current.show_new_game()
		await _wait(10)
		await _save("newgame")
	if mode in ["game", "all"]:
		main.start_game({"scenario": "first_recon", "seed": 1, "players": [{"hero": "arythea", "ctrl": "human", "ai_level": 2, "name": "Stefano"}]})
		await _wait(30)
		await _save("game")
	await _clear()
