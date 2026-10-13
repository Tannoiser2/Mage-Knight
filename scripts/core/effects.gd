class_name MKEffects
extends RefCounted
## Interpreter of the effect DSL (SPEC §5). Effects are executed from a
## queue; compound ops push their parts to the front. When a decision is
## needed, the remaining queue + context are stored in s.pending and the
## run stops; the engine resumes it when the player answers.

const ELEM_IT := {"phys": "", "fire": " di fuoco", "ice": " di ghiaccio", "cold": " di fuoco-ghiaccio"}
const KIND_IT := {"melee": "Attacco", "ranged": "Attacco a distanza", "siege": "Attacco d'assedio"}
const TERR_IT := {"plains": "pianura", "hills": "colline", "forest": "foresta", "desert": "deserto", "wasteland": "landa desolata",
	"swamp": "palude", "lake": "lago", "mountain": "montagna", "ocean": "oceano", "all": "tutti i terreni"}

## Start executing an effect list.
static func start(eng, effects: Array, ctx: Dictionary) -> void:
	run(eng, effects.duplicate(true), ctx)

## Run a queue until empty or suspended on a decision.
static func run(eng, queue: Array, ctx: Dictionary) -> void:
	var guard := 0
	while not queue.is_empty():
		guard += 1
		if guard > 500:
			eng.add_log("error", "Effetto interrotto (ciclo)")
			return
		var e = queue.pop_front()
		if not (e is Array) or e.is_empty():
			continue
		if not (e[0] is String):
			# nested list of effects
			for i in range(e.size() - 1, -1, -1):
				queue.push_front(e[i])
			continue
		eng._q = queue
		eng._suspended = false
		exec(eng, e, ctx, queue)
		if eng._suspended:
			eng._suspended = false
			return

## Push effects in front of the running queue (used by specials).
static func push(eng, effects: Array) -> void:
	if eng._q == null:
		eng._q = []
	for i in range(effects.size() - 1, -1, -1):
		eng._q.push_front(effects[i])

## Suspend the running queue on a decision.
static func suspend(eng, ctx: Dictionary, pending: Dictionary) -> void:
	pending["queue"] = eng._q.duplicate(true) if eng._q != null else []
	pending["ctx"] = ctx.duplicate(true)
	if not pending.has("player"):
		pending["player"] = int(ctx.get("p", eng.s.turn.get("player", 0)))
	if not pending.has("min"):
		pending["min"] = 1
	if not pending.has("max"):
		pending["max"] = 1
	eng.s.pending = pending
	if eng._q != null:
		eng._q.clear()
	eng._suspended = true

static func _n(e: Array, i: int, ctx: Dictionary) -> int:
	var v = e[i] if e.size() > i else 0
	if v is String and v.begins_with("$"):
		return int(ctx.get(v.substr(1), 0))
	return int(v)

static func exec(eng, e: Array, ctx: Dictionary, queue: Array) -> void:
	var s: Dictionary = eng.s
	var p: int = int(ctx.get("p", s.turn.get("player", 0)))
	var op: String = e[0]
	var boost := int(ctx.get("boost", 0))
	var pool: Dictionary = s.turn.pool
	match op:
		"move":
			var n := _n(e, 1, ctx) + boost
			n = MKSpecials.adjust(eng, ctx, "move", n, "", "")[0]
			pool.move = int(pool.move) + n
			eng.add_log("pts", "+%d Movimento" % n, {"p": p, "what": "move", "n": n})
		"influence":
			var n2 := _n(e, 1, ctx) + boost
			n2 = MKSpecials.adjust(eng, ctx, "influence", n2, "", "")[0]
			pool.influence = int(pool.influence) + n2
			eng.add_log("pts", "+%d Influenza" % n2, {"p": p, "what": "influence", "n": n2})
		"heal":
			var n3 := _n(e, 1, ctx)
			pool.heal = int(pool.heal) + n3
			eng.add_log("pts", "+%d Guarigione" % n3, {"p": p, "what": "heal", "n": n3})
			eng.auto_heal(p)
		"attack":
			var n4 := _n(e, 1, ctx) + boost
			var el: String = e[2] if e.size() > 2 and e[2] != null else "phys"
			var kd: String = e[3] if e.size() > 3 and e[3] != null else "melee"
			n4 += eng.attack_bonus(p, kd, el, ctx)
			var adj: Array = MKSpecials.adjust(eng, ctx, "attack", n4, el, kd)
			n4 = adj[0]
			el = adj[1]
			kd = adj[2]
			var key := kd + ":" + el
			pool.attack[key] = int(pool.attack.get(key, 0)) + n4
			eng.add_log("pts", "+%d %s%s" % [n4, KIND_IT.get(kd, "Attacco"), ELEM_IT.get(el, "")], {"p": p, "what": "attack", "n": n4, "kind": kd, "elem": el})
		"block":
			var n5 := _n(e, 1, ctx) + boost
			var el2: String = e[2] if e.size() > 2 and e[2] != null else "phys"
			n5 += eng.block_bonus(p, el2, ctx)
			var adj2: Array = MKSpecials.adjust(eng, ctx, "block", n5, el2, "")
			n5 = adj2[0]
			el2 = adj2[1]
			pool.block[el2] = int(pool.block.get(el2, 0)) + n5
			eng.add_log("pts", "+%d Blocco%s" % [n5, ELEM_IT.get(el2, "")], {"p": p, "what": "block", "n": n5, "elem": el2})
		"fame":
			eng.gain_fame(p, _n(e, 1, ctx))
		"rep":
			eng.change_rep(p, _n(e, 1, ctx))
		"draw":
			eng.draw(p, _n(e, 1, ctx))
		"mana":
			var c: String = str(e[1]) if e.size() > 1 else "basic"
			if c == "basic" or c == "any":
				_ask_color(eng, ctx, "mana", "Scegli il colore del gettone mana", c == "any")
			else:
				eng.gain_token(p, c)
		"crystal":
			var c2: String = str(e[1]) if e.size() > 1 else "basic"
			if c2 == "$paid":
				c2 = str(ctx.get("paid", "basic"))
			if not c2 in MKMana.BASIC:
				_ask_color(eng, ctx, "crystal", "Scegli il colore del cristallo", false)
			else:
				eng.gain_crystal(p, c2)
		"choice":
			var opts: Array = e[1] if e.size() > 1 and e[1] is Array else []
			var ok_opts: Array = []
			var labels: Array = []
			for i in opts.size():
				if any_can(eng, opts[i], ctx):
					ok_opts.append(i)
			if ok_opts.is_empty():
				return
			if ok_opts.size() == 1:
				push(eng, [opts[ok_opts[0]]])
				return
			var options: Array = []
			for i in ok_opts:
				options.append({"v": i, "label": describe_list(opts[i])})
			suspend(eng, ctx, {"type": "choice", "handler": "choice", "prompt": "Scegli un effetto", "options": options, "data": {"opts": opts}})
		"if":
			var cond: String = str(e[1]) if e.size() > 1 else ""
			if cond_ok(eng, cond, ctx):
				if e.size() > 2:
					push(eng, [e[2]])
			elif e.size() > 3:
				push(eng, [e[3]])
		"pay_mana":
			var need: String = str(e[1]) if e.size() > 1 else "any"
			var then: Array = e[2] if e.size() > 2 and e[2] is Array else []
			var srcs: Array = MKMana.sources_for(eng, p, need)
			if srcs.is_empty():
				return
			var opts2: Array = _mana_options(eng, p, srcs, need)
			if opts2.size() == 1:
				_do_pay(eng, p, opts2[0].v, need, ctx)
				push(eng, [then])
				return
			suspend(eng, ctx, {"type": "mana", "handler": "pay_mana", "prompt": "Scegli il mana da pagare (%s)" % MKMana.color_it(need),
				"options": opts2, "data": {"need": need, "then": then}})
		"discard":
			var n6 := _n(e, 1, ctx)
			var then2: Array = e[2] if e.size() > 2 and e[2] is Array else []
			var allow_wounds: bool = e.size() > 3 and e[3] == true
			_ask_discard(eng, ctx, n6, then2, allow_wounds)
		"extra_die":
			s.turn.dice_allowed = int(s.turn.dice_allowed) + _n(e, 1, ctx)
			eng.add_log("info", "Puoi usare %d dado in più dalla Fonte" % _n(e, 1, ctx), {"p": p})
		"ready_unit":
			var lv := _n(e, 1, ctx)
			var cands: Array = []
			for u in s.players[p].units:
				if not u.ready and eng.unit_level(u) <= lv:
					cands.append(u.uid)
			_ask_unit(eng, ctx, cands, "ready", "Scegli l'unità da preparare")
		"heal_unit":
			var lv2 := _n(e, 1, ctx)
			var cands2: Array = []
			for u in s.players[p].units:
				if u.wounded and eng.unit_level(u) <= lv2:
					cands2.append(u.uid)
			_ask_unit(eng, ctx, cands2, "heal", "Scegli l'unità da guarire")
		"boost_next":
			var bn := _n(e, 1, ctx)
			var cands: Array = boost_candidates(eng, p, ctx, bn)
			if cands.is_empty():
				return
			var bopts: Array = []
			for iid in cands:
				bopts.append({"v": iid, "label": "%s potenziata (+%d)" % [eng.card_name(iid), bn]})
			suspend(eng, ctx, {"type": "card", "handler": "boost_play", "prompt": "Scegli la carta Azione da giocare potenziata gratis (+%d)" % bn,
				"options": bopts, "data": {"n": bn}})
		"terrain":
			var m: Dictionary = e[1] if e.size() > 1 and e[1] is Dictionary else {}
			s.turn.mods.append({"name": "terrain", "map": m.duplicate(), "src": ctx.get("src", "")})
			eng.add_log("info", "Costi del terreno modificati", {"p": p})
		"mod":
			var nm: String = str(e[1]) if e.size() > 1 else ""
			var prm = e[2] if e.size() > 2 else {}
			MKSpecials.run_mod(eng, ctx, nm, prm)
		"special":
			var nm2: String = str(e[1]) if e.size() > 1 else ""
			var prm2 = e[2] if e.size() > 2 else {}
			MKSpecials.run(eng, ctx, nm2, prm2)
		"noop", "text":
			pass
		_:
			# unknown op: try as special
			if MKSpecials.has(op):
				MKSpecials.run(eng, ctx, op, e[1] if e.size() > 1 else {})
			else:
				eng.add_log("error", "Effetto sconosciuto: " + op)

static func _ask_color(eng, ctx: Dictionary, what: String, prompt: String, with_gold: bool) -> void:
	var options: Array = []
	for c in MKMana.BASIC:
		if what == "crystal" and int(eng.s.players[int(ctx.get("p", 0))].crystals.get(c, 0)) >= 3 and false:
			continue
		options.append({"v": c, "label": MKMana.color_it(c).capitalize()})
	if with_gold:
		options.append({"v": "gold", "label": "Oro"})
	suspend(eng, ctx, {"type": "color", "handler": "color", "prompt": prompt, "options": options, "data": {"what": what}})

static func _mana_options(eng, p: int, srcs: Array, need: String) -> Array:
	var out: Array = []
	var seen := {}
	for x in srcs:
		var src: String = x[0]
		var col: String = x[1]
		var cols: Array = [col]
		if col == "gold" and (need == "basic" or need == "any"):
			cols = MKMana.BASIC.duplicate()
		for c in cols:
			var v: String = src if c == col else src + "=" + c
			var sig: String = src.split(":")[0] + ":" + c + ":" + col
			if src.begins_with("die:") or src.begins_with("token:"):
				sig = src.split(":")[0] + ":" + col + ":" + c
			if seen.has(sig):
				continue
			seen[sig] = true
			out.append({"v": v, "label": MKMana.label(eng, p, v)})
	return out

static func _do_pay(eng, p: int, src: String, need: String, ctx: Dictionary) -> void:
	var paid: Array = MKMana.pay(eng, p, [src], [need])
	if not paid.is_empty():
		ctx["paid"] = paid[0]
		eng.add_log("mana", "Paga mana %s" % MKMana.color_it(paid[0]), {"p": p, "color": paid[0]})

static func _ask_discard(eng, ctx: Dictionary, n: int, then: Array, allow_wounds: bool) -> void:
	var p: int = int(ctx.get("p", 0))
	var hand: Array = eng.s.players[p].hand
	var options: Array = []
	var seen := {}
	for iid in hand:
		var c: Dictionary = eng.card(iid)
		if c.get("type", "") == "wound" and not allow_wounds:
			continue
		if seen.has(c.get("id", "")):
			continue
		seen[c.get("id", "")] = true
		options.append({"v": iid, "label": "Scarta " + eng.card_name(iid)})
	if options.size() < 1:
		return
	suspend(eng, ctx, {"type": "card", "handler": "discard", "prompt": "Scegli una carta da scartare", "options": options,
		"data": {"n": n, "then": then, "allow_wounds": allow_wounds}})

static func _ask_unit(eng, ctx: Dictionary, cands: Array, what: String, prompt: String) -> void:
	if cands.is_empty():
		return
	if cands.size() == 1:
		_unit_do(eng, int(ctx.get("p", 0)), cands[0], what)
		return
	var options: Array = []
	for uid in cands:
		options.append({"v": uid, "label": eng.unit_name_by_uid(int(ctx.get("p", 0)), uid)})
	suspend(eng, ctx, {"type": "unit", "handler": "unit_" + what, "prompt": prompt, "options": options, "data": {}})

static func _unit_do(eng, p: int, uid, what: String) -> void:
	var u = eng.find_unit(p, uid)
	if u == null:
		return
	if what == "ready":
		u.ready = true
		eng.add_log("unit", "%s è pronta" % eng.unit_name(u), {"p": p, "uid": uid})
	elif what == "heal":
		u.wounded = false
		eng.add_log("heal", "%s è guarita" % eng.unit_name(u), {"p": p, "uid": uid})

## Resolve a pending decision created by this module. Returns true if handled.
static func resolve(eng, pend: Dictionary, v) -> bool:
	var ctx: Dictionary = pend.get("ctx", {})
	var queue: Array = pend.get("queue", [])
	var p: int = int(pend.get("player", 0))
	var data: Dictionary = pend.get("data", {})
	match str(pend.get("handler", "")):
		"choice":
			var opts: Array = data.get("opts", [])
			var i := int(v)
			if i >= 0 and i < opts.size():
				queue.push_front(opts[i])
		"color":
			if data.get("what", "") == "crystal":
				eng.gain_crystal(p, str(v))
			else:
				eng.gain_token(p, str(v))
		"pay_mana":
			_do_pay(eng, p, str(v), str(data.get("need", "any")), ctx)
			queue.push_front(data.get("then", []))
		"discard":
			var iid := str(v)
			eng.discard_from_hand(p, iid)
			var left := int(data.get("n", 1)) - 1
			if left > 0:
				queue.push_front(["discard", left, data.get("then", []), data.get("allow_wounds", false)])
			else:
				queue.push_front(data.get("then", []))
		"boost_play":
			var iid2 := str(v)
			var pl: Dictionary = eng.s.players[p]
			pl.hand.erase(iid2)
			pl.play.append(iid2)
			eng.s.turn.played.append(iid2)
			var c2: Dictionary = eng.card(iid2)
			eng.add_log("play", "%s gioca %s potenziata (gratis, +%d)" % [eng.pname(p), eng.card_name(iid2), int(data.n)], {"p": p, "card": iid2, "mode": "powered"})
			var ctx2: Dictionary = eng._play_ctx(p, iid2, "powered")
			ctx2.boost = int(data.n)
			run(eng, c2.get("powered", []).duplicate(true), ctx2)
			if eng.s.pending != null:
				# the inner card suspended: append our remaining queue to it
				eng.s.pending.queue.append_array(queue)
				return true
		"unit_ready":
			_unit_do(eng, p, v, "ready")
		"unit_heal":
			_unit_do(eng, p, v, "heal")
		_:
			return false
	run(eng, queue, ctx)
	return true

## Action cards in hand that can be played powered for free with a boost.
static func boost_candidates(eng, p: int, ctx: Dictionary, n: int) -> Array:
	var out: Array = []
	var seen := {}
	for iid in eng.s.players[p].hand:
		if iid == ctx.get("src", ""):
			continue
		var c: Dictionary = eng.card(iid)
		if not str(c.get("type", "")) in ["basic", "aa"]:
			continue
		if seen.has(c.id):
			continue
		var ctx2: Dictionary = {"p": p, "src": iid, "kind": "card", "mode": "powered", "boost": n, "_nested": true}
		if c.get("combat_only", false) and eng.s.combat == null:
			continue
		if any_can(eng, c.get("powered", []), ctx2):
			seen[c.id] = true
			out.append(iid)
	return out

# ---------------------------------------------------------------- applicability
static func any_can(eng, list, ctx: Dictionary) -> bool:
	if not (list is Array) or list.is_empty():
		return false
	if list[0] is String:
		return can(eng, list, ctx)
	for e in list:
		if can(eng, e, ctx):
			return true
	return false

static func can(eng, e, ctx: Dictionary) -> bool:
	if not (e is Array) or e.is_empty():
		return false
	if not (e[0] is String):
		return any_can(eng, e, ctx)
	var s: Dictionary = eng.s
	var p: int = int(ctx.get("p", s.turn.get("player", 0)))
	var cb = s.get("combat")
	var in_combat: bool = cb != null
	var op: String = e[0]
	match op:
		"move":
			return not in_combat and eng.can_still_move(p)
		"influence":
			return not in_combat
		"heal":
			if in_combat:
				return false
			for iid in s.players[p].hand:
				if eng.is_wound(iid):
					return true
			for u in s.players[p].units:
				if u.wounded:
					return true
			return false
		"draw":
			return not s.players[p].deck.is_empty()
		"attack":
			if not in_combat:
				return false
			var kd: String = e[3] if e.size() > 3 and e[3] != null else "melee"
			if cb.phase == "ranged":
				return kd == "ranged" or kd == "siege"
			return cb.phase == "attack"
		"block":
			return in_combat and cb.phase == "block"
		"fame", "mana", "crystal":
			return true
		"rep":
			# a reputation loss is a cost, not a reason to play a card
			return e.size() > 1 and int(e[1]) > 0
		"noop", "text":
			return false
		"boost_next":
			if ctx.get("_nested", false):
				return true
			return not boost_candidates(eng, p, ctx, int(e[1]) if e.size() > 1 else 2).is_empty()
		"extra_die":
			return true
		"terrain":
			return not in_combat and eng.can_still_move(p)
		"choice":
			for o in (e[1] if e.size() > 1 else []):
				if any_can(eng, o, ctx):
					return true
			return false
		"if":
			var cond: String = str(e[1]) if e.size() > 1 else ""
			if cond_ok(eng, cond, ctx):
				return e.size() > 2 and any_can(eng, e[2], ctx)
			return e.size() > 3 and any_can(eng, e[3], ctx)
		"pay_mana":
			var need: String = str(e[1]) if e.size() > 1 else "any"
			if MKMana.sources_for(eng, p, need, ctx.get("_mana_used", [])).is_empty():
				return false
			return e.size() < 3 or (e[2] is Array and (e[2].is_empty() or any_can(eng, e[2], ctx)))
		"discard":
			var n := int(e[1]) if e.size() > 1 else 1
			var allow_w: bool = e.size() > 3 and e[3] == true
			var cnt := 0
			for iid in s.players[p].hand:
				if iid == ctx.get("src", "") :
					continue
				if allow_w or eng.card(iid).get("type", "") != "wound":
					cnt += 1
			if cnt < n:
				return false
			return e.size() < 3 or (e[2] is Array and (e[2].is_empty() or any_can(eng, e[2], ctx)))
		"ready_unit":
			for u in s.players[p].units:
				if not u.ready and eng.unit_level(u) <= int(e[1]):
					return true
			return false
		"heal_unit":
			if in_combat:
				return false
			for u in s.players[p].units:
				if u.wounded and eng.unit_level(u) <= int(e[1]):
					return true
			return false
		"mod":
			return MKSpecials.can_mod(eng, ctx, str(e[1]) if e.size() > 1 else "", e[2] if e.size() > 2 else {})
		"special":
			return MKSpecials.can(eng, ctx, str(e[1]) if e.size() > 1 else "", e[2] if e.size() > 2 else {})
	return MKSpecials.has(op)

static func cond_ok(eng, cond: String, ctx: Dictionary) -> bool:
	var s: Dictionary = eng.s
	var cb = s.get("combat")
	match cond:
		"day":
			return s.day
		"night":
			return not s.day
		"combat":
			return cb != null
		"not_combat":
			return cb == null
		"phase:ranged":
			return cb != null and cb.phase == "ranged"
		"phase:block":
			return cb != null and cb.phase == "block"
		"phase:attack":
			return cb != null and cb.phase == "attack"
		"phase:damage":
			return cb != null and cb.phase == "damage"
		"underground":
			return cb != null and cb.get("night_rules", false)
		"powered":
			return ctx.get("mode", "") == "powered"
	if cond.begins_with("site:"):
		var h: Dictionary = eng.hex(eng.s.players[int(ctx.get("p", 0))].pos)
		return h.get("site", "") == cond.substr(5)
	if cond.begins_with("terrain:"):
		var h2: Dictionary = eng.hex(eng.s.players[int(ctx.get("p", 0))].pos)
		return h2.get("t", "") == cond.substr(8)
	return MKSpecials.cond(eng, ctx, cond)

# ---------------------------------------------------------------- descriptions
static func describe_list(list) -> String:
	if not (list is Array) or list.is_empty():
		return "niente"
	if list[0] is String:
		return describe(list)
	var parts: Array = []
	for e in list:
		parts.append(describe(e))
	return ", ".join(parts)

static func _num(v) -> String:
	if v is float or v is int:
		return str(int(v))
	return str(v)

static func describe(e) -> String:
	if not (e is Array) or e.is_empty():
		return ""
	if not (e[0] is String):
		return describe_list(e)
	var op: String = e[0]
	match op:
		"move":
			return "Movimento %s" % _num(e[1])
		"influence":
			return "Influenza %s" % _num(e[1])
		"heal":
			return "Guarigione %s" % _num(e[1])
		"attack":
			var kd: String = e[3] if e.size() > 3 and e[3] != null else "melee"
			var el: String = e[2] if e.size() > 2 and e[2] != null else "phys"
			return "%s %s%s" % [KIND_IT.get(kd, "Attacco"), _num(e[1]), ELEM_IT.get(el, "")]
		"block":
			var el2: String = e[2] if e.size() > 2 and e[2] != null else "phys"
			return "Blocco %s%s" % [_num(e[1]), ELEM_IT.get(el2, "")]
		"fame":
			return "Fama %+d" % int(e[1])
		"rep":
			return "Reputazione %+d" % int(e[1])
		"draw":
			return "Pesca %s cart%s" % [_num(e[1]), "a" if int(e[1]) == 1 else "e"]
		"mana":
			return "Gettone mana %s" % MKMana.color_it(_num(e[1]))
		"crystal":
			var c: String = _num(e[1])
			return "Cristallo %s" % ("del colore pagato" if c == "$paid" else MKMana.color_it(c))
		"choice":
			var parts: Array = []
			for o in e[1]:
				parts.append(describe_list(o))
			return " oppure ".join(parts)
		"if":
			return describe_list(e[2]) if e.size() > 2 else ""
		"pay_mana":
			return "Paga mana %s: %s" % [MKMana.color_it(_num(e[1])), describe_list(e[2]) if e.size() > 2 else ""]
		"discard":
			return "Scarta %s carta: %s" % [_num(e[1]), describe_list(e[2]) if e.size() > 2 else ""]
		"extra_die":
			return "+%s dado dalla Fonte" % _num(e[1])
		"ready_unit":
			return "Prepara un'unità (livello ≤ %s)" % _num(e[1])
		"heal_unit":
			return "Guarisci un'unità (livello ≤ %s)" % _num(e[1])
		"boost_next":
			return "La prossima carta potenziata +%s" % _num(e[1])
		"terrain":
			var bits: Array = []
			if e.size() > 1 and e[1] is Dictionary:
				for k in e[1]:
					if k == "min":
						continue
					bits.append("%s %s" % [TERR_IT.get(k, k), str(e[1][k])])
			return "Costi terreno: " + ", ".join(bits)
		"mod", "special":
			var nm: String = _num(e[1]) if e.size() > 1 else ""
			var d: Dictionary = MKDB.specials.get(nm, {})
			var t: String = str(d.get("label_it", d.get("short_it", "")))
			if t == "":
				t = str(d.get("desc", nm))
				if t.length() > 60:
					t = t.substr(0, 57) + "…"
			return t
	return op
