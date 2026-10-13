extends SceneTree
## City-assault lab (agent AI): sets up an assault on a city garrison with a given hand/units/level and lets
## the AI fight it; prints the pre-combat mission estimate and the outcome (defenders defeated, wounds).
## Usage: godot --headless --path . -s res://tests/ai_citylab.gd -- [trials] [city_color] [level] [build] [ai_level]
##   build: a | b | c (see BUILDS)

const AI = preload("res://scripts/core/ai.gd")
const CB = preload("res://scripts/core/ai_combat.gd")

const BUILDS := {
	"a": {"hero_level": 3, "hand": ["rage", "determination", "march", "swiftness", "stamina"], "units": []},
	"b": {"hero_level": 5, "hand": ["rage", "determination", "swiftness", "fire_bolt", "ice_shield", "concentration"], "units": ["utem_crossbowmen", "red_cape_monks"]},
	"s": {"hero_level": 5, "hand": ["rage", "determination", "chill", "whirlwind", "tremor", "concentration"], "units": ["utem_crossbowmen", "red_cape_monks"], "crystals": {"blue": 2, "white": 2, "green": 1}},
	"u": {"hero_level": 2, "hand": [], "units": ["utem_guardsmen"]},
	"c": {"hero_level": 6, "hand": ["rage", "determination", "swiftness", "fire_bolt", "ice_shield", "concentration", "blood_rage"], "units": ["catapults", "ice_mages", "utem_guardsmen"]},
}

func _init():
	var args = OS.get_cmdline_user_args()
	var trials = int(args[0]) if args.size() > 0 else 5
	var color = str(args[1]) if args.size() > 1 else "green"
	var clevel = int(args[2]) if args.size() > 2 else 5
	var build = str(args[3]) if args.size() > 3 else "b"
	var lv = int(args[4]) if args.size() > 4 else 3
	MKDB.load_dir("res://data")
	var kills = 0.0
	var wounds = 0.0
	var conq = 0
	for t in trials:
		var r = trial(color, clevel, BUILDS[build], lv, 1000 + t * 17)
		kills += r.kills
		wounds += r.wounds
		conq += 1 if r.conq else 0
		print("trial %d: garrison=%s est=%.2f kills=%d/%d wounds=%d conquered=%s" % [t, ",".join(r.types), r.est, r.kills, r.n, r.wounds, str(r.conq)])
	print("avg kills %.2f wounds %.2f conquered %d/%d" % [kills / trials, wounds / trials, conq, trials])
	quit()

func trial(color: String, clevel: int, build: Dictionary, lv: int, seed: int) -> Dictionary:
	var e := MKEngine.create({"scenario": "solo_conquest", "seed": seed, "players": [{"hero": "tovak", "ctrl": "ai"}], "options": {}})
	var guard := 0
	while (e.s.phase == "tactics" or e.s.pending != null) and guard < 20:
		guard += 1
		e.apply(AI.decide(e, 2))
	var pl: Dictionary = e.P(0)
	pl.level = int(build.hero_level)
	pl.armor = 2 if pl.level < 3 else (3 if pl.level < 7 else 4)
	pl.hand_limit = 5 if pl.level < 5 else 6
	pl.hand = []
	var i := 900
	for id in build.hand:
		i += 1
		pl.hand.append("%s#%d" % [id, i])
	for uid in build.units:
		MKSites.gain_unit(e, 0, uid)
	for col in build.get("crystals", {}):
		pl.crystals[col] = int(build.crystals[col])
	# a city next to the hero
	var here: String = pl.pos
	var k := ""
	for nk in MKHex.neighbors(here):
		if not e.hex(nk).is_empty() and e.move_cost(nk) < 999:
			k = nk
			break
	var h: Dictionary = e.hex(k)
	var types: Array = []
	var kind := "assault"
	h.t = "plains"
	h.enemies = []
	if color.begins_with("enemy:"):
		# rampaging enemies next to the hero (challenge)
		kind = "challenge"
		h.site = ""
		h.rampage = true
		for tid in color.substr(6).split(","):
			var eid2 := "x%d" % (h.enemies.size() + 1)
			e.s.enemies[eid2] = {"type": tid, "color": str(MKDB.enemies[tid].color), "face_up": true, "hex": k}
			h.enemies.append(eid2)
			types.append(tid)
	else:
		h.site = "city"
		h.city = {"color": color, "level": clevel, "shields": [], "leader": -1}
		var gar: Array = MKDB.cities[color].garrison[str(clevel)]
		for col in gar:
			var eid: String = e.draw_enemy(str(col), true, k)
			h.enemies.append(eid)
			types.append(str(e.s.enemies[eid].type))
	e.s.turn.pool.move = 2
	# pre-combat estimate (mission planner)
	var ctx = AI._ctx(e, 0, lv, Time.get_ticks_usec())
	ctx.deadline = Time.get_ticks_usec() + 5000000
	var est = AI.TU._fight_mission(e, 0, ctx, k, kind, 2 if kind == "assault" else 0, [], [], "" if kind == "assault" else here, {})
	var n: int = h.enemies.size()
	var f0 := int(pl.fame)
	var w0 := 0
	if kind == "assault":
		e.apply({"t": "move", "to": k})
	else:
		print("challenge: ", e.apply({"t": "challenge", "hexes": [k]}))
	if OS.get_environment("LAB_TRACE") != "":
		var ctx2 = AI._ctx(e, 0, lv, Time.get_ticks_usec())
		ctx2.deadline = Time.get_ticks_usec() + 5000000
		var pn = CB.plan_now(e, 0, ctx2)
		print("plan score %.2f kills=%s blocks=%d R=%d A=%d" % [float(pn.score), str(pn.kills), pn.blocks.size(), pn.groupsR.size(), pn.groupsA.size()])
		for it in pn.items:
			var vs: Array = []
			for o in it.opts:
				vs.append("%s c%.2f" % [JSON.stringify({"a": o.b.atk, "b": o.b.blk}), float(o.c)])
			print("   item %s %s val %.2f: %s" % [it.kind, str(it.key), float(it.val), "; ".join(vs)])
		for m in pn.models:
			print("   enemy ", JSON.stringify(m))
	var steps := 0
	while e.s.combat != null and steps < 120:
		steps += 1
		var a: Dictionary = AI.decide(e, lv)
		if OS.get_environment("LAB_TRACE") != "":
			print("   ", JSON.stringify(a))
		var r = e.apply(a)
		if not r.ok:
			print("rejected ", JSON.stringify(a), r.err)
			break
	var w := 0
	for iid in pl.hand + pl.discard + pl.deck:
		if e.is_wound(iid):
			w += 1
	var kills: int = n - h.enemies.size()
	return {"types": types, "est": float(est.get("value", -99.0)), "kills": kills, "n": n, "wounds": w, "conq": bool(h.get("conquered", false))}
