class_name MKEngine
extends RefCounted
## Mage Knight rules engine. All state lives in `s` (JSON types only).
## API: create / from_state / clone / apply / check / actor / available /
## reachable / move_cost / effective_attack / effective_block / fingerprint /
## card / score. No UI dependencies.

const DUMMY := 9
const FAME_LEVELS := [0, 3, 8, 15, 24, 35, 48, 63, 80, 99]
const LV_ARMOR := [2, 2, 3, 3, 3, 3, 4, 4, 4, 4]
const LV_HAND := [5, 5, 5, 5, 6, 6, 6, 6, 7, 7]
const LV_CMD := [1, 1, 2, 2, 3, 3, 4, 4, 5, 5]
const REP_BONUS := [-99, -5, -3, -2, -1, -1, 0, 0, 0, 1, 1, 2, 2, 3, 5]
const COST_DAY := {"plains": 2, "hills": 3, "forest": 3, "desert": 5, "wasteland": 4, "swamp": 5}
const COST_NIGHT := {"plains": 2, "hills": 3, "forest": 5, "desert": 3, "wasteland": 4, "swamp": 5}
const DIE_COLORS := ["red", "blue", "green", "white", "gold", "black"]
const FORTIFIED_SITES := ["keep", "mage_tower", "city"]
const ADVENTURE_SITES := ["dungeon", "tomb", "monster_den", "spawning_grounds", "ruins", "maze", "labyrinth"]
const SITE_IT := {"village": "villaggio", "monastery": "monastero", "keep": "castello", "mage_tower": "torre della magia",
	"dungeon": "sotterraneo", "tomb": "tomba", "monster_den": "tana del mostro", "spawning_grounds": "terreni di nidificazione",
	"ruins": "antiche rovine", "glade": "radura magica", "mine": "miniera di cristalli", "city": "città", "portal": "portale",
	"camp": "campo profughi", "maze": "dedalo", "labyrinth": "labirinto"}
const HERO_COLORS := {"arythea": ["red", "red", "white"], "goldyx": ["green", "green", "blue"], "norowas": ["white", "white", "green"],
	"tovak": ["blue", "blue", "red"], "wolfhawk": ["white", "white", "blue"], "krang": ["red", "red", "green"], "braevalar": ["green", "green", "blue"]}

var s: Dictionary = {}
var _q = null            # running effect queue (transient)
var _suspended := false  # set when an effect asks a decision (transient)

# ================================================================ creation
static func create(cfg: Dictionary) -> MKEngine:
	MKDB.ensure()
	var e := MKEngine.new()
	e._setup(cfg)
	return e

static func from_state(st: Dictionary) -> MKEngine:
	MKDB.ensure()
	var e := MKEngine.new()
	e.s = _intify(st.duplicate(true))
	return e

func clone() -> MKEngine:
	var e := MKEngine.new()
	e.s = s.duplicate(true)
	return e

static func _intify(v):
	if v is float:
		if v == floor(v) and abs(v) < 9.0e15:
			return int(v)
		return v
	if v is Array:
		for i in v.size():
			v[i] = _intify(v[i])
		return v
	if v is Dictionary:
		for k in v.keys():
			v[k] = _intify(v[k])
		return v
	return v

static var _fp_re: RegEx = null

## Stable hash of the state (integral floats normalised, keys sorted).
func fingerprint() -> String:
	if _fp_re == null:
		_fp_re = RegEx.new()
		_fp_re.compile("(?<=[0-9])\\.0(?=[,}\\]])")
	return _fp_re.sub(JSON.stringify(s, "", true), "", true).md5_text()

# ================================================================ small helpers
func add_log(k: String, txt: String, extra: Dictionary = {}) -> void:
	var e := {}
	for x in extra:
		e[x] = extra[x]
	e["k"] = k
	e["txt"] = txt
	e["seq"] = int(s.get("log_seq", 0))
	s["log_seq"] = int(s.get("log_seq", 0)) + 1
	s.log.append(e)
	if s.log.size() > 400:
		s.log = s.log.slice(s.log.size() - 300)

func P(i: int) -> Dictionary:
	return s.players[i]

func pname(i: int) -> String:
	if i == DUMMY:
		return "Giocatore Neutrale"
	return str(s.players[i].name)

func hex(k: String) -> Dictionary:
	return s.map.hex.get(k, {})

func card_id(iid: String) -> String:
	var i := iid.find("#")
	return iid if i < 0 else iid.substr(0, i)

func card(iid: String) -> Dictionary:
	var id := card_id(iid)
	if id == "wound":
		return MKDB.cards.get("wound", {"id": "wound", "type": "wound", "name_it": "Ferita", "basic": [], "powered": [], "side": false, "color": ""})
	return MKDB.cards.get(id, {})

func card_name(iid: String) -> String:
	var c := card(iid)
	return str(c.get("name_it", c.get("name_en", card_id(iid))))

func is_wound(iid: String) -> bool:
	return card_id(iid) == "wound" or card(iid).get("type", "") == "wound"

func new_iid(id: String) -> String:
	s.iid_seq = int(s.iid_seq) + 1
	return "%s#%d" % [id, s.iid_seq]

func unit_def(u: Dictionary) -> Dictionary:
	return MKDB.units.get(str(u.get("id", "")), {})

func unit_level(u: Dictionary) -> int:
	return int(unit_def(u).get("level", 1))

func unit_name(u: Dictionary) -> String:
	var d := unit_def(u)
	return str(d.get("name_it", d.get("name_en", u.get("id", "Unità"))))

func unit_name_by_uid(p: int, uid) -> String:
	var u = find_unit(p, uid)
	return unit_name(u) if u != null else "Unità"

func find_unit(p: int, uid) -> Variant:
	for u in s.players[p].units:
		if int(u.uid) == int(uid):
			return u
	return null

func enemy_def(eid: String) -> Dictionary:
	var inst: Dictionary = s.enemies.get(eid, {})
	return MKDB.enemies.get(str(inst.get("type", "")), {})

func enemy_name(eid: String) -> String:
	return str(enemy_def(eid).get("name_it", "Nemico"))

func level_of(fame: int) -> int:
	var lv := 1
	for i in FAME_LEVELS.size():
		if fame >= FAME_LEVELS[i]:
			lv = i + 1
	return lv

func flag(p: int, name: String) -> bool:
	if s.turn.get("player", -1) != p:
		return false
	for m in s.turn.mods:
		if m.get("name", "") == name:
			return true
	return false

func mods_named(name: String) -> Array:
	var out: Array = []
	for m in s.turn.get("mods", []):
		if m.get("name", "") == name:
			out.append(m)
	return out

func is_competitive() -> bool:
	return s.scn.get("mode", "") == "competitive"

func is_solo_like() -> bool:
	return s.dummy != null

# ================================================================ setup
func _setup(cfg: Dictionary) -> void:
	var c := cfg.duplicate(true)
	if not c.has("seed"):
		c["seed"] = 1
	if not c.has("players") or c.players.is_empty():
		c["players"] = [{"hero": "arythea", "ctrl": "human", "name": "Giocatore"}]
	if not c.has("options"):
		c["options"] = {}
	s = {
		"v": 1, "cfg": c, "rng": MKRng.seed_state(int(c.seed)), "round": 0, "day": true, "phase": "setup",
		"turn_order": [], "order_pos": 0, "active": -1, "final_turns": {}, "announced_by": -1, "game_end_pending": false,
		"players": [], "dummy": null, "map": {"tiles": [], "hex": {}, "tile_deck": [], "shape": "wedge"},
		"source": [], "offers": {"units": [], "aa": [], "spells": [], "skills": [], "monastery": []},
		"decks": {"aa": [], "spells": [], "artifacts": [], "units_reg": [], "units_elite": [], "wounds": 99, "tiles_spare": []},
		"enemy_bags": {}, "enemies": {}, "eid_seq": 0, "iid_seq": 0, "uid_seq": 0,
		"turn": {}, "combat": null, "pending": null, "log": [], "log_seq": 0, "result": null,
		"tactics_avail": [], "tactics_removed": [], "tactic_pick": [], "core_revealed": false, "cities_revealed": 0,
		"scn": {},
	}
	s.turn = _fresh_turn(-1)
	var sc := _scenario(c)
	s.scn = sc
	var sets: Array = c.options.get("sets", [c.options.get("set", "base")])
	if not c.options.has("sets") and c.options.has("content"):
		sets = MKDB.content_sets(str(c.options.content))
	sc["sets"] = sets
	# players
	var used_heroes: Array = []
	for i in c.players.size():
		var pc: Dictionary = c.players[i]
		var hero: String = str(pc.get("hero", "arythea"))
		used_heroes.append(hero)
		var pl := _new_player(hero, pc, i)
		s.players.append(pl)
	# dummy player
	if sc.get("dummy", false):
		var cands: Array = []
		for h in _hero_ids():
			if not h in used_heroes:
				cands.append(h)
		if not cands.is_empty():
			var dh: String = MKRng.pick(s, cands)
			var deck: Array = []
			for id in build_deck(dh):
				deck.append(new_iid(id))
			MKRng.shuffle(s, deck)
			var cr := {"red": 0, "blue": 0, "green": 0, "white": 0}
			for col in hero_spheres(dh):
				cr[col] = int(cr.get(col, 0)) + 1
			s.dummy = {"hero": dh, "name": "Neutrale (%s)" % hero_name(dh), "deck": deck, "discard": [], "crystals": cr, "tactic": ""}
	# solo scenario specials
	if sc.get("start_fame", 0) > 0:
		for pl in s.players:
			pl.fame = int(sc.start_fame)
	if sc.get("start_rep", 0) != 0:
		for pl in s.players:
			pl.rep = int(sc.start_rep)
	_setup_decks(sets)
	_setup_enemies(sets)
	_setup_map(sc, sets)
	# skills pile per player
	for pl in s.players:
		var pile: Array = []
		for k in MKDB.skills:
			var sk: Dictionary = MKDB.skills[k]
			# a hero always brings its own skills (the expansion heroes are playable with any content set)
			if sk.get("hero", "") == pl.hero and MKDB.skill_ok(k) and _skill_mode_ok(sk):
				pile.append(k)
		pile.sort()
		MKRng.shuffle(s, pile)
		pl.skill_pile = pile
	if s.dummy != null:
		var dp: Array = []
		for k in MKDB.skills:
			var sk2: Dictionary = MKDB.skills[k]
			if sk2.get("hero", "") == s.dummy.hero and MKDB.skill_ok(k) and _skill_mode_ok(sk2):
				dp.append(k)
		dp.sort()
		MKRng.shuffle(s, dp)
		s.dummy["skill_pile"] = dp
	# draw starting hands
	for i in s.players.size():
		draw(i, int(P(i).hand_limit), true)
	add_log("setup", "Nuova partita: %s" % str(sc.get("name_it", sc.id)), {"scenario": sc.id})
	_start_round(true)

func _skill_mode_ok(sk: Dictionary) -> bool:
	var m := str(sk.get("mode", sk.get("interactive", "")))
	if m == "" or m == "false":
		return true
	if is_competitive():
		return m != "coop" and m != "cooperative"
	return m != "competitive" and m != "comp"

func _hero_ids() -> Array:
	var out: Array = []
	for h in MKDB.heroes:
		var hd: Dictionary = MKDB.heroes[h]
		if MKDB.set_ok(hd, s.scn.get("sets", ["base"])) or s.scn.get("sets", ["base"]).has(str(hd.get("set", ""))):
			out.append(h)
	if out.is_empty():
		out = ["arythea", "goldyx", "norowas", "tovak"]
	out.sort()
	return out

func hero_name(h: String) -> String:
	var hd: Dictionary = MKDB.heroes.get(h, {})
	return str(hd.get("name_it", hd.get("name", h.capitalize())))

func hero_spheres(h: String) -> Array:
	var hd: Dictionary = MKDB.heroes.get(h, {})
	for k in ["spheres", "crystals", "dummy_crystals", "colors"]:
		if hd.get(k, null) is Array and hd[k].size() > 0:
			var out: Array = []
			for c in hd[k]:
				out.append(MKDB._color(c))
			return out
	return HERO_COLORS.get(h, ["red", "blue", "green"])

func _new_player(hero: String, pc: Dictionary, i: int) -> Dictionary:
	var deck: Array = []
	for id in build_deck(hero):
		deck.append(new_iid(id))
	MKRng.shuffle(s, deck)
	return {
		"hero": hero, "name": str(pc.get("name", hero_name(hero))), "ctrl": str(pc.get("ctrl", "human")),
		"ai_level": int(pc.get("ai_level", 2)), "seat": pc.get("seat", i),
		"fame": 0, "level": 1, "rep": 0, "armor": 2, "hand_limit": 5, "command": 1,
		"deck": deck, "hand": [], "discard": [], "play": [], "removed": [],
		"units": [], "crystals": {"red": 0, "blue": 0, "green": 0, "white": 0}, "tokens": [],
		"skills": [], "skill_pile": [], "pos": "", "tactic": "", "tactic_used": false, "tactic_store": [],
		"shields": [], "knocked_out": false, "wounds_this_combat": 0, "stolen_die": "",
		"pending_hand_bonus": 0, "spells_cast": 0, "turns": 0, "finished": false,
	}

## Basic deck of a hero (16 cards), using heroes.json deck if given.
func build_deck(hero: String) -> Array:
	var hd: Dictionary = MKDB.heroes.get(hero, {})
	var out: Array = []
	var dk = hd.get("deck", MKDB.hero_decks.get(hero, null))
	if dk is Array and not dk.is_empty():
		for x in dk:
			if x is String:
				out.append(x)
			elif x is Dictionary:
				for n in int(x.get("copies", x.get("n", 1))):
					out.append(str(x.get("id", "")))
	elif dk is Dictionary and not dk.is_empty():
		for k in dk:
			for n in int(dk[k]):
				out.append(str(k))
	else:
		var ids: Array = MKDB.cards.keys()
		ids.sort()
		for id in ids:
			var c: Dictionary = MKDB.cards[id]
			if c.type == "basic" and c.get("hero", "") == "" and c.get("set", "base") == "base":
				for n in int(c.copies):
					out.append(id)
		for id in ids:
			var c2: Dictionary = MKDB.cards[id]
			if c2.type == "basic" and c2.get("hero", "") == hero:
				var rep: String = str(c2.get("replaces", ""))
				var idx := out.find(rep)
				if idx >= 0:
					out[idx] = id
				else:
					out.append(id)
	var ok: Array = []
	for id in out:
		if MKDB.card_ok(id):
			ok.append(id)
	return ok

func _scenario(c: Dictionary) -> Dictionary:
	var id := str(c.get("scenario", "first_recon"))
	var np: int = c.players.size()
	var sc := {"id": id, "name_it": id, "rounds": 6, "shape": "wedge", "country": 8, "core": 2, "city": 2,
		"city_levels": [5, 8], "mode": "competitive", "dummy": false, "end": "cities", "cities_enterable": true,
		"elite": true, "fame_per_tile": 0, "start_fame": 0, "start_rep": 0, "extra_die": 0, "extra_unit": 0,
		"tactics_removed_solo": false, "dummy_first": false, "fame_line_bonus": 0, "remove_one_tactic": false,
		"dummy_no_final": false, "titles": np > 1, "scoring": "standard", "score_extra": {}, "cols": 5}
	match id:
		"first_recon":
			sc.merge({"name_it": "Prima ricognizione", "rounds": 3 if np > 1 else 4, "country": [8, 8, 9, 11][clampi(np - 1, 0, 3)],
				"core": 2, "city": 1, "city_levels": [1], "end": "city_revealed", "cities_enterable": false, "elite": false,
				"fame_per_tile": 1, "dummy": np == 1, "mode": "competitive" if np > 1 else "solo", "tactics_removed_solo": np == 1}, true)
		"solo_conquest":
			sc.merge({"name_it": "Conquista in solitario", "rounds": 6, "country": 7, "core": 2, "city": 2, "city_levels": [5, 8],
				"end": "cities", "dummy": true, "mode": "solo", "tactics_removed_solo": true, "dummy_no_final": true}, true)
		"coop_conquest":
			sc.merge({"name_it": "Cooperazione totale", "rounds": 6, "shape": "open", "country": 8 if np <= 2 else 10,
				"core": np, "city": np + 1, "city_levels": ([5, 5, 8] if np <= 2 else [5, 5, 5, 11]), "end": "cities",
				"dummy": true, "mode": "coop", "dummy_first": true}, true)
		"full_conquest":
			sc.merge({"name_it": "Conquista completa", "rounds": 6, "shape": "wedge" if np <= 3 else "open",
				"country": [8, 8, 9, 11][clampi(np - 1, 0, 3)], "core": maxi(1, np - 1), "city": maxi(2, np),
				"city_levels": [4, 4, 4, 4], "end": "cities", "mode": "competitive", "dummy": np == 1}, true)
	# data (scenarios.json)
	var d: Dictionary = MKDB.scenarios.get(id, {})
	if not d.is_empty():
		_scenario_from_data(sc, d, np)
	if c.options.has("city_level"):
		var lv := int(c.options.city_level)
		var arr: Array = []
		for i in maxi(1, int(sc.city)):
			arr.append(lv)
		sc.city_levels = arr
	if c.options.has("rounds"):
		sc.rounds = int(c.options.rounds)
	sc.shape = str(c.options.get("shape", sc.shape))
	return sc

static func _by_np(v, np: int, def):
	if v == null:
		return def
	if v is Dictionary:
		if v.has(str(np)):
			return v[str(np)]
		# nearest key
		var best = def
		var bd := 99
		for k in v:
			if str(k).is_valid_int() and abs(int(k) - np) < bd:
				bd = abs(int(k) - np)
				best = v[k]
		return best
	return v

static func _formula(v, np: int, def: int) -> int:
	v = _by_np(v, np, def)
	if v is int or v is float:
		return int(v)
	var sv := str(v).replace(" ", "")
	if sv.begins_with("players"):
		var rest := sv.substr(7)
		if rest == "":
			return np
		return np + int(rest)
	if sv.is_valid_int():
		return int(sv)
	return def

func _scenario_from_data(sc: Dictionary, d: Dictionary, np: int) -> void:
	sc.name_it = str(d.get("name_it", sc.name_it))
	sc.rounds = int(d.get("rounds", sc.rounds))
	if np == 1 and d.has("rounds_solo"):
		sc.rounds = int(d.rounds_solo)
	var mp = d.get("map", {})
	if mp is Dictionary and mp.has("shape"):
		var shp := str(_by_np(mp.shape, np, sc.shape))
		sc["cols"] = 5
		if shp.begins_with("open") and shp.length() > 4:
			sc["cols"] = int(shp.substr(4))
		sc.shape = "open" if shp.begins_with("open") else "wedge"
	var tl = d.get("tiles", {})
	if tl is Dictionary:
		sc.country = _formula(tl.get("country", null), np, int(sc.country))
		sc.core = _formula(tl.get("core_noncity", null), np, int(sc.core))
		sc.city = _formula(tl.get("city", null), np, int(sc.city))
		sc["country_order"] = str(tl.get("country_order", ""))
	var cl = d.get("city_levels", null)
	var levels: Array = []
	if cl is Dictionary:
		if cl.has("order"):
			var o = _by_np(cl.order, np, [])
			if o is Array:
				levels = o.duplicate()
		elif cl.has("all"):
			for i in maxi(1, int(sc.city)):
				levels.append(int(cl.all))
			if cl.has("last"):
				levels[levels.size() - 1] = int(_by_np(cl.last, np, cl.all))
	if levels.is_empty():
		levels = [1]
	sc.city_levels = levels
	if d.has("cities_enterable"):
		sc.cities_enterable = bool(d.cities_enterable)
	var dm = d.get("dummy", null)
	sc.dummy = (dm == "neutral") or (dm == "solo" and np == 1) or (dm == null and np == 1)
	var typ := str(d.get("type", ""))
	if typ.find("solit") >= 0:
		sc.mode = "solo"
	elif typ.find("coop") >= 0:
		sc.mode = "coop"
	else:
		sc.mode = "competitive" if np > 1 else "solo"
	sc.end = "city_revealed" if str(d.get("end", "")).find("rivela una città") >= 0 else "cities"
	sc["scoring"] = str(d.get("scoring", "standard"))
	sc["titles"] = bool(d.get("titles", np > 1)) and np > 1
	sc["score_extra"] = d.get("score_extra", {})
	sc.tactics_removed_solo = false
	sc.dummy_first = false
	sc["remove_one_tactic"] = false
	sc["dummy_no_final"] = false
	for sp in d.get("special", []):
		var ss := str(sp)
		var parts := ss.split(":")
		var val := int(parts[1]) if parts.size() > 1 and parts[1].is_valid_int() else 1
		match parts[0]:
			"fame_per_tile_revealed":
				sc.fame_per_tile = val
			"no_elite_units":
				sc.elite = false
			"start_fame":
				sc.start_fame = val
			"fame_bonus_per_track_line":
				sc["fame_line_bonus"] = val
			"start_rep":
				sc.start_rep = val
			"extra_source_die":
				sc.extra_die = val
			"extra_unit_offer":
				sc.extra_unit = val
			"tactics_removed_after_round":
				sc.tactics_removed_solo = true
			"tactics_dummy_first_random":
				sc.dummy_first = true
			"remove_one_player_tactic_per_round":
				sc.remove_one_tactic = true
			"dummy_no_final_turn":
				sc.dummy_no_final = true
			"remove_competitive_spells":
				sc["no_competitive_cards"] = true
	if np == 1 and sc.id == "first_recon":
		sc.tactics_removed_solo = true
		sc.mode = "solo"

func _setup_decks(sets: Array) -> void:
	var ids: Array = MKDB.cards.keys()
	ids.sort()
	var excl: Array = s.cfg.options.get("exclude_cards", [])
	for id in ids:
		var c: Dictionary = MKDB.cards[id]
		if not MKDB.set_ok(c, sets) or not MKDB.card_ok(id) or id in excl:
			continue
		if (not is_competitive() or s.scn.get("no_competitive_cards", false)) and (str(c.get("mode", "")) in ["competitive", "comp"] or c.get("interactive", false) == true):
			continue
		var key := ""
		match c.type:
			"aa":
				key = "aa"
			"spell":
				key = "spells"
			"artifact":
				key = "artifacts"
		if key == "":
			continue
		for n in maxi(1, int(c.copies)):
			s.decks[key].append(id)
	for k in ["aa", "spells", "artifacts"]:
		MKRng.shuffle(s, s.decks[k])
	var uids: Array = MKDB.units.keys()
	uids.sort()
	for id in uids:
		var u: Dictionary = MKDB.units[id]
		if not MKDB.set_ok(u, sets) or not MKDB.unit_ok(id):
			continue
		for n in maxi(1, int(u.copies)):
			s.decks["units_elite" if u.elite else "units_reg"].append(id)
	MKRng.shuffle(s, s.decks.units_reg)
	MKRng.shuffle(s, s.decks.units_elite)
	for n in 3:
		_refill_offer("aa")
		_refill_offer("spells")

func _refill_offer(kind: String) -> void:
	var deck: Array = s.decks[kind]
	if deck.is_empty():
		return
	s.offers[kind].push_front(deck.pop_front())

func _setup_enemies(sets: Array) -> void:
	var bags := {}
	var ids: Array = MKDB.enemies.keys()
	ids.sort()
	for id in ids:
		var e: Dictionary = MKDB.enemies[id]
		if not MKDB.set_ok(e, sets):
			continue
		var col: String = e.color
		if not bags.has(col):
			bags[col] = {"draw": [], "discard": []}
		for n in maxi(1, int(e.copies)):
			bags[col].draw.append(id)
	var rids: Array = MKDB.ruins.keys()
	rids.sort()
	bags["ruins"] = {"draw": [], "discard": []}
	for id in rids:
		var r: Dictionary = MKDB.ruins[id]
		if not MKDB.set_ok(r, sets):
			continue
		for n in maxi(1, int(r.get("copies", 1))):
			bags.ruins.draw.append(id)
	for k in bags:
		MKRng.shuffle(s, bags[k].draw)
	s.enemy_bags = bags

## Draw an enemy of a colour; returns eid or "" if none left.
func draw_enemy(color: String, face_up: bool, hexk: String = "") -> String:
	var bag: Dictionary = s.enemy_bags.get(color, {})
	if bag.is_empty():
		return ""
	if bag.draw.is_empty():
		bag.draw = bag.discard
		bag.discard = []
		MKRng.shuffle(s, bag.draw)
	if bag.draw.is_empty():
		return ""
	var t: String = bag.draw.pop_front()
	s.eid_seq = int(s.eid_seq) + 1
	var eid := "e%d" % s.eid_seq
	s.enemies[eid] = {"type": t, "color": color, "face_up": face_up, "hex": hexk}
	return eid

func discard_enemy(eid: String) -> void:
	var inst: Dictionary = s.enemies.get(eid, {})
	if inst.is_empty():
		return
	var bag: Dictionary = s.enemy_bags.get(inst.color, {})
	if not bag.is_empty():
		bag.discard.append(inst.type)
	var hk: String = inst.get("hex", "")
	if hk != "" and s.map.hex.has(hk):
		s.map.hex[hk].enemies.erase(eid)
	s.enemies.erase(eid)

func _setup_map(sc: Dictionary, sets: Array) -> void:
	var shape: String = sc.shape
	s.map.shape = shape
	var country: Array = []
	var core: Array = []
	var cities: Array = []
	var start_id := ""
	var tids: Array = MKDB.tiles.keys()
	tids.sort()
	for id in tids:
		var t: Dictionary = MKDB.tiles[id]
		if not MKDB.set_ok(t, sets):
			continue
		if not _tile_supported(t):
			continue
		match t.kind:
			"start":
				var want := "A" if shape == "wedge" else "B"
				var tsh := str(t.get("shape", ""))
				var is_a: bool = tsh in ["wedge", "A", "a"] or id.to_lower().ends_with("a") or id.to_lower().find("wedge") >= 0
				var is_b: bool = tsh in ["open", "B", "b"] or id.to_lower().ends_with("b") or id.to_lower().find("open") >= 0
				if (want == "A" and is_a) or (want == "B" and is_b) or start_id == "":
					if start_id == "" or (want == "A" and is_a) or (want == "B" and is_b):
						start_id = id
			"country":
				country.append(id)
			"core":
				if t.city != "":
					cities.append(id)
				else:
					core.append(id)
	MKRng.shuffle(s, country)
	MKRng.shuffle(s, core)
	MKRng.shuffle(s, cities)
	if sc.id == "first_recon":
		country.sort_custom(func(a, b): return int(MKDB.tiles[a].number) < int(MKDB.tiles[b].number))
	if cities.size() < int(sc.city):
		# not enough city tiles in the chosen sets: the objective counts only the cities that exist
		sc.city = cities.size()
	var n_c: int = mini(int(sc.country), country.size())
	var deck: Array = country.slice(0, n_c)
	var spare: Array = country.slice(n_c)
	var bottom: Array = core.slice(0, mini(int(sc.core), core.size())) + cities.slice(0, mini(int(sc.city), cities.size()))
	MKRng.shuffle(s, bottom)
	if sc.id == "first_recon":
		# city at the bottom
		var cs: Array = []
		var ns: Array = []
		for t in bottom:
			if MKDB.tiles[t].city != "":
				cs.append(t)
			else:
				ns.append(t)
		bottom = ns + cs
	deck.append_array(bottom)
	s.map.tile_deck = deck
	s.decks.tiles_spare = spare + core.slice(mini(int(sc.core), core.size()))
	if start_id == "":
		start_id = "_start"
		MKDB.tiles["_start"] = {"id": "_start", "kind": "start", "number": 0, "city": "", "set": "base", "hexes": {
			"center": {"t": "plains", "site": "portal", "rampage": "", "city": "", "mine": ""},
			"0": {"t": "ocean", "site": "", "rampage": "", "city": "", "mine": ""}, "60": {"t": "ocean", "site": "", "rampage": "", "city": "", "mine": ""},
			"120": {"t": "ocean" if shape == "wedge" else "plains", "site": "", "rampage": "", "city": "", "mine": ""},
			"180": {"t": "plains", "site": "", "rampage": "", "city": "", "mine": ""}, "240": {"t": "forest", "site": "", "rampage": "", "city": "", "mine": ""},
			"300": {"t": "plains", "site": "", "rampage": "", "city": "", "mine": ""}}}
	place_tile(start_id, "0,0", -1)
	var portal := "0,0"
	for k in s.map.hex:
		if s.map.hex[k].site == "portal":
			portal = k
	for pl in s.players:
		pl.pos = portal
	s.map["portal"] = portal
	# initial revealed tiles
	var init_slots: Array = [MKHex.key(MKHex.MACRO[0]), MKHex.key(MKHex.MACRO[1])]
	if shape == "open":
		init_slots.append(MKHex.key(MKHex.MACRO[2]))
	for sl in init_slots:
		if s.map.tile_deck.is_empty():
			break
		place_tile(s.map.tile_deck.pop_front(), sl, -1)

func _tile_supported(t: Dictionary) -> bool:
	# exclude tiles with sites the engine does not know (expansions)
	var known := ["", "village", "monastery", "keep", "mage_tower", "dungeon", "tomb", "monster_den", "spawning_grounds",
		"ruins", "glade", "mine", "city", "portal", "camp", "maze", "labyrinth"]
	for dk in t.hexes:
		if not str(t.hexes[dk].site) in known:
			return false
	if t.hexes.size() < 7:
		return false
	return true

## Place a tile at a slot and populate its sites.
func place_tile(tid: String, slot: String, by: int) -> void:
	var t: Dictionary = MKDB.tiles.get(tid, {})
	if t.is_empty():
		return
	s.map.tiles.append({"id": tid, "slot": slot})
	var c := MKHex.parse(slot)
	var placed_hexes: Array = []
	for dk in t.hexes:
		var hd: Dictionary = t.hexes[dk]
		var k := MKHex.key(c + MKHex.TILE_KEYS.get(dk, Vector2i.ZERO))
		var h := {"t": hd.t, "site": hd.site, "tile": tid, "mine": hd.get("mine", ""), "enemies": [], "owner": -1,
			"conquered": false, "burned": false, "ruins": "", "rampage": hd.get("rampage", "") != "", "revealed": true}
		if hd.has("mines"):
			h["mines"] = hd.mines
		if hd.site == "city":
			h["city"] = {"color": hd.get("city", t.get("city", "")), "level": 1, "shields": [], "leader": -1}
		s.map.hex[k] = h
		placed_hexes.append(k)
	# walls between hexes of this tile (Lost Legion): s.map.walls = {"k1|k2": true} (keys sorted)
	var tw: Dictionary = t.get("walls", {})
	for dk in tw:
		var k1 := MKHex.key(c + MKHex.TILE_KEYS.get(dk, Vector2i.ZERO))
		for dk2 in tw[dk]:
			var k2 := MKHex.key(c + MKHex.TILE_KEYS.get(dk2, Vector2i.ZERO))
			if not s.map.has("walls"):
				s.map["walls"] = {}
			s.map.walls[wall_key(k1, k2)] = true
	if t.kind == "core":
		s.core_revealed = true
	# populate
	for k in placed_hexes:
		var h: Dictionary = s.map.hex[k]
		var hd2: Dictionary = t.hexes[_dk_of(k, c)]
		if hd2.get("rampage", "") != "":
			var eid := draw_enemy(hd2.rampage, true, k)
			if eid != "":
				h.enemies.append(eid)
		match h.site:
			"keep":
				_garrison(k, "gray")
			"mage_tower":
				_garrison(k, "violet")
			"monastery":
				if not s.decks.aa.is_empty():
					s.offers.monastery.append(s.decks.aa.pop_front())
			"ruins":
				var bag: Dictionary = s.enemy_bags.get("ruins", {})
				if not bag.is_empty():
					if bag.draw.is_empty():
						bag.draw = bag.discard
						bag.discard = []
						MKRng.shuffle(s, bag.draw)
					if not bag.draw.is_empty():
						h.ruins = bag.draw.pop_front()
						h["ruins_face_up"] = s.day
			"city":
				_setup_city(k)
	var lbl := "Rivelata la tessera %s" % _tile_label(t)
	add_log("reveal", lbl, {"tile": tid, "slot": slot, "p": by})
	if by >= 0:
		_reveal_adjacent(by)

func _dk_of(k: String, c: Vector2i) -> String:
	var d := MKHex.parse(k) - c
	for dk in MKHex.TILE_KEYS:
		if MKHex.TILE_KEYS[dk] == d:
			return dk
	return "center"

func _tile_label(t: Dictionary) -> String:
	if t.kind == "start":
		return "iniziale"
	if t.kind == "core":
		return ("città %s" % MKMana.color_it(t.city)) if t.city != "" else "centrale %d" % int(t.number)
	return "campagna %d" % int(t.number)

func _garrison(k: String, color: String) -> void:
	var eid := draw_enemy(color, false, k)
	if eid != "":
		s.map.hex[k].enemies.append(eid)

func _setup_city(k: String) -> void:
	var h: Dictionary = s.map.hex[k]
	var col: String = h.city.color
	var idx: int = int(s.cities_revealed)
	s.cities_revealed = idx + 1
	var levels: Array = s.scn.city_levels
	var lv: int = int(levels[mini(idx, levels.size() - 1)]) if not levels.is_empty() else 5
	h.city.level = lv
	var cd: Dictionary = MKDB.cities.get(col, {})
	if cd.is_empty():
		for cid in MKDB.cities:
			if MKDB.cities[cid].get("color", "") == col:
				cd = MKDB.cities[cid]
	var colors: Array = _city_garrison(cd, lv)
	for gc in colors:
		var eid := draw_enemy(gc, false, k)
		if eid != "":
			h.enemies.append(eid)
	add_log("city", "Rivelata la città %s di livello %d" % [MKMana.color_it(col), lv], {"hex": k, "color": col, "level": lv})

func _city_garrison(cd: Dictionary, lv: int) -> Array:
	for key in ["garrison", "levels", "garrisons"]:
		var g = cd.get(key, null)
		if g is Dictionary and g.has(str(lv)):
			var x = g[str(lv)]
			if x is Dictionary:
				x = x.get("enemies", x.get("garrison", []))
			return _colors_list(x)
		if g is Array and lv - 1 < g.size() and lv >= 1:
			var y = g[lv - 1]
			if y is Dictionary:
				y = y.get("enemies", y.get("garrison", []))
			return _colors_list(y)
	# default (rough approximation of the city miniature bases)
	var table := {1: ["gray", "white"], 2: ["gray", "white"], 3: ["gray", "gray", "white"], 4: ["gray", "white", "white"],
		5: ["gray", "violet", "white", "white"], 6: ["gray", "violet", "white", "white"], 7: ["gray", "violet", "white", "white", "white"],
		8: ["violet", "violet", "white", "white", "white"], 9: ["gray", "violet", "violet", "white", "white", "white"],
		10: ["violet", "violet", "white", "white", "white", "white"], 11: ["violet", "violet", "violet", "white", "white", "white", "white"]}
	return table.get(clampi(lv, 1, 11), ["white"])

func _colors_list(x) -> Array:
	var out: Array = []
	if x is Array:
		for c in x:
			out.append(MKDB._color(c))
	elif x is Dictionary:
		for c in x:
			for n in int(x[c]):
				out.append(MKDB._color(c))
	return out

# ================================================================ rounds
func _start_round(first: bool) -> void:
	s.round = int(s.round) + 1
	if not first:
		s.day = not s.day
		_refresh_offers()
	s.announced_by = -1
	s.final_turns = {}
	_new_unit_offer()
	_roll_source()
	MKSpecials.on_round_start(self)
	for i in s.players.size():
		var pl: Dictionary = P(i)
		for u in pl.units:
			u.ready = true
		for sk in pl.skills:
			sk.used_round = false
			sk.used_turn = false
		pl.tactic = ""
		pl.tactic_used = false
		pl.finished = false
		pl.stolen_die = ""
		if not first:
			var all: Array = pl.deck + pl.discard + pl.hand + pl.play
			pl.deck = all
			pl.discard = []
			pl.hand = []
			pl.play = []
			MKRng.shuffle(s, pl.deck)
			draw(i, hand_limit_now(i) + int(pl.pending_hand_bonus), true)
			pl.pending_hand_bonus = 0
	if s.dummy != null and not first:
		s.dummy.deck.append_array(s.dummy.discard)
		s.dummy.discard = []
		MKRng.shuffle(s, s.dummy.deck)
	# ruins face up during the day
	if s.day:
		for k in s.map.hex:
			var h: Dictionary = s.map.hex[k]
			if h.get("ruins", "") != "":
				h["ruins_face_up"] = true
	# tactics
	var avail: Array = []
	var tids: Array = MKDB.tactics.keys()
	tids.sort_custom(func(a, b): return int(MKDB.tactics[a].number) < int(MKDB.tactics[b].number))
	for t in tids:
		if bool(MKDB.tactics[t].day) == s.day and not t in s.tactics_removed:
			avail.append(t)
	if avail.is_empty():
		for n in 6:
			avail.append(("d%d" if s.day else "n%d") % (n + 1))
	s.tactics_avail = avail
	s.phase = "tactics"
	add_log("round", "Inizia il round %d (%s)" % [s.round, "Giorno" if s.day else "Notte"], {"round": s.round, "day": s.day})
	# tactic choice order: lowest fame first; ties: later in old turn order first
	var old: Array = s.turn_order.duplicate()
	var order: Array = []
	for i in s.players.size():
		order.append(i)
	order.sort_custom(func(a, b):
		var fa := int(s.players[a].fame)
		var fb := int(s.players[b].fame)
		if fa != fb:
			return fa < fb
		var ia := old.find(a)
		var ib := old.find(b)
		if ia < 0 or ib < 0:
			return a > b
		return ia > ib)
	if s.scn.mode == "solo":
		order = [0]
	s.tactic_pick = order
	if s.dummy != null and s.scn.get("dummy_first", false):
		_dummy_pick_tactic()
	_next_tactic_pick()

func _dummy_pick_tactic() -> void:
	if s.dummy == null or s.tactics_avail.is_empty():
		return
	var t: String = MKRng.pick(s, s.tactics_avail)
	s.tactics_avail.erase(t)
	s.dummy.tactic = t
	add_log("tactic", "Il Giocatore Neutrale prende la tattica %s" % tactic_name(t), {"p": DUMMY, "tactic": t})

func tactic_name(t: String) -> String:
	var td: Dictionary = MKDB.tactics.get(t, {})
	return str(td.get("name_it", td.get("name_en", t)))

func tactic_number(t: String) -> int:
	var td: Dictionary = MKDB.tactics.get(t, {})
	if td.has("number"):
		return int(td.number)
	return int(t.substr(1)) if t.length() > 1 else 0

func tactic_key(t: String) -> String:
	# "d1".."d6" / "n1".."n6"
	var td: Dictionary = MKDB.tactics.get(t, {})
	if td.is_empty():
		return t
	return ("d%d" if bool(td.day) else "n%d") % int(td.number)

func _next_tactic_pick() -> void:
	if s.pending != null:
		return
	while not s.tactic_pick.is_empty():
		var p: int = s.tactic_pick[0]
		if P(p).tactic == "":
			s.active = p
			return
		s.tactic_pick.pop_front()
	# everyone has chosen
	if s.dummy != null and s.dummy.tactic == "":
		_dummy_pick_tactic()
	if s.dummy != null and s.dummy.tactic == "" and s.tactics_avail.is_empty():
		pass
	_begin_turns()

func _begin_turns() -> void:
	var order: Array = []
	for i in s.players.size():
		order.append(i)
	if s.dummy != null:
		order.append(DUMMY)
	order.sort_custom(func(a, b): return _tactic_num_of(a) < _tactic_num_of(b))
	s.turn_order = order
	s.order_pos = 0
	s.phase = "turn"
	var names: Array = []
	for i in order:
		names.append(pname(i))
	add_log("order", "Ordine di turno: " + ", ".join(names), {"order": order})
	_start_turn_at(0)

func _tactic_num_of(i: int) -> int:
	if i == DUMMY:
		return tactic_number(s.dummy.tactic) if s.dummy.tactic != "" else 99
	return tactic_number(P(i).tactic) if P(i).tactic != "" else 99

func _fresh_turn(p: int) -> Dictionary:
	return {"player": p, "stage": "move", "moved": false, "acted": false, "rested": false, "started": false,
		"pool": {"move": 0, "influence": 0, "heal": 0, "attack": {}, "block": {}}, "mods": [],
		"dice_allowed": 1, "dice_taken": 0, "dice_used_colors": [], "played": [], "rewards": [], "rep_applied": false,
		"interacted": false, "prev": "", "path": [], "ending": false, "end_step": 0, "plundered": false,
		"destroy": [], "set_aside": [], "explored": 0, "combats": 0, "discarded": 0, "site_used": false, "extra_turn": false,
		"skip_draw": false, "fixed_dice": []}

func _start_turn_at(pos: int) -> void:
	# find next player who should play; handles the dummy automatically
	var guard := 0
	while guard < 60:
		guard += 1
		if s.phase != "turn" or s.turn_order.is_empty():
			return
		var final_mode: bool = s.announced_by != -1 or s.game_end_pending
		if final_mode and _final_done():
			_end_round()
			return
		pos = pos % s.turn_order.size()
		s.order_pos = pos
		var who: int = s.turn_order[pos]
		if final_mode and not s.final_turns.has(str(who)):
			pos += 1
			continue
		if who == DUMMY:
			_dummy_turn()
			if final_mode:
				s.final_turns.erase(str(DUMMY))
			pos += 1
			continue
		_start_player_turn(who)
		return
	_end_round()

func _final_done() -> bool:
	return s.final_turns.is_empty()

func _start_player_turn(p: int) -> void:
	s.active = p
	s.turn = _fresh_turn(p)
	var pl: Dictionary = P(p)
	s.turn.prev = pl.pos
	s.turn.path = [pl.pos]
	pl.knocked_out = false
	pl.wounds_this_combat = 0
	pl.turns = int(pl.turns) + 1
	for sk in pl.skills:
		sk.used_turn = false
		if sk.get("active_until_turn", false):
			sk.active_until_turn = false
	if MKPvP.skip_turn(self, p):
		_finish_turn_now()
		return
	add_log("turn", "Turno di %s" % pname(p), {"p": p, "round": s.round})
	# skip turn if nothing left and round end already announced
	if pl.deck.is_empty() and pl.hand.is_empty():
		if s.announced_by == -1 and not s.game_end_pending:
			_announce(p)
			return
		add_log("turn", "%s non ha più carte e salta il turno" % pname(p), {"p": p})
		_finish_turn_now()
		return
	MKSpecials.on_turn_start(self, p)
	# glade: mana token at start of turn
	var h := hex(pl.pos)
	if h.get("site", "") == "glade":
		gain_token(p, "gold" if s.day else "black")
		add_log("site", "Radura magica: gettone mana %s" % ("oro" if s.day else "nero"), {"p": p})
	# extra die (solo conquest) / tactic effects
	if int(s.scn.get("extra_die", 0)) > 0:
		pass

func _announce(p: int) -> void:
	s.announced_by = p
	s.final_turns = {}
	for i in s.turn_order:
		if i != p:
			s.final_turns[str(i)] = true
	add_log("announce", "%s annuncia la fine del round" % pname(p), {"p": p})
	if p != DUMMY:
		_finish_turn_now()

func _finish_turn_now() -> void:
	# end of turn without the usual sequence (announce / skip)
	var p: int = s.turn.get("player", -1)
	if p >= 0 and p != DUMMY:
		s.final_turns.erase(str(p))
	_advance()

func _advance() -> void:
	if s.phase != "turn":
		return
	if (s.announced_by != -1 or s.game_end_pending) and _final_done():
		_end_round()
		return
	var p: int = s.turn.get("player", -1)
	if s.turn.get("extra_turn", false) and p >= 0:
		add_log("turn", "%s gioca un altro turno (Il Momento Giusto)" % pname(p), {"p": p})
		_start_player_turn(p)
		return
	_start_turn_at(int(s.order_pos) + 1)

func _dummy_turn() -> void:
	var d: Dictionary = s.dummy
	if d.deck.is_empty():
		if s.announced_by == -1 and not s.game_end_pending:
			s.turn = _fresh_turn(DUMMY)
			_announce(DUMMY)
		return
	var n := 3
	var flipped: Array = []
	for i in n:
		if d.deck.is_empty():
			break
		var iid: String = d.deck.pop_front()
		d.discard.append(iid)
		flipped.append(iid)
	if not flipped.is_empty():
		var last_col: String = str(card(flipped[-1]).get("color", ""))
		var extra := int(d.crystals.get(last_col, 0))
		for i in extra:
			if d.deck.is_empty():
				break
			var iid2: String = d.deck.pop_front()
			d.discard.append(iid2)
			flipped.append(iid2)
	add_log("dummy", "Il Giocatore Neutrale gira %d carte (ne restano %d)" % [flipped.size(), d.deck.size()], {"p": DUMMY, "n": flipped.size()})

func _end_round() -> void:
	add_log("round_end", "Fine del round %d" % s.round, {"round": s.round})
	# tactics removal (solo / coop)
	if s.scn.get("tactics_removed_solo", false):
		for pl in s.players:
			if pl.tactic != "":
				s.tactics_removed.append(pl.tactic)
		if s.dummy != null and s.dummy.tactic != "":
			s.tactics_removed.append(s.dummy.tactic)
	elif s.scn.get("remove_one_tactic", false):
		for pl in s.players:
			if pl.tactic != "":
				s.tactics_removed.append(pl.tactic)
				break
	if s.dummy != null:
		s.dummy.tactic = ""
	for pl in s.players:
		# return Sparing Power cards to deck (they will be shuffled)
		if not pl.tactic_store.is_empty():
			pl.deck.append_array(pl.tactic_store)
			pl.tactic_store = []
	if _game_over_check():
		_game_over()
		return
	_start_round(false)

func _game_over_check() -> bool:
	if s.game_end_pending:
		return true
	if int(s.round) >= int(s.scn.rounds):
		return true
	return false

func _refresh_offers() -> void:
	# AA: lowest card (last) goes to the bottom of the deck (or to the dummy)
	for kind in ["aa", "spells"]:
		var off: Array = s.offers[kind]
		if not off.is_empty():
			var low: String = off.pop_back()
			if s.dummy != null and kind == "aa":
				s.dummy.deck.append(new_iid(low))
				add_log("dummy", "Il Giocatore Neutrale prende %s" % str(MKDB.card(low).get("name_it", low)), {"p": DUMMY})
			else:
				s.decks[kind].append(low)
				if s.dummy != null and kind == "spells":
					var col := str(MKDB.card(low).get("color", ""))
					if col in MKMana.BASIC:
						s.dummy.crystals[col] = int(s.dummy.crystals.get(col, 0)) + 1
		_refill_offer(kind)
		while s.offers[kind].size() < 3 and not s.decks[kind].is_empty():
			_refill_offer(kind)
	# common skill offer: dummy's skill (solo) handled at level up

func _new_unit_offer() -> void:
	for u in s.offers.units:
		var ud: Dictionary = MKDB.units.get(u, {})
		s.decks["units_elite" if ud.get("elite", false) else "units_reg"].append(u)
	s.offers.units = []
	for a in s.offers.monastery:
		s.decks.aa.append(a)
	s.offers.monastery = []
	var n: int = s.players.size() + 2 + int(s.scn.get("extra_unit", 0))
	var elite_ok: bool = s.core_revealed and s.scn.get("elite", true)
	for i in n:
		var from := "units_elite" if elite_ok and i % 2 == 0 else "units_reg"
		if s.decks[from].is_empty():
			from = "units_reg" if from == "units_elite" else ("units_elite" if elite_ok else "")
		if from == "" or s.decks[from].is_empty():
			continue
		s.offers.units.append(s.decks[from].pop_front())
	# monastery AA
	for k in s.map.hex:
		var h: Dictionary = s.map.hex[k]
		if h.site == "monastery" and not h.burned and not s.decks.aa.is_empty():
			s.offers.monastery.append(s.decks.aa.pop_front())

func _roll_source() -> void:
	var n: int = s.players.size() + 2 + int(s.scn.get("extra_die", 0))
	s.source = []
	for i in n:
		s.source.append({"color": DIE_COLORS[MKRng.rand_int(s, 6)], "taken_by": -1})
	_fix_source()

func _fix_source() -> void:
	var guard := 0
	while guard < 100:
		guard += 1
		var basic := 0
		for d in s.source:
			if d.color in MKMana.BASIC:
				basic += 1
		if basic * 2 >= s.source.size():
			return
		for d in s.source:
			if not d.color in MKMana.BASIC and int(d.taken_by) == -1:
				d.color = DIE_COLORS[MKRng.rand_int(s, 6)]

# ================================================================ resources
func draw(p: int, n: int, silent: bool = false) -> int:
	var pl: Dictionary = P(p)
	var got := 0
	for i in n:
		if pl.deck.is_empty():
			break
		pl.hand.append(pl.deck.pop_front())
		got += 1
	if not silent and got > 0:
		add_log("draw", "%s pesca %d cart%s" % [pname(p), got, "a" if got == 1 else "e"], {"p": p, "n": got})
	return got

func gain_fame(p: int, n: int) -> void:
	if n == 0:
		return
	var pl: Dictionary = P(p)
	var before := int(pl.fame)
	pl.fame = maxi(0, before + n)
	# solo conquest: +1 fame each time a level line is crossed
	if int(s.scn.get("fame_line_bonus", 0)) > 0 and n > 0:
		if level_of(int(pl.fame)) > level_of(before):
			pl.fame = int(pl.fame) + int(s.scn.fame_line_bonus) * (level_of(int(pl.fame)) - level_of(before))
	add_log("fame", "%s %+d Fama (totale %d)" % [pname(p), int(pl.fame) - before, pl.fame], {"p": p, "n": int(pl.fame) - before, "total": pl.fame})

func change_rep(p: int, n: int) -> void:
	if n == 0:
		return
	var pl: Dictionary = P(p)
	var before := int(pl.rep)
	pl.rep = clampi(before + n, -7, 7)
	if int(pl.rep) != before:
		add_log("rep", "%s Reputazione %+d (ora %d)" % [pname(p), int(pl.rep) - before, pl.rep], {"p": p, "n": int(pl.rep) - before, "total": pl.rep})

func rep_bonus(p: int) -> int:
	if flag(p, "ignore_reputation"):
		return 0
	return REP_BONUS[clampi(int(P(p).rep) + 7, 0, 14)]

func explore_cost(p: int) -> int:
	var c := 2 - int(P(p).get("explore_discount", 0))
	for m in mods_named("explore_discount"):
		c -= int(m.get("n", 1))
	return maxi(0, c)

func gain_token(p: int, c: String) -> void:
	P(p).tokens.append(c)
	add_log("mana", "%s ottiene un gettone mana %s" % [pname(p), MKMana.color_it(c)], {"p": p, "color": c, "what": "token"})

func gain_crystal(p: int, c: String) -> void:
	if not c in MKMana.BASIC:
		return
	var pl: Dictionary = P(p)
	if int(pl.crystals[c]) >= 3:
		gain_token(p, c)
		return
	pl.crystals[c] = int(pl.crystals[c]) + 1
	add_log("mana", "%s ottiene un cristallo %s" % [pname(p), MKMana.color_it(c)], {"p": p, "color": c, "what": "crystal"})

func add_wound(p: int, to_hand: bool = true) -> String:
	var iid := new_iid("wound")
	if to_hand:
		P(p).hand.append(iid)
	else:
		P(p).discard.append(iid)
	s.decks.wounds = int(s.decks.wounds) - 1
	MKSpecials.on_wound(self, p, iid, to_hand)
	return iid

func remove_unit(p: int, u) -> void:
	if u == null:
		return
	var pl: Dictionary = P(p)
	pl.units.erase(u)
	var bn: Dictionary = pl.get("banners", {})
	if bn.has(str(u.uid)):
		pl.discard.append(bn[str(u.uid)])
		bn.erase(str(u.uid))

## Move a hero directly (special movement). Does not cost Move points.
func teleport(p: int, to: String, no_provoke: bool, assault: bool = false) -> void:
	var pl: Dictionary = P(p)
	var from: String = pl.pos
	pl.pos = to
	s.turn.moved = true
	s.turn.started = true
	s.turn.prev = from
	s.turn.path.append(to)
	add_log("move", "%s si sposta in %s" % [pname(p), _hex_label(to)], {"p": p, "from": from, "to": to, "cost": 0})
	_reveal_adjacent(p)
	var h := hex(to)
	if h.site in FORTIFIED_SITES and not _is_safe_fortified(p, to):
		var defenders: Array = []
		if h.site == "keep" and int(h.owner) >= 0 and int(h.owner) != p and h.enemies.is_empty():
			var eid := draw_enemy("gray", true, to)
			if eid != "":
				h.enemies.append(eid)
				s.enemies[eid]["half_fame"] = true
		for eid in h.enemies:
			defenders.append(eid)
		change_rep(p, -1)
		add_log("assault", "%s assalta %s" % [pname(p), _hex_label(to)], {"p": p, "hex": to})
		MKCombat.start(self, defenders, {"site": to, "kind": "assault", "assault": true, "defenders": defenders, "retreat": from})

func discard_from_hand(p: int, iid: String) -> void:
	var pl: Dictionary = P(p)
	if pl.hand.has(iid):
		pl.hand.erase(iid)
		pl.discard.append(iid)
		s.turn.discarded = int(s.turn.get("discarded", 0)) + 1
		add_log("discard", "%s scarta %s" % [pname(p), card_name(iid)], {"p": p, "card": iid})

## Throw away (remove from game). Wounds go back to the pile.
func throw_away(p: int, iid: String) -> void:
	var pl: Dictionary = P(p)
	for zone in ["hand", "discard", "play", "deck"]:
		if pl[zone].has(iid):
			pl[zone].erase(iid)
			break
	if is_wound(iid):
		s.decks.wounds = int(s.decks.wounds) + 1
	else:
		pl.removed.append(iid)

func base_hand_limit(p: int) -> int:
	return int(P(p).hand_limit)

func hand_limit_now(p: int) -> int:
	var pl: Dictionary = P(p)
	var lim := int(pl.hand_limit)
	var keep_bonus := 0
	var city_bonus := 0
	var my_keeps := 0
	for k in s.map.hex:
		var h: Dictionary = s.map.hex[k]
		if h.site == "keep" and int(h.owner) == p:
			my_keeps += 1
	var near: Array = [pl.pos] + MKHex.neighbors(pl.pos)
	for k in near:
		var h2 := hex(k)
		if h2.is_empty():
			continue
		if h2.site == "keep" and int(h2.owner) == p:
			keep_bonus = my_keeps
		if h2.site == "city" and h2.conquered and h2.has("city"):
			if int(h2.city.get("leader", -1)) == p:
				city_bonus = maxi(city_bonus, 2)
			elif h2.city.get("shields", []).has(p):
				city_bonus = maxi(city_bonus, 1)
	return lim + maxi(keep_bonus, city_bonus)

func armor_of(p: int) -> int:
	var a := int(P(p).armor)
	for m in mods_named("armor"):
		a += int(m.get("n", 0))
	return maxi(1, a)

func command_free(p: int) -> int:
	return int(P(p).command) - P(p).units.size() + MKSpecialsExp.command_bonus(self, p)

## Bonus for attacks generated by effects (specials can add mods).
func attack_bonus(p: int, kind: String, elem: String, ctx: Dictionary) -> int:
	var b := 0
	for m in mods_named("attack_bonus"):
		if m.has("except_uid") and int(ctx.get("uid", -2)) == int(m.except_uid):
			continue
		if m.has("only_uid") and int(ctx.get("uid", -2)) != int(m.only_uid):
			continue
		if (m.get("kind", "") == "" or m.kind == kind) and (m.get("elem", "") == "" or m.elem == elem):
			if m.get("src_kind", "") == "" or m.src_kind == ctx.get("kind", ""):
				b += int(m.get("n", 0))
	return b

func block_bonus(p: int, elem: String, ctx: Dictionary) -> int:
	var b := 0
	for m in mods_named("block_bonus"):
		if m.get("elem", "") == "" or m.elem == elem:
			if m.get("src_kind", "") == "" or m.src_kind == ctx.get("kind", ""):
				b += int(m.get("n", 0))
	return b

func side_value(p: int, side: String, iid: String = "", consume: bool = false) -> int:
	var v := 1
	for m in mods_named("side_value"):
		var sides: Array = m.get("sides", ["move", "influence", "attack", "block"])
		if side in sides:
			v = maxi(v, int(m.get("n", 1)))
	return MKSpecials.side_value(self, p, side, iid, v, consume)

func auto_heal(p: int) -> void:
	# if no wounded units, heal points go straight to wounds in hand
	var pl: Dictionary = P(p)
	var has_wu := false
	for u in pl.units:
		if u.wounded:
			has_wu = true
	if has_wu:
		return
	var pool: Dictionary = s.turn.pool
	while int(pool.heal) > 0:
		var w := ""
		for iid in pl.hand:
			if is_wound(iid):
				w = iid
				break
		if w == "":
			break
		pool.heal = int(pool.heal) - 1
		throw_away(p, w)
		add_log("heal", "%s guarisce una ferita" % pname(p), {"p": p, "what": "hand"})
		MKSpecials.on_heal(self, p)

# ================================================================ movement
func can_still_move(p: int) -> bool:
	var t: Dictionary = s.turn
	return s.phase == "turn" and int(t.player) == p and not t.acted and not t.rested and s.combat == null and not t.ending

func terrain_cost(t: String, hk: String = "") -> int:
	var base := 999
	var tab: Dictionary = COST_DAY if s.day else COST_NIGHT
	if tab.has(t):
		base = int(tab[t])
	var h := hex(hk) if hk != "" else {}
	if not h.is_empty() and h.site == "city":
		base = 2
	var cost := base
	var mods: Array = mods_named("terrain")
	# 1) explicit costs (an impassable terrain may become passable); "all" never affects lake/mountain
	for m in mods:
		var mp: Dictionary = m.get("map", {})
		if mp.has(t) and (mp[t] is int or mp[t] is float):
			cost = int(mp[t])
		elif mp.has("all") and (mp.all is int or mp.all is float) and base < 999:
			cost = mini(cost, int(mp.all))
	if cost >= 999:
		return 999
	# 2) relative changes and caps
	for m in mods:
		var mp2: Dictionary = m.get("map", {})
		for key in [t, "all"]:
			if not mp2.has(key) or not (mp2[key] is String):
				continue
			if key == "all" and base >= 999:
				continue
			var sv: String = mp2[key]
			if sv.begins_with("<="):
				cost = mini(cost, int(sv.substr(2)))
			elif sv.begins_with("-") or sv.begins_with("+"):
				cost = maxi(int(mp2.get("min", 0)), cost + int(sv))
	return maxi(0, cost)

## Move cost of entering hk; with `from` (adjacent hex) a wall between the two adds 1
## (Lost Legion: terrain discounts cannot remove the wall cost).
func move_cost(hk: String, from: String = "") -> int:
	var h := hex(hk)
	if h.is_empty():
		return 999
	var c := terrain_cost(h.t, hk)
	if c < 999:
		c = MKSpecialsExp.space_cost(self, hk, h.t, c)
	if c < 999 and from != "" and has_wall(from, hk):
		c += 1
	return c

static func wall_key(a: String, b: String) -> String:
	return a + "|" + b if a < b else b + "|" + a

## Is there a wall between two adjacent hexes?
func has_wall(a: String, b: String) -> bool:
	var w = s.map.get("walls", null)
	if w == null or not (w is Dictionary) or w.is_empty():
		return false
	return w.has(wall_key(a, b))

## Rampaging enemies on hex `ek` attack a hero moving into `to` only if adjacent and not behind a wall.
func rampage_threatens(ek: String, to: String) -> bool:
	return MKHex.adjacent(ek, to) and not has_wall(ek, to)

func _hex_blocked(p: int, hk: String) -> String:
	var h := hex(hk)
	if h.is_empty():
		return "Esagono non esplorato"
	if h.rampage and not h.enemies.is_empty():
		return "Non puoi entrare in uno spazio con nemici scatenati"
	if h.site == "city" and not s.scn.get("cities_enterable", true):
		return "In questo scenario non si può entrare nelle città"
	return ""

func _check_move(p: int, to: String) -> String:
	if not can_still_move(p):
		return "Non puoi più muoverti in questo turno"
	if wounds_only_lock(p):
		return "Hai solo Ferite in mano: devi riposare"
	var pl: Dictionary = P(p)
	if not MKHex.adjacent(pl.pos, to) and not (flag(p, "space_bending") and MKHex.distance(pl.pos, to) == 2):
		return "Puoi muovere solo in uno spazio adiacente"
	var b := _hex_blocked(p, to)
	if b != "":
		return b
	var c := move_cost(to, pl.pos if MKHex.adjacent(pl.pos, to) else "")
	if c >= 999:
		return "Terreno invalicabile"
	if c > int(s.turn.pool.move):
		return "Punti Movimento insufficienti (servono %d)" % c
	return MKPvP.move_block(self, p, to)

func _do_move(p: int, to: String) -> void:
	var pl: Dictionary = P(p)
	var from: String = pl.pos
	var c := move_cost(to, from if MKHex.adjacent(from, to) else "")
	MKSpecialsExp.on_move_cost(self, p, to)
	s.turn.pool.move = int(s.turn.pool.move) - c
	s.turn.prev = from
	pl.pos = to
	s.turn.moved = true
	s.turn.started = true
	s.turn.path.append(to)
	var h := hex(to)
	add_log("move", "%s si muove in %s (costo %d)" % [pname(p), _hex_label(to), c], {"p": p, "from": from, "to": to, "cost": c})
	_reveal_adjacent(p)
	if h.get("ruins", "") != "" and not h.get("ruins_face_up", true):
		h["ruins_face_up"] = true
		add_log("reveal_ruins", "Rovine rivelate", {"hex": to, "ruins": h.ruins})
	# provoked rampaging enemies
	var provoked: Array = []
	var no_prov: bool = flag(p, "no_provoke")
	for nk in ([] if no_prov else MKHex.neighbors(from)):
		if nk == to:
			continue
		var nh := hex(nk)
		if nh.is_empty() or not nh.rampage or nh.enemies.is_empty():
			continue
		if rampage_threatens(nk, to):
			for eid in nh.enemies:
				provoked.append(eid)
	var assault := false
	var defenders: Array = []
	if provoked.is_empty() and MKPvP.keep_attack(self, p, to):
		return
	if h.site in FORTIFIED_SITES and not _is_safe_fortified(p, to):
		assault = true
		if h.site == "keep" and int(h.owner) >= 0 and int(h.owner) != p and h.enemies.is_empty():
			var eid := draw_enemy("gray", true, to)
			if eid != "":
				h.enemies.append(eid)
				s.enemies[eid]["half_fame"] = true
		for eid in h.enemies:
			defenders.append(eid)
	if assault or not provoked.is_empty():
		if assault:
			change_rep(p, -1)
			add_log("assault", "%s assalta %s" % [pname(p), _hex_label(to)], {"p": p, "hex": to})
		if not provoked.is_empty():
			add_log("provoke", "%s provoca i nemici scatenati" % pname(p), {"p": p, "enemies": provoked})
		var opts := {"site": to if assault else "", "kind": "assault" if assault else "provoke", "assault": assault,
			"defenders": defenders, "retreat": from}
		if assault and has_wall(from, to):
			opts["wall"] = true
		MKCombat.start(self, defenders + provoked, opts)
	else:
		MKSpecialsExp.after_move(self, p, to)

func _is_safe_fortified(p: int, hk: String) -> bool:
	var h := hex(hk)
	match h.site:
		"keep":
			return int(h.owner) == p or (h.conquered and int(h.owner) == -1) or (not is_competitive() and h.conquered)
		"mage_tower", "city":
			return h.conquered
	return true

func _hex_label(k: String) -> String:
	var h := hex(k)
	if h.is_empty():
		return k
	var site: String = h.get("site", "")
	if site != "" and site != "mine":
		return str(SITE_IT.get(site, site))
	return str(MKEffects.TERR_IT.get(h.t, h.t))

func _reveal_adjacent(p: int) -> void:
	var pl: Dictionary = P(p)
	for nk in [pl.pos] + MKHex.neighbors(pl.pos):
		var h := hex(nk)
		if h.is_empty():
			continue
		if h.site == "city" or (s.day and h.site in ["keep", "mage_tower"]):
			for eid in h.enemies:
				if not s.enemies[eid].face_up:
					s.enemies[eid].face_up = true
					add_log("reveal_enemy", "Rivelato: %s (%s)" % [enemy_name(eid), _hex_label(nk)], {"eid": eid, "hex": nk})

## {hex: cost} reachable with current Move points (Dijkstra, stops at
## hexes where movement would end: provocation, assault).
func reachable() -> Dictionary:
	var out := {}
	var p: int = s.turn.get("player", -1)
	if p < 0 or p == DUMMY or not can_still_move(p):
		return out
	var budget := int(s.turn.pool.move)
	var start: String = P(p).pos
	var dist := {start: 0}
	var frontier: Array = [start]
	while not frontier.is_empty():
		# pick min
		var bi := 0
		for i in frontier.size():
			if dist[frontier[i]] < dist[frontier[bi]]:
				bi = i
		var cur: String = frontier[bi]
		frontier.remove_at(bi)
		if cur != start and _move_stops(p, dist, cur):
			continue
		for nk in MKHex.neighbors(cur):
			if _hex_blocked(p, nk) != "":
				continue
			var c := move_cost(nk, cur)
			if c >= 999:
				continue
			var nd: int = dist[cur] + c
			if nd > budget:
				continue
			if not dist.has(nk) or nd < dist[nk]:
				dist[nk] = nd
				out[nk] = nd
				if not nk in frontier:
					frontier.append(nk)
	return out

func _move_stops(p: int, _dist: Dictionary, k: String) -> bool:
	var h := hex(k)
	if h.site in FORTIFIED_SITES and not _is_safe_fortified(p, k):
		return true
	for nk in MKHex.neighbors(k):
		var nh := hex(nk)
		if not nh.is_empty() and nh.rampage and not nh.enemies.is_empty() and not has_wall(nk, k):
			return true
	return false

# ================================================================ exploration
func explorable_slots(p: int) -> Array:
	var out: Array = []
	if s.map.tile_deck.is_empty():
		return out
	var placed := {}
	for t in s.map.tiles:
		placed[t.slot] = true
	var pos: String = P(p).pos
	var reach := 1
	for m in mods_named("explore_distance"):
		reach = maxi(reach, int(m.get("n", 1)))
	var cand := {}
	var near: Array = [pos]
	for k0 in s.map.hex:
		if MKHex.distance(k0, pos) <= reach:
			near.append(k0)
	for nk in near + MKHex.neighbors(pos):
		for kk in MKHex.TILE_KEYS:
			var c := MKHex.key(MKHex.parse(nk) - MKHex.TILE_KEYS[kk])
			cand[c] = true
	var next_tile: String = s.map.tile_deck[0]
	var next_core: bool = MKDB.tiles.get(next_tile, {}).get("kind", "") == "core"
	for c in cand:
		if placed.has(c):
			continue
		if not MKHex.in_shape(c, s.map.shape):
			continue
		if s.map.shape == "open" and not _open_cols_ok(c):
			continue
		# the hero must stand adjacent to a hex of that slot
		var adj := false
		for hk in MKHex.tile_hexes(c):
			if MKHex.distance(hk, pos) <= reach:
				adj = true
				break
		if not adj:
			continue
		var n_adj := 0
		var touches_start := false
		for m in MKHex.macro_neighbors(c):
			if placed.has(m):
				n_adj += 1
				if m == "0,0":
					touches_start = true
		if next_core:
			if n_adj < 2:
				continue
			if s.map.shape == "wedge" and _on_coast(c):
				continue
		elif n_adj < 2 and not _next_to_well_connected(c, placed):
			# Countryside tiles: adjacent to at least two tiles, or adjacent to a tile that
			# borders at least two other tiles (Regolamento p. 7, "Movimento" 5f).
			continue
		out.append(c)
	out.sort()
	return out

func _next_to_well_connected(c: String, placed: Dictionary) -> bool:
	for m in MKHex.macro_neighbors(c):
		if not placed.has(m):
			continue
		var n := 0
		for m2 in MKHex.macro_neighbors(m):
			if placed.has(m2):
				n += 1
		if n >= 2:
			return true
	return false

func _is_coast(c: String) -> bool:
	for m in MKHex.macro_neighbors(c):
		if m != "0,0" and (not MKHex.in_shape(m, s.map.shape) or (s.map.shape == "open" and not _open_cols_ok(m))):
			return true
	return false

func _on_coast(c: String) -> bool:
	# wedge: slots a*N or b*NE only (outer lines)
	var v := MKHex.parse(c)
	var det := 7
	var a := (v.x * MKHex.MACRO[1].y - v.y * MKHex.MACRO[1].x) / det
	var b := (MKHex.MACRO[0].x * v.y - MKHex.MACRO[0].y * v.x) / det
	return a == 0 or b == 0

func _open_cols_ok(c: String) -> bool:
	# fully open map: at most `cols` parallel columns of tiles. In the (N, E) basis
	# of the open shape (NE = N + E) the column index is the number of N steps.
	var v := MKHex.parse(c)
	var u := (v.x * MKHex.MACRO[2].y - v.y * MKHex.MACRO[2].x) / 7
	return u >= 0 and u <= int(s.scn.get("cols", 5)) - 1

func _check_explore(p: int, slot: String) -> String:
	if not can_still_move(p):
		return "Non puoi più esplorare in questo turno"
	if s.map.tile_deck.is_empty():
		return "Non ci sono più tessere"
	if int(s.turn.pool.move) < explore_cost(p):
		return "Servono %d punti Movimento per esplorare" % explore_cost(p)
	if not slot in explorable_slots(p):
		return "Non puoi esplorare quella posizione"
	return ""

func _do_explore(p: int, slot: String) -> void:
	s.turn.pool.move = int(s.turn.pool.move) - explore_cost(p)
	s.turn.started = true
	s.turn.explored = int(s.turn.explored) + 1
	var tid: String = s.map.tile_deck.pop_front()
	place_tile(tid, slot, p)
	if int(s.scn.get("fame_per_tile", 0)) > 0:
		gain_fame(p, int(s.scn.fame_per_tile))
	var t: Dictionary = MKDB.tiles.get(tid, {})
	if t.get("city", "") != "" and s.scn.end == "city_revealed" and not s.game_end_pending:
		_trigger_game_end("È stata rivelata una città")

func _trigger_game_end(why: String) -> void:
	s.game_end_pending = true
	if s.announced_by == -1:
		s.final_turns = {}
		for i in s.turn_order:
			s.final_turns[str(i)] = true
		s.turn["no_final_consume"] = true
	add_log("game_end", why + ": ogni giocatore ha ancora un ultimo turno", {})

# ================================================================ pending helpers
func ask(p: int, typ: String, handler: String, prompt: String, options: Array, data: Dictionary = {}) -> void:
	s.pending = {"type": typ, "player": p, "handler": handler, "prompt": prompt, "options": options, "min": 1, "max": 1,
		"data": data, "queue": [], "ctx": {"p": p}}

func actor() -> int:
	if s.phase == "game_over":
		return -1
	if s.pending != null:
		return int(s.pending.player)
	if s.phase == "tactics":
		return int(s.active)
	if s.phase == "turn":
		return int(s.turn.get("player", -1))
	return -1

# ================================================================ apply / check
const _STR_FIELDS := ["t", "card", "mode", "side", "slot", "id", "eid", "what", "name", "opt", "kind", "op", "city"]
const _INT_FIELDS := ["uid", "ability", "attack", "disband"]

## Validates field types and returns a clean copy ({"_err": msg} on error).
static func sanitize(a) -> Dictionary:
	if not (a is Dictionary):
		return {"_err": "Azione non valida"}
	var out := {}
	for k in a:
		var v = a[k]
		if k in _STR_FIELDS:
			if not (v is String):
				return {"_err": "Campo '%s' non valido" % k}
			out[k] = v
		elif k in _INT_FIELDS:
			if v is int:
				out[k] = v
			elif v is float and v == floor(v):
				out[k] = int(v)
			else:
				return {"_err": "Campo '%s' non valido" % k}
		elif k in ["targets", "hexes", "mana"]:
			if v == null and k == "mana":
				continue
			if not (v is Array):
				return {"_err": "Campo '%s' non valido" % k}
			for x in v:
				if not (x is String):
					return {"_err": "Campo '%s' non valido" % k}
			out[k] = v.duplicate()
		elif k == "target" or k == "to":
			if v is String:
				out[k] = v
			elif (v is int) or (v is float and v == floor(v)):
				out[k] = int(v)
			else:
				return {"_err": "Campo '%s' non valido" % k}
		elif k == "v":
			var arr: Array = v if v is Array else [v]
			out[k] = arr.duplicate(true)
		else:
			out[k] = v
	if not out.has("t"):
		return {"_err": "Azione senza tipo"}
	return out

func check(a0: Dictionary) -> String:
	var a := sanitize(a0)
	if a.has("_err"):
		return str(a._err)
	if s.phase == "game_over":
		return "La partita è finita"
	var t: String = str(a.get("t", ""))
	if s.pending != null:
		if t != "choose":
			return "C'è una decisione in sospeso: " + str(s.pending.get("prompt", ""))
		var v = a.get("v", null)
		if v is Array:
			v = v[0] if not v.is_empty() else null
		for o in s.pending.options:
			if _same(o.v, v):
				return ""
		return "Scelta non valida"
	if t == "choose":
		return "Nessuna decisione in sospeso"
	if s.phase == "tactics":
		if t != "tactic":
			return "Devi scegliere una tattica"
		if not str(a.get("id", "")) in s.tactics_avail:
			return "Tattica non disponibile"
		return ""
	if t == "tactic":
		return "Non è il momento di scegliere la tattica"
	var p := actor()
	if p < 0:
		return "Nessun giocatore di turno"
	if s.turn.get("ending", false):
		return "Il turno sta terminando"
	if s.get("pvp", null) != null:
		var ge := MKPvP.gate(self, p, a)
		if ge != "":
			return ge
	if t in ["site", "altar", "burn", "challenge", "recruit", "buy"] and MKPvP.crowded(self, p):
		return "Nel tuo spazio c'è un altro eroe: non puoi compiere altre azioni"
	match t:
		"pvp_attack":
			return MKPvP.check_attack(self, p)
		"pvp":
			return "" if s.get("pvp", null) != null else "Nessun combattimento tra giocatori in corso"
		"coop":
			return MKCoop.check_propose(self, p, str(a.get("city", "")))
		"play":
			return _check_play(p, a)
		"move":
			return _check_move(p, str(a.get("to", "")))
		"explore":
			return _check_explore(p, str(a.get("slot", "")))
		"unit":
			return _check_unit(p, a)
		"skill":
			return _check_skill(p, a)
		"end_turn":
			return _check_end_turn(p)
		"rest":
			return _check_rest(p)
		"announce_end":
			return _check_announce(p)
		"heal":
			return _check_heal(p, a)
		"discard":
			if s.combat != null:
				return "Non durante il combattimento"
			var di := str(a.get("card", ""))
			if not P(p).hand.has(di) or is_wound(di):
				return "Puoi scartare solo una carta non-Ferita dalla mano"
			return ""
		"tactic_use":
			return MKSites.check_tactic_use(self, p, a)
		"sp":
			return MKSpecials.check_action(self, p, a)
		"attack", "block", "damage", "next":
			return MKCombat.check(self, p, a)
		_:
			return MKSites.check(self, p, a)

func _same(a, b) -> bool:
	if (a is int or a is float) and (b is int or b is float):
		return int(a) == int(b)
	return typeof(a) == typeof(b) and a == b

func apply(a0: Dictionary) -> Dictionary:
	var err := check(a0)
	if err != "":
		return {"ok": false, "err": err}
	var a := sanitize(a0)
	_do(a)
	_resume()
	return {"ok": true, "err": ""}

func _do(a: Dictionary) -> void:
	var t: String = str(a.get("t", ""))
	if s.pending != null:
		var v = a.get("v", null)
		if v is Array:
			v = v[0]
		for o in s.pending.options:
			if _same(o.v, v):
				v = o.v
				break
		var pend: Dictionary = s.pending
		s.pending = null
		_resolve(pend, v)
		return
	if s.phase == "tactics":
		MKSites.take_tactic(self, actor(), str(a.id))
		return
	var p := actor()
	match t:
		"pvp_attack":
			MKPvP.start(self, p)
		"pvp":
			MKPvP.do_op(self, p, a)
		"coop":
			MKCoop.propose(self, p, str(a.city))
		"play":
			_do_play(p, a)
		"move":
			_do_move(p, str(a.to))
		"explore":
			_do_explore(p, str(a.slot))
		"unit":
			_do_unit(p, a)
		"skill":
			_do_skill(p, a)
		"end_turn":
			_do_end_turn(p)
		"rest":
			_do_rest(p)
		"announce_end":
			s.turn.started = true
			_announce(p)
		"heal":
			_do_heal(p, a)
		"discard":
			discard_from_hand(p, str(a.card))
		"tactic_use":
			MKSites.do_tactic_use(self, p, a)
		"sp":
			MKSpecials.do_action(self, p, a)
		"attack", "block", "damage", "next":
			MKCombat.do(self, p, a)
		_:
			MKSites.do(self, p, a)

func _resolve(pend: Dictionary, v) -> void:
	var h: String = str(pend.get("handler", ""))
	if MKEffects.resolve(self, pend, v):
		return
	if h.begins_with("sp:"):
		MKSpecials.resolve(self, pend, v)
		return
	if h.begins_with("pvp:"):
		MKPvP.resolve(self, pend, v)
		return
	if h.begins_with("coop:"):
		MKCoop.resolve(self, pend, v)
		return
	match h:
		"rest_card", "rest_wound":
			_resolve_rest(pend, v)
		"end_discard":
			discard_from_hand(int(pend.player), str(v))
		_:
			if not MKSites.resolve(self, pend, v):
				if not MKCombat.resolve(self, pend, v):
					add_log("error", "Decisione sconosciuta: " + h)

## Continue automatic flow after an action (end of turn steps etc.).
func _resume() -> void:
	_resume_loop()
	if s.phase == "turn" and s.turn.has("player"):
		s.turn.stage = "done" if s.turn.get("ending", false) else ("action" if s.turn.get("acted", false) else "move")

func _resume_loop() -> void:
	var guard := 0
	while guard < 200:
		guard += 1
		if s.pending != null or s.phase == "game_over":
			return
		if s.phase == "tactics":
			if s.tactic_pick.is_empty() or P(s.tactic_pick[0]).tactic != "":
				_next_tactic_pick()
				if s.phase == "tactics" and s.pending == null and not s.tactic_pick.is_empty() and P(s.tactic_pick[0]).tactic == "":
					s.active = s.tactic_pick[0]
					return
				continue
			s.active = s.tactic_pick[0]
			return
		if s.phase == "turn" and s.turn.get("ending", false):
			if not _continue_end_turn():
				return
			continue
		if s.combat != null and s.combat.get("phase", "") == "end":
			MKCombat.finish(self)
			continue
		if s.combat == null and s.get("coop", null) != null and str(s.coop.stage) == "combat":
			MKCoop.after_combat(self)
			continue
		return

# ================================================================ playing cards
## Mana needs for a play, choosing among the card colours (dual-colour
## cards) the first one that can be paid. Returns null if none can.
func play_mana(p: int, c: Dictionary, mode: String, given = null) -> Variant:
	var opts: Array = []
	var cols = c.get("colors", [])
	if cols is Array and cols.size() > 1 and mode != "side":
		for col in cols:
			var c2: Dictionary = c.duplicate()
			c2["color"] = col
			opts.append(card_mana_needs(c2, mode))
	else:
		opts.append(card_mana_needs(c, mode))
	for needs in opts:
		if needs.is_empty():
			return {"needs": needs, "plan": []}
		var plan = MKMana.plan(self, p, needs, given)
		if plan != null:
			return {"needs": needs, "plan": plan}
	return null

func card_mana_needs(c: Dictionary, mode: String) -> Array:
	if mode == "side":
		return []
	match str(c.get("type", "")):
		"basic", "aa":
			if mode == "powered":
				var col: String = str(c.get("color", ""))
				if c.has("powered_mana"):
					return c.powered_mana.duplicate()
				return [col] if col != "" else []
		"spell":
			var col2: String = str(c.get("color", ""))
			if mode == "powered":
				return [col2, "black"]
			return [col2]
	return []

func _play_ctx(p: int, iid: String, mode: String) -> Dictionary:
	var c := card(iid)
	return {"p": p, "src": iid, "card": card_id(iid), "kind": "card", "ctype": c.get("type", ""), "mode": mode,
		"color": c.get("color", ""), "boost": 0}

func _check_play(p: int, a: Dictionary) -> String:
	var iid := str(a.get("card", ""))
	var pl: Dictionary = P(p)
	if not pl.hand.has(iid):
		return "La carta non è nella tua mano"
	if s.turn.get("rested", false) and s.combat == null:
		pass
	var c := card(iid)
	if c.is_empty():
		return "Carta sconosciuta"
	if is_wound(iid):
		return "Le ferite non si possono giocare"
	var mode := str(a.get("mode", "basic"))
	var in_combat: bool = s.combat != null
	if mode == "side":
		if not c.get("side", true):
			return "Questa carta non si può giocare di lato"
		var side := str(a.get("side", ""))
		match side:
			"move":
				if not can_still_move(p) and not (in_combat and flag(p, "move_to_attack")) and not MKSpecialsExp.move_ok(self, p):
					return "Non puoi usare Movimento ora"
			"influence":
				if (in_combat and not flag(p, "influence_as_block")) or (not in_combat and not _can_influence(p)):
					return "Non puoi usare Influenza ora"
			"attack":
				if not in_combat or s.combat.phase != "attack":
					return "Attacco 1 di lato solo nella fase di attacco"
			"block":
				if not in_combat or s.combat.phase != "block":
					return "Blocco 1 di lato solo nella fase di blocco"
			_:
				return "Lato non valido"
		return ""
	if mode != "basic" and mode != "powered":
		return "Modo non valido"
	if c.get("combat_only", false) and not in_combat:
		return "Questa carta si gioca solo in combattimento"
	if mode == "powered" and c.get("combat_only_powered", false) and not in_combat:
		return "L'effetto potenziato si gioca solo in combattimento"
	var effs: Array = c.get(mode, [])
	if effs.is_empty():
		return "Questa carta non ha un effetto %s" % ("potenziato" if mode == "powered" else "base")
	var ctx := _play_ctx(p, iid, mode)
	if mode == "powered" and int(_boost_available()) > 0 and c.type in ["basic", "aa"]:
		ctx.boost = _boost_available()
	var pm = play_mana(p, c, mode, a.get("mana", null))
	if pm == null:
		return "Mana insufficiente per giocare la carta" if a.get("mana", null) == null else "Mana non valido"
	ctx["_mana_used"] = pm.plan
	if not MKEffects.any_can(self, effs, ctx):
		return "L'effetto non si può usare ora"
	if s.turn.get("rested", false) and not _restful_ok(effs):
		return "Hai riposato: puoi solo usare effetti speciali o di guarigione"
	return ""

func _restful_ok(effs) -> bool:
	# while resting, move/attack/block/influence are useless; allow anything else
	return true

func _can_influence(p: int) -> bool:
	return s.combat == null and not s.turn.get("rested", false)

func _boost_available() -> int:
	for m in s.turn.mods:
		if m.get("name", "") == "boost":
			return int(m.get("n", 0))
	return 0

func _consume_boost() -> int:
	for i in s.turn.mods.size():
		if s.turn.mods[i].get("name", "") == "boost":
			var n := int(s.turn.mods[i].get("n", 0))
			s.turn.mods.remove_at(i)
			return n
	return 0

func _do_play(p: int, a: Dictionary) -> void:
	var iid := str(a.card)
	var pl: Dictionary = P(p)
	var c := card(iid)
	var mode := str(a.get("mode", "basic"))
	pl.hand.erase(iid)
	pl.play.append(iid)
	s.turn.played.append(iid)
	s.turn.started = true
	if mode == "side":
		var side := str(a.side)
		var v := side_value(p, side, iid, true)
		match side:
			"move":
				s.turn.pool.move = int(s.turn.pool.move) + v
			"influence":
				s.turn.pool.influence = int(s.turn.pool.influence) + v
			"attack":
				s.turn.pool.attack["melee:phys"] = int(s.turn.pool.attack.get("melee:phys", 0)) + v
			"block":
				s.turn.pool.block["phys"] = int(s.turn.pool.block.get("phys", 0)) + v
		var side_it := {"move": "Movimento", "influence": "Influenza", "attack": "Attacco", "block": "Blocco"}
		add_log("play", "%s gioca %s di lato: %s %d" % [pname(p), card_name(iid), side_it[side], v], {"p": p, "card": iid, "mode": "side", "side": side})
		return
	var ctx := _play_ctx(p, iid, mode)
	var pm = play_mana(p, c, mode, a.get("mana", null))
	var needs: Array = pm.needs
	if not needs.is_empty():
		var plan: Array = pm.plan
		var paid: Array = MKMana.pay(self, p, plan, needs)
		ctx["paid"] = paid[0] if not paid.is_empty() else ""
		var cols: Array = []
		for x in paid:
			cols.append(MKMana.color_it(x))
		add_log("mana", "%s paga mana %s" % [pname(p), ", ".join(cols)], {"p": p, "colors": paid})
	if mode == "powered" and c.type in ["basic", "aa"]:
		ctx.boost = _consume_boost()
	if c.type == "spell":
		pl.spells_cast = int(pl.spells_cast) + 1
	if c.type == "artifact" and mode == "powered":
		s.turn.destroy.append(iid)
	var nm := card_name(iid)
	if c.type == "spell" and mode == "powered" and c.get("name_powered_it", "") != "":
		nm = str(c.name_powered_it)
	add_log("play", "%s gioca %s%s" % [pname(p), nm, " (potenziata)" if mode == "powered" and c.type != "spell" else ""],
		{"p": p, "card": iid, "mode": mode})
	MKSpecials.on_card_played(self, p, iid, mode)
	MKEffects.start(self, c.get(mode, []), ctx)

# ================================================================ units / skills
func units_usable() -> bool:
	return s.combat == null or s.combat.get("units_allowed", true)

func _check_unit(p: int, a: Dictionary) -> String:
	var u = find_unit(p, a.get("uid", -1))
	if u == null:
		return "Unità non trovata"
	if not u.ready:
		return "L'unità è esaurita"
	if u.wounded:
		return "L'unità è ferita"
	if not units_usable():
		return "Le unità non possono partecipare a questo combattimento"
	var ux := MKSitesExp.unit_restrict(self, p, u)
	if ux != "":
		return ux
	var d := unit_def(u)
	var ac = MKSpecials.unit_rule(d, "unit_assault_cost")
	if ac != null and s.combat != null and s.combat.get("assault", false) and not u.get("assault_paid", false):
		if int(s.turn.pool.influence) < int(ac.get("influence", 2)):
			return "Serve pagare %d Influenza per usare questa unità in un assalto" % int(ac.get("influence", 2))
	var ai := int(a.get("ability", 0))
	var abs: Array = d.get("abilities", [])
	if ai < 0 or ai >= abs.size():
		return "Abilità non valida"
	var ab: Dictionary = abs[ai]
	var eff: Array = ab.get("effect", [])
	if eff.is_empty():
		return "Abilità passiva"
	var ctx := {"p": p, "src": "unit:%d" % int(u.uid), "uid": int(u.uid), "kind": "unit", "mode": "unit", "color": ab.get("mana", ""), "boost": 0}
	var mana: String = str(ab.get("mana", ""))
	if mana != "":
		var plan = MKMana.plan(self, p, [mana], a.get("mana", null))
		if plan == null:
			return "Mana insufficiente per l'abilità"
		ctx["_mana_used"] = plan
	if not MKEffects.any_can(self, eff, ctx):
		return "L'abilità non si può usare ora"
	return ""

func _do_unit(p: int, a: Dictionary) -> void:
	var u = find_unit(p, a.uid)
	var d := unit_def(u)
	var ab: Dictionary = d.abilities[int(a.get("ability", 0))]
	var ctx := {"p": p, "src": "unit:%d" % int(u.uid), "uid": int(u.uid), "kind": "unit", "mode": "unit", "color": ab.get("mana", ""), "boost": 0}
	var mana: String = str(ab.get("mana", ""))
	if mana != "":
		var plan = MKMana.plan(self, p, [mana], a.get("mana", null))
		var paid: Array = MKMana.pay(self, p, plan, [mana])
		ctx["paid"] = paid[0]
	var ac = MKSpecials.unit_rule(d, "unit_assault_cost")
	if ac != null and s.combat != null and s.combat.get("assault", false) and not u.get("assault_paid", false):
		s.turn.pool.influence = int(s.turn.pool.influence) - int(ac.get("influence", 2))
		u["assault_paid"] = true
	u.ready = false
	s.turn.started = true
	add_log("unit", "%s attiva %s" % [pname(p), unit_name(u)], {"p": p, "uid": u.uid, "ability": int(a.get("ability", 0))})
	MKEffects.start(self, ab.get("effect", []), ctx)

func find_skill(p: int, id: String) -> Variant:
	for sk in P(p).skills:
		if sk.id == id:
			return sk
	return null

func _check_skill(p: int, a: Dictionary) -> String:
	var sk = find_skill(p, str(a.get("id", "")))
	if sk == null:
		return "Abilità non posseduta"
	var d: Dictionary = MKDB.skills.get(sk.id, {})
	var usage := str(d.get("usage", "turn"))
	if usage == "passive":
		return "Abilità passiva"
	if usage == "turn" and sk.used_turn:
		return "Abilità già usata in questo turno"
	if usage in ["round", "interactive"] and sk.used_round:
		return "Abilità già usata in questo round"
	if sk.get("flipped", false):
		return "Abilità girata: va prima rigirata"
	var eff: Array = d.get("effect", [])
	if eff.is_empty():
		return "Abilità senza effetto attivabile"
	var ctx := {"p": p, "src": "skill:" + sk.id, "kind": "skill", "mode": "skill", "boost": 0}
	if not MKEffects.any_can(self, eff, ctx):
		return "L'abilità non si può usare ora"
	return ""

func _do_skill(p: int, a: Dictionary) -> void:
	var sk = find_skill(p, str(a.id))
	var d: Dictionary = MKDB.skills.get(sk.id, {})
	var usage := str(d.get("usage", "turn"))
	sk.used_turn = true
	if usage in ["round", "interactive"]:
		sk.used_round = true
	s.turn.started = true
	add_log("skill", "%s usa l'abilità %s" % [pname(p), str(d.get("name_it", sk.id))], {"p": p, "skill": sk.id})
	MKEffects.start(self, d.get("effect", []), {"p": p, "src": "skill:" + sk.id, "kind": "skill", "mode": "skill", "boost": 0})

# ================================================================ healing
func _check_heal(p: int, a: Dictionary) -> String:
	if s.combat != null:
		return "Non puoi guarire durante il combattimento"
	var pool: Dictionary = s.turn.pool
	var tgt = a.get("target", "hand")
	if str(tgt) == "hand":
		if int(pool.heal) < 1:
			return "Non hai punti Cura"
		for iid in P(p).hand:
			if is_wound(iid):
				return ""
		return "Non hai ferite in mano"
	var u = find_unit(p, tgt)
	if u == null or not u.wounded:
		return "Unità non ferita"
	if int(pool.heal) < unit_level(u):
		return "Servono %d punti Cura" % unit_level(u)
	return ""

func _do_heal(p: int, a: Dictionary) -> void:
	var pool: Dictionary = s.turn.pool
	var tgt = a.get("target", "hand")
	if str(tgt) == "hand":
		for iid in P(p).hand:
			if is_wound(iid):
				pool.heal = int(pool.heal) - 1
				throw_away(p, iid)
				add_log("heal", "%s guarisce una ferita" % pname(p), {"p": p, "what": "hand"})
				MKSpecials.on_heal(self, p)
				return
	var u = find_unit(p, tgt)
	pool.heal = int(pool.heal) - unit_level(u)
	u.wounds = int(u.get("wounds", 1)) - 1
	if int(u.wounds) <= 0:
		u.wounds = 0
		u.wounded = false
	u["healed_turn"] = true
	if flag(p, "cure_bonus"):
		u.ready = true
	add_log("heal", "%s guarisce %s" % [pname(p), unit_name(u)], {"p": p, "uid": u.uid})

# ================================================================ rest / end turn / announce
func _check_rest(p: int) -> String:
	var t: Dictionary = s.turn
	if s.combat != null:
		return "Non puoi riposare in combattimento"
	if t.moved or t.acted or t.rested:
		return "Puoi riposare solo se non ti sei mosso e non hai compiuto azioni"
	if P(p).hand.is_empty():
		return "Non hai carte in mano"
	return ""

func _do_rest(p: int) -> void:
	var t: Dictionary = s.turn
	t.rested = true
	t.started = true
	MKSpecialsExp.on_rest(self, p)
	var hand: Array = P(p).hand
	var non_w: Array = []
	for iid in hand:
		if not is_wound(iid):
			non_w.append(iid)
	if non_w.is_empty():
		add_log("rest", "%s fa una Lunga Guarigione" % pname(p), {"p": p, "kind": "slow"})
		discard_from_hand(p, hand[0])
		return
	add_log("rest", "%s riposa" % pname(p), {"p": p, "kind": "standard"})
	var options: Array = []
	var seen := {}
	for iid in non_w:
		var cid := card_id(iid)
		if seen.has(cid):
			continue
		seen[cid] = true
		options.append({"v": iid, "label": "Scarta " + card_name(iid)})
	if options.size() == 1:
		discard_from_hand(p, options[0].v)
		_ask_rest_wounds(p)
		return
	ask(p, "card", "rest_card", "Riposo: scegli una carta non-Ferita da scartare", options)

func _ask_rest_wounds(p: int) -> void:
	var w := 0
	for iid in P(p).hand:
		if is_wound(iid):
			w += 1
	if w == 0:
		return
	var options: Array = [{"v": "all", "label": "Scarta tutte le Ferite (%d)" % w}, {"v": "one", "label": "Scarta una Ferita"}, {"v": "none", "label": "Tieni le Ferite"}]
	if w == 1:
		options = [{"v": "all", "label": "Scarta la Ferita"}, {"v": "none", "label": "Tieni la Ferita"}]
	ask(p, "choice", "rest_wound", "Riposo: quante Ferite vuoi scartare?", options)

func _resolve_rest(pend: Dictionary, v) -> void:
	var p: int = int(pend.player)
	if pend.handler == "rest_card":
		discard_from_hand(p, str(v))
		_ask_rest_wounds(p)
		return
	match str(v):
		"all":
			for iid in P(p).hand.duplicate():
				if is_wound(iid):
					discard_from_hand(p, iid)
		"one":
			for iid in P(p).hand.duplicate():
				if is_wound(iid):
					discard_from_hand(p, iid)
					break
			_ask_rest_wounds(p)

func _check_announce(p: int) -> String:
	if s.turn.get("started", false):
		return "Puoi annunciare la fine del round solo all'inizio del turno"
	if s.announced_by != -1 or s.game_end_pending:
		return "La fine del round è già stata annunciata"
	if not P(p).deck.is_empty():
		return "Puoi annunciare la fine del round solo con il mazzo vuoto"
	return ""

func card_rule_open(p: int) -> bool:
	## true if the player has not yet played/discarded a card this turn
	var t: Dictionary = s.turn
	return t.played.is_empty() and not t.rested and int(t.get("discarded", 0)) == 0 and not P(p).hand.is_empty()

func has_non_wound(p: int) -> bool:
	for iid in P(p).hand:
		if not is_wound(iid):
			return true
	return false

## Only wounds in hand and nothing played yet: the only legal option is resting.
func wounds_only_lock(p: int) -> bool:
	# (solo finché si può ancora riposare: dopo un movimento o un'azione non c'è più nulla da forzare)
	return card_rule_open(p) and not has_non_wound(p) and not s.turn.get("moved", false) and not s.turn.get("acted", false)

func _check_end_turn(p: int) -> String:
	if s.combat != null:
		return "Devi prima terminare il combattimento"
	if wounds_only_lock(p):
		return "Hai solo Ferite in mano: devi riposare (Lunga Guarigione)"
	return ""

func _do_end_turn(p: int) -> void:
	if MKPvP.auto_attack(self, p):
		return
	s.turn.ending = true
	s.turn.end_step = 0
	add_log("end_turn", "%s termina il turno" % pname(p), {"p": p})

## Runs end-of-turn steps; returns true if progress was made (call again).
func _continue_end_turn() -> bool:
	var t: Dictionary = s.turn
	var p: int = int(t.player)
	var pl: Dictionary = P(p)
	match int(t.end_step):
		0:
			t.end_step = 1
			if card_rule_open(p) and has_non_wound(p):
				var opts: Array = []
				var seen := {}
				for iid in pl.hand:
					if is_wound(iid) or seen.has(card_id(iid)):
						continue
					seen[card_id(iid)] = true
					opts.append({"v": iid, "label": "Scarta " + card_name(iid)})
				if opts.size() == 1:
					discard_from_hand(p, opts[0].v)
				else:
					ask(p, "card", "end_discard", "Devi giocare o scartare almeno una carta: scegli la carta da scartare", opts)
			# forced retreat if on an unsafe space
			_forced_retreat(p)
			return true
		1:
			# site benefits
			t.end_step = 2
			var h := hex(pl.pos)
			if not t.get("skip_site_benefits", false):
				if h.get("site", "") == "glade":
					var w := ""
					for iid in pl.hand:
						if is_wound(iid):
							w = iid
							break
					if w == "":
						for iid in pl.discard:
							if is_wound(iid):
								w = iid
								break
					if w != "":
						throw_away(p, w)
						add_log("site", "Radura magica: %s getta via una Ferita" % pname(p), {"p": p})
				if h.get("mine", "") != "" or h.has("mines"):
					var cols: Array = h.get("mines", [h.mine])
					if cols.size() > 1:
						var opts: Array = []
						for c in cols:
							if int(pl.crystals.get(c, 0)) < 3:
								opts.append({"v": c, "label": "Cristallo " + MKMana.color_it(c)})
						if opts.size() > 1:
							ask(p, "color", "mine", "Miniera: scegli il colore del cristallo", opts)
							return true
						elif opts.size() == 1:
							gain_crystal(p, opts[0].v)
					elif int(pl.crystals.get(cols[0], 0)) < 3:
						gain_crystal(p, cols[0])
						add_log("site", "Miniera di cristalli", {"p": p})
			return true
		2:
			# rewards
			if not t.rewards.is_empty():
				var r: Dictionary = t.rewards.pop_front()
				MKSites.give_reward(self, p, r)
				return true
			t.end_step = 3
			return true
		3:
			if not t.rewards.is_empty():
				MKSites.give_reward(self, p, t.rewards.pop_front())
				return true
			# level ups
			var lv := level_of(int(pl.fame))
			if lv > int(pl.level):
				var nl := int(pl.level) + 1
				pl.level = nl
				pl.armor = LV_ARMOR[nl - 1]
				pl.hand_limit = LV_HAND[nl - 1]
				pl.command = LV_CMD[nl - 1] + int(pl.get("extra_command", 0))
				add_log("level", "%s sale al livello %d" % [pname(p), nl], {"p": p, "level": nl})
				if nl % 2 == 0:
					MKSites.level_up_skill(self, p)
				return true
			t.end_step = 4
			return true
		4:
			if not t.get("sp_end_asked", false):
				t["sp_end_asked"] = true
				if MKSpecials.end_turn_pending(self, p):
					return true
			t.end_step = 5
			MKSpecials.on_cleanup(self, p)
			_cleanup(p)
			return true
		5:
			t.end_step = 6
			if not t.get("skip_draw", false):
				var lim := hand_limit_now(p)
				if pl.tactic != "" and tactic_key(pl.tactic) == "d4" and pl.hand.size() >= 2:
					lim += 1
				var hl_bonus := 0
				for m in t.mods:
					if m.get("name", "") == "hand_limit":
						hl_bonus += int(m.get("n", 0))
				lim += hl_bonus
				if hl_bonus > 0 and (s.announced_by != -1 or s.game_end_pending):
					# last turn of the round: the bonus applies at the start of the next round
					pl.pending_hand_bonus = int(pl.pending_hand_bonus) + hl_bonus
				var need: int = lim - pl.hand.size()
				if need > 0:
					if pl.deck.size() < need and pl.tactic != "" and tactic_key(pl.tactic) == "n2" and not pl.tactic_used and not pl.discard.is_empty():
						MKSites.long_night(self, p)
					draw(p, need)
			return true
		6:
			t.end_step = 7
			t.ending = false
			if (s.announced_by != -1 or s.game_end_pending) and not t.get("no_final_consume", false):
				s.final_turns.erase(str(p))
			_check_objectives(p)
			if MKPvP.sub_turn_end(self) or MKCoop.sub_turn_end(self):
				return true
			_advance()
			return true
	return false

func _forced_retreat(p: int) -> void:
	var pl: Dictionary = P(p)
	var path: Array = s.turn.path
	var i := path.size() - 1
	var moved := 0
	while i > 0 and not _is_safe(p, path[i]):
		i -= 1
		moved += 1
	if moved > 0:
		pl.pos = path[i]
		for n in moved:
			add_wound(p, true)
		add_log("retreat", "%s si ritira e prende %d Ferit%s" % [pname(p), moved, "a" if moved == 1 else "e"], {"p": p, "to": pl.pos, "n": moved})

func _is_safe(p: int, k: String) -> bool:
	var h := hex(k)
	if h.is_empty():
		return false
	if COST_DAY.get(h.t, 999) >= 999 and h.site != "city":
		var made_safe := false
		for m in mods_named("terrain"):
			if h.t in m.get("map", {}).get("safe", []):
				made_safe = true
		if not made_safe:
			return false
	if h.site in FORTIFIED_SITES and not _is_safe_fortified(p, k):
		return false
	if h.site == "portal" or (h.site == "city" and h.conquered):
		return true
	for i in s.players.size():
		if i != p and P(i).pos == k:
			return false
	return true

func _cleanup(p: int) -> void:
	var pl: Dictionary = P(p)
	var t: Dictionary = s.turn
	pl.tokens = []
	# dice back and rerolled
	for i in s.source.size():
		var d: Dictionary = s.source[i]
		if int(d.taken_by) == p:
			d.taken_by = -1
			if not i in t.get("fixed_dice", []):
				d.color = DIE_COLORS[MKRng.rand_int(s, 6)]
	if t.get("stolen_used", "") != "":
		s.source.append({"color": DIE_COLORS[MKRng.rand_int(s, 6)], "taken_by": -1})
	# (the "at least half basic colours" check applies only when the Source is reset at round start)
	for iid in pl.play:
		if iid in t.destroy:
			throw_away_played(p, iid)
		elif iid in t.get("set_aside", []):
			pl.removed.append(iid)
		else:
			pl.discard.append(iid)
	pl.play = []
	t.pool = {"move": 0, "influence": 0, "heal": 0, "attack": {}, "block": {}}
	for u in pl.units:
		u.erase("healed_turn")
		u.erase("assault_paid")
		u.erase("dmg_paid")

func throw_away_played(p: int, iid: String) -> void:
	if is_wound(iid):
		s.decks.wounds = int(s.decks.wounds) + 1
	else:
		P(p).removed.append(iid)

func _check_objectives(p: int) -> void:
	if s.game_end_pending:
		return
	if s.scn.end == "cities":
		var total := 0
		var conq := 0
		for k in s.map.hex:
			var h: Dictionary = s.map.hex[k]
			if h.site == "city":
				total += 1
				if h.conquered:
					conq += 1
		var expected: int = int(s.scn.city)
		if total >= expected and conq >= total and total > 0:
			_trigger_game_end("Tutte le città sono state conquistate")
			if s.scn.get("dummy_no_final", false):
				# the dummy does not get a final turn
				s.final_turns.erase(str(DUMMY))

# ================================================================ game over & scoring
func _game_over() -> void:
	s.phase = "game_over"
	s.active = -1
	var scores: Array = []
	for i in s.players.size():
		scores.append(score(i))
	var best := -9999
	var winners: Array = []
	for i in scores.size():
		var tot := int(scores[i].total)
		if tot > best:
			best = tot
			winners = [i]
		elif tot == best:
			winners.append(i)
	var res := {"scores": scores, "winners": winners, "rounds": s.round}
	if s.scn.end == "cities":
		var conq := 0
		var total := 0
		for k in s.map.hex:
			if s.map.hex[k].site == "city":
				total += 1
				if s.map.hex[k].conquered:
					conq += 1
		res["cities_conquered"] = conq
		res["cities_total"] = int(s.scn.city)
		res["victory"] = conq >= int(s.scn.city) and int(s.scn.city) > 0
	if s.scn.mode == "coop" and scores.size() > 0:
		var low := 9999
		for sc in scores:
			low = mini(low, int(sc.fame))
		var team := low
		for key in scores[0].achievements:
			var best_v := -9999
			var worst_v := 9999
			for sc in scores:
				best_v = maxi(best_v, int(sc.achievements[key]))
				worst_v = mini(worst_v, int(sc.achievements[key]))
			team += worst_v if key == "beating" else best_v
		var ex: Dictionary = s.scn.get("score_extra", {})
		var cc: int = int(res.get("cities_conquered", 0))
		team += int(ex.get("per_city", 10)) * cc
		if res.get("victory", false):
			team += int(ex.get("all_cities", 15))
			team += int(ex.get("per_round_early", 30)) * maxi(0, int(s.scn.rounds) - int(s.round))
			if s.dummy != null:
				team += int(ex.get("per_dummy_deck_card", 1)) * s.dummy.deck.size()
			if s.announced_by == -1:
				team += int(ex.get("round_end_not_announced", 5))
		var all_lead := true
		for i in s.players.size():
			var leads := false
			for k in s.map.hex:
				var hh: Dictionary = s.map.hex[k]
				if hh.site == "city" and hh.conquered and int(hh.city.get("leader", -1)) == i:
					leads = true
			if not leads:
				all_lead = false
		if all_lead:
			team += int(ex.get("every_player_leader", 10))
		res["team_score"] = team
	s.result = res
	var txt := "Partita finita."
	if s.scn.mode in ["solo", "coop"]:
		txt += " Obiettivo %s." % ("raggiunto" if res.get("victory", false) else "fallito")
	for i in scores.size():
		txt += " %s: %d" % [pname(i), int(scores[i].total)]
	add_log("game_over", txt, {"result": res})

func score(i: int) -> Dictionary:
	var pl: Dictionary = P(i)
	var all: Array = pl.deck + pl.hand + pl.discard + pl.play + pl.get("set_aside", []) + pl.get("tactic_store", [])
	var spells := 0
	var aas := 0
	var arts := 0
	var wounds := 0
	for iid in all:
		var c := card(iid)
		match str(c.get("type", "")):
			"spell":
				spells += 1
			"aa":
				aas += 1
			"artifact":
				arts += 1
			"wound":
				wounds += 1
		if card_id(iid) == "wound":
			if c.get("type", "") != "wound":
				wounds += 1
	arts += pl.get("banners", {}).size()
	var cr := 0
	for c2 in pl.crystals:
		cr += int(pl.crystals[c2])
	var leader := 0
	for u in pl.units:
		var lv := unit_level(u)
		leader += lv / 2 if u.wounded else lv
	var conq := 0
	var adv := 0
	for k in pl.shields:
		var h := hex(k)
		if h.get("site", "") in ["keep", "mage_tower", "monastery"]:
			conq += 2
		elif h.get("site", "") in ADVENTURE_SITES:
			adv += 2
	var ach := {"knowledge": spells * 2 + aas, "loot": arts * 2 + cr / 2, "leader": leader, "conqueror": conq,
		"adventurer": adv, "beating": -2 * wounds}
	var titles := {}
	var give_titles: bool = s.players.size() > 1 and bool(s.scn.get("titles", s.scn.mode == "competitive"))
	if give_titles:
		for key in ach:
			var vals: Array = []
			for j in s.players.size():
				vals.append(_ach_value(j, key))
			var mine: int = vals[i]
			if key == "beating":
				var worst: int = vals.min()
				if worst < 0 and mine == worst:
					titles[key] = -3 if vals.count(worst) == 1 else -1
			else:
				var mx: int = vals.max()
				if mx > 0 and mine == mx:
					titles[key] = 3 if vals.count(mx) == 1 else 1
	var cities := 0
	if str(s.scn.get("scoring", "")).find("cities") >= 0:
		var cv: Array = []
		for j in s.players.size():
			cv.append(_city_points(j))
		cities = cv[i]
		var mx: int = cv.max()
		if mx > 0 and cities == mx:
			cities += 5 if cv.count(mx) == 1 else 2
	var obj := 0
	if s.scn.mode == "solo" and s.scn.end == "cities":
		var cc := 0
		var tot := 0
		for k in s.map.hex:
			if s.map.hex[k].site == "city":
				tot += 1
				if s.map.hex[k].conquered:
					cc += 1
		obj += 10 * cc
		if cc >= int(s.scn.city) and cc > 0:
			obj += 15
			obj += 30 * maxi(0, int(s.scn.rounds) - int(s.round))
			if s.dummy != null:
				obj += s.dummy.deck.size()
			if s.announced_by == -1:
				obj += 5
	var total := int(pl.fame)
	for key in ach:
		total += int(ach[key])
	for key in titles:
		total += int(titles[key])
	total += cities + obj
	return {"fame": pl.fame, "achievements": ach, "titles": titles, "cities": cities, "objective": obj, "total": total}

func _city_points(i: int) -> int:
	var v := 0
	for k in s.map.hex:
		var h2: Dictionary = s.map.hex[k]
		if h2.site == "city" and h2.conquered:
			if int(h2.city.get("leader", -1)) == i:
				v += 7
			elif h2.city.get("shields", []).has(i):
				v += 4
	return v

func _ach_value(j: int, key: String) -> int:
	# computed without titles (avoid recursion)
	var pl: Dictionary = P(j)
	var all: Array = pl.deck + pl.hand + pl.discard + pl.play + pl.get("set_aside", []) + pl.get("tactic_store", [])
	var v := 0
	match key:
		"knowledge":
			for iid in all:
				var t := str(card(iid).get("type", ""))
				v += 2 if t == "spell" else (1 if t == "aa" else 0)
		"loot":
			for iid in all:
				if str(card(iid).get("type", "")) == "artifact":
					v += 2
			v += 2 * pl.get("banners", {}).size()   # banners attached to units count as artifacts
			var cr := 0
			for c in pl.crystals:
				cr += int(pl.crystals[c])
			v += cr / 2
		"leader":
			for u in pl.units:
				v += unit_level(u) / 2 if u.wounded else unit_level(u)
		"conqueror":
			for k in pl.shields:
				if hex(k).get("site", "") in ["keep", "mage_tower", "monastery"]:
					v += 2
		"adventurer":
			for k in pl.shields:
				if hex(k).get("site", "") in ADVENTURE_SITES:
					v += 2
		"beating":
			for iid in all:
				if is_wound(iid):
					v -= 2
	return v

# ================================================================ combat wrappers
func effective_attack(targets: Array) -> int:
	return MKCombat.effective_attack(self, targets)

func effective_block(eid, attack_index: int = 0) -> int:
	return MKCombat.effective_block(self, str(eid), attack_index)

# ================================================================ available actions
func available() -> Array:
	return MKAvail.list(self)
