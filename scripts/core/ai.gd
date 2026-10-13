class_name MKAI
extends RefCounted
## Mage Knight AI (agent AI). Entry point:
##   static func decide(eng: MKEngine, level: int) -> Dictionary
## returns a legal action for eng.actor() (also answers pending decisions).
## level 1 = Facile (cautious, noisy, shallow), 2 = Normale, 3 = Difficile (wider search, lookahead on
## special cards and mana generators, small exploration noise).
## Never modifies eng.s (all lookahead runs on log-less copies). Every returned action is validated
## with eng.check(); on failure a safe legal fallback is returned. Deterministic for a given state.
##
## Design: the AI re-plans at every call (cheap) with a per-turn memory (intent of the last card play,
## fight-evaluation cache, long-term goal, "camping" counters).
## - Outside combat (ai_turn.gd): enumerate missions reachable this turn (assault, adventure site,
##   challenge, interaction purchases, exploration, altar, relocation, rest, end) and score them as
##   gain - card/mana/rep cost + strategic position value; then execute step by step (play move cards,
##   move, act, then end-of-turn extras: healing, crystallize a free die, tactics, card cycling).
## - Combat (ai_combat.gd): abstract planner over cards/units/skills/pool options (static effect parse):
##   enumerate which enemies die in the ranged phase and in the attack phase, min-cost DP allocations
##   for each attack group / block, damage assignment to units or hero (wounds, poison, paralysis,
##   knock-out), site conquest/progress bonuses; joint mana and discard feasibility checks; 1-ply
##   simulated lookahead for cards with non-modelled special effects.
## - Pending decisions (ai_pending.gd): intent-driven effect choices, rewards by card/unit/skill tiers,
##   generic clone lookahead for special handlers.
##
## Helpers: ai_cards.gd (effect analysis/valuation, tunables), ai_combat.gd (combat planner),
## ai_turn.gd (missions outside combat, tactics), ai_pending.gd (pending decisions).

const C = preload("res://scripts/core/ai_cards.gd")
const CB = preload("res://scripts/core/ai_combat.gd")
const TU = preload("res://scripts/core/ai_turn.gd")
const PE = preload("res://scripts/core/ai_pending.gd")
const PV = preload("res://scripts/core/ai_pvp.gd")

## Time budget per decision (µs) by level; the web build is slower, callers may lower it.
static var budget_us = {1: 60000, 2: 120000, 3: 150000}
## Statistics (benchmarks): illegal = AI produced an illegal action (fallback used), forced = loop guards.
static var stats = {"illegal": 0, "forced": 0, "calls": 0, "us": 0, "max_us": 0}
static var _mem: Dictionary = {}

static func decide(eng, level: int = 2) -> Dictionary:
	var p: int = eng.actor()
	if p < 0 or eng.s.phase == "game_over":
		return {}
	var t0 = Time.get_ticks_usec()
	level = clampi(level, 1, 3)
	var mem = _memory(eng, p)
	var ctx = _ctx(eng, p, level, t0)
	var a: Dictionary = {}
	mem.n = int(mem.n) + 1
	if int(mem.n) > 160:
		# loop guard: too many actions in one turn
		stats.forced = int(stats.forced) + 1
		a = _fallback(eng, p, true)
	else:
		a = _decide(eng, p, ctx, mem)
	if a.is_empty() or eng.check(a) != "":
		if not a.is_empty():
			stats.illegal = int(stats.illegal) + 1
			if OS.is_debug_build() and OS.get_environment("AI_DEBUG") != "":
				printerr("AI illegal: ", JSON.stringify(a), " -> ", eng.check(a))
		a = _fallback(eng, p, false)
	var dt = Time.get_ticks_usec() - t0
	if dt > 200000 and OS.get_environment("AI_DEBUG") != "":
		printerr("AI slow %d ms: phase=%s pending=%s combat=%s -> %s" % [dt / 1000, eng.s.phase,
			str(eng.s.pending.handler) if eng.s.pending != null else "-", str(eng.s.combat.phase) if eng.s.combat != null else "-", JSON.stringify(a)])
	stats.calls = int(stats.calls) + 1
	stats.us = int(stats.us) + dt
	stats.max_us = maxi(int(stats.max_us), dt)
	return a

static func reset_stats() -> void:
	stats = {"illegal": 0, "forced": 0, "calls": 0, "us": 0, "max_us": 0}
	_mem.clear()

static func _memory(eng, p: int) -> Dictionary:
	var s: Dictionary = eng.s
	var gk = "%s|%d|%d" % [str(s.cfg.get("seed", 0)), s.players.size(), p]
	var tid = "%d:%d:%d" % [int(s.round), int(s.players[p].turns), int(s.turn.get("player", -1))]
	if s.phase == "tactics":
		tid = "tac:%d" % int(s.round)
	var mem: Dictionary = _mem.get(gk, {})
	if int(mem.get("seq", -1)) > int(s.get("log_seq", 0)):
		mem = {}   # a different game with the same seed (time went backwards)
	mem["seq"] = int(s.get("log_seq", 0))
	if mem.get("tid", "") != tid:
		var keep = {}
		for k in ["strat_sig", "strat", "goal", "tfail", "tfail_tid", "idle_n"]:
			if mem.has(k):
				keep[k] = mem[k]
		# consecutive turns without a productive action (fight, interaction, exploration)
		var old_tid = str(mem.get("tid", ""))
		if old_tid != "" and not old_tid.begins_with("tac"):
			keep["idle_n"] = 0 if mem.get("productive", false) else int(mem.get("idle_n", 0)) + 1
		mem = keep
		mem["seq"] = int(s.get("log_seq", 0))
		mem["tid"] = tid
		mem["n"] = 0
	if _mem.size() > 64 and not _mem.has(gk):
		_mem.clear()
	_mem[gk] = mem
	return mem

static func _ctx(eng, p: int, level: int, t0: int) -> Dictionary:
	var rng = RandomNumberGenerator.new()
	rng.seed = hash("%d|%d|%d" % [int(eng.s.get("rng", 0)), int(eng.s.get("log_seq", 0)), p])
	var rf = C.round_factor(eng, p)
	if level == 1:
		rf *= 1.35   # Facile: more cautious with its cards (fewer, safer fights)
	var idle_n = 0
	var gk = "%s|%d|%d" % [str(eng.s.cfg.get("seed", 0)), eng.s.players.size(), p]
	if _mem.has(gk):
		idle_n = mini(4, int(_mem[gk].get("idle_n", 0)))
	rf *= pow(0.75, float(idle_n))
	var wc = C.T("wc")
	var rounds = int(eng.s.scn.get("rounds", 6))
	var left = rounds - int(eng.s.round)
	if level >= 2:
		# a wound clogs the deck for the rest of the game: dearer early, cheap in the last round
		wc *= C.T("wc_base") + C.T("wc_slope") * float(clampi(left, 0, 5))
	elif int(eng.s.round) >= rounds:
		wc *= 0.85
	var fm = 1.0 + C.T("fm_slope") * float(clampi(left, 0, 5))
	if level >= 2 and str(eng.s.scn.get("mode", "")) == "coop" and eng.s.players.size() > 1:
		# the team score counts the LOWEST fame: fame of the leading hero matters less than the cities
		var low = 9999
		for j in eng.s.players.size():
			low = mini(low, int(eng.P(j).fame))
		var gap = int(eng.P(p).fame) - low
		if gap > 6:
			fm *= clampf(1.0 - 0.03 * float(gap - 6), C.T("coop_fm_min"), 1.0)
	return {"level": level, "rng": rng, "rf": rf, "idle_n": idle_n, "mp": C.mana_pool(eng, p), "wc": wc, "fm": fm,
		"deadline": t0 + int(budget_us.get(level, 120000)), "cap": 32 if level >= 3 else (12 if level == 2 else 6),
		"unit_mult": C.T("unit_mult") if level >= 3 else 1.0}

static func _decide(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var s: Dictionary = eng.s
	if s.pending != null:
		var hd = str(s.pending.get("handler", ""))
		if hd.begins_with("pvp:") or hd.begins_with("coop:"):
			return PV.pending(eng, p, ctx, mem)
		return PE.decide(eng, p, ctx, mem)
	if s.phase == "tactics":
		return TU.choose_tactic(eng, p, ctx)
	if s.phase != "turn":
		return {}
	if s.get("pvp", null) != null and s.combat != null:
		mem["productive"] = true
		mem.erase("intent")
		return PV.decide(eng, p, ctx, mem)
	if s.combat != null:
		mem["productive"] = true
		return CB.decide(eng, p, ctx, mem)
	var hk = PV.turn_hook(eng, p, ctx, mem)
	if not hk.is_empty() and eng.check(hk) == "":
		return hk
	return TU.decide(eng, p, ctx, mem)

## Safe legal action when the planner fails.
static func _fallback(eng, p: int, forced: bool) -> Dictionary:
	var s: Dictionary = eng.s
	if s.pending != null:
		for o in s.pending.options:
			var a = {"t": "choose", "v": [o.v]}
			if eng.check(a) == "":
				return a
		return {}
	if s.phase == "tactics":
		if not s.tactics_avail.is_empty():
			return {"t": "tactic", "id": s.tactics_avail[0]}
		return {}
	if s.get("pvp", null) != null and s.combat != null:
		for a3 in [{"t": "pvp", "op": "pass"}, {"t": "pvp", "op": "block"}, {"t": "pvp", "op": "strike"}]:
			if eng.check(a3) == "":
				return a3
	if s.combat != null:
		var c: Dictionary = s.combat
		if c.phase == "damage":
			for e in c.enemies:
				for i in e.attacks.size():
					if int(e.attacks[i].rem) > 0:
						return {"t": "damage", "eid": str(e.eid), "attack": i, "to": "hero"}
		if eng.check({"t": "next"}) == "":
			return {"t": "next"}
	for a2 in [{"t": "end_turn"}, {"t": "rest"}, {"t": "announce_end"}]:
		if eng.check(a2) == "":
			return a2
	var av: Array = eng.available()
	for x in av:
		if eng.check(x.a) == "":
			return x.a
	return {}
