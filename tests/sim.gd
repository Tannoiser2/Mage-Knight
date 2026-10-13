extends SceneTree
## Headless random simulation: plays whole games choosing random legal
## actions from available() (biased towards progress) and reports crashes,
## stuck states, illegal "available" actions and game length.
## Usage: godot --headless --path . -s res://tests/sim.gd -- [games] [scenario|""] [seed]
## Env: SIM_GOD=1 (boost pools so combats are won: exercises rewards/level ups/conquests),
##      SIM_TRACE=1 (print every action + log to stderr), SIM_QUIET=1 (print only failures),
##      SIM_SETS=base,ll,… (card/enemy sets; uses expansion heroes).
## Every game must end (game_over) without crashes, stuck states or rejected "available" actions;
## games with seed%3==1 are replayed to check determinism.

const W := {"choice": 1.0, "tactic": 1.0, "card": 2.0, "move": 3.0, "site": 3.0, "combat": 3.0, "unit": 1.5,
	"skill": 1.5, "heal": 2.0, "turn": 0.6}

var rng := RandomNumberGenerator.new()
var god := false

func _init():
	var args := OS.get_cmdline_user_args()
	var games := int(args[0]) if args.size() > 0 else 3
	god = OS.get_environment("SIM_GOD") != ""
	var only := str(args[1]) if args.size() > 1 else ""
	var seed0 := int(args[2]) if args.size() > 2 else 1
	MKDB.load_dir("res://data")
	var heroes := ["arythea", "goldyx", "norowas", "tovak"]
	if OS.get_environment("SIM_SETS") != "":
		heroes = ["wolfhawk", "krang", "braevalar", "tovak"]
	var scen := [
		["first_recon", [{"hero": "arythea"}]],
		["first_recon", [{"hero": "tovak"}, {"hero": "goldyx"}]],
		["solo_conquest", [{"hero": "norowas"}]],
		["coop_conquest", [{"hero": "goldyx"}, {"hero": "tovak"}]],
		["full_conquest", [{"hero": "arythea"}, {"hero": "norowas"}, {"hero": "tovak"}]],
		["blitz_conquest", [{"hero": "goldyx"}, {"hero": "arythea"}]],
	]
	var t0 := Time.get_ticks_msec()
	var total_actions := 0
	var fails := 0
	for g in games:
		for sc in scen:
			if only != "" and sc[0] != only:
				continue
			var seed := seed0 + g * 101
			var pls: Array = []
			for i in sc[1].size():
				pls.append({"hero": heroes[(i + g) % 4]})
			var r := play(sc[0], pls, seed)
			total_actions += int(r.actions)
			if r.err != "":
				fails += 1
			if r.err != "" or OS.get_environment("SIM_QUIET") == "":
				print("%s np=%d seed=%d -> %s rounds=%d actions=%d fame=%s %s" % [sc[0], sc[1].size(), seed, r.end, r.rounds, r.actions, str(r.fame), r.err])
	var dt := Time.get_ticks_msec() - t0
	print("TOTAL actions=%d time=%dms (%.2f ms/action) failures=%d" % [total_actions, dt, float(dt) / maxf(1.0, total_actions), fails])
	quit()

func play(scn: String, players: Array, seed: int) -> Dictionary:
	rng.seed = seed
	var cfg := {"scenario": scn, "seed": seed, "players": [], "options": {}}
	if OS.get_environment("SIM_SETS") != "":
		cfg.options["sets"] = OS.get_environment("SIM_SETS").split(",")
	for p in players:
		cfg.players.append({"hero": p.hero, "ctrl": "ai", "name": p.hero.capitalize()})
	var e := MKEngine.create(cfg)
	var n := 0
	var err := ""
	var history: Array = []
	while e.s.phase != "game_over":
		n += 1
		if n > 30000:
			err = "TROPPE AZIONI (partita infinita?)"
			break
		var av: Array = e.available()
		if av.is_empty():
			err = "BLOCCATO: nessuna azione disponibile (phase=%s actor=%d pending=%s combat=%s) end_turn:%s rest:%s" % [e.s.phase, e.actor(), str(e.s.pending != null), str(e.s.combat != null), e.check({"t": "end_turn"}), e.check({"t": "rest"})]
			err += " turn=" + JSON.stringify(e.s.turn).substr(0, 400)
			break
		if god and e.s.pending == null and e.s.phase == "turn":
			_god(e)
			av = e.available()
		var pick: Dictionary = choose(e, av)
		if OS.get_environment("SIM_TRACE") != "":
			printerr("  #%d p%d %s" % [n, e.actor(), pick.label])
		var l0: int = e.s.log_seq
		var res: Dictionary = e.apply(pick.a)
		history.append(pick.a)
		if OS.get_environment("SIM_TRACE") != "":
			for le in e.s.log:
				if int(le.seq) >= l0:
					printerr("        · ", le.txt)
		if not res.ok:
			err = "AZIONE DISPONIBILE RIFIUTATA: %s -> %s" % [JSON.stringify(pick.a), res.err]
			break
	var fame: Array = []
	for p in e.s.players:
		fame.append(p.fame)
	# determinism check: replay
	if err == "" and seed % 3 == 1 and not god:
		var e2 := MKEngine.create(cfg)
		for a in history:
			e2.apply(a)
		if e2.fingerprint() != e.fingerprint():
			err = "NON DETERMINISTICO"
	return {"end": e.s.phase, "rounds": e.s.round, "actions": n, "fame": fame, "err": err}

## God mode: boosts pools so that combats are won and sites conquered
## (exercises rewards, level ups, recruiting, conquests).
func _god(e: MKEngine) -> void:
	var t: Dictionary = e.s.turn
	var cb = e.s.combat
	if cb != null:
		if cb.phase in ["ranged", "attack"] and t.pool.attack.is_empty() and rng.randf() < 0.8:
			t.pool.attack[("siege" if cb.phase == "ranged" else "melee") + ":cold"] = 25
		elif cb.phase == "block" and t.pool.block.is_empty() and rng.randf() < 0.7:
			t.pool.block["cold"] = 12
	elif not t.get("god", false):
		t["god"] = true
		t.pool.move = int(t.pool.move) + 4
		t.pool.influence = int(t.pool.influence) + 6

func choose(e: MKEngine, av: Array) -> Dictionary:
	var tot := 0.0
	var ws: Array = []
	var cb = e.s.combat
	var ph: String = str(cb.phase) if cb != null else ""
	var p: int = e.actor()
	var nonw := 0
	if p >= 0 and p < e.s.players.size():
		for iid in e.s.players[p].hand:
			if not e.is_wound(iid):
				nonw += 1
	for x in av:
		var w: float = W.get(x.group, 1.0)
		var a: Dictionary = x.a
		var lbl: String = str(x.label)
		match str(a.get("t", "")):
			"choose":
				w = 1.0
				if ph == "attack" and lbl.find("Attacco") >= 0:
					w = 6.0
				elif ph == "ranged" and lbl.find("distanza") >= 0:
					w = 6.0
				elif ph == "block" and lbl.find("Blocco") >= 0:
					w = 6.0
				elif cb == null and lbl.find("Movimento") >= 0:
					w = 3.0
			"move":
				var dr: int = MKHex.parse(str(a.to)).y - MKHex.parse(e.s.players[p].pos).y
				w = 1.0 if dr >= 0 else 5.0
			"explore":
				w = 30.0
			"attack", "block":
				w = 40.0
			"site", "challenge":
				w = 6.0 if nonw >= 3 else 0.3
			"recruit", "buy":
				w = 5.0
			"end_turn":
				w = 0.5 if e.s.turn.played.size() < 3 else 3.0
			"rest":
				w = 0.3
			"announce_end":
				w = 2.0
			"plunder", "burn":
				w = 0.2
			"pvp_attack", "coop":
				w = 25.0
			"pvp":
				w = 6.0 if str(a.get("op", "")) != "pass" else 1.5
			"discard":
				w = 0.15
			"next":
				w = 1.0 if ph in ["ranged", "attack", "block"] else 4.0
			"damage":
				w = 2.0
			"play":
				if cb != null:
					var side := str(a.get("side", ""))
					if ph == "attack" and (lbl.find("Attacco") >= 0 or side == "attack"):
						w = 8.0
					elif ph == "block" and (lbl.find("Blocco") >= 0 or side == "block"):
						w = 8.0
					elif ph == "ranged" and lbl.find("distanza") >= 0:
						w = 4.0
					else:
						w = 1.0
				else:
					w = 2.5 if (lbl.find("Movimento") >= 0 and int(e.s.turn.pool.move) < 4) else 1.0
					if lbl.find("Influenza") >= 0 and MKSites.can_interact(e, p) == "":
						w = 4.0
		ws.append(w)
		tot += w
	var r := rng.randf() * tot
	for i in av.size():
		r -= ws[i]
		if r <= 0.0:
			return av[i]
	return av[-1]
