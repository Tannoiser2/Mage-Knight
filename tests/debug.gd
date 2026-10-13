extends SceneTree
func _init():
	var args := OS.get_cmdline_user_args()
	var scn := str(args[0]) if args.size() > 0 else "solo_conquest"
	var seed := int(args[1]) if args.size() > 1 else 1
	var np := int(args[2]) if args.size() > 2 else 1
	var maxn := int(args[3]) if args.size() > 3 else 400
	MKDB.load_dir("res://data")
	var heroes := ["arythea", "tovak", "goldyx", "norowas"]
	var cfg := {"scenario": scn, "seed": seed, "players": []}
	for i in np:
		cfg.players.append({"hero": heroes[i], "name": heroes[i]})
	var e := MKEngine.create(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var shown := 0
	for n in maxn:
		if e.s.phase == "game_over":
			break
		var av: Array = e.available()
		if av.is_empty():
			print("STUCK phase=", e.s.phase, " actor=", e.actor(), " turn=", JSON.stringify(e.s.turn).substr(0, 600))
			break
		var x: Dictionary = av[rng.randi() % av.size()]
		for a in av:
			if a.a.t in ["explore", "attack", "site", "challenge", "block"] and rng.randf() < 0.7:
				x = a
		var r := e.apply(x.a)
		print("> [%d] %s  %s" % [e.actor(), x.label, "" if r.ok else "ERR " + r.err])
		while shown < e.s.log.size():
			print("     · ", e.s.log[shown].txt)
			shown += 1
		if e.s.log.size() < shown:
			shown = e.s.log.size()
	quit()
