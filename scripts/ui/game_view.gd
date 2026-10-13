class_name MKGameView
extends Control
## Vista della partita: tavolo 3D + HUD (CanvasLayer) con i pannelli segnaposto che la seconda
## ondata riempirà: barra in alto (round, giorno/notte), plance dei giocatori a sinistra, mano in
## basso, diario a destra, comandi della telecamera. Se il motore MKEngine esiste lo usa, altrimenti
## mostra lo stato di prova (MKTableDemo) e permette di muovere l'eroe di turno con un clic.

signal state_changed

var main
var config: Dictionary = {}
var eng = null                          # MKEngine (se disponibile)
var s: Dictionary = {}
var demo := false

var table: MKTable3D
var hud: CanvasLayer
var hud_root: Control
var top_bar: PanelContainer
var left_panel: PanelContainer
var bottom_panel: PanelContainer
var right_panel: PanelContainer
var cam_box: Control
var hover_label: Label
var _top_label: RichTextLabel
var _players_box: VBoxContainer
var _log: RichTextLabel
var _hand_box: HBoxContainer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	table = MKTable3D.new()
	table.name = "Table"
	add_child(table)
	table.hex_clicked.connect(_on_hex_clicked)
	table.hex_hovered.connect(_on_hex_hovered)
	_build_hud()
	_start()


# ================================================================== motore

static func engine_script() -> Script:
	for c in ProjectSettings.get_global_class_list():
		if str(c.get("class", "")) == "MKEngine":
			var sc = load(str(c["path"]))
			# uno script con errori (motore in lavorazione) non si usa
			if sc is Script and (sc as Script).can_instantiate():
				return sc
	return null


func _start() -> void:
	var E := engine_script()
	if E != null and not config.is_empty():
		var e = E.call("create", config)
		if e != null and e.get("s") is Dictionary:
			eng = e
			s = eng.s
	if eng == null:
		demo = true
		s = MKTableDemo.state(0)
		var heroes := []
		for p in config.get("players", []):
			heroes.append(str(p.get("hero", "")))
		# lo stato di prova usa gli eroi scelti nel menu (al massimo 2)
		for i in range(mini(heroes.size(), s["players"].size())):
			s["players"][i]["hero"] = heroes[i]
			s["players"][i]["name"] = str(config["players"][i].get("name", heroes[i]))
		if heroes.size() == 1:
			s["players"].resize(1)
			s["active"] = 0
	refresh()


## Ridisegna tutto dallo stato corrente (tavolo + HUD).
func refresh() -> void:
	if eng != null:
		s = eng.s
	table.refresh(s)
	_update_highlights()
	_update_hud()
	state_changed.emit()


func _update_highlights() -> void:
	var d := {}
	if eng != null and eng.has_method("reachable"):
		var r = eng.reachable()
		if r is Dictionary:
			for k in r:
				d[k] = {"kind": "move", "label": str(r[k])}
	elif demo:
		var a := int(s.get("active", 0))
		var pos := str(s["players"][a].get("pos", ""))
		if pos != "":
			var c := MKHexMesh.parse(pos)
			for dd in MKHexMesh.DIRS:
				var n: Vector2i = c + dd
				var k := MKHexMesh.key(n.x, n.y)
				var h = s["map"]["hex"].get(k)
				if h is Dictionary and not (str(h.get("t", "")) in ["lake", "mountain", "ocean"]) and h.get("enemies", []).is_empty():
					d[k] = {"kind": "move", "label": str({"plains": 2, "hills": 3, "forest": 3 if s.get("day", true) else 5, "desert": 5 if s.get("day", true) else 3, "wasteland": 4, "swamp": 5}.get(str(h.get("t", "")), 2))}
	table.set_highlights(d)


func _on_hex_clicked(k: String) -> void:
	if eng != null:
		var a := {"t": "move", "to": k}
		var r = eng.apply(a)
		if r is Dictionary and r.get("ok", false):
			refresh()
		else:
			_log_line("[color=#d8473a]%s[/color]" % str(r.get("err", "Mossa non valida")) if r is Dictionary else "Mossa non valida")
		return
	if demo:
		if table.hl.has(k):
			var i := int(s.get("active", 0))
			s["players"][i]["pos"] = k
			_log_line("%s si muove in %s." % [s["players"][i].get("name", ""), table.hex_info(k)])
			refresh()
		else:
			_log_line(table.hex_info(k) if table.hex_info(k) != "" else "Esagono %s" % k)


func _on_hex_hovered(k: String) -> void:
	if hover_label == null:
		return
	var t := table.hex_info(k)
	hover_label.text = t
	hover_label.get_parent().visible = t != ""


# ================================================================== HUD (segnaposto)

func _panel(name_: String) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = name_
	p.add_theme_stylebox_override("panel", MKUI.frame_style(0.82, 8))
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	hud_root.add_child(p)
	return p


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 1
	add_child(hud)
	hud_root = Control.new()
	hud_root.name = "Root"
	hud_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_root.theme = MKUI.make_theme()
	hud.add_child(hud_root)
	# barra in alto: round, giorno/notte
	top_bar = _panel("TopBar")
	top_bar.anchor_left = 0.5
	top_bar.anchor_right = 0.5
	top_bar.offset_left = -300
	top_bar.offset_right = 300
	top_bar.offset_top = 10
	top_bar.offset_bottom = 70
	_top_label = MKUI.rich(26)
	_top_label.fit_content = true
	_top_label.add_theme_font_override("normal_font", MKUI.font_title)
	_top_label.add_theme_font_override("bold_font", MKUI.font_title)
	_top_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top_bar.add_child(_top_label)
	# bottone del menu
	var mb := MKUI.icon_button("☰", "Torna al menu", 56)
	mb.position = Vector2(14, 12)
	mb.pressed.connect(func():
		if main != null:
			main.show_menu())
	hud_root.add_child(mb)
	# plance dei giocatori a sinistra
	left_panel = _panel("PlayerBoards")
	left_panel.anchor_top = 0.0
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 12
	left_panel.offset_right = 312
	left_panel.offset_top = 84
	left_panel.offset_bottom = -260
	_players_box = VBoxContainer.new()
	_players_box.add_theme_constant_override("separation", 10)
	left_panel.add_child(_players_box)
	# mano in basso
	bottom_panel = _panel("Hand")
	bottom_panel.anchor_top = 1.0
	bottom_panel.anchor_bottom = 1.0
	bottom_panel.anchor_left = 0.5
	bottom_panel.anchor_right = 0.5
	bottom_panel.offset_left = -560
	bottom_panel.offset_right = 560
	bottom_panel.offset_top = -236
	bottom_panel.offset_bottom = -12
	_hand_box = HBoxContainer.new()
	_hand_box.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_box.add_theme_constant_override("separation", 10)
	bottom_panel.add_child(_hand_box)
	# diario a destra
	right_panel = _panel("Log")
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -372
	right_panel.offset_right = -12
	right_panel.offset_top = 84
	right_panel.offset_bottom = -260
	var lv := VBoxContainer.new()
	right_panel.add_child(lv)
	lv.add_child(MKUI.title("Diario", 24, MKUI.GOLD))
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(sc)
	_log = MKUI.rich(19)
	_log.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(_log)
	# comandi della telecamera (in basso a destra, per il tocco)
	cam_box = table.make_camera_buttons()
	cam_box.name = "CameraButtons"
	var cam_wrap := _panel("CameraPanel")
	cam_wrap.add_theme_stylebox_override("panel", MKUI.panel_style(Color(MKUI.PANEL, 0.55), Color(MKUI.GOLD_DARK, 0.5), 1, 10, 6))
	cam_wrap.anchor_left = 1.0
	cam_wrap.anchor_right = 1.0
	cam_wrap.anchor_top = 1.0
	cam_wrap.anchor_bottom = 1.0
	cam_wrap.offset_left = -258
	cam_wrap.offset_right = -12
	cam_wrap.offset_top = -138
	cam_wrap.offset_bottom = -12
	cam_wrap.add_child(cam_box)
	# descrizione dell'esagono sotto il puntatore
	var hp := PanelContainer.new()
	hp.add_theme_stylebox_override("panel", MKUI.panel_style(Color(MKUI.INK, 0.8), Color(MKUI.GOLD_DARK, 0.8), 1, 6, 8))
	hp.anchor_left = 0.5
	hp.anchor_right = 0.5
	hp.offset_left = -300
	hp.offset_right = 300
	hp.offset_top = 80
	hp.offset_bottom = 120
	hp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hp.visible = false
	hud_root.add_child(hp)
	hover_label = MKUI.label("", 21, MKUI.BONE, MKUI.font_bold)
	hover_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hp.add_child(hover_label)


func _update_hud() -> void:
	var is_day := bool(s.get("day", true))
	_top_label.text = "[center]%s  [b]Round %d[/b] · %s[/center]" % ["☀" if is_day else "☾", int(s.get("round", 1)), "Giorno" if is_day else "Notte"]
	for c in _players_box.get_children():
		c.queue_free()
	var P: Array = s.get("players", [])
	var act := int(s.get("active", -1))
	for i in range(P.size()):
		var p: Dictionary = P[i]
		var hero := str(p.get("hero", ""))
		var box := PanelContainer.new()
		var col := MKUI.hero_col(hero)
		box.add_theme_stylebox_override("panel", MKUI.panel_style(Color(0.04, 0.03, 0.05, 0.85), col if i == act else Color(col, 0.35), 3 if i == act else 1, 6, 8))
		var vb := VBoxContainer.new()
		box.add_child(vb)
		var nm := MKUI.title(MKUI.HERO_NAME.get(hero, hero), 22, col.lightened(0.25))
		vb.add_child(nm)
		vb.add_child(MKUI.label(str(p.get("name", "")), 18, MKUI.MUTED, MKUI.font_italic))
		vb.add_child(MKUI.label("Fama %d · Livello %d · Reputazione %+d" % [int(p.get("fame", 0)), int(p.get("level", 1)), int(p.get("rep", 0))], 18, MKUI.BONE))
		box.mouse_filter = Control.MOUSE_FILTER_STOP
		box.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT and str(p.get("pos", "")) != "":
				table.focus_hex(str(p["pos"]), 10.0))
		_players_box.add_child(box)
	for c in _hand_box.get_children():
		c.queue_free()
	var ph := MKUI.label("La mano del giocatore comparirà qui", 22, Color("#7a7064"), MKUI.font_italic)
	_hand_box.add_child(ph)
	var lines := []
	var L = s.get("log", [])
	if L is Array:
		for e in L.slice(maxi(0, L.size() - 40)):
			lines.append(str(e.get("txt", e)) if e is Dictionary else str(e))
	if lines.is_empty() and _log.text == "":
		lines.append("[i]%s[/i]" % ("Partita di prova: il motore non è ancora disponibile. Clic su un esagono evidenziato per muovere l'eroe di turno." if demo else "La partita comincia."))
	if not lines.is_empty():
		_log.text = "\n".join(lines)


func _log_line(t: String) -> void:
	_log.text += ("\n" if _log.text != "" else "") + t
