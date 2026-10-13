class_name MKMiniatures
extends RefCounted
## Miniature 3D facoltative (generate con Meshy: meshy/genera_miniature.py) in assets/miniatures/<id>.glb.
## Convenzione di BEAST: se il file c'è sostituisce (o arricchisce) il modello predefinito, senza
## altre modifiche al codice. Id: tipo di nemico (es. "high_dragon"), "site_<sito>" per i siti
## (site_keep, site_mage_tower, site_monastery, site_village).
## La miniatura viene normalizzata: alta `height` (unità del tavolo: 1 = raggio di un esagono),
## larga al massimo `max_w`, appoggiata a y = 0, centrata in x/z, rivolta verso +Z (verso chi guarda,
## come escono i modelli di Meshy); `yaw` in gradi la ruota attorno alla verticale.

const DIR := "res://assets/miniatures/"

const SETTINGS := "user://mk_settings.cfg"

static var _cache := {}        # id -> PackedScene oppure null (non c'è)
## Impostazione «Miniature 3D» (menu di gioco): false = solo i segnalini e le tessere.
static var enabled: bool = _load_enabled()


static func _load_enabled() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return true
	return bool(cf.get_value("table", "miniatures", true))


static func set_enabled(on: bool) -> void:
	enabled = on
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("table", "miniatures", on)
	cf.save(SETTINGS)


static func path_for(id: String) -> String:
	return DIR + id + ".glb"


static func has(id: String) -> bool:
	if _cache.has(id):
		return _cache[id] != null
	return ResourceLoader.exists(path_for(id))


## Nodo pronto da aggiungere alla scena, oppure null se la miniatura non esiste.
static func load_for(id: String, height := 0.55, max_w := 0.7, yaw := 0.0) -> Node3D:
	var ps: PackedScene = null
	if _cache.has(id):
		ps = _cache[id]
	else:
		var p := path_for(id)
		if ResourceLoader.exists(p):
			var r = load(p)
			ps = r if r is PackedScene else null
		_cache[id] = ps
	if ps == null:
		return null
	var inst = ps.instantiate()
	if not (inst is Node3D):
		if inst != null:
			inst.free()
		return null
	var root := Node3D.new()
	root.name = "mini_" + id
	var hold := Node3D.new()
	hold.add_child(inst)
	root.add_child(hold)
	var ab := scene_aabb(inst)
	if ab.size.y > 0.0001:
		var sc := minf(height / ab.size.y, max_w / maxf(0.0001, maxf(ab.size.x, ab.size.z)))
		hold.scale = Vector3.ONE * sc
		hold.position = Vector3(-(ab.position.x + ab.size.x / 2.0) * sc, -ab.position.y * sc, -(ab.position.z + ab.size.z / 2.0) * sc)
	root.rotation_degrees.y = yaw
	return root


## Miniatura di un tipo di nemico (solo per i segnalini scoperti: quelli coperti non vanno rivelati).
static func enemy(type: String, height := 0.55, max_w := 0.7) -> Node3D:
	return load_for(type, height, max_w)


## Struttura di un sito (village, monastery, keep, mage_tower).
static func site(site_id: String, height := 0.6, max_w := 0.9) -> Node3D:
	return load_for("site_" + site_id, height, max_w)


## Struttura di un sito calibrata sul disegno della tessera (data/site_minis.json): il modello non è
## normalizzato ma scalato di `scale` (unità del tavolo per unità del .glb) e ancorato al centro del suo
## AABB in x/z e alla base (y minima), come nella calibrazione; la rotazione la decide chi lo piazza.
static func site_fitted(site_id: String, scale: float) -> Node3D:
	var root := load_for("site_" + site_id, 1.0, 1.0)
	if root == null:
		return null
	var hold: Node3D = root.get_child(0)
	var inst: Node = hold.get_child(0)
	var ab := scene_aabb(inst)
	hold.scale = Vector3.ONE * scale
	hold.position = Vector3(-(ab.position.x + ab.size.x / 2.0) * scale, -ab.position.y * scale, -(ab.position.z + ab.size.z / 2.0) * scale)
	root.rotation = Vector3.ZERO
	return root


## AABB di tutte le mesh della scena, nel sistema di `n`.
static func scene_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			if p is Node3D:
				t = (p as Node3D).transform * t
			p = p.get_parent()
		var a := t * mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	if n is MeshInstance3D and first:
		out = (n as MeshInstance3D).get_aabb()
	return out

