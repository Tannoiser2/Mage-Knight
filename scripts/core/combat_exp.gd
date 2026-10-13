class_name MKCombatExp
extends RefCounted
## Enemy abilities and combat rules of the expansions (La Legione Perduta, Shades of Tezla), kept apart
## from combat.gd: Elusivo, Difensore, Ingombrante, Assassinio, Vampirico, Evocatore multiplo, mura
## (fortificazione attraverso un muro), Dedalo/Labirinto (una sola Unità), attacchi a bersaglio singolo
## (Fulmine Biforcuto), Ululato / Vendetta della Natura (effetti sugli altri giocatori).
##
## Interpretations (Lost Legion / Ultimate Edition rules, from memory; see README):
## - Elusivo: armatura alta (elusive_armor); nella fase di Attacco vale quella bassa se tutti i suoi
##   attacchi sono stati bloccati (o ridotti a 0 / annullati).
## - Difensore X: quando attacchi, ogni Difensore non ancora usato aggiunge X all'Armatura di uno dei
##   bersagli non ancora difesi (anche se stesso), una volta per combattimento; il bonus resta.
## - Ingombrante: nella fase di Blocco puoi spendere punti Movimento: ogni punto riduce di 1 un suo
##   attacco per il turno; un attacco ridotto a 0 conta come bloccato.
## - Assassinio: i danni dei suoi attacchi non si possono assegnare alle Unità.
## - Vampirico: ogni Ferita che infligge (in mano all'eroe o a un'Unità) gli dà Armatura +1 per il resto
##   del combattimento (le ferite del veleno negli scarti non contano).

# ---------------------------------------------------------------- armour
## Armour without the potential Defend bonus (elusive, vampiric, defend already received).
static func armor_core(eng, e: Dictionary) -> int:
	var a := int(e.armor)
	if MKCombat.has_ab(e, "elusive") and int(e.get("elusive_armor", 0)) > a:
		if not (eng.s.combat != null and str(eng.s.combat.phase) == "attack" and all_blocked(eng, e)):
			a = int(e.elusive_armor)
	a += int(e.get("vamp", 0)) + int(e.get("defend_bonus", 0))
	return maxi(1, a + int(e.get("armor_mod", 0)))

## Armour shown / used by planners: includes the Defend bonus this enemy would receive if attacked now
## (conservative: a group attack never needs more than the sum of these values).
static func armor_full(eng, e: Dictionary) -> int:
	return armor_core(eng, e) + pending_defend(eng, e)

static func all_blocked(eng, e: Dictionary) -> bool:
	if e.get("no_attack", false):
		return true
	for i in e.attacks.size():
		if not e.attacks[i].blocked and MKCombat.attack_value(eng, e, i) > 0:
			return false
	return true

# ---------------------------------------------------------------- Defend
static func _defend_value(e: Dictionary) -> int:
	return int(MKDB.enemies.get(str(e.get("type", "")), {}).get("defend", 0))

static func _defenders(eng) -> Array:
	var out: Array = []
	var c = eng.s.combat
	if c == null:
		return out
	for d in c.enemies:
		if d.defeated or d.get("hidden", false) or d.get("defend_used", false) or not MKCombat.has_ab(d, "defend"):
			continue
		if _defend_value(d) > 0:
			out.append(d)
	out.sort_custom(func(a, b): return _defend_value(a) > _defend_value(b) or (_defend_value(a) == _defend_value(b) and str(a.eid) < str(b.eid)))
	return out

static func pending_defend(eng, e: Dictionary) -> int:
	var c = eng.s.combat
	if c == null or not str(c.phase) in ["ranged", "attack"] or int(e.get("defend_bonus", 0)) > 0 or e.defeated:
		return 0
	var ds := _defenders(eng)
	return _defend_value(ds[0]) if not ds.is_empty() else 0

## Exact extra armour of a group attack: the k largest free Defend values, k = undefended targets.
static func defend_extra(eng, targets: Array) -> int:
	var ds := _defenders(eng)
	var k := 0
	for eid in targets:
		var e = MKCombat.entry(eng, str(eid))
		if e != null and int(e.get("defend_bonus", 0)) == 0:
			k += 1
	var tot := 0
	for i in mini(k, ds.size()):
		tot += _defend_value(ds[i])
	return tot

static func apply_defend(eng, targets: Array) -> void:
	var ds := _defenders(eng)
	var i := 0
	for eid in targets:
		if i >= ds.size():
			break
		var e = MKCombat.entry(eng, str(eid))
		if e == null or int(e.get("defend_bonus", 0)) > 0:
			continue
		var d: Dictionary = ds[i]
		i += 1
		d["defend_used"] = true
		e["defend_bonus"] = _defend_value(d)
		eng.add_log("info", "%s difende %s: Armatura +%d" % [d.name, e.name, _defend_value(d)], {"eid": e.eid})

# ---------------------------------------------------------------- start / phases
static func on_start(eng, opts: Dictionary) -> void:
	var c: Dictionary = eng.s.combat
	var p: int = int(eng.s.turn.get("player", 0))
	# walls: assault across a wall -> double fortified garrison; challenge across a wall -> fortified
	if opts.get("wall", false):
		for e in c.enemies:
			if e.site_def and not "unfortified" in e.abilities:
				e.self_fort = true
				e.fortified = true
				e.dfort = e.site_fort
		eng.add_log("info", "Assalto attraverso un muro: la guarnigione è fortificata doppia", {})
	var wh: Array = opts.get("wall_hexes", [])
	if not wh.is_empty():
		for e in c.enemies:
			var hk := str(eng.s.enemies.get(e.eid, {}).get("hex", ""))
			if hk in wh and not "unfortified" in e.abilities:
				if e.self_fort:
					e.dfort = true
				e.site_fort = true
				e.fortified = true
		eng.add_log("info", "Nemici sfidati attraverso un muro: sono fortificati", {})
	if opts.has("units_only"):
		c["units_only"] = int(opts.units_only)
		c.units_allowed = int(opts.units_only) >= 0
	MKSpecialsExp.on_combat_start(eng, p)

static func on_block_phase(eng) -> void:
	MKSpecialsExp.on_block_phase(eng)

static func on_phase_end(eng, old_phase: String) -> void:
	var c = eng.s.combat
	if c == null:
		return
	if old_phase == "ranged":
		for e in c.enemies:
			e.erase("tbonus")

## Number of monsters a summoner calls (Evocatore di Draghi: 2).
static func summon_count(e: Dictionary) -> int:
	return maxi(1, int(MKDB.enemies.get(str(e.get("type", "")), {}).get("summon_n", 1)))

# ---------------------------------------------------------------- damage
## Reason why damage of attack ai of enemy e cannot go to unit u ("" = allowed).
static func unit_damage_block(eng, e: Dictionary, ai: int, u: Dictionary) -> String:
	var c: Dictionary = eng.s.combat
	if int(c.get("units_only", -1)) >= 0 and int(u.uid) != int(c.units_only):
		return "Solo l'Unità che ti accompagna partecipa a questo combattimento"
	if MKCombat.has_ab(e, "assassinate") and int(e.attacks[ai].get("draw_fire", -1)) != int(u.uid):
		return "Assassinio: i danni di questo nemico vanno all'eroe"
	return ""

## Shocktroops "draw fire": uid that must take the damage of this attack first (-1 = none / not possible).
static func forced_unit(eng, p: int, e: Dictionary, ai: int) -> int:
	var uid := int(e.attacks[ai].get("draw_fire", -1))
	if uid < 0:
		return -1
	var u = eng.find_unit(p, uid)
	var c: Dictionary = eng.s.combat
	if u == null or u.wounded or not c.get("units_allowed", true) or uid in e.attacks[ai].units_hit or uid in c.get("units_absorbed", []):
		return -1
	return uid

## Vampiric: n wounds inflicted by e.
static func on_wounds(eng, e: Dictionary, n: int) -> void:
	if n > 0 and MKCombat.has_ab(e, "vampiric") and not e.defeated:
		e["vamp"] = int(e.get("vamp", 0)) + n
		eng.add_log("info", "%s è Vampirico: Armatura +%d" % [e.name, n], {"eid": e.eid})

# ---------------------------------------------------------------- Cumbersome (special action)
static func cumbersome_actions(eng, p: int) -> Array:
	var out: Array = []
	var c = eng.s.combat
	if c == null or str(c.phase) != "block" or int(eng.s.turn.pool.move) < 1:
		return out
	for e in c.enemies:
		if e.defeated or e.get("hidden", false) or not MKCombat.has_ab(e, "cumbersome"):
			continue
		for i in e.attacks.size():
			if e.attacks[i].blocked or MKCombat.attack_value(eng, e, i) <= 0:
				continue
			var which := (" %d" % (i + 1)) if e.attacks.size() > 1 else ""
			out.append({"a": {"t": "sp", "name": "cumbersome", "eid": e.eid, "attack": i},
				"label": "Ingombrante: spendi 1 Movimento, attacco%s di %s -1 (ora %d)" % [which, e.name, MKCombat.attack_value(eng, e, i)], "group": "combat"})
	return out

static func do_cumbersome(eng, p: int, a: Dictionary) -> void:
	var e = MKCombat.entry(eng, str(a.eid))
	var i := int(a.get("attack", 0))
	eng.s.turn.pool.move = int(eng.s.turn.pool.move) - 1
	var at: Dictionary = e.attacks[i]
	at["mod"] = int(at.get("mod", 0)) - 1
	eng.add_log("info", "%s spende 1 Movimento: l'attacco di %s scende a %d" % [eng.pname(p), e.name, MKCombat.attack_value(eng, e, i)], {"p": p, "eid": e.eid})
	if MKCombat.attack_value(eng, e, i) <= 0:
		at.blocked = true
		eng.s.combat["blocked_count"] = int(eng.s.combat.get("blocked_count", 0)) + 1
		eng.add_log("block", "L'attacco di %s è ridotto a 0: conta come bloccato" % e.name, {"p": p, "eid": e.eid})

## Move effects/cards are useful in combat only to pay Cumbersome enemies (block phase).
static func move_usable(eng) -> bool:
	var c = eng.s.combat
	if c == null or str(c.phase) != "block":
		return false
	for e in c.enemies:
		if not e.defeated and not e.get("hidden", false) and MKCombat.has_ab(e, "cumbersome"):
			for i in e.attacks.size():
				if not e.attacks[i].blocked and MKCombat.attack_value(eng, e, i) > 0:
					return true
	return false

# ---------------------------------------------------------------- single-target attacks (Forked Lightning)
## e.tbonus = [{n, elem, kind}]: attacks that can be used only against that enemy (in a group too).
static func has_target_bonus(eng) -> bool:
	var c = eng.s.combat
	if c == null:
		return false
	for e in c.enemies:
		if not e.defeated and not e.get("tbonus", []).is_empty():
			return true
	return false

## [efficient, inefficient] attack points of the target bonuses usable against the group now.
static func target_bonus(eng, targets: Array) -> Array:
	var c = eng.s.combat
	var eff := 0
	var ineff := 0
	if c == null:
		return [0, 0]
	var fort := false
	for eid in targets:
		var e = MKCombat.entry(eng, str(eid))
		if e != null and MKCombat.is_fortified(e):
			fort = true
	for eid in targets:
		var e = MKCombat.entry(eng, str(eid))
		if e == null:
			continue
		for b in e.get("tbonus", []):
			var kind := str(b.get("kind", "melee"))
			if str(c.phase) == "ranged" and (kind == "melee" or (fort and kind != "siege")):
				continue
			if not str(c.phase) in ["ranged", "attack"]:
				continue
			var res := false
			for eid2 in targets:
				var e2 = MKCombat.entry(eng, str(eid2))
				if e2 != null and MKCombat.resists(e2, str(b.get("elem", "phys"))):
					res = true
			if res:
				ineff += int(b.n)
			else:
				eff += int(b.n)
	return [eff, ineff]

static func consume_target_bonus(eng, targets: Array) -> void:
	for eid in targets:
		var e = MKCombat.entry(eng, str(eid))
		if e != null:
			e.erase("tbonus")
