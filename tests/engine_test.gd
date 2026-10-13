extends SceneTree
## Focused rules tests for the engine (headless):
## godot --headless --path /home/claude/mage-knight -s res://tests/engine_test.gd

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
	# fixtures: the loader must work on any directory
	MKDB.load_dir("res://tests/fixtures")
	ok(MKDB.cards.has("march") and MKDB.enemies.has("prowlers") and MKDB.tiles.size() >= 3, "caricamento fixtures")
	var ef := MKEngine.create({"scenario": "first_recon", "seed": 3, "players": [{"hero": "arythea"}]})
	ok(ef.s.phase == "tactics", "partita con le fixtures")
	MKDB.load_dir("res://data")
	print("DB problems: ", MKDB.problems)
	for t in [test_terrain, test_mana, test_play, test_resistances, test_blocks, test_damage, test_poison_paralyze,
			test_units_damage, test_fortified, test_summon, test_level_up, test_rest, test_end_of_round, test_determinism,
			test_explore, test_interaction, test_conquest, test_specials_list, test_clone_speed, test_fuzz,
			test_concentration, test_spells_artifacts, test_unit_ability, test_sites_end_turn, test_adventure, test_dummy]:
		var before := fails
		t.call()
		print("%s %s" % ["OK " if fails == before else "ERR", t.get_method()])
	print("TEST: %d ok, %d falliti" % [passes, fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ helpers
func mk(scn := "solo_conquest", seed := 1, heroes := ["arythea"]) -> MKEngine:
	var cfg := {"scenario": scn, "seed": seed, "players": []}
	for h in heroes:
		cfg.players.append({"hero": h, "name": h})
	var e := MKEngine.create(cfg)
	while e.s.phase == "tactics" or e.s.pending != null:
		var av := e.available()
		var r := e.apply(av[0].a)
		if not r.ok:
			print(r)
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

func fight(e: MKEngine, types: Array, opts := {}) -> Array:
	var eids: Array = []
	for t in types:
		e.s.eid_seq += 1
		var eid := "t%d" % e.s.eid_seq
		e.s.enemies[eid] = {"type": t, "color": MKDB.enemies[t].color, "face_up": true, "hex": ""}
		eids.append(eid)
	if not opts.has("defenders"):
		opts["defenders"] = eids
	if not opts.has("kind"):
		opts["kind"] = "challenge"
	MKCombat.start(e, eids, opts)
	return eids

func act(e: MKEngine, a: Dictionary) -> bool:
	var r := e.apply(a)
	if not r.ok:
		print("    azione rifiutata ", a, " -> ", r.err)
	return r.ok

# ------------------------------------------------------------------ tests
func test_terrain():
	var e := mk()
	e.s.day = true
	eq(e.terrain_cost("forest"), 3, "foresta di giorno")
	eq(e.terrain_cost("desert"), 5, "deserto di giorno")
	eq(e.terrain_cost("lake"), 999, "lago invalicabile")
	e.s.day = false
	eq(e.terrain_cost("forest"), 5, "foresta di notte")
	eq(e.terrain_cost("desert"), 3, "deserto di notte")
	eq(e.terrain_cost("plains"), 2, "pianura")
	e.s.turn.mods.append({"name": "terrain", "map": {"forest": "-2", "min": 2}})
	eq(e.terrain_cost("forest"), 3, "riduzione con minimo")
	e.s.turn.mods.append({"name": "terrain", "map": {"lake": 2}})
	eq(e.terrain_cost("lake"), 2, "lago reso attraversabile")

func test_mana():
	var e := mk()
	var p := 0
	e.s.day = true
	e.s.source = [{"color": "gold", "taken_by": -1}, {"color": "black", "taken_by": -1}, {"color": "red", "taken_by": -1}]
	e.s.players[p].tokens = []
	e.s.players[p].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	ok(MKMana.plan(e, p, ["blue"]) != null, "oro di giorno vale blu")
	ok(MKMana.plan(e, p, ["blue", "red"]) == null, "un solo dado per turno")
	ok(MKMana.plan(e, p, ["black"]) == null, "nero inutilizzabile di giorno")
	e.s.day = false
	ok(MKMana.plan(e, p, ["blue"]) == null, "oro inutilizzabile di notte")
	ok(MKMana.plan(e, p, ["black"]) != null, "nero usabile di notte")
	e.s.players[p].crystals.blue = 1
	ok(MKMana.plan(e, p, ["blue", "black"]) != null, "cristallo + dado nero")

func test_play():
	var e := mk()
	var iids := hand(e, 0, ["march", "rage", "wound"])
	e.s.turn.pool.move = 0
	ok(act(e, {"t": "play", "card": iids[0], "mode": "basic"}), "gioca Marcia")
	eq(e.s.turn.pool.move, 2, "Marcia dà Movimento 2")
	ok(e.check({"t": "play", "card": iids[2], "mode": "side", "side": "move"}) != "", "le ferite non si giocano")
	ok(e.check({"t": "play", "card": iids[1], "mode": "basic"}) != "", "Furia (attacco/blocco) non utilizzabile fuori dal combattimento")
	ok(act(e, {"t": "play", "card": iids[1], "mode": "side", "side": "move"}), "Furia di lato")
	eq(e.s.turn.pool.move, 3, "di lato +1")

func test_resistances():
	var e := mk()
	var eids := fight(e, ["golems"])   # armor 5, phys resistance
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:phys": 9}
	eq(e.effective_attack(eids), 4, "attacco fisico dimezzato dalla resistenza")
	ok(e.check({"t": "attack", "targets": eids}) != "", "attacco insufficiente rifiutato")
	e.s.turn.pool.attack = {"melee:phys": 6, "melee:fire": 3}
	eq(e.effective_attack(eids), 6, "parti inefficienti sommate e poi dimezzate")
	ok(act(e, {"t": "attack", "targets": eids}), "attacco riuscito")
	ok(e.s.combat == null, "combattimento finito quando tutti i nemici sono sconfitti")
	var e2 := mk()
	var d2 := fight(e2, ["high_dragon"])  # resist fire+ice
	e2.s.combat.phase = "attack"
	e2.s.turn.pool.attack = {"melee:cold": 10, "melee:fire": 4}
	eq(e2.effective_attack(d2), 7, "fuoco-ghiaccio dimezzato solo con entrambe le resistenze")

func test_blocks():
	var e := mk()
	var eids := fight(e, ["fire_mages"])  # fire attack 6
	act(e, {"t": "next"})
	eq(e.s.combat.phase, "block", "fase di blocco")
	e.s.turn.pool.block = {"phys": 6}
	eq(e.effective_block(eids[0]), 3, "blocco fisico contro fuoco inefficiente")
	e.s.turn.pool.block = {"ice": 6}
	eq(e.effective_block(eids[0]), 6, "blocco di ghiaccio efficiente contro il fuoco")
	ok(act(e, {"t": "block", "eid": eids[0]}), "blocco riuscito")
	var e2 := mk()
	var w := fight(e2, ["wolf_riders"])  # swift 3
	act(e2, {"t": "next"})
	e2.s.turn.pool.block = {"phys": 5}
	ok(e2.check({"t": "block", "eid": w[0]}) != "", "Rapido: serve il doppio del blocco")
	e2.s.turn.pool.block = {"phys": 6}
	ok(e2.check({"t": "block", "eid": w[0]}) == "", "Rapido: blocco doppio sufficiente")

func test_damage():
	var e := mk()
	var p := 0
	hand(e, p, ["march", "rage", "stamina"])
	e.s.players[p].armor = 2
	var eids := fight(e, ["ironclads"])  # 4 brutal
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	eq(e.s.combat.phase, "damage", "fase danni")
	ok(act(e, {"t": "damage", "eid": eids[0], "to": "hero"}), "danno all'eroe")
	var w := 0
	for iid in e.s.players[p].hand:
		if e.is_wound(iid):
			w += 1
	eq(w, 4, "Brutale: 8 danni con armatura 2 = 4 ferite")
	ok(e.s.players[p].knocked_out == false, "non fuori combattimento con 4 ferite (limite 5)")
	var e2 := mk()
	hand(e2, p, ["march", "rage"])
	e2.s.players[p].armor = 2
	var g := fight(e2, ["ironclads", "prowlers"])
	act(e2, {"t": "next"})
	act(e2, {"t": "next"})
	act(e2, {"t": "damage", "eid": g[0], "to": "hero"})
	act(e2, {"t": "damage", "eid": g[1], "to": "hero"})
	ok(e2.s.players[p].knocked_out, "fuori combattimento con 6 ferite")
	var nonw := 0
	for iid in e2.s.players[p].hand:
		if not e2.is_wound(iid):
			nonw += 1
	eq(nonw, 0, "KO: carte non-ferita scartate")

func test_poison_paralyze():
	var e := mk()
	var p := 0
	hand(e, p, ["march"])
	e.s.players[p].armor = 3
	e.s.players[p].discard = []
	var eids := fight(e, ["cursed_hags"])  # 3 poison
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	act(e, {"t": "damage", "eid": eids[0], "to": "hero"})
	var wd := 0
	for iid in e.s.players[p].discard:
		if e.is_wound(iid):
			wd += 1
	eq(wd, 1, "Velenoso: una ferita anche negli scarti")
	var e2 := mk()
	hand(e2, p, ["march", "rage", "stamina"])
	var g := fight(e2, ["ice_golems"])  # paralyze ice 2
	act(e2, {"t": "next"})
	act(e2, {"t": "next"})
	act(e2, {"t": "damage", "eid": g[0], "to": "hero"})
	var nonw := 0
	for iid in e2.s.players[p].hand:
		if not e2.is_wound(iid):
			nonw += 1
	eq(nonw, 0, "Paralizzante: scarta le carte non-ferita")

func test_units_damage():
	var e := mk()
	var p := 0
	MKSites.gain_unit(e, p, "utem_guardsmen")  # armor 5, no resist
	MKSites.gain_unit(e, p, "guardian_golems") if MKDB.units.has("guardian_golems") else null
	var u: Dictionary = e.s.players[p].units[0]
	var eids := fight(e, ["prowlers"])  # 4 phys
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	ok(act(e, {"t": "damage", "eid": eids[0], "to": int(u.uid)}), "danno a un'unità")
	ok(u.wounded, "unità ferita")
	eq(int(e.s.combat.enemies[0].attacks[0].rem), 0, "danno completamente assorbito")
	if e.s.players[p].units.size() > 1:
		var e2 := mk()
		MKSites.gain_unit(e2, p, "guardian_golems")
		var gu: Dictionary = e2.s.players[p].units[0]
		var g := fight(e2, ["diggers"])
		act(e2, {"t": "next"})
		act(e2, {"t": "next"})
		act(e2, {"t": "damage", "eid": g[0], "to": int(gu.uid)})
		ok(not gu.wounded, "unità resistente assorbe senza ferirsi")
		ok(e2.check({"t": "next"}) == "", "danno assorbito dalla resistenza")
	var e3 := mk()
	MKSites.gain_unit(e3, p, "peasants")
	var pu: Dictionary = e3.s.players[p].units[0]
	var h := fight(e3, ["cursed_hags"])
	act(e3, {"t": "next"})
	act(e3, {"t": "next"})
	act(e3, {"t": "damage", "eid": h[0], "to": int(pu.uid)})
	eq(int(pu.wounds), 2, "unità avvelenata: due ferite")
	var e4 := mk()
	e4.s.players[p].units = []
	MKSites.gain_unit(e4, p, "peasants")
	var dd := fight(e4, ["prowlers"], {"kind": "site", "site_type": "dungeon"})
	ok(not e4.s.combat.units_allowed, "niente unità nel dungeon")
	ok(e4.s.combat.night_rules, "regole notturne nel dungeon")

func test_fortified():
	var e := mk()
	var eids := fight(e, ["diggers"])  # fortified armor 3
	e.s.turn.pool.attack = {"ranged:phys": 5}
	ok(e.check({"t": "attack", "targets": eids}) != "", "a distanza non colpisce i fortificati")
	e.s.turn.pool.attack = {"siege:phys": 3}
	ok(e.check({"t": "attack", "targets": eids}) == "", "l'assedio colpisce i fortificati")
	var e2 := mk()
	var g := fight(e2, ["diggers"], {"assault": true, "site_type": "keep"})
	e2.s.turn.pool.attack = {"siege:phys": 10}
	ok(e2.check({"t": "attack", "targets": g}) != "", "doppiamente fortificato non attaccabile a distanza")

func test_summon():
	var e := mk()
	var eids := fight(e, ["orc_summoners"])
	act(e, {"t": "next"})
	eq(e.s.combat.enemies.size(), 2, "l'evocatore evoca un nemico marrone")
	ok(e.s.combat.enemies[0].hidden, "l'evocatore è nascosto in fase di blocco")
	act(e, {"t": "next"})
	if e.s.combat.phase == "damage":
		act(e, {"t": "damage", "eid": e.s.combat.enemies[1].eid, "to": "hero"})
		act(e, {"t": "next"})
	eq(e.s.combat.phase, "attack", "fase di attacco")
	ok(not e.s.combat.enemies[0].hidden and e.s.combat.enemies[1].defeated, "l'evocato se ne va in fase d'attacco")

func test_level_up():
	var e := mk()
	var p := 0
	hand(e, p, ["march", "rage"])
	act(e, {"t": "play", "card": e.s.players[p].hand[0], "mode": "basic"})
	e.gain_fame(p, 3)
	ok(act(e, {"t": "end_turn"}), "fine turno")
	eq(e.s.players[p].level, 2, "livello 2 con 3 Fama")
	ok(e.s.pending != null and e.s.pending.handler == "level_skill", "scelta dell'abilità al livello pari")
	act(e, {"t": "choose", "v": [e.s.pending.options[0].v]})
	ok(e.s.pending != null and e.s.pending.handler == "level_aa", "scelta dell'azione avanzata")
	act(e, {"t": "choose", "v": [e.s.pending.options[0].v]})
	eq(e.s.players[p].skills.size(), 1, "abilità ottenuta")

func test_rest():
	var e := mk()
	var p := 0
	var iids := hand(e, p, ["march", "wound", "wound"])
	ok(act(e, {"t": "rest"}), "riposo standard")
	ok(e.s.pending != null, "scelta delle ferite da scartare")
	act(e, {"t": "choose", "v": ["all"]})
	eq(e.s.players[p].hand.size(), 0, "riposo: scartate la carta e le ferite")
	var e2 := mk()
	hand(e2, p, ["wound", "wound"])
	ok(e2.check({"t": "end_turn"}) != "", "solo ferite: non puoi terminare senza riposare")
	ok(e2.check({"t": "move", "to": MKHex.neighbors(e2.s.players[p].pos)[0]}) != "", "solo ferite: non puoi muoverti")
	ok(act(e2, {"t": "rest"}), "lunga guarigione")
	eq(e2.s.players[p].hand.size(), 1, "lunga guarigione scarta una ferita")

func test_end_of_round():
	var e := mk()
	var p := 0
	e.s.players[p].discard.append_array(e.s.players[p].deck)
	e.s.players[p].deck = []
	hand(e, p, ["march"])
	ok(e.check({"t": "announce_end"}) == "", "annuncio possibile con il mazzo vuoto")
	var r0: int = e.s.round
	act(e, {"t": "announce_end"})
	ok(e.s.round == r0 + 1 or e.s.phase == "tactics", "nuovo round dopo l'annuncio (solitario)")
	eq(e.s.day, false, "il secondo round è Notte")
	eq(e.s.players[p].hand.size(), 5, "nuova mano a inizio round")
	var basic := 0
	for d in e.s.source:
		if d.color in MKMana.BASIC:
			basic += 1
	ok(basic * 2 >= e.s.source.size(), "almeno metà dadi di colore base")
	ok(e.s.offers.spells.size() == mini(3, e.s.offers.spells.size() + e.s.decks.spells.size()), "offerta incantesimi rinnovata")

func test_determinism():
	var cfg := {"scenario": "full_conquest", "seed": 77, "players": [{"hero": "arythea"}, {"hero": "tovak"}]}
	var e1 := MKEngine.create(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var hist: Array = []
	for i in 400:
		if e1.s.phase == "game_over":
			break
		var av := e1.available()
		var a: Dictionary = av[rng.randi() % av.size()].a
		hist.append(a.duplicate(true))
		e1.apply(a)
	var e2 := MKEngine.create(cfg)
	for a in hist:
		e2.apply(a)
	eq(e2.fingerprint(), e1.fingerprint(), "stessa sequenza => stessa impronta")
	var e3 := MKEngine.from_state(JSON.parse_string(JSON.stringify(e1.s)))
	eq(e3.fingerprint(), e1.fingerprint(), "salvataggio/ripristino JSON")
	for i in 300:
		if e1.s.phase == "game_over":
			break
		var av2 := e1.available()
		var a2: Dictionary = JSON.parse_string(JSON.stringify(av2[rng.randi() % av2.size()].a))
		var r1 := e1.apply(a2)
		var r3 := e3.apply(a2)
		if r1.ok != r3.ok:
			ok(false, "ripristino: esito diverso per " + JSON.stringify(a2))
			break
	eq(e3.fingerprint(), e1.fingerprint(), "dopo il ripristino la partita prosegue identica (azioni via JSON)")
	var e4 := MKEngine.create({"scenario": "full_conquest", "seed": 78, "players": cfg.players})
	ok(e4.fingerprint() != MKEngine.create(cfg).fingerprint(), "seme diverso => partita diversa")

func test_explore():
	var e := mk("first_recon", 4)
	var p := 0
	# put the hero next to the frontier
	var best := ""
	for k in e.s.map.hex:
		e.s.players[p].pos = k
		if not e.explorable_slots(p).is_empty() and e.s.map.hex[k].t in ["plains", "forest", "hills"]:
			best = k
			break
	ok(best != "", "esiste una posizione da cui esplorare")
	e.s.turn.pool.move = 2
	var slot: String = e.explorable_slots(p)[0]
	var n0: int = e.s.map.tiles.size()
	var f0: int = e.s.players[p].fame
	ok(act(e, {"t": "explore", "slot": slot}), "esplorazione")
	eq(e.s.map.tiles.size(), n0 + 1, "nuova tessera")
	eq(e.s.players[p].fame, f0 + 1, "Prima ricognizione: +1 Fama per tessera")
	eq(e.s.turn.pool.move, 0, "esplorare costa 2")

func test_interaction():
	var e := mk()
	var p := 0
	var vil := ""
	for k in e.s.map.hex:
		if e.s.map.hex[k].site == "village":
			vil = k
	if vil == "":
		e.s.map.hex[e.s.players[p].pos].site = "village"
		vil = e.s.players[p].pos
	e.s.players[p].pos = vil
	var iids := hand(e, p, ["promise", "wound", "wound"])
	act(e, {"t": "play", "card": iids[0], "mode": "basic"})
	e.s.turn.pool.influence = 6
	ok(e.check({"t": "buy", "what": "heal"}) == "", "comprare guarigione al villaggio")
	act(e, {"t": "buy", "what": "heal"})
	var w := 0
	for iid in e.s.players[p].hand:
		if e.is_wound(iid):
			w += 1
	eq(w, 1, "guarita una ferita")
	ok(e.s.turn.acted, "interagire è l'azione del turno")
	ok(e.check({"t": "move", "to": MKHex.neighbors(vil)[0]}) != "", "niente movimento dopo l'azione")

func test_conquest():
	var e := mk()
	var p := 0
	var keep := ""
	for k in e.s.map.hex:
		if e.s.map.hex[k].site == "keep":
			keep = k
	if keep == "":
		keep = MKHex.neighbors(e.s.players[p].pos)[3]
		e.s.map.hex[keep].site = "keep"
		e.s.map.hex[keep].t = "plains"
		var g := e.draw_enemy("gray", false, keep)
		e.s.map.hex[keep].enemies = [g]
	var from := ""
	for nk in MKHex.neighbors(keep):
		if e.s.map.hex.has(nk) and e.s.map.hex[nk].t in ["plains", "hills", "forest"] and e.s.map.hex[nk].enemies.is_empty():
			from = nk
	e.s.players[p].pos = from
	hand(e, p, ["march"])
	e.s.turn.pool.move = 9
	var rep0: int = e.s.players[p].rep
	ok(act(e, {"t": "move", "to": keep}), "assalto alla fortezza")
	ok(e.s.combat != null and e.s.combat.kind == "assault", "combattimento d'assalto")
	eq(e.s.players[p].rep, rep0 - 1, "assalto: Reputazione -1")
	for en in e.s.combat.enemies:
		ok(en.fortified, "difensori fortificati")
	# win
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:phys": 30}
	var tg: Array = []
	for en in e.s.combat.enemies:
		tg.append(en.eid)
	ok(act(e, {"t": "attack", "targets": tg}), "difensori sconfitti")
	ok(e.s.map.hex[keep].conquered and int(e.s.map.hex[keep].owner) == p, "fortezza conquistata")
	ok(keep in e.s.players[p].shields, "scudo sulla fortezza")
	ok(e.hand_limit_now(p) == e.s.players[p].hand_limit + 1, "limite di mano +1 vicino alla propria fortezza")

func test_specials_list():
	var impl := MKSpecials.implemented()
	ok(impl.size() > 0, "elenco degli speciali implementati")
	var missing := 0
	for c in MKDB.cards:
		if MKDB.cards[c].get("set", "") == "base" and not MKDB.card_ok(c):
			missing += 1
	print("    carte base non disponibili: ", missing)

func test_clone_speed():
	var e := mk("full_conquest", 9, ["arythea", "goldyx"])
	var t0 := Time.get_ticks_usec()
	for i in 100:
		e.available()
	var t1 := Time.get_ticks_usec()
	for i in 100:
		e.clone()
	var t2 := Time.get_ticks_usec()
	print("    available(): %.2f ms  clone(): %.2f ms" % [(t1 - t0) / 100000.0, (t2 - t1) / 100000.0])
	ok((t1 - t0) / 100000.0 < 20.0, "available() abbastanza veloce")

func test_fuzz():
	# malformed / random actions must be rejected cleanly (no crash, no state change)
	var e := mk("full_conquest", 11, ["arythea", "goldyx"])
	var rng := RandomNumberGenerator.new()
	rng.seed = 99 + int(OS.get_environment("FUZZ_SEED")) if OS.get_environment("FUZZ_SEED") != "" else 99
	var ts := ["play", "move", "explore", "unit", "skill", "site", "recruit", "buy", "plunder", "burn", "altar", "challenge",
		"rest", "end_turn", "announce_end", "attack", "block", "damage", "next", "choose", "tactic", "heal", "sp", "tactic_use", "xyz", ""]
	var vals := [null, 0, -1, 99, "x", "0,0", [], ["e1"], {}, [1, 2], "march#1", 1.5, true]
	var rejected := 0
	var iters := int(OS.get_environment("FUZZ_N")) if OS.get_environment("FUZZ_N") != "" else 600
	for i in iters:
		var a := {"t": ts[rng.randi() % ts.size()]}
		for k in ["card", "mode", "side", "to", "slot", "uid", "ability", "id", "targets", "eid", "attack", "v", "what", "hexes", "mana", "target", "name", "opt", "disband"]:
			if rng.randf() < 0.3:
				a[k] = vals[rng.randi() % vals.size()]
		var fp := e.fingerprint()
		var r := e.apply(a)
		if not r.ok:
			rejected += 1
			if e.fingerprint() != fp:
				ok(false, "azione rifiutata ha modificato lo stato: " + JSON.stringify(a))
				return
		if e.s.phase == "game_over":
			break
		# keep the game going with a legal action from time to time
		if i % 3 == 0:
			var av := e.available()
			if not av.is_empty():
				e.apply(av[rng.randi() % av.size()].a)
	ok(rejected > 100, "azioni casuali rifiutate senza errori")

func test_concentration():
	var e := mk()
	var p := 0
	var iids := hand(e, p, ["concentration", "march"])
	e.s.players[p].crystals.green = 1
	e.s.turn.pool.move = 0
	ok(act(e, {"t": "play", "card": iids[0], "mode": "powered"}), "Concentrazione potenziata")
	if e.s.pending != null:
		act(e, {"t": "choose", "v": [e.s.pending.options[0].v]})
	eq(e.s.turn.pool.move, 6, "Marcia potenziata gratis +2 = Movimento 6")
	var e2 := mk()
	var j := hand(e2, p, ["concentration", "rage"])
	e2.s.players[p].crystals.green = 1
	ok(e2.check({"t": "play", "card": j[0], "mode": "powered"}) != "", "Concentrazione senza carte utilizzabili rifiutata")

func test_spells_artifacts():
	var e := mk()
	var p := 0
	var ids := hand(e, p, ["fireball", "ruby_ring"])
	e.s.day = true
	e.s.players[p].crystals.red = 2
	e.s.source = [{"color": "black", "taken_by": -1}, {"color": "red", "taken_by": -1}]
	fight(e, ["prowlers"])
	ok(e.check({"t": "play", "card": ids[0], "mode": "powered"}) != "", "incantesimo potenziato impossibile di giorno")
	ok(act(e, {"t": "play", "card": ids[0], "mode": "basic"}), "Palla di fuoco base")
	eq(e.s.turn.pool.attack.get("ranged:fire", 0), 5, "Attacco a distanza di fuoco 5")
	var e2 := mk()
	var ids2 := hand(e2, p, ["fireball"])
	e2.s.day = false
	e2.s.players[p].crystals.red = 1
	e2.s.source = [{"color": "black", "taken_by": -1}]
	fight(e2, ["prowlers"])
	ok(act(e2, {"t": "play", "card": ids2[0], "mode": "powered"}), "incantesimo potenziato di notte con il nero")
	eq(e2.s.turn.pool.attack.get("siege:fire", 0), 8, "Attacco d'assedio di fuoco 8")
	var e3 := mk()
	var ids3 := hand(e3, p, ["endless_bag_of_gold", "march"])
	act(e3, {"t": "play", "card": ids3[0], "mode": "powered"})
	act(e3, {"t": "end_turn"})
	while e3.s.pending != null and e3.actor() == p:
		act(e3, {"t": "choose", "v": [e3.s.pending.options[0].v]})
	ok(ids3[0] in e3.s.players[p].removed, "artefatto potenziato distrutto")

func test_unit_ability():
	var e := mk()
	var p := 0
	MKSites.gain_unit(e, p, "herbalists")
	var u: Dictionary = e.s.players[p].units[0]
	hand(e, p, ["wound", "march"])
	e.s.players[p].crystals.green = 0
	e.s.players[p].tokens = []
	e.s.source = [{"color": "red", "taken_by": -1}]
	ok(e.check({"t": "unit", "uid": int(u.uid), "ability": 0}) != "", "abilità con mana verde non pagabile")
	e.s.players[p].crystals.green = 1
	ok(act(e, {"t": "unit", "uid": int(u.uid), "ability": 0}), "Erboristi: Cura 2 pagando verde")
	ok(not u.ready, "unità esaurita dopo l'uso")
	var w := 0
	for iid in e.s.players[p].hand:
		if e.is_wound(iid):
			w += 1
	eq(w, 0, "ferita guarita")

func test_sites_end_turn():
	var e := mk()
	var p := 0
	var mine := ""
	for k in e.s.map.hex:
		if e.s.map.hex[k].get("mine", "") != "":
			mine = k
	if mine == "":
		mine = e.s.players[p].pos
		e.s.map.hex[mine].mine = "blue"
	var col: String = e.s.map.hex[mine].mine
	e.s.players[p].pos = mine
	e.s.players[p].crystals[col] = 0
	var ids := hand(e, p, ["march", "rage"])
	act(e, {"t": "play", "card": ids[0], "mode": "basic"})
	act(e, {"t": "end_turn"})
	eq(int(e.s.players[p].crystals[col]), 1, "miniera: cristallo a fine turno")

func test_adventure():
	var e := mk()
	var p := 0
	var k: String = e.s.players[p].pos
	e.s.map.hex[k].site = "monster_den"
	e.s.map.hex[k].enemies = []
	e.s.map.hex[k].conquered = false
	var ids := hand(e, p, ["march", "rage"])
	ok(act(e, {"t": "site"}), "entra nella tana dei mostri")
	ok(e.s.combat != null and e.s.combat.kind == "site", "combattimento nel sito")
	ok(e.s.combat.units_allowed, "unità permesse nella tana")
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:cold": 30}
	var tg: Array = []
	for en in e.s.combat.enemies:
		tg.append(en.eid)
	act(e, {"t": "attack", "targets": tg})
	ok(e.s.map.hex[k].conquered, "tana conquistata")
	eq(e.s.turn.rewards.size(), 1, "ricompensa in attesa per fine turno")
	var cr0 := 0
	for c in e.s.players[p].crystals:
		cr0 += int(e.s.players[p].crystals[c])
	var f0: int = e.s.players[p].fame
	act(e, {"t": "end_turn"})
	while e.s.pending != null and e.actor() == p:
		act(e, {"t": "choose", "v": [e.s.pending.options[0].v]})
	var cr1 := 0
	for c in e.s.players[p].crystals:
		cr1 += int(e.s.players[p].crystals[c])
	ok(cr1 - cr0 + (int(e.s.players[p].fame) - f0) >= 2, "due cristalli tirati (o Fama per il nero)")

func test_dummy():
	var e := mk("solo_conquest", 5)
	ok(e.s.dummy != null, "giocatore neutrale presente")
	var cr := 0
	for c in e.s.dummy.crystals:
		cr += int(e.s.dummy.crystals[c])
	eq(cr, 3, "3 cristalli del neutrale")
	ok(9 in e.s.turn_order, "neutrale nell'ordine di turno")
	var n0: int = e.s.dummy.deck.size() + e.s.dummy.discard.size()
	eq(n0, 16, "mazzo del neutrale di 16 carte")
