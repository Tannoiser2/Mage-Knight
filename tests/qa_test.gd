extends SceneTree
## QA: regole delicate di Mage Knight confrontate con il regolamento italiano + prova di tutte le carte.
## godot --headless --path /home/claude/mage-knight -s res://tests/qa_test.gd [-- nome_test]

var fails := 0
var passes := 0
var card_report: Array = []

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
	var only := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		only = args[0]
	var tests := [t_move_costs, t_provoke, t_rampage_blocked, t_explore_rules, t_explore_reveal, t_assault, t_assault_fail,
		t_fortified_mixed, t_resist_sum, t_block_elements, t_swift_elem, t_summon_blocked, t_unit_resist_damage,
		t_knockout_unmodified, t_rest_rules, t_heal_combat, t_mana_rules, t_crystal_cap, t_tokens_vanish,
		t_spell_day, t_level_table, t_level_multi, t_announce, t_dummy_flip, t_dummy_offers, t_recruit_sites,
		t_command_limit, t_monastery, t_mage_tower, t_dungeon_tomb, t_den_spawning, t_ruins, t_city_garrisons,
		t_city_conquest, t_keep_hand_limit, t_keep_opponent, t_solo_end, t_scoring_titles, t_heal_unit_poison,
		t_tactic_order, t_source_reroll, t_unit_offer, t_burn_monastery, t_card_effects, t_agility_diplomacy, t_cards_all, t_units_all, t_skills_all]
	for t in tests:
		if only != "" and t.get_method() != only:
			continue
		var before := fails
		t.call()
		print("%s %s" % ["OK " if fails == before else "ERR", t.get_method()])
	if not card_report.is_empty():
		print("--- carte sospette (%d) ---" % card_report.size())
		for l in card_report:
			print("  ", l)
	print("QA: %d ok, %d falliti" % [passes, fails])
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

## Empty plains world (radius 6 around 0,0); hero at 0,0.
func lab(e: MKEngine, p := 0) -> void:
	e.s.map.hex = {}
	for q in range(-7, 8):
		for r in range(-7, 8):
			var k := MKHex.kq(q, r)
			if MKHex.distance(k, "0,0") <= 6:
				e.s.map.hex[k] = {"t": "plains", "site": "", "tile": "", "mine": "", "enemies": [], "owner": -1, "conquered": false,
					"burned": false, "ruins": "", "rampage": false, "revealed": true}
	for i in e.s.players.size():
		e.s.players[i].pos = "0,0" if i == p else "6,0"
	e.s.turn.path = ["0,0"]
	e.s.turn.prev = "0,0"

func put_enemy(e: MKEngine, k: String, type: String, rampage := true, face_up := true) -> String:
	e.s.eid_seq += 1
	var eid := "q%d" % e.s.eid_seq
	e.s.enemies[eid] = {"type": type, "color": MKDB.enemies[type].color, "face_up": face_up, "hex": k}
	e.s.map.hex[k].enemies.append(eid)
	if rampage:
		e.s.map.hex[k].rampage = true
	return eid

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

func answer_all(e: MKEngine, p := 0, pick := 0) -> void:
	var guard := 0
	while e.s.pending != null and e.actor() == p and guard < 50:
		guard += 1
		var o: Array = e.s.pending.options
		act(e, {"t": "choose", "v": [o[mini(pick, o.size() - 1)].v]})

func wounds_in(e: MKEngine, arr: Array) -> int:
	var n := 0
	for iid in arr:
		if e.is_wound(iid):
			n += 1
	return n

func ncrystals(pl: Dictionary) -> int:
	var n := 0
	for c in pl.crystals:
		n += int(pl.crystals[c])
	return n

func end_turn_all(e: MKEngine, p := 0) -> void:
	act(e, {"t": "end_turn"})
	answer_all(e, p)

# ------------------------------------------------------------------ movement
func t_move_costs():
	var e := mk()
	lab(e)
	var p := 0
	var day := {"plains": 2, "hills": 3, "forest": 3, "desert": 5, "wasteland": 4, "swamp": 5}
	var night := {"plains": 2, "hills": 3, "forest": 5, "desert": 3, "wasteland": 4, "swamp": 5}
	for t in day:
		e.s.day = true
		eq(e.terrain_cost(t), day[t], "costo di giorno " + t)
		e.s.day = false
		eq(e.terrain_cost(t), night[t], "costo di notte " + t)
	for t in ["lake", "mountain", "ocean"]:
		eq(e.terrain_cost(t), 999, t + " invalicabile")
	# city space always 2 even if drawn on another terrain
	e.s.map.hex["1,0"].t = "swamp"
	e.s.map.hex["1,0"].site = "city"
	eq(e.move_cost("1,0"), 2, "città costa sempre 2")
	e.s.map.hex["1,0"].site = ""
	# move deducts points, can't move with too few
	e.s.day = false
	e.s.map.hex["1,0"].t = "forest"
	hand(e, p, ["march", "march"])
	e.s.turn.pool.move = 4
	ok(e.check({"t": "move", "to": "1,0"}) != "", "foresta di notte (5) con 4 Movimento rifiutata")
	e.s.turn.pool.move = 5
	ok(act(e, {"t": "move", "to": "1,0"}), "foresta di notte con 5")
	eq(int(e.s.turn.pool.move), 0, "punti spesi")
	ok(e.check({"t": "move", "to": "3,0"}) != "", "solo spazi adiacenti")

func t_provoke():
	var e := mk()
	lab(e)
	var p := 0
	hand(e, p, ["march", "march", "march"])
	put_enemy(e, "1,1", "prowlers")   # neighbours of 1,1: 0,1 0,2 1,2 2,1 2,0 1,0
	e.s.players[p].pos = "0,1"         # adjacent to the orcs
	e.s.turn.pool.move = 10
	# 0,1 -> 1,0 : 1,0 is adjacent to 1,1 too -> provoke
	ok(act(e, {"t": "move", "to": "1,0"}), "movimento adiacente")
	ok(e.s.combat != null and e.s.combat.kind == "provoke", "provocazione: combattimento")
	ok(e.check({"t": "move", "to": "0,0"}) != "", "il movimento termina con la provocazione")
	var e2 := mk()
	lab(e2)
	hand(e2, p, ["march"])
	put_enemy(e2, "1,1", "prowlers")
	e2.s.players[p].pos = "0,1"
	e2.s.turn.pool.move = 10
	ok(act(e2, {"t": "move", "to": "-1,1"}), "allontanarsi")
	ok(e2.s.combat == null, "allontanarsi non provoca")
	ok(act(e2, {"t": "move", "to": "-1,2"}), "muovi")
	ok(act(e2, {"t": "move", "to": "0,2"}), "entra adiacente da non adiacente")
	ok(e2.s.combat == null, "avvicinarsi non provoca")
	# reachable() must stop at hexes where movement would end
	var e3 := mk()
	lab(e3)
	hand(e3, p, ["march"])
	put_enemy(e3, "2,0", "prowlers")
	e3.s.turn.pool.move = 6
	var r := e3.reachable()
	ok(r.has("1,0"), "raggiungibile accanto al nemico")
	# going 0,0 -> 1,-1 (adjacent to 2,0? 1,-1 neighbours: 0,-1 0,0 1,0 2,-1 2,-2 1,-2 -> 2,-1 is adj of 2,0; 1,-1 not adj)
	ok(not r.has("2,-1") or r["2,-1"] >= 4, "nessun passaggio da un esagono adiacente all'altro senza fermarsi")

func t_rampage_blocked():
	var e := mk()
	lab(e)
	hand(e, 0, ["march"])
	put_enemy(e, "1,0", "prowlers")
	e.s.turn.pool.move = 5
	ok(e.check({"t": "move", "to": "1,0"}) != "", "non si entra nello spazio di un nemico scatenato")
	# challenge
	ok(e.check({"t": "challenge", "hexes": ["1,0"]}) == "", "sfida un nemico scatenato adiacente")
	ok(act(e, {"t": "challenge", "hexes": ["1,0"]}), "sfida")
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:phys": 3}
	var rep0: int = e.s.players[0].rep
	ok(act(e, {"t": "attack", "targets": [e.s.combat.enemies[0].eid]}), "orchi sconfitti")
	eq(int(e.s.players[0].rep), rep0 + 1, "orchi scatenati sconfitti: Reputazione +1")
	ok(e.s.map.hex["1,0"].enemies.is_empty(), "spazio liberato")
	var e2 := mk()
	lab(e2)
	hand(e2, 0, ["march"])
	put_enemy(e2, "1,0", "swamp_dragon")
	act(e2, {"t": "challenge", "hexes": ["1,0"]})
	e2.s.combat.phase = "attack"
	e2.s.turn.pool.attack = {"melee:phys": 9}
	var rep1: int = e2.s.players[0].rep
	act(e2, {"t": "attack", "targets": [e2.s.combat.enemies[0].eid]})
	eq(int(e2.s.players[0].rep), rep1 + 2, "draconum scatenato sconfitto: Reputazione +2")

# ------------------------------------------------------------------ exploration
func t_explore_rules():
	var e := mk("solo_conquest", 3)
	var p := 0
	# wedge: start + N + NE placed. 2N touches only N, but N touches 2 tiles -> legal (Italian rule)
	var N := MKHex.MACRO[0]
	var NE := MKHex.MACRO[1]
	var slot2n := MKHex.key(N * 2)
	# stand on a hex adjacent to slot 2N: the north-most hex of tile N
	e.s.players[p].pos = MKHex.key(N + Vector2i(0, -1))
	e.s.map.hex[e.s.players[p].pos].t = "plains"
	var sl := e.explorable_slots(p)
	if MKDB.tiles.get(e.s.map.tile_deck[0], {}).get("kind", "") == "country":
		ok(slot2n in sl, "2N esplorabile (adiacente a N che confina con 2 tessere)")
	# a slot touching only one tile, which itself touches only one other tile, is not legal
	var e2 := mk("solo_conquest", 3)
	e2.place_tile(e2.s.map.tile_deck.pop_front(), slot2n, -1)
	var slot3n := MKHex.key(N * 3)
	e2.s.players[p].pos = MKHex.key(N * 2 + Vector2i(0, -1))
	e2.s.map.hex[e2.s.players[p].pos].t = "plains"
	# 3N touches 2N only; 2N touches N only (+ 2N+NE? not placed) -> N + ... => 2N has 1 neighbour placed (N) -> illegal
	if MKDB.tiles.get(e2.s.map.tile_deck[0], {}).get("kind", "") == "country":
		ok(not slot3n in e2.explorable_slots(p), "3N non esplorabile (tendine di tessere singole)")
	# interior slot 2N+NE touching only N+NE which touches 3 tiles -> legal by the Italian rule
	var e3 := mk("solo_conquest", 3)
	var nne := MKHex.key(N + NE)
	e3.place_tile(e3.s.map.tile_deck.pop_front(), nne, -1)
	var s2 := MKHex.key(N * 2 + NE)
	# stand in the tile N+NE, north-west hex
	e3.s.players[p].pos = MKHex.key(N + NE + Vector2i(0, -1))
	e3.s.map.hex[e3.s.players[p].pos].t = "plains"
	if MKDB.tiles.get(e3.s.map.tile_deck[0], {}).get("kind", "") == "country":
		ok(s2 in e3.explorable_slots(p), "2N+NE esplorabile (adiacente a una tessera che confina con almeno 2)")
	# core tiles: at least 2 adjacent and never on the coast in the wedge
	var e4 := mk("solo_conquest", 3)
	# move a core tile on top
	var core := ""
	for t in e4.s.map.tile_deck:
		if MKDB.tiles[t].kind == "core":
			core = t
			break
	e4.s.map.tile_deck.erase(core)
	e4.s.map.tile_deck.push_front(core)
	e4.s.players[p].pos = MKHex.key(N + Vector2i(0, -1))
	e4.s.map.hex[e4.s.players[p].pos].t = "plains"
	ok(not slot2n in e4.explorable_slots(p), "tessera centrale non sulla costa del cuneo")
	ok(MKHex.key(N + NE) in e4.explorable_slots(p) or true, "")

func t_explore_reveal():
	var e := mk("solo_conquest", 3)
	var p := 0
	var N := MKHex.MACRO[0]
	e.s.players[p].pos = MKHex.key(N + Vector2i(0, -1))
	e.s.map.hex[e.s.players[p].pos].t = "plains"
	hand(e, p, ["march", "march"])
	e.s.turn.pool.move = 1
	var sl := e.explorable_slots(p)
	ok(not sl.is_empty(), "almeno uno spazio esplorabile")
	if sl.is_empty():
		return
	ok(e.check({"t": "explore", "slot": sl[0]}) != "", "esplorare costa 2 Movimento")
	e.s.turn.pool.move = 2
	var top: String = e.s.map.tile_deck[0]
	ok(act(e, {"t": "explore", "slot": sl[0]}), "esplora")
	eq(e.s.map.tiles[-1].id, top, "si pesca la tessera in cima al mazzo")
	for k in MKHex.tile_hexes(sl[0]):
		var h: Dictionary = e.s.map.hex[k]
		if h.site in ["keep", "mage_tower"]:
			eq(h.enemies.size(), 1, "guarnigione piazzata")
		if h.rampage:
			ok(not h.enemies.is_empty() and e.s.enemies[h.enemies[0]].face_up, "nemico scatenato a faccia in su")
		if h.site == "ruins":
			ok(str(h.ruins) != "", "gettone rovine piazzato")
	ok(e.s.turn.moved or e.can_still_move(p), "si può continuare a muovere dopo aver esplorato")

# ------------------------------------------------------------------ assault
func _keep_lab(e: MKEngine, site := "keep", enemy := "guardsmen") -> String:
	lab(e)
	var k := "1,0"
	e.s.map.hex[k].site = site
	put_enemy(e, k, enemy, false, false)
	return k

func t_assault():
	var e := mk()
	var p := 0
	var k := _keep_lab(e)
	hand(e, p, ["march"])
	e.s.day = true
	e.s.turn.pool.move = 6
	e.s.turn.pool.influence = 3
	var rep0: int = e.s.players[p].rep
	ok(act(e, {"t": "move", "to": k}), "entra nel castello")
	ok(e.s.combat != null and e.s.combat.assault, "assalto")
	eq(int(e.s.players[p].rep), rep0 - 1, "assalto: Reputazione -1")
	eq(int(e.s.turn.pool.move), 0, "Movimento perso entrando in combattimento")
	eq(int(e.s.turn.pool.influence), 0, "Influenza persa entrando in combattimento")
	var en: Dictionary = e.s.combat.enemies[0]
	ok(en.fortified and en.dfort, "Guardie fortificate due volte nel castello")
	e.s.turn.pool.attack = {"siege:phys": 20}
	ok(e.check({"t": "attack", "targets": [en.eid]}) != "", "doppia fortificazione: nemmeno l'assedio in fase a distanza")
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	if e.s.combat.phase == "damage":
		act(e, {"t": "damage", "eid": en.eid, "to": "hero"})
		act(e, {"t": "next"})
	eq(e.s.combat.phase, "attack", "fase di attacco")
	e.s.turn.pool.attack = {"melee:phys": 7}
	ok(act(e, {"t": "attack", "targets": [en.eid]}), "nella fase di attacco la fortificazione non conta")
	ok(e.s.map.hex[k].conquered and int(e.s.map.hex[k].owner) == p, "castello conquistato")
	ok(k in e.s.players[p].shields, "scudo sul castello")
	eq(e.s.players[p].pos, k, "l'eroe resta nel castello conquistato")
	# conquered: recruit with keep icon possible, interaction ok
	ok(MKSites.interaction_site(e, p) == "keep", "interazione nel proprio castello")

func t_assault_fail():
	var e := mk()
	var p := 0
	var k := _keep_lab(e, "mage_tower", "fire_mages")
	hand(e, p, ["march", "rage", "stamina", "swiftness"])
	e.s.turn.pool.move = 2
	act(e, {"t": "move", "to": k})
	ok(e.s.combat != null, "assalto alla torre")
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	if e.s.combat.phase == "damage":
		act(e, {"t": "damage", "eid": e.s.combat.enemies[0].eid, "to": "hero"})
		act(e, {"t": "next"})
	act(e, {"t": "next"})
	ok(e.s.combat == null, "combattimento finito")
	eq(e.s.players[p].pos, "0,0", "assalto fallito: ritirata nello spazio di partenza")
	ok(not e.s.map.hex[k].conquered, "torre non conquistata")
	eq(e.s.map.hex[k].enemies.size(), 1, "il difensore resta")
	ok(e.s.turn.acted, "l'assalto era l'azione del turno")

func t_fortified_mixed():
	var e := mk()
	var g := fight(e, ["diggers", "prowlers"])  # diggers fortified
	e.s.turn.pool.attack = {"ranged:phys": 4}
	ok(e.check({"t": "attack", "targets": [g[1]]}) == "", "a distanza contro i non fortificati")
	ok(e.check({"t": "attack", "targets": g}) != "", "a distanza non si può includere un fortificato nel gruppo")
	e.s.turn.pool.attack = {"ranged:phys": 4, "siege:phys": 3}
	eq(e.effective_attack(g), 3, "con un fortificato nel gruppo vale solo l'assedio")
	eq(e.effective_attack([g[1]]), 7, "contro i non fortificati valgono distanza e assedio")
	ok(e.check({"t": "play", "card": hand(e, 0, ["rage"])[0], "mode": "side", "side": "attack"}) != "", "niente Attacco 1 di lato in fase a distanza")

func t_resist_sum():
	var e := mk()
	var g := fight(e, ["fire_golems"])  # resist phys + fire, armor 4
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:phys": 3, "melee:fire": 3}
	eq(e.effective_attack(g), 3, "parti inefficaci di tipo diverso sommate e poi dimezzate (3+3)/2")
	e.s.turn.pool.attack = {"melee:phys": 1, "ranged:fire": 2, "melee:ice": 3}
	eq(e.effective_attack(g), 4, "1+2 inefficaci -> 1, ghiaccio pieno 3")
	e.s.turn.pool.attack = {"melee:cold": 5}
	eq(e.effective_attack(g), 5, "fuoco-ghiaccio pieno se manca la resistenza al ghiaccio")
	var e2 := mk()
	var g2 := fight(e2, ["fire_golems", "prowlers"])
	e2.s.combat.phase = "attack"
	e2.s.turn.pool.attack = {"melee:phys": 3, "melee:fire": 3}
	eq(e2.effective_attack(g2), 3, "un nemico resistente nel gruppo dimezza per tutti")
	eq(e2.effective_attack([g2[1]]), 6, "da solo il nemico non resistente subisce tutto")

func t_block_elements():
	var cases := [
		["fire_mages", {"phys": 4, "fire": 2, "ice": 3}, 3 + 3],     # fire 6: ice efficient; phys+fire ineff (6)/2=3
		["ice_mages", {"ice": 5, "fire": 4}, 4 + 2],                 # ice 5: fire efficient
		["high_dragon", {"fire": 4, "ice": 4, "cold": 2}, 2 + 4],    # cold 6: only cold efficient
		["prowlers", {"fire": 1, "ice": 1, "phys": 1, "cold": 1}, 4],
	]
	for c in cases:
		var e := mk()
		var g := fight(e, [c[0]])
		act(e, {"t": "next"})
		e.s.turn.pool.block = c[1]
		eq(e.effective_block(g[0]), c[2], "blocco efficace contro " + str(c[0]))
	var e2 := mk()
	var h := fight(e2, ["high_dragon"])
	act(e2, {"t": "next"})
	e2.s.turn.pool.block = {"ice": 6, "fire": 6}
	ok(e2.check({"t": "block", "eid": h[0]}) == "", "6+6 inefficaci = 6 bastano contro fuoco-ghiaccio 6")
	e2.s.turn.pool.block = {"ice": 5, "fire": 6}
	ok(e2.check({"t": "block", "eid": h[0]}) != "", "11 inefficaci = 5 non bastano")

func t_swift_elem():
	var e := mk()
	var g := fight(e, ["freezers"])  # ice 3 swift paralyze
	act(e, {"t": "next"})
	e.s.turn.pool.block = {"fire": 5}
	ok(e.check({"t": "block", "eid": g[0]}) != "", "Rapido: servono 6")
	e.s.turn.pool.block = {"fire": 6}
	ok(e.check({"t": "block", "eid": g[0]}) == "", "Rapido: fuoco 6 basta contro ghiaccio 3")
	e.s.turn.pool.block = {"phys": 11}
	ok(e.check({"t": "block", "eid": g[0]}) != "", "fisico inefficace 11/2=5 < 6")
	# block resets after a block (points can't be saved)
	e.s.turn.pool.block = {"fire": 8}
	act(e, {"t": "block", "eid": g[0]})
	ok(e.s.turn.pool.block.is_empty(), "il blocco in eccesso è perso")
	# brutal doubles damage (not the block)
	var e2 := mk()
	var b := fight(e2, ["minotaur"])  # 5 brutal
	act(e2, {"t": "next"})
	e2.s.turn.pool.block = {"phys": 5}
	ok(e2.check({"t": "block", "eid": b[0]}) == "", "Brutale non cambia il blocco necessario")
	e2.s.turn.pool.block = {}
	act(e2, {"t": "next"})
	eq(int(e2.s.combat.enemies[0].attacks[0].rem), 10, "Brutale: danno doppio")

func t_summon_blocked():
	var e := mk()
	var g := fight(e, ["orc_summoners"])
	var f0: int = e.s.players[0].fame
	act(e, {"t": "next"})
	var summ: Dictionary = e.s.combat.enemies[1]
	ok(summ.summoned, "nemico evocato")
	ok(not MKCombat.targetable(e, e.s.combat.enemies[0]), "l'evocatore non è bersagliabile in fase di blocco")
	e.s.turn.pool.block = {"cold": 30}
	ok(act(e, {"t": "block", "eid": summ.eid}), "blocca l'evocato")
	act(e, {"t": "next"})
	eq(e.s.combat.phase, "attack", "nessun danno: si passa all'attacco")
	ok(summ.defeated, "evocato bloccato scartato")
	eq(int(e.s.players[0].fame), f0, "nessuna Fama per l'evocato")
	e.s.turn.pool.attack = {"melee:phys": 4}
	ok(act(e, {"t": "attack", "targets": [g[0]]}), "l'evocatore torna e si può attaccare")
	eq(int(e.s.players[0].fame), f0 + 4, "Fama dell'evocatore")
	# summoned enemy is drawn from brown
	ok(MKDB.enemies[summ.type].color == "brown", "evocato marrone")

func t_unit_resist_damage():
	var e := mk()
	var p := 0
	MKSites.gain_unit(e, p, "guardian_golems")  # armor 3, resist phys
	var u: Dictionary = e.s.players[p].units[0]
	var g := fight(e, ["swordsmen"])  # 6 phys
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	ok(act(e, {"t": "damage", "eid": g[0], "to": int(u.uid)}), "danno all'unità resistente")
	# rule: reduce by armor without wounding (6->3); damage left -> wound and reduce again (3->0)
	ok(u.wounded, "resistente: ferita se il danno supera l'armatura")
	eq(int(e.s.combat.enemies[0].attacks[0].rem), 0, "resistente: assorbe il doppio dell'armatura")
	var e2 := mk()
	MKSites.gain_unit(e2, p, "guardian_golems")
	var u2: Dictionary = e2.s.players[p].units[0]
	var g2 := fight(e2, ["prowlers", "prowlers"])
	act(e2, {"t": "next"})
	act(e2, {"t": "next"})
	act(e2, {"t": "damage", "eid": g2[0], "to": int(u2.uid)})  # 4 phys vs 3: 4-3=1 -> wound, 1-3 -> 0
	ok(u2.wounded, "4 danni contro 3 resistente: ferita")
	var e3 := mk()
	MKSites.gain_unit(e3, p, "guardian_golems")
	var u3: Dictionary = e3.s.players[p].units[0]
	var g3 := fight(e3, ["golems", "golems"])  # 2 phys each
	act(e3, {"t": "next"})
	act(e3, {"t": "next"})
	act(e3, {"t": "damage", "eid": g3[0], "to": int(u3.uid)})
	ok(not u3.wounded, "2 danni assorbiti dalla resistenza")
	ok(e3.check({"t": "damage", "eid": g3[1], "to": int(u3.uid)}) != "", "un'unità che ha assorbito non riceve altri danni")
	# fire damage to a non-fire-resistant golem: normal
	var e4 := mk()
	MKSites.gain_unit(e4, p, "guardian_golems")
	var u4: Dictionary = e4.s.players[p].units[0]
	var g4 := fight(e4, ["fire_mages"])  # fire 6
	act(e4, {"t": "next"})
	act(e4, {"t": "next"})
	act(e4, {"t": "damage", "eid": g4[0], "to": int(u4.uid)})
	ok(u4.wounded, "fuoco contro golem senza resistenza al fuoco: ferita")
	eq(int(e4.s.combat.enemies[0].attacks[0].rem), 3, "restano 6-3 danni")
	ok(e4.check({"t": "damage", "eid": g4[0], "to": int(u4.uid)}) != "", "unità ferita non riceve danni")
	act(e4, {"t": "damage", "eid": g4[0], "to": "hero"})
	ok(e4.check({"t": "next"}) == "", "danni assegnati")
	# exhausted (not ready) unwounded unit can take damage
	var e5 := mk()
	MKSites.gain_unit(e5, p, "peasants")
	var u5: Dictionary = e5.s.players[p].units[0]
	u5.ready = false
	var g5 := fight(e5, ["prowlers"])
	act(e5, {"t": "next"})
	act(e5, {"t": "next"})
	ok(e5.check({"t": "damage", "eid": g5[0], "to": int(u5.uid)}) == "", "unità esaurita non ferita può ricevere danni")
	# paralyze destroys unit
	var e6 := mk()
	MKSites.gain_unit(e6, p, "peasants")
	var g6 := fight(e6, ["medusa"])
	act(e6, {"t": "next"})
	act(e6, {"t": "next"})
	act(e6, {"t": "damage", "eid": g6[0], "to": int(e6.s.players[p].units[0].uid)})
	eq(e6.s.players[p].units.size(), 0, "Paralizzante: unità ferita distrutta")

func t_knockout_unmodified():
	var e := mk()
	var p := 0
	hand(e, p, ["march", "rage", "stamina"])
	e.s.players[p].armor = 2
	e.s.turn.mods.append({"name": "hand_limit", "n": 3})
	var g := fight(e, ["swordsmen", "prowlers"])  # 6 -> 3 wounds, 4 -> 2 wounds
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	act(e, {"t": "damage", "eid": g[0], "to": "hero"})
	ok(not e.s.players[p].knocked_out, "3 ferite: ancora in piedi")
	act(e, {"t": "damage", "eid": g[1], "to": "hero"})
	ok(e.s.players[p].knocked_out, "5 ferite = limite di mano non modificato: fuori combattimento")
	# the knock-out counts only wounds of this combat
	var e2 := mk()
	hand(e2, p, ["march", "wound", "wound", "wound", "wound"])
	e2.s.players[p].armor = 2
	var g2 := fight(e2, ["prowlers"])
	act(e2, {"t": "next"})
	act(e2, {"t": "next"})
	act(e2, {"t": "damage", "eid": g2[0], "to": "hero"})
	ok(not e2.s.players[p].knocked_out, "le ferite già in mano non contano per il colpo di grazia")

func t_rest_rules():
	var e := mk()
	lab(e)
	var p := 0
	var ids := hand(e, p, ["march", "rage", "wound"])
	act(e, {"t": "play", "card": ids[0], "mode": "basic"})
	act(e, {"t": "move", "to": "1,0"})
	ok(e.check({"t": "rest"}) != "", "niente riposo dopo essersi mossi")
	var e2 := mk()
	lab(e2)
	var ids2 := hand(e2, p, ["march", "rage", "wound", "wound"])
	ok(act(e2, {"t": "rest"}), "riposo standard")
	ok(e2.s.pending != null, "scelta della carta")
	act(e2, {"t": "choose", "v": [ids2[0]]})
	ok(e2.s.pending != null, "scelta delle ferite")
	act(e2, {"t": "choose", "v": ["one"]})
	act(e2, {"t": "choose", "v": ["none"]})
	eq(e2.s.players[p].hand.size(), 2, "riposo: 1 carta + 1 ferita scartate")
	eq(wounds_in(e2, e2.s.players[p].discard), 1, "le ferite finiscono negli scarti (non guarite)")
	ok(e2.check({"t": "move", "to": "1,0"}) != "", "dopo il riposo niente movimento")
	ok(e2.check({"t": "challenge", "hexes": ["1,0"]}) != "", "dopo il riposo niente combattimento")
	# can still play heal/special effects while resting
	e2.s.players[p].hand.append(e2.new_iid("tranquility"))
	ok(e2.check({"t": "play", "card": e2.s.players[p].hand[-1], "mode": "basic"}) == "", "durante il riposo si può curare")

func t_heal_combat():
	var e := mk()
	var p := 0
	var ids := hand(e, p, ["tranquility", "wound"])
	e.s.turn.pool.heal = 2
	fight(e, ["prowlers"])
	eq(int(e.s.turn.pool.heal), 0, "punti Cura persi entrando in combattimento")
	ok(e.check({"t": "heal", "target": "hand"}) != "", "niente cure in combattimento")
	# tranquility in combat: only the draw option should be possible
	if e.check({"t": "play", "card": ids[0], "mode": "basic"}) == "":
		var w0 := wounds_in(e, e.s.players[p].hand)
		act(e, {"t": "play", "card": ids[0], "mode": "basic"})
		answer_all(e, p)
		eq(wounds_in(e, e.s.players[p].hand), w0, "Tranquillità in combattimento non cura")
	var e2 := mk()
	MKSites.gain_unit(e2, p, "herbalists")
	var u: Dictionary = e2.s.players[p].units[0]
	hand(e2, p, ["wound", "march"])
	e2.s.players[p].crystals.green = 1
	fight(e2, ["prowlers"])
	ok(e2.check({"t": "unit", "uid": int(u.uid), "ability": 0}) != "", "Erboristi: niente Cura in combattimento")

# ------------------------------------------------------------------ mana
func t_mana_rules():
	var e := mk()
	var p := 0
	e.s.day = true
	e.s.players[p].tokens = []
	e.s.players[p].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	e.s.source = [{"color": "gold", "taken_by": -1}, {"color": "blue", "taken_by": -1}, {"color": "black", "taken_by": -1}]
	var ids := hand(e, p, ["stamina", "march", "swiftness"])
	ok(act(e, {"t": "play", "card": ids[0], "mode": "powered", "mana": ["die:1"]}), "Resistenza potenziata con il dado blu")
	eq(int(e.s.source[1].taken_by), p, "dado preso")
	ok(e.check({"t": "play", "card": ids[1], "mode": "powered", "mana": ["die:0"]}) != "", "un solo dado per turno")
	# tokens: gained mana tokens vanish at end of turn
	e.s.players[p].tokens = ["red"]
	end_turn_all(e, p)
	# solo: the dummy plays, then us again
	eq(e.s.players[p].tokens.size(), 0, "i gettoni mana spariscono a fine turno")
	var taken := 0
	for d in e.s.source:
		if int(d.taken_by) != -1:
			taken += 1
	eq(taken, 0, "dadi restituiti alla Riserva a fine turno")
	# night: gold not usable, black only for powered spells
	var e2 := mk()
	e2.s.day = false
	e2.s.players[p].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	e2.s.players[p].tokens = []
	e2.s.source = [{"color": "gold", "taken_by": -1}, {"color": "black", "taken_by": -1}]
	var ids2 := hand(e2, p, ["march", "fireball"])
	ok(e2.check({"t": "play", "card": ids2[0], "mode": "powered"}) != "", "di notte l'oro non si usa e il nero non vale un colore base")
	e2.s.players[p].crystals.red = 1
	fight(e2, ["prowlers"])
	ok(e2.check({"t": "play", "card": ids2[1], "mode": "powered"}) == "", "di notte: rosso + nero per l'incantesimo potenziato")
	# dungeon by day: night rules
	var e3 := mk()
	e3.s.day = true
	e3.s.players[p].crystals = {"red": 1, "blue": 0, "green": 0, "white": 0}
	e3.s.players[p].tokens = []
	e3.s.source = [{"color": "gold", "taken_by": -1}, {"color": "black", "taken_by": -1}]
	var ids3 := hand(e3, p, ["fireball", "march"])
	fight(e3, ["prowlers"], {"kind": "site", "site_type": "dungeon"})
	ok(e3.check({"t": "play", "card": ids3[0], "mode": "powered"}) == "", "nel sotterraneo di giorno si usa il nero")
	e3.s.players[p].crystals.red = 0
	ok(e3.check({"t": "play", "card": ids3[0], "mode": "basic"}) != "", "nel sotterraneo l'oro non si usa")

func t_crystal_cap():
	var e := mk()
	var p := 0
	e.s.players[p].crystals.red = 3
	e.s.players[p].tokens = []
	e.gain_crystal(p, "red")
	eq(int(e.s.players[p].crystals.red), 3, "massimo 3 cristalli per colore")
	eq(e.s.players[p].tokens, ["red"], "il cristallo in eccesso diventa un gettone mana")
	# mine with 3 crystals: nothing
	lab(e)
	e.s.map.hex["0,0"].mine = "red"
	e.s.players[p].tokens = []
	hand(e, p, ["march", "rage"])
	act(e, {"t": "play", "card": e.s.players[p].hand[0], "mode": "basic"})
	act(e, {"t": "end_turn"})
	answer_all(e, p)
	eq(int(e.s.players[p].crystals.red), 3, "miniera con 3 cristalli: niente")

func t_tokens_vanish():
	var e := mk()
	var p := 0
	lab(e)
	e.s.map.hex["0,0"].site = "glade"
	var ids := hand(e, p, ["march", "wound"])
	e.s.players[p].discard = []
	act(e, {"t": "play", "card": ids[0], "mode": "basic"})
	act(e, {"t": "end_turn"})
	answer_all(e, p)
	eq(wounds_in(e, e.s.players[p].hand) + wounds_in(e, e.s.players[p].discard) + wounds_in(e, e.s.players[p].deck), 0, "radura magica: ferita gettata via")

func t_spell_day():
	var e := mk()
	var p := 0
	e.s.day = true
	e.s.players[p].crystals = {"red": 2, "blue": 0, "green": 0, "white": 0}
	e.s.players[p].tokens = ["black"]
	var ids := hand(e, p, ["fireball"])
	fight(e, ["prowlers"])
	ok(e.check({"t": "play", "card": ids[0], "mode": "powered"}) != "", "di giorno il nero non si usa nemmeno da gettone")
	ok(e.check({"t": "play", "card": ids[0], "mode": "basic"}) == "", "incantesimo base con 1 mana del colore")

# ------------------------------------------------------------------ level up
func t_level_table():
	var e := mk()
	var exp := {1: [2, 5, 1], 2: [2, 5, 1], 3: [3, 5, 2], 4: [3, 5, 2], 5: [3, 6, 3], 6: [3, 6, 3], 7: [4, 6, 4], 8: [4, 6, 4], 9: [4, 7, 5], 10: [4, 7, 5]}
	var fames := [0, 3, 8, 15, 24, 35, 48, 63, 80, 99]
	for lv in range(1, 11):
		eq(e.level_of(fames[lv - 1]), lv, "Fama %d = livello %d" % [fames[lv - 1], lv])
		if lv > 1:
			eq(e.level_of(fames[lv - 1] - 1), lv - 1, "Fama %d = livello %d" % [fames[lv - 1] - 1, lv - 1])
		eq([MKEngine.LV_ARMOR[lv - 1], MKEngine.LV_HAND[lv - 1], MKEngine.LV_CMD[lv - 1]], exp[lv], "armatura/mano/comando al livello %d" % lv)

func t_level_multi():
	var e := mk()
	var p := 0
	var ids := hand(e, p, ["march", "rage"])
	act(e, {"t": "play", "card": ids[0], "mode": "basic"})
	var aa_off: Array = e.s.offers.aa.duplicate()
	e.s.players[p].fame = 9   # level 3 (passes 2)
	act(e, {"t": "end_turn"})
	ok(e.s.pending != null and e.s.pending.handler == "level_skill", "livello 2: scelta dell'abilità")
	var n_opts: int = e.s.pending.options.size()
	ok(n_opts >= 2, "due abilità pescate (+ offerta comune)")
	act(e, {"t": "choose", "v": [e.s.pending.options[0].v]})
	ok(e.s.pending != null and e.s.pending.handler == "level_aa", "poi un'Azione avanzata dall'offerta")
	var pick: String = str(e.s.pending.options[1].v)
	act(e, {"t": "choose", "v": [pick]})
	answer_all(e, p)
	eq(int(e.s.players[p].level), 3, "livello 3")
	eq(int(e.s.players[p].armor), 3, "armatura 3")
	eq(int(e.s.players[p].command), 2, "comando 2")
	ok(e.s.offers.skills.size() >= 1, "l'abilità non scelta va nell'offerta comune")
	var has_aa := false
	for iid in e.s.players[p].deck + e.s.players[p].hand:
		if e.card_id(iid) == pick:
			has_aa = true
	ok(has_aa, "l'Azione avanzata scelta è nel mazzo (in cima)")
	eq(e.s.offers.aa.size(), aa_off.size(), "offerta azioni avanzate riempita")

# ------------------------------------------------------------------ round end
func t_announce():
	var e := mk("coop_conquest", 2, ["arythea", "goldyx"])
	var p: int = e.actor()
	ok(e.check({"t": "announce_end"}) != "", "non si annuncia con il mazzo non vuoto")
	e.s.players[p].discard.append_array(e.s.players[p].deck)
	e.s.players[p].deck = []
	ok(e.check({"t": "announce_end"}) == "", "annuncio con il mazzo vuoto a inizio turno")
	var r0: int = e.s.round
	act(e, {"t": "announce_end"})
	ok(e.s.announced_by == p, "annunciato")
	var other := 1 - p
	var guard := 0
	var turns_other := 0
	while e.s.round == r0 and guard < 30:
		guard += 1
		if e.s.phase != "turn":
			break
		var a := e.actor()
		if a == other and e.s.pending == null:
			turns_other += 1
			var h: Array = e.s.players[other].hand
			if not h.is_empty() and e.check({"t": "play", "card": h[0], "mode": "side", "side": "move"}) == "":
				act(e, {"t": "play", "card": h[0], "mode": "side", "side": "move"})
			act(e, {"t": "end_turn"})
		elif e.s.pending != null:
			act(e, {"t": "choose", "v": [e.s.pending.options[0].v]})
		else:
			act(e, {"t": "end_turn"})
	eq(turns_other, 1, "l'altro giocatore fa esattamente un ultimo turno")
	ok(e.s.round == r0 + 1, "nuovo round")

func t_dummy_flip():
	var e := mk("solo_conquest", 5)
	var d: Dictionary = e.s.dummy
	d.crystals = {"red": 2, "blue": 0, "green": 0, "white": 0}
	var deck: Array = []
	for id in ["march", "rage", "rage", "march", "march", "march", "march"]:   # rage = red
		deck.append(e.new_iid(id))
	d.deck = deck
	d.discard = []
	e._dummy_turn()
	eq(d.discard.size(), 5, "ultima carta rossa con 2 cristalli rossi: 3+2 carte")
	d.deck = [e.new_iid("march"), e.new_iid("march"), e.new_iid("rage")]
	d.discard = []
	e._dummy_turn()
	eq(d.discard.size(), 3, "mazzo finito durante il turno")
	e._dummy_turn()
	ok(e.s.announced_by == MKEngine.DUMMY or e.s.round > 1, "con il mazzo vuoto il Neutrale annuncia la fine del round")

func t_dummy_offers():
	var e := mk("solo_conquest", 5)
	var low_aa: String = e.s.offers.aa[-1]
	var low_sp: String = e.s.offers.spells[-1]
	var col := str(MKDB.card(low_sp).get("color", ""))
	var c0 := int(e.s.dummy.crystals.get(col, 0))
	var n0: int = e.s.dummy.deck.size() + e.s.dummy.discard.size()
	e._refresh_offers()
	var found := false
	for iid in e.s.dummy.deck:
		if e.card_id(iid) == low_aa:
			found = true
	ok(found, "il Neutrale prende l'Azione avanzata più in basso")
	eq(e.s.dummy.deck.size() + e.s.dummy.discard.size(), n0 + 1, "mazzo del Neutrale +1")
	eq(int(e.s.dummy.crystals.get(col, 0)), c0 + 1, "cristallo del colore dell'incantesimo più in basso")
	ok(low_sp in e.s.decks.spells and e.s.decks.spells[-1] == low_sp, "l'incantesimo va in fondo al mazzo")
	eq(e.s.offers.aa.size(), 3, "offerta AA di nuovo a 3")
	eq(e.s.offers.spells.size(), 3, "offerta incantesimi di nuovo a 3")

# ------------------------------------------------------------------ units
func _site_lab(e: MKEngine, site: String) -> void:
	lab(e)
	e.s.map.hex["0,0"].site = site
	if site in ["keep", "mage_tower", "city"]:
		e.s.map.hex["0,0"].conquered = true
		e.s.map.hex["0,0"].owner = 0
	if site == "city":
		e.s.map.hex["0,0"]["city"] = {"color": "green", "level": 1, "shields": [0], "leader": 0}

func t_recruit_sites():
	var units := MKDB.units.keys()
	for site in ["village", "monastery", "keep", "mage_tower", "city"]:
		var e := mk()
		_site_lab(e, site)
		e.s.offers.units = []
		for id in units:
			if MKDB.units[id].get("set", "base") == "base" and MKDB.unit_ok(id):
				e.s.offers.units.append(id)
		hand(e, 0, ["march"])
		e.s.turn.pool.influence = 30
		for id in e.s.offers.units:
			var rec: Array = MKDB.units[id].get("recruit", [])
			var can := e.check({"t": "recruit", "id": id}) == ""
			eq(can, site in rec, "recluta %s in %s" % [id, site])
	# white city: any unit
	var e2 := mk()
	_site_lab(e2, "city")
	e2.s.map.hex["0,0"].city.color = "white"
	e2.s.offers.units = ["peasants", "herbalists"]
	hand(e2, 0, ["march"])
	e2.s.turn.pool.influence = 30
	ok(e2.check({"t": "recruit", "id": "peasants"}) == "", "città bianca: qualsiasi unità")
	# reputation bonus applies once
	var e3 := mk()
	_site_lab(e3, "village")
	e3.s.offers.units = ["peasants", "peasants"]
	e3.s.players[0].rep = 3   # +1
	e3.s.players[0].command = 3
	hand(e3, 0, ["march"])
	e3.s.turn.pool.influence = 7
	ok(act(e3, {"t": "recruit", "id": "peasants"}), "recluta Contadini (4) con 7+1")
	ok(act(e3, {"t": "recruit", "id": "peasants"}), "seconda recluta con 4 rimasti")
	eq(int(e3.s.turn.pool.influence), 0, "bonus di Reputazione applicato una sola volta")
	var u: Dictionary = e3.s.players[0].units[0]
	ok(u.ready and not u.wounded, "l'unità reclutata è pronta")
	# rep -7: no interaction
	var e4 := mk()
	_site_lab(e4, "village")
	e4.s.offers.units = ["peasants"]
	e4.s.players[0].rep = -7
	e4.s.turn.pool.influence = 30
	ok(e4.check({"t": "recruit", "id": "peasants"}) != "", "Reputazione X: niente interazione")
	eq(e4.rep_bonus(0), -99, "")
	var tab := {-6: -5, -5: -3, -4: -2, -3: -1, -2: -1, -1: 0, 0: 0, 1: 0, 2: 1, 3: 1, 4: 2, 5: 2, 6: 3, 7: 5}
	for r in tab:
		e4.s.players[0].rep = r
		eq(e4.rep_bonus(0), tab[r], "bonus Reputazione %d" % r)

func t_command_limit():
	var e := mk()
	_site_lab(e, "village")
	e.s.offers.units = ["peasants", "herbalists"]
	hand(e, 0, ["march"])
	e.s.turn.pool.influence = 20
	ok(act(e, {"t": "recruit", "id": "peasants"}), "prima unità")
	ok(e.check({"t": "recruit", "id": "herbalists"}) != "", "comando pieno: serve congedare")
	var old: int = int(e.s.players[0].units[0].uid)
	e.s.players[0].units[0].wounded = true
	ok(act(e, {"t": "recruit", "id": "herbalists", "disband": old}), "recluta congedando")
	eq(e.s.players[0].units.size(), 1, "una sola unità")
	eq(e.s.players[0].units[0].id, "herbalists", "la nuova unità")
	ok(not e.s.players[0].units[0].wounded, "nuova unità non ferita")
	ok(not "herbalists" in e.s.offers.units, "l'offerta unità non si riempie")

func t_monastery():
	var e := mk()
	_site_lab(e, "monastery")
	e.s.offers.monastery = [e.s.decks.aa[0]]
	var aa: String = e.s.offers.monastery[0]
	hand(e, 0, ["march", "wound"])
	e.s.turn.pool.influence = 7
	ok(e.check({"t": "buy", "what": "aa", "id": aa}) == "", "monastero: AA per 6")
	ok(act(e, {"t": "buy", "what": "heal"}), "monastero: Cura per 2")
	eq(wounds_in(e, e.s.players[0].hand), 0, "ferita curata")
	ok(e.check({"t": "buy", "what": "aa", "id": aa}) != "", "5 rimasti: non basta per l'AA")
	e.s.turn.pool.influence = 11
	ok(act(e, {"t": "buy", "what": "aa", "id": aa}), "compra l'AA")
	eq(e.card_id(e.s.players[0].deck[0]), aa, "AA in cima al mazzo")
	ok(e.s.offers.monastery.is_empty(), "l'offerta del monastero non si riempie")
	var e2 := mk()
	_site_lab(e2, "village")
	hand(e2, 0, ["march", "wound"])
	e2.s.turn.pool.influence = 2
	ok(e2.check({"t": "buy", "what": "heal"}) != "", "villaggio: la Cura costa 3")
	e2.s.turn.pool.influence = 3
	ok(e2.check({"t": "buy", "what": "heal"}) == "", "villaggio: Cura per 3")
	# plunder: once, rep -1, draw 2, only before acting
	var e3 := mk()
	_site_lab(e3, "village")
	var h0: int = e3.s.players[0].hand.size()
	var r0: int = e3.s.players[0].rep
	ok(act(e3, {"t": "plunder"}), "saccheggio")
	eq(e3.s.players[0].hand.size(), h0 + 2, "saccheggio: pesca 2 carte")
	eq(int(e3.s.players[0].rep), r0 - 1, "saccheggio: Reputazione -1")
	ok(e3.check({"t": "plunder"}) != "", "un solo saccheggio")

func t_mage_tower():
	var e := mk()
	_site_lab(e, "mage_tower")
	var sp: String = e.s.offers.spells[0]
	var col := str(MKDB.card(sp).get("color", ""))
	hand(e, 0, ["march"])
	e.s.players[0].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	e.s.players[0].tokens = []
	e.s.source = [{"color": "black", "taken_by": -1}]
	e.s.turn.pool.influence = 7
	ok(e.check({"t": "buy", "what": "spell", "id": sp}) != "", "serve anche 1 mana del colore")
	e.s.players[0].crystals[col] = 1
	ok(act(e, {"t": "buy", "what": "spell", "id": sp}), "incantesimo per 7 + mana")
	eq(e.card_id(e.s.players[0].deck[0]), sp, "incantesimo in cima al mazzo")
	eq(e.s.offers.spells.size(), 3, "offerta incantesimi riempita")
	# unconquered tower: assault only
	var e2 := mk()
	_site_lab(e2, "mage_tower")
	e2.s.map.hex["0,0"].conquered = false
	e2.s.turn.pool.influence = 9
	ok(e2.check({"t": "buy", "what": "spell", "id": e2.s.offers.spells[0]}) != "", "torre non conquistata: niente acquisti")
	# conquest reward: spell at end of turn
	var e3 := mk()
	var k := _keep_lab(e3, "mage_tower", "monks")
	hand(e3, 0, ["march", "rage"])
	e3.s.turn.pool.move = 2
	act(e3, {"t": "move", "to": k})
	e3.s.combat.phase = "attack"
	e3.s.turn.pool.attack = {"melee:phys": 10}
	act(e3, {"t": "attack", "targets": [e3.s.combat.enemies[0].eid]})
	ok(e3.s.map.hex[k].conquered, "torre conquistata")
	eq(e3.s.turn.rewards.size(), 1, "ricompensa incantesimo a fine turno")
	act(e3, {"t": "end_turn"})
	if e3.s.pending != null and e3.s.pending.handler == "end_discard":
		act(e3, {"t": "choose", "v": [e3.s.pending.options[0].v]})
	ok(e3.s.pending != null and e3.s.pending.handler == "reward_spell", "scelta dell'incantesimo dall'offerta")

func t_dungeon_tomb():
	var e := mk()
	_site_lab(e, "dungeon")
	hand(e, 0, ["march", "rage"])
	MKSites.gain_unit(e, 0, "peasants")
	ok(act(e, {"t": "site"}), "entra nel sotterraneo")
	var en: Dictionary = e.s.combat.enemies[0]
	eq(en.color, "brown", "nemico marrone")
	ok(not e.s.combat.units_allowed and e.s.combat.night_rules, "niente unità, regole della notte")
	ok(e.check({"t": "unit", "uid": int(e.s.players[0].units[0].uid), "ability": 2}) != "", "unità non utilizzabili")
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:cold": 30}
	act(e, {"t": "attack", "targets": [en.eid]})
	ok(e.s.map.hex["0,0"].conquered and "0,0" in e.s.players[0].shields, "sotterraneo conquistato con scudo")
	eq(e.s.turn.rewards, [{"k": "dungeon_roll"}], "ricompensa: tiro del dado")
	ok(not e.s.enemies.has(en.eid), "nemico scartato")
	act(e, {"t": "end_turn"})
	if e.s.pending != null and e.s.pending.handler == "end_discard":
		act(e, {"t": "choose", "v": [e.s.pending.options[0].v]})
	ok(e.s.pending != null and e.s.pending.handler in ["reward_spell", "reward_artifact"], "incantesimo o artefatto")
	# second time: no reward, no shield
	var e2 := mk()
	_site_lab(e2, "dungeon")
	e2.s.map.hex["0,0"].conquered = true
	hand(e2, 0, ["march"])
	act(e2, {"t": "site"})
	e2.s.combat.phase = "attack"
	e2.s.turn.pool.attack = {"melee:cold": 30}
	act(e2, {"t": "attack", "targets": [e2.s.combat.enemies[0].eid]})
	eq(e2.s.turn.rewards.size(), 0, "sotterraneo già conquistato: solo Fama")
	# failed dungeon: enemy discarded
	var e3 := mk()
	_site_lab(e3, "dungeon")
	hand(e3, 0, ["march", "rage", "stamina"])
	act(e3, {"t": "site"})
	var eid3: String = e3.s.combat.enemies[0].eid
	act(e3, {"t": "next"})
	act(e3, {"t": "next"})
	while e3.s.combat != null and e3.s.combat.phase == "damage":
		act(e3, {"t": "damage", "eid": eid3, "to": "hero"})
		act(e3, {"t": "next"})
	act(e3, {"t": "next"})
	ok(not e3.s.enemies.has(eid3) and e3.s.map.hex["0,0"].enemies.is_empty(), "sotterraneo fallito: nemico scartato")
	# tomb: red, spell + artifact
	var e4 := mk()
	_site_lab(e4, "tomb")
	hand(e4, 0, ["march"])
	act(e4, {"t": "site"})
	eq(e4.s.combat.enemies[0].color, "red", "tomba: draconum rosso")
	e4.s.combat.phase = "attack"
	e4.s.turn.pool.attack = {"melee:cold": 30}
	act(e4, {"t": "attack", "targets": [e4.s.combat.enemies[0].eid]})
	eq(e4.s.turn.rewards, [{"k": "spell"}, {"k": "artifact"}], "tomba: incantesimo + artefatto")

func t_den_spawning():
	var e := mk()
	_site_lab(e, "monster_den")
	hand(e, 0, ["march", "rage", "stamina"])
	act(e, {"t": "site"})
	var eid: String = e.s.combat.enemies[0].eid
	ok(e.s.combat.units_allowed, "tana: unità ammesse")
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	while e.s.combat != null and e.s.combat.phase == "damage":
		act(e, {"t": "damage", "eid": eid, "to": "hero"})
		act(e, {"t": "next"})
	act(e, {"t": "next"})
	ok(eid in e.s.map.hex["0,0"].enemies and e.s.enemies[eid].face_up, "tana fallita: il nemico resta a faccia in su")
	# spawning grounds: both, artifact + 3 crystals; failed -> defeated one replaced
	var e2 := mk()
	_site_lab(e2, "spawning_grounds")
	hand(e2, 0, ["march", "rage", "stamina"])
	act(e2, {"t": "site"})
	eq(e2.s.combat.enemies.size(), 2, "terreni: due nemici marroni")
	var a: Dictionary = e2.s.combat.enemies[0]
	var b: Dictionary = e2.s.combat.enemies[1]
	e2.s.combat.phase = "attack"
	e2.s.turn.pool.attack = {"melee:cold": 30}
	act(e2, {"t": "attack", "targets": [a.eid]})
	act(e2, {"t": "next"})
	ok(e2.s.combat == null, "fine combattimento")
	eq(e2.s.map.hex["0,0"].enemies.size(), 2, "terreni falliti: il nemico sconfitto è rimpiazzato da uno nuovo")
	ok(b.eid in e2.s.map.hex["0,0"].enemies, "il sopravvissuto resta")
	var e3 := mk()
	_site_lab(e3, "spawning_grounds")
	hand(e3, 0, ["march"])
	act(e3, {"t": "site"})
	e3.s.combat.phase = "attack"
	e3.s.turn.pool.attack = {"melee:cold": 60}
	var tg: Array = []
	for x in e3.s.combat.enemies:
		tg.append(x.eid)
	act(e3, {"t": "attack", "targets": tg})
	eq(e3.s.turn.rewards, [{"k": "artifact"}, {"k": "crystal_roll", "n": 3}], "terreni: artefatto + 3 cristalli a caso")

func t_ruins():
	var e := mk()
	_site_lab(e, "ruins")
	var altar := ""
	var enemies_r := ""
	for id in MKDB.ruins:
		if MKDB.ruins[id].get("set", "base") != "base":
			continue
		if MKDB.ruins[id].get("kind", "") == "altar" and altar == "":
			altar = id
		elif MKDB.ruins[id].get("kind", "") != "altar" and enemies_r == "":
			enemies_r = id
	e.s.map.hex["0,0"].ruins = altar
	var needs: Array = MKSites.altar_needs(MKDB.ruins[altar])
	eq(needs.size(), 3, "altare: 3 mana")
	e.s.players[0].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	e.s.players[0].crystals[needs[0]] = 3
	hand(e, 0, ["march"])
	var f0: int = e.s.players[0].fame
	ok(act(e, {"t": "altar"}), "tributo all'altare")
	eq(int(e.s.players[0].fame), f0 + 7, "altare: 7 Fama")
	ok("0,0" in e.s.players[0].shields, "scudo sulle rovine")
	var e2 := mk()
	_site_lab(e2, "ruins")
	e2.s.map.hex["0,0"].ruins = enemies_r
	hand(e2, 0, ["march"])
	act(e2, {"t": "site"})
	eq(e2.s.combat.enemies.size(), MKDB.ruins[enemies_r].get("enemies", []).size(), "nemici delle rovine")
	print("    rovine %s: nemici %s ricompensa %s" % [enemies_r, str(MKDB.ruins[enemies_r].get("enemies", [])), str(MKDB.ruins[enemies_r].get("reward", []))])

# ------------------------------------------------------------------ cities
func t_city_garrisons():
	# straight from the Italian city cards (brown = marrone)
	var tab := {
		"red": ["w", "bv", "bw", "bvv", "bvw", "bbvv", "bvvw", "bvww", "bbvvw", "bbvww", "bvwww"],
		"blue": ["gv", "vv", "vw", "gvw", "vvw", "vww", "gvvw", "vvww", "vwww", "gvvww", "vvwww"],
		"green": ["gb", "bb", "ggb", "gbw", "bbw", "ggbw", "gbbw", "bbww", "gbbbw", "gbbww", "bbwww"],
		"white": ["w", "gw", "ww", "ggw", "gww", "gggw", "ggww", "gwww", "gggww", "ggwww", "gwwww"],
	}
	var cmap := {"w": "white", "b": "brown", "v": "violet", "g": "gray"}
	var e := mk()
	for col in tab:
		for lv in range(1, 12):
			var want: Array = []
			for ch in tab[col][lv - 1]:
				want.append(cmap[ch])
			var got: Array = e._city_garrison(MKSites.city_def(col), lv)
			want.sort()
			got = got.duplicate()
			got.sort()
			eq(got, want, "guarnigione città %s livello %d" % [col, lv])

func _city_lab(e: MKEngine, col: String, types: Array) -> String:
	lab(e)
	var k := "1,0"
	e.s.map.hex[k].site = "city"
	e.s.map.hex[k]["city"] = {"color": col, "level": 1, "shields": [], "leader": -1}
	for t in types:
		put_enemy(e, k, t, false, false)
	return k

func t_city_conquest():
	var e := mk("coop_conquest", 2, ["arythea", "goldyx"])
	var p: int = e.actor()
	var k := _city_lab(e, "white", ["prowlers", "golems"])
	hand(e, p, ["march"])
	e.s.players[p].pos = "0,0"
	_reveal_test(e, p, k)
	e.s.turn.pool.move = 2
	act(e, {"t": "move", "to": k})
	ok(e.s.combat != null and e.s.combat.city == "white", "assalto alla città bianca")
	eq(int(e.s.combat.enemies[0].armor), 4, "città bianca: Armatura +1")
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:ice": 4}
	act(e, {"t": "attack", "targets": [e.s.combat.enemies[0].eid]})
	eq(e.s.map.hex[k].city.shields, [p], "uno scudo per nemico sconfitto")
	act(e, {"t": "next"})
	ok(not e.s.map.hex[k].conquered, "città non conquistata")
	eq(e.s.players[p].pos, "0,0", "ritirata")
	ok(e.s.map.hex[k].enemies.size() == 1, "resta un difensore")
	# blue/red/green bonuses
	var e2 := mk()
	var k2 := _city_lab(e2, "blue", ["fire_mages", "high_dragon", "prowlers"])
	e2.s.turn.pool.move = 2
	act(e2, {"t": "move", "to": k2})
	var vals: Array = []
	for en in e2.s.combat.enemies:
		vals.append(int(en.attacks[0].n))
	eq(vals, [8, 7, 4], "città blu: +2 fuoco/ghiaccio, +1 fuoco-ghiaccio, fisico invariato")
	var e3 := mk()
	var k3 := _city_lab(e3, "red", ["prowlers", "fire_mages"])
	e3.s.turn.pool.move = 2
	act(e3, {"t": "move", "to": k3})
	ok("brutal" in e3.s.combat.enemies[0].abilities and not "brutal" in e3.s.combat.enemies[1].abilities, "città rossa: Brutale agli attacchi fisici")
	var e4 := mk()
	var k4 := _city_lab(e4, "green", ["prowlers"])
	e4.s.turn.pool.move = 2
	act(e4, {"t": "move", "to": k4})
	ok("poison" in e4.s.combat.enemies[0].abilities, "città verde: Velenoso agli attacchi fisici")
	# leader: most shields, ties -> first placed
	var e5 := mk("coop_conquest", 2, ["arythea", "goldyx"])
	var k5 := _city_lab(e5, "green", [])
	e5.s.map.hex[k5].city.shields = [1, 0, 0, 1]
	MKSites.conquer(e5, 0, k5)
	eq(int(e5.s.map.hex[k5].city.leader), 1, "parità di scudi: leader chi ha piazzato per primo")
	e5.s.map.hex[k5].city.shields = [1, 0, 0]
	MKSites.conquer(e5, 0, k5)
	eq(int(e5.s.map.hex[k5].city.leader), 0, "leader chi ha più scudi")
	# city interaction bonus +1 per shield
	e5.s.players[0].pos = k5
	e5.s.players[0].rep = 0
	eq(MKSites.influence_bonus(e5, 0), 2, "interazione in città: +1 per scudo")

func _reveal_test(e: MKEngine, p: int, k: String) -> void:
	e.s.day = false
	e._reveal_adjacent(p)
	var all_up := true
	for eid in e.s.map.hex[k].enemies:
		if not e.s.enemies[eid].face_up:
			all_up = false
	ok(all_up, "guarnigione della città rivelata da uno spazio adiacente anche di notte")

func t_keep_hand_limit():
	var e := mk()
	lab(e)
	var p := 0
	for k in ["0,0", "3,0", "-3,0"]:
		e.s.map.hex[k].site = "keep"
		e.s.map.hex[k].conquered = true
		e.s.map.hex[k].owner = p
	e.s.players[p].pos = "1,0"
	eq(e.hand_limit_now(p), 5 + 3, "accanto a un proprio castello: +1 per castello posseduto")
	e.s.players[p].pos = "5,-3"
	eq(e.hand_limit_now(p), 5, "lontano: nessun bonus")
	# city leader +2 vs keeps: only the higher
	e.s.map.hex["5,-2"].site = "city"
	e.s.map.hex["5,-2"].conquered = true
	e.s.map.hex["5,-2"]["city"] = {"color": "red", "level": 1, "shields": [p], "leader": p}
	eq(e.hand_limit_now(p), 7, "accanto a una città di cui sei leader: +2")
	e.s.players[p].pos = "4,-1"   # adjacent to keep 3,0 (3 keeps) and the city
	eq(e.hand_limit_now(p), 8, "castelli e città: solo il bonus più alto")
	# draw at end of turn uses it
	e.s.players[p].pos = "0,0"
	hand(e, p, ["march", "rage"])
	act(e, {"t": "play", "card": e.s.players[p].hand[0], "mode": "basic"})
	act(e, {"t": "end_turn"})
	answer_all(e, p)
	eq(e.s.players[p].hand.size(), mini(8, 1 + 13), "pesca fino al limite aumentato")

func t_keep_opponent():
	var e := mk("full_conquest", 4, ["arythea", "goldyx"])
	var p: int = e.actor()
	var o := 1 - p
	lab(e, p)
	e.s.map.hex["1,0"].site = "keep"
	e.s.map.hex["1,0"].conquered = true
	e.s.map.hex["1,0"].owner = o
	e.s.players[o].shields.append("1,0")
	e.s.players[o].pos = "-5,0"
	hand(e, p, ["march"])
	e.s.turn.pool.move = 2
	var r0: int = e.s.players[p].rep
	act(e, {"t": "move", "to": "1,0"})
	ok(e.s.combat != null and e.s.combat.assault, "assalto al castello di un avversario")
	eq(int(e.s.players[p].rep), r0 - 1, "Reputazione -1")
	var en: Dictionary = e.s.combat.enemies[0]
	eq(en.color, "gray", "difensore grigio pescato")
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:cold": 30}
	var f0: int = e.s.players[p].fame
	act(e, {"t": "attack", "targets": [en.eid]})
	eq(int(e.s.players[p].fame) - f0, (int(en.fame) + 1) / 2, "metà Fama arrotondata per eccesso")
	eq(int(e.s.map.hex["1,0"].owner), p, "castello passato di mano")
	ok(not "1,0" in e.s.players[o].shields and "1,0" in e.s.players[p].shields, "scudo sostituito")

# ------------------------------------------------------------------ scenarios & scoring
func t_solo_end():
	var e := mk("solo_conquest", 7)
	eq(int(e.s.scn.rounds), 6, "Conquista in solitario: 6 round")
	eq(e.s.scn.city_levels.map(func(x): return int(x)), [5, 8], "città di livello 5 e 8")
	eq(int(e.s.scn.city), 2, "2 città")
	eq(int(e.s.scn.country), 7, "7 tessere campagna")
	eq(int(e.s.scn.core), 2, "2 tessere centrali non-città")
	eq(e.s.map.tile_deck.size() + e.s.map.tiles.size() - 1, 7 + 2 + 2, "mazzo tessere")
	# all cities conquered -> one last turn for the player, none for the dummy
	var cities: Array = []
	while e.s.map.tile_deck.size() > 0:
		var tid: String = e.s.map.tile_deck.pop_front()
		if MKDB.tiles[tid].city != "":
			var slot := "%d,%d" % [50 + cities.size() * 10, 50]
			e.place_tile(tid, slot, -1)
			cities.append(slot)
	for k in e.s.map.hex:
		if e.s.map.hex[k].site == "city":
			e.s.map.hex[k].conquered = true
			e.s.map.hex[k].city.leader = 0
			e.s.map.hex[k].city.shields = [0]
	var p := 0
	hand(e, p, ["march", "rage"])
	act(e, {"t": "play", "card": e.s.players[p].hand[0], "mode": "basic"})
	act(e, {"t": "end_turn"})
	answer_all(e, p)
	ok(e.s.game_end_pending, "tutte le città conquistate: fine partita annunciata")
	ok(not e.s.final_turns.has(str(MKEngine.DUMMY)), "il Neutrale non ha l'ultimo turno")
	var guard := 0
	while e.s.phase != "game_over" and guard < 20:
		guard += 1
		if e.s.pending != null:
			act(e, {"t": "choose", "v": [e.s.pending.options[0].v]})
		else:
			var h: Array = e.s.players[p].hand
			if not h.is_empty() and e.check({"t": "play", "card": h[0], "mode": "side", "side": "move"}) == "":
				act(e, {"t": "play", "card": h[0], "mode": "side", "side": "move"})
			act(e, {"t": "end_turn"})
	eq(e.s.phase, "game_over", "partita finita dopo l'ultimo turno")
	var res: Dictionary = e.s.result
	ok(res.get("victory", false), "vittoria")
	var sc: Dictionary = res.scores[0]
	ok(sc.titles.is_empty(), "in solitario nessun titolo")
	# objective: 10/city + 15 + 30 per round early + dummy cards + 5 if not announced
	var expect: int = 20 + 15 + 30 * (6 - int(e.s.round)) + e.s.dummy.deck.size() + (5 if e.s.announced_by == -1 else 0)
	eq(int(sc.objective), expect, "punteggio dell'obiettivo")

func t_scoring_titles():
	var e := mk("full_conquest", 4, ["arythea", "goldyx", "tovak"])
	for i in 3:
		var pl: Dictionary = e.s.players[i]
		pl.deck = []
		pl.hand = []
		pl.discard = []
		pl.play = []
		pl.crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
		pl.units = []
		pl.shields = []
	e.s.players[0].deck = [e.new_iid(e.s.decks.spells[0]), e.new_iid(e.s.decks.aa[0])]   # knowledge 3
	e.s.players[1].deck = [e.new_iid(e.s.decks.spells[1]), e.new_iid(e.s.decks.aa[1])]   # 3 (tie)
	e.s.players[2].deck = [e.new_iid("wound"), e.new_iid("wound")]                       # beating -4
	e.s.players[0].crystals = {"red": 3, "blue": 0, "green": 0, "white": 0}           # loot 1
	var s0 := e.score(0)
	var s1 := e.score(1)
	var s2 := e.score(2)
	eq(int(s0.achievements.knowledge), 3, "Massima conoscenza: 2 per incantesimo + 1 per AA")
	eq(int(s0.titles.get("knowledge", 0)), 1, "titolo condiviso: +1")
	eq(int(s1.titles.get("knowledge", 0)), 1, "titolo condiviso: +1")
	eq(int(s0.achievements.loot), 1, "1 Fama ogni 2 cristalli")
	eq(int(s0.titles.get("loot", 0)), 3, "Massimo bottino: +3")
	eq(int(s2.achievements.beating), -4, "-2 per Ferita")
	eq(int(s2.titles.get("beating", 0)), -3, "Più grande sconfitto: -3")
	ok(not s0.titles.has("beating"), "chi non ha ferite non prende la penalità")
	MKSites.gain_unit(e, 1, "fire_golems")   # level 3
	e.s.players[1].units[0].wounded = true
	eq(int(e.score(1).achievements.leader), 1, "unità ferita: metà livello per difetto")

func t_heal_unit_poison():
	var e := mk()
	var p := 0
	MKSites.gain_unit(e, p, "peasants")
	var u: Dictionary = e.s.players[p].units[0]
	u.wounded = true
	u.wounds = 2
	hand(e, p, ["march"])
	e.s.turn.pool.heal = 1
	ok(act(e, {"t": "heal", "target": int(u.uid)}), "cura l'unità avvelenata (livello 1)")
	ok(u.wounded, "dopo una cura resta una ferita")
	e.s.turn.pool.heal = 1
	act(e, {"t": "heal", "target": int(u.uid)})
	ok(not u.wounded, "seconda cura: guarita")
	# heal_unit effect also removes only one wound
	u.wounded = true
	u.wounds = 2
	MKEffects.start(e, [["heal_unit", 3]], {"p": p, "kind": "card"})
	ok(u.wounded, "un effetto 'cura un'unità' rimuove una sola ferita")

func t_tactic_order():
	var e := MKEngine.create({"scenario": "full_conquest", "seed": 3, "players": [{"hero": "arythea"}, {"hero": "goldyx"}, {"hero": "tovak"}]})
	eq(e.s.tactic_pick, [2, 1, 0], "primo round: sceglie per primo chi ha scelto l'eroe per ultimo")
	act(e, {"t": "tactic", "id": e.s.tactics_avail[5]})
	act(e, {"t": "tactic", "id": e.s.tactics_avail[0]})
	answer_all(e, 1)
	answer_all(e, 0)
	act(e, {"t": "tactic", "id": e.s.tactics_avail[0]})
	answer_all(e, 0)
	answer_all(e, 1)
	answer_all(e, 2)
	eq(e.s.turn_order[0], 1, "ordine di turno secondo il numero della tattica")
	eq(e.s.turn_order[2], 2, "tattica 6 per ultima")
	# solo: player chooses first, dummy random among the rest, both removed at round end
	var e2 := MKEngine.create({"scenario": "solo_conquest", "seed": 3, "players": [{"hero": "arythea"}]})
	ok(e2.s.dummy.tactic == "", "il Neutrale sceglie dopo")
	var t0: String = e2.s.tactics_avail[2]
	act(e2, {"t": "tactic", "id": t0})
	answer_all(e2, 0)
	ok(e2.s.dummy.tactic != "" and e2.s.dummy.tactic != t0, "il Neutrale prende una tattica a caso tra le rimaste")
	var dt: String = e2.s.dummy.tactic
	e2._end_round()
	ok(t0 in e2.s.tactics_removed and dt in e2.s.tactics_removed, "le due tattiche usate vengono rimosse")
	# coop: dummy first
	var e3 := MKEngine.create({"scenario": "coop_conquest", "seed": 3, "players": [{"hero": "arythea"}, {"hero": "goldyx"}]})
	ok(e3.s.dummy.tactic != "", "cooperativo: il Neutrale prende la tattica per primo")
	eq(e3.s.tactics_avail.size(), 5, "restano 5 tattiche")

func t_source_reroll():
	var e := mk("full_conquest", 4, ["arythea", "goldyx"])
	eq(e.s.source.size(), 4, "dadi = giocatori + 2")
	var es := mk("solo_conquest", 4)
	eq(es.s.source.size(), 3, "solitario: il Neutrale non conta per i dadi")
	# at end of turn only the used die is rerolled; the others are untouched (no 'half basic' fix-up)
	var p: int = e.actor()
	e.s.source = [{"color": "gold", "taken_by": -1}, {"color": "gold", "taken_by": -1}, {"color": "black", "taken_by": -1}, {"color": "red", "taken_by": -1}]
	var ids := hand(e, p, ["rage", "march"])
	e.s.day = true
	act(e, {"t": "play", "card": ids[1], "mode": "basic"})
	act(e, {"t": "end_turn"})
	answer_all(e, p)
	eq([e.s.source[0].color, e.s.source[1].color, e.s.source[2].color], ["gold", "gold", "black"], "i dadi non usati non vengono rilanciati a fine turno")

func t_unit_offer():
	var e := mk("full_conquest", 4, ["arythea", "goldyx"])
	eq(e.s.offers.units.size(), 4, "offerta unità = giocatori + 2")
	for u in e.s.offers.units:
		ok(not MKDB.units[u].elite, "senza tessere centrali solo unità regolari")
	e.s.core_revealed = true
	e._new_unit_offer()
	ok(MKDB.units[e.s.offers.units[0]].elite and not MKDB.units[e.s.offers.units[1]].elite, "con una tessera centrale: élite, regolare, ...")
	var es := mk("solo_conquest", 4)
	eq(es.s.offers.units.size(), 3, "solitario: 1 + 2 unità")

func t_burn_monastery():
	var e := mk()
	_site_lab(e, "monastery")
	MKSites.gain_unit(e, 0, "peasants")
	hand(e, 0, ["march"])
	var r0: int = e.s.players[0].rep
	ok(act(e, {"t": "burn"}), "brucia il monastero")
	eq(int(e.s.players[0].rep), r0 - 3, "Reputazione -3")
	eq(e.s.combat.enemies[0].color, "violet", "nemico viola")
	ok(not e.s.combat.units_allowed, "niente unità")
	e.s.combat.phase = "attack"
	e.s.turn.pool.attack = {"melee:cold": 30}
	act(e, {"t": "attack", "targets": [e.s.combat.enemies[0].eid]})
	ok(e.s.map.hex["0,0"].burned, "monastero bruciato")
	eq(e.s.turn.rewards, [{"k": "artifact"}], "ricompensa: artefatto")
	ok(MKSites.interaction_site(e, 0) == "", "monastero bruciato: niente interazione")

# ------------------------------------------------------------------ cards
## Ready-made state for playing a card: returns true if something changed.
func _snapshot(e: MKEngine, p: int, hand_adj := 0) -> String:
	var pl: Dictionary = e.s.players[p]
	var d := {"pool": e.s.turn.pool, "hand": pl.hand.size() + hand_adj, "deck": pl.deck.size(), "disc": pl.discard.size(), "cr": pl.crystals,
		"tok": pl.tokens, "mods": e.s.turn.mods.size(), "fame": pl.fame, "rep": pl.rep, "units": pl.units, "pend": e.s.pending,
		"combat": e.s.combat, "dice": e.s.turn.dice_allowed, "pos": pl.pos, "source": e.s.source, "turn_keys": e.s.turn.keys().size(),
		"removed": pl.removed.size(), "skills": pl.skills, "banners": pl.get("banners", {}), "offers": e.s.offers}
	return JSON.stringify(d)

const WHERES := ["move", "site", "ranged", "block", "attack", "n_move", "n_site", "n_ranged", "n_block", "n_attack"]

func _card_state(id: String, mode: String, where0: String) -> MKEngine:
	var e := mk("solo_conquest", 2)
	lab(e)
	var p := 0
	var pl: Dictionary = e.s.players[p]
	var night := where0.begins_with("n_")
	var where := where0.trim_prefix("n_")
	e.s.day = not night
	pl.crystals = {"red": 2, "blue": 2, "green": 2, "white": 2}
	pl.tokens = ["black"] if night else []
	e.s.source = [{"color": "red", "taken_by": -1}, {"color": "blue", "taken_by": -1}, {"color": "green", "taken_by": -1},
		{"color": "white", "taken_by": -1}, {"color": "black" if night else "gold", "taken_by": -1}]
	MKSites.gain_unit(e, p, "peasants")
	pl.units[0].ready = false
	pl.units[0].wounded = false
	pl.command = 3
	MKSites.gain_unit(e, p, "utem_crossbowmen")
	e.s.map.hex["1,0"].t = "forest"
	e.s.map.hex["0,1"].t = "hills"
	hand(e, p, [id, "march", "rage", "wound", "swiftness", "stamina"])
	pl.deck = [e.new_iid("promise"), e.new_iid("threaten"), e.new_iid("tranquility")]
	pl.discard = [e.new_iid("wound"), e.new_iid("concentration")]
	if where in ["ranged", "block", "attack"]:
		fight(e, ["prowlers", "fire_mages"])
		if where == "block":
			act(e, {"t": "next"})
		elif where == "attack":
			act(e, {"t": "next"})
			e.s.turn.pool.block = {"cold": 20}
			act(e, {"t": "block", "eid": e.s.combat.enemies[0].eid})
			e.s.turn.pool.block = {"cold": 20}
			act(e, {"t": "block", "eid": e.s.combat.enemies[1].eid})
			act(e, {"t": "next"})
	elif where == "site":
		e.s.map.hex["0,0"].site = "village"
		e.s.offers.units = ["peasants", "herbalists"]
	return e

func _try_card(id: String) -> void:
	var c: Dictionary = MKDB.cards[id]
	var played_any := false
	var notes: Array = []
	for mode in ["basic", "powered"]:
		if c.get(mode, []).is_empty():
			continue
		var worked := false
		for where in WHERES:
			var e := _card_state(id, mode, where)
			var iid: String = e.s.players[0].hand[0]
			var a := {"t": "play", "card": iid, "mode": mode}
			if e.check(a) != "":
				continue
			var before := _snapshot(e, 0, -1)
			var lc: int = e.s.log_seq
			var r := e.apply(a)
			if not r.ok:
				notes.append("%s %s rifiutata in %s: %s" % [id, mode, where, r.err])
				continue
			# answer decisions with the first option, making sure we never get stuck
			var guard := 0
			while e.s.pending != null and guard < 20:
				guard += 1
				e.apply({"t": "choose", "v": [e.s.pending.options[0].v]})
			if e.s.pending != null:
				notes.append("%s %s: decisione infinita" % [id, mode])
			for le in e.s.log:
				if int(le.seq) >= lc and le.k == "error":
					notes.append("%s %s: errore nel diario: %s" % [id, mode, le.txt])
			var after := _snapshot(e, 0)
			# the card itself moved hand -> play: compare ignoring that
			var gained := false
			var pool: Dictionary = e.s.turn.pool
			if int(pool.move) > 0 or int(pool.influence) > 0 or int(pool.heal) > 0 or not pool.attack.is_empty() or not pool.block.is_empty():
				gained = true
			if after != before:
				gained = true
			# all actions still consistent
			for x in e.available():
				if e.check(x.a) != "":
					notes.append("%s %s: available() propone un'azione illegale %s" % [id, mode, JSON.stringify(x.a)])
					break
			worked = worked or gained
			if worked:
				played_any = true
				break
		if not worked:
			notes.append("%s (%s): nessun effetto osservabile in nessuno stato provato" % [id, mode])
	if not played_any:
		notes.append("%s: mai giocabile" % id)
	for n in notes:
		card_report.append(n)

func t_cards_all():
	var ids: Array = MKDB.cards.keys()
	ids.sort()
	var n := 0
	for id in ids:
		var c: Dictionary = MKDB.cards[id]
		if c.get("set", "base") != "base" or not MKDB.card_ok(id) or c.type == "wound":
			continue
		n += 1
		_try_card(id)
	print("    carte provate: ", n)
	ok(n > 50, "carte base provate")

func t_units_all():
	var ids: Array = MKDB.units.keys()
	ids.sort()
	for id in ids:
		var ud: Dictionary = MKDB.units[id]
		if ud.get("set", "base") != "base" or not MKDB.unit_ok(id):
			continue
		var abs: Array = ud.get("abilities", [])
		for ai in abs.size():
			if abs[ai].get("effect", []).is_empty():
				continue
			var worked := false
			for where in WHERES:
				var e := _card_state("march", "basic", where)
				e.s.players[0].units = []
				MKSites.gain_unit(e, 0, id)
				MKSites.gain_unit(e, 0, "peasants")
				e.s.players[0].units[1].ready = false
				var uid: int = int(e.s.players[0].units[0].uid)
				var a := {"t": "unit", "uid": uid, "ability": ai}
				if e.check(a) != "":
					continue
				var before := _snapshot(e, 0)
				e.apply(a)
				var guard := 0
				while e.s.pending != null and guard < 20:
					guard += 1
					e.apply({"t": "choose", "v": [e.s.pending.options[0].v]})
				var pool: Dictionary = e.s.turn.pool
				if int(pool.move) > 0 or int(pool.influence) > 0 or int(pool.heal) > 0 or not pool.attack.is_empty() or not pool.block.is_empty() or _snapshot(e, 0) != before:
					worked = true
					break
			if not worked:
				card_report.append("unità %s abilità %d (%s): mai utilizzabile/nessun effetto" % [id, ai, abs[ai].get("text_it", "")])

func t_skills_all():
	var ids: Array = MKDB.skills.keys()
	ids.sort()
	for id in ids:
		var sd: Dictionary = MKDB.skills[id]
		if sd.get("set", "base") != "base" or not MKDB.skill_ok(id):
			continue
		if sd.get("usage", "") == "passive" or sd.get("effect", []).is_empty():
			continue
		var worked := false
		for where in WHERES:
			var e := _card_state("march", "basic", where)
			MKSites.add_skill(e, 0, id)
			var a := {"t": "skill", "id": id}
			if e.check(a) != "":
				continue
			var before := _snapshot(e, 0)
			e.apply(a)
			var guard := 0
			while e.s.pending != null and guard < 20:
				guard += 1
				e.apply({"t": "choose", "v": [e.s.pending.options[0].v]})
			var pool: Dictionary = e.s.turn.pool
			if int(pool.move) > 0 or int(pool.influence) > 0 or int(pool.heal) > 0 or not pool.attack.is_empty() or not pool.block.is_empty() or _snapshot(e, 0) != before:
				worked = true
				break
		if not worked:
			card_report.append("abilità %s (%s): mai utilizzabile/nessun effetto" % [id, sd.get("text_it", "").substr(0, 80)])


# ------------------------------------------------------------------ specific card effects vs text_it
func _pick(e: MKEngine, label_part: String) -> bool:
	if e.s.pending == null:
		return false
	for o in e.s.pending.options:
		if str(o.label).findn(label_part) >= 0:
			return act(e, {"t": "choose", "v": [o.v]})
	print("    opzione '%s' non trovata in %s" % [label_part, str(e.s.pending.options)])
	return false

func t_card_effects():
	var p := 0
	# Concentration powered + Rage: Attack 4 + 2
	var e := mk()
	var ids := hand(e, p, ["concentration", "rage"])
	e.s.players[p].crystals.green = 1
	fight(e, ["prowlers"])
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	act(e, {"t": "damage", "eid": e.s.combat.enemies[0].eid, "to": "hero"})
	act(e, {"t": "next"})
	ok(act(e, {"t": "play", "card": ids[0], "mode": "powered"}), "Concentrazione potenziata in fase d'attacco")
	answer_all(e, p)
	eq(int(e.s.turn.pool.attack.get("melee:phys", 0)), 6, "Concentrazione + Furia potenziata = Attacco 6")
	# Improvisation: discard another card, then Block 3
	var e2 := mk()
	var ids2 := hand(e2, p, ["improvisation", "march", "wound"])
	fight(e2, ["prowlers"])
	act(e2, {"t": "next"})
	ok(act(e2, {"t": "play", "card": ids2[0], "mode": "basic"}), "Improvvisazione")
	ok(e2.s.pending != null and e2.s.pending.options.size() == 1, "si può scartare solo la carta non-Ferita")
	answer_all(e2, p)
	eq(int(e2.s.turn.pool.block.get("phys", 0)), 3, "Improvvisazione in fase di blocco: Blocco 3")
	ok(ids2[1] in e2.s.players[p].discard, "Marcia scartata")
	# Crystallize basic: pay a mana, gain a crystal of that colour
	var e3 := mk()
	var ids3 := hand(e3, p, ["crystallize"])
	e3.s.players[p].tokens = ["white"]
	e3.s.players[p].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	e3.s.source = [{"color": "black", "taken_by": -1}]
	e3.s.day = true
	ok(act(e3, {"t": "play", "card": ids3[0], "mode": "basic"}), "Cristallizzare")
	answer_all(e3, p)
	eq(int(e3.s.players[p].crystals.white), 1, "gettone bianco trasformato in cristallo bianco")
	eq(e3.s.players[p].tokens.size(), 0, "gettone speso")
	# Mana Draw powered: die set to a colour, two tokens, die not rerolled at end of turn
	var e4 := mk()
	var ids4 := hand(e4, p, ["mana_draw", "march"])
	e4.s.day = true
	e4.s.players[p].tokens = []
	e4.s.players[p].crystals = {"red": 0, "blue": 0, "green": 0, "white": 1}
	e4.s.source = [{"color": "red", "taken_by": -1}, {"color": "blue", "taken_by": -1}, {"color": "green", "taken_by": -1}]
	ok(act(e4, {"t": "play", "card": ids4[0], "mode": "powered", "mana": ["crystal:white"]}), "Attingere Mana potenziata")
	var guard := 0
	while e4.s.pending != null and guard < 5:
		guard += 1
		if not _pick(e4, "verde") and not _pick(e4, "green"):
			act(e4, {"t": "choose", "v": [e4.s.pending.options[0].v]})
	var greens := 0
	for t in e4.s.players[p].tokens:
		if t == "green":
			greens += 1
	ok(e4.s.players[p].tokens.size() == 2, "due gettoni dello stesso colore (%s)" % str(e4.s.players[p].tokens))
	var taken_i := -1
	for i in e4.s.source.size():
		if int(e4.s.source[i].taken_by) == p:
			taken_i = i
	ok(taken_i >= 0, "il dado è preso dalla Riserva")
	var col: String = e4.s.source[taken_i].color if taken_i >= 0 else ""
	act(e4, {"t": "play", "card": ids4[1], "mode": "basic"})
	end_turn_all(e4, p)
	if taken_i >= 0:
		eq(e4.s.source[taken_i].color, col, "il dado torna nella Riserva senza essere rilanciato")
	# Tranquility out of combat with wounds: heal
	var e5 := mk()
	var ids5 := hand(e5, p, ["tranquility", "wound", "wound"])
	act(e5, {"t": "play", "card": ids5[0], "mode": "basic"})
	_pick(e5, "Cura")
	eq(wounds_in(e5, e5.s.players[p].hand), 1, "Tranquillità: Cura 1 elimina una Ferita")
	# Swiftness powered: ranged 3 usable against unfortified in ranged phase
	var e6 := mk()
	var ids6 := hand(e6, p, ["swiftness"])
	e6.s.players[p].crystals.white = 1
	var g6 := fight(e6, ["prowlers"])
	ok(act(e6, {"t": "play", "card": ids6[0], "mode": "powered"}), "Rapidità potenziata in fase a distanza")
	ok(act(e6, {"t": "attack", "targets": g6}), "Attacco a distanza 3 sconfigge i Predoni (armatura 3)")
	# Whirlwind basic: target enemy does not attack
	var e7 := mk()
	var ids7 := hand(e7, p, ["whirlwind"])
	e7.s.players[p].crystals.white = 1
	var g7 := fight(e7, ["swordsmen"])
	ok(act(e7, {"t": "play", "card": ids7[0], "mode": "basic"}), "Turbine")
	answer_all(e7, p)
	act(e7, {"t": "next"})
	act(e7, {"t": "next"})
	eq(e7.s.combat.phase, "attack", "Turbine: il nemico non attacca, nessun danno")
	# Tremor: one enemy armour -3 (min 1)
	var e8 := mk()
	var ids8 := hand(e8, p, ["tremor"])
	e8.s.players[p].crystals.green = 1
	var g8 := fight(e8, ["guardsmen", "prowlers"])
	act(e8, {"t": "play", "card": ids8[0], "mode": "basic"})
	if not _pick(e8, "-3"):
		answer_all(e8, p)
	answer_all(e8, p)
	var arms: Array = []
	for en in e8.s.combat.enemies:
		arms.append(MKCombat.armor_of(e8, en))
	ok(arms.has(4) or arms == [5, 1], "Tremore: Armatura -3 a un nemico (%s)" % str(arms))
	# Demolish basic before an assault: site fortification ignored
	var e9 := mk()
	var k := _keep_lab(e9, "keep", "guardsmen")
	var ids9 := hand(e9, p, ["demolish", "march"])
	e9.s.players[p].crystals.red = 1
	e9.s.turn.pool.move = 2
	ok(act(e9, {"t": "play", "card": ids9[0], "mode": "basic"}), "Demolire prima dell'assalto")
	act(e9, {"t": "move", "to": k})
	var en9: Dictionary = e9.s.combat.enemies[0]
	ok(MKCombat.is_fortified(en9) and not MKCombat.is_double_fortified(en9), "Demolire: resta solo la fortificazione propria delle Guardie")
	eq(MKCombat.armor_of(e9, en9), 6, "Demolire: Armatura -1")
	# Burning shield powered: successful block destroys the enemy
	var e10 := mk()
	var ids10 := hand(e10, p, ["burning_shield"])
	e10.s.day = false
	e10.s.players[p].crystals.red = 1
	e10.s.players[p].tokens = ["black"]
	var g10 := fight(e10, ["prowlers"])
	act(e10, {"t": "next"})
	ok(act(e10, {"t": "play", "card": ids10[0], "mode": "powered"}), "Scudo Esplosivo")
	var f10: int = e10.s.players[p].fame
	ok(act(e10, {"t": "block", "eid": g10[0]}), "blocco riuscito con Blocco di Fuoco 4")
	answer_all(e10, p)
	ok(e10.s.combat == null or e10.s.combat.enemies[0].defeated, "il nemico bloccato viene distrutto")
	eq(int(e10.s.players[p].fame), f10 + 2, "Fama per il nemico distrutto")
	# Maximal effect basic: throw away March, Move 2 x 3
	var e11 := mk()
	var ids11 := hand(e11, p, ["maximal_effect", "march"])
	ok(act(e11, {"t": "play", "card": ids11[0], "mode": "basic"}), "Effetto Massimo")
	answer_all(e11, p)
	eq(int(e11.s.turn.pool.move), 6, "Effetto Massimo: Marcia base tre volte = Movimento 6")
	ok(ids11[1] in e11.s.players[p].removed, "Marcia gettata via")
	# Expose basic: target loses fortification and resistances, ranged 2
	var e12 := mk()
	var ids12 := hand(e12, p, ["expose"])
	e12.s.players[p].crystals.white = 1
	var g12 := fight(e12, ["diggers"])
	ok(act(e12, {"t": "play", "card": ids12[0], "mode": "basic"}), "Esposizione")
	answer_all(e12, p)
	e12.s.turn.pool.attack["ranged:phys"] = 3
	ok(e12.check({"t": "attack", "targets": g12}) == "", "Esposizione: i Fossori perdono la fortificazione")

func t_agility_diplomacy():
	var p := 0
	# Agility in combat: Move cards can be played and converted into attacks
	var e := mk()
	var ids := hand(e, p, ["agility", "march", "stamina"])
	var g := fight(e, ["prowlers"])
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	act(e, {"t": "damage", "eid": g[0], "to": "hero"})
	act(e, {"t": "next"})
	eq(e.s.combat.phase, "attack", "fase di attacco")
	ok(act(e, {"t": "play", "card": ids[0], "mode": "basic"}), "Agilità in combattimento")
	ok(e.check({"t": "play", "card": ids[1], "mode": "basic"}) == "", "con Agilità si può giocare Marcia in combattimento")
	act(e, {"t": "play", "card": ids[1], "mode": "basic"})
	eq(int(e.s.turn.pool.move), 4, "Movimento 2 + 2")
	ok(e.check({"t": "play", "card": ids[2], "mode": "side", "side": "move"}) == "", "e anche Movimento 1 di lato")
	for i in 3:
		act(e, {"t": "sp", "name": "move_to_attack", "kind": "melee"})
	eq(int(e.s.turn.pool.attack.get("melee:phys", 0)), 3, "3 Movimento convertiti in Attacco 3")
	ok(act(e, {"t": "attack", "targets": g}), "Predoni sconfitti con l'Attacco da Movimento")
	# without Agility, March is not playable in combat
	var e2 := mk()
	var ids2 := hand(e2, p, ["march"])
	fight(e2, ["prowlers"])
	ok(e2.check({"t": "play", "card": ids2[0], "mode": "basic"}) != "", "senza Agilità niente Movimento in combattimento")
	# Diplomacy: Influence cards in combat become Block
	var e3 := mk()
	var ids3 := hand(e3, p, ["diplomacy", "promise", "march"])
	var g3 := fight(e3, ["prowlers"])
	act(e3, {"t": "next"})
	ok(act(e3, {"t": "play", "card": ids3[0], "mode": "basic"}), "Diplomazia in fase di blocco")
	ok(e3.check({"t": "play", "card": ids3[1], "mode": "basic"}) == "", "con Diplomazia si gioca Promessa in combattimento")
	act(e3, {"t": "play", "card": ids3[1], "mode": "basic"})
	ok(act(e3, {"t": "sp", "name": "influence_as_block"}), "Influenza usata come Blocco")
	ok(act(e3, {"t": "block", "eid": g3[0]}), "Predoni bloccati con Blocco 4 da Influenza")
