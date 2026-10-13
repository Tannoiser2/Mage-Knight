class_name MKSitesExp
extends RefCounted
## Sites of the Lost Legion tiles (from the Italian site cards of the module):
## - Campo Profughi (camp): si interagisce per reclutare; vale come uno qualsiasi dei siti raffigurati:
##   Unità del villaggio +0, del castello / torre della magia / monastero +1, solo della città +3 Influenza
##   (per le Unità reclutabili in più siti si sceglie l'opzione più conveniente). Niente cure né acquisti.
## - Dedalo (maze, nemico marrone) / Labirinto (labyrinth, nemico rosso Draconum): si entra come azione;
##   si può scegliere UNA Unità pronta e non ferita che accompagna l'eroe (nessun'altra Unità per tutta
##   l'azione); poi si sceglie il sentiero pagando Movimento 2, 4 o 6 (i punti avanzati dalla fase di
##   movimento non valgono) e si combatte un nemico pescato (scartato comunque alla fine).
##   Ricompensa: 2 = due cristalli a scelta, 4 = un Incantesimo, 6 = un Artefatto; nel Labirinto anche
##   un'Azione Avanzata. Ogni sentiero si conquista una volta sola (Scudo), ogni giocatore conquista lo
##   stesso dedalo una volta sola.
## State: hex.maze_paths = {"2": p, "4": p, "6": p}; s.turn.maze = {hex, stage:"unit"|"pay"|"fight", unit, cost}.

const MAZE_SITES := ["maze", "labyrinth"]

## Rules summary shown in the "Regole" screen when expansion content is in play.
const RULES_TEXT := """[b]Espansioni.[/b] [b]Mura[/b]: attraversare un muro costa 1 Movimento in più (gli sconti sul terreno non lo tolgono); non si provocano nemici scatenati separati da un muro; i nemici scatenati sfidati attraverso un muro sono fortificati e la guarnigione di un sito fortificato assaltato attraverso un muro è fortificata doppia.
[b]Campo Profughi[/b]: si interagisce solo per reclutare; le Unità del villaggio costano il normale, quelle di castello, torre della magia o monastero +1, quelle solo della città +3.
[b]Dedalo / Labirinto[/b]: entri come azione portando al massimo una Unità pronta (nessun'altra per tutta l'azione); poi generi Movimento 2, 4 o 6 (i punti avanzati dal movimento non valgono), scegli il sentiero e combatti un nemico marrone (Dedalo) o rosso (Labirinto). Ricompense: 2 = due cristalli, 4 = un Incantesimo, 6 = un Artefatto; nel Labirinto anche un'Azione Avanzata. Ogni sentiero si conquista una volta, ogni eroe una volta per sito.
[b]Miniere Profonde[/b]: a fine turno scegli il colore del cristallo tra quelli della miniera.
[b]Nemici[/b]: [i]Elusivo[/i] (armatura alta, bassa nella fase di Attacco se tutti i suoi attacchi sono bloccati), [i]Difensore[/i] (+X all'Armatura di un nemico attaccato, una volta), [i]Ingombrante[/i] (nella fase di Blocco ogni Movimento speso ne riduce di 1 l'attacco), [i]Assassinio[/i] (danni solo all'eroe), [i]Vampirico[/i] (+1 Armatura per ogni Ferita che infligge), [i]Immunità arcana[/i] (ignora gli effetti che non sono Attacchi o Blocchi), Reputazione +1/−1 alla sconfitta di Teppisti/Eroi."""
const PATHS := [2, 4, 6]

# ---------------------------------------------------------------- refugee camp
## Extra Influence to recruit unit `ud` in a refugee camp, -1 if it cannot be recruited there.
static func camp_surcharge(ud: Dictionary) -> int:
	var rec: Array = ud.get("recruit", [])
	var best := -1
	if "village" in rec:
		best = 0
	elif "keep" in rec or "mage_tower" in rec or "monastery" in rec:
		best = 1
	elif "city" in rec:
		best = 3
	elif "camp" in rec:
		best = 0
	return best

# ---------------------------------------------------------------- maze / labyrinth
static func free_paths(eng, h: Dictionary) -> Array:
	var out: Array = []
	var mp: Dictionary = h.get("maze_paths", {})
	for c in PATHS:
		if not mp.has(str(c)):
			out.append(c)
	return out

static func site_check(eng, p: int, h: Dictionary) -> String:
	var mp: Dictionary = h.get("maze_paths", {})
	for k in mp:
		if int(mp[k]) == p:
			return "Hai già conquistato questo %s" % ("labirinto" if h.site == "labyrinth" else "dedalo")
	if free_paths(eng, h).is_empty():
		return "Tutti i sentieri sono già stati conquistati"
	return ""

static func enter(eng, p: int) -> void:
	var s: Dictionary = eng.s
	var pl: Dictionary = eng.P(p)
	var t: Dictionary = s.turn
	var h: Dictionary = eng.hex(pl.pos)
	t.acted = true
	t.started = true
	t.pool.move = 0
	t["maze"] = {"hex": pl.pos, "stage": "unit", "unit": -1, "cost": 0}
	eng.add_log("enter_site", "%s entra nel %s" % [eng.pname(p), "Labirinto" if h.site == "labyrinth" else "Dedalo"], {"p": p, "hex": pl.pos})
	var opts: Array = []
	for u in pl.units:
		if u.ready and not u.wounded:
			opts.append({"v": int(u.uid), "label": "Ti accompagna %s" % eng.unit_name(u)})
	if opts.is_empty():
		_to_pay(eng, p)
		return
	opts.push_front({"v": -1, "label": "Nessuna Unità"})
	eng.ask(p, "unit", "sp:maze_unit", "Scegli l'Unità che ti accompagna (nessun'altra potrà essere usata)", opts)

static func choose_unit(eng, p: int, v) -> void:
	var m: Dictionary = eng.s.turn.get("maze", {})
	m["unit"] = int(v)
	if int(v) >= 0:
		eng.add_log("info", "%s entra con %s" % [eng.pname(p), eng.unit_name_by_uid(p, v)], {"p": p})
	_to_pay(eng, p)

static func _to_pay(eng, p: int) -> void:
	var m: Dictionary = eng.s.turn.get("maze", {})
	m["stage"] = "pay"
	eng.add_log("info", "Scegli il sentiero: genera Movimento 2, 4 o 6 e pagalo", {"p": p})

## True while the hero is generating Move points to pay a maze path.
static func paying(eng, p: int) -> bool:
	var t: Dictionary = eng.s.turn
	return eng.s.combat == null and int(t.get("player", -1)) == p and str(t.get("maze", {}).get("stage", "")) == "pay" and not t.get("ending", false)

## Units: in a maze only the chosen unit may be used during the whole action.
static func unit_restrict(eng, p: int, u: Dictionary) -> String:
	var m = eng.s.turn.get("maze", null)
	if m is Dictionary and int(eng.s.turn.get("player", -1)) == p and str(m.get("stage", "")) in ["pay", "fight"]:
		if int(m.get("unit", -1)) != int(u.uid):
			return "Nel dedalo puoi usare solo l'Unità che ti accompagna"
	return ""

static func actions(eng, p: int) -> Array:
	var out: Array = []
	if not paying(eng, p):
		return out
	var h: Dictionary = eng.hex(str(eng.s.turn.maze.hex))
	for c in free_paths(eng, h):
		if int(eng.s.turn.pool.move) >= int(c):
			var rw: String = {2: "due cristalli a scelta", 4: "un Incantesimo", 6: "un Artefatto"}[c]
			out.append({"a": {"t": "sp", "name": "maze_path", "cost": int(c)}, "label": "Sentiero %d: paga Movimento %d e combatti (ricompensa: %s%s)" % [c, c, rw,
				" + un'Azione Avanzata" if h.site == "labyrinth" else ""], "group": "site"})
	return out

static func do_path(eng, p: int, a: Dictionary) -> void:
	var s: Dictionary = eng.s
	var t: Dictionary = s.turn
	var m: Dictionary = t.maze
	var k: String = str(m.hex)
	var h: Dictionary = eng.hex(k)
	var cost := int(a.cost)
	t.pool.move = int(t.pool.move) - cost
	m.cost = cost
	m.stage = "fight"
	var eid: String = eng.draw_enemy("red" if h.site == "labyrinth" else "brown", true, "")
	eng.add_log("enter_site", "%s sceglie il sentiero %d" % [eng.pname(p), cost], {"p": p, "hex": k})
	var opts := {"site": k, "kind": "site", "site_type": str(h.site), "defenders": [eid] if eid != "" else [], "first_time": true,
		"units_only": int(m.unit)}
	MKCombat.start(eng, [eid] if eid != "" else [], opts)

static func won(eng, p: int, k: String) -> void:
	var s: Dictionary = eng.s
	var h: Dictionary = eng.hex(k)
	var m: Dictionary = s.turn.get("maze", {})
	var cost := int(m.get("cost", 2))
	if not h.has("maze_paths"):
		h["maze_paths"] = {}
	h.maze_paths[str(cost)] = p
	var rw: Array = s.turn.rewards
	match cost:
		2:
			rw.append({"k": "crystal_choice"})
			rw.append({"k": "crystal_choice"})
		4:
			rw.append({"k": "spell"})
		_:
			rw.append({"k": "artifact"})
	if h.site == "labyrinth":
		rw.append({"k": "aa"})
	if free_paths(eng, h).is_empty():
		h.conquered = true
	MKSites._shield(eng, p, k)
	eng.add_log("conquer", "%s conquista il sentiero %d del %s" % [eng.pname(p), cost, "labirinto" if h.site == "labyrinth" else "dedalo"], {"p": p, "hex": k})
