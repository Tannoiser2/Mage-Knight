extends SceneTree
## Partite intere solo IA guidate da MKController (senza grafica), per verificare il controllore:
##   godot --headless --path . -s res://tests/ui_ctrl.gd -- [scenario|all]
## Stampa "UICTRL <scenario> ..." con l'esito; usa MKAI se c'è, altrimenti l'IA di ripiego.

func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0 and args[0] != "all":
		only = args[0]
	var games := [
		["first_recon", ["goldyx", "tovak"]],
		["solo_conquest", ["arythea"]],
		["coop_conquest", ["norowas", "arythea"]],
		["full_conquest", ["tovak", "goldyx", "arythea"]],
	]
	var fails := 0
	for g in games:
		if only != "" and g[0] != only:
			continue
		var pl := []
		for h in g[1]:
			pl.append({"hero": h, "ctrl": "ai", "ai_level": 2, "name": h.capitalize()})
		var c := MKController.new()
		c.autosave = false
		c.set_speed(3)
		root.add_child(c)
		var t0 := Time.get_ticks_msec()
		var n := [0]
		c.changed.connect(func(): n[0] += 1)
		c.start({"scenario": g[0], "seed": 5, "players": pl, "options": {"set": "base"}})
		var last := -1
		var still := 0
		while not c.game_over() and Time.get_ticks_msec() - t0 < 600000:
			await process_frame
			if n[0] == last:
				still += 1
				if still > 600:
					break
			else:
				still = 0
				last = n[0]
		var ok := c.game_over()
		if not ok:
			fails += 1
		print("UICTRL %s %s actions=%d round=%d time=%ds %s" % [g[0], "OK" if ok else "BLOCCATA", n[0], int(c.eng.s.round), (Time.get_ticks_msec() - t0) / 1000,
			JSON.stringify(c.eng.s.result).substr(0, 160) if ok else "phase=%s actor=%d pending=%s" % [c.eng.s.phase, c.eng.actor(), str(c.eng.s.pending != null)]])
		c.queue_free()
		await process_frame
	print("UICTRL done fails=%d" % fails)
	quit()
