extends SceneTree
## Screenshot delle miniature 3D dei siti e dei nemici sui segnalini (basetta), per controllo visivo.
## Serve un display (xvfb):
##   xvfb-run -a -s "-screen 0 1600x900x24" <godot> --path . --rendering-driver opengl3 -s res://tests/site_shot.gd -- <prefisso> [siti]
## [siti] = elenco separato da virgole (es. mage_tower,keep) per fare solo quelle inquadrature.
## Salva <prefisso>_site_<sito>.png, _enemies.png, _garrison.png, _city.png, _rotated.png, _night.png, _overview.png ed esce.

var out := "/tmp/site"
var only: Array = []
var main: MKMain
var view: MKGameView

# tessere con i siti da mostrare (anche delle espansioni): id tessera
const TILES := ["c04", "c07", "c09", "c08", "k01", "c12", "k10", "k11", "c16", "c03", "c01", "k05"]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	if args.size() > 1:
		only = Array(args[1].split(","))
	create_timer(1500.0).timeout.connect(func(): quit(1))
	_run.call_deferred()


func _wait(n: int) -> void:
	for i in range(n):
		await process_frame


func _save(name: String) -> void:
	await _wait(6)
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
	var t: MKTable3D = view.table
	for tid in TILES:
		var slots := t._free_slots()
		if slots.is_empty():
			break
		slots.sort()
		e.s.map.tile_deck.erase(tid)
		e.place_tile(tid, str(slots[0]), -1)
		view.refresh()
		await _wait(1)
	# nemici scoperti su esagoni liberi: 1, 2 e 3 per esagono; uno con l'eroe
	var free: Array = []
	for k in e.s.map.hex:
		var h: Dictionary = e.s.map.hex[k]
		if h.enemies.is_empty() and str(h.site) == "" and str(h.t) not in ["lake", "mountain"]:
			free.append(k)
	free.sort()
	var groups := [["minotaur"], ["high_dragon", "golems"], ["werewolf", "medusa", "ice_mages"], ["swordsmen"]]
	var cols := {"minotaur": "brown", "high_dragon": "red", "golems": "gray", "werewolf": "brown", "medusa": "brown",
		"ice_mages": "violet", "swordsmen": "gray"}
	var ehex: Array = []
	for gi in range(mini(groups.size(), free.size())):
		ehex.append(free[gi])
		for ty in groups[gi]:
			e.s.eid_seq = int(e.s.eid_seq) + 1
			var eid := "e%d" % e.s.eid_seq
			e.s.enemies[eid] = {"type": ty, "color": cols[ty], "face_up": true, "hex": free[gi]}
			e.s.map.hex[free[gi]].enemies.append(eid)
	e.s.players[0].pos = ehex[3]
	view.refresh()
	await _wait(4)
	if only.is_empty():
		t.rig.reset(true)
		t.rig.snap()
		await _save("overview")
		t.focus_hex(ehex[1], 6.0)
		t.rig.snap()
		await _save("enemies")
	var done := {}
	var tower := ""
	var keep := ""
	var city := ""
	for k in e.s.map.hex:
		var site := str(e.s.map.hex[k].site)
		if site == "mage_tower" and tower == "":
			tower = k
		if site == "keep" and keep == "":
			keep = k
		if site == "city" and city == "":
			city = k
		if site == "" or done.has(site) or site in ["mine", "glade", "orcs", "draconum", "portal", "city"]:
			continue
		if not only.is_empty() and not only.has(site):
			continue
		done[site] = true
		t.focus_hex(k, 4.2)
		t.rig.snap()
		await _save("site_" + site)
	if not only.is_empty():
		quit()
		return
	# città con i difensori scoperti in fila davanti
	if city != "":
		for eid in e.s.map.hex[city].enemies:
			e.s.enemies[eid].face_up = true
		view.refresh()
		await _wait(3)
		t.focus_hex(city, 4.6)
		t.rig.snap()
		await _save("city")
	# fortezza con l'eroe e la guarnigione scoperta
	if keep != "":
		for eid in e.s.map.hex[keep].enemies:
			e.s.enemies[eid].face_up = true
		e.s.players[0].pos = keep
		view.refresh()
		await _wait(3)
		t.focus_hex(keep, 4.2)
		t.rig.snap()
		await _save("garrison")
	if tower != "":
		t.focus_hex(tower, 5.0)
		t.rig.yaw = 130.0
		t.rig.snap()
		await _save("rotated")
		t.rig.yaw = 0.0
		t.rig.snap()
		t.set_day(false, true)
		await _save("night")
	quit()
