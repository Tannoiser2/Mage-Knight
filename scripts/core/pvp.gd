class_name MKPvP
extends RefCounted
## Combattimento Giocatore contro Giocatore (Regolamento p. 12–13) e regole collegate
## (gettone Ordine di Round a faccia in giù = salta il prossimo turno, spazi condivisi).
##
## Stato: s.pvp = null oppure
##   {att, def, mode:"full"|"partial"|"", phase:"ranged"|"melee", step:"mode"|"attack"|"block"|"hit"|"after",
##    striker, passes, strike:{n, elems, by}|null, dmg, saved: turno (dizionario s.turn) del giocatore che NON
##    sta agendo, from: spazio da cui l'aggressore ha attaccato, hex, fort, result, winner}
## Durante il combattimento s.turn è il turno di chi agisce (l'attaccante o colui che blocca): le carte
## giocate finiscono nel pool del proprio turno. s.combat = {kind:"pvp", phase:"ranged"|"block"|"attack", enemies:[]}.
## Azioni: {t:"pvp_attack"} (aggressore), {t:"pvp", op:"strike"|"pass"|"block"}; decisioni "pvp:mode", "pvp:hit".

const SHAREABLE := ["portal"]

static func enabled(eng) -> bool:
	var s: Dictionary = eng.s
	if not eng.is_competitive() or s.players.size() < 2:
		return false
	var def: bool = str(s.scn.get("id", "")) != "first_recon"
	return bool(s.cfg.get("options", {}).get("pvp", def))

## Spazio in cui possono stare più eroi (e dove non si combatte mai tra giocatori).
static func shareable(eng, k: String) -> bool:
	var h: Dictionary = eng.hex(k)
	if h.is_empty():
		return false
	return str(h.get("site", "")) in SHAREABLE or (str(h.get("site", "")) == "city" and h.get("conquered", false))

static func other_here(eng, p: int) -> int:
	if p < 0 or p >= eng.s.players.size():
		return -1
	var pos: String = str(eng.P(p).pos)
	for j in eng.s.players.size():
		if j != p and str(eng.P(j).pos) == pos:
			return j
	return -1

## true se p condivide uno spazio non condivisibile con un altro eroe (nessun'altra azione consentita).
static func crowded(eng, p: int) -> bool:
	var j := other_here(eng, p)
	return j >= 0 and not shareable(eng, str(eng.P(p).pos))

static func flipped(eng, j: int) -> bool:
	return bool(eng.P(j).get("skip_next", false))

static func active(eng) -> bool:
	return eng.s.get("pvp", null) != null

# ================================================================ checks
static func check_attack(eng, p: int) -> String:
	var s: Dictionary = eng.s
	if not enabled(eng):
		return "Il combattimento tra giocatori non è consentito in questa partita"
	if s.combat != null or active(eng) or s.get("coop", null) != null:
		return "Sei già in combattimento"
	var t: Dictionary = s.turn
	if int(t.get("player", -1)) != p:
		return "Non è il tuo turno"
	if t.get("acted", false) or t.get("rested", false):
		return "Hai già compiuto la tua azione in questo turno"
	if t.get("pvp_side", false) or t.get("coop_side", false):
		return "Non puoi attaccare adesso"
	var j := other_here(eng, p)
	if j < 0:
		return "Non c'è nessun altro eroe nel tuo spazio"
	if shareable(eng, str(eng.P(p).pos)):
		return "Sul portale e nelle città non si combatte tra giocatori"
	var h: Dictionary = eng.hex(str(eng.P(p).pos))
	if str(h.get("site", "")) == "city":
		return "Nelle città non si combatte tra giocatori"
	if int(s.announced_by) != -1 or s.game_end_pending:
		return "La fine del round (o della partita) è stata annunciata"
	if flipped(eng, j):
		return "%s ha il gettone Ordine di Round a faccia in giù: non può essere attaccato" % eng.pname(j)
	if eng.wounds_only_lock(p):
		return "Hai solo Ferite in mano: devi riposare"
	return ""

## Movimento verso uno spazio con un altro eroe che provocherebbe nemici scatenati: vietato.
static func move_block(eng, p: int, to: String) -> String:
	if eng.flag(p, "no_provoke") or shareable(eng, to):
		return ""
	var someone := false
	for j in eng.s.players.size():
		if j != p and str(eng.P(j).pos) == to:
			someone = true
	if not someone:
		return ""
	var from: String = str(eng.P(p).pos)
	for nk in MKHex.neighbors(from):
		if nk == to:
			continue
		var nh: Dictionary = eng.hex(nk)
		if nh.is_empty() or not nh.get("rampage", false) or nh.get("enemies", []).is_empty():
			continue
		if MKHex.adjacent(nk, to):
			return "Non puoi entrare nello spazio di un altro eroe provocando nemici scatenati"
	return ""

## Azioni consentite mentre s.pvp è attivo ("" = prosegui con il controllo normale).
static func gate(eng, p: int, a: Dictionary) -> String:
	var pv: Dictionary = eng.s.pvp
	var t: String = str(a.get("t", ""))
	var step: String = str(pv.step)
	if step == "after":
		if t in ["play", "unit", "skill", "sp", "heal", "end_turn", "discard", "tactic_use"]:
			return ""
		return "Puoi solo curarti, giocare effetti speciali e terminare il turno"
	if t == "pvp":
		return _check_op(eng, p, a)
	if step in ["attack", "block"] and t in ["play", "unit", "sp"]:
		return ""
	if step in ["attack", "block"] and t == "skill":
		if str(pv.mode) == "partial" and p == int(pv.def):
			var d: Dictionary = MKDB.skills.get(str(a.get("id", "")), {})
			if str(d.get("usage", "")) != "interactive":
				return "Affrontando parzialmente il combattimento non puoi usare le tue Abilità"
		return ""
	return "Durante il combattimento tra giocatori puoi solo giocare carte, unità e abilità, attaccare, bloccare o passare"

static func _check_op(eng, p: int, a: Dictionary) -> String:
	var pv: Dictionary = eng.s.pvp
	var op: String = str(a.get("op", ""))
	if p != int(eng.s.turn.get("player", -1)):
		return "Non tocca a te"
	match op:
		"strike":
			if str(pv.step) != "attack" or p != int(pv.striker):
				return "Non è il momento di attaccare"
			if strike_value(eng) <= 0:
				return "Non hai punti Attacco utilizzabili in questa fase" + (" (solo Assedio contro un sito fortificato)" if _siege_only(eng) else "")
			return ""
		"pass":
			if str(pv.step) != "attack" or p != int(pv.striker):
				return "Non è il momento di passare"
			return ""
		"block":
			if str(pv.step) != "block" or p == int(pv.striker):
				return "Non è il momento di bloccare"
			return ""
	return "Operazione sconosciuta"

# ================================================================ values
static func _siege_only(eng) -> bool:
	var pv: Dictionary = eng.s.pvp
	return str(pv.phase) == "ranged" and bool(pv.get("fort", false)) and int(pv.striker) == int(pv.att)

static func _strike_keys(eng) -> Array:
	var pv: Dictionary = eng.s.pvp
	var pool: Dictionary = eng.s.turn.pool.attack
	var out: Array = []
	for key in pool:
		if int(pool[key]) <= 0:
			continue
		var kind: String = str(key).split(":")[0]
		if str(pv.phase) == "ranged":
			if kind == "melee":
				continue
			if _siege_only(eng) and kind != "siege":
				continue
		out.append(key)
	return out

## Valore dell'attacco che l'attaccante sta preparando (pool del turno corrente).
static func strike_value(eng) -> int:
	if not active(eng):
		return 0
	var n := 0
	for key in _strike_keys(eng):
		n += int(eng.s.turn.pool.attack[key])
	return n

static func strike_elems(eng) -> Array:
	var out: Array = []
	for key in _strike_keys(eng):
		var el: String = str(key).split(":")[1] if str(key).find(":") >= 0 else "phys"
		if not el in out:
			out.append(el)
	return out

## Riduzione dell'attacco in corso con il Blocco nel pool di chi blocca (turno corrente).
static func block_reduction(eng) -> int:
	var pv: Dictionary = eng.s.pvp
	var st = pv.get("strike", null)
	if st == null:
		return 0
	var elems: Array = st.get("elems", ["phys"])
	var pool: Dictionary = eng.s.turn.pool.block
	var eff := 0
	var ineff := 0
	for el in pool:
		var ok := false
		for ae in elems:
			if MKCombat.block_efficient(str(el), str(ae)):
				ok = true
		if ok:
			eff += int(pool[el])
		else:
			ineff += int(pool[el])
	var bs := int(eng.s.turn.get("block_swift", 0))
	eff += bs
	var total := eff + ineff / 2
	if str(pv.phase) == "ranged" and bs <= 0:
		return total / 2
	return total

## Armatura dell'eroe di chi blocca, con i modificatori del suo turno.
static func hero_armor(eng, j: int) -> int:
	var a := int(eng.P(j).armor)
	var t: Dictionary = eng.s.turn if int(eng.s.turn.get("player", -1)) == j else eng.s.pvp.get("saved", {})
	if t is Dictionary:
		for m in t.get("mods", []):
			if str(m.get("name", "")) == "armor":
				a += int(m.get("n", 0))
	return maxi(1, a)

static func unit_armor(eng, j: int, u: Dictionary, elems: Array) -> int:
	var a := int(eng.unit_def(u).get("armor", 1))
	var bn = eng.P(j).get("banners", {}).get(str(u.uid), null)
	if bn != null:
		a += int(MKSpecials.banner_params(eng, bn).get("armor", 0))
	var res: Array = MKCombat.unit_resists(eng, j, u)
	for el in elems:
		if (el == "cold" and "fire" in res and "ice" in res) or (el != "cold" and el in res):
			return maxi(1, a) * 2
	return maxi(1, a)

static func retreat_cost(eng, k: String) -> int:
	var h: Dictionary = eng.hex(k)
	if h.is_empty():
		return 999
	if str(h.get("site", "")) == "city":
		return 2
	var tab: Dictionary = MKEngine.COST_DAY if eng.s.day else MKEngine.COST_NIGHT
	return int(tab.get(str(h.t), 999))

static func retreat_hexes(eng, j: int) -> Array:
	var out: Array = []
	var pos: String = str(eng.P(j).pos)
	for nk in MKHex.neighbors(pos):
		if eng.hex(nk).is_empty() or eng._hex_blocked(j, nk) != "":
			continue
		var c := retreat_cost(eng, nk)
		if c >= 999:
			continue
		if not eng._is_safe(j, nk):
			continue
		out.append([nk, c])
	return out

const DIR_IT := ["ovest", "sud-ovest", "sud-est", "est", "nord-est", "nord-ovest"]

static func direction_it(from: String, to: String) -> String:
	var i := MKHex.neighbors(from).find(to)
	return DIR_IT[i] if i >= 0 else to

static func fame_reward(eng, w: int, l: int) -> int:
	var lw := int(eng.P(w).level)
	var ll := int(eng.P(l).level)
	if lw < ll:
		return 1 + 2 * (ll - lw)
	if lw == ll and int(eng.P(w).fame) < int(eng.P(l).fame):
		return 1
	return 0

# ================================================================ flow
static func _swap(eng) -> void:
	var pv: Dictionary = eng.s.pvp
	var other = pv.saved
	pv.saved = eng.s.turn
	eng.s.turn = other

static func _focus(eng, who: int) -> void:
	if int(eng.s.turn.get("player", -1)) != who:
		_swap(eng)

static func _other(eng, who: int) -> int:
	var pv: Dictionary = eng.s.pvp
	return int(pv.def) if who == int(pv.att) else int(pv.att)

static func start(eng, p: int) -> void:
	var s: Dictionary = eng.s
	var j := other_here(eng, p)
	var t: Dictionary = s.turn
	t.acted = true
	t.started = true
	t.combats = int(t.get("combats", 0)) + 1
	t.pool.move = 0
	t.pool.influence = 0
	t.pool.heal = 0
	t.pool.attack = {}
	t.pool.block = {}
	var path: Array = t.get("path", [])
	var from := ""
	if path.size() >= 2:
		from = str(path[path.size() - 2])
	var pos: String = str(eng.P(p).pos)
	var site: String = str(eng.hex(pos).get("site", ""))
	s["pvp"] = {"att": p, "def": j, "mode": "", "phase": "ranged", "step": "mode", "striker": j, "passes": 0,
		"strike": null, "dmg": 0, "saved": null, "from": from, "hex": pos, "fort": site in ["keep", "mage_tower"],
		"result": "", "winner": -1, "log_from": int(s.get("log_seq", 0))}
	eng.add_log("pvp_start", "%s attacca %s: combattimento tra giocatori!" % [eng.pname(p), eng.pname(j)], {"p": p, "def": j, "hex": pos})
	var opts: Array = []
	if eng.has_non_wound(j):
		opts.append({"v": "full", "label": "Affrontalo completamente: giochi ora il tuo prossimo turno (dado della Fonte, Abilità, fine turno con pesca) e poi lo salti"})
	opts.append({"v": "partial", "label": "Affrontalo parzialmente: niente dado della Fonte né Abilità, nessuna pesca dopo il combattimento; il tuo turno resta"})
	eng.ask(j, "choice", "pvp:mode", "%s ti attacca! Come affronti il combattimento?" % eng.pname(p), opts)

## Ingresso in un castello posseduto da un altro eroe che si trova lì: assalto + combattimento tra giocatori.
static func keep_attack(eng, p: int, to: String) -> bool:
	var h: Dictionary = eng.hex(to)
	if str(h.get("site", "")) != "keep" or int(h.get("owner", -1)) < 0 or int(h.get("owner", -1)) == p:
		return false
	var j := int(h.owner)
	if j >= eng.s.players.size() or str(eng.P(j).pos) != to:
		return false
	if check_attack(eng, p) != "":
		return false
	eng.change_rep(p, -1)
	eng.add_log("assault", "%s assalta il castello di %s" % [eng.pname(p), eng.pname(j)], {"p": p, "hex": to})
	start(eng, p)
	return true

## Fine turno nello spazio di un altro eroe: è automaticamente un attacco (se consentito).
static func auto_attack(eng, p: int) -> bool:
	if check_attack(eng, p) != "":
		return false
	eng.add_log("info", "%s termina il movimento nello spazio di %s: è un attacco" % [eng.pname(p), eng.pname(other_here(eng, p))], {"p": p})
	start(eng, p)
	return true

static func _begin(eng, mode: String) -> void:
	var s: Dictionary = eng.s
	var pv: Dictionary = s.pvp
	var j := int(pv.def)
	var pl: Dictionary = eng.P(j)
	pv.mode = mode
	var dt: Dictionary = eng._fresh_turn(j)
	dt.started = true
	dt.moved = true
	dt.acted = true
	dt["pvp_side"] = true
	dt["no_final_consume"] = true
	dt.prev = str(pl.pos)
	dt.path = [str(pl.pos)]
	if mode == "partial":
		dt.dice_allowed = 0
	else:
		pl["skip_next"] = true
		for sk in pl.skills:
			sk.used_turn = false
	pl.wounds_this_combat = 0
	pl.knocked_out = false
	pl.turns = int(pl.turns) + 1
	eng.P(int(pv.att)).wounds_this_combat = 0
	s.combat = {"enemies": [], "phase": "ranged", "site": str(pv.hex), "site_type": str(eng.hex(str(pv.hex)).get("site", "")),
		"kind": "pvp", "assault": false, "retreat": "", "units_allowed": true, "night_rules": false, "wounds_hand": 0,
		"fame": 0, "fortified_site": false, "city": "", "ruins": "", "first_time": false, "summoned": [], "pvp": true}
	pv.saved = s.turn
	s.turn = dt
	if mode == "full" and str(eng.hex(str(pl.pos)).get("site", "")) == "glade":
		eng.gain_token(j, "gold" if s.day else "black")
	pv.step = "attack"
	pv.phase = "ranged"
	pv.striker = j
	pv.passes = 0
	eng.add_log("pvp", "%s affronta il combattimento %s" % [eng.pname(j), "completamente (salterà il prossimo turno)" if mode == "full" else "parzialmente"], {"p": j, "mode": mode})
	eng.add_log("combat_phase", "Attacchi a distanza e d'assedio: inizia %s" % eng.pname(j), {"phase": "ranged"})

static func do_op(eng, p: int, a: Dictionary) -> void:
	match str(a.get("op", "")):
		"strike":
			_strike(eng, p)
		"pass":
			_pass(eng, p)
		"block":
			_block(eng, p)

static func _strike(eng, p: int) -> void:
	var s: Dictionary = eng.s
	var pv: Dictionary = s.pvp
	var n := strike_value(eng)
	var elems := strike_elems(eng)
	for k in _strike_keys(eng):
		s.turn.pool.attack.erase(k)
	pv.strike = {"n": n, "elems": elems, "by": p}
	pv.passes = 0
	var el_it: Array = []
	for el in elems:
		el_it.append(str(MKCombat.ELEM_IT.get(el, el)))
	eng.add_log("pvp_strike", "%s attacca %s con %d (%s)" % [eng.pname(p), eng.pname(_other(eng, p)), n, ", ".join(el_it)], {"p": p, "n": n, "elems": elems})
	pv.step = "block"
	_focus(eng, _other(eng, p))
	s.combat.phase = "block"

static func _block(eng, p: int) -> void:
	var s: Dictionary = eng.s
	var pv: Dictionary = s.pvp
	var red := block_reduction(eng)
	var n := int(pv.strike.n)
	var dmg := maxi(0, n - red)
	s.turn.pool.block = {}
	s.turn.erase("block_swift")
	s.turn.erase("block_per_ability")
	s.turn.erase("multi_block")
	if red > 0:
		eng.add_log("pvp_block", "%s blocca: l'attacco scende da %d a %d" % [eng.pname(p), n, dmg], {"p": p, "red": red, "dmg": dmg})
	pv.dmg = dmg
	pv.step = "hit"
	var striker := int(pv.striker)
	_focus(eng, striker)
	s.combat.phase = "attack" if str(pv.phase) == "melee" else "ranged"
	_ask_hit(eng)

static func hit_options(eng) -> Array:
	var pv: Dictionary = eng.s.pvp
	var d := int(pv.dmg)
	var b := _other(eng, int(pv.striker))
	var elems: Array = pv.strike.get("elems", ["phys"]) if pv.strike != null else ["phys"]
	var out: Array = []
	if d <= 0:
		return out
	var ha := hero_armor(eng, b)
	if d >= ha:
		out.append({"v": "hero", "label": "Ferisci %s (Armatura %d): una Ferita in mano" % [eng.pname(b), ha]})
	for u in eng.P(b).units:
		if u.wounded:
			continue
		var ua := unit_armor(eng, b, u, elems)
		if d >= ua:
			out.append({"v": "u:%d" % int(u.uid), "label": "Ferisci l'unità %s (Armatura %d)" % [eng.unit_name(u), ua]})
	if str(pv.phase) == "melee":
		if d >= 5:
			for iid in stealable(eng, b):
				out.append({"v": "a:" + str(iid), "label": "Ruba l'Artefatto %s (5 danni)" % eng.card_name(str(iid))})
		for rc in retreat_hexes(eng, b):
			if d >= int(rc[1]):
				# valore = esagono (la mappa lo evidenzia e lo rende cliccabile)
				out.append({"v": str(rc[0]), "label": "Costringi %s a ritirarsi a %s, in %s (%d danni) e vinci" % [eng.pname(b),
					direction_it(str(eng.P(b).pos), str(rc[0])), eng._hex_label(str(rc[0])), int(rc[1])]})
	return out

static func stealable(eng, b: int) -> Array:
	var pl: Dictionary = eng.P(b)
	var out: Array = []
	for zone in ["discard", "play"]:
		for iid in pl.get(zone, []):
			if str(eng.card(str(iid)).get("type", "")) == "artifact" and not iid in out:
				out.append(iid)
	var bn: Dictionary = pl.get("banners", {})
	for uid in bn:
		var u = eng.find_unit(b, int(uid))
		if u != null and u.wounded and not bn[uid] in out:
			out.append(bn[uid])
	return out

static func _ask_hit(eng) -> void:
	var pv: Dictionary = eng.s.pvp
	var opts := hit_options(eng)
	if opts.is_empty():
		if int(pv.dmg) > 0:
			eng.add_log("pvp", ("1 danno non assegnabile" if int(pv.dmg) == 1 else "%d danni non assegnabili" % int(pv.dmg)), {"p": int(pv.striker)})
		_after_strike(eng)
		return
	opts.append({"v": "done", "label": "Basta così (lascia %d danni non assegnati)" % int(pv.dmg)})
	eng.ask(int(pv.striker), "choice", "pvp:hit", "Hai %d danni da assegnare a %s" % [int(pv.dmg), eng.pname(_other(eng, int(pv.striker)))], opts)

static func _hit(eng, v) -> void:
	var s: Dictionary = eng.s
	var pv: Dictionary = s.pvp
	var sv := str(v)
	var a := int(pv.striker)
	var b := _other(eng, a)
	var elems: Array = pv.strike.get("elems", ["phys"])
	if sv == "done":
		_after_strike(eng)
		return
	if sv == "hero":
		pv.dmg = int(pv.dmg) - hero_armor(eng, b)
		eng.add_wound(b, true)
		var bp: Dictionary = eng.P(b)
		bp.wounds_this_combat = int(bp.wounds_this_combat) + 1
		eng.add_log("wound", "%s ferisce %s: una Ferita in mano" % [eng.pname(a), eng.pname(b)], {"p": b, "n": 1, "by": a})
		if not bp.knocked_out and int(bp.wounds_this_combat) >= eng.base_hand_limit(b):
			bp.knocked_out = true
			var n := 0
			for iid in bp.hand.duplicate():
				if not eng.is_wound(iid):
					bp.hand.erase(iid)
					bp.discard.append(iid)
					n += 1
			eng.add_log("knockout", "%s è fuori combattimento! (scarta %d carte)" % [eng.pname(b), n], {"p": b})
	elif sv.begins_with("u:"):
		var u = eng.find_unit(b, int(sv.substr(2)))
		if u != null:
			pv.dmg = int(pv.dmg) - unit_armor(eng, b, u, elems)
			u.wounded = true
			u.wounds = 1
			eng.add_log("unit_wound", "%s ferisce l'unità %s di %s" % [eng.pname(a), eng.unit_name(u), eng.pname(b)], {"p": b, "uid": u.uid, "by": a})
	elif sv.begins_with("a:"):
		var iid := sv.substr(2)
		var bp2: Dictionary = eng.P(b)
		var took := false
		for zone in ["discard", "play"]:
			if bp2[zone].has(iid):
				bp2[zone].erase(iid)
				took = true
				break
		if not took:
			var bn: Dictionary = bp2.get("banners", {})
			for uid in bn.keys():
				if str(bn[uid]) == iid:
					bn.erase(uid)
					took = true
		var bt = pv.saved if int(pv.saved.get("player", -1)) == b else s.turn
		for lst in ["played", "destroy", "set_aside"]:
			if bt.get(lst, []).has(iid):
				bt[lst].erase(iid)
		if took:
			eng.P(a).discard.append(iid)
			pv.dmg = int(pv.dmg) - 5
			eng.add_log("pvp_steal", "%s ruba %s a %s" % [eng.pname(a), eng.card_name(iid), eng.pname(b)], {"p": a, "from": b, "card": iid})
	elif not eng.hex(sv).is_empty():
		var to := sv
		_move_player(eng, b, to)
		eng.add_log("retreat", "%s costringe %s a ritirarsi in %s" % [eng.pname(a), eng.pname(b), eng._hex_label(to)], {"p": b, "to": to, "by": a})
		_finish(eng, "win", a)
		return
	_ask_hit(eng)

static func _move_player(eng, j: int, to: String) -> void:
	var s: Dictionary = eng.s
	eng.P(j).pos = to
	var t = s.turn if int(s.turn.get("player", -1)) == j else s.pvp.get("saved", null)
	if t is Dictionary:
		t.get("path", []).append(to)

static func _after_strike(eng) -> void:
	var s: Dictionary = eng.s
	var pv: Dictionary = s.pvp
	pv.strike = null
	pv.dmg = 0
	pv.step = "attack"
	var nxt := _other(eng, int(pv.striker))
	pv.striker = nxt
	_focus(eng, nxt)
	s.combat.phase = "attack" if str(pv.phase) == "melee" else "ranged"

static func _pass(eng, p: int) -> void:
	var s: Dictionary = eng.s
	var pv: Dictionary = s.pvp
	pv.passes = int(pv.passes) + 1
	eng.add_log("pvp_pass", "%s passa" % eng.pname(p), {"p": p})
	s.turn.pool.attack = {}
	if int(pv.passes) >= 2:
		if str(pv.phase) == "ranged":
			pv.phase = "melee"
			pv.passes = 0
			pv.striker = int(pv.att)
			_focus(eng, int(pv.att))
			s.combat.phase = "attack"
			eng.add_log("combat_phase", "Attacchi corpo a corpo: inizia %s" % eng.pname(int(pv.att)), {"phase": "attack"})
		else:
			_finish(eng, "draw", -1)
		return
	var nxt := _other(eng, p)
	pv.striker = nxt
	_focus(eng, nxt)

static func _finish(eng, result: String, winner: int) -> void:
	var s: Dictionary = eng.s
	var pv: Dictionary = s.pvp
	var att := int(pv.att)
	var dfn := int(pv.def)
	for t in [s.turn, pv.saved]:
		if t is Dictionary:
			t.pool.attack = {}
			t.pool.block = {}
	s.combat = null
	pv.result = result
	pv.winner = winner
	if result == "win":
		var loser := _other(eng, winner)
		var f := fame_reward(eng, winner, loser)
		if f > 0:
			eng.gain_fame(winner, f)
		eng.add_log("pvp_end", "%s vince il combattimento contro %s%s" % [eng.pname(winner), eng.pname(loser), (" (+%d Fama)" % f) if f > 0 else ""], {"p": winner, "loser": loser, "fame": f})
	else:
		eng.add_log("pvp_end", "Nessuno vuole più attaccare: il combattimento finisce in parità", {"p": att})
		if str(pv.from) != "" and str(eng.P(att).pos) == str(pv.hex):
			_move_player(eng, att, str(pv.from))
			eng.add_log("retreat", "%s torna nello spazio da cui ha attaccato" % eng.pname(att), {"p": att, "to": pv.from})
	if str(pv.mode) == "full":
		# il difensore completa ora il suo turno (cure, effetti speciali, fine del turno con pesca)
		_focus(eng, dfn)
		pv.step = "after"
		s.turn.stage = "action"
		return
	# parziale: la parte del difensore finisce subito, senza la procedura di fine turno
	_focus(eng, att)
	var dt: Dictionary = pv.saved
	var dp: Dictionary = eng.P(dfn)
	for iid in dp.play.duplicate():
		if iid in dt.get("destroy", []):
			eng.throw_away_played(dfn, iid)
		else:
			dp.discard.append(iid)
	dp.play = []
	s.pvp = null

## Hook di fine turno (passo 6): il turno anticipato del difensore è finito, si torna all'aggressore.
static func sub_turn_end(eng) -> bool:
	var s: Dictionary = eng.s
	var pv = s.get("pvp", null)
	if pv == null or str(pv.step) != "after" or int(s.turn.get("player", -1)) != int(pv.def):
		return false
	s.turn = pv.saved
	s.pvp = null
	return true

static func resolve(eng, pend: Dictionary, v) -> bool:
	match str(pend.get("handler", "")):
		"pvp:mode":
			_begin(eng, str(v))
			return true
		"pvp:hit":
			_hit(eng, v)
			return true
	return false

## Inizio del turno: gettone Ordine di Round a faccia in giù → lo si rigira e si salta il turno.
static func skip_turn(eng, p: int) -> bool:
	var pl: Dictionary = eng.P(p)
	if not pl.get("skip_next", false):
		return false
	pl.skip_next = false
	eng.add_log("turn", "%s salta il turno (gettone Ordine di Round a faccia in giù)" % eng.pname(p), {"p": p, "skip": true})
	return true

# ================================================================ available()
static func avail(eng, p: int, out: Array) -> void:
	var pv: Dictionary = eng.s.pvp
	if str(pv.step) == "attack" and p == int(pv.striker):
		var a := {"t": "pvp", "op": "strike"}
		if eng.check(a) == "":
			out.append({"a": a, "label": "Attacca %s con %d" % [eng.pname(_other(eng, p)), strike_value(eng)], "group": "combat"})
		out.append({"a": {"t": "pvp", "op": "pass"}, "label": "Passa (non attaccare)", "group": "combat"})
	elif str(pv.step) == "block" and p != int(pv.striker):
		var n := int(pv.strike.n) if pv.strike != null else 0
		out.append({"a": {"t": "pvp", "op": "block"}, "label": "Blocca (attacco %d → %d)" % [n, maxi(0, n - block_reduction(eng))], "group": "combat"})
