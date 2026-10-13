class_name MKOnlineLobby
extends Control
## Sala d'attesa del gioco online: nome, «Crea una stanza» (con la partita scelta nella schermata
## Nuova partita: i posti UMANO diventano posti per le persone, il primo è di chi crea la stanza),
## «Entra» con il codice di 4 lettere, elenco dei posti con i nomi, «Inizia online» (i posti rimasti
## liberi li gioca l'IA sul dispositivo dell'host), rientro nella stessa stanza con lo stesso codice.
## Quando la partita parte chiede a MKMain di aprire la vista con un MKOnlineController.

signal game_started(ctrl)

var main                       # MKMain (facoltativo)
var menu                       # MKMenu che ha aperto la sala (facoltativo)
var cfg: Dictionary = {}       # configurazione proposta (se vuota: MKMenu.current_config())

var net: MKNet
var code := ""
var seat := -1
var role := ""
var room_data: Dictionary = {}
var launched := false
var busy := false

var name_edit: LineEdit
var code_edit: LineEdit
var status_label: Label
var proposal: RichTextLabel
var room_panel: PanelContainer
var room_title: Label
var seats_box: VBoxContainer
var start_btn: Button
var rejoin_btn: Button
var left_box: VBoxContainer
var _alive := true


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	net = MKNet.new()
	net.name = "Net"
	add_child(net)
	_build()
	var sess := net.load_session()
	name_edit.text = str(sess.get("name", ""))
	if str(sess.get("room", "")) != "":
		rejoin_btn.text = "RIENTRA NELLA STANZA %s" % str(sess["room"])
		rejoin_btn.visible = true
		code_edit.text = str(sess["room"])
	_show_proposal()


func _exit_tree() -> void:
	_alive = false


# ================================================================== interfaccia

func _build() -> void:
	add_child(MKUI.shade(0.55, 0.92))
	var title := MKUI.title("Gioca online", 56, MKUI.GOLD)
	title.position = Vector2(80, 50)
	add_child(title)
	var sub := MKUI.label("Partita in rete con gli amici: stesso seme, stesse mosse su ogni dispositivo (Firebase).", 22, MKUI.MUTED)
	sub.position = Vector2(84, 130)
	add_child(sub)

	var lp := PanelContainer.new()
	lp.add_theme_stylebox_override("panel", MKUI.frame_style(0.92, 10))
	lp.position = Vector2(80, 190)
	lp.custom_minimum_size = Vector2(820, 0)
	add_child(lp)
	left_box = VBoxContainer.new()
	left_box.add_theme_constant_override("separation", 12)
	lp.add_child(left_box)
	left_box.add_child(MKUI.title("Il tuo nome", 28, MKUI.GOLD))
	name_edit = LineEdit.new()
	name_edit.max_length = 24
	name_edit.placeholder_text = "Come ti vedranno gli altri"
	name_edit.custom_minimum_size = Vector2(500, 52)
	name_edit.add_theme_font_size_override("font_size", 24)
	left_box.add_child(name_edit)
	left_box.add_child(HSeparator.new())
	left_box.add_child(MKUI.title("Nuova stanza", 28, MKUI.GOLD))
	proposal = MKUI.rich(21)
	proposal.custom_minimum_size = Vector2(780, 0)
	left_box.add_child(proposal)
	var b_create := MKUI.big_button("CREA UNA STANZA", 460, true, 64)
	b_create.pressed.connect(func(): do_create())
	left_box.add_child(b_create)
	left_box.add_child(HSeparator.new())
	left_box.add_child(MKUI.title("Entra in una stanza", 28, MKUI.GOLD))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 14)
	left_box.add_child(hb)
	code_edit = LineEdit.new()
	code_edit.max_length = 4
	code_edit.placeholder_text = "ABCD"
	code_edit.custom_minimum_size = Vector2(200, 64)
	code_edit.add_theme_font_size_override("font_size", 34)
	code_edit.alignment = HORIZONTAL_ALIGNMENT_CENTER
	code_edit.text_changed.connect(func(t):
		var up: String = t.to_upper()
		if up != t:
			var c := code_edit.caret_column
			code_edit.text = up
			code_edit.caret_column = c)
	code_edit.text_submitted.connect(func(_t): do_join())
	hb.add_child(code_edit)
	var b_join := MKUI.big_button("ENTRA", 240, false, 64)
	b_join.pressed.connect(func(): do_join())
	hb.add_child(b_join)
	rejoin_btn = MKUI.big_button("RIENTRA", 560, false, 60)
	rejoin_btn.visible = false
	rejoin_btn.pressed.connect(func():
		code_edit.text = str(net.load_session().get("room", ""))
		do_join())
	left_box.add_child(rejoin_btn)
	var b_back := MKUI.big_button("INDIETRO", 280, false, 60)
	b_back.pressed.connect(_back)
	left_box.add_child(b_back)

	room_panel = PanelContainer.new()
	room_panel.add_theme_stylebox_override("panel", MKUI.frame_style(0.92, 10))
	room_panel.position = Vector2(960, 190)
	room_panel.custom_minimum_size = Vector2(880, 0)
	room_panel.visible = false
	add_child(room_panel)
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 14)
	room_panel.add_child(rv)
	room_title = MKUI.title("Stanza", 44, MKUI.GOLD_LIGHT)
	rv.add_child(room_title)
	rv.add_child(MKUI.label("Comunica il codice agli amici: entrano con «Entra».", 21, MKUI.MUTED))
	seats_box = VBoxContainer.new()
	seats_box.add_theme_constant_override("separation", 8)
	rv.add_child(seats_box)
	var rb := HBoxContainer.new()
	rb.add_theme_constant_override("separation", 14)
	rv.add_child(rb)
	start_btn = MKUI.big_button("INIZIA ONLINE", 420, true, 64)
	start_btn.pressed.connect(func(): do_start())
	rb.add_child(start_btn)
	var b_leave := MKUI.big_button("ESCI DALLA STANZA", 380, false, 64)
	b_leave.pressed.connect(_leave_room)
	rb.add_child(b_leave)

	status_label = MKUI.label("", 24, MKUI.GOLD_LIGHT, MKUI.font_bold)
	status_label.anchor_top = 1.0
	status_label.anchor_bottom = 1.0
	status_label.offset_top = -90
	status_label.offset_bottom = -40
	status_label.offset_left = 84
	status_label.offset_right = 1800
	add_child(status_label)


func say(msg: String, bad := false) -> void:
	if status_label != null:
		status_label.text = msg
		status_label.add_theme_color_override("font_color", MKUI.RED if bad else MKUI.GOLD_LIGHT)
	if OS.has_feature("headless") or DisplayServer.get_name() == "headless":
		print("LOBBY ", msg)


func _hero_name(h: String) -> String:
	return str(MKUI.HERO_NAME.get(h, h.capitalize()))


func _scenario_name(id: String) -> String:
	for sc in MKMenu.SCENARIOS:
		if sc["id"] == id:
			return str(sc["n"])
	return id


func _show_proposal() -> void:
	var c := _base_config()
	var t := "[b]%s[/b]\n" % _scenario_name(str(c.get("scenario", "")))
	var first := true
	for p in c.get("players", []):
		var who := ""
		if str(p.get("ctrl", "human")) == "ai":
			who = "IA %s" % str(MKMenu.LEVELS[clampi(int(p.get("ai_level", 2)) - 1, 0, 2)])
		elif first:
			who = "UMANO — il tuo posto"
			first = false
		else:
			who = "UMANO — posto per un amico (se resta libero gioca l'IA)"
		t += "• %s: %s\n" % [_hero_name(str(p.get("hero", ""))), who]
	t += "[color=#a59c8a][i]Scenario ed eroi si scelgono in «Nuova partita».[/i][/color]"
	proposal.text = t


## Configurazione proposta: quella passata, oppure quella della schermata Nuova partita.
func _base_config() -> Dictionary:
	if not cfg.is_empty():
		return cfg
	var c = null
	if menu != null and menu.has_method("current_config"):
		c = menu.current_config()
	elif main != null and main.get("current") != null and main.current.has_method("current_config"):
		c = main.current.current_config()
	else:
		var M = load("res://scripts/ui/menu.gd")
		if M is Script:
			for m in (M as Script).get_script_method_list():
				if str(m.get("name", "")) == "current_config" and (int(m.get("flags", 0)) & METHOD_FLAG_STATIC):
					c = M.call("current_config")
					break
	if c is Dictionary and not c.is_empty():
		return c
	return {"scenario": "first_recon", "seed": 1 + randi() % 2000000000, "options": {"set": "base"},
		"players": [{"hero": "arythea", "ctrl": "human", "ai_level": 2, "name": "Arythea"},
			{"hero": "goldyx", "ctrl": "human", "ai_level": 2, "name": "Goldyx"}]}


func _player_name() -> String:
	var nm := name_edit.text.strip_edges()
	return nm.substr(0, 24)


func _show_room() -> void:
	room_panel.visible = true
	room_title.text = "Stanza  %s" % code
	start_btn.visible = role == "host"
	_refresh_seats()


func _refresh_seats() -> void:
	for ch in seats_box.get_children():
		ch.queue_free()
	var c = JSON.parse_string(str(room_data.get("cfg", ""))) if room_data.get("cfg") is String else null
	if not (c is Dictionary):
		return
	var seats := MKNet._as_dict(room_data.get("seats", {}))
	var pl: Array = c.get("players", [])
	for i in range(pl.size()):
		var p: Dictionary = pl[i]
		var hero := _hero_name(str(p.get("hero", "")))
		var who := ""
		var col := MKUI.BONE
		if str(p.get("ctrl", "human")) == "ai":
			who = "IA %s" % str(MKMenu.LEVELS[clampi(int(p.get("ai_level", 2)) - 1, 0, 2)])
			col = MKUI.MUTED
		elif seats.has(str(i)):
			var st: Dictionary = seats[str(i)]
			who = str(st.get("name", "?"))
			if i == seat:
				who += "  (tu)"
				col = MKUI.GOLD_LIGHT
			if st.get("away", false):
				who += "  — assente"
		else:
			who = "libero (se resta libero gioca l'IA)"
			col = MKUI.MUTED
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 16)
		var dot := ColorRect.new()
		dot.color = MKUI.hero_col(str(p.get("hero", "")))
		dot.custom_minimum_size = Vector2(18, 40)
		row.add_child(dot)
		var hl := MKUI.label(hero, 26, MKUI.GOLD, MKUI.font_bold)
		hl.custom_minimum_size = Vector2(220, 0)
		row.add_child(hl)
		row.add_child(MKUI.label(who, 24, col))
		seats_box.add_child(row)


# ================================================================== azioni

func do_create() -> void:
	if busy or launched:
		return
	var nm := _player_name()
	if nm == "":
		say("Scrivi prima il tuo nome.", true)
		return
	var c := _base_config().duplicate(true)
	var humans := []
	var pl: Array = c.get("players", [])
	for i in range(pl.size()):
		if str(pl[i].get("ctrl", "human")) != "ai":
			humans.append(i)
	if humans.is_empty():
		say("Serve almeno un eroe UMANO (in «Nuova partita»).", true)
		return
	busy = true
	net._save({"name": nm})
	say("Creo la stanza…")
	var cd := await net.create_room(nm, humans, JSON.stringify(c))
	busy = false
	if not _alive:
		return
	if cd == "":
		say("Non riesco a creare la stanza (%s)." % (net.last_error if net.last_error != "" else "rete"), true)
		return
	code = cd
	seat = int(humans[0])
	role = "host"
	net.remember_room(code, seat)
	room_data = await net.room(code)
	_show_room()
	say("Stanza %s creata. Quando gli amici sono entrati premi «Inizia online»." % code)
	_poll_room()


func do_join() -> void:
	if busy or launched:
		return
	var nm := _player_name()
	if nm == "":
		say("Scrivi prima il tuo nome.", true)
		return
	var cd := code_edit.text.strip_edges().to_upper()
	if cd.length() != 4:
		say("Il codice della stanza ha 4 lettere.", true)
		return
	busy = true
	net._save({"name": nm})
	say("Entro nella stanza %s…" % cd)
	var s := await net.join_room(cd, nm)
	busy = false
	if not _alive:
		return
	if s == -1:
		say("La stanza %s è al completo." % cd, true)
		return
	if s < 0:
		var r: Dictionary = net.last_room
		if r.is_empty():
			say("La stanza %s non esiste (o la rete non risponde: %s)." % [cd, net.last_error], true)
		else:
			say("La partita in %s è già iniziata: per rientrare usa lo stesso nome; se il tuo posto risulta ancora occupato riprova tra un minuto." % cd, true)
		net.remember_room("")
		rejoin_btn.visible = false
		return
	code = cd
	seat = s
	room_data = net.last_room
	role = "host" if str(room_data.get("host", "")) == net.uid else "guest"
	net.remember_room(code, seat)
	if str(room_data.get("status", "")) in ["playing", "over"]:
		# rientro (o partita finita: la si rigioca fino al risultato)
		await _launch()
		return
	room_data = await net.room(code)
	_show_room()
	say("Sei nella stanza %s. Aspetta che l'host avvii la partita." % code if role == "guest" else "Sei di nuovo nella tua stanza %s." % code)
	_poll_room()


## Aggiorna l'elenco dei posti; chi non è l'host parte quando l'host avvia la partita.
func _poll_room() -> void:
	var my_code := code
	while _alive and not launched and code == my_code and is_inside_tree():
		await get_tree().create_timer(1.5).timeout
		if not _alive or launched or code != my_code:
			return
		var r := await net.room(code)
		if not _alive or launched or code != my_code:
			return
		if r.is_empty():
			if net.last_error == "":
				say("La stanza %s è stata chiusa." % code, true)
				_reset_room()
				return
			continue
		room_data = r
		_refresh_seats()
		if str(r.get("status", "")) == "playing" and not busy:
			await _launch()
			return


## (host) Avvia la partita: i posti UMANO rimasti liberi diventano IA.
func do_start() -> void:
	if busy or launched or role != "host":
		return
	busy = true
	say("Avvio la partita…")
	var r := await net.room(code)
	if r.is_empty():
		busy = false
		say("Non riesco a leggere la stanza (%s)." % net.last_error, true)
		return
	room_data = r
	var c = JSON.parse_string(str(r.get("cfg", "")))
	if not (c is Dictionary):
		busy = false
		say("Configurazione della stanza non valida.", true)
		return
	c = MKEngine._intify(c)
	var seats := MKNet._as_dict(r.get("seats", {}))
	var pl: Array = c.get("players", [])
	for i in range(pl.size()):
		var p: Dictionary = pl[i]
		if str(p.get("ctrl", "human")) == "ai":
			continue
		if seats.has(str(i)):
			p["name"] = str(seats[str(i)].get("name", p.get("name", "")))
			p["ctrl"] = "human"
		else:
			p["ctrl"] = "ai"
			p["ai_level"] = int(p.get("ai_level", 2))
			p["name"] = _hero_name(str(p.get("hero", ""))) + " (IA)"
	if int(c.get("seed", 0)) <= 0:
		c["seed"] = 1 + randi() % 2000000000
	var ok := await net.start_room(code, {"cfg": JSON.stringify(c)})
	busy = false
	if not ok:
		say("Non riesco ad avviare la partita (%s)." % net.last_error, true)
		return
	room_data["game"] = {"cfg": JSON.stringify(c)}
	room_data["status"] = "playing"
	await _launch()


## Apre la partita: configurazione definitiva dalla stanza, mosse già giocate (rientro).
func _launch() -> void:
	if launched:
		return
	busy = true
	var game = room_data.get("game")
	if not (game is Dictionary) or not (game.get("cfg") is String):
		var r := await net.room(code)
		room_data = r
		game = r.get("game")
	var c = JSON.parse_string(str(game.get("cfg", ""))) if game is Dictionary else null
	if not (c is Dictionary):
		busy = false
		say("La partita non è leggibile (rete: %s)." % net.last_error, true)
		return
	say("Scarico le mosse già giocate…")
	var acts := await net.get_acts(code)
	busy = false
	if not _alive:
		return
	launched = true
	var ctrl := MKOnlineController.new()
	ctrl.name = "OnlineController"
	ctrl.setup(net, code, seat, role, acts)
	ctrl.start(c)
	say("")
	game_started.emit(ctrl)
	if main != null and main.has_method("start_game_with"):
		main.start_game_with(ctrl)
	elif ctrl.get_parent() == null:
		get_tree().root.add_child(ctrl)


func _leave_room() -> void:
	if role == "host" and str(room_data.get("status", "lobby")) == "lobby" and code != "":
		net.close_room(code)
	net.remember_room("")
	_reset_room()
	say("Sei uscito dalla stanza.")


func _reset_room() -> void:
	code = ""
	seat = -1
	role = ""
	room_data = {}
	room_panel.visible = false
	rejoin_btn.visible = false


func _back() -> void:
	if main != null and main.has_method("back_to_menu"):
		main.back_to_menu()
	elif main != null and main.has_method("show_menu"):
		main.show_menu()
	else:
		queue_free()
