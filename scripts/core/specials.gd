class_name MKSpecials
extends RefCounted
## Registry of named special effects: func sp_<name>(eng, ctx, params).
## Optional: can_<name>(eng, ctx, params) -> bool, res_<name>(eng, ctx, data, v)
## for decisions created with ask(). Mods ("mod" op) known by the engine are
## stored in s.turn.mods and consulted where relevant.

## Modifier names consulted directly by the engine.
const ENGINE_MODS := ["attack_bonus", "block_bonus", "side_value", "armor", "unit_armor", "hand_limit",
	"recruit_discount", "no_dice"]

static var _inst: MKSpecials = null
static var _impl_cache: Dictionary = {}

static func inst() -> MKSpecials:
	if _inst == null:
		_inst = MKSpecials.new()
	return _inst

static func implemented() -> Array[String]:
	var out: Array[String] = []
	for k in implemented_set():
		out.append(k)
	out.sort()
	return out

static func implemented_set() -> Dictionary:
	if _impl_cache.is_empty():
		for m in inst().get_method_list():
			var n: String = m.name
			if n.begins_with("sp_"):
				_impl_cache[n.substr(3)] = true
		for n in ENGINE_MODS:
			_impl_cache[n] = true
	return _impl_cache

static func has(name: String) -> bool:
	return implemented_set().has(name)

static func run(eng, ctx: Dictionary, name: String, params) -> void:
	var o := inst()
	if o.has_method("sp_" + name):
		o.call("sp_" + name, eng, ctx, params if params != null else {})
	else:
		eng.add_log("error", "Effetto speciale non implementato: " + name)

## Specials that are only a cost/side effect: they never make an effect list "applicable".
const COST_SPECIALS := ["take_wound", "motivation_lock", "roll_wound", "use_as_action", "wound_self_unit", "card_to_deck_end_turn",
	"return_card_end_turn", "fame_per_kill", "opponents_exhaust_unit"]

static func can(eng, ctx: Dictionary, name: String, params) -> bool:
	var o := inst()
	if not o.has_method("sp_" + name):
		return false
	if name in COST_SPECIALS:
		return false
	if o.has_method("can_" + name):
		return bool(o.call("can_" + name, eng, ctx, params if params != null else {}))
	return true

static func run_mod(eng, ctx: Dictionary, name: String, params) -> void:
	var o := inst()
	if o.has_method("sp_" + name):
		o.call("sp_" + name, eng, ctx, params if params != null else {})
		return
	var m := {"name": name, "src": ctx.get("src", ""), "p": ctx.get("p", 0)}
	if params is Dictionary:
		for k in params:
			m[k] = params[k]
	elif params != null:
		m["n"] = params
	eng.s.turn.mods.append(m)

static func can_mod(eng, ctx: Dictionary, name: String, params) -> bool:
	if ENGINE_MODS.has(name):
		return true
	return can(eng, ctx, name, params)

static func cond(eng, ctx: Dictionary, c: String) -> bool:
	var o := inst()
	if o.has_method("cond_" + c):
		return bool(o.call("cond_" + c, eng, ctx))
	return false

## Ask a decision from inside a special; resolution calls res_<name>.
static func ask(eng, ctx: Dictionary, name: String, prompt: String, options: Array, data: Dictionary = {}, typ: String = "choice") -> void:
	if options.is_empty():
		return
	MKEffects.suspend(eng, ctx, {"type": typ, "handler": "sp:" + name, "prompt": prompt, "options": options, "data": data})

static func resolve(eng, pend: Dictionary, v) -> void:
	var name: String = str(pend.handler).substr(3)
	var ctx: Dictionary = pend.get("ctx", {})
	var queue: Array = pend.get("queue", [])
	var o := inst()
	eng._q = queue
	if o.has_method("res_" + name):
		o.call("res_" + name, eng, ctx, pend.get("data", {}), v)
	MKEffects.run(eng, eng._q if eng._q != null else queue, ctx)

# ======================================================================
# Small helpers
# ======================================================================
static func _p(eng, ctx: Dictionary) -> int:
	return int(ctx.get("p", eng.s.turn.get("player", 0)))

static func _pi(params, key: String, def: int) -> int:
	if params is Dictionary:
		var v = params.get(key, def)
		if v is int or v is float:
			return int(v)
		if v is String and v.is_valid_int():
			return int(v)
		return def
	if params is int or params is float:
		return int(params)
	return def

static func _ps(params, key: String, def: String) -> String:
	if params is Dictionary:
		return str(params.get(key, def))
	if params is String:
		return params
	return def

static func get_mod(eng, name: String) -> Variant:
	for m in eng.s.turn.get("mods", []):
		if m.get("name", "") == name:
			return m
	return null

static func add_mod(eng, ctx: Dictionary, name: String, data = {}) -> Dictionary:
	var m := {"name": name, "src": str(ctx.get("src", "")), "p": _p(eng, ctx)}
	if data is Dictionary:
		for k in data:
			m[k] = data[k]
	eng.s.turn.mods.append(m)
	return m

static func _open_mod(eng, name: String) -> Variant:
	for m in eng.s.turn.get("mods", []):
		if m.get("name", "") == name and not m.get("_done", false):
			return m
	return null

static func remove_mod(eng, m) -> void:
	eng.s.turn.mods.erase(m)

static func in_combat(eng) -> bool:
	return eng.s.combat != null

static func phase(eng) -> String:
	return str(eng.s.combat.phase) if eng.s.combat != null else ""

## Enemies that an effect can target. f: {immune, unfortified, need_attack, phase}
static func enemy_targets(eng, f: Dictionary = {}) -> Array:
	var out: Array = []
	if eng.s.combat == null:
		return out
	for e in eng.s.combat.enemies:
		if e.defeated or e.hidden:
			continue
		if MKCombat.has_ab(e, "arcane_immunity"):
			continue
		var imm := str(f.get("immune", ""))
		if imm != "" and MKCombat.resists(e, imm):
			continue
		if f.get("unfortified", false) and MKCombat.is_fortified(e):
			continue
		if f.get("need_attack", false):
			var any := false
			for i in e.attacks.size():
				if MKCombat.attack_value(eng, e, i) > 0 and not e.attacks[i].blocked:
					any = true
			if not any:
				continue
		out.append(e)
	return out

static func _enemy_opts(list: Array) -> Array:
	var o: Array = []
	for e in list:
		o.append({"v": e.eid, "label": e.name})
	return o

## Ask (or auto-apply when only one option) and call res_<name>.
static func choose(eng, ctx: Dictionary, name: String, prompt: String, options: Array, data: Dictionary = {}, typ: String = "choice") -> void:
	if options.is_empty():
		return
	if options.size() == 1 and not data.get("always_ask", false):
		var o := inst()
		if o.has_method("res_" + name):
			o.call("res_" + name, eng, ctx, data, options[0].v)
		return
	ask(eng, ctx, name, prompt, options, data, typ)

static func card_colors(c: Dictionary) -> Array:
	var cols = c.get("colors", [])
	if cols is Array and not cols.is_empty():
		return cols
	var col := str(c.get("color", ""))
	return [col] if col != "" else []

static func action_cards_in_hand(eng, p: int, exclude: String) -> Array:
	var out: Array = []
	var seen := {}
	for iid in eng.P(p).hand:
		if iid == exclude:
			continue
		var c: Dictionary = eng.card(iid)
		if not str(c.get("type", "")) in ["basic", "aa"]:
			continue
		if seen.has(c.id):
			continue
		seen[c.id] = true
		out.append(iid)
	return out

static func ko_check(eng, p: int, n: int) -> void:
	var c = eng.s.combat
	if c == null:
		return
	c.wounds_hand = int(c.wounds_hand) + n
	var pl: Dictionary = eng.P(p)
	if not pl.knocked_out and int(c.wounds_hand) >= eng.base_hand_limit(p):
		pl.knocked_out = true
		MKCombat._discard_non_wounds(eng, p, "fuori combattimento")
		eng.add_log("knockout", "%s è fuori combattimento!" % eng.pname(p), {"p": p})

# ======================================================================
# Engine hooks
# ======================================================================
static func adjust(eng, ctx: Dictionary, op: String, n: int, elem: String, kind: String) -> Array:
	var p := _p(eng, ctx)
	var t: Dictionary = eng.s.turn
	if t.get("player", -1) != p:
		return [n, elem, kind]
	var from_card: bool = ctx.get("kind", "") == "card"
	var from_unit: bool = ctx.get("kind", "") == "unit"
	if from_card and op in ["move", "influence", "attack", "block"] and not ctx.get("_cpb", false):
		var cpb = get_mod(eng, "card_play_bonus")
		if cpb != null and ctx.get("src", "") != cpb.src:
			n += int(cpb.get("n", 1))
			ctx["_cpb"] = true
	match op:
		"move":
			var mb = get_mod(eng, "move_card_bonus")
			if mb != null and from_card and ctx.get("src", "") != mb.src:
				n += int(mb.get("n", 1))
				if str(mb.get("cards", "1")) != "all":
					remove_mod(eng, mb)
		"attack", "block":
			var fb = get_mod(eng, "first_attack_or_block_bonus")
			if fb != null and from_card:
				n += int(fb.get(op, 0))
				remove_mod(eng, fb)
			if from_unit:
				var ub = get_mod(eng, "unit_activation_bonus")
				if ub != null and not ctx.get("_ub_used", false):
					var add := 0
					if op == "block":
						add = int(ub.get("block", 0))
					elif kind == "ranged":
						add = int(ub.get("ranged", 0))
					elif kind == "melee":
						add = int(ub.get("attack", 0))
					if add > 0:
						n += add
						ctx["_ub_used"] = true
						remove_mod(eng, ub)
				var uid := str(ctx.get("uid", ""))
				var bn = eng.P(p).get("banners", {}).get(uid, null)
				if bn != null:
					var bp: Dictionary = banner_params(eng, bn)
					n += int(bp.get("bonus", 0))
					if int(bp.get("fame_on_use", 0)) > 0 and not ctx.get("_bfame", false):
						ctx["_bfame"] = true
						eng.gain_fame(p, int(bp.fame_on_use))
				var ag = get_mod(eng, "all_units_bonus")
				if ag != null:
					n += int(ag.get("bonus", 0))
					if not ctx.get("_agfame", false):
						ctx["_agfame"] = true
						eng.gain_fame(p, int(ag.get("fame", 0)))
			if from_card and op == "attack":
				var dm = get_mod(eng, "deadly_aim")
				if dm != null:
					n += 1 if phase(eng) == "ranged" else 2
					remove_mod(eng, dm)
			if op == "attack":
				var tr = get_mod(eng, "attacks_transform")
				if tr != null:
					if tr.get("to", "") == "cold":
						elem = "cold"
					elif tr.get("to", "") == "siege":
						kind = "siege"
				var da = get_mod(eng, "double_attacks")
				if da != null and elem == str(da.get("elem", "phys")) and phase(eng) == str(da.get("phase", "attack")):
					n *= 2
	return [n, elem, kind]

static func side_value(eng, p: int, side: String, iid: String, base: int) -> int:
	var v := base
	var c: Dictionary = eng.card(iid)
	for m in eng.mods_named("sideways_bonus"):
		var b := int(m.get("base", 2))
		if m.has("aa_spell_artifact") and str(c.get("type", "")) in ["aa", "spell", "artifact"]:
			b = int(m.aa_spell_artifact)
		if m.has("no_source") and int(eng.s.turn.get("dice_taken", 0)) == 0:
			b = int(m.no_source)
		v = maxi(v, b)
	var sm = get_mod(eng, "sideways_mana_boost")
	if sm != null:
		var b2 := int(sm.get("base", 3))
		if str(sm.get("color", "")) in card_colors(c) and str(c.get("type", "")) in ["basic", "aa", "spell"]:
			b2 = int(sm.get("same_color", 4))
		v = maxi(v, b2)
		remove_mod(eng, sm)
	if side == "attack":
		var dm = get_mod(eng, "deadly_aim")
		if dm != null and phase(eng) == "attack":
			v += 2
			remove_mod(eng, dm)
	if side in ["attack", "block"]:
		var fb = get_mod(eng, "first_attack_or_block_bonus")
		if fb != null:
			v += int(fb.get(side, 0))
			remove_mod(eng, fb)
	if side == "move":
		var mb = get_mod(eng, "move_card_bonus")
		if mb != null and iid != mb.src:
			v += int(mb.get("n", 1))
			if str(mb.get("cards", "1")) != "all":
				remove_mod(eng, mb)
	return v

static func on_card_played(eng, p: int, iid: String, mode: String) -> void:
	var c: Dictionary = eng.card(iid)
	if str(c.get("type", "")) == "spell":
		for m in eng.mods_named("ring_powered"):
			if str(m.get("color", "")) in card_colors(c):
				eng.gain_fame(p, 1)

static func on_block(eng, p: int, e: Dictionary) -> void:
	var mb = eng.s.turn.get("multi_block", null)
	if mb is Dictionary and int(mb.get("left", 0)) > 0:
		mb.left = int(mb.left) - 1
	if e.get("destroy_if_blocked", false) and not e.defeated:
		MKCombat.defeat(eng, p, e)
		MKCombat._check_all_defeated(eng)
	var ba = get_mod(eng, "block_armor_reduce")
	if ba != null:
		remove_mod(eng, ba)
		if not MKCombat.resists(e, "ice") and not MKCombat.has_ab(e, "arcane_immunity"):
			e.armor_mod = int(e.get("armor_mod", 0)) - int(ba.get("n", 3))
			eng.add_log("info", "%s: Armatura -%d" % [e.name, int(ba.get("n", 3))])
	var sb = get_mod(eng, "shield_on_block")
	if sb != null:
		remove_mod(eng, sb)
		if sb.get("destroy", false):
			if not MKCombat.resists(e, str(sb.get("immune", "fire"))) and not MKCombat.has_ab(e, "arcane_immunity") and not e.defeated:
				MKCombat.defeat(eng, p, e)
				MKCombat._check_all_defeated(eng)
		elif int(sb.get("attack", 0)) > 0:
			var c: Dictionary = eng.s.combat
			if not c.has("delayed"):
				c["delayed"] = []
			c.delayed.append({"n": int(sb.attack), "elem": str(sb.get("elem", "fire"))})

static func on_defeat(eng, p: int, e: Dictionary) -> void:
	for m in eng.mods_named("fame_per_kill"):
		if m.get("once", false):
			if m.get("_done", false):
				continue
			m["_done"] = true
		eng.gain_fame(p, int(m.get("n", 1)))
	for m in eng.mods_named("scout_fame"):
		if e.eid in m.get("eids", []):
			eng.gain_fame(p, int(m.get("fame", 1)))
	for m in eng.mods_named("crystal_per_kill"):
		if int(m.get("got", 0)) >= int(m.get("max", 1)):
			continue
		m["got"] = int(m.get("got", 0)) + 1
		var col := "white"
		if "fire" in e.resist:
			col = "red"
		elif "ice" in e.resist:
			col = "blue"
		elif "phys" in e.resist:
			col = "green"
		eng.gain_crystal(p, col)
	for m in eng.mods_named("kill_reward"):
		if m.get("phase", "") != phase(eng):
			continue
		if int(m.get("rep", 0)) != 0:
			eng.change_rep(p, int(m.rep))
		var f := int(m.get("fame", 0))
		if int(m.get("fame_once", 0)) > 0 and not m.get("_done", false):
			f += int(m.fame_once)
			m["_done"] = true
		if f > 0:
			eng.gain_fame(p, f)
		var amo := int(m.get("armor_minus_other", 0))
		if amo > 0:
			for o in enemy_targets(eng, {}):
				o.armor_mod = int(o.get("armor_mod", 0)) - amo
				break

static func on_attack_phase(eng, p: int) -> void:
	var c: Dictionary = eng.s.combat
	var pool: Dictionary = eng.s.turn.pool.attack
	for d in c.get("delayed", []):
		var key := "melee:" + str(d.get("elem", "phys"))
		pool[key] = int(pool.get(key, 0)) + int(d.n)
	c["delayed"] = []
	for m in eng.mods_named("attack_if_no_wounds"):
		if int(c.get("wounds_hand", 0)) == 0:
			pool["melee:phys"] = int(pool.get("melee:phys", 0)) + int(m.get("n", 0))
	for m in eng.mods_named("attack_per_blocked"):
		pool["melee:phys"] = int(pool.get("melee:phys", 0)) + int(m.get("n", 1)) * int(c.get("blocked_count", 0))

static func on_combat_start(eng, p: int) -> void:
	var c: Dictionary = eng.s.combat
	for m in eng.mods_named("pre_combat"):
		for e in c.enemies:
			if m.get("site_fort", false):
				e["site_fort_lost"] = true
			if int(m.get("armor", 0)) != 0 and not MKCombat.resists(e, str(m.get("immune", ""))) and not MKCombat.has_ab(e, "arcane_immunity"):
				e.armor_mod = int(e.get("armor_mod", 0)) - int(m.armor)

static func on_mana_used(eng, p: int, color: String) -> void:
	pass

static func on_wound(eng, p: int, iid: String, to_hand: bool) -> void:
	var t: Dictionary = eng.s.turn
	if t.get("player", -1) != p:
		return
	if not t.has("wounds_received"):
		t["wounds_received"] = []
	t.wounds_received.append(iid)
	if to_hand:
		var m = get_mod(eng, "draw_on_wound")
		if m != null:
			if m.get("throw_first", false) and not m.get("_thrown", false):
				m["_thrown"] = true
				eng.throw_away(p, iid)
				eng.add_log("info", "Prima ferita gettata via (Scarica di adrenalina)", {"p": p})
				return
			if int(m.get("used", 0)) < int(m.get("n", 3)):
				m["used"] = int(m.get("used", 0)) + 1
				eng.draw(p, 1)

static func on_heal(eng, p: int) -> void:
	var m = get_mod(eng, "fame_per_heal")
	if m != null and int(m.get("left", 0)) > 0:
		m.left = int(m.left) - 1
		eng.gain_fame(p, 1)
	if get_mod(eng, "draw_per_heal") != null:
		eng.draw(p, 1)

static func on_recruit(eng, p: int, id: String) -> void:
	eng.s.turn["recruited"] = int(eng.s.turn.get("recruited", 0)) + 1
	for m in eng.mods_named("per_recruit"):
		eng.change_rep(p, int(m.get("rep", 0)))
		eng.gain_fame(p, int(m.get("fame", 0)))
	var rd = get_mod(eng, "recruit_discount")
	if rd != null:
		if int(rd.get("rep", 0)) != 0:
			eng.change_rep(p, int(rd.rep))
		if str(rd.get("units", "all")) != "all":
			remove_mod(eng, rd)
	var pl: Dictionary = eng.P(p)
	if pl.get("bonds_discount", 0) > 0:
		pl.bonds_discount = 0

static func unit_cost_mod(eng, p: int, id: String) -> int:
	var d := 0
	var pl: Dictionary = eng.P(p)
	d += int(pl.get("bonds_discount", 0))
	return d

static func on_interaction(eng, p: int) -> void:
	var m = _open_mod(eng, "interaction_bonus")
	while m != null:
		m["_done"] = true
		eng.gain_fame(p, int(m.get("fame", 0)))
		eng.change_rep(p, int(m.get("rep", 0)))
		m = _open_mod(eng, "interaction_bonus")

static func on_turn_start(eng, p: int) -> void:
	var pl: Dictionary = eng.P(p)
	if pl.get("mana_claim_color", "") != "":
		eng.gain_token(p, pl.mana_claim_color)
	if int(pl.get("frozen_die", -1)) >= 0:
		var i := int(pl.frozen_die)
		if i < eng.s.source.size():
			eng.s.source[i].taken_by = -1
			eng.s.source[i].color = eng.DIE_COLORS[MKRng.rand_int(eng.s, 6)]
		pl.frozen_die = -1

static func on_round_start(eng) -> void:
	for pl in eng.s.players:
		pl["mana_claim_color"] = ""
		pl["banner_used"] = {}
		pl["frozen_die"] = -1
		if pl.get("set_aside", []).size() > 0:
			pl.deck.append_array(pl.set_aside)
			pl.set_aside = []

## Extra end-of-turn decisions (before cleanup). Returns true if it asked.
static func end_turn_pending(eng, p: int) -> bool:
	var t: Dictionary = eng.s.turn
	var pl: Dictionary = eng.P(p)
	for m in eng.mods_named("return_card_end_turn"):
		if m.get("_done", false):
			continue
		m["_done"] = true
		if not pl.play.has(m.src):
			continue
		var opts: Array = [{"v": "", "label": "No"}]
		for iid in pl.hand:
			if eng.is_wound(iid) and not m.get("wound_ok", false):
				continue
			opts.append({"v": iid, "label": "Scarta %s e riprendi %s" % [eng.card_name(iid), eng.card_name(m.src)]})
		if opts.size() > 1:
			eng.ask(p, "card", "sp:return_card", "Vuoi riprendere in mano %s?" % eng.card_name(m.src), opts, {"card": m.src})
			return true
	return false

static func res_return_card(eng, ctx: Dictionary, data: Dictionary, v) -> void:
	if str(v) == "":
		return
	var p := _p(eng, ctx)
	var pl: Dictionary = eng.P(p)
	eng.discard_from_hand(p, str(v))
	pl.play.erase(data.card)
	pl.hand.append(data.card)

static func on_cleanup(eng, p: int) -> void:
	var t: Dictionary = eng.s.turn
	var pl: Dictionary = eng.P(p)
	if get_mod(eng, "crystals_return") != null:
		for c in t.get("crystals_spent", []):
			if int(pl.crystals.get(c, 0)) < 3:
				pl.crystals[c] = int(pl.crystals[c]) + 1
	for m in eng.mods_named("card_to_deck_end_turn"):
		if pl.play.has(m.src):
			if str(m.get("pos", "bottom")) == "top":
				pl.play.erase(m.src)
				pl.deck.push_front(m.src)
			elif not pl.deck.is_empty():
				pl.play.erase(m.src)
				pl.deck.append(m.src)
	if get_mod(eng, "throw_away_turn_wounds") != null:
		for iid in t.get("wounds_received", []):
			if pl.hand.has(iid) or pl.discard.has(iid):
				eng.throw_away(p, iid)
	var tb = get_mod(eng, "time_bending")
	if tb != null and not t.get("extra_turn", false):
		if pl.play.has(tb.src):
			pl.play.erase(tb.src)
			if not pl.has("set_aside"):
				pl["set_aside"] = []
			pl.set_aside.append(tb.src)
		for iid in pl.play.duplicate():
			if iid in t.destroy:
				continue
			pl.play.erase(iid)
			pl.hand.append(iid)
		t.skip_draw = true
		t.extra_turn = true
		eng.add_log("info", "%s piega il tempo e gioca un altro turno" % eng.pname(p), {"p": p})
	for m in eng.mods_named("wound_sideways_played"):
		pass

## Banner parameters of an attached banner card instance.
static func banner_params(eng, iid) -> Dictionary:
	var c: Dictionary = eng.card(str(iid))
	for e in c.get("basic", []):
		if e is Array and e.size() > 2 and e[0] == "special" and e[1] == "banner_attach" and e[2] is Dictionary:
			return e[2]
	return {}

# ======================================================================
# Special actions (outside the card flow): {t:"sp", name, ...}
# ======================================================================
static func actions(eng, p: int) -> Array:
	var out: Array = []
	var s: Dictionary = eng.s
	var t: Dictionary = s.turn
	var pool: Dictionary = t.pool
	var cb = s.combat
	for m in t.get("mods", []):
		match str(m.get("name", "")):
			"move_to_attack":
				if cb != null and cb.phase in ["ranged", "attack"]:
					if m.has("melee") and cb.phase == "attack" and int(pool.move) >= int(m.melee):
						out.append({"a": {"t": "sp", "name": "move_to_attack", "kind": "melee"}, "label": "Converti %d Movimento in Attacco 1" % int(m.melee), "group": "combat"})
					if m.has("ranged") and int(pool.move) >= int(m.ranged):
						out.append({"a": {"t": "sp", "name": "move_to_attack", "kind": "ranged"}, "label": "Converti %d Movimento in Attacco a distanza 1" % int(m.ranged), "group": "combat"})
			"influence_as_block":
				if cb != null and cb.phase == "block" and int(pool.influence) >= 1:
					out.append({"a": {"t": "sp", "name": "influence_as_block"}, "label": "Usa l'Influenza come Blocco (%d)" % int(pool.influence), "group": "combat"})
			"buy_aa_with_influence":
				if not m.get("_done", false) and cb == null:
					for id in s.offers.aa:
						if int(pool.influence) >= int(m.get("cost", 6)):
							out.append({"a": {"t": "sp", "name": "buy_aa_with_influence", "id": id}, "label": "Impara %s (%d Influenza)" % [MKSites._cname(id), int(m.get("cost", 6))], "group": "card"})
			"influence_to_heal":
				if cb == null and int(pool.influence) >= int(m.get("per", 2)) and MKSites._has_healable(eng, p):
					out.append({"a": {"t": "sp", "name": "influence_to_heal"}, "label": "Converti %d Influenza in Cura 1" % int(m.get("per", 2)), "group": "heal"})
			"ready_units_for_influence":
				if cb == null:
					for u in eng.P(p).units:
						var lv: int = eng.unit_level(u)
						if not u.ready and lv <= int(m.get("max_level", 2)) and int(pool.influence) >= lv * int(m.get("per_level", 2)):
							out.append({"a": {"t": "sp", "name": "ready_units_for_influence", "uid": int(u.uid)}, "label": "Prepara %s pagando %d Influenza" % [eng.unit_name(u), lv * int(m.get("per_level", 2))], "group": "unit"})
			"wound_sideways":
				if not m.get("_done", false):
					var has_w := ""
					for iid in eng.P(p).hand:
						if eng.is_wound(iid):
							has_w = iid
							break
					if has_w != "":
						for side in ["move", "influence", "attack", "block"]:
							var a := {"t": "sp", "name": "wound_sideways", "side": side}
							if check_action(eng, p, a) == "":
								out.append({"a": a, "label": "Gioca una Ferita di lato: %s %d" % [{"move": "Movimento", "influence": "Influenza", "attack": "Attacco", "block": "Blocco"}[side], int(m.get("bonus", 2))], "group": "card"})
	# banners
	var bn: Dictionary = eng.P(p).get("banners", {})
	for uid in bn:
		var u = eng.find_unit(p, int(uid))
		if u == null:
			continue
		var bp := banner_params(eng, bn[uid])
		if bp.get("fear", false) and cb != null and cb.phase == "block" and u.ready and not u.wounded and eng.units_usable():
			for e in enemy_targets(eng, {"need_attack": true}):
				out.append({"a": {"t": "sp", "name": "banner_fear", "uid": int(uid), "eid": e.eid}, "label": "Stendardo della Paura: annulla l'attacco di %s" % e.name, "group": "unit"})
		if bp.get("ready_once_round", false) and cb == null and not u.ready and not eng.P(p).get("banner_used", {}).has(str(uid)):
			out.append({"a": {"t": "sp", "name": "banner_ready", "uid": int(uid)}, "label": "Stendardo del Coraggio: prepara %s" % eng.unit_name(u), "group": "unit"})
	return out

static func check_action(eng, p: int, a: Dictionary) -> String:
	var s: Dictionary = eng.s
	var t: Dictionary = s.turn
	var pool: Dictionary = t.pool
	match str(a.get("name", "")):
		"wound_sideways":
			var m = _open_mod(eng, "wound_sideways")
			if m == null:
				return "Non disponibile"
			var side := str(a.get("side", ""))
			match side:
				"move":
					if not eng.can_still_move(p):
						return "Non puoi muoverti ora"
				"influence":
					if s.combat != null or MKSites.can_interact(eng, p) != "":
						return "Non puoi usare Influenza ora"
				"attack":
					if s.combat == null or s.combat.phase != "attack":
						return "Solo nella fase di attacco"
				"block":
					if s.combat == null or s.combat.phase != "block":
						return "Solo nella fase di blocco"
				_:
					return "Lato non valido"
			return ""
		"buy_aa_with_influence":
			var m2 = _open_mod(eng, "buy_aa_with_influence")
			if m2 == null or not str(a.get("id", "")) in s.offers.aa:
				return "Non disponibile"
			if int(pool.influence) < int(m2.get("cost", 6)):
				return "Influenza insufficiente"
			return ""
	for x in actions(eng, p):
		if x.a.hash() == a.hash():
			return ""
	return "Azione speciale non disponibile"

static func do_action(eng, p: int, a: Dictionary) -> void:
	var s: Dictionary = eng.s
	var t: Dictionary = s.turn
	var pool: Dictionary = t.pool
	t.started = true
	match str(a.name):
		"move_to_attack":
			var m = get_mod(eng, "move_to_attack")
			var kind := str(a.kind)
			pool.move = int(pool.move) - int(m.get(kind, 1))
			var key := kind + ":phys"
			pool.attack[key] = int(pool.attack.get(key, 0)) + 1
			eng.add_log("pts", "+1 %s" % ("Attacco" if kind == "melee" else "Attacco a distanza"), {"p": p, "what": "attack", "n": 1})
		"influence_as_block":
			var m2 = get_mod(eng, "influence_as_block")
			var el := str(m2.get("elem", "phys"))
			pool.block[el] = int(pool.block.get(el, 0)) + int(pool.influence)
			eng.add_log("pts", "+%d Blocco (da Influenza)" % int(pool.influence), {"p": p, "what": "block", "n": int(pool.influence)})
			pool.influence = 0
		"buy_aa_with_influence":
			var m3 = _open_mod(eng, "buy_aa_with_influence")
			m3["_done"] = true
			pool.influence = int(pool.influence) - int(m3.get("cost", 6))
			var id := str(a.id)
			s.offers.aa.erase(id)
			eng._refill_offer("aa")
			var iid: String = eng.new_iid(id)
			if str(m3.get("to", "discard")) == "hand":
				eng.P(p).hand.append(iid)
			else:
				eng.P(p).discard.append(iid)
			eng.add_log("gain_card", "%s impara %s" % [eng.pname(p), MKSites._cname(id)], {"p": p, "card": iid})
		"influence_to_heal":
			var m4 = get_mod(eng, "influence_to_heal")
			pool.influence = int(pool.influence) - int(m4.get("per", 2))
			pool.heal = int(pool.heal) + 1
			eng.auto_heal(p)
		"ready_units_for_influence":
			var m5 = get_mod(eng, "ready_units_for_influence")
			var u = eng.find_unit(p, a.uid)
			pool.influence = int(pool.influence) - eng.unit_level(u) * int(m5.get("per_level", 2))
			u.ready = true
			eng.add_log("unit", "%s è pronta" % eng.unit_name(u), {"p": p})
		"wound_sideways":
			var m6 = _open_mod(eng, "wound_sideways")
			m6["_done"] = true
			var pl: Dictionary = eng.P(p)
			var w := ""
			for iid2 in pl.hand:
				if eng.is_wound(iid2):
					w = iid2
					break
			pl.hand.erase(w)
			pl.play.append(w)
			t.played.append(w)
			var v := int(m6.get("bonus", 2))
			match str(a.side):
				"move":
					pool.move = int(pool.move) + v
				"influence":
					pool.influence = int(pool.influence) + v
				"attack":
					pool.attack["melee:phys"] = int(pool.attack.get("melee:phys", 0)) + v
				"block":
					pool.block["phys"] = int(pool.block.get("phys", 0)) + v
			eng.add_log("play", "%s gioca una Ferita di lato (+%d)" % [eng.pname(p), v], {"p": p, "card": w, "mode": "side"})
		"banner_fear":
			var u2 = eng.find_unit(p, a.uid)
			u2.ready = false
			var e = MKCombat.entry(eng, str(a.eid))
			for at in e.attacks:
				at.blocked = true
			eng.gain_fame(p, 1)
			eng.add_log("unit", "Lo Stendardo della Paura annulla l'attacco di %s" % e.name, {"p": p, "eid": e.eid})
		"banner_ready":
			var u3 = eng.find_unit(p, a.uid)
			u3.ready = true
			eng.P(p).banner_used[str(a.uid)] = true
			eng.add_log("unit", "%s è pronta (Stendardo del Coraggio)" % eng.unit_name(u3), {"p": p})

# ======================================================================
# Tactics (logic in MKSites, keyed by tactic number)
# ======================================================================
func sp_tactic_rethink(eng, ctx, params): pass
func sp_tactic_mana_steal(eng, ctx, params): pass
func sp_tactic_planning(eng, ctx, params): pass
func sp_tactic_right_moment(eng, ctx, params): pass
func sp_tactic_long_night(eng, ctx, params): pass
func sp_tactic_mana_search(eng, ctx, params): pass
func sp_tactic_midnight_meditation(eng, ctx, params): pass
func sp_tactic_preparation(eng, ctx, params): pass
func sp_tactic_sparing_power(eng, ctx, params): pass

# ======================================================================
# Card / unit / skill specials
# ======================================================================
func sp_take_wound(eng, ctx, params):
	var p := _p(eng, ctx)
	var n := _pi(params, "n", 1)
	var to := _ps(params, "to", "hand")
	for i in n:
		eng.add_wound(p, to != "discard")
	eng.add_log("wound", "%s prende %d Ferit%s" % [eng.pname(p), n, "a" if n == 1 else "e"], {"p": p, "n": n})
	if to != "discard":
		ko_check(eng, p, n)

func sp_block_armor_reduce(eng, ctx, params):
	add_mod(eng, ctx, "block_armor_reduce", {"n": _pi(params, "n", 3)})

func sp_influence_per_wound(eng, ctx, params):
	var p := _p(eng, ctx)
	var w := 0
	for iid in eng.P(p).hand:
		if eng.is_wound(iid):
			w += 1
	for u in eng.P(p).units:
		if u.wounded:
			w += 1
	var n := w * _pi(params, "n", 1)
	if n > 0:
		MKEffects.push(eng, [["influence", n]])

func sp_throw_action(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for iid in action_cards_in_hand(eng, p, str(ctx.get("src", ""))):
		opts.append({"v": iid, "label": "Getta via " + eng.card_name(iid)})
	choose(eng, ctx, "throw_action", "Scegli la carta Azione da gettare via", opts, {"by_color": params.get("by_color", {})}, "card")

func can_throw_action(eng, ctx, params) -> bool:
	return not action_cards_in_hand(eng, _p(eng, ctx), str(ctx.get("src", ""))).is_empty()

func res_throw_action(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var iid := str(v)
	var c: Dictionary = eng.card(iid)
	eng.P(p).hand.erase(iid)
	eng.P(p).removed.append(iid)
	eng.add_log("throw", "%s getta via %s" % [eng.pname(p), eng.card_name(iid)], {"p": p, "card": iid})
	var cols := card_colors(c)
	var bc: Dictionary = data.get("by_color", {})
	if cols.size() > 1:
		var opts: Array = []
		for col in cols:
			if bc.has(col):
				opts.append({"v": col, "label": MKMana.color_it(col).capitalize()})
		choose(eng, ctx, "throw_action_color", "Scegli il colore della carta gettata", opts, {"by_color": bc})
	elif not cols.is_empty() and bc.has(cols[0]):
		MKEffects.push(eng, bc[cols[0]])

func res_throw_action_color(eng, ctx, data, v):
	MKEffects.push(eng, data.by_color.get(str(v), []))

func _offer_matches(eng, ctx, params) -> Array:
	var kind := "spells" if _ps(params, "offer", "aa") in ["spells", "spell"] else "aa"
	var col := _ps(params, "color", "")
	if col == "$paid":
		col = str(ctx.get("paid", ""))
	var off: Array = eng.s.offers[kind]
	var out: Array = []
	for i in off.size():
		var id: String = off[i]
		var cols := card_colors(MKDB.card(id))
		if col == "" or col == "any":
			out.append(id)
		elif col == "lowest":
			if i == off.size() - 1:
				out.append(id)
		elif col.begins_with("not:"):
			if not col.substr(4) in cols:
				out.append(id)
		elif col in cols:
			out.append(id)
	return out

func sp_gain_from_offer(eng, ctx, params):
	var opts: Array = []
	var seen := {}
	for id in _offer_matches(eng, ctx, params):
		if seen.has(id):
			continue
		seen[id] = true
		opts.append({"v": id, "label": MKSites._cname(id)})
	var kind := "spells" if _ps(params, "offer", "aa") in ["spells", "spell"] else "aa"
	choose(eng, ctx, "gain_from_offer", "Scegli la carta dall'offerta", opts, {"kind": kind, "to": _ps(params, "to", "deck_top")}, "offer")

func res_gain_from_offer(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var id := str(v)
	eng.s.offers[data.kind].erase(id)
	eng._refill_offer(data.kind)
	var iid: String = eng.new_iid(id)
	match str(data.get("to", "deck_top")):
		"hand":
			eng.P(p).hand.append(iid)
		"discard":
			eng.P(p).discard.append(iid)
		_:
			eng.P(p).deck.push_front(iid)
	eng.add_log("gain_card", "%s ottiene %s" % [eng.pname(p), MKSites._cname(id)], {"p": p, "card": iid})

func sp_maximal_effect(eng, ctx, params):
	var p := _p(eng, ctx)
	var mode := _ps(params, "mode", "basic")
	var opts: Array = []
	for iid in action_cards_in_hand(eng, p, str(ctx.get("src", ""))):
		var c: Dictionary = eng.card(iid)
		if MKEffects.any_can(eng, c.get(mode, []), ctx):
			opts.append({"v": iid, "label": "Getta via " + eng.card_name(iid)})
	choose(eng, ctx, "maximal_effect", "Scegli la carta Azione da gettare via (Effetto massimo)", opts, {"mode": mode, "times": _pi(params, "times", 2)}, "card")

func can_maximal_effect(eng, ctx, params) -> bool:
	if ctx.get("_nested", false):
		return true
	var p := _p(eng, ctx)
	var c2: Dictionary = ctx.duplicate()
	c2["_nested"] = true
	for iid in action_cards_in_hand(eng, p, str(ctx.get("src", ""))):
		if MKEffects.any_can(eng, eng.card(iid).get(_ps(params, "mode", "basic"), []), c2):
			return true
	return false

func res_maximal_effect(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var iid := str(v)
	var c: Dictionary = eng.card(iid)
	eng.P(p).hand.erase(iid)
	eng.P(p).removed.append(iid)
	eng.add_log("throw", "%s getta via %s (Effetto massimo)" % [eng.pname(p), eng.card_name(iid)], {"p": p, "card": iid})
	var effs: Array = []
	for i in int(data.times):
		effs.append(c.get(data.mode, []).duplicate(true))
	MKEffects.push(eng, effs)

func sp_crystal_copy(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for c in MKMana.BASIC:
		if int(eng.P(p).crystals[c]) > 0:
			opts.append({"v": c, "label": "Cristallo " + MKMana.color_it(c)})
	choose(eng, ctx, "crystal_gain", "Scegli il colore del cristallo", opts, {}, "color")

func can_crystal_copy(eng, ctx, params) -> bool:
	var p := _p(eng, ctx)
	for c in MKMana.BASIC:
		if int(eng.P(p).crystals[c]) > 0:
			return true
	return false

func res_crystal_gain(eng, ctx, data, v):
	eng.gain_crystal(_p(eng, ctx), str(v))

func sp_crystals_return(eng, ctx, params):
	add_mod(eng, ctx, "crystals_return")

func sp_crystal_from_source_die(eng, ctx, params):
	var opts: Array = []
	for i in eng.s.source.size():
		var d: Dictionary = eng.s.source[i]
		if int(d.taken_by) == -1 and d.color in MKMana.BASIC:
			opts.append({"v": i, "label": "Dado " + MKMana.color_it(d.color)})
	choose(eng, ctx, "crystal_from_source_die", "Scegli un dado della Riserva", opts, {"reroll": params.get("reroll", true) if params is Dictionary else true}, "die")

func can_crystal_from_source_die(eng, ctx, params) -> bool:
	for d in eng.s.source:
		if int(d.taken_by) == -1 and d.color in MKMana.BASIC:
			return true
	return false

func res_crystal_from_source_die(eng, ctx, data, v):
	var d: Dictionary = eng.s.source[int(v)]
	eng.gain_crystal(_p(eng, ctx), d.color)
	if data.get("reroll", true):
		d.color = eng.DIE_COLORS[MKRng.rand_int(eng.s, 6)]

func sp_reroll_source(eng, ctx, params):
	for d in eng.s.source:
		if int(d.taken_by) == -1:
			d.color = eng.DIE_COLORS[MKRng.rand_int(eng.s, 6)]
	eng.add_log("info", "Tutti i dadi della Riserva vengono rilanciati")

func sp_source_black_gold_any(eng, ctx, params):
	add_mod(eng, ctx, "source_black_gold_any")

func sp_first_attack_or_block_bonus(eng, ctx, params):
	add_mod(eng, ctx, "first_attack_or_block_bonus", {"attack": _pi(params, "attack", 0), "block": _pi(params, "block", 0)})

func sp_magic_talent(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	var seen := {}
	for iid in eng.P(p).hand:
		if iid == ctx.get("src", "") or eng.is_wound(iid):
			continue
		var c: Dictionary = eng.card(iid)
		if seen.has(c.id):
			continue
		var ok := false
		for col in card_colors(c):
			for sid in eng.s.offers.spells:
				if col in card_colors(MKDB.card(sid)):
					ok = true
		if ok:
			seen[c.id] = true
			opts.append({"v": iid, "label": "Scarta " + eng.card_name(iid)})
	choose(eng, ctx, "magic_talent", "Talento magico: scegli la carta da scartare", opts, {}, "card")

func can_magic_talent(eng, ctx, params) -> bool:
	return not eng.s.offers.spells.is_empty() and eng.P(_p(eng, ctx)).hand.size() > 0

func res_magic_talent(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var c: Dictionary = eng.card(str(v))
	eng.discard_from_hand(p, str(v))
	var opts: Array = []
	for sid in eng.s.offers.spells:
		var sc: Dictionary = MKDB.card(sid)
		var col := str(sc.get("color", ""))
		if not col in card_colors(c):
			continue
		for mode in ["basic", "powered"]:
			var needs: Array = eng.card_mana_needs(sc, mode)
			if MKMana.plan(eng, p, needs) == null:
				continue
			var c2 := {"p": p, "src": "offer:" + sid, "kind": "card", "mode": mode}
			if not MKEffects.any_can(eng, sc.get(mode, []), c2):
				continue
			opts.append({"v": sid + "|" + mode, "label": "Lancia %s%s" % [MKSites._cname(sid), " (potenziato)" if mode == "powered" else ""]})
	opts.append({"v": "", "label": "Nessun incantesimo"})
	choose(eng, ctx, "magic_talent_cast", "Talento magico: scegli l'Incantesimo da lanciare", opts, {"always_ask": opts.size() > 1}, "offer")

func res_magic_talent_cast(eng, ctx, data, v):
	if str(v) == "":
		return
	var p := _p(eng, ctx)
	var parts := str(v).split("|")
	var sc: Dictionary = MKDB.card(parts[0])
	var needs: Array = eng.card_mana_needs(sc, parts[1])
	var plan = MKMana.plan(eng, p, needs)
	if plan == null:
		return
	MKMana.pay(eng, p, plan, needs)
	eng.add_log("play", "%s lancia %s dall'offerta" % [eng.pname(p), MKSites._cname(parts[0])], {"p": p})
	MKEffects.push(eng, sc.get(parts[1], []).duplicate(true))

func sp_buy_aa_with_influence(eng, ctx, params):
	add_mod(eng, ctx, "buy_aa_with_influence", {"cost": _pi(params, "cost", 6), "to": _ps(params, "to", "discard")})

func sp_attack_per_blocked(eng, ctx, params):
	if phase(eng) == "attack":
		var n := _pi(params, "n", 1) * int(eng.s.combat.get("blocked_count", 0))
		if n > 0:
			MKEffects.push(eng, [["attack", n]])
	else:
		add_mod(eng, ctx, "attack_per_blocked", {"n": _pi(params, "n", 1)})

func sp_block_vs_swift(eng, ctx, params):
	var n := _pi(params, "n", 3)
	eng.s.turn["block_swift"] = int(eng.s.turn.get("block_swift", 0)) + n
	eng.add_log("pts", "+%d Blocco (doppio contro Rapido)" % n, {"p": _p(eng, ctx), "what": "block", "n": n})

func can_block_vs_swift(eng, ctx, params) -> bool:
	return phase(eng) == "block"

func sp_block_swift(eng, ctx, params):
	sp_block_vs_swift(eng, ctx, params)

func can_block_swift(eng, ctx, params) -> bool:
	return phase(eng) == "block"

func sp_use_as_action(eng, ctx, params):
	eng.s.turn.acted = true

func can_use_as_action(eng, ctx, params) -> bool:
	return not eng.s.turn.acted and eng.s.combat == null

func sp_hand_limit_next(eng, ctx, params):
	var p := _p(eng, ctx)
	var n := _pi(params, "any", 0)
	var h: Dictionary = eng.hex(eng.P(p).pos)
	if h.get("t", "") == "hills":
		n = maxi(n, _pi(params, "hills", 0))
	if h.get("t", "") == "mountain":
		n = maxi(n, _pi(params, "mountain", 0))
	if n > 0:
		add_mod(eng, ctx, "hand_limit", {"n": n})

func sp_crystal_from_offer(eng, ctx, params):
	var opts: Array = []
	var seen := {}
	for sid in eng.s.offers.spells:
		var col := str(MKDB.card(sid).get("color", ""))
		if col in MKMana.BASIC and not seen.has(col):
			seen[col] = true
			opts.append({"v": col, "label": "Cristallo " + MKMana.color_it(col)})
	var n := _pi(params, "n", 1)
	if n > 1:
		MKEffects.push(eng, [["special", "crystal_from_offer", {"n": n - 1}]])
	choose(eng, ctx, "crystal_gain", "Scegli il colore del cristallo", opts, {}, "color")

func sp_attack_with_kill_reward(eng, ctx, params):
	var n := _pi(params, "n", 3)
	MKEffects.push(eng, [["attack", n, _ps(params, "elem", "phys"), _ps(params, "kind", "melee")]])
	add_mod(eng, ctx, "kill_reward", {"phase": phase(eng), "rep": _pi(params, "rep", 0), "fame": _pi(params, "fame", 0),
		"fame_once": _pi(params, "fame_once", 0), "armor_minus_other": _pi(params, "armor_minus_other", 0)})

func can_attack_with_kill_reward(eng, ctx, params) -> bool:
	return MKEffects.can(eng, ["attack", 1, "phys", _ps(params, "kind", "melee")], ctx)

func sp_influence_to_heal(eng, ctx, params):
	add_mod(eng, ctx, "influence_to_heal", {"per": _pi(params, "per", 2)})

func sp_ready_units_for_influence(eng, ctx, params):
	add_mod(eng, ctx, "ready_units_for_influence", {"per_level": _pi(params, "per_level", 2), "max_level": _pi(params, "max_level", 2)})

func sp_reduce_enemy_attack(eng, ctx, params):
	var opts: Array = []
	for e in enemy_targets(eng, {"need_attack": true}):
		for i in e.attacks.size():
			if MKCombat.attack_value(eng, e, i) > 0:
				opts.append({"v": e.eid + "|" + str(i), "label": "%s (attacco %d)" % [e.name, MKCombat.attack_value(eng, e, i)]})
	choose(eng, ctx, "reduce_enemy_attack", "Scegli l'attacco nemico da ridurre", opts, {"n": _pi(params, "n", 1), "left": _pi(params, "attacks", 1)}, "enemy")

func can_reduce_enemy_attack(eng, ctx, params) -> bool:
	return phase(eng) in ["ranged", "block"] and not enemy_targets(eng, {"need_attack": true}).is_empty()

func res_reduce_enemy_attack(eng, ctx, data, v):
	var parts := str(v).split("|")
	var e = MKCombat.entry(eng, parts[0])
	var at: Dictionary = e.attacks[int(parts[1])]
	at["mod"] = int(at.get("mod", 0)) - int(data.n)
	eng.add_log("info", "Attacco di %s ridotto di %d" % [e.name, int(data.n)])
	if int(data.get("left", 1)) > 1:
		var opts: Array = []
		for e2 in enemy_targets(eng, {"need_attack": true}):
			for i in e2.attacks.size():
				var key: String = e2.eid + "|" + str(i)
				if key != str(v) and MKCombat.attack_value(eng, e2, i) > 0:
					opts.append({"v": key, "label": "%s (attacco %d)" % [e2.name, MKCombat.attack_value(eng, e2, i)]})
		choose(eng, ctx, "reduce_enemy_attack", "Scegli un altro attacco nemico da ridurre", opts, {"n": data.n, "left": int(data.left) - 1}, "enemy")

func sp_attack_if_no_wounds(eng, ctx, params):
	if phase(eng) == "attack":
		if int(eng.s.combat.get("wounds_hand", 0)) == 0:
			MKEffects.push(eng, [["attack", _pi(params, "n", 2)]])
	else:
		add_mod(eng, ctx, "attack_if_no_wounds", {"n": _pi(params, "n", 2)})

func sp_unit_resist(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for u in eng.P(p).units:
		opts.append({"v": int(u.uid), "label": eng.unit_name(u)})
	choose(eng, ctx, "unit_resist", "Scegli l'unità", opts, {"elem": _ps(params, "elem", "phys")}, "unit")

func can_unit_resist(eng, ctx, params) -> bool:
	return in_combat(eng) and not eng.P(_p(eng, ctx)).units.is_empty()

func res_unit_resist(eng, ctx, data, v):
	var u = eng.find_unit(_p(eng, ctx), v)
	if u != null:
		if not u.has("extra_resist"):
			u["extra_resist"] = []
		u.extra_resist.append(data.elem)

func sp_crystal_new_color(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for c in MKMana.BASIC:
		if int(eng.P(p).crystals[c]) == 0:
			opts.append({"v": c, "label": "Cristallo " + MKMana.color_it(c)})
	choose(eng, ctx, "crystal_gain", "Scegli il colore del cristallo", opts, {}, "color")

func can_crystal_new_color(eng, ctx, params) -> bool:
	var p := _p(eng, ctx)
	for c in MKMana.BASIC:
		if int(eng.P(p).crystals[c]) == 0:
			return true
	return false

func sp_repeat_per_crystal_set(eng, ctx, params):
	var p := _p(eng, ctx)
	var sets := 99
	for c in MKMana.BASIC:
		sets = mini(sets, int(eng.P(p).crystals[c]))
	var effs: Array = []
	for i in sets:
		effs.append(params.get("effects", []).duplicate(true))
	if not effs.is_empty():
		MKEffects.push(eng, effs)

func sp_draw_on_wound(eng, ctx, params):
	var p := _p(eng, ctx)
	var m := add_mod(eng, ctx, "draw_on_wound", {"n": _pi(params, "n", 3), "throw_first": params.get("throw_first", false) if params is Dictionary else false, "used": 0})
	# wounds already taken this turn
	var already := 0
	for iid in eng.s.turn.get("wounds_received", []):
		if eng.P(p).hand.has(iid):
			already += 1
	if m.throw_first and already > 0:
		m["_thrown"] = true
		for iid in eng.s.turn.wounds_received:
			if eng.P(p).hand.has(iid):
				eng.throw_away(p, iid)
				already -= 1
				break
	var d := mini(already, int(m.n))
	if d > 0:
		m.used = d
		eng.draw(p, d)

func sp_enemy_attack_strip(eng, ctx, params):
	var what := _ps(params, "what", "abilities")
	var opts := _enemy_opts(enemy_targets(eng, {}))
	choose(eng, ctx, "enemy_attack_strip", "Scegli il nemico", opts, {"what": what}, "enemy")

func can_enemy_attack_strip(eng, ctx, params) -> bool:
	return phase(eng) in ["ranged", "block"] and not enemy_targets(eng, {}).is_empty()

func res_enemy_attack_strip(eng, ctx, data, v):
	var e = MKCombat.entry(eng, str(v))
	if e == null:
		return
	var atk_ab := ["swift", "brutal", "poison", "paralyze", "summon", "assassinate", "vampiric"]
	if data.what == "abilities":
		if not e.has("lost"):
			e["lost"] = []
		for a in atk_ab:
			e.lost.append(a)
		eng.add_log("info", "%s perde le abilità d'attacco" % e.name)
		return
	var opts: Array = []
	for i in e.attacks.size():
		if MKCombat.attack_elem(e, i) != "phys":
			opts.append({"v": "elem|%d" % i, "label": "L'attacco diventa fisico"})
	for a in atk_ab:
		if MKCombat.has_ab(e, a):
			opts.append({"v": "ab|" + a, "label": "Rimuovi " + a})
	choose(eng, ctx, "enemy_attack_strip_one", "Cosa rimuovere?", opts, {"eid": e.eid}, "choice")

func res_enemy_attack_strip_one(eng, ctx, data, v):
	var e = MKCombat.entry(eng, str(data.eid))
	var parts := str(v).split("|")
	if parts[0] == "elem":
		e.attacks[int(parts[1])]["elem_override"] = "phys"
	else:
		if not e.has("lost"):
			e["lost"] = []
		e.lost.append(parts[1])

func sp_enemy_no_attack(eng, ctx, params):
	var f := {"unfortified": params.get("unfortified", false) if params is Dictionary else false, "immune": _ps(params, "immune", ""), "need_attack": true}
	var opts := _enemy_opts(enemy_targets(eng, f))
	var data := {"left": _pi(params, "targets", 1), "f": f, "armor": _pi(params, "armor", 0), "lose_resist": _ps(params, "lose_resist", ""),
		"extra_move": params.get("extra_targets_move", false) if params is Dictionary else false, "count": 0}
	choose(eng, ctx, "enemy_no_attack", "Scegli il nemico che non attaccherà", opts, data, "enemy")

func can_enemy_no_attack(eng, ctx, params) -> bool:
	var f := {"unfortified": params.get("unfortified", false) if params is Dictionary else false, "immune": _ps(params, "immune", ""), "need_attack": true}
	return phase(eng) in ["ranged", "block"] and not enemy_targets(eng, f).is_empty()

func res_enemy_no_attack(eng, ctx, data, v):
	if str(v) == "":
		return
	var e = MKCombat.entry(eng, str(v))
	if e == null:
		return
	e["no_attack"] = true
	data.count = int(data.count) + 1
	if int(data.armor) > 0:
		e.armor_mod = int(e.get("armor_mod", 0)) - int(data.armor)
	if str(data.lose_resist) != "":
		if not e.has("lost_resist"):
			e["lost_resist"] = []
		e.lost_resist.append(data.lose_resist)
	eng.add_log("info", "%s non attacca in questo combattimento" % e.name, {"eid": e.eid})
	var left := int(data.left) - 1
	var opts := _enemy_opts(enemy_targets(eng, data.f))
	if data.get("extra_move", false):
		var cost := int(data.count)
		if int(eng.s.turn.pool.move) >= cost and not opts.is_empty():
			var o2: Array = [{"v": "", "label": "Basta così"}]
			for o in opts:
				o2.append({"v": o.v, "label": "%s (paga %d Movimento)" % [o.label, cost]})
			data["pay_move"] = cost
			data["always_ask"] = true
			choose(eng, ctx, "enemy_no_attack_move", "Vuoi bloccare un altro nemico?", o2, data, "enemy")
		return
	if left > 0 and not opts.is_empty():
		opts.push_front({"v": "", "label": "Basta così"})
		data.left = left
		data["always_ask"] = true
		choose(eng, ctx, "enemy_no_attack", "Scegli un altro nemico che non attaccherà", opts, data, "enemy")

func res_enemy_no_attack_move(eng, ctx, data, v):
	if str(v) == "":
		return
	eng.s.turn.pool.move = int(eng.s.turn.pool.move) - int(data.pay_move)
	res_enemy_no_attack(eng, ctx, data, v)

func sp_mana_draw(eng, ctx, params):
	var dice := _pi(params, "dice", 1)
	var opts: Array = []
	for i in eng.s.source.size():
		var d: Dictionary = eng.s.source[i]
		if int(d.taken_by) == -1:
			opts.append({"v": i, "label": "Prendi il dado %s" % MKMana.color_it(d.color)})
	choose(eng, ctx, "mana_draw", "Scegli il dado da prendere", opts, {"left": dice, "tokens": _pi(params, "tokens", 2)}, "die")

func can_mana_draw(eng, ctx, params) -> bool:
	for d in eng.s.source:
		if int(d.taken_by) == -1:
			return true
	return false

func res_mana_draw(eng, ctx, data, v):
	var opts: Array = []
	for c in ["red", "blue", "green", "white", "black"]:
		opts.append({"v": "%d|%s" % [int(v), c], "label": MKMana.color_it(c).capitalize()})
	choose(eng, ctx, "mana_draw_color", "Scegli il colore del dado", opts, data, "color")

func res_mana_draw_color(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var parts := str(v).split("|")
	var i := int(parts[0])
	var col := parts[1]
	var d: Dictionary = eng.s.source[i]
	d.color = col
	d.taken_by = p
	eng.s.turn.fixed_dice.append(i)
	for n in int(data.tokens):
		eng.gain_token(p, col)
	var left := int(data.left) - 1
	if left > 0:
		var opts: Array = []
		for j in eng.s.source.size():
			if int(eng.s.source[j].taken_by) == -1:
				opts.append({"v": j, "label": "Prendi il dado %s" % MKMana.color_it(eng.s.source[j].color)})
		data.left = left
		choose(eng, ctx, "mana_draw", "Scegli un altro dado", opts, data, "die")

func sp_extra_black_die_any(eng, ctx, params):
	add_mod(eng, ctx, "extra_black_die_any")

func sp_per_recruit(eng, ctx, params):
	add_mod(eng, ctx, "per_recruit", {"rep": _pi(params, "rep", 0), "fame": _pi(params, "fame", 0)})

func sp_units_bonus(eng, ctx, params):
	add_mod(eng, ctx, "attack_bonus", {"n": _pi(params, "attack", 2), "src_kind": "unit"})
	add_mod(eng, ctx, "block_bonus", {"n": _pi(params, "block", 2), "src_kind": "unit"})
	if params is Dictionary and params.get("no_unit_damage", false):
		add_mod(eng, ctx, "no_unit_damage")

func can_units_bonus(eng, ctx, params) -> bool:
	return phase(eng) == "ranged"

func sp_card_to_deck_end_turn(eng, ctx, params):
	add_mod(eng, ctx, "card_to_deck_end_turn", {"pos": _ps(params, "pos", "bottom")})

func sp_influence_as_block(eng, ctx, params):
	add_mod(eng, ctx, "influence_as_block", {"elem": _ps(params, "elem", "phys")})

func sp_move_to_attack(eng, ctx, params):
	var d := {}
	if params is Dictionary:
		for k in ["melee", "ranged"]:
			if params.has(k):
				d[k] = int(params[k])
	add_mod(eng, ctx, "move_to_attack", d)

func sp_interaction_bonus(eng, ctx, params):
	add_mod(eng, ctx, "interaction_bonus", {"fame": _pi(params, "fame", 0), "rep": _pi(params, "rep", 0)})

func sp_block_per_enemy_ability(eng, ctx, params):
	eng.s.turn["block_per_ability"] = {"n": _pi(params, "n", 1), "elem": _ps(params, "elem", "ice")}

func sp_move_card_bonus(eng, ctx, params):
	add_mod(eng, ctx, "move_card_bonus", {"n": _pi(params, "n", 1), "cards": str(params.get("cards", 1)) if params is Dictionary else "1"})

func sp_recruit_discount(eng, ctx, params):
	add_mod(eng, ctx, "recruit_discount", {"n": _pi(params, "n", 2), "units": str(params.get("units", "1")) if params is Dictionary else "1", "rep": _pi(params, "rep", 0)})

func sp_block_by_terrain(eng, ctx, params):
	var p := _p(eng, ctx)
	var h: Dictionary = eng.hex(eng.P(p).pos)
	var t := str(h.get("t", "plains"))
	var n := 2
	if t == "mountain":
		n = 5
	elif t == "lake":
		n = 2
	else:
		var tab: Dictionary = eng.COST_DAY if eng.s.day else eng.COST_NIGHT
		n = int(tab.get(t, 2))
	MKEffects.push(eng, [["block", n, "fire" if eng.s.day else "ice"]])

func can_block_by_terrain(eng, ctx, params) -> bool:
	return phase(eng) == "block"

func sp_return_card_end_turn(eng, ctx, params):
	add_mod(eng, ctx, "return_card_end_turn", {"wound_ok": params.get("wound_ok", false) if params is Dictionary else false})

func sp_delayed_attack(eng, ctx, params):
	var n := _pi(params, "n", 1)
	var el := _ps(params, "elem", "phys")
	if phase(eng) == "attack" or (params is Dictionary and params.get("any_time", false) and in_combat(eng) and phase(eng) == "attack"):
		MKEffects.push(eng, [["attack", n, el]])
	elif in_combat(eng):
		if not eng.s.combat.has("delayed"):
			eng.s.combat["delayed"] = []
		eng.s.combat.delayed.append({"n": n, "elem": el})

func sp_attack_vs_resistant(eng, ctx, params):
	var any := false
	for e in enemy_targets(eng, {}):
		if not e.resist.is_empty():
			any = true
	MKEffects.push(eng, [["attack", _pi(params, "n_if_resist", 6) if any else _pi(params, "n", 4)]])

func can_attack_vs_resistant(eng, ctx, params) -> bool:
	return phase(eng) == "attack"

func sp_attack_per_combat_wound(eng, ctx, params):
	if not in_combat(eng):
		return
	var w := mini(int(eng.s.combat.get("wounds_hand", 0)), _pi(params, "max", 1))
	var n := w * _pi(params, "n", 1)
	if n > 0:
		MKEffects.push(eng, [["attack", n]])

func sp_no_provoke(eng, ctx, params):
	add_mod(eng, ctx, "no_provoke")

func sp_discard_card(eng, ctx, params):
	var wound_ok: bool = params.get("wound_ok", false) if params is Dictionary else false
	MKEffects.push(eng, [["discard", 1, params.get("effects", []) if params is Dictionary else [], wound_ok]])

func sp_pay_crystal(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for c in MKMana.BASIC:
		if int(eng.P(p).crystals[c]) > 0:
			opts.append({"v": c, "label": "Spendi un cristallo " + MKMana.color_it(c)})
	choose(eng, ctx, "pay_crystal", "Scegli il cristallo da spendere", opts, {"effects": params.get("effects", []), "by_color": params.get("by_color", {})}, "color")

func can_pay_crystal(eng, ctx, params) -> bool:
	return can_crystal_copy(eng, ctx, params)

func res_pay_crystal(eng, ctx, data, v):
	var p := _p(eng, ctx)
	eng.P(p).crystals[str(v)] = int(eng.P(p).crystals[str(v)]) - 1
	ctx["paid"] = str(v)
	if data.by_color is Dictionary and data.by_color.has(str(v)):
		MKEffects.push(eng, data.by_color[str(v)])
	else:
		MKEffects.push(eng, data.effects)

# ---------------------------------------------------------------- magic
func sp_all_units_bonus(eng, ctx, params):
	add_mod(eng, ctx, "unit_armor", {"n": _pi(params, "armor", 1)})
	add_mod(eng, ctx, "all_units_bonus", {"bonus": _pi(params, "bonus", 1), "fame": _pi(params, "fame", 1)})

func sp_amulet_darkness(eng, ctx, params):
	if eng.s.day:
		eng.s.turn.mods.append({"name": "terrain", "map": {"desert": 3}, "src": ctx.get("src", "")})
		add_mod(eng, ctx, "black_ok")

func sp_amulet_sun(eng, ctx, params):
	if not eng.s.day:
		eng.s.turn.mods.append({"name": "terrain", "map": {"forest": 3}, "src": ctx.get("src", "")})
		add_mod(eng, ctx, "gold_ok")
		var p := _p(eng, ctx)
		for nk in [eng.P(p).pos] + MKHex.neighbors(eng.P(p).pos):
			var h: Dictionary = eng.hex(nk)
			for eid in h.get("enemies", []):
				eng.s.enemies[eid].face_up = true
			if h.get("ruins", "") != "":
				h["ruins_face_up"] = true

func sp_armor_mod(eng, ctx, params):
	var f := {"immune": _ps(params, "immune", "")}
	var data := {"amount": _pi(params, "amount", 1), "fortified": _pi(params, "fortified", -1), "others": _pi(params, "others", 0), "f": f}
	if not in_combat(eng):
		# before combat (e.g. Demolish basic): applied when the combat starts
		add_mod(eng, ctx, "pre_combat", {"armor": data.amount, "immune": f.immune})
		return
	if _ps(params, "targets", "one") == "all":
		for e in enemy_targets(eng, f):
			_armor_reduce(e, data)
		eng.add_log("info", "Tutti i nemici: Armatura -%d" % int(data.amount))
		return
	choose(eng, ctx, "armor_mod", "Scegli il nemico", _enemy_opts(enemy_targets(eng, f)), data, "enemy")

func can_armor_mod(eng, ctx, params) -> bool:
	if not in_combat(eng):
		return eng.s.turn.get("player", -1) == _p(eng, ctx)
	return not enemy_targets(eng, {"immune": _ps(params, "immune", "")}).is_empty() and phase(eng) in ["ranged", "block", "attack"]

static func _armor_reduce(e: Dictionary, data: Dictionary) -> void:
	var amt := int(data.amount)
	if int(data.get("fortified", -1)) >= 0 and MKCombat.is_fortified(e):
		amt = int(data.fortified)
	e.armor_mod = int(e.get("armor_mod", 0)) - amt

func res_armor_mod(eng, ctx, data, v):
	var e = MKCombat.entry(eng, str(v))
	_armor_reduce(e, data)
	eng.add_log("info", "%s: Armatura ridotta" % e.name)
	if int(data.get("others", 0)) > 0:
		for o in enemy_targets(eng, data.f):
			if o.eid != e.eid:
				o.armor_mod = int(o.get("armor_mod", 0)) - int(data.others)

func sp_armor_per_resistance(eng, ctx, params):
	choose(eng, ctx, "armor_per_resistance", "Scegli il nemico", _enemy_opts(enemy_targets(eng, {})), {"n": _pi(params, "n", 1)}, "enemy")

func can_armor_per_resistance(eng, ctx, params) -> bool:
	for e in enemy_targets(eng, {}):
		if not e.resist.is_empty():
			return true
	return false

func res_armor_per_resistance(eng, ctx, data, v):
	var e = MKCombat.entry(eng, str(v))
	var n: int = e.resist.size() * int(data.n)
	e.armor_mod = int(e.get("armor_mod", 0)) - n
	eng.add_log("info", "%s: Armatura -%d" % [e.name, n])

func sp_attacks_transform(eng, ctx, params):
	add_mod(eng, ctx, "attacks_transform", {"to": _ps(params, "to", "cold")})
	var to := _ps(params, "to", "cold")
	var pool: Dictionary = eng.s.turn.pool.attack
	var np := {}
	for k in pool:
		var kd: String = k.split(":")[0]
		var el: String = k.split(":")[1]
		if to == "cold":
			el = "cold"
		else:
			kd = "siege"
		var nk := kd + ":" + el
		np[nk] = int(np.get(nk, 0)) + int(pool[k])
	eng.s.turn.pool.attack = np

func can_attacks_transform(eng, ctx, params) -> bool:
	return in_combat(eng)

func sp_banner_attach(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for u in eng.P(p).units:
		opts.append({"v": int(u.uid), "label": "Assegna a " + eng.unit_name(u)})
	choose(eng, ctx, "banner_attach", "Scegli l'unità a cui assegnare lo Stendardo", opts, {"card": str(ctx.get("src", ""))}, "unit")

func can_banner_attach(eng, ctx, params) -> bool:
	return not eng.P(_p(eng, ctx)).units.is_empty() and str(ctx.get("src", "")).find("#") >= 0

func res_banner_attach(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var pl: Dictionary = eng.P(p)
	if not pl.has("banners"):
		pl["banners"] = {}
	var key := str(int(v))
	if pl.banners.has(key):
		pl.discard.append(pl.banners[key])
	pl.banners[key] = data.card
	pl.play.erase(data.card)
	eng.add_log("info", "%s assegna %s a %s" % [eng.pname(p), eng.card_name(data.card), eng.unit_name_by_uid(p, v)], {"p": p})

func sp_bonds_of_loyalty(eng, ctx, params):
	var p := _p(eng, ctx)
	var pl: Dictionary = eng.P(p)
	if ctx.get("kind", "") != "skill_passive":
		return
	pl.command = int(pl.command) + 1
	pl["extra_command"] = int(pl.get("extra_command", 0)) + 1
	pl["bonds_discount"] = _pi(params, "discount", 5)
	for i in _pi(params, "offer_regular", 2):
		if not eng.s.decks.units_reg.is_empty():
			eng.s.offers.units.append(eng.s.decks.units_reg.pop_front())

func sp_book_of_wisdom(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for iid in action_cards_in_hand(eng, p, str(ctx.get("src", ""))):
		opts.append({"v": iid, "label": "Getta via " + eng.card_name(iid)})
	choose(eng, ctx, "book_of_wisdom", "Scegli la carta Azione da gettare via", opts, {"gain": _ps(params, "gain", "aa"), "crystal": params.get("crystal", false) if params is Dictionary else false}, "card")

func can_book_of_wisdom(eng, ctx, params) -> bool:
	return can_throw_action(eng, ctx, params)

func res_book_of_wisdom(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var c: Dictionary = eng.card(str(v))
	eng.P(p).hand.erase(str(v))
	eng.P(p).removed.append(str(v))
	var col := str(card_colors(c)[0]) if not card_colors(c).is_empty() else ""
	if data.get("crystal", false) and col in MKMana.BASIC:
		eng.gain_crystal(p, col)
	MKEffects.push(eng, [["special", "gain_from_offer", {"offer": "spells" if data.gain == "spell" else "aa", "color": col, "to": "hand"}]])

func sp_destroy_enemy(eng, ctx, params):
	var f := {"immune": _ps(params, "immune", "")}
	choose(eng, ctx, "destroy_enemy", "Scegli il nemico da distruggere", _enemy_opts(enemy_targets(eng, f)), {"others": _pi(params, "others_armor", 0), "f": f}, "enemy")

func can_destroy_enemy(eng, ctx, params) -> bool:
	var ph := _ps(params, "phase", "")
	if ph != "" and phase(eng) != ph:
		return false
	return not enemy_targets(eng, {"immune": _ps(params, "immune", "")}).is_empty()

func res_destroy_enemy(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var e = MKCombat.entry(eng, str(v))
	MKCombat.defeat(eng, p, e)
	if int(data.others) > 0:
		for o in enemy_targets(eng, data.f):
			o.armor_mod = int(o.get("armor_mod", 0)) - int(data.others)
	MKCombat._check_all_defeated(eng)

func sp_discard_any_for(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = [{"v": "", "label": "Basta così"}]
	for iid in eng.P(p).hand:
		if not eng.is_wound(iid):
			opts.append({"v": iid, "label": "Scarta " + eng.card_name(iid)})
	if opts.size() > 1:
		ask(eng, ctx, "discard_any_for", "Scarta carte per ottenere %s ciascuna" % MKEffects.describe(params.get("effect", [])), opts, {"effect": params.get("effect", [])}, "card")

func res_discard_any_for(eng, ctx, data, v):
	if str(v) == "":
		return
	var p := _p(eng, ctx)
	eng.discard_from_hand(p, str(v))
	MKEffects.push(eng, [data.effect.duplicate(true), ["special", "discard_any_for", {"effect": data.effect}]])

func sp_discard_wound_draw(eng, ctx, params):
	var p := _p(eng, ctx)
	for iid in eng.P(p).hand:
		if eng.is_wound(iid):
			eng.discard_from_hand(p, iid)
			eng.draw(p, 1)
			return

func can_discard_wound_draw(eng, ctx, params) -> bool:
	for iid in eng.P(_p(eng, ctx)).hand:
		if eng.is_wound(iid):
			return true
	return false

func sp_double_attacks(eng, ctx, params):
	add_mod(eng, ctx, "double_attacks", {"elem": _ps(params, "elem", "phys"), "phase": _ps(params, "phase", "attack")})
	if phase(eng) == _ps(params, "phase", "attack"):
		var pool: Dictionary = eng.s.turn.pool.attack
		for k in pool:
			if k.ends_with(":" + _ps(params, "elem", "phys")):
				pool[k] = int(pool[k]) * 2

func sp_draw_per_heal(eng, ctx, params):
	add_mod(eng, ctx, "draw_per_heal")

func sp_fame_per_heal(eng, ctx, params):
	add_mod(eng, ctx, "fame_per_heal", {"left": 2})

func sp_fame_per_kill(eng, ctx, params):
	add_mod(eng, ctx, "fame_per_kill", {"n": _pi(params, "n", 1)})

func sp_flight(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	var pos: String = eng.P(p).pos
	for k in eng.s.map.hex:
		var d := MKHex.distance(pos, k)
		if d == 0 or d > 2:
			continue
		if d == 2 and int(eng.s.turn.pool.move) < 2:
			continue
		if not eng._is_safe(p, k) or not eng.hex(k).get("enemies", []).is_empty() and eng.hex(k).get("rampage", false):
			continue
		opts.append({"v": k, "label": "Vola in %s (%s)%s" % [k, eng._hex_label(k), " - 2 Movimento" if d == 2 else ""]})
	opts.sort_custom(func(a, b): return str(a.v) < str(b.v))
	opts.push_front({"v": "", "label": "Non volare"})
	choose(eng, ctx, "flight", "Volo: scegli la destinazione", opts, {"always_ask": true}, "hex")

func can_flight(eng, ctx, params) -> bool:
	return eng.can_still_move(_p(eng, ctx))

func res_flight(eng, ctx, data, v):
	if str(v) == "":
		return
	var p := _p(eng, ctx)
	if MKHex.distance(eng.P(p).pos, str(v)) == 2:
		eng.s.turn.pool.move = int(eng.s.turn.pool.move) - 2
	eng.teleport(p, str(v), true)

func sp_gem_pouch_roll(eng, ctx, params):
	var p := _p(eng, ctx)
	var effs: Array = []
	for i in _pi(params, "rolls", 2):
		var col: String = eng.DIE_COLORS[MKRng.rand_int(eng.s, 6)]
		eng.add_log("roll", "Dado: %s" % MKMana.color_it(col), {"p": p})
		if col == "black":
			effs.append(["fame", 1])
		elif col == "gold":
			effs.append(["crystal", "basic"])
		else:
			effs.append(["crystal", col])
	MKEffects.push(eng, effs)

func sp_heal_by_terrain(eng, ctx, params):
	var p := _p(eng, ctx)
	var n := _pi(params, "n", 3)
	if eng.hex(eng.P(p).pos).get("t", "") == _ps(params, "terrain", "forest"):
		n = _pi(params, "n_terrain", n)
	MKEffects.push(eng, [["heal", n]])

func can_heal_by_terrain(eng, ctx, params) -> bool:
	return MKEffects.can(eng, ["heal", 1], ctx)

func _throw_wounds(eng, p: int, n: int) -> int:
	var k := 0
	for iid in eng.P(p).hand.duplicate():
		if k >= n:
			break
		if eng.is_wound(iid):
			eng.throw_away(p, iid)
			k += 1
	return k

func sp_healing_ritual(eng, ctx, params):
	var p := _p(eng, ctx)
	var k := _throw_wounds(eng, p, 2)
	if k > 0 and eng.s.players.size() > 1 and eng.is_competitive():
		var best := -1
		var bd := 999
		for i in eng.s.players.size():
			if i == p:
				continue
			var d := MKHex.distance(eng.P(p).pos, eng.P(i).pos)
			if d < bd:
				bd = d
				best = i
		if best >= 0:
			eng.add_wound(best, true)
	eng.add_log("heal", "%s getta via %d ferite" % [eng.pname(p), k], {"p": p})

func can_healing_ritual(eng, ctx, params) -> bool:
	return can_discard_wound_draw(eng, ctx, params)

func sp_ritual_of_pain(eng, ctx, params):
	var p := _p(eng, ctx)
	var k := _throw_wounds(eng, p, 2)
	eng.add_log("heal", "%s getta via %d ferite" % [eng.pname(p), k], {"p": p})

func can_ritual_of_pain(eng, ctx, params) -> bool:
	return can_discard_wound_draw(eng, ctx, params)

func sp_horn_powered(eng, ctx, params):
	var opts: Array = []
	for i in _pi(params, "max", 5) + 1:
		opts.append({"v": i, "label": "+%d Attacco d'assedio (tira %d dad%s)" % [i, i, "o" if i == 1 else "i"]})
	choose(eng, ctx, "horn_powered", "Corno dell'ira: quanto vuoi aggiungere?", opts, {}, "choice")

func res_horn_powered(eng, ctx, data, v):
	var n := int(v)
	if n <= 0:
		return
	MKEffects.push(eng, [["attack", n, "phys", "siege"], ["special", "roll_wound", {"dice": n}]])

func sp_roll_wound(eng, ctx, params):
	var p := _p(eng, ctx)
	var w := 0
	for i in _pi(params, "dice", 1):
		var col: String = eng.DIE_COLORS[MKRng.rand_int(eng.s, 6)]
		if col in ["black", "red"]:
			w += 1
	if w > 0:
		sp_take_wound(eng, ctx, {"n": w})
	else:
		eng.add_log("roll", "Nessuna ferita dai dadi", {"p": p})

func sp_if_lowest_fame(eng, ctx, params):
	var p := _p(eng, ctx)
	if eng.s.players.size() < 2:
		return
	for i in eng.s.players.size():
		if i != p and int(eng.P(i).fame) <= int(eng.P(p).fame):
			return
	MKEffects.push(eng, params.get("effects", []).duplicate(true))

func sp_motivation_lock(eng, ctx, params):
	pass

func sp_influence_per_crystal_color(eng, ctx, params):
	var p := _p(eng, ctx)
	var n := 0
	for c in MKMana.BASIC:
		if int(eng.P(p).crystals[c]) > 0:
			n += 1
	if n > 0:
		MKEffects.push(eng, [["influence", n]])

func can_influence_per_crystal_color(eng, ctx, params) -> bool:
	return eng.s.combat == null and MKSites.can_interact(eng, _p(eng, ctx)) == "" and can_crystal_copy(eng, ctx, params)

func sp_invocation(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	var w := false
	var nw := {}
	for iid in eng.P(p).hand:
		if eng.is_wound(iid):
			if not w:
				w = true
				opts.append({"v": iid + "|red", "label": "Scarta una Ferita: gettone rosso"})
				opts.append({"v": iid + "|black", "label": "Scarta una Ferita: gettone nero"})
		elif not nw.has(eng.card_id(iid)):
			nw[eng.card_id(iid)] = true
			opts.append({"v": iid + "|white", "label": "Scarta %s: gettone bianco" % eng.card_name(iid)})
			opts.append({"v": iid + "|green", "label": "Scarta %s: gettone verde" % eng.card_name(iid)})
	choose(eng, ctx, "invocation", "Invocazione", opts, {"always_ask": true}, "card")

func can_invocation(eng, ctx, params) -> bool:
	return not eng.P(_p(eng, ctx)).hand.is_empty()

func res_invocation(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var parts := str(v).split("|")
	eng.discard_from_hand(p, parts[0])
	eng.gain_token(p, parts[1])

func sp_mana_any(eng, ctx, params):
	var effs: Array = []
	for i in _pi(params, "n", 1):
		effs.append(["choice", [[["mana", "red"]], [["mana", "blue"]], [["mana", "green"]], [["mana", "white"]], [["mana", "gold"]], [["mana", "black"]]]])
	MKEffects.push(eng, effs)

func sp_mana_claim(eng, ctx, params):
	var opts: Array = []
	for i in eng.s.source.size():
		var d: Dictionary = eng.s.source[i]
		if int(d.taken_by) == -1 and d.color in MKMana.BASIC:
			opts.append({"v": "%d|now" % i, "label": "Dado %s: 3 gettoni ora" % MKMana.color_it(d.color)})
			opts.append({"v": "%d|turn" % i, "label": "Dado %s: 1 gettone a ogni tuo turno" % MKMana.color_it(d.color)})
	choose(eng, ctx, "mana_claim", "Rivendicare il mana: scegli il dado", opts, {}, "die")

func can_mana_claim(eng, ctx, params) -> bool:
	return can_crystal_from_source_die(eng, ctx, params)

func res_mana_claim(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var parts := str(v).split("|")
	var i := int(parts[0])
	var col: String = eng.s.source[i].color
	eng.s.source.remove_at(i)
	if parts[1] == "now":
		for n in 3:
			eng.gain_token(p, col)
	else:
		eng.gain_token(p, col)
		eng.P(p)["mana_claim_color"] = col

func sp_mana_exploit(eng, ctx, params):
	MKEffects.push(eng, [["choice", [[["mana", "red"]], [["mana", "blue"]], [["mana", "green"]], [["mana", "white"]], [["mana", "black"]]]]])

func sp_mana_overload(eng, ctx, params):
	sp_mana_exploit(eng, ctx, params)

func sp_mana_meltdown(eng, ctx, params):
	var p := _p(eng, ctx)
	var lost: Array = []
	for i in eng.s.players.size():
		if i == p:
			continue
		var pl: Dictionary = eng.P(i)
		var have: Array = []
		for c in MKMana.BASIC:
			for n in int(pl.crystals[c]):
				have.append(c)
		if have.is_empty():
			eng.add_wound(i, true)
		else:
			var c2: String = have[MKRng.rand_int(eng.s, have.size())]
			pl.crystals[c2] = int(pl.crystals[c2]) - 1
			lost.append(c2)
	if not lost.is_empty():
		var opts: Array = [{"v": "", "label": "Nessuno"}]
		for c3 in lost:
			opts.append({"v": c3, "label": "Prendi un cristallo " + MKMana.color_it(c3)})
		choose(eng, ctx, "crystal_gain_opt", "Prendi uno dei cristalli persi", opts, {"always_ask": true}, "color")

func res_crystal_gain_opt(eng, ctx, data, v):
	if str(v) != "":
		eng.gain_crystal(_p(eng, ctx), str(v))

func sp_mana_radiance(eng, ctx, params):
	var opts: Array = []
	for c in MKMana.BASIC:
		opts.append({"v": c, "label": MKMana.color_it(c).capitalize()})
	choose(eng, ctx, "mana_radiance", "Splendore del mana: scegli un colore", opts, {}, "color")

func res_mana_radiance(eng, ctx, data, v):
	var p := _p(eng, ctx)
	for i in eng.s.players.size():
		for n in int(eng.P(i).crystals[str(v)]):
			eng.add_wound(i, true)
	eng.gain_crystal(p, str(v))
	eng.gain_crystal(p, str(v))

func sp_meditation(eng, ctx, params):
	var p := _p(eng, ctx)
	var pl: Dictionary = eng.P(p)
	add_mod(eng, ctx, "hand_limit", {"n": 2})
	if pl.discard.is_empty():
		return
	if params is Dictionary and params.get("random", true):
		var picks: Array = []
		var pool: Array = pl.discard.duplicate()
		for i in 2:
			if pool.is_empty():
				break
			var j := MKRng.rand_int(eng.s, pool.size())
			picks.append(pool[j])
			pool.remove_at(j)
		for iid in picks:
			pl.discard.erase(iid)
			pl.deck.push_front(iid)
		eng.add_log("info", "%s rimette 2 carte in cima al mazzo" % eng.pname(p), {"p": p})
	else:
		_meditation_ask(eng, ctx, 2)

func _meditation_ask(eng, ctx, left: int):
	var p := _p(eng, ctx)
	var opts: Array = []
	var seen := {}
	for iid in eng.P(p).discard:
		if seen.has(eng.card_id(iid)):
			continue
		seen[eng.card_id(iid)] = true
		opts.append({"v": iid, "label": eng.card_name(iid)})
	choose(eng, ctx, "meditation", "Scegli una carta dagli scarti da mettere in cima al mazzo", opts, {"left": left}, "card")

func res_meditation(eng, ctx, data, v):
	var p := _p(eng, ctx)
	eng.P(p).discard.erase(str(v))
	eng.P(p).deck.push_front(str(v))
	if int(data.left) > 1 and not eng.P(p).discard.is_empty():
		_meditation_ask(eng, ctx, int(data.left) - 1)

func sp_mind_read(eng, ctx, params):
	var opts: Array = []
	for c in MKMana.BASIC:
		opts.append({"v": c, "label": "Cristallo " + MKMana.color_it(c)})
	choose(eng, ctx, "mind_read", "Leggere la mente: scegli un colore", opts, {}, "color")

func res_mind_read(eng, ctx, data, v):
	var p := _p(eng, ctx)
	eng.gain_crystal(p, str(v))
	for i in eng.s.players.size():
		if i == p:
			continue
		for iid in eng.P(i).hand:
			var c: Dictionary = eng.card(iid)
			if str(c.get("type", "")) in ["basic", "aa", "spell"] and str(v) in card_colors(c):
				eng.discard_from_hand(i, iid)
				break

func sp_move_per_ready_unit(eng, ctx, params):
	var p := _p(eng, ctx)
	var n := 0
	for u in eng.P(p).units:
		if u.ready and not u.wounded:
			n += 1
	n = mini(n, _pi(params, "max", 3))
	if n > 0:
		MKEffects.push(eng, [["move", n]])

func can_move_per_ready_unit(eng, ctx, params) -> bool:
	if not eng.can_still_move(_p(eng, ctx)):
		return false
	for u in eng.P(_p(eng, ctx)).units:
		if u.ready and not u.wounded:
			return true
	return false

func sp_opponents_exhaust_unit(eng, ctx, params):
	var p := _p(eng, ctx)
	if not eng.is_competitive():
		return
	for i in eng.s.players.size():
		if i == p:
			continue
		var best = null
		for u in eng.P(i).units:
			if u.ready and eng.unit_level(u) <= _pi(params, "max_level", 2):
				if best == null or eng.unit_level(u) > eng.unit_level(best):
					best = u
		if best != null:
			best.ready = false

func sp_pay_boost(eng, ctx, params):
	var opts: Array = []
	var options: Array = params.get("options", [])
	for i in options.size():
		if MKEffects.can(eng, options[i], ctx):
			opts.append({"v": i, "label": MKEffects.describe(options[i])})
	choose(eng, ctx, "pay_boost", "Scegli l'effetto", opts, {"options": options, "per_mana": params.get("per_mana", {})}, "choice")

func can_pay_boost(eng, ctx, params) -> bool:
	for o in params.get("options", []):
		if MKEffects.can(eng, o, ctx):
			return true
	return false

func res_pay_boost(eng, ctx, data, v):
	var eff: Array = data.options[int(v)].duplicate()
	data["eff"] = eff
	data["paid"] = []
	_pay_boost_more(eng, ctx, data)

func _pay_boost_more(eng, ctx, data):
	var p := _p(eng, ctx)
	var opts: Array = [{"v": "", "label": "%s (nessun altro mana)" % MKEffects.describe(data.eff)}]
	for col in data.per_mana:
		if col in data.paid:
			continue
		if not MKMana.sources_for(eng, p, col).is_empty():
			opts.append({"v": col, "label": "Paga 1 mana %s: +%d" % [MKMana.color_it(col), int(data.per_mana[col])]})
	if opts.size() == 1:
		MKEffects.push(eng, [data.eff])
		return
	data["always_ask"] = true
	choose(eng, ctx, "pay_boost_mana", "Vuoi pagare mana per aumentare l'effetto?", opts, data, "mana")

func res_pay_boost_mana(eng, ctx, data, v):
	if str(v) == "":
		MKEffects.push(eng, [data.eff])
		return
	var p := _p(eng, ctx)
	var plan = MKMana.plan(eng, p, [str(v)])
	if plan != null:
		MKMana.pay(eng, p, plan, [str(v)])
		data.eff[1] = int(data.eff[1]) + int(data.per_mana[str(v)])
		data.paid.append(str(v))
	_pay_boost_more(eng, ctx, data)

func sp_plus_per_enemy(eng, ctx, params):
	var n := _pi(params, "n", 5)
	if in_combat(eng):
		var cnt := 0
		for e in eng.s.combat.enemies:
			if not e.defeated and not e.summoned:
				cnt += 1
		n += cnt * _pi(params, "per", 2)
	var op := _ps(params, "op", "attack")
	if op == "block":
		MKEffects.push(eng, [["block", n, _ps(params, "elem", "fire")]])
	else:
		MKEffects.push(eng, [["attack", n, _ps(params, "elem", "fire"), "melee"]])

func can_plus_per_enemy(eng, ctx, params) -> bool:
	return phase(eng) == ("block" if _ps(params, "op", "attack") == "block" else "attack")

func sp_polarization(eng, ctx, params):
	var p := _p(eng, ctx)
	var opp := {"red": "blue", "blue": "red", "green": "white", "white": "green", "gold": "black", "black": "gold"}
	var opts: Array = []
	var pl: Dictionary = eng.P(p)
	for i in pl.tokens.size():
		opts.append({"v": "token:%d" % i, "label": "Gettone %s → %s" % [MKMana.color_it(pl.tokens[i]), MKMana.color_it(opp[pl.tokens[i]])]})
	for c in MKMana.BASIC:
		if int(pl.crystals[c]) > 0:
			opts.append({"v": "crystal:" + c, "label": "Cristallo %s → gettone %s" % [MKMana.color_it(c), MKMana.color_it(opp[c])]})
	if MKMana.dice_left(eng, p) > 0:
		for j in eng.s.source.size():
			var d: Dictionary = eng.s.source[j]
			if int(d.taken_by) == -1:
				opts.append({"v": "die:%d" % j, "label": "Dado %s → gettone %s" % [MKMana.color_it(d.color), MKMana.color_it(opp[d.color])]})
	choose(eng, ctx, "polarization", "Polarizzazione: scegli il mana da convertire", opts, {"always_ask": true}, "mana")

func can_polarization(eng, ctx, params) -> bool:
	var pl: Dictionary = eng.P(_p(eng, ctx))
	return not pl.tokens.is_empty() or can_crystal_copy(eng, ctx, params) or MKMana.dice_left(eng, _p(eng, ctx)) > 0

func res_polarization(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var opp := {"red": "blue", "blue": "red", "green": "white", "white": "green", "gold": "black", "black": "gold"}
	var src := str(v)
	var col: String = MKMana.source_color(eng, p, src)
	if src.begins_with("die:"):
		var j := int(src.substr(4))
		eng.s.source[j].taken_by = p
		eng.s.turn.dice_taken = int(eng.s.turn.dice_taken) + 1
	elif src.begins_with("token:"):
		eng.P(p).tokens.remove_at(int(src.substr(6)))
	elif src.begins_with("crystal:"):
		eng.P(p).crystals[col] = int(eng.P(p).crystals[col]) - 1
	var nc: String = opp.get(col, col)
	eng.P(p).tokens.append(nc)
	if nc == "black":
		add_mod(eng, ctx, "black_ok")
	elif nc == "gold":
		add_mod(eng, ctx, "gold_ok")
	eng.add_log("mana", "%s polarizza il mana: %s → %s" % [eng.pname(p), MKMana.color_it(col), MKMana.color_it(nc)], {"p": p})

func sp_ready_all_units(eng, ctx, params):
	for u in eng.P(_p(eng, ctx)).units:
		u.ready = true
	eng.add_log("unit", "Tutte le unità sono pronte", {"p": _p(eng, ctx)})

func can_ready_all_units(eng, ctx, params) -> bool:
	if in_combat(eng):
		return false
	for u in eng.P(_p(eng, ctx)).units:
		if not u.ready:
			return true
	return false

func sp_ready_unit_heal(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for u in eng.P(p).units:
		if not u.ready or u.wounded:
			opts.append({"v": int(u.uid), "label": eng.unit_name(u)})
	choose(eng, ctx, "ready_unit_heal", "Scegli l'unità da preparare e guarire", opts, {}, "unit")

func can_ready_unit_heal(eng, ctx, params) -> bool:
	for u in eng.P(_p(eng, ctx)).units:
		if not u.ready or (u.wounded and not in_combat(eng)):
			return true
	return false

func res_ready_unit_heal(eng, ctx, data, v):
	var u = eng.find_unit(_p(eng, ctx), v)
	u.ready = true
	u.wounded = false
	u.wounds = 0
	eng.add_log("unit", "%s è pronta e guarita" % eng.unit_name(u), {"p": _p(eng, ctx)})

func sp_ready_unit_levels(eng, ctx, params):
	var p := _p(eng, ctx)
	var lv := _pi(params, "levels", 3)
	if eng.hex(eng.P(p).pos).get("t", "") == _ps(params, "terrain", "forest"):
		lv = _pi(params, "terrain_levels", lv)
	_ready_levels_ask(eng, ctx, lv)

func _ready_levels_ask(eng, ctx, left: int):
	var p := _p(eng, ctx)
	var opts: Array = []
	for u in eng.P(p).units:
		if not u.ready and eng.unit_level(u) <= left:
			opts.append({"v": int(u.uid), "label": "Prepara " + eng.unit_name(u)})
	if opts.is_empty():
		return
	opts.push_front({"v": -1, "label": "Basta così"})
	choose(eng, ctx, "ready_unit_levels", "Scegli le unità da preparare (livelli rimasti: %d)" % left, opts, {"left": left, "always_ask": true}, "unit")

func res_ready_unit_levels(eng, ctx, data, v):
	if int(v) == -1:
		return
	var u = eng.find_unit(_p(eng, ctx), v)
	u.ready = true
	_ready_levels_ask(eng, ctx, int(data.left) - eng.unit_level(u))

func sp_recruit_free_from_offer(eng, ctx, params):
	var opts: Array = []
	for id in eng.s.offers.units:
		opts.append({"v": id, "label": str(MKDB.units.get(id, {}).get("name_it", id))})
	choose(eng, ctx, "recruit_free", "Scegli l'unità da reclutare gratis", opts, {}, "offer")

func can_recruit_free_from_offer(eng, ctx, params) -> bool:
	return not eng.s.offers.units.is_empty() and not in_combat(eng)

func res_recruit_free(eng, ctx, data, v):
	var p := _p(eng, ctx)
	if eng.command_free(p) <= 0:
		var opts: Array = []
		for u in eng.P(p).units:
			opts.append({"v": int(u.uid), "label": "Congeda " + eng.unit_name(u)})
		opts.append({"v": -1, "label": "Rinuncia"})
		choose(eng, ctx, "recruit_free_disband", "Comando pieno: congeda un'unità", opts, {"id": str(v), "always_ask": true}, "unit")
		return
	eng.s.offers.units.erase(str(v))
	MKSites.gain_unit(eng, p, str(v))

func res_recruit_free_disband(eng, ctx, data, v):
	if int(v) == -1:
		return
	var p := _p(eng, ctx)
	eng.remove_unit(p, eng.find_unit(p, v))
	eng.s.offers.units.erase(str(data.id))
	MKSites.gain_unit(eng, p, str(data.id))

func sp_ring_powered(eng, ctx, params):
	var p := _p(eng, ctx)
	var col := _ps(params, "color", "red")
	for i in 4:
		eng.gain_token(p, col)
	eng.gain_token(p, "black")
	eng.gain_token(p, "black")
	add_mod(eng, ctx, "black_ok")
	add_mod(eng, ctx, "ring_powered", {"color": col})

func sp_shield_on_block(eng, ctx, params):
	add_mod(eng, ctx, "shield_on_block", {"attack": _pi(params, "attack", 0), "elem": _ps(params, "elem", "fire"),
		"destroy": params.get("destroy", false) if params is Dictionary else false, "immune": _ps(params, "immune", "fire")})

func sp_sideways_bonus(eng, ctx, params):
	var d := {"base": _pi(params, "base", 2)}
	if params is Dictionary:
		for k in ["aa_spell_artifact", "no_source"]:
			if params.has(k):
				d[k] = int(params[k])
	add_mod(eng, ctx, "sideways_bonus", d)

func sp_sideways_mana_boost(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for c in MKMana.BASIC:
		var srcs: Array = MKMana.sources_for(eng, p, c)
		if not srcs.is_empty():
			opts.append({"v": c, "label": "Paga mana " + MKMana.color_it(c)})
	choose(eng, ctx, "sideways_mana_boost", "Potere universale: scegli il mana", opts, {"base": _pi(params, "base", 3), "same": _pi(params, "same_color", 4)}, "mana")

func can_sideways_mana_boost(eng, ctx, params) -> bool:
	var p := _p(eng, ctx)
	for c in MKMana.BASIC:
		if not MKMana.sources_for(eng, p, c).is_empty():
			return true
	return false

func res_sideways_mana_boost(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var plan = MKMana.plan(eng, p, [str(v)])
	if plan == null:
		return
	MKMana.pay(eng, p, plan, [str(v)])
	add_mod(eng, ctx, "sideways_mana_boost", {"base": data.base, "same_color": data.same, "color": str(v)})

func sp_source_freeze(eng, ctx, params):
	var opts: Array = []
	for i in eng.s.source.size():
		var d: Dictionary = eng.s.source[i]
		if int(d.taken_by) == -1 and d.color in MKMana.BASIC:
			opts.append({"v": i, "label": "Dado " + MKMana.color_it(d.color)})
	choose(eng, ctx, "source_freeze", "Congelare la Riserva: scegli un dado", opts, {}, "die")

func can_source_freeze(eng, ctx, params) -> bool:
	return can_crystal_from_source_die(eng, ctx, params)

func res_source_freeze(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var d: Dictionary = eng.s.source[int(v)]
	eng.gain_crystal(p, d.color)
	d.taken_by = -2
	eng.P(p)["frozen_die"] = int(v)

func sp_source_opening(eng, ctx, params):
	var opts: Array = [{"v": -1, "label": "Nessun dado"}]
	for i in eng.s.source.size():
		var d: Dictionary = eng.s.source[i]
		if int(d.taken_by) == -1:
			opts.append({"v": i, "label": "Rilancia il dado " + MKMana.color_it(d.color)})
	choose(eng, ctx, "source_opening", "Apertura della Riserva: rilancia un dado", opts, {"always_ask": true}, "die")

func res_source_opening(eng, ctx, data, v):
	if int(v) >= 0:
		eng.s.source[int(v)].color = eng.DIE_COLORS[MKRng.rand_int(eng.s, 6)]

func sp_space_bending(eng, ctx, params):
	add_mod(eng, ctx, "space_bending")
	add_mod(eng, ctx, "no_provoke")

func sp_time_bending(eng, ctx, params):
	add_mod(eng, ctx, "time_bending")

func can_time_bending(eng, ctx, params) -> bool:
	return str(ctx.get("src", "")).find("#") >= 0 and not eng.s.turn.get("extra_turn", false)

func sp_strip(eng, ctx, params):
	var fort = params.get("fort", false) if params is Dictionary else false
	var resist = params.get("resist", false) if params is Dictionary else false
	var data := {"fort": fort, "resist": resist}
	if not in_combat(eng):
		if str(fort) == "site":
			add_mod(eng, ctx, "pre_combat", {"site_fort": true})
		return
	if _ps(params, "targets", "one") == "all":
		for e in enemy_targets(eng, {}):
			_strip(e, data)
		eng.add_log("info", "I nemici perdono fortificazioni/resistenze")
		return
	choose(eng, ctx, "strip", "Scegli il nemico", _enemy_opts(enemy_targets(eng, {})), data, "enemy")

func can_strip(eng, ctx, params) -> bool:
	if not in_combat(eng):
		return params is Dictionary and str(params.get("fort", "")) == "site" and eng.s.turn.get("player", -1) == _p(eng, ctx)
	return not enemy_targets(eng, {}).is_empty()

static func _strip(e: Dictionary, data: Dictionary) -> void:
	var fort = data.get("fort", false)
	if str(fort) == "site":
		e["site_fort_lost"] = true
	elif fort == true:
		e["site_fort_lost"] = true
		e["self_fort_lost"] = true
	var res = data.get("resist", false)
	if not e.has("lost_resist"):
		e["lost_resist"] = []
	if res is bool and res:
		for r in ["phys", "fire", "ice"]:
			e.lost_resist.append(r)
	elif res is Array:
		for r in res:
			e.lost_resist.append(str(r))

func res_strip(eng, ctx, data, v):
	var e = MKCombat.entry(eng, str(v))
	_strip(e, data)
	eng.add_log("info", "%s perde fortificazioni/resistenze" % e.name)

func sp_throw_away_turn_wounds(eng, ctx, params):
	add_mod(eng, ctx, "throw_away_turn_wounds")

func sp_underground_travel(eng, ctx, params):
	var p := _p(eng, ctx)
	var rng := _pi(params, "range", 3)
	var attack: bool = params.get("attack", false) if params is Dictionary else false
	var start: String = eng.P(p).pos
	var dist := {start: 0}
	var frontier: Array = [start]
	var opts: Array = []
	while not frontier.is_empty():
		var cur: String = frontier.pop_front()
		if int(dist[cur]) >= rng:
			continue
		for nk in MKHex.neighbors(cur):
			var h: Dictionary = eng.hex(nk)
			if h.is_empty() or dist.has(nk) or h.t in ["swamp", "lake", "ocean"]:
				continue
			dist[nk] = int(dist[cur]) + 1
			frontier.append(nk)
	for k in dist:
		if k == start:
			continue
		var h2: Dictionary = eng.hex(k)
		if attack:
			if h2.site in eng.FORTIFIED_SITES and not eng._is_safe_fortified(p, k):
				opts.append({"v": k, "label": "Assalta %s in %s" % [eng._hex_label(k), k]})
		elif eng._is_safe(p, k) and not (h2.rampage and not h2.enemies.is_empty()) and h2.t != "mountain":
			opts.append({"v": k, "label": "Viaggia in %s (%s)" % [k, eng._hex_label(k)]})
	opts.sort_custom(func(a, b): return str(a.v) < str(b.v))
	choose(eng, ctx, "underground_travel", "Viaggio sotterraneo: scegli la destinazione", opts, {"attack": attack}, "hex")

func can_underground_travel(eng, ctx, params) -> bool:
	return eng.can_still_move(_p(eng, ctx))

func res_underground_travel(eng, ctx, data, v):
	var p := _p(eng, ctx)
	if data.get("attack", false):
		add_mod(eng, ctx, "pre_combat", {"site_fort": true})
		eng.teleport(p, str(v), true, true)
	else:
		eng.teleport(p, str(v), true)

func sp_unit_activation_bonus(eng, ctx, params):
	add_mod(eng, ctx, "unit_activation_bonus", {"block": _pi(params, "block", 3), "attack": _pi(params, "attack", 2), "ranged": _pi(params, "ranged", 1)})

func can_unit_activation_bonus(eng, ctx, params) -> bool:
	return not eng.P(_p(eng, ctx)).units.is_empty()

func sp_units_all_resist(eng, ctx, params):
	add_mod(eng, ctx, "units_all_resist")

func sp_use_offer_unit(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for id in eng.s.offers.units:
		var ud: Dictionary = MKDB.units.get(id, {})
		var abs: Array = ud.get("abilities", [])
		for i in abs.size():
			var ab: Dictionary = abs[i]
			if ab.get("effect", []).is_empty():
				continue
			var mana := str(ab.get("mana", ""))
			if mana != "" and MKMana.plan(eng, p, [mana]) == null:
				continue
			if not MKEffects.any_can(eng, ab.effect, {"p": p, "kind": "unit", "src": "offer"}):
				continue
			opts.append({"v": "%s|%d" % [id, i], "label": "%s: %s" % [str(ud.get("name_it", id)), str(ab.get("text_it", MKEffects.describe_list(ab.effect)))]})
	choose(eng, ctx, "use_offer_unit", "Chiamata alle armi: scegli l'abilità", opts, {}, "unit")

func can_use_offer_unit(eng, ctx, params) -> bool:
	return not eng.s.offers.units.is_empty()

func res_use_offer_unit(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var parts := str(v).split("|")
	var ab: Dictionary = MKDB.units[parts[0]].abilities[int(parts[1])]
	var mana := str(ab.get("mana", ""))
	if mana != "":
		var plan = MKMana.plan(eng, p, [mana])
		if plan == null:
			return
		MKMana.pay(eng, p, plan, [mana])
	MKEffects.push(eng, ab.effect.duplicate(true))

func sp_weather(eng, ctx, params):
	var n := _pi(params, "self", 2)
	eng.s.turn.mods.append({"name": "terrain", "map": {"all": "-%d" % n, "min": 1}, "src": ctx.get("src", "")})

func can_weather(eng, ctx, params) -> bool:
	return eng.can_still_move(_p(eng, ctx))

func sp_wings_of_wind(eng, ctx, params):
	var p := _p(eng, ctx)
	var mx := mini(_pi(params, "max", 5), int(eng.s.turn.pool.move))
	var opts: Array = []
	var pos: String = eng.P(p).pos
	for k in eng.s.map.hex:
		var d := MKHex.distance(pos, k)
		if d < 1 or d > mx:
			continue
		var h: Dictionary = eng.hex(k)
		if not eng._is_safe(p, k) or (h.rampage and not h.enemies.is_empty()):
			continue
		opts.append({"v": k, "label": "Vola in %s (%s), %d Movimento" % [k, eng._hex_label(k), d]})
	opts.sort_custom(func(a, b): return str(a.v) < str(b.v))
	choose(eng, ctx, "wings_of_wind", "Ali del vento: scegli la destinazione", opts, {}, "hex")

func can_wings_of_wind(eng, ctx, params) -> bool:
	return eng.can_still_move(_p(eng, ctx)) and int(eng.s.turn.pool.move) >= 1

func res_wings_of_wind(eng, ctx, data, v):
	var p := _p(eng, ctx)
	eng.s.turn.pool.move = int(eng.s.turn.pool.move) - MKHex.distance(eng.P(p).pos, str(v))
	eng.teleport(p, str(v), true)

func sp_wound_self_unit(eng, ctx, params):
	var p := _p(eng, ctx)
	var u = eng.find_unit(p, ctx.get("uid", -1))
	if u != null:
		u.wounded = true
		u.wounds = maxi(1, int(u.get("wounds", 0)))
		eng.add_log("unit_wound", "%s viene ferita" % eng.unit_name(u), {"p": p, "uid": u.uid})

func sp_wound_sideways(eng, ctx, params):
	add_mod(eng, ctx, "wound_sideways", {"bonus": _pi(params, "bonus", 2)})

# ======================================================================
# Expansion content (Lost Legion / Krang / Braevalar …) — subset
# ======================================================================
func sp_units_attack_bonus(eng, ctx, params):
	add_mod(eng, ctx, "attack_bonus", {"n": _pi(params, "n", 1), "src_kind": "unit", "except_uid": int(ctx.get("uid", -1))})

func sp_rep_if_interaction(eng, ctx, params):
	add_mod(eng, ctx, "interaction_bonus", {"fame": 0, "rep": _pi(params, "n", 1)})

# unit rules (checked by the engine through the unit definition)
func sp_unit_rep_recruit_mult(eng, ctx, params): pass
func sp_unit_damage_cost(eng, ctx, params): pass
func sp_unit_assault_cost(eng, ctx, params): pass
func sp_unit_multi_ability(eng, ctx, params): pass

static func unit_rule(u_def: Dictionary, name: String):
	for r in u_def.get("rules", []):
		if r is Array and r.size() > 1 and r[0] == "special" and r[1] == name:
			return r[2] if r.size() > 2 else {}
	return null

func sp_heal_all_units(eng, ctx, params):
	for u in eng.P(_p(eng, ctx)).units:
		u.wounded = false
		u.wounds = 0
	eng.add_log("heal", "Tutte le unità sono guarite", {"p": _p(eng, ctx)})

func can_heal_all_units(eng, ctx, params) -> bool:
	if in_combat(eng):
		return false
	for u in eng.P(_p(eng, ctx)).units:
		if u.wounded:
			return true
	return false

func sp_enemy_attack_reduce_all(eng, ctx, params):
	choose(eng, ctx, "enemy_attack_reduce_all", "Scegli il nemico", _enemy_opts(enemy_targets(eng, {"need_attack": true})), {"n": _pi(params, "n", 1)}, "enemy")

func can_enemy_attack_reduce_all(eng, ctx, params) -> bool:
	return phase(eng) in ["ranged", "block"] and not enemy_targets(eng, {"need_attack": true}).is_empty()

func res_enemy_attack_reduce_all(eng, ctx, data, v):
	var e = MKCombat.entry(eng, str(v))
	e["attack_mod"] = int(e.get("attack_mod", 0)) - int(data.n)

func sp_destroy_if_blocked(eng, ctx, params):
	choose(eng, ctx, "destroy_if_blocked", "Scegli il nemico", _enemy_opts(enemy_targets(eng, {"immune": _ps(params, "immune", ""), "need_attack": true})), {}, "enemy")

func can_destroy_if_blocked(eng, ctx, params) -> bool:
	return phase(eng) in ["ranged", "block"] and not enemy_targets(eng, {"immune": _ps(params, "immune", ""), "need_attack": true}).is_empty()

func res_destroy_if_blocked(eng, ctx, data, v):
	var e = MKCombat.entry(eng, str(v))
	e["destroy_if_blocked"] = true

func sp_crystal_per_kill(eng, ctx, params):
	add_mod(eng, ctx, "crystal_per_kill", {"phase": phase(eng), "max": 1 if _ps(params, "scope", "attack") == "attack" else 99})

func sp_cure_bonus(eng, ctx, params):
	add_mod(eng, ctx, "draw_per_heal")
	add_mod(eng, ctx, "cure_bonus")
	for u in eng.P(_p(eng, ctx)).units:
		if u.get("healed_turn", false):
			u.ready = true

func sp_disease(eng, ctx, params):
	if not in_combat(eng):
		return
	for e in eng.s.combat.enemies:
		var bl := false
		for at in e.attacks:
			if at.blocked:
				bl = true
		if bl and not MKCombat.has_ab(e, "arcane_immunity"):
			e.armor_mod = 1 - int(e.armor)

func sp_discard_for_crystals(eng, ctx, params):
	_dfc_ask(eng, ctx, _pi(params, "max", 2))

func _dfc_ask(eng, ctx, left: int):
	var p := _p(eng, ctx)
	var opts: Array = [{"v": "", "label": "Basta così"}]
	for iid in eng.P(p).hand:
		if not eng.is_wound(iid) and iid != ctx.get("src", ""):
			opts.append({"v": iid, "label": "Scarta " + eng.card_name(iid)})
	if opts.size() > 1 and left > 0:
		choose(eng, ctx, "discard_for_crystals", "Scarta carte per ottenere cristalli", opts, {"left": left, "always_ask": true}, "card")

func res_discard_for_crystals(eng, ctx, data, v):
	if str(v) == "":
		return
	var p := _p(eng, ctx)
	var c: Dictionary = eng.card(str(v))
	eng.discard_from_hand(p, str(v))
	var cols := card_colors(c)
	if cols.is_empty():
		MKEffects.push(eng, [["crystal", "basic"]])
	else:
		eng.gain_crystal(p, str(cols[0]))
	_dfc_ask(eng, ctx, int(data.left) - 1)

func sp_explore_distance(eng, ctx, params):
	add_mod(eng, ctx, "explore_distance", {"n": _pi(params, "n", 2)})

func sp_explore_discount(eng, ctx, params):
	var p := _p(eng, ctx)
	if ctx.get("kind", "") == "skill_passive":
		eng.P(p)["explore_discount"] = int(eng.P(p).get("explore_discount", 0)) + _pi(params, "n", 1)
	else:
		add_mod(eng, ctx, "explore_discount", {"n": _pi(params, "n", 1)})

func sp_scout_peek(eng, ctx, params):
	var p := _p(eng, ctx)
	var eids: Array = []
	for k in eng.s.map.hex:
		if MKHex.distance(eng.P(p).pos, k) <= _pi(params, "range", 3):
			for eid in eng.s.map.hex[k].enemies:
				if not eng.s.enemies[eid].face_up:
					eng.s.enemies[eid].face_up = true
					eids.append(eid)
					eng.add_log("reveal_enemy", "Rivelato: %s" % eng.enemy_name(eid), {"eid": eid, "hex": k})
	add_mod(eng, ctx, "scout_fame", {"eids": eids, "fame": _pi(params, "fame", 1)})

func sp_on_her_own(eng, ctx, params):
	var n := 1 if int(eng.s.turn.get("recruited", 0)) > 0 else 3
	MKEffects.push(eng, [["influence", n]])

func sp_taunt(eng, ctx, params):
	var opts: Array = []
	for e in enemy_targets(eng, {"need_attack": true}):
		opts.append({"v": e.eid + "|down", "label": "%s: attacco -1" % e.name})
		opts.append({"v": e.eid + "|up", "label": "%s: attacco +2, Armatura -2" % e.name})
	choose(eng, ctx, "taunt", "Provocazione", opts, {}, "enemy")

func can_taunt(eng, ctx, params) -> bool:
	return phase(eng) == "block" and not enemy_targets(eng, {"need_attack": true}).is_empty()

func res_taunt(eng, ctx, data, v):
	var parts := str(v).split("|")
	var e = MKCombat.entry(eng, parts[0])
	if parts[1] == "down":
		e["attack_mod"] = int(e.get("attack_mod", 0)) - 1
	else:
		e["attack_mod"] = int(e.get("attack_mod", 0)) + 2
		e.armor_mod = int(e.get("armor_mod", 0)) - 2

func sp_know_your_prey(eng, ctx, params):
	var opts: Array = []
	for e in enemy_targets(eng, {}):
		for a in e.abilities:
			if a != "arcane_immunity":
				opts.append({"v": e.eid + "|ab|" + a, "label": "%s: ignora %s" % [e.name, a]})
		for r in e.resist:
			opts.append({"v": e.eid + "|res|" + r, "label": "%s: ignora la resistenza %s" % [e.name, r]})
		for i in e.attacks.size():
			if MKCombat.attack_elem(e, i) != "phys":
				opts.append({"v": e.eid + "|el|%d" % i, "label": "%s: attacco fisico" % e.name})
	choose(eng, ctx, "know_your_prey", "Conosci la tua preda", opts, {}, "enemy")

func can_know_your_prey(eng, ctx, params) -> bool:
	return in_combat(eng) and not enemy_targets(eng, {}).is_empty()

func res_know_your_prey(eng, ctx, data, v):
	var parts := str(v).split("|")
	var e = MKCombat.entry(eng, parts[0])
	match parts[1]:
		"ab":
			if not e.has("lost"):
				e["lost"] = []
			e.lost.append(parts[2])
			if parts[2] == "fortified":
				e["self_fort_lost"] = true
		"res":
			if not e.has("lost_resist"):
				e["lost_resist"] = []
			e.lost_resist.append(parts[2])
		"el":
			e.attacks[int(parts[2])]["elem_override"] = "phys"

func sp_deadly_aim(eng, ctx, params):
	add_mod(eng, ctx, "deadly_aim")

func sp_hawk_eyes(eng, ctx, params):
	var p := _p(eng, ctx)
	if eng.s.day:
		for k in eng.s.map.hex:
			if MKHex.distance(eng.P(p).pos, k) <= 2 and eng.s.map.hex[k].site in eng.FORTIFIED_SITES:
				for eid in eng.s.map.hex[k].enemies:
					eng.s.enemies[eid].face_up = true
	else:
		add_mod(eng, ctx, "explore_discount", {"n": 1})

func sp_dueling(eng, ctx, params):
	MKEffects.push(eng, [["block", 1]])
	if not eng.s.combat.has("delayed"):
		eng.s.combat["delayed"] = []
	eng.s.combat.delayed.append({"n": 1, "elem": "phys"})
	add_mod(eng, ctx, "fame_per_kill", {"n": 1, "once": true})

func can_dueling(eng, ctx, params) -> bool:
	return phase(eng) == "block"

func sp_regenerate(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for x in MKEffects._mana_options(eng, p, MKMana.sources_for(eng, p, "any"), "any"):
		opts.append(x)
	choose(eng, ctx, "regenerate", "Rigenerazione: paga un mana", opts, {"color": _ps(params, "color", "")}, "mana")

func can_regenerate(eng, ctx, params) -> bool:
	var p := _p(eng, ctx)
	return can_discard_wound_draw(eng, ctx, params) and not MKMana.sources_for(eng, p, "any").is_empty() and not in_combat(eng)

func res_regenerate(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var paid: Array = MKMana.pay(eng, p, [str(v)], ["any"])
	_throw_wounds(eng, p, 1)
	var lowest: bool = eng.s.players.size() > 1
	for i in eng.s.players.size():
		if i != p and int(eng.P(i).fame) <= int(eng.P(p).fame):
			lowest = false
	if (not paid.is_empty() and paid[0] == data.color) or lowest:
		eng.draw(p, 1)

func sp_terrain_all(eng, ctx, params):
	var c := _pi(params, "cost", 2)
	var mp := {}
	for t in ["plains", "hills", "forest", "desert", "wasteland", "swamp", "lake"]:
		mp[t] = c
	for b in (params.get("blocked", []) if params is Dictionary else []):
		mp[str(b)] = 999
	eng.s.turn.mods.append({"name": "terrain", "map": mp, "src": ctx.get("src", "")})

func sp_veil_of_mist(eng, ctx, params):
	add_mod(eng, ctx, "units_all_resist")
	add_mod(eng, ctx, "ignore_first_wound")

func sp_damage_reduction(eng, ctx, params):
	add_mod(eng, ctx, "damage_reduction", {"match": params.get("match", []) if params is Dictionary else [], "n_match": _pi(params, "n_match", 2), "n_other": _pi(params, "n_other", 1)})

func sp_delayed_effect(eng, ctx, params):
	var eff = params.get("effect", []) if params is Dictionary else []
	if eff is Array and not eff.is_empty():
		MKEffects.push(eng, [eff])

func sp_secret_ways(eng, ctx, params):
	eng.s.turn.mods.append({"name": "terrain", "map": {"mountain": 5, "safe": ["mountain"]}, "src": ctx.get("src", "")})
	MKEffects.push(eng, [["choice", [[], [["pay_mana", "blue", [["terrain", {"lake": 2, "safe": ["lake"]}]]]]]]])

func can_secret_ways(eng, ctx, params) -> bool:
	return eng.can_still_move(_p(eng, ctx))

func sp_beguile(eng, ctx, params):
	var p := _p(eng, ctx)
	var h: Dictionary = eng.hex(eng.P(p).pos)
	var n := _pi(params, "base", 3)
	if h.get("site", "") in eng.FORTIFIED_SITES:
		n = _pi(params, "fortified", n)
	elif h.get("site", "") == "glade":
		n = _pi(params, "glade", n)
	MKEffects.push(eng, [["influence", n]])

func sp_ignore_reputation(eng, ctx, params):
	add_mod(eng, ctx, "ignore_reputation")

func sp_card_play_bonus(eng, ctx, params):
	add_mod(eng, ctx, "card_play_bonus", {"n": _pi(params, "n", 1)})

func sp_spectral_guise(eng, ctx, params):
	add_mod(eng, ctx, "ignore_reputation")
	MKEffects.push(eng, [["choice", [[["influence", 10]], [["attack", 9]]]], ["rep", -2]])

func sp_charm_bonus(eng, ctx, params):
	MKEffects.push(eng, [["choice", [[["crystal", "basic"]], [["special", "recruit_discount", {"n": 3, "units": "1"}]]]]])

func sp_battle_frenzy(eng, ctx, params):
	MKEffects.push(eng, [["choice", [[["attack", _pi(params, "n", 2)]], [["attack", _pi(params, "flipped", 4)]]]]])

func can_battle_frenzy(eng, ctx, params) -> bool:
	return phase(eng) == "attack"

func sp_curse(eng, ctx, params):
	var opts: Array = []
	for e in enemy_targets(eng, {}):
		if phase(eng) == "ranged" and MKCombat.is_fortified(e):
			continue
		opts.append({"v": e.eid + "|armor", "label": "%s: Armatura -1" % e.name})
		if not e.attacks.is_empty():
			opts.append({"v": e.eid + "|attack", "label": "%s: attacco -1" % e.name})
	choose(eng, ctx, "curse", "Maledizione", opts, {}, "enemy")

func can_curse(eng, ctx, params) -> bool:
	return in_combat(eng) and not enemy_targets(eng, {}).is_empty()

func res_curse(eng, ctx, data, v):
	var parts := str(v).split("|")
	var e = MKCombat.entry(eng, parts[0])
	if parts[1] == "armor":
		e.armor_mod = int(e.get("armor_mod", 0)) - 1
	else:
		e["attack_mod"] = int(e.get("attack_mod", 0)) - 1

func sp_possess(eng, ctx, params):
	choose(eng, ctx, "possess", "Possedere: scegli il nemico", _enemy_opts(enemy_targets(eng, {"need_attack": true})), {}, "enemy")

func can_possess(eng, ctx, params) -> bool:
	return phase(eng) in ["ranged", "block"] and not enemy_targets(eng, {"need_attack": true}).is_empty()

func res_possess(eng, ctx, data, v):
	var e = MKCombat.entry(eng, str(v))
	var c: Dictionary = eng.s.combat
	for i in e.attacks.size():
		var n := MKCombat.attack_value(eng, e, i)
		if n > 0:
			if not c.has("delayed"):
				c["delayed"] = []
			c.delayed.append({"n": n, "elem": MKCombat.attack_elem(e, i)})
	e["no_attack"] = true

func sp_multi_block(eng, ctx, params):
	eng.s.turn["multi_block"] = {"n": _pi(params, "n", 3), "elem": _ps(params, "elem", "phys"), "left": _pi(params, "count", 2)}

func can_multi_block(eng, ctx, params) -> bool:
	return phase(eng) == "block"

func sp_frenzy_unit(eng, ctx, params):
	var p := _p(eng, ctx)
	var opts: Array = []
	for u in eng.P(p).units:
		if not u.wounded:
			opts.append({"v": int(u.uid), "label": eng.unit_name(u)})
	choose(eng, ctx, "frenzy_unit", "Scegli l'unità", opts, {"bonus": _pi(params, "bonus", 2)}, "unit")

func res_frenzy_unit(eng, ctx, data, v):
	var u = eng.find_unit(_p(eng, ctx), v)
	u.ready = true
	add_mod(eng, ctx, "attack_bonus", {"n": int(data.bonus), "src_kind": "unit", "only_uid": int(v)})

func sp_tome_of_all_spells(eng, ctx, params):
	var p := _p(eng, ctx)
	var powered: bool = params.get("powered", false) if params is Dictionary else false
	var opts: Array = []
	var seen := {}
	for iid in eng.P(p).hand:
		if iid == ctx.get("src", "") or eng.is_wound(iid) or seen.has(eng.card_id(iid)):
			continue
		seen[eng.card_id(iid)] = true
		opts.append({"v": iid, "label": "Scarta " + eng.card_name(iid)})
	choose(eng, ctx, "tome", "Scegli la carta da scartare", opts, {"powered": powered}, "card")

func can_tome_of_all_spells(eng, ctx, params) -> bool:
	return not eng.s.offers.spells.is_empty()

func res_tome(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var c: Dictionary = eng.card(str(v))
	eng.discard_from_hand(p, str(v))
	var mode := "powered" if data.powered else "basic"
	var opts: Array = []
	for sid in eng.s.offers.spells:
		var sc: Dictionary = MKDB.card(sid)
		if not str(sc.get("color", "")) in card_colors(c):
			continue
		if MKEffects.any_can(eng, sc.get(mode, []), ctx):
			opts.append({"v": sid, "label": "Usa %s" % MKSites._cname(sid)})
	choose(eng, ctx, "tome_cast", "Scegli l'Incantesimo dell'offerta", opts, {"mode": mode}, "offer")

func res_tome_cast(eng, ctx, data, v):
	MKEffects.push(eng, MKDB.card(str(v)).get(data.mode, []).duplicate(true))

func sp_use_offer_card(eng, ctx, params):
	var p := _p(eng, ctx)
	var kind := "spells" if _ps(params, "offer", "aa") in ["spells", "spell"] else "aa"
	var mode := _ps(params, "mode", "basic")
	var free: bool = params.get("free", true) if params is Dictionary else true
	var opts: Array = []
	for id in _offer_matches(eng, ctx, params):
		var c: Dictionary = MKDB.card(id)
		if not free and MKMana.plan(eng, p, eng.card_mana_needs(c, mode)) == null:
			continue
		if MKEffects.any_can(eng, c.get(mode, []), ctx):
			opts.append({"v": id, "label": "Usa " + MKSites._cname(id)})
	choose(eng, ctx, "use_offer_card", "Scegli la carta dell'offerta", opts, {"mode": mode, "free": free, "times": _pi(params, "times", 1)}, "offer")

func res_use_offer_card(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var c: Dictionary = MKDB.card(str(v))
	if not data.free:
		var needs: Array = eng.card_mana_needs(c, data.mode)
		var plan = MKMana.plan(eng, p, needs)
		if plan == null:
			return
		MKMana.pay(eng, p, plan, needs)
	var effs: Array = []
	for i in int(data.times):
		effs.append(c.get(data.mode, []).duplicate(true))
	MKEffects.push(eng, effs)

func sp_sacrifice(eng, ctx, params):
	var opts: Array = []
	for a in ["green", "white"]:
		for b in ["red", "blue"]:
			opts.append({"v": a + "|" + b, "label": "%s + %s" % [MKMana.color_it(a), MKMana.color_it(b)]})
	choose(eng, ctx, "sacrifice", "Sacrificio: scegli i colori", opts, {}, "color")

func can_sacrifice(eng, ctx, params) -> bool:
	return phase(eng) in ["ranged", "attack"]

func res_sacrifice(eng, ctx, data, v):
	var p := _p(eng, ctx)
	var parts := str(v).split("|")
	var pl: Dictionary = eng.P(p)
	var pairs := mini(int(pl.crystals[parts[0]]), int(pl.crystals[parts[1]]))
	if pairs <= 0:
		return
	var el := "fire" if parts[1] == "red" else "ice"
	var effs: Array = []
	for i in pairs:
		if parts[0] == "green":
			effs.append(["attack", 4, el, "siege"])
		else:
			effs.append(["attack", 6, el, "ranged"])
	pl.crystals[parts[0]] = int(pl.crystals[parts[0]]) - pairs
	pl.crystals[parts[1]] = int(pl.crystals[parts[1]]) - pairs
	for i in pairs:
		pl.tokens.append(parts[0])
		pl.tokens.append(parts[1])
	MKEffects.push(eng, effs)

func sp_safe_move(eng, ctx, params):
	var p := _p(eng, ctx)
	var n := _pi(params, "spaces", 1)
	var opts: Array = [{"v": "", "label": "Resta qui"}]
	var pos: String = eng.P(p).pos
	for k in eng.s.map.hex:
		var d := MKHex.distance(pos, k)
		if d < 1 or d > n:
			continue
		var h: Dictionary = eng.hex(k)
		if not eng._is_safe(p, k) or (h.rampage and not h.enemies.is_empty()):
			continue
		opts.append({"v": k, "label": "Spostati in %s (%s)" % [k, eng._hex_label(k)]})
	choose(eng, ctx, "safe_move", "Scegli dove spostarti", opts, {"always_ask": true}, "hex")

func res_safe_move(eng, ctx, data, v):
	if str(v) != "":
		eng.teleport(_p(eng, ctx), str(v), true)

func sp_stout_resolve(eng, ctx, params):
	var opts: Array = []
	var n := _pi(params, "n", 2)
	for op in ["move", "influence", "attack", "block"]:
		if MKEffects.can(eng, [op, n], ctx):
			opts.append({"v": op, "label": MKEffects.describe([op, n])})
	choose(eng, ctx, "stout_resolve", "Scegli l'effetto", opts, {"n": n, "per": _pi(params, "per", 1), "left": _pi(params, "max_cards", 1),
		"wounds_left": _pi(params, "max_wounds", 1), "wounds_only": params.get("wounds_only", false) if params is Dictionary else false}, "choice")

func can_stout_resolve(eng, ctx, params) -> bool:
	for op in ["move", "influence", "attack", "block"]:
		if MKEffects.can(eng, [op, 1], ctx):
			return true
	return false

func res_stout_resolve(eng, ctx, data, v):
	data["op"] = str(v)
	_stout_more(eng, ctx, data)

func _stout_more(eng, ctx, data):
	var p := _p(eng, ctx)
	var opts: Array = [{"v": "", "label": "%s (nessuno scarto in più)" % MKEffects.describe([data.op, int(data.n)])}]
	if int(data.left) > 0:
		var seen := {}
		for iid in eng.P(p).hand:
			var w: bool = eng.is_wound(iid)
			if data.wounds_only and not w:
				continue
			if w and int(data.wounds_left) <= 0:
				continue
			if seen.has(eng.card_id(iid)) or iid == ctx.get("src", ""):
				continue
			seen[eng.card_id(iid)] = true
			opts.append({"v": iid, "label": "Scarta %s: +%d" % [eng.card_name(iid), int(data.per)]})
	if opts.size() == 1:
		MKEffects.push(eng, [[data.op, int(data.n)]])
		return
	data["always_ask"] = true
	choose(eng, ctx, "stout_more", "Vuoi scartare carte per aumentare il valore?", opts, data, "card")

func res_stout_more(eng, ctx, data, v):
	if str(v) == "":
		MKEffects.push(eng, [[data.op, int(data.n)]])
		return
	var p := _p(eng, ctx)
	if eng.is_wound(str(v)):
		data.wounds_left = int(data.wounds_left) - 1
	var pl: Dictionary = eng.P(p)
	pl.hand.erase(str(v))
	pl.discard.append(str(v))
	eng.s.turn.discarded = int(eng.s.turn.get("discarded", 0)) + 1
	data.n = int(data.n) + int(data.per)
	data.left = int(data.left) - 1
	_stout_more(eng, ctx, data)

func sp_draw_fire_unit(eng, ctx, params):
	sp_reduce_enemy_attack(eng, ctx, {"n": _pi(params, "reduce", 3)})

func can_draw_fire_unit(eng, ctx, params) -> bool:
	return can_reduce_enemy_attack(eng, ctx, params)

func sp_bow_powered(eng, ctx, params):
	var opts: Array = [{"v": "double", "label": "Raddoppia gli Attacchi a distanza"}, {"v": "siege", "label": "Gli Attacchi a distanza diventano d'Assedio"}]
	choose(eng, ctx, "bow_powered", "Arco dell'Alba Stellare", opts, {}, "choice")

func can_bow_powered(eng, ctx, params) -> bool:
	return in_combat(eng)

func res_bow_powered(eng, ctx, data, v):
	var pool: Dictionary = eng.s.turn.pool.attack
	var np := {}
	for k in pool:
		var kd: String = k.split(":")[0]
		var el: String = k.split(":")[1]
		var n := int(pool[k])
		if kd in ["ranged", "siege"]:
			if str(v) == "double":
				n *= 2
				kd = "ranged"
			else:
				kd = "siege"
		var nk := kd + ":" + el
		np[nk] = int(np.get(nk, 0)) + n
	eng.s.turn.pool.attack = np

func sp_circlet(eng, ctx, params):
	var powered: bool = params.get("powered", false) if params is Dictionary else false
	var opts: Array = []
	for id in eng.s.offers.skills:
		var sd: Dictionary = MKDB.skills.get(id, {})
		if str(sd.get("usage", "")) == "interactive" or not MKDB.skill_ok(id):
			continue
		if powered or MKEffects.any_can(eng, sd.get("effect", []), ctx):
			opts.append({"v": id, "label": MKSites._skill_label(id)})
	choose(eng, ctx, "circlet", "Scegli l'Abilità dell'offerta comune", opts, {"powered": powered}, "skill")

func can_circlet(eng, ctx, params) -> bool:
	return not eng.s.offers.skills.is_empty()

func res_circlet(eng, ctx, data, v):
	var p := _p(eng, ctx)
	if data.powered:
		eng.s.offers.skills.erase(str(v))
		MKSites.add_skill(eng, p, str(v))
		return
	var sd: Dictionary = MKDB.skills.get(str(v), {})
	var eff: Array = sd.get("effect", []).duplicate(true)
	if str(sd.get("usage", "")) == "turn":
		MKEffects.push(eng, [eff, eff.duplicate(true)])
	else:
		MKEffects.push(eng, [eff])
