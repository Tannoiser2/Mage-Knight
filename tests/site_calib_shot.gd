extends SceneTree
## Controllo visivo della calibrazione delle miniature dei siti (data/site_minis.json): mette in mappa tutte
## le tessere con siti calibrati e fotografa ogni esagono con un sito dall'alto e di scorcio (pitch 55°).
## Serve un display (xvfb):
##   xvfb-run -a -s "-screen 0 1000x700x24" <godot> --path . --rendering-driver opengl3 -s res://tests/site_calib_shot.gd -- <cartella> [filtro] [tokens]
## [filtro] = elenco di siti o di "tessera|dir" separati da virgole ("all" = tutti); con "tokens" su ogni sito
## mette anche due nemici scoperti (e l'eroe sul primo) per controllare la fila davanti all'edificio.
## Salva <cartella>/<tessera>_<dir>_<sito>_top.png e _obl.png ed esce.

var out := "/tmp/site_calib"
var only: Array = []
var tokens := false


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1 and args[1] != "all":
		only = Array(args[1].split(","))
	tokens = args.size() > 2 and args[2] == "tokens"
	DirAccess.make_dir_recursive_absolute(out)
	create_timer(1500.0).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _save(name: String) -> void:
	await _wait(4)
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _run() -> void:
	MKController.clear_save()
	MKMiniatures.enabled = true
	var main: MKMain = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(5)
	main.start_game({"scenario": "solo_conquest", "seed": 11, "players": [{"hero": "goldyx", "ctrl": "human", "name": "Stefano"}], "options": {"set": "base"}})
	await _wait(10)
	var view: MKGameView = main.current
	view.table.animate = false
	var e: MKEngine = view.ctrl.eng
	view.submit({"t": "tactic", "id": e.s.tactics_avail[0]})
	await _wait(3)
	while e.s.pending != null:
		view.submit(e.available()[0]["a"])
		await _wait(1)
	view.hud.visible = false
	var t: MKTable3D = view.table
	var cal = JSON.parse_string(FileAccess.get_file_as_string("res://data/site_minis.json"))
	var want := {}
	for key in cal.hexes:
		want[str(key).split("|")[0]] = true
	# togli le tessere già in mappa (tranne la iniziale) e metti quelle da controllare su una griglia di posti
	var used := {}
	for tl in e.s.map.tiles:
		used[str(tl.slot)] = true
	var slots: Array = []
	for a in range(1, 9):
		for b in range(0, 9):
			var sv: Vector2i = MKHexMesh.MACRO[0] * a + MKHexMesh.MACRO[1] * b + MKHexMesh.MACRO[2] * 4
			var sk := MKHexMesh.key(sv.x, sv.y)
			if not used.has(sk):
				slots.append(sk)
	var tids := want.keys()
	tids.sort()
	var i := 0
	var placed := {}
	for tl in e.s.map.tiles:
		placed[str(tl.id)] = true
	for tid in tids:
		if placed.has(tid):
			continue
		if not MKDB.tiles.has(tid):
			print("manca la tessera ", tid)
			continue
		e.s.map.tile_deck.erase(tid)
		e.place_tile(tid, slots[i], -1)
		i += 1
	view.refresh()
	await _wait(3)
	var shots: Array = []
	for tl in e.s.map.tiles:
		var tid := str(tl.id)
		var c := MKHexMesh.parse(str(tl.slot))
		for dk in ["center", "0", "60", "120", "180", "240", "300"]:
			var key: String = tid + "|" + dk
			if not cal.hexes.has(key):
				continue
			var site := str(cal.hexes[key].site)
			if not only.is_empty() and not (only.has(site) or only.has(key)):
				continue
			var d: Vector2i = Vector2i.ZERO if dk == "center" else MKHexMesh.DIRS[MKTable3D.TILE_DIR_KEYS.find(dk)]
			shots.append([key, site, MKHexMesh.key(c.x + d.x, c.y + d.y)])
	if tokens:
		var first := true
		for sh in shots:
			var hk: String = sh[2]
			var h: Dictionary = e.s.map.hex[hk]
			for eid in h.enemies:
				e.s.enemies[eid].face_up = true
			for ty in ["swordsmen", "golems"].slice(0, maxi(0, 2 - h.enemies.size())):
				e.s.eid_seq = int(e.s.eid_seq) + 1
				var eid := "e%d" % e.s.eid_seq
				e.s.enemies[eid] = {"type": ty, "color": "gray", "face_up": true, "hex": hk}
				h.enemies.append(eid)
			if first:
				e.s.players[0].pos = hk
				first = false
		view.refresh()
		await _wait(4)
	for sh in shots:
		var name := "%s_%s" % [str(sh[0]).replace("|", "_"), sh[1]]
		# dall'alto: proiezione ortogonale, così si vede la pianta vera sopra il disegno
		t.focus_hex(sh[2], 3.6)
		t.rig.pitch = 88.0
		t.rig.yaw = 0.0
		t.rig.snap()
		t.rig.cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		t.rig.cam.size = 2.6
		await _save(name + "_top")
		t.rig.cam.projection = Camera3D.PROJECTION_PERSPECTIVE
		t.rig.pitch = 55.0
		t.rig.snap()
		await _save(name + "_obl")
		print("SHOT ", name)
	quit()
