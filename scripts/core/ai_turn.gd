extends RefCounted
## AI helper (agent AI): turn planning outside combat (missions: fight, adventure, challenge,
## interaction, exploration, altar, relocation, rest) and tactic choice.

const C = preload("res://scripts/core/ai_cards.gd")
const CB = preload("res://scripts/core/ai_combat.gd")
const BIG := 1.0e9

# ================================================================ tactics
const TAC_DAY := {"the_right_moment": 6.0, "great_start": 5.5, "mana_steal": 4.5, "rethink": 3.5, "planning": 4.0, "early_bird": 2.0}
const TAC_NIGHT := {"sparing_power": 4.5, "midnight_meditation": 4.0, "preparation": 5.0, "mana_search": 3.0, "long_night": 3.0, "from_the_dusk": 2.0}

static func choose_tactic(eng, p: int, ctx: Dictionary) -> Dictionary:
	var best = ""
	var bv = -BIG
	var pl: Dictionary = eng.P(p)
	var wounds = 0
	for iid in pl.hand:
		if eng.is_wound(iid):
			wounds += 1
	var rng: RandomNumberGenerator = ctx.rng
	for t in eng.s.tactics_avail:
		var key: String = eng.tactic_key(t)
		var v = 3.0
		match key:
			"d1":
				v = 2.0
			"d2":
				v = 2.5 + 1.5 * float(wounds)
			"d3":
				v = 4.5
			"d4":
				v = 4.0
			"d5":
				v = 5.5
			"d6":
				v = 6.0 if int(eng.s.round) < int(eng.s.scn.rounds) or true else 3.0
			"n1":
				v = 2.0
			"n2":
				v = 3.0
			"n3":
				v = 3.0
			"n4":
				v = 3.0 + 1.2 * float(wounds)
			"n5":
				v = 5.0
			"n6":
				v = 4.5
		# competitive: early turn order matters a little
		if eng.is_competitive():
			v += 0.25 * (7 - eng.tactic_number(t))
		if int(ctx.level) == 1:
			v += rng.randf_range(-2.5, 2.5)
		elif int(ctx.level) == 2:
			v += rng.randf_range(-0.8, 0.8)
		if v > bv:
			bv = v
			best = t
	return {"t": "tactic", "id": best}

# ================================================================ movement graph
static func provokes(eng, p: int, from: String, to: String) -> bool:
	if eng.flag(p, "no_provoke"):
		return false
	for nk in MKHex.neighbors(from):
		if nk == to:
			continue
		var nh: Dictionary = eng.hex(nk)
		if nh.is_empty() or not nh.rampage or nh.enemies.is_empty():
			continue
		if MKHex.adjacent(nk, to):
			return true
	return false

static func is_assault_hex(eng, p: int, k: String) -> bool:
	var h: Dictionary = eng.hex(k)
	return h.get("site", "") in MKEngine.FORTIFIED_SITES and not eng._is_safe_fortified(p, k)

static func other_hero_at(eng, p: int, k: String) -> bool:
	for i in eng.s.players.size():
		if i != p and str(eng.P(i).pos) == k:
			return true
	return false

## Dijkstra (Dial buckets) from the hero position within `budget` move points.
## Fortified sites end the movement (assault); provocation paths are excluded.
static func reach(eng, p: int, budget: int) -> Dictionary:
	var start: String = eng.P(p).pos
	var dist = {start: 0}
	var prev = {}
	var buckets: Array = []
	buckets.resize(budget + 1)
	for i in budget + 1:
		buckets[i] = []
	buckets[0].append(start)
	for d in budget + 1:
		var bk: Array = buckets[d]
		var bi = 0
		while bi < bk.size():
			var cur: String = bk[bi]
			bi += 1
			if int(dist.get(cur, 999)) != d:
				continue
			if cur != start and is_assault_hex(eng, p, cur):
				continue
			for nk in MKHex.neighbors(cur):
				if eng._hex_blocked(p, nk) != "":
					continue
				var c: int = eng.move_cost(nk)
				if c >= 999:
					continue
				var nd: int = d + c
				if nd > budget:
					continue
				if provokes(eng, p, cur, nk):
					continue
				if not dist.has(nk) or nd < int(dist[nk]):
					dist[nk] = nd
					prev[nk] = cur
					buckets[nd].append(nk)
	return {"dist": dist, "prev": prev}

static func path_to(r: Dictionary, k: String) -> Array:
	var out: Array = []
	var cur = k
	var guard = 0
	while r.prev.has(cur) and guard < 100:
		out.push_front(cur)
		cur = r.prev[cur]
		guard += 1
	return out

## Distance map (move points) from a hex, ignoring the budget (for strategic estimates).
static func dist_map(eng, p: int, src: String, cap: int = 40) -> Dictionary:
	var dist = {src: 0}
	var buckets: Array = []
	buckets.resize(cap + 1)
	for i in cap + 1:
		buckets[i] = []
	buckets[0].append(src)
	for d in cap + 1:
		var bk: Array = buckets[d]
		var bi = 0
		while bi < bk.size():
			var cur: String = bk[bi]
			bi += 1
			if int(dist.get(cur, 999)) != d:
				continue
			for nk in MKHex.neighbors(cur):
				var h: Dictionary = eng.hex(nk)
				if h.is_empty():
					continue
				if h.rampage and not h.enemies.is_empty():
					continue
				var c: int = eng.terrain_cost(h.t, nk)
				if c >= 999:
					continue
				var nd: int = d + c
				if nd > cap:
					continue
				if not dist.has(nk) or nd < int(dist[nk]):
					dist[nk] = nd
					buckets[nd].append(nk)
	return dist

# ================================================================ exploration
static func slots_from(eng, p: int, pos: String) -> Array:
	var out: Array = []
	if eng.s.map.tile_deck.is_empty():
		return out
	var placed = {}
	for t in eng.s.map.tiles:
		placed[t.slot] = true
	var cand = {}
	for nk in [pos] + MKHex.neighbors(pos):
		for kk in MKHex.TILE_KEYS:
			cand[MKHex.key(MKHex.parse(nk) - MKHex.TILE_KEYS[kk])] = true
	var next_tile: String = eng.s.map.tile_deck[0]
	var next_core: bool = MKDB.tiles.get(next_tile, {}).get("kind", "") == "core"
	for c in cand:
		if placed.has(c) or not MKHex.in_shape(c, eng.s.map.shape):
			continue
		if eng.s.map.shape == "open" and not eng._open_cols_ok(c):
			continue
		var adj = false
		for hk in MKHex.tile_hexes(c):
			if MKHex.distance(hk, pos) <= 1:
				adj = true
				break
		if not adj:
			continue
		var n_adj = 0
		var touches_start = false
		for m in MKHex.macro_neighbors(c):
			if placed.has(m):
				n_adj += 1
				if m == "0,0":
					touches_start = true
		if next_core:
			if n_adj < 2:
				continue
			if eng.s.map.shape == "wedge" and eng._on_coast(c):
				continue
		elif n_adj < 2 and not touches_start and not (n_adj >= 1 and eng._is_coast(c)):
			continue
		out.append(c)
	out.sort()
	return out

static func cities_pending(eng) -> int:
	# cities still to reveal (scenario goal)
	var revealed = 0
	for k in eng.s.map.hex:
		if eng.s.map.hex[k].site == "city":
			revealed += 1
	return maxi(0, int(eng.s.scn.get("city", 0)) - revealed / 1)

static func explore_value(eng, p: int, level: int = 2) -> float:
	if eng.s.map.tile_deck.is_empty():
		return 0.0
	var v = 2.4
	var scn: Dictionary = eng.s.scn
	if int(scn.get("fame_per_tile", 0)) > 0:
		v += float(scn.fame_per_tile)
		# revealing the city ends the game: avoid if it is next and we still have time
		# the city tile is the last one of the tile deck (scenario setup: public information)
		if eng.s.map.tile_deck.size() == 1 and str(scn.get("end", "")) == "city_revealed":
			v = -2.0 if int(eng.s.round) < int(scn.rounds) else 1.0
	elif str(scn.get("end", "")) == "cities":
		var revealed = 0
		for k in eng.s.map.hex:
			if eng.s.map.hex[k].site == "city":
				revealed += 1
		var missing = int(scn.get("city", 0)) - revealed
		if missing > 0:
			v += 2.2 + 0.7 * float(int(eng.s.round)) + C.T("explore_bonus")
			if level >= 2:
				# the cities lie in the core tiles at the bottom of the tile deck: explore aggressively,
				# more so when the core tiles are next and when the game advances
				var core_next = 0
				for tid in eng.s.map.tile_deck:
					if MKDB.tiles.get(tid, {}).get("kind", "") == "core":
						core_next += 1
				var frac = float(core_next) / float(maxi(1, eng.s.map.tile_deck.size()))
				var lv_f = (1.0 if level >= 3 else 0.5) * C.T("explore_lv")
				# competitive: the cities (fame, leadership, early conquest) are a race - reveal them sooner
				var ec = C.T("explore_city") + (C.T("explore_comp") if eng.is_competitive() else 0.0)
				v += lv_f * (ec + 2.0 * frac + C.T("explore_r") * float(int(eng.s.round)) + 1.5 * float(missing - 1))
	return v

# ================================================================ power / feasibility
static var _atk_cache: Dictionary = {}
static func card_attack(id: String) -> float:
	if _atk_cache.has(id):
		return _atk_cache[id]
	var c: Dictionary = MKDB.card(id)
	var best = 1.0 if c.get("side", true) else 0.0
	for mode in ["basic", "powered"]:
		for b in C.parse(c.get(mode, []), {"day": true, "combat": true, "phase": "any"}):
			var t = 0.0
			for k in b.atk:
				t += float(b.atk[k]) * (1.15 if not str(k).begins_with("melee") else 1.0)
			var bl = 0.0
			for k2 in b.blk:
				bl += float(b.blk[k2])
			t = maxf(t, bl * 0.8)
			if mode == "powered":
				t *= 0.6
			best = maxf(best, t)
	_atk_cache[id] = best
	return best

static func power(eng, p: int) -> float:
	var pl: Dictionary = eng.P(p)
	var tot = 0.0
	var n = 0
	for iid in pl.deck + pl.hand + pl.discard + pl.play:
		n += 1
		if not eng.is_wound(iid):
			tot += card_attack(eng.card_id(iid))
	var avg = tot / float(maxi(1, n))
	var pw = avg * float(pl.hand_limit)
	for u in pl.units:
		if u.wounded:
			continue
		var best = 0.0
		for ab in eng.unit_def(u).get("abilities", []):
			for b in C.parse(ab.get("effect", []), {"day": true, "combat": true, "phase": "any"}):
				var t = 0.0
				for k in b.atk:
					t += float(b.atk[k])
				best = maxf(best, t)
		pw += best
	for c in C.BASIC:
		pw += 0.4 * float(pl.crystals.get(c, 0))
	return pw

static func feas(pw: float, req: float) -> float:
	if req <= 0.0:
		return 1.0
	return clampf((pw - 0.75 * req) / (0.6 * req) + 0.3, 0.0, 1.0)

static func models_req(models: Array) -> float:
	var r = 0.0
	for m in models:
		r += float(m.armor)
		var a = 0
		for at in m.atks:
			a += int(at.n) * (2 if m.swift else 1)
		r += 0.35 * float(a)
		if m.fort:
			r += 1.5
		r += 0.8 * float(m.resist.size())
	return r

# ================================================================ target models
static func site_models(eng, p: int, k: String, kind: String, full: bool) -> Array:
	## Returns a list of alternatives: [[weight, models]]
	var h: Dictionary = eng.hex(k)
	var city = ""
	if h.get("site", "") == "city" and h.has("city"):
		city = str(h.city.color)
	match kind:
		"assault":
			var ms: Array = []
			# a single face-down defender (keep / mage tower): average over the types of its colour
			if full and h.enemies.size() == 1 and not eng.s.enemies.get(h.enemies[0], {}).get("face_up", true):
				var inst0: Dictionary = eng.s.enemies.get(h.enemies[0], {})
				var alts0: Array = []
				var tot0 = 0.0
				for t0 in CB.color_types(eng, str(inst0.color)):
					var m0 = CB.model_type(eng, t0[0], true, city, false, str(h.enemies[0]))
					m0.site_def = true
					alts0.append([float(t0[1]), [m0]])
					tot0 += float(t0[1])
				for a0 in alts0:
					a0[0] = a0[0] / maxf(1.0, tot0)
				if not alts0.is_empty():
					return alts0
			for eid in h.enemies:
				var inst: Dictionary = eng.s.enemies.get(eid, {})
				if inst.is_empty():
					continue
				var tid = str(inst.type) if inst.get("face_up", false) else CB.typical_type(eng, str(inst.color))
				if tid == "":
					continue
				var m = CB.model_type(eng, tid, true, city, false, str(eid))
				m.site_def = true
				if inst.get("half_fame", false):
					m.fame = (int(m.fame) + 1) / 2
				ms.append(m)
			return [[1.0, ms]]
		"challenge":
			var ms2: Array = []
			for eid in h.enemies:
				var inst2: Dictionary = eng.s.enemies.get(eid, {})
				if inst2.is_empty():
					continue
				var m2 = CB.model_type(eng, str(inst2.type), false, "", true, str(eid))
				m2.site_def = false
				ms2.append(m2)
			return [[1.0, ms2]]
		"adventure":
			var st = str(h.get("site", ""))
			var colors: Array = []
			var known: Array = []
			match st:
				"dungeon":
					colors = ["brown"]
				"tomb":
					colors = ["red"]
				"monster_den":
					if h.enemies.is_empty():
						colors = ["brown"]
				"spawning_grounds":
					if h.enemies.is_empty():
						colors = ["brown", "brown"]
				"ruins":
					if h.enemies.is_empty():
						var rd: Dictionary = MKDB.ruins.get(str(h.get("ruins", "")), {})
						for c in rd.get("enemies", []):
							colors.append(MKDB._color(c))
			for eid in h.enemies:
				var inst3: Dictionary = eng.s.enemies.get(eid, {})
				if not inst3.is_empty():
					var m3 = CB.model_type(eng, str(inst3.type), false, "", false, "site:" + str(eid))
					m3.eid = str(eid)
					m3.site_def = true
					known.append(m3)
			if colors.size() == 1 and full:
				var alts: Array = []
				var tot = 0.0
				for t in CB.color_types(eng, colors[0]):
					var m4 = CB.model_type(eng, t[0], false, "", false, "site:new0")
					m4.site_def = true
					alts.append([float(t[1]), known + [m4]])
					tot += float(t[1])
				for a in alts:
					a[0] = a[0] / maxf(1.0, tot)
				return alts
			var ms3: Array = known.duplicate()
			var i = 0
			for c in colors:
				var tid2 = CB.typical_type(eng, c)
				if tid2 != "":
					var m5 = CB.model_type(eng, tid2, false, "", false, "site:new%d" % i)
					m5.site_def = true
					ms3.append(m5)
				i += 1
			return [[1.0, ms3]]
	return []

# ================================================================ items for movement / influence
static func move_items(eng, p: int, ctx: Dictionary, relevance: String) -> Array:
	var items: Array = []
	var pl: Dictionary = eng.P(p)
	var rf: float = ctx.rf
	var mp: Dictionary = ctx.mp
	var octx = C.base_ctx(eng, p, false, "")
	var cctx = C.base_ctx(eng, p, true, "any")
	for iid in pl.hand:
		if eng.is_wound(iid):
			continue
		var opts: Array = []
		for o in C.card_opts(eng, p, iid, octx):
			var mv = int(o.b.move) + int(o.b.terr)
			if mv <= 0 or o.mode == "side" and o.act.side != "move":
				continue
			if int(o.b.disc) > 0:
				continue
			var mc = C.mana_cost(mp, o.needs)
			if mc < 0.0:
				continue
			o.c = float(o.c) + mc
			o["v"] = mv
			opts.append(o)
		if opts.is_empty():
			continue
		var rel = 0.0
		if relevance == "fight":
			rel = 0.35 * card_attack(eng.card_id(iid))
		elif relevance == "inf":
			var bi = 0
			for o2 in C.card_opts(eng, p, iid, octx):
				bi = maxi(bi, int(o2.b.inf))
			rel = 0.25 * float(bi)
		items.append({"kind": "card", "key": iid, "val": C.card_value(eng, p, iid, rf) + rel * rf, "opts": opts})
	for u in pl.units:
		if not u.ready or u.wounded:
			continue
		var uo: Array = []
		for o3 in C.unit_opts(eng, p, u, octx):
			var mv3 = int(o3.b.move) + int(o3.b.terr)
			if mv3 <= 0:
				continue
			var mc3 = C.mana_cost(mp, o3.needs)
			if mc3 < 0.0:
				continue
			o3.c = float(o3.c) + mc3
			o3["v"] = mv3
			uo.append(o3)
		if not uo.is_empty():
			items.append({"kind": "unit", "key": int(u.uid), "val": C.unit_use_cost(eng, p, u, rf) + (0.6 if relevance == "fight" else 0.0), "opts": uo})
	for sk in pl.skills:
		var d: Dictionary = MKDB.skills.get(sk.id, {})
		var usage = str(d.get("usage", "turn"))
		if usage == "passive" or (usage == "turn" and sk.used_turn) or (usage in ["round", "interactive"] and sk.used_round):
			continue
		var so: Array = []
		for o4 in C.skill_opts(eng, p, sk, octx):
			var mv4 = int(o4.b.move)
			if mv4 > 0:
				o4["v"] = mv4
				so.append(o4)
		if not so.is_empty():
			items.append({"kind": "skill", "key": str(sk.id), "val": 0.1 if usage == "turn" else 0.5, "opts": so})
	return items

static func inf_items(eng, p: int, ctx: Dictionary, exclude: Dictionary) -> Array:
	var items: Array = []
	var pl: Dictionary = eng.P(p)
	var rf: float = ctx.rf
	var mp: Dictionary = ctx.mp
	var octx = C.base_ctx(eng, p, false, "")
	for iid in pl.hand:
		if eng.is_wound(iid) or exclude.has(iid):
			continue
		var opts: Array = []
		for o in C.card_opts(eng, p, iid, octx):
			var iv = int(o.b.inf)
			if iv <= 0:
				continue
			if o.mode == "side" and o.act.side != "influence":
				continue
			var mc = C.mana_cost(mp, o.needs)
			if mc < 0.0:
				continue
			o.c = float(o.c) + mc + C.rep_cost(int(pl.rep), int(o.b.rep)) + 0.9 * float(o.b.disc)
			o["v"] = iv
			opts.append(o)
		if not opts.is_empty():
			items.append({"kind": "card", "key": iid, "val": C.card_value(eng, p, iid, rf), "opts": opts})
	for u in pl.units:
		if not u.ready or u.wounded or exclude.has("u%d" % int(u.uid)):
			continue
		var uo: Array = []
		for o3 in C.unit_opts(eng, p, u, octx):
			if int(o3.b.inf) > 0:
				var mc3 = C.mana_cost(mp, o3.needs)
				if mc3 < 0.0:
					continue
				o3.c = float(o3.c) + mc3
				o3["v"] = int(o3.b.inf)
				uo.append(o3)
		if not uo.is_empty():
			items.append({"kind": "unit", "key": int(u.uid), "val": C.unit_use_cost(eng, p, u, rf), "opts": uo})
	for sk in pl.skills:
		var d: Dictionary = MKDB.skills.get(sk.id, {})
		var usage = str(d.get("usage", "turn"))
		if usage == "passive" or (usage == "turn" and sk.used_turn) or (usage in ["round", "interactive"] and sk.used_round):
			continue
		var so: Array = []
		for o4 in C.skill_opts(eng, p, sk, octx):
			if int(o4.b.inf) > 0:
				o4["v"] = int(o4.b.inf)
				so.append(o4)
		if not so.is_empty():
			items.append({"kind": "skill", "key": str(sk.id), "val": 0.1 if usage == "turn" else 0.5, "opts": so})
	return items

static func cover(items: Array, need: int) -> Dictionary:
	var vals: Array = []
	for it in items:
		var vv: Array = []
		for o in it.opts:
			vv.append(int(o.get("v", 0)))
		vals.append(vv)
	return CB.dp_cover(items, {}, need, vals)

static func picks_keys(items: Array, picks: Array) -> Dictionary:
	var out = {}
	for pk in picks:
		var it: Dictionary = items[pk[0]]
		if it.kind == "card":
			out[it.key] = true
		elif it.kind == "unit":
			out["u%d" % int(it.key)] = true
	return out

# ================================================================ strategic position value
static func strategic(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Array:
	var sig = "%d|%d|%d|%d|%d" % [int(eng.s.round), int(eng.P(p).turns), eng.s.map.tiles.size(), int(eng.P(p).fame), eng.P(p).units.size()]
	if mem.get("strat_sig", "") == sig:
		return mem.strat
	var pw = power(eng, p)
	var targets: Array = []
	var pl: Dictionary = eng.P(p)
	var wounds = 0
	for iid in pl.hand + pl.discard + pl.deck:
		if eng.is_wound(iid):
			wounds += 1
	var cmd_free: int = eng.command_free(p)
	var mode = str(eng.s.scn.get("mode", ""))
	var inf_pot = -1.0
	var siege_k = siege_target(eng, p, ctx, mem)
	for k in eng.s.map.hex:
		var h: Dictionary = eng.s.map.hex[k]
		var st = str(h.site)
		var v = 0.0
		var models: Array = []
		match st:
			"keep":
				if not eng._is_safe_fortified(p, k):
					var alts = site_models(eng, p, k, "assault", false)
					if not alts.is_empty():
						models = alts[0][1]
					v = 6.0 + 4.0 * float(models.size()) if not models.is_empty() else 5.0
				elif int(h.owner) == p and cmd_free > 0:
					v = 2.0
			"mage_tower":
				if not h.conquered:
					var alts2 = site_models(eng, p, k, "assault", false)
					if not alts2.is_empty():
						models = alts2[0][1]
					v = 13.0
				elif cmd_free > 0 or true:
					v = 1.5
			"city":
				if not h.conquered and eng.s.scn.get("cities_enterable", true):
					var alts3 = site_models(eng, p, k, "assault", false)
					if not alts3.is_empty():
						models = alts3[0][1]
					v = 18.0 + (14.0 if mode in ["solo", "coop"] else 6.0)
					if int(ctx.level) >= 2 and not models.is_empty():
						# multi-turn siege: defeated defenders stay defeated, so the feasibility is judged
						# on the weakest defender (plus the threat of the others), not the whole garrison
						var cs = city_siege(eng, p, k, models, pw, int(ctx.level), ctx, mem)
						if k == siege_k:
							cs = maxf(cs, C.T("siege_v"))
						targets.append({"k": k, "v": cs, "city": true})
						continue
			"dungeon", "tomb", "monster_den", "spawning_grounds", "ruins":
				if st == "ruins" and str(h.get("ruins", "")) == "":
					continue
				if st in ["monster_den", "spawning_grounds"] and h.conquered:
					continue
				var alts4 = site_models(eng, p, k, "adventure", false)
				if not alts4.is_empty():
					models = alts4[0][1]
				var fm = 0.0
				for m in models:
					fm += float(m.fame)
				v = fm + CB.site_bonus(eng, p, st, k)
				if st in ["dungeon", "tomb"] and h.conquered:
					v = fm
				if st == "ruins":
					var rd: Dictionary = MKDB.ruins.get(str(h.ruins), {})
					if rd.get("kind", "") == "altar":
						v = 5.0
						models = []
			"village":
				v = 1.5 + 1.0 * float(mini(wounds, 3)) + (1.5 if cmd_free > 0 else 0.0)
			"monastery":
				if not h.burned:
					v = 2.0 + 0.8 * float(mini(wounds, 3)) + (1.5 if cmd_free > 0 else 0.0) + (1.0 if not eng.s.offers.monastery.is_empty() else 0.0)
			"glade":
				v = 0.8 + 0.8 * float(mini(wounds, 2))
		if int(ctx.level) >= 3 and st in ["village", "monastery", "keep", "mage_tower", "city"] and not (h.rampage and not h.enemies.is_empty()):
			# shops: the best purchase we can probably afford on a later turn (units first of all)
			var site_i = _interaction_site_at(eng, p, k)
			if site_i != "":
				if inf_pot < 0.0:
					inf_pot = influence_potential(eng, p)
				var shop = 0.0
				for b in _purchases(eng, p, ctx, k, site_i):
					var aff = 1.0 if float(b.cost) <= inf_pot else clampf(1.0 - (float(b.cost) - inf_pot) / 4.0, 0.0, 1.0)
					shop = maxf(shop, (float(b.value) - 0.3 * float(b.cost)) * aff)
				v = maxf(v, shop * C.T("shop_w"))
		if h.rampage and not h.enemies.is_empty():
			var alts5 = site_models(eng, p, k, "challenge", false)
			if not alts5.is_empty():
				models = alts5[0][1]
			var fm2 = 0.0
			for m2 in models:
				fm2 += float(m2.fame) + 0.6 * float(m2.rep)
			v = fm2
		if v <= 0.0:
			continue
		if not models.is_empty():
			var req = models_req(models)
			if st in ["dungeon", "tomb"]:
				req += 2.0
			v *= feas(pw, req)
		if v > 0.4:
			targets.append({"k": k, "v": v})
	# exploration frontier
	var ev = explore_value(eng, p, int(ctx.level))
	if int(ctx.level) >= 2:
		# scarcity: with few worthwhile targets around, new tiles are worth more
		var bloc = 0.0
		for tg0 in targets:
			var dh = float(MKHex.distance(str(tg0.k), str(pl.pos))) * 2.6
			bloc = maxf(bloc, float(tg0.v) * pow(C.T("pos_decay"), dh / 5.0))
		var scar = clampf(1.0 - bloc / C.T("scar_ref"), 0.0, 1.0)
		mem["scarcity"] = scar
		if not eng.s.map.tile_deck.is_empty():
			ev += C.T("explore_scar") * scar
	if ev > 0.0:
		var placed = {}
		for t in eng.s.map.tiles:
			placed[t.slot] = true
		var seen = {}
		for t in eng.s.map.tiles:
			for m in MKHex.macro_neighbors(t.slot):
				if placed.has(m) or seen.has(m) or not MKHex.in_shape(m, eng.s.map.shape):
					continue
				if eng.s.map.shape == "open" and not eng._open_cols_ok(m):
					continue
				seen[m] = true
				# entry hexes of the existing tile next to that slot
				var best_k = ""
				var bd = 99
				for hk in MKHex.tile_hexes(t.slot):
					for hk2 in MKHex.tile_hexes(m):
						if MKHex.adjacent(hk, hk2) and MKHex.distance(hk, str(pl.pos)) < bd:
							var hh: Dictionary = eng.hex(hk)
							if not hh.is_empty() and eng.terrain_cost(hh.t, hk) < 999:
								bd = MKHex.distance(hk, str(pl.pos))
								best_k = hk
				if best_k != "":
					targets.append({"k": best_k, "v": ev * 0.9})
	targets.sort_custom(func(a, b): return a.v > b.v)
	if targets.size() > 9:
		targets = targets.slice(0, 9)
	for tg in targets:
		tg["dist"] = dist_map(eng, p, tg.k, 36)
	# several heroes (level >= 2): leave targets to a hero that is clearly closer (coop: split the work;
	# competitive: it will probably be gone) - cities stay shared (siege by the whole team)
	if int(ctx.level) >= 2 and eng.s.players.size() > 1:
		var here0: String = pl.pos
		for tg in targets:
			if tg.get("city", false):
				continue
			var mine = tg.dist.get(here0, null)
			if mine == null:
				continue
			for j in eng.s.players.size():
				if j == p:
					continue
				var dj = tg.dist.get(str(eng.P(j).pos), null)
				if mode == "coop" and int(eng.P(j).fame) > int(pl.fame) + 4:
					continue   # coop: the weaker hero (team score = lowest fame) does not yield
				if dj != null and int(dj) + 3 <= int(mine):
					tg.v = float(tg.v) * (C.T("share_coop") if mode == "coop" else C.T("share_comp"))
					break
	mem["strat_sig"] = sig
	mem["strat"] = targets
	return targets

## Siege mode (Difficile, solo/coop): from a given round (or earlier when strong enough) the hero commits
## to one revealed city - the one with the fewest defenders left, then the closest - and keeps returning
## to assault it. Stored in mem.siege ("" = none).
static func siege_target(eng, p: int, ctx: Dictionary, mem: Dictionary) -> String:
	mem["siege"] = ""
	var lvl = int(ctx.level)
	var mode = str(eng.s.scn.get("mode", ""))
	if lvl < 2 or (lvl < 3 and not mode in ["solo", "coop"]):
		return ""
	if not eng.s.scn.get("cities_enterable", true):
		return ""
	var pl: Dictionary = eng.P(p)
	var best = ""
	var bs = -BIG
	for k in eng.s.map.hex:
		var h: Dictionary = eng.s.map.hex[k]
		if h.site != "city" or h.conquered:
			continue
		var alive = h.enemies.size()
		var shields = h.get("city", {}).get("shields", []).size()
		var sc = -4.0 * float(alive) - 0.25 * float(MKHex.distance(k, str(pl.pos))) + 1.5 * float(shields)
		if sc > bs:
			bs = sc
			best = k
	if best == "":
		return ""
	# commit only when a typical assault already defeats someone at an acceptable cost (later in the game
	# a higher cost is accepted); otherwise the hero keeps building up instead of camping by the walls
	var alts = site_models(eng, p, best, "assault", false)
	if alts.is_empty() or alts[0][1].is_empty():
		return ""
	var est = siege_estimate(eng, p, best, alts[0][1], ctx, mem)
	var thr = C.T("siege_early") if int(eng.s.round) < int(C.T("siege_round")) else C.T("siege_thr")
	if lvl < 3:
		thr = minf(C.T("siege_early"), thr + C.T("siege_l2"))   # Normale: a more cautious siege
	if not mode in ["solo", "coop"]:
		thr = maxf(thr, C.T("siege_comp"))   # competitive: the city is only worth its fame and leadership
	if int(est.kills) < 1 or float(est.score) <= thr:
		return ""
	mem["siege"] = best
	return best

## Influence a typical hand can muster (cards' best influence option, rep bonus).
static func influence_potential(eng, p: int) -> float:
	var pl: Dictionary = eng.P(p)
	var octx = C.base_ctx(eng, p, false, "")
	var tot = 0.0
	var n = 0
	var w = 0
	for iid in pl.deck + pl.hand + pl.discard + pl.play:
		if eng.is_wound(iid):
			w += 1
			continue
		n += 1
		var best = 0.0
		for o in C.card_opts(eng, p, iid, octx):
			var iv = float(o.b.inf)
			if o.mode == "powered":
				iv *= 0.75
			best = maxf(best, iv)
		tot += best
	if n == 0:
		return 0.0
	var hand = float(pl.hand_limit) * float(n) / float(n + w)
	return tot / float(n) * hand * 0.85 + float(eng.rep_bonus(p))

## A "typical" hand for planning future fights: cards spread over the strength ranking of the whole deck,
## minus the expected wounds. Returns an array of iids.
static func typical_hand(eng, p: int) -> Array:
	var pl: Dictionary = eng.P(p)
	var good: Array = []
	var wounds = 0
	for iid in pl.deck + pl.hand + pl.discard + pl.play:
		if eng.is_wound(iid):
			wounds += 1
		else:
			good.append([card_attack(eng.card_id(iid)) + 0.01 * C.card_base_value(eng.card_id(iid)), str(iid)])
	if good.is_empty():
		return []
	good.sort_custom(func(a, b): return a[0] > b[0] or (a[0] == b[0] and a[1] < b[1]))
	var hl: int = int(pl.hand_limit)
	var tot = float(good.size() + wounds)
	var h = clampi(int(round(float(hl) * float(good.size()) / tot)), 1, hl)
	var out: Array = []
	for i in h:
		var idx = int(floor((float(i) + 0.4) * float(good.size()) * C.T("hand_q") / float(h)))
		out.append(good[clampi(idx, 0, good.size() - 1)][1])
	return out

## Expected result of one assault on city k with a typical hand, all non-wounded units ready, one die:
## {score, kills, alive}. Cached per turn in mem.
static func siege_estimate(eng, p: int, k: String, models: Array, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var sig = "%s|%d|%d|%d|%d|%d|%d" % [k, int(eng.s.round), int(pl.fame), pl.units.size(), (pl.deck + pl.hand + pl.discard + pl.play).size(), models.size(), int(pl.level)]
	var cache: Dictionary = mem.get("siege_cache", {})
	if cache.has(sig):
		return cache[sig]
	var hand = typical_hand(eng, p)
	var mp = C.mana_pool(eng, p)
	mp.tok = {}
	mp.dice = ["red", "blue", "green", "white"]
	mp.dice_left = 1
	var ctx2: Dictionary = ctx.duplicate()
	ctx2["mp"] = mp
	ctx2["rf"] = 1.0
	ctx2["cap"] = 8
	ctx2["deadline"] = Time.get_ticks_usec() + 15000
	var items = CB.gather(eng, p, ctx2, {}, true, false, hand, true)
	var cfg = CB.base_cfg(eng, p, ctx2)
	cfg.wounds_so_far = 0
	cfg.hand_cards = hand.size()
	cfg.units = []
	for u in pl.units:
		if not u.wounded:
			cfg.units.append({"uid": int(u.uid), "armor": MKCombat.unit_armor(eng, p, u), "resist": MKCombat.unit_resists(eng, p, u),
				"worth": C.unit_worth(str(u.id))})
	var bonus = CB.site_bonus(eng, p, "city", k)
	var defs: Array = []
	for m in models:
		defs.append(m.eid)
	cfg.site_bonus = bonus
	cfg.defenders_alive = defs
	cfg["progress"] = CB.progress_frac(eng, "city", int(ctx.level)) * bonus / float(maxi(1, defs.size()))
	var pln = CB.plan_checked(items, models, "ranged", cfg, mp)
	var res = {"score": float(pln.get("score", -99.0)), "kills": pln.get("kills", []).size(), "alive": models.size()}
	if OS.get_environment("AI_PLAN") == "4":
		var ut: Array = []
		for u in pl.units:
			ut.append(str(u.id) + ("(w)" if u.wounded else ""))
		var mt: Array = []
		for m in models:
			mt.append("%s a%d" % [str(m.eid), int(m.armor)])
		printerr("   siege est %s: %s hand=%s units=%s defs=%s blocks=%d" % [k, str(res), ",".join(hand), ",".join(ut), ",".join(mt), pln.get("blocks", []).size()])
	if cache.size() > 16:
		cache.clear()
	cache[sig] = res
	mem["siege_cache"] = cache
	return res

## Strategic value of besieging a city (level >= 2): conquest bonus scaled by the feasibility of
## defeating at least its weakest defender in one assault (the siege can take several turns).
static func city_siege(eng, p: int, k: String, models: Array, pw: float, level: int, ctx: Dictionary = {}, mem: Dictionary = {}) -> float:
	var bonus = CB.site_bonus(eng, p, "city", k)
	if level >= 2 and C.T("siege_sim") > 0.5:
		var est = siege_estimate(eng, p, k, models, ctx, mem)
		var fame0 = 0.0
		for m0 in models:
			fame0 += float(m0.fame)
		var kills = int(est.kills) if float(est.score) > C.T("siege_thr") else 0
		# turns of the game left (about 6 per round) vs assaults needed (each followed by recovery)
		var left_turns = float(int(eng.s.scn.get("rounds", 6)) - int(eng.s.round)) * 5.0 + 3.0
		var need = 99.0 if kills <= 0 else 2.2 * ceil(float(models.size()) / float(kills))
		var f = clampf(left_turns / maxf(1.0, need), 0.0, 1.0)
		if kills >= models.size() and float(est.score) > 0.0:
			f = 1.0
		f = maxf(f, 0.25 * clampf(1.0 + float(est.score) / 20.0, 0.0, 1.0))
		mem["siege_dbg"] = "%s est=%.1f kills=%d/%d f=%.2f" % [k, float(est.score), int(est.kills), models.size(), f]
		return (bonus + 0.6 * fame0) * (0.1 + 0.9 * f)
	var fame = 0.0
	var atk_tot = 0.0
	for m in models:
		fame += float(m.fame)
		for at in m.atks:
			atk_tot += float(at.n) * (2.0 if m.brutal else 1.0)
	var best1 = BIG
	for m in models:
		var own = 0.0
		for at in m.atks:
			own += float(at.n) * (2.0 if m.brutal else 1.0)
		var r1 = models_req([m]) + 0.3 * (atk_tot - own)
		best1 = minf(best1, r1)
	var f1 = feas(pw, best1)
	var fall = feas(pw, models_req(models))
	var f = maxf(fall, C.T("siege_f1") * f1)
	var v = (bonus + 0.6 * fame) * (0.12 + 0.88 * f)
	if level < 3:
		v *= 0.8
	return v

static func pos_value(targets: Array, k: String, exclude: String = "") -> float:
	var best = 0.0
	for tg in targets:
		if exclude != "" and str(tg.k) == exclude:
			continue
		var d = tg.dist.get(k, null)
		if d == null:
			continue
		var f = pow(C.T("pos_decay"), float(d) / 5.0)
		best = maxf(best, float(tg.v) * f * float(tg.get("w", 1.0)))
	return best * C.T("pos_scale")

## Long-term goal: the strategic target with the best value/distance ratio, kept across turns (hysteresis).
static func choose_goal(eng, p: int, strat: Array, mem: Dictionary) -> void:
	var here: String = eng.P(p).pos
	var prev: String = str(mem.get("goal", ""))
	var best = null
	var bs = -1.0
	for tg in strat:
		var d = tg.dist.get(here, null)
		if d == null:
			continue
		var sc = float(tg.v) / (1.0 + float(d) / 5.0)
		if str(tg.k) == prev:
			sc *= 1.35
		if sc > bs:
			bs = sc
			best = tg
	var tf: Dictionary = mem.get("tfail", {})
	for tg in strat:
		# a city siege may need several attempts: its value decays much more slowly after failures
		var fb = 0.88 if tg.get("city", false) else 0.6
		tg["w"] = (1.0 if best != null and tg == best else C.T("goal_other")) * pow(fb, float(tf.get(str(tg.k), 0)))
	if best != null:
		mem["goal"] = str(best.k)

## Targets that were in reach but not worth attacking lose strategic value (avoids camping next to them).
static func update_fails(eng, p: int, missions: Array, mem: Dictionary) -> void:
	var tid := str(mem.get("tid", ""))
	if mem.get("tfail_tid", "") == tid:
		return
	mem["tfail_tid"] = tid
	var bestv := {}
	for m in missions:
		if not m.kind in ["assault", "adventure", "challenge", "interact", "altar"]:
			continue
		var k := str(m.get("target", m.hex))
		bestv[k] = maxf(float(bestv.get(k, -99.0)), float(m.value))
	var tf: Dictionary = mem.get("tfail", {})
	for k in bestv:
		if float(bestv[k]) < 1.0:
			tf[k] = int(tf.get(k, 0)) + 1
		else:
			tf[k] = 0
	mem["tfail"] = tf

# ================================================================ end-of-turn site bonus
static func end_bonus(eng, p: int, k: String) -> float:
	var h: Dictionary = eng.hex(k)
	if h.is_empty():
		return 0.0
	var pl: Dictionary = eng.P(p)
	var v = 0.0
	if h.get("site", "") == "glade":
		for iid in pl.hand + pl.discard:
			if eng.is_wound(iid):
				v += 2.0
				break
	if str(h.get("mine", "")) != "":
		if int(pl.crystals.get(str(h.mine), 0)) < 3:
			v += 0.9
	return v

# ================================================================ mission planning
## Returns the best mission: {kind, hex, path, cost, value, ...}
static func plan(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var t: Dictionary = eng.s.turn
	var level: int = int(ctx.level)
	var rng: RandomNumberGenerator = ctx.rng
	var noise: float = C.T("noise3") if level >= 3 else (0.2 if level == 2 else 0.4)
	var _t0 = Time.get_ticks_usec()
	var strat = strategic(eng, p, ctx, mem)
	choose_goal(eng, p, strat, mem)
	var _t1 = Time.get_ticks_usec()
	var can_move: bool = eng.can_still_move(p)
	var action_free: bool = MKSites._action_free(eng, p) == ""
	var missions: Array = []
	var here: String = pl.pos
	var pos_here = pos_value(strat, here)
	# movement budget
	var mitems_plain = move_items(eng, p, ctx, "")
	var max_move = int(t.pool.move)
	if can_move:
		for it in mitems_plain:
			var bm = 0
			for o in it.opts:
				bm = maxi(bm, int(o.v))
			max_move += bm
	max_move = mini(max_move, 24)
	var r = reach(eng, p, max_move) if can_move else {"dist": {here: 0}, "prev": {}}
	var mitems_fight = move_items(eng, p, ctx, "fight") if can_move else []
	var mitems_inf = move_items(eng, p, ctx, "inf") if can_move else []
	var last: Dictionary = mem.get("last_mission", {})
	# ---- idle / end turn here (if nothing was played yet, a card must be discarded anyway)
	var credit = 0.0
	if eng.card_rule_open(p) and eng.has_non_wound(p):
		credit = BIG
		for iid in pl.hand:
			if not eng.is_wound(iid):
				credit = minf(credit, C.card_value(eng, p, iid, ctx.rf))
	var idle_pen = C.T("idle_pen") * (1.0 + 0.5 * float(ctx.get("idle_n", 0))) if not mem.get("productive", false) else 0.0
	missions.append({"kind": "end", "hex": here, "value": pos_here + end_bonus(eng, p, here) - credit - idle_pen, "move": 0})
	# ---- rest
	if eng.check({"t": "rest"}) == "":
		var w = 0
		var nw = 0
		for iid in pl.hand:
			if eng.is_wound(iid):
				w += 1
			else:
				nw += 1
		var rv = -1.0 + 0.85 * float(w) - (0.2 if nw > 0 else 0.0)
		if w > 0 and nw <= 1:
			rv += 1.2
		if w == 0:
			rv = -3.0
		rv += C.T("rest_bias")
		missions.append({"kind": "rest", "hex": here, "value": rv + pos_here, "move": 0})
	# ---- relocation (end the turn elsewhere)
	if can_move:
		var cands: Array = []
		for k in r.dist:
			if k == here or other_hero_at(eng, p, k) or is_assault_hex(eng, p, k):
				continue
			if not eng._is_safe(p, k):
				continue
			cands.append([pos_value(strat, k) + end_bonus(eng, p, k), k])
		cands.sort_custom(func(a, b): return a[0] > b[0])
		for i in mini(4, cands.size()):
			var k2: String = cands[i][1]
			var need = int(r.dist[k2]) - int(t.pool.move)
			var mpl = _move_plan(mitems_plain, need)
			if mpl.is_empty():
				continue
			missions.append({"kind": "relocate", "hex": k2, "value": float(cands[i][0]) - float(mpl.cost) - idle_pen, "move": int(r.dist[k2]), "move_acts": mpl.acts})
	# ---- per-hex missions
	var _t2 = Time.get_ticks_usec()
	var _tf = 0
	var deadline: int = int(ctx.deadline)
	var fights = 0
	for k in r.dist:
		var h: Dictionary = eng.hex(k)
		if h.is_empty():
			continue
		var d = int(r.dist[k])
		var st = str(h.get("site", ""))
		var late = Time.get_ticks_usec() > deadline
		# assault
		if action_free and k != here and is_assault_hex(eng, p, k) and not late:
			if st == "city" and not eng.s.scn.get("cities_enterable", true):
				continue
			var _tt = Time.get_ticks_usec()
			var m = _fight_mission(eng, p, ctx, k, "assault", d, mitems_fight, strat, "", mem)
			_tf += Time.get_ticks_usec() - _tt
			if not m.is_empty():
				missions.append(m)
				fights += 1
			continue
		if other_hero_at(eng, p, k) and k != here:
			pass
		# adventure sites
		if action_free and st in MKEngine.ADVENTURE_SITES and not late:
			var ok = true
			if st in ["monster_den", "spawning_grounds"] and h.conquered:
				ok = false
			if st == "ruins":
				var rid = str(h.get("ruins", ""))
				if rid == "":
					ok = false
				elif MKDB.ruins.get(rid, {}).get("kind", "") == "altar":
					ok = false
					var am = _altar_mission(eng, p, ctx, k, d, mitems_plain, strat)
					if not am.is_empty():
						missions.append(am)
			if ok:
				var _tt2 = Time.get_ticks_usec()
				var m2 = _fight_mission(eng, p, ctx, k, "adventure", d, mitems_fight, strat, "", mem)
				_tf += Time.get_ticks_usec() - _tt2
				if not m2.is_empty():
					missions.append(m2)
					fights += 1
		# challenge rampaging enemies from here
		if action_free and not late and not is_assault_hex(eng, p, k) and (k == here or not other_hero_at(eng, p, k)):
			for nk in MKHex.neighbors(k):
				var nh: Dictionary = eng.hex(nk)
				if nh.is_empty() or not nh.rampage or nh.enemies.is_empty():
					continue
				var _tt3 = Time.get_ticks_usec()
				var m3 = _fight_mission(eng, p, ctx, nk, "challenge", d, mitems_fight, strat, k, mem)
				_tf += Time.get_ticks_usec() - _tt3
				if not m3.is_empty():
					missions.append(m3)
					fights += 1
		# interaction
		if k == here or not other_hero_at(eng, p, k):
			var im = _interact_mission(eng, p, ctx, k, d, mitems_inf, strat)
			if not im.is_empty():
				missions.append(im)
		# exploration
		if can_move and not eng.s.map.tile_deck.is_empty():
			var slots = slots_from(eng, p, k)
			if not slots.is_empty() and (k == here or not other_hero_at(eng, p, k) or true):
				var ev = explore_value(eng, p, level)
				if level >= 2:
					ev += C.T("explore_scar") * float(mem.get("scarcity", 0.0))
				if ev > 0.0:
					var need2 = d + eng.explore_cost(p) - int(t.pool.move)
					var mpl2 = _move_plan(mitems_plain, need2)
					if not mpl2.is_empty():
						missions.append({"kind": "explore", "hex": k, "slot": _best_slot(eng, slots, strat), "value": ev - float(mpl2.cost) + pos_value(strat, k),
							"move": d + eng.explore_cost(p), "move_acts": mpl2.acts})
	update_fails(eng, p, missions, mem)
	if OS.get_environment("AI_PLAN") != "":
		var ms2 = missions.duplicate()
		ms2.sort_custom(func(a, b): return float(a.value) > float(b.value))
		var txt = []
		for i in mini(8, ms2.size()):
			txt.append("%s@%s=%.2f" % [ms2[i].kind, ms2[i].hex, float(ms2[i].value)])
		var hnd: Array = []
		for iid in pl.hand:
			hnd.append(str(iid).split("#")[0])
		printerr("  missions[r%d t%d pos %s mv%d f%d u%d deck%d hand=%s]: %s" % [int(eng.s.round), int(pl.turns), here, max_move, int(pl.fame), pl.units.size(), pl.deck.size(), ",".join(hnd), ", ".join(txt)])
		if OS.get_environment("AI_PLAN") == "2":
			var st2 = []
			for tg in strat:
				st2.append("%s v%.1f w%.2f d%s" % [tg.k, float(tg.v), float(tg.get("w", 1.0)), str(tg.dist.get(here, "-"))])
			printerr("     strat: ", "; ".join(st2), "  siege: ", str(mem.get("siege_dbg", "")))
	if OS.get_environment("AI_PLAN") == "5" and int(mem.get("n", 0)) <= 1:
		var cs: Array = []
		for tg in strat:
			if tg.get("city", false):
				cs.append("%s v%.1f w%.2f d%s" % [tg.k, float(tg.v), float(tg.get("w", 1.0)), str(tg.dist.get(here, "-"))])
		var ms3 = missions.duplicate()
		ms3.sort_custom(func(a, b): return float(a.value) > float(b.value))
		var top: Array = []
		for i in mini(3, ms3.size()):
			top.append("%s@%s=%.1f" % [ms3[i].kind, ms3[i].hex, float(ms3[i].value)])
		printerr("T r%d p%d f%d u%d pos %s goal %s cities[%s] %s | %s" % [int(eng.s.round), p, int(pl.fame), pl.units.size(), here, str(mem.get("goal", "")), "; ".join(cs), str(mem.get("siege_dbg", "")), ", ".join(top)])
	# pick
	if OS.get_environment("AI_DEBUG") != "" and Time.get_ticks_usec() - _t0 > 150000:
		printerr("  plan: strat %d ms, pre %d ms, hexes %d ms (fights %d, %d ms) n=%d" % [(_t1 - _t0) / 1000, (_t2 - _t1) / 1000, (Time.get_ticks_usec() - _t2) / 1000, fights, _tf / 1000, r.dist.size()])
	var best = {}
	var bv = -BIG
	for m in missions:
		var v = float(m.value)
		if noise > 0.0:
			v += rng.randf_range(-noise, noise) * maxf(1.0, absf(v))
		if not last.is_empty() and str(last.get("kind", "")) == str(m.kind) and str(last.get("hex", "")) == str(m.hex):
			v += 0.8
		if v > bv:
			bv = v
			best = m
	if not best.is_empty() and best.kind != "end" and best.kind != "rest":
		if best.hex != here:
			best["path"] = path_to(r, best.hex)
		else:
			best["path"] = []
	return best

static func _best_slot(eng, slots: Array, strat: Array) -> String:
	return slots[0]

## Move cards to reach `need` points: {cost, acts} (largest move first) or {} if impossible.
static func _move_plan(items: Array, need: int) -> Dictionary:
	if need <= 0:
		return {"cost": 0.0, "acts": []}
	var res = cover(items, need)
	if res.is_empty():
		return {}
	var arr: Array = []
	for pk in res.picks:
		var o: Dictionary = items[pk[0]].opts[pk[1]]
		arr.append([int(o.v), o.act])
	arr.sort_custom(func(a, b): return a[0] > b[0])
	var acts: Array = []
	for x in arr:
		acts.append(x[1])
	return {"cost": float(res.cost), "acts": acts}

static func _move_cost(items: Array, need: int) -> float:
	if need <= 0:
		return 0.0
	var res = cover(items, need)
	if res.is_empty():
		return -1.0
	return float(res.cost)

static func _fight_mission(eng, p: int, ctx: Dictionary, k: String, kind: String, d: int, mitems: Array, strat: Array, from: String = "", mem_f: Dictionary = {}) -> Dictionary:
	var t: Dictionary = eng.s.turn
	var stand = k if from == "" else from
	var need = d - int(t.pool.move)
	var excl = {}
	var mcost = 0.0
	var macts: Array = []
	if need > 0:
		var res = cover(mitems, need)
		if res.is_empty():
			return {}
		excl = picks_keys(mitems, res.picks)
		var mvp = _move_plan(mitems, need)
		macts = mvp.get("acts", [])
		var mp2: Dictionary = ctx.mp.duplicate(true)
		for pk in res.picks:
			var it: Dictionary = mitems[pk[0]]
			var op: Dictionary = it.opts[pk[1]]
			mcost += float(op.c) + (C.card_value(eng, p, str(it.key), ctx.rf) if it.kind == "card" else float(it.val))
			C.mana_cost(mp2, op.needs, true)
		ctx = ctx.duplicate()
		ctx["mp"] = mp2
	var h: Dictionary = eng.hex(k)
	var st = str(h.get("site", ""))
	var units_ok = true
	if kind == "adventure" and st in ["dungeon", "tomb"]:
		units_ok = false
	# per-turn cache of fight evaluations (the planner is re-run at every decision)
	var hk: Array = []
	for iid in eng.P(p).hand:
		if not excl.has(iid):
			hk.append(iid)
	hk.sort()
	var us: Array = []
	for u in eng.P(p).units:
		us.append("%d%s%s" % [int(u.uid), "r" if u.ready else "", "w" if u.wounded else ""])
	var fu: Array = []
	for eid in eng.hex(k).get("enemies", []):
		fu.append("%s%s" % [eid, "u" if eng.s.enemies.get(eid, {}).get("face_up", false) else ""])
	var ckey = "%s|%s|%s|%s|%s|%d|%s" % [kind, k, ",".join(hk), ",".join(us), ",".join(fu), int(eng.P(p).rep), JSON.stringify(ctx.mp)]
	if not mem_f.has("fcache"):
		mem_f["fcache"] = {}
	var fc: Dictionary = mem_f.fcache
	if fc.has(ckey):
		var v0 = float(fc[ckey]) - mcost
		return {"kind": kind, "hex": stand, "target": k, "value": v0 + pos_value(strat, stand, k), "move": d, "move_acts": macts}
	var items = CB.gather(eng, p, ctx, excl, units_ok, false)
	var cfg = CB.base_cfg(eng, p, ctx)
	# cards played for the approach are no longer in hand (discard costs need other free cards)
	var n_excl = 0
	for kx in excl:
		if not str(kx).begins_with("u") or str(kx).find("#") >= 0:
			n_excl += 1
	cfg.hand_cards = maxi(0, int(cfg.hand_cards) - n_excl)
	if not units_ok:
		cfg.units = []
	var bonus = 0.0
	if kind == "assault" or kind == "adventure":
		bonus = CB.site_bonus(eng, p, st, k)
	var alts = site_models(eng, p, k, kind, int(ctx.level) >= 3 and C.T("full_alts") > 0.5)
	if alts.is_empty():
		return {}
	var tot = 0.0
	for alt in alts:
		var models: Array = alt[1]
		if models.is_empty():
			continue
		var defs: Array = []
		for m in models:
			if kind == "assault" or kind == "adventure":
				defs.append(m.eid)
		cfg.site_bonus = bonus
		cfg.defenders_alive = defs
		if kind == "assault" or st in ["monster_den", "spawning_grounds", "ruins"]:
			cfg["progress"] = CB.progress_frac(eng, st, int(ctx.level)) * bonus / float(maxi(1, defs.size()))
		cfg.cap = (16 if int(ctx.level) >= 3 else 8) if alts.size() == 1 else 6
		var pl = CB.plan_checked(items, models, "ranged", cfg, ctx.mp)
		var sc = float(pl.score)
		if st == "city" and kind == "assault" and str(mem_f.get("siege", "")) == k and pl.get("kills", []).size() > 0:
			# siege mode: every defender defeated now brings the conquest closer (urgency)
			sc += C.T("siege_push") * minf(2.0, float(pl.kills.size()))
		tot += float(alt[0]) * sc
	var v = tot
	if kind == "assault":
		v -= C.rep_cost(int(eng.P(p).rep), -1)
	fc[ckey] = v
	if st == "city" and OS.get_environment("AI_PLAN") == "3":
		printerr("   city assault eval %s from d=%d: v=%.2f mcost=%.2f hand=%s" % [k, d, v, mcost, ",".join(hk)])
	v -= mcost
	v += pos_value(strat, stand, k)
	return {"kind": kind, "hex": stand, "target": k, "value": v, "move": d, "move_acts": macts}

static func _altar_mission(eng, p: int, ctx: Dictionary, k: String, d: int, mitems: Array, strat: Array) -> Dictionary:
	var h: Dictionary = eng.hex(k)
	var rd: Dictionary = MKDB.ruins.get(str(h.ruins), {})
	var needs: Array = MKSites.altar_needs(rd)
	var mp2: Dictionary = ctx.mp.duplicate(true)
	var mc = C.mana_cost(mp2, needs, true)
	if mc < 0.0:
		return {}
	var need = d - int(eng.s.turn.pool.move)
	var ctx2 = ctx.duplicate()
	ctx2["mp"] = mp2
	var mpl = _move_plan(move_items(eng, p, ctx2, ""), need)
	if mpl.is_empty():
		return {}
	return {"kind": "altar", "hex": k, "value": float(rd.get("fame", 7)) + 2.0 - mc - float(mpl.cost) + pos_value(strat, k, k), "move": d,
		"move_acts": mpl.acts, "reserve": needs}

static func _interact_mission(eng, p: int, ctx: Dictionary, k: String, d: int, mitems: Array, strat: Array) -> Dictionary:
	var h: Dictionary = eng.hex(k)
	var st = str(h.get("site", ""))
	if not st in ["village", "monastery", "keep", "mage_tower", "city"]:
		return {}
	var t: Dictionary = eng.s.turn
	if d > 0 and (t.acted or not eng.can_still_move(p)):
		return {}
	if d == 0 and MKSites.can_interact(eng, p) != "":
		return {}
	if int(eng.P(p).rep) <= -7:
		return {}
	# which site services would be available there
	var site = _interaction_site_at(eng, p, k)
	if site == "":
		return {}
	var buys = _purchases(eng, p, ctx, k, site)
	if buys.is_empty():
		return {}
	var need = d - int(t.pool.move)
	var excl = {}
	var mcost = 0.0
	var imacts: Array = []
	if need > 0:
		var res = cover(mitems, need)
		if res.is_empty():
			return {}
		excl = picks_keys(mitems, res.picks)
		mcost = float(res.cost)
		imacts = _move_plan(mitems, need).get("acts", [])
		var mp3: Dictionary = ctx.mp.duplicate(true)
		for pk in res.picks:
			C.mana_cost(mp3, mitems[pk[0]].opts[pk[1]].needs, true)
		ctx = ctx.duplicate()
		ctx["mp"] = mp3
	var iitems = inf_items(eng, p, ctx, excl)
	var base_inf = int(t.pool.influence)
	if not t.rep_applied:
		base_inf += eng.rep_bonus(p)
		if site == "city" and h.has("city"):
			for x in h.city.get("shields", []):
				if int(x) == p:
					base_inf += 1
	# choose up to 3 purchases greedily by value density, then evaluate combos
	var best_v = 0.0
	var best_set: Array = []
	var n = mini(buys.size(), 5)
	for mask in range(1, 1 << n):
		var cost_inf = 0
		var val = 0.0
		var units = 0
		var heals = 0
		var setb: Array = []
		var mana_needs: Array = []
		for i in n:
			if mask & (1 << i):
				var b: Dictionary = buys[i]
				cost_inf += int(b.cost)
				val += float(b.value)
				setb.append(b)
				if b.what == "recruit":
					units += 1
				if b.has("mana"):
					mana_needs.append(b.mana)
		if units > maxi(0, eng.command_free(p)) + (1 if units == 1 else 0):
			continue
		if not mana_needs.is_empty() and C.mana_cost(ctx.mp, mana_needs) < 0.0:
			continue
		var needi = cost_inf - base_inf
		var cc = 0.0
		if needi > 0:
			var res2 = cover(iitems, needi)
			if res2.is_empty():
				continue
			cc = float(res2.cost)
		var net = val - cc
		if net > best_v:
			best_v = net
			best_set = setb
	if OS.get_environment("AI_PLAN") == "6":
		var bl: Array = []
		for b in buys:
			bl.append("%s:%s c%d v%.1f" % [b.what, str(b.get("id", "")), int(b.cost), float(b.value)])
		printerr("   interact %s site=%s base_inf=%d buys=[%s] best=%.1f n=%d" % [k, site, base_inf, "; ".join(bl), best_v, best_set.size()])
	if best_set.is_empty():
		return {}
	return {"kind": "interact", "hex": k, "value": best_v - mcost + pos_value(strat, k) + end_bonus(eng, p, k), "buys": best_set, "move": d, "move_acts": imacts}

static func _interaction_site_at(eng, p: int, k: String) -> String:
	var h: Dictionary = eng.hex(k)
	match str(h.get("site", "")):
		"village":
			return "village"
		"monastery":
			return "" if h.burned else "monastery"
		"keep":
			if int(h.owner) == p or (h.conquered and not eng.is_competitive()):
				return "keep"
		"mage_tower":
			if h.conquered:
				return "mage_tower"
		"city":
			if h.conquered:
				return "city"
	return ""

static func _purchases(eng, p: int, ctx: Dictionary, k: String, site: String) -> Array:
	var out: Array = []
	var pl: Dictionary = eng.P(p)
	var h: Dictionary = eng.hex(k)
	var col = str(h.city.color) if site == "city" and h.has("city") else ""
	# units
	var weakest = BIG
	for u in pl.units:
		weakest = minf(weakest, C.unit_worth(str(u.id)) * (0.6 if u.wounded else 1.0))
	for id in eng.s.offers.units:
		var ud: Dictionary = MKDB.units.get(id, {})
		var rec: Array = ud.get("recruit", [])
		var ok = false
		if site == "city":
			ok = col == "white" or "city" in rec
		else:
			ok = site in rec
		if not ok:
			continue
		var cost = int(ud.get("cost", 0))
		for m in eng.mods_named("recruit_discount"):
			cost -= int(m.get("n", 0))
		cost = maxi(0, cost)
		var v = C.unit_worth(id) * float(ctx.get("unit_mult", 1.0))
		if int(ctx.level) >= 3 and eng.command_free(p) == 1:
			# the last free command slot: a weak unit now blocks a better one later
			v -= C.T("slot_cost") * clampf(float(int(eng.s.scn.get("rounds", 6)) - int(eng.s.round)) / 3.0, 0.0, 1.0)
		var disband = -1
		if eng.command_free(p) <= 0:
			if pl.units.is_empty() or weakest >= v - 1.0:
				continue
			v -= weakest
			for u in pl.units:
				if absf(C.unit_worth(str(u.id)) * (0.6 if u.wounded else 1.0) - weakest) < 0.001:
					disband = int(u.uid)
		var b = {"what": "recruit", "id": id, "cost": cost, "value": v}
		if disband >= 0:
			b["disband"] = disband
		out.append(b)
	# healing
	var wounds = 0
	for iid in pl.hand:
		if eng.is_wound(iid):
			wounds += 1
	if site in ["village", "monastery"]:
		var hc = 3 if site == "village" else 2
		for i in mini(wounds, 3):
			out.append({"what": "heal", "cost": hc, "value": C.T("heal_v")})
	if site == "monastery":
		for id2 in eng.s.offers.monastery:
			out.append({"what": "aa", "id": id2, "cost": 6, "value": C.pick_value(id2) * 0.75 * C.T("buy_card")})
	if site == "mage_tower" or col == "blue":
		for id3 in eng.s.offers.spells:
			out.append({"what": "spell", "id": id3, "cost": 7, "value": C.pick_value(id3) * 0.8 * C.T("buy_card"), "mana": str(MKDB.card(id3).get("color", ""))})
	if col == "green":
		for id4 in eng.s.offers.aa:
			out.append({"what": "aa_offer", "id": id4, "cost": 6, "value": C.pick_value(id4) * 0.75 * C.T("buy_card")})
	if col == "red":
		out.append({"what": "artifact", "cost": 12, "value": 6.0})
	out.sort_custom(func(a, b): return float(a.value) / maxf(1.0, float(a.cost)) > float(b.value) / maxf(1.0, float(b.cost)))
	return out

# ================================================================ execution
## Activatable tactics: Midnight Meditation (cycle wounds at turn start), Sparing Power (take the stored cards),
## Mana Search (reroll useless dice).
static func _tactic_start(eng, p: int, ctx: Dictionary) -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var t: Dictionary = eng.s.turn
	var uses := {}
	for u in MKSites._tactic_uses(eng, p):
		uses[str(u.opt)] = true
	if uses.is_empty():
		return {}
	var wounds = 0
	for iid in pl.hand:
		if eng.is_wound(iid):
			wounds += 1
	if uses.has("meditation") and not t.started and (wounds >= 2 or (wounds >= 1 and int(eng.s.round) >= int(eng.s.scn.get("rounds", 6)))):
		return {"t": "tactic_use", "opt": "meditation"}
	if uses.has("take") and (pl.deck.is_empty() or eng.s.announced_by != -1 or eng.s.game_end_pending or pl.tactic_store.size() >= 3):
		return {"t": "tactic_use", "opt": "take"}
	if uses.has("mana_search") and int(t.dice_taken) == 0:
		for d in eng.s.source:
			if int(d.taken_by) == -1 and ((eng.s.day and d.color == "black") or (not eng.s.day and d.color == "gold")):
				return {"t": "tactic_use", "opt": "mana_search"}
	return {}

## Tactics used at the end of the turn: The Right Moment (extra turn), Sparing Power (store a card).
static func _tactic_end(eng, p: int, ctx: Dictionary) -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var uses := {}
	for u in MKSites._tactic_uses(eng, p):
		uses[str(u.opt)] = true
	if uses.has("right_moment") and not pl.deck.is_empty() and eng.s.announced_by == -1:
		return {"t": "tactic_use", "opt": "right_moment"}
	if uses.has("store") and pl.deck.size() >= 3 and eng.s.announced_by == -1:
		return {"t": "tactic_use", "opt": "store"}
	return {}

static func decide(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var t: Dictionary = eng.s.turn
	var ta = _tactic_start(eng, p, ctx)
	if not ta.is_empty() and eng.check(ta) == "":
		return ta
	# forced: only wounds in hand and nothing played
	if eng.wounds_only_lock(p):
		if eng.check({"t": "rest"}) == "":
			return {"t": "rest"}
	# announce the end of the round with a weak hand and an empty deck
	if eng.check({"t": "announce_end"}) == "":
		var good = 0
		for iid in pl.hand:
			if not eng.is_wound(iid):
				good += 1
		if good <= 1:
			return {"t": "announce_end"}
	var m = plan(eng, p, ctx, mem)
	if m.is_empty():
		return _finish(eng, p, ctx, mem)
	if eng.check({"t": "announce_end"}) == "" and float(m.value) < 0.8 and m.kind in ["end", "relocate", "rest"]:
		return {"t": "announce_end"}
	mem["last_mission"] = {"kind": m.kind, "hex": m.hex}
	if m.kind in ["interact", "explore", "altar"] and m.get("path", []).is_empty():
		mem["productive"] = true
	mem["mission"] = m
	match str(m.kind):
		"end":
			return _finish(eng, p, ctx, mem)
		"rest":
			return {"t": "rest"}
	# move along the path
	var path: Array = m.get("path", [])
	if not path.is_empty():
		var nxt: String = path[0]
		var a = {"t": "move", "to": nxt}
		if eng.check(a) == "":
			return a
		var remaining = 0
		for k in path:
			remaining += eng.move_cost(k)
		if m.kind == "explore":
			remaining += eng.explore_cost(p)
		for ma in m.get("move_acts", []):
			if eng.check(ma) == "":
				mem["intent"] = {"kind": "", "want": "move"}
				return ma
		var pa = _play_move(eng, p, _reserve_ctx(ctx, m), mem, remaining - int(t.pool.move), "fight" if m.kind in ["assault", "adventure", "challenge"] else ("inf" if m.kind == "interact" else ""))
		if not pa.is_empty():
			return pa
		return _finish(eng, p, ctx, mem)
	# at the mission hex
	match str(m.kind):
		"assault":
			return _finish(eng, p, ctx, mem)
		"adventure":
			var a2 = {"t": "site"}
			if eng.check(a2) == "":
				return a2
		"challenge":
			var a3 = {"t": "challenge", "hexes": [str(m.target)]}
			if eng.check(a3) == "":
				return a3
		"altar":
			var a4 = {"t": "altar"}
			if eng.check(a4) == "":
				return a4
		"explore":
			var a5 = {"t": "explore", "slot": str(m.slot)}
			if eng.check(a5) == "":
				return a5
			for ma2 in m.get("move_acts", []):
				if eng.check(ma2) == "":
					mem["intent"] = {"kind": "", "want": "move"}
					return ma2
			var pa2 = _play_move(eng, p, ctx, mem, eng.explore_cost(p) - int(t.pool.move), "")
			if not pa2.is_empty():
				return pa2
		"interact":
			var ia = _do_interact(eng, p, ctx, mem, m)
			if not ia.is_empty():
				return ia
		"relocate":
			pass
	return _finish(eng, p, ctx, mem)

static func _reserve_ctx(ctx: Dictionary, m: Dictionary) -> Dictionary:
	if not m.has("reserve"):
		return ctx
	var c2 = ctx.duplicate()
	var mp2: Dictionary = ctx.mp.duplicate(true)
	C.mana_cost(mp2, m.reserve, true)
	c2["mp"] = mp2
	return c2

static func _play_move(eng, p: int, ctx: Dictionary, mem: Dictionary, need: int, relevance: String) -> Dictionary:
	if need <= 0:
		return {}
	var items = move_items(eng, p, ctx, relevance)
	var res = cover(items, need)
	if res.is_empty():
		return {}
	# play the pick with the largest move first
	var best = {}
	var bv = -1
	for pk in res.picks:
		var o: Dictionary = items[pk[0]].opts[pk[1]]
		if int(o.v) > bv and eng.check(o.act) == "":
			bv = int(o.v)
			best = o.act
	if not best.is_empty():
		mem["intent"] = {"kind": "", "want": "move"}
	return best

static func _do_interact(eng, p: int, ctx: Dictionary, mem: Dictionary, m: Dictionary) -> Dictionary:
	var buys: Array = m.get("buys", [])
	for b in buys:
		var a = {}
		match str(b.what):
			"recruit":
				a = {"t": "recruit", "id": str(b.id)}
				if b.has("disband"):
					a["disband"] = int(b.disband)
			"heal":
				a = {"t": "buy", "what": "heal"}
			_:
				a = {"t": "buy", "what": str(b.what)}
				if b.has("id"):
					a["id"] = str(b.id)
		if eng.check(a) == "":
			return a
		# need more influence?
		var have = MKSites.influence_avail(eng, p)
		var need = int(b.cost) - have
		if need > 0:
			var items = inf_items(eng, p, ctx, {})
			var res = cover(items, need)
			if res.is_empty():
				continue
			var best = {}
			var bv = -1
			for pk in res.picks:
				var o: Dictionary = items[pk[0]].opts[pk[1]]
				if int(o.v) > bv and eng.check(o.act) == "":
					bv = int(o.v)
					best = o.act
			if not best.is_empty():
				mem["intent"] = {"kind": "", "want": "inf"}
				return best
	return {}

## End of the turn: useful free plays (healing), then end turn.
static func _finish(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var t: Dictionary = eng.s.turn
	# spend heal points / heal wounds with cards when worth it
	var wounds = 0
	for iid in pl.hand:
		if eng.is_wound(iid):
			wounds += 1
	if int(t.pool.heal) > 0:
		for u in pl.units:
			var hu = {"t": "heal", "target": int(u.uid)}
			if u.wounded and eng.check(hu) == "":
				return hu
		var hh = {"t": "heal", "target": "hand"}
		if eng.check(hh) == "":
			return hh
	if wounds > 0 and eng.s.combat == null:
		var octx = C.base_ctx(eng, p, false, "")
		var rf: float = ctx.rf
		for iid in pl.hand:
			if eng.is_wound(iid):
				continue
			for o in C.card_opts(eng, p, iid, octx, false):
				if int(o.b.heal) <= 0 or int(o.b.disc) > 0:
					continue
				var gain = C.T("heal_v") * float(mini(int(o.b.heal), wounds)) - C.card_value(eng, p, iid, rf) - C.mana_cost(ctx.mp, o.needs) * 1.0
				if C.mana_cost(ctx.mp, o.needs) < 0.0:
					continue
				if gain > 0.3 and eng.check(o.act) == "":
					mem["intent"] = {"kind": "", "want": "heal"}
					return o.act
		for sk in pl.skills:
			var d: Dictionary = MKDB.skills.get(sk.id, {})
			for b in C.parse(d.get("effect", []), octx):
				if int(b.heal) > 0:
					var a = {"t": "skill", "id": str(sk.id)}
					if eng.check(a) == "":
						return a
	# an unused source die can become a permanent crystal (Crystallize and similar cards)
	if eng.s.combat == null and MKMana.dice_left(eng, p) > 0:
		var octx2 = C.base_ctx(eng, p, false, "")
		for iid in pl.hand:
			if eng.is_wound(iid):
				continue
			for o in C.card_opts(eng, p, iid, octx2, false):
				var cr = 0
				for kc in o.b.crys:
					cr += int(o.b.crys[kc])
				if cr <= 0 or int(o.b.disc) > 0 or int(o.b.wound) > 0:
					continue
				var gain2 = 0.9 * float(cr) - C.card_value(eng, p, iid, ctx.rf) - 0.1
				var mpn: Dictionary = ctx.mp.duplicate(true)
				mpn["cr"] = {"red": 0, "blue": 0, "green": 0, "white": 0}
				if gain2 > 0.0 and C.mana_cost(mpn, o.needs) >= 0.0 and eng.check(o.act) == "":
					mem["intent"] = {"kind": "", "want": "crystal"}
					return o.act
	var te = _tactic_end(eng, p, ctx)
	if not te.is_empty() and eng.check(te) == "":
		return te
	# cycle weak cards when the deck holds more cards than the rest of the round can use
	if eng.s.combat == null and eng.s.announced_by == -1 and not eng.s.game_end_pending:
		var tl = C.turns_left(eng, p)
		var extra = float(pl.deck.size()) - float(tl - 1) * 3.5
		var done = int(t.get("discarded", 0))
		if extra - float(done) >= 1.0 and done < 3:
			var worst = ""
			var wv = 0.71
			for iid in pl.hand:
				if eng.is_wound(iid):
					continue
				var v = C.card_base_value(eng.card_id(iid))
				if v < wv:
					wv = v
					worst = iid
			if worst != "" and eng.check({"t": "discard", "card": worst}) == "":
				return {"t": "discard", "card": worst}
	if eng.check({"t": "end_turn"}) == "":
		return {"t": "end_turn"}
	if eng.check({"t": "rest"}) == "":
		return {"t": "rest"}
	return {}
