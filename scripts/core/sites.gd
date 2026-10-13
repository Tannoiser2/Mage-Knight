class_name MKSites
extends RefCounted
## Sites, interaction, rewards, conquest, level up and tactics.

const HEAL_COST := {"village": 3, "monastery": 2}

# ================================================================ helpers
static func here(eng, p: int) -> Dictionary:
	return eng.hex(eng.P(p).pos)

static func interaction_site(eng, p: int) -> String:
	## Returns the site type if p can interact with the inhabitants here, else "".
	var h := here(eng, p)
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

static func can_interact(eng, p: int) -> String:
	var s: Dictionary = eng.s
	if s.combat != null:
		return "Non durante il combattimento"
	var t: Dictionary = s.turn
	if t.rested:
		return "Hai riposato in questo turno"
	if t.acted and not t.interacted:
		return "Hai già compiuto la tua azione"
	if int(eng.P(p).rep) <= -7 and not eng.flag(p, "ignore_reputation"):
		return "Con Reputazione X non puoi interagire"
	if eng.wounds_only_lock(p):
		return "Hai solo Ferite in mano: devi riposare"
	if interaction_site(eng, p) == "":
		return "Qui non c'è nessuno con cui interagire"
	return ""

static func influence_bonus(eng, p: int) -> int:
	var b: int = eng.rep_bonus(p)
	var h := here(eng, p)
	if h.get("site", "") == "city" and h.has("city"):
		for x in h.city.get("shields", []):
			if int(x) == p:
				b += 1
	return b

static func influence_avail(eng, p: int) -> int:
	var t: Dictionary = eng.s.turn
	var v := int(t.pool.influence)
	if not t.rep_applied:
		v += influence_bonus(eng, p)
	return v

static func spend_influence(eng, p: int, n: int) -> void:
	var t: Dictionary = eng.s.turn
	if not t.rep_applied:
		t.rep_applied = true
		t.pool.influence = int(t.pool.influence) + influence_bonus(eng, p)
	t.pool.influence = int(t.pool.influence) - n
	t.acted = true
	t.interacted = true
	t.started = true
	t.pool.move = 0
	MKSpecials.on_interaction(eng, p)

static func city_color(eng, p: int) -> String:
	var h := here(eng, p)
	if h.get("site", "") == "city" and h.has("city"):
		return str(h.city.color)
	return ""

static func city_def(color: String) -> Dictionary:
	var cd: Dictionary = MKDB.cities.get(color, {})
	if cd.is_empty():
		for k in MKDB.cities:
			if MKDB.cities[k].get("color", "") == color:
				return MKDB.cities[k]
	return cd

static func unit_recruitable_here(eng, p: int, uid: String) -> bool:
	var site := interaction_site(eng, p)
	var ud: Dictionary = MKDB.units.get(uid, {})
	var rec: Array = ud.get("recruit", [])
	if site == "city":
		var col := city_color(eng, p)
		if col == "white":
			return true
		return "city" in rec
	return site in rec

# ================================================================ checks
static func check(eng, p: int, a: Dictionary) -> String:
	var s: Dictionary = eng.s
	var t: String = str(a.get("t", ""))
	var h := here(eng, p)
	match t:
		"recruit":
			var e := can_interact(eng, p)
			if e != "":
				return e
			var id := str(a.get("id", ""))
			if not id in s.offers.units:
				return "Unità non presente nell'offerta"
			if not unit_recruitable_here(eng, p, id):
				return "Questa unità non si recluta qui"
			var cost := unit_cost(eng, p, id)
			if influence_avail(eng, p) < cost:
				return "Influenza insufficiente (servono %d)" % cost
			if eng.command_free(p) <= 0:
				if a.get("disband", null) == null or eng.find_unit(p, a.disband) == null:
					return "Non hai Comando libero: indica un'unità da congedare"
			return ""
		"buy":
			var e2 := can_interact(eng, p)
			if e2 != "":
				return e2
			return _check_buy(eng, p, a)
		"plunder":
			if h.get("site", "") != "village":
				return "Puoi saccheggiare solo un villaggio"
			if s.combat != null or s.turn.get("plundered", false) or s.turn.get("started", false):
				return "Puoi saccheggiare solo all'inizio del turno, una volta"
			return ""
		"burn":
			if h.get("site", "") != "monastery" or h.burned:
				return "Non sei in un monastero"
			return _action_free(eng, p)
		"site":
			var e3 := _action_free(eng, p)
			if e3 != "":
				return e3
			var st: String = str(h.get("site", ""))
			if not st in eng.ADVENTURE_SITES:
				return "Qui non c'è un sito avventura"
			if st in ["monster_den", "spawning_grounds"] and h.conquered:
				return "Sito già conquistato"
			if st == "ruins":
				if str(h.get("ruins", "")) == "":
					return "Le rovine sono già state esplorate"
				var rd: Dictionary = MKDB.ruins.get(str(h.ruins), {})
				if rd.get("kind", "") == "altar":
					return "Questo è un altare: usa l'altare"
			return ""
		"altar":
			var e4 := _action_free(eng, p)
			if e4 != "":
				return e4
			if str(h.get("site", "")) != "ruins" or str(h.get("ruins", "")) == "":
				return "Non ci sono altari qui"
			var rd2: Dictionary = MKDB.ruins.get(str(h.ruins), {})
			if rd2.get("kind", "") != "altar":
				return "Queste rovine non hanno un altare"
			var needs: Array = altar_needs(rd2)
			if MKMana.plan(eng, p, needs, a.get("mana", null)) == null:
				var cols: Array = []
				for c in needs:
					cols.append(MKMana.color_it(c))
				return "Servono i mana: %s" % ", ".join(cols)
			return ""
		"challenge":
			var e5 := _action_free(eng, p)
			if e5 != "":
				return e5
			var hexes: Array = a.get("hexes", [])
			if hexes.is_empty():
				return "Scegli i nemici da sfidare"
			for k in hexes:
				var nh: Dictionary = eng.hex(str(k))
				if nh.is_empty() or not nh.rampage or nh.enemies.is_empty() or not MKHex.adjacent(str(k), eng.P(p).pos):
					return "Nessun nemico scatenato adiacente lì"
			return ""
		"disband":
			if eng.find_unit(p, a.get("uid", -1)) == null:
				return "Unità non trovata"
			return ""
	return "Azione sconosciuta: " + t

static func _action_free(eng, p: int) -> String:
	var s: Dictionary = eng.s
	if eng.wounds_only_lock(p):
		return "Hai solo Ferite in mano: devi riposare"
	if s.combat != null:
		return "Sei già in combattimento"
	if s.turn.acted:
		return "Hai già compiuto la tua azione in questo turno"
	if s.turn.rested:
		return "Hai riposato in questo turno"
	return ""

static func altar_needs(rd: Dictionary) -> Array:
	var ac = rd.get("altar_cost", null)
	if ac is Array and not ac.is_empty():
		return ac.duplicate()
	var col := _altar_color(rd)
	return [col, col, col]

static func _altar_color(rd: Dictionary) -> String:
	for k in ["altar_color", "color", "mana", "altar"]:
		var v = rd.get(k, null)
		if v is String and MKDB._color(v) in MKMana.BASIC:
			return MKDB._color(v)
	return "red"

static func unit_cost(eng, p: int, id: String) -> int:
	var c := int(MKDB.units.get(id, {}).get("cost", 0))
	for m in eng.mods_named("recruit_discount"):
		c -= int(m.get("n", 0))
	c -= MKSpecials.unit_cost_mod(eng, p, id)
	var rm = MKSpecials.unit_rule(MKDB.units.get(id, {}), "unit_rep_recruit_mult")
	if rm != null:
		c -= (int(rm.get("mult", 1)) - 1) * eng.rep_bonus(p)
	return maxi(0, c)

static func _buy_options(eng, p: int) -> Array:
	## [{what, id?, cost, mana?, label}]
	var s: Dictionary = eng.s
	var out: Array = []
	var site := interaction_site(eng, p)
	if site == "":
		return out
	if HEAL_COST.has(site):
		out.append({"what": "heal", "cost": HEAL_COST[site], "label": "Compra 1 punto Cura"})
	if site == "monastery":
		for id in s.offers.monastery:
			out.append({"what": "aa", "id": id, "cost": 6, "label": "Impara %s" % _cname(id)})
	var col := city_color(eng, p) if site == "city" else ""
	var cd := city_def(col) if col != "" else {}
	if site == "mage_tower" or col == "blue":
		for id in s.offers.spells:
			out.append({"what": "spell", "id": id, "cost": 7, "mana": str(MKDB.card(id).get("color", "")), "label": "Impara %s" % _cname(id)})
	if col == "red":
		out.append({"what": "artifact", "cost": int(cd.get("artifact_cost", 12)), "label": "Compra un Artefatto"})
	if col == "green":
		for id in s.offers.aa:
			out.append({"what": "aa_offer", "id": id, "cost": int(cd.get("aa_cost", 6)), "label": "Impara %s" % _cname(id)})
		if not s.decks.aa.is_empty():
			out.append({"what": "aa_top", "cost": int(cd.get("aa_cost", 6)), "label": "Azione avanzata a caso dal mazzo"})
	if col == "white" and not s.decks.units_elite.is_empty():
		out.append({"what": "elite", "cost": int(cd.get("elite_cost", 2)), "label": "Aggiungi un'unità d'élite all'offerta"})
	return out

static func _cname(id: String) -> String:
	var c: Dictionary = MKDB.card(id)
	return str(c.get("name_it", c.get("name_en", id)))

static func _check_buy(eng, p: int, a: Dictionary) -> String:
	var what := str(a.get("what", ""))
	var id := str(a.get("id", ""))
	for o in _buy_options(eng, p):
		if o.what == what and (not o.has("id") or o.id == id):
			if influence_avail(eng, p) < int(o.cost):
				return "Influenza insufficiente (servono %d)" % int(o.cost)
			if what == "heal" and not _has_healable(eng, p):
				return "Non hai ferite da guarire"
			if o.get("mana", "") != "":
				if MKMana.plan(eng, p, [o.mana], a.get("mana", null)) == null:
					return "Serve 1 mana %s" % MKMana.color_it(o.mana)
			return ""
	return "Non puoi comprarlo qui"

static func _has_healable(eng, p: int) -> bool:
	for iid in eng.P(p).hand:
		if eng.is_wound(iid):
			return true
	for u in eng.P(p).units:
		if u.wounded:
			return true
	return false

# ================================================================ actions
static func do(eng, p: int, a: Dictionary) -> void:
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	var h := here(eng, p)
	match str(a.t):
		"recruit":
			var id := str(a.id)
			spend_influence(eng, p, unit_cost(eng, p, id))
			if eng.command_free(p) <= 0:
				var old = eng.find_unit(p, a.disband)
				eng.add_log("disband", "%s congeda %s" % [eng.pname(p), eng.unit_name(old)], {"p": p, "uid": old.uid})
				eng.remove_unit(p, old)
			s.offers.units.erase(id)
			gain_unit(eng, p, id)
			_unit_recruit_effects(eng, p, id)
			MKSpecials.on_recruit(eng, p, id)
		"buy":
			_do_buy(eng, p, a)
		"plunder":
			s.turn.plundered = true
			eng.change_rep(p, -1)
			eng.add_log("plunder", "%s saccheggia il villaggio" % eng.pname(p), {"p": p})
			eng.draw(p, 2)
		"burn":
			eng.change_rep(p, -3)
			var eid: String = eng.draw_enemy("violet", true, "")
			eng.add_log("burn", "%s tenta di bruciare il monastero" % eng.pname(p), {"p": p})
			MKCombat.start(eng, [eid] if eid != "" else [], {"site": pl.pos, "kind": "burn", "site_type": "monastery", "defenders": [eid], "units_allowed": false})
		"site":
			_enter_adventure(eng, p)
		"altar":
			var rd: Dictionary = MKDB.ruins.get(str(h.ruins), {})
			var needs: Array = altar_needs(rd)
			var plan = MKMana.plan(eng, p, needs, a.get("mana", null))
			MKMana.pay(eng, p, plan, needs)
			s.turn.acted = true
			s.turn.started = true
			eng.add_log("altar", "%s offre %d mana all'altare" % [eng.pname(p), needs.size()], {"p": p})
			eng.gain_fame(p, int(rd.get("fame", 7)))
			_bag_discard_ruin(eng, str(h.ruins))
			h.ruins = ""
			h.conquered = true
			_shield(eng, p, pl.pos)
		"challenge":
			var eids: Array = []
			for k in a.hexes:
				for eid in eng.hex(str(k)).enemies:
					eids.append(eid)
			eng.add_log("challenge", "%s sfida i nemici scatenati" % eng.pname(p), {"p": p, "enemies": eids})
			MKCombat.start(eng, eids, {"kind": "challenge"})
		"disband":
			var u = eng.find_unit(p, a.uid)
			eng.remove_unit(p, u)
			eng.add_log("disband", "%s congeda %s" % [eng.pname(p), eng.unit_name(u)], {"p": p})

static func gain_unit(eng, p: int, id: String) -> void:
	var s: Dictionary = eng.s
	s.uid_seq = int(s.uid_seq) + 1
	eng.P(p).units.append({"uid": int(s.uid_seq), "id": id, "ready": true, "wounded": false, "wounds": 0})
	var ud: Dictionary = MKDB.units.get(id, {})
	eng.add_log("recruit", "%s recluta %s" % [eng.pname(p), str(ud.get("name_it", id))], {"p": p, "unit": id, "uid": s.uid_seq})

static func _unit_recruit_effects(eng, p: int, id: String) -> void:
	var ud: Dictionary = MKDB.units.get(id, {})
	var eff = ud.get("on_recruit", [])
	if eff is Array and not eff.is_empty():
		MKEffects.start(eng, eff, {"p": p, "kind": "recruit", "src": "unit:" + id})

static func _do_buy(eng, p: int, a: Dictionary) -> void:
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	var what := str(a.what)
	var id := str(a.get("id", ""))
	var opt := {}
	for o in _buy_options(eng, p):
		if o.what == what and (not o.has("id") or o.id == id):
			opt = o
			break
	spend_influence(eng, p, int(opt.cost))
	if opt.get("mana", "") != "":
		var plan = MKMana.plan(eng, p, [opt.mana], a.get("mana", null))
		MKMana.pay(eng, p, plan, [opt.mana])
	match what:
		"heal":
			s.turn.pool.heal = int(s.turn.pool.heal) + 1
			eng.add_log("buy", "%s compra 1 punto Cura" % eng.pname(p), {"p": p})
			eng.auto_heal(p)
		"aa":
			s.offers.monastery.erase(id)
			gain_card_top(eng, p, id)
		"spell":
			s.offers.spells.erase(id)
			eng._refill_offer("spells")
			gain_card_top(eng, p, id)
		"aa_offer":
			s.offers.aa.erase(id)
			eng._refill_offer("aa")
			gain_card_top(eng, p, id)
		"aa_top":
			gain_card_top(eng, p, s.decks.aa.pop_front())
		"artifact":
			s.turn.rewards.append({"k": "artifact"})
			eng.add_log("buy", "%s compra un Artefatto (alla fine del turno)" % eng.pname(p), {"p": p})
		"elite":
			s.offers.units.append(s.decks.units_elite.pop_front())
			eng.add_log("buy", "%s aggiunge un'unità d'élite all'offerta" % eng.pname(p), {"p": p})

static func gain_card_top(eng, p: int, id: String) -> void:
	var iid: String = eng.new_iid(id)
	eng.P(p).deck.push_front(iid)
	eng.add_log("gain_card", "%s ottiene %s (in cima al mazzo)" % [eng.pname(p), _cname(id)], {"p": p, "card": iid})

static func _bag_discard_ruin(eng, rid: String) -> void:
	var bag: Dictionary = eng.s.enemy_bags.get("ruins", {})
	if not bag.is_empty() and rid != "":
		bag.discard.append(rid)

static func _shield(eng, p: int, k: String) -> void:
	var pl: Dictionary = eng.P(p)
	if not k in pl.shields:
		pl.shields.append(k)

static func _enter_adventure(eng, p: int) -> void:
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	var k: String = pl.pos
	var h := here(eng, p)
	var st: String = h.site
	var eids: Array = []
	var first: bool = not h.conquered
	match st:
		"dungeon":
			var e1: String = eng.draw_enemy("brown", true, "")
			if e1 != "":
				eids.append(e1)
		"tomb":
			var e2: String = eng.draw_enemy("red", true, "")
			if e2 != "":
				eids.append(e2)
		"monster_den":
			if h.enemies.is_empty():
				_garrison_adv(eng, k, ["brown"])
			eids = h.enemies.duplicate()
		"spawning_grounds":
			if h.enemies.is_empty():
				_garrison_adv(eng, k, ["brown", "brown"])
			eids = h.enemies.duplicate()
		"ruins":
			h["ruins_face_up"] = true
			if h.enemies.is_empty():
				var rd: Dictionary = MKDB.ruins.get(str(h.ruins), {})
				_garrison_adv(eng, k, rd.get("enemies", []))
			eids = h.enemies.duplicate()
	eng.add_log("enter_site", "%s entra in %s" % [eng.pname(p), eng.SITE_IT.get(st, st)], {"p": p, "hex": k})
	MKCombat.start(eng, eids, {"site": k, "kind": "site", "site_type": st, "defenders": eids, "first_time": first,
		"ruins": str(h.get("ruins", ""))})

static func _garrison_adv(eng, k: String, colors: Array) -> void:
	var h: Dictionary = eng.hex(k)
	for c in colors:
		var eid: String = eng.draw_enemy(str(c), true, k)
		if eid != "":
			h.enemies.append(eid)

# ================================================================ combat outcomes
static func conquer(eng, p: int, k: String) -> void:
	var h: Dictionary = eng.hex(k)
	if h.is_empty():
		return
	match str(h.site):
		"keep":
			h.conquered = true
			var prev := int(h.owner)
			h.owner = p
			if prev >= 0 and prev != p:
				eng.P(prev).shields.erase(k)
			_shield(eng, p, k)
			eng.add_log("conquer", "%s conquista il castello" % eng.pname(p), {"p": p, "hex": k})
		"mage_tower":
			h.conquered = true
			h.owner = p
			_shield(eng, p, k)
			eng.s.turn.rewards.append({"k": "spell"})
			eng.add_log("conquer", "%s conquista la torre della magia" % eng.pname(p), {"p": p, "hex": k})
		"city":
			h.conquered = true
			var counts := {}
			var first := {}
			var shields: Array = h.city.get("shields", [])
			for i in shields.size():
				var x := int(shields[i])
				counts[x] = int(counts.get(x, 0)) + 1
				if not first.has(x):
					first[x] = i
			var best := p
			var bc := -1
			for x in counts:
				if int(counts[x]) > bc or (int(counts[x]) == bc and int(first[x]) < int(first[best])):
					best = x
					bc = int(counts[x])
			h.city.leader = best
			h.owner = best
			eng.add_log("conquer", "%s conquista la città %s" % [eng.pname(p), MKMana.color_it(str(h.city.color))], {"p": p, "hex": k, "leader": best})

static func adventure_won(eng, p: int, k: String, c: Dictionary) -> void:
	var h: Dictionary = eng.hex(k)
	var st: String = h.site
	var first: bool = not h.conquered
	var rw: Array = eng.s.turn.rewards
	match st:
		"dungeon":
			if first:
				rw.append({"k": "dungeon_roll"})
		"tomb":
			if first:
				rw.append({"k": "spell"})
				rw.append({"k": "artifact"})
		"monster_den":
			rw.append({"k": "crystal_roll", "n": 2})
		"spawning_grounds":
			rw.append({"k": "artifact"})
			rw.append({"k": "crystal_roll", "n": 3})
		"ruins":
			var rd: Dictionary = MKDB.ruins.get(str(h.get("ruins", "")), {})
			for r in rd.get("reward", []):
				for x in _norm_reward(r):
					rw.append(x)
			_bag_discard_ruin(eng, str(h.get("ruins", "")))
			h.ruins = ""
	if first:
		h.conquered = true
		_shield(eng, p, k)
	eng.add_log("conquer", "%s conquista %s" % [eng.pname(p), eng.SITE_IT.get(st, st)], {"p": p, "hex": k})

static func _norm_reward(r) -> Array:
	if r is Dictionary:
		if r.has("fame") and not r.has("k"):
			return [{"k": "fame", "n": int(r.fame)}]
		var k := str(r.get("k", r.get("type", r.get("kind", ""))))
		var n := int(r.get("n", r.get("count", 1)))
		var out: Array = []
		match k:
			"crystal_roll", "crystals_roll":
				out.append({"k": "crystal_roll", "n": n})
			"crystals", "crystal":
				if r.has("colors"):
					out.append({"k": "crystals", "colors": r.colors})
				else:
					out.append({"k": "crystals4"})
			"fame":
				out.append({"k": "fame", "n": n})
			_:
				for i in n:
					out.append({"k": k})
		return out
	var sv := str(r).to_lower()
	match sv:
		"artifact", "artefatto":
			return [{"k": "artifact"}]
		"spell", "incantesimo":
			return [{"k": "spell"}]
		"aa", "advanced_action", "azione_avanzata":
			return [{"k": "aa"}]
		"unit", "unità", "unita":
			return [{"k": "unit"}]
		"crystals", "crystals4", "4crystals", "crystal_set", "cristalli", "crystals_all":
			return [{"k": "crystals4"}]
	if sv.begins_with("fame"):
		return [{"k": "fame", "n": int(sv.substr(4).strip_edges().trim_prefix(":"))}]
	return [{"k": sv}]

static func monastery_burned(eng, p: int, k: String) -> void:
	var h: Dictionary = eng.hex(k)
	h.burned = true
	h.conquered = true
	_shield(eng, p, k)
	eng.s.turn.rewards.append({"k": "artifact"})
	# remove the monastery AA from the unit offer
	if not eng.s.offers.monastery.is_empty():
		eng.s.decks.aa.append(eng.s.offers.monastery.pop_back())
	eng.add_log("conquer", "%s brucia il monastero" % eng.pname(p), {"p": p, "hex": k})

# ================================================================ rewards
static func give_reward(eng, p: int, r: Dictionary) -> void:
	var s: Dictionary = eng.s
	match str(r.get("k", "")):
		"spell":
			_offer_pick(eng, p, "spells", "reward_spell", "Ricompensa: scegli un Incantesimo")
		"aa":
			_offer_pick(eng, p, "aa", "reward_aa", "Ricompensa: scegli un'Azione avanzata")
		"artifact":
			var n := int(r.get("n", 1))
			var drawn: Array = []
			for i in n + 1:
				if not s.decks.artifacts.is_empty():
					drawn.append(s.decks.artifacts.pop_front())
			if drawn.is_empty():
				return
			if drawn.size() <= n:
				for id in drawn:
					gain_card_top(eng, p, id)
				return
			var opts: Array = []
			for id in drawn:
				opts.append({"v": id, "label": _cname(id), "img": str(MKDB.card(id).get("img", ""))})
			eng.ask(p, "offer", "reward_artifact", "Ricompensa: scegli l'Artefatto da tenere", opts, {"drawn": drawn, "keep": n})
		"unit":
			var opts2: Array = []
			for id in s.offers.units:
				var ud: Dictionary = MKDB.units.get(id, {})
				opts2.append({"v": id, "label": str(ud.get("name_it", id)), "img": str(ud.get("img", ""))})
			if opts2.is_empty():
				return
			opts2.append({"v": "", "label": "Rinuncia"})
			eng.ask(p, "offer", "reward_unit", "Ricompensa: scegli un'Unità dall'offerta", opts2)
		"crystal_roll":
			var n2 := int(r.get("n", 1))
			for i in n2:
				var col: String = eng.DIE_COLORS[MKRng.rand_int(s, 6)]
				if col == "black":
					eng.add_log("roll", "Dado: nero → +1 Fama", {"p": p})
					eng.gain_fame(p, 1)
				elif col == "gold":
					s.turn.rewards.push_front({"k": "crystal_choice"})
					eng.add_log("roll", "Dado: oro → scegli il colore", {"p": p})
				else:
					eng.add_log("roll", "Dado: %s" % MKMana.color_it(col), {"p": p})
					eng.gain_crystal(p, col)
		"crystal_choice":
			var o3: Array = []
			for c in MKMana.BASIC:
				o3.append({"v": c, "label": "Cristallo " + MKMana.color_it(c)})
			eng.ask(p, "color", "reward_crystal", "Scegli il colore del cristallo", o3)
		"crystals4":
			for c in MKMana.BASIC:
				eng.gain_crystal(p, c)
		"crystals":
			for c in r.get("colors", []):
				eng.gain_crystal(p, MKDB._color(c))
		"fame":
			eng.gain_fame(p, int(r.get("n", 0)))
		"dungeon_roll":
			var col2: String = eng.DIE_COLORS[MKRng.rand_int(s, 6)]
			eng.add_log("roll", "Dado del sotterraneo: %s" % MKMana.color_it(col2), {"p": p})
			# site card: gold or black = Spell, otherwise Artifact
			if col2 in ["gold", "black"]:
				s.turn.rewards.push_front({"k": "spell"})
			else:
				s.turn.rewards.push_front({"k": "artifact"})
		"aa_lowest":
			if not s.offers.aa.is_empty():
				var id2: String = s.offers.aa.pop_back()
				eng._refill_offer("aa")
				gain_card_top(eng, p, id2)

static func _offer_pick(eng, p: int, kind: String, handler: String, prompt: String) -> void:
	var off: Array = eng.s.offers[kind]
	if off.is_empty():
		return
	var opts: Array = []
	var seen := {}
	for id in off:
		if seen.has(id):
			continue
		seen[id] = true
		opts.append({"v": id, "label": _cname(id), "img": str(MKDB.card(id).get("img", ""))})
	eng.ask(p, "offer", handler, prompt, opts)

# ================================================================ level up
static func level_up_skill(eng, p: int) -> void:
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	var drawn: Array = []
	for i in 2:
		if not pl.skill_pile.is_empty():
			drawn.append(pl.skill_pile.pop_front())
	if s.dummy != null and s.dummy.get("skill_pile", []).size() > 0:
		s.offers.skills.append(s.dummy.skill_pile.pop_front())
	var opts: Array = []
	for id in drawn:
		opts.append({"v": "own:" + id, "label": _skill_label(id)})
	for id in s.offers.skills:
		opts.append({"v": "common:" + id, "label": _skill_label(id) + " (offerta comune, prendi l'ultima Azione avanzata)"})
	if opts.is_empty():
		_offer_pick(eng, p, "aa", "level_aa", "Salita di livello: scegli un'Azione avanzata")
		return
	eng.ask(p, "skill", "level_skill", "Salita di livello: scegli un'Abilità", opts, {"drawn": drawn})

static func _skill_label(id: String) -> String:
	var d: Dictionary = MKDB.skills.get(id, {})
	return str(d.get("name_it", d.get("name_en", id)))

static func add_skill(eng, p: int, id: String) -> void:
	eng.P(p).skills.append({"id": id, "used_round": false, "used_turn": false, "flipped": false})
	eng.add_log("skill_gain", "%s ottiene l'abilità %s" % [eng.pname(p), _skill_label(id)], {"p": p, "skill": id})
	var d: Dictionary = MKDB.skills.get(id, {})
	if d.get("usage", "") == "passive":
		var eff: Array = d.get("effect", [])
		if not eff.is_empty():
			MKEffects.start(eng, eff, {"p": p, "kind": "skill_passive", "src": "skill:" + id})

# ================================================================ pending resolution
static func resolve(eng, pend: Dictionary, v) -> bool:
	var s: Dictionary = eng.s
	var p: int = int(pend.player)
	var data: Dictionary = pend.get("data", {})
	match str(pend.handler):
		"reward_spell", "reward_aa", "level_aa":
			var kind := "spells" if pend.handler == "reward_spell" else "aa"
			s.offers[kind].erase(str(v))
			eng._refill_offer(kind)
			gain_card_top(eng, p, str(v))
		"reward_artifact":
			var drawn: Array = data.get("drawn", [])
			drawn.erase(str(v))
			gain_card_top(eng, p, str(v))
			for id in drawn:
				s.decks.artifacts.append(id)
		"reward_unit":
			if str(v) == "":
				return true
			if eng.command_free(p) <= 0:
				var opts: Array = []
				for u in eng.P(p).units:
					opts.append({"v": int(u.uid), "label": "Congeda " + eng.unit_name(u)})
				opts.append({"v": -1, "label": "Rinuncia alla nuova unità"})
				eng.ask(p, "unit", "reward_unit_disband", "Comando pieno: congeda un'unità", opts, {"id": str(v)})
				return true
			s.offers.units.erase(str(v))
			gain_unit(eng, p, str(v))
		"reward_unit_disband":
			if int(v) == -1:
				return true
			var u = eng.find_unit(p, v)
			eng.remove_unit(p, u)
			s.offers.units.erase(str(data.id))
			gain_unit(eng, p, str(data.id))
		"reward_crystal", "mine":
			eng.gain_crystal(p, str(v))
		"level_skill":
			var sv := str(v)
			var drawn2: Array = data.get("drawn", [])
			if sv.begins_with("own:"):
				var id := sv.substr(4)
				drawn2.erase(id)
				add_skill(eng, p, id)
				for x in drawn2:
					s.offers.skills.append(x)
				if s.pending == null:
					_offer_pick(eng, p, "aa", "level_aa", "Salita di livello: scegli un'Azione avanzata")
				else:
					s.turn.rewards.push_front({"k": "aa"})
			else:
				var id2 := sv.substr(7)
				s.offers.skills.erase(id2)
				add_skill(eng, p, id2)
				for x in drawn2:
					s.offers.skills.append(x)
				if s.pending == null:
					give_reward(eng, p, {"k": "aa_lowest"})
				else:
					s.turn.rewards.push_front({"k": "aa_lowest"})
		"tactic_rethink", "tactic_meditation":
			_resolve_cycle(eng, pend, v)
		"tactic_preparation":
			var pl: Dictionary = eng.P(p)
			pl.deck.erase(str(v))
			pl.hand.append(str(v))
			MKRng.shuffle(s, pl.deck)
			eng.add_log("tactic", "%s prende una carta dal mazzo (Preparazione)" % eng.pname(p), {"p": p})
		"tactic_steal":
			if int(v) == -1:
				return true
			var i := int(v)
			var d: Dictionary = s.source[i]
			eng.P(p).stolen_die = d.color
			s.source.remove_at(i)
			eng.add_log("tactic", "%s ruba un dado %s dalla Riserva" % [eng.pname(p), MKMana.color_it(d.color)], {"p": p})
		"tactic_search":
			if int(v) == -1:
				return true
			var j := int(v)
			s.source[j].color = eng.DIE_COLORS[MKRng.rand_int(s, 6)]
			eng.add_log("tactic", "Rilancia un dado: ora è %s" % MKMana.color_it(s.source[j].color), {"p": p})
			var left := int(data.get("left", 1)) - 1
			if left > 0:
				_ask_search(eng, p, left)
		"tactic_sparing":
			var pl2: Dictionary = eng.P(p)
			if str(v) == "store":
				pl2.tactic_store.append(pl2.deck.pop_front())
				eng.add_log("tactic", "%s mette da parte una carta (Risparmiare Potere)" % eng.pname(p), {"p": p})
			else:
				pl2.hand.append_array(pl2.tactic_store)
				pl2.tactic_store = []
				pl2.tactic_used = true
				eng.add_log("tactic", "%s prende le carte messe da parte" % eng.pname(p), {"p": p})
			s.turn["sparing_done"] = true
		_:
			return false
	return true

# ================================================================ tactics
static func take_tactic(eng, p: int, id: String) -> void:
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	pl.tactic = id
	s.tactics_avail.erase(id)
	eng.add_log("tactic", "%s sceglie la tattica %s" % [eng.pname(p), eng.tactic_name(id)], {"p": p, "tactic": id})
	if not s.tactic_pick.is_empty() and s.tactic_pick[0] == p:
		s.tactic_pick.pop_front()
	match eng.tactic_key(id):
		"d2":
			_ask_cycle(eng, p, "tactic_rethink", 3, [])
		"d3":
			var opts: Array = []
			for i in s.source.size():
				var d: Dictionary = s.source[i]
				if d.color in MKMana.BASIC and int(d.taken_by) == -1:
					opts.append({"v": i, "label": "Dado " + MKMana.color_it(d.color)})
			if not opts.is_empty():
				opts.append({"v": -1, "label": "Nessuno"})
				eng.ask(p, "die", "tactic_steal", "Rubare Mana: scegli un dado da tenere", opts)
		"d5":
			eng.draw(p, 2)
		"n5":
			var opts2: Array = []
			var seen := {}
			for iid in pl.deck:
				var cid: String = eng.card_id(iid)
				if seen.has(cid):
					continue
				seen[cid] = true
				opts2.append({"v": iid, "label": eng.card_name(iid)})
			if not opts2.is_empty():
				eng.ask(p, "card", "tactic_preparation", "Preparazione: scegli una carta dal mazzo", opts2)
		_:
			var td: Dictionary = MKDB.tactics.get(id, {})
			var eff: Array = td.get("on_take", [])
			if not eff.is_empty():
				MKEffects.start(eng, eff, {"p": p, "kind": "tactic", "src": "tactic:" + id})

static func _ask_cycle(eng, p: int, handler: String, left: int, chosen: Array) -> void:
	var pl: Dictionary = eng.P(p)
	var opts: Array = [{"v": "done", "label": "Fine" if not chosen.is_empty() else "Nessuna carta"}]
	var seen := {}
	for iid in pl.hand:
		var cid: String = eng.card_id(iid)
		if seen.has(cid) or iid in chosen:
			continue
		if handler == "tactic_meditation" and false:
			continue
		seen[cid] = true
		opts.append({"v": iid, "label": ("Scarta " if handler == "tactic_rethink" else "Rimescola ") + eng.card_name(iid)})
	var prompt := "Ripensamento: scegli fino a %d carte da scartare" % left if handler == "tactic_rethink" else "Meditazione di Mezzanotte: scegli fino a %d carte da rimescolare nel mazzo" % left
	eng.ask(p, "card", handler, prompt, opts, {"left": left, "chosen": chosen})

static func _resolve_cycle(eng, pend: Dictionary, v) -> void:
	var s: Dictionary = eng.s
	var p: int = int(pend.player)
	var pl: Dictionary = eng.P(p)
	var data: Dictionary = pend.data
	var chosen: Array = data.get("chosen", [])
	if str(v) != "done":
		chosen.append(str(v))
		var left := int(data.left) - 1
		if left > 0 and pl.hand.size() > chosen.size():
			_ask_cycle(eng, p, pend.handler, left, chosen)
			return
	if chosen.is_empty():
		return
	for iid in chosen:
		pl.hand.erase(iid)
	if pend.handler == "tactic_rethink":
		pl.discard.append_array(chosen)
		eng.draw(p, chosen.size())
		pl.deck.append_array(pl.discard)
		pl.discard = []
		MKRng.shuffle(s, pl.deck)
		eng.add_log("tactic", "%s scarta %d carte, ne pesca altrettante e rimescola gli scarti nel mazzo (Ripensamento)" % [eng.pname(p), chosen.size()], {"p": p})
		return
	else:
		pl.deck.append_array(chosen)
		MKRng.shuffle(s, pl.deck)
		pl.tactic_used = true
		eng.add_log("tactic", "%s rimescola %d carte nel mazzo (Meditazione di Mezzanotte)" % [eng.pname(p), chosen.size()], {"p": p})
	eng.draw(p, chosen.size())

static func _tactic_uses(eng, p: int) -> Array:
	## list of available tactic activations: [{opt, label}]
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	var out: Array = []
	if pl.tactic == "" or s.phase != "turn" or s.pending != null or s.turn.get("ending", false):
		return out
	var t: Dictionary = s.turn
	match eng.tactic_key(pl.tactic):
		"d6":
			if not pl.tactic_used and s.announced_by == -1 and not s.game_end_pending:
				out.append({"opt": "right_moment", "label": "Il Momento Giusto: gioca un altro turno dopo questo"})
		"n2":
			if not pl.tactic_used and pl.deck.is_empty() and not pl.discard.is_empty():
				out.append({"opt": "long_night", "label": "Una Lunga Notte: rimescola 3 carte degli scarti nel mazzo"})
		"n3":
			if not t.get("search_used", false) and int(t.dice_taken) == 0 and s.combat == null:
				out.append({"opt": "mana_search", "label": "Cercare Mana: rilancia fino a 2 dadi della Riserva"})
		"n4":
			if not pl.tactic_used and not t.started and not pl.hand.is_empty():
				out.append({"opt": "meditation", "label": "Meditazione di Mezzanotte: rimescola fino a 5 carte e ripesca"})
		"n6":
			if not pl.tactic_used and not t.get("sparing_done", false) and s.combat == null:
				if not pl.deck.is_empty():
					out.append({"opt": "store", "label": "Risparmiare Potere: metti da parte la prima carta del mazzo"})
				if not pl.tactic_store.is_empty():
					out.append({"opt": "take", "label": "Risparmiare Potere: prendi in mano le %d carte messe da parte" % pl.tactic_store.size()})
	return out

static func check_tactic_use(eng, p: int, a: Dictionary) -> String:
	var opt := str(a.get("opt", ""))
	for u in _tactic_uses(eng, p):
		if u.opt == opt:
			return ""
	return "Tattica non utilizzabile ora"

static func do_tactic_use(eng, p: int, a: Dictionary) -> void:
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	match str(a.opt):
		"right_moment":
			pl.tactic_used = true
			s.turn.extra_turn = true
			eng.add_log("tactic", "%s userà Il Momento Giusto" % eng.pname(p), {"p": p})
		"long_night":
			long_night(eng, p)
		"mana_search":
			s.turn["search_used"] = true
			_ask_search(eng, p, 2)
		"meditation":
			_ask_cycle(eng, p, "tactic_meditation", 5, [])
		"store", "take":
			resolve(eng, {"player": p, "handler": "tactic_sparing", "data": {}}, a.opt)

static func _ask_search(eng, p: int, left: int) -> void:
	var s: Dictionary = eng.s
	var opts: Array = [{"v": -1, "label": "Basta così"}]
	for i in s.source.size():
		var d: Dictionary = s.source[i]
		if int(d.taken_by) == -1:
			opts.append({"v": i, "label": "Rilancia il dado %s" % MKMana.color_it(d.color)})
	eng.ask(p, "die", "tactic_search", "Cercare Mana: scegli un dado da rilanciare", opts, {"left": left})

static func long_night(eng, p: int) -> void:
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	pl.tactic_used = true
	MKRng.shuffle(s, pl.discard)
	for i in 3:
		if pl.discard.is_empty():
			break
		pl.deck.append(pl.discard.pop_front())
	eng.add_log("tactic", "%s usa Una Lunga Notte" % eng.pname(p), {"p": p})
