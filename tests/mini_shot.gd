extends SceneTree
## Screenshot delle miniature 3D (Meshy) sul tavolo: tutti i tipi di nemico scoperti, uno per esagono,
## e le strutture dei siti. Serve un display (xvfb):
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-driver opengl3 -s res://tests/mini_shot.gd -- <prefisso>
## Salva <prefisso>_overview.png, _close_N.png, _site_<sito>.png, _rotated.png, _night.png, _off.png,
## _on_again.png, _hud.png, _menu.png ed esce.

var out := "/tmp/mini"
var main: MKMain
var view: MKGameView


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	create_timer(300.0).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _save(name: String) -> void:
	await _wait(8)
	await RenderingServer.frame_post_draw
	var p := "%s_%s.png" % [out, name]
	root.get_texture().get_image().save_png(p)
	print("SHOT ", p)


func _run() -> void:
	MKController.clear_save()
	MKMiniatures.enabled = true
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(5)
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
	view.hud.visible = false
	# altre tessere, finché ci sono tutti e quattro i siti (o fino a 8)
	var t: MKTable3D = view.table
	for i in range(8):
		var have := {}
		for k in e.s.map.hex:
			have[str(e.s.map.hex[k].site)] = true
		if have.has("village") and have.has("monastery") and have.has("keep") and have.has("mage_tower"):
			break
		var slots := t._free_slots()
		if slots.is_empty() or e.s.map.tile_deck.is_empty():
			break
		slots.sort()
		e.place_tile(e.s.map.tile_deck.pop_front(), str(slots[0]), -1)
		view.refresh()
		await _wait(2)
	# tutti i tipi di nemico, scoperti, uno per esagono libero
	var types: Array = []
	for c in e.s.enemy_bags:
		for ty in e.s.enemy_bags[c].draw + e.s.enemy_bags[c].discard:
			if not types.has([ty, c]):
				types.append([ty, c])
	for eid in e.s.enemies:
		e.s.enemies[eid].face_up = true
	var free: Array = []
	for k in e.s.map.hex:
		var h: Dictionary = e.s.map.hex[k]
		if h.enemies.is_empty() and str(h.site) in ["", "magical_glade", "mine"] and str(h.t) not in ["lake", "mountain"]:
			free.append(k)
	free.sort()
	var seen := {}
	var j := 0
	for tc in types:
		if seen.has(tc[0]) or j >= free.size() or not MKMiniatures.has(tc[0]):
			continue
		seen[tc[0]] = true
		e.s.eid_seq = int(e.s.eid_seq) + 1
		var eid := "e%d" % e.s.eid_seq
		e.s.enemies[eid] = {"type": tc[0], "color": tc[1], "face_up": true, "hex": free[j]}
		e.s.map.hex[free[j]].enemies.append(eid)
		j += 1
	print("MINI tipi sul tavolo: ", seen.size())
	view.refresh()
	await _wait(5)
	await _save("overview")
	var n := 0
	for k in free.slice(0, j):
		if n % 4 == 0:
			t.focus_hex(k, 6.5)
			t.rig.snap()
			await _save("close_%d" % (n / 4))
		n += 1
	for k in e.s.map.hex:
		var site := str(e.s.map.hex[k].site)
		if site in ["village", "monastery", "keep", "mage_tower"]:
			e.s.players[0].pos = k
			view.refresh()
			t.focus_hex(k, 5.5)
			t.rig.snap()
			await _save("site_" + site)
	t.rig.yaw = 120.0
	t.rig.snap()
	await _save("rotated")
	t.rig.yaw = 0.0
	t.rig.snap()
	t.set_day(false, true)
	await _save("night")
	t.set_day(true, true)
	t.set_miniatures(false)
	await _save("off")
	t.set_miniatures(true)
	await _save("on_again")
	view.hud.visible = true
	t.rig.reset(true)
	await _save("hud")
	MKScreens.game_menu(view)
	await _save("menu")
	MKMiniatures.set_enabled(true)
	quit()
