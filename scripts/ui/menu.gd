class_name MKMenu
extends Control
## Menu principale: titolo, Nuova partita (scenario, posti degli eroi Umano/IA e livello dell'IA),
## Gioca online (segnaposto per la seconda ondata), Regole (segnaposto), Esci.
## Sullo sfondo gira lentamente il tavolo 3D con una mappa di prova.

const SCENARIOS := [
	{"id": "first_recon", "n": "La Prima Ricognizione", "players": [1, 4],
		"d": "Partita introduttiva per imparare le regole: esplorate le terre, affrontate i primi predoni orchi e scoprite una città. Si può giocare da soli o con altri eroi."},
	{"id": "solo_conquest", "n": "Conquista in Solitario", "players": [1, 1],
		"d": "Un solo eroe contro le città dell'Impero, mentre il Giocatore Neutrale scandisce il ritmo dei round. Conquista le città prima che il tempo finisca."},
	{"id": "coop_conquest", "n": "Cooperazione Totale", "players": [2, 3],
		"d": "2 o 3 eroi alleati, umani o guidati dall'IA, uniscono le forze per conquistare insieme le città entro il limite di round, con il Giocatore Neutrale che scandisce il tempo."},
	{"id": "full_conquest", "n": "Conquista Totale", "players": [2, 4],
		"d": "Da 2 a 4 eroi in competizione per la Fama: si esplora, si combatte e si conquistano le città. Alla fine vince chi ha più Fama (con i titoli)."},
]
const HEROES := ["arythea", "goldyx", "norowas", "tovak"]
const HERO_SUB := {
	"arythea": "la Signora del Sangue", "goldyx": "il Drago Cristallino", "norowas": "il Signore degli Elfi",
	"tovak": "il Cavaliere Nero",
}
const LEVELS := ["Facile", "Normale", "Difficile"]

var main
var scenario := 0
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
var _seats_box: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if main != null and main.menu_state.has("seats"):
		scenario = int(main.menu_state["scenario"])
		seats = main.menu_state["seats"].duplicate(true)
	_build_background()
	show_home()


func _exit_tree() -> void:
	_store()


func _store() -> void:
	if main != null:
		main.menu_state = {"scenario": scenario, "seats": seats.duplicate(true)}


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

func show_new_game() -> void:
	var p := _new_page()
	_title_block(p, true)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", MKUI.frame_style(0.9, 10))
	panel.position = Vector2(80, 190)
	panel.custom_minimum_size = Vector2(1760, 0)
	p.add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	panel.add_child(vb)
	vb.add_child(MKUI.title("Scenario", 32, MKUI.GOLD))
	var names := []
	for sc in SCENARIOS:
		names.append(sc["n"])
	vb.add_child(_segmented(names, scenario, func(k):
		scenario = k
		_fit_seats()
		_refresh_new_game(), 420))
	_scen_desc = MKUI.rich(22)
	_scen_desc.custom_minimum_size = Vector2(1700, 60)
	vb.add_child(_scen_desc)
	vb.add_child(HSeparator.new())
	vb.add_child(MKUI.title("Eroi", 32, MKUI.GOLD))
	_seats_box = HBoxContainer.new()
	_seats_box.add_theme_constant_override("separation", 18)
	vb.add_child(_seats_box)
	msg = MKUI.label("", 24, MKUI.RED, MKUI.font_bold)
	vb.add_child(msg)
	var btns := HBoxContainer.new()
	btns.add_theme_constant_override("separation", 18)
	vb.add_child(btns)
	var b_start := MKUI.big_button("INIZIA LA PARTITA", 460, true)
	b_start.pressed.connect(_on_start)
	btns.add_child(b_start)
	var b_back := MKUI.big_button("INDIETRO", 280)
	b_back.pressed.connect(show_home)
	btns.add_child(b_back)
	_fit_seats()
	_refresh_new_game()


func _range() -> Array:
	return SCENARIOS[scenario]["players"]


## Rispetta i limiti di giocatori dello scenario.
func _fit_seats() -> void:
	var r := _range()
	var n := _n_on()
	if n > int(r[1]):
		for i in range(seats.size() - 1, -1, -1):
			if _n_on() > int(r[1]) and i > 0:
				seats[i]["on"] = false
	while _n_on() < int(r[0]):
		for i in range(seats.size()):
			if not seats[i]["on"]:
				seats[i]["on"] = true
				break
	seats[0]["on"] = true
	if SCENARIOS[scenario]["id"] == "solo_conquest":
		seats[0]["ai"] = false


func _n_on() -> int:
	var n := 0
	for s in seats:
		if s["on"]:
			n += 1
	return n


func _refresh_new_game() -> void:
	var sc: Dictionary = SCENARIOS[scenario]
	var r := _range()
	var pl := "1 eroe" if r[1] == 1 else ("%d–%d eroi" % [r[0], r[1]])
	_scen_desc.text = "[b]%s[/b] · %s\n[i]%s[/i]" % [sc["n"], pl, sc["d"]]
	if msg:
		msg.text = ""
	for c in _seats_box.get_children():
		c.queue_free()
	for i in range(seats.size()):
		_seats_box.add_child(_seat_card(i))


func _seat_card(i: int) -> Control:
	var st: Dictionary = seats[i]
	var r := _range()
	var on: bool = st["on"]
	var hero: String = st["hero"]
	var col := MKUI.hero_col(hero)
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(414, 330)
	var sb := MKUI.panel_style(Color(0.05, 0.04, 0.06, 0.92 if on else 0.6), col if on else Color("#3a3438"), 3 if on else 1, 8, 12)
	card.add_theme_stylebox_override("panel", sb)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var lab := MKUI.label("Posto %d" % (i + 1), 22, MKUI.MUTED, MKUI.font_bold)
	lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(lab)
	if i > 0:
		var tog := Button.new()
		tog.text = "RIMUOVI" if on else "AGGIUNGI"
		tog.custom_minimum_size = Vector2(130, 44)
		var can := (on and _n_on() > int(r[0])) or (not on and _n_on() < int(r[1]))
		tog.disabled = not can
		tog.pressed.connect(func():
			seats[i]["on"] = not seats[i]["on"]
			_refresh_new_game())
		head.add_child(tog)
	if not on:
		var off := MKUI.label("Posto libero", 26, Color("#6a6260"), MKUI.font_italic)
		off.size_flags_vertical = Control.SIZE_EXPAND_FILL
		off.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		off.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		vb.add_child(off)
		return card
	# eroe: ◀ stemma + nome ▶
	var hrow := HBoxContainer.new()
	hrow.add_theme_constant_override("separation", 8)
	vb.add_child(hrow)
	var bl := Button.new()
	bl.text = "◀"
	bl.custom_minimum_size = Vector2(52, 96)
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
	br.custom_minimum_size = Vector2(52, 96)
	br.pressed.connect(func(): _cycle(i, 1))
	hrow.add_child(br)
	var nm := MKUI.title(MKUI.HERO_NAME.get(hero, hero).to_upper(), 30, Color.WHITE)
	nm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(nm)
	var sub := MKUI.label(HERO_SUB.get(hero, ""), 19, Color("#cbbf9f"), MKUI.font_italic)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(sub)
	var solo: bool = SCENARIOS[scenario]["id"] == "solo_conquest"
	var ai_row := _segmented(["UMANO", "IA"], 1 if st["ai"] else 0, func(k):
		seats[i]["ai"] = k == 1
		_refresh_new_game(), 186)
	if solo:
		for b in ai_row.get_children():
			(b as Button).disabled = true
	vb.add_child(ai_row)
	var lv := _segmented(LEVELS, int(st["level"]) - 1, func(k): seats[i]["level"] = k + 1, 121)
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
	for st in seats:
		if not st["on"]:
			continue
		var nm: String = MKUI.HERO_NAME.get(st["hero"], st["hero"])
		if st["ai"]:
			nm += " (IA)"
		pl.append({"hero": st["hero"], "ctrl": "ai" if st["ai"] else "human", "ai_level": int(st["level"]), "name": nm})
	return {"scenario": SCENARIOS[scenario]["id"], "seed": 1 + randi() % 2000000000, "players": pl,
		"options": {"set": "base"}}


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
		msg.text = "Questo scenario richiede %s." % ("un solo eroe" if r[1] == 1 else "da %d a %d eroi" % [r[0], r[1]])
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
	r.text = MKScreens.scenario_text(SCENARIOS[scenario]["id"]) + "\n\n" + MKScreens.RULES_IT
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
