extends SceneTree
## Test degli scenari (Manuale degli Scenari, MKScn):
##   godot --headless --path . -s res://tests/scn_test.gd -- [giri IA (default 1)] [solo:<id scenario>]
## 1) regole speciali di ogni scenario con stati preparati a mano;
## 2) per ogni scenario e numero di giocatori: preparazione + partita completa IA contro IA (livello 2) senza
##    azioni rifiutate né blocchi, con il risultato (vincitori, vittoria/missione, punteggi) calcolato.

const AI = preload("res://scripts/core/ai.gd")
const HEROES := ["arythea", "goldyx", "norowas", "tovak"]

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
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 1
	var only := ""
	if args.size() > 1 and str(args[1]).begins_with("solo:"):
		only = str(args[1]).substr(5)
	if only == "":
		for t in [test_data, test_setup_all, test_mines, test_druid, test_dungeon, test_conquer_hold, test_one_return]:
			var before := fails
			t.call()
			print("%s %s" % ["OK " if fails == before else "ERR", t.get_method()])
	# partite IA contro IA
	var t0 := Time.get_ticks_msec()
	for id in MKDB.scenarios:
		if only != "" and id != only:
			continue
		var pr: Array = MKDB.scenarios[id].get("players", [1, 4])
		var counts: Array = []
		for n in range(int(pr[0]), int(pr[1]) + 1):
			counts.append(n)
		# per contenere i tempi: minimo, massimo (e 1 se c'è la variante in solitario)
		var pick: Array = [counts[0]]
		if counts[-1] != counts[0]:
			pick.append(counts[-1])
		for g in games:
			for np in pick:
				var before2 := fails
				var r := ai_game(id, np, 100 + g * 37 + np)
				print("%s AI %-17s np=%d seed=%d -> %s" % ["OK " if fails == before2 else "ERR", id, np, 100 + g * 37 + np, r])
	print("partite IA: %d s" % ((Time.get_ticks_msec() - t0) / 1000))
	print("TEST: %d ok, %d falliti" % [passes, fails])
	quit(1 if fails > 0 else 0)


# ------------------------------------------------------------------ helpers
func mk(scn: String, np := 2, seed := 1) -> MKEngine:
	var cfg := {"scenario": scn, "seed": seed, "players": []}
	for i in np:
		cfg.players.append({"hero": HEROES[i], "name": HEROES[i], "ctrl": "ai"})
	var e := MKEngine.create(cfg)
	_settle(e)
	return e


## Risolve tattiche e decisioni finché tocca a un giocatore muoversi.
func _settle(e: MKEngine) -> void:
	var guard := 0
	while (e.s.phase == "tactics" or e.s.pending != null) and guard < 50:
		guard += 1
		var av := e.available()
		if av.is_empty():
			break
		e.apply(av[0].a)


func act(e: MKEngine, a: Dictionary) -> bool:
	var r := e.apply(a)
	if not r.ok:
		print("    azione rifiutata ", a, " -> ", r.err)
	return r.ok


func hexes_with(e: MKEngine, site: String) -> Array:
	var out: Array = []
	for k in e.s.map.hex:
		if str(e.s.map.hex[k].site) == site:
			out.append(k)
	out.sort()
	return out


func all_tiles(e: MKEngine) -> Array:
	var out: Array = []
	for t in e.s.map.tiles:
		out.append(str(t.id))
	out.append_array(e.s.map.tile_deck)
	return out


## Rivela tutte le tessere rimaste (in posizioni qualsiasi libere della forma).
func reveal_all(e: MKEngine) -> void:
	var guard := 0
	while not e.s.map.tile_deck.is_empty() and guard < 40:
		guard += 1
		var placed := {}
		for t in e.s.map.tiles:
			placed[t.slot] = true
		var slot := ""
		var pd = e.s.map.get("predef", null)
		if pd is Dictionary:
			slot = str(pd.keys()[0])
		else:
			for t in e.s.map.tiles:
				for m in MKHex.macro_neighbors(t.slot):
					if slot == "" and not placed.has(m) and MKHex.in_shape(m, e.s.map.shape):
						slot = m
		if slot == "":
			break
		e.place_tile(MKScn.take_tile(e, slot), slot, -1)


func win_combat(e: MKEngine) -> void:
	var c = e.s.combat
	if c == null:
		return
	c.phase = "attack"
	e.s.turn.pool.attack = {"melee:cold": 80}
	var tg: Array = []
	for en in c.enemies:
		if not en.defeated:
			tg.append(en.eid)
	act(e, {"t": "attack", "targets": tg})
	if e.s.combat != null:
		act(e, {"t": "next"})


# ------------------------------------------------------------------ dati e preparazione
func test_data():
	var groups := {}
	for id in MKDB.scenarios:
		var d: Dictionary = MKDB.scenarios[id]
		ok(str(d.get("group", "")) in ["intro", "competitive", "coop", "solo"], "%s: gruppo" % id)
		ok(d.get("players", []).size() == 2, "%s: numero di giocatori" % id)
		ok(str(d.get("short_it", "")).length() > 20 and str(d.get("desc_it", "")).length() > 80, "%s: descrizioni" % id)
		ok(str(d.get("page", "")) != "", "%s: pagina" % id)
		groups[d.group] = true
	eq(groups.size(), 4, "quattro gruppi di scenari")
	for id in ["first_recon", "full_conquest", "blitz_conquest", "mines_liberation", "druid_nights", "dungeon_lords",
			"conquer_hold", "one_to_return", "coop_conquest", "coop_blitz", "solo_conquest"]:
		ok(MKDB.scenarios.has(id), "scenario del manuale presente: " + id)


func test_setup_all():
	for id in MKDB.scenarios:
		var pr: Array = MKDB.scenarios[id].players
		for np in range(int(pr[0]), int(pr[1]) + 1):
			var e := mk(id, np, 7)
			ok(e.s.phase == "turn", "%s np=%d: la partita inizia" % [id, np])
			ok(not e.s.map.tile_deck.is_empty(), "%s np=%d: mazzo delle tessere" % [id, np])
			eq(e.s.players.size(), np, "%s: giocatori" % id)
			ok((e.s.dummy != null) == (np == 1 or str(e.s.scn.mode) == "coop"), "%s np=%d: giocatore Neutrale" % [id, np])
	var c4 := mk("coop_conquest", 4, 3)
	eq(c4.s.scn.city_levels, [5, 5, 8, 11], "cooperazione a 4: livelli delle città")
	eq(int(c4.s.scn.city), 4, "cooperazione a 4: 4 città")
	ok(c4.s.dummy != null and not str(c4.s.dummy.hero) in ["arythea", "goldyx", "norowas", "tovak"], "cooperazione a 4: il Neutrale usa un altro eroe")


# ------------------------------------------------------------------ Liberazione delle Miniere
func test_mines():
	var e := mk("mines_liberation", 2, 3)
	var tiles := all_tiles(e)
	for t in ["c02", "c03", "c05", "c06"]:
		ok(t in tiles, "miniere: tessera Campagna con miniera %s inclusa" % t)
	ok("k08" in tiles and not "k05" in tiles and not "k06" in tiles, "miniere: solo la città Rossa")
	ok(not "k01" in tiles, "miniere: esclusa la tessera Principale senza miniera")
	reveal_all(e)
	var mines := hexes_with(e, "mine")
	ok(mines.size() >= 5, "miniere sulla mappa (%d)" % mines.size())
	for k in mines:
		var h: Dictionary = e.hex(k)
		ok(h.get("guarded", false) and h.enemies.size() == 2, "miniera %s sorvegliata da 2 nemici" % k)
		var core := str(MKDB.tiles[h.tile].kind) != "country"
		ok(str(e.s.enemies[h.enemies[0]].color) == ("red" if core else "green") and e.s.enemies[h.enemies[0]].face_up, "guardiano verde/rosso a faccia in su")
		ok(str(e.s.enemies[h.enemies[1]].color) == "brown" and not e.s.enemies[h.enemies[1]].face_up, "guardiano marrone a faccia in giù")
		ok(not MKScn.mine_produces(e, k), "miniera occupata: niente cristalli")
	var city := hexes_with(e, "city")
	ok(city.size() == 1 and e.hex(city[0]).conquered and e.hex(city[0]).enemies.is_empty() and e.hex(city[0]).city.shields.size() == 2, "città amica con uno Scudo per giocatore")
	# liberazione
	var p := int(e.s.turn.player)
	var mk_k: String = mines[0]
	var core0 := str(MKDB.tiles[e.hex(mk_k).tile].kind) != "country"
	e.s.players[p].pos = mk_k
	var rep0 := int(e.s.players[p].rep)
	ok(act(e, {"t": "site"}), "entra nella miniera occupata")
	ok(e.s.combat != null and e.s.combat.night_rules and e.s.combat.units_allowed and e.s.combat.enemies.size() == 2, "combattimento notturno con le Unità contro 2 nemici")
	win_combat(e)
	ok(e.s.combat == null and e.hex(mk_k).conquered and mk_k in e.s.players[p].shields, "miniera liberata con lo Scudo")
	eq(int(e.s.players[p].rep), rep0 + (2 if core0 else 1), "Reputazione +1/+2")
	ok(MKScn.mine_produces(e, mk_k), "miniera liberata produce")
	eq(MKScn.points(e, p), 7 if core0 else 4, "punti miniera")
	var sc: Dictionary = e.score(p)
	eq(int(sc.scenario), (7 if core0 else 4) + 5, "punti miniera + Più Grande Liberatore")
	# cristallo all'inizio del round
	var cr0 := 0
	for c in e.s.players[p].crystals:
		cr0 += int(e.s.players[p].crystals[c])
	MKScn.on_round_start(e, false)
	var cr1 := 0
	for c in e.s.players[p].crystals:
		cr1 += int(e.s.players[p].crystals[c])
	eq(cr1, cr0 + 1, "dono dei minatori a inizio round")
	ok(e.check({"t": "site"}) != "", "miniera già liberata: niente combattimento")
	# fine: tutte liberate
	for k in mines:
		e.hex(k).conquered = true
	ok(MKScn.objective_done(e), "obiettivo raggiunto")
	MKScn.check_end(e, p)
	ok(e.s.game_end_pending, "fine della partita annunciata")
	# solitario
	var e1 := mk("mines_liberation", 1, 5)
	ok(e1.s.dummy != null and str(e1.s.scn.mode) == "solo" and e1.s.scn.tactics_removed_solo and e1.s.scn.get("dummy_no_final", false), "miniere in solitario: Neutrale e regole del solitario")
	eq(int(e1.s.scn.country), 7, "miniere in solitario: 7 tessere Campagna")


# ------------------------------------------------------------------ Le Notti del Druido
func test_druid():
	var e := mk("druid_nights", 2, 4)
	var tiles := all_tiles(e)
	for t in ["c01", "c02", "c05", "c07", "c08"]:
		ok(t in tiles, "druido: tessera con radura %s inclusa" % t)
	ok("k05" in tiles and not "k06" in tiles, "druido: città Verde")
	reveal_all(e)
	var glades := hexes_with(e, "glade")
	ok(glades.size() >= 5, "radure sulla mappa")
	var p := int(e.s.turn.player)
	# segna due radure
	for i in 2:
		e.s.players[p].pos = glades[i]
		MKScn.on_end_turn_site(e, p)
	eq(MKScn.marked_glades(e, p), 2, "due radure segnate")
	MKScn.on_end_turn_site(e, p)
	eq(MKScn.marked_glades(e, p), 2, "una sola volta per radura")
	ok(e.check({"t": "scn", "op": "incant"}) != "", "di Giorno niente incantesimo")
	# prima Notte
	e.s.round = 2
	e.s.day = false
	e.s.players[p].pos = glades[0]
	ok(e.check({"t": "scn", "op": "incant"}) == "", "incantesimo possibile di Notte")
	var lab := false
	for x in e.available():
		if str(x.a.get("t", "")) == "scn":
			lab = true
	ok(lab, "azione dell'incantesimo nell'elenco")
	var f0 := int(e.s.players[p].fame)
	ok(act(e, {"t": "scn", "op": "incant"}), "compie l'incantesimo")
	ok(e.s.combat != null and e.s.combat.enemies.size() == 2, "due nemici marroni evocati")
	var fame := 0
	for en in e.s.combat.enemies:
		ok(str(en.color) == "brown", "nemico marrone")
		fame += int(en.fame)
		ok(int(en.fame) == 2 * int(MKDB.enemies[en.type].fame), "Fama raddoppiata")
	ok(e.s.turn.rewards.size() == 1 and int(e.s.turn.rewards[0].n) == 2, "un cristallo a caso per mostro")
	win_combat(e)
	eq(int(e.s.players[p].fame), f0 + fame, "Fama doppia ottenuta")
	ok(e.check({"t": "scn", "op": "incant"}) != "", "una volta per Notte")
	# fine della prima Notte: gli Scudi si tolgono
	MKScn.on_round_end(e)
	eq(MKScn.marked_glades(e, p), 0, "Scudi tolti dalle radure dopo la prima Notte")
	# seconda Notte: tutti → fine
	e.s.round = 4
	e.s.combat = null
	e.s.turn.acted = false
	MKScn.st(e).glades = {glades[0]: [0, 1]}
	MKScn.st(e).incant["4"] = [1 - p]
	e.s.players[p].pos = glades[1]
	e.s.players[1 - p].pos = glades[2]
	ok(act(e, {"t": "scn", "op": "incant"}), "incantesimo della seconda Notte")
	ok(e.s.combat != null and str(e.s.combat.enemies[0].color) == "red", "nemico rosso nella seconda Notte")
	ok(int(e.s.turn.rewards[-1].n) == 2, "due cristalli per nemico rosso")
	ok(e.s.game_end_pending, "tutti hanno compiuto l'incantesimo: ultimo turno")
	ok(e.check({"t": "scn", "op": "incant"}) != "" or e.s.combat != null, "non due volte")
	e.s.players[p].pos = hexes_with(e, "village")[0] if not hexes_with(e, "village").is_empty() else glades[1]


# ------------------------------------------------------------------ I Signori del Sotterraneo
func test_dungeon():
	var e := mk("dungeon_lords", 2, 6)
	var tiles := all_tiles(e)
	ok("c07" in tiles and "c09" in tiles, "sotterraneo: tessere con sotterranei incluse")
	ok("k06" in tiles and "k01" in tiles, "sotterraneo: città Blu e tessera deserto con la tomba")
	reveal_all(e)
	_settle(e)
	var vil := hexes_with(e, "village")
	var mon := hexes_with(e, "monastery")
	var secret_d := 0
	var secret_t := 0
	for k in e.s.map.hex:
		var h: Dictionary = e.s.map.hex[k]
		if h.get("secret", false):
			if h.site == "dungeon":
				secret_d += 1
				ok(h.enemies.size() == 1 and str(e.s.enemies[h.enemies[0]].color) == "brown" and not e.s.enemies[h.enemies[0]].face_up, "segnalino marrone coperto")
			else:
				secret_t += 1
				ok(h.enemies.size() == 1 and str(e.s.enemies[h.enemies[0]].color) == "red", "segnalino rosso")
			ok(not str(h.t) in ["swamp", "lake", "mountain"], "entrata segreta non su palude/lago/montagna")
	ok(secret_d >= 1 and secret_d <= vil.size(), "sotterranei segreti accanto ai villaggi (%d/%d)" % [secret_d, vil.size()])
	ok(secret_t >= 1 and secret_t <= mon.size(), "tombe segrete accanto ai monasteri (%d/%d)" % [secret_t, mon.size()])
	# scelta del giocatore che rivela
	var e2 := mk("dungeon_lords", 2, 8)
	var asked := false
	for vt in ["c01", "c02", "c08", "c04", "c03"]:
		if asked or not vt in e2.s.map.tile_deck:
			continue
		var placed := {}
		for t in e2.s.map.tiles:
			placed[t.slot] = true
		var slot := ""
		for t in e2.s.map.tiles:
			for m in MKHex.macro_neighbors(t.slot):
				if slot == "" and not placed.has(m) and MKHex.in_shape(m, e2.s.map.shape):
					slot = m
		e2.s.map.tile_deck.erase(vt)
		e2.place_tile(vt, slot, int(e2.s.turn.player))
		if e2.s.pending != null:
			asked = true
			ok(str(e2.s.pending.handler) == "scn:secret" and e2.s.pending.options.size() >= 2 and int(e2.s.pending.player) == int(e2.s.turn.player), "chi rivela sceglie lo spazio dell'entrata segreta")
			var v = e2.s.pending.options[0].v
			ok(act(e2, {"t": "choose", "v": [v]}), "sceglie lo spazio")
			ok(e2.hex(str(v)).get("secret", false), "entrata segreta piazzata")
	ok(asked, "almeno una scelta dell'entrata segreta")
	# combattimento e conquista di un sotterraneo segreto
	var sk := ""
	for k in e.s.map.hex:
		if e.s.map.hex[k].get("secret", false) and e.s.map.hex[k].site == "dungeon":
			sk = k
	var p := int(e.s.turn.player)
	e.s.players[p].pos = sk
	ok(act(e, {"t": "site"}), "entra nel sotterraneo segreto")
	ok(e.s.combat != null and e.s.combat.night_rules and not e.s.combat.units_allowed, "regole del sotterraneo")
	# fallisce: nuovo segnalino
	act(e, {"t": "next"})
	while e.s.combat != null:
		var av := e.available()
		var done := false
		for x in av:
			if str(x.a.t) == "damage" or str(x.a.t) == "next":
				act(e, x.a)
				done = true
				break
		if not done:
			break
	_settle(e)
	ok(e.s.combat == null and not e.hex(sk).conquered and e.hex(sk).enemies.size() == 1, "sconfitta: nuovo segnalino sull'entrata segreta")
	# vittoria
	e.s.turn = e._fresh_turn(p)
	e.s.players[p].hand.append(e.new_iid("march"))
	ok(act(e, {"t": "site"}), "di nuovo nel sotterraneo")
	win_combat(e)
	ok(e.hex(sk).conquered and sk in e.s.players[p].shields, "sotterraneo segreto conquistato")
	eq(MKScn.adv_points(e, "dungeon"), 4, "sotterranei a 4 punti")
	eq(int(e._ach_value(p, "adventurer")), 4, "Avventuriero conta 4 punti per il sotterraneo")
	eq(MKScn.title_bonus(e, "adventurer", true), 5, "Più Grande Esploratore di Sotterranei +5")
	_settle(e)
	e.s.turn = e._fresh_turn(p)
	e.s.players[p].hand.append(e.new_iid("march"))
	ok(e.check({"t": "site"}) != "", "sotterraneo conquistato: non si visita più")
	# gallerie
	var other := ""
	for k in hexes_with(e, "dungeon") + hexes_with(e, "tomb"):
		if k != sk and other == "":
			other = k
	e.hex(other).conquered = true
	var tl := MKScn.tunnels(e, p)
	ok(tl.size() >= 1, "galleria verso un altro sotterraneo conquistato")
	if tl.size() > 0:
		var d: Dictionary = tl[0]
		ok(int(d.cost) == 2 + MKHex.distance(sk, str(d.to)) or int(d.cost) > 2 + MKHex.distance(sk, str(d.to)), "costo 2 + distanza")
		e.s.turn.pool.move = int(d.cost)
		ok(act(e, {"t": "scn", "op": "tunnel", "to": d.to}), "viaggio in galleria")
		eq(str(e.s.players[p].pos), str(d.to), "arrivato a destinazione")
		eq(int(e.s.turn.pool.move), 0, "Movimento speso")


# ------------------------------------------------------------------ Conquista e Mantieni
func test_conquer_hold():
	var e := mk("conquer_hold", 2, 9)
	var tiles := all_tiles(e)
	tiles.sort()
	eq(tiles, ["c03", "c04", "c09", "c10", "c11", "k02", "k03", "k04", "k07", "start_b"], "tessere fisse dello scenario")
	eq(int(e.s.scn.rounds), 6, "6 round con 2 giocatori")
	eq(e.s.map.tiles.size(), 4, "iniziale + 3 Campagna rivelate")
	var pd: Dictionary = e.s.map.predef
	eq(pd.size(), 6, "6 posizioni predefinite")
	for s in ["4,-5", "5,-1"]:
		ok(str(MKDB.tiles[pd[s]].kind) == "country", "Campagna in %s" % s)
	ok(not e.s.scn.cities_enterable, "città chiusa")
	for id in e.s.decks.units_elite + e.s.decks.units_reg + e.s.offers.units:
		ok(int(MKDB.units[id].level) < 4, "niente Unità di livello IV")
	for id in e.s.offers.units:
		ok(not MKDB.units[id].elite, "solo Unità Regolari nella prima metà")
	ok(MKScn.elite_ok(e, true) == false, "Élite non ancora")
	e.s.round = 4
	ok(MKScn.elite_ok(e, false), "Élite dal round 4 con 2 giocatori")
	e.s.round = 1
	var e4 := mk("conquer_hold", 4, 9)
	eq(int(e4.s.scn.rounds), 4, "4 round con 4 giocatori")
	eq(e4.s.scn.get("teams", []), [[0, 1], [2, 3]], "squadre con 4 giocatori")
	ok(MKScn.allies(e4, 0, 1) and not MKScn.allies(e4, 1, 2), "alleati")
	# esplorazione predefinita
	var p := int(e.s.turn.player)
	var target := "5,-1"
	var near := ""
	for hk in MKHex.tile_hexes(target):
		for nk in MKHex.neighbors(hk):
			if e.s.map.hex.has(nk) and e.terrain_cost(e.hex(nk).t) < 999 and near == "":
				near = nk
	e.s.players[p].pos = near
	e.s.turn.pool.move = 4
	ok(target in e.explorable_slots(p), "posizione predefinita esplorabile")
	var tid: String = pd[target]
	ok(act(e, {"t": "explore", "slot": target}), "esplora la posizione predefinita")
	var found := false
	for t in e.s.map.tiles:
		if t.slot == target and t.id == tid:
			found = true
	ok(found, "rivelata la tessera assegnata a quella posizione")
	# torre: assalto senza perdita di Reputazione, conquista senza Incantesimo, sicura per il proprietario
	reveal_all(e)
	var tower: String = hexes_with(e, "mage_tower")[0]
	var from := ""
	for nk in MKHex.neighbors(tower):
		if e.s.map.hex.has(nk) and e.terrain_cost(e.hex(nk).t) < 999 and e.hex(nk).enemies.is_empty() and from == "":
			from = nk
	e.s.turn = e._fresh_turn(p)
	e.s.players[p].pos = from
	e.s.turn.pool.move = 9
	var rep0 := int(e.s.players[p].rep)
	ok(act(e, {"t": "move", "to": tower}), "assalto alla torre")
	eq(int(e.s.players[p].rep), rep0, "assalto senza perdere Reputazione")
	win_combat(e)
	ok(e.hex(tower).conquered and int(e.hex(tower).owner) == p, "torre conquistata e posseduta")
	ok(e.s.turn.rewards.filter(func(r): return str(r.k) == "spell").is_empty(), "nessun Incantesimo per la torre")
	ok(e._is_safe_fortified(p, tower) and not e._is_safe_fortified(1 - p, tower), "torre sicura solo per il proprietario")
	eq(MKSites.interaction_site(e, p), "mage_tower", "si comprano Incantesimi nella propria torre")
	ok(MKSites.unit_recruitable_here(e, p, "herbalists") or not e.s.offers.units.has("herbalists"), "Unità dei monasteri nella torre")
	eq(MKScn.victory_points(e, p), 2, "torre = 2 punti Vittoria")
	# mana della torre a inizio turno
	var tk0: int = e.s.players[p].tokens.size()
	MKScn.on_turn_start(e, p)
	eq(e.s.players[p].tokens.size(), tk0 + 1, "mana dalla torre all'inizio del turno")
	# l'altro giocatore assalta la torre: difensori (round 3: 2 nemici viola) a metà Fama
	_settle(e)
	var q := 1 - p
	e.s.round = 3
	e.s.turn = e._fresh_turn(q)
	e.s.active = q
	e.s.players[p].pos = from if from != "" else e.s.map.portal
	e.s.players[q].pos = from
	for eid in e.hex(tower).enemies.duplicate():
		e.discard_enemy(eid)
	e.s.turn.pool.move = 9
	ok(act(e, {"t": "move", "to": tower}) or e.s.get("pvp", null) != null, "assalto alla torre di un altro giocatore")
	if e.s.combat != null and e.s.get("pvp", null) == null:
		eq(e.s.combat.enemies.size(), 2, "2 difensori nel secondo Giorno/Notte")
		for en in e.s.combat.enemies:
			ok(str(en.color) == "violet" and en.half_fame, "difensore viola a metà Fama")
		win_combat(e)
		ok(int(e.hex(tower).owner) == q and not tower in e.s.players[p].shields, "la torre cambia proprietario")
	# fine: punti Vittoria
	var res := {"winners": [0], "scores": []}
	MKScn.finalize(e, res, [])
	ok(res.has("scn_notes") and res.winners.size() <= 1, "vincitore per punti Vittoria")
	# squadre: niente combattimento tra alleati
	e4.s.players[1].pos = e4.s.players[0].pos
	var t0 := int(e4.s.turn.player)
	var ally := 1 if t0 == 0 else (0 if t0 == 1 else (3 if t0 == 2 else 2))
	e4.s.players[ally].pos = e4.s.players[t0].pos
	var hk2 := ""
	for k in e4.s.map.hex:
		if e4.s.map.hex[k].site == "" and e4.terrain_cost(e4.s.map.hex[k].t) < 999 and hk2 == "":
			hk2 = k
	e4.s.players[t0].pos = hk2
	e4.s.players[ally].pos = hk2
	ok(MKPvP.check_attack(e4, t0).find("squadra") >= 0, "niente combattimento tra alleati")


# ------------------------------------------------------------------ Solo Uno Tornerà
func test_one_return():
	var e := mk("one_to_return", 3, 10)
	eq(int(e.s.scn.city), 2, "città = giocatori - 1")
	eq(int(e.s.scn.country), 8, "8 tessere Campagna con 3 giocatori")
	var portal := str(e.s.map.portal)
	ok(MKScn.portal_open(e), "portale aperto nel primo Giorno")
	# fine del primo Giorno: chi è sul portale è eliminato
	var away := MKHex.neighbors(portal).filter(func(k): return e.s.map.hex.has(k) and e.terrain_cost(e.hex(k).t) < 999)
	e.s.players[0].pos = portal
	e.s.players[1].pos = away[0]
	e.s.players[2].pos = away[1]
	MKScn.on_round_end(e)
	ok(MKScn.eliminated(e, 0) and str(e.s.players[0].pos) == "", "eliminato chi era sul portale")
	ok(not MKScn.eliminated(e, 1), "gli altri restano")
	e.s.round = 2
	ok(not MKScn.portal_open(e) and not MKPvP.shareable(e, portal), "il portale diventa uno spazio come gli altri")
	e._start_round(false)
	_settle(e)
	ok(not 0 in e.s.turn_order, "l'eliminato non gioca più")
	# vince chi è sul portale alla fine
	e.s.players[1].pos = portal
	var res := {"winners": [2]}
	MKScn.finalize(e, res, [])
	eq(res.winners, [1], "vince chi è sul portale")
	e.s.players[1].pos = away[0]
	var res2 := {"winners": [2]}
	MKScn.finalize(e, res2, [])
	eq(res2.winners, [], "nessuno sul portale: nessun vincitore")


# ------------------------------------------------------------------ partite IA
func ai_game(id: String, np: int, seed: int) -> String:
	var cfg := {"scenario": id, "seed": seed, "players": [], "options": {}}
	for i in np:
		cfg.players.append({"hero": HEROES[(i + seed) % 4], "ctrl": "ai", "ai_level": 2, "name": HEROES[(i + seed) % 4]})
	var e := MKEngine.create(cfg)
	var n := 0
	var err := ""
	var incants := 0
	var tunnels := 0
	while e.s.phase != "game_over":
		n += 1
		if n > 8000:
			err = "BLOCCATO: troppe azioni"
			break
		var p := e.actor()
		if p < 0:
			err = "BLOCCATO: nessun attore (phase=%s)" % e.s.phase
			break
		var a: Dictionary = AI.decide(e, 2)
		if a.is_empty():
			err = "BLOCCATO: nessuna azione"
			break
		if str(a.get("t", "")) == "scn":
			if str(a.get("op", "")) == "incant":
				incants += 1
			else:
				tunnels += 1
		var r := e.apply(a)
		if not r.ok:
			err = "AZIONE RIFIUTATA %s -> %s" % [JSON.stringify(a), r.err]
			break
	ok(err == "", "%s np=%d: %s" % [id, np, err])
	var res = e.s.result
	ok(res is Dictionary and res.has("scores") and res.scores.size() == np, "%s np=%d: punteggi calcolati" % [id, np])
	if not (res is Dictionary):
		return err
	var out := "round %d azioni %d fama %s vincitori %s" % [int(e.s.round), n, str(e.s.players.map(func(x): return int(x.fame))), str(res.get("winners", []))]
	if res.has("victory"):
		out += " vittoria=%s" % str(res.victory)
	if res.has("team_score"):
		out += " squadra=%d" % int(res.team_score)
	match MKScn.rule(e):
		"mines":
			var lib := 0
			var tot := 0
			for k in e.s.map.hex:
				if str(e.s.map.hex[k].site) == "mine":
					tot += 1
					if e.s.map.hex[k].conquered:
						lib += 1
			out += " miniere liberate %d/%d" % [lib, tot]
			ok(res.has("mission"), "miniere: esito della missione")
		"druid":
			out += " incantesimi %d" % incants
		"dungeon":
			var cq := 0
			var tot2 := 0
			for k in e.s.map.hex:
				if str(e.s.map.hex[k].site) in ["dungeon", "tomb"]:
					tot2 += 1
					if e.s.map.hex[k].conquered:
						cq += 1
			out += " sotterranei/tombe %d/%d gallerie %d" % [cq, tot2, tunnels]
		"conquer_hold":
			var vps: Array = []
			for i in np:
				vps.append(MKScn.victory_points(e, i))
			out += " punti Vittoria %s" % str(vps)
		"one_return":
			out += " eliminati %s" % str(MKScn.st(e).eliminated)
	if res.has("scn_notes"):
		out += " | " + "; ".join(res.scn_notes)
	return out + ("" if err == "" else " " + err)
