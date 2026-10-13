extends SceneTree
## Combattimento tra giocatori e assalto cooperativo alla città (motore + IA), senza grafica:
## godot --headless --path . -s res://tests/pvp_test.gd

const AI = preload("res://scripts/core/ai.gd")

var fails := 0
var passes := 0

func ok(cond: bool, what: String) -> void:
	if cond:
		passes += 1
	else:
		fails += 1
		print("  FALLITO: ", what)

func eq(a, b, what: String) -> void:
	ok(a == b, "%s (atteso %s, ottenuto %s)" % [what, str(b), str(a)])

func _init():
	MKDB.load_dir("res://data")
	for t in [test_pvp_conditions, test_pvp_partial, test_pvp_ranged_block, test_pvp_full_and_skip, test_pvp_fortified_keep,
			test_pvp_steal, test_pvp_auto_attack, test_pvp_ai, test_coop_success, test_coop_fail_and_refuse, test_coop_ai,
			test_determinism]:
		var before := fails
		t.call()
		print("%s %s" % ["OK " if fails == before else "ERR", t.get_method()])
	print("TEST: %d ok, %d falliti" % [passes, fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ helpers
func mk(scn: String, heroes: Array, seed := 5, opts := {}) -> MKEngine:
	var cfg := {"scenario": scn, "seed": seed, "players": [], "options": opts}
	for h in heroes:
		cfg.players.append({"hero": h, "name": h, "ctrl": "ai"})
	var e := MKEngine.create(cfg)
	while e.s.phase == "tactics" or e.s.pending != null:
		var av := e.available()
		if av.is_empty() or not e.apply(av[0].a).ok:
			break
	return e

func hand(e: MKEngine, p: int, ids: Array) -> Array:
	var out: Array = []
	e.s.players[p].hand = []
	for id in ids:
		var iid := e.new_iid(id)
		e.s.players[p].hand.append(iid)
		out.append(iid)
	return out

func act(e: MKEngine, a: Dictionary) -> bool:
	var r := e.apply(a)
	if not r.ok:
		print("    azione rifiutata ", a, " -> ", r.err)
	return r.ok

func choose(e: MKEngine, v) -> bool:
	return act(e, {"t": "choose", "v": [v]})

func has_opt(e: MKEngine, v) -> bool:
	if e.s.pending == null:
		return false
	for o in e.s.pending.options:
		if str(o.v) == str(v):
			return true
	return false

## Esagono di pianura libero (con almeno 3 vicini di pianura liberi), lontano da siti e nemici.
func clear_area(e: MKEngine) -> Array:
	var keys: Array = e.s.map.hex.keys()
	keys.sort()
	for k in keys:
		var h: Dictionary = e.s.map.hex[k]
		var good: Array = []
		for nk in MKHex.neighbors(k):
			if e.s.map.hex.has(nk):
				good.append(nk)
		if good.size() >= 4:
			for x in [k] + good:
				var hx: Dictionary = e.s.map.hex[x]
				hx.t = "plains"
				hx.site = ""
				hx.enemies = []
				hx.rampage = false
				hx.mine = ""
				hx.erase("city")
			# niente nemici scatenati attorno
			for x in good:
				for nn in MKHex.neighbors(x):
					if e.s.map.hex.has(nn) and e.s.map.hex[nn].rampage:
						e.s.map.hex[nn].rampage = false
						e.s.map.hex[nn].enemies = []
			return [k] + good
	return []

## Mette p (attivo) accanto a q e lo fa entrare nel suo spazio. Ritorna l'esagono.
func meet(e: MKEngine) -> Dictionary:
	var a := int(e.s.turn.player)
	var b := 1 - a
	var area := clear_area(e)
	e.s.players[b].pos = area[0]
	e.s.players[a].pos = area[1]
	e.s.turn.path = [area[1]]
	e.s.turn.pool.move = 6
	ok(act(e, {"t": "move", "to": area[0]}), "l'aggressore entra nello spazio dell'altro eroe")
	return {"a": a, "b": b, "hex": area[0], "from": area[1], "area": area}

# ------------------------------------------------------------------ PvP
func test_pvp_conditions():
	var e := mk("full_conquest", ["arythea", "tovak"])
	ok(MKPvP.enabled(e), "Conquista completa: combattimento tra giocatori consentito")
	var e2 := mk("full_conquest", ["arythea", "tovak"], 5, {"pvp": false})
	ok(not MKPvP.enabled(e2), "opzione Combattimento tra giocatori: no")
	var e3 := mk("first_recon", ["arythea", "tovak"])
	ok(not MKPvP.enabled(e3), "Prima Ricognizione: niente combattimento tra giocatori")
	var e4 := mk("coop_conquest", ["arythea", "tovak"])
	ok(not MKPvP.enabled(e4), "cooperativo: niente combattimento tra giocatori")
	var m := meet(e)
	var a: int = m.a
	hand(e, a, ["march", "rage", "stamina"])
	ok(e.check({"t": "pvp_attack"}) == "", "attacco consentito nello spazio dell'altro eroe")
	var found := false
	for x in e.available():
		if str(x.a.get("t", "")) == "pvp_attack":
			found = true
	ok(found, "available() propone l'attacco all'altro eroe")
	e.s.players[m.b].skip_next = true
	ok(e.check({"t": "pvp_attack"}) != "", "non si attacca chi ha il gettone a faccia in giù")
	e.s.players[m.b].skip_next = false
	e.s.announced_by = m.b
	ok(e.check({"t": "pvp_attack"}) != "", "non dopo l'annuncio della fine del round")
	e.s.announced_by = -1
	# senza combattimento: fine turno con Ritirata Forzata
	var m2 := meet(e2)
	hand(e2, m2.a, ["march", "rage"])
	ok(e2.check({"t": "pvp_attack"}) != "", "opzione no: niente attacco")
	ok(act(e2, {"t": "play", "card": e2.s.players[m2.a].hand[0], "mode": "side", "side": "move"}), "gioca una carta")
	ok(act(e2, {"t": "end_turn"}), "fine turno nello spazio dell'altro eroe")
	var guard := 0
	while e2.s.pending != null and guard < 10:
		guard += 1
		choose(e2, e2.s.pending.options[0].v)
	ok(e2.s.players[m2.a].pos == m2.from, "Ritirata Forzata nello spazio precedente")

func test_pvp_partial():
	var e := mk("full_conquest", ["arythea", "tovak"])
	var m := meet(e)
	var a: int = m.a
	var b: int = m.b
	hand(e, a, ["march", "rage", "stamina"])
	hand(e, b, ["march", "rage", "determination", "swiftness"])
	e.s.players[a].level = 1
	e.s.players[b].level = 3
	e.s.players[b].fame = 9
	e.s.players[b].armor = 3
	var fame0: int = e.s.players[a].fame
	ok(act(e, {"t": "pvp_attack"}), "attacco")
	ok(e.s.pending != null and int(e.s.pending.player) == b and e.s.pending.handler == "pvp:mode", "il difensore sceglie come affrontare il combattimento")
	eq(e.actor(), b, "decide il difensore")
	ok(choose(e, "partial"), "affronta parzialmente")
	eq(int(e.s.turn.player), b, "inizia il difensore (attacchi a distanza)")
	eq(int(e.s.turn.dice_allowed), 0, "parziale: niente dado della Fonte")
	ok(e.s.combat != null and e.s.combat.kind == "pvp", "combattimento tra giocatori")
	ok(e.check({"t": "move", "to": m.from}) != "", "non si muove durante il combattimento")
	ok(e.check({"t": "next"}) != "", "niente fasi del combattimento normale")
	ok(e.check({"t": "pvp", "op": "strike"}) != "", "senza punti attacco non si attacca")
	ok(act(e, {"t": "pvp", "op": "pass"}), "il difensore passa")
	eq(int(e.s.turn.player), a, "tocca all'aggressore")
	ok(act(e, {"t": "pvp", "op": "pass"}), "l'aggressore passa")
	eq(str(e.s.pvp.phase), "melee", "fase corpo a corpo")
	eq(int(e.s.turn.player), a, "nel corpo a corpo inizia l'aggressore")
	# carta di lato = attacco fisico 1 nel corpo a corpo
	var r_iid: String = e.s.players[a].hand[1]
	ok(act(e, {"t": "play", "card": r_iid, "mode": "side", "side": "attack"}), "carta di lato come Attacco 1")
	e.s.turn.pool.attack["melee:phys"] = 8
	ok(act(e, {"t": "pvp", "op": "strike"}), "colpisce con 8")
	eq(int(e.s.turn.player), b, "ora blocca il difensore")
	e.s.turn.pool.block = {"phys": 2}
	ok(act(e, {"t": "pvp", "op": "block"}), "blocco 2: nel corpo a corpo riduce di 2")
	eq(int(e.s.pvp.dmg), 6, "restano 6 danni")
	ok(e.s.pending != null and e.s.pending.handler == "pvp:hit" and int(e.s.pending.player) == a, "l'attaccante assegna i danni")
	ok(has_opt(e, "hero"), "si può ferire l'eroe (danni ≥ armatura)")
	var w0 := 0
	for iid in e.s.players[b].hand:
		if e.is_wound(iid):
			w0 += 1
	ok(choose(e, "hero"), "ferisce l'eroe")
	ok(choose(e, "hero"), "lo ferisce ancora")
	var w1 := 0
	for iid in e.s.players[b].hand:
		if e.is_wound(iid):
			w1 += 1
	eq(w1 - w0, 2, "due Ferite in mano al difensore (3+3 danni)")
	ok(e.s.pending == null, "nessun danno assegnabile oltre")
	eq(int(e.s.turn.player), b, "ruoli invertiti: attacca il difensore")
	ok(act(e, {"t": "pvp", "op": "pass"}), "il difensore passa")
	e.s.turn.pool.attack = {"melee:phys": 3}
	ok(act(e, {"t": "pvp", "op": "strike"}), "l'aggressore colpisce con 3")
	ok(act(e, {"t": "pvp", "op": "block"}), "nessun blocco")
	var rh := ""
	for o in e.s.pending.options:
		if not e.hex(str(o.v)).is_empty():
			rh = str(o.v)
	ok(rh != "", "si può costringere l'avversario a ritirarsi (costo del terreno)")
	ok(choose(e, rh), "costringe a ritirarsi")
	ok(e.s.get("pvp") == null and e.s.combat == null, "combattimento finito")
	eq(e.s.players[b].pos, rh, "il perdente si è ritirato")
	eq(int(e.s.players[a].fame) - fame0, 5, "Fama al vincitore: 1 + 2 per livello in meno")
	eq(int(e.s.turn.player), a, "si torna al turno dell'aggressore")
	ok(not e.s.players[b].get("skip_next", false), "parziale: il difensore non salta il turno")
	ok(e.check({"t": "end_turn"}) == "", "l'aggressore può terminare il turno")

func test_pvp_ranged_block():
	var e := mk("full_conquest", ["arythea", "tovak"])
	var m := meet(e)
	var a: int = m.a
	var b: int = m.b
	hand(e, a, ["march", "rage"])
	hand(e, b, ["march", "rage", "stamina"])
	ok(act(e, {"t": "pvp_attack"}), "attacco")
	ok(choose(e, "partial"), "parziale")
	e.s.turn.pool.attack = {"ranged:fire": 4, "melee:phys": 5}
	eq(MKPvP.strike_value(e), 4, "nella fase a distanza contano solo gli attacchi a distanza/d'assedio")
	ok(act(e, {"t": "pvp", "op": "strike"}), "Attacco di Fuoco a Distanza 4")
	e.s.turn.pool.block = {"ice": 4}
	eq(MKPvP.block_reduction(e), 2, "Blocco di Ghiaccio 4 riduce di 2 (come Rapido)")
	e.s.turn.pool.block = {"phys": 7}
	eq(MKPvP.block_reduction(e), 1, "Blocco 7 inefficiente: 3, riduce di 1 (esempio del regolamento)")
	ok(act(e, {"t": "pvp", "op": "block"}), "blocca")
	eq(int(e.s.pvp.dmg), 3, "restano 3 danni")

func test_pvp_full_and_skip():
	var e := mk("full_conquest", ["arythea", "tovak"])
	var m := meet(e)
	var a: int = m.a
	var b: int = m.b
	hand(e, a, ["march", "rage"])
	hand(e, b, ["rage", "stamina"])
	ok(act(e, {"t": "pvp_attack"}), "attacco")
	ok(has_opt(e, "full"), "con carte non-Ferita si può affrontare completamente")
	ok(choose(e, "full"), "affronta completamente")
	ok(e.s.players[b].skip_next, "gettone Ordine di Round a faccia in giù")
	eq(int(e.s.turn.dice_allowed), 1, "completo: può usare un dado della Fonte")
	for i in 4:
		ok(act(e, {"t": "pvp", "op": "pass"}), "passa %d" % i)
	ok(e.s.combat == null, "parità: combattimento finito")
	eq(e.s.players[a].pos, m.from, "parità: l'aggressore torna nello spazio da cui ha attaccato")
	eq(int(e.s.turn.player), b, "il difensore completa il suo turno")
	ok(e.check({"t": "move", "to": m.area[2]}) != "", "il difensore non può muoversi")
	ok(act(e, {"t": "end_turn"}), "il difensore termina il turno")
	var guard := 0
	while e.s.pending != null and int(e.s.pending.player) == b and guard < 10:
		guard += 1
		choose(e, e.s.pending.options[0].v)
	eq(e.s.players[b].hand.size(), int(e.s.players[b].hand_limit), "il difensore pesca fino al limite di mano")
	ok(e.s.get("pvp") == null, "fine del combattimento tra giocatori")
	eq(int(e.s.turn.player), a, "si torna all'aggressore")
	ok(act(e, {"t": "end_turn"}), "l'aggressore termina il turno")
	guard = 0
	var skipped := false
	while guard < 60 and int(e.s.turn.get("player", -1)) != b and e.s.phase != "game_over":
		guard += 1
		var x = AI.decide(e, 2)
		if x.is_empty():
			break
		e.apply(x)
	for L in e.s.log:
		if str(L.get("k", "")) == "turn" and L.get("skip", false) and int(L.get("p", -1)) == b:
			skipped = true
	ok(skipped, "il difensore salta il suo turno successivo")
	ok(not e.s.players[b].get("skip_next", false), "gettone di nuovo a faccia in su")

func test_pvp_fortified_keep():
	var e := mk("full_conquest", ["arythea", "tovak"])
	var a := int(e.s.turn.player)
	var b := 1 - a
	var area := clear_area(e)
	var k: String = area[0]
	e.s.map.hex[k].site = "keep"
	e.s.map.hex[k].owner = b
	e.s.map.hex[k].conquered = true
	e.s.players[b].shields.append(k)
	e.s.players[b].pos = k
	e.s.players[a].pos = area[1]
	e.s.turn.path = [area[1]]
	e.s.turn.pool.move = 6
	hand(e, a, ["march", "rage"])
	var rep0: int = e.s.players[a].rep
	ok(act(e, {"t": "move", "to": k}), "entra nel castello dell'avversario")
	eq(int(e.s.players[a].rep), rep0 - 1, "assalto: Reputazione −1")
	ok(e.s.pending != null and e.s.pending.handler == "pvp:mode", "combattimento tra giocatori, nessuna guarnigione pescata")
	eq(e.s.map.hex[k].enemies.size(), 0, "nessun nemico grigio nel castello")
	ok(choose(e, "partial"), "parziale")
	ok(act(e, {"t": "pvp", "op": "pass"}), "il difensore passa")
	e.s.turn.pool.attack = {"ranged:phys": 5}
	ok(e.check({"t": "pvp", "op": "strike"}) != "", "contro il difensore fortificato servono attacchi d'assedio")
	e.s.turn.pool.attack = {"siege:phys": 5}
	ok(e.check({"t": "pvp", "op": "strike"}) == "", "l'assedio è consentito")

func test_pvp_steal():
	var e := mk("full_conquest", ["arythea", "tovak"])
	var m := meet(e)
	var a: int = m.a
	var b: int = m.b
	hand(e, a, ["march", "rage"])
	hand(e, b, ["rage", "stamina"])
	var art := ""
	for id in MKDB.cards:
		if str(MKDB.cards[id].get("type", "")) == "artifact":
			art = id
			break
	var aiid := e.new_iid(art)
	e.s.players[b].discard.append(aiid)
	ok(act(e, {"t": "pvp_attack"}), "attacco")
	ok(choose(e, "partial"), "parziale")
	ok(act(e, {"t": "pvp", "op": "pass"}), "passa")
	e.s.turn.pool.attack = {"ranged:phys": 6}
	ok(act(e, {"t": "pvp", "op": "strike"}), "attacco a distanza")
	ok(act(e, {"t": "pvp", "op": "block"}), "nessun blocco")
	ok(not has_opt(e, "a:" + aiid), "nella fase a distanza non si rubano Artefatti")
	choose(e, "done")
	ok(act(e, {"t": "pvp", "op": "pass"}), "passa")
	ok(act(e, {"t": "pvp", "op": "pass"}), "passa: corpo a corpo")
	e.s.turn.pool.attack = {"melee:phys": 6}
	ok(act(e, {"t": "pvp", "op": "strike"}), "corpo a corpo 6")
	ok(act(e, {"t": "pvp", "op": "block"}), "nessun blocco")
	ok(has_opt(e, "a:" + aiid), "5 danni: si può rubare l'Artefatto negli scarti")
	ok(choose(e, "a:" + aiid), "ruba")
	ok(aiid in e.s.players[a].discard and not aiid in e.s.players[b].discard, "l'Artefatto passa negli scarti dell'attaccante")

func test_pvp_auto_attack():
	var e := mk("full_conquest", ["arythea", "tovak"])
	var m := meet(e)
	hand(e, m.a, ["march", "rage"])
	ok(act(e, {"t": "play", "card": e.s.players[m.a].hand[0], "mode": "side", "side": "move"}), "gioca una carta")
	ok(act(e, {"t": "end_turn"}), "fine turno nello spazio dell'altro eroe")
	ok(e.s.pending != null and e.s.pending.handler == "pvp:mode", "è automaticamente un attacco")
	ok(e.check({"t": "site"}) != "", "nessun'altra azione")

## IA contro IA: tutte le decisioni del combattimento sono legali e il combattimento termina.
func test_pvp_ai():
	for seed in [3, 8, 21]:
		var e := mk("full_conquest", ["arythea", "tovak"], seed)
		var m := meet(e)
		e.s.players[m.a].hand = []
		for id in ["rage", "determination", "swiftness", "stamina", "march"]:
			e.s.players[m.a].hand.append(e.new_iid(id))
		ok(act(e, {"t": "pvp_attack"}), "attacco")
		AI.reset_stats()
		var n := 0
		while (e.s.get("pvp") != null) and n < 200:
			n += 1
			var x = AI.decide(e, 1 + seed % 3)
			if x.is_empty() or not e.apply(x).ok:
				print("    IA bloccata: ", x)
				break
		ok(e.s.get("pvp") == null, "l'IA porta a termine il combattimento tra giocatori (seed %d, %d decisioni)" % [seed, n])
		eq(int(AI.stats.illegal), 0, "nessuna azione illegale dell'IA")
		eq(int(e.s.turn.player), m.a, "si torna all'aggressore")

# ------------------------------------------------------------------ assalto cooperativo
func coop_setup(seed := 5, n_def := 3) -> Dictionary:
	var e := mk("coop_conquest", ["arythea", "tovak"], seed)
	var a := int(e.s.turn.player)
	var b := 1 - a
	var area := clear_area(e)
	var city: String = area[0]
	var h: Dictionary = e.s.map.hex[city]
	h.site = "city"
	h.conquered = false
	h.owner = -1
	h["city"] = {"color": "white", "level": 5, "shields": [], "leader": -1}
	h.enemies = []
	for i in n_def:
		var eid := e.draw_enemy("gray", true, city)
		h.enemies.append(eid)
	e.s.players[a].pos = area[1]
	e.s.players[b].pos = area[2]
	e.s.turn.path = [area[1]]
	hand(e, a, ["march", "rage", "stamina"])
	hand(e, b, ["march", "rage", "determination"])
	return {"e": e, "a": a, "b": b, "city": city, "area": area}

func kill_all(e: MKEngine) -> void:
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"siege:phys": 99}
	var tg: Array = []
	for en in e.s.combat.enemies:
		if not en.defeated:
			tg.append(en.eid)
	ok(act(e, {"t": "attack", "targets": tg}), "sconfigge i nemici assegnati")

func test_coop_success():
	var c := coop_setup()
	var e: MKEngine = c.e
	var a: int = c.a
	var b: int = c.b
	var rep_a: int = e.s.players[a].rep
	var rep_b: int = e.s.players[b].rep
	ok(e.check({"t": "coop", "city": c.city}) == "", "assalto cooperativo proponibile")
	var found := false
	for x in e.available():
		if str(x.a.get("t", "")) == "coop":
			found = true
	ok(found, "available() propone l'assalto cooperativo")
	ok(act(e, {"t": "coop", "city": c.city}), "proposta")
	ok(e.s.pending != null and e.s.pending.handler == "coop:invite", "scelta degli invitati")
	ok(choose(e, str(b)), "invita l'alleato")
	ok(e.s.pending.handler == "coop:split", "distribuzione dei nemici")
	ok(has_opt(e, "2,1") and has_opt(e, "1,2") and not has_opt(e, "3,0"), "almeno un nemico a testa")
	ok(choose(e, "2,1"), "2 a me, 1 all'alleato")
	ok(e.s.pending.handler == "coop:accept" and int(e.s.pending.player) == b, "l'invitato decide")
	ok(choose(e, "yes"), "accetta")
	ok(e.s.players[b].skip_next, "l'invitato salterà il prossimo turno")
	ok(e.s.combat != null and e.s.combat.get("coop", false), "combatte chi ha iniziato")
	eq(int(e.s.turn.player), a, "prima chi ha iniziato")
	eq(e.s.combat.enemies.size(), 2, "affronta solo i 2 nemici assegnati")
	eq(e.s.players[a].pos, c.city, "è entrato in città")
	eq(int(e.s.players[a].rep), rep_a - 1, "assalto: Reputazione −1")
	ok(e.s.combat.enemies[0].fortified, "difensori fortificati")
	kill_all(e)
	ok(not e.s.map.hex[c.city].conquered, "la città non è ancora conquistata")
	eq(int(e.s.turn.player), b, "ora combatte l'alleato")
	ok(e.s.combat != null and e.s.combat.enemies.size() == 1, "l'alleato affronta il suo nemico")
	eq(int(e.s.players[b].rep), rep_b - 1, "anche l'alleato perde Reputazione")
	eq(int(e.s.turn.dice_allowed), 1, "l'alleato può usare un dado della Fonte")
	kill_all(e)
	ok(e.s.map.hex[c.city].conquered, "città conquistata quando tutti i difensori sono sconfitti")
	eq(int(e.s.map.hex[c.city].city.leader), a, "capo della città: chi ha più Scudi")
	eq(e.s.map.hex[c.city].city.shields.size(), 3, "uno Scudo per nemico sconfitto")
	eq(int(e.s.turn.player), a, "chi ha iniziato termina per primo il turno")
	ok(act(e, {"t": "end_turn"}), "fine turno di chi ha iniziato")
	var guard := 0
	while e.s.pending != null and guard < 20:
		guard += 1
		choose(e, e.s.pending.options[0].v)
	eq(int(e.s.turn.player), b, "poi l'alleato termina il suo turno")
	ok(act(e, {"t": "end_turn"}), "fine turno dell'alleato")
	guard = 0
	while e.s.pending != null and guard < 20 and e.s.get("coop") != null:
		guard += 1
		choose(e, e.s.pending.options[0].v)
	ok(e.s.get("coop") == null, "assalto concluso")
	ok(e.s.players[b].hand.size() >= int(e.s.players[b].hand_limit), "l'alleato ha pescato fino al limite di mano (+1 per lo Scudo sulla città)")

func test_coop_fail_and_refuse():
	var c := coop_setup(9)
	var e: MKEngine = c.e
	var a: int = c.a
	var b: int = c.b
	ok(act(e, {"t": "coop", "city": c.city}), "proposta")
	choose(e, str(b))
	choose(e, "1,2")
	ok(choose(e, "no"), "l'invitato rifiuta")
	ok(e.s.get("coop") == null and e.s.combat == null, "non succede nulla")
	ok(not e.s.players[b].get("skip_next", false), "l'invitato non salta il turno")
	ok(e.check({"t": "coop", "city": c.city}) == "", "si può fare un'altra proposta")
	ok(act(e, {"t": "coop", "city": c.city}), "seconda proposta")
	choose(e, str(b))
	choose(e, "1,2")
	ok(choose(e, "yes"), "accetta")
	kill_all(e)
	eq(int(e.s.turn.player), b, "tocca all'alleato")
	e.s.combat.phase = "attack"
	ok(act(e, {"t": "next"}), "l'alleato non sconfigge i suoi nemici")
	ok(not e.s.map.hex[c.city].conquered, "città non conquistata")
	eq(e.s.players[a].pos, c.area[1], "chi ha iniziato torna nello spazio da cui ha attaccato")
	eq(e.s.players[b].pos, c.area[2], "anche l'alleato si ritira")
	eq(e.s.map.hex[c.city].enemies.size(), 2, "i difensori non sconfitti restano in città")

## L'IA propone/accetta l'assalto e lo porta a termine senza azioni illegali.
func test_coop_ai():
	var done := 0
	for seed in [4, 11, 19]:
		var c := coop_setup(seed, 2)
		var e: MKEngine = c.e
		e.s.players[c.a].hand = []
		e.s.players[c.b].hand = []
		for id in ["rage", "determination", "swiftness", "stamina", "march"]:
			e.s.players[c.a].hand.append(e.new_iid(id))
			e.s.players[c.b].hand.append(e.new_iid(id))
		e.s.players[c.a].units.append({"uid": 900, "id": "utem_crossbowmen", "ready": true, "wounded": false})
		e.s.players[c.b].units.append({"uid": 901, "id": "utem_guardsmen", "ready": true, "wounded": false})
		AI.reset_stats()
		var started := false
		var n := 0
		var p0 := int(e.s.turn.player)
		while n < 300 and e.s.phase != "game_over":
			n += 1
			if e.s.get("coop") != null:
				started = true
			if started and e.s.get("coop") == null:
				break
			if not started and int(e.s.turn.get("player", -1)) != p0:
				break
			var x = AI.decide(e, 3)
			if x.is_empty() or not e.apply(x).ok:
				print("    IA bloccata: ", x)
				break
		if started:
			done += 1
			ok(e.s.get("coop") == null, "l'assalto cooperativo dell'IA si conclude (seed %d)" % seed)
		eq(int(AI.stats.illegal), 0, "nessuna azione illegale dell'IA (seed %d)" % seed)
	ok(done >= 1, "l'IA propone l'assalto cooperativo con un alleato adiacente (%d/3)" % done)

func test_determinism():
	var c := coop_setup(13)
	var e: MKEngine = c.e
	act(e, {"t": "coop", "city": c.city})
	choose(e, str(c.b))
	choose(e, "2,1")
	choose(e, "yes")
	var e2 := MKEngine.from_state(JSON.parse_string(JSON.stringify(e.s)))
	eq(e2.fingerprint(), MKEngine.from_state(JSON.parse_string(JSON.stringify(e.s))).fingerprint(), "stato serializzabile")
	kill_all(e)
	kill_all(e2)
	eq(e2.fingerprint(), e.fingerprint(), "assalto cooperativo deterministico dopo serializzazione")
