class_name MKGloss
extends RefCounted
## Glossario dei suggerimenti (data/glossario.json): spiegazioni brevi di abilità dei nemici, elementi,
## resistenze, parole chiave delle Unità, terreni e siti. Le spiegazioni compaiono come blocco extra
## (più piccolo, attenuato) sotto il testo base dei suggerimenti, solo se l'impostazione
## «Spiegazioni nei suggerimenti» è su Sì (menu di gioco / menu principale; salvata in user://mk_settings.cfg).
## Suggerimenti a capo e in BBCode: set_tip(ctrl, testo) usa un tooltip personalizzato largo al massimo TIP_W.

const PATH := "res://data/glossario.json"
const SETTINGS := "user://mk_settings.cfg"
## Ogni riga del blocco di spiegazioni comincia così (show_zoom tiene queste righe anche sulle carte).
const PREFIX := "[font_size=16][color=#b2a78e]"
const SUFFIX := "[/color][/font_size]"
const TIP_W := 420.0
const FORTIFIED_SITES := ["keep", "mage_tower", "city"]
const RICH_TIP := preload("res://scripts/ui/rich_tip.gd")

static var enabled: bool = _load_enabled()
static var _voci: Dictionary = {}
static var _loaded := false
static var _strip: RegEx = null


static func _load_enabled() -> bool:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS) != OK:
		return true
	return bool(cf.get_value("ui", "explain", true))


static func set_enabled(on: bool) -> void:
	enabled = on
	var cf := ConfigFile.new()
	cf.load(SETTINGS)
	cf.set_value("ui", "explain", on)
	cf.save(SETTINGS)


static func voci() -> Dictionary:
	if not _loaded:
		_loaded = true
		var txt := FileAccess.get_file_as_string(PATH)
		var d = JSON.parse_string(txt) if txt != "" else null
		if d is Dictionary and d.get("voci") is Dictionary:
			_voci = d.voci
	return _voci


static func has(key: String) -> bool:
	return voci().has(key)


static func nome(key: String) -> String:
	return str(voci().get(key, {}).get("nome", key))


static func testo(key: String) -> String:
	return str(voci().get(key, {}).get("testo", ""))


## Una riga del blocco: «Nome: spiegazione» (senza a capo).
static func line(key: String, label := "") -> String:
	if not has(key):
		return ""
	return PREFIX + "[b]%s[/b]: %s" % [label if label != "" else nome(key), testo(key)] + SUFFIX


## Blocco di spiegazioni (righe separate da \n), vuoto se l'impostazione è su No.
static func block(keys: Array, limit := 12) -> String:
	if not enabled:
		return ""
	var seen := {}
	var out: Array = []
	for k in keys:
		var key := str(k)
		if seen.has(key) or not has(key):
			continue
		seen[key] = true
		out.append(line(key))
		if out.size() >= limit:
			break
	return "\n".join(out)


## Aggiunge il blocco a un testo, se c'è qualcosa da spiegare.
static func append(text: String, keys: Array, limit := 12) -> String:
	var b := block(keys, limit)
	if b == "":
		return text
	return text + ("\n" if text != "" else "") + b


# ------------------------------------------------------------------ chiavi

## Chiave del glossario per un'abilità del nemico ("summon:brown" -> "summon").
static func ability_key(ab: String) -> String:
	var base := ab.split(":")[0]
	match base:
		"resist_phys", "resist_fire", "resist_ice":
			return base
		"rep_on_defeat":
			return "rep_on_defeat"
	return base


## Voci che spiegano un nemico: abilità, resistenze, elementi degli attacchi, attacchi multipli.
## `e` può essere la definizione (MKDB.enemies) o la voce di combattimento (MKCombat.entry).
static func enemy_keys(e: Dictionary, site := "") -> Array:
	var out: Array = []
	var ab: Array = e.get("abilities", [])
	for a in ab:
		var k := ability_key(str(a))
		if k == "faction_reward":
			continue
		if k == "fortified" and site in FORTIFIED_SITES and not "unfortified" in ab:
			out.append("double_fortified")
		out.append(k)
	if site in FORTIFIED_SITES and not "unfortified" in ab and not "fortified" in ab:
		out.append("fortified_site")
	if e.get("site_fort", false) and not "fortified" in ab:
		out.append("fortified_site")
	var res: Array = e.get("resist", [])
	for r in res:
		out.append("resist_" + str(r))
	if "fire" in res and "ice" in res:
		out.append("resist_fire_ice")
	if int(e.get("rep", 0)) != 0:
		out.append("rep_on_defeat")
	var atk: Array = e.get("attacks", [])
	for a in atk:
		var el := str(a.get("elem_override", a.get("elem", "phys")))
		if el != "phys":
			out.append("attack_" + el)
	if atk.size() > 1:
		out.append("multiple_attacks")
	return out


## Voci che compaiono nel testo (carte, Unità, Abilità): cerca le parole chiave del glossario.
static func scan(text: String, limit := 4) -> Array:
	var t := strip(text).to_lower()
	if t == "":
		return []
	var out: Array = []
	# le voci più specifiche consumano il testo (Fuoco Freddo prima di «di Fuoco»)
	for key in ["elem_cold", "resist_phys", "resist_fire", "resist_ice", "arcane_immunity"]:
		for w in voci().get(key, {}).get("cerca", []):
			if t.contains(str(w)):
				if not key in out:
					out.append(key)
				t = t.replace(str(w), " ")
	for key in voci():
		if key in out:
			continue
		for w in voci()[key].get("cerca", []):
			if str(w) != "" and t.contains(str(w)):
				out.append(key)
				break
	return out.slice(0, limit)


## Voci per un'Unità: resistenze, stato (ferita / esausta) e parole chiave delle sue Abilità.
static func unit_keys(d: Dictionary, state := "") -> Array:
	var out: Array = []
	var res: Array = d.get("resist", [])
	for r in res:
		out.append("resist_" + str(r))
	if not res.is_empty():
		out.append("unit_resist")
	if "fire" in res and "ice" in res:
		out.append("resist_fire_ice")
	match state:
		"Ferita":
			out.append("unit_wounded")
		"Esaurita":
			out.append("unit_exhausted")
	var txt := ""
	for ab in d.get("abilities", []):
		txt += " " + str(ab.get("text_it", ""))
	for k in scan(txt, 4):
		out.append(k)
	return out


## Righe del glossario per un'Unità: resistenze (regola delle Unità), stato e parole chiave.
static func unit_block(d: Dictionary, state := "") -> String:
	if not enabled:
		return ""
	var keys := unit_keys(d, state)
	var res: Array = d.get("resist", [])
	for r in res:
		keys.erase("resist_" + str(r))
	var lines: Array = []
	if not res.is_empty():
		keys.erase("unit_resist")
		lines.append(PREFIX + "[b]%s[/b]: %s" % [", ".join(_names(res)), testo("unit_resist")] + SUFFIX)
	var b := block(keys, 6)
	if b != "":
		lines.append(b)
	return "\n".join(lines)


static func _names(res: Array) -> Array:
	var out: Array = []
	for r in res:
		out.append(nome("resist_" + str(r)))
	return out


## Voci per un esagono: terreno, sito, mura, nemici scatenati.
static func hex_keys(h: Dictionary, nwall := 0) -> Array:
	var out: Array = []
	var t := str(h.get("t", ""))
	if t != "":
		out.append("terrain_" + t)
	var site := str(h.get("site", ""))
	var sk := site
	if site in ["ruin", "ancient_ruins"]:
		sk = "ruins"
	elif site == "magical_glade":
		sk = "glade"
	elif site == "crystal_mine":
		sk = "mine"
	elif site == "rampaging":
		sk = "orcs"
	if sk != "":
		out.append("site_" + sk)
	if site in FORTIFIED_SITES and not h.get("burned", false):
		out.append("fortified_site")
	if site in ["dungeon", "tomb"]:
		out.append("night_rules")
	if nwall > 0:
		out.append("site_walls")
	if h.get("rampage", false) and not h.get("enemies", []).is_empty():
		out.append("rampaging")
	return out


# ------------------------------------------------------------------ suggerimenti a capo

static func strip(text: String) -> String:
	if _strip == null:
		_strip = RegEx.new()
		_strip.compile("\\[[^\\]]*\\]")
	return _strip.sub(text, "", true)


## Imposta un suggerimento in BBCode che va a capo (largo al massimo TIP_W).
static func set_tip(ctrl: Control, text: String) -> void:
	ctrl.tooltip_text = text
	if text != "" and ctrl.get_script() == null:
		ctrl.set_script(RICH_TIP)
		ctrl.tooltip_text = text


## Solo la spiegazione (riga attenuata), per i suggerimenti che mostrano già il nome.
static func explain(key: String) -> String:
	if not enabled or testo(key) == "":
		return ""
	return PREFIX + testo(key) + SUFFIX


## Nodo del suggerimento personalizzato (usato da rich_tip.gd): il riquadro è quello del tema (TooltipPanel).
static func tip_node(text: String) -> Control:
	MKUI.init_fonts()
	var r := MKUI.rich(18)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.text = text
	# larghezza: quella della riga più lunga, al massimo TIP_W
	var w := 40.0
	for ln in strip(text).split("\n"):
		var sz := MKUI.font_body.get_string_size(ln, HORIZONTAL_ALIGNMENT_LEFT, -1, 18)
		w = maxf(w, sz.x + 8)
	r.custom_minimum_size = Vector2(minf(w, TIP_W), 0)
	return r
