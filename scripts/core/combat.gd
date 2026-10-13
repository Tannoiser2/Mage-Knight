class_name MKCombat
extends RefCounted
## Combat: phases ranged -> block -> damage -> attack -> end.

const ELEM_IT := {"phys": "fisico", "fire": "di fuoco", "ice": "di ghiaccio", "cold": "di fuoco-ghiaccio"}

## opts: site, kind ("assault"|"provoke"|"challenge"|"site"|"burn"), assault, defenders:[eid], retreat,
##       units_allowed, night_rules, site_type
static func start(eng, eids: Array, opts: Dictionary) -> void:
	var s: Dictionary = eng.s
	var p: int = int(s.turn.player)
	var site: String = str(opts.get("site", ""))
	var h: Dictionary = eng.hex(site) if site != "" else {}
	var site_type: String = str(opts.get("site_type", h.get("site", "")))
	var fort_site: bool = site_type in ["keep", "mage_tower", "city"] and bool(opts.get("assault", false))
	var defenders: Array = opts.get("defenders", [])
	var city_color := ""
	if site_type == "city" and h.has("city"):
		city_color = str(h.city.color)
	var list: Array = []
	var seen := {}
	for eid in eids:
		if seen.has(eid) or not s.enemies.has(eid):
			continue
		seen[eid] = true
		var inst: Dictionary = s.enemies[eid]
		inst.face_up = true
		var d: Dictionary = MKDB.enemies.get(str(inst.type), {})
		var is_def: bool = eid in defenders
		var ent := _entry(eng, eid, d, is_def and fort_site, is_def, city_color if is_def else "")
		ent["rampage"] = eng.hex(str(inst.get("hex", ""))).get("rampage", false) and not is_def
		ent["half_fame"] = inst.get("half_fame", false)
		list.append(ent)
	var night_rules: bool = bool(opts.get("night_rules", site_type in ["dungeon", "tomb"] and opts.get("kind", "") == "site"))
	var units_ok: bool = bool(opts.get("units_allowed", not (site_type in ["dungeon", "tomb"] and opts.get("kind", "") == "site")))
	s.combat = {"enemies": list, "phase": "ranged", "site": site, "site_type": site_type, "kind": str(opts.get("kind", "provoke")),
		"assault": bool(opts.get("assault", false)), "retreat": str(opts.get("retreat", "")), "units_allowed": units_ok,
		"night_rules": night_rules, "wounds_hand": 0, "fame": 0, "fortified_site": fort_site, "city": city_color,
		"ruins": str(opts.get("ruins", "")), "first_time": bool(opts.get("first_time", true)), "summoned": []}
	var t: Dictionary = s.turn
	t.acted = true
	t.started = true
	t.combats = int(t.get("combats", 0)) + 1
	t.pool.move = 0
	t.pool.influence = 0
	t.pool.heal = 0
	t.pool.attack = {}
	t.pool.block = {}
	var names: Array = []
	for e in list:
		names.append(e.name)
	eng.add_log("combat_start", "Combattimento contro: %s" % ", ".join(names), {"p": p, "enemies": eids, "site": site, "kind": s.combat.kind})
	MKSpecials.on_combat_start(eng, p)
	if list.is_empty():
		s.combat.phase = "end"

static func _entry(eng, eid: String, d: Dictionary, fort_site: bool, is_def: bool, city: String) -> Dictionary:
	var abil: Array = d.get("abilities", []).duplicate()
	var attacks: Array = []
	for a in d.get("attacks", []):
		var n := int(a.n)
		var el: String = str(a.elem)
		if city == "blue":
			if el in ["fire", "ice"]:
				n += 2
			elif el == "cold":
				n += 1
		attacks.append({"n": n, "elem": el, "blocked": false, "rem": 0, "done": false, "units_hit": []})
	if city == "red" or city == "green":
		var has_phys := false
		for a in attacks:
			if a.elem == "phys":
				has_phys = true
		if has_phys:
			var ab := "brutal" if city == "red" else "poison"
			if not ab in abil:
				abil.append(ab)
	var armor := int(d.get("armor", 1)) + (1 if city == "white" else 0)
	var self_fort: bool = "fortified" in abil
	if "unfortified" in abil:
		fort_site = false
	return {"eid": eid, "self_fort": self_fort, "site_fort": fort_site, "type": str(d.get("id", "")), "name": str(d.get("name_it", "Nemico")), "armor": armor,
		"fame": int(d.get("fame", 0)), "resist": d.get("resist", []).duplicate(), "abilities": abil,
		"fortified": self_fort or fort_site, "dfort": self_fort and fort_site, "attacks": attacks, "defeated": false,
		"site_def": is_def, "summoned": false, "by": "", "hidden": false, "color": str(d.get("color", "")),
		"rep": int(d.get("rep", 0)), "armor_mod": 0}

static func entry(eng, eid: String) -> Variant:
	var c = eng.s.combat
	if c == null:
		return null
	for e in c.enemies:
		if e.eid == eid:
			return e
	return null

static func is_fortified(e: Dictionary) -> bool:
	return (e.get("self_fort", false) and not e.get("self_fort_lost", false)) or (e.get("site_fort", false) and not e.get("site_fort_lost", false))

static func is_double_fortified(e: Dictionary) -> bool:
	return (e.get("self_fort", false) and not e.get("self_fort_lost", false)) and (e.get("site_fort", false) and not e.get("site_fort_lost", false))

static func armor_of(eng, e: Dictionary) -> int:
	return maxi(1, int(e.armor) + int(e.get("armor_mod", 0)))

static func has_ab(e: Dictionary, ab: String) -> bool:
	return ab in e.get("abilities", []) and not ab in e.get("lost", [])

static func resists(e: Dictionary, elem: String) -> bool:
	var r: Array = e.get("resist", [])
	if elem in e.get("lost_resist", []):
		return false
	if elem == "cold":
		return "fire" in r and "ice" in r and not "fire" in e.get("lost_resist", []) and not "ice" in e.get("lost_resist", [])
	return elem in r

# ---------------------------------------------------------------- attack / block values
static func _attack_keys(eng, targets: Array) -> Array:
	var c: Dictionary = eng.s.combat
	var pool: Dictionary = eng.s.turn.pool.attack
	var fort := false
	for eid in targets:
		var e = entry(eng, eid)
		if e != null and is_fortified(e):
			fort = true
	var out: Array = []
	for key in pool:
		if int(pool[key]) <= 0:
			continue
		var kind: String = key.split(":")[0]
		if c.phase == "ranged":
			if kind == "melee":
				continue
			if fort and kind != "siege":
				continue
		elif c.phase != "attack":
			continue
		out.append(key)
	return out

static func effective_attack(eng, targets: Array) -> int:
	if eng.s.combat == null:
		return 0
	var pool: Dictionary = eng.s.turn.pool.attack
	var eff := 0
	var ineff := 0
	for key in _attack_keys(eng, targets):
		var elem: String = key.split(":")[1]
		var res := false
		for eid in targets:
			var e = entry(eng, eid)
			if e != null and resists(e, elem):
				res = true
		if res:
			ineff += int(pool[key])
		else:
			eff += int(pool[key])
	return eff + ineff / 2

static func block_efficient(block_elem: String, attack_elem: String) -> bool:
	match attack_elem:
		"phys":
			return true
		"fire":
			return block_elem in ["ice", "cold"]
		"ice":
			return block_elem in ["fire", "cold"]
		"cold":
			return block_elem == "cold"
	return true

static func effective_block(eng, eid: String, ai: int = 0) -> int:
	var e = entry(eng, eid)
	if e == null or ai >= e.attacks.size():
		return 0
	var ael: String = attack_elem(e, ai)
	var pool: Dictionary = eng.s.turn.pool.block
	var eff := 0
	var ineff := 0
	for el in pool:
		if block_efficient(el, ael):
			eff += int(pool[el])
		else:
			ineff += int(pool[el])
	var t: Dictionary = eng.s.turn
	var bs := int(t.get("block_swift", 0))
	if bs > 0:
		var v := bs * (2 if has_ab(e, "swift") else 1)
		if block_efficient("phys", ael):
			eff += v
		else:
			ineff += v
	var mb = t.get("multi_block", null)
	if mb is Dictionary and int(mb.get("left", 0)) > 0:
		if block_efficient(str(mb.get("elem", "phys")), ael):
			eff += int(mb.n)
		else:
			ineff += int(mb.n)
	var bpa = t.get("block_per_ability", null)
	if bpa is Dictionary and not has_ab(e, "arcane_immunity"):
		var cnt: int = e.abilities.size() + e.resist.size()
		if ael != "phys":
			cnt += 1
		var v2 := int(bpa.get("n", 1)) * cnt
		if block_efficient(str(bpa.get("elem", "ice")), ael):
			eff += v2
		else:
			ineff += v2
	return eff + ineff / 2

static func block_needed(eng, e: Dictionary, ai: int) -> int:
	var n := attack_value(eng, e, ai)
	if has_ab(e, "swift"):
		n *= 2
	return n

static func attack_value(eng, e: Dictionary, ai: int) -> int:
	if e.get("no_attack", false):
		return 0
	var n := int(e.attacks[ai].n) + int(e.get("attack_mod", 0)) + int(e.attacks[ai].get("mod", 0))
	return maxi(0, n)

static func attack_elem(e: Dictionary, ai: int) -> String:
	return str(e.attacks[ai].get("elem_override", e.attacks[ai].elem))

static func targetable(eng, e: Dictionary) -> bool:
	var c: Dictionary = eng.s.combat
	if e.defeated or e.hidden:
		return false
	if c.phase == "ranged" and is_double_fortified(e):
		return false
	if c.phase == "ranged" and e.summoned:
		return false
	return c.phase in ["ranged", "attack"]

# ---------------------------------------------------------------- checks
static func check(eng, p: int, a: Dictionary) -> String:
	var c = eng.s.combat
	if c == null:
		return "Non sei in combattimento"
	var t: String = a.get("t", "")
	match t:
		"next":
			if c.phase == "damage":
				for e in c.enemies:
					for at in e.attacks:
						if int(at.rem) > 0:
							return "Devi prima assegnare tutti i danni"
			return ""
		"attack":
			if not c.phase in ["ranged", "attack"]:
				return "Non è la fase di attacco"
			var targets: Array = a.get("targets", [])
			if targets.is_empty():
				return "Scegli almeno un nemico"
			var arm := 0
			var seen := {}
			for eid in targets:
				if seen.has(eid):
					return "Bersaglio ripetuto"
				seen[eid] = true
				var e = entry(eng, str(eid))
				if e == null or not targetable(eng, e):
					return "Bersaglio non valido"
				arm += armor_of(eng, e)
			var ea := effective_attack(eng, targets)
			if ea < arm:
				return "Attacco insufficiente (%d contro Armatura %d)" % [ea, arm]
			return ""
		"block":
			if c.phase != "block":
				return "Non è la fase di blocco"
			var e2 = entry(eng, str(a.get("eid", "")))
			var ai := int(a.get("attack", 0))
			if e2 == null or e2.defeated or e2.hidden:
				return "Nemico non valido"
			if ai < 0 or ai >= e2.attacks.size():
				return "Attacco non valido"
			if e2.attacks[ai].blocked:
				return "Attacco già bloccato"
			if attack_value(eng, e2, ai) <= 0:
				return "Questo nemico non attacca"
			var need := block_needed(eng, e2, ai)
			var have := effective_block(eng, e2.eid, ai)
			if have < need:
				return "Blocco insufficiente (%d contro %d)" % [have, need]
			return ""
		"damage":
			if c.phase != "damage":
				return "Non è la fase di assegnazione dei danni"
			var e3 = entry(eng, str(a.get("eid", "")))
			if e3 == null:
				return "Nemico non valido"
			var ai3 := int(a.get("attack", _first_rem(e3)))
			if ai3 < 0 or ai3 >= e3.attacks.size() or int(e3.attacks[ai3].rem) <= 0:
				return "Nessun danno da assegnare per questo nemico"
			var to = a.get("to", "hero")
			if str(to) == "hero":
				return ""
			if not c.units_allowed:
				return "Le unità non partecipano a questo combattimento"
			if eng.flag(p, "no_unit_damage"):
				return "In questo turno non puoi assegnare danni alle unità"
			var u = eng.find_unit(p, to)
			if u == null:
				return "Unità non trovata"
			if u.wounded:
				return "Non puoi assegnare danni a un'unità ferita"
			if int(u.uid) in e3.attacks[ai3].units_hit or int(u.uid) in c.get("units_absorbed", []):
				return "Questa unità ha già assorbito danni"
			var dc = MKSpecials.unit_rule(eng.unit_def(u), "unit_damage_cost")
			if dc != null and not u.get("dmg_paid", false) and int(eng.s.turn.pool.influence) < int(dc.get("influence", 2)):
				return "Per assegnare danni a questa unità servono %d Influenza" % int(dc.get("influence", 2))
			return ""
	return "Azione di combattimento sconosciuta"

static func _first_rem(e: Dictionary) -> int:
	for i in e.attacks.size():
		if int(e.attacks[i].rem) > 0:
			return i
	return 0

# ---------------------------------------------------------------- actions
static func do(eng, p: int, a: Dictionary) -> void:
	var c: Dictionary = eng.s.combat
	match str(a.t):
		"next":
			next_phase(eng)
		"attack":
			var targets: Array = a.targets
			var keys := _attack_keys(eng, targets)
			var val := effective_attack(eng, targets)
			for k in keys:
				eng.s.turn.pool.attack.erase(k)
			var names: Array = []
			for eid in targets:
				var e = entry(eng, str(eid))
				names.append(e.name)
				defeat(eng, p, e)
			eng.add_log("attack", "%s attacca (%d) e sconfigge %s" % [eng.pname(p), val, ", ".join(names)], {"p": p, "targets": targets, "value": val})
			_check_all_defeated(eng)
		"block":
			var e2 = entry(eng, str(a.eid))
			var ai := int(a.get("attack", 0))
			e2.attacks[ai].blocked = true
			eng.s.turn.pool.block = {}
			eng.s.turn.erase("block_swift")
			eng.s.turn.erase("block_per_ability")
			c["blocked_count"] = int(c.get("blocked_count", 0)) + 1
			MKSpecials.on_block(eng, p, e2)
			eng.add_log("block", "%s blocca l'attacco di %s" % [eng.pname(p), e2.name], {"p": p, "eid": e2.eid})
			if e2.summoned:
				var all_b := true
				for at in e2.attacks:
					if not at.blocked:
						all_b = false
				if all_b:
					e2.defeated = true
					e2["no_fame"] = true
		"damage":
			var e3 = entry(eng, str(a.eid))
			var ai3 := int(a.get("attack", _first_rem(e3)))
			assign_damage(eng, p, e3, ai3, a.get("to", "hero"))

static func defeat(eng, p: int, e: Dictionary) -> void:
	e.defeated = true
	var s: Dictionary = eng.s
	if e.summoned or e.get("no_fame", false):
		return
	var fame := int(e.fame)
	if e.get("half_fame", false):
		fame = (fame + 1) / 2
	fame += int(s.turn.get("fame_bonus_per_enemy", 0))
	eng.gain_fame(p, fame)
	MKSpecials.on_defeat(eng, p, e)
	s.combat.fame = int(s.combat.fame) + fame
	if e.get("rampage", false):
		eng.change_rep(p, 2 if e.color == "red" else 1)
	if int(e.get("rep", 0)) != 0:
		eng.change_rep(p, int(e.rep))
	if e.site_def and s.combat.site_type == "city":
		var h: Dictionary = eng.hex(s.combat.site)
		if h.has("city"):
			h.city.shields.append(p)
	eng.add_log("enemy_defeated", "%s sconfitto (+%d Fama)" % [e.name, fame], {"p": p, "eid": e.eid, "fame": fame})

static func _check_all_defeated(eng) -> void:
	var c: Dictionary = eng.s.combat
	for e in c.enemies:
		if not e.defeated:
			return
	c.phase = "end"

static func next_phase(eng) -> void:
	var s: Dictionary = eng.s
	var c: Dictionary = s.combat
	var p: int = int(s.turn.player)
	match c.phase:
		"ranged":
			s.turn.pool.attack = {}
			c.phase = "block"
			_summon(eng)
			eng.add_log("combat_phase", "Fase di blocco", {"phase": "block"})
			if _alive(c).is_empty():
				c.phase = "end"
		"block":
			s.turn.pool.block = {}
			var any := false
			for e in c.enemies:
				if e.defeated or e.hidden:
					continue
				for i in e.attacks.size():
					var at: Dictionary = e.attacks[i]
					if not at.blocked and attack_value(eng, e, i) > 0:
						var dmg := attack_value(eng, e, i)
						if has_ab(e, "brutal"):
							dmg *= 2
						at.rem = dmg
						any = true
			c.phase = "damage"
			eng.add_log("combat_phase", "Fase di assegnazione dei danni", {"phase": "damage"})
			if not any:
				_enter_attack(eng)
		"damage":
			_enter_attack(eng)
		"attack":
			s.turn.pool.attack = {}
			c.phase = "end"

static func _alive(c: Dictionary) -> Array:
	var out: Array = []
	for e in c.enemies:
		if not e.defeated:
			out.append(e)
	return out

static func _enter_attack(eng) -> void:
	var s: Dictionary = eng.s
	var c: Dictionary = s.combat
	# summoned monsters leave, summoners return
	for e in c.enemies:
		if e.summoned and not e.defeated:
			e.defeated = true
			e["no_fame"] = true
		if e.hidden:
			e.hidden = false
	c.phase = "attack"
	eng.add_log("combat_phase", "Fase di attacco", {"phase": "attack"})
	MKSpecials.on_attack_phase(eng, int(s.turn.player))
	if _alive(c).is_empty():
		c.phase = "end"

static func _summon(eng) -> void:
	var s: Dictionary = eng.s
	var c: Dictionary = s.combat
	var add: Array = []
	for e in c.enemies:
		if e.defeated or e.summoned or not has_ab(e, "summon"):
			continue
		var col: String = str(MKDB.enemies.get(e.type, {}).get("summon", "brown"))
		var eid: String = eng.draw_enemy(col, true, "")
		if eid == "":
			continue
		var d: Dictionary = MKDB.enemies.get(str(s.enemies[eid].type), {})
		var ent := _entry(eng, eid, d, false, false, "")
		ent.summoned = true
		ent.by = e.eid
		add.append(ent)
		e.hidden = true
		c.summoned.append(eid)
		eng.add_log("summon", "%s evoca %s" % [e.name, ent.name], {"eid": e.eid, "summoned": eid})
	c.enemies.append_array(add)

static func assign_damage(eng, p: int, e: Dictionary, ai: int, to) -> void:
	var s: Dictionary = eng.s
	var c: Dictionary = s.combat
	var at: Dictionary = e.attacks[ai]
	var dmg := int(at.rem)
	var poison := has_ab(e, "poison")
	var paralyze := has_ab(e, "paralyze")
	var pl: Dictionary = eng.P(p)
	if str(to) == "hero":
		var arm: int = eng.armor_of(p)
		var dr = MKSpecials.get_mod(eng, "damage_reduction")
		if dr != null:
			MKSpecials.remove_mod(eng, dr)
			var ael0: String = attack_elem(e, ai)
			dmg = maxi(0, dmg - (int(dr.n_match) if ael0 in dr.get("match", []) else int(dr.n_other)))
		var w := int(ceil(float(dmg) / float(arm)))
		var ifw = MKSpecials.get_mod(eng, "ignore_first_wound")
		if ifw != null and w > 0:
			MKSpecials.remove_mod(eng, ifw)
			w -= 1
			poison = poison and w > 0
			paralyze = paralyze and w > 0
		at.rem = 0
		for i in w:
			eng.add_wound(p, true)
		if poison:
			for i in w:
				eng.add_wound(p, false)
		c.wounds_hand = int(c.wounds_hand) + w
		pl.wounds_this_combat = int(pl.wounds_this_combat) + w
		eng.add_log("wound", "%s subisce %d danni da %s: %d Ferit%s%s" % [eng.pname(p), dmg, e.name, w, "a" if w == 1 else "e",
			" (veleno: altrettante negli scarti)" if poison else ""], {"p": p, "n": w, "eid": e.eid, "poison": poison})
		if paralyze and w > 0:
			_discard_non_wounds(eng, p, "paralisi")
		if not pl.knocked_out and int(c.wounds_hand) >= eng.base_hand_limit(p):
			pl.knocked_out = true
			_discard_non_wounds(eng, p, "fuori combattimento")
			eng.add_log("knockout", "%s è fuori combattimento!" % eng.pname(p), {"p": p})
		return
	var u = eng.find_unit(p, to)
	var ud: Dictionary = eng.unit_def(u)
	var dc = MKSpecials.unit_rule(ud, "unit_damage_cost")
	if dc != null and not u.get("dmg_paid", false):
		eng.s.turn.pool.influence = int(eng.s.turn.pool.influence) - int(dc.get("influence", 2))
		u["dmg_paid"] = true
	var uarm := unit_armor(eng, p, u)
	var res := false
	var ures: Array = unit_resists(eng, p, u)
	var ael: String = attack_elem(e, ai)
	if ael == "cold":
		res = "fire" in ures and "ice" in ures
	else:
		res = ael in ures
	at.units_hit.append(int(u.uid))
	var wounded := false
	if res:
		dmg -= uarm
		if dmg > 0:
			wounded = true
			dmg -= uarm
		else:
			if not c.has("units_absorbed"):
				c["units_absorbed"] = []
			c.units_absorbed.append(int(u.uid))
	else:
		wounded = true
		dmg -= uarm
	at.rem = maxi(0, dmg)
	if wounded:
		if paralyze:
			eng.remove_unit(p, u)
			eng.add_log("unit_destroyed", "%s viene distrutta (paralisi)" % eng.unit_name(u), {"p": p, "uid": u.uid})
			return
		u.wounded = true
		u.wounds = 2 if poison else 1
		eng.add_log("unit_wound", "%s viene ferita%s" % [eng.unit_name(u), " due volte (veleno)" if poison else ""], {"p": p, "uid": u.uid})
	else:
		eng.add_log("unit_absorb", "%s assorbe il danno grazie alla resistenza" % eng.unit_name(u), {"p": p, "uid": u.uid})

static func unit_resists(eng, p: int, u: Dictionary) -> Array:
	var r: Array = eng.unit_def(u).get("resist", []).duplicate()
	if eng.flag(p, "units_all_resist"):
		r = ["phys", "fire", "ice"]
	var bn = eng.P(p).get("banners", {}).get(str(u.uid), null)
	if bn != null:
		for x in MKSpecials.banner_params(eng, bn).get("resist", []):
			if not x in r:
				r.append(x)
	for x in u.get("extra_resist", []):
		if not x in r:
			r.append(x)
	return r

static func unit_armor(eng, p: int, u: Dictionary) -> int:
	var a := int(eng.unit_def(u).get("armor", 1))
	for m in eng.mods_named("unit_armor"):
		a += int(m.get("n", 0))
	var bn = eng.P(p).get("banners", {}).get(str(u.uid), null)
	if bn != null:
		a += int(MKSpecials.banner_params(eng, bn).get("armor", 0))
	return a

static func _discard_non_wounds(eng, p: int, why: String) -> void:
	var pl: Dictionary = eng.P(p)
	var n := 0
	for iid in pl.hand.duplicate():
		if not eng.is_wound(iid):
			pl.hand.erase(iid)
			pl.discard.append(iid)
			n += 1
	if n > 0:
		eng.s.turn.discarded = int(eng.s.turn.get("discarded", 0)) + n
		eng.add_log("discard", "%s scarta %d carte (%s)" % [eng.pname(p), n, why], {"p": p, "n": n})

static func resolve(eng, pend: Dictionary, v) -> bool:
	return false

# ---------------------------------------------------------------- end of combat
static func finish(eng) -> void:
	var s: Dictionary = eng.s
	var c: Dictionary = s.combat
	var p: int = int(s.turn.player)
	var pl: Dictionary = eng.P(p)
	var defenders_all := true
	var any_def := false
	var all_def := true
	for e in c.enemies:
		if e.site_def:
			any_def = true
			if not e.defeated:
				defenders_all = false
		if not e.defeated and not e.summoned:
			all_def = false
	var site: String = c.site
	var h: Dictionary = eng.hex(site) if site != "" else {}
	for e in c.enemies:
		var eid: String = e.eid
		if not s.enemies.has(eid):
			continue
		if e.defeated or e.summoned:
			eng.discard_enemy(eid)
		elif c.kind in ["site", "burn"] and c.site_type in ["dungeon", "tomb", "monastery"]:
			eng.discard_enemy(eid)
		else:
			s.enemies[eid].face_up = true
			if c.kind == "site" and site != "" and not eid in h.get("enemies", []):
				h.enemies.append(eid)
				s.enemies[eid].hex = site
	# spawning grounds not cleared: every defeated monster is replaced by a new face-down brown token
	if c.kind == "site" and c.site_type == "spawning_grounds" and not all_def and not h.is_empty():
		var guard := 0
		while h.enemies.size() < 2 and guard < 4:
			guard += 1
			var ne: String = eng.draw_enemy("brown", false, site)
			if ne == "":
				break
			h.enemies.append(ne)
	var won := false
	match c.kind:
		"assault":
			if any_def and defenders_all or (not any_def and true):
				won = true
				MKSites.conquer(eng, p, site)
			else:
				if c.retreat != "":
					pl.pos = c.retreat
					s.turn.path.append(c.retreat)
					eng.add_log("retreat", "%s si ritira dopo l'assalto fallito" % eng.pname(p), {"p": p, "to": c.retreat})
		"site":
			if all_def:
				won = true
				MKSites.adventure_won(eng, p, site, c)
		"burn":
			if all_def:
				won = true
				MKSites.monastery_burned(eng, p, site)
	s.combat = null
	s.turn.pool.attack = {}
	s.turn.pool.block = {}
	for u in pl.units:
		u.erase("extra_resist")
	eng.add_log("combat_end", "Fine del combattimento%s" % (": vittoria!" if won or all_def else ""), {"p": p, "won": won or all_def, "fame": c.fame})
