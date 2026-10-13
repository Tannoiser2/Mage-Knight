class_name MKHud
extends RefCounted
## Aiutanti statici per l'HUD della partita: immagini di carte/unità/nemici/abilità, testi italiani
## (elementi, abilità dei nemici, tipi d'attacco), piccoli widget (pallini di mana, distintivi, dadi).

const ELEM_IT := {"phys": "fisico", "fire": "di Fuoco", "ice": "di Ghiaccio", "cold": "di Fuoco-Ghiaccio"}
const ELEM_SHORT := {"phys": "", "fire": "Fuoco", "ice": "Ghiaccio", "cold": "Fuoco-Ghiaccio"}
const ELEM_COL := {"phys": Color("#d8cdb5"), "fire": Color("#ff7a3a"), "ice": Color("#6fc3ff"), "cold": Color("#c58cff")}
const KIND_IT := {"melee": "Attacco", "ranged": "Attacco a distanza", "siege": "Attacco d'assedio"}
const ABIL_IT := {
	"fortified": ["Fortificato", "Solo gli attacchi d'Assedio lo colpiscono nella fase a distanza."],
	"unfortified": ["Mai fortificato", "Non è fortificato nemmeno nei siti."],
	"swift": ["Rapido", "Per bloccarlo serve il doppio del Blocco."],
	"brutal": ["Brutale", "Il danno non bloccato è raddoppiato."],
	"poison": ["Velenoso", "Ogni Ferita all'eroe ne aggiunge una negli scarti; un'unità ferita riceve 2 Ferite."],
	"paralyze": ["Paralizzante", "Un'unità ferita è distrutta; se l'eroe è ferito scarta le carte non-Ferita."],
	"summon": ["Evocatore", "In fase di blocco evoca un nemico che attacca al suo posto."],
	"defend": ["Difensore", "Quando attacchi, aggiunge il suo valore all'Armatura di un nemico attaccato (anche se stesso), una volta per combattimento."],
	"vampiric": ["Vampirico", "Ogni Ferita che infligge (all'eroe o a un'Unità) gli dà Armatura +1 per il resto del combattimento."],
	"elusive": ["Elusivo", "Usa l'Armatura più alta; nella fase di Attacco quella più bassa se tutti i suoi attacchi sono stati bloccati."],
	"cumbersome": ["Ingombrante", "Nella fase di Blocco puoi spendere Movimento: ogni punto riduce di 1 il suo attacco (a 0 conta come bloccato)."],
	"arcane_immunity": ["Immunità arcana", "Ignora gli effetti non di attacco/blocco."],
	"assassinate": ["Assassinio", "Il suo danno non si può assegnare alle unità."],
	"faction_reward": ["Fazione", "Nemico di fazione di Shades of Tezla: conta solo negli scenari delle fazioni (non usati qui)."],
}
const RESIST_IT := {"phys": "Resistenza fisica", "fire": "Resistenza al Fuoco", "ice": "Resistenza al Ghiaccio"}
const COLOR_IT := {"red": "rosso", "blue": "blu", "green": "verde", "white": "bianco", "gold": "oro", "black": "nero"}
## colours of the enemy token backs
const ENEMY_COLOR_IT := {"green": "verde", "gray": "grigio", "brown": "marrone", "violet": "viola", "red": "rosso", "white": "bianco"}
const PHASE_IT := {"ranged": "Distanza / Assedio", "block": "Blocco", "damage": "Danni", "attack": "Attacco", "end": "Fine"}
const PHASES := ["ranged", "block", "damage", "attack"]


static func res(p: String) -> String:
	if p == "":
		return ""
	if p.begins_with("res://") or p.begins_with("/"):
		return p
	return "res://" + p


static func tex_of(p: String) -> Texture2D:
	var r := res(p)
	if r == "" or not MKUI.exists(r):
		return null
	return MKUI.tex(r)


## Immagine di una carta (id carta o istanza "march#3").
static func card_img(eng, iid: String) -> String:
	var id := iid.split("#")[0]
	var c: Dictionary = MKDB.cards.get(id, {})
	var p := str(c.get("img", ""))
	if p == "":
		p = "assets/cards/%s.webp" % id
	return res(p)


static func card_def(iid: String) -> Dictionary:
	return MKDB.cards.get(iid.split("#")[0], {})


static func card_name(iid: String) -> String:
	var c := card_def(iid)
	return str(c.get("name_it", iid.split("#")[0]))


static func back_img(type: String) -> String:
	match type:
		"aa":
			return "res://assets/cards/back_aa.webp"
		"spell":
			return "res://assets/cards/back_spell.webp"
		"artifact":
			return "res://assets/cards/back_artifact.webp"
	return "res://assets/cards/back_action.webp"


static func unit_img(id: String) -> String:
	var u: Dictionary = MKDB.units.get(id, {})
	var p := str(u.get("img", ""))
	if p == "":
		p = "assets/cards/unit_%s.webp" % id
	return res(p)


static func skill_img(id: String) -> String:
	var u: Dictionary = MKDB.skills.get(id, {})
	var p := str(u.get("img", ""))
	if p == "":
		p = "assets/skills/%s.webp" % id
	return res(p)


static func tactic_img(id: String) -> String:
	var u: Dictionary = MKDB.tactics.get(id, {})
	var p := str(u.get("img", ""))
	if p == "":
		p = "assets/cards/tactic_%s.webp" % id
	return res(p)


static func enemy_img(type: String) -> String:
	var e: Dictionary = MKDB.enemies.get(type, {})
	var p := str(e.get("img", ""))
	if p == "":
		p = "assets/enemies/%s.webp" % type
	return res(p)


static func enemy_back(color: String) -> String:
	return "res://assets/enemies/back_%s.webp" % color


static func hero_token(hero: String) -> String:
	return MKUI.first([MKUI.asset("hero_token_" + hero), "res://assets/tokens/hero_%s_token.webp" % hero])


static func hero_card(hero: String) -> String:
	return MKUI.first([MKUI.asset("hero_card_" + hero), "res://assets/tokens/hero_%s_card.webp" % hero])


## Testo leggibile di una carta (base / potenziata).
static func card_text(iid: String) -> String:
	var c := card_def(iid)
	var tx = c.get("text_it", {})
	var out := ""
	var b := ""
	var pw := ""
	if tx is Dictionary:
		b = str(tx.get("basic", ""))
		pw = str(tx.get("powered", ""))
	elif tx is String:
		b = tx
	if b == "" and c.has("basic"):
		b = MKEffects.describe_list(c.get("basic", []))
	if pw == "" and c.has("powered"):
		pw = MKEffects.describe_list(c.get("powered", []))
	if b != "":
		out += "[b]Base:[/b] " + b
	if pw != "":
		var pn := str(c.get("name_powered_it", ""))
		out += "\n[b]Potenziata%s:[/b] %s" % [(" (" + pn + ")") if pn != "" else "", pw]
	return out


static func elem_col(e: String) -> Color:
	return ELEM_COL.get(e, Color.WHITE)


## "melee:fire" -> "Attacco di Fuoco"
static func attack_key_it(k: String) -> String:
	var p := k.split(":")
	var kind: String = p[0]
	var el: String = p[1] if p.size() > 1 else "phys"
	var s: String = KIND_IT.get(kind, kind)
	if el != "phys":
		s += " " + ELEM_IT.get(el, el)
	return s


static func block_key_it(el: String) -> String:
	return "Blocco" + ("" if el == "phys" else " " + ELEM_IT.get(el, el))


# ------------------------------------------------------------------ widget

## Pallino di mana/cristallo con un numero dentro (o vuoto).
static func pip(color: String, n := -1, sz := 26, crystal := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(sz, sz)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	var col: Color = MKUI.MANA_COL.get(color, Color.GRAY)
	c.tooltip_text = ("Cristallo " if crystal else "Mana ") + COLOR_IT.get(color, color) + ((": %d" % n) if n >= 0 else "")
	c.draw.connect(func():
		var r := sz / 2.0
		var ctr := Vector2(r, r)
		if crystal:
			var pts := PackedVector2Array([ctr + Vector2(0, -r), ctr + Vector2(r * 0.85, -r * 0.2), ctr + Vector2(r * 0.55, r), ctr + Vector2(-r * 0.55, r), ctr + Vector2(-r * 0.85, -r * 0.2)])
			c.draw_colored_polygon(pts, col)
			var pl := pts.duplicate()
			pl.append(pts[0])
			c.draw_polyline(pl, Color(0, 0, 0, 0.8), 1.5, true)
		else:
			c.draw_circle(ctr, r, Color(0, 0, 0, 0.7))
			c.draw_circle(ctr, r - 2, col)
			c.draw_arc(ctr, r - 1, 0, TAU, 32, MKUI.GOLD_DARK, 1.5, true)
		if n >= 0:
			var f := MKUI.font_bold
			var txt := str(n)
			var fs := int(sz * 0.62)
			var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
			var tc := Color.BLACK if color in ["white", "gold"] else Color.WHITE
			c.draw_string_outline(f, ctr + Vector2(-ts.x / 2, ts.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 3, Color(1 - tc.r, 1 - tc.g, 1 - tc.b, 0.6))
			c.draw_string(f, ctr + Vector2(-ts.x / 2, ts.y * 0.32), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc))
	return c


## Dado della Riserva (immagine del dado colorata o quadrato).
static func die(color: String, taken: bool, sz := 46) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(sz, sz)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	var col: Color = MKUI.MANA_COL.get(color, Color.GRAY)
	c.tooltip_text = "Dado %s%s" % [COLOR_IT.get(color, color), " (preso)" if taken else ""]
	c.draw.connect(func():
		var a := 0.35 if taken else 1.0
		var r := Rect2(Vector2(3, 3), Vector2(sz - 6, sz - 6))
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(col, a)
		sb.set_corner_radius_all(8)
		sb.border_color = Color(MKUI.GOLD_LIGHT if not taken else Color("#555"), a)
		sb.set_border_width_all(2)
		sb.shadow_color = Color(0, 0, 0, 0.5 * a)
		sb.shadow_size = 3
		c.draw_style_box(sb, r)
		var dot := Color(0, 0, 0, 0.55 * a) if color in ["white", "gold"] else Color(1, 1, 1, 0.75 * a)
		var ctr := r.get_center()
		var o := sz * 0.2
		for d in [Vector2(-o, -o), Vector2(o, o), Vector2(0, 0), Vector2(o, -o), Vector2(-o, o)]:
			c.draw_circle(ctr + d, sz * 0.06, dot)
		if taken:
			c.draw_line(r.position + Vector2(6, 6), r.end - Vector2(6, 6), Color(0.9, 0.2, 0.2, 0.8), 3)
	)
	return c


## Piccolo riquadro "etichetta: valore".
static func stat(label: String, value: String, col := MKUI.BONE, tip := "") -> Control:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", -4)
	v.tooltip_text = tip
	v.mouse_filter = Control.MOUSE_FILTER_PASS
	var a := MKUI.label(label, 15, MKUI.MUTED, MKUI.font_body)
	a.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(a)
	var b := MKUI.label(value, 24, col, MKUI.font_bold)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	v.add_child(b)
	return v


## Bottone compatto per l'HUD.
static func btn(text: String, cb: Callable, w := 0.0, h := 44.0, primary := false, size := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_size_override("font_size", size)
	b.clip_text = false
	if primary:
		MKUI.primary(b)
	b.pressed.connect(cb)
	return b


## Immagine con cornice; tooltip opzionale. Restituisce un TextureRect.
static func image(path: String, sz: Vector2, tip := "") -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex_of(path)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.tooltip_text = tip
	r.mouse_filter = Control.MOUSE_FILTER_PASS
	return r


static func sep_v(h := 30.0) -> Control:
	var c := ColorRect.new()
	c.color = Color(MKUI.GOLD_DARK, 0.5)
	c.custom_minimum_size = Vector2(1, h)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


## Descrizione delle abilità di un nemico (lista di [nome, spiegazione]).
static func enemy_traits(e: Dictionary) -> Array:
	var out := []
	for a in e.get("abilities", []):
		var key := str(a)
		var base := key.split(":")[0]
		var d: Array = ABIL_IT.get(base, [base.capitalize(), ""])
		var nm: String = d[0]
		if base == "summon" and e.get("summon", "") != "":
			nm += " (%s)" % ENEMY_COLOR_IT.get(str(e["summon"]), str(e["summon"]))
		if base == "defend" and e.has("defend"):
			nm += " %d" % int(e["defend"])
		out.append([nm, d[1]])
	for r in e.get("resist", []):
		out.append([RESIST_IT.get(str(r), "Resistenza " + str(r)), "Gli attacchi di questo tipo valgono la metà."])
	return out


## Testo per il suggerimento di un nemico (definizione da enemies.json).
static func enemy_tip(type: String) -> String:
	var d: Dictionary = MKDB.enemies.get(type, {})
	if d.is_empty():
		return ""
	var at := []
	for a in d.get("attacks", []):
		at.append("%d %s" % [int(a.get("n", 0)), ELEM_SHORT.get(str(a.get("elem", "phys")), "")])
	var tr := []
	for x in enemy_traits(d):
		tr.append(x[0])
	var arm := str(int(d.get("armor", 0)))
	if int(d.get("elusive_armor", 0)) > 0:
		arm = "%d/%d" % [int(d.get("elusive_armor", 0)), int(d.get("armor", 0))]
	var s := "%s · Armatura %s · Attacco %s · Fama %d" % [d.get("name_it", type), arm, " + ".join(at) if not at.is_empty() else "—", int(d.get("fame", 0))]
	if int(d.get("rep", 0)) != 0:
		s += " · Reputazione %+d se sconfitto" % int(d.get("rep", 0))
	if not tr.is_empty():
		s += " · " + ", ".join(tr)
	return s
