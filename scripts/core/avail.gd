class_name MKAvail
extends RefCounted
## Enumerates every legal high-level action for eng.actor(), with Italian labels.

const SIDE_IT := {"move": "Movimento 1", "influence": "Influenza 1", "attack": "Attacco 1", "block": "Blocco 1"}

static func list(eng) -> Array:
	var s: Dictionary = eng.s
	var out: Array = []
	if s.phase == "game_over":
		return out
	if s.pending != null:
		for o in s.pending.options:
			out.append({"a": {"t": "choose", "v": [o.v]}, "label": str(o.get("label", str(o.v))), "group": "choice"})
		return out
	if s.phase == "tactics":
		for t in s.tactics_avail:
			var td: Dictionary = MKDB.tactics.get(t, {})
			out.append({"a": {"t": "tactic", "id": t}, "label": "Tattica %d: %s" % [eng.tactic_number(t), eng.tactic_name(t)], "group": "tactic"})
		return out
	var p: int = eng.actor()
	if p < 0 or s.phase != "turn" or s.turn.get("ending", false):
		return out
	var pl: Dictionary = eng.P(p)
	var t: Dictionary = s.turn
	var cb = s.combat
	# --- announce end of round
	if eng.check({"t": "announce_end"}) == "":
		out.append({"a": {"t": "announce_end"}, "label": "Annuncia la fine del round", "group": "turn"})
	# --- cards
	var seen := {}
	for iid in pl.hand:
		var cid: String = eng.card_id(iid)
		if seen.has(cid) or eng.is_wound(iid):
			continue
		seen[cid] = true
		var c: Dictionary = eng.card(iid)
		var nm: String = eng.card_name(iid)
		for mode in ["basic", "powered"]:
			var a := {"t": "play", "card": iid, "mode": mode}
			if eng.check(a) == "":
				var lbl := "Gioca %s" % nm
				if mode == "powered":
					lbl = "Gioca %s potenziata" % nm
					if c.get("type", "") == "spell" and c.get("name_powered_it", "") != "":
						lbl = "Gioca %s (%s)" % [nm, c.name_powered_it]
				var tx = c.get("text_it", {})
				if tx is Dictionary and tx.get(mode, "") != "":
					lbl += ": " + str(tx[mode])
				else:
					lbl += ": " + MKEffects.describe_list(c.get(mode, []))
				out.append({"a": a, "label": lbl, "group": "card"})
		if c.get("side", true):
			for side in ["move", "influence", "attack", "block"]:
				if side == "influence" and MKSites.can_interact(eng, p) != "" and not (cb != null and eng.flag(p, "influence_as_block")):
					continue
				if side == "move" and t.pool.move == 0 and false:
					continue
				var a2 := {"t": "play", "card": iid, "mode": "side", "side": side}
				if eng.check(a2) == "":
					out.append({"a": a2, "label": "Gioca %s di lato: %s" % [nm, SIDE_IT[side]], "group": "card"})
	# --- units
	for u in pl.units:
		var d: Dictionary = eng.unit_def(u)
		var abs: Array = d.get("abilities", [])
		for i in abs.size():
			var a3 := {"t": "unit", "uid": int(u.uid), "ability": i}
			if eng.check(a3) == "":
				var tx2: String = str(abs[i].get("text_it", ""))
				if tx2 == "":
					tx2 = MKEffects.describe_list(abs[i].get("effect", []))
				out.append({"a": a3, "label": "Attiva %s: %s" % [eng.unit_name(u), tx2], "group": "unit"})
	# --- skills
	for sk in pl.skills:
		var a4 := {"t": "skill", "id": sk.id}
		if eng.check(a4) == "":
			var sd: Dictionary = MKDB.skills.get(sk.id, {})
			out.append({"a": a4, "label": "Usa l'abilità %s" % str(sd.get("name_it", sk.id)), "group": "skill"})
	# --- special actions (from played effects)
	out.append_array(MKSpecials.actions(eng, p))
	# --- tactic activations
	for u2 in MKSites._tactic_uses(eng, p):
		out.append({"a": {"t": "tactic_use", "opt": u2.opt}, "label": u2.label, "group": "tactic"})
	if cb != null:
		_combat(eng, p, out)
		return out
	# --- healing
	if int(t.pool.heal) > 0:
		if eng.check({"t": "heal", "target": "hand"}) == "":
			out.append({"a": {"t": "heal", "target": "hand"}, "label": "Guarisci una Ferita dalla mano", "group": "heal"})
		for u in pl.units:
			var a5 := {"t": "heal", "target": int(u.uid)}
			if eng.check(a5) == "":
				out.append({"a": a5, "label": "Guarisci %s" % eng.unit_name(u), "group": "heal"})
	# --- movement / exploration
	if eng.can_still_move(p):
		for nk in MKHex.neighbors(pl.pos):
			var a6 := {"t": "move", "to": nk}
			if eng.check(a6) == "":
				out.append({"a": a6, "label": "Muovi in %s (%s) costo %d" % [nk, eng._hex_label(nk), eng.move_cost(nk)], "group": "move"})
		if int(t.pool.move) >= 2:
			for sl in eng.explorable_slots(p):
				out.append({"a": {"t": "explore", "slot": sl}, "label": "Esplora una nuova tessera (%s)" % sl, "group": "move"})
	# --- site actions
	_sites(eng, p, out)
	# --- optional discard (equivalent to discarding before drawing at end of turn)
	var seen_d := {}
	for iid in pl.hand:
		if eng.is_wound(iid) or seen_d.has(eng.card_id(iid)):
			continue
		seen_d[eng.card_id(iid)] = true
		out.append({"a": {"t": "discard", "card": iid}, "label": "Scarta %s (prima di pescare)" % eng.card_name(iid), "group": "discard"})
	# --- turn
	if eng.check({"t": "rest"}) == "":
		out.append({"a": {"t": "rest"}, "label": "Riposa", "group": "turn"})
	if eng.check({"t": "end_turn"}) == "":
		out.append({"a": {"t": "end_turn"}, "label": "Termina il turno", "group": "turn"})
	return out

static func _sites(eng, p: int, out: Array) -> void:
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	var h: Dictionary = eng.hex(pl.pos)
	for a in [{"t": "site"}, {"t": "altar"}, {"t": "burn"}, {"t": "plunder"}]:
		if eng.check(a) == "":
			var lbl := ""
			match a.t:
				"site":
					lbl = "Entra in %s" % eng.SITE_IT.get(h.site, h.site)
				"altar":
					lbl = "Offri mana all'altare delle rovine"
				"burn":
					lbl = "Brucia il monastero (Reputazione -3)"
				"plunder":
					lbl = "Saccheggia il villaggio (Reputazione -1, pesca 2 carte)"
			out.append({"a": a, "label": lbl, "group": "site"})
	# challenge rampaging enemies
	var ramp: Array = []
	for nk in MKHex.neighbors(pl.pos):
		var nh: Dictionary = eng.hex(nk)
		if not nh.is_empty() and nh.rampage and not nh.enemies.is_empty():
			ramp.append(nk)
	if not ramp.is_empty() and MKSites._action_free(eng, p) == "":
		for k in ramp:
			var names: Array = []
			for eid in eng.hex(k).enemies:
				names.append(eng.enemy_name(eid))
			out.append({"a": {"t": "challenge", "hexes": [k]}, "label": "Sfida %s" % ", ".join(names), "group": "site"})
		if ramp.size() > 1:
			out.append({"a": {"t": "challenge", "hexes": ramp}, "label": "Sfida tutti i nemici scatenati adiacenti", "group": "site"})
	if MKSites.can_interact(eng, p) == "":
		for id in s.offers.units:
			if not MKSites.unit_recruitable_here(eng, p, id):
				continue
			var ud: Dictionary = MKDB.units.get(id, {})
			var nm := str(ud.get("name_it", id))
			var a2 := {"t": "recruit", "id": id}
			if eng.check(a2) == "":
				out.append({"a": a2, "label": "Recluta %s (%d Influenza)" % [nm, MKSites.unit_cost(eng, p, id)], "group": "site"})
			elif eng.command_free(p) <= 0:
				for u in pl.units:
					var a3 := {"t": "recruit", "id": id, "disband": int(u.uid)}
					if eng.check(a3) == "":
						out.append({"a": a3, "label": "Recluta %s congedando %s" % [nm, eng.unit_name(u)], "group": "site"})
		for o in MKSites._buy_options(eng, p):
			var a4 := {"t": "buy", "what": o.what}
			if o.has("id"):
				a4["id"] = o.id
			if eng.check(a4) == "":
				out.append({"a": a4, "label": "%s (%d Influenza%s)" % [o.label, int(o.cost), (" + 1 mana " + MKMana.color_it(o.mana)) if o.get("mana", "") != "" else ""], "group": "site"})

static func _combat(eng, p: int, out: Array) -> void:
	var s: Dictionary = eng.s
	var c: Dictionary = s.combat
	var pl: Dictionary = eng.P(p)
	match c.phase:
		"ranged", "attack":
			var tg: Array = []
			for e in c.enemies:
				if MKCombat.targetable(eng, e):
					tg.append(e.eid)
			if not s.turn.pool.attack.is_empty() and not tg.is_empty():
				var n := tg.size()
				var lim := mini(n, 6)
				for mask in range(1, 1 << lim):
					var group: Array = []
					for i in lim:
						if mask & (1 << i):
							group.append(tg[i])
					var a := {"t": "attack", "targets": group}
					if MKCombat.check(eng, p, a) == "":
						var names: Array = []
						for eid in group:
							names.append(MKCombat.entry(eng, eid).name)
						out.append({"a": a, "label": "Attacca %s (attacco %d)" % [" + ".join(names), MKCombat.effective_attack(eng, group)], "group": "combat"})
		"block":
			for e in c.enemies:
				if e.defeated or e.hidden:
					continue
				for i in e.attacks.size():
					var a2 := {"t": "block", "eid": e.eid, "attack": i}
					if MKCombat.check(eng, p, a2) == "":
						out.append({"a": a2, "label": "Blocca %s (blocco %d contro %d)" % [e.name, MKCombat.effective_block(eng, e.eid, i), MKCombat.block_needed(eng, e, i)], "group": "combat"})
		"damage":
			for e in c.enemies:
				for i in e.attacks.size():
					if int(e.attacks[i].rem) <= 0:
						continue
					out.append({"a": {"t": "damage", "eid": e.eid, "attack": i, "to": "hero"},
						"label": "Assegna %d danni di %s all'eroe" % [int(e.attacks[i].rem), e.name], "group": "combat"})
					for u in pl.units:
						var a3 := {"t": "damage", "eid": e.eid, "attack": i, "to": int(u.uid)}
						if MKCombat.check(eng, p, a3) == "":
							out.append({"a": a3, "label": "Assegna i danni di %s a %s" % [e.name, eng.unit_name(u)], "group": "combat"})
	if MKCombat.check(eng, p, {"t": "next"}) == "":
		var nxt := {"ranged": "Passa alla fase di blocco", "block": "Passa all'assegnazione dei danni", "damage": "Passa alla fase di attacco", "attack": "Termina il combattimento"}
		out.append({"a": {"t": "next"}, "label": nxt.get(c.phase, "Avanti"), "group": "combat"})
