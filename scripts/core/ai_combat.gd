extends RefCounted
## AI helper (agent AI): abstract combat planner + in-combat decisions.
## The planner partitions the available resources (cards/units/skills/pool) between
## ranged kills, blocks and melee kills, estimating damage (wounds) for the rest,
## and returns the best plan; execution plays the cards of the current phase step by step
## (re-planning after every action, so the plan always reflects the real pool).

const C = preload("res://scripts/core/ai_cards.gd")
const BIG := 1.0e9

# ================================================================ enemy models
static func resists(m: Dictionary, elem: String) -> bool:
	var r: Array = m.resist
	if elem == "cold":
		return "fire" in r and "ice" in r
	return elem in r

static func model_entry(eng, e: Dictionary) -> Dictionary:
	var fame = 0
	if not e.get("summoned", false) and not e.get("no_fame", false):
		fame = int(e.fame)
		if e.get("half_fame", false):
			fame = (fame + 1) / 2
		fame += int(eng.s.turn.get("fame_bonus_per_enemy", 0))
	var res: Array = []
	for x in e.get("resist", []):
		if not x in e.get("lost_resist", []):
			res.append(x)
	var atks: Array = []
	for i in e.attacks.size():
		atks.append({"i": i, "n": MKCombat.attack_value(eng, e, i), "elem": MKCombat.attack_elem(e, i), "blocked": bool(e.attacks[i].blocked),
			"rem": int(e.attacks[i].get("rem", 0))})
	var rep = 0
	if e.get("rampage", false):
		rep += 2 if str(e.get("color", "")) == "red" else 1
	rep += int(e.get("rep", 0))
	return {"eid": str(e.eid), "armor": MKCombat.armor_of(eng, e), "fame": fame, "resist": res,
		"fort": MKCombat.is_fortified(e), "dfort": MKCombat.is_double_fortified(e),
		"swift": MKCombat.has_ab(e, "swift"), "brutal": MKCombat.has_ab(e, "brutal"), "poison": MKCombat.has_ab(e, "poison"),
		"paralyze": MKCombat.has_ab(e, "paralyze"), "summon": MKCombat.has_ab(e, "summon") and not e.get("summoned", false),
		"summoned": bool(e.get("summoned", false)), "hidden": bool(e.get("hidden", false)), "site_def": bool(e.get("site_def", false)),
		"rep": rep, "atks": atks, "no_attack": bool(e.get("no_attack", false)), "color": str(e.get("color", ""))}

## Model from an enemy type (planning before the combat).
static func model_type(eng, type_id: String, fort_site: bool, city: String, rampage: bool = false, eid: String = "") -> Dictionary:
	var d: Dictionary = MKDB.enemies.get(type_id, {})
	var abil: Array = d.get("abilities", [])
	var atks: Array = []
	var i = 0
	for a in d.get("attacks", []):
		var n = int(a.n)
		var el = str(a.elem)
		if city == "blue":
			if el in ["fire", "ice"]:
				n += 2
			elif el == "cold":
				n += 1
		atks.append({"i": i, "n": n, "elem": el, "blocked": false, "rem": 0})
		i += 1
	var brutal: bool = "brutal" in abil
	var poison: bool = "poison" in abil
	if city == "red" or city == "green":
		for a2 in atks:
			if a2.elem == "phys":
				if city == "red":
					brutal = true
				else:
					poison = true
	var fort: bool = "fortified" in abil
	var sfort = fort_site and not ("unfortified" in abil)
	var rep = 0
	if rampage:
		rep = 2 if str(d.get("color", "")) == "red" else 1
	rep += int(d.get("rep", 0))
	return {"eid": eid if eid != "" else "t:" + type_id, "armor": int(d.get("armor", 1)) + (1 if city == "white" else 0),
		"fame": int(d.get("fame", 0)), "resist": d.get("resist", []).duplicate(), "fort": fort or sfort, "dfort": fort and sfort,
		"swift": "swift" in abil, "brutal": brutal, "poison": poison, "paralyze": "paralyze" in abil,
		"summon": "summon" in abil, "summoned": false, "hidden": false, "site_def": fort_site or eid.begins_with("site"),
		"rep": rep, "atks": atks, "no_attack": false, "color": str(d.get("color", ""))}

## Types of a colour with their copy counts (public information, not the bag contents).
static var _types_cache: Dictionary = {}
static func color_types(eng, color: String) -> Array:
	var key = color + "|" + ",".join(eng.s.scn.get("sets", ["base"]))
	if _types_cache.has(key):
		return _types_cache[key]
	var out: Array = []
	var ids: Array = MKDB.enemies.keys()
	ids.sort()
	for id in ids:
		var d: Dictionary = MKDB.enemies[id]
		if str(d.get("color", "")) == color and MKDB.set_ok(d, eng.s.scn.get("sets", ["base"])):
			out.append([id, maxi(1, int(d.get("copies", 1)))])
	_types_cache[key] = out
	return out

## A "typical" enemy type of a colour (median armor+attack) for quick estimates.
static func typical_type(eng, color: String) -> String:
	var ts = color_types(eng, color)
	if ts.is_empty():
		return ""
	var arr: Array = []
	for t in ts:
		var d: Dictionary = MKDB.enemies[t[0]]
		var atk = 0
		for a in d.get("attacks", []):
			atk += int(a.n)
		arr.append([int(d.get("armor", 1)) * 2 + atk + d.get("resist", []).size() * 2, t[0]])
	arr.sort_custom(func(a, b): return a[0] < b[0] or (a[0] == b[0] and a[1] < b[1]))
	return arr[(arr.size() * 3) / 5][1]

# ================================================================ items
## Resources usable in combat: [{kind, key, val, opts:[{act, needs, b, c, v...}]}]
static func gather(eng, p: int, ctx: Dictionary, exclude: Dictionary = {}, units_ok: bool = true, with_pool: bool = true) -> Array:
	var items: Array = []
	var pl: Dictionary = eng.P(p)
	var rf: float = ctx.get("rf", C.round_factor(eng, p))
	var mp: Dictionary = ctx.get("mp", C.mana_pool(eng, p))
	var cctx: Dictionary = C.base_ctx(eng, p, true, "any")
	var wc: float = ctx.get("wc", 2.6)
	if with_pool and eng.s.combat != null:
		var pb = C.empty_b()
		var pool: Dictionary = eng.s.turn.pool
		for k in pool.attack:
			pb.atk[k] = int(pool.attack[k])
		for k2 in pool.block:
			pb.blk[k2] = int(pool.block[k2])
		pb.bsw = int(eng.s.turn.get("block_swift", 0))
		if not pb.atk.is_empty() or not pb.blk.is_empty() or pb.bsw > 0:
			# the pool is emptied when the phase ends: it only helps in the current phase
			items.append({"kind": "pool", "key": "pool", "val": 0.0, "only": str(eng.s.combat.phase), "opts": [{"act": {}, "needs": [], "b": pb, "c": 0.0}]})
	for iid in pl.hand:
		if eng.is_wound(iid) or exclude.has(iid):
			continue
		var opts: Array = []
		for o in C.card_opts(eng, p, iid, cctx):
			if not _combat_useful(o.b):
				continue
			var mc = C.mana_cost(mp, o.needs)
			if mc < 0.0:
				continue
			o.c = float(o.c) + mc + float(o.b.wound) * wc + float(o.b.disc) * 1.0 * rf + C.rep_cost(int(pl.rep), int(o.b.rep))
			opts.append(o)
		if not opts.is_empty():
			items.append({"kind": "card", "key": iid, "val": C.card_value(eng, p, iid, rf), "opts": opts})
	if units_ok and eng.units_usable():
		for u in pl.units:
			if not u.ready or u.wounded or exclude.has("u%d" % int(u.uid)):
				continue
			var uopts: Array = []
			for o2 in C.unit_opts(eng, p, u, cctx):
				if not _combat_useful(o2.b):
					continue
				var mc2 = C.mana_cost(mp, o2.needs)
				if mc2 < 0.0:
					continue
				o2.c = float(o2.c) + mc2 + float(o2.b.wound) * wc
				if "wound_self_unit" in o2.b.sp:
					o2.c = float(o2.c) + 0.4 * C.unit_worth(str(u.id))
				uopts.append(o2)
			if not uopts.is_empty():
				items.append({"kind": "unit", "key": int(u.uid), "val": C.unit_use_cost(eng, p, u, rf), "opts": uopts})
	for sk in pl.skills:
		var d: Dictionary = MKDB.skills.get(sk.id, {})
		var usage = str(d.get("usage", "turn"))
		if usage == "passive" or (usage == "turn" and sk.used_turn) or (usage in ["round", "interactive"] and sk.used_round):
			continue
		var sopts: Array = []
		for o3 in C.skill_opts(eng, p, sk, cctx):
			if _combat_useful(o3.b):
				sopts.append(o3)
		if not sopts.is_empty():
			items.append({"kind": "skill", "key": str(sk.id), "val": 0.15 if usage == "turn" else 0.6 * rf, "opts": sopts})
	return items

static func _combat_useful(b: Dictionary) -> bool:
	return not b.atk.is_empty() or not b.blk.is_empty() or int(b.bsw) > 0

# ================================================================ value functions
static func atk_v2(b: Dictionary, group: Array, ph: String) -> int:
	var fort = false
	for m in group:
		if m.fort:
			fort = true
	var v2 = 0
	for key in b.atk:
		var n = int(b.atk[key])
		if n <= 0:
			continue
		var parts: PackedStringArray = str(key).split(":")
		var kind: String = parts[0]
		var elem: String = parts[1] if parts.size() > 1 else "phys"
		if ph == "ranged":
			if kind == "melee":
				continue
			if fort and kind != "siege":
				continue
		var res = false
		for m in group:
			if resists(m, elem):
				res = true
				break
		v2 += n if res else 2 * n
	return v2

static func block_eff(bel: String, ael: String) -> bool:
	match ael:
		"phys":
			return true
		"fire":
			return bel in ["ice", "cold"]
		"ice":
			return bel in ["fire", "cold"]
		"cold":
			return bel == "cold"
	return true

static func blk_v2(b: Dictionary, at: Dictionary) -> int:
	var v2 = 0
	for el in b.blk:
		var n = int(b.blk[el])
		v2 += 2 * n if block_eff(el, at.elem) else n
	var bs = int(b.bsw)
	if bs > 0:
		var x = bs * (2 if at.get("swift", false) else 1)
		v2 += 2 * x if block_eff("phys", at.elem) else x
	return v2

# ================================================================ allocation (min-cost cover DP)
## vals[ii] = Array of int (value of each option, 0 = unusable). Returns {cost, picks} or {} if impossible.
static func dp_cover(items: Array, used: Dictionary, need2: int, vals: Array) -> Dictionary:
	if need2 <= 0:
		return {"cost": 0.0, "picks": []}
	var dp = PackedFloat32Array()
	dp.resize(need2 + 1)
	dp.fill(BIG)
	dp[0] = 0.0
	var layers: Array = []
	for ii in items.size():
		if used.has(ii):
			continue
		var vv: Array = vals[ii]
		var anyv = false
		for x in vv:
			if x > 0:
				anyv = true
				break
		if not anyv:
			continue
		var nd = dp.duplicate()
		var bp = PackedInt32Array()
		bp.resize(need2 + 1)
		bp.fill(-1)
		var it: Dictionary = items[ii]
		var base_c: float = float(it.val)
		var opts: Array = it.opts
		for v in range(need2 + 1):
			var cur: float = dp[v]
			if cur >= BIG:
				continue
			for oi in vv.size():
				var x2: int = vv[oi]
				if x2 <= 0:
					continue
				var nv = mini(need2, v + x2)
				var c: float = cur + base_c + float(opts[oi].c)
				if c < nd[nv] - 0.0001:
					nd[nv] = c
					bp[nv] = v * 64 + oi
		dp = nd
		layers.append([ii, bp])
	if dp[need2] >= BIG:
		return {}
	var picks: Array = []
	var cv = need2
	for li in range(layers.size() - 1, -1, -1):
		var bpv: int = layers[li][1][cv]
		if bpv >= 0:
			picks.append([layers[li][0], bpv % 64])
			cv = bpv / 64
	return {"cost": float(dp[need2]), "picks": picks}

static func _mark(used: Dictionary, picks: Array) -> void:
	for pk in picks:
		used[pk[0]] = true

static func group_armor(group: Array) -> int:
	var a = 0
	for m in group:
		a += int(m.armor)
	return a

## Kill a set of enemies in phase ph: one group or one-by-one, cheapest.
static func alloc_kill(items: Array, used: Dictionary, K: Array, ph: String) -> Dictionary:
	if K.is_empty():
		return {"cost": 0.0, "groups": [], "used": []}
	var best = {}
	# one group
	var vals: Array = []
	for it in items:
		var vv: Array = []
		var only = str(it.get("only", ""))
		for o in it.opts:
			vv.append(0 if only != "" and only != ph else atk_v2(o.b, K, ph))
		vals.append(vv)
	var r = dp_cover(items, used, 2 * group_armor(K), vals)
	if not r.is_empty():
		var ids: Array = []
		for m in K:
			ids.append(m.eid)
		best = {"cost": r.cost, "groups": [{"targets": ids, "picks": r.picks}]}
	# separately
	if K.size() > 1:
		var u2 = used.duplicate()
		var tot = 0.0
		var groups: Array = []
		var ok = true
		var order = K.duplicate()
		order.sort_custom(func(a, b): return int(a.armor) > int(b.armor))
		for m in order:
			var vals2: Array = []
			for it in items:
				var vv2: Array = []
				var only2 = str(it.get("only", ""))
				for o in it.opts:
					vv2.append(0 if only2 != "" and only2 != ph else atk_v2(o.b, [m], ph))
				vals2.append(vv2)
			var r2 = dp_cover(items, u2, 2 * int(m.armor), vals2)
			if r2.is_empty():
				ok = false
				break
			tot += float(r2.cost)
			_mark(u2, r2.picks)
			groups.append({"targets": [m.eid], "picks": r2.picks})
		if ok and (best.is_empty() or tot < float(best.cost) - 0.01):
			best = {"cost": tot, "groups": groups}
	return best

static func alloc_block(items: Array, used: Dictionary, at: Dictionary) -> Dictionary:
	var vals: Array = []
	for it in items:
		var vv: Array = []
		var only = str(it.get("only", ""))
		for o in it.opts:
			vv.append(0 if only != "" and only != "block" else blk_v2(o.b, at))
		vals.append(vv)
	var need = int(at.n) * (2 if at.get("swift", false) else 1)
	return dp_cover(items, used, 2 * need, vals)

# ================================================================ damage
## cfg: {armor, hand_limit, wounds_so_far, wc, units:[{uid, armor, resist, worth}], ko_pen}
static func attack_damage(at: Dictionary) -> int:
	return int(at.n) * (2 if at.get("brutal", false) else 1)

static func hero_cost(d: int, at: Dictionary, cfg: Dictionary) -> Array:
	# returns [cost, wounds]
	var arm: int = maxi(1, int(cfg.armor))
	var w = int(ceil(float(d) / float(arm)))
	var c = float(w) * float(cfg.wc)
	if at.get("poison", false):
		c += float(w) * float(cfg.wc) * 0.6
	if at.get("paralyze", false) and w > 0:
		c += float(cfg.ko_pen)
	return [c, w]

static func unit_dmg(d: int, at: Dictionary, u: Dictionary) -> Array:
	# returns [cost, remaining damage]
	var res = false
	var ures: Array = u.resist
	if at.elem == "cold":
		res = "fire" in ures and "ice" in ures
	else:
		res = at.elem in ures
	var arm = int(u.armor)
	var wounded = true
	var rem = d
	if res:
		rem -= arm
		if rem > 0:
			rem -= arm
		else:
			wounded = false
	else:
		rem -= arm
	var c = 0.0
	if wounded:
		if at.get("paralyze", false):
			c = float(u.worth)
		else:
			c = 0.3 * float(u.worth) + 1.2
			if at.get("poison", false):
				c *= 1.6
	return [c, maxi(0, rem)]

## Cost of a set of unblocked attacks with greedy assignment. Returns {cost, hero_w, ko}
static func damage_cost(attacks: Array, cfg: Dictionary) -> Dictionary:
	var lst = attacks.duplicate()
	lst.sort_custom(func(a, b): return attack_damage(a) > attack_damage(b))
	var units_free: Array = cfg.units.duplicate()
	var tot = 0.0
	var hw = 0
	var para = false
	for at in lst:
		var d = attack_damage(at)
		if d <= 0:
			continue
		var hc: Array = hero_cost(d, at, cfg)
		var best_c: float = hc[0]
		var best_u = -1
		var best_w: int = hc[1]
		for ui in units_free.size():
			var ud: Array = unit_dmg(d, at, units_free[ui])
			var rem: int = ud[1]
			var c2: float = ud[0]
			var w2 = 0
			if rem > 0:
				var hc2: Array = hero_cost(rem, at, cfg)
				c2 += hc2[0]
				w2 = hc2[1]
			if c2 < best_c - 0.01:
				best_c = c2
				best_u = ui
				best_w = w2
		if best_u >= 0:
			units_free.remove_at(best_u)
		tot += best_c
		hw += best_w
		if at.get("paralyze", false) and best_w > 0:
			para = true
	var ko: bool = para or (int(cfg.wounds_so_far) + hw >= int(cfg.hand_limit) and hw > 0)
	if ko and not para:
		tot += float(cfg.ko_pen)
	return {"cost": tot, "hero_w": hw, "ko": ko}

# ================================================================ planner
## Subsets of arr as [mask, Array]; sorted by size; capped (keeps empty, full and high-fame sets).
static func subsets(arr: Array, cap: int) -> Array:
	var n = mini(arr.size(), 10)
	var out: Array = []
	for mask in range(1 << n):
		var s: Array = []
		for i in n:
			if mask & (1 << i):
				s.append(arr[i])
		out.append([mask, s])
	out.sort_custom(func(a, b): return a[1].size() < b[1].size())
	if out.size() > cap:
		var keep: Array = [out[0], out[out.size() - 1]]
		var rest: Array = out.slice(1, out.size() - 1)
		rest.sort_custom(func(a, b): return _fame_of(a[1]) > _fame_of(b[1]))
		for x in rest:
			if keep.size() >= cap:
				break
			keep.append(x)
		keep.sort_custom(func(a, b): return a[1].size() < b[1].size())
		return keep
	return out

static func _fame_of(K: Array) -> float:
	var f = 0.0
	for m in K:
		f += float(m.fame) + 0.6 * float(m.rep)
	return f

## Expected attack of a summoned brown monster (for planning before it appears).
const SUMMON_ATK := {"i": 0, "n": 6, "elem": "phys", "blocked": false, "swift": false, "brutal": false, "poison": false, "paralyze": false}

## enemies: models still alive. phase: "ranged"|"block"|"damage"|"attack".
## cfg: {armor, hand_limit, wounds_so_far, wc, units, ko_pen, site_bonus, defenders_alive:[eids], cap, deadline}
static func plan(items: Array, enemies: Array, phase: String, cfg: Dictionary) -> Dictionary:
	var alive: Array = enemies
	var best = {"score": -BIG, "groupsR": [], "blocks": [], "groupsA": [], "kills": []}
	var kr_list: Array = [[0, []]]
	var cap = int(cfg.get("cap", 32))
	if phase == "ranged":
		var tg: Array = []
		for m in alive:
			if not m.dfort and not m.summoned and not m.hidden:
				tg.append(m)
		kr_list = subsets(tg, cap)
	var deadline: int = int(cfg.get("deadline", 0))
	var bonus = float(cfg.get("site_bonus", 0.0))
	var fm = float(cfg.get("fm", 1.0))
	var prog = float(cfg.get("progress", 0.0))
	var defs: Array = cfg.get("defenders_alive", [])
	var kr_bad: Array = []
	for kre in kr_list:
		if deadline > 0 and Time.get_ticks_usec() > deadline and best.score > -BIG:
			break
		var KR: Array = kre[1]
		var skip = false
		for bm in kr_bad:
			if (int(kre[0]) & int(bm)) == int(bm):
				skip = true
				break
		if skip:
			continue
		var usedR = {}
		var costR = 0.0
		var groupsR: Array = []
		if not KR.is_empty():
			var r = alloc_kill(items, usedR, KR, "ranged")
			if r.is_empty():
				kr_bad.append(int(kre[0]))
				continue
			costR = float(r.cost)
			groupsR = r.groups
			for g in groupsR:
				_mark(usedR, g.picks)
		var rest: Array = []
		for m in alive:
			if not m in KR:
				rest.append(m)
		# attacks that will hit in the block phase
		var hits: Array = []
		if phase in ["ranged", "block"]:
			for m in rest:
				if m.no_attack or m.hidden:
					continue
				for at in m.atks:
					if at.blocked or int(at.n) <= 0:
						continue
					var a2: Dictionary = at.duplicate()
					a2["eid"] = m.eid
					a2["swift"] = m.swift
					a2["brutal"] = m.brutal
					a2["poison"] = m.poison
					a2["paralyze"] = m.paralyze
					hits.append(a2)
				if phase == "ranged" and m.summon:
					var sa: Dictionary = SUMMON_ATK.duplicate()
					sa["eid"] = ""
					hits.append(sa)
		var targets_a: Array = []
		for m in rest:
			if not m.summoned:
				targets_a.append(m)
		# order 1: blocks first (computed once for this ranged choice)
		var bl1 = _greedy_blocks(items, usedR, hits, cfg)
		var dmg1 = damage_cost(bl1.unblocked, cfg)
		var used1: Dictionary = usedR.duplicate()
		for blk in bl1.blocks:
			_mark(used1, blk.picks)
		if dmg1.ko:
			for ii in items.size():
				if items[ii].kind == "card":
					used1[ii] = true
		var ka_bad: Array = []
		var ka_list = subsets(targets_a, cap)
		var n0 = 0
		for kae in ka_list:
			if deadline > 0 and Time.get_ticks_usec() > deadline and best.score > -BIG:
				break
			var KA: Array = kae[1]
			var skip2 = false
			for bm2 in ka_bad:
				if (int(kae[0]) & int(bm2)) == int(bm2):
					skip2 = true
					break
			if skip2:
				continue
			var r0 = alloc_kill(items, usedR, KA, "attack")
			if r0.is_empty():
				ka_bad.append(int(kae[0]))
				continue
			var base = (_fame_of(KR) + _fame_of(KA)) * fm - costR
			if bonus != 0.0:
				if _all_dead(defs, KR, KA):
					base += bonus
				elif prog > 0.0:
					base += prog * float(_n_dead(defs, KR, KA))
			# order 1
			var r1 = alloc_kill(items, used1, KA, "attack")
			if not r1.is_empty():
				var sc1 = base - float(bl1.cost) - float(dmg1.cost) - float(r1.cost)
				if sc1 > float(best.score):
					best = {"score": sc1, "groupsR": groupsR, "blocks": bl1.blocks, "groupsA": r1.groups, "kills": _ids(KR + KA), "ko": dmg1.ko, "dmg": dmg1}
			# order 0: attack cards reserved first, blocks with what is left
			if not hits.is_empty() and not KA.is_empty() and n0 < 12:
				n0 += 1
				var used0: Dictionary = usedR.duplicate()
				for g in r0.groups:
					_mark(used0, g.picks)
				var bl0 = _greedy_blocks(items, used0, hits, cfg)
				var dmg0 = damage_cost(bl0.unblocked, cfg)
				var ok0 = true
				if dmg0.ko:
					for g2 in r0.groups:
						for pk in g2.picks:
							if items[pk[0]].kind == "card":
								ok0 = false
				if ok0:
					var sc0 = base - float(r0.cost) - float(bl0.cost) - float(dmg0.cost)
					if sc0 > float(best.score):
						best = {"score": sc0, "groupsR": groupsR, "blocks": bl0.blocks, "groupsA": r0.groups, "kills": _ids(KR + KA), "ko": dmg0.ko, "dmg": dmg0}
	return best

## Plan, then make sure the powered plays of the plan can be paid together (one die per turn...);
## if not, disable the most expensive conflicting powered option and plan again.
static func plan_checked(items: Array, enemies: Array, phase: String, cfg: Dictionary, mp: Dictionary) -> Dictionary:
	var pl = plan(items, enemies, phase, cfg)
	for it_n in 4:
		var needs: Array = []
		var powered: Array = []
		for key in ["groupsR", "blocks", "groupsA"]:
			for g in pl.get(key, []):
				for pk in g.picks:
					var o: Dictionary = items[pk[0]].opts[pk[1]]
					if not o.needs.is_empty():
						needs.append_array(o.needs)
						powered.append(pk)
		# discards required by the plan must find free cards in hand
		var disc = 0
		var card_picks = 0
		var disc_pk: Array = []
		for key2 in ["groupsR", "blocks", "groupsA"]:
			for g2 in pl.get(key2, []):
				for pk3 in g2.picks:
					var it3: Dictionary = items[pk3[0]]
					if it3.kind == "card":
						card_picks += 1
					var o3: Dictionary = it3.opts[pk3[1]]
					if int(o3.b.disc) > 0:
						disc += int(o3.b.disc)
						disc_pk = pk3
		var free_cards = int(cfg.get("hand_cards", 99)) - card_picks
		if disc > free_cards and not disc_pk.is_empty():
			var itd: Dictionary = items[disc_pk[0]]
			var optsd: Array = itd.opts.duplicate()
			var od: Dictionary = optsd[disc_pk[1]].duplicate()
			od["c"] = 1.0e6
			optsd[disc_pk[1]] = od
			itd["opts"] = optsd
			pl = plan(items, enemies, phase, cfg)
			continue
		if needs.is_empty() or C.mana_cost(mp, needs) >= 0.0:
			return pl
		# disable the last powered option (later phases first) and retry
		var pk2: Array = powered[powered.size() - 1]
		var it: Dictionary = items[pk2[0]]
		var opts: Array = it.opts.duplicate()
		var o2: Dictionary = opts[pk2[1]].duplicate()
		o2["c"] = 1.0e6
		opts[pk2[1]] = o2
		it["opts"] = opts
		pl = plan(items, enemies, phase, cfg)
	return pl

static func _ids(K: Array) -> Array:
	var out: Array = []
	for m in K:
		out.append(m.eid)
	return out

static func _n_dead(defs: Array, KR: Array, KA: Array) -> int:
	var n = 0
	for m in KR + KA:
		if m.eid in defs:
			n += 1
	return n

static func _all_dead(defs: Array, KR: Array, KA: Array) -> bool:
	for eid in defs:
		var dead = false
		for m in KR:
			if m.eid == eid:
				dead = true
				break
		if not dead:
			for m2 in KA:
				if m2.eid == eid:
					dead = true
					break
		if not dead:
			return false
	return true

static func _greedy_blocks(items: Array, used: Dictionary, hits: Array, cfg: Dictionary) -> Dictionary:
	if hits.is_empty():
		return {"cost": 0.0, "blocks": [], "unblocked": []}
	var cands: Array = []
	for at in hits:
		var dc: Dictionary = damage_cost([at], cfg)
		cands.append([float(dc.cost) + (2.0 if dc.ko else 0.0), at])
	cands.sort_custom(func(a, b): return a[0] > b[0])
	var cost = 0.0
	var blocks: Array = []
	var unblocked: Array = []
	for cd in cands:
		var at: Dictionary = cd[1]
		var saved: float = cd[0]
		if saved <= 0.05 or str(at.get("eid", "")) == "":
			# phantom summon attacks cannot be planned exactly: assume they are blocked half the time
			if str(at.get("eid", "")) == "" and saved > 0.05:
				var rb = alloc_block(items, used, at)
				if not rb.is_empty() and float(rb.cost) < saved:
					cost += float(rb.cost) * 0.8
					continue
			unblocked.append(at)
			continue
		var r = alloc_block(items, used, at)
		if not r.is_empty() and float(r.cost) < saved - 0.05:
			cost += float(r.cost)
			_mark(used, r.picks)
			blocks.append({"eid": at.eid, "i": int(at.i), "picks": r.picks})
		else:
			unblocked.append(at)
	return {"cost": cost, "blocks": blocks, "unblocked": unblocked}

# ================================================================ config helpers
static func base_cfg(eng, p: int, ctx: Dictionary) -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var units: Array = []
	var c = eng.s.combat
	var units_ok: bool = c == null or c.get("units_allowed", true)
	if units_ok and not eng.flag(p, "no_unit_damage"):
		for u in pl.units:
			if u.wounded:
				continue
			units.append({"uid": int(u.uid), "armor": MKCombat.unit_armor(eng, p, u), "resist": MKCombat.unit_resists(eng, p, u),
				"worth": C.unit_worth(str(u.id))})
	var rf: float = ctx.get("rf", 1.0)
	var hand_v = 0.0
	for iid in pl.hand:
		hand_v += C.card_value(eng, p, iid, rf)
	var wsf = int(pl.get("wounds_this_combat", 0)) if c != null else 0
	var hand_cards = 0
	for iid in pl.hand:
		if not eng.is_wound(iid):
			hand_cards += 1
	return {"fm": ctx.get("fm", 1.0), "armor": eng.armor_of(p), "hand_limit": eng.base_hand_limit(p), "wounds_so_far": wsf, "wc": ctx.get("wc", 2.6),
		"units": units, "ko_pen": hand_v * 0.8 + 2.0, "site_bonus": 0.0, "defenders_alive": [], "cap": ctx.get("cap", 32),
		"deadline": ctx.get("deadline", 0), "hand_cards": hand_cards}

## Value of conquering the site of the current/planned combat.
static func site_bonus(eng, p: int, site_type: String, hexk: String) -> float:
	var h: Dictionary = eng.hex(hexk) if hexk != "" else {}
	var solo_like: bool = eng.s.scn.get("mode", "") in ["solo", "coop"]
	match site_type:
		"keep":
			return 6.0
		"mage_tower":
			return 9.0
		"city":
			var v = 12.0
			if solo_like:
				v += 12.0
			if eng.s.scn.get("end", "") == "cities":
				# conquering the last city ends the game early (big bonus in solo/coop)
				var total = 0
				var conq = 0
				for k in eng.s.map.hex:
					if eng.s.map.hex[k].site == "city":
						total += 1
						if eng.s.map.hex[k].conquered:
							conq += 1
				if solo_like and total >= int(eng.s.scn.city) and conq == total - 1:
					v += 25.0
			return v
		"dungeon":
			return 6.0 if not h.get("conquered", false) else 0.0
		"tomb":
			return 13.0 if not h.get("conquered", false) else 0.0
		"monster_den":
			return 3.5 if not h.get("conquered", false) else 1.6
		"spawning_grounds":
			return 9.5 if not h.get("conquered", false) else 6.0
		"ruins":
			return _ruins_value(eng, str(h.get("ruins", "")))
		"monastery":
			return 6.0
	return 0.0

static func _ruins_value(eng, rid: String) -> float:
	var rd: Dictionary = MKDB.ruins.get(rid, {})
	var v = 2.0
	for r in rd.get("reward", []):
		var s = str(r).to_lower()
		if s.find("artifact") >= 0 or s.find("artefatto") >= 0:
			v += 6.0
		elif s.find("spell") >= 0 or s.find("incantesimo") >= 0:
			v += 5.5
		elif s.find("unit") >= 0:
			v += 5.0
		elif s.find("aa") >= 0 or s.find("advanced") >= 0:
			v += 4.5
		elif s.find("crystal") >= 0:
			v += 3.0
		elif s.find("fame") >= 0:
			v += 3.0
	return v

# ================================================================ in-combat decision
static func current_models(eng) -> Array:
	var out: Array = []
	for e in eng.s.combat.enemies:
		if e.defeated:
			continue
		out.append(model_entry(eng, e))
	return out

static func combat_cfg(eng, p: int, ctx: Dictionary) -> Dictionary:
	var cfg = base_cfg(eng, p, ctx)
	var c: Dictionary = eng.s.combat
	var st = str(c.get("site_type", ""))
	var kind = str(c.get("kind", ""))
	var bonus = 0.0
	if kind in ["assault", "site", "burn"]:
		bonus = site_bonus(eng, p, st, str(c.get("site", "")))
	var defs: Array = []
	for e in c.enemies:
		if e.site_def and not e.defeated:
			defs.append(str(e.eid))
	if kind in ["site", "burn"]:
		defs = []
		for e in c.enemies:
			if not e.defeated and not e.summoned:
				defs.append(str(e.eid))
	cfg.site_bonus = bonus
	cfg.defenders_alive = defs
	if kind == "assault" or st in ["monster_den", "spawning_grounds", "ruins"]:
		cfg["progress"] = 0.35 * bonus / float(maxi(1, defs.size()))
	return cfg

## Plan for the current combat state.
static func plan_now(eng, p: int, ctx: Dictionary) -> Dictionary:
	var items = gather(eng, p, ctx)
	var cfg = combat_cfg(eng, p, ctx)
	var models = current_models(eng)
	var ph = str(eng.s.combat.phase)
	var pl = plan_checked(items, models, ph, cfg, ctx.get("mp", C.mana_pool(eng, p)))
	pl["items"] = items
	pl["models"] = models
	return pl

## Choose the next combat action. mem: per-player memory (intent for pending choices).
static func decide(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var c: Dictionary = eng.s.combat
	var ph = str(c.phase)
	if ph == "damage":
		return decide_damage(eng, p, ctx)
	if ph == "end":
		return {}
	var pl = plan_now(eng, p, ctx)
	var level: int = int(ctx.get("level", 2))
	# 1-ply lookahead on actions with effects the planner does not model (specials)
	if level >= 2 and Time.get_ticks_usec() < int(ctx.get("deadline", 0)):
		var alt = _special_lookahead(eng, p, ctx, pl)
		if not alt.is_empty():
			mem["intent"] = {"kind": "special"}
			return alt
	var steps: Array = []
	var finkind = "attack"
	match ph:
		"ranged":
			steps = pl.get("groupsR", [])
		"block":
			steps = pl.get("blocks", [])
			finkind = "block"
		"attack":
			steps = pl.get("groupsA", [])
	var items: Array = pl.items
	for g in steps:
		var fin: Dictionary
		if finkind == "block":
			fin = {"t": "block", "eid": str(g.eid), "attack": int(g.i)}
		else:
			fin = {"t": "attack", "targets": g.targets.duplicate()}
		if eng.check(fin) == "":
			return fin
		var tried = false
		for pk in g.picks:
			var it: Dictionary = items[pk[0]]
			if it.kind == "pool":
				continue
			var o: Dictionary = it.opts[pk[1]]
			var a: Dictionary = o.act
			if eng.check(a) == "":
				mem["intent"] = _intent_for(pl, g, finkind, ph, o)
				mem.intent["reserve"] = _planned_cards(pl)
				return a
			tried = true
		if tried:
			break
	# nothing more planned in this phase: if the pool already allows a useful attack/block, do it
	var extra = _opportunistic(eng, p, ph)
	if not extra.is_empty():
		return extra
	return {"t": "next"}

static func _planned_cards(pl: Dictionary) -> Array:
	var out: Array = []
	for key in ["groupsR", "blocks", "groupsA"]:
		for g in pl.get(key, []):
			for pk in g.picks:
				var it: Dictionary = pl.items[pk[0]]
				if it.kind == "card":
					out.append(str(it.key))
	return out

static func _intent_for(pl: Dictionary, g: Dictionary, finkind: String, ph: String, o: Dictionary) -> Dictionary:
	var models: Array = pl.models
	if finkind == "block":
		for m in models:
			if m.eid == str(g.eid):
				for at in m.atks:
					if int(at.i) == int(g.i):
						var a2: Dictionary = at.duplicate()
						a2["swift"] = m.swift
						return {"kind": "blk", "at": a2, "want": o.b}
		return {"kind": "blk", "at": {"n": 1, "elem": "phys", "swift": false}, "want": o.b}
	var grp: Array = []
	for m in models:
		if m.eid in g.targets:
			grp.append(m)
	return {"kind": "atk", "group": grp, "ph": ph, "want": o.b}

static func _opportunistic(eng, p: int, ph: String) -> Dictionary:
	var c: Dictionary = eng.s.combat
	if ph == "ranged" or ph == "attack":
		if eng.s.turn.pool.attack.is_empty():
			return {}
		var best = {}
		var bf = -1.0
		var tg: Array = []
		for e in c.enemies:
			if MKCombat.targetable(eng, e):
				tg.append(e)
		for e in tg:
			var a = {"t": "attack", "targets": [str(e.eid)]}
			if eng.check(a) == "" and float(e.fame) > bf:
				bf = float(e.fame)
				best = a
		return best
	if ph == "block":
		if eng.s.turn.pool.block.is_empty() and int(eng.s.turn.get("block_swift", 0)) == 0:
			return {}
		var best2 = {}
		var bd = -1
		for e in c.enemies:
			if e.defeated or e.hidden:
				continue
			for i in e.attacks.size():
				var a2 = {"t": "block", "eid": str(e.eid), "attack": i}
				if eng.check(a2) == "":
					var d = MKCombat.attack_value(eng, e, i) * (2 if MKCombat.has_ab(e, "brutal") else 1)
					if d > bd:
						bd = d
						best2 = a2
		return best2
	return {}

# ---------------------------------------------------------------- damage assignment
static func decide_damage(eng, p: int, ctx: Dictionary) -> Dictionary:
	var c: Dictionary = eng.s.combat
	var cfg = base_cfg(eng, p, ctx)
	var pl: Dictionary = eng.P(p)
	var best = {}
	var best_d = -1
	var best_e = null
	var best_i = 0
	for e in c.enemies:
		for i in e.attacks.size():
			if int(e.attacks[i].rem) > 0 and int(e.attacks[i].rem) > best_d:
				best_d = int(e.attacks[i].rem)
				best_e = e
				best_i = i
	if best_e == null:
		return {"t": "next"}
	var e2: Dictionary = best_e
	var at = {"n": best_d, "elem": MKCombat.attack_elem(e2, best_i), "brutal": false, "poison": MKCombat.has_ab(e2, "poison"),
		"paralyze": MKCombat.has_ab(e2, "paralyze")}
	var hero = {"t": "damage", "eid": str(e2.eid), "attack": best_i, "to": "hero"}
	var hc: Array = hero_cost(best_d, at, cfg)
	var best_c: float = hc[0]
	# KO check for the hero option
	if int(cfg.wounds_so_far) + int(hc[1]) >= int(cfg.hand_limit) and int(hc[1]) > 0:
		best_c += float(cfg.ko_pen)
	best = hero
	for u in cfg.units:
		var a = {"t": "damage", "eid": str(e2.eid), "attack": best_i, "to": int(u.uid)}
		if eng.check(a) != "":
			continue
		var ud: Array = unit_dmg(best_d, at, u)
		var c2: float = ud[0]
		if int(ud[1]) > 0:
			c2 += hero_cost(int(ud[1]), at, cfg)[0] * 0.9
		if c2 < best_c - 0.01:
			best_c = c2
			best = a
	if eng.check(best) != "":
		best = hero
	return best

# ---------------------------------------------------------------- lookahead on specials
static func _special_lookahead(eng, p: int, ctx: Dictionary, base_plan: Dictionary) -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var cands: Array = []
	var cctx = C.base_ctx(eng, p, true, str(eng.s.combat.phase))
	cctx["level"] = int(ctx.get("level", 2))
	var seen = {}
	for iid in pl.hand:
		if eng.is_wound(iid):
			continue
		var cid: String = eng.card_id(iid)
		if seen.has(cid):
			continue
		seen[cid] = true
		var c: Dictionary = eng.card(iid)
		for mode in ["basic", "powered"]:
			var effs = c.get(mode, [])
			if not (effs is Array) or effs.is_empty():
				continue
			if not _has_special(effs, cctx):
				continue
			var a = {"t": "play", "card": iid, "mode": mode}
			if eng.check(a) == "":
				cands.append([a, C.card_value(eng, p, iid, float(ctx.get("rf", 1.0))) + (2.5 if mode == "powered" and str(c.get("type", "")) == "artifact" else 0.0)])
	if eng.units_usable():
		for u in pl.units:
			if not u.ready or u.wounded:
				continue
			var abs: Array = eng.unit_def(u).get("abilities", [])
			for i in abs.size():
				if _has_special(abs[i].get("effect", []), cctx):
					var a2 = {"t": "unit", "uid": int(u.uid), "ability": i}
					if eng.check(a2) == "":
						cands.append([a2, C.unit_use_cost(eng, p, u, float(ctx.get("rf", 1.0)))])
	for sk in pl.skills:
		var d: Dictionary = MKDB.skills.get(sk.id, {})
		if _has_special(d.get("effect", []), cctx):
			var a3 = {"t": "skill", "id": str(sk.id)}
			if eng.check(a3) == "":
				cands.append([a3, 0.3])
	if cands.is_empty():
		return {}
	var base_score: float = float(base_plan.score)
	var fame0 = int(pl.fame)
	var best = {}
	var best_gain = 0.6
	for cd in cands:
		if Time.get_ticks_usec() > int(ctx.get("deadline", 0)):
			break
		var e2 = light_clone(eng)
		var r: Dictionary = e2.apply(cd[0])
		if not r.ok:
			continue
		_resolve_quick(e2, p, ctx, 0)
		if e2.s.combat == null:
			# the combat ended (e.g. last enemy destroyed)
			var gain0 = float(int(e2.P(p).fame) - fame0) - float(cd[1])
			if gain0 > best_gain:
				best_gain = gain0
				best = cd[0]
			continue
		if e2.s.pending != null:
			continue
		var ctx2: Dictionary = ctx.duplicate()
		ctx2["mp"] = C.mana_pool(e2, p)
		ctx2["cap"] = 16
		var pl2 = plan_now(e2, p, ctx2)
		var gain: float = float(pl2.score) + float(int(e2.P(p).fame) - fame0) - float(cd[1]) - base_score
		gain -= _wounds_delta(eng, e2, p) * float(ctx.get("wc", 2.6))
		if gain > best_gain:
			best_gain = gain
			best = cd[0]
	return best

static func _wounds_delta(e1, e2, p: int) -> float:
	var w1 = 0
	var w2 = 0
	for iid in e1.P(p).hand + e1.P(p).discard:
		if e1.is_wound(iid):
			w1 += 1
	for iid in e2.P(p).hand + e2.P(p).discard:
		if e2.is_wound(iid):
			w2 += 1
	return float(w2 - w1)

static func _has_special(effs, cctx: Dictionary) -> bool:
	for b in C.parse(effs, cctx):
		for s in b.sp:
			var n = str(s)
			if n.begins_with("mod:") or n in ["extra_die", "die", "ready_unit", "heal_unit"]:
				continue
			return true
		# mana generators can enable powered plays: evaluate them by lookahead too (Difficile)
		if not b.tok.is_empty() and b.atk.is_empty() and b.blk.is_empty() and int(cctx.get("level", 3)) >= 3:
			return true
	return false

## Resolve pending decisions on a simulation clone with a combat-aware heuristic (enemy targets by lookahead).
static func _resolve_quick(e2, p: int, ctx: Dictionary, depth: int) -> void:
	var guard = 0
	while e2.s.pending != null and guard < 6:
		guard += 1
		var pend: Dictionary = e2.s.pending
		if int(pend.player) != p:
			return
		var opts: Array = pend.options
		if opts.is_empty():
			return
		var pick = opts[0].v
		if (str(pend.get("type", "")) == "enemy" or str(pend.get("handler", "")) in ["boost_play", "choice", "color"]) and depth < 1 and opts.size() <= 6:
			var bs = -BIG
			for o in opts:
				var e3 = light_clone(e2)
				if not e3.apply({"t": "choose", "v": [o.v]}).ok:
					continue
				_resolve_quick(e3, p, ctx, depth + 1)
				var sc = float(e3.P(p).fame)
				if e3.s.combat != null and e3.s.pending == null:
					var ctx2: Dictionary = ctx.duplicate()
					ctx2["cap"] = 8
					ctx2["mp"] = C.mana_pool(e3, p)
					sc += float(plan_now(e3, p, ctx2).score)
				if sc > bs:
					bs = sc
					pick = o.v
		else:
			pick = _quick_pick(e2, p, pend)
		if not e2.apply({"t": "choose", "v": [pick]}).ok:
			return

static func _quick_pick(e2, p: int, pend: Dictionary):
	var opts: Array = pend.options
	var h = str(pend.get("handler", ""))
	if h == "choice" and e2.s.combat != null:
		# prefer the option adding the most attack/block for the phase
		var ph = str(e2.s.combat.phase)
		var data: Dictionary = pend.get("data", {})
		var all_opts: Array = data.get("opts", [])
		var best = opts[0].v
		var bv = -1
		var cctx = C.base_ctx(e2, p, true, ph)
		for o in opts:
			var i = int(o.v)
			if i < 0 or i >= all_opts.size():
				continue
			var v = 0
			for b in C.parse(all_opts[i], cctx):
				var t = 0
				for k in b.atk:
					if ph == "block":
						continue
					t += int(b.atk[k])
				if ph == "block":
					for k2 in b.blk:
						t += int(b.blk[k2])
					t += int(b.bsw)
				if not b.sp.is_empty():
					t += 1
				v = maxi(v, t)
			if v > bv:
				bv = v
				best = o.v
		return best
	for o in opts:
		var lbl = str(o.get("label", "")).to_lower()
		if lbl.find("rinuncia") < 0 and lbl.find("nessun") < 0 and str(o.v) != "" and str(o.v) != "-1":
			return o.v
	return opts[0].v

## Deep copy of the state without the log (cheap simulation copy).
static func light_clone(eng):
	var st: Dictionary = eng.s.duplicate(false)
	st["log"] = []
	var e2 = MKEngine.new()
	e2.s = st.duplicate(true)
	return e2
