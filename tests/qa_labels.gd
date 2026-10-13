extends SceneTree
## QA: etichette delle scelte ("choice") di carte/unità/abilità: segnala opzioni indistinguibili o troncate.
## godot --headless --path . -s res://tests/qa_labels.gd

var bad := 0

func _init():
	MKDB.load_dir("res://data")
	for id in MKDB.cards:
		var c: Dictionary = MKDB.cards[id]
		if c.get("set", "base") != "base":
			continue
		for m in ["basic", "powered"]:
			_scan("carta " + id + " " + m, c.get(m, []))
	for id in MKDB.units:
		var u: Dictionary = MKDB.units[id]
		if u.get("set", "base") != "base":
			continue
		for ab in u.get("abilities", []):
			_scan("unità " + id, ab.get("effect", []))
	for id in MKDB.skills:
		var k: Dictionary = MKDB.skills[id]
		if k.get("set", "base") != "base":
			continue
		_scan("abilità " + id, k.get("effect", []))
	print("QALABELS problemi: ", bad)
	quit()

func _scan(where: String, effs) -> void:
	if not (effs is Array):
		return
	for e in effs:
		if not (e is Array) or e.is_empty():
			continue
		if not (e[0] is String):
			_scan(where, e)
			continue
		if e[0] == "choice" and e.size() > 1:
			var labels: Array = []
			for o in e[1]:
				labels.append(MKEffects.describe_list(o))
			var seen := {}
			for l in labels:
				if seen.has(l) or l.ends_with("…") or l == "niente":
					bad += 1
					print("%s: %s" % [where, str(labels)])
					break
				seen[l] = true
			for o in e[1]:
				_scan(where, o)
		elif e[0] == "if" or e[0] == "pay_mana" or e[0] == "discard":
			for i in range(1, e.size()):
				if e[i] is Array:
					_scan(where, e[i])
