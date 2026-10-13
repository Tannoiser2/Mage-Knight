class_name MKCoop
extends RefCounted
## Assalto cooperativo a una città (Regolamento p. 13), negli scenari cooperativi.
##
## Proposta: {t:"coop", city:"q,r"} (giocatore di turno, prima dell'azione, adiacente alla città) →
##   decisioni "coop:invite" (chi invitare), "coop:split" (quanti nemici a testa), poi "coop:accept" per ogni
##   invitato (player = invitato). s.coop_prop = {city, init, members:[…], split:[…], idx} durante la proposta.
## Assalto: s.coop = {city, init, order:[giocatori in ordine di round a partire da chi ha iniziato],
##   groups:{"i":[eid]}, from:{"i":hex}, idx, stage:"combat"|"end", saved:{"i": turno sospeso}}.
##   Ogni partecipante, a turno, entra in città (Reputazione −1) e combatte solo i nemici assegnatigli
##   (s.combat.coop = true: la conquista si valuta alla fine). Poi la città è conquistata se tutti i difensori
##   sono stati sconfitti (capo = più Scudi), altrimenti tutti tornano allo spazio da cui hanno attaccato.
##   Infine ognuno termina il proprio turno in ordine (cure, ricompense, pesca); gli invitati saltano il
##   prossimo turno (gettone Ordine di Round a faccia in giù, giocatore.skip_next).

const MAX_TRIES := 3

static func enabled(eng) -> bool:
	return str(eng.s.scn.get("mode", "")) == "coop" and eng.s.players.size() > 1

static func available_heroes(eng, p: int, city: String) -> Array:
	var out: Array = []
	for j in eng.s.players.size():
		if j == p:
			continue
		var pl: Dictionary = eng.P(j)
		if not MKHex.adjacent(str(pl.pos), city):
			continue
		if pl.get("skip_next", false):
			continue
		if not eng.has_non_wound(j):
			continue
		out.append(j)
	return out

static func cities_adjacent(eng, p: int) -> Array:
	var out: Array = []
	for nk in MKHex.neighbors(str(eng.P(p).pos)):
		var h: Dictionary = eng.hex(nk)
		if str(h.get("site", "")) == "city" and not h.get("conquered", false) and not h.get("enemies", []).is_empty():
			out.append(nk)
	return out

static func check_propose(eng, p: int, city: String) -> String:
	var s: Dictionary = eng.s
	if not enabled(eng):
		return "L'assalto cooperativo si fa solo negli scenari cooperativi"
	if s.combat != null or s.get("pvp", null) != null or s.get("coop", null) != null or s.get("coop_prop", null) != null:
		return "Non adesso"
	var t: Dictionary = s.turn
	if int(t.get("player", -1)) != p or t.get("coop_side", false) or t.get("pvp_side", false):
		return "Non è il tuo turno"
	if t.get("acted", false) or t.get("rested", false):
		return "Hai già compiuto la tua azione in questo turno"
	if int(s.announced_by) != -1 or s.game_end_pending:
		return "La fine del round (o della partita) è stata annunciata"
	if eng.wounds_only_lock(p):
		return "Hai solo Ferite in mano: devi riposare"
	if int(t.get("coop_tries", 0)) >= MAX_TRIES:
		return "Hai già fatto abbastanza proposte in questo turno"
	var h: Dictionary = eng.hex(city)
	if str(h.get("site", "")) != "city" or h.get("conquered", false) or h.get("enemies", []).is_empty():
		return "Lì non c'è una città da assaltare"
	if not s.scn.get("cities_enterable", true):
		return "In questo scenario non si può entrare nelle città"
	if not MKHex.adjacent(str(eng.P(p).pos), city):
		return "Devi essere adiacente alla città"
	for j in s.players.size():
		if j != p and str(eng.P(j).pos) == str(eng.P(p).pos):
			return "Nel tuo spazio c'è un altro eroe"
	if available_heroes(eng, p, city).is_empty():
		return "Nessun altro eroe disponibile adiacente alla città"
	if h.enemies.size() < 2:
		return "La guarnigione è troppo piccola per dividerla"
	return ""

static func propose(eng, p: int, city: String) -> void:
	var s: Dictionary = eng.s
	s.turn["coop_tries"] = int(s.turn.get("coop_tries", 0)) + 1
	s["coop_prop"] = {"city": city, "init": p, "members": [p], "split": [], "idx": 0}
	var av := available_heroes(eng, p, city)
	var n: int = eng.hex(city).enemies.size()
	var opts: Array = []
	var subsets: Array = []
	for mask in range(1, 1 << av.size()):
		var sub: Array = []
		for i in av.size():
			if mask & (1 << i):
				sub.append(av[i])
		if sub.size() + 1 <= n:
			subsets.append(sub)
	subsets.sort_custom(func(a, b): return a.size() < b.size())
	for sub in subsets:
		var names: Array = []
		for j in sub:
			names.append(eng.pname(j))
		opts.append({"v": ",".join(sub.map(func(x): return str(x))), "label": "Invita " + " e ".join(names)})
	opts.append({"v": "cancel", "label": "Annulla"})
	eng.add_log("coop", "%s propone un assalto cooperativo alla città %s" % [eng.pname(p), MKMana.color_it(str(eng.hex(city).city.color))], {"p": p, "hex": city})
	eng.ask(p, "choice", "coop:invite", "Assalto cooperativo: chi inviti?", opts)

## Tutte le distribuzioni dei nemici (almeno 1 a testa), proposte come opzioni.
static func splits(n: int, k: int) -> Array:
	var out: Array = []
	if k == 1:
		return [[n]]
	for first in range(1, n - k + 2):
		for rest in splits(n - first, k - 1):
			out.append([first] + rest)
	return out

static func _ask_split(eng) -> void:
	var s: Dictionary = eng.s
	var pr: Dictionary = s.coop_prop
	var n: int = eng.hex(str(pr.city)).enemies.size()
	var opts: Array = []
	for sp in splits(n, pr.members.size()):
		var parts: Array = []
		for i in sp.size():
			parts.append("%s %d" % ["tu" if i == 0 else eng.pname(int(pr.members[i])), int(sp[i])])
		opts.append({"v": ",".join(sp.map(func(x): return str(x))), "label": "Nemici: " + ", ".join(parts)})
	opts.append({"v": "cancel", "label": "Annulla"})
	eng.ask(int(pr.init), "choice", "coop:split", "Assalto cooperativo: quanti dei %d difensori affronterà ciascuno?" % n, opts)

static func _ask_accept(eng) -> void:
	var s: Dictionary = eng.s
	var pr: Dictionary = s.coop_prop
	var i := int(pr.idx)
	var j := int(pr.members[i])
	var h: Dictionary = eng.hex(str(pr.city))
	var parts: Array = []
	for k in pr.members.size():
		parts.append("%s %d" % [eng.pname(int(pr.members[k])), int(pr.split[k])])
	eng.ask(j, "choice", "coop:accept", "%s ti invita ad assaltare insieme la città %s (%s). Accettando salterai il tuo prossimo turno." % [
		eng.pname(int(pr.init)), MKMana.color_it(str(h.city.color)), ", ".join(parts)],
		[{"v": "yes", "label": "Accetto: combattiamo insieme (%d nemici per me)" % int(pr.split[i])}, {"v": "no", "label": "Rifiuto"}])

static func resolve(eng, pend: Dictionary, v) -> bool:
	var s: Dictionary = eng.s
	var h: String = str(pend.get("handler", ""))
	if not h.begins_with("coop:"):
		return false
	var pr = s.get("coop_prop", null)
	if pr == null:
		return true
	var sv := str(v)
	match h:
		"coop:invite":
			if sv == "cancel":
				s.coop_prop = null
				eng.add_log("coop", "Proposta ritirata", {"p": int(pend.player)})
				return true
			for x in sv.split(","):
				pr.members.append(int(x))
			_ask_split(eng)
		"coop:split":
			if sv == "cancel":
				s.coop_prop = null
				eng.add_log("coop", "Proposta ritirata", {"p": int(pend.player)})
				return true
			var sp: Array = []
			for x in sv.split(","):
				sp.append(int(x))
			pr.split = sp
			pr.idx = 1
			_ask_accept(eng)
		"coop:accept":
			if sv != "yes":
				eng.add_log("coop", "%s rifiuta l'assalto cooperativo" % eng.pname(int(pend.player)), {"p": int(pend.player)})
				s.coop_prop = null
				return true
			eng.add_log("coop", "%s accetta" % eng.pname(int(pend.player)), {"p": int(pend.player)})
			pr.idx = int(pr.idx) + 1
			if int(pr.idx) < pr.members.size():
				_ask_accept(eng)
			else:
				_launch(eng)
	return true

static func _round_order_from(eng, init: int, members: Array) -> Array:
	var order: Array = eng.s.turn_order
	var start := order.find(init)
	var out: Array = []
	for k in order.size():
		var who: int = int(order[(start + k) % order.size()])
		if who in members and not who in out:
			out.append(who)
	for m in members:
		if not int(m) in out:
			out.append(int(m))
	return out

static func _launch(eng) -> void:
	var s: Dictionary = eng.s
	var pr: Dictionary = s.coop_prop
	s.coop_prop = null
	var city: String = str(pr.city)
	var h: Dictionary = eng.hex(city)
	var eids: Array = h.enemies.duplicate()
	MKRng.shuffle(eng.s, eids)
	var groups := {}
	var pos := 0
	for k in pr.members.size():
		var m := int(pr.members[k])
		groups[str(m)] = eids.slice(pos, pos + int(pr.split[k]))
		pos += int(pr.split[k])
	var init := int(pr.init)
	for m in pr.members:
		if int(m) != init:
			eng.P(int(m))["skip_next"] = true
	s.turn.acted = true
	s.turn.started = true
	var from := {}
	for m in pr.members:
		from[str(m)] = str(eng.P(int(m)).pos)
	s["coop"] = {"city": city, "init": init, "order": _round_order_from(eng, init, pr.members), "groups": groups,
		"from": from, "idx": 0, "stage": "combat", "saved": {}, "log_from": int(s.get("log_seq", 0))}
	for eid in h.enemies:
		s.enemies[eid].face_up = true
	eng.add_log("coop_start", "Assalto cooperativo alla città %s: %s" % [MKMana.color_it(str(h.city.color)), ", ".join(s.coop.order.map(func(x): return "%s (%d nemici)" % [eng.pname(x), groups[str(x)].size()]))], {"p": init, "hex": city})
	_start_member(eng, 0)

static func _start_member(eng, i: int) -> void:
	var s: Dictionary = eng.s
	var co: Dictionary = s.coop
	co.idx = i
	var m := int(co.order[i])
	if int(s.turn.get("player", -1)) != m:
		co.saved[str(int(s.turn.player))] = s.turn
		var dt: Dictionary = eng._fresh_turn(m)
		dt.started = true
		dt.moved = true
		dt["coop_side"] = true
		dt["no_final_consume"] = true
		dt.prev = str(eng.P(m).pos)
		dt.path = [str(eng.P(m).pos)]
		s.turn = dt
		for sk in eng.P(m).skills:
			sk.used_turn = false
		eng.P(m).knocked_out = false
		eng.P(m).wounds_this_combat = 0
		eng.P(m).turns = int(eng.P(m).turns) + 1
	var pl: Dictionary = eng.P(m)
	var from: String = str(pl.pos)
	var city: String = str(co.city)
	pl.pos = city
	s.turn.prev = from
	s.turn.path.append(city)
	s.turn.moved = true
	eng.change_rep(m, -1)
	eng.add_log("assault", "%s assalta la città" % eng.pname(m), {"p": m, "hex": city})
	var provoked: Array = []
	if not eng.flag(m, "no_provoke"):
		for nk in MKHex.neighbors(from):
			if nk == city:
				continue
			var nh: Dictionary = eng.hex(nk)
			if nh.is_empty() or not nh.get("rampage", false) or nh.enemies.is_empty():
				continue
			if MKHex.adjacent(nk, city):
				for eid in nh.enemies:
					provoked.append(eid)
	if not provoked.is_empty():
		eng.add_log("provoke", "%s provoca i nemici scatenati" % eng.pname(m), {"p": m, "enemies": provoked})
	var group: Array = []
	for eid in co.groups.get(str(m), []):
		if s.enemies.has(eid):
			group.append(eid)
	MKCombat.start(eng, group + provoked, {"site": city, "kind": "assault", "assault": true, "defenders": group, "retreat": from})
	if s.combat != null:
		s.combat["coop"] = true

## Hook dopo MKCombat.finish: passa al partecipante successivo o risolve l'assalto.
static func after_combat(eng) -> void:
	var s: Dictionary = eng.s
	var co = s.get("coop", null)
	if co == null or str(co.stage) != "combat" or s.combat != null or s.pending != null:
		return
	var i := int(co.idx) + 1
	if i < co.order.size():
		_start_member(eng, i)
		return
	_resolve_assault(eng)

static func _resolve_assault(eng) -> void:
	var s: Dictionary = eng.s
	var co: Dictionary = s.coop
	var city: String = str(co.city)
	var h: Dictionary = eng.hex(city)
	var left: Array = []
	for eid in h.enemies:
		if s.enemies.has(eid):
			left.append(eid)
	co.saved[str(int(s.turn.player))] = s.turn
	if left.is_empty():
		MKSites.conquer(eng, int(co.init), city)
		eng.add_log("coop_end", "Assalto cooperativo riuscito!", {"p": int(co.init), "hex": city, "won": true})
	else:
		eng.add_log("coop_end", "Assalto cooperativo fallito: restano %d difensori" % left.size(), {"p": int(co.init), "hex": city, "won": false})
		for m in co.order:
			var f: String = str(co.from[str(m)])
			eng.P(int(m)).pos = f
			var t: Dictionary = co.saved[str(int(m))]
			t.path.append(f)
			eng.add_log("retreat", "%s si ritira dopo l'assalto fallito" % eng.pname(int(m)), {"p": int(m), "to": f})
	co.stage = "end"
	co.idx = 0
	s.turn = co.saved[str(int(co.order[0]))]
	co.saved.erase(str(int(co.order[0])))

## Hook di fine turno (passo 6): turno del partecipante finito → tocca al successivo; true = non avanzare.
static func sub_turn_end(eng) -> bool:
	var s: Dictionary = eng.s
	var co = s.get("coop", null)
	if co == null or str(co.stage) != "end":
		return false
	var cur := int(s.turn.get("player", -1))
	if cur != int(co.order[int(co.idx)]):
		return false
	co.saved[str(cur)] = s.turn
	var i := int(co.idx) + 1
	if i < co.order.size():
		co.idx = i
		var nxt := str(int(co.order[i]))
		s.turn = co.saved[nxt]
		co.saved.erase(nxt)
		s.turn.stage = "action"
		return true
	# finito: si riprende il turno (concluso) di chi ha iniziato e si avanza normalmente
	s.turn = co.saved[str(int(co.init))]
	s.coop = null
	return false

static func avail(eng, p: int, out: Array) -> void:
	if not enabled(eng):
		return
	for k in cities_adjacent(eng, p):
		var a := {"t": "coop", "city": k}
		if check_propose(eng, p, k) == "":
			out.append({"a": a, "label": "Proponi un assalto cooperativo alla città %s" % MKMana.color_it(str(eng.hex(k).city.color)), "group": "site"})
