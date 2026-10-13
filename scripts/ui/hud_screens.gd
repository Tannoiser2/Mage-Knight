class_name MKScreens
extends RefCounted
## Finestre modali dell'HUD: menu delle azioni (carte/unità/abilità), conferme, decisioni in sospeso
## (s.pending), scelta delle tattiche, passa il dispositivo, offerte, diario, regole, menu di gioco,
## fine partita. Statico; v = MKGameView.

const RULES_IT := """[b]Il round.[/b] La partita dura un numero fisso di round, alternando Giorno e Notte (il primo è Giorno). All'inizio di ogni round si rilanciano i dadi della [b]Riserva[/b] e ognuno sceglie una carta [b]Tattica[/b] (chi ha meno Fama sceglie per primo): il numero della tattica decide l'ordine di turno.

[b]Il turno.[/b] Nel tuo turno puoi [b]riposare[/b] (scarta 1 carta non-Ferita e quante Ferite vuoi; se hai solo Ferite ne scarti una) oppure [b]muoverti[/b] e poi compiere [b]una sola azione[/b]: interagire con un sito, combattere, reclutare. A fine turno le carte giocate vanno negli scarti e peschi fino al limite di mano.

[b]Le carte.[/b] Ogni carta si gioca in modo [b]base[/b], [b]potenziato[/b] (pagando 1 mana del suo colore) oppure [b]di lato[/b] per 1 Movimento, Influenza, Attacco o Blocco. Le Ferite non si giocano.

[b]Il mana.[/b] Puoi prendere 1 dado della Riserva per turno. L'oro vale qualsiasi colore base di Giorno ed è inutilizzabile di Notte; il nero si usa solo di Notte per gli Incantesimi potenziati. I [b]Cristalli[/b] (massimo 3 per colore) si spendono come mana; i gettoni mana spariscono a fine turno.

[b]Movimento.[/b] Costi Giorno/Notte: pianura 2/2, colline 3/3, foresta 3/5, deserto 5/3, terre perdute 4/4, palude 5/5, città 2. Laghi, montagne e oceano sono invalicabili. Esplorare una tessera adiacente costa 2 Movimento. Non puoi entrare negli spazi dei nemici scatenati; passare da uno spazio adiacente a un nemico scatenato a un altro adiacente allo stesso nemico lo [b]provoca[/b] (il movimento finisce e si combatte). Entrare in un castello, una torre della magia o una città non conquistati è un [b]assalto[/b] (Reputazione −1): i difensori sono fortificati.

[b]I siti.[/b] Villaggio: reclutare, Cura (3 Influenza = 1 punto Cura), saccheggiare (Reputazione −1, peschi 2 carte). Monastero: reclutare, Cura (2 Influenza = 1 punto), imparare l'Azione avanzata del monastero (6 Influenza), bruciarlo (Reputazione −3, combattimento senza unità, Artefatto). Castello e torre della magia: prima vanno conquistati; poi nel castello si reclutano Unità, nella torre si comprano Incantesimi (7 Influenza + 1 mana del colore). Sotterraneo e tomba: combattimento senza unità con le regole della Notte per il mana. Tana del mostro, terreni di nidificazione, antiche rovine: combattimento per le ricompense. Radura magica e miniera di cristalli danno mana e cristalli.

[b]Il combattimento.[/b] Quattro fasi: [b]1. Distanza/Assedio[/b] (contro i fortificati solo Assedio) → [b]2. Blocco[/b] → [b]3. Danni[/b] (i colpi non bloccati vanno all'eroe o alle unità) → [b]4. Attacco[/b]. Per sconfiggere un gruppo di nemici l'attacco efficace deve eguagliare la somma delle armature. Le resistenze dimezzano gli attacchi di quel tipo; contro il Fuoco blocca bene il Ghiaccio e viceversa. Rapido: serve il doppio del Blocco. Brutale: danno doppio. Velenoso e Paralizzante peggiorano le ferite. Ogni ferita all'eroe assorbe danno pari all'armatura. Se in un combattimento ricevi ferite pari al limite di mano scarti tutte le carte non-Ferita.

[b]Fama e livelli.[/b] Ogni nemico sconfitto dà Fama. Livelli a 3, 8, 15, 24, 35, 48, 63, 80, 99 Fama: armatura, limite di mano e Comando crescono; ai livelli pari scegli un'Abilità e un'Azione avanzata.

[b]Reputazione[/b] (−7…+7): modifica l'Influenza nelle interazioni (+1 a +2/+3, +2 a +4/+5, +3 a +6, +5 a +7; −1 a −2/−3, −2 a −4, −3 a −5, −5 a −6; a −7 nessuno ti parla).

[b]Fine del round.[/b] Chi inizia il turno con il mazzo vuoto può annunciare la fine del round: gli altri fanno un ultimo turno. Nel solitario il Giocatore Neutrale gira 3 carte a ogni suo turno e annuncia la fine del round quando il suo mazzo finisce."""


static func _panel(v, name_: String, w: float, dim := 0.6, close_on_bg := true, title := "") -> VBoxContainer:
	var holder: Control = v.open_modal(name_, dim, close_on_bg)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cc)
	var p := PanelContainer.new()
	var sb := MKUI.frame_style(0.96, 10)
	sb.set_content_margin_all(18)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(w, 0)
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	cc.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	p.add_child(vb)
	if title != "":
		var t := MKUI.title(title, 32, MKUI.GOLD)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(t)
	return vb


static func _shrink(c: Control) -> Control:
	c.size_flags_horizontal = Control.SIZE_SHRINK_END
	return c


static func _scroll(h: float) -> ScrollContainer:
	var sc := ScrollContainer.new()
	sc.custom_minimum_size = Vector2(0, h)
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return sc


# ================================================================== menu delle azioni

## Finestra con immagine grande a sinistra e le azioni possibili a destra.
static func action_menu(v, title: String, img: String, info: String, entries: Array, empty_msg: String) -> void:
	var vb := _panel(v, "cardmenu", 860, 0.5, true)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	vb.add_child(hb)
	var tex := MKHud.tex_of(img)
	var isz := Vector2(300, 420)
	if tex != null and tex.get_width() > tex.get_height():
		isz = Vector2(330, 220)
	hb.add_child(MKHud.image(img, isz))
	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 8)
	rv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(rv)
	rv.add_child(MKUI.title(title, 30, MKUI.GOLD_LIGHT))
	if info != "":
		var r := MKUI.rich(19)
		r.text = info
		r.custom_minimum_size = Vector2(480, 0)
		rv.add_child(r)
	rv.add_child(HSeparator.new())
	if entries.is_empty():
		var l := MKUI.label(empty_msg, 20, MKUI.MUTED, MKUI.font_italic)
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size = Vector2(480, 0)
		rv.add_child(l)
	else:
		var sc := _scroll(minf(420, entries.size() * 56 + 10))
		rv.add_child(sc)
		var bl := VBoxContainer.new()
		bl.add_theme_constant_override("separation", 6)
		bl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sc.add_child(bl)
		for e in entries:
			var a: Dictionary = e["a"]
			var b := MKHud.btn(str(e["label"]), func():
				v.close_modal("cardmenu")
				v.submit(a), 0, 48, not e.get("side", false) and not e.get("minor", false), 19)
			b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			if e.get("disabled", false):
				b.disabled = true
				b.tooltip_text = str(e["label"])
			if e.has("mana"):
				var ic := MKHud.pip(str(e["mana"]), -1, 22)
				var hb2 := HBoxContainer.new()
				hb2.add_child(ic)
				b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hb2.add_child(b)
				bl.add_child(hb2)
			else:
				bl.add_child(b)
	rv.add_child(_shrink(MKHud.btn("Annulla", func(): v.close_modal("cardmenu"), 160, 44)))


static func confirm(v, title: String, text: String, cb: Callable) -> void:
	var vb := _panel(v, "confirm", 640, 0.6, true, title)
	var l := MKUI.rich(21)
	l.text = text
	l.custom_minimum_size = Vector2(600, 0)
	vb.add_child(l)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	hb.alignment = BoxContainer.ALIGNMENT_END
	vb.add_child(hb)
	hb.add_child(MKHud.btn("Annulla", func(): v.close_modal("confirm"), 160, 48))
	hb.add_child(MKHud.btn("Conferma", func():
		v.close_modal("confirm")
		cb.call(), 180, 48, true))


static func info(v, title: String, text: String) -> void:
	var vb := _panel(v, "info", 700, 0.45, true, title)
	var l := MKUI.rich(20)
	l.text = text
	l.custom_minimum_size = Vector2(660, 0)
	vb.add_child(l)
	vb.add_child(_shrink(MKHud.btn("OK", func(): v.close_modal("info"), 160, 46, true)))


## Interazione rapida con il sito (senza reclutamenti/acquisti): Entra, altare, saccheggio, incendio.
static func site_quick(v) -> void:
	var entries := []
	for x in v.avail():
		var a: Dictionary = x["a"]
		if str(a.get("t", "")) in ["site", "altar", "burn", "plunder"]:
			entries.append({"label": str(x.label), "a": a})
	var eng: MKEngine = v.eng
	var h: Dictionary = eng.hex(str(v.s.players[v.actor()].pos))
	var site := str(h.get("site", ""))
	action_menu(v, MKUI.site_it(site), MKUI.first([MKUI.asset("site_" + site)]), "", entries, "Qui non puoi fare nulla adesso.")


# ================================================================== decisioni

static func _opt_image(v, pend: Dictionary, o: Dictionary) -> String:
	if str(o.get("img", "")) != "":
		return MKHud.res(str(o.img))
	var val = o.get("v")
	var typ := str(pend.get("type", ""))
	if val is String:
		var sv: String = val
		var id := sv
		if sv.begins_with("own:") or sv.begins_with("common:"):
			id = sv.split(":", true, 1)[1]
		if typ == "skill" or MKDB.skills.has(id):
			if MKDB.skills.has(id):
				return MKHud.skill_img(id)
		if MKDB.tactics.has(id) and typ == "tactic":
			return MKHud.tactic_img(id)
		if MKDB.units.has(id):
			return MKHud.unit_img(id)
		var cid := id.split("#")[0]
		if MKDB.cards.has(cid) and (id.find("#") >= 0 or typ in ["offer", "card"]):
			return MKHud.card_img(v.eng, id)
		if v.s.enemies.has(id):
			var e: Dictionary = v.s.enemies[id]
			return MKHud.enemy_img(str(e.get("type", ""))) if e.get("face_up", false) else MKHud.enemy_back(str(e.get("color", "")))
	return ""


static func pending_dialog(v) -> void:
	var pend: Dictionary = v.s.pending
	var eng: MKEngine = v.eng
	if v.pending_min:
		var holder: Control = v.open_modal("pending", 0.0, false)
		holder.get_child(0).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var bar := PanelContainer.new()
		bar.add_theme_stylebox_override("panel", MKUI.panel_style(Color(MKUI.INK, 0.92), MKUI.GOLD, 2, 10, 10))
		bar.anchor_left = 0.5
		bar.anchor_right = 0.5
		bar.offset_left = -420
		bar.offset_right = 420
		bar.offset_top = 140
		bar.offset_bottom = 200
		holder.add_child(bar)
		var hb := HBoxContainer.new()
		bar.add_child(hb)
		var l := MKUI.label("Decisione: " + str(pend.get("prompt", "")), 20, MKUI.GOLD_LIGHT, MKUI.font_bold)
		l.clip_text = true
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(l)
		hb.add_child(MKHud.btn("Mostra", func():
			v.pending_min = false
			pending_dialog(v), 120, 40, true))
		return
	var opts: Array = pend.get("options", [])
	var imgs := []
	var n_img := 0
	for o in opts:
		var ip := _opt_image(v, pend, o)
		imgs.append(ip)
		if ip != "":
			n_img += 1
	var typ := str(pend.get("type", ""))
	var w := 900.0
	if n_img >= 2:
		w = clampf(n_img * 272 + 80, 760, 1560)
	var vb := _panel(v, "pending", w, 0.4, false)
	var hh := HBoxContainer.new()
	vb.add_child(hh)
	var who := ""
	if v.ctrl.human_seats.size() > 1:
		who = eng.pname(int(pend.get("player", 0))) + ": "
	var t := MKUI.title(who + str(pend.get("prompt", "Scegli")), 28, MKUI.GOLD_LIGHT)
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hh.add_child(t)
	hh.add_child(MKHud.btn("Guarda la mappa ▾", func():
		v.pending_min = true
		pending_dialog(v), 0, 40))
	var grid := HFlowContainer.new()
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	grid.alignment = FlowContainer.ALIGNMENT_CENTER
	var plain := VBoxContainer.new()
	plain.add_theme_constant_override("separation", 6)
	var sc := _scroll(0)
	sc.add_child(plain)
	plain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in range(opts.size()):
		var o: Dictionary = opts[i]
		var a := {"t": "choose", "v": [o.get("v")]}
		var lbl := str(o.get("label", str(o.get("v"))))
		var ip: String = imgs[i]
		if n_img >= 2 and ip != "":
			grid.add_child(_img_option(v, ip, lbl, a, _opt_desc(o)))
		elif typ == "color" or (o.get("v") is String and MKUI.MANA_COL.has(str(o.get("v")).split("|")[-1]) and typ in ["color", "mana"]):
			var colname := str(o.get("v")).split("|")[-1]
			var hb := HBoxContainer.new()
			hb.add_theme_constant_override("separation", 8)
			hb.add_child(MKHud.pip(colname, -1, 34))
			var b := MKHud.btn(lbl, func(): v.submit(a), 0, 48, false, 20)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb.add_child(b)
			plain.add_child(hb)
		elif typ == "die" and (o.get("v") is int or o.get("v") is float) and int(o.get("v")) >= 0 and int(o.get("v")) < v.s.source.size():
			var hb2 := HBoxContainer.new()
			hb2.add_theme_constant_override("separation", 8)
			hb2.add_child(MKHud.die(str(v.s.source[int(o.get("v"))].get("color", "")), false, 40))
			var b2 := MKHud.btn(lbl, func(): v.submit(a), 0, 48, false, 20)
			b2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			hb2.add_child(b2)
			plain.add_child(hb2)
		else:
			var b3 := MKHud.btn(lbl, func(): v.submit(a), 0, 48, false, 20)
			b3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			# mana da pagare: pallino del colore
			var sv = o.get("v")
			if sv is String and (sv.begins_with("die:") or sv.begins_with("crystal:") or sv.begins_with("token:")):
				var col := MKMana.source_color(eng, int(pend.get("player", 0)), sv.split("=")[0])
				var hb3 := HBoxContainer.new()
				hb3.add_theme_constant_override("separation", 8)
				hb3.add_child(MKHud.pip(col, -1, 30, sv.begins_with("crystal:")))
				b3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				hb3.add_child(b3)
				plain.add_child(hb3)
			else:
				plain.add_child(b3)
	if grid.get_child_count() > 0:
		vb.add_child(grid)
	else:
		grid.queue_free()
	if plain.get_child_count() > 0:
		sc.custom_minimum_size.y = minf(520, plain.get_child_count() * 56)
		vb.add_child(sc)
	else:
		sc.queue_free()


## Testo descrittivo di un'opzione (abilità, carta) da mostrare sotto l'immagine.
static func _opt_desc(o: Dictionary) -> String:
	var val = o.get("v")
	if not (val is String):
		return ""
	var id: String = val
	if id.begins_with("own:") or id.begins_with("common:"):
		id = id.split(":", true, 1)[1]
	if MKDB.skills.has(id):
		return str(MKDB.skills[id].get("text_it", ""))
	return ""


static func _img_option(v, ip: String, lbl: String, a: Dictionary, desc := "") -> Control:
	var tex := MKHud.tex_of(ip)
	var sz := Vector2(200, 280)
	if tex != null and tex.get_width() > tex.get_height() * 1.1:
		sz = Vector2(240, 160)
	elif tex != null and absf(tex.get_width() - tex.get_height()) < 10:
		sz = Vector2(170, 170)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	var bt := Button.new()
	bt.custom_minimum_size = sz + Vector2(10, 10)
	bt.focus_mode = Control.FOCUS_NONE
	bt.icon = tex
	bt.expand_icon = true
	bt.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bt.tooltip_text = lbl
	bt.pressed.connect(func(): v.submit(a))
	bt.mouse_entered.connect(func(): v.show_zoom(ip, "[b]%s[/b]" % lbl, Vector2(330, 462) if sz.y > sz.x else Vector2(450, 300)))
	bt.mouse_exited.connect(func(): v.hide_zoom())
	vb.add_child(bt)
	var l := MKUI.label(lbl, 18, MKUI.BONE, MKUI.font_bold)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.custom_minimum_size = Vector2(sz.x + 10, 0)
	vb.add_child(l)
	if desc != "":
		var d := MKUI.label(desc, 16, MKUI.BONE)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(sz.x + 10, 0)
		vb.add_child(d)
	return vb


# ================================================================== tattiche

static func tactics(v) -> void:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var day := bool(s.get("day", true))
	var all := []
	for id in MKDB.tactics:
		var d: Dictionary = MKDB.tactics[id]
		if bool(d.get("day", true)) == day:
			all.append(id)
	all.sort_custom(func(a, b): return eng.tactic_number(a) < eng.tactic_number(b))
	var avail: Array = s.get("tactics_avail", [])
	var owner := {}
	for i in range(s.players.size()):
		var t := str(s.players[i].get("tactic", ""))
		if t != "":
			owner[t] = eng.pname(i)
	if s.get("dummy") != null and str(s.dummy.get("tactic", "")) != "":
		owner[str(s.dummy.tactic)] = "Neutrale"
	var me: int = v.actor()
	var vb := _panel(v, "tactics", 1460, 0.35, false, "%s: scegli la tua Tattica (%s)" % [eng.pname(me), "Giorno" if day else "Notte"])
	var sub := MKUI.label("Il numero decide l'ordine di turno (prima il più basso). Passa sopra una carta per leggerla.", 19, MKUI.MUTED, MKUI.font_italic)
	vb.add_child(sub)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	for id in all:
		var ok: bool = id in avail
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 4)
		row.add_child(col)
		var bt := Button.new()
		bt.custom_minimum_size = Vector2(212, 296)
		bt.focus_mode = Control.FOCUS_NONE
		bt.icon = MKHud.tex_of(MKHud.tactic_img(id))
		bt.expand_icon = true
		bt.disabled = not ok
		var txt := str(MKDB.tactics[id].get("text_it", ""))
		bt.tooltip_text = "%d · %s\n%s" % [eng.tactic_number(id), eng.tactic_name(id), txt]
		var a := {"t": "tactic", "id": id}
		bt.pressed.connect(func(): v.submit(a))
		if not ok:
			bt.modulate = Color(0.45, 0.45, 0.45)
		col.add_child(bt)
		var l := MKUI.label("%d · %s" % [eng.tactic_number(id), eng.tactic_name(id)], 19, MKUI.GOLD_LIGHT if ok else MKUI.MUTED, MKUI.font_bold)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
		var st := ""
		if owner.has(id):
			st = "presa da " + str(owner[id])
		elif not ok:
			st = "non disponibile"
		if st != "":
			var l2 := MKUI.label(st, 17, MKUI.MUTED, MKUI.font_italic)
			l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			col.add_child(l2)
		var t2 := MKUI.label(txt, 15, MKUI.BONE)
		t2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t2.custom_minimum_size = Vector2(212, 0)
		col.add_child(t2)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	hb.add_child(MKHud.btn("Guarda la mappa", func():
		v.close_modal("tactics")
		var holder: Control = v.open_modal("tactics", 0.0, false)
		holder.get_child(0).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b := MKHud.btn("Torna alla scelta della tattica", func(): tactics(v), 0, 52, true)
		b.anchor_left = 0.5
		b.anchor_right = 0.5
		b.offset_left = -220
		b.offset_right = 220
		b.offset_top = 140
		b.offset_bottom = 192
		holder.add_child(b), 0, 44))


# ================================================================== hotseat

static func pass_device(v) -> void:
	var eng: MKEngine = v.eng
	var a: int = v.actor()
	var holder: Control = v.open_modal("pass", 0.97, false)
	var cc := CenterContainer.new()
	cc.set_anchors_preset(Control.PRESET_FULL_RECT)
	cc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	holder.add_child(cc)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 22)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	cc.add_child(vb)
	var t := MKUI.title("PASSA IL DISPOSITIVO", 64, MKUI.GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var hero := str(v.s.players[a].get("hero", ""))
	var im := MKHud.image(MKHud.hero_token(hero), Vector2(180, 180))
	im.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	vb.add_child(im)
	var l := MKUI.label("Tocca a %s" % eng.pname(a), 36, MKUI.hero_col(hero).lightened(0.3), MKUI.font_title)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l)
	var l2 := MKUI.label("Gli altri giocatori non guardino: la mano verrà mostrata.", 22, MKUI.MUTED, MKUI.font_italic)
	l2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(l2)
	var b := MKUI.big_button("SONO IO: MOSTRA LA MANO", 520, true)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	b.pressed.connect(func(): v.confirm_pass())
	vb.add_child(b)


# ================================================================== schermate

static func offers(v) -> void:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var vb := _panel(v, "screen", 1500, 0.6, true, "Offerte")
	var sc := _scroll(minf(800.0, v.get_viewport_rect().size.y - 250.0))
	vb.add_child(sc)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(body)
	var of: Dictionary = s.get("offers", {})
	# rows: units on top; AA and spells side by side; monastery AA and common skills side by side
	var rows: Array = []
	for i in 3:
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 40)
		body.add_child(hb)
		rows.append(hb)
	var slot := {"units": 0, "aa": 1, "spells": 1, "monastery": 2, "skills": 2}
	var sect := func(title: String, ids: Array, kind: String, key: String):
		if ids.is_empty():
			return
		var col := VBoxContainer.new()
		col.add_theme_constant_override("separation", 6)
		rows[slot[key]].add_child(col)
		col.add_child(MKUI.label(title, 24, MKUI.GOLD, MKUI.font_title))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		for id in ids:
			var sid := str(id)
			var path := ""
			var tip := ""
			match kind:
				"unit":
					path = MKHud.unit_img(sid)
					var d: Dictionary = MKDB.units.get(sid, {})
					tip = "[b]%s[/b] · livello %d · costo %d · armatura %d" % [str(d.get("name_it", sid)), int(d.get("level", 1)), int(d.get("cost", 0)), int(d.get("armor", 0))]
					for ab in d.get("abilities", []):
						tip += "\n• " + str(ab.get("text_it", ""))
				"skill":
					path = MKHud.skill_img(sid)
					tip = "[b]%s[/b]\n%s" % [str(MKDB.skills.get(sid, {}).get("name_it", sid)), str(MKDB.skills.get(sid, {}).get("text_it", ""))]
				_:
					path = MKHud.card_img(eng, sid)
					tip = "[b]%s[/b]\n%s" % [MKHud.card_name(sid), MKHud.card_text(sid)]
			var sz := Vector2(150, 100) if kind == "skill" else Vector2(150, 210)
			var im := MKHud.image(path, sz)
			im.mouse_entered.connect(func(): v.show_zoom(path, tip, Vector2(360, 240) if kind == "skill" else Vector2(330, 462)))
			im.mouse_exited.connect(func(): v.hide_zoom())
			row.add_child(im)
	sect.call("Unità", of.get("units", []), "unit", "units")
	sect.call("Azioni avanzate", of.get("aa", []), "card", "aa")
	sect.call("Incantesimi", of.get("spells", []), "card", "spells")
	sect.call("Azioni avanzate del monastero (6 Influenza in un monastero)", of.get("monastery", []), "card", "monastery")
	sect.call("Abilità comuni", of.get("skills", []), "skill", "skills")
	var d2: Dictionary = s.get("decks", {})
	body.add_child(MKUI.label("Mazzi: Azioni avanzate %d · Incantesimi %d · Artefatti %d · Unità regolari %d · Unità d'élite %d" % [
		d2.get("aa", []).size(), d2.get("spells", []).size(), d2.get("artifacts", []).size(), d2.get("units_reg", []).size(), d2.get("units_elite", []).size()], 18, MKUI.MUTED))
	vb.add_child(_shrink(MKHud.btn("Chiudi", func(): v.close_modal("screen"), 160, 46, true)))


static func diary(v) -> void:
	var vb := _panel(v, "screen", 1100, 0.6, true, "Diario")
	var sc := _scroll(720)
	vb.add_child(sc)
	var r := MKUI.rich(19)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(r)
	var lines := []
	for e in v.s.get("log", []):
		lines.append(MKPanels.log_line(v, e))
	r.text = "\n".join(lines)
	sc.call_deferred("set", "scroll_vertical", 1000000)
	vb.add_child(_shrink(MKHud.btn("Chiudi", func(): v.close_modal("screen"), 160, 46, true)))


static func rules(v) -> void:
	var s: Dictionary = v.s
	var vb := _panel(v, "screen", 1240, 0.6, true, "Regole")
	var sc := _scroll(740)
	vb.add_child(sc)
	var r := MKUI.rich(20)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(r)
	r.text = scenario_text(str(s.get("scn", {}).get("id", s.cfg.get("scenario", "")))) + "\n\n" + RULES_IT
	vb.add_child(_shrink(MKHud.btn("Chiudi", func(): v.close_modal("screen"), 160, 46, true)))


static func scenario_text(id: String) -> String:
	var sc: Dictionary = MKDB.scenarios.get(id, {})
	if sc.is_empty():
		return ""
	var t := "[font_size=26][color=#f2d78c]%s[/color][/font_size]\n%s" % [str(sc.get("name_it", id)), str(sc.get("desc_it", ""))]
	if str(sc.get("end", "")) != "":
		t += "\n[i]Fine della partita: %s[/i]" % str(sc.end)
	return t


static func game_menu(v) -> void:
	var vb := _panel(v, "screen", 560, 0.6, true, "Menu")
	vb.add_child(MKUI.label("Velocità dell'IA", 20, MKUI.GOLD, MKUI.font_bold))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 6)
	vb.add_child(hb)
	for k in range(MKController.SPEED_NAMES.size()):
		var b := MKHud.btn(MKController.SPEED_NAMES[k], func():
			v.ctrl.set_speed(k)
			game_menu(v), 124, 44, v.ctrl.speed == k, 18)
		hb.add_child(b)
	vb.add_child(HSeparator.new())
	vb.add_child(MKUI.big_button("RIPRENDI", 520, true, 62))
	vb.get_child(vb.get_child_count() - 1).pressed.connect(func(): v.close_modal("screen"))
	var b2 := MKUI.big_button("SALVA ED ESCI AL MENU", 520, false, 62)
	b2.pressed.connect(func():
		v.ctrl.save_now()
		if v.main != null:
			v.main.back_to_menu())
	vb.add_child(b2)
	var b3 := MKUI.big_button("ABBANDONA LA PARTITA", 520, false, 62)
	b3.pressed.connect(func():
		confirm(v, "Abbandonare la partita?", "Il salvataggio automatico verrà cancellato.", func():
			MKController.clear_save()
			v.ctrl.autosave = false
			if v.main != null:
				v.main.back_to_menu()))
	vb.add_child(b3)
	vb.add_child(MKUI.label("Salvataggio automatico: la partita si riprende dal menu con «Continua partita».", 16, MKUI.MUTED, MKUI.font_italic))


static func end_screen(v) -> void:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var res = s.get("result")
	var vb := _panel(v, "end", 1300, 0.7, false, "Fine della partita")
	if not (res is Dictionary):
		vb.add_child(MKUI.label("La partita è terminata.", 22))
	else:
		var head := ""
		if res.has("victory"):
			head = "[font_size=30][color=%s]%s[/color][/font_size]" % ["#9fe870" if res.victory else "#ff8a7a", "Vittoria!" if res.victory else "Obiettivo non raggiunto"]
			if res.has("cities_total"):
				head += "\nCittà conquistate: %d/%d" % [int(res.get("cities_conquered", 0)), int(res.cities_total)]
		var winners := []
		for w in res.get("winners", []):
			winners.append(eng.pname(int(w)))
		if s.players.size() > 1 and not winners.is_empty() and str(s.scn.get("mode", "")) != "coop":
			head += ("\n" if head != "" else "") + "[font_size=28][color=#f2d78c]Vince: %s[/color][/font_size]" % ", ".join(winners)
		head += "\nRound giocati: %d" % int(res.get("rounds", s.round))
		if res.has("team_score"):
			head += "\nPunteggio della squadra: [b]%d[/b]" % int(res.team_score)
		var r := MKUI.rich(22)
		r.text = head
		vb.add_child(r)
		var g := GridContainer.new()
		var cols := ["Eroe", "Fama", "Sapiente", "Predone", "Leader", "Conquistatore", "Avventuriero", "Ferite", "Titoli"]
		var show_cities := str(s.scn.get("scoring", "")).find("cities") >= 0
		var show_obj := str(s.scn.get("mode", "")) == "solo" and str(s.scn.get("end", "")) == "cities"
		if show_cities:
			cols.append("Città")
		if show_obj:
			cols.append("Obiettivo")
		cols.append("Totale")
		g.columns = cols.size()
		g.add_theme_constant_override("h_separation", 18)
		g.add_theme_constant_override("v_separation", 6)
		vb.add_child(g)
		for c in cols:
			g.add_child(MKUI.label(c, 18, MKUI.GOLD, MKUI.font_bold))
		var scores: Array = res.get("scores", [])
		for i in range(scores.size()):
			var sc: Dictionary = scores[i]
			var ach: Dictionary = sc.get("achievements", {})
			g.add_child(MKUI.label(eng.pname(i), 20, MKUI.hero_col(str(s.players[i].hero)).lightened(0.3), MKUI.font_bold))
			g.add_child(MKUI.label(str(int(sc.get("fame", 0))), 20))
			for k in ["knowledge", "loot", "leader", "conqueror", "adventurer", "beating"]:
				g.add_child(MKUI.label(str(int(ach.get(k, 0))), 20))
			var tit = sc.get("titles", {})
			var tt := []
			if tit is Dictionary:
				for k in tit:
					tt.append("%s %+d" % [_title_it(str(k)), int(tit[k])])
			g.add_child(MKUI.label(", ".join(tt) if not tt.is_empty() else "—", 18, MKUI.MUTED))
			if show_cities:
				g.add_child(MKUI.label(str(int(sc.get("cities", 0))), 20))
			if show_obj:
				var ol := MKUI.label(str(int(sc.get("objective", 0))), 20)
				ol.tooltip_text = "10 per città conquistata; se le conquisti tutte +15, +30 per ogni round d'anticipo, +1 per carta rimasta nel mazzo del Neutrale, +5 se la fine dell'ultimo round non era stata annunciata."
				ol.mouse_filter = Control.MOUSE_FILTER_PASS
				g.add_child(ol)
			g.add_child(MKUI.label(str(int(sc.get("total", 0))), 24, MKUI.GOLD_LIGHT, MKUI.font_bold))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	vb.add_child(hb)
	hb.add_child(MKHud.btn("Guarda la mappa", func():
		v.close_modal("end")
		var holder: Control = v.open_modal("end", 0.0, false)
		holder.get_child(0).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var b := MKHud.btn("Risultati", func(): end_screen(v), 220, 52, true)
		b.anchor_left = 0.5
		b.anchor_right = 0.5
		b.offset_left = -110
		b.offset_right = 110
		b.offset_top = 140
		b.offset_bottom = 192
		holder.add_child(b), 0, 50))
	hb.add_child(MKHud.btn("Diario", func(): diary(v), 0, 50))
	hb.add_child(MKHud.btn("TORNA AL MENU", func():
		MKController.clear_save()
		if v.main != null:
			v.main.back_to_menu(), 0, 50, true))


static func _title_it(k: String) -> String:
	return {"knowledge": "Sapiente", "loot": "Predone", "leader": "Leader", "conqueror": "Conquistatore",
		"adventurer": "Avventuriero", "beating": "Ferite"}.get(k, k)
