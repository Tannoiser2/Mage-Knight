class_name MKTableDemo
extends RefCounted
## Stato di prova per il tavolo 3D (sfondo del menu e test grafici) quando il motore non c'è.
## Segue la forma dello stato della SPEC §3 (solo i campi che il tavolo usa).

## Terreni/siti di alcune tessere (dal Lua del modulo, chiavi direzionali della SPEC §2).
const TILES := {
	"start_a": {"t": {"center": "plains", "0": "ocean", "60": "ocean", "120": "ocean", "180": "plains", "240": "forest", "300": "plains"},
		"f": {"center": "portal"}},
	"c01": {"t": {"center": "forest", "0": "forest", "60": "plains", "120": "plains", "180": "plains", "240": "lake", "300": "forest"},
		"f": {"center": "glade", "180": "village", "300": "rampaging"}},
	"c02": {"t": {"center": "hills", "0": "plains", "60": "hills", "120": "plains", "180": "plains", "240": "forest", "300": "hills"},
		"f": {"60": "mine", "180": "village", "240": "glade", "300": "rampaging"}},
	"c03": {"t": {"center": "forest", "0": "plains", "60": "plains", "120": "hills", "180": "hills", "240": "hills", "300": "plains"},
		"f": {"60": "village", "120": "mine", "240": "keep"}},
	"c05": {"t": {"center": "lake", "0": "forest", "60": "forest", "120": "hills", "180": "plains", "240": "plains", "300": "forest"},
		"f": {"0": "glade", "120": "mine", "180": "rampaging", "240": "monastery"}},
	"k05": {"t": {"center": "plains", "0": "lake", "60": "forest", "120": "swamp", "180": "swamp", "240": "swamp", "300": "forest"},
		"f": {"center": "city green", "60": "rampaging", "180": "rampaging", "240": "village", "300": "glade"}},
}
const DIRKEY := {"center": Vector2i(0, 0), "0": Vector2i(-1, 0), "60": Vector2i(-1, 1), "120": Vector2i(0, 1),
	"180": Vector2i(1, 0), "240": Vector2i(1, -1), "300": Vector2i(0, -1)}


static func _place(s: Dictionary, id: String, slot: Vector2i) -> void:
	s["map"]["tiles"].append({"id": id, "slot": MKHexMesh.key(slot.x, slot.y)})
	var T: Dictionary = TILES.get(id, {"t": {}, "f": {}})
	var rj = _tiles_json().get(id, {})
	var real: Dictionary = rj if rj is Dictionary else {}
	for d in DIRKEY:
		var h: Vector2i = slot + DIRKEY[d]
		var site: String = str(T["f"].get(d, "")).replace(" ", "_")
		var terr: String = str(T["t"].get(d, "plains"))
		# dati veri delle tessere (data/tiles.json dell'agente WORLD), se ci sono
		if real.get("hexes") is Dictionary and real["hexes"].get(d) is Dictionary:
			terr = str(real["hexes"][d].get("t", terr))
			site = str(real["hexes"][d].get("site", site))
			if site == "city" and real.get("city") is String:
				site = "city_" + str(real["city"])
		var hx := {"t": terr, "site": site, "tile": id, "enemies": [], "owner": -1}
		if site.begins_with("city_"):
			hx["city"] = {"color": site.substr(5), "level": 5}
			hx["site"] = "city"
		if site == "city" and not hx.has("city"):
			hx["city"] = {"color": "green", "level": 5}
		if site in ["rampaging", "orcs", "draconum"]:
			hx["site"] = ""
		s["map"]["hex"][MKHexMesh.key(h.x, h.y)] = hx


## Nemici veri (assets/enemies/<id>.webp, agente WORLD) al posto degli id di prova, se ci sono.
const REAL := {"green_0": "diggers", "green_1": "prowlers", "green_2": "wolf_riders", "white_0": "altem_guardsmen",
	"white_1": "altem_mages", "gray_0": "crossbowmen"}


static var _tj = null

static func _tiles_json() -> Dictionary:
	if _tj == null:
		_tj = {}
		if FileAccess.file_exists("res://data/tiles.json"):
			var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/tiles.json"))
			if j is Dictionary and j.get("tiles") is Dictionary:
				_tj = j["tiles"]
	return _tj


static func _enemy(s: Dictionary, eid: String, type: String, color: String, hex: Vector2i, up := true) -> void:
	var k := MKHexMesh.key(hex.x, hex.y)
	if REAL.has(type) and ResourceLoader.exists("res://assets/enemies/%s.webp" % REAL[type]):
		type = REAL[type]
	s["enemies"][eid] = {"type": type, "color": color, "face_up": up, "hex": k}
	if s["map"]["hex"].has(k):
		s["map"]["hex"][k]["enemies"].append(eid)


## variant 0: inizio partita; 1: qualche turno dopo (eroi mossi, una tessera in più, notte).
static func state(variant := 0) -> Dictionary:
	var s := {
		"round": 1 + variant, "day": variant == 0, "phase": "turn", "active": 0, "turn_order": [0, 1],
		"map": {"tiles": [], "hex": {}, "shape": "wedge", "tile_deck": ["c04", "c06", "c07", "c08"]},
		"enemies": {},
		"players": [
			{"hero": "arythea", "name": "Stefano", "ctrl": "human", "pos": "2,-3", "shields": ["3,-3"], "fame": 5, "level": 2},
			{"hero": "goldyx", "name": "Goldyx (IA)", "ctrl": "ai", "pos": "0,0", "shields": [], "fame": 2, "level": 1},
		],
	}
	_place(s, "start_a", Vector2i(0, 0))
	_place(s, "c01", Vector2i(1, -3))
	_place(s, "c02", Vector2i(3, -2))
	_place(s, "c05", Vector2i(2, -6))
	_place(s, "k05", Vector2i(4, -5))
	_enemy(s, "e1", "green_0", "green", Vector2i(1, -4))
	_enemy(s, "e3", "green_2", "green", Vector2i(3, -6))
	_enemy(s, "e4", "white_0", "white", Vector2i(4, -5))
	_enemy(s, "e5", "white_1", "white", Vector2i(4, -5))
	_enemy(s, "e6", "green_1", "green", Vector2i(3, -4))
	_enemy(s, "e7", "green_2", "green", Vector2i(5, -5))
	if variant >= 1:
		_place(s, "c03", Vector2i(6, -4))
		_enemy(s, "e8", "gray_0", "gray", Vector2i(7, -5), false)
		s["players"][0]["pos"] = "4,-3"
		s["players"][1]["pos"] = "1,-4"
		s["players"][1]["shields"] = ["1,-4"]
		s["enemies"].erase("e1")
		s["map"]["hex"]["1,-4"]["enemies"].clear()
		s["active"] = 1
	return s
