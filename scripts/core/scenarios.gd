class_name MKScn
extends RefCounted
## Regole speciali degli scenari del Manuale degli Scenari (regolamento italiano pp. 18–22) che il motore
## base non conosce: Liberazione delle Miniere (rules "mines"), Le Notti del Druido ("druid"), I Signori del
## Sotterraneo ("dungeon"), Conquista e Mantieni ("conquer_hold"), Solo Uno Tornerà ("one_return").
## Il motore chiama questi hook (tutti statici, senza effetto negli altri scenari).
##
## Stato: s.scn_state = {
##   glades: {"q,r": [giocatori]}      Notti del Druido: Scudi sulle radure magiche
##   incant: {"2": [giocatori], "4": […]} chi ha compiuto l'incantesimo in quel round (Notte)
##   secret_q: [{kind:"dungeon"|"tomb", near:"q,r", p}]  entrate segrete da piazzare (Signori del Sotterraneo)
##   eliminated: [giocatori]          Solo Uno Tornerà: eliminati alla chiusura del portale
## }
## Esagoni: h.guarded (miniera sorvegliata), h.secret (sotterraneo/tomba segreti), h.conquered/owner come al solito.
## Azioni: {t:"scn", op:"incant"} (incantesimo del druido), {t:"scn", op:"tunnel", to:"q,r"} (galleria).
## Decisioni: "scn:secret" (v = esagono dell'entrata segreta).

const INHABITED := ["village", "monastery", "keep", "mage_tower", "city", "camp"]
const DIR_IT := ["a ovest", "a sud-ovest", "a sud-est", "a est", "a nord-est", "a nord-ovest"]


static func rule(eng) -> String:
	return str(eng.s.scn.get("rules", ""))


static func st(eng) -> Dictionary:
	if not eng.s.has("scn_state") or not (eng.s.scn_state is Dictionary):
		eng.s["scn_state"] = {"glades": {}, "incant": {}, "secret_q": [], "eliminated": []}
	return eng.s.scn_state


# ================================================================ squadre
static func team_of(eng, p: int) -> int:
	var teams = eng.s.scn.get("teams", [])
	if teams is Array:
		for i in teams.size():
			for x in teams[i]:
				if int(x) == p:
					return i
	return -1


static func allies(eng, a: int, b: int) -> bool:
	if a == b:
		return true
	var ta := team_of(eng, a)
	return ta >= 0 and ta == team_of(eng, b)


# ================================================================ setup
## Sceglie le tessere secondo lo scenario (le liste sono già mescolate e vengono modificate sul posto).
static func pick_tiles(eng, sc: Dictionary, country: Array, core: Array, cities: Array) -> void:
	var tr: Dictionary = sc.get("tile_rules", {})
	if tr.is_empty():
		return
	if str(tr.get("country_only", "")) != "":
		country.assign(country.filter(func(id): return _tile_has(id, str(tr.country_only))))
	if str(tr.get("country_first", "")) != "":
		var a: Array = country.filter(func(id): return _tile_has(id, str(tr.country_first)))
		var b: Array = country.filter(func(id): return not _tile_has(id, str(tr.country_first)))
		country.assign(a + b)
	if str(tr.get("core_only", "")) != "":
		core.assign(core.filter(func(id): return _tile_has(id, str(tr.core_only))))
	var inc: Array = tr.get("core_include", [])
	if not inc.is_empty():
		var a2: Array = core.filter(func(id): return id in inc)
		var b2: Array = core.filter(func(id): return not id in inc)
		core.assign(a2 + b2)
	if str(tr.get("city_color", "")) != "":
		var col := str(tr.city_color)
		var a3: Array = cities.filter(func(id): return str(MKDB.tiles[id].get("city", "")) == col)
		if not a3.is_empty():
			cities.assign(a3)


static func _tile_has(id: String, sites: String) -> bool:
	var t: Dictionary = MKDB.tiles.get(id, {})
	var want := sites.split("|")
	for dk in t.get("hexes", {}):
		var hd: Dictionary = t.hexes[dk]
		if str(hd.get("site", "")) in want:
			return true
	return false


## Dopo la preparazione della mappa: posizioni predefinite (Conquista e Mantieni).
static func after_map(eng) -> void:
	var sc: Dictionary = eng.s.scn
	var pd = sc.get("predefined", null)
	if not (pd is Dictionary):
		return
	var deck: Array = eng.s.map.tile_deck
	var cslots: Array = pd.get("country", []).duplicate()
	var kslots: Array = pd.get("core", []).duplicate()
	MKRng.shuffle(eng.s, cslots)
	MKRng.shuffle(eng.s, kslots)
	var country: Array = deck.filter(func(id): return str(MKDB.tiles[id].kind) == "country")
	var core: Array = deck.filter(func(id): return str(MKDB.tiles[id].kind) != "country")
	MKRng.shuffle(eng.s, core)
	var predef := {}
	for i in mini(cslots.size(), country.size()):
		predef[str(cslots[i])] = country[i]
	for i in mini(kslots.size(), core.size()):
		predef[str(kslots[i])] = core[i]
	var used: Array = predef.values()
	eng.s.map["predef"] = predef
	eng.s.map.tile_deck = used.duplicate()


## Dopo la creazione delle pile: Unità escluse dallo scenario.
static func after_setup(eng) -> void:
	st(eng)
	if rule(eng) == "conquer_hold":
		for key in ["units_elite", "units_reg"]:
			eng.s.decks[key] = eng.s.decks[key].filter(func(id): return int(MKDB.units.get(id, {}).get("level", 1)) < 4)


## Tessera da rivelare in una certa posizione (mappa predefinita) oppure la prima del mazzo.
static func take_tile(eng, slot: String) -> String:
	var pd = eng.s.map.get("predef", null)
	if pd is Dictionary and pd.has(slot):
		var tid: String = pd[slot]
		pd.erase(slot)
		eng.s.map.tile_deck.erase(tid)
		return tid
	return eng.s.map.tile_deck.pop_front()


static func predefined(eng) -> bool:
	return eng.s.map.get("predef", null) is Dictionary


## La prossima tessera che verrebbe rivelata in quella posizione.
static func next_tile_at(eng, slot: String) -> String:
	var pd = eng.s.map.get("predef", null)
	if pd is Dictionary:
		return str(pd.get(slot, ""))
	return eng.s.map.tile_deck[0] if not eng.s.map.tile_deck.is_empty() else ""


## Città amica (Miniere, Druido, Sotterraneo): uno Scudo di ogni giocatore, nessun capo, nessun difensore.
static func friendly_city(eng, k: String) -> bool:
	if not eng.s.scn.get("friendly_city", false):
		return false
	var h: Dictionary = eng.hex(k)
	h.conquered = true
	h.owner = -1
	var sh: Array = []
	for i in eng.s.players.size():
		sh.append(i)
	h.city.shields = sh
	h.city.leader = -1
	h["friendly"] = true
	eng.add_log("city", "La città %s è amica: ogni eroe vi ha uno Scudo" % MKMana.color_it(str(h.city.color)), {"hex": k})
	return true


## Nuova tessera: guardiani delle miniere, entrate segrete.
static func on_tile_placed(eng, tid: String, hexes: Array, by: int) -> void:
	match rule(eng):
		"mines":
			var t: Dictionary = MKDB.tiles.get(tid, {})
			for k in hexes:
				var h: Dictionary = eng.hex(k)
				if str(h.get("site", "")) != "mine":
					continue
				h["guarded"] = true
				var e1: String = eng.draw_enemy("green" if str(t.kind) == "country" else "red", true, k)
				if e1 != "":
					h.enemies.append(e1)
				var e2: String = eng.draw_enemy("brown", false, k)
				if e2 != "":
					h.enemies.append(e2)
				eng.add_log("info", "I nemici occupano la miniera: per liberarla entra nel suo spazio e combattili", {"hex": k})
		"dungeon":
			var q: Array = st(eng).secret_q
			for k in hexes:
				var site := str(eng.hex(k).get("site", ""))
				if site == "village":
					q.append({"kind": "dungeon", "near": k, "p": by})
				elif site == "monastery":
					q.append({"kind": "tomb", "near": k, "p": by})
			next_secret(eng)


static func _secret_options(eng, near: String) -> Array:
	var out: Array = []
	for i in MKHex.DIRS.size():
		var k := MKHex.key(MKHex.parse(near) + MKHex.DIRS[i])
		var h: Dictionary = eng.hex(k)
		if h.is_empty() or str(h.get("site", "")) != "" or not h.get("enemies", []).is_empty():
			continue
		if str(h.t) in ["lake", "mountain", "ocean", "swamp"]:
			continue
		out.append({"v": k, "label": "Spazio %s del sito (%s)" % [DIR_IT[i], MKEffects.TERR_IT.get(h.t, h.t)]})
	return out


## Piazza le entrate segrete in coda (chi ha rivelato la tessera sceglie lo spazio; in preparazione a caso).
static func next_secret(eng) -> void:
	var q: Array = st(eng).secret_q
	while not q.is_empty() and eng.s.pending == null:
		var it: Dictionary = q[0]
		var opts := _secret_options(eng, str(it.near))
		if opts.is_empty():
			q.pop_front()
			continue
		var p := int(it.get("p", -1))
		if p < 0 or opts.size() == 1:
			q.pop_front()
			var o: Dictionary = opts[0] if opts.size() == 1 else MKRng.pick(eng.s, opts)
			_place_secret(eng, str(it.kind), str(o.v))
			continue
		eng.ask(p, "hex", "scn:secret", "Scegli lo spazio dell'entrata segreta di %s" % ("un sotterraneo (accanto al villaggio)" if it.kind == "dungeon" else "una tomba (accanto al monastero)"), opts, {"kind": it.kind})
		return


static func _place_secret(eng, kind: String, k: String) -> void:
	var h: Dictionary = eng.hex(k)
	h.site = kind
	h["secret"] = true
	_secret_marker(eng, k)
	eng.add_log("info", "Entrata segreta: %s in %s" % ["un sotterraneo" if kind == "dungeon" else "una tomba", k], {"hex": k})


static func _secret_marker(eng, k: String) -> void:
	var h: Dictionary = eng.hex(k)
	var eid: String = eng.draw_enemy("brown" if str(h.site) == "dungeon" else "red", false, k)
	if eid != "":
		h.enemies.append(eid)


static func resolve(eng, pend: Dictionary, v) -> bool:
	match str(pend.get("handler", "")):
		"scn:secret":
			var q: Array = st(eng).secret_q
			if not q.is_empty():
				q.pop_front()
			_place_secret(eng, str(pend.get("data", {}).get("kind", "dungeon")), str(v))
			next_secret(eng)
			return true
	return false


# ================================================================ round e turni
static func on_round_start(eng, first: bool) -> void:
	match rule(eng):
		"mines":
			if first:
				return
			for i in eng.s.players.size():
				for k in eng.P(i).shields:
					var h: Dictionary = eng.hex(k)
					if str(h.get("site", "")) == "mine" and h.get("guarded", false):
						var cols: Array = h.get("mines", [h.get("mine", "")])
						var col := str(cols[0]) if not cols.is_empty() else ""
						for c in cols:
							if int(eng.P(i).crystals.get(str(c), 0)) < 3:
								col = str(c)
								break
						if col != "":
							eng.add_log("site", "I minatori riconoscenti donano un cristallo a %s" % eng.pname(i), {"p": i})
							eng.gain_crystal(i, col)


static func on_round_end(eng) -> void:
	var s: Dictionary = eng.s
	match rule(eng):
		"druid":
			if not s.day and int(s.round) == 2:
				st(eng).glades = {}
				eng.add_log("info", "Fine della prima Notte: gli Scudi vengono tolti dalle radure magiche", {})
		"one_return":
			if int(s.round) == 1:
				var portal := str(s.map.get("portal", ""))
				var elim: Array = st(eng).eliminated
				for i in s.players.size():
					if str(eng.P(i).pos) == portal and not i in elim:
						elim.append(i)
						eng.P(i)["eliminated"] = true
						eng.P(i).pos = ""
						eng.add_log("info", "Il portale si chiude: %s è eliminato dalla partita" % eng.pname(i), {"p": i})
				eng.add_log("info", "Il portale si è chiuso: d'ora in poi è uno spazio come gli altri", {})
				if elim.size() >= s.players.size():
					s.game_end_pending = true


static func eliminated(eng, p: int) -> bool:
	return p >= 0 and p < eng.s.players.size() and bool(eng.P(p).get("eliminated", false))


static func active_players(eng) -> Array:
	var out: Array = []
	for i in eng.s.players.size():
		if not eliminated(eng, i):
			out.append(i)
	return out


static func on_turn_start(eng, p: int) -> void:
	if rule(eng) != "conquer_hold":
		return
	var pos := str(eng.P(p).pos)
	var mine: Array = []
	var near := false
	for k in eng.s.map.hex:
		var h: Dictionary = eng.s.map.hex[k]
		if str(h.site) == "mage_tower" and h.conquered and int(h.owner) == p:
			mine.append(k)
			if k == pos or MKHex.adjacent(k, pos):
				near = true
	if near:
		for k in mine:
			eng.gain_token(p, "gold" if eng.s.day else "black")
		eng.add_log("site", "Le torri di %s producono %d mana %s" % [eng.pname(p), mine.size(), "oro" if eng.s.day else "nero"], {"p": p})


## Fine turno su un sito (dopo radura/miniera): Notti del Druido = segna la radura.
static func on_end_turn_site(eng, p: int) -> void:
	if rule(eng) != "druid":
		return
	var k := str(eng.P(p).pos)
	if str(eng.hex(k).get("site", "")) != "glade":
		return
	var g: Dictionary = st(eng).glades
	var arr: Array = g.get(k, [])
	if p in arr:
		return
	arr.append(p)
	g[k] = arr
	eng.add_log("site", "%s attiva la radura magica (Scudo sulla radura: %d)" % [eng.pname(p), marked_glades(eng, p)], {"p": p, "hex": k})


static func marked_glades(eng, p: int) -> int:
	var n := 0
	var g: Dictionary = st(eng).glades
	for k in g:
		if p in g[k]:
			n += 1
	return n


## Le miniere producono cristalli? (Liberazione delle Miniere: solo se liberate)
static func mine_produces(eng, k: String) -> bool:
	if rule(eng) != "mines":
		return true
	var h: Dictionary = eng.hex(k)
	return not h.get("guarded", false) or h.get("conquered", false)


static func elite_ok(eng, def: bool) -> bool:
	if rule(eng) == "conquer_hold":
		return int(eng.s.round) >= (4 if eng.s.players.size() == 2 else 3)
	return def


# ================================================================ siti
## Sito avventura "di scenario" (miniera sorvegliata)?
static func is_adventure(eng, h: Dictionary) -> bool:
	return rule(eng) == "mines" and str(h.get("site", "")) == "mine" and h.get("guarded", false) and not h.get("conquered", false) and not h.get("enemies", []).is_empty()


## Controllo dell'azione "site" (""=ok, null = controllo normale).
static func site_check(eng, p: int, h: Dictionary):
	var site := str(h.get("site", ""))
	if is_adventure(eng, h):
		return ""
	if rule(eng) == "dungeon" and site in ["dungeon", "tomb"] and h.get("conquered", false):
		return "In questo scenario sotterranei e tombe conquistati non si possono più visitare"
	return null


## Combattimento di un sito di scenario; true se gestito.
static func enter_site(eng, p: int) -> bool:
	var k := str(eng.P(p).pos)
	var h: Dictionary = eng.hex(k)
	if is_adventure(eng, h):
		var eids: Array = h.enemies.duplicate()
		eng.add_log("enter_site", "%s entra nella miniera occupata" % eng.pname(p), {"p": p, "hex": k})
		MKCombat.start(eng, eids, {"site": k, "kind": "site", "site_type": "mine", "defenders": eids, "first_time": true,
			"night_rules": true, "units_allowed": true})
		return true
	if h.get("secret", false) and not h.enemies.is_empty():
		var eids2: Array = h.enemies.duplicate()
		var site := str(h.site)
		eng.add_log("enter_site", "%s entra nell'entrata segreta (%s)" % [eng.pname(p), eng.SITE_IT.get(site, site)], {"p": p, "hex": k})
		MKCombat.start(eng, eids2, {"site": k, "kind": "site", "site_type": site, "defenders": eids2, "first_time": not h.conquered})
		return true
	return false


## Sito conquistato; true se gestito qui.
static func site_won(eng, p: int, k: String) -> bool:
	var h: Dictionary = eng.hex(k)
	if rule(eng) == "mines" and str(h.get("site", "")) == "mine" and h.get("guarded", false):
		h.conquered = true
		h.owner = p
		if not k in eng.P(p).shields:
			eng.P(p).shields.append(k)
		var core := str(MKDB.tiles.get(str(h.get("tile", "")), {}).get("kind", "")) != "country"
		eng.change_rep(p, 2 if core else 1)
		eng.add_log("conquer", "%s libera la miniera%s" % [eng.pname(p), " (tessera Principale)" if core else ""], {"p": p, "hex": k})
		return true
	return false


## Dopo ogni combattimento: segnalini delle entrate segrete, mostri evocati che scompaiono.
static func after_combat(eng, c: Dictionary) -> void:
	var s: Dictionary = eng.s
	if str(c.get("kind", "")) == "incant":
		for e in c.enemies:
			if s.enemies.has(str(e.eid)):
				eng.discard_enemy(str(e.eid))
		return
	var site := str(c.get("site", ""))
	if site == "" or str(c.get("kind", "")) != "site":
		return
	var h: Dictionary = eng.hex(site)
	if h.get("secret", false) and not h.get("conquered", false) and h.enemies.is_empty():
		_secret_marker(eng, site)


## Conquista di castello/torre in Conquista e Mantieni; true se gestita.
static func conquer(eng, p: int, k: String) -> bool:
	if rule(eng) != "conquer_hold":
		return false
	var h: Dictionary = eng.hex(k)
	if not str(h.site) in ["keep", "mage_tower"]:
		return false
	h.conquered = true
	var prev := int(h.owner)
	h.owner = p
	if prev >= 0 and prev != p and prev < eng.s.players.size():
		eng.P(prev).shields.erase(k)
	if not k in eng.P(p).shields:
		eng.P(p).shields.append(k)
	eng.add_log("conquer", "%s conquista %s" % [eng.pname(p), "il castello" if h.site == "keep" else "la torre della magia"], {"p": p, "hex": k})
	return true


## Castello/torre sicuri per p? (null = regola normale)
static func safe_fortified(eng, p: int, h: Dictionary):
	var site := str(h.get("site", ""))
	if rule(eng) == "conquer_hold" and site in ["keep", "mage_tower"]:
		if not h.conquered:
			return false
		return int(h.owner) < 0 or allies(eng, p, int(h.owner))
	if site == "keep" and h.conquered and int(h.owner) >= 0 and team_of(eng, p) >= 0 and allies(eng, p, int(h.owner)):
		return true
	return null


## Siti posseduti dagli eroi che gli altri possono assaltare (castelli; anche le torri in Conquista e Mantieni).
static func owned_sites(eng) -> Array:
	return ["keep", "mage_tower"] if rule(eng) == "conquer_hold" else ["keep"]


## Difensori pescati quando si assalta un sito posseduto da un altro giocatore.
static func owned_defenders(eng) -> int:
	if rule(eng) != "conquer_hold":
		return 1
	var r := int(eng.s.round)
	if eng.s.players.size() == 2 and r >= 5:
		return 3
	return 2 if r >= 3 else 1


static func assault_rep(eng, site: String) -> bool:
	return not (rule(eng) == "conquer_hold" and site in ["keep", "mage_tower"])


## Sito con cui p può interagire (null = regola normale).
static func interaction_site(eng, p: int, h: Dictionary):
	if rule(eng) != "conquer_hold":
		if str(h.get("site", "")) == "keep" and h.conquered and int(h.owner) >= 0 and team_of(eng, p) >= 0:
			return "keep" if allies(eng, p, int(h.owner)) else ""
		return null
	match str(h.get("site", "")):
		"keep":
			return "keep" if h.conquered and int(h.owner) >= 0 and allies(eng, p, int(h.owner)) else ""
		"mage_tower":
			return "mage_tower" if h.conquered and int(h.owner) >= 0 and allies(eng, p, int(h.owner)) else ""
	return null


static func recruit_extra(eng, site: String, rec: Array) -> bool:
	if rule(eng) != "conquer_hold":
		return false
	return (site == "mage_tower" and "monastery" in rec) or (site == "keep" and "village" in rec)


## Portale: spazio condivisibile e sicuro? (Solo Uno Tornerà: dopo il primo Giorno no)
static func portal_open(eng) -> bool:
	return not (rule(eng) == "one_return" and int(eng.s.round) >= 2)


# ================================================================ azioni di scenario
static func actions(eng, p: int) -> Array:
	var out: Array = []
	match rule(eng):
		"druid":
			if check(eng, p, {"op": "incant"}) == "":
				var n := marked_glades(eng, p)
				out.append({"a": {"t": "scn", "op": "incant"}, "label": "Compi l'incantesimo del druido: evoca %d nemic%s %s" % [n, "o" if n == 1 else "i", "marron%s" % ("e" if n == 1 else "i") if int(eng.s.round) <= 2 else ("rosso" if n == 1 else "rossi")], "group": "site"})
		"dungeon":
			for d in tunnels(eng, p):
				if int(d.cost) <= int(eng.s.turn.pool.move):
					out.append({"a": {"t": "scn", "op": "tunnel", "to": d.to}, "label": "Galleria verso %s in %s (costo %d)" % [eng.SITE_IT.get(str(eng.hex(d.to).site), ""), d.to, int(d.cost)], "group": "move"})
	return out


static func check(eng, p: int, a: Dictionary) -> String:
	var s: Dictionary = eng.s
	match str(a.get("op", "")):
		"incant":
			if rule(eng) != "druid":
				return "Non in questo scenario"
			var e := MKSites._action_free(eng, p)
			if e != "":
				return e
			if s.day or not int(s.round) in [2, 4]:
				return "L'incantesimo si compie solo durante la prima o la seconda Notte"
			if p in st(eng).incant.get(str(s.round), []):
				return "Hai già compiuto l'incantesimo in questa Notte"
			if str(eng.hex(str(eng.P(p).pos)).get("site", "")) in INHABITED:
				return "Non puoi compiere l'incantesimo in uno spazio abitato"
			if marked_glades(eng, p) <= 0:
				return "Non hai Scudi su nessuna radura magica"
			if MKPvP.crowded(eng, p):
				return "Nel tuo spazio c'è un altro eroe"
			return ""
		"tunnel":
			if rule(eng) != "dungeon":
				return "Non in questo scenario"
			if not eng.can_still_move(p):
				return "Non puoi più muoverti in questo turno"
			var to := str(a.get("to", ""))
			for d in tunnels(eng, p):
				if str(d.to) == to:
					if int(d.cost) > int(s.turn.pool.move):
						return "Punti Movimento insufficienti (servono %d)" % int(d.cost)
					return ""
			return "Nessuna galleria verso quello spazio"
	return "Azione di scenario sconosciuta"


static func do(eng, p: int, a: Dictionary) -> void:
	var s: Dictionary = eng.s
	match str(a.get("op", "")):
		"incant":
			var r := str(s.round)
			var inc: Dictionary = st(eng).incant
			var arr: Array = inc.get(r, [])
			arr.append(p)
			inc[r] = arr
			var second: bool = int(s.round) >= 4
			var n := marked_glades(eng, p)
			var eids: Array = []
			for i in n:
				var eid: String = eng.draw_enemy("red" if second else "brown", true, "")
				if eid != "":
					eids.append(eid)
			eng.add_log("info", "%s compie l'incantesimo del druido ed evoca %d mostri" % [eng.pname(p), eids.size()], {"p": p})
			if eids.size() > 0:
				s.turn.rewards.append({"k": "crystal_roll", "n": eids.size() * (2 if second else 1)})
			MKCombat.start(eng, eids, {"kind": "incant", "units_allowed": true})
			if s.combat != null:
				for e in s.combat.enemies:
					e.fame = int(e.fame) * 2
			_druid_end_check(eng)
		"tunnel":
			var to := str(a.get("to", ""))
			var cost := 0
			for d in tunnels(eng, p):
				if str(d.to) == to:
					cost = int(d.cost)
			s.turn.pool.move = int(s.turn.pool.move) - cost
			eng.add_log("move", "%s percorre le gallerie sotterranee (costo %d)" % [eng.pname(p), cost], {"p": p})
			eng.teleport(p, to, true)


## Gallerie: da un sotterraneo/tomba conquistati verso gli altri (2 + distanza su spazi rivelati, senza laghi né paludi).
static func tunnels(eng, p: int) -> Array:
	var out: Array = []
	if rule(eng) != "dungeon":
		return out
	var pos := str(eng.P(p).pos)
	var h0: Dictionary = eng.hex(pos)
	if not (str(h0.get("site", "")) in ["dungeon", "tomb"] and h0.get("conquered", false)):
		return out
	var dist := {pos: 0}
	var fr: Array = [pos]
	while not fr.is_empty():
		var cur: String = fr.pop_front()
		for nk in MKHex.neighbors(cur):
			if dist.has(nk):
				continue
			var nh: Dictionary = eng.hex(nk)
			if nh.is_empty() or str(nh.t) in ["lake", "swamp", "ocean"]:
				continue
			dist[nk] = int(dist[cur]) + 1
			fr.append(nk)
	for k in eng.s.map.hex:
		if k == pos:
			continue
		var h: Dictionary = eng.s.map.hex[k]
		if str(h.site) in ["dungeon", "tomb"] and h.get("conquered", false) and dist.has(k):
			var busy := false
			for j in eng.s.players.size():
				if j != p and str(eng.P(j).pos) == k:
					busy = true
			if not busy:
				out.append({"to": k, "cost": 2 + int(dist[k])})
	return out


# ================================================================ fine partita
static func _druid_end_check(eng) -> void:
	var s: Dictionary = eng.s
	if int(s.round) != 4 or s.game_end_pending:
		return
	var done: Array = st(eng).incant.get("4", [])
	for i in s.players.size():
		if not i in done:
			return
	eng._trigger_game_end("Tutti hanno compiuto l'incantesimo della seconda Notte")
	if s.scn.get("dummy_no_final", false):
		s.final_turns.erase(str(eng.DUMMY))


## Controllo degli obiettivi a fine turno; true se gestito (fine scenario diversa dalle città).
static func check_end(eng, p: int) -> bool:
	var s: Dictionary = eng.s
	var e := str(s.scn.get("end", ""))
	match e:
		"mines", "dungeon":
			if not s.map.tile_deck.is_empty():
				return true
			if objective_done(eng):
				eng._trigger_game_end("Tutte le tessere sono rivelate e %s" % ("tutte le miniere sono state liberate" if e == "mines" else "tutti i sotterranei e le tombe sono conquistati"))
				if s.scn.get("dummy_no_final", false):
					s.final_turns.erase(str(eng.DUMMY))
			return true
		"druid", "rounds":
			return true
	return false


## Obiettivo comune raggiunto (miniere liberate / sotterranei e tombe conquistati)?
static func objective_done(eng) -> bool:
	var e := str(eng.s.scn.get("end", ""))
	var n := 0
	for k in eng.s.map.hex:
		var h: Dictionary = eng.s.map.hex[k]
		if e == "mines" and str(h.site) == "mine":
			n += 1
			if not h.get("conquered", false):
				return false
		elif e == "dungeon" and str(h.site) in ["dungeon", "tomb"]:
			n += 1
			if not h.get("conquered", false):
				return false
	return n > 0 and eng.s.map.tile_deck.is_empty()


## Punti Avventuriero per uno Scudo su un sito.
static func adv_points(eng, site: String) -> int:
	if rule(eng) == "dungeon" and site in ["dungeon", "tomb"]:
		return 4
	return 2


## Bonus del titolo (Signori del Sotterraneo: Più Grande Esploratore di Sotterranei +5/+2).
static func title_bonus(eng, key: String, unique: bool) -> int:
	if key == "adventurer" and rule(eng) == "dungeon":
		return 5 if unique else 2
	return 3 if unique else 1


## Punti di scenario del giocatore i (Miniere: 4/7 per miniera) senza il bonus del titolo.
static func points(eng, i: int) -> int:
	match rule(eng):
		"mines":
			var v := 0
			for k in eng.P(i).shields:
				var h: Dictionary = eng.hex(k)
				if str(h.get("site", "")) == "mine":
					v += 4 if str(MKDB.tiles.get(str(h.get("tile", "")), {}).get("kind", "")) == "country" else 7
			return v
		"conquer_hold":
			return victory_points(eng, i)
	return 0


static func victory_points(eng, i: int) -> int:
	var v := 0
	for k in eng.s.map.hex:
		var h: Dictionary = eng.s.map.hex[k]
		if h.get("conquered", false) and int(h.get("owner", -1)) == i:
			if str(h.site) == "keep":
				v += 3
			elif str(h.site) == "mage_tower":
				v += 2
	return v


## Punti di scenario nel totale della Fama (Miniere: liberatore +5/+2).
static func score_points(eng, i: int) -> int:
	if rule(eng) != "mines":
		return 0
	var vals: Array = []
	for j in eng.s.players.size():
		vals.append(points(eng, j))
	var v: int = vals[i]
	var mx: int = vals.max()
	if eng.s.players.size() > 1 and mx > 0 and v == mx:
		v += 5 if vals.count(mx) == 1 else 2
	return v


## Risultato finale: vincitori e note dello scenario.
static func finalize(eng, res: Dictionary, scores: Array) -> void:
	var s: Dictionary = eng.s
	var notes: Array = []
	match rule(eng):
		"mines", "dungeon":
			var ok := objective_done(eng)
			res["mission"] = ok
			if s.players.size() == 1:
				res["victory"] = ok
			notes.append("Missione %s: %s" % ["riuscita" if ok else "fallita", "tutte le miniere liberate" if rule(eng) == "mines" else "tutti i sotterranei e le tombe conquistati"] if ok else "Missione fallita: %s" % ("non tutte le miniere sono state liberate" if rule(eng) == "mines" else "non tutti i sotterranei e le tombe sono stati conquistati"))
			res["scn_col"] = "Miniere" if rule(eng) == "mines" else ""
		"druid":
			var inc: Dictionary = st(eng).incant
			notes.append("Incantesimi compiuti: prima Notte %d, seconda Notte %d" % [inc.get("2", []).size(), inc.get("4", []).size()])
		"conquer_hold":
			var teams: Array = s.scn.get("teams", [])
			var groups: Array = []
			if teams.is_empty():
				for i in s.players.size():
					groups.append([i])
			else:
				groups = teams
			var best := -1
			var win: Array = []
			var parts: Array = []
			for g in groups:
				var vp := 0
				var names: Array = []
				for x in g:
					vp += victory_points(eng, int(x))
					names.append(eng.pname(int(x)))
				parts.append("%s %d" % [" + ".join(names), vp])
				if vp > best:
					best = vp
					win = [g]
				elif vp == best:
					win.append(g)
			res["winners"] = []
			if win.size() == 1 and best > 0:
				for x in win[0]:
					res.winners.append(int(x))
			notes.append("Punti Vittoria (castello 3, torre 2): " + ", ".join(parts))
			if res.winners.is_empty():
				notes.append("Parità: nessun vincitore")
			res["scn_col"] = "Punti Vittoria"
			res["scn_key"] = "scenario_raw"
		"one_return":
			var portal := str(s.map.get("portal", ""))
			res["winners"] = []
			for i in s.players.size():
				if not eliminated(eng, i) and str(eng.P(i).pos) == portal:
					res.winners.append(i)
			if res.winners.size() > 1:
				res.winners = []
			for i in st(eng).eliminated:
				notes.append("%s è stato eliminato alla chiusura del portale" % eng.pname(int(i)))
			if res.winners.is_empty():
				notes.append("Nessuno si trova sul portale: nessun vincitore")
			else:
				notes.append("%s è sul portale e torna a casa" % eng.pname(int(res.winners[0])))
	if not notes.is_empty():
		res["scn_notes"] = notes


# ================================================================ testi per l'interfaccia
## Obiettivo dello scenario per la barra in alto ("" = testo normale).
static func goal_text(eng) -> String:
	var s: Dictionary = eng.s
	match rule(eng):
		"mines":
			var a := 0
			var t := 0
			for k in s.map.hex:
				if str(s.map.hex[k].site) == "mine":
					t += 1
					if s.map.hex[k].get("conquered", false):
						a += 1
			return "Obiettivo: libera le miniere (%d liberate su %d rivelate)" % [a, t]
		"dungeon":
			var a2 := 0
			var t2 := 0
			for k in s.map.hex:
				if str(s.map.hex[k].site) in ["dungeon", "tomb"]:
					t2 += 1
					if s.map.hex[k].get("conquered", false):
						a2 += 1
			return "Obiettivo: sotterranei e tombe (%d/%d)" % [a2, t2]
		"druid":
			var p: int = eng.actor()
			var n := marked_glades(eng, p) if p >= 0 and p < s.players.size() else 0
			if s.day:
				return "Segna le radure magiche (tue: %d) per l'incantesimo della Notte" % n
			return "Notte: compi l'incantesimo del druido (%d radure segnate)" % n
		"conquer_hold":
			var parts: Array = []
			for i in s.players.size():
				parts.append("%s %d" % [eng.pname(i), victory_points(eng, i)])
			return "Punti Vittoria: " + ", ".join(parts)
		"one_return":
			if int(s.round) == 1:
				return "Il portale si chiude alla fine del Giorno: chi vi resta è eliminato"
			return "Vince chi è sul portale alla fine del round %d" % int(s.scn.rounds)
	return ""


## Nota di scenario per il riquadro informativo di un esagono.
static func hex_note(eng, k: String) -> String:
	var h: Dictionary = eng.hex(k)
	if h.is_empty():
		return ""
	match rule(eng):
		"mines":
			if str(h.site) == "mine" and h.get("guarded", false):
				if h.get("conquered", false):
					return "[color=#9fe870]Miniera liberata da %s[/color]" % eng.pname(int(h.owner)) if int(h.get("owner", -1)) >= 0 else "Miniera liberata"
				return "[color=#ff9a3a]Miniera occupata: entra nello spazio e combatti i nemici (Azione, regole della Notte, con le Unità) per liberarla[/color]"
		"druid":
			if str(h.site) == "glade":
				var who: Array = []
				for i in st(eng).glades.get(k, []):
					who.append(eng.pname(int(i)))
				return "Scudi sulla radura: %s" % (", ".join(who) if not who.is_empty() else "nessuno")
		"dungeon":
			if h.get("secret", false):
				return "Entrata segreta (%s)%s" % ["sotterraneo" if str(h.site) == "dungeon" else "tomba", " · conquistata: collegata alle gallerie" if h.get("conquered", false) else ""]
			if str(h.site) in ["dungeon", "tomb"] and h.get("conquered", false):
				return "Conquistato: collegato alle gallerie"
	if h.get("friendly", false):
		return "Città amica: ogni eroe vi ha uno Scudo"
	return ""
