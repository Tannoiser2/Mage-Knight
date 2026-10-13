class_name MKSpecialsExp
extends RefCounted
## Named specials of the expansions (Wolfhawk, Krang, Braevalar, La Legione Perduta, promo) and the
## engine hooks they need. Looked up by MKSpecials.obj(): func sp_<name>(eng, ctx, params), optional
## can_<name>, res_<name>(eng, ctx, data, v) - same conventions as specials.gd.
##
## Interactive skills: the owner's effect is applied when used; the part for the other players is kept in
## s.inter = [{id, owner, mode, ...}] until the start of the owner's next turn (it "comes back").


const CHAOS_WHEEL := ["blue", "green", "white", "red", "black", "gold"]
const CHAOS_EFF := {"blue": [["block", 3]], "green": [["move", 1]], "white": [["influence", 2]], "red": [["attack", 2]],
	"black": [["attack", 1, "cold", "ranged"]]}
const CHAOS_IT := {"blue": "blu", "green": "verde", "white": "bianco", "red": "rosso", "black": "nero", "gold": "oro"}

# ======================================================================
# Interactive skills store
# ======================================================================
static func inter_list(eng) -> Array:
	if not eng.s.has("inter") or not (eng.s.inter is Array):
		eng.s["inter"] = []
	return eng.s.inter

static func inter_get(eng, id: String) -> Variant:
	for x in eng.s.get("inter", []):
		if str(x.get("id", "")) == id:
			return x
	return null

static func inter_add(eng, entry: Dictionary) -> void:
	var l := inter_list(eng)
	for x in l.duplicate():
		if str(x.id) == str(entry.id) and int(x.owner) == int(entry.owner):
			l.erase(x)
	l.append(entry)

# ======================================================================
# Engine hooks
# ======================================================================
## Druidic Paths (basic): the cost of one space is reduced (bound to the first space where it applies).
static func space_cost(eng, hk: String, t: String, c: int) -> int:
	for m in eng.mods_named("reduce_space_cost"):
		var bound := str(m.get("hex", ""))
		if bound != "" and bound != hk:
			continue
		if str(m.get("terrain", "")) != "" and str(m.terrain) != t:
			continue
		var mn := int(m.get("min", 2))
		if c > mn:
			c = maxi(mn, c - int(m.get("n", 1)))
	return c

static func on_move_cost(eng, p: int, to: String) -> void:
	var h: Dictionary = eng.hex(to)
	if h.is_empty():
		return
	var base: int = eng.terrain_cost(h.t, to)
	for m in eng.mods_named("reduce_space_cost"):
		if str(m.get("hex", "")) == "" and base > int(m.get("min", 2)) and (str(m.get("terrain", "")) == "" or str(m.terrain) == h.t):
			m["hex"] = to
			eng.add_log("info", "Il costo di questo spazio è ridotto", {"p": p})
			break

## Savage Harvesting: after moving into a space, discard a card for a crystal of its colour.
static func after_move(eng, p: int, to: String) -> void:
	var m = MKSpecials.get_mod(eng, "crystal_on_move")
	if m == null:
		return
	if str(m.get("times", "1")) != "each" and int(m.get("used", 0)) >= int(m.get("times", 1)):
		return
	var opts: Array = [{"v": "", "label": "Nessuna carta"}]
	var seen := {}
	for iid in eng.P(p).hand:
		if eng.is_wound(iid) or seen.has(eng.card_id(iid)):
			continue
		seen[eng.card_id(iid)] = true
		var c: Dictionary = eng.card(iid)
		var cols: Array = MKSpecials.card_colors(c)
		var what := "un cristallo a scelta" if cols.is_empty() else ("un cristallo " + "/".join(cols.map(func(x): return MKMana.color_it(str(x)))))
		opts.append({"v": iid, "label": "Scarta %s: %s" % [eng.card_name(iid), what]})
	if opts.size() > 1:
		eng.ask(p, "card", "sp:harvest", "Raccolta Selvaggia: scarta una carta per un cristallo?", opts)

## Extra Move usable (sideways) outside the move phase: maze path payment, Cumbersome enemies.
static func move_ok(eng, p: int) -> bool:
	return MKSitesExp.paying(eng, p) or MKCombatExp.move_usable(eng)

## Units carrying the Banner of Command do not use a Command token; an unattached Banner of Command
## played this turn gives one extra slot for the next recruit.
static func command_bonus(eng, p: int) -> int:
	var n := 0
	var pl: Dictionary = eng.P(p)
	var bn: Dictionary = pl.get("banners", {})
	for uid in bn:
		if eng.card_id(str(bn[uid])) == "banner_of_command":
			n += 1
	if int(eng.s.turn.get("player", -1)) == p:
		for m in eng.mods_named("banner_command"):
			if not m.get("_done", false) and pl.play.has(str(m.get("src", ""))):
				n += 1
	return n

## Shapeshift: convert a fixed Move/Attack/Block effect of a basic Action card.
static func convert_op(eng, ctx: Dictionary, e: Array, bind: bool) -> Array:
	if str(ctx.get("kind", "")) != "card" or str(ctx.get("ctype", "")) != "basic" or ctx.get("_nested", false):
		return e
	var op := str(e[0])
	if not op in ["move", "attack", "block"] or e.size() < 2 or not (e[1] is int or e[1] is float):
		return e
	var src := str(ctx.get("src", ""))
	for m in eng.s.turn.get("mods", []):
		if str(m.get("name", "")) != "shapeshift" or str(m.get("from", "")) != op:
			continue
		var b := str(m.get("card", ""))
		if b != "" and b != src:
			continue
		if bind and b == "":
			m["card"] = src
		var n := int(e[1])
		var elem := "phys"
		if op == "attack" and e.size() > 2 and e[2] != null:
			elem = str(e[2])
		elif op == "block" and e.size() > 2 and e[2] != null:
			elem = str(e[2])
		match str(m.get("to", "")):
			"move":
				return ["move", n]
			"attack":
				return ["attack", n, elem, "melee"]
			"block":
				return ["block", n, elem]
	return e

static func on_combat_start(eng, p: int) -> void:
	# Howl of the Pack (coop): the next other player who fights weakens an enemy
	var x = inter_get(eng, "wolfs_howl")
	if x != null and str(x.get("mode", "")) == "coop" and int(x.owner) != p and not x.get("used", false):
		x["used"] = true
		var best = null
		for e in MKSpecials.enemy_targets(eng, {}):
			if best == null or MKCombat.armor_of(eng, e) > MKCombat.armor_of(eng, best):
				best = e
		if best != null:
			best.armor_mod = int(best.get("armor_mod", 0)) - 1
			var bi := -1
			var bv := 0
			for i in best.attacks.size():
				if MKCombat.attack_value(eng, best, i) > bv:
					bv = MKCombat.attack_value(eng, best, i)
					bi = i
			if bi >= 0:
				best.attacks[bi]["mod"] = int(best.attacks[bi].get("mod", 0)) - 1
			eng.add_log("info", "Ululato del Branco: %s Armatura -1 e attacco -1" % best.name, {"p": p})

static func on_block_phase(eng) -> void:
	# Nature's Vengeance (competitive): enemies of the other players attack +1 in the Block phase
	var p: int = int(eng.s.turn.get("player", -1))
	var x = inter_get(eng, "natures_vengeance")
	if x != null and str(x.get("mode", "")) == "competitive" and int(x.owner) != p:
		for e in eng.s.combat.enemies:
			if e.defeated:
				continue
			for at in e.attacks:
				at["mod"] = int(at.get("mod", 0)) + 1
		eng.add_log("info", "Vendetta della Natura: gli attacchi nemici aumentano di 1", {"p": p})

static func on_turn_start(eng, p: int) -> void:
	var pl: Dictionary = eng.P(p)
	# interactive skills come back to their owner
	for x in inter_list(eng).duplicate():
		if int(x.owner) != p:
			continue
		inter_list(eng).erase(x)
		if str(x.id) == "mana_suppression":
			var cols: Array = x.get("colors", [])
			if cols.is_empty():
				cols = MKMana.BASIC.duplicate()
			var opts: Array = []
			for c in cols:
				opts.append({"v": c, "label": "Cristallo " + MKMana.color_it(str(c))})
			if opts.size() == 1:
				eng.gain_crystal(p, str(opts[0].v))
			elif eng.s.pending == null:
				eng.ask(p, "color", "sp:suppress_crystal", "Soppressione del Mana: scegli il cristallo", opts)
	for sk in pl.skills:
		if sk.id == "krang_master_of_chaos":
			sk["chaos_free"] = int(sk.get("chaos_last", -9)) != int(pl.turns) - 1

static func on_round_start(eng) -> void:
	# Magic Familiars: pay a crystal to keep them (it becomes the new token) or lose them
	var q: Array = []
	for i in eng.s.players.size():
		for u in eng.P(i).units:
			if MKSpecials.unit_rule(eng.unit_def(u), "familiars_upkeep") != null:
				q.append([i, int(u.uid)])
	eng.s["familiars_q"] = q
	_familiars_next(eng)

static func _familiars_next(eng) -> void:
	var q: Array = eng.s.get("familiars_q", [])
	while not q.is_empty():
		var it: Array = q.pop_front()
		var p := int(it[0])
		var u = eng.find_unit(p, it[1])
		if u == null:
			continue
		var opts: Array = []
		for c in MKMana.BASIC:
			if int(eng.P(p).crystals.get(c, 0)) > 0:
				opts.append({"v": c, "label": "Paga un cristallo %s (nuovo segnalino)" % MKMana.color_it(c)})
		if opts.is_empty():
			eng.remove_unit(p, u)
			eng.add_log("unit_destroyed", "%s: nessun cristallo per i Famigli Magici, che se ne vanno" % eng.pname(p), {"p": p, "uid": u.uid})
			continue
		opts.append({"v": "", "label": "Lascia andare i Famigli Magici"})
		eng.ask(p, "choice", "sp:familiars_keep", "Famigli Magici: paga un cristallo per tenerli", opts, {"uid": int(u.uid)})
		return

static func recruit_check(eng, p: int, id: String) -> String:
	if MKSpecials.unit_rule(MKDB.units.get(id, {}), "familiars_upkeep") != null and MKMana.sources_for(eng, p, "basic").is_empty():
		return "Per reclutare i Famigli Magici serve un mana di un colore base"
	return ""

static func on_recruit(eng, p: int, id: String) -> void:
	var pl: Dictionary = eng.P(p)
	var u = null
	for x in pl.units:
		if str(x.id) == id:
			u = x
	if u == null:
		return
	var t: Dictionary = eng.s.turn
	if not t.has("recruited_uids"):
		t["recruited_uids"] = []
	t.recruited_uids.append(int(u.uid))
	# Banner of Command played before recruiting
	for m in eng.mods_named("banner_command"):
		if m.get("_done", false) or not pl.play.has(str(m.get("src", ""))):
			continue
		m["_done"] = true
		_attach_banner(eng, p, str(m.src), int(u.uid))
		break
	if MKSpecials.unit_rule(MKDB.units.get(id, {}), "familiars_upkeep") != null:
		var opts: Array = MKEffects._mana_options(eng, p, MKMana.sources_for(eng, p, "basic"), "basic")
		if not opts.is_empty():
			if eng.s.pending == null:
				eng.ask(p, "mana", "sp:familiar_token", "Famigli Magici: paga un mana di un colore base (diventa il loro segnalino)", opts, {"uid": int(u.uid)})

static func _attach_banner(eng, p: int, iid: String, uid: int) -> void:
	var pl: Dictionary = eng.P(p)
	if not pl.has("banners"):
		pl["banners"] = {}
	var key := str(uid)
	if pl.banners.has(key):
		pl.discard.append(pl.banners[key])
	pl.banners[key] = iid
	pl.play.erase(iid)
	eng.add_log("info", "%s assegna %s a %s" % [eng.pname(p), eng.card_name(iid), eng.unit_name_by_uid(p, uid)], {"p": p})

static func on_mana_used(eng, p: int, color: String) -> void:
	var t: Dictionary = eng.s.turn
	if int(t.get("player", -1)) != p:
		return
	if not t.has("basic_spent"):
		t["basic_spent"] = []
	t.basic_spent.append(color)
	var m = MKSpecials._open_mod(eng, "mana_enhancement")
	if m != null:
		m["_done"] = true
		_enhance(eng, p, color)

static func _enhance(eng, p: int, color: String) -> void:
	eng.gain_crystal(p, color)
	inter_add(eng, {"id": "mana_enhancement", "owner": p, "mode": "coop", "color": color, "taken": false})
	eng.add_log("info", "Potenziamento del Mana: cristallo %s (un gettone %s resta sull'abilità)" % [MKMana.color_it(color), MKMana.color_it(color)], {"p": p})

## Mana Suppression (competitive): the first basic mana another player uses costs one more of that colour.
## Interpretation: the extra mana is taken automatically from a token, then a crystal of that colour; if the
## player has neither, the extra cost is waived (the engine cannot undo a payment already made).
static func after_pay(eng, p: int, paid: Array) -> void:
	var x = inter_get(eng, "mana_suppression")
	if x == null or int(x.owner) == p:
		return
	var hit: Dictionary = x.get("hit", {})
	if hit.has(str(p)):
		return
	var col := ""
	for c in paid:
		if str(c) in MKMana.BASIC:
			col = str(c)
			break
	if col == "":
		return
	hit[str(p)] = true
	x["hit"] = hit
	if not col in x.get("colors", []):
		x.colors.append(col)
	var pl: Dictionary = eng.P(p)
	var i: int = pl.tokens.find(col)
	if i >= 0:
		pl.tokens.remove_at(i)
		eng.add_log("mana", "Soppressione del Mana: %s paga un gettone %s in più" % [eng.pname(p), MKMana.color_it(col)], {"p": p})
	elif int(pl.crystals.get(col, 0)) > 0:
		pl.crystals[col] = int(pl.crystals[col]) - 1
		eng.add_log("mana", "Soppressione del Mana: %s paga un cristallo %s in più" % [eng.pname(p), MKMana.color_it(col)], {"p": p})
	else:
		eng.add_log("mana", "Soppressione del Mana: %s non ha altro mana %s da pagare" % [eng.pname(p), MKMana.color_it(col)], {"p": p})

## Wolf's Howl (competitive): the units of the other players get -1 to all attacks and blocks.
static func adjust_unit(eng, p: int, op: String, n: int) -> int:
	var x = inter_get(eng, "wolfs_howl")
	if x != null and str(x.get("mode", "")) == "competitive" and int(x.owner) != p and op in ["attack", "block"]:
		return maxi(0, n - 1)
	return n

## Wolf's Howl (owner): one sideways card (Move/Attack/Block) is worth 4 (+1 per free Command token).
static func side_bonus(eng, p: int, side: String, iid: String, v: int, consume: bool = false) -> int:
	if side == "influence":
		return v
	var m = MKSpecials.get_mod(eng, "wolfs_howl")
	if m != null:
		if consume:
			MKSpecials.remove_mod(eng, m)
		return maxi(v, int(m.get("n", 4)))
	return v

static func on_defeat(eng, p: int, e: Dictionary) -> void:
	var t: Dictionary = eng.s.turn
	if int(t.get("player", -1)) != p or e.get("summoned", false):
		return
	if not t.has("defeated_types"):
		t["defeated_types"] = []
	t.defeated_types.append(str(e.type))

static func on_skill_gained(eng, p: int, id: String) -> void:
	if id == "krang_master_of_chaos":
		var sk = eng.find_skill(p, id)
		if sk != null and not sk.has("chaos"):
			sk["chaos"] = CHAOS_WHEEL[MKRng.rand_int(eng.s, CHAOS_WHEEL.size())]
			eng.add_log("info", "Signore del Caos: colore iniziale %s" % CHAOS_IT[sk.chaos], {"p": p})

## Krang: flipped skills that come back by resting (Battle Frenzy).
static func on_rest(eng, p: int) -> void:
	for sk in eng.P(p).skills:
		if sk.get("flipped", false) and str(sk.get("unflip", "")) == "rest":
			sk.flipped = false
			eng.add_log("skill", "%s rigira %s riposando" % [eng.pname(p), MKSites._skill_label(str(sk.id))], {"p": p})

static func on_cleanup(eng, p: int) -> void:
	var t: Dictionary = eng.s.turn
	for a in t.get("box_revealed", []):
		eng.s.decks.artifacts.append(a)
	t["box_revealed"] = []

# ======================================================================
# Special actions {t:"sp", name, ...}
# ======================================================================
static func actions(eng, p: int) -> Array:
	var out: Array = []
	var s: Dictionary = eng.s
	var t: Dictionary = s.turn
	out.append_array(MKCombatExp.cumbersome_actions(eng, p))
	out.append_array(MKSitesExp.actions(eng, p))
	var pl: Dictionary = eng.P(p)
	for sk in pl.skills:
		if sk.id == "krang_master_of_chaos" and sk.get("chaos_free", false) and not t.get("started", false) and not t.get("chaos_rot", false) and s.combat == null:
			var nx: String = CHAOS_WHEEL[(CHAOS_WHEEL.find(str(sk.get("chaos", "blue"))) + 1) % CHAOS_WHEEL.size()]
			out.append({"a": {"t": "sp", "name": "chaos_rotate"}, "label": "Signore del Caos: avanza gratis al colore %s" % CHAOS_IT[nx], "group": "skill"})
	# Krang: flipped skills that come back with green mana (Arcane Disguise) or as the turn's action (Shamanic Ritual)
	if s.combat == null and not t.get("ending", false):
		for sk in pl.skills:
			var sd: Dictionary = MKDB.skills.get(str(sk.id), {})
			if sk.get("flipped", false) and str(sk.get("unflip", "")) == "green" and not MKMana.sources_for(eng, p, "green").is_empty():
				out.append({"a": {"t": "sp", "name": "skill_unflip", "id": str(sk.id)}, "label": "Rigira %s pagando un mana verde" % MKSites._skill_label(str(sk.id)), "group": "skill"})
			elif str(sd.get("unflip", "")) == "action" and sk.used_round and MKSites._action_free(eng, p) == "":
				out.append({"a": {"t": "sp", "name": "skill_unflip", "id": str(sk.id)}, "label": "Rigira %s usando l'azione del turno" % MKSites._skill_label(str(sk.id)), "group": "skill"})
	var enh = inter_get(eng, "mana_enhancement")
	if enh != null and int(enh.owner) != p and not enh.get("taken", false):
		out.append({"a": {"t": "sp", "name": "enh_token"}, "label": "Prendi il gettone mana %s dall'abilità Potenziamento del Mana" % MKMana.color_it(str(enh.color)), "group": "skill"})
	var nv = inter_get(eng, "natures_vengeance")
	if nv != null and str(nv.get("mode", "")) == "coop" and int(nv.owner) != p and not nv.get("used_by", {}).has(str(p)) and s.combat != null \
			and str(s.combat.phase) in ["ranged", "block"]:
		for e in MKSpecials.enemy_targets(eng, {"need_attack": true}):
			out.append({"a": {"t": "sp", "name": "nv_coop", "eid": e.eid}, "label": "Vendetta della Natura: attacco di %s -1 e Ingombrante" % e.name, "group": "combat"})
	return out

static func do_action(eng, p: int, a: Dictionary) -> void:
	var s: Dictionary = eng.s
	match str(a.name):
		"cumbersome":
			MKCombatExp.do_cumbersome(eng, p, a)
		"maze_path":
			MKSitesExp.do_path(eng, p, a)
		"chaos_rotate":
			for sk in eng.P(p).skills:
				if sk.id == "krang_master_of_chaos":
					sk.chaos = CHAOS_WHEEL[(CHAOS_WHEEL.find(str(sk.get("chaos", "blue"))) + 1) % CHAOS_WHEEL.size()]
					sk["chaos_free"] = false
					eng.add_log("skill", "Signore del Caos avanza a %s" % CHAOS_IT[sk.chaos], {"p": p})
			s.turn["chaos_rot"] = true
		"skill_unflip":
			var sk = eng.find_skill(p, str(a.id))
			if sk.get("flipped", false):
				var plan = MKMana.plan(eng, p, ["green"])
				MKMana.pay(eng, p, plan, ["green"])
				sk.flipped = false
			else:
				sk.used_round = false
				sk.used_turn = false
				s.turn.acted = true
			s.turn.started = true
			eng.add_log("skill", "%s rigira %s" % [eng.pname(p), MKSites._skill_label(str(sk.id))], {"p": p})
		"enh_token":
			var enh = inter_get(eng, "mana_enhancement")
			enh["taken"] = true
			eng.gain_token(p, str(enh.color))
		"nv_coop":
			var nv = inter_get(eng, "natures_vengeance")
			if not nv.has("used_by"):
				nv["used_by"] = {}
			nv.used_by[str(p)] = true
			_vengeance(eng, p, str(a.eid))

static func _vengeance(eng, p: int, eid: String) -> void:
	var e = MKCombat.entry(eng, eid)
	if e == null:
		return
	var bi := 0
	var bv := -1
	for i in e.attacks.size():
		if not e.attacks[i].blocked and MKCombat.attack_value(eng, e, i) > bv:
			bv = MKCombat.attack_value(eng, e, i)
			bi = i
	if bv > 0:
		e.attacks[bi]["mod"] = int(e.attacks[bi].get("mod", 0)) - 1
	if not "cumbersome" in e.abilities:
		e.abilities.append("cumbersome")
	eng.add_log("info", "Vendetta della Natura: %s attacco -1 e diventa Ingombrante" % e.name, {"p": p, "eid": eid})

# ======================================================================
# Hero skills
# ======================================================================
## Flip the skill token that produced the effect (it stays unusable until unflipped).
func sp_skill_flip(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var sk = eng.find_skill(p, str(ctx.get("src", "")).trim_prefix("skill:"))
	if sk == null:
		return
	sk.flipped = true
	sk["unflip"] = MKSpecials._ps(params, "unflip", "rest")
	eng.add_log("skill", "%s gira %s" % [eng.pname(p), MKSites._skill_label(str(sk.id))], {"p": p})

func can_skill_flip(eng, ctx, params) -> bool:
	return false

func sp_wolfs_howl(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var n := 4 + maxi(0, int(eng.command_free(p)))
	MKSpecials.add_mod(eng, ctx, "wolfs_howl", {"n": n})
	eng.add_log("info", "Ululato: la prossima carta giocata di lato vale %d" % n, {"p": p})
	if eng.s.players.size() > 1:
		inter_add(eng, {"id": "wolfs_howl", "owner": p, "mode": MKSpecials._ps(params, "mode", "competitive")})

func can_wolfs_howl(eng, ctx, params) -> bool:
	var p := MKSpecials._p(eng, ctx)
	if eng.s.turn.get("interacted", false):
		return false
	return eng.has_non_wound(p)

func sp_puppet_master(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var opts: Array = []
	var seen := {}
	for ty in eng.s.turn.get("defeated_types", []):
		if seen.has(ty):
			continue
		seen[ty] = true
		opts.append({"v": "keep|" + str(ty), "label": "Conserva il segnalino %s" % _ename(str(ty))})
	var kept: Array = eng.P(p).get("kept_enemies", [])
	for i in kept.size():
		var d: Dictionary = MKDB.enemies.get(str(kept[i]), {})
		if MKSpecials.phase(eng) == "attack" and not d.get("attacks", []).is_empty():
			opts.append({"v": "atk|%d" % i, "label": "Scarta %s: %s" % [_ename(str(kept[i])), MKEffects.describe_list(_puppet_attacks(d))]})
		if MKSpecials.phase(eng) == "block":
			opts.append({"v": "blk|%d" % i, "label": "Scarta %s: %s" % [_ename(str(kept[i])), MKEffects.describe(_puppet_block(d))]})
	MKSpecials.choose(eng, ctx, "puppet_master", "Burattinaio", opts, {}, "choice")

func can_puppet_master(eng, ctx, params) -> bool:
	if not eng.s.turn.get("defeated_types", []).is_empty():
		return true
	var kept: Array = eng.P(MKSpecials._p(eng, ctx)).get("kept_enemies", [])
	if kept.is_empty():
		return false
	if MKSpecials.phase(eng) == "block":
		return true
	if MKSpecials.phase(eng) == "attack":
		for ty in kept:
			if not MKDB.enemies.get(str(ty), {}).get("attacks", []).is_empty():
				return true
	return false

static func _ename(ty: String) -> String:
	return str(MKDB.enemies.get(ty, {}).get("name_it", ty))

static func _puppet_attacks(d: Dictionary) -> Array:
	var out: Array = []
	for a in d.get("attacks", []):
		var n := (int(a.n) + 1) / 2
		if n > 0:
			out.append(["attack", n, str(a.elem), "melee"])
	return out

static func _puppet_block(d: Dictionary) -> Array:
	var res: Array = d.get("resist", [])
	var el := "phys"
	if "fire" in res and "ice" in res:
		el = "cold"
	elif "fire" in res:
		el = "ice"
	elif "ice" in res:
		el = "fire"
	return ["block", (int(d.get("armor", 1)) + 1) / 2, el]

func res_puppet_master(eng, ctx, data, v):
	var p := MKSpecials._p(eng, ctx)
	var pl: Dictionary = eng.P(p)
	var parts := str(v).split("|")
	if not pl.has("kept_enemies"):
		pl["kept_enemies"] = []
	match parts[0]:
		"keep":
			pl.kept_enemies.append(parts[1])
			eng.s.turn.defeated_types.erase(parts[1])
			eng.add_log("skill", "%s conserva il segnalino %s" % [eng.pname(p), _ename(parts[1])], {"p": p})
		"atk", "blk":
			var i := int(parts[1])
			var ty: String = str(pl.kept_enemies[i])
			pl.kept_enemies.remove_at(i)
			var d: Dictionary = MKDB.enemies.get(ty, {})
			var bag: Dictionary = eng.s.enemy_bags.get(str(d.get("color", "")), {})
			if not bag.is_empty():
				bag.discard.append(ty)
			if parts[0] == "atk":
				MKEffects.push(eng, _puppet_attacks(d))
			else:
				MKEffects.push(eng, [_puppet_block(d)])

func sp_master_of_chaos(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var sk = eng.find_skill(p, "krang_master_of_chaos")
	if sk == null:
		return
	var nx: String = CHAOS_WHEEL[(CHAOS_WHEEL.find(str(sk.get("chaos", "blue"))) + 1) % CHAOS_WHEEL.size()]
	sk["chaos"] = nx
	sk["chaos_last"] = int(eng.P(p).turns)
	eng.add_log("skill", "Signore del Caos: %s" % CHAOS_IT[nx], {"p": p})
	if nx == "gold":
		var opts: Array = []
		for c in ["blue", "green", "white", "red", "black"]:
			opts.append(CHAOS_EFF[c])
		MKEffects.push(eng, [["choice", opts]])
	else:
		MKEffects.push(eng, CHAOS_EFF[nx].duplicate(true))

func can_master_of_chaos(eng, ctx, params) -> bool:
	var p := MKSpecials._p(eng, ctx)
	var sk = eng.find_skill(p, "krang_master_of_chaos")
	if sk == null:
		return false
	var nx: String = CHAOS_WHEEL[(CHAOS_WHEEL.find(str(sk.get("chaos", "blue"))) + 1) % CHAOS_WHEEL.size()]
	if nx == "gold":
		for c in CHAOS_EFF:
			if MKEffects.any_can(eng, CHAOS_EFF[c], ctx):
				return true
		return false
	return MKEffects.any_can(eng, CHAOS_EFF[nx], ctx)

func sp_mana_suppression(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	inter_add(eng, {"id": "mana_suppression", "owner": p, "mode": "competitive", "colors": [], "hit": {}})
	eng.add_log("info", "Soppressione del Mana attiva: il primo mana base degli avversari costa un mana in più", {"p": p})

func can_mana_suppression(eng, ctx, params) -> bool:
	return eng.s.players.size() > 1

func res_suppress_crystal(eng, ctx, data, v):
	eng.gain_crystal(MKSpecials._p(eng, ctx), str(v))

func sp_mana_enhancement(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var spent: Array = eng.s.turn.get("basic_spent", [])
	if not spent.is_empty():
		_enhance(eng, p, str(spent[-1]))
	else:
		MKSpecials.add_mod(eng, ctx, "mana_enhancement")
		eng.add_log("info", "Potenziamento del Mana: il prossimo mana base speso dà un cristallo", {"p": p})

func sp_natures_vengeance(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	MKSpecials.choose(eng, ctx, "natures_vengeance", "Vendetta della Natura: scegli il nemico", MKSpecials._enemy_opts(MKSpecials.enemy_targets(eng, {"need_attack": true})), {"mode": MKSpecials._ps(params, "mode", "competitive")}, "enemy")

func can_natures_vengeance(eng, ctx, params) -> bool:
	return MKSpecials.phase(eng) in ["ranged", "block"] and not MKSpecials.enemy_targets(eng, {"need_attack": true}).is_empty()

func res_natures_vengeance(eng, ctx, data, v):
	var p := MKSpecials._p(eng, ctx)
	_vengeance(eng, p, str(v))
	if eng.s.players.size() > 1:
		inter_add(eng, {"id": "natures_vengeance", "owner": p, "mode": str(data.get("mode", "competitive")), "used_by": {}})

func sp_multi_attack(eng, ctx, params):
	var data := {"n": MKSpecials._pi(params, "n", 1), "elem": MKSpecials._ps(params, "elem", "phys"), "kind": MKSpecials._ps(params, "kind", "melee"),
		"left": MKSpecials._pi(params, "targets", 1), "chosen": []}
	_multi_ask(eng, ctx, data)

func _multi_targets(eng, data: Dictionary) -> Array:
	var out: Array = []
	var c = eng.s.combat
	if c == null:
		return out
	for e in c.enemies:
		if not MKCombat.targetable(eng, e) or e.eid in data.chosen:
			continue
		if str(c.phase) == "ranged" and MKCombat.is_fortified(e) and str(data.kind) != "siege":
			continue
		if str(c.phase) == "ranged" and str(data.kind) == "melee":
			continue
		out.append(e)
	return out

func _multi_ask(eng, ctx, data: Dictionary):
	if int(data.left) <= 0:
		return
	var opts: Array = []
	if not data.chosen.is_empty():
		opts.append({"v": "", "label": "Basta così"})
	for e in _multi_targets(eng, data):
		opts.append({"v": e.eid, "label": "%s contro %s" % [MKEffects.describe(["attack", int(data.n), data.elem, data.kind]), e.name]})
	if opts.is_empty() or (opts.size() == 1 and not data.chosen.is_empty()):
		return
	data["always_ask"] = not data.chosen.is_empty()
	MKSpecials.choose(eng, ctx, "multi_attack", "Scegli il bersaglio (attacco separato)", opts, data, "enemy")

func can_multi_attack(eng, ctx, params) -> bool:
	if not MKSpecials.phase(eng) in ["ranged", "attack"]:
		return false
	return not _multi_targets(eng, {"kind": MKSpecials._ps(params, "kind", "melee"), "chosen": []}).is_empty()

func res_multi_attack(eng, ctx, data, v):
	if str(v) == "":
		return
	var e = MKCombat.entry(eng, str(v))
	if e == null:
		return
	if not e.has("tbonus"):
		e["tbonus"] = []
	e.tbonus.append({"n": int(data.n), "elem": str(data.elem), "kind": str(data.kind)})
	eng.add_log("pts", "+%d %s contro %s" % [int(data.n), MKEffects.describe(["attack", int(data.n), data.elem, data.kind]), e.name], {"what": "attack", "n": int(data.n)})
	data.chosen.append(str(v))
	data.left = int(data.left) - 1
	_multi_ask(eng, ctx, data)

const _SHAPE_IT := {"move": "Movimento", "attack": "Attacco", "block": "Blocco"}

func sp_shapeshift(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var opts: Array = []
	for fr in _shape_sources(eng, p):
		for to in ["move", "attack", "block"]:
			if to == fr or not _shape_target_ok(eng, p, to, ctx):
				continue
			opts.append({"v": fr + "|" + to, "label": "Una carta Azione base: %s diventa %s" % [_SHAPE_IT[fr], _SHAPE_IT[to]]})
	MKSpecials.choose(eng, ctx, "shapeshift", "Mutare Forma", opts, {}, "choice")

func can_shapeshift(eng, ctx, params) -> bool:
	var p := MKSpecials._p(eng, ctx)
	for fr in _shape_sources(eng, p):
		for to in ["move", "attack", "block"]:
			if to != fr and _shape_target_ok(eng, p, to, ctx):
				return true
	return false

func _shape_sources(eng, p: int) -> Array:
	var out: Array = []
	for iid in eng.P(p).hand:
		var c: Dictionary = eng.card(iid)
		if str(c.get("type", "")) != "basic":
			continue
		for mode in ["basic", "powered"]:
			_collect_fixed(c.get(mode, []), out)
	return out

func _collect_fixed(eff, out: Array) -> void:
	if not (eff is Array) or eff.is_empty():
		return
	if eff[0] is String:
		var op := str(eff[0])
		if op in ["move", "attack", "block"] and eff.size() > 1 and (eff[1] is int or eff[1] is float):
			if not op in out:
				out.append(op)
		elif op == "choice" and eff.size() > 1 and eff[1] is Array:
			for o in eff[1]:
				_collect_fixed(o, out)
		return
	for x in eff:
		_collect_fixed(x, out)

func _shape_target_ok(eng, p: int, to: String, ctx) -> bool:
	match to:
		"move":
			return eng.can_still_move(p)
		"attack":
			return MKSpecials.phase(eng) == "attack"
		"block":
			return MKSpecials.phase(eng) == "block"
	return false

func res_shapeshift(eng, ctx, data, v):
	var parts := str(v).split("|")
	MKSpecials.add_mod(eng, ctx, "shapeshift", {"from": parts[0], "to": parts[1], "card": ""})
	eng.add_log("info", "Mutare Forma: %s → %s per una carta Azione base" % [_SHAPE_IT[parts[0]], _SHAPE_IT[parts[1]]], {"p": MKSpecials._p(eng, ctx)})

# ======================================================================
# Cards
# ======================================================================
## Savage Harvesting (mod crystal_on_move).
func sp_crystal_on_move(eng, ctx, params):
	var times = params.get("times", 1) if params is Dictionary else 1
	MKSpecials.add_mod(eng, ctx, "crystal_on_move", {"times": times, "used": 0})

func res_harvest(eng, ctx, data, v):
	if str(v) == "":
		return
	var p := MKSpecials._p(eng, ctx)
	var m = MKSpecials.get_mod(eng, "crystal_on_move")
	if m != null:
		m["used"] = int(m.get("used", 0)) + 1
	var c: Dictionary = eng.card(str(v))
	eng.discard_from_hand(p, str(v))
	var cols: Array = MKSpecials.card_colors(c)
	if cols.size() == 1:
		eng.gain_crystal(p, str(cols[0]))
		return
	var opts: Array = []
	for col in (cols if not cols.is_empty() else MKMana.BASIC):
		opts.append({"v": col, "label": "Cristallo " + MKMana.color_it(str(col))})
	eng.ask(p, "color", "sp:harvest_color", "Scegli il colore del cristallo", opts)

func res_harvest_color(eng, ctx, data, v):
	eng.gain_crystal(MKSpecials._p(eng, ctx), str(v))

## Druidic Paths (basic): one space costs n less this turn (min).
func sp_reduce_space_cost(eng, ctx, params):
	MKSpecials.add_mod(eng, ctx, "reduce_space_cost", {"n": MKSpecials._pi(params, "n", 1), "min": MKSpecials._pi(params, "min", 2), "terrain": MKSpecials._ps(params, "terrain", ""), "hex": ""})

func can_reduce_space_cost(eng, ctx, params) -> bool:
	return eng.can_still_move(MKSpecials._p(eng, ctx))

const STAFF := {"white": [["special", "safe_move", {"spaces": 2}]], "blue": [["crystal", "basic"], ["crystal", "basic"]],
	"red": [["ready_unit", 3]], "green": [["heal", 3]]}
const STAFF_IT := {"white": "muovi fino a 2 spazi in uno spazio sicuro", "blue": "2 cristalli a scelta", "red": "prepara un'Unità (livello ≤ III)",
	"green": "Cura 3"}

func sp_druidic_staff(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var powered: bool = params.get("powered", false) if params is Dictionary else false
	if powered:
		_staff_pick(eng, ctx, [])
		return
	var opts: Array = []
	var seen := {}
	for iid in eng.P(p).hand:
		if iid == str(ctx.get("src", "")) or eng.is_wound(iid) or seen.has(eng.card_id(iid)):
			continue
		seen[eng.card_id(iid)] = true
		for col in MKSpecials.card_colors(eng.card(iid)):
			if STAFF.has(str(col)) and MKEffects.any_can(eng, STAFF[col], ctx):
				opts.append({"v": iid + "|" + str(col), "label": "Scarta %s: %s" % [eng.card_name(iid), STAFF_IT[col]]})
	MKSpecials.choose(eng, ctx, "druidic_staff", "Bastone Druidico: scegli la carta da scartare", opts, {}, "card")

func can_druidic_staff(eng, ctx, params) -> bool:
	var p := MKSpecials._p(eng, ctx)
	var powered: bool = params.get("powered", false) if params is Dictionary else false
	for col in STAFF:
		if not MKEffects.any_can(eng, STAFF[col], ctx):
			continue
		if powered:
			return true
		for iid in eng.P(p).hand:
			if iid != str(ctx.get("src", "")) and not eng.is_wound(iid) and col in MKSpecials.card_colors(eng.card(iid)):
				return true
	return false

func res_druidic_staff(eng, ctx, data, v):
	var parts := str(v).split("|")
	eng.discard_from_hand(MKSpecials._p(eng, ctx), parts[0])
	MKEffects.push(eng, STAFF[parts[1]].duplicate(true))

func _staff_pick(eng, ctx, done: Array):
	var opts: Array = []
	for col in ["white", "blue", "red", "green"]:
		if not col in done and MKEffects.any_can(eng, STAFF[col], ctx):
			opts.append({"v": col, "label": STAFF_IT[col].capitalize()})
	if done.size() >= 2 or opts.is_empty():
		return
	MKSpecials.choose(eng, ctx, "staff_powered", "Bastone Druidico: scegli un'opzione (%d di 2)" % (done.size() + 1), opts, {"done": done}, "choice")

func res_staff_powered(eng, ctx, data, v):
	var done: Array = data.get("done", [])
	done.append(str(v))
	MKEffects.push(eng, STAFF[str(v)].duplicate(true) + [["special", "staff_next", {"done": done}]])

## Internal continuation of the powered Druidic Staff (second option after the first one resolved).
func sp_staff_next(eng, ctx, params):
	var done: Array = params.get("done", []) if params is Dictionary else []
	_staff_pick(eng, ctx, done)

## Banner of Command (basic): attach to a unit recruited this turn instead of a Command token.
func sp_banner_command(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var src := str(ctx.get("src", ""))
	if src.find("#") < 0:
		return
	var opts: Array = []
	var bn: Dictionary = eng.P(p).get("banners", {})
	for uid in eng.s.turn.get("recruited_uids", []):
		var u = eng.find_unit(p, uid)
		if u != null and not bn.has(str(uid)):
			opts.append({"v": int(uid), "label": "Assegna a " + eng.unit_name(u)})
	if opts.is_empty():
		MKSpecials.add_mod(eng, ctx, "banner_command")
		eng.add_log("info", "Stendardo del Comando: se recluti un'Unità in questo turno lo assegni a lei al posto di un segnalino Comando", {"p": p})
		return
	opts.append({"v": -1, "label": "Non assegnarlo"})
	MKSpecials.choose(eng, ctx, "banner_command", "Stendardo del Comando: a quale Unità reclutata in questo turno?", opts, {"card": src, "always_ask": true}, "unit")

func res_banner_command(eng, ctx, data, v):
	if int(v) < 0:
		return
	_attach_banner(eng, MKSpecials._p(eng, ctx), str(data.card), int(v))

## Mysterious Box: use the top artifact of the deck this turn.
func sp_mysterious_box(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var s: Dictionary = eng.s
	var t: Dictionary = s.turn
	var powered: bool = params.get("powered", false) if params is Dictionary else false
	var src := str(ctx.get("src", ""))
	if s.decks.artifacts.is_empty():
		return
	var a: String = s.decks.artifacts.pop_front()
	if not t.has("box_revealed"):
		t["box_revealed"] = []
	t.box_revealed.append(a)
	if not t.has("box_used"):
		t["box_used"] = []
	t.box_used.append(src)
	var ad: Dictionary = MKDB.card(a)
	var mode := "powered" if powered else "basic"
	var effs: Array = ad.get(mode, [])
	eng.add_log("reveal", "Forziere Misterioso: rivelato %s" % MKSites._cname(a), {"p": p, "card": a})
	var banner: bool = ad.get("banner", false) and mode == "basic"
	var ok: bool = not effs.is_empty() and not banner and (not ad.get("combat_only", false) or s.combat != null) and MKEffects.any_can(eng, effs, ctx)
	if ok:
		MKEffects.push(eng, effs.duplicate(true) + [["fame", 1]])
		return
	# not usable: the box goes back to the hand
	var pl: Dictionary = eng.P(p)
	if pl.play.has(src):
		pl.play.erase(src)
		pl.hand.append(src)
		t.played.erase(src)
		t.destroy.erase(src)
	eng.add_log("info", "%s non è utilizzabile ora: il Forziere torna in mano" % MKSites._cname(a), {"p": p})

func can_mysterious_box(eng, ctx, params) -> bool:
	return not eng.s.decks.artifacts.is_empty() and not str(ctx.get("src", "")) in eng.s.turn.get("box_used", [])

# ======================================================================
# Units
# ======================================================================
func sp_familiars_upkeep(eng, ctx, params):
	pass

func res_familiar_token(eng, ctx, data, v):
	var p := MKSpecials._p(eng, ctx)
	var paid: Array = MKMana.pay(eng, p, [str(v)], ["basic"])
	var u = eng.find_unit(p, data.get("uid", -1))
	if u != null and not paid.is_empty():
		u["token"] = str(paid[0])
		eng.add_log("unit", "Famigli Magici: segnalino %s" % MKMana.color_it(str(paid[0])), {"p": p})

func res_familiars_keep(eng, ctx, data, v):
	var p := MKSpecials._p(eng, ctx)
	var u = eng.find_unit(p, data.get("uid", -1))
	if u != null:
		if str(v) == "":
			eng.remove_unit(p, u)
			eng.add_log("unit_destroyed", "%s lascia andare i Famigli Magici" % eng.pname(p), {"p": p})
		else:
			var pl: Dictionary = eng.P(p)
			pl.crystals[str(v)] = maxi(0, int(pl.crystals.get(str(v), 0)) - 1)
			u["token"] = str(v)
			eng.add_log("unit", "Famigli Magici: nuovo segnalino %s" % MKMana.color_it(str(v)), {"p": p})
	_familiars_next(eng)

func sp_unit_token_bonus(eng, ctx, params):
	var p := MKSpecials._p(eng, ctx)
	var eff: Array = (params.get("effect", []) if params is Dictionary else []).duplicate(true)
	if eff.size() < 2:
		return
	var u = eng.find_unit(p, ctx.get("uid", -1))
	if u != null and str(u.get("token", "")) == MKSpecials._ps(params, "color", ""):
		eff[1] = int(eff[1]) + MKSpecials._pi(params, "bonus", 0)
	MKEffects.push(eng, [eff])

func can_unit_token_bonus(eng, ctx, params) -> bool:
	var eff = params.get("effect", []) if params is Dictionary else []
	return eff is Array and not eff.is_empty() and MKEffects.can(eng, eff, ctx)

# ======================================================================
# Maze (pending handler)
# ======================================================================
func res_maze_unit(eng, ctx, data, v):
	MKSitesExp.choose_unit(eng, MKSpecials._p(eng, ctx), v)
