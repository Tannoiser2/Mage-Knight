extends SceneTree
## AI benchmark (agent AI): plays whole games with AI heroes and reports statistics per scenario/level.
## Usage: godot --headless --path . -s res://tests/ai_sim.gd -- [games] [scenario|all] [level|all] [seed] [players]
##   scenario: solo_conquest | first_recon | coop_conquest | full_conquest | all
##   players: number of heroes for multi-player scenarios (default: coop 2, full 3)
## Env: AI_TRACE=1 (print every action + log), AI_QUIET=1 (only the summary).
## Reports: fame, level, cities conquered / victory, wounds, decision time (avg/max), illegal actions, stuck games.

const AI = preload("res://scripts/core/ai.gd")
const HEROES := ["arythea", "goldyx", "norowas", "tovak"]
var fights := {}

func _init():
	var args = OS.get_cmdline_user_args()
	var games = int(args[0]) if args.size() > 0 else 3
	var scen = str(args[1]) if args.size() > 1 else "all"
	var lv = str(args[2]) if args.size() > 2 else "all"
	var seed0 = int(args[3]) if args.size() > 3 else 1
	var np_arg = int(args[4]) if args.size() > 4 else 0
	var force_heroes: Array = str(args[5]).split(",") if args.size() > 5 else []
	MKDB.load_dir("res://data")
	var scens: Array = ["solo_conquest", "first_recon", "coop_conquest", "full_conquest"] if scen == "all" else [scen]
	var levels: Array = [1, 2, 3] if lv == "all" else [int(lv)]
	var quiet = OS.get_environment("AI_QUIET") != ""
	print("scenario        lvl np games  fame  lvl  cities  vict  wounds  rounds  acts   ms/dec  max_ms  illegal stuck forced")
	for sc in scens:
		for level in levels:
			var np = 1
			if sc == "coop_conquest":
				np = np_arg if np_arg > 0 else 2
			elif sc == "full_conquest":
				np = np_arg if np_arg > 0 else 3
			elif sc == "first_recon" and np_arg > 0:
				np = np_arg
			var agg = {"fame": 0.0, "lvl": 0.0, "cities": 0.0, "vict": 0.0, "wounds": 0.0, "rounds": 0.0, "acts": 0.0, "stuck": 0,
				"heroes": 0, "games": 0, "us": 0, "calls": 0, "max_us": 0, "illegal": 0, "forced": 0, "cities_total": 0.0}
			var kagg := {}
			for g in games:
				var seed: int = seed0 + g * 7919 + int(level) * 13
				var pls: Array = []
				for i in np:
					pls.append(HEROES[(i + g) % HEROES.size()] if force_heroes.is_empty() else force_heroes[i % force_heroes.size()])
				AI.reset_stats()
				var r = play(sc, pls, seed, level, quiet)
				agg.games += 1
				agg.stuck += 1 if r.err != "" else 0
				agg.rounds += float(r.rounds)
				agg.acts += float(r.actions)
				agg.cities += float(r.cities)
				agg.cities_total += float(r.cities_total)
				agg.vict += 1.0 if r.victory else 0.0
				for f in r.fame:
					agg.fame += float(f)
				for l in r.levels:
					agg.lvl += float(l)
				for w in r.wounds:
					agg.wounds += float(w)
				agg.heroes += np
				agg.us += int(AI.stats.us)
				agg.calls += int(AI.stats.calls)
				agg.max_us = maxi(int(agg.max_us), int(AI.stats.max_us))
				agg.illegal += int(AI.stats.illegal)
				agg.forced += int(AI.stats.forced)
				for kk in r.kinds:
					kagg[kk] = int(kagg.get(kk, 0)) + int(r.kinds[kk])
				if not quiet:
					print("  %s L%d seed=%d heroes=%s -> fame=%s lvl=%s cities=%d/%d victory=%s rounds=%d acts=%d %s" % [sc, level, seed, ",".join(pls),
						str(r.fame), str(r.levels), r.cities, r.cities_total, str(r.victory), r.rounds, r.actions, r.err])
			var nh: float = maxf(1.0, float(agg.heroes))
			var ng: float = maxf(1.0, float(agg.games))
			print("%-15s L%d  %d  %4d  %5.1f  %4.1f  %4.2f/%d  %4.2f  %5.1f  %5.1f  %5.0f  %6.1f  %6.1f   %d      %d     %d" % [sc, level, np, agg.games,
				agg.fame / nh, agg.lvl / nh, agg.cities / ng, int(round(agg.cities_total / ng)), agg.vict / ng, agg.wounds / nh, agg.rounds / ng,
				agg.acts / ng, float(agg.us) / maxf(1.0, float(agg.calls)) / 1000.0, float(agg.max_us) / 1000.0, agg.illegal, agg.stuck, agg.forced])
			if OS.get_environment("AI_KINDS") != "":
				for fk in fights:
					var fs: Dictionary = fights[fk]
					print("   fights %s: n=%d won=%.0f%% fame/f=%.2f pred=%.2f wounds/f=%.2f" % [fk, fs.n, 100.0 * fs.won / maxf(1, fs.n), float(fs.fame) / maxf(1, fs.n), fs.pred / maxf(1, fs.n), float(fs.wounds) / maxf(1, fs.n)])
				fights.clear()
				var parts: Array = []
				for kk in kagg:
					parts.append("%s=%.1f" % [kk, float(kagg[kk]) / ng])
				print("   per game: ", ", ".join(parts))
	quit()

func play(scn: String, heroes: Array, seed: int, level: int, quiet: bool) -> Dictionary:
	var cfg = {"scenario": scn, "seed": seed, "players": [], "options": {}}
	if OS.get_environment("AI_SETS") != "":
		cfg.options["sets"] = OS.get_environment("AI_SETS").split(",")
	for h in heroes:
		cfg.players.append({"hero": h, "ctrl": "ai", "ai_level": level, "name": h.capitalize()})
	var e = MKEngine.create(cfg)
	var n = 0
	var err = ""
	var trace = OS.get_environment("AI_TRACE") != ""
	var kinds := {}
	var cur_fight := {}
	var tflags := {}
	while e.s.phase != "game_over":
		n += 1
		if n > 6000:
			err = "STUCK: troppe azioni"
			break
		var p: int = e.actor()
		if p < 0:
			err = "STUCK: nessun attore (phase=%s)" % e.s.phase
			break
		var a: Dictionary = AI.decide(e, level)
		if a.is_empty():
			err = "STUCK: nessuna azione (phase=%s pending=%s combat=%s)" % [e.s.phase, str(e.s.pending != null), str(e.s.combat != null)]
			break
		var l0: int = int(e.s.log_seq)
		var res: Dictionary = e.apply(a)
		for le in e.s.log:
			if int(le.seq) >= l0:
				var kk := str(le.k)
				if kk == "turn" or kk == "game_over":
					if not tflags.is_empty():
						var cls := "t_idle"
						for fk2 in ["combat_start", "reveal", "interact", "rest"]:
							if tflags.has(fk2):
								cls = "t_" + fk2
								break
						kinds[cls] = int(kinds.get(cls, 0)) + 1
					tflags = {}
					if kk == "turn" and int(le.get("p", -1)) != 9:
						tflags["_"] = true
				elif not tflags.is_empty():
					if kk in ["combat_start", "reveal", "rest"]:
						tflags[kk] = true
					elif kk in ["recruit", "heal", "gain_card", "buy"]:
						tflags["interact"] = true
				if kk == "assault" and str(e.hex(str(le.get("hex", ""))).get("site", "")) == "city":
					kinds["city_assault"] = int(kinds.get("city_assault", 0)) + 1
				if kk == "round_end" or kk == "game_over":
					var rr := int(le.get("round", e.s.round))
					if rr == 3 or kk == "game_over":
						var tag := "r3" if kk != "game_over" else "end"
						for pi in e.s.players.size():
							kinds["fame_" + tag] = int(kinds.get("fame_" + tag, 0)) + int(e.P(pi).fame)
							kinds["units_" + tag] = int(kinds.get("units_" + tag, 0)) + e.P(pi).units.size()
				if kk == "city":
					kinds["city_round_sum"] = int(kinds.get("city_round_sum", 0)) + int(e.s.round)
					kinds["city_n"] = int(kinds.get("city_n", 0)) + 1
				if kk == "combat_start":
					cur_fight = {"kind": "?", "pred": 0.0, "w0": _wounds(e, p)}
					for gk in AI._mem:
						var mm: Dictionary = AI._mem[gk]
						if mm.has("mission") and str(gk).ends_with("|%d" % p):
							cur_fight.kind = str(mm.mission.get("kind", "?"))
							cur_fight.pred = float(mm.mission.get("value", 0.0))
				if kk == "combat_end" and not cur_fight.is_empty():
					var fk: String = cur_fight.kind
					var fs: Dictionary = fights.get(fk, {"n": 0, "won": 0, "fame": 0, "pred": 0.0, "wounds": 0})
					fs.n += 1
					fs.won += 1 if le.get("won", false) else 0
					fs.fame += int(le.get("fame", 0))
					fs.pred += float(cur_fight.pred)
					fs.wounds += _wounds(e, p) - int(cur_fight.w0)
					fights[fk] = fs
					cur_fight = {}
				if kk == "combat_end" and le.get("won", false):
					kinds["combat_won"] = int(kinds.get("combat_won", 0)) + 1
				if kk == "combat_end":
					kinds["fame_in_combat"] = int(kinds.get("fame_in_combat", 0)) + int(le.get("fame", 0))
				if kk in ["combat_start", "enemy_defeated", "rest", "conquer", "recruit", "reveal", "turn", "wound", "knockout", "retreat", "gain_card", "skill_gain", "end_turn", "pvp_start", "pvp_end", "coop_start", "coop_end"]:
					kinds[kk] = int(kinds.get(kk, 0)) + 1
		if trace:
			printerr("#%d p%d %s %s" % [n, p, JSON.stringify(a), "" if res.ok else "RIFIUTATA " + res.err])
			for le in e.s.log:
				if int(le.seq) >= l0:
					printerr("      · ", le.txt)
		if not res.ok:
			err = "AZIONE RIFIUTATA: %s -> %s" % [JSON.stringify(a), res.err]
			break
	var fame: Array = []
	var levels: Array = []
	var wounds: Array = []
	for pl in e.s.players:
		fame.append(int(pl.fame))
		levels.append(int(pl.level))
		var w = 0
		for iid in pl.deck + pl.hand + pl.discard + pl.play:
			if e.is_wound(iid):
				w += 1
		wounds.append(w)
	var cities = 0
	var total = 0
	for k in e.s.map.hex:
		if e.s.map.hex[k].site == "city":
			total += 1
			if e.s.map.hex[k].conquered:
				cities += 1
	var res2 = e.s.result
	var victory: bool = res2 != null and res2.get("victory", false)
	if res2 != null:
		var tot := 0.0
		for sc in res2.get("scores", []):
			tot += float(sc.get("total", 0))
		kinds["score"] = int(tot)
		if res2.has("team_score"):
			kinds["team_score"] = int(res2.team_score)
	return {"fame": fame, "levels": levels, "wounds": wounds, "cities": cities, "cities_total": int(e.s.scn.get("city", 0)) if e.s.scn.get("end", "") == "cities" else total,
		"victory": victory, "rounds": int(e.s.round), "actions": n, "err": err, "kinds": kinds}

func _wounds(e: MKEngine, p: int) -> int:
	var w := 0
	var pl: Dictionary = e.P(p)
	for iid in pl.deck + pl.hand + pl.discard + pl.play:
		if e.is_wound(iid):
			w += 1
	return w
