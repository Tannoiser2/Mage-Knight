class_name MKGameView
extends Control
## Vista della partita: tavolo 3D (MKTable3D) + HUD completo in italiano.
## Tutte le azioni passano da ctrl.submit(); lo stato si legge da ctrl.eng.s.
## Struttura dell'HUD (CanvasLayer):
##   barra in alto (round, giorno/notte, ordine di turno, obiettivo, bottoni) · plancia del giocatore a
##   sinistra (+ altri giocatori in breve) · Riserva, punti del turno, carte giocate, azioni e diario
##   breve a destra · mano a ventaglio in basso · pannelli centrali (combattimento, sito) · finestre
##   modali (decisioni, tattiche, offerte, diario, regole, menu, passa il dispositivo, fine partita).
## Costruzione dei pannelli in MKPanels (hud_panels.gd) e delle finestre in MKScreens (hud_screens.gd).

signal state_changed

const LEFT_W := 340.0
const RIGHT_W := 340.0
const TOP_H := 66.0
const HAND_H := 250.0
const CARD_W := 150.0
const CARD_H := 210.0

var main
var config: Dictionary = {}
var ctrl: MKController
var eng: MKEngine
var s: Dictionary = {}

var table: MKTable3D
var hud: CanvasLayer
var root: Control
var top_bar: PanelContainer
var left_panel: PanelContainer
var right_panel: PanelContainer
var hand_area: Control
var center_holder: Control
var modal_layer: Control
var zoom_panel: PanelContainer
var tip_panel: PanelContainer
var tip_label: RichTextLabel
var toast_box: VBoxContainer
var banner: PanelContainer
var banner_label: Label
var cam_wrap: Control

var viewer := -1                 # giocatore di cui si vedono mano e plancia
var _pass_ok := -1               # in hotseat: ultimo giocatore che ha confermato "sono io"
var site_open := false           # pannello del sito aperto
var combat_sel: Array = []       # nemici selezionati come bersaglio
var combat_min := false          # pannello del combattimento ridotto
var pending_min := false         # finestra della decisione ridotta
var _pending_sig := ""
var _modal := {}                 # nome -> nodo
var _hl_action := {}             # esagono -> azione/tipo al clic
var _last_log_seq := -1
var _was_combat := false
var _combat_log_from := -1
var _combat_local := false
var left_hidden := false
var _av_cache = null
var _av_seq := -1
var _state_serial := 0         # plancia nascosta per vedere meglio il tavolo
var _menu_card_iid := ""
var _end_shown := false
var _hover_hex := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	MKDB.ensure()
	table = MKTable3D.new()
	table.name = "Table"
	add_child(table)
	table.hex_clicked.connect(_on_hex_clicked)
	table.hex_hovered.connect(_on_hex_hovered)
	_build_hud()
	if ctrl == null:
		ctrl = MKController.new()
		ctrl.name = "Controller"
		add_child(ctrl)
		_connect_ctrl()
		ctrl.start(config)
	else:
		if ctrl.get_parent() == null:
			add_child(ctrl)
		_connect_ctrl()
		if ctrl.eng != null:
			_on_changed()
			ctrl.kick()


func _connect_ctrl() -> void:
	if not ctrl.changed.is_connected(_on_changed):
		ctrl.changed.connect(_on_changed)
		ctrl.rejected.connect(func(m): toast(m, MKUI.RED))
		ctrl.ai_thinking.connect(_on_ai_thinking)
		# controllore online: messaggi di stato (attesa, ricollegamento…)
		if ctrl.has_signal("status"):
			ctrl.connect("status", func(m): if str(m) != "": toast(str(m), MKUI.GOLD_LIGHT, 3.5))


func _exit_tree() -> void:
	if ctrl != null and ctrl.eng != null and not ctrl.game_over():
		ctrl.save_now()


# ================================================================== azioni

func submit(a: Dictionary) -> void:
	if ctrl == null:
		return
	ctrl.submit(a)


func local() -> bool:
	return ctrl != null and ctrl.is_local_turn() and not _needs_pass()


func actor() -> int:
	return eng.actor() if eng != null else -1


## Voci di eng.available() (solo nel turno locale).
func avail() -> Array:
	if eng == null or not local():
		return []
	if _av_cache == null or _av_seq != _state_serial:
		_av_cache = eng.available()
		_av_seq = _state_serial
	return _av_cache


# ================================================================== aggiornamento

func _on_changed() -> void:
	eng = ctrl.eng
	if eng == null:
		return
	s = eng.s
	refresh()


func refresh() -> void:
	if eng == null:
		return
	s = eng.s
	_state_serial += 1
	_pick_viewer()
	table.refresh(s)
	_log_fx()
	_close_modal("cardmenu")
	if s.combat == null:
		combat_sel = []
	if s.combat != null and not _was_combat:
		combat_min = false
		_combat_local = int(s.turn.get("player", -1)) in ctrl.human_seats
		_combat_log_from = int(s.get("log_seq", 0)) - 3
	if s.combat == null and _was_combat and _combat_local:
		_combat_summary()
	_was_combat = s.combat != null
	if s.combat != null or not local():
		site_open = false
	_update_highlights()
	MKPanels.build_top(self, top_bar)
	left_panel.visible = not left_hidden
	MKPanels.build_left(self, left_panel)
	MKPanels.build_right(self, right_panel)
	_build_hand()
	_build_center()
	_state_modals()
	_update_banner()
	state_changed.emit()


## Giocatore di cui mostrare mano e plancia.
func _pick_viewer() -> void:
	var hs: Array = ctrl.human_seats
	var a := actor()
	if hs.is_empty():
		viewer = a if a >= 0 and a < s.players.size() else maxi(viewer, 0)
		return
	if hs.size() == 1:
		viewer = int(hs[0])
		return
	if a in hs and a == _pass_ok:
		viewer = a
	elif viewer < 0 or not (viewer in hs):
		viewer = int(hs[0])


## Hotseat: un altro umano deve prendere il dispositivo prima di vedere la sua mano.
func _needs_pass() -> bool:
	if ctrl == null or eng == null or ctrl.human_seats.size() < 2:
		return false
	var a := actor()
	return a in ctrl.human_seats and a != _pass_ok


func confirm_pass() -> void:
	_pass_ok = actor()
	viewer = _pass_ok
	_close_modal("pass")
	refresh()


func show_hand() -> bool:
	if viewer < 0 or viewer >= s.players.size() or _needs_pass():
		return false
	# hotseat: durante i turni dell'IA non si mostra la mano di nessuno
	if ctrl.human_seats.size() > 1 and not (actor() in ctrl.human_seats) and str(s.phase) != "game_over":
		return false
	return true


# ================================================================== HUD

func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.name = "HUD"
	hud.layer = 1
	add_child(hud)
	root = Control.new()
	root.name = "Root"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = MKUI.make_theme()
	hud.add_child(root)
	# barra in alto
	top_bar = _panel("TopBar", 0.86)
	top_bar.anchor_right = 1.0
	top_bar.offset_left = 8
	top_bar.offset_right = -8
	top_bar.offset_top = 6
	top_bar.offset_bottom = TOP_H
	# plancia a sinistra
	left_panel = _panel("Left", 0.80)
	left_panel.anchor_bottom = 1.0
	left_panel.offset_left = 8
	left_panel.offset_right = 8 + LEFT_W
	left_panel.offset_top = TOP_H + 8
	left_panel.offset_bottom = -12
	# colonna destra
	right_panel = _panel("Right", 0.80)
	right_panel.anchor_left = 1.0
	right_panel.anchor_right = 1.0
	right_panel.anchor_bottom = 1.0
	right_panel.offset_left = -8 - RIGHT_W
	right_panel.offset_right = -8
	right_panel.offset_top = TOP_H + 8
	right_panel.offset_bottom = -150
	# telecamera (in basso a destra)
	var cb := table.make_camera_buttons()
	var cw := PanelContainer.new()
	cw.add_theme_stylebox_override("panel", MKUI.panel_style(Color(MKUI.PANEL, 0.55), Color(MKUI.GOLD_DARK, 0.5), 1, 10, 6))
	cw.anchor_left = 1.0
	cw.anchor_right = 1.0
	cw.anchor_top = 1.0
	cw.anchor_bottom = 1.0
	cw.offset_left = -8 - 238
	cw.offset_right = -8
	cw.offset_top = -140
	cw.offset_bottom = -12
	cw.add_child(cb)
	root.add_child(cw)
	cam_wrap = cw
	# mano
	hand_area = Control.new()
	hand_area.name = "Hand"
	hand_area.anchor_top = 1.0
	hand_area.anchor_bottom = 1.0
	hand_area.anchor_right = 1.0
	hand_area.offset_left = LEFT_W + 24
	hand_area.offset_right = -RIGHT_W - 24
	hand_area.offset_top = -HAND_H
	hand_area.offset_bottom = 0
	hand_area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(hand_area)
	# pannelli centrali (combattimento / sito)
	center_holder = Control.new()
	center_holder.name = "Center"
	center_holder.anchor_right = 1.0
	center_holder.anchor_bottom = 1.0
	center_holder.offset_left = LEFT_W + 22
	center_holder.offset_right = -RIGHT_W - 22
	center_holder.offset_top = TOP_H + 10
	center_holder.offset_bottom = -HAND_H + 10
	center_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center_holder)
	# striscia dell'IA / stato
	banner = PanelContainer.new()
	banner.add_theme_stylebox_override("panel", MKUI.panel_style(Color(MKUI.INK, 0.82), Color(MKUI.GOLD, 0.8), 1, 18, 10))
	banner.anchor_left = 0.5
	banner.anchor_right = 0.5
	banner.offset_left = -330
	banner.offset_right = 330
	banner.offset_top = TOP_H + 12
	banner.offset_bottom = TOP_H + 58
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner_label = MKUI.label("", 22, MKUI.GOLD_LIGHT, MKUI.font_bold)
	banner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.add_child(banner_label)
	banner.visible = false
	root.add_child(banner)
	# suggerimento sull'esagono
	tip_panel = PanelContainer.new()
	tip_panel.add_theme_stylebox_override("panel", MKUI.panel_style(Color(MKUI.INK, 0.88), Color(MKUI.GOLD_DARK, 0.9), 1, 6, 10))
	tip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.visible = false
	tip_panel.custom_minimum_size = Vector2(380, 0)
	tip_label = MKUI.rich(19)
	tip_label.custom_minimum_size = Vector2(380, 0)
	tip_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tip_panel.add_child(tip_label)
	root.add_child(tip_panel)
	# zoom della carta
	zoom_panel = PanelContainer.new()
	zoom_panel.add_theme_stylebox_override("panel", MKUI.panel_style(Color(MKUI.INK, 0.92), MKUI.GOLD, 2, 10, 10))
	zoom_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_panel.visible = false
	root.add_child(zoom_panel)
	# finestre modali e avvisi
	modal_layer = Control.new()
	modal_layer.name = "Modals"
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(modal_layer)
	toast_box = VBoxContainer.new()
	toast_box.anchor_left = 0.5
	toast_box.anchor_right = 0.5
	toast_box.anchor_top = 1.0
	toast_box.anchor_bottom = 1.0
	toast_box.offset_left = -420
	toast_box.offset_right = 420
	toast_box.offset_top = -HAND_H - 200
	toast_box.offset_bottom = -HAND_H - 10
	toast_box.alignment = BoxContainer.ALIGNMENT_END
	toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(toast_box)


func _panel(name_: String, alpha := 0.82) -> PanelContainer:
	var p := PanelContainer.new()
	p.name = name_
	var sb := MKUI.frame_style(alpha, 8)
	sb.set_content_margin_all(10)
	p.add_theme_stylebox_override("panel", sb)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	p.clip_contents = true
	root.add_child(p)
	return p


# ------------------------------------------------------------------ avvisi

func toast(msg: String, col := MKUI.BONE, secs := 2.8) -> void:
	if msg == "":
		return
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MKUI.panel_style(Color(MKUI.INK, 0.9), col, 2, 8, 10))
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var l := MKUI.label(msg, 22, col if col != MKUI.BONE else MKUI.GOLD_LIGHT, MKUI.font_bold)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	p.add_child(l)
	toast_box.add_child(p)
	while toast_box.get_child_count() > 4:
		toast_box.get_child(0).free()
	if is_inside_tree():
		var tw := create_tween()
		tw.tween_interval(secs)
		tw.tween_property(p, "modulate:a", 0.0, 0.5)
		tw.tween_callback(p.queue_free)


func _update_banner() -> void:
	var a := actor()
	var txt := ""
	if str(s.phase) == "game_over":
		txt = ""
	elif a >= 0 and a < s.players.size() and ctrl.is_ai_seat(a):
		var what := "sceglie la tattica" if str(s.phase) == "tactics" else ("combatte" if s.combat != null else "gioca il suo turno")
		txt = "%s (IA) %s…" % [eng.pname(a), what]
	elif a >= 0 and not (a in ctrl.human_seats) and a < s.players.size():
		txt = "In attesa di %s…" % eng.pname(a)
	banner.visible = txt != ""
	banner_label.text = txt


func _on_ai_thinking(_p: int) -> void:
	_update_banner()


## Piccoli effetti sul tavolo per le voci nuove del diario.
func _log_fx() -> void:
	var L: Array = s.get("log", [])
	if L.is_empty():
		return
	var last := int(L[-1].get("seq", 0))
	if _last_log_seq < 0:
		_last_log_seq = last
		return
	for e in L:
		var sq := int(e.get("seq", 0))
		if sq <= _last_log_seq:
			continue
		var k := str(e.get("k", ""))
		var p := int(e.get("p", -1))
		var pos := ""
		if p >= 0 and p < s.players.size():
			pos = str(s.players[p].get("pos", ""))
		if pos == "":
			continue
		match k:
			"fame":
				table.fx_text(pos, "+%s Fama" % str(e.get("n", "")) if e.has("n") else "Fama", Color("#ffd36b"))
			"wound":
				table.fx_text(pos, "Ferita!", Color("#ff5a48"))
			"enemy_defeated":
				table.fx_ring(pos, Color("#ffd36b"))
			"conquer":
				table.fx_text(pos, "Conquistato!", Color("#9fe870"))
			"level":
				table.fx_text(pos, "Nuovo livello!", Color("#9fd8ff"))
		if k in ["level", "conquer", "enemy_defeated", "announce", "round_end"] and (ctrl.is_local_turn() or k in ["announce", "round_end"]):
			toast(str(e.get("txt", "")), MKUI.GOLD_LIGHT, 2.5)
	_last_log_seq = last


func _combat_summary() -> void:
	var lines := []
	for e in s.get("log", []):
		if int(e.get("seq", 0)) < _combat_log_from:
			continue
		if str(e.get("k", "")) in ["enemy_defeated", "wound", "unit_wound", "unit_destroyed", "knockout", "combat_end", "conquer", "retreat", "fame"]:
			lines.append(str(e.get("txt", "")))
	if lines.is_empty():
		return
	MKScreens.info(self, "Esito del combattimento", "\n".join(lines.slice(maxi(0, lines.size() - 10))))


# ================================================================== mano

func _build_hand() -> void:
	for c in hand_area.get_children():
		c.queue_free()
	if not show_hand():
		if _needs_pass() or ctrl.human_seats.size() > 1:
			var l := MKUI.label("La mano è nascosta: passa il dispositivo." if _needs_pass() else "Mano nascosta durante il turno degli altri.", 22, MKUI.MUTED, MKUI.font_italic)
			l.position = Vector2(20, HAND_H - 70)
			hand_area.add_child(l)
		return
	var pl: Dictionary = s.players[viewer]
	var hand: Array = pl.get("hand", [])
	var w := hand_area.size.x if hand_area.size.x > 10 else (1920.0 - LEFT_W - RIGHT_W - 48)
	var n := hand.size()
	var playable := local() and actor() == viewer
	var av_cards := {}
	if playable:
		for x in avail():
			var a: Dictionary = x["a"]
			if str(a.get("t", "")) in ["play", "discard"]:
				av_cards[str(a.get("card", "")).split("#")[0]] = true
	var step := CARD_W + 10.0
	if n * step > w:
		step = maxf(40.0, (w - CARD_W) / maxf(1.0, n - 1))
	var total := step * (n - 1) + CARD_W
	var x0 := (w - total) / 2.0
	var lab := MKUI.label("Mano di %s · %d carte" % [eng.pname(viewer), n], 17, MKUI.MUTED, MKUI.font_bold)
	lab.position = Vector2(x0, 2)
	lab.add_theme_color_override("font_outline_color", Color.BLACK)
	lab.add_theme_constant_override("outline_size", 5)
	hand_area.add_child(lab)
	for i in range(n):
		var iid := str(hand[i])
		var mid := (n - 1) / 2.0
		var ang := (i - mid) * (2.2 if n > 1 else 0.0)
		var lift := absf(i - mid) * absf(i - mid) * 2.0
		var cw := _card_widget(iid, Vector2(CARD_W, CARD_H), playable and av_cards.has(iid.split("#")[0]))
		cw.position = Vector2(x0 + i * step, 22 + lift)
		cw.rotation_degrees = ang
		cw.pivot_offset = Vector2(CARD_W / 2, CARD_H)
		hand_area.add_child(cw)


## Carta della mano: immagine, alone se giocabile, zoom al passaggio, menu al clic.
func _card_widget(iid: String, sz: Vector2, playable: bool) -> Control:
	var c := Control.new()
	c.custom_minimum_size = sz
	c.size = sz
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var glow := Panel.new()
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = -4
	glow.offset_top = -4
	glow.offset_right = 4
	glow.offset_bottom = 4
	var gs := MKUI.panel_style(Color(0, 0, 0, 0), Color("#ffd36b") if playable else Color(0, 0, 0, 0.6), 3 if playable else 1, 10, 0)
	if playable:
		gs.shadow_color = Color(1, 0.8, 0.3, 0.45)
		gs.shadow_size = 8
	glow.add_theme_stylebox_override("panel", gs)
	glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(glow)
	var img := MKHud.image(MKHud.card_img(eng, iid), sz)
	img.set_anchors_preset(Control.PRESET_FULL_RECT)
	img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(img)
	if img.texture == null:
		var l := MKUI.label(MKHud.card_name(iid), 18, MKUI.BONE, MKUI.font_bold)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size = sz
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.add_child(l)
	c.mouse_entered.connect(func():
		c.position.y -= 30
		c.z_index = 5
		show_zoom(MKHud.card_img(eng, iid), "[b]%s[/b]\n%s" % [MKHud.card_name(iid), MKHud.card_text(iid)]))
	c.mouse_exited.connect(func():
		c.position.y += 30
		c.z_index = 0
		hide_zoom())
	c.gui_input.connect(func(ev):
		if _is_click(ev):
			hide_zoom()
			open_card_menu(iid))
	return c


static func _is_click(ev: InputEvent) -> bool:
	return (ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT)


## Zoom grande (carte, unità, abilità) sopra la mano, a sinistra del centro.
func show_zoom(path: String, text := "", sz := Vector2(330, 462)) -> void:
	for c in zoom_panel.get_children():
		c.queue_free()
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	zoom_panel.add_child(hb)
	var im := MKHud.image(path, sz)
	im.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hb.add_child(im)
	if text != "":
		var r := MKUI.rich(20)
		r.custom_minimum_size = Vector2(280, 0)
		r.text = text
		r.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(r)
	zoom_panel.reset_size()
	zoom_panel.position = Vector2(LEFT_W + 30, maxf(TOP_H + 10, get_viewport_rect().size.y - HAND_H - sz.y - 40))
	zoom_panel.visible = true


func hide_zoom() -> void:
	zoom_panel.visible = false


# ================================================================== menu delle carte

## Modi legali per una carta della mano (da eng.available(), con le scelte di mana).
func card_entries(iid: String) -> Array:
	var out := []
	if not local() or actor() != viewer:
		return out
	var cid := iid.split("#")[0]
	var p := actor()
	var c: Dictionary = eng.card(iid)
	var tx = c.get("text_it", {})
	var seen := {}
	for x in avail():
		var a: Dictionary = x["a"].duplicate(true)
		var t := str(a.get("t", ""))
		if not (t in ["play", "discard"]) or str(a.get("card", "")).split("#")[0] != cid:
			continue
		a["card"] = iid
		if eng.check(a) != "":
			continue
		if t == "discard":
			out.append({"label": "Scarta (prima di pescare)", "a": a, "minor": true})
			continue
		var mode := str(a.get("mode", ""))
		if mode == "side":
			var side := str(a.get("side", ""))
			var nm: String = {"move": "Movimento", "influence": "Influenza", "attack": "Attacco", "block": "Blocco"}.get(side, side)
			out.append({"label": "Di lato: %s %d" % [nm, eng.side_value(p, side, iid)], "a": a, "side": true})
			continue
		var desc := ""
		if tx is Dictionary:
			desc = str(tx.get(mode, ""))
		if desc == "":
			desc = MKEffects.describe_list(c.get(mode, []))
		var head := "Base" if mode == "basic" else "Potenziata"
		if mode == "powered" and str(c.get("name_powered_it", "")) != "":
			head = str(c["name_powered_it"])
		var needs: Array = eng.card_mana_needs(c, mode)
		if needs.size() == 1 and str(c.get("type", "")) != "artifact":
			var any := false
			for src in MKMana.sources_for(eng, p, str(needs[0])):
				var a2 := a.duplicate(true)
				a2["mana"] = [str(src[0])]
				var lb := MKMana.label(eng, p, str(src[0]))
				if seen.has(mode + lb):
					continue
				if eng.check(a2) == "":
					seen[mode + lb] = true
					any = true
					out.append({"label": "%s (con %s): %s" % [head, lb, desc], "a": a2, "mana": str(src[1])})
			if not any:
				out.append({"label": "%s: %s" % [head, desc], "a": a})
		else:
			var hint := ""
			if not needs.is_empty():
				var cols := []
				for nd in needs:
					cols.append(MKMana.color_it(str(nd)))
				hint = " (mana " + " + ".join(cols) + ")"
			if str(c.get("type", "")) == "artifact" and mode == "powered":
				hint = " (l'Artefatto viene distrutto)"
			out.append({"label": "%s%s: %s" % [head, hint, desc], "a": a})
	return out


func open_card_menu(iid: String) -> void:
	var entries := card_entries(iid)
	var info := MKHud.card_text(iid)
	if entries.is_empty():
		var why := ""
		if not local():
			why = "Non è il tuo turno."
		elif eng.is_wound(iid):
			why = "Le Ferite non si possono giocare."
		else:
			why = "Questa carta non si può giocare adesso."
		MKScreens.action_menu(self, MKHud.card_name(iid), MKHud.card_img(eng, iid), info, [], why)
		return
	MKScreens.action_menu(self, MKHud.card_name(iid), MKHud.card_img(eng, iid), info, entries, "")


## Menu per unità/abilità/tattica: voci di available() che soddisfano il filtro.
func open_filtered_menu(title: String, img: String, info: String, filter: Callable, empty_msg := "Nessuna azione disponibile adesso.") -> void:
	var entries := []
	for x in avail():
		if filter.call(x["a"]):
			entries.append({"label": str(x.get("label", "")), "a": x["a"]})
	MKScreens.action_menu(self, title, img, info, entries, empty_msg if entries.is_empty() else "")


# ================================================================== finestre modali

func open_modal(name_: String, dim := 0.55, close_on_bg := true) -> Control:
	_close_modal(name_)
	var holder := Control.new()
	holder.name = name_
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.01, 0.03, dim)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	if close_on_bg:
		bg.gui_input.connect(func(ev):
			if _is_click(ev):
				_close_modal(name_))
	holder.add_child(bg)
	modal_layer.add_child(holder)
	_modal[name_] = holder
	return holder


func _close_modal(name_: String) -> void:
	if _modal.has(name_):
		var n = _modal[name_]
		if is_instance_valid(n):
			n.queue_free()
		_modal.erase(name_)


func has_modal(name_: String) -> bool:
	return _modal.has(name_) and is_instance_valid(_modal[name_])


func close_modal(name_: String) -> void:
	_close_modal(name_)


## Finestre che dipendono dallo stato: fine partita, passa il dispositivo, decisione, tattiche.
func _state_modals() -> void:
	if str(s.phase) == "game_over":
		for n in ["pass", "pending", "tactics"]:
			_close_modal(n)
		if not _end_shown:
			_end_shown = true
			MKScreens.end_screen(self)
		return
	if _needs_pass():
		for n in ["pending", "tactics", "info", "confirm", "cardmenu", "screen"]:
			_close_modal(n)
		site_open = false
		if not has_modal("pass"):
			MKScreens.pass_device(self)
		return
	_close_modal("pass")
	if local() and s.pending != null:
		_close_modal("tactics")
		var sig := JSON.stringify([s.pending.get("handler", ""), s.pending.get("prompt", ""), s.pending.get("options", [])])
		if sig != _pending_sig:
			pending_min = false
		_pending_sig = sig
		MKScreens.pending_dialog(self)
		return
	_pending_sig = ""
	_close_modal("pending")
	if local() and str(s.phase) == "tactics":
		MKScreens.tactics(self)
		return
	_close_modal("tactics")


# ================================================================== centro: combattimento / sito

func _build_center() -> void:
	for c in center_holder.get_children():
		c.queue_free()
	if s.combat != null:
		MKCombatPanel.build(self, center_holder)
	elif site_open and local():
		MKCombatPanel.build_site(self, center_holder)


func open_site() -> void:
	site_open = true
	_build_center()


func close_site() -> void:
	site_open = false
	_build_center()


# ================================================================== mappa

func _update_highlights() -> void:
	_hl_action = {}
	var d := {}
	if not local() or s.pending != null or str(s.phase) != "turn":
		# decisione su un esagono: si evidenziano le opzioni
		if local() and s.pending != null:
			for o in s.pending.get("options", []):
				var v = o.get("v")
				if v is String and eng.hex(v).size() > 0:
					d[v] = {"kind": "select", "label": ""}
					_hl_action[v] = {"t": "choose", "v": [v]}
		table.set_highlights(d)
		return
	var p := actor()
	var pos := str(s.players[p].get("pos", ""))
	if s.combat == null:
		var reach: Dictionary = eng.reachable()
		var paths := move_paths()
		for k in reach:
			var prov := _provokes(paths.get(k, []))
			var label := str(reach[k])
			var kind := "move"
			if prov:
				label += " ⚔"
				kind = "danger"
			elif _assault(k):
				label += " ⚑"
				kind = "danger"
			d[k] = {"kind": kind, "label": label}
			_hl_action[k] = {"t": "path", "to": k}
		if int(s.turn.pool.move) >= 2:
			for sl in eng.explorable_slots(p):
				if eng.check({"t": "explore", "slot": sl}) == "":
					d[sl] = "explore"
					_hl_action[sl] = {"t": "explore", "slot": sl}
		for x in avail():
			var a: Dictionary = x["a"]
			if str(a.get("t", "")) == "challenge" and a.get("hexes", []).size() == 1:
				var hk := str(a["hexes"][0])
				d[hk] = {"kind": "target", "label": "Sfida"}
				_hl_action[hk] = a
			elif str(a.get("t", "")) in ["site", "altar", "burn", "plunder", "recruit", "buy"] and pos != "":
				if not d.has(pos):
					d[pos] = {"kind": "site", "label": ""}
					_hl_action[pos] = {"t": "_site"}
	table.set_highlights(d)


## Percorsi minimi (come eng.reachable) verso ogni esagono raggiungibile: {esagono: [passi]}.
func move_paths() -> Dictionary:
	var out := {}
	var p: int = int(s.turn.get("player", -1))
	if p < 0 or p >= s.players.size() or not eng.can_still_move(p):
		return out
	var budget := int(s.turn.pool.move)
	var start: String = s.players[p].pos
	var dist := {start: 0}
	var prev := {}
	var frontier: Array = [start]
	while not frontier.is_empty():
		var bi := 0
		for i in frontier.size():
			if dist[frontier[i]] < dist[frontier[bi]]:
				bi = i
		var cur: String = frontier[bi]
		frontier.remove_at(bi)
		if cur != start and eng._move_stops(p, dist, cur):
			continue
		for nk in MKHex.neighbors(cur):
			if eng._hex_blocked(p, nk) != "":
				continue
			var c := eng.move_cost(nk)
			if c >= 999:
				continue
			var nd: int = dist[cur] + c
			if nd > budget:
				continue
			if not dist.has(nk) or nd < dist[nk]:
				dist[nk] = nd
				prev[nk] = cur
				if not nk in frontier:
					frontier.append(nk)
	for k in prev:
		var path := []
		var cur2: String = k
		while cur2 != start and prev.has(cur2):
			path.push_front(cur2)
			cur2 = prev[cur2]
		out[k] = path
	return out


## Il percorso provoca nemici scatenati? (passo da un esagono adiacente a uno adiacente allo stesso nemico)
func _provokes(path: Array) -> bool:
	if path.is_empty():
		return false
	var p := actor()
	var from: String = str(s.players[p].pos)
	for k in path:
		for nk in MKHex.neighbors(k):
			var h := eng.hex(nk)
			if not h.is_empty() and h.get("rampage", false) and not h.get("enemies", []).is_empty():
				if MKHex.adjacent(from, nk):
					return true
		from = k
	return false


func _assault(k: String) -> bool:
	var h := eng.hex(k)
	if h.is_empty():
		return false
	return str(h.get("site", "")) in MKEngine.FORTIFIED_SITES and not eng._is_safe_fortified(actor(), k)


func _on_hex_clicked(k: String) -> void:
	_show_hex_tip(k, true)
	if not local():
		return
	var a = _hl_action.get(k)
	if a == null:
		return
	match str(a.get("t", "")):
		"path":
			_walk(str(a["to"]))
		"_site":
			if _has_site_menu():
				open_site()
			else:
				MKScreens.site_quick(self)
		"challenge":
			MKScreens.confirm(self, "Sfidare i nemici scatenati?", "Inizierà un combattimento contro %s." % eng._hex_label(str(a["hexes"][0])), func(): submit(a))
		_:
			submit(a)


func _has_site_menu() -> bool:
	for x in avail():
		if str(x["a"].get("t", "")) in ["recruit", "buy"]:
			return true
	return false


## Muove l'eroe lungo il percorso minimo, un esagono alla volta (si ferma su combattimento/decisioni).
func _walk(to: String) -> void:
	var path: Array = move_paths().get(to, [])
	if path.is_empty():
		submit({"t": "move", "to": to})
		return
	if not _provokes(path) and not _assault(to):
		_do_walk(path)
	else:
		var why := "Questo percorso provoca nemici scatenati: il movimento finisce e inizia il combattimento." if _provokes(path) else "Entrare in questo sito fortificato è un assalto: Reputazione −1 e combattimento con la guarnigione."
		MKScreens.confirm(self, "Attenzione", why, func(): _do_walk(path))


func _do_walk(path: Array) -> void:
	for k in path:
		if not local() or s.combat != null or s.pending != null:
			break
		var a := {"t": "move", "to": str(k)}
		var err := eng.check(a)
		if err != "":
			toast(err, MKUI.RED)
			break
		submit(a)


func _on_hex_hovered(k: String) -> void:
	_hover_hex = k
	_show_hex_tip(k, false)


func _show_hex_tip(k: String, sticky: bool) -> void:
	if k == "" or eng == null:
		tip_panel.visible = false
		return
	var t := hex_tip(k)
	if t == "":
		tip_panel.visible = false
		return
	tip_label.text = t
	tip_panel.visible = true
	tip_panel.reset_size()
	var mp := get_viewport().get_mouse_position()
	var vs := get_viewport_rect().size
	var pos := mp + Vector2(24, 18)
	if sticky:
		pos = mp + Vector2(24, 18)
	pos.x = clampf(pos.x, LEFT_W + 20, vs.x - RIGHT_W - 20 - tip_panel.size.x)
	pos.y = clampf(pos.y, TOP_H + 10, vs.y - tip_panel.size.y - 10)
	tip_panel.position = pos


## Testo del suggerimento di un esagono: terreno e costo, sito, nemici con statistiche, avvisi.
func hex_tip(k: String) -> String:
	var h := eng.hex(k)
	if h.is_empty():
		if _hl_action.has(k) and str(_hl_action[k].get("t", "")) == "explore":
			return "[b]Esplora[/b]: rivela una nuova tessera (2 Movimento)."
		return ""
	var lines := []
	var cost := eng.move_cost(k)
	var tt := "[b]%s[/b]" % MKUI.terrain_it(h.get("t", ""))
	if cost < 999:
		tt += " · costo %d" % cost
	else:
		tt += " · invalicabile"
	lines.append(tt)
	var site := str(h.get("site", ""))
	if site != "":
		var st := "[color=#f2d78c]%s[/color]" % MKUI.site_it(site)
		if h.get("city") is Dictionary:
			st += " %s (livello %d)" % [{"green": "verde", "blue": "blu", "red": "rossa", "white": "bianca"}.get(str(h.city.get("color", "")), ""), int(h.city.get("level", 0))]
		if str(h.get("mine", "")) != "":
			st += " (%s)" % MKHud.COLOR_IT.get(str(h.mine), str(h.mine))
		if h.get("conquered", false):
			var ow := int(h.get("owner", -1))
			st += " · conquistato" + ((" da " + eng.pname(ow)) if ow >= 0 and ow < s.players.size() else "")
		if h.get("burned", false):
			st += " · bruciato"
		lines.append(st)
	var ru = h.get("ruins", "")
	if ru is String and ru != "":
		lines.append("Segnalino Rovine " + ("scoperto" if h.get("ruins_face_up", false) else "coperto"))
	for eid in h.get("enemies", []):
		var e: Dictionary = s.enemies.get(eid, {})
		if e.is_empty():
			continue
		if e.get("face_up", false):
			lines.append("• " + MKHud.enemy_tip(str(e.get("type", ""))))
		else:
			lines.append("• Nemico coperto (%s)" % MKHud.COLOR_IT.get(str(e.get("color", "")), str(e.get("color", ""))))
	if h.get("rampage", false) and not h.get("enemies", []).is_empty():
		lines.append("[color=#ff9a3a]Nemici scatenati: non si può entrare; passare accanto da un esagono adiacente all'altro li provoca.[/color]")
	for i in range(s.players.size()):
		if str(s.players[i].get("pos", "")) == k:
			lines.append("Eroe: %s" % eng.pname(i))
	if local() and _hl_action.has(k):
		var a: Dictionary = _hl_action[k]
		match str(a.get("t", "")):
			"path":
				var path: Array = move_paths().get(k, [])
				lines.append("[color=#9fe870]Clic: muovi qui (%d Movimento)[/color]" % int(eng.reachable().get(k, 0)))
				if _provokes(path):
					lines.append("[color=#ff9a3a]⚔ Il percorso provoca nemici scatenati![/color]")
				if _assault(k):
					lines.append("[color=#ff9a3a]⚑ Assalto: Reputazione −1 e combattimento.[/color]")
			"challenge":
				lines.append("[color=#ff7a6a]Clic: sfida questi nemici[/color]")
			"_site":
				lines.append("[color=#9fd0ff]Clic: interagisci con il sito[/color]")
	return "\n".join(lines)


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and not ev.echo:
		if ev.keycode == KEY_ESCAPE:
			if not _modal.is_empty():
				for n in _modal.keys():
					if n in ["cardmenu", "screen", "confirm", "info"]:
						_close_modal(n)
						return
			MKScreens.game_menu(self)
