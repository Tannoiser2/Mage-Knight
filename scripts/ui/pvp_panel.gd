class_name MKPvPPanel
extends RefCounted
## Pannello centrale del combattimento tra giocatori: i due eroi (armatura, unità, Ferite in mano), la fase
## (a distanza/d'assedio → corpo a corpo), chi attacca e chi blocca, l'attacco in corso con la riduzione del
## Blocco, i punti del turno e i bottoni Attacca / Passa / Blocca. Funziona per entrambi i lati: agisce chi è
## eng.actor() (in hotseat compare prima la schermata «Passa il dispositivo»). Statico; v = MKGameView.


static func build(v, holder: Control) -> void:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var pv: Dictionary = s.pvp
	var loc: bool = v.local()
	var p := PanelContainer.new()
	var sb := MKUI.frame_style(0.86, 10)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.anchor_right = 1.0
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(p)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	# intestazione
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	head.add_child(MKUI.title("⚔ Combattimento tra giocatori", 26, MKUI.GOLD_LIGHT))
	var mode_it := "affrontato completamente" if str(pv.mode) == "full" else ("affrontato parzialmente" if str(pv.mode) == "partial" else "")
	if mode_it != "":
		head.add_child(MKUI.label("— %s %s" % [eng.pname(int(pv.def)), mode_it], 18, MKUI.MUTED, MKUI.font_italic))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	for ph in [["ranged", "1. Distanza / Assedio"], ["melee", "2. Corpo a corpo"]]:
		var on: bool = str(pv.phase) == ph[0]
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", MKUI.panel_style(MKUI.GOLD if on else Color(0, 0, 0, 0.4), MKUI.GOLD_LIGHT if on else Color(MKUI.GOLD_DARK, 0.6), 1, 4, 6))
		pc.add_child(MKUI.label(ph[1], 18, MKUI.INK if on else MKUI.BONE, MKUI.font_bold))
		head.add_child(pc)
	head.add_child(MKHud.btn("▾" if not v.combat_min else "▴", func():
		v.combat_min = not v.combat_min
		v._build_center(), 44, 40))
	# regola della fase
	var hint := ""
	if str(pv.phase) == "ranged":
		hint = "Si alternano gli attacchi a distanza e d'assedio (inizia il difensore). Il Blocco riduce l'attacco di 1 ogni 2 punti."
		if pv.get("fort", false):
			hint += " Il difensore è in un sito fortificato: contro di lui solo Assedio."
	else:
		hint = "Corpo a corpo (inizia l'aggressore): vale ogni attacco, anche le carte di lato (Attacco 1). Il Blocco riduce di 1 per punto. Con i danni puoi ferire, rubare Artefatti (5) o costringere alla ritirata (costo del terreno) e vincere."
	var hl := MKUI.label(hint, 17, Color("#d9c9a0"), MKUI.font_italic)
	hl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(hl)
	if v.combat_min:
		vb.add_child(_footer(v, loc))
		return
	# i due eroi
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_child(row)
	var striker := int(pv.striker)
	row.add_child(_hero_box(v, int(pv.att), "Aggressore", striker))
	var mid := VBoxContainer.new()
	mid.alignment = BoxContainer.ALIGNMENT_CENTER
	mid.custom_minimum_size = Vector2(260, 0)
	row.add_child(mid)
	var st = pv.get("strike", null)
	if str(pv.step) == "block" and st != null:
		var els := []
		for el in st.get("elems", []):
			var e2 := str(MKHud.ELEM_SHORT.get(el, ""))
			els.append(e2 if e2 != "" else "fisico")
		var al := MKUI.label("Attacco %d (%s)" % [int(st.n), ", ".join(els)], 26, Color("#ff7a5a"), MKUI.font_bold)
		al.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(al)
		var red: int = MKPvP.block_reduction(eng)
		var bl := MKUI.label("Blocco: −%d  →  %d danni" % [red, maxi(0, int(st.n) - red)], 22, Color("#8fc0ff"), MKUI.font_bold)
		bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(bl)
		var who := MKUI.label("%s blocca" % eng.pname(_other(pv, striker)), 18, MKUI.MUTED, MKUI.font_italic)
		who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(who)
	else:
		var arrow := MKUI.label("⟶" if striker == int(pv.att) else "⟵", 54, MKUI.GOLD_LIGHT, MKUI.font_title)
		arrow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(arrow)
		var who2 := MKUI.label("Attacca %s" % eng.pname(striker), 20, MKUI.GOLD, MKUI.font_bold)
		who2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		mid.add_child(who2)
		if str(pv.step) == "attack":
			var sv: int = MKPvP.strike_value(eng)
			var vl := MKUI.label("Attacco pronto: %d" % sv, 20, Color("#ff9a7a") if sv > 0 else MKUI.MUTED, MKUI.font_bold)
			vl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			mid.add_child(vl)
		if int(pv.passes) > 0:
			var pl2 := MKUI.label("(l'avversario ha passato: se passi anche tu, la fase finisce)", 15, MKUI.MUTED, MKUI.font_italic)
			pl2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			pl2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			mid.add_child(pl2)
	row.add_child(_hero_box(v, int(pv.def), "Difensore", striker))
	# ultime voci del combattimento
	var lines := []
	for e in s.get("log", []):
		if int(e.get("seq", 0)) >= int(pv.get("log_from", 0)) and str(e.get("k", "")) in ["pvp_strike", "pvp_block", "pvp_pass", "wound", "unit_wound", "pvp_steal", "knockout", "combat_phase", "pvp"]:
			lines.append("• " + str(e.get("txt", "")))
	if not lines.is_empty():
		var lg := MKUI.label("\n".join(lines.slice(maxi(0, lines.size() - 4))), 16, MKUI.BONE)
		lg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(lg)
	vb.add_child(_footer(v, loc))


static func _other(pv: Dictionary, who: int) -> int:
	return int(pv.def) if who == int(pv.att) else int(pv.att)


static func _hero_box(v, i: int, role: String, striker: int) -> Control:
	var eng: MKEngine = v.eng
	var pl: Dictionary = v.s.players[i]
	var hero := str(pl.get("hero", ""))
	var on := i == striker
	var pc := PanelContainer.new()
	var col := MKUI.hero_col(hero)
	pc.add_theme_stylebox_override("panel", MKUI.panel_style(Color(col, 0.16) if on else Color(0.05, 0.03, 0.04, 0.85), MKUI.GOLD_LIGHT if on else Color(col, 0.7), 3 if on else 1, 8, 8))
	pc.custom_minimum_size = Vector2(300, 0)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	pc.add_child(hb)
	hb.add_child(MKHud.image(MKHud.hero_token(hero), Vector2(96, 96)))
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 1)
	hb.add_child(info)
	info.add_child(MKUI.label(role, 15, MKUI.MUTED, MKUI.font_italic))
	info.add_child(MKUI.label(eng.pname(i), 22, MKUI.BONE, MKUI.font_bold))
	var w := 0
	var nw := 0
	for iid in pl.get("hand", []):
		if eng.is_wound(str(iid)):
			w += 1
		else:
			nw += 1
	info.add_child(MKUI.label("Armatura %d · Livello %d · Fama %d" % [MKPvP.hero_armor(eng, i), int(pl.get("level", 1)), int(pl.get("fame", 0))], 17, Color("#e8e0cc")))
	info.add_child(MKUI.label("Mano: %d carte%s" % [nw + w, (" (%d Ferite)" % w) if w > 0 else ""], 17, MKUI.RED if w > 0 else MKUI.MUTED))
	var units := []
	for u in pl.get("units", []):
		units.append("%s%s" % [eng.unit_name(u), " (ferita)" if u.get("wounded", false) else ("" if u.get("ready", true) else " (esausta)")])
	if not units.is_empty():
		var ul := MKUI.label("Unità: " + ", ".join(units), 15, MKUI.MUTED)
		ul.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		ul.custom_minimum_size = Vector2(180, 0)
		info.add_child(ul)
	return pc


static func _footer(v, loc: bool) -> Control:
	var eng: MKEngine = v.eng
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var pv_ := MKPanels.pool_view(v)
	pv_.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(pv_)
	if not loc:
		hb.add_child(MKUI.label("In attesa di %s…" % eng.pname(v.actor()), 19, MKUI.MUTED, MKUI.font_italic))
		return hb
	for x in v.avail():
		var a: Dictionary = x["a"]
		if str(a.get("t", "")) != "pvp":
			continue
		var op := str(a.get("op", ""))
		var lbl: String = str({"strike": "ATTACCA", "pass": "Passa", "block": "BLOCCA"}.get(op, op))
		if op == "strike":
			lbl = "ATTACCA (%d)" % MKPvP.strike_value(eng)
		elif op == "block":
			var st = v.s.pvp.get("strike", null)
			var red: int = MKPvP.block_reduction(eng)
			lbl = "BLOCCA (−%d)" % red if red > 0 else "Subisci l'attacco (%d)" % (int(st.n) if st != null else 0)
		var b := MKHud.btn(lbl, func(): v.submit(a), 0, 48, op != "pass", 21)
		b.tooltip_text = str(x.get("label", ""))
		hb.add_child(b)
	return hb
