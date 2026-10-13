extends RefCounted
## AI helper (agent AI): static analysis of effect lists (cards, units, skills)
## into "bundles" of resources, card/unit valuations and mana feasibility.
##
## Bundle = {move, inf, heal, draw, fame, rep, atk:{"kind:elem": n}, blk:{elem: n}, bsw (block counted
##   double vs swift), tok:{color: n}, crys:{color: n}, mana:[colors paid by pay_mana], disc, wound, sp:[names]}

const MAXALT := 24
const BASIC := ["red", "blue", "green", "white"]

# opportunity value of a card kept in hand (fame-equivalent), by card id; default by type
const CARD_V := {"march": 0.6, "stamina": 0.6, "swiftness": 0.75, "rage": 0.75, "determination": 0.8,
	"promise": 0.55, "threaten": 0.6, "crystallize": 0.5, "concentration": 0.85, "tranquility": 0.65,
	"improvisation": 0.9, "mana_draw": 0.65, "battle_versatility": 1.0, "mana_pull": 0.7, "will_focus": 0.9,
	"crystal_joy": 0.65, "noble_manners": 0.75, "rejuvenate": 0.8, "cold_toughness": 0.95, "instinct": 1.0}
const TYPE_V := {"basic": 0.7, "aa": 1.2, "spell": 1.5, "artifact": 1.6, "wound": 0.0}

# reward preferences (higher = better), others default by type
const PICK_V := {
	# spells
	"fireball": 9.0, "snowstorm": 8.5, "flame_wall": 8.0, "mana_bolt": 8.5, "tremor": 7.0, "demolish": 7.0,
	"burning_shield": 6.5, "chill": 7.0, "whirlwind": 8.0, "expose": 6.5, "restoration": 6.0, "call_to_arms": 7.5,
	"wings_of_wind": 5.5, "space_bending": 5.0, "underground_travel": 5.0, "energy_flow": 5.5, "meditation": 4.5,
	"mana_meltdown": 4.0, "mana_claim": 4.5, "mind_read": 4.0,
	# advanced actions
	"blood_rage": 7.0, "intimidate": 6.0, "ice_shield": 6.0, "fire_bolt": 6.5, "ice_bolt": 6.5, "swift_bolt": 7.0,
	"crushing_bolt": 7.5, "agility": 6.0, "refreshing_walk": 6.0, "frost_bridge": 5.0, "song_of_wind": 5.5,
	"path_finding": 6.5, "pure_magic": 7.0, "heroic_tale": 5.5, "regeneration": 5.5, "into_the_heat": 6.0,
	"steady_tempo": 5.0, "diplomacy": 6.0, "in_need": 5.0, "decompose": 4.5, "crystal_mastery": 5.0,
	"mana_storm": 5.0, "ambush": 6.0, "maximal_effect": 6.0, "magic_talent": 5.0, "learning": 5.0, "training": 5.0,
	"blood_ritual": 5.0,
	# artifacts
	"sword_of_justice": 9.0, "horn_of_wrath": 8.5, "banner_of_glory": 7.0, "banner_of_fear": 7.5,
	"banner_of_protection": 7.0, "banner_of_courage": 6.5, "endless_bag_of_gold": 7.0, "endless_gem_pouch": 6.5,
	"golden_grail": 7.0, "book_of_wisdom": 6.0, "amulet_of_the_sun": 6.5, "amulet_of_darkness": 6.5,
	"ruby_ring": 6.5, "sapphire_ring": 6.5, "diamond_ring": 6.0, "emerald_ring": 6.0,
}

## Tunable weights (benchmarks may override them with AI_TUNE="name=value,...").
static var tune := {"card_scale": 1.0, "wc": 2.0, "explore_bonus": 0.0, "pos_scale": 0.6, "fm_slope": 0.16, "rest_bias": 0.0,
	"idle_pen": 1.0, "goal_other": 1.0, "pos_decay": 0.82, "full_alts": 0.0, "noise3": 0.12}
static var _tune_loaded := false

static func T(name: String) -> float:
	if not _tune_loaded:
		_tune_loaded = true
		var env := OS.get_environment("AI_TUNE")
		if env != "":
			for kv in env.split(","):
				var parts := kv.split("=")
				if parts.size() == 2:
					tune[parts[0].strip_edges()] = float(parts[1])
	return float(tune.get(name, 0.0))

static func empty_b() -> Dictionary:
	return {"move": 0, "inf": 0, "heal": 0, "draw": 0, "fame": 0, "rep": 0, "atk": {}, "blk": {}, "bsw": 0,
		"tok": {}, "crys": {}, "mana": [], "disc": 0, "wound": 0, "sp": [], "terr": 0}

static func merge(a: Dictionary, b: Dictionary) -> Dictionary:
	var r = a.duplicate(true)
	for k in ["move", "inf", "heal", "draw", "fame", "rep", "bsw", "disc", "wound", "terr"]:
		r[k] = int(r[k]) + int(b[k])
	for k in ["atk", "blk", "tok", "crys"]:
		for x in b[k]:
			r[k][x] = int(r[k].get(x, 0)) + int(b[k][x])
	r.mana.append_array(b.mana)
	r.sp.append_array(b.sp)
	return r

static func _cross(alts: Array, sub: Array) -> Array:
	var out: Array = []
	for a in alts:
		for b in sub:
			out.append(merge(a, b))
			if out.size() >= MAXALT:
				return out
	return out

## Parse an effect list into alternative bundles. ctx: {day, combat, phase, mode, wounds, units_ready, ccolors, boost}
static func parse(list, ctx: Dictionary) -> Array:
	if not (list is Array) or list.is_empty():
		return [empty_b()]
	if list[0] is String:
		return _one(list, ctx)
	var alts: Array = [empty_b()]
	for e in list:
		alts = _cross(alts, _any(e, ctx))
	return alts

static func _any(e, ctx: Dictionary) -> Array:
	if e is Array and not e.is_empty() and e[0] is String:
		return _one(e, ctx)
	return parse(e, ctx)

static func _n(e: Array, i: int) -> int:
	if e.size() <= i:
		return 0
	var v = e[i]
	if v is int or v is float:
		return int(v)
	if v is String and v.is_valid_int():
		return int(v)
	return 0

static func _pi(params, key: String, def: int) -> int:
	if params is Dictionary:
		var v = params.get(key, def)
		if v is int or v is float:
			return int(v)
		return def
	if params is int or params is float:
		return int(params)
	return def

static func _one(e: Array, ctx: Dictionary) -> Array:
	var b = empty_b()
	var op: String = e[0]
	var boost = int(ctx.get("boost", 0))
	match op:
		"move":
			b.move = _n(e, 1) + boost
		"influence":
			b.inf = _n(e, 1) + boost
		"heal":
			b.heal = _n(e, 1)
		"draw":
			b.draw = _n(e, 1)
		"fame":
			b.fame = _n(e, 1)
		"rep":
			b.rep = _n(e, 1)
		"attack":
			var el: String = str(e[2]) if e.size() > 2 and e[2] != null else "phys"
			var kd: String = str(e[3]) if e.size() > 3 and e[3] != null else "melee"
			b.atk[kd + ":" + el] = _n(e, 1) + boost
		"block":
			var el2: String = str(e[2]) if e.size() > 2 and e[2] != null else "phys"
			b.blk[el2] = _n(e, 1) + boost
		"mana":
			var c: String = str(e[1]) if e.size() > 1 else "basic"
			if c == "basic" or c == "any":
				var out: Array = []
				for col in BASIC:
					var bb = empty_b()
					bb.tok[col] = 1
					out.append(bb)
				return out
			b.tok[c] = 1
		"crystal":
			var c2: String = str(e[1]) if e.size() > 1 else "basic"
			if c2 == "$paid":
				c2 = "paid"
			if not c2 in BASIC and c2 != "paid":
				c2 = "any"
			b.crys[c2] = 1
		"choice":
			var out2: Array = []
			var opts = e[1] if e.size() > 1 and e[1] is Array else []
			for o in opts:
				for x in parse(o, ctx):
					out2.append(x)
					if out2.size() >= MAXALT:
						return out2
			if out2.is_empty():
				out2.append(b)
			return out2
		"if":
			var cond: String = str(e[1]) if e.size() > 1 else ""
			var r = _cond(cond, ctx)
			if r == true:
				return parse(e[2], ctx) if e.size() > 2 else [b]
			return parse(e[3], ctx) if e.size() > 3 else [b]
		"pay_mana":
			var need: String = str(e[1]) if e.size() > 1 else "any"
			var subs: Array = parse(e[2], ctx) if e.size() > 2 else [b]
			for x in subs:
				x.mana.append(need)
			return subs
		"discard":
			var subs2: Array = parse(e[2], ctx) if e.size() > 2 else [b]
			for x in subs2:
				x.disc = int(x.disc) + _n(e, 1)
			return subs2
		"extra_die":
			b.sp.append("extra_die")
		"ready_unit":
			b.sp.append("ready_unit")
		"heal_unit":
			b.sp.append("heal_unit")
		"boost_next":
			b.sp.append("boost_next")
		"terrain":
			b.terr = 1
			var m = e[1] if e.size() > 1 else {}
			if m is Dictionary and (m.has("all") or m.size() >= 3):
				b.terr = 2
		"mod":
			_mod(b, str(e[1]) if e.size() > 1 else "", e[2] if e.size() > 2 else {}, ctx)
		"special":
			return _special(b, str(e[1]) if e.size() > 1 else "", e[2] if e.size() > 2 else {}, ctx)
		"noop", "text":
			pass
		_:
			b.sp.append(op)
	return [b]

static func _cond(cond: String, ctx: Dictionary):
	match cond:
		"day":
			return bool(ctx.get("day", true))
		"night":
			return not bool(ctx.get("day", true))
		"combat":
			return bool(ctx.get("combat", false))
		"not_combat":
			return not bool(ctx.get("combat", false))
		"powered":
			return ctx.get("mode", "") == "powered"
		"underground":
			return bool(ctx.get("underground", false))
	if cond.begins_with("phase:"):
		var ph = str(ctx.get("phase", ""))
		return ph == "" or ph == "any" or ph == cond.substr(6)
	return false

static func _mod(b: Dictionary, name: String, prm, ctx: Dictionary) -> void:
	match name:
		"move_to_attack", "influence_as_block", "first_attack_or_block_bonus":
			b.sp.append("mod:" + name)
		_:
			b.sp.append("mod:" + name)

static func _special(b: Dictionary, name: String, prm, ctx: Dictionary) -> Array:
	match name:
		"take_wound":
			b.wound = _pi(prm, "n", 1)
		"block_swift", "block_vs_swift":
			b.bsw = _pi(prm, "n", 4)
			if name == "block_vs_swift":
				b.bsw = _pi(prm, "n", 4)
		"plus_per_enemy":
			var n = _pi(prm, "n", 5) + _pi(prm, "per", 2) * maxi(1, int(ctx.get("enemies", 1)))
			var el: String = str(prm.get("elem", "fire")) if prm is Dictionary else "fire"
			if (str(prm.get("op", "attack")) if prm is Dictionary else "attack") == "block":
				b.blk[el] = n
			else:
				b.atk["melee:" + el] = n
		"attack_vs_resistant":
			b.atk["melee:phys"] = _pi(prm, "n", 4)
		"attack_with_kill_reward":
			var kd: String = str(prm.get("kind", "melee")) if prm is Dictionary else "melee"
			b.atk[kd + ":phys"] = _pi(prm, "n", 3)
		"mana_draw":
			var out: Array = []
			for col in BASIC:
				var bb = empty_b()
				bb.tok[col] = _pi(prm, "tokens", 2)
				bb.sp.append("die")
				out.append(bb)
			return out
		"mana_any":
			var out2: Array = []
			for col in BASIC:
				var bb2 = empty_b()
				bb2.tok[col] = _pi(prm, "n", 1)
				out2.append(bb2)
			return out2
		"crystal_copy":
			b.crys["any"] = 1
		"influence_per_wound":
			b.inf = _pi(prm, "n", 1) * int(ctx.get("wounds", 0))
		"discard_any_for":
			b.atk["melee:phys"] = 3
			b.disc = 1
		"heal_by_terrain":
			b.heal = 3
		"block_per_enemy_ability":
			b.blk["ice"] = 2
		"move_per_ready_unit":
			b.move = mini(int(ctx.get("units_ready", 0)), _pi(prm, "max", 3))
		"influence_per_crystal_color":
			b.inf = int(ctx.get("ccolors", 0))
		_:
			b.sp.append(name)
	return [b]

# ================================================================ card options
static func base_ctx(eng, p: int, combat: bool, phase: String = "any") -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var w = 0
	for iid in pl.hand:
		if eng.is_wound(iid):
			w += 1
	var ur = 0
	for u in pl.units:
		if u.ready and not u.wounded:
			ur += 1
	var cc = 0
	for c in BASIC:
		if int(pl.crystals.get(c, 0)) > 0:
			cc += 1
	var ne = 1
	if eng.s.combat != null:
		ne = 0
		for e in eng.s.combat.enemies:
			if not e.defeated and not e.summoned:
				ne += 1
	return {"day": bool(eng.s.day), "combat": combat, "phase": phase, "mode": "basic", "wounds": w, "units_ready": ur,
		"ccolors": cc, "boost": 0, "enemies": ne}

## Options of a card in hand: [{act, mode, needs:[colors], b, c(extra cost)}]
static func card_opts(eng, p: int, iid: String, ctx: Dictionary, sides: bool = true) -> Array:
	var c: Dictionary = eng.card(iid)
	var out: Array = []
	if c.is_empty() or eng.is_wound(iid):
		return out
	var combat: bool = bool(ctx.get("combat", false))
	for mode in ["basic", "powered"]:
		var effs = c.get(mode, [])
		if not (effs is Array) or effs.is_empty():
			continue
		if c.get("combat_only", false) and not combat:
			continue
		if mode == "powered" and c.get("combat_only_powered", false) and not combat:
			continue
		var needs: Array = eng.card_mana_needs(c, mode)
		var cols = c.get("colors", [])
		if cols is Array and cols.size() > 1 and mode != "side" and not needs.is_empty():
			needs = needs.duplicate()
			needs[0] = "dual:" + ",".join(cols)
		var ctx2: Dictionary = ctx.duplicate()
		ctx2["mode"] = mode
		var extra = 0.0
		if mode == "powered" and str(c.get("type", "")) == "artifact":
			extra += 2.5
		for b in parse(effs, ctx2):
			var nd: Array = needs.duplicate()
			nd.append_array(b.mana)
			out.append({"act": {"t": "play", "card": iid, "mode": mode}, "mode": mode, "needs": nd, "b": b, "c": extra})
	if sides and c.get("side", true):
		for side in ["move", "influence", "attack", "block"]:
			var b2 = empty_b()
			var v: int = eng.side_value(p, side, iid)
			match side:
				"move":
					b2.move = v
				"influence":
					b2.inf = v
				"attack":
					b2.atk["melee:phys"] = v
				"block":
					b2.blk["phys"] = v
			out.append({"act": {"t": "play", "card": iid, "mode": "side", "side": side}, "mode": "side", "needs": [], "b": b2, "c": 0.0})
	return out

static func unit_opts(eng, p: int, u: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var d: Dictionary = eng.unit_def(u)
	var abs: Array = d.get("abilities", [])
	for i in abs.size():
		var eff = abs[i].get("effect", [])
		if not (eff is Array) or eff.is_empty():
			continue
		var mana: String = str(abs[i].get("mana", ""))
		for b in parse(eff, ctx):
			var nd: Array = [mana] if mana != "" else []
			nd.append_array(b.mana)
			out.append({"act": {"t": "unit", "uid": int(u.uid), "ability": i}, "mode": "unit", "needs": nd, "b": b, "c": 0.0})
	return out

static func skill_opts(eng, p: int, sk: Dictionary, ctx: Dictionary) -> Array:
	var out: Array = []
	var d: Dictionary = MKDB.skills.get(sk.id, {})
	var eff = d.get("effect", [])
	if not (eff is Array) or eff.is_empty():
		return out
	for b in parse(eff, ctx):
		out.append({"act": {"t": "skill", "id": str(sk.id)}, "mode": "skill", "needs": b.mana.duplicate(), "b": b, "c": 0.0})
	return out

# ================================================================ valuations
## Progress factor of the round: cards kept are worth less when there are more cards left
## than the turns remaining in the round can use.
static func round_factor(eng, p: int) -> float:
	var pl: Dictionary = eng.P(p)
	if eng.s.announced_by != -1 or eng.s.game_end_pending:
		return 0.15
	var cards = pl.deck.size()
	for iid in pl.hand:
		if not eng.is_wound(iid):
			cards += 1
	var tl = turns_left(eng, p)
	var f = (float(tl) * 3.3) / float(maxi(1, cards))
	return clampf(f, 0.3, 1.0)

## Rough estimate of the player's turns left in this round (including the current one).
static func turns_left(eng, p: int) -> int:
	var s: Dictionary = eng.s
	var best = 99
	if s.dummy != null:
		best = 1 + int(ceil(float(s.dummy.deck.size()) / 3.8))
	for i in s.players.size():
		var d: int = s.players[i].deck.size()
		var t = 1 + int(ceil(float(d) / 3.0))
		if i != p:
			best = mini(best, t + 1)
	var mine: int = eng.P(p).deck.size() + eng.P(p).hand.size()
	best = mini(best, 1 + int(ceil(float(mine) / 2.5)))
	return maxi(1, best)

## Cost (fame-equivalent) of changing the reputation by delta (negative = loss).
static func rep_cost(rep_now: int, delta: int) -> float:
	if delta == 0:
		return 0.0
	if delta > 0:
		return -0.5 * float(mini(delta, 7 - rep_now))
	var c = 0.0
	var r = rep_now
	for i in -delta:
		if r <= -7:
			break
		r -= 1
		if r >= -1:
			c += 0.5
		elif r >= -3:
			c += 0.9
		elif r >= -5:
			c += 1.8
		elif r == -6:
			c += 3.0
		else:
			c += 25.0
	return c

static func card_base_value(id: String) -> float:
	if CARD_V.has(id):
		return float(CARD_V[id])
	var c: Dictionary = MKDB.cards.get(id, {})
	var t = str(c.get("type", "basic"))
	if t == "basic" and str(c.get("hero", "")) != "":
		return 0.95
	return float(TYPE_V.get(t, 1.0))

static func card_value(eng, p: int, iid: String, rf: float = -1.0) -> float:
	if eng.is_wound(iid):
		return 0.0
	if rf < 0.0:
		rf = round_factor(eng, p)
	return card_base_value(eng.card_id(iid)) * rf * T("card_scale")

static func pick_value(id: String) -> float:
	if PICK_V.has(id):
		return float(PICK_V[id])
	var c: Dictionary = MKDB.card(id)
	match str(c.get("type", "")):
		"spell":
			return 6.0
		"artifact":
			return 6.5
		"aa":
			return 5.5
	return 3.0

## Long-term value of owning a unit (fame-equivalent).
static func unit_worth(id: String) -> float:
	var d: Dictionary = MKDB.units.get(id, {})
	var lv = int(d.get("level", 1))
	var v = 1.0 + 1.8 * lv
	var best_atk = 0
	var best_blk = 0
	for ab in d.get("abilities", []):
		for b in parse(ab.get("effect", []), {"day": true, "combat": true, "phase": "any"}):
			var a = 0
			for k in b.atk:
				a += int(b.atk[k]) + (1 if not str(k).begins_with("melee") else 0)
			best_atk = maxi(best_atk, a)
			var bl = int(b.bsw)
			for k2 in b.blk:
				bl += int(b.blk[k2])
			best_blk = maxi(best_blk, bl)
	v += 0.6 * maxi(best_atk, best_blk)
	v += 0.15 * float(d.get("armor", 2))
	v += 0.4 * float(d.get("resist", []).size())
	return v

## Cost of exhausting a ready unit (it refreshes at round end).
static func unit_use_cost(eng, p: int, u: Dictionary, rf: float) -> float:
	return (0.35 + 0.25 * float(eng.unit_level(u))) * rf

# ================================================================ mana
## Mana available for planning: {col: n} from tokens + crystals, plus dice info.
static func mana_pool(eng, p: int) -> Dictionary:
	var pl: Dictionary = eng.P(p)
	var tok = {}
	for t in pl.tokens:
		tok[t] = int(tok.get(t, 0)) + 1
	var cr = {}
	for c in BASIC:
		cr[c] = int(pl.crystals.get(c, 0))
	var dice: Array = []
	var left: int = MKMana.dice_left(eng, p)
	if eng.flag(p, "no_dice"):
		left = 0
	if left > 0:
		for d in eng.s.source:
			if int(d.taken_by) == -1:
				dice.append(str(d.color))
	if str(pl.get("stolen_die", "")) != "":
		tok[str(pl.stolen_die)] = int(tok.get(str(pl.stolen_die), 0)) + 1
	return {"tok": tok, "cr": cr, "dice": dice, "dice_left": left, "gold_ok": MKMana.gold_ok(eng, p), "black_ok": MKMana.black_ok(eng, p)}

## Try to pay a list of needs; returns cost (crystals spent * CRYSTAL value) or -1 if impossible.
## Mutates mp if commit=true.
static func mana_cost(mp: Dictionary, needs: Array, commit: bool = false) -> float:
	if needs.is_empty():
		return 0.0
	var m: Dictionary = mp if commit else mp.duplicate(true)
	var cost = 0.0
	for need0 in needs:
		var need = str(need0)
		var cands: Array = [need]
		if need.begins_with("dual:"):
			cands = need.substr(5).split(",")
		var paid = false
		for need2 in cands:
			if _pay1(m, need2):
				paid = true
				cost += float(m.get("_last", 0.0))
				break
		if not paid:
			return -1.0
	return cost

static func _fits(have: String, need: String, gold_ok: bool, black_ok: bool) -> bool:
	if have == "gold":
		return gold_ok and (need in BASIC or need == "basic" or need == "any")
	if have == "black":
		return black_ok and need == "black"
	if need == "basic" or need == "any":
		return have in BASIC
	return have == need

static func _pay1(m: Dictionary, need: String) -> bool:
	# tokens
	for col in m.tok:
		if int(m.tok[col]) > 0 and _fits(col, need, m.gold_ok, m.black_ok):
			m.tok[col] = int(m.tok[col]) - 1
			m["_last"] = 0.0
			return true
	# die (exact colour first, then gold)
	if int(m.dice_left) > 0:
		var pick = -1
		for i in m.dice.size():
			if m.dice[i] == need or (need in ["basic", "any"] and m.dice[i] in BASIC):
				pick = i
				break
		if pick < 0:
			for i in m.dice.size():
				if _fits(m.dice[i], need, m.gold_ok, m.black_ok):
					pick = i
					break
		if pick >= 0:
			m.dice.remove_at(pick)
			m.dice_left = int(m.dice_left) - 1
			m["_last"] = 0.05
			return true
	# crystals
	if need in BASIC and int(m.cr.get(need, 0)) > 0:
		m.cr[need] = int(m.cr[need]) - 1
		m["_last"] = 0.9
		return true
	if need in ["basic", "any"]:
		for c in BASIC:
			if int(m.cr.get(c, 0)) > 0:
				m.cr[c] = int(m.cr[c]) - 1
				m["_last"] = 0.9
				return true
	return false
