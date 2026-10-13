extends SceneTree
## QA dell'interfaccia: un "umano" gioca alcuni turni premendo i veri bottoni dell'HUD (cerca i Button per testo
## e ne emette `pressed`), con qualche aiutino sullo stato per arrivare alle situazioni da controllare.
##   xvfb-run -a -s "-screen 0 1920x1080x24" <godot> --path . --rendering-driver opengl3 -s res://tests/qa_ui.gd -- <solo|coop|all> <prefisso>
## Stampa "QAUI ..." per ogni passo e "QAUI done errors=N"; salva gli screenshot <prefisso>_<nome>.png.

var out := "/tmp/qaui"
var mode := "all"
var main: MKMain
var view: MKGameView
var errors := 0
var steps := 0

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		mode = args[0]
	if args.size() > 1:
		out = args[1]
	create_timer(1200.0).timeout.connect(func():
		printerr("qa_ui: tempo scaduto")
		quit(1))
	_run.call_deferred()

func _wait(n: int) -> void:
	for i in range(n):
		await process_frame

func shot(name: String) -> void:
	await _wait(3)
	await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png("%s_%s.png" % [out, name])
	print("SHOT ", name)

func err(msg: String) -> void:
	errors += 1
	print("QAUI ERRORE: ", msg)

func note(msg: String) -> void:
	steps += 1
	print("QAUI ", msg)

func eng() -> MKEngine:
	return view.ctrl.eng

# ------------------------------------------------------------------ finding and pressing buttons
func _buttons(n: Node, outl: Array) -> void:
	for c in n.get_children():
		if c is Button and c.is_visible_in_tree():
			outl.append(c)
		_buttons(c, outl)

func find_btn(txt: String, under: Node = null) -> Button:
	var l: Array = []
	_buttons(under if under != null else view, l)
	# modal buttons first (last added = on top)
	l.reverse()
	for b in l:
		if not b.disabled and b.text.findn(txt) >= 0:
			return b
	return null

func btn_texts() -> Array:
	var l: Array = []
	_buttons(view, l)
	var t: Array = []
	for b in l:
		if b.text != "":
			t.append(("[x]" if b.disabled else "") + b.text)
	return t

func press(txt: String, required := true) -> bool:
	var b := find_btn(txt)
	if b == null:
		if required:
			err("bottone '%s' non trovato; visibili: %s" % [txt, str(btn_texts())])
		return false
	note("premo '%s'" % b.text.replace("\n", " "))
	b.pressed.emit()
	await _wait(4)
	return true

func wait_local(max_frames := 3000) -> bool:
	var n := 0
	while n < max_frames:
		if eng().s.phase == "game_over":
			return true
		if view.ctrl.is_local_turn():
			await _wait(2)
			return true
		n += 1
		await process_frame
	err("il turno dell'umano non arriva (actor=%d phase=%s)" % [eng().actor(), eng().s.phase])
	return false

## Answers any pending decision of the human by pressing the first option button of the dialog.
func answer_pending(pick := 0, tag := "") -> void:
	var guard := 0
	while eng().s.pending != null and view.ctrl.is_local_turn() and guard < 12:
		guard += 1
		if tag != "" and guard == 1:
			await shot(tag)
		if not view.has_modal("pending"):
			err("decisione in sospeso senza finestra: " + str(eng().s.pending.prompt))
			return
		var opts: Array = eng().s.pending.options
		var want: String = str(opts[mini(pick, opts.size() - 1)].get("label", ""))
		var holder: Node = view._modal["pending"]
		var l: Array = []
		_buttons(holder, l)
		var hit: Button = null
		for b in l:
			if b.text == want or b.tooltip_text == want:
				hit = b
				break
		if hit == null:
			err("opzione '%s' non trovata nella finestra" % want)
			view.submit({"t": "choose", "v": [opts[mini(pick, opts.size() - 1)].v]})
		else:
			note("scelgo '%s'" % want)
			hit.pressed.emit()
		await _wait(4)

func play_card(card_id: String, entry: String, tag := "") -> bool:
	var hand: Array = eng().s.players[view.viewer].hand
	var iid := ""
	for x in hand:
		if eng().card_id(x) == card_id:
			iid = x
	if iid == "":
		err("carta %s non in mano" % card_id)
		return false
	view.open_card_menu(iid)
	await _wait(4)
	if tag != "":
		await shot(tag)
	var ok := await press(entry)
	if view.has_modal("cardmenu"):
		view.close_modal("cardmenu")
	return ok

func set_hand(ids: Array) -> void:
	var p: int = view.viewer
	var pl: Dictionary = eng().s.players[p]
	pl.hand = []
	for id in ids:
		pl.hand.append(eng().new_iid(id))
	view.refresh()

func click_hex(k: String) -> void:
	view._on_hex_clicked(k)
	await _wait(4)

func click_enemy(eid: String) -> void:
	if eid in view.combat_sel:
		note("bersaglio già selezionato automaticamente")
		return
	# simulates a click on the enemy card of the combat panel
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	var found := false
	for pc in _panels(view.center_holder):
		if pc.tooltip_text != "" or true:
			pass
	# the enemy cards are PanelContainers connected to gui_input: emit on the one showing the enemy name
	var e = MKCombat.entry(eng(), eid)
	for pc in _panels(view.center_holder):
		if _has_label(pc, str(e.name)) and pc.custom_minimum_size.x >= 200:
			pc.gui_input.emit(ev)
			found = true
			break
	if not found:
		err("carta del nemico %s non trovata" % e.name)
	await _wait(3)

func _panels(n: Node) -> Array:
	var out: Array = []
	for c in n.get_children():
		if c is PanelContainer:
			out.append(c)
		out.append_array(_panels(c))
	return out

func _has_label(n: Node, txt: String) -> bool:
	for c in n.get_children():
		if c is Label and c.text == txt:
			return true
		if _has_label(c, txt):
			return true
	return false

func check_overlaps(tag: String) -> void:
	# the central panel must not cover the hand; modals must fit the screen
	var vs := view.get_viewport_rect().size
	for n in view._modal:
		var h = view._modal[n]
		if not is_instance_valid(h):
			continue
		for pc in _panels(h):
			var r: Rect2 = pc.get_global_rect()
			if r.size.x > 50 and (r.position.x < -2 or r.position.y < -2 or r.end.x > vs.x + 2 or r.end.y > vs.y + 2):
				err("%s: la finestra '%s' esce dallo schermo %s" % [tag, n, str(r)])
				break

# ------------------------------------------------------------------ games
func _start(scn: String, players: Array, seed := 11) -> void:
	for c in root.get_children():
		c.queue_free()
	await _wait(2)
	main = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	await _wait(5)
	main.start_game({"scenario": scn, "seed": seed, "players": players, "options": {"set": "base"}})
	await _wait(10)
	view = main.current
	view.ctrl.set_speed(3)
	view.table.animate = false

func _run() -> void:
	MKController.clear_save()
	if mode in ["solo", "all"]:
		await solo()
	if mode in ["solo2", "all"]:
		await solo2()
	if mode in ["coop", "all"]:
		await coop()
	if mode in ["city", "all"]:
		await city()
	print("QAUI done errors=%d steps=%d" % [errors, steps])
	quit()

func pick_tactic(idx := 0) -> void:
	await wait_local()
	if not view.has_modal("tactics"):
		err("finestra delle tattiche assente")
		return
	var l: Array = []
	_buttons(view._modal["tactics"], l)
	var cands: Array = []
	for b in l:
		if b.icon != null and not b.disabled:
			cands.append(b)
	if cands.is_empty():
		err("nessuna tattica selezionabile")
		return
	var b: Button = cands[mini(idx, cands.size() - 1)]
	note("tattica: " + b.tooltip_text.split("\n")[0])
	b.pressed.emit()
	await _wait(5)
	await answer_pending(0, "tactic_followup")

func solo() -> void:
	await _start("solo_conquest", [{"hero": "arythea", "ctrl": "human", "name": "Stefano"}])
	var e := eng()
	await shot("solo_01_tactics")
	check_overlaps("tattiche")
	await pick_tactic(4)   # Grande inizio: +2 carte
	await wait_local()
	await shot("solo_02_turn1")
	var p: int = view.viewer
	# ---- movement with a card from the hand
	set_hand(["march", "stamina", "rage", "promise", "swiftness", "concentration", "improvisation"])
	await play_card("march", "Base", "solo_03_cardmenu_march")
	if int(e.s.turn.pool.move) != 2:
		err("Marcia non ha dato Movimento 2 (pool=%d)" % int(e.s.turn.pool.move))
	await shot("solo_04_move_highlights")
	var dest := ""
	for k in view._hl_action:
		if str(view._hl_action[k].get("t", "")) == "path":
			dest = k
			break
	if dest == "":
		err("nessun esagono raggiungibile evidenziato")
	else:
		var p0: String = e.s.players[p].pos
		await click_hex(dest)
		if view.has_modal("confirm"):
			await shot("solo_05_confirm_move")
			await press("Conferma")
		note("mosso da %s a %s" % [p0, e.s.players[p].pos])
		if e.s.players[p].pos == p0:
			err("il clic sull'esagono non ha mosso l'eroe")
	# ---- exploration
	await play_card("stamina", "Base")
	var expl := ""
	for k in view._hl_action:
		if str(view._hl_action[k].get("t", "")) == "explore":
			expl = k
	if expl != "":
		var nt: int = e.s.map.tiles.size()
		await click_hex(expl)
		if e.s.map.tiles.size() != nt + 1:
			err("l'esplorazione dal clic non ha rivelato la tessera")
		else:
			note("esplorata la tessera " + expl)
		await shot("solo_06_explored")
	else:
		note("nessuna tessera esplorabile da qui")
	# ---- end of turn with the button
	await end_turn_btn()
	await answer_pending(0, "solo_07_end_discard")
	await wait_local()
	await shot("solo_08_turn2")
	# ---- village: recruit and heal
	var vil := ""
	for k in e.s.map.hex:
		if e.s.map.hex[k].site == "village":
			vil = k
	if vil == "":
		vil = e.s.players[p].pos
		e.s.map.hex[vil].site = "village"
	e.s.players[p].pos = vil
	e.s.turn.path = [vil]
	set_hand(["promise", "promise", "threaten", "wound", "march", "rage"])
	await click_hex(vil)
	await shot("solo_09_site_open")
	if not view.site_open and not view.has_modal("cardmenu"):
		err("il clic sul proprio esagono (villaggio) non apre il pannello del sito")
	await play_card("promise", "Base")
	await play_card("promise", "Potenziata", "solo_10_powered_menu")
	if not view.site_open:
		view.open_site()
		await _wait(3)
	await shot("solo_11_site_influence")
	var inf0: int = MKSites.influence_avail(e, p)
	note("Influenza disponibile %d" % inf0)
	var units0: int = e.s.players[p].units.size()
	if find_btn("Recluta (") != null:
		await press("Recluta (")
		if e.s.players[p].units.size() != units0 + 1:
			err("Recluta non ha reclutato")
	else:
		note("nessuna unità reclutabile al villaggio in questa offerta")
	if find_btn("punto Cura") != null:
		var w0: int = 0
		for iid in e.s.players[p].hand:
			if e.is_wound(iid):
				w0 += 1
		await press("punto Cura")
		var w1: int = 0
		for iid in e.s.players[p].hand:
			if e.is_wound(iid):
				w1 += 1
		if w1 != w0 - 1:
			err("Compra 1 punto Cura non ha curato la ferita")
	await shot("solo_12_after_recruit_heal")
	if view.site_open:
		await press("Chiudi")
	await end_turn_btn()
	await answer_pending(0)
	await wait_local()
	# ---- fight a rampaging enemy through all phases
	var ork := ""
	for k in e.s.map.hex:
		var h: Dictionary = e.s.map.hex[k]
		if h.rampage and not h.enemies.is_empty():
			ork = k
			break
	if ork == "":
		err("nessun nemico scatenato sulla mappa")
		return
	var stand := ""
	for nk in MKHex.neighbors(ork):
		var nh := e.hex(nk)
		if not nh.is_empty() and nh.site == "" and e.move_cost(nk) < 999 and nh.enemies.is_empty():
			stand = nk
			break
	e.s.players[p].pos = stand
	e.s.turn.path = [stand]
	var etype: String = e.s.enemies[e.s.map.hex[ork].enemies[0]].type
	note("nemico scatenato: %s (%s)" % [MKDB.enemies[etype].name_it, etype])
	set_hand(["rage", "determination", "march", "swiftness", "stamina", "rage"])
	e.s.players[p].crystals.red = 1
	e.s.players[p].fame = 1
	view.refresh()
	await _wait(3)
	await shot("solo_13_next_to_enemy")
	await click_hex(ork)
	await shot("solo_14_challenge_confirm")
	await press("Conferma")
	if e.s.combat == null:
		err("la sfida non ha iniziato il combattimento")
		return
	await shot("solo_15_combat_ranged")
	check_overlaps("combattimento")
	await press("Passa al Blocco")
	await shot("solo_16_combat_block")
	await play_card("determination", "Base", "solo_17_cardmenu_block")
	await answer_pending(1, "solo_17b_choice")
	await shot("solo_18_block_points")
	if find_btn("Blocca ") != null:
		await press("Blocca ")
		await shot("solo_19_blocked")
	await press("Passa ai Danni")
	if e.s.combat != null and e.s.combat.phase == "damage":
		await shot("solo_20_damage")
		await press("All'eroe")
		await shot("solo_21_damage_assigned")
		await press("Passa all'Attacco")
	if e.s.combat != null and e.s.combat.phase == "attack":
		await play_card("rage", "Potenziata", "solo_22_cardmenu_attack")
		await answer_pending(0)
		var eid: String = ""
		for en in e.s.combat.enemies:
			if not en.defeated:
				eid = en.eid
		await click_enemy(eid)
		await shot("solo_23_attack_selected")
		if find_btn("ATTACCA") != null:
			await press("ATTACCA")
		else:
			note("attacco insufficiente: " + e.check({"t": "attack", "targets": [eid]}))
			await press("Termina il combattimento")
	await _wait(5)
	await shot("solo_24_combat_result")
	if view.has_modal("info"):
		await press("OK")
	if e.s.combat != null:
		err("il combattimento non è finito")
	# ---- level up at end of turn
	e.gain_fame(p, 3)
	view.refresh()
	await end_turn_btn()
	await answer_pending(0, "solo_25_levelup")
	await wait_local()
	await shot("solo_26_after_levelup")
	note("livello %d, abilità %s" % [int(e.s.players[p].level), str(e.s.players[p].skills)])
	if int(e.s.players[p].level) < 2:
		err("nessuna salita di livello")
	# ---- end of round: empty deck, announce
	var pl: Dictionary = e.s.players[p]
	pl.discard.append_array(pl.deck)
	pl.deck = []
	view.refresh()
	set_hand(["march", "rage"])
	await play_card("march", "Base")
	await end_turn_btn()
	await answer_pending(0)
	await wait_local()
	await shot("solo_27_deck_empty")
	if find_btn("Annuncia la fine del round") == null:
		err("bottone per annunciare la fine del round assente con il mazzo vuoto")
	else:
		var r0: int = e.s.round
		await press("Annuncia la fine del round")
		await press("Conferma")
		await wait_local()
		await shot("solo_28_new_round_tactics")
		if int(e.s.round) != r0 + 1:
			err("il round non è finito dopo l'annuncio (round %d)" % int(e.s.round))
		await pick_tactic(0)
		await wait_local()
		await shot("solo_29_night_turn")
	# ---- screens
	await press("OFFERTE")
	await shot("solo_30_offers")
	check_overlaps("offerte")
	view.close_modal("screen")
	await press("REGOLE")
	await shot("solo_31_rules")
	view.close_modal("screen")
	# ---- end screen
	e._game_over()
	view.refresh()
	await _wait(5)
	await shot("solo_32_end")

func coop() -> void:
	await _start("coop_conquest", [{"hero": "goldyx", "ctrl": "human", "name": "Stefano"}, {"hero": "tovak", "ctrl": "ai", "ai_level": 2, "name": "Tovak (IA)"}], 21)
	var e := eng()
	await wait_local()
	await shot("coop_01_tactics")
	note("tattica del Neutrale: %s" % e.s.dummy.tactic)
	await pick_tactic(1)
	var turns := 0
	var guard := 0
	while turns < 4 and guard < 40 and e.s.phase != "game_over":
		guard += 1
		await wait_local()
		if e.s.phase == "tactics":
			await shot("coop_tactics_r%d" % int(e.s.round))
			await pick_tactic(0)
			continue
		if e.s.pending != null:
			await answer_pending(0, "coop_pending_%d" % guard)
			continue
		turns += 1
		await shot("coop_turn%d" % turns)
		var p: int = view.viewer
		# play the first card with a movement entry, walk, then end the turn
		var played := false
		for iid in e.s.players[p].hand.duplicate():
			for en in view.card_entries(iid):
				if en.get("disabled", false):
					continue
				if str(en.label).find("Movimento") >= 0 and not played:
					await play_card(e.card_id(iid), str(en.label).substr(0, 12))
					played = true
		for k in view._hl_action:
			if str(view._hl_action[k].get("t", "")) == "path":
				await click_hex(k)
				if view.has_modal("confirm"):
					await press("Annulla")
				break
		if e.s.combat != null:
			await shot("coop_combat%d" % turns)
			var g2 := 0
			while e.s.combat != null and g2 < 12:
				g2 += 1
				if not (await press("Passa", false)):
					if not (await press("All'eroe", false)):
						await press("Termina il combattimento", false)
			if view.has_modal("info"):
				await press("OK")
		if e.s.pending != null:
			await answer_pending(0)
		await end_turn_btn(false)
		await answer_pending(0, "coop_end_pending%d" % turns)
		# the AI ally plays now: catch the banner
		await _wait(20)
		if not view.ctrl.is_local_turn() and e.s.phase != "game_over":
			await shot("coop_ai_turn%d" % turns)
			if not view.banner.visible:
				err("nessuna striscia durante il turno dell'IA")
	e._game_over()
	view.refresh()
	await _wait(5)
	await shot("coop_end")


func click_control(c: Control) -> void:
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	c.gui_input.emit(ev)
	await _wait(4)

## The unit / skill widgets of the left board (Controls with gui_input connections, by tooltip/size).
func left_widgets(min_w: float, min_h: float) -> Array:
	var out: Array = []
	var stack: Array = [view.left_panel]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
			if c is Control and c.mouse_filter == Control.MOUSE_FILTER_STOP and c.size.x >= min_w - 1 and c.size.y >= min_h - 1 and c.size.x <= min_w + 60:
				if c.gui_input.get_connections().size() > 0:
					out.append(c)
	return out

func solo2() -> void:
	await _start("solo_conquest", [{"hero": "arythea", "ctrl": "human", "name": "Stefano"}], 33)
	var e := eng()
	await pick_tactic(0)
	await wait_local()
	var p: int = view.viewer
	# ---- rest
	set_hand(["march", "rage", "wound", "wound"])
	await press("Riposa")
	await press("Conferma")
	await answer_pending(0, "solo2_01_rest_card")
	await shot("solo2_02_rest_wounds")
	await answer_pending(0)
	note("mano dopo il riposo: %s" % str(e.s.players[p].hand))
	if e.s.players[p].hand.size() != 1:
		err("riposo standard: attese 1 carta in mano")
	await end_turn_btn()
	await answer_pending(0)
	await wait_local()
	# ---- unit and skill activation from the board
	MKSites.gain_unit(e, p, "peasants")
	MKSites.add_skill(e, p, "arythea_dark_paths")
	set_hand(["march", "rage", "promise"])
	await _wait(4)
	await shot("solo2_03_board_unit_skill")
	var units := left_widgets(98, 137)
	if units.is_empty():
		err("widget dell'unità non trovato")
	else:
		await click_control(units[0])
		await shot("solo2_04_unit_menu")
		var mv0: int = int(e.s.turn.pool.move)
		await press("Movimento 2")
		if int(e.s.turn.pool.move) != mv0 + 2:
			err("l'unità Contadini non ha dato Movimento 2")
		if e.s.players[p].units[0].ready:
			err("unità non esaurita dopo l'uso")
	var skills := left_widgets(150, 100)
	if skills.is_empty():
		err("widget dell'abilità non trovato")
	else:
		await click_control(skills[0])
		await shot("solo2_05_skill_menu")
		var mv1: int = int(e.s.turn.pool.move)
		await press("Usa l'abilità")
		if int(e.s.turn.pool.move) != mv1 + 1:
			err("Sentieri Oscuri di giorno: atteso Movimento +1")
	# ---- dungeon: no units, night rules
	var k: String = e.s.players[p].pos
	e.s.map.hex[k].site = "dungeon"
	e.s.map.hex[k].conquered = false
	view.refresh()
	await _wait(3)
	await shot("solo2_06_dungeon_actions")
	await press("Entra in sotterraneo")
	if e.s.combat == null:
		err("entrare nel sotterraneo non ha iniziato il combattimento")
		return
	await shot("solo2_07_dungeon_combat")
	if find_btn("Contadini") != null:
		err("nel sotterraneo è proposta un'unità")
	await press("Passa al Blocco")
	await press("Passa ai Danni")
	while e.s.combat != null and e.s.combat.phase == "damage":
		if not await press("All'eroe", false):
			break
	await press("Passa all'Attacco", false)
	await press("Termina il combattimento", false)
	if view.has_modal("info"):
		await shot("solo2_08_dungeon_result")
		await press("OK")
	await end_turn_btn()
	await answer_pending(0)
	await wait_local()
	# ---- knock out
	var ork := ""
	for nk in MKHex.neighbors(e.s.players[p].pos):
		var nh := e.hex(nk)
		if not nh.is_empty() and nh.site == "" and nh.enemies.is_empty() and e.move_cost(nk) < 999:
			ork = nk
			break
	var eid := "qko"
	e.s.enemies[eid] = {"type": "fire_dragon", "color": "red", "face_up": true, "hex": ork}
	e.s.map.hex[ork].enemies = [eid]
	e.s.map.hex[ork].rampage = true
	e.s.players[p].units = []
	set_hand(["march", "rage", "stamina", "swiftness", "promise"])
	await click_hex(ork)
	await press("Conferma")
	await press("Passa al Blocco")
	await press("Passa ai Danni")
	await shot("solo2_09_before_ko")
	await press("All'eroe")
	await shot("solo2_10_knocked_out")
	if not e.s.players[p].knocked_out:
		err("9 danni con armatura 2 = 5 ferite: atteso fuori combattimento")
	var nonw := 0
	for iid in e.s.players[p].hand:
		if not e.is_wound(iid):
			nonw += 1
	if nonw != 0:
		err("fuori combattimento: restano carte non-Ferita in mano")
	await press("Passa all'Attacco", false)
	await press("Termina il combattimento", false)
	if view.has_modal("info"):
		await shot("solo2_11_ko_summary")
		await press("OK")
	await shot("solo2_12_after_ko")
	# only wounds in hand: the only way on is resting (slow recovery) next turn
	await end_turn_btn(false)
	await answer_pending(0)
	await wait_local()
	await shot("solo2_13_wounds_only")
	if find_btn("Riposa") == null:
		err("con sole Ferite in mano manca il bottone Riposa")


func end_turn_btn(required := true) -> void:
	if not await press("TERMINA IL TURNO", required):
		return
	if view.has_modal("confirm"):
		await shot("confirm_end_turn")
		await press("Conferma")


## Assault on a big city: many defenders, city bonuses, shields.
func city() -> void:
	await _start("full_conquest", [{"hero": "tovak", "ctrl": "human", "name": "Stefano"}, {"hero": "goldyx", "ctrl": "ai", "ai_level": 1, "name": "Goldyx (IA)"}], 5)
	var e := eng()
	await wait_local()
	if e.s.phase == "tactics":
		await pick_tactic(0)
	await wait_local()
	var p: int = view.viewer
	# build a level-11 blue city next to the hero
	var pos: String = e.s.players[p].pos
	var k := ""
	for nk in MKHex.neighbors(pos):
		var nh := e.hex(nk)
		if not nh.is_empty() and nh.enemies.is_empty() and nh.site == "" and e.move_cost(nk) < 999:
			k = nk
			break
	e.s.map.hex[k].site = "city"
	e.s.map.hex[k]["city"] = {"color": "blue", "level": 11, "shields": [], "leader": -1}
	for col in e._city_garrison(MKSites.city_def("blue"), 11):
		var eid := e.draw_enemy(col, false, k)
		e.s.map.hex[k].enemies.append(eid)
	set_hand(["march", "rage", "determination", "swiftness", "stamina"])
	view.refresh()
	await _wait(3)
	await play_card("march", "Base")
	await shot("city_01_before")
	await click_hex(k)
	await shot("city_02_assault_confirm")
	await press("Conferma")
	if e.s.combat == null:
		err("l'assalto alla città non è iniziato")
		return
	await shot("city_03_combat")
	check_overlaps("città")
	# the combat panel must not cover the hand
	var cr: Rect2 = view.center_holder.get_child(0).get_global_rect() if view.center_holder.get_child_count() > 0 else Rect2()
	var hr: Rect2 = view.hand_area.get_global_rect()
	note("pannello combattimento %s, mano %s" % [str(cr), str(hr)])
	if cr.end.y > hr.position.y + 40:
		err("il pannello del combattimento copre la mano")
	await press("Passa al Blocco")
	await shot("city_04_block")
	await press("Passa ai Danni")
	await shot("city_05_damage")
