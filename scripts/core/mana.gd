class_name MKMana
extends RefCounted
## Mana sources and payments. Sources are strings:
##   "token:<i>"   mana token i of p.tokens
##   "die:<i>"     source die i (counts against the dice-per-turn limit)
##   "crystal:<c>" a crystal of colour c
##   "stolen"      the die kept with the Mana Steal tactic
## A source may carry an explicit colour for gold: "die:3=red".

const BASIC := ["red", "blue", "green", "white"]

static func night_rules(eng) -> bool:
	var s: Dictionary = eng.s
	if not s.day:
		return true
	var c = s.get("combat")
	return c != null and c.get("night_rules", false)

## Can mana of colour `have` pay for requirement `need`?
static func fits(have: String, need: String, gold_ok: bool, black_ok: bool) -> bool:
	if have == "gold":
		return gold_ok and (need in BASIC or need == "basic" or need == "any" or need == "gold")
	if have == "black":
		return black_ok and need == "black"
	if need == "basic" or need == "any":
		return have in BASIC
	return have == need

static func gold_ok(eng, p: int) -> bool:
	return not night_rules(eng) or eng.flag(p, "gold_ok")

static func black_ok(eng, p: int) -> bool:
	return night_rules(eng) or eng.flag(p, "black_ok")

static func dice_left(eng, p: int) -> int:
	var t: Dictionary = eng.s.turn
	if t.get("player", -1) != p:
		return 0
	return int(t.get("dice_allowed", 1)) - int(t.get("dice_taken", 0))

## List of (source, colour) that can pay `need` for player p.
static func sources_for(eng, p: int, need: String, used: Array = [], dice_used: int = 0) -> Array:
	var s: Dictionary = eng.s
	var pl: Dictionary = s.players[p]
	var g_ok := gold_ok(eng, p)
	var b_ok := black_ok(eng, p)
	var dice_any: bool = eng.flag(p, "source_black_gold_any")
	var black_die_any: bool = eng.flag(p, "extra_black_die_any")
	var out: Array = []
	var toks: Array = pl.tokens
	for i in toks.size():
		var src := "token:%d" % i
		if src in used:
			continue
		if fits(toks[i], need, g_ok, b_ok):
			out.append([src, toks[i]])
	if pl.get("stolen_die", "") != "" and not ("stolen" in used) and fits(pl.stolen_die, need, g_ok, b_ok):
		out.append(["stolen", pl.stolen_die])
	if dice_left(eng, p) - dice_used > 0 and not eng.flag(p, "no_dice"):
		var src_list: Array = s.source
		for i in src_list.size():
			var d: Dictionary = src_list[i]
			var src2 := "die:%d" % i
			if int(d.taken_by) != -1 or src2 in used:
				continue
			if fits(d.color, need, g_ok, b_ok):
				out.append([src2, d.color])
			elif (dice_any and d.color in ["gold", "black"] or black_die_any and d.color == "black") and (need in BASIC or need == "basic" or need == "any"):
				out.append([src2, "gold"])
	for c in BASIC:
		var have_n := int(pl.crystals.get(c, 0))
		for u in used:
			if u == "crystal:" + c:
				have_n -= 1
		if have_n > 0 and fits(c, need, g_ok, b_ok):
			out.append(["crystal:" + c, c])
	# exact colour first, gold later (stable)
	var exact: Array = []
	var other: Array = []
	for x in out:
		if x[1] == need or need in ["basic", "any"]:
			exact.append(x)
		else:
			other.append(x)
	return exact + other

static func _is_die(src: String) -> bool:
	return src.begins_with("die:")

## Find sources for a list of needs. Returns Array of sources or null.
static func plan(eng, p: int, needs: Array, given = null) -> Variant:
	if given != null and given is Array and not given.is_empty():
		return given if validate(eng, p, needs, given) else null
	var res: Array = []
	if _bt(eng, p, needs, 0, [], 0, res):
		return res
	return null

static func _bt(eng, p: int, needs: Array, i: int, used: Array, dice_used: int, res: Array) -> bool:
	if i >= needs.size():
		res.clear()
		res.append_array(used)
		return true
	for x in sources_for(eng, p, needs[i], used, dice_used):
		var src: String = x[0]
		var u2 := used.duplicate()
		u2.append(src)
		if _bt(eng, p, needs, i + 1, u2, dice_used + (1 if _is_die(src) else 0), res):
			return true
	return false

static func validate(eng, p: int, needs: Array, given: Array) -> bool:
	if given.size() != needs.size():
		return false
	var used: Array = []
	var dice_used := 0
	for i in needs.size():
		var src: String = str(given[i]).split("=")[0]
		var ok := false
		for x in sources_for(eng, p, needs[i], used, dice_used):
			if x[0] == src:
				ok = true
				break
		if not ok:
			return false
		used.append(src)
		if _is_die(src):
			dice_used += 1
	return true

## Colour a source provides (before gold substitution).
static func source_color(eng, p: int, src: String) -> String:
	var pl: Dictionary = eng.s.players[p]
	var base := src.split("=")[0]
	if base.begins_with("token:"):
		var i := int(base.substr(6))
		return pl.tokens[i] if i < pl.tokens.size() else ""
	if base.begins_with("die:"):
		var j := int(base.substr(4))
		return eng.s.source[j].color if j < eng.s.source.size() else ""
	if base.begins_with("crystal:"):
		return base.substr(8)
	if base == "stolen":
		return pl.get("stolen_die", "")
	return ""

## Pay with a list of sources (already validated). Token removal is done
## in descending index order so indices stay valid. Returns paid colours.
static func pay(eng, p: int, sources: Array, needs: Array) -> Array:
	var s: Dictionary = eng.s
	var pl: Dictionary = s.players[p]
	var paid: Array = []
	var tok_rm: Array = []
	for i in sources.size():
		var src: String = str(sources[i])
		var parts := src.split("=")
		var base := parts[0]
		var col := source_color(eng, p, base)
		var need: String = needs[i] if i < needs.size() else col
		var eff := col
		if (col == "gold" or col == "black") and need in BASIC:
			eff = need
		elif (col == "gold" or col == "black") and parts.size() > 1:
			eff = parts[1]
		paid.append(eff)
		if eff in BASIC:
			MKSpecials.on_mana_used(eng, p, eff)
		if base.begins_with("token:"):
			tok_rm.append(int(base.substr(6)))
		elif base.begins_with("die:"):
			var j := int(base.substr(4))
			s.source[j].taken_by = p
			s.turn.dice_taken = int(s.turn.get("dice_taken", 0)) + 1
			s.turn.dice_used_colors.append(col)
		elif base.begins_with("crystal:"):
			var c := base.substr(8)
			pl.crystals[c] = int(pl.crystals[c]) - 1
			if not s.turn.has("crystals_spent"):
				s.turn["crystals_spent"] = []
			s.turn.crystals_spent.append(c)
		elif base == "stolen":
			s.turn["stolen_used"] = pl.stolen_die
			pl.stolen_die = ""
	tok_rm.sort()
	tok_rm.reverse()
	for i in tok_rm:
		pl.tokens.remove_at(i)
	return paid

## Human readable label of a source.
static func label(eng, p: int, src: String) -> String:
	var base := src.split("=")[0]
	var col := source_color(eng, p, base)
	var extra := ""
	if src.find("=") >= 0:
		extra = " come " + color_it(src.split("=")[1])
	if base.begins_with("token:"):
		return "gettone " + color_it(col) + extra
	if base.begins_with("die:"):
		return "dado " + color_it(col) + " della Riserva" + extra
	if base.begins_with("crystal:"):
		return "cristallo " + color_it(col)
	if base == "stolen":
		return "dado rubato " + color_it(col) + extra
	return src

static func color_it(c: String) -> String:
	return {"red": "rosso", "blue": "blu", "green": "verde", "white": "bianco", "gold": "oro", "black": "nero",
		"basic": "base", "any": "qualsiasi"}.get(c, c)
