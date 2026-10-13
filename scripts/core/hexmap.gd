class_name MKHex
extends RefCounted
## Axial hex coordinates (pointy top). Keys are "q,r" strings.

# W, SW, SE, E, NE, NW
const DIRS := [Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1)]
# tile data direction keys -> offset from tile centre
const TILE_KEYS := {"center": Vector2i(0, 0), "0": Vector2i(-1, 0), "60": Vector2i(-1, 1), "120": Vector2i(0, 1),
	"180": Vector2i(1, 0), "240": Vector2i(1, -1), "300": Vector2i(0, -1)}
# centres of adjacent tiles: N NE E S SW W
const MACRO := [Vector2i(1, -3), Vector2i(3, -2), Vector2i(2, 1), Vector2i(-1, 3), Vector2i(-3, 2), Vector2i(-2, -1)]

static func key(v: Vector2i) -> String:
	return "%d,%d" % [v.x, v.y]

static func kq(q: int, r: int) -> String:
	return "%d,%d" % [q, r]

static func parse(k: String) -> Vector2i:
	var i := k.find(",")
	if i < 0:
		return Vector2i.ZERO
	return Vector2i(int(k.substr(0, i)), int(k.substr(i + 1)))

static func neighbors(k: String) -> Array:
	var v := parse(k)
	var out := []
	for d in DIRS:
		out.append(key(v + d))
	return out

static func adjacent(a: String, b: String) -> bool:
	var d := parse(a) - parse(b)
	return d in DIRS

static func distance(a: String, b: String) -> int:
	var d := parse(a) - parse(b)
	return (absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2

static func tile_hexes(slot: String) -> Array:
	var c := parse(slot)
	var out := []
	for kk in TILE_KEYS:
		out.append(key(c + TILE_KEYS[kk]))
	return out

static func world(k: String) -> Vector3:
	var v := parse(k)
	return Vector3(sqrt(3.0) * (v.x + v.y / 2.0), 0.0, 1.5 * v.y)

static func macro_neighbors(slot: String) -> Array:
	var c := parse(slot)
	var out := []
	for m in MACRO:
		out.append(key(c + m))
	return out

## Is a tile slot part of the map shape?
static func in_shape(slot: String, shape: String, max_n: int = 14) -> bool:
	var c := parse(slot)
	if c == Vector2i.ZERO:
		return false
	# solve c = a*N + b*NE  (N=(1,-3) NE=(3,-2)) -> det = 1*-2 - 3*-3 = 7
	if _comb_ok(c, MACRO[0], MACRO[1], max_n):
		return true
	if shape == "open" and _comb_ok(c, MACRO[1], MACRO[2], max_n):
		return true
	return false

static func _comb_ok(c: Vector2i, u: Vector2i, w: Vector2i, max_n: int) -> bool:
	var det := u.x * w.y - u.y * w.x
	if det == 0:
		return false
	var an := c.x * w.y - c.y * w.x
	var bn := u.x * c.y - u.y * c.x
	if an % det != 0 or bn % det != 0:
		return false
	var a := an / det
	var b := bn / det
	return a >= 0 and b >= 0 and a + b >= 1 and a + b <= max_n

## Which tile slot (centre) contains hex k, given placed tiles {slot:..}
static func slot_of(k: String, placed: Dictionary) -> String:
	var v := parse(k)
	for kk in TILE_KEYS:
		var c := key(v - TILE_KEYS[kk])
		if placed.has(c):
			return c
	return ""
