extends RefCounted
## IA: piccoli aggiustamenti perché gli eroi IA perseguano l'obiettivo degli scenari del Manuale degli Scenari
## (MKScn): miniere da liberare, radure da segnare e incantesimo del druido, sotterranei e tombe da 4 punti,
## castelli e torri da tenere (Conquista e Mantieni), portale da evitare/raggiungere (Solo Uno Tornerà).


## Azione di scenario da compiere subito (prima del pianificatore), {} se nessuna.
static func turn_hook(eng, p: int, ctx: Dictionary, mem: Dictionary, TU) -> Dictionary:
	if MKScn.rule(eng) == "druid":
		var a := {"t": "scn", "op": "incant"}
		if eng.check(a) != "":
			return {}
		var pl: Dictionary = eng.P(p)
		var good := 0
		for iid in pl.hand:
			if not eng.is_wound(iid):
				good += 1
		var n := MKScn.marked_glades(eng, p)
		var req := float(n) * (11.0 if int(eng.s.round) >= 4 else 7.0)
		var late: bool = pl.deck.size() <= 2 or int(eng.s.announced_by) != -1 or eng.s.game_end_pending
		if eng.s.dummy != null and eng.s.dummy.deck.size() <= 4:
			late = true
		if (good >= 4 and not eng.s.turn.get("started", false) and TU.feas(TU.power(eng, p), req) >= 0.55) or (late and good >= 2):
			mem["productive"] = true
			return a
	return {}


## Valore strategico aggiuntivo di un esagono (bersagli del pianificatore).
static func target_value(eng, p: int, k: String, h: Dictionary, v: float) -> float:
	match MKScn.rule(eng):
		"druid":
			if str(h.get("site", "")) == "glade" and not p in MKScn.st(eng).glades.get(k, []) and _druid_glade_time(eng, p):
				v = maxf(v, 0.0) + 5.0
		"dungeon":
			if str(h.get("site", "")) in ["dungeon", "tomb"] and not h.get("conquered", false):
				v *= 1.5
		"conquer_hold":
			var site := str(h.get("site", ""))
			if site in ["keep", "mage_tower"]:
				var mine: bool = h.get("conquered", false) and int(h.get("owner", -1)) >= 0 and MKScn.allies(eng, p, int(h.owner))
				if not mine:
					v = maxf(v, 4.0) * 1.6 + (6.0 if site == "keep" else 4.0)
		"one_return":
			if str(h.get("site", "")) == "portal" and int(eng.s.round) >= int(eng.s.scn.rounds):
				v = maxf(v, 0.0) + 40.0
	return v


static func _druid_glade_time(eng, p: int) -> bool:
	var r := int(eng.s.round)
	if r <= 2:
		return not p in MKScn.st(eng).incant.get("2", [])
	return r <= 4 and not p in MKScn.st(eng).incant.get("4", [])


## Bonus/penalità per terminare il turno in k.
static func end_bonus(eng, p: int, k: String) -> float:
	var h: Dictionary = eng.hex(k)
	match MKScn.rule(eng):
		"druid":
			if str(h.get("site", "")) == "glade" and not p in MKScn.st(eng).glades.get(k, []) and _druid_glade_time(eng, p):
				return 4.0
		"one_return":
			if str(h.get("site", "")) == "portal":
				var r := int(eng.s.round)
				if r == 1:
					return -60.0
				if r >= int(eng.s.scn.rounds):
					return 60.0
	return 0.0


## Bonus per la conquista di un sito avventura di scenario (miniere liberate).
static func site_bonus(eng, p: int, k: String) -> float:
	var h: Dictionary = eng.hex(k)
	if MKScn.is_adventure(eng, h):
		var core := str(MKDB.tiles.get(str(h.get("tile", "")), {}).get("kind", "")) != "country"
		# in solitario la missione (liberarle tutte) conta di più
		return (7.0 if core else 4.0) + (2.0 if core else 1.0) + 2.5 + (4.0 if eng.s.players.size() == 1 else 0.0)
	return 0.0
