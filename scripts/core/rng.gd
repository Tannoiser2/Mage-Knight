class_name MKRng
extends RefCounted
## Deterministic PRNG (xorshift32). The state is a plain int stored in the
## game state dictionary (s.rng), so the whole game is reproducible from
## cfg + seed + actions (online lockstep).

const MASK := 0xFFFFFFFF

static func seed_state(seed: int) -> int:
	var x: int = (seed ^ 0x9E3779B9) & MASK
	if x == 0:
		x = 0x6D2B79F5
	# warm up
	for i in 8:
		x = _step(x)
	return x

static func _step(x: int) -> int:
	x ^= (x << 13) & MASK
	x ^= (x >> 17)
	x ^= (x << 5) & MASK
	return x & MASK

## Advances s.rng and returns a 32-bit unsigned value.
static func next(s: Dictionary) -> int:
	var x: int = int(s.get("rng", 1))
	if x == 0:
		x = 0x6D2B79F5
	x = _step(x)
	s["rng"] = x
	return x

## Uniform int in [0, n).
static func rand_int(s: Dictionary, n: int) -> int:
	if n <= 1:
		return 0
	return next(s) % n

## In-place Fisher-Yates shuffle.
static func shuffle(s: Dictionary, arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rand_int(s, i + 1)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t

static func pick(s: Dictionary, arr: Array) -> Variant:
	if arr.is_empty():
		return null
	return arr[rand_int(s, arr.size())]
