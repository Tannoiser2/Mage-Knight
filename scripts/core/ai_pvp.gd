extends RefCounted
## IA (agente PVP-COOP): combattimento tra giocatori e assalto cooperativo alla città.
## - turn_hook: prima del pianificatore del turno (ai_turn.gd): attacca un altro eroe quando conviene
##   (competitivo), propone un assalto cooperativo con gli alleati adiacenti alla città o si avvicina alla
##   città dove un alleato aspetta (cooperativo).
## - decide: azioni durante s.pvp (gioca carte d'attacco/blocco in modo avido, attacca, blocca, passa).
## - pending: decisioni "pvp:*" e "coop:*".

const C = preload("res://scripts/core/ai_cards.gd")
const TU = preload("res://scripts/core/ai_turn.gd")

# ================================================================ stime
static func _unit_best(eng, u: Dictionary, what: String) -> float:
	var best = 0.0
	for ab in eng.unit_def(u).get("abilities", []):
		for b in C.parse(ab.get("effect", []), {"day": eng.s.day, "combat": true, "phase": "any"}):
			var t = 0.0
			for k in (b.atk if what == "atk" else b.blk):
				t += float((b.atk if what == "atk" else b.blk)[k])
			best = maxf(best, t)
	return best

## Attacco stimato con la mano attuale e le unità pronte.
static func hand_attack(eng, p: int) -> float:
	var pl: Dictionary = eng.P(p)
	var t = 0.0
	for iid in pl.hand:
		if not eng.is_wound(iid):
			t += TU.card_attack(eng.card_id(iid))
	for u in pl.units:
		if u.ready and not u.wounded:
			t += _unit_best(eng, u, "atk")
	for c in C.BASIC:
		t += 0.5 * float(mini(1, int(pl.crystals.get(c, 0))))
	return t

## Blocco che un avversario può probabilmente opporre (si conosce solo il numero di carte in mano).
static func block_guess(eng, j: int) -> float:
	var pl: Dictionary = eng.P(j)
	var n = 0
	for iid in pl.hand:
		if not eng.is_wound(iid):
			n += 1
	var u = 0.0
	for x in pl.units:
		if x.ready and not x.wounded:
			u += _unit_best(eng, x, "blk")
	return 1.4 * float(n) + u

static func _non_wounds(eng, p: int) -> int:
	var n = 0
	for iid in eng.P(p).hand:
		if not eng.is_wound(iid):
			n += 1
	return n

# ================================================================ turno: iniziative
static func turn_hook(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var s: Dictionary = eng.s
	if s.combat != null or s.get("pvp", null) != null or s.get("coop", null) != null or s.phase != "turn":
		return {}
	var t: Dictionary = s.turn
	if t.get("acted", false) or t.get("rested", false) or t.get("ending", false):
		return {}
	# --- assalto cooperativo
	if MKCoop.enabled(eng):
		var ca = _coop_initiative(eng, p, ctx, mem)
		if not ca.is_empty():
			return ca
	# --- combattimento tra giocatori
	if MKPvP.enabled(eng):
		var goal = str(mem.get("pvp_goal", ""))
		if goal == "" and not t.get("moved", false) and t.played.is_empty() and not mem.has("pvp_eval"):
			mem["pvp_eval"] = true
			goal = _pvp_target(eng, p, ctx)
			if goal != "":
				mem["pvp_goal"] = goal
		if goal != "":
			if str(eng.P(p).pos) == goal:
				mem.erase("pvp_goal")
				if eng.check({"t": "pvp_attack"}) == "":
					mem["productive"] = true
					return {"t": "pvp_attack"}
				return {}
			var mv = _walk_to(eng, p, ctx, mem, goal)
			if mv.is_empty():
				mem.erase("pvp_goal")
			return mv
	return {}

## Spazio di un avversario da attaccare in questo turno ("" = nessuno).
static func _pvp_target(eng, p: int, ctx: Dictionary) -> String:
	var level = int(ctx.get("level", 2))
	if level < 2:
		return ""
	var s: Dictionary = eng.s
	if int(s.round) >= int(s.scn.get("rounds", 6)) and false:
		return ""
	var my_atk = hand_attack(eng, p)
	var best = ""
	var bv = 0.0
	var budget = int(s.turn.pool.move)
	for it in TU.move_items(eng, p, ctx, "fight"):
		var bm = 0
		for o in it.opts:
			bm = maxi(bm, int(o.v))
		budget += bm
	budget = mini(budget, 12)
	var r = TU.reach(eng, p, budget)
	for j in s.players.size():
		if j == p:
			continue
		var k = str(eng.P(j).pos)
		if not r.dist.has(k) or MKPvP.shareable(eng, k) or str(eng.hex(k).get("site", "")) == "city" or MKPvP.flipped(eng, j):
			continue
		var d = int(r.dist[k])
		var atk_left = my_atk - 0.5 * float(maxi(0, d - int(s.turn.pool.move)))
		var need = block_guess(eng, j) + float(eng.P(j).armor) + 3.0
		if atk_left < need * (1.1 if level >= 3 else 1.3):
			continue
		var fame = float(MKPvP.fame_reward(eng, p, j))
		var lead = float(int(eng.P(j).fame) - int(eng.P(p).fame))
		var v = fame + 0.15 * maxf(0.0, lead) + 0.25 * (atk_left - need)
		if fame <= 0.0 and lead < 6.0:
			continue
		if v > bv and v >= 2.5:
			bv = v
			best = k
	return best

## Un passo verso goal: movimento o carta di movimento ({} = impossibile).
static func _walk_to(eng, p: int, ctx: Dictionary, mem: Dictionary, goal: String) -> Dictionary:
	var t: Dictionary = eng.s.turn
	var budget = int(t.pool.move)
	var items = TU.move_items(eng, p, ctx, "fight")
	for it in items:
		var bm = 0
		for o in it.opts:
			bm = maxi(bm, int(o.v))
		budget += bm
	var r = TU.reach(eng, p, mini(budget, 20))
	if not r.dist.has(goal):
		return {}
	var path = TU.path_to(r, goal)
	if path.is_empty():
		return {}
	var a = {"t": "move", "to": path[0]}
	if eng.check(a) == "":
		return a
	var need = 0
	for k in path:
		need += eng.move_cost(k)
	var pa = TU._play_move(eng, p, ctx, mem, need - int(t.pool.move), "fight")
	return pa

static func _coop_initiative(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var s: Dictionary = eng.s
	for k in MKCoop.cities_adjacent(eng, p):
		if int(s.turn.get("coop_tries", 0)) > 0:
			break
		var a = {"t": "coop", "city": k}
		if eng.check(a) != "":
			continue
		var team = hand_attack(eng, p)
		for j in MKCoop.available_heroes(eng, p, k):
			team += hand_attack(eng, j)
		var req = _city_req(eng, p, k)
		if team >= req * (0.8 if int(ctx.get("level", 2)) >= 2 else 1.0):
			mem["productive"] = true
			return a
	# avvicinarsi a una città dove un alleato è già adiacente (coordinamento)
	if s.turn.get("moved", false) or not s.turn.played.is_empty():
		if str(mem.get("coop_goal", "")) == "":
			return {}
	var goal = str(mem.get("coop_goal", ""))
	if goal == "":
		goal = _coop_stage_target(eng, p, ctx)
		if goal == "":
			return {}
		mem["coop_goal"] = goal
	if str(eng.P(p).pos) == goal:
		mem.erase("coop_goal")
		return {}
	var mv = _walk_to(eng, p, ctx, mem, goal)
	if mv.is_empty():
		mem.erase("coop_goal")
	return mv

static func _city_req(eng, p: int, k: String) -> float:
	var alts = TU.site_models(eng, p, k, "assault", false)
	if alts.is_empty():
		return 99.0
	return TU.models_req(alts[0][1])

## Spazio adiacente a una città, raggiungibile in questo turno, accanto alla quale un alleato disponibile aspetta.
static func _coop_stage_target(eng, p: int, ctx: Dictionary) -> String:
	var s: Dictionary = eng.s
	var budget = int(s.turn.pool.move)
	for it in TU.move_items(eng, p, ctx, "fight"):
		var bm = 0
		for o in it.opts:
			bm = maxi(bm, int(o.v))
		budget += bm
	budget = mini(budget, 12)
	var r = TU.reach(eng, p, budget)
	var best = ""
	var bd = 999
	for k in s.map.hex:
		var h: Dictionary = s.map.hex[k]
		if str(h.get("site", "")) != "city" or h.get("conquered", false) or h.get("enemies", []).is_empty():
			continue
		if MKHex.adjacent(str(eng.P(p).pos), k):
			continue
		var allies: Array = []
		for j in s.players.size():
			if j != p and MKHex.adjacent(str(eng.P(j).pos), k) and not eng.P(j).get("skip_next", false) and eng.has_non_wound(j):
				allies.append(j)
		if allies.is_empty():
			continue
		var team = hand_attack(eng, p)
		for j in allies:
			team += hand_attack(eng, j)
		if team < _city_req(eng, p, k) * 0.8:
			continue
		for nk in MKHex.neighbors(k):
			if not r.dist.has(nk) or TU.other_hero_at(eng, p, nk) or not eng._is_safe(p, nk):
				continue
			var d = int(r.dist[nk])
			if d < bd:
				bd = d
				best = nk
	return best

# ================================================================ combattimento tra giocatori
static func decide(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var pv: Dictionary = eng.s.pvp
	var step = str(pv.step)
	if step == "attack":
		return _as_striker(eng, p, ctx)
	if step == "block":
		return _as_blocker(eng, p, ctx)
	return {}

static func _phase(eng) -> String:
	return "attack" if str(eng.s.pvp.phase) == "melee" else "ranged"

## Opzioni (carte, unità) che aggiungono punti del tipo voluto ("atk" con i tipi d'attacco consentiti, "blk").
static func _gain_opts(eng, p: int, what: String) -> Array:
	var pl: Dictionary = eng.P(p)
	var ph = _phase(eng) if what == "atk" else "block"
	var cctx = C.base_ctx(eng, p, true, ph)
	var out: Array = []
	var siege_only = MKPvP._siege_only(eng)
	var seen = {}
	for iid in pl.hand:
		if eng.is_wound(iid) or seen.has(eng.card_id(iid)):
			continue
		seen[eng.card_id(iid)] = true
		for o in C.card_opts(eng, p, iid, cctx, true):
			var v = _opt_value(o.b, what, ph, siege_only)
			if v <= 0:
				continue
			if not o.b.sp.is_empty() and o.mode != "side":
				continue
			if eng.check(o.act) != "":
				continue
			var cost = C.card_value(eng, p, iid, -1.0) + (0.6 if o.mode == "powered" else 0.0) + float(o.get("c", 0.0))
			out.append({"act": o.act, "v": v, "cost": cost})
	for u in pl.units:
		if not u.ready or u.wounded:
			continue
		for o2 in C.unit_opts(eng, p, u, cctx):
			var v2 = _opt_value(o2.b, what, ph, siege_only)
			if v2 <= 0 or eng.check(o2.act) != "":
				continue
			out.append({"act": o2.act, "v": v2, "cost": 0.8})
	return out

static func _opt_value(b: Dictionary, what: String, ph: String, siege_only: bool) -> int:
	var v = 0
	if what == "atk":
		for k in b.atk:
			var kind = str(k).split(":")[0]
			if ph == "ranged" and (kind == "melee" or (siege_only and kind != "siege")):
				continue
			v += int(b.atk[k])
	else:
		for k in b.blk:
			v += int(b.blk[k])
	return v

static func _best_gain(opts: Array) -> Dictionary:
	var best = {}
	var bv = -1.0
	for o in opts:
		var r = float(o.v) / maxf(0.3, float(o.cost))
		if r > bv:
			bv = r
			best = o
	return best

static func _as_striker(eng, p: int, ctx: Dictionary) -> Dictionary:
	var pv: Dictionary = eng.s.pvp
	var b = int(pv.def) if p == int(pv.att) else int(pv.att)
	var v = MKPvP.strike_value(eng)
	var melee = str(pv.phase) == "melee"
	var arm = MKPvP.hero_armor(eng, b)
	var guess = block_guess(eng, b) / (2.0 if not melee else 1.0)
	var rc = 99
	for x in MKPvP.retreat_hexes(eng, b):
		rc = mini(rc, int(x[1]))
	var goal = float(arm) + guess
	if melee and rc < 99:
		goal = maxf(goal, float(rc) + guess)
	var opts = _gain_opts(eng, p, "atk")
	var pot = float(v)
	for o in opts:
		pot += float(o.v)
	if v == 0 and pot < goal * 0.8:
		return {"t": "pvp", "op": "pass"}
	if float(v) >= goal or opts.is_empty():
		if v > 0:
			return {"t": "pvp", "op": "strike"}
		return {"t": "pvp", "op": "pass"}
	var g = _best_gain(opts)
	return g.act

static func _as_blocker(eng, p: int, ctx: Dictionary) -> Dictionary:
	var pv: Dictionary = eng.s.pvp
	var n = int(pv.strike.n) if pv.strike != null else 0
	var red = MKPvP.block_reduction(eng)
	var left = n - red
	# il danno minimo utile per l'attaccante: ferire l'eroe o un'unità, o (corpo a corpo) farlo ritirare
	var thr = MKPvP.hero_armor(eng, p)
	for u in eng.P(p).units:
		if not u.wounded:
			thr = mini(thr, MKPvP.unit_armor(eng, p, u, pv.strike.get("elems", ["phys"])))
	if str(pv.phase) == "melee":
		for x in MKPvP.retreat_hexes(eng, p):
			thr = mini(thr, int(x[1]))
	if left < thr:
		return {"t": "pvp", "op": "block"}
	var opts = _gain_opts(eng, p, "blk")
	if opts.is_empty():
		return {"t": "pvp", "op": "block"}
	var g = _best_gain(opts)
	return g.act

# ================================================================ decisioni
static func pending(eng, p: int, ctx: Dictionary, mem: Dictionary) -> Dictionary:
	var pend: Dictionary = eng.s.pending
	var opts: Array = pend.options
	var h = str(pend.handler)
	var pick = opts[0].v
	match h:
		"pvp:mode":
			pick = "partial"
			if _non_wounds(eng, p) <= 1 and _has(opts, "full"):
				pick = "full"
		"pvp:hit":
			pick = _hit_pick(eng, p, opts)
		"coop:invite":
			var bestn = -1
			for o in opts:
				var n = str(o.v).split(",").size() if str(o.v) != "cancel" else 0
				if n > bestn:
					bestn = n
					pick = o.v
		"coop:split":
			pick = _split_pick(eng, p, opts)
		"coop:accept":
			pick = "yes" if _accept(eng, p) else "no"
	return {"t": "choose", "v": [pick]}

static func _has(opts: Array, v) -> bool:
	for o in opts:
		if str(o.v) == str(v):
			return true
	return false

static func _hit_pick(eng, p: int, opts: Array):
	var pv: Dictionary = eng.s.pvp
	var b = int(pv.def) if p == int(pv.att) else int(pv.att)
	var d = int(pv.dmg)
	var arm = MKPvP.hero_armor(eng, b)
	var retreat = ""
	var rcost = 99
	var art = ""
	var unit = ""
	for o in opts:
		var sv = str(o.v)
		if not eng.hex(sv).is_empty():
			var c = MKPvP.retreat_cost(eng, sv)
			if c < rcost:
				rcost = c
				retreat = sv
		elif sv.begins_with("a:") and art == "":
			art = sv
		elif sv.begins_with("u:") and unit == "":
			unit = sv
	if retreat != "":
		if _has(opts, "hero") and d - arm >= rcost:
			return "hero"
		if art != "" and d - 5 >= rcost:
			return art
		return retreat
	if _has(opts, "hero"):
		return "hero"
	if art != "":
		return art
	if unit != "":
		return unit
	return "done"

static func _split_pick(eng, p: int, opts: Array):
	var pr = eng.s.get("coop_prop", null)
	if pr == null:
		return opts[0].v
	var pw: Array = []
	for m in pr.members:
		pw.append(maxf(1.0, hand_attack(eng, int(m))))
	var best = opts[0].v
	var bv = 1e9
	for o in opts:
		if str(o.v) == "cancel":
			continue
		var parts = str(o.v).split(",")
		var worst = 0.0
		for i in parts.size():
			worst = maxf(worst, float(int(parts[i])) / float(pw[i]))
		if worst < bv:
			bv = worst
			best = o.v
	return best

static func _accept(eng, p: int) -> bool:
	var pr = eng.s.get("coop_prop", null)
	if pr == null:
		return false
	var i = pr.members.find(p)
	var n = int(pr.split[i]) if i >= 0 and i < pr.split.size() else 1
	var nw = _non_wounds(eng, p)
	return nw >= 3 or (nw >= 2 and n <= 1) or hand_attack(eng, p) >= 4.0 * float(n)
