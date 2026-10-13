class_name MKPanels
extends RefCounted
## Pannelli fissi dell'HUD: barra in alto, plance dei giocatori (sinistra), Riserva/punti/azioni/diario
## (destra). Funzioni statiche che ricostruiscono il contenuto dallo stato della vista v (MKGameView).


static func _clear(n: Node) -> void:
	for c in n.get_children():
		c.queue_free()


# ================================================================== barra in alto

static func build_top(v, bar: PanelContainer) -> void:
	_clear(bar)
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	bar.add_child(hb)
	hb.add_child(MKHud.btn("☰ MENU", func(): MKScreens.game_menu(v), 0, 44))
	var pt := MKHud.btn("◧" if not v.left_hidden else "▶", func():
		v.left_hidden = not v.left_hidden
		v.refresh(), 44, 44)
	pt.tooltip_text = "Nascondi/mostra la plancia per vedere meglio il tavolo"
	hb.add_child(pt)
	var is_day := bool(s.get("day", true))
	var rounds := int(s.get("scn", {}).get("rounds", 0))
	var rl := MKUI.label("%s Round %d%s · %s" % ["☀" if is_day else "☾", int(s.round), ("/%d" % rounds) if rounds > 0 else "", "Giorno" if is_day else "Notte"], 24, MKUI.GOLD_LIGHT if is_day else Color("#a9c4ff"), MKUI.font_title)
	rl.tooltip_text = "Di giorno l'oro vale qualsiasi colore base; di notte il nero serve agli incantesimi potenziati e i costi della foresta/deserto cambiano."
	rl.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(rl)
	hb.add_child(MKHud.sep_v(40))
	# ordine di turno con le tattiche
	var order: Array = s.get("turn_order", [])
	if str(s.phase) == "tactics" or order.is_empty():
		order = []
		for i in range(s.players.size()):
			order.append(i)
		if s.get("dummy") != null:
			order.append(MKEngine.DUMMY)
	var oh := HBoxContainer.new()
	oh.add_theme_constant_override("separation", 4)
	hb.add_child(oh)
	var act: int = v.actor()
	var cur_turn := int(s.turn.get("player", -1)) if str(s.phase) == "turn" else -1
	for i in order:
		oh.add_child(_order_chip(v, int(i), int(i) == act or int(i) == cur_turn))
	hb.add_child(MKHud.sep_v(40))
	# stato del turno
	var st := ""
	if str(s.phase) == "tactics":
		st = "Scelta delle tattiche"
		if act >= 0:
			st += " · tocca a " + eng.pname(act)
	elif str(s.phase) == "game_over":
		st = "Partita finita"
	elif act >= 0:
		st = "Turno di " + eng.pname(int(s.turn.get("player", act)))
		if s.combat != null:
			st += " · combattimento"
		elif s.turn.get("rested", false):
			st += " · riposo"
		elif s.turn.get("acted", false):
			st += " · azione compiuta"
		elif s.turn.get("moved", false):
			st += " · movimento"
	if int(s.get("announced_by", -1)) != -1 and str(s.phase) == "turn":
		st += " · ultimo giro del round"
	var sl := MKUI.label(st, 21, MKUI.BONE, MKUI.font_bold)
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.clip_text = true
	hb.add_child(sl)
	var gl := MKUI.label(goal_text(v), 19, MKUI.MUTED, MKUI.font_italic)
	gl.tooltip_text = str(s.get("scn", {}).get("name_it", ""))
	gl.mouse_filter = Control.MOUSE_FILTER_PASS
	hb.add_child(gl)
	hb.add_child(MKHud.btn("REGOLE", func(): MKScreens.rules(v), 0, 44))
	hb.add_child(MKHud.btn("DIARIO", func(): MKScreens.diary(v), 0, 44))
	hb.add_child(MKHud.btn("OFFERTE", func(): MKScreens.offers(v), 0, 44))


static func goal_text(v) -> String:
	var s: Dictionary = v.s
	var scn: Dictionary = s.get("scn", {})
	match str(scn.get("end", "")):
		"cities":
			var conq := 0
			var tot := int(scn.get("city", 0))
			for k in s.map.hex:
				if str(s.map.hex[k].get("site", "")) == "city" and s.map.hex[k].get("conquered", false):
					conq += 1
			return "Obiettivo: conquista le città (%d/%d)" % [conq, tot]
		"city_revealed":
			return "Obiettivo: esplora fino a rivelare la città"
	return str(scn.get("name_it", ""))


static func _order_chip(v, i: int, active: bool) -> Control:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var hero := ""
	var tac := ""
	var nm := ""
	if i == MKEngine.DUMMY:
		var d = s.get("dummy")
		if d == null:
			return Control.new()
		hero = str(d.get("hero", ""))
		tac = str(d.get("tactic", ""))
		nm = str(d.get("name", "Neutrale"))
	else:
		hero = str(s.players[i].get("hero", ""))
		tac = str(s.players[i].get("tactic", ""))
		nm = eng.pname(i)
	var p := PanelContainer.new()
	var col := MKUI.hero_col(hero)
	p.add_theme_stylebox_override("panel", MKUI.panel_style(Color(0, 0, 0, 0.5), MKUI.GOLD_LIGHT if active else Color(col, 0.6), 3 if active else 1, 22, 2))
	p.tooltip_text = nm + ((" · Tattica %d: %s" % [eng.tactic_number(tac), eng.tactic_name(tac)]) if tac != "" else " · tattica non ancora scelta")
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 2)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_child(h)
	var im := MKHud.image(MKHud.hero_token(hero), Vector2(38, 38))
	im.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if i == MKEngine.DUMMY:
		im.modulate = Color(0.6, 0.6, 0.6)
	h.add_child(im)
	var t := MKUI.label(str(eng.tactic_number(tac)) if tac != "" else "–", 20, MKUI.GOLD_LIGHT, MKUI.font_bold)
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(t)
	if i != MKEngine.DUMMY and s.players[i].get("skip_next", false):
		# gettone Ordine di Round a faccia in giù: salterà il prossimo turno
		im.modulate = Color(0.55, 0.55, 0.65)
		var fl := MKUI.label("⤓", 20, Color("#ff9a7a"), MKUI.font_bold)
		fl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		h.add_child(fl)
		p.tooltip_text += " · gettone a faccia in giù: salterà il prossimo turno"
	p.gui_input.connect(func(ev):
		if MKGameView._is_click(ev) and i != MKEngine.DUMMY:
			var pos := str(s.players[i].get("pos", ""))
			if pos != "":
				v.table.focus_hex(pos, 11.0))
	return p


# ================================================================== plance (sinistra)

static func build_left(v, panel: PanelContainer) -> void:
	_clear(panel)
	var s: Dictionary = v.s
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var vb := VBoxContainer.new()
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vb.add_theme_constant_override("separation", 8)
	sc.add_child(vb)
	var me: int = v.viewer
	if me >= 0 and me < s.players.size():
		vb.add_child(board(v, me, v.show_hand()))
	var others := []
	for i in range(s.players.size()):
		if i != me:
			others.append(i)
	if not others.is_empty() or s.get("dummy") != null:
		var t := MKUI.title("Altri eroi" if not others.is_empty() else "Neutrale", 18, MKUI.GOLD)
		vb.add_child(t)
	for i in others:
		vb.add_child(compact(v, i))
	if s.get("dummy") != null:
		vb.add_child(dummy_box(v))


## Plancia completa di un giocatore.
static func board(v, i: int, details: bool) -> Control:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var pl: Dictionary = s.players[i]
	var hero := str(pl.get("hero", ""))
	var col := MKUI.hero_col(hero)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	# intestazione
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	box.add_child(head)
	var tok := MKHud.image(MKHud.hero_token(hero), Vector2(70, 70), "Clic: centra la mappa sull'eroe")
	tok.gui_input.connect(func(ev):
		if MKGameView._is_click(ev) and str(pl.get("pos", "")) != "":
			v.table.focus_hex(str(pl.pos), 10.0))
	head.add_child(tok)
	var hv := VBoxContainer.new()
	hv.add_theme_constant_override("separation", -2)
	hv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(hv)
	hv.add_child(MKUI.title(MKUI.HERO_NAME.get(hero, hero), 25, col.lightened(0.3)))
	var nl := MKUI.label(str(pl.get("name", "")), 17, MKUI.MUTED, MKUI.font_italic)
	nl.clip_text = true
	hv.add_child(nl)
	hv.add_child(MKUI.label("Livello %d" % int(pl.get("level", 1)), 20, MKUI.GOLD_LIGHT, MKUI.font_bold))
	var tac := str(pl.get("tactic", ""))
	if tac != "":
		var ti := MKHud.image(MKHud.tactic_img(tac), Vector2(50, 70), "Tattica %d: %s\n%s" % [eng.tactic_number(tac), eng.tactic_name(tac), str(MKDB.tactics.get(tac, {}).get("text_it", ""))])
		if pl.get("tactic_used", false):
			ti.modulate = Color(0.5, 0.5, 0.5)
		ti.mouse_entered.connect(func(): v.show_zoom(MKHud.tactic_img(tac), "[b]%s[/b]\n%s" % [eng.tactic_name(tac), str(MKDB.tactics.get(tac, {}).get("text_it", ""))], Vector2(300, 420)))
		ti.mouse_exited.connect(func(): v.hide_zoom())
		ti.gui_input.connect(func(ev):
			if MKGameView._is_click(ev):
				v.hide_zoom()
				v.open_filtered_menu(eng.tactic_name(tac), MKHud.tactic_img(tac), str(MKDB.tactics.get(tac, {}).get("text_it", "")),
					func(a): return str(a.get("t", "")) == "tactic_use", "Questa tattica non ha azioni da attivare adesso."))
		head.add_child(ti)
	# Fama e livello
	var fame := int(pl.get("fame", 0))
	var lv := int(pl.get("level", 1))
	var fl: Array = MKEngine.FAME_LEVELS
	var cur_t: int = fl[clampi(lv - 1, 0, fl.size() - 1)]
	var nxt_t: int = fl[lv] if lv < fl.size() else cur_t
	var frow := HBoxContainer.new()
	frow.add_theme_constant_override("separation", 8)
	box.add_child(frow)
	frow.add_child(MKUI.label("Fama %d" % fame, 22, MKUI.GOLD_LIGHT, MKUI.font_bold))
	var pb := ProgressBar.new()
	pb.min_value = cur_t
	pb.max_value = maxi(nxt_t, cur_t + 1)
	pb.value = fame
	pb.show_percentage = false
	pb.custom_minimum_size = Vector2(120, 14)
	pb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pb.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pb.add_theme_stylebox_override("background", MKUI.panel_style(Color(0, 0, 0, 0.6), Color(MKUI.GOLD_DARK, 0.6), 1, 4, 0))
	pb.add_theme_stylebox_override("fill", MKUI.panel_style(MKUI.GOLD, MKUI.GOLD_LIGHT, 0, 4, 0))
	pb.tooltip_text = ("Livello %d a %d Fama (mancano %d)" % [lv + 1, nxt_t, nxt_t - fame]) if lv < fl.size() else "Livello massimo"
	frow.add_child(pb)
	frow.add_child(MKUI.label(("→%d" % nxt_t) if lv < fl.size() else "max", 17, MKUI.MUTED))
	# Reputazione
	var rep := int(pl.get("rep", 0))
	var rb: int = eng.rep_bonus(i)
	var rtxt := "Reputazione %+d" % rep
	if rep <= -7:
		rtxt += " · nessuna interazione"
	else:
		rtxt += " · Influenza %+d" % rb
	var rl := MKUI.label(rtxt, 19, MKUI.GREEN if rep > 0 else (MKUI.RED if rep < 0 else MKUI.BONE), MKUI.font_bold)
	rl.tooltip_text = "Il bonus si aggiunge all'Influenza quando interagisci con un sito."
	rl.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(rl)
	# statistiche
	var g := HBoxContainer.new()
	g.add_theme_constant_override("separation", 14)
	box.add_child(g)
	g.add_child(MKHud.stat("Armatura", str(eng.armor_of(i)), MKUI.BONE, "Armatura dell'eroe: ogni ferita assorbe danno pari all'armatura."))
	g.add_child(MKHud.stat("Mano", str(eng.hand_limit_now(i)) if eng.has_method("hand_limit_now") else str(pl.get("hand_limit", 5)), MKUI.BONE, "Limite di mano: a fine turno peschi fino a questo numero."))
	g.add_child(MKHud.stat("Comando", "%d/%d" % [pl.get("units", []).size(), int(pl.get("command", 1)) + int(pl.get("extra_command", 0))], MKUI.BONE, "Unità possedute / gettoni Comando."))
	g.add_child(MKHud.stat("Mazzo", str(pl.get("deck", []).size()), MKUI.BONE, "Carte nel mazzo Impresa."))
	g.add_child(MKHud.stat("Scarti", str(pl.get("discard", []).size()), MKUI.BONE, "Carte nella pila degli scarti."))
	# cristalli e gettoni
	var mr := HBoxContainer.new()
	mr.add_theme_constant_override("separation", 4)
	box.add_child(mr)
	mr.add_child(MKUI.label("Cristalli", 17, MKUI.MUTED))
	for c in ["red", "blue", "green", "white"]:
		var pp := MKHud.pip(c, int(pl.get("crystals", {}).get(c, 0)), 28, true)
		mr.add_child(pp)
	var toks: Array = pl.get("tokens", [])
	if not toks.is_empty():
		mr.add_child(MKUI.label(" Mana", 17, MKUI.MUTED))
		for t in toks:
			mr.add_child(MKHud.pip(str(t), -1, 24))
	if str(pl.get("stolen_die", "")) != "":
		mr.add_child(MKHud.die(str(pl.stolen_die), false, 28))
	# unità
	var units: Array = pl.get("units", [])
	var ut := MKUI.label("Unità (%d)" % units.size(), 19, MKUI.GOLD, MKUI.font_bold)
	box.add_child(ut)
	if units.is_empty():
		box.add_child(MKUI.label("Nessuna unità: reclutale nei villaggi, monasteri, fortezze…", 16, MKUI.MUTED, MKUI.font_italic))
		box.get_child(box.get_child_count() - 1).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	else:
		var ug := GridContainer.new()
		ug.columns = 3
		ug.add_theme_constant_override("h_separation", 6)
		ug.add_theme_constant_override("v_separation", 6)
		box.add_child(ug)
		for u in units:
			ug.add_child(unit_widget(v, i, u, details))
	# abilità
	var skills: Array = pl.get("skills", [])
	if not skills.is_empty():
		box.add_child(MKUI.label("Abilità (%d)" % skills.size(), 19, MKUI.GOLD, MKUI.font_bold))
		var sg := GridContainer.new()
		sg.columns = 2
		sg.add_theme_constant_override("h_separation", 6)
		sg.add_theme_constant_override("v_separation", 6)
		box.add_child(sg)
		for sk in skills:
			sg.add_child(skill_widget(v, i, sk))
	return box


static func unit_widget(v, i: int, u: Dictionary, details: bool) -> Control:
	var eng: MKEngine = v.eng
	var id := str(u.get("id", ""))
	var d: Dictionary = MKDB.units.get(id, {})
	var c := Control.new()
	c.custom_minimum_size = Vector2(98, 137)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var im := MKHud.image(MKHud.unit_img(id), Vector2(98, 137))
	im.set_anchors_preset(Control.PRESET_FULL_RECT)
	im.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(im)
	var state := "Pronta"
	var scol := MKUI.GREEN
	if u.get("wounded", false):
		state = "Ferita"
		scol = MKUI.RED
	elif not u.get("ready", true):
		state = "Esaurita"
		scol = MKUI.MUTED
		im.modulate = Color(0.55, 0.55, 0.55)
	if u.get("wounded", false):
		im.modulate = Color(1, 0.6, 0.6)
	var tag := MKUI.label(state, 15, scol, MKUI.font_bold)
	tag.add_theme_color_override("font_outline_color", Color.BLACK)
	tag.add_theme_constant_override("outline_size", 5)
	tag.position = Vector2(4, 116)
	tag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.add_child(tag)
	var info := "[b]%s[/b] (livello %d, armatura %d)\n" % [str(d.get("name_it", id)), int(d.get("level", 1)), int(d.get("armor", 0))]
	var ab_lines := []
	for ab in d.get("abilities", []):
		var t := str(ab.get("text_it", ""))
		if str(ab.get("mana", "")) != "":
			t += " [i](mana %s)[/i]" % MKMana.color_it(str(ab.mana))
		ab_lines.append("• " + t)
	info += "\n".join(ab_lines)
	if not d.get("resist", []).is_empty():
		var rr := []
		for r in d.resist:
			rr.append(MKHud.RESIST_IT.get(str(r), str(r)))
		info += "\n" + ", ".join(rr)
	info += "\n[i]Stato: %s[/i]" % state
	c.mouse_entered.connect(func(): v.show_zoom(MKHud.unit_img(id), info, Vector2(300, 420)))
	c.mouse_exited.connect(func(): v.hide_zoom())
	var uid := int(u.get("uid", -1))
	c.gui_input.connect(func(ev):
		if MKGameView._is_click(ev):
			v.hide_zoom()
			if details:
				v.open_filtered_menu(str(d.get("name_it", id)), MKHud.unit_img(id), info, func(a): return MKPanels.unit_match(a, uid), "Questa unità non può agire adesso."))
	return c


static func unit_match(a: Dictionary, uid: int) -> bool:
	var t := str(a.get("t", ""))
	if t in ["unit", "disband"] or (t == "sp" and a.has("uid")):
		return int(a.get("uid", -1)) == uid
	if t == "heal":
		var tg = a.get("target")
		return not (tg is String) and int(tg) == uid
	return false


static func skill_widget(v, _i: int, sk: Dictionary) -> Control:
	var eng: MKEngine = v.eng
	var id := str(sk.get("id", ""))
	var d: Dictionary = MKDB.skills.get(id, {})
	var im := MKHud.image(MKHud.skill_img(id), Vector2(150, 100))
	im.mouse_filter = Control.MOUSE_FILTER_STOP
	var used: bool = sk.get("used_turn", false) or sk.get("used_round", false) or sk.get("flipped", false)
	if used:
		im.modulate = Color(0.5, 0.5, 0.5)
	var usage: String = {"turn": "una volta per turno", "round": "una volta per round", "passive": "passiva", "interactive": "interattiva"}.get(str(d.get("usage", "")), "")
	var info := "[b]%s[/b] (%s)\n%s%s" % [str(d.get("name_it", id)), usage, str(d.get("text_it", "")), "\n[i]Già usata[/i]" if used else ""]
	im.mouse_entered.connect(func(): v.show_zoom(MKHud.skill_img(id), info, Vector2(360, 240)))
	im.mouse_exited.connect(func(): v.hide_zoom())
	im.gui_input.connect(func(ev):
		if MKGameView._is_click(ev):
			v.hide_zoom()
			v.open_filtered_menu(str(d.get("name_it", id)), MKHud.skill_img(id), info, func(a): return str(a.get("t", "")) == "skill" and str(a.get("id", "")) == id, "Questa abilità non si può usare adesso."))
	return im


## Riga compatta per gli altri eroi (mano nascosta).
static func compact(v, i: int) -> Control:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var pl: Dictionary = s.players[i]
	var hero := str(pl.get("hero", ""))
	var col := MKUI.hero_col(hero)
	var p := PanelContainer.new()
	var act: bool = int(s.turn.get("player", -1)) == i and str(s.phase) == "turn"
	p.add_theme_stylebox_override("panel", MKUI.panel_style(Color(0, 0, 0, 0.35), col if act else Color(col, 0.4), 2 if act else 1, 6, 6))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	h.add_child(MKHud.image(MKHud.hero_token(hero), Vector2(46, 46)))
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vb)
	var ai := " (IA)" if v.ctrl.is_ai_seat(i) and not str(pl.get("name", "")).ends_with("(IA)") else ""
	var nl := MKUI.label(eng.pname(i) + ai, 19, col.lightened(0.3), MKUI.font_bold)
	nl.clip_text = true
	vb.add_child(nl)
	vb.add_child(MKUI.label("Fama %d · Liv %d · Rep %+d" % [int(pl.fame), int(pl.level), int(pl.rep)], 16, MKUI.BONE))
	vb.add_child(MKUI.label("Mano %d · Mazzo %d · Unità %d" % [pl.hand.size(), pl.deck.size(), pl.units.size()], 16, MKUI.MUTED))
	var cr := VBoxContainer.new()
	cr.add_theme_constant_override("separation", 2)
	h.add_child(cr)
	var tac := str(pl.get("tactic", ""))
	if tac != "":
		cr.add_child(MKUI.label("T%d" % eng.tactic_number(tac), 17, MKUI.GOLD_LIGHT, MKUI.font_bold))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 1)
	for c in ["red", "blue", "green", "white"]:
		var n := int(pl.crystals.get(c, 0))
		if n > 0:
			crow.add_child(MKHud.pip(c, n, 18, true))
	cr.add_child(crow)
	p.tooltip_text = "Clic: centra la mappa su %s" % eng.pname(i)
	p.gui_input.connect(func(ev):
		if MKGameView._is_click(ev) and str(pl.get("pos", "")) != "":
			v.table.focus_hex(str(pl.pos), 11.0)
			# spettatore (nessun umano): si può guardare la plancia degli altri
			if v.ctrl.human_seats.is_empty():
				v.viewer = i
				v.refresh())
	return p


static func dummy_box(v) -> Control:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var d: Dictionary = s.dummy
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", MKUI.panel_style(Color(0, 0, 0, 0.35), Color("#7a7064"), 1, 6, 6))
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 6)
	p.add_child(h)
	var im := MKHud.image(MKHud.hero_token(str(d.get("hero", ""))), Vector2(46, 46))
	im.modulate = Color(0.65, 0.65, 0.65)
	h.add_child(im)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", -3)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(vb)
	var nl := MKUI.label(str(d.get("name", "Giocatore Neutrale")), 18, MKUI.BONE, MKUI.font_bold)
	nl.clip_text = true
	vb.add_child(nl)
	vb.add_child(MKUI.label("Mazzo %d · Scarti %d" % [d.get("deck", []).size(), d.get("discard", []).size()], 16, MKUI.MUTED))
	var crow := HBoxContainer.new()
	crow.add_theme_constant_override("separation", 2)
	for c in ["red", "blue", "green", "white"]:
		var n := int(d.get("crystals", {}).get(c, 0))
		if n > 0:
			crow.add_child(MKHud.pip(c, n, 20, true))
	vb.add_child(crow)
	var tac := str(d.get("tactic", ""))
	if tac != "":
		var ti := MKHud.image(MKHud.tactic_img(tac), Vector2(40, 56), "Tattica del Neutrale: %d %s" % [eng.tactic_number(tac), eng.tactic_name(tac)])
		h.add_child(ti)
	p.tooltip_text = "Il Giocatore Neutrale gira 3 carte a ogni suo turno; quando il suo mazzo finisce annuncia la fine del round."
	return p


# ================================================================== colonna destra

static func build_right(v, panel: PanelContainer) -> void:
	_clear(panel)
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	vb.custom_minimum_size = Vector2(v.RIGHT_W - 20, 0)
	vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_child(vb)
	# Riserva
	var src: Array = s.get("source", [])
	var tp := int(s.turn.get("player", -1))
	var rh := HBoxContainer.new()
	vb.add_child(rh)
	var rt := MKUI.title("Riserva", 20, MKUI.GOLD)
	rt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rt.tooltip_text = "I dadi mana della Riserva: puoi usarne uno per turno (oro = qualsiasi colore base di giorno; nero solo di notte)."
	rt.mouse_filter = Control.MOUSE_FILTER_PASS
	rh.add_child(rt)
	if tp >= 0 and str(s.phase) == "turn":
		rh.add_child(MKUI.label("dadi usati %d/%d" % [int(s.turn.get("dice_taken", 0)), int(s.turn.get("dice_allowed", 1))], 16, MKUI.MUTED))
	var dh := HFlowContainer.new()
	dh.add_theme_constant_override("h_separation", 4)
	vb.add_child(dh)
	for i in range(src.size()):
		var d: Dictionary = src[i]
		var taken := int(d.get("taken_by", -1)) != -1
		var dcol := str(d.get("color", ""))
		var dw := MKHud.die(dcol, taken, 44)
		if taken:
			dw.tooltip_text += " da " + eng.pname(int(d.taken_by))
		elif (bool(s.day) and dcol == "black") or (not bool(s.day) and dcol == "gold"):
			# exhausted: black by day, gold by night (Regolamento p. 5, "Utilizzare mana" 3c)
			dw.modulate = Color(1, 1, 1, 0.4)
			dw.tooltip_text += " (esaurito: %s)" % ("il nero non si usa di Giorno" if bool(s.day) else "l'oro non si usa di Notte")
		dh.add_child(dw)
	vb.add_child(HSeparator.new())
	# punti del turno
	if str(s.phase) == "turn" and tp >= 0 and tp < s.players.size():
		vb.add_child(MKUI.title("Punti del turno", 18, MKUI.GOLD))
		vb.add_child(pool_view(v))
		var played: Array = s.turn.get("played", [])
		if not played.is_empty():
			vb.add_child(MKUI.label("Carte giocate (%d)" % played.size(), 17, MKUI.MUTED, MKUI.font_bold))
			var pf := HFlowContainer.new()
			pf.add_theme_constant_override("h_separation", 3)
			pf.add_theme_constant_override("v_separation", 3)
			vb.add_child(pf)
			for iid in played:
				var im := MKHud.image(MKHud.card_img(eng, str(iid)), Vector2(46, 64), MKHud.card_name(str(iid)))
				im.mouse_entered.connect(func(): v.show_zoom(MKHud.card_img(eng, str(iid)), "[b]%s[/b]\n%s" % [MKHud.card_name(str(iid)), MKHud.card_text(str(iid))]))
				im.mouse_exited.connect(func(): v.hide_zoom())
				pf.add_child(im)
		vb.add_child(HSeparator.new())
	# azioni
	var acts := action_buttons(v)
	if not acts.is_empty():
		vb.add_child(MKUI.title("Azioni", 18, MKUI.GOLD))
		var ab := VBoxContainer.new()
		ab.add_theme_constant_override("separation", 5)
		vb.add_child(ab)
		for b in acts:
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.custom_minimum_size.x = 0
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ab.add_child(b)
		vb.add_child(HSeparator.new())
	elif v.local() and str(s.phase) == "turn" and s.combat == null and s.pending == null:
		var l := MKUI.label("Gioca carte dalla mano, muovi sulla mappa…", 17, MKUI.MUTED, MKUI.font_italic)
		vb.add_child(l)
	# diario breve
	var lt := MKUI.title("Diario", 18, MKUI.GOLD)
	vb.add_child(lt)
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	vb.add_child(sc)
	var r := MKUI.rich(17)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(r)
	var L: Array = s.get("log", [])
	var lines := []
	for e in L.slice(maxi(0, L.size() - 14)):
		lines.append(log_line(v, e))
	r.text = "\n".join(lines)
	sc.ready.connect(func(): sc.scroll_vertical = 100000)
	sc.call_deferred("set", "scroll_vertical", 100000)


static func log_line(v, e: Dictionary) -> String:
	var k := str(e.get("k", ""))
	var t := str(e.get("txt", ""))
	var col := ""
	match k:
		"turn", "round", "order":
			col = "#f2d78c"
		"wound", "unit_wound", "unit_destroyed", "knockout", "error":
			col = "#ff8a7a"
		"fame", "level", "conquer", "enemy_defeated", "skill_gain", "gain_card", "recruit":
			col = "#b8e890"
		"combat_start", "provoke", "assault", "challenge":
			col = "#ffb070"
	var p := int(e.get("p", -1))
	if p >= 0 and p < v.s.players.size() and k == "turn":
		col = MKUI.hero_col(str(v.s.players[p].hero)).lightened(0.35).to_html(false)
	if col != "":
		return "[color=#%s]%s[/color]" % [col.trim_prefix("#"), t]
	return t


## Punti accumulati nel turno (pool): Movimento, Influenza, Cura, Attacco e Blocco per tipo/elemento.
static func pool_view(v) -> Control:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var pool: Dictionary = s.turn.get("pool", {})
	var g := HFlowContainer.new()
	g.add_theme_constant_override("h_separation", 6)
	g.add_theme_constant_override("v_separation", 4)
	var tp := int(s.turn.get("player", -1))
	var any := false
	var chip := func(txt: String, col: Color, tip := ""):
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", MKUI.panel_style(Color(col, 0.18), Color(col, 0.8), 1, 12, 5))
		p.tooltip_text = tip
		var l := MKUI.label(txt, 19, col.lightened(0.25), MKUI.font_bold)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.add_child(l)
		g.add_child(p)
	if int(pool.get("move", 0)) > 0:
		chip.call("Movimento %d" % int(pool.move), Color("#59d98a"), "Punti Movimento: spendili cliccando gli esagoni evidenziati.")
		any = true
	if int(pool.get("influence", 0)) > 0:
		var inf := int(pool.influence)
		var bonus := ""
		if tp >= 0 and tp < s.players.size() and not s.turn.get("rep_applied", false):
			var b: int = MKSites.influence_bonus(eng, tp)
			if b != 0:
				bonus = " (%+d Rep.)" % b
		chip.call("Influenza %d%s" % [inf, bonus], Color("#c49bff"), "Influenza: si spende nei siti (reclutare, guarire, comprare).")
		any = true
	if int(pool.get("heal", 0)) > 0:
		chip.call("Cura %d" % int(pool.heal), Color("#7fd0ff"))
		any = true
	var att: Dictionary = pool.get("attack", {})
	for k in att:
		if int(att[k]) <= 0:
			continue
		chip.call("%s %d" % [MKHud.attack_key_it(str(k)), int(att[k])], MKHud.elem_col(str(k).split(":")[1] if ":" in str(k) else "phys").lerp(Color("#ff6a50"), 0.5))
		any = true
	var blk: Dictionary = pool.get("block", {})
	for k in blk:
		if int(blk[k]) <= 0:
			continue
		chip.call("%s %d" % [MKHud.block_key_it(str(k)), int(blk[k])], MKHud.elem_col(str(k)).lerp(Color("#6fa8ff"), 0.5))
		any = true
	if not any:
		var l := MKUI.label("Nessun punto: gioca una carta.", 17, MKUI.MUTED, MKUI.font_italic)
		g.add_child(l)
	return g


## Bottoni delle azioni generali dalle voci di available().
static func action_buttons(v) -> Array:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var out := []
	if not v.local() or s.pending != null or str(s.phase) != "turn":
		return out
	var av: Array = v.avail()
	var has_site_menu := false
	var turn_btns := []
	for x in av:
		var a: Dictionary = x["a"]
		var t := str(a.get("t", ""))
		var lbl := str(x.get("label", ""))
		match t:
			"recruit", "buy":
				has_site_menu = true
			"site", "altar":
				out.append(MKHud.btn(lbl, func(): v.submit(a), 0, 46, true))
			"burn":
				out.append(MKHud.btn(lbl, func(): MKScreens.confirm(v, "Bruciare il monastero?", "Reputazione −3 e combattimento contro un nemico viola (senza unità). Se vinci: un Artefatto.", func(): v.submit(a)), 0, 44))
			"plunder":
				out.append(MKHud.btn(lbl, func(): MKScreens.confirm(v, "Saccheggiare il villaggio?", "Reputazione −1; peschi 2 carte.", func(): v.submit(a)), 0, 44))
			"challenge":
				out.append(MKHud.btn(lbl, func(): v.submit(a), 0, 44))
			"pvp_attack":
				var foe := MKPvP.other_here(eng, v.actor())
				out.push_front(MKHud.btn("⚔ Attacca %s" % eng.pname(foe), func(): MKScreens.confirm(v, "Attaccare %s?" % eng.pname(foe),
					"Combattimento tra giocatori (è la tua azione del turno): prima gli attacchi a distanza e d'assedio, poi il corpo a corpo, alternandovi. Vince chi costringe l'altro a ritirarsi.", func(): v.submit(a)), 0, 48, true))
			"coop":
				out.push_front(MKHud.btn("⚑ " + lbl, func(): v.submit(a), 0, 48, true))
			"heal", "sp", "tactic_use":
				if s.combat == null or t == "sp":
					var b := MKHud.btn(lbl, func(): v.submit(a), 0, 44)
					b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
					out.append(b)
			"announce_end":
				turn_btns.append(MKHud.btn("Annuncia la fine del round", func(): MKScreens.confirm(v, "Annunciare la fine del round?", "Gli altri giocatori faranno un ultimo turno.", func(): v.submit(a)), 0, 44))
			"rest":
				var only_w := not eng.has_non_wound(v.actor())
				var rt := "Lunga Guarigione: scarti una Ferita dalla mano." if only_w else "Riposo: scarti una carta non-Ferita e quante Ferite vuoi (vanno negli scarti). In questo turno non potrai muoverti, combattere né interagire."
				turn_btns.append(MKHud.btn("Riposa", func(): MKScreens.confirm(v, "Riposare?", rt, func(): v.submit(a)), 0, 46))
			"end_turn":
				var must_discard: bool = eng.card_rule_open(v.actor()) and eng.has_non_wound(v.actor())
				var b2 := MKHud.btn("TERMINA IL TURNO", func():
					if eng.check({"t": "pvp_attack"}) == "":
						MKScreens.confirm(v, "Terminare il turno qui?", "Sei nello spazio di %s: terminare qui il movimento è automaticamente un attacco (combattimento tra giocatori)." % eng.pname(MKPvP.other_here(eng, v.actor())), func(): v.submit(a))
					elif must_discard:
						MKScreens.confirm(v, "Terminare il turno?", "Non hai giocato nessuna carta: per regola dovrai scartarne una dalla mano prima di pescare.", func(): v.submit(a))
					else:
						v.submit(a), 0, 52, true, 22)
				turn_btns.append(b2)
	if s.combat == null and MKSites.can_interact(eng, v.actor()) == "":
		has_site_menu = true
	if has_site_menu and s.combat == null:
		var h: Dictionary = eng.hex(str(s.players[v.actor()].pos))
		out.push_front(MKHud.btn("Interagisci: %s" % MKUI.site_it(str(h.get("site", ""))), func(): v.open_site(), 0, 48, true))
	if s.combat == null:
		out.append_array(turn_btns)
	return out
