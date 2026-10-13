extends SceneTree
## AI unit tests (agent AI). Usage: godot --headless --path . -s res://tests/ai_test.gd
## - decide() never returns illegal actions and never modifies the engine state (random states, all levels)
## - combat: kills an easy enemy, blocks instead of taking avoidable wounds, uses ranged vs fortified correctly
## - pending decisions: rewards/level-up choices are legal and sensible
## - decisions are deterministic for the same state

const AI = preload("res://scripts/core/ai.gd")

var fails := 0
var checks := 0

func ok(cond: bool, msg: String) -> void:
	checks += 1
	if not cond:
		fails += 1
		print("FAIL: ", msg)

func _init():
	MKDB.load_dir("res://data")
	test_random_states()
	test_easy_kill()
	test_block_vs_wounds()
	test_fortified_ranged()
	test_pending_rewards()
	test_determinism()
	test_full_game_smoke()
	print("AI tests: %d checks, %d failures" % [checks, fails])
	quit(1 if fails > 0 else 0)

func new_game(scn: String = "solo_conquest", hero: String = "tovak", seed: int = 3) -> MKEngine:
	return MKEngine.create({"scenario": scn, "seed": seed, "players": [{"hero": hero, "ctrl": "ai"}], "options": {}})

## Random walks through the game; at random points ask the AI (all levels) and check legality + no mutation.
func test_random_states() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var scens := ["solo_conquest", "first_recon", "coop_conquest", "full_conquest"]
	for g in 8:
		var scn: String = scens[g % scens.size()]
		var pls: Array = [{"hero": "arythea", "ctrl": "ai"}]
		if scn == "coop_conquest":
			pls = [{"hero": "goldyx", "ctrl": "ai"}, {"hero": "norowas", "ctrl": "ai"}]
		elif scn == "full_conquest":
			pls = [{"hero": "tovak", "ctrl": "ai"}, {"hero": "arythea", "ctrl": "ai"}, {"hero": "goldyx", "ctrl": "ai"}]
		var e := MKEngine.create({"scenario": scn, "seed": 100 + g, "players": pls, "options": {}})
		var n := 0
		while e.s.phase != "game_over" and n < 400:
			n += 1
			if rng.randf() < 0.25:
				for lv in [1, 2, 3]:
					var fp := e.fingerprint()
					var a: Dictionary = AI.decide(e, lv)
					ok(fp == e.fingerprint(), "decide() modified the state (scn=%s n=%d lv=%d)" % [scn, n, lv])
					ok(not a.is_empty() and e.check(a) == "", "illegal/empty AI action %s -> %s (scn=%s n=%d)" % [JSON.stringify(a), e.check(a) if not a.is_empty() else "empty", scn, n])
			# advance: mostly AI moves (to reach interesting states), sometimes random
			var act: Dictionary
			if rng.randf() < 0.7:
				act = AI.decide(e, 2)
			else:
				var av: Array = e.available()
				if av.is_empty():
					break
				act = av[rng.randi() % av.size()].a
			if act.is_empty() or not e.apply(act).ok:
				var av2: Array = e.available()
				if av2.is_empty():
					break
				e.apply(av2[0].a)

func setup_combat(e: MKEngine, hand: Array, enemies: Array, opts: Dictionary = {}) -> Array:
	# finish the tactic phase
	var guard := 0
	while e.s.phase == "tactics" or e.s.pending != null:
		guard += 1
		if guard > 20:
			break
		e.apply(AI.decide(e, 2))
	var pl: Dictionary = e.P(0)
	pl.hand = []
	var i := 900
	for id in hand:
		i += 1
		pl.hand.append("%s#%d" % [id, i])
	for d in e.s.source:
		d.color = "black"
	pl.crystals = {"red": 0, "blue": 0, "green": 0, "white": 0}
	pl.tokens = []
	var eids: Array = []
	for t in enemies:
		i += 1
		var eid := "e%d" % i
		e.s.enemies[eid] = {"type": t, "color": str(MKDB.enemies[t].color), "face_up": true, "hex": ""}
		eids.append(eid)
	var o := {"kind": "challenge"}
	o.merge(opts, true)
	MKCombat.start(e, eids, o)
	return eids

func run_combat(e: MKEngine, level: int) -> void:
	var guard := 0
	while e.s.combat != null and guard < 80:
		guard += 1
		var a: Dictionary = AI.decide(e, level)
		var r: Dictionary = e.apply(a)
		ok(r.ok, "combat action rejected: %s %s" % [JSON.stringify(a), r.err])
		if not r.ok:
			return

func wounds_in_hand(e: MKEngine) -> int:
	var w := 0
	for iid in e.P(0).hand:
		if e.is_wound(iid):
			w += 1
	return w

## Prowlers (armor 3, attack 4): Rage + Determination + 2x March: block 4 is possible (Determination 2 + 2 sideways)
## and attack 3 (Rage 2 + 1 sideways) -> kill without wounds.
func test_easy_kill() -> void:
	for lv in [2, 3]:
		var e := new_game()
		var eids := setup_combat(e, ["rage", "determination", "march", "march", "stamina"], ["prowlers"])
		var f0 := int(e.P(0).fame)
		run_combat(e, lv)
		ok(int(e.P(0).fame) > f0, "L%d: prowlers not defeated" % lv)
		ok(wounds_in_hand(e) == 0, "L%d: took avoidable wounds vs prowlers (%d)" % [lv, wounds_in_hand(e)])

## Swordsmen (armor 5, attack 6) with a hand that can block 6 but not kill: block rather than take 3 wounds.
func test_block_vs_wounds() -> void:
	var e := new_game()
	setup_combat(e, ["determination", "rage", "march", "stamina", "promise"], ["swordsmen"])
	run_combat(e, 3)
	ok(wounds_in_hand(e) == 0, "took %d wounds instead of blocking Swordsmen" % wounds_in_hand(e))

## Diggers are fortified: ranged attacks cannot be used in the ranged phase, but count in the attack phase.
func test_fortified_ranged() -> void:
	var e := new_game("solo_conquest", "arythea")
	setup_combat(e, ["swiftness", "rage", "march", "stamina", "determination"], ["diggers"])
	# give a white crystal so Swiftness can be powered (ranged 3)
	e.P(0).crystals.white = 1
	var f0 := int(e.P(0).fame)
	run_combat(e, 3)
	ok(int(e.P(0).fame) > f0, "diggers not defeated")

func test_pending_rewards() -> void:
	var e := new_game()
	var guard := 0
	while e.s.phase == "tactics" or e.s.pending != null:
		guard += 1
		if guard > 20:
			break
		e.apply(AI.decide(e, 2))
	# reward: spell from offer
	MKSites.give_reward(e, 0, {"k": "spell"})
	ok(e.s.pending != null, "spell reward did not ask")
	if e.s.pending != null:
		var a: Dictionary = AI.decide(e, 3)
		ok(a.get("t", "") == "choose" and e.check(a) == "", "spell reward choice illegal")
		e.apply(a)
	# level-up skill choice
	MKSites.level_up_skill(e, 0)
	if e.s.pending != null:
		var a2: Dictionary = AI.decide(e, 3)
		ok(e.check(a2) == "", "skill choice illegal")
		e.apply(a2)
		if e.s.pending != null:
			var a3: Dictionary = AI.decide(e, 3)
			ok(e.check(a3) == "", "AA choice after skill illegal")
			e.apply(a3)
	ok(e.P(0).skills.size() == 1, "skill not gained")

func test_determinism() -> void:
	var e := new_game("solo_conquest", "goldyx", 11)
	for i in 30:
		if e.s.phase == "game_over":
			break
		var e2 := MKEngine.from_state(e.s)
		var a1: Dictionary = AI.decide(e, 3)
		var a2: Dictionary = AI.decide(e2, 3)
		ok(JSON.stringify(a1) == JSON.stringify(a2), "non deterministic decision at step %d: %s vs %s" % [i, JSON.stringify(a1), JSON.stringify(a2)])
		e.apply(a1)

func test_full_game_smoke() -> void:
	AI.reset_stats()
	var e := new_game("solo_conquest", "norowas", 21)
	var n := 0
	while e.s.phase != "game_over" and n < 3000:
		n += 1
		var a: Dictionary = AI.decide(e, 3)
		if a.is_empty() or not e.apply(a).ok:
			ok(false, "smoke game stuck at action %d" % n)
			break
	ok(e.s.phase == "game_over", "smoke game did not end")
	ok(int(AI.stats.illegal) == 0, "illegal AI actions in smoke game: %d" % int(AI.stats.illegal))
	ok(int(e.P(0).fame) > 5, "smoke game: AI fame too low (%d)" % int(e.P(0).fame))
