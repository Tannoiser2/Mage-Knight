extends SceneTree
## Espansioni: ogni carta/unità/abilità delle espansioni (La Legione Perduta, Krang, Shades of Tezla,
## Ultimate Edition, promo) giocata almeno una volta come in qa_test, più le regole nuove (nemici,
## mura, Campo Profughi, Dedalo/Labirinto, Miniere Profonde, eroi e speciali).
## godot --headless --path . -s res://tests/exp_test.gd [-- nome_test]

const EXP_SETS := ["ll", "krang", "tezla", "ue", "promo"]

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
	var tests := [t_data, t_setup_content, t_elusive, t_assassinate, t_defend, t_cumbersome, t_vampiric, t_summon_two,
		t_rep_on_defeat, t_walls_move, t_walls_combat, t_camp, t_maze, t_maze_unit, t_labyrinth, t_deep_mine, t_familiars,
		t_banner_command, t_mysterious_box, t_druidic_staff, t_puppet_master, t_master_of_chaos, t_wolfs_howl,
		t_mana_suppression, t_mana_enhancement, t_natures_vengeance, t_forked_lightning, t_shapeshift, t_druidic_paths,
		t_savage_harvesting, t_draw_fire, t_inter_others, t_krang_flips, t_hero_decks, t_cards_all, t_units_all, t_skills_all]
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
	print("EXP: %d ok, %d falliti" % [passes, fails])
	quit(1 if fails > 0 else 0)

# ------------------------------------------------------------------ helpers (as in qa_test)
func mk(scn := "solo_conquest", seed := 1, heroes := ["arythea"], content := "tezla") -> MKEngine:
	var cfg := {"scenario": scn, "seed": seed, "players": [], "options": {"content": content}}
	for h in heroes:
		cfg.players.append({"hero": h, "name": h})
	var e := MKEngine.create(cfg)
	var guard := 0
	while (e.s.phase == "tactics" or e.s.pending != null) and guard < 50:
		guard += 1
		var av := e.available()
		var r := e.apply(av[0].a)
		if not r.ok:
			print(r)
			break
	return e

func lab(e: MKEngine, p := 0) -> void:
	e.s.map.hex = {}
	e.s.map["walls"] = {}
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

func pick(e: MKEngine, label_part: String) -> bool:
	if e.s.pending == null:
		print("    nessuna decisione in sospeso (cercavo '%s')" % label_part)
		return false
	for o in e.s.pending.options:
		if str(o.label).findn(label_part) >= 0:
			return act(e, {"t": "choose", "v": [o.v]})
	print("    opzione '%s' non trovata in %s" % [label_part, str(e.s.pending.options)])
	return false

func has_action(e: MKEngine, pred: Callable) -> Dictionary:
	for x in e.available():
		if pred.call(x.a):
			return x.a
	return {}

func entry(e: MKEngine, eid: String) -> Dictionary:
	return MKCombat.entry(e, eid)

func to_attack_phase(e: MKEngine) -> void:
	act(e, {"t": "next"})      # ranged -> block
	act(e, {"t": "next"})      # block -> damage (or attack)
	while e.s.combat != null and e.s.combat.phase == "damage":
		var done := false
		for en in e.s.combat.enemies:
			for i in en.attacks.size():
				if int(en.attacks[i].rem) > 0 and not done:
					act(e, {"t": "damage", "eid": en.eid, "attack": i, "to": "hero"})
					done = true
		if not done:
			act(e, {"t": "next"})

func skill_state(id: String, heroes := ["arythea"], scn := "solo_conquest") -> MKEngine:
	var e := mk(scn, 3, heroes)
	lab(e)
	MKSites.add_skill(e, 0, id)
	return e

# ------------------------------------------------------------------ data
func t_data():
	ok(MKDB.problems.is_empty(), "nessun problema nei dati: %s" % str(MKDB.problems))
	for sid in ["wolfs_howl", "puppet_master", "master_of_chaos", "mana_suppression", "mana_enhancement", "multi_attack", "shapeshift",
			"natures_vengeance", "crystal_on_move", "reduce_space_cost", "druidic_staff", "banner_command", "mysterious_box",
			"familiars_upkeep", "unit_token_bonus"]:
		ok(MKSpecials.has(sid), "speciale implementato: " + sid)
	for st in EXP_SETS:
		for id in MKDB.cards:
			if MKDB.cards[id].get("set", "") == st:
				ok(MKDB.card_ok(id), "carta disponibile: " + id)
		for id in MKDB.units:
			if MKDB.units[id].get("set", "") == st:
				ok(MKDB.unit_ok(id), "unità disponibile: " + id)
		for id in MKDB.skills:
			if MKDB.skills[id].get("set", "") == st:
				ok(MKDB.skill_ok(id), "abilità disponibile: " + id)
	eq(MKDB.enemies.orc_tracker.get("elusive_armor", 0), 6, "armatura elusiva dell'Orco Segugio")
	eq(MKDB.enemies.dragon_summoner.get("summon_n", 0), 2, "Evocatore di Draghi: due evocazioni")
	eq(MKDB.enemies.thugs.rep, 1, "Teppisti: Reputazione +1")
	ok(MKDB.tiles.c12.has("walls"), "mura della tessera 12")

func t_setup_content():
	var e := mk("full_conquest", 5, ["wolfhawk", "krang", "braevalar"], "tezla")
	var sets: Array = e.s.scn.sets
	ok("ll" in sets and "tezla" in sets and "krang" in sets and not "fan" in sets, "set dei contenuti: %s" % str(sets))
	for tid in ["c12", "c13", "c14", "k09", "k10"]:
		ok(e._tile_supported(MKDB.tiles[tid]), "tessera %s supportata" % tid)
	ok(not e._tile_supported(MKDB.tiles["volkare_camp"]), "accampamento di Volkare escluso")
	var all_tiles: Array = e.s.map.tile_deck + e.s.decks.tiles_spare
	for t in e.s.map.tiles:
		all_tiles.append(t.id)
	var has_ll := false
	for tid in all_tiles:
		if MKDB.tiles.get(tid, {}).get("set", "") == "ll":
			has_ll = true
		ok(MKDB.tiles.get(tid, {}).get("set", "") in ["base", "ll"], "nessuna tessera di altri set (%s)" % tid)
	ok(has_ll, "tessere della Legione Perduta nel mazzo")
	var types := {}
	for col in e.s.enemy_bags:
		for ty in e.s.enemy_bags[col].draw:
			types[MKDB.enemies.get(ty, MKDB.ruins.get(ty, {})).get("set", "?")] = true
	ok(types.has("ll") and types.has("tezla"), "nemici LL e Tezla nelle pile: %s" % str(types.keys()))
	var aa_ll := false
	for id in e.s.decks.aa + e.s.offers.aa:
		if MKDB.cards[id].set == "ll":
			aa_ll = true
	ok(aa_ll, "Azioni Avanzate della Legione nel mazzo")
	for pl in e.s.players:
		ok(pl.skill_pile.size() >= 10, "%s ha la pila delle abilità (%d)" % [pl.hero, pl.skill_pile.size()])
		eq(pl.deck.size() + pl.hand.size(), 16, "%s ha 16 carte" % pl.hero)
	# base content: expansion heroes keep their own cards and skills
	var e2 := mk("solo_conquest", 2, ["braevalar"], "base")
	ok(e2.s.players[0].skill_pile.size() >= 10, "Braevalar ha le sue abilità anche col gioco base")
	for col in e2.s.enemy_bags:
		for ty in e2.s.enemy_bags[col].draw:
			if MKDB.enemies.has(ty):
				eq(MKDB.enemies[ty].set, "base", "solo nemici base con i contenuti Base")
				break
	# tile placement creates the walls
	var e3 := mk()
	e3.place_tile("c12", "3,-2", -1)
	ok(not e3.s.map.get("walls", {}).is_empty(), "le mura della tessera 12 sono sulla mappa")

# ------------------------------------------------------------------ enemy abilities
func t_elusive():
	var e := mk()
	lab(e)
	var ids := fight(e, ["orc_tracker"])
	var en := entry(e, ids[0])
	eq(MKCombat.armor_of(e, en), 6, "Elusivo: armatura alta nella fase a distanza")
	e.s.turn.pool.attack = {"ranged:phys": 5}
	ok(e.check({"t": "attack", "targets": ids}) != "", "attacco a distanza 5 non basta")
	act(e, {"t": "next"})
	e.s.turn.pool.block = {"phys": 4}
	act(e, {"t": "block", "eid": ids[0]})
	act(e, {"t": "next"})
	eq(e.s.combat.phase, "attack", "fase di attacco")
	eq(MKCombat.armor_of(e, en), 3, "Elusivo bloccato: armatura bassa nella fase di attacco")
	# not blocked -> high armour also in the attack phase
	var e2 := mk()
	lab(e2)
	var ids2 := fight(e2, ["orc_tracker"])
	to_attack_phase(e2)
	eq(MKCombat.armor_of(e2, entry(e2, ids2[0])), 6, "Elusivo non bloccato: armatura alta")

func t_assassinate():
	var e := mk()
	lab(e)
	MKSites.gain_unit(e, 0, "utem_guardsmen")
	var ids := fight(e, ["orc_tracker"])
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	var uid: int = int(e.s.players[0].units[0].uid)
	ok(e.check({"t": "damage", "eid": ids[0], "attack": 0, "to": uid}) != "", "Assassinio: niente danni alle unità")
	eq(e.check({"t": "damage", "eid": ids[0], "attack": 0, "to": "hero"}), "", "Assassinio: danni all'eroe")
	# a normal enemy can still damage units
	var e2 := mk()
	lab(e2)
	MKSites.gain_unit(e2, 0, "utem_guardsmen")
	var ids2 := fight(e2, ["prowlers"])
	act(e2, {"t": "next"})
	act(e2, {"t": "next"})
	eq(e2.check({"t": "damage", "eid": ids2[0], "attack": 0, "to": int(e2.s.players[0].units[0].uid)}), "", "danni alle unità normali")

func t_defend():
	var e := mk()
	lab(e)
	var ids := fight(e, ["elven_protectors", "prowlers"])
	var pr := entry(e, ids[1])
	eq(MKCombat.armor_of(e, pr), 3 + 2, "armatura mostrata con il Difensore")
	e.s.turn.pool.attack = {"ranged:phys": 4}
	ok(e.check({"t": "attack", "targets": [ids[1]]}) != "", "Difensore: 4 non basta contro armatura 3+2")
	e.s.turn.pool.attack = {"ranged:phys": 5}
	ok(act(e, {"t": "attack", "targets": [ids[1]]}), "attacco 5 sconfigge i Predatori difesi")
	ok(entry(e, ids[0]).get("defend_used", false), "il Difensore ha usato la sua abilità")
	eq(MKCombat.armor_of(e, entry(e, ids[0])), 4, "il Difensore ora non si difende più")
	e.s.turn.pool.attack = {"ranged:phys": 4}
	ok(act(e, {"t": "attack", "targets": [ids[0]]}), "Protettori Elfici (armatura 4) sconfitti con 4")
	# group of two targets: only one defend bonus
	var e2 := mk()
	lab(e2)
	var ids2 := fight(e2, ["elven_protectors", "prowlers"])
	e2.s.turn.pool.attack = {"ranged:phys": 9}
	ok(e2.check({"t": "attack", "targets": ids2}) == "", "gruppo: 4+3+2 = 9 basta (un solo bonus)")
	e2.s.turn.pool.attack = {"ranged:phys": 8}
	ok(e2.check({"t": "attack", "targets": ids2}) != "", "gruppo: 8 non basta")

func t_cumbersome():
	var e := mk()
	lab(e)
	var ids := fight(e, ["zombie_horde"])
	act(e, {"t": "next"})
	eq(e.s.combat.phase, "block", "fase di blocco")
	var iids := hand(e, 0, ["march", "rage"])
	eq(e.check({"t": "play", "card": iids[0], "mode": "basic"}), "", "Marcia giocabile contro un nemico Ingombrante")
	act(e, {"t": "play", "card": iids[0], "mode": "basic"})
	eq(int(e.s.turn.pool.move), 2, "2 punti Movimento in combattimento")
	var a := has_action(e, func(x): return x.get("name", "") == "cumbersome")
	ok(not a.is_empty(), "azione Ingombrante disponibile")
	act(e, {"t": "sp", "name": "cumbersome", "eid": ids[0], "attack": 0})
	ok(entry(e, ids[0]).attacks[0].blocked, "attacco ridotto a 0 = bloccato")
	act(e, {"t": "sp", "name": "cumbersome", "eid": ids[0], "attack": 1})
	eq(int(e.s.turn.pool.move), 0, "Movimento speso")
	act(e, {"t": "next"})
	eq(int(entry(e, ids[0]).attacks[1].rem), 0, "nessun danno dall'attacco ridotto a 0")
	eq(int(entry(e, ids[0]).attacks[2].rem), 1, "il terzo attacco colpisce")
	# no cumbersome enemy -> no move in combat
	var e2 := mk()
	lab(e2)
	fight(e2, ["prowlers"])
	act(e2, {"t": "next"})
	var i2 := hand(e2, 0, ["march"])
	ok(e2.check({"t": "play", "card": i2[0], "mode": "basic"}) != "", "Movimento inutile senza nemici Ingombranti")

func t_vampiric():
	var e := mk()
	lab(e)
	var ids := fight(e, ["gibbering_ghouls"])
	act(e, {"t": "next"})
	act(e, {"t": "next"})
	act(e, {"t": "damage", "eid": ids[0], "attack": 0, "to": "hero"})
	eq(int(entry(e, ids[0]).get("vamp", 0)), 2, "Vampirico: +1 per ferita (2 ferite)")
	act(e, {"t": "next"})
	eq(MKCombat.armor_of(e, entry(e, ids[0])), 6, "armatura 4+2")

func t_summon_two():
	var e := mk()
	lab(e)
	var ids := fight(e, ["dragon_summoner"])
	act(e, {"t": "next"})
	var n := 0
	for en in e.s.combat.enemies:
		if en.summoned:
			n += 1
	eq(n, 2, "l'Evocatore di Draghi evoca due mostri")

func t_rep_on_defeat():
	var e := mk()
	lab(e)
	e.s.players[0].rep = 0
	var ids := fight(e, ["thugs", "heroes_1"])
	e.s.turn.pool.attack = {"ranged:phys": 40}
	act(e, {"t": "attack", "targets": [ids[0]]})
	eq(int(e.s.players[0].rep), 1, "Teppisti: Reputazione +1")
	e.s.turn.pool.attack = {"ranged:phys": 40}
	act(e, {"t": "attack", "targets": [ids[1]]})
	eq(int(e.s.players[0].rep), 0, "Eroi: Reputazione -1")

# ------------------------------------------------------------------ walls
func t_walls_move():
	var e := mk()
	lab(e)
	e.s.map.walls[MKEngine.wall_key("0,0", "1,0")] = true
	eq(e.move_cost("1,0", "0,0"), 3, "muro: +1 Movimento")
	eq(e.move_cost("1,0"), 2, "senza provenienza il muro non conta")
	e.s.turn.pool.move = 2
	ok(e.check({"t": "move", "to": "1,0"}) != "", "2 Movimento non bastano attraverso il muro")
	e.s.turn.pool.move = 3
	ok(e.reachable().has("1,0"), "reachable conta il muro")
	act(e, {"t": "move", "to": "1,0"})
	eq(int(e.s.turn.pool.move), 0, "muro pagato")
	# terrain discounts cannot remove the wall cost
	var e2 := mk()
	lab(e2)
	e2.s.map.walls[MKEngine.wall_key("0,0", "1,0")] = true
	e2.s.turn.mods.append({"name": "terrain", "map": {"all": 0}, "src": ""})
	eq(e2.move_cost("1,0", "0,0"), 1, "sconti sul terreno: il muro costa sempre 1")
	# provocation across a wall
	var e3 := mk()
	lab(e3)
	put_enemy(e3, "1,-1", "prowlers")
	e3.s.turn.pool.move = 10
	act(e3, {"t": "move", "to": "1,0"})
	ok(e3.s.combat != null, "senza mura: provocazione")
	var e4 := mk()
	lab(e4)
	put_enemy(e4, "1,-1", "prowlers")
	e4.s.map.walls[MKEngine.wall_key("1,-1", "1,0")] = true
	e4.s.turn.pool.move = 10
	act(e4, {"t": "move", "to": "1,0"})
	ok(e4.s.combat == null, "il muro impedisce la provocazione")

func t_walls_combat():
	var e := mk()
	lab(e)
	var eid := put_enemy(e, "1,-1", "prowlers")
	e.s.map.walls[MKEngine.wall_key("0,0", "1,-1")] = true
	act(e, {"t": "challenge", "hexes": ["1,-1"]})
	ok(e.s.combat != null and MKCombat.is_fortified(entry(e, eid)), "sfida attraverso un muro: nemico fortificato")
	# assault across a wall: double fortification
	var e2 := mk()
	lab(e2)
	e2.s.map.hex["1,0"].site = "keep"
	var g := put_enemy(e2, "1,0", "swordsmen", false)
	e2.s.map.walls[MKEngine.wall_key("0,0", "1,0")] = true
	e2.s.turn.pool.move = 5
	act(e2, {"t": "move", "to": "1,0"})
	ok(e2.s.combat != null and MKCombat.is_double_fortified(entry(e2, g)), "assalto attraverso un muro: fortificazione doppia")
	var e3 := mk()
	lab(e3)
	e3.s.map.hex["1,0"].site = "keep"
	var g3 := put_enemy(e3, "1,0", "swordsmen", false)
	e3.s.turn.pool.move = 5
	act(e3, {"t": "move", "to": "1,0"})
	ok(e3.s.combat != null and not MKCombat.is_double_fortified(entry(e3, g3)), "assalto normale: fortificazione semplice")

# ------------------------------------------------------------------ sites
func t_camp():
	var e := mk()
	lab(e)
	e.s.map.hex["0,0"].site = "camp"
	e.s.players[0].rep = 0
	eq(MKSites.interaction_site(e, 0), "camp", "Campo Profughi: si interagisce")
	e.s.offers.units = ["peasants", "magic_familiars", "altem_guardians", "utem_swordsmen"]
	eq(MKSites.unit_cost(e, 0, "peasants"), 4, "villaggio +0")
	eq(MKSites.unit_cost(e, 0, "utem_swordsmen"), 6 + 1, "castello +1")
	eq(MKSites.unit_cost(e, 0, "magic_familiars"), 6 + 1, "monastero/torre +1")
	eq(MKSites.unit_cost(e, 0, "altem_guardians"), 11 + 3, "solo città +3")
	hand(e, 0, ["promise", "threaten"])
	e.s.turn.pool.influence = 7
	e.s.players[0].command = 2
	ok(act(e, {"t": "recruit", "id": "utem_swordsmen"}), "reclutamento al campo")
	eq(int(e.s.turn.pool.influence), 0, "pagati 7")
	ok(MKSites._buy_options(e, 0).is_empty(), "al campo non si compra altro")

func t_maze():
	var e := mk()
	lab(e)
	e.s.map.hex["0,0"].site = "maze"
	e.s.turn.pool.move = 6
	var iids := hand(e, 0, ["march", "stamina", "rage", "rage"])
	ok(act(e, {"t": "site"}), "entra nel dedalo")
	eq(int(e.s.turn.pool.move), 0, "i punti Movimento avanzati non valgono")
	ok(MKSitesExp.paying(e, 0), "fase di pagamento del sentiero")
	ok(has_action(e, func(x): return x.get("name", "") == "maze_path").is_empty(), "senza Movimento nessun sentiero")
	act(e, {"t": "play", "card": iids[0], "mode": "basic"})
	var a := has_action(e, func(x): return x.get("name", "") == "maze_path" and int(x.get("cost", 0)) == 2)
	ok(not a.is_empty(), "sentiero 2 disponibile")
	ok(act(e, a), "sceglie il sentiero 2")
	ok(e.s.combat != null and e.s.combat.site_type == "maze", "combattimento nel dedalo")
	eq(str(e.s.combat.enemies[0].color), "brown", "nemico marrone")
	ok(not e.s.combat.units_allowed, "nessuna unità")
	e.s.turn.pool.attack = {"ranged:cold": 30}
	act(e, {"t": "attack", "targets": [e.s.combat.enemies[0].eid]})
	ok(e.s.combat == null, "combattimento vinto")
	eq(int(e.s.map.hex["0,0"].get("maze_paths", {}).get("2", -1)), 0, "sentiero 2 conquistato")
	ok("0,0" in e.s.players[0].shields, "scudo sul dedalo")
	var cr0 := 0
	for c in e.s.players[0].crystals:
		cr0 += int(e.s.players[0].crystals[c])
	act(e, {"t": "end_turn"})
	answer_all(e)
	var cr1 := 0
	for c in e.s.players[0].crystals:
		cr1 += int(e.s.players[0].crystals[c])
	eq(cr1 - cr0, 2, "ricompensa: due cristalli a scelta")
	eq(MKSitesExp.site_check(e, 0, e.s.map.hex["0,0"]).find("già") >= 0, true, "lo stesso giocatore non riconquista il dedalo")
	eq(MKSitesExp.free_paths(e, e.s.map.hex["0,0"]), [4, 6], "restano i sentieri 4 e 6")
	ok(e.s.enemy_bags.brown.discard.size() >= 1, "il nemico del dedalo è scartato")

func t_maze_unit():
	var e := mk()
	lab(e)
	e.s.map.hex["0,0"].site = "maze"
	e.s.players[0].command = 3
	MKSites.gain_unit(e, 0, "peasants")
	MKSites.gain_unit(e, 0, "utem_crossbowmen")
	var u0: int = int(e.s.players[0].units[0].uid)
	var u1: int = int(e.s.players[0].units[1].uid)
	hand(e, 0, ["march", "march", "rage"])
	act(e, {"t": "site"})
	ok(e.s.pending != null and e.s.pending.type == "unit", "scelta dell'Unità che accompagna")
	act(e, {"t": "choose", "v": [u0]})
	var peas: Dictionary = MKDB.units.peasants
	var mv_ab := 0
	for i in peas.abilities.size():
		if str(peas.abilities[i].effect[0][0]) == "move":
			mv_ab = i
	ok(e.check({"t": "unit", "uid": u1, "ability": 0}) != "", "le altre Unità non si usano nel dedalo")
	eq(e.check({"t": "unit", "uid": u0, "ability": mv_ab}), "", "l'Unità scelta si usa (Contadini: Movimento)")
	act(e, {"t": "unit", "uid": u0, "ability": mv_ab})
	answer_all(e)
	ok(int(e.s.turn.pool.move) >= 2, "Movimento dall'Unità")
	act(e, {"t": "sp", "name": "maze_path", "cost": 2})
	ok(e.s.combat != null and int(e.s.combat.get("units_only", -1)) == u0, "solo l'Unità scelta in combattimento")

func t_labyrinth():
	var e := mk()
	lab(e)
	e.s.map.hex["0,0"].site = "labyrinth"
	e.s.map.hex["0,0"]["maze_paths"] = {"2": 1, "4": 1}
	hand(e, 0, ["march", "march", "march", "rage"])
	act(e, {"t": "site"})
	for iid in e.s.players[0].hand.duplicate():
		if e.card_id(iid) == "march":
			act(e, {"t": "play", "card": iid, "mode": "basic"})
	ok(e.check({"t": "sp", "name": "maze_path", "cost": 2}) != "", "sentiero già conquistato da un altro")
	ok(act(e, {"t": "sp", "name": "maze_path", "cost": 6}), "sentiero 6")
	eq(str(e.s.combat.enemies[0].color), "red", "Draconum rosso nel labirinto")
	e.s.turn.pool.attack = {"siege:cold": 40}
	act(e, {"t": "attack", "targets": [e.s.combat.enemies[0].eid]})
	var kinds: Array = []
	for r in e.s.turn.rewards:
		kinds.append(r.k)
	eq(kinds, ["artifact", "aa"], "labirinto sentiero 6: Artefatto + Azione Avanzata")
	ok(e.s.map.hex["0,0"].conquered, "tutti i sentieri conquistati")

func t_deep_mine():
	var e := mk()
	lab(e)
	e.s.map.hex["0,0"].site = "mine"
	e.s.map.hex["0,0"]["mines"] = ["red", "white"]
	hand(e, 0, ["march", "rage"])
	act(e, {"t": "play", "card": e.s.players[0].hand[0], "mode": "basic"})
	act(e, {"t": "end_turn"})
	ok(e.s.pending != null and e.s.pending.handler == "mine", "Miniera profonda: scelta del colore")
	pick(e, "bianco")
	eq(int(e.s.players[0].crystals.white), 1, "cristallo bianco")

# ------------------------------------------------------------------ units / artifacts
func t_familiars():
	var e := mk()
	lab(e)
	e.s.map.hex["0,0"].site = "monastery"
	e.s.offers.units = ["magic_familiars"]
	e.s.players[0].crystals = {"red": 1, "blue": 0, "green": 0, "white": 0}
	e.s.players[0].tokens = []
	e.s.source = [{"color": "black", "taken_by": -1}]
	e.s.day = true
	e.s.turn.pool.influence = 6
	hand(e, 0, ["promise"])
	ok(act(e, {"t": "recruit", "id": "magic_familiars"}), "recluta i Famigli Magici")
	ok(e.s.pending != null and e.s.pending.handler == "sp:familiar_token", "paga il mana del segnalino")
	answer_all(e)
	var u: Dictionary = e.s.players[0].units[0]
	eq(str(u.get("token", "")), "red", "segnalino rosso")
	eq(int(e.s.players[0].crystals.red), 0, "cristallo speso")
	fight(e, ["prowlers"])
	to_attack_phase(e)
	act(e, {"t": "unit", "uid": int(u.uid), "ability": 0})
	eq(int(e.s.turn.pool.attack.get("melee:phys", 0)), 5, "Attacco 3 +2 con il segnalino rosso")
	# without mana they cannot be recruited
	var e2 := mk()
	lab(e2)
	e2.s.map.hex["0,0"].site = "monastery"
	e2.s.offers.units = ["magic_familiars"]
	e2.s.players[0].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	e2.s.players[0].tokens = []
	e2.s.source = []
	e2.s.turn.pool.influence = 9
	ok(e2.check({"t": "recruit", "id": "magic_familiars"}) != "", "senza mana non si reclutano")
	# upkeep at the start of the round
	var e3 := mk()
	lab(e3)
	MKSites.gain_unit(e3, 0, "magic_familiars")
	e3.s.players[0].crystals = {"red": 0, "blue": 2, "green": 0, "white": 0}
	MKSpecialsExp.on_round_start(e3)
	ok(e3.s.pending != null and e3.s.pending.handler == "sp:familiars_keep", "mantenimento a inizio round")
	pick(e3, "blu")
	eq(int(e3.s.players[0].crystals.blue), 1, "pagato un cristallo blu")
	eq(str(e3.s.players[0].units[0].get("token", "")), "blue", "nuovo segnalino blu")
	e3.s.players[0].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	MKSpecialsExp.on_round_start(e3)
	eq(e3.s.players[0].units.size(), 0, "senza cristalli i Famigli se ne vanno")

func t_banner_command():
	var e := mk()
	lab(e)
	e.s.map.hex["0,0"].site = "village"
	MKSites.gain_unit(e, 0, "herbalists")
	e.s.players[0].command = 1
	e.s.offers.units = ["peasants"]
	var iids := hand(e, 0, ["banner_of_command", "promise"])
	eq(e.command_free(0), 0, "comando pieno")
	act(e, {"t": "play", "card": iids[0], "mode": "basic"})
	eq(e.command_free(0), 1, "lo Stendardo del Comando dà un posto in più")
	ok(act(e, {"t": "recruit", "id": "peasants"}), "recluta senza congedare")
	eq(e.s.players[0].units.size(), 2, "due unità")
	ok(e.s.players[0].get("banners", {}).size() == 1, "stendardo assegnato all'unità reclutata")
	eq(e.command_free(0), 0, "comando: l'unità con lo stendardo non usa un segnalino")
	# recruited first, then played
	var e2 := mk()
	lab(e2)
	e2.s.map.hex["0,0"].site = "village"
	e2.s.players[0].command = 2
	e2.s.offers.units = ["peasants"]
	var i2 := hand(e2, 0, ["banner_of_command", "promise"])
	e2.s.turn.pool.influence = 4
	act(e2, {"t": "recruit", "id": "peasants"})
	act(e2, {"t": "play", "card": i2[0], "mode": "basic"})
	ok(e2.s.pending != null, "scelta dell'unità reclutata")
	pick(e2, "Assegna")
	eq(e2.command_free(0), 2 - 1 + 1, "un segnalino Comando libero in più")

func t_mysterious_box():
	var e := mk()
	lab(e)
	var iids := hand(e, 0, ["mysterious_box", "march"])
	e.s.decks.artifacts.push_front("sword_of_justice")
	var nsw: int = e.s.decks.artifacts.count("sword_of_justice")
	fight(e, ["prowlers"])
	to_attack_phase(e)
	var f0 := int(e.s.players[0].fame)
	ok(act(e, {"t": "play", "card": iids[0], "mode": "basic"}), "gioca il Forziere")
	pick(e, "Marcia")
	answer_all(e)
	ok(not e.s.turn.pool.attack.is_empty(), "effetto della Spada della Giustizia")
	eq(int(e.s.players[0].fame) - f0, 1, "Fama +1")
	eq(e.s.decks.artifacts.count("sword_of_justice"), nsw - 1, "artefatto rivelato fuori dal mazzo")
	ok(e.check({"t": "play", "card": iids[0], "mode": "basic"}) != "", "una volta sola")
	e.s.turn.pool.attack = {"melee:phys": 10}
	act(e, {"t": "attack", "targets": [e.s.combat.enemies[0].eid]})
	act(e, {"t": "end_turn"})
	answer_all(e)
	eq(e.s.decks.artifacts[-1], "sword_of_justice", "a fine turno l'artefatto va in fondo al mazzo")
	# not usable -> back to hand
	var e2 := mk()
	lab(e2)
	var i2 := hand(e2, 0, ["mysterious_box", "march"])
	e2.s.decks.artifacts.push_front("sword_of_justice")
	act(e2, {"t": "play", "card": i2[0], "mode": "basic"})
	ok(i2[0] in e2.s.players[0].hand, "fuori dal combattimento la Spada non serve: il Forziere torna in mano")

func t_druidic_staff():
	var e := mk()
	lab(e)
	var iids := hand(e, 0, ["druidic_staff", "march", "wound", "wound", "wound"])
	ok(act(e, {"t": "play", "card": iids[0], "mode": "basic"}), "Bastone Druidico")
	answer_all(e)
	var w := 0
	for iid in e.s.players[0].hand:
		if e.is_wound(iid):
			w += 1
	eq(w, 0, "scarta Marcia (verde): Cura 3")
	var e2 := mk()
	lab(e2)
	var i2 := hand(e2, 0, ["druidic_staff", "march"])
	e2.s.players[0].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	act(e2, {"t": "play", "card": i2[0], "mode": "powered"})
	pick(e2, "2 cristalli")
	answer_all(e2)
	var cr := 0
	for c in e2.s.players[0].crystals:
		cr += int(e2.s.players[0].crystals[c])
	eq(cr, 2, "potenziato: due cristalli + un'altra opzione")
	ok(i2[1] in e2.s.players[0].hand, "potenziato: nessuno scarto")

# ------------------------------------------------------------------ hero skills
func t_puppet_master():
	var e := skill_state("krang_puppet_master", ["krang"])
	var ids := fight(e, ["prowlers"])
	e.s.turn.pool.attack = {"ranged:phys": 10}
	act(e, {"t": "attack", "targets": ids})
	ok(e.s.combat == null, "nemico sconfitto")
	ok(act(e, {"t": "skill", "id": "krang_puppet_master"}), "Burattinaio: conserva")
	answer_all(e)
	eq(e.s.players[0].get("kept_enemies", []), ["prowlers"], "segnalino conservato")
	e.s.turn = e._fresh_turn(0)
	for sk in e.s.players[0].skills:
		sk.used_turn = false
	fight(e, ["ironclads"])
	act(e, {"t": "next"})
	act(e, {"t": "skill", "id": "krang_puppet_master"})
	if e.s.pending != null:
		pick(e, "Blocco")
	eq(int(e.s.turn.pool.block.get("phys", 0)), 2, "Blocco = metà dell'armatura dei Predatori (3 -> 2)")
	eq(e.s.players[0].kept_enemies.size(), 0, "segnalino scartato")
	var e2 := skill_state("krang_puppet_master", ["krang"])
	e2.s.players[0]["kept_enemies"] = ["fire_mages"]
	fight(e2, ["prowlers"])
	to_attack_phase(e2)
	act(e2, {"t": "skill", "id": "krang_puppet_master"})
	answer_all(e2)
	eq(int(e2.s.turn.pool.attack.get("melee:fire", 0)), 3, "Attacco di Fuoco 3 (metà di 6)")

func t_master_of_chaos():
	var e := skill_state("krang_master_of_chaos", ["krang"])
	var sk = e.find_skill(0, "krang_master_of_chaos")
	ok(sk.has("chaos"), "colore iniziale casuale")
	sk.chaos = "green"
	ok(act(e, {"t": "skill", "id": "krang_master_of_chaos"}), "usa il Signore del Caos")
	eq(str(sk.chaos), "white", "verde -> bianco")
	eq(int(e.s.turn.pool.influence), 2, "bianco: Influenza 2")
	# blue -> green: Move 1
	var e2 := skill_state("krang_master_of_chaos", ["krang"])
	e2.find_skill(0, "krang_master_of_chaos").chaos = "blue"
	act(e2, {"t": "skill", "id": "krang_master_of_chaos"})
	eq(int(e2.s.turn.pool.move), 1, "verde: Movimento 1")
	# red -> black: ranged cold fire 1 in combat only
	var e3 := skill_state("krang_master_of_chaos", ["krang"])
	e3.find_skill(0, "krang_master_of_chaos").chaos = "red"
	ok(e3.check({"t": "skill", "id": "krang_master_of_chaos"}) != "", "nero fuori combattimento: inutilizzabile")
	fight(e3, ["prowlers"])
	act(e3, {"t": "skill", "id": "krang_master_of_chaos"})
	eq(int(e3.s.turn.pool.attack.get("ranged:cold", 0)), 1, "nero: Attacco a Distanza di Fuoco Freddo 1")
	# free rotation at the start of a turn when it was not used in the previous one
	var e4 := mk("solo_conquest", 3, ["krang"])
	MKSites.add_skill(e4, 0, "krang_master_of_chaos")
	e4.s.players[0].turns = 5
	MKSpecialsExp.on_turn_start(e4, 0)
	e4.s.turn = e4._fresh_turn(0)
	var c0: String = e4.find_skill(0, "krang_master_of_chaos").chaos
	var a := has_action(e4, func(x): return x.get("name", "") == "chaos_rotate")
	ok(not a.is_empty(), "rotazione gratuita disponibile")
	act(e4, a)
	ok(str(e4.find_skill(0, "krang_master_of_chaos").chaos) != c0, "colore avanzato")

func t_wolfs_howl():
	var e := skill_state("wolfhawk_wolfs_howl", ["wolfhawk"])
	e.s.players[0].command = 2
	var iids := hand(e, 0, ["march", "rage"])
	act(e, {"t": "skill", "id": "wolfhawk_wolfs_howl"})
	act(e, {"t": "play", "card": iids[0], "mode": "side", "side": "move"})
	eq(int(e.s.turn.pool.move), 4 + 2, "Ululato: carta di lato 4 +1 per segnalino Comando libero")
	act(e, {"t": "play", "card": iids[1], "mode": "side", "side": "move"})
	eq(int(e.s.turn.pool.move), 7, "solo una carta")
	# competitive: the units of the other players get -1
	var e2 := mk("full_conquest", 4, ["wolfhawk", "tovak"])
	lab(e2)
	MKSites.add_skill(e2, 0, "wolfhawk_wolfs_howl")
	e2.s.turn = e2._fresh_turn(0)
	hand(e2, 0, ["march"])
	act(e2, {"t": "skill", "id": "wolfhawk_wolfs_howl"})
	ok(MKSpecialsExp.inter_get(e2, "wolfs_howl") != null, "Ululato in gioco per gli altri")
	e2.s.turn = e2._fresh_turn(1)
	MKSites.gain_unit(e2, 1, "peasants")
	fight(e2, ["prowlers"])
	act(e2, {"t": "next"})
	act(e2, {"t": "unit", "uid": int(e2.s.players[1].units[0].uid), "ability": 0})
	pick(e2, "Blocco")
	eq(int(e2.s.turn.pool.block.get("phys", 0)), 2 - 1, "Unità avversaria: blocco -1")
	MKSpecialsExp.on_turn_start(e2, 0)
	ok(MKSpecialsExp.inter_get(e2, "wolfs_howl") == null, "l'Ululato torna alla proprietaria")

func t_mana_suppression():
	var e := mk("full_conquest", 4, ["krang", "tovak"])
	lab(e)
	MKSites.add_skill(e, 0, "krang_mana_suppression")
	e.s.turn = e._fresh_turn(0)
	ok(act(e, {"t": "skill", "id": "krang_mana_suppression"}), "Soppressione del Mana")
	e.s.turn = e._fresh_turn(1)
	var pl: Dictionary = e.s.players[1]
	pl.crystals = {"red": 0, "blue": 0, "green": 2, "white": 0}
	pl.tokens = []
	e.s.source = []
	var iids := hand(e, 1, ["march"])
	ok(act(e, {"t": "play", "card": iids[0], "mode": "powered"}), "Tovak paga verde")
	eq(int(pl.crystals.green), 0, "paga un cristallo verde in più")
	pl.crystals.green = 1
	var i2 := hand(e, 1, ["march"])
	act(e, {"t": "play", "card": i2[0], "mode": "powered"})
	eq(int(pl.crystals.green), 0, "solo la prima volta")
	e.s.turn = e._fresh_turn(0)
	MKSpecialsExp.on_turn_start(e, 0)
	eq(int(e.s.players[0].crystals.green), 1, "Krang prende il cristallo verde dall'abilità")

func t_mana_enhancement():
	var e := skill_state("krang_mana_enhancement", ["krang"], "coop_conquest")
	var pl: Dictionary = e.s.players[0]
	pl.crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	pl.tokens = ["red"]
	act(e, {"t": "skill", "id": "krang_mana_enhancement"})
	var iids := hand(e, 0, ["rage", "march"])
	act(e, {"t": "play", "card": iids[1], "mode": "side", "side": "move"})
	fight(e, ["prowlers"])
	to_attack_phase(e)
	act(e, {"t": "play", "card": iids[0], "mode": "powered"})
	eq(int(pl.crystals.red), 1, "Potenziamento: cristallo rosso")
	var x = MKSpecialsExp.inter_get(e, "mana_enhancement")
	ok(x != null and str(x.color) == "red", "gettone rosso sull'abilità")

func t_natures_vengeance():
	var e := skill_state("braevalar_natures_vengeance", ["braevalar"])
	var ids := fight(e, ["prowlers"])
	act(e, {"t": "next"})
	ok(act(e, {"t": "skill", "id": "braevalar_natures_vengeance"}), "Vendetta della Natura")
	answer_all(e)
	eq(MKCombat.attack_value(e, entry(e, ids[0]), 0), 3, "attacco -1")
	ok(MKCombat.has_ab(entry(e, ids[0]), "cumbersome"), "diventa Ingombrante")

func t_forked_lightning():
	var e := skill_state("braevalar_forked_lightning", ["braevalar"])
	var ids := fight(e, ["prowlers", "diggers", "wolf_riders"])
	ok(act(e, {"t": "skill", "id": "braevalar_forked_lightning"}), "Fulmine Biforcuto")
	answer_all(e, 0, 1)
	var n := 0
	for en in e.s.combat.enemies:
		n += en.get("tbonus", []).size()
	eq(n, 2, "due bersagli (i Diggers fortificati non si possono colpire a distanza)")
	eq(MKCombat.effective_attack(e, [ids[0]]), 1, "Attacco 1 contro il bersaglio")
	e.s.turn.pool.attack = {"ranged:phys": 2}
	ok(act(e, {"t": "attack", "targets": [ids[0]]}), "2 + 1 sconfigge i Predatori (armatura 3)")

func t_shapeshift():
	var e := skill_state("braevalar_shapeshift", ["braevalar"])
	var iids := hand(e, 0, ["march", "rage"])
	fight(e, ["prowlers"])
	to_attack_phase(e)
	ok(act(e, {"t": "skill", "id": "braevalar_shapeshift"}), "Mutare Forma")
	pick(e, "Movimento diventa Attacco")
	ok(act(e, {"t": "play", "card": iids[0], "mode": "basic"}), "Marcia giocabile come attacco")
	eq(int(e.s.turn.pool.attack.get("melee:phys", 0)), 2, "Marcia: Attacco 2")

func t_druidic_paths():
	var e := mk("solo_conquest", 2, ["braevalar"])
	lab(e)
	e.s.day = false
	e.s.map.hex["1,0"].t = "forest"
	var iids := hand(e, 0, ["druidic_paths", "march"])
	act(e, {"t": "play", "card": iids[0], "mode": "basic"})
	eq(e.move_cost("1,0", "0,0"), 4, "foresta di notte 5 -> 4")
	eq(e.move_cost("0,1", "0,0"), 2, "la pianura resta 2 (minimo 2)")
	e.s.turn.pool.move = 4
	act(e, {"t": "move", "to": "1,0"})
	eq(int(e.s.turn.pool.move), 0, "pagato 4")
	e.s.map.hex["2,0"].t = "forest"
	eq(e.move_cost("2,0", "1,0"), 5, "una sola riduzione")

func t_savage_harvesting():
	var e := mk("solo_conquest", 2, ["krang"])
	lab(e)
	e.s.players[0].crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	var iids := hand(e, 0, ["savage_harvesting", "rage", "march"])
	act(e, {"t": "play", "card": iids[0], "mode": "basic"})
	act(e, {"t": "move", "to": "1,0"})
	ok(e.s.pending != null and e.s.pending.handler == "sp:harvest", "Raccolta Selvaggia dopo il movimento")
	pick(e, "Furia")
	eq(int(e.s.players[0].crystals.red), 1, "cristallo rosso")
	e.s.turn.pool.move = 4
	act(e, {"t": "move", "to": "2,0"})
	ok(e.s.pending == null, "base: una volta sola")

func t_draw_fire():
	var e := mk()
	lab(e)
	e.s.players[0].command = 3
	MKSites.gain_unit(e, 0, "shocktroops")
	MKSites.gain_unit(e, 0, "utem_guardsmen")
	var st: int = int(e.s.players[0].units[0].uid)
	var ids := fight(e, ["orc_tracker"])
	act(e, {"t": "next"})
	act(e, {"t": "unit", "uid": st, "ability": 2})
	answer_all(e)
	eq(MKCombat.attack_value(e, entry(e, ids[0]), 0), 1, "attirare il fuoco: attacco -3")
	act(e, {"t": "next"})
	ok(e.check({"t": "damage", "eid": ids[0], "attack": 0, "to": "hero"}) != "", "il danno va prima alle Truppe d'Assalto")
	eq(e.check({"t": "damage", "eid": ids[0], "attack": 0, "to": st}), "", "anche contro Assassinio")

func t_inter_others():
	# Nature's Vengeance (competitive): the other players' enemies attack +1 in the Block phase
	var e := mk("full_conquest", 4, ["braevalar", "tovak"])
	lab(e)
	MKSites.add_skill(e, 0, "braevalar_natures_vengeance")
	e.s.turn = e._fresh_turn(0)
	var ids := fight(e, ["prowlers"])
	act(e, {"t": "next"})
	act(e, {"t": "skill", "id": "braevalar_natures_vengeance"})
	answer_all(e)
	e.s.combat = null
	e.s.turn = e._fresh_turn(1)
	var ids2 := fight(e, ["prowlers"])
	act(e, {"t": "next"})
	eq(MKCombat.attack_value(e, entry(e, ids2[0]), 0), 5, "Vendetta della Natura: attacco +1 per gli avversari")
	# Howl of the Pack (coop): the next player who fights weakens an enemy
	var e2 := mk("coop_conquest", 4, ["wolfhawk", "tovak"])
	lab(e2)
	MKSites.add_skill(e2, 0, "wolfhawk_howl_of_the_pack")
	e2.s.turn = e2._fresh_turn(0)
	hand(e2, 0, ["march"])
	act(e2, {"t": "skill", "id": "wolfhawk_howl_of_the_pack"})
	e2.s.turn = e2._fresh_turn(1)
	var ids3 := fight(e2, ["prowlers"])
	eq(MKCombat.armor_of(e2, entry(e2, ids3[0])), 2, "Ululato del Branco: Armatura -1")
	eq(MKCombat.attack_value(e2, entry(e2, ids3[0]), 0), 3, "Ululato del Branco: attacco -1")
	# Mana Enhancement (coop): another player takes the mana token
	var e3 := mk("coop_conquest", 4, ["krang", "tovak"])
	lab(e3)
	MKSpecialsExp.inter_add(e3, {"id": "mana_enhancement", "owner": 0, "mode": "coop", "color": "green", "taken": false})
	e3.s.turn = e3._fresh_turn(1)
	e3.s.players[1].tokens = []
	var a := has_action(e3, func(x): return x.get("name", "") == "enh_token")
	ok(not a.is_empty(), "un altro giocatore può prendere il gettone")
	act(e3, a)
	eq(e3.s.players[1].tokens, ["green"], "gettone verde preso")
	ok(has_action(e3, func(x): return x.get("name", "") == "enh_token").is_empty(), "una volta sola")
	# Nature's Vengeance (coop): another player can use the same effect
	var e4 := mk("coop_conquest", 4, ["braevalar", "tovak"])
	lab(e4)
	MKSpecialsExp.inter_add(e4, {"id": "natures_vengeance", "owner": 0, "mode": "coop", "used_by": {}})
	e4.s.turn = e4._fresh_turn(1)
	var ids4 := fight(e4, ["prowlers"])
	var a4 := has_action(e4, func(x): return x.get("name", "") == "nv_coop")
	ok(not a4.is_empty(), "Vendetta della Natura per l'alleato")
	act(e4, a4)
	eq(MKCombat.attack_value(e4, entry(e4, ids4[0]), 0), 3, "attacco -1")

func t_krang_flips():
	# Battle Frenzy: Attack 4 flips the token until a turn of rest
	var e := skill_state("krang_battle_frenzy", ["krang"])
	fight(e, ["prowlers"])
	to_attack_phase(e)
	act(e, {"t": "skill", "id": "krang_battle_frenzy"})
	pick(e, "Attacco 4")
	eq(int(e.s.turn.pool.attack.get("melee:phys", 0)), 4, "Frenesia: Attacco 4")
	var sk = e.find_skill(0, "krang_battle_frenzy")
	ok(sk.get("flipped", false), "segnalino girato")
	e.s.combat = null
	e.s.turn = e._fresh_turn(0)
	sk.used_turn = false
	fight(e, ["prowlers"])
	to_attack_phase(e)
	ok(e.check({"t": "skill", "id": "krang_battle_frenzy"}) != "", "girato: inutilizzabile")
	e.s.combat = null
	e.s.turn = e._fresh_turn(0)
	hand(e, 0, ["march", "rage"])
	act(e, {"t": "rest"})
	answer_all(e)
	ok(not sk.get("flipped", false), "riposando si rigira")
	# Arcane Disguise: ignore reputation flips; green mana unflips
	var e2 := skill_state("krang_arcane_disguise", ["krang"])
	act(e2, {"t": "skill", "id": "krang_arcane_disguise"})
	pick(e2, "Reputazione")
	var sk2 = e2.find_skill(0, "krang_arcane_disguise")
	ok(sk2.get("flipped", false), "Travestimento girato")
	e2.s.turn = e2._fresh_turn(0)
	sk2.used_turn = false
	ok(e2.check({"t": "skill", "id": "krang_arcane_disguise"}) != "", "girato: inutilizzabile")
	e2.s.players[0].crystals.green = 1
	e2.s.source = []
	e2.s.players[0].tokens = []
	var a := has_action(e2, func(x): return x.get("name", "") == "skill_unflip")
	ok(not a.is_empty(), "rigira pagando verde")
	act(e2, a)
	eq(int(e2.s.players[0].crystals.green), 0, "mana verde pagato")
	eq(e2.check({"t": "skill", "id": "krang_arcane_disguise"}), "", "di nuovo utilizzabile")
	# Shamanic Ritual: unflip as the action of the turn
	var e3 := skill_state("krang_shamanic_ritual", ["krang"])
	act(e3, {"t": "skill", "id": "krang_shamanic_ritual"})
	answer_all(e3)
	ok(e3.check({"t": "skill", "id": "krang_shamanic_ritual"}) != "", "una volta per round")
	var a3 := has_action(e3, func(x): return x.get("name", "") == "skill_unflip")
	ok(not a3.is_empty(), "rigira come azione")
	act(e3, a3)
	ok(e3.s.turn.acted, "azione del turno spesa")
	eq(e3.check({"t": "skill", "id": "krang_shamanic_ritual"}), "", "Rituale di nuovo utilizzabile")

func t_hero_decks():
	for h in ["wolfhawk", "krang", "braevalar"]:
		var e := mk("solo_conquest", 1, [h])
		var ids: Array = []
		for iid in e.s.players[0].deck + e.s.players[0].hand:
			ids.append(e.card_id(iid))
		eq(ids.size(), 16, "%s: 16 carte" % h)
		for c in MKDB.cards:
			if MKDB.cards[c].hero == h:
				ok(c in ids, "%s ha la sua carta %s" % [h, c])

# ------------------------------------------------------------------ every expansion card / unit / skill
func _snapshot(e: MKEngine, p: int, hand_adj := 0) -> String:
	var pl: Dictionary = e.s.players[p]
	var d := {"pool": e.s.turn.pool, "hand": pl.hand.size() + hand_adj, "deck": pl.deck.size(), "disc": pl.discard.size(), "cr": pl.crystals,
		"tok": pl.tokens, "mods": e.s.turn.mods.size(), "fame": pl.fame, "rep": pl.rep, "units": pl.units, "pend": e.s.pending,
		"combat": e.s.combat, "dice": e.s.turn.dice_allowed, "pos": pl.pos, "source": e.s.source, "turn_keys": e.s.turn.keys().size(),
		"removed": pl.removed.size(), "skills": pl.skills, "banners": pl.get("banners", {}), "offers": e.s.offers, "inter": e.s.get("inter", []),
		"kept": pl.get("kept_enemies", [])}
	return JSON.stringify(d)

const WHERES := ["move", "site", "ranged", "block", "attack", "n_move", "n_site", "n_ranged", "n_block", "n_attack"]

func _card_state(id: String, where0: String, heroes := ["arythea"], scn := "solo_conquest") -> MKEngine:
	var e := mk(scn, 2, heroes)
	lab(e)
	e.s.turn = e._fresh_turn(0)
	e.s.active = 0
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
	e.s.turn.defeated_types = ["prowlers"]
	for sid in MKDB.skills:
		if MKDB.skills[sid].hero == "norowas" and MKDB.skills[sid].usage == "turn":
			e.s.offers.skills = [sid]
			break
	if where in ["ranged", "block", "attack"]:
		fight(e, ["prowlers", "zombie_horde"])
		if where == "block":
			act(e, {"t": "next"})
		elif where == "attack":
			act(e, {"t": "next"})
			for en in e.s.combat.enemies:
				for i in en.attacks.size():
					en.attacks[i].blocked = true
			act(e, {"t": "next"})
	elif where == "site":
		e.s.map.hex["0,0"].site = "village"
		e.s.offers.units = ["peasants", "herbalists"]
	return e

func _resolve_all(e: MKEngine) -> bool:
	var guard := 0
	while e.s.pending != null and guard < 30:
		guard += 1
		e.apply({"t": "choose", "v": [e.s.pending.options[0].v]})
	return e.s.pending == null

func _consistent(e: MKEngine, what: String) -> void:
	for x in e.available():
		if e.check(x.a) != "":
			card_report.append("%s: available() propone un'azione illegale %s" % [what, JSON.stringify(x.a)])
			break

func _changed(e: MKEngine, before: String) -> bool:
	var pool: Dictionary = e.s.turn.pool
	if int(pool.move) > 0 or int(pool.influence) > 0 or int(pool.heal) > 0 or not pool.attack.is_empty() or not pool.block.is_empty():
		return true
	return _snapshot(e, 0) != before

func t_cards_all():
	var ids: Array = MKDB.cards.keys()
	ids.sort()
	var n := 0
	for id in ids:
		var c: Dictionary = MKDB.cards[id]
		if not str(c.get("set", "base")) in EXP_SETS or c.type == "wound":
			continue
		n += 1
		var heroes := [str(c.hero)] if str(c.hero) != "" else ["arythea"]
		var played := false
		for mode in ["basic", "powered"]:
			if c.get(mode, []).is_empty():
				continue
			var worked := false
			for where in WHERES:
				var e := _card_state(id, where, heroes)
				var iid: String = e.s.players[0].hand[0]
				var a := {"t": "play", "card": iid, "mode": mode}
				if e.check(a) != "":
					continue
				var before := _snapshot(e, 0, -1)
				var lc: int = e.s.log_seq
				if not e.apply(a).ok:
					continue
				if not _resolve_all(e):
					card_report.append("%s %s: decisione infinita" % [id, mode])
				for le in e.s.log:
					if int(le.seq) >= lc and le.k == "error":
						card_report.append("%s %s: errore nel diario: %s" % [id, mode, le.txt])
				_consistent(e, "%s %s" % [id, mode])
				if _changed(e, before):
					worked = true
					played = true
					break
			if not worked:
				card_report.append("%s (%s): nessun effetto osservabile" % [id, mode])
		ok(played, "carta d'espansione giocata: " + id)
	print("    carte d'espansione provate: ", n)

func t_units_all():
	var ids: Array = MKDB.units.keys()
	ids.sort()
	for id in ids:
		var ud: Dictionary = MKDB.units[id]
		if not str(ud.get("set", "base")) in EXP_SETS:
			continue
		var abs: Array = ud.get("abilities", [])
		for ai in abs.size():
			if abs[ai].get("effect", []).is_empty():
				continue
			var worked := false
			for where in WHERES:
				var e := _card_state("march", where)
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
				_resolve_all(e)
				_consistent(e, "unità %s/%d" % [id, ai])
				if _changed(e, before):
					worked = true
					break
			ok(worked, "abilità di unità usata: %s/%d (%s)" % [id, ai, abs[ai].get("text_it", "")])

func t_skills_all():
	var ids: Array = MKDB.skills.keys()
	ids.sort()
	for id in ids:
		var sd: Dictionary = MKDB.skills[id]
		if not str(sd.get("set", "base")) in EXP_SETS:
			continue
		if sd.get("usage", "") == "passive" or sd.get("effect", []).is_empty():
			continue
		var comp: bool = str(sd.get("mode", "")) == "competitive"
		var worked := false
		for where in WHERES:
			var e := _card_state("march", where, [str(sd.hero), "tovak"] if comp else [str(sd.hero)], "full_conquest" if comp else "solo_conquest")
			MKSites.add_skill(e, 0, id)
			var a := {"t": "skill", "id": id}
			if e.check(a) != "":
				continue
			var before := _snapshot(e, 0)
			e.apply(a)
			_resolve_all(e)
			_consistent(e, "abilità " + id)
			if _changed(e, before):
				worked = true
				break
		ok(worked, "abilità usata: " + id)
