class_name MKCombatPanel
extends RefCounted
## Pannelli centrali: combattimento (nemici, fasi, bersagli, blocchi, danni) e interazione con un sito
## (unità da reclutare, acquisti, guarigione, saccheggio/incendio). Statico; v = MKGameView.


static func _frame(holder: Control, alpha := 0.86) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := MKUI.frame_style(alpha, 10)
	sb.set_content_margin_all(12)
	p.add_theme_stylebox_override("panel", sb)
	p.anchor_right = 1.0
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	holder.add_child(p)
	return p


# ================================================================== combattimento

static func build(v, holder: Control) -> void:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var c: Dictionary = s.combat
	var loc: bool = v.local()
	var phase := str(c.get("phase", ""))
	var p := _frame(holder, 0.84)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	# intestazione: titolo + fasi + riduci
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	vb.add_child(head)
	var kind: String = {"assault": "Assalto", "provoke": "Provocazione", "challenge": "Sfida", "site": "Combattimento nel sito", "burn": "Incendio del monastero"}.get(str(c.get("kind", "")), "Combattimento")
	if c.get("assault", false):
		kind = "Assalto"
	var who := eng.pname(int(s.turn.get("player", 0)))
	head.add_child(MKUI.title("⚔ %s" % kind, 26, MKUI.GOLD_LIGHT))
	head.add_child(MKUI.label("— " + who, 20, MKUI.MUTED, MKUI.font_italic))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	var steps := HBoxContainer.new()
	steps.add_theme_constant_override("separation", 2)
	head.add_child(steps)
	for i in range(MKHud.PHASES.size()):
		var ph: String = MKHud.PHASES[i]
		var on := ph == phase
		var done := MKHud.PHASES.find(phase) > i
		var pc := PanelContainer.new()
		pc.add_theme_stylebox_override("panel", MKUI.panel_style(MKUI.GOLD if on else Color(0, 0, 0, 0.4), MKUI.GOLD_LIGHT if on else Color(MKUI.GOLD_DARK, 0.6), 1, 4, 6))
		var l := MKUI.label("%d. %s" % [i + 1, MKHud.PHASE_IT[ph]], 18, MKUI.INK if on else (MKUI.MUTED if done else MKUI.BONE), MKUI.font_bold)
		pc.add_child(l)
		steps.add_child(pc)
	head.add_child(MKHud.btn("▾" if not v.combat_min else "▴", func():
		v.combat_min = not v.combat_min
		v._build_center(), 44, 40))
	# note sulle regole del combattimento
	var notes := []
	if c.get("fortified_site", false):
		notes.append("Sito fortificato: a distanza solo Assedio")
	if not c.get("units_allowed", true):
		notes.append("Le unità non partecipano")
	if c.get("night_rules", false):
		notes.append("Regole notturne per il mana")
	var hint := _phase_hint(phase)
	if not notes.is_empty() or hint != "":
		var nl := MKUI.label(" · ".join(notes + [hint]) if not notes.is_empty() else hint, 18, Color("#d9c9a0"), MKUI.font_italic)
		nl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vb.add_child(nl)
	if v.combat_min:
		vb.add_child(_footer(v, phase, loc))
		return
	# nemici
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 10)
	row.add_theme_constant_override("v_separation", 10)
	vb.add_child(row)
	# selezione: tieni solo i bersagli ancora validi
	var keep := []
	for eid in v.combat_sel:
		var e = MKCombat.entry(eng, str(eid))
		if e != null and MKCombat.targetable(eng, e):
			keep.append(eid)
	v.combat_sel = keep
	# a single possible target is selected automatically
	if keep.is_empty() and loc and phase in ["ranged", "attack"]:
		var only := []
		for e in c.get("enemies", []):
			if MKCombat.targetable(eng, e):
				only.append(str(e.eid))
		if only.size() == 1:
			v.combat_sel = only
	var av: Array = v.avail()
	for e in c.get("enemies", []):
		if e.get("hidden", false):
			continue
		row.add_child(_enemy_card(v, e, phase, loc, av))
	vb.add_child(_footer(v, phase, loc))


static func _phase_hint(phase: String) -> String:
	match phase:
		"ranged":
			return "Fase 1: attacchi a distanza e d'assedio (seleziona i bersagli e attacca, oppure passa)."
		"block":
			return "Fase 2: blocca gli attacchi nemici con i punti Blocco."
		"damage":
			return "Fase 3: assegna i danni non bloccati all'eroe o alle unità."
		"attack":
			return "Fase 4: attacca con tutti i tipi di attacco (seleziona i bersagli)."
	return ""


static func _enemy_card(v, e: Dictionary, phase: String, loc: bool, av: Array) -> Control:
	var eng: MKEngine = v.eng
	var eid := str(e.get("eid", ""))
	var defeated: bool = e.get("defeated", false)
	var sel: bool = eid in v.combat_sel
	var tgt: bool = loc and not defeated and MKCombat.targetable(eng, e)
	var pc := PanelContainer.new()
	var bc := MKUI.GOLD_LIGHT if sel else (Color("#ff6a50") if tgt else Color(MKUI.GOLD_DARK, 0.7))
	var sb := MKUI.panel_style(Color(0.05, 0.03, 0.04, 0.85) if not sel else Color(0.25, 0.18, 0.05, 0.9), bc, 3 if sel else 1, 8, 8)
	pc.add_theme_stylebox_override("panel", sb)
	pc.custom_minimum_size = Vector2(212, 0)
	pc.mouse_filter = Control.MOUSE_FILTER_STOP
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 3)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pc.add_child(vb)
	var top := Control.new()
	top.custom_minimum_size = Vector2(190, 120)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.add_child(top)
	var im := MKHud.image(MKHud.enemy_img(str(e.get("type", ""))), Vector2(120, 120))
	im.position = Vector2(0, 0)
	im.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if defeated:
		im.modulate = Color(0.4, 0.4, 0.4)
	top.add_child(im)
	# armatura e fama
	var arm := MKCombat.armor_of(eng, e)
	var st := VBoxContainer.new()
	st.position = Vector2(126, 0)
	st.add_theme_constant_override("separation", -2)
	st.mouse_filter = Control.MOUSE_FILTER_IGNORE
	top.add_child(st)
	st.add_child(MKUI.label("Armatura", 14, MKUI.MUTED))
	var al := MKUI.label(str(arm), 34, Color("#e8e0cc") if int(e.get("armor_mod", 0)) == 0 else Color("#ffb070"), MKUI.font_bold)
	st.add_child(al)
	st.add_child(MKUI.label("Fama %d" % int(e.get("fame", 0)), 17, MKUI.GOLD_LIGHT, MKUI.font_bold))
	if MKCombat.is_fortified(e):
		st.add_child(MKUI.label("Fortif.%s" % ("×2" if MKCombat.is_double_fortified(e) else ""), 15, Color("#c8b8ff"), MKUI.font_bold))
	var nm := MKUI.label(str(e.get("name", "")), 20, MKUI.BONE, MKUI.font_bold)
	nm.clip_text = true
	nm.custom_minimum_size = Vector2(190, 0)
	vb.add_child(nm)
	# attacchi
	var atks: Array = e.get("attacks", [])
	for ai in range(atks.size()):
		var at: Dictionary = atks[ai]
		var val := MKCombat.attack_value(eng, e, ai)
		var el := MKCombat.attack_elem(e, ai)
		var ah := HBoxContainer.new()
		ah.add_theme_constant_override("separation", 4)
		vb.add_child(ah)
		var txt := "Attacco %d %s" % [val, MKHud.ELEM_SHORT.get(el, "")]
		if val <= 0:
			txt = "Nessun attacco"
		var acol := MKHud.elem_col(el)
		var lab := MKUI.label(txt, 18, acol, MKUI.font_bold)
		lab.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ah.add_child(lab)
		var state := ""
		if at.get("blocked", false):
			state = "bloccato"
		elif int(at.get("rem", 0)) > 0:
			state = "%d danni" % int(at.rem)
		if state != "":
			ah.add_child(MKUI.label("· " + state, 16, MKUI.GREEN if at.get("blocked", false) else MKUI.RED, MKUI.font_bold))
		if defeated or not loc:
			continue
		# bottoni di fase
		if phase == "block" and not at.get("blocked", false) and val > 0:
			var need := MKCombat.block_needed(eng, e, ai)
			var have: int = eng.effective_block(eid, ai)
			var a := {"t": "block", "eid": eid, "attack": ai}
			var ok := eng.check(a) == ""
			var b := MKHud.btn("Blocca %d/%d" % [have, need], func(): v.submit(a), 0, 38, ok, 17)
			b.disabled = not ok
			b.tooltip_text = "Blocco efficace %d, ne serve %d%s" % [have, need, " (Rapido: doppio)" if MKCombat.has_ab(e, "swift") else ""]
			vb.add_child(b)
		elif phase == "damage" and int(at.get("rem", 0)) > 0:
			var g := HFlowContainer.new()
			g.add_theme_constant_override("h_separation", 3)
			g.add_theme_constant_override("v_separation", 3)
			vb.add_child(g)
			for x in av:
				var a2: Dictionary = x["a"]
				if str(a2.get("t", "")) != "damage" or str(a2.get("eid", "")) != eid or int(a2.get("attack", 0)) != ai:
					continue
				var to = a2.get("to")
				var lb := "All'eroe" if str(to) == "hero" else eng.unit_name_by_uid(int(v.actor()), int(to))
				if str(to) == "hero":
					var nw := int(ceil(float(int(at.rem)) / float(maxi(1, eng.armor_of(int(v.actor()))))))
					lb = "All'eroe (%d Ferit%s)" % [nw, "a" if nw == 1 else "e"]
				var b2 := MKHud.btn(lb, func(): v.submit(a2), 0, 36, str(to) == "hero", 16)
				b2.tooltip_text = str(x.get("label", ""))
				g.add_child(b2)
	# abilità e resistenze
	var tr := MKHud.enemy_traits(e)
	if not tr.is_empty():
		var names := []
		var tips := []
		for t in tr:
			names.append(t[0])
			tips.append("%s: %s" % [t[0], t[1]])
		var tl := MKUI.label(", ".join(names), 16, Color("#c8b8ff"), MKUI.font_bold)
		tl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tl.custom_minimum_size = Vector2(190, 0)
		vb.add_child(tl)
		pc.tooltip_text = "\n".join(tips)
	if defeated:
		var dl := MKUI.label("SCONFITTO", 22, MKUI.GREEN, MKUI.font_title)
		vb.add_child(dl)
	elif tgt:
		var hl := MKUI.label("✔ bersaglio" if sel else "Clic: seleziona", 16, MKUI.GOLD_LIGHT if sel else MKUI.MUTED, MKUI.font_italic)
		vb.add_child(hl)
		pc.gui_input.connect(func(ev):
			if MKGameView._is_click(ev):
				if eid in v.combat_sel:
					v.combat_sel.erase(eid)
				else:
					v.combat_sel.append(eid)
				v._build_center())
	return pc


static func _footer(v, phase: String, loc: bool) -> Control:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	var pv := MKPanels.pool_view(v)
	pv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(pv)
	if not loc:
		return hb
	if phase in ["ranged", "attack"] and not v.combat_sel.is_empty():
		var need := 0
		for eid in v.combat_sel:
			var e = MKCombat.entry(eng, str(eid))
			if e != null:
				need += MKCombat.armor_of(eng, e)
		var eff: int = eng.effective_attack(v.combat_sel)
		var col := MKUI.GREEN if eff >= need else MKUI.RED
		hb.add_child(MKUI.label("Attacco efficace %d / Armatura %d" % [eff, need], 21, col, MKUI.font_bold))
		var a := {"t": "attack", "targets": v.combat_sel.duplicate()}
		var ok := eng.check(a) == ""
		var b := MKHud.btn("ATTACCA", func():
			v.submit(a)
			v.combat_sel = [], 150, 48, ok, 22)
		b.disabled = not ok
		if not ok:
			b.tooltip_text = eng.check(a)
		hb.add_child(b)
	elif phase in ["ranged", "attack"]:
		hb.add_child(MKUI.label("Seleziona i nemici da attaccare", 18, MKUI.MUTED, MKUI.font_italic))
	var na := {"t": "next"}
	if eng.check(na) == "":
		var lbl: String = {"ranged": "Passa al Blocco ▶", "block": "Passa ai Danni ▶", "damage": "Passa all'Attacco ▶", "attack": "Termina il combattimento ▶"}.get(phase, "Avanti ▶")
		hb.add_child(MKHud.btn(lbl, func(): v.submit(na), 0, 48, phase == "damage" or v.combat_sel.is_empty() or eng.check({"t": "attack", "targets": v.combat_sel.duplicate()}) != "", 20))
	elif phase == "damage":
		hb.add_child(MKUI.label("Assegna tutti i danni", 18, MKUI.RED, MKUI.font_italic))
	return hb


# ================================================================== sito

static func build_site(v, holder: Control) -> void:
	var s: Dictionary = v.s
	var eng: MKEngine = v.eng
	var me: int = v.actor()
	var h: Dictionary = eng.hex(str(s.players[me].pos))
	var site := str(h.get("site", ""))
	var p := _frame(holder, 0.9)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 8)
	p.add_child(vb)
	var head := HBoxContainer.new()
	vb.add_child(head)
	var tl := MKUI.title(MKUI.site_it(site), 28, MKUI.GOLD_LIGHT)
	tl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tl)
	var inf: int = MKSites.influence_avail(eng, me)
	head.add_child(MKUI.label("Influenza disponibile: %d" % inf, 22, Color("#c49bff"), MKUI.font_bold))
	head.add_child(MKHud.btn("✕ Chiudi", func(): v.close_site(), 0, 42))
	var bonus: int = MKSites.influence_bonus(eng, me)
	if not s.turn.get("rep_applied", false) and bonus != 0:
		vb.add_child(MKUI.label("Comprende il bonus di Reputazione %+d (si applica una volta per turno)." % bonus, 17, MKUI.MUTED, MKUI.font_italic))
	var av: Array = v.avail()
	# unità reclutabili
	var units := []
	for id in s.offers.get("units", []):
		if MKSites.unit_recruitable_here(eng, me, str(id)):
			units.append(str(id))
	if not units.is_empty():
		vb.add_child(MKUI.label("Unità da reclutare (Comando libero: %d)" % eng.command_free(me), 20, MKUI.GOLD, MKUI.font_bold))
		var sc := ScrollContainer.new()
		sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		sc.custom_minimum_size = Vector2(0, 268)
		vb.add_child(sc)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		sc.add_child(row)
		var seen := {}
		for id in units:
			if seen.has(id):
				continue
			seen[id] = true
			var col := VBoxContainer.new()
			col.add_theme_constant_override("separation", 3)
			row.add_child(col)
			var d: Dictionary = MKDB.units.get(id, {})
			var im := MKHud.image(MKHud.unit_img(id), Vector2(140, 196))
			var info := "[b]%s[/b] (livello %d, armatura %d)\n" % [str(d.get("name_it", id)), int(d.get("level", 1)), int(d.get("armor", 0))]
			for ab in d.get("abilities", []):
				info += "• %s\n" % str(ab.get("text_it", ""))
			im.mouse_entered.connect(func(): v.show_zoom(MKHud.unit_img(id), info, Vector2(300, 420)))
			im.mouse_exited.connect(func(): v.hide_zoom())
			col.add_child(im)
			var cost: int = MKSites.unit_cost(eng, me, id)
			var entries := []
			for x in av:
				var a: Dictionary = x["a"]
				if str(a.get("t", "")) == "recruit" and str(a.get("id", "")) == id:
					entries.append(x)
			if entries.is_empty():
				var why := eng.check({"t": "recruit", "id": id})
				var b := MKHud.btn("Recluta (%d)" % cost, func(): pass, 140, 38, false, 17)
				b.disabled = true
				b.tooltip_text = why
				col.add_child(b)
			else:
				for x in entries:
					var a2: Dictionary = x["a"]
					var lb := "Recluta (%d)" % cost
					if a2.has("disband"):
						lb = "Congeda %s" % eng.unit_name_by_uid(me, int(a2.disband))
					var b2 := MKHud.btn(lb, func(): v.submit(a2), 140, 38, not a2.has("disband"), 17)
					b2.tooltip_text = str(x.get("label", ""))
					col.add_child(b2)
	# acquisti
	var buys := []
	for x in av:
		if str(x["a"].get("t", "")) == "buy":
			buys.append(x)
	var opts: Array = MKSites._buy_options(eng, me)
	if not opts.is_empty():
		vb.add_child(MKUI.label("Acquisti", 20, MKUI.GOLD, MKUI.font_bold))
		var fl := HFlowContainer.new()
		fl.add_theme_constant_override("h_separation", 10)
		fl.add_theme_constant_override("v_separation", 8)
		vb.add_child(fl)
		for o in opts:
			var a3 := {"t": "buy", "what": str(o.what)}
			if o.has("id"):
				a3["id"] = str(o.id)
			var ok := eng.check(a3) == ""
			var box := VBoxContainer.new()
			box.add_theme_constant_override("separation", 3)
			fl.add_child(box)
			if o.has("id"):
				var cid := str(o.id)
				var im2 := MKHud.image(MKHud.card_img(eng, cid), Vector2(120, 168))
				im2.mouse_entered.connect(func(): v.show_zoom(MKHud.card_img(eng, cid), "[b]%s[/b]\n%s" % [MKHud.card_name(cid), MKHud.card_text(cid)]))
				im2.mouse_exited.connect(func(): v.hide_zoom())
				box.add_child(im2)
			var lb2 := "%s (%d%s)" % [str(o.label), int(o.cost), (" + mana " + MKMana.color_it(str(o.mana))) if str(o.get("mana", "")) != "" else ""]
			var b3 := MKHud.btn(lb2, func(): v.submit(a3), 0, 40, ok, 17)
			b3.disabled = not ok
			if not ok:
				b3.tooltip_text = eng.check(a3)
			b3.custom_minimum_size.x = 120 if o.has("id") else 0
			b3.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if o.has("id") else TextServer.AUTOWRAP_OFF
			box.add_child(b3)
	# guarigione con i punti già nel pool, saccheggio, incendio
	var other := HFlowContainer.new()
	other.add_theme_constant_override("h_separation", 8)
	for x in av:
		var a4: Dictionary = x["a"]
		match str(a4.get("t", "")):
			"heal":
				other.add_child(MKHud.btn(str(x.label), func(): v.submit(a4), 0, 42))
			"plunder":
				other.add_child(MKHud.btn(str(x.label), func(): MKScreens.confirm(v, "Saccheggiare il villaggio?", "Reputazione −1; peschi 2 carte. La gente del villaggio non lo dimenticherà.", func(): v.submit(a4)), 0, 42))
			"burn":
				other.add_child(MKHud.btn(str(x.label), func(): MKScreens.confirm(v, "Bruciare il monastero?", "Reputazione −3 e combattimento contro un nemico viola, senza unità. Se vinci ottieni un Artefatto.", func(): v.submit(a4)), 0, 42))
	if other.get_child_count() > 0:
		vb.add_child(other)
	else:
		other.queue_free()
	vb.add_child(MKUI.label("Gioca carte di lato per l'Influenza (clic su una carta → Di lato: Influenza).", 16, MKUI.MUTED, MKUI.font_italic))
