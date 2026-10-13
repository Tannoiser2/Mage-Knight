extends SceneTree
func _init():
	MKDB.load_dir("res://data")
	var impl := MKSpecials.implemented_set()
	var missing: Array = []
	var done: Array = []
	for n in MKDB.specials:
		if n.begins_with("_"):
			continue
		if impl.has(n):
			done.append(n)
		else:
			missing.append(n)
	done.sort()
	missing.sort()
	print("IMPLEMENTED (%d): %s" % [done.size(), ", ".join(done)])
	print("MISSING (%d): %s" % [missing.size(), ", ".join(missing)])
	var by := {}
	for c in MKDB.cards:
		var k: String = "card/" + str(MKDB.cards[c].get("set", ""))
		if not by.has(k): by[k] = [0, 0, []]
		by[k][0] += 1
		if MKDB.card_ok(c): by[k][1] += 1
		else: by[k][2].append(c)
	for u in MKDB.units:
		var k2: String = "unit/" + str(MKDB.units[u].get("set", ""))
		if not by.has(k2): by[k2] = [0, 0, []]
		by[k2][0] += 1
		if MKDB.unit_ok(u): by[k2][1] += 1
		else: by[k2][2].append(u)
	for s in MKDB.skills:
		var k3: String = "skill/" + str(MKDB.skills[s].get("set", ""))
		if not by.has(k3): by[k3] = [0, 0, []]
		by[k3][0] += 1
		if MKDB.skill_ok(s): by[k3][1] += 1
		else: by[k3][2].append(s)
	var keys := by.keys()
	keys.sort()
	for k in keys:
		print("%s: %d/%d disponibili %s" % [k, by[k][1], by[k][0], str(by[k][2]) if by[k][2].size() < 30 else "(%d mancanti)" % by[k][2].size()])
	quit()
