class_name MKMenu
extends Control
## Menu principale: titolo, Nuova partita (scenario, posti degli eroi Umano/IA e livello dell'IA),
## Gioca online (segnaposto per la seconda ondata), Regole (segnaposto), Esci.
## Sullo sfondo gira lentamente il tavolo 3D con una mappa di prova.

## Gruppi degli scenari nella schermata Nuova partita (data/scenarios.json, campo "group").
const GROUPS := [["intro", "Introduttivi"], ["competitive", "Competitivi"], ["coop", "Cooperativi"], ["solo", "Solitario"]]
const TYPE_IT := {"intro": "Introduttivo", "competitive": "Competitivo", "coop": "Cooperativo", "solo": "Solitario"}
const HEROES := ["arythea", "goldyx", "norowas", "tovak", "wolfhawk", "krang", "braevalar"]
const HERO_SUB := {
	"arythea": "la Signora del Sangue", "goldyx": "il Drago Cristallino", "norowas": "il Signore degli Elfi",
	"tovak": "il Cavaliere Nero", "wolfhawk": "la Cacciatrice (La Legione Perduta)", "krang": "lo Sciamano Orco (Krang)",
	"braevalar": "il Druido Mutaforma (Shades of Tezla)",
}
## Contenuti della partita (MKDB.CONTENT_SETS): tessere, nemici, carte, unità e rovine delle espansioni.
const CONTENTS := [
	{"id": "base", "n": "Base", "d": "Solo il gioco base."},
	{"id": "ll", "n": "+ La Legione Perduta", "d": "Tessere con Campo Profughi, Dedalo, Labirinto, Miniere Profonde e mura; nuovi nemici, carte, Unità e Rovine."},
	{"id": "tezla", "n": "+ Shades of Tezla", "d": "Come sopra, più i nemici di Shades of Tezla (Vampirico, Difensore…) nelle pile."},
]
const LEVELS := ["Facile", "Normale", "Difficile"]

var main
var scenario := 0
## Combattimento tra giocatori negli scenari competitivi (Conquista completa)
var pvp_on := true
var _pvp_row: Control
var content := 0
## posti: {on, hero, ai, level(1..3), name}
var seats := [
	{"on": true, "hero": "arythea", "ai": false, "level": 2, "name": "Giocatore 1"},
	{"on": false, "hero": "goldyx", "ai": true, "level": 2, "name": "Giocatore 2"},
	{"on": false, "hero": "norowas", "ai": true, "level": 2, "name": "Giocatore 3"},
	{"on": false, "hero": "tovak", "ai": true, "level": 2, "name": "Giocatore 4"},
]

var bg_table: MKTable3D
var page: Control
var msg: Label
var _scen_desc: RichTextLabel
var _content_desc: Label
var _seats_box: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if main != null and main.menu_state.has("seats"):
		scenario = int(main.menu_state["scenario"])
		seats = main.menu_state["seats"].duplicate(true)
		pvp_on = bool(main.menu_state.get("pvp", true))
		content = clampi(int(main.menu_state.get("content", 0)), 0, CONTENTS.size() - 1)
	_build_background()
	show_home()


func _exit_tree() -> void:
	_store()


func _store() -> void:
	if main != null:
		main.menu_state = {"scenario": scenario, "seats": seats.duplicate(true), "pvp": pvp_on, "content": content}


## Tavolo 3D di sfondo (non interattivo) che ruota piano, scurito ai bordi.
func _build_background() -> void:
	var holder := Node3D.new()
	holder.name = "BG3D"
	add_child(holder)
	bg_table = MKTable3D.new()
	bg_table.interactive = false
	bg_table.animate = false
	holder.add_child(bg_table)
	var st := _demo_state()
	bg_table.refresh(st)
	bg_table.slots_root.visible = false
	# la mappa sta a destra (a sinistra titolo e bottoni) e oscilla piano
	bg_table.rig.bounds = Rect2(-40, -40, 80, 80)
	bg_table.rig.set_home(Vector3(-1.5, MKTable3D.TH, -2.5), 15.0, 36.0, -28.0)
	bg_table.rig.reset(true)
	bg_table.rig.smooth = 2.0
	add_child(MKUI.vignette(0.92))
	# velo scuro a sinistra dietro al titolo e ai bottoni
	var veil := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.02, 0.04, 0.92))
	g.set_color(1, Color(0.03, 0.02, 0.04, 0.0))
	grad.gradient = g
	grad.fill_from = Vector2(0.0, 0.5)
	grad.fill_to = Vector2(1.0, 0.5)
	veil.texture = grad
	veil.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	veil.stretch_mode = TextureRect.STRETCH_SCALE
	veil.anchor_bottom = 1.0
	veil.anchor_right = 0.62
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)


## Stato per lo sfondo: dal motore se c'è, altrimenti la mappa di prova.
func _demo_state() -> Dictionary:
	return MKTableDemo.state(0)


var _t := 0.0

func _process(delta: float) -> void:
	_t += delta
	if bg_table != null and bg_table.rig != null:
		bg_table.rig.yaw = -28.0 + sin(_t * 0.12) * 10.0
		bg_table.rig.pitch = 36.0 + sin(_t * 0.07) * 4.0


func _clear_page() -> void:
	if page != null:
		page.queue_free()
		page = null


func _new_page() -> Control:
	_clear_page()
	page = Control.new()
	page.set_anchors_preset(Control.PRESET_FULL_RECT)
	page.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(page)
	return page


func _title_block(parent: Control, small := false) -> void:
	var vb := VBoxContainer.new()
	vb.position = Vector2(90, 70 if not small else 40)
	vb.add_theme_constant_override("separation", 0)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(vb)
	var t := MKUI.title("MAGE KNIGHT", 112 if not small else 64, MKUI.GOLD)
	t.add_theme_color_override("font_outline_color", Color("#1a0f05"))
	vb.add_child(t)
	var sub := MKUI.label("Il gioco da tavolo · adattamento digitale", 30 if not small else 22, Color("#d9cdb0"), MKUI.font_italic)
	vb.add_child(sub)
	var orn := MKUI.ornament(560 if not small else 380)
	vb.add_child(orn)


# ================================================================== pagina principale

func show_home() -> void:
	var p := _new_page()
	_title_block(p)
	var vb := VBoxContainer.new()
	vb.position = Vector2(96, 400)
	vb.add_theme_constant_override("separation", 16)
	p.add_child(vb)
	var items := []
	if MKController.has_save():
		items.append(["CONTINUA PARTITA", _on_continue, true])
	items.append(["NUOVA PARTITA", show_new_game, not MKController.has_save()])
	items.append(["GIOCA ONLINE", show_online, false])
	items.append(["REGOLE", show_rules, false])
	if not OS.has_feature("web"):
		items.append(["ESCI", func(): get_tree().quit(), false])
	for it in items:
		var b := MKUI.big_button(it[0], 460, it[2], 78)
		b.pressed.connect(it[1])
		vb.add_child(b)
	if MKController.has_save():
		var sl := MKUI.label(MKController.save_summary(), 19, Color("#cbbf9f"), MKUI.font_italic)
		vb.add_child(sl)
		vb.move_child(sl, 1)
	var gx := HBoxContainer.new()
	gx.add_theme_constant_override("separation", 10)
	gx.add_child(MKUI.label("Spiegazioni nei suggerimenti:", 20, MKUI.GOLD, MKUI.font_bold))
	var seg := _segmented(["Sì", "No"], 0 if MKGloss.enabled else 1, func(k): MKGloss.set_enabled(k == 0), 84)
	seg.tooltip_text = "Nei suggerimenti spiega cosa fanno abilità dei nemici, elementi, resistenze, terreni e siti."
	gx.add_child(seg)
	vb.add_child(gx)
	msg = MKUI.label("", 22, MKUI.RED, MKUI.font_bold)
	vb.add_child(msg)
	var credits := MKUI.label("Adattamento non ufficiale per uso personale · Mage Knight di Vlaada Chvátil · © WizKids · F11 schermo intero", 17, Color("#8a8070"))
	credits.anchor_top = 1.0
	credits.anchor_bottom = 1.0
	credits.offset_top = -50
	credits.offset_bottom = -20
	credits.offset_left = 96
	p.add_child(credits)


# ================================================================== nuova partita

## Scenari nell'ordine di data/scenarios.json.
static func scenario_ids() -> Array:
	var out: Array = []
	for id in MKDB.scenarios:
		out.append(str(id))
	if out.is_empty():
		out = ["first_recon", "solo_conquest", "coop_conquest", "full_conquest"]
	return out


func scenario_count() -> int:
	return scenario_ids().size()


func scenario_id(i: int) -> String:
	var ids := scenario_ids()
	return str(ids[clampi(i, 0, ids.size() - 1)])


func _scn(i := -1) -> Dictionary:
	return MKDB.scenarios.get(scenario_id(scenario if i < 0 else i), {})


func _scn_name(i: int) -> String:
	return str(_scn(i).get("name_it", scenario_id(i)))


func _players_it(r: Array) -> String:
	if int(r[1]) == 1:
		return "un solo eroe"
	if int(r[0]) == int(r[1]):
		return "%d eroi" % int(r[0])
	if int(r[1]) - int(r[0]) == 1:
		return "%d o %d eroi" % [int(r[0]), int(r[1])]
	return "da %d a %d eroi" % [int(r[0]), int(r[1])]


func _range_short(r: Array) -> String:
	return str(int(r[0])) if int(r[0]) == int(r[1]) else "%d–%d" % [int(r[0]), int(r[1])]


func _max_players() -> int:
	return clampi(int(_range()[1]), 1, seats.size())


func _pvp_possible() -> bool:
	var d := _scn()
	return str(d.get("group", "")) == "competitive" and _n_on() >= 2


func select_scenario(i: int) -> void:
	scenario = clampi(i, 0, scenario_count() - 1)
	_fit_seats()
	_refresh_new_game()


## Aggiunge il primo posto libero, se lo scenario lo consente (per i test e la tastiera).
func try_add_seat() -> bool:
	if _n_on() >= _max_players():
		return false
	for i in range(_max_players()):
		if not seats[i]["on"]:
			seats[i]["on"] = true
			_refresh_new_game()
			return true
	return false


func show_new_game() -> void:
	scenario = clampi(scenario, 0, scenario_count() - 1)
	var p := _new_page()
	_title_block(p, true)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MKUI.frame_style(0.9, 10))
	panel.position = Vector2(60, 178)
	panel.custom_minimum_size = Vector2(1800, 884)
	p.add_child(panel)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 22)
	panel.add_child(hb)
	# ---- colonna sinistra: elenco degli scenari raggruppati
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(500, 0)
	left.add_theme_constant_override("separation", 8)
	hb.add_child(left)
	left.add_child(MKUI.title("Scenario", 32, MKUI.GOLD))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(500, 800)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(sc)
	_scen_list = VBoxContainer.new()
	_scen_list.add_theme_constant_override("separation", 5)
	_scen_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_scen_list)
	hb.add_child(VSeparator.new())
	# ---- colonna destra: descrizione, opzioni, eroi
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(vb)
	_scen_title = MKUI.title("", 34, MKUI.GOLD_LIGHT)
	vb.add_child(_scen_title)
	_scen_desc = MKUI.rich(21)
	_scen_desc.custom_minimum_size = Vector2(1200, 84)
	vb.add_child(_scen_desc)
	var rrow := HBoxContainer.new()
	rrow.add_theme_constant_override("separation", 14)
	vb.add_child(rrow)
	var b_rules := Button.new()
	b_rules.text = "Regole complete dello scenario…"
	b_rules.custom_minimum_size = Vector2(330, 44)
	b_rules.add_theme_font_size_override("font_size", 19)
	b_rules.pressed.connect(_show_scenario_rules)
	rrow.add_child(b_rules)
	var pr := HBoxContainer.new()
	pr.add_theme_constant_override("separation", 10)
	pr.add_child(MKUI.label("Combattimento tra giocatori:", 20, MKUI.GOLD, MKUI.font_bold))
	pr.add_child(_segmented(["Sì", "No"], 0 if pvp_on else 1, func(k): pvp_on = k == 0, 84))
	_pvp_row = pr
	rrow.add_child(pr)
	vb.add_child(HSeparator.new())
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 14)
	vb.add_child(crow)
	crow.add_child(MKUI.title("Contenuti", 26, MKUI.GOLD))
	var cnames := []
	for c in CONTENTS:
		cnames.append(c["n"])
	var seg := _segmented(cnames, content, func(k):
		content = k
		_refresh_new_game(), 250)
	for k in seg.get_child_count():
		(seg.get_child(k) as Button).tooltip_text = CONTENTS[k]["d"]
	crow.add_child(seg)
	_content_desc = MKUI.label("", 16, Color("#cbbf9f"), MKUI.font_italic)
	_content_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_content_desc.custom_minimum_size = Vector2(260, 0)
	_content_desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crow.add_child(_content_desc)
	var erow := HBoxContainer.new()
	erow.add_theme_constant_override("separation", 16)
	vb.add_child(erow)
	erow.add_child(MKUI.title("Eroi", 30, MKUI.GOLD))
	_seat_note = MKUI.label("", 19, Color("#cbbf9f"), MKUI.font_italic)
	_seat_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_seat_note.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seat_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	erow.add_child(_seat_note)
	_seats_box = HBoxContainer.new()
	_seats_box.add_theme_constant_override("separation", 12)
	vb.add_child(_seats_box)
	msg = MKUI.label("", 22, MKUI.RED, MKUI.font_bold)
	vb.add_child(msg)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	vb.add_child(btns)
	var b_start := MKUI.big_button("INIZIA LA PARTITA", 440, true, 66)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_back := MKUI.big_button("INDIETRO", 260, false, 66)
	b_back.pressed.connect(show_home)
	btns.add_child(b_back)
	_fit_seats()
	_refresh_new_game()


var _scen_list: VBoxContainer
var _scen_title: Label
var _seat_note: Label


## Elenco degli scenari a sinistra, raggruppato.
func _build_scen_list() -> void:
	if _scen_list == null:
		return
	for c in _scen_list.get_children():
		c.queue_free()
	var ids := scenario_ids()
	for g in GROUPS:
		var any := false
		for i in ids.size():
			if str(MKDB.scenarios.get(ids[i], {}).get("group", "")) != g[0]:
				continue
			if not any:
				any = true
				var gl := MKUI.label(str(g[1]).to_upper(), 18, MKUI.GOLD, MKUI.font_bold)
				gl.add_theme_constant_override("line_spacing", 0)
				var m := MarginContainer.new()
				m.add_theme_constant_override("margin_top", 6)
				m.add_child(gl)
				_scen_list.add_child(m)
			_scen_list.add_child(_scen_button(i))


func _scen_button(i: int) -> Control:
	var d: Dictionary = _scn(i)
	var sel: bool = i == scenario
	var b := Button.new()
	b.custom_minimum_size = Vector2(480, 50)
	b.focus_mode = Control.FOCUS_NONE
	b.tooltip_text = str(d.get("short_it", ""))
	b.add_theme_stylebox_override("normal", MKUI.panel_style(MKUI.GOLD if sel else Color("#1a161c"), MKUI.GOLD_LIGHT if sel else Color("#4a3e2c"), 2, 5))
	b.add_theme_stylebox_override("hover", MKUI.panel_style(MKUI.GOLD_LIGHT if sel else Color("#2a2230"), MKUI.GOLD, 2, 5))
	b.add_theme_stylebox_override("pressed", MKUI.panel_style(MKUI.GOLD_DARK, MKUI.GOLD_LIGHT, 2, 5))
	b.pressed.connect(func(): select_scenario(i))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 14
	row.offset_right = -14
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(row)
	var nm := MKUI.label(str(d.get("name_it", scenario_id(i))), 21, MKUI.INK if sel else MKUI.BONE, MKUI.font_bold)
	nm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	nm.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	nm.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(nm)
	var r: Array = d.get("players", [1, 4])
	var pl := MKUI.label(_range_short(r) + (" eroe" if int(r[1]) == 1 else " eroi"), 18, MKUI.INK if sel else MKUI.MUTED, MKUI.font_italic)
	pl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(pl)
	return b


func _range() -> Array:
	var r: Array = _scn().get("players", [1, 4])
	return [int(r[0]), int(r[1])]


## Rispetta i limiti di giocatori dello scenario (i posti oltre il massimo si spengono).
func _fit_seats() -> void:
	var r := _range()
	for i in range(seats.size()):
		if i >= int(r[1]) and i > 0:
			seats[i]["on"] = false
	while _n_on() < int(r[0]):
		var added := false
		for i in range(mini(seats.size(), int(r[1]))):
			if not seats[i]["on"]:
				seats[i]["on"] = true
				added = true
				break
		if not added:
			break
	seats[0]["on"] = true
	if int(r[1]) == 1:
		seats[0]["ai"] = false


func _n_on() -> int:
	var n := 0
	for s in seats:
		if s["on"]:
			n += 1
	return n


func _refresh_new_game() -> void:
	var d: Dictionary = _scn()
	var r := _range()
	_build_scen_list()
	if _scen_title != null:
		_scen_title.text = str(d.get("name_it", scenario_id(scenario)))
	var rounds = d.get("rounds", 6)
	var rtxt := ""
	if rounds is Dictionary:
		var vals := {}
		for k in rounds:
			vals[int(rounds[k])] = true
		var rs: Array = vals.keys()
		rs.sort()
		rtxt = "%s round" % " o ".join(rs.map(func(x): return str(x)))
	else:
		rtxt = "%d round" % int(rounds)
	var typ := str(TYPE_IT.get(str(d.get("group", "")), ""))
	var pg := str(d.get("page", ""))
	var src := ("Manuale degli Scenari " + pg) if pg.begins_with("p") else ("Fonte: " + pg)
	var info := "%s · %s%s · %s · [color=#a59c8a]%s[/color]" % [typ, _players_it(r),
		" (anche in solitario)" if d.get("solo_variant", false) else "", rtxt, src]
	_scen_desc.text = "%s\n[i]%s[/i]" % [info, str(d.get("short_it", d.get("desc_it", "")))]
	if _pvp_row != null:
		_pvp_row.visible = _pvp_possible()
	if _content_desc != null:
		_content_desc.text = CONTENTS[content]["d"]
	if msg:
		msg.text = ""
	if _seat_note != null:
		var note := "Numero di eroi: %s." % _range_short(r)
		if int(r[1]) < seats.size():
			var ns: Array = []
			for i in range(int(r[1]), seats.size()):
				ns.append(str(i + 1))
			var lst: String = ns[0] if ns.size() == 1 else ", ".join(ns.slice(0, ns.size() - 1)) + " e " + ns[-1]
			note += " %s %s non %s in questo scenario." % ["Il posto" if ns.size() == 1 else "I posti", lst, "è disponibile" if ns.size() == 1 else "sono disponibili"]
		if str(d.get("group", "")) == "coop" and _n_on() == 4:
			note += " 4 eroi: variante del regolamento (p. 15, Nota 3)."
		if d.get("teams", {}) is Dictionary and d.get("teams", {}).has(str(_n_on())):
			note += " Con %d eroi: squadre Posti 1+2 contro Posti 3+4." % _n_on()
		_seat_note.text = note
	for c in _seats_box.get_children():
		c.queue_free()
	for i in range(seats.size()):
		_seats_box.add_child(_seat_card(i))


## Finestra con le regole complete dello scenario scelto.
func _show_scenario_rules() -> void:
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	page.add_child(layer)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MKUI.frame_style(0.97, 10))
	panel.position = Vector2(300, 120)
	panel.custom_minimum_size = Vector2(1320, 0)
	layer.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	panel.add_child(vb)
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1290, 700)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var r := MKUI.rich(22)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.text = MKScreens.scenario_text(scenario_id(scenario))
	sc.add_child(r)
	var b := MKUI.big_button("CHIUDI", 260, true, 60)
	b.pressed.connect(func(): layer.queue_free())
	vb.add_child(b)


func _seat_card(i: int) -> Control:
	var st: Dictionary = seats[i]
	var r := _range()
	var avail: bool = i < int(r[1])
	var on: bool = st["on"] and avail
	var hero: String = st["hero"]
	var col := MKUI.hero_col(hero)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(294, 312)
	var sb := MKUI.panel_style(Color(0.05, 0.04, 0.06, 0.92 if on else 0.55), col if on else Color("#3a3438"), 3 if on else 1, 8, 10)
	card.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	card.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var lab := MKUI.label("Posto %d" % (i + 1), 21, MKUI.MUTED, MKUI.font_bold)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lab)
	if i > 0 and avail:
		var tog := Button.new()
		tog.text = "RIMUOVI" if on else "AGGIUNGI"
		tog.custom_minimum_size = Vector2(118, 40)
		var can := (on and _n_on() > int(r[0])) or (not on and _n_on() < int(r[1]))
		tog.disabled = not can
		if not can:
			tog.tooltip_text = "Lo scenario richiede almeno %d eroi" % int(r[0]) if on else "Lo scenario consente al massimo %d eroi" % int(r[1])
		tog.pressed.connect(func():
			seats[i]["on"] = not seats[i]["on"]
			_refresh_new_game())
		head.add_child(tog)
	if not avail:
		var off := MKUI.label("Non disponibile\nin questo scenario\n(al massimo %s)" % _players_it([int(r[1]), int(r[1])]), 21, Color("#6a6260"), MKUI.font_italic)
		off.size_flags_vertical = Control.SIZE_EXPAND_FILL
		off.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		off.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vb.add_child(off)
		return card
	if not on:
		var off2 := MKUI.label("Posto libero", 24, Color("#6a6260"), MKUI.font_italic)
		off2.size_flags_vertical = Control.SIZE_EXPAND_FILL
		off2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		off2.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vb.add_child(off2)
		return card
	# eroe: ◀ stemma + nome ▶
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 6)
	vb.add_child(hrow)
	var bl := Button.new()
	bl.text = "◀"
	bl.custom_minimum_size = Vector2(46, 88)
	bl.pressed.connect(func(): _cycle(i, -1))
	hrow.add_child(bl)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	hrow.add_child(mid)
	var emb := _hero_emblem(hero)
	emb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	mid.add_child(emb)
	var br := Button.new()
	br.text = "▶"
	br.custom_minimum_size = Vector2(46, 88)
	br.pressed.connect(func(): _cycle(i, 1))
	hrow.add_child(br)
	var nm := MKUI.title(MKUI.HERO_NAME.get(hero, hero).to_upper(), 26, Color.WHITE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	var sub := MKUI.label(HERO_SUB.get(hero, ""), 16, Color("#cbbf9f"), MKUI.font_italic)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(270, 0)
	vb.add_child(sub)
	var solo: bool = int(r[1]) == 1
	var ai_row := _segmented(["UMANO", "IA"], 1 if st["ai"] else 0, func(k):
		seats[i]["ai"] = k == 1
		_refresh_new_game(), 134)
	if solo:
		# in solitario l'eroe è guidato da una persona: si può scegliere solo UMANO
		(ai_row.get_child(1) as Button).disabled = true
		(ai_row.get_child(1) as Button).tooltip_text = "In solitario l'eroe è guidato da te"
	vb.add_child(ai_row)
	var lv := _segmented(LEVELS, int(st["level"]) - 1, func(k): seats[i]["level"] = k + 1, 88)
	for b2 in lv.get_children():
		(b2 as Button).add_theme_font_size_override("font_size", 17)
	lv.visible = st["ai"]
	vb.add_child(lv)
	return card


## Stemma dell'eroe: ritratto se c'è un'immagine (assets/heroes/<id>.webp o manifesto), altrimenti
## un medaglione col colore dell'eroe e l'iniziale.
func _hero_emblem(hero: String) -> Control:
	var p := MKUI.first([MKUI.asset("hero_token_" + hero), "res://assets/tokens/hero_%s_token.webp" % hero])
	if p != "":
		var r := MKUI.icon_rect(MKUI.tex(p), Vector2(96, 96))
		return r
	var col := MKUI.hero_col(hero)
	var c := Control.new()
	c.custom_minimum_size = Vector2(96, 96)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var initial: String = str(MKUI.HERO_NAME.get(hero, hero)).left(1)
	c.draw.connect(func():
		var ctr := Vector2(48, 48)
		c.draw_circle(ctr, 46, MKUI.GOLD_DARK)
		c.draw_circle(ctr, 42, col.darkened(0.35))
		c.draw_circle(ctr, 34, col)
		c.draw_arc(ctr, 38, 0, TAU, 48, MKUI.GOLD, 2.0, true)
		var f := MKUI.font_title
		var sz := f.get_string_size(initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 44)
		c.draw_string_outline(f, ctr + Vector2(-sz.x / 2, sz.y / 2 - 10), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, 6, Color(0, 0, 0, 0.8))
		c.draw_string(f, ctr + Vector2(-sz.x / 2, sz.y / 2 - 10), initial, HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color.WHITE))
	return c


## Eroe successivo/precedente non già usato da un altro posto attivo.
func _cycle(i: int, k: int) -> void:
	var cur: String = seats[i]["hero"]
	var idx := HEROES.find(cur)
	for n in range(HEROES.size()):
		idx = (idx + k + HEROES.size()) % HEROES.size()
		var cand: String = HEROES[idx]
		var used := false
		for j in range(seats.size()):
			if j != i and seats[j]["on"] and seats[j]["hero"] == cand:
				used = true
		if used:
			continue
		# chi aveva quell'eroe in un posto spento lo cede
		for j in range(seats.size()):
			if j != i and seats[j]["hero"] == cand:
				seats[j]["hero"] = cur
		seats[i]["hero"] = cand
		break
	_refresh_new_game()


func _on_continue() -> void:
	if main != null and not main.resume_game():
		MKController.clear_save()
		show_home()
		if msg:
			msg.text = "Impossibile riprendere la partita salvata."


## Configurazione che la schermata Nuova partita avvierebbe (usata anche dalla sala online).
func current_config() -> Dictionary:
	return config()


## Configurazione per il motore (SPEC §4).
func config() -> Dictionary:
	var pl := []
	for i in range(seats.size()):
		var st: Dictionary = seats[i]
		if not st["on"] or i >= _max_players():
			continue
		var nm: String = MKUI.HERO_NAME.get(st["hero"], st["hero"])
		if st["ai"]:
			nm += " (IA)"
		pl.append({"hero": st["hero"], "ctrl": "ai" if st["ai"] else "human", "ai_level": int(st["level"]), "name": nm})
	var opts := {"content": CONTENTS[content]["id"]}
	if _pvp_possible():
		opts["pvp"] = pvp_on
	return {"scenario": scenario_id(scenario), "seed": 1 + randi() % 2000000000, "players": pl,
		"options": opts}


func _on_start() -> void:
	var cfg := config()
	var heroes := {}
	var humans := 0
	for p in cfg["players"]:
		if heroes.has(p["hero"]):
			msg.text = "Ogni eroe può essere scelto una volta sola."
			return
		heroes[p["hero"]] = true
		if p["ctrl"] == "human":
			humans += 1
	var r := _range()
	if cfg["players"].size() < int(r[0]) or cfg["players"].size() > int(r[1]):
		msg.text = "Questo scenario richiede %s." % _players_it(r)
		return
	if humans == 0:
		msg.text = "Serve almeno un eroe guidato da una persona (UMANO)."
		return
	_store()
	if main != null:
		main.start_game(cfg)


# ================================================================== online e regole (segnaposto)

func _info_page(title: String, body: String) -> void:
	var p := _new_page()
	_title_block(p, true)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MKUI.frame_style(0.92, 10))
	panel.position = Vector2(80, 200)
	panel.custom_minimum_size = Vector2(1100, 0)
	p.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	panel.add_child(vb)
	vb.add_child(MKUI.title(title, 44, MKUI.GOLD))
	var r := MKUI.rich(23)
	r.custom_minimum_size = Vector2(1060, 0)
	r.text = body
	vb.add_child(r)
	var b := MKUI.big_button("INDIETRO", 280)
	b.pressed.connect(show_home)
	vb.add_child(b)


func show_online() -> void:
	var lp := "res://scripts/net/online_lobby.gd"
	if ResourceLoader.exists(lp):
		var sc = load(lp)
		if sc is Script and (sc as Script).can_instantiate():
			_store()
			var lobby_node = sc.new()
			if lobby_node is Control:
				if "cfg" in lobby_node:
					lobby_node.set("cfg", current_config())
				if main != null:
					main.show_screen(lobby_node)
				else:
					add_child(lobby_node)
				return
	_info_page("Gioca online",
		"Il gioco online non è ancora disponibile in questa versione.\n\n" +
		"Chi crea la stanza sceglierà scenario ed eroi; gli amici entreranno con un codice. " +
		"I posti liberi saranno guidati dall'IA. Tutti i dispositivi eseguono la stessa partita in parallelo " +
		"(stesso seme, stesse azioni), sincronizzati tramite Firebase.")


func show_rules() -> void:
	var p := _new_page()
	_title_block(p, true)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MKUI.frame_style(0.92, 10))
	panel.position = Vector2(80, 180)
	panel.custom_minimum_size = Vector2(1240, 0)
	p.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	vb.add_child(MKUI.title("Regole in breve", 40, MKUI.GOLD))
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(1200, 700)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var r := MKUI.rich(21)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.text = MKScreens.scenario_text(scenario_id(scenario)) + "\n\n" + MKScreens.RULES_IT
	sc.add_child(r)
	var b := MKUI.big_button("INDIETRO", 280)
	b.pressed.connect(show_home)
	vb.add_child(b)


# ================================================================== widget

func _segmented(items: Array, cur: int, cb: Callable, w := 200) -> HBoxContainer:
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	var btns := []
	for k in range(items.size()):
		var b := Button.new()
		b.text = items[k]
		b.custom_minimum_size = Vector2(w, 50)
		b.focus_mode = Control.FOCUS_NONE
		b.add_theme_font_size_override("font_size", 21)
		hb.add_child(b)
		btns.append(b)
	var paint := func(sel: int):
		for k in range(btns.size()):
			var on: bool = k == sel
			btns[k].add_theme_stylebox_override("normal", MKUI.panel_style(MKUI.GOLD if on else Color("#1a161c"), MKUI.GOLD_LIGHT if on else Color("#4a3e2c"), 2, 5))
			btns[k].add_theme_stylebox_override("hover", MKUI.panel_style(MKUI.GOLD_LIGHT if on else Color("#2a2230"), MKUI.GOLD, 2, 5))
			btns[k].add_theme_color_override("font_color", MKUI.INK if on else MKUI.BONE)
			btns[k].add_theme_color_override("font_hover_color", MKUI.INK if on else MKUI.GOLD_LIGHT)
	for k in range(btns.size()):
		btns[k].pressed.connect(func():
			paint.call(k)
			cb.call(k))
	paint.call(cur)
	return hb
