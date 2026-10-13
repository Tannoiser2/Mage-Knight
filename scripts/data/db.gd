class_name MKDB
extends RefCounted
## Static data loader. Loads every JSON file of a data directory once
## (default res://data), merges cards_*.json into one card table and
## specials_*.json into one specials table, and normalises the different
## shapes the data files may have into the shapes the engine expects.
##
## Tables (all Dictionary id -> record):
##   cards units skills tactics enemies tiles ruins cities heroes scenarios specials
##   rules (Dictionary, raw)  assets (raw)

static var loaded_dir: String = ""
static var cards: Dictionary = {}
static var units: Dictionary = {}
static var skills: Dictionary = {}
static var tactics: Dictionary = {}
static var enemies: Dictionary = {}
static var tiles: Dictionary = {}
static var ruins: Dictionary = {}
static var cities: Dictionary = {}
static var heroes: Dictionary = {}
static var scenarios: Dictionary = {}
static var specials: Dictionary = {}
static var rules: Dictionary = {}
static var assets: Dictionary = {}
static var hero_decks: Dictionary = {}
static var standard_deck: Dictionary = {}
static var files: Array = []
static var problems: Array = []        # data problems found while loading
static var _ok_cache: Dictionary = {}

const TERRAIN_ALIASES := {
	"plains": "plains", "pianura": "plains", "plain": "plains", "grassland": "plains",
	"hills": "hills", "colline": "hills", "hill": "hills",
	"forest": "forest", "foresta": "forest", "woods": "forest",
	"desert": "desert", "deserto": "desert",
	"wasteland": "wasteland", "landa": "wasteland", "landa desolata": "wasteland", "wastelands": "wasteland",
	"swamp": "swamp", "palude": "swamp",
	"lake": "lake", "lago": "lake",
	"mountain": "mountain", "montagna": "mountain", "mountains": "mountain",
	"ocean": "ocean", "oceano": "ocean", "sea": "ocean", "": "ocean",
	"city": "plains",
}

const SITE_ALIASES := {
	"village": "village", "villaggio": "village",
	"monastery": "monastery", "monastero": "monastery",
	"keep": "keep", "fortezza": "keep",
	"mage tower": "mage_tower", "mage_tower": "mage_tower", "magetower": "mage_tower", "torre magica": "mage_tower",
	"dungeon": "dungeon",
	"tomb": "tomb", "tomba": "tomb",
	"monster den": "monster_den", "monster_den": "monster_den", "den": "monster_den", "tana dei mostri": "monster_den",
	"spawning grounds": "spawning_grounds", "spawning_grounds": "spawning_grounds", "terreno di nidificazione": "spawning_grounds",
	"ruin": "ruins", "ruins": "ruins", "ancient ruins": "ruins", "ancient_ruins": "ruins", "rovine": "ruins",
	"glade": "glade", "magical glade": "glade", "magical_glade": "glade", "radura": "glade", "radura magica": "glade",
	"mine": "mine", "crystal mine": "mine", "crystal_mine": "mine", "miniera": "mine",
	"city": "city", "città": "city",
	"portal": "portal", "portale": "portal",
}

const ELEM_ALIASES := {"P": "phys", "F": "fire", "I": "ice", "C": "cold", "phys": "phys", "physical": "phys",
	"fire": "fire", "ice": "ice", "cold": "cold", "coldfire": "cold", "cold_fire": "cold", "fuoco": "fire", "ghiaccio": "ice"}

const COLOR_ALIASES := {"red": "red", "blue": "blue", "green": "green", "white": "white", "gold": "gold", "black": "black",
	"rosso": "red", "blu": "blue", "verde": "green", "bianco": "white", "oro": "gold", "nero": "black",
	"gray": "gray", "grey": "gray", "brown": "brown", "tan": "brown", "violet": "violet", "purple": "violet",
	"yellow": "yellow"}

static func ensure(dir: String = "res://data") -> void:
	if loaded_dir == "":
		load_dir(dir)

static func reload() -> void:
	var d := loaded_dir if loaded_dir != "" else "res://data"
	loaded_dir = ""
	load_dir(d)

static func load_dir(dir: String) -> void:
	cards = {}; units = {}; skills = {}; tactics = {}; enemies = {}; tiles = {}; ruins = {}
	cities = {}; heroes = {}; scenarios = {}; specials = {}; rules = {}; assets = {}
	hero_decks = {}; standard_deck = {}
	files = []; problems = []; _ok_cache = {}
	loaded_dir = dir
	var da := DirAccess.open(dir)
	if da == null:
		problems.append("cartella dati non trovata: " + dir)
		return
	var names: Array = []
	for f in da.get_files():
		if f.ends_with(".json"):
			names.append(f)
	names.sort()
	for f in names:
		var txt := FileAccess.get_file_as_string(dir.path_join(f))
		if txt == "":
			continue
		var data = JSON.parse_string(txt)
		if data == null:
			problems.append("JSON non valido: " + f)
			continue
		files.append(f)
		var base: String = f.get_basename()
		if base == "cards" or base.begins_with("cards_"):
			for r in _records(data, "cards"):
				_add_card(r, f)
			if data is Dictionary:
				if data.get("hero_decks", null) is Dictionary:
					hero_decks.merge(data.hero_decks, true)
				if data.get("standard_deck", null) is Dictionary:
					standard_deck.merge(data.standard_deck, true)
		elif base == "specials" or base.begins_with("specials_"):
			if data is Dictionary:
				for k in data:
					if data[k] is Dictionary:
						specials[k] = data[k]
		elif base == "units" or base.begins_with("units_"):
			for r in _records(data, "units"):
				units[str(r.get("id", ""))] = _norm_unit(r)
		elif base == "skills" or base.begins_with("skills_"):
			for r in _records(data, "skills"):
				skills[str(r.get("id", ""))] = _norm_skill(r)
		elif base == "tactics" or base.begins_with("tactics_"):
			for r in _records(data, "tactics"):
				tactics[str(r.get("id", ""))] = _norm_tactic(r)
		elif base == "enemies" or base.begins_with("enemies_"):
			for r in _records(data, "enemies"):
				var e := _norm_enemy(r)
				enemies[e.id] = e
		elif base == "tiles" or base.begins_with("tiles_"):
			for r in _records(data, "tiles"):
				var t := _norm_tile(r)
				if t.id != "":
					tiles[t.id] = t
		elif base == "ruins" or base.begins_with("ruins_"):
			for r in _records(data, "ruins"):
				var rr := _norm_ruin(r)
				ruins[rr.id] = rr
		elif base == "cities" or base.begins_with("cities_"):
			for r in _records(data, "cities"):
				var c := _norm_city(r)
				cities[c.id] = c
		elif base == "heroes" or base.begins_with("heroes_"):
			for r in _records(data, "heroes"):
				heroes[str(r.get("id", ""))] = r
		elif base == "scenarios" or base.begins_with("scenarios_"):
			for r in _records(data, "scenarios"):
				scenarios[str(r.get("id", ""))] = r
		elif base == "rules":
			rules = data if data is Dictionary else {"list": data}
		elif base == "assets":
			assets = data if data is Dictionary else {}
	units.erase(""); skills.erase(""); tactics.erase(""); heroes.erase(""); scenarios.erase("")

## Turns any reasonable JSON shape into an array of records with "id".
static func _records(data, hint: String) -> Array:
	var out: Array = []
	if data is Array:
		for r in data:
			if r is Dictionary:
				out.append(r)
		return out
	if data is Dictionary:
		if data.has(hint) and (data[hint] is Array or data[hint] is Dictionary):
			return _records(data[hint], hint)
		# single list-valued key
		var list_keys := []
		for k in data:
			if data[k] is Array and not data[k].is_empty() and data[k][0] is Dictionary and data[k][0].has("id"):
				list_keys.append(k)
		if list_keys.size() >= 1 and list_keys.size() == data.size() - _meta_keys(data):
			for k in list_keys:
				out.append_array(_records(data[k], hint))
			return out
		for k in data:
			var v = data[k]
			if v is Dictionary and not str(k).begins_with("_"):
				var r: Dictionary = v.duplicate()
				if not r.has("id"):
					r["id"] = str(k)
				out.append(r)
	return out

static func _meta_keys(d: Dictionary) -> int:
	var n := 0
	for k in d:
		if str(k).begins_with("_") or k in ["version", "note", "notes", "source", "meta"]:
			n += 1
	return n

# ---------------------------------------------------------------- cards
static func _add_card(r: Dictionary, f: String) -> void:
	var c: Dictionary = r.duplicate(true)
	var id := str(c.get("id", ""))
	if id == "":
		problems.append("%s: carta senza id" % f)
		return
	c["id"] = id
	c["type"] = str(c.get("type", "basic"))
	c["color"] = _color(c.get("color", ""))
	if not c.has("basic") or not (c.basic is Array):
		c["basic"] = []
	if not c.has("powered") or not (c.powered is Array):
		c["powered"] = []
	if not c.has("side"):
		c["side"] = c.type != "wound"
	if c.type == "wound":
		c["side"] = false
	c["copies"] = int(c.get("copies", 1))
	c["impl"] = bool(c.get("impl", true))
	c["set"] = str(c.get("set", "base"))
	c["hero"] = str(c.get("hero", ""))
	c["combat_only"] = bool(c.get("combat_only", false))
	c["_file"] = f
	if cards.has(id):
		problems.append("%s: carta duplicata %s (già in %s)" % [f, id, cards[id].get("_file", "")])
	cards[id] = c

static func _color(v) -> String:
	var s := str(v).to_lower()
	return COLOR_ALIASES.get(s, s)

# ---------------------------------------------------------------- units / skills / tactics
static func _norm_unit(r: Dictionary) -> Dictionary:
	var u: Dictionary = r.duplicate(true)
	u["id"] = str(u.get("id", ""))
	u["level"] = int(u.get("level", 1))
	u["cost"] = int(u.get("cost", u.get("influence", 0)))
	u["armor"] = int(u.get("armor", u.get("armour", 1)))
	u["elite"] = bool(u.get("elite", false))
	u["copies"] = int(u.get("copies", 1))
	u["impl"] = bool(u.get("impl", true))
	u["set"] = str(u.get("set", "base"))
	var res: Array = []
	for x in u.get("resist", u.get("resistances", [])):
		res.append(ELEM_ALIASES.get(str(x), str(x)))
	u["resist"] = res
	var rec: Array = []
	for x in u.get("recruit", []):
		rec.append(SITE_ALIASES.get(str(x).to_lower(), str(x).to_lower()))
	u["recruit"] = rec
	var abs: Array = []
	for a in u.get("abilities", []):
		if a is Dictionary:
			var aa: Dictionary = a.duplicate(true)
			if not (aa.get("effect", []) is Array):
				aa["effect"] = []
			aa["mana"] = _color(aa.get("mana", "")) if aa.get("mana", "") != null else ""
			abs.append(aa)
		elif a is Array:
			abs.append({"effect": a, "mana": "", "text_it": ""})
	u["abilities"] = abs
	return u

static func _norm_skill(r: Dictionary) -> Dictionary:
	var k: Dictionary = r.duplicate(true)
	k["id"] = str(k.get("id", ""))
	k["hero"] = str(k.get("hero", ""))
	k["usage"] = str(k.get("usage", "turn"))
	if not (k.get("effect", []) is Array):
		k["effect"] = []
	k["impl"] = bool(k.get("impl", true))
	return k

static func _norm_tactic(r: Dictionary) -> Dictionary:
	var t: Dictionary = r.duplicate(true)
	t["id"] = str(t.get("id", ""))
	t["day"] = bool(t.get("day", true))
	t["number"] = int(t.get("number", 0))
	if not (t.get("effect", []) is Array):
		t["effect"] = []
	return t

# ---------------------------------------------------------------- enemies
static func _norm_enemy(r: Dictionary) -> Dictionary:
	var e := {}
	e["id"] = str(r.get("id", ""))
	e["name_it"] = str(r.get("name_it", r.get("name", e.id)))
	e["name_en"] = str(r.get("name_en", r.get("name", e.id)))
	e["color"] = _color(r.get("color", r.get("pugType", "green")))
	e["armor"] = int(r.get("armor", r.get("armour", 1)))
	e["fame"] = int(r.get("fame", 1))
	e["copies"] = int(r.get("copies", r.get("count", 1)))
	e["set"] = str(r.get("set", "base"))
	e["img"] = r.get("img", "")
	e["rep"] = int(r.get("rep", r.get("reputation", 0)))
	e["rep_bonus"] = int(r.get("rep_bonus", 0))
	# attacks
	var atk: Array = []
	var ra = r.get("attacks", r.get("attack", []))
	if ra is Array:
		for a in ra:
			if a is Dictionary:
				var el := str(ELEM_ALIASES.get(str(a.get("elem", a.get("element", "phys"))), "phys"))
				atk.append({"n": int(a.get("n", a.get("v", a.get("value", 0)))), "elem": el})
			elif a is float or a is int:
				atk.append({"n": int(a), "elem": "phys"})
			elif a is Array and a.size() >= 1:
				atk.append({"n": int(a[0]), "elem": str(ELEM_ALIASES.get(str(a[1]) if a.size() > 1 else "phys", "phys"))})
	elif ra is Dictionary:
		for k in ra:
			var el2 := str(ELEM_ALIASES.get(str(k), "phys"))
			var vals = ra[k]
			if not (vals is Array):
				vals = [vals]
			for v in vals:
				atk.append({"n": int(v), "elem": el2})
	elif ra is float or ra is int:
		atk.append({"n": int(ra), "elem": str(ELEM_ALIASES.get(str(r.get("elem", r.get("attack_elem", "phys"))), "phys"))})
	e["attacks"] = atk
	# resistances
	var res: Array = []
	var rr = r.get("resist", r.get("resistances", []))
	if rr is Array:
		for x in rr:
			res.append(ELEM_ALIASES.get(str(x), str(x)))
	for pair in [["pResist", "phys"], ["fResist", "fire"], ["iResist", "ice"]]:
		if r.get(pair[0], false) and not pair[1] in res:
			res.append(pair[1])
	e["resist"] = res
	# abilities
	var ab: Array = []
	for x in r.get("abilities", []):
		ab.append(str(x).to_lower())
	var flags := {"fortified": "fortified", "swiftness": "swift", "swift": "swift", "brutal": "brutal",
		"poison": "poison", "paralyze": "paralyze", "paralysis": "paralyze", "elusive": "elusive",
		"summon": "summon", "summoner": "summon", "assassin": "assassin", "cumbersome": "cumbersome",
		"unfortified": "unfortified", "arcane_immune": "arcane_immune", "defend": "defend", "vampiric": "vampiric"}
	for k in flags:
		if r.get(k, false) is bool and r.get(k, false):
			if not flags[k] in ab:
				ab.append(flags[k])
	var parsed: Array = []
	for x in ab:
		if x.begins_with("resist_"):
			var rel: String = ELEM_ALIASES.get(x.substr(7), x.substr(7))
			if not rel in res:
				res.append(rel)
		elif x.begins_with("summon:"):
			e["summon"] = _color(x.substr(7))
			parsed.append("summon")
		elif x.begins_with("rep_on_defeat:"):
			e["rep"] = int(x.substr(14))
		elif x.begins_with("defend:"):
			e["defend"] = int(x.substr(7))
			parsed.append("defend")
		else:
			parsed.append(x)
	ab = parsed
	var norm_ab: Array = []
	var ab_alias := {"swiftness": "swift", "rapido": "swift", "brutale": "brutal", "velenoso": "poison", "paralizzante": "paralyze",
		"fortificato": "fortified", "evocatore": "summon", "summoner": "summon", "paralysis": "paralyze"}
	for x in ab:
		var y: String = ab_alias.get(x, x)
		if not y in norm_ab:
			norm_ab.append(y)
	e["abilities"] = norm_ab
	e["fortified"] = "fortified" in norm_ab
	var sm = r.get("summon", r.get("monsters", null))
	if sm is Array and not sm.is_empty():
		e["summon"] = _color(sm[0])
		if not "summon" in norm_ab:
			norm_ab.append("summon")
	elif sm is String and sm != "":
		e["summon"] = _color(sm)
	elif "summon" in norm_ab and not e.has("summon"):
		e["summon"] = "brown"
	if "summon" in norm_ab and atk.is_empty():
		pass
	return e

# ---------------------------------------------------------------- tiles
static func _site(v) -> Dictionary:
	# returns {site, rampage, city}
	var s := str(v).strip_edges().to_lower()
	var out := {"site": "", "rampage": "", "city": ""}
	if s == "":
		return out
	if s.begins_with("city"):
		out.site = "city"
		var parts := s.split(" ", false)
		if parts.size() > 1:
			out.city = _color(parts[1])
		return out
	if s in ["rampaging", "orcs", "orc", "marauding orcs", "rampaging_green", "green"]:
		out.rampage = "green"
		return out
	if s in ["draconum", "rampaging_red", "red", "dragon"]:
		out.rampage = "red"
		return out
	out.site = SITE_ALIASES.get(s, s.replace(" ", "_"))
	return out

static func _norm_tile(r: Dictionary) -> Dictionary:
	var t := {}
	t["id"] = str(r.get("id", ""))
	var kind := str(r.get("kind", r.get("type", r.get("tileType", "country")))).to_lower()
	if kind in ["start", "starting", "iniziale"]:
		kind = "start"
	elif kind in ["core", "centrale", "city"]:
		kind = "core"
	else:
		kind = "country"
	t["kind"] = kind
	t["number"] = int(r.get("number", r.get("tileNumber", 0)))
	t["set"] = str(r.get("set", "base"))
	t["img"] = r.get("img", "")
	t["shape"] = str(r.get("shape", ""))
	t["city"] = ""
	var hexes := {}
	var src = r.get("hexes", null)
	if src is Dictionary:
		for k in src:
			var h = src[k]
			var dk := _dirkey(str(k))
			if h is Dictionary:
				hexes[dk] = _norm_hex(h)
			elif h is String:
				hexes[dk] = _norm_hex({"t": h})
	elif src is Array:
		for h in src:
			if h is Dictionary:
				var dk2 := _dirkey(str(h.get("d", h.get("dir", h.get("pos", "center")))))
				hexes[dk2] = _norm_hex(h)
	else:
		var ht = r.get("hexType", r.get("terrain", {}))
		var hf = r.get("hexFeature", r.get("features", {}))
		var mc = r.get("mineColors", r.get("mines", {}))
		if ht is Dictionary:
			for k in ht:
				var dk3 := _dirkey(str(k))
				var hd := {"t": ht[k], "site": hf.get(k, "") if hf is Dictionary else ""}
				if mc is Dictionary and mc.has(k):
					hd["mine"] = mc[k]
				hexes[dk3] = _norm_hex(hd)
	for dk in hexes:
		if hexes[dk].site == "city":
			t.city = hexes[dk].city
			if t.city == "":
				t.city = _color(r.get("city", r.get("city_color", "")))
				hexes[dk].city = t.city
	if t.city == "" and r.has("city"):
		t.city = _color(r.get("city"))
	t["hexes"] = hexes
	return t

static func _dirkey(k: String) -> String:
	var m := {"c": "center", "center": "center", "centre": "center", "0": "0", "w": "0", "60": "60", "sw": "60",
		"120": "120", "se": "120", "180": "180", "e": "180", "240": "240", "ne": "240", "300": "300", "nw": "300"}
	return m.get(k.to_lower(), k)

static func _norm_hex(h: Dictionary) -> Dictionary:
	var out := {}
	out["t"] = TERRAIN_ALIASES.get(str(h.get("t", h.get("terrain", "plains"))).to_lower(), str(h.get("t", "plains")).to_lower())
	var sinfo := _site(h.get("site", h.get("feature", "")))
	out["site"] = sinfo.site
	out["rampage"] = _color(h.get("rampage", sinfo.rampage)) if h.has("rampage") else sinfo.rampage
	if out.rampage == "orcs":
		out.rampage = "green"
	out["city"] = _color(h.get("city", sinfo.city)) if h.get("city", "") is String else sinfo.city
	var mine = h.get("mine", "")
	if mine is Array:
		var cl: Array = []
		for c in mine:
			cl.append(_color(c))
		out["mine"] = cl[0] if cl.size() == 1 else ""
		if cl.size() > 1:
			out["mines"] = cl
	else:
		out["mine"] = _color(mine) if mine != null else ""
	if out.mine != "" and out.site == "":
		out.site = "mine"
	return out

# ---------------------------------------------------------------- ruins / cities
static func _norm_ruin(r: Dictionary) -> Dictionary:
	var x: Dictionary = r.duplicate(true)
	x["id"] = str(x.get("id", ""))
	# kind: "altar" (pay 3 mana of a colour -> fame) or "enemies"
	if not x.has("kind"):
		x["kind"] = "altar" if x.has("altar") or x.has("mana") or x.has("cost") else "enemies"
	var en: Array = []
	for c in x.get("enemies", []):
		en.append(_color(c))
	x["enemies"] = en
	if x.has("rewards") and not x.has("reward"):
		x["reward"] = x.rewards
	if not (x.get("reward", []) is Array):
		x["reward"] = [x.get("reward")]
	if x.get("altar_cost", null) is Array:
		var ac: Array = []
		for c in x.altar_cost:
			ac.append(_color(c))
		x["altar_cost"] = ac
	x["copies"] = int(x.get("copies", 1))
	return x

static func _norm_city(r: Dictionary) -> Dictionary:
	var c: Dictionary = r.duplicate(true)
	c["id"] = str(c.get("id", c.get("color", "")))
	c["color"] = _color(c.get("color", c.id))
	return c

# ---------------------------------------------------------------- helpers
static func card(id: String) -> Dictionary:
	return cards.get(id, {})

## Collect all special/mod names used by an effect list (recursive).
static func effect_names(eff, out: Array) -> void:
	if not (eff is Array):
		return
	if eff.size() > 0 and eff[0] is String:
		var op: String = eff[0]
		if (op == "special" or op == "mod") and eff.size() > 1:
			if not str(eff[1]) in out:
				out.append(str(eff[1]))
		for i in range(1, eff.size()):
			if eff[i] is Array:
				effect_names(eff[i], out)
	else:
		for x in eff:
			effect_names(x, out)

## Is an effect list fully implemented (no unknown special/mod names)?
static func effects_ok(eff) -> bool:
	var names: Array = []
	effect_names(eff, names)
	var impl: Dictionary = MKSpecials.implemented_set()
	for n in names:
		if not impl.has(n):
			return false
	return true

static func card_ok(id: String) -> bool:
	if _ok_cache.has("c:" + id):
		return _ok_cache["c:" + id]
	var c: Dictionary = cards.get(id, {})
	var ok := not c.is_empty() and bool(c.get("impl", true)) and effects_ok(c.get("basic", [])) and effects_ok(c.get("powered", []))
	_ok_cache["c:" + id] = ok
	return ok

static func unit_ok(id: String) -> bool:
	if _ok_cache.has("u:" + id):
		return _ok_cache["u:" + id]
	var u: Dictionary = units.get(id, {})
	var ok := not u.is_empty() and bool(u.get("impl", true))
	if ok:
		for a in u.get("abilities", []):
			if not effects_ok(a.get("effect", [])):
				ok = false
		if not effects_ok(u.get("rules", [])) or not effects_ok(u.get("on_recruit", [])):
			ok = false
	_ok_cache["u:" + id] = ok
	return ok

static func skill_ok(id: String) -> bool:
	if _ok_cache.has("k:" + id):
		return _ok_cache["k:" + id]
	var k: Dictionary = skills.get(id, {})
	var ok := not k.is_empty() and bool(k.get("impl", true)) and effects_ok(k.get("effect", []))
	_ok_cache["k:" + id] = ok
	return ok

static func set_ok(rec: Dictionary, sets: Array) -> bool:
	return str(rec.get("set", "base")) in sets
