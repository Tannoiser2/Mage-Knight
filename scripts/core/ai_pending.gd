extends RefCounted
## AI helper (agent AI): answers to pending decisions (s.pending).

const C = preload("res://scripts/core/ai_cards.gd")
const CB = preload("res://scripts/core/ai_combat.gd")

static func decide(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var pend: Dictionary = eng.s.pending
	var opts: Array = pend.get("options", [])
	if opts.is_empty():
		return {}
	if opts.size() == 1:
		return _ch(opts[0].v)
	var h = str(pend.get("handler", ""))
	var v = null
	match h:
		"choice":
			v = _effect_choice(eng, p, pend, ctx, mem)
		"color":
			v = _color(eng, p, opts, str(pend.get("data", {}).get("what", "mana")))
		"pay_mana":
			v = _pay_mana(eng, p, opts)
		"discard", "rest_card", "end_discard":
			v = _discard(eng, p, opts, ctx, mem.get("intent", {}).get("reserve", []) if h == "discard" else [])
		"rest_wound":
			v = "all"
		"boost_play":
			v = _boost(eng, p, opts, ctx, mem)
		"unit_ready", "unit_heal":
			v = _best_unit(eng, p, opts)
		"reward_spell", "reward_aa", "level_aa", "reward_artifact":
			v = _best_pick(opts)
		"reward_unit":
			v = _reward_unit(eng, p, opts)
		"reward_unit_disband":
			v = _disband(eng, p, opts, str(pend.get("data", {}).get("id", "")))
		"reward_crystal", "mine":
			v = _color(eng, p, opts, "crystal")
		"level_skill":
			v = _skill(eng, p, opts, ctx)
		"tactic_rethink", "tactic_meditation":
			v = _cycle(eng, p, opts, pend)
		"tactic_preparation":
			v = _preparation(eng, p, opts)
		"tactic_steal":
			v = _steal(eng, p, opts)
		"tactic_search":
			v = _search(eng, p, opts)
		_:
			v = _generic(eng, p, pend, ctx)
	if v == null:
		v = opts[0].v
	var a = _ch(v)
	if eng.check(a) != "":
		return _ch(opts[0].v)
	return a

static func _ch(v) -> Dictionary:
	return {"t": "choose", "v": [v]}

# ---------------------------------------------------------------- effect choices
static func _effect_choice(eng, p: int, pend: Dictionary, ctx: Dictionary, mem: Dictionary):
	var opts: Array = pend.options
	var data: Dictionary = pend.get("data", {})
	var all_opts: Array = data.get("opts", [])
	var cb = eng.s.combat
	var intent: Dictionary = mem.get("intent", {})
	var cctx = C.base_ctx(eng, p, cb != null, str(cb.phase) if cb != null else "")
	var best = null
	var bv = -INF
	for o in opts:
		var i = int(o.v)
		if i < 0 or i >= all_opts.size():
			continue
		var v = -INF
		for b in C.parse(all_opts[i], cctx):
			v = maxf(v, _bundle_score(eng, p, b, intent, cb))
		if v > bv + 0.001:
			bv = v
			best = o.v
	if best == null:
		return _generic(eng, p, pend, ctx)
	# combat options with specials: compare by lookahead when ambiguous
	return best

## Score a bundle against the current intent (or a generic context score).
static func _bundle_score(eng, p: int, b: Dictionary, intent: Dictionary, cb) -> float:
	var kind = str(intent.get("kind", ""))
	var s = 0.0
	if kind == "atk" and cb != null:
		s = float(CB.atk_v2(b, intent.group, str(intent.ph))) * 0.5
		if not intent.group.is_empty():
			s = minf(s, float(CB.group_armor(intent.group)) + 0.5) + 0.05 * float(CB.atk_v2(b, intent.group, str(intent.ph)))
	elif kind == "blk" and cb != null:
		s = float(CB.blk_v2(b, intent.at)) * 0.5
	elif cb != null:
		var ph = str(cb.phase)
		if ph == "block":
			for k in b.blk:
				s += float(b.blk[k])
			s += float(b.bsw)
		elif ph in ["ranged", "attack"]:
			for k in b.atk:
				if ph == "ranged" and str(k).begins_with("melee"):
					continue
				s += float(b.atk[k])
	else:
		var want = str(intent.get("want", ""))
		match want:
			"move":
				s = float(b.move) + 0.5 * float(b.terr)
			"inf":
				s = float(b.inf)
			"heal":
				s = float(b.heal) * 2.0
			_:
				s = float(b.move) * 0.5 + float(b.inf) * 0.4 + float(b.heal) * 1.5 + float(b.draw) * 0.3
		s += float(b.fame) + 0.8 * _sum(b.crys) + 0.3 * _sum(b.tok)
	s += float(b.fame)
	s -= float(b.wound) * 2.6 + float(b.disc) * 0.9
	if b.rep < 0:
		s += float(b.rep) * 0.6
	return s

static func _sum(d: Dictionary) -> float:
	var t = 0.0
	for k in d:
		t += float(d[k])
	return t

# ---------------------------------------------------------------- mana / colours
## Colours needed by powered effects of the hand (count), used to pick tokens/crystals.
static func needed_colors(eng, p: int) -> Dictionary:
	var need = {"red": 0.0, "blue": 0.0, "green": 0.0, "white": 0.0}
	for iid in eng.P(p).hand:
		if eng.is_wound(iid):
			continue
		var c: Dictionary = eng.card(iid)
		var cols: Array = []
		var cc = c.get("colors", [])
		if cc is Array and cc.size() > 0:
			cols = cc
		elif str(c.get("color", "")) != "":
			cols = [str(c.color)]
		for col in cols:
			if need.has(col):
				need[col] += 1.0 + (0.5 if str(c.get("type", "")) in ["aa", "spell"] else 0.0)
	return need

static func _color(eng, p: int, opts: Array, what: String):
	var need = needed_colors(eng, p)
	var pl: Dictionary = eng.P(p)
	var best = null
	var bv = -INF
	for o in opts:
		var col = str(o.v)
		var v = 0.0
		if col == "gold":
			v = 2.0
		elif need.has(col):
			v = float(need[col])
			if what == "crystal":
				v -= 0.6 * float(pl.crystals.get(col, 0))
				if int(pl.crystals.get(col, 0)) >= 3:
					v -= 5.0
			else:
				# tokens: avoid colours we already have plenty of
				v -= 0.3 * float(pl.crystals.get(col, 0))
		elif col == "black":
			v = 0.5 if not eng.s.day else -1.0
		if v > bv:
			bv = v
			best = o.v
	return best

static func _pay_mana(eng, p: int, opts: Array):
	# tokens first, then dice, then crystals
	var best = null
	var bs = 99
	for o in opts:
		var v = str(o.v)
		var s = 5
		if v.begins_with("token:"):
			s = 0
		elif v.begins_with("stolen"):
			s = 1
		elif v.begins_with("die:"):
			s = 2
		elif v.begins_with("crystal:"):
			s = 3
		if s < bs:
			bs = s
			best = o.v
	return best

# ---------------------------------------------------------------- cards
static func _discard(eng, p: int, opts: Array, ctx: Dictionary, reserve: Array = []):
	var best = null
	var bv = INF
	for o in opts:
		var iid = str(o.v)
		var v = C.card_value(eng, p, iid, 1.0)
		if iid in reserve:
			v += 10.0
		if eng.is_wound(iid):
			v = -1.0
		if v < bv:
			bv = v
			best = o.v
	return best

static func _boost(eng, p: int, opts: Array, ctx: Dictionary, mem: Dictionary):
	var cb = eng.s.combat
	var best = null
	var bv = -INF
	var cctx = C.base_ctx(eng, p, cb != null, str(cb.phase) if cb != null else "")
	for o in opts:
		var iid = str(o.v)
		var c: Dictionary = eng.card(iid)
		var ctx2 = cctx.duplicate()
		ctx2["boost"] = 2
		var v = -INF
		for b in C.parse(c.get("powered", []), ctx2):
			v = maxf(v, _bundle_score(eng, p, b, mem.get("intent", {}), cb))
		v -= 0.3 * C.card_value(eng, p, iid, 1.0)
		if v > bv:
			bv = v
			best = o.v
	return best

static func _best_unit(eng, p: int, opts: Array):
	var best = null
	var bl = -1
	for o in opts:
		var u = eng.find_unit(p, o.v)
		if u == null:
			continue
		var lv: int = eng.unit_level(u)
		if lv > bl:
			bl = lv
			best = o.v
	return best

static func _best_pick(opts: Array):
	var best = null
	var bv = -INF
	for o in opts:
		var v = C.pick_value(str(o.v))
		if v > bv:
			bv = v
			best = o.v
	return best

static func _reward_unit(eng, p: int, opts: Array):
	var best = null
	var bv = 0.0
	for o in opts:
		if str(o.v) == "":
			continue
		var v = C.unit_worth(str(o.v))
		if v > bv:
			bv = v
			best = o.v
	return best if best != null else ""

static func _disband(eng, p: int, opts: Array, new_id: String):
	var nv = C.unit_worth(new_id)
	var worst = -1
	var wv = INF
	for o in opts:
		if int(o.v) == -1:
			continue
		var u = eng.find_unit(p, o.v)
		if u == null:
			continue
		var v = C.unit_worth(str(u.id)) * (0.6 if u.wounded else 1.0)
		if v < wv:
			wv = v
			worst = o.v
	if worst != -1 and wv < nv - 0.5:
		return worst
	return -1

static func _cycle(eng, p: int, opts: Array, pend: Dictionary):
	# Rethink / Midnight Meditation: cycle away wounds and the weakest cards
	var chosen: Array = pend.get("data", {}).get("chosen", [])
	var best = null
	var bv = 0.75
	for o in opts:
		if str(o.v) == "done":
			continue
		var iid = str(o.v)
		var v = C.card_value(eng, p, iid, 1.0)
		if eng.is_wound(iid):
			v = -1.0
		if v < bv:
			bv = v
			best = o.v
	if best == null:
		return "done"
	return best

static func _preparation(eng, p: int, opts: Array):
	var best = null
	var bv = -INF
	for o in opts:
		var v = C.card_value(eng, p, str(o.v), 1.0)
		if v > bv:
			bv = v
			best = o.v
	return best

static func _steal(eng, p: int, opts: Array):
	var need = needed_colors(eng, p)
	var best = null
	var bv = -INF
	for o in opts:
		if int(o.v) == -1:
			continue
		var d: Dictionary = eng.s.source[int(o.v)]
		var v = float(need.get(str(d.color), 0.0))
		if v > bv:
			bv = v
			best = o.v
	return best if best != null else -1

static func _search(eng, p: int, opts: Array):
	# reroll a die we cannot use (black by day / gold by night) if any
	for o in opts:
		if int(o.v) < 0:
			continue
		var d: Dictionary = eng.s.source[int(o.v)]
		if (eng.s.day and d.color == "black") or (not eng.s.day and d.color == "gold"):
			return o.v
	return -1

static func _skill(eng, p: int, opts: Array, ctx: Dictionary):
	var best = null
	var bv = -INF
	for o in opts:
		var sv = str(o.v)
		var id = sv.substr(sv.find(":") + 1)
		var v = skill_value(id)
		if sv.begins_with("common:"):
			v -= 0.8
		if v > bv:
			bv = v
			best = o.v
	return best

static func skill_value(id: String) -> float:
	var d: Dictionary = MKDB.skills.get(id, {})
	var v = 3.0
	var usage = str(d.get("usage", "turn"))
	var eff = d.get("effect", [])
	for b in C.parse(eff, {"day": true, "combat": true, "phase": "any"}):
		var t = 0.0
		for k in b.atk:
			t += float(b.atk[k]) * (1.6 if not str(k).begins_with("melee") else 1.0)
		for k2 in b.blk:
			t += float(b.blk[k2]) * 0.9
		t += float(b.move) * 0.9 + float(b.inf) * 0.6 + float(b.heal) * 1.2
		t += _sum(b.crys) * 1.0 + _sum(b.tok) * 0.5 + float(b.draw) * 0.6
		v = maxf(v, 2.0 + t)
	for b2 in C.parse(eff, {"day": false, "combat": false, "phase": ""}):
		v = maxf(v, 2.0 + float(b2.move) * 0.9 + float(b2.inf) * 0.6 + float(b2.heal) * 1.2)
	if usage == "turn":
		v *= 1.25
	elif usage == "interactive":
		v *= 0.6
	return v

# ---------------------------------------------------------------- generic (lookahead on a clone)
static func _generic(eng, p: int, pend: Dictionary, ctx: Dictionary):
	var opts: Array = pend.options
	if opts.size() > 8 or Time.get_ticks_usec() > int(ctx.get("deadline", 0)):
		return CB._quick_pick(eng, p, pend)
	var best = null
	var bv = -INF
	for o in opts:
		var e2 = CB.light_clone(eng)
		if not e2.apply({"t": "choose", "v": [o.v]}).ok:
			continue
		CB._resolve_quick(e2, p, ctx, 1)
		var v = state_value(e2, p, ctx)
		var lbl = str(o.get("label", "")).to_lower()
		if lbl.find("rinuncia") >= 0 or lbl.find("nessun") >= 0:
			v -= 0.05
		if v > bv:
			bv = v
			best = o.v
	return best

## Quick static value of a state for player p (fame-equivalent).
static func state_value(e2, p: int, ctx: Dictionary) -> float:
	var pl: Dictionary = e2.P(p)
	var v = float(pl.fame)
	var rf = 1.0
	for iid in pl.hand:
		v += C.card_value(e2, p, iid, rf) * 0.9
		if e2.is_wound(iid):
			v -= 2.6
	for iid in pl.deck + pl.discard + pl.play:
		if e2.is_wound(iid):
			v -= 2.0
		else:
			v += C.card_base_value(e2.card_id(iid)) * 0.5
	for c in C.BASIC:
		v += 0.9 * float(pl.crystals.get(c, 0))
	v += 0.25 * float(pl.tokens.size())
	for u in pl.units:
		v += C.unit_worth(str(u.id)) * (0.6 if u.wounded else 1.0)
	v += 0.5 * float(pl.rep)
	var pool: Dictionary = e2.s.turn.get("pool", {})
	if not pool.is_empty() and int(e2.s.turn.get("player", -1)) == p:
		v += 0.15 * float(pool.get("move", 0)) + 0.12 * float(pool.get("influence", 0)) + 0.6 * float(pool.get("heal", 0))
		for k in pool.get("attack", {}):
			v += 0.2 * float(pool.attack[k])
		for k in pool.get("block", {}):
			v += 0.15 * float(pool.block[k])
	if e2.s.combat != null and int(e2.s.turn.get("player", -1)) == p and e2.s.pending == null:
		var ctx2: Dictionary = ctx.duplicate()
		ctx2["cap"] = 8
		ctx2["mp"] = C.mana_pool(e2, p)
		var ph = str(e2.s.combat.phase)
		if ph in ["ranged", "block", "attack"]:
			v += float(CB.plan_now(e2, p, ctx2).score)
	return v
