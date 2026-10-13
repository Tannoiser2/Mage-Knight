class_name MKHexMesh
extends RefCounted
## Geometria esagonale per il tavolo 3D (SPEC §2): esagoni a punta in alto, raggio 1 unità del mondo,
## x = √3·(q + r/2), z = 1.5·r. Mesh della tessera a «fiore» di 7 esagoni con spessore, smusso e
## UV ricavate dalla geometria della texture; anelli/riempimenti esagonali per evidenziazioni e contorni.

const SQ3 := 1.7320508075688772
## Vicini nell'ordine fisso della SPEC: W SW SE E NE NW.
const DIRS := [Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1)]
## Centri delle tessere adiacenti (vettori «macro»): N NE E S SW W.
const MACRO := [Vector2i(1, -3), Vector2i(3, -2), Vector2i(2, 1), Vector2i(-1, 3), Vector2i(-3, 2), Vector2i(-2, -1)]
## Geometria predefinita della texture di una tessera (2048×1970): centro e raggio in pixel.
const TEX_W := 2048.0
const TEX_H := 1970.0
const TEX_CX := 1024.0
const TEX_CY := 985.0
const TEX_R := 394.0

static var _cache := {}


static func key(q: int, r: int) -> String:
	return "%d,%d" % [q, r]


static func parse(k: String) -> Vector2i:
	var p := k.split(",")
	if p.size() < 2:
		return Vector2i.ZERO
	return Vector2i(int(p[0]), int(p[1]))


static func to_world(q: float, r: float) -> Vector2:
	return Vector2(SQ3 * (q + r / 2.0), 1.5 * r)


static func key_world(k: String) -> Vector3:
	var a := parse(k)
	var w := to_world(a.x, a.y)
	return Vector3(w.x, 0, w.y)


## Esagono (assiale) che contiene il punto del mondo (x, z).
static func from_world(x: float, z: float) -> Vector2i:
	var qf := (SQ3 / 3.0 * x - z / 3.0)
	var rf := (2.0 / 3.0 * z)
	return cube_round(qf, rf)


static func cube_round(qf: float, rf: float) -> Vector2i:
	var sf := -qf - rf
	var q := roundf(qf)
	var r := roundf(rf)
	var s := roundf(sf)
	var dq := absf(q - qf)
	var dr := absf(r - rf)
	var ds := absf(s - sf)
	if dq > dr and dq > ds:
		q = -r - s
	elif dr > ds:
		r = -q - s
	return Vector2i(int(q), int(r))


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return int((absi(d.x) + absi(d.y) + absi(d.x + d.y)) / 2)


## I 7 esagoni di una tessera centrata in c (centro + 6 vicini, ordine della SPEC).
static func flower(c: Vector2i) -> Array:
	var out := [c]
	for d in DIRS:
		out.append(c + d)
	return out


## Angoli dell'esagono (punta in alto) attorno all'origine: 0 = nord, poi in senso orario visto dall'alto.
static func corner(i: int, radius := 1.0) -> Vector2:
	var a := deg_to_rad(-90.0 + 60.0 * i)
	return Vector2(cos(a), sin(a)) * radius


# ------------------------------------------------------------------ forme della mappa

## Coefficienti (a, b) di un posto rispetto a due vettori macro, o null se non interi.
static func _solve(slot: Vector2i, u: Vector2i, v: Vector2i):
	var det := u.x * v.y - v.x * u.y
	if det == 0:
		return null
	var an := slot.x * v.y - v.x * slot.y
	var bn := u.x * slot.y - slot.x * u.y
	if an % det != 0 or bn % det != 0:
		return null
	return Vector2i(an / det, bn / det)


## Il posto (centro di tessera) appartiene alla forma della mappa? (SPEC §2)
static func in_shape(slot: Vector2i, shape: String) -> bool:
	if slot == Vector2i.ZERO:
		return true
	var ab = _solve(slot, MACRO[0], MACRO[1])   # a·N + b·NE
	if ab != null and ab.x >= 0 and ab.y >= 0:
		return true
	if shape == "open":
		var ab2 = _solve(slot, MACRO[1], MACRO[2])   # a·NE + b·E
		if ab2 != null and ab2.x >= 0 and ab2.y >= 0:
			return true
	return false


# ------------------------------------------------------------------ mesh della tessera

## Fiore di 7 esagoni: superficie 0 = faccia superiore + smusso (texture della tessera, colori per
## vertice: smusso più scuro), superficie 1 = fianco (cartone scuro). Origine al centro, y=0 sotto.
## uvgeo = {w, h, cx, cy, r} in pixel della texture.
static func tile_mesh(thick := 0.09, bevel := 0.035, uvgeo := {}) -> ArrayMesh:
	var ck := "tile|%s|%s|%s" % [thick, bevel, str(uvgeo)]
	if _cache.has(ck):
		return _cache[ck]
	var W: float = float(uvgeo.get("w", TEX_W))
	var H: float = float(uvgeo.get("h", TEX_H))
	var CX: float = float(uvgeo.get("cx", TEX_CX))
	var CY: float = float(uvgeo.get("cy", TEX_CY))
	var R: float = float(uvgeo.get("r", TEX_R))
	var uv_of := func(p: Vector2) -> Vector2:
		return Vector2((CX + p.x * R) / W, (CY + p.y * R) / H)
	var centers := []
	for h in flower(Vector2i.ZERO):
		centers.append(to_world(h.x, h.y))
	# spigoli di bordo: quelli il cui esagono vicino non è nel fiore
	var is_center := func(p: Vector2) -> bool:
		for c in centers:
			if c.distance_to(p) < 0.01:
				return true
		return false
	var boundary := []        # [a, b] in senso orario visto dall'alto
	for c in centers:
		for i in range(6):
			var a: Vector2 = c + corner(i)
			var b: Vector2 = c + corner((i + 1) % 6)
			var mid := (a + b) / 2.0
			var other: Vector2 = c + (mid - c) * 2.0
			if not is_center.call(other):
				boundary.append([a, b])
	# rientro (smusso) dei vertici di bordo lungo la bisettrice delle normali dei due spigoli
	var vkey := func(p: Vector2) -> String:
		return "%d|%d" % [roundi(p.x * 1000), roundi(p.y * 1000)]
	var vnorm := {}
	for e in boundary:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var d := (b - a).normalized()
		var n := Vector2(-d.y, d.x)     # normale esterna (spigoli in senso orario con z verso sud)
		if n.dot((a + b) / 2.0) < 0:
			n = -n
		for p in [a, b]:
			var k: String = vkey.call(p)
			vnorm[k] = (vnorm.get(k, Vector2.ZERO) as Vector2) + n
	var inset := func(p: Vector2) -> Vector2:
		var k: String = vkey.call(p)
		if not vnorm.has(k):
			return p
		var n: Vector2 = vnorm[k]
		var nn := n.normalized()
		# miter: lo spostamento lungo la bisettrice vale bevel / cos(mezzo angolo)
		var cosh := clampf(n.length() / 2.0, 0.35, 1.0)
		return p - nn * (bevel / cosh)
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var up := Vector3.UP
	for c in centers:
		var cc: Vector2 = c
		for i in range(6):
			var a: Vector2 = inset.call(cc + corner(i))
			var b: Vector2 = inset.call(cc + corner((i + 1) % 6))
			for p in [cc, a, b]:
				top.set_color(Color.WHITE)
				top.set_normal(up)
				top.set_uv(uv_of.call(p))
				top.add_vertex(Vector3(p.x, thick, p.y))
	# smusso: dalla faccia (rientrata, y=thick) allo spigolo esterno (y=thick-bevel)
	var bcol := Color(0.62, 0.58, 0.52)
	for e in boundary:
		var a0: Vector2 = e[0]
		var b0: Vector2 = e[1]
		var ai: Vector2 = inset.call(a0)
		var bi: Vector2 = inset.call(b0)
		var d := (b0 - a0).normalized()
		var n2 := Vector2(-d.y, d.x)
		if n2.dot((a0 + b0) / 2.0) < 0:
			n2 = -n2
		var nrm := Vector3(n2.x, 1.0, n2.y).normalized()
		var A := Vector3(ai.x, thick, ai.y)
		var B := Vector3(bi.x, thick, bi.y)
		var A2 := Vector3(a0.x, thick - bevel, a0.y)
		var B2 := Vector3(b0.x, thick - bevel, b0.y)
		var tri := [[A, ai], [B, bi], [B2, b0], [A, ai], [B2, b0], [A2, a0]]
		for t in tri:
			top.set_color(bcol)
			top.set_normal(nrm)
			top.set_uv(uv_of.call(t[1]))
			top.add_vertex(t[0])
	var side := SurfaceTool.new()
	side.begin(Mesh.PRIMITIVE_TRIANGLES)
	for e in boundary:
		var a1: Vector2 = e[0]
		var b1: Vector2 = e[1]
		var d1 := (b1 - a1).normalized()
		var n3 := Vector2(-d1.y, d1.x)
		if n3.dot((a1 + b1) / 2.0) < 0:
			n3 = -n3
		var nrm2 := Vector3(n3.x, 0, n3.y)
		var At := Vector3(a1.x, thick - bevel, a1.y)
		var Bt := Vector3(b1.x, thick - bevel, b1.y)
		var Ab := Vector3(a1.x, 0, a1.y)
		var Bb := Vector3(b1.x, 0, b1.y)
		for v in [At, Bt, Bb, At, Bb, Ab]:
			side.set_normal(nrm2)
			side.set_uv(Vector2(v.x, v.y))
			side.add_vertex(v)
	var mesh := top.commit()
	side.commit(mesh)
	_fix_winding(mesh)
	_cache[ck] = mesh
	return mesh


## Le facce devono essere in senso orario viste dall'esterno (convenzione di Godot): invece di
## ragionare caso per caso, si controlla ogni triangolo con la sua normale e lo si gira se serve.
static func _fix_winding(mesh: ArrayMesh) -> void:
	var surfaces := []
	for s in range(mesh.get_surface_count()):
		var arr := mesh.surface_get_arrays(s)
		var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX] if arr[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		if idx.is_empty():
			idx.resize(v.size())
			for i in range(v.size()):
				idx[i] = i
		for t in range(0, idx.size(), 3):
			var p0 := v[idx[t]]
			var p1 := v[idx[t + 1]]
			var p2 := v[idx[t + 2]]
			var fn := (p1 - p0).cross(p2 - p0)
			# Godot: fronte = senso orario → la normale geometrica (p1-p0)x(p2-p0) punta verso l'interno
			if fn.dot(n[idx[t]]) > 0:
				var tmp := idx[t + 1]
				idx[t + 1] = idx[t + 2]
				idx[t + 2] = tmp
		arr[Mesh.ARRAY_INDEX] = idx
		surfaces.append(arr)
	mesh.clear_surfaces()
	for arr in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)


## Anello esagonale piatto (contorno), raggio esterno r, spessore w; y=0.
static func ring_mesh(r := 0.97, w := 0.06) -> ArrayMesh:
	var ck := "ring|%s|%s" % [r, w]
	if _cache.has(ck):
		return _cache[ck]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(6):
		var a := corner(i, r)
		var b := corner((i + 1) % 6, r)
		var ai := corner(i, r - w)
		var bi := corner((i + 1) % 6, r - w)
		for p in [a, b, bi, a, bi, ai]:
			st.set_normal(Vector3.UP)
			st.set_uv(Vector2(p.x, p.y))
			st.add_vertex(Vector3(p.x, 0, p.y))
	var m := st.commit()
	_fix_winding(m)
	_cache[ck] = m
	return m


## Esagono pieno (riempimento delle evidenziazioni), raggio r; UV radiale (u = distanza dal centro).
static func fill_mesh(r := 0.96) -> ArrayMesh:
	var ck := "fill|%s" % r
	if _cache.has(ck):
		return _cache[ck]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(6):
		var a := corner(i, r)
		var b := corner((i + 1) % 6, r)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(0, 0))
		st.add_vertex(Vector3.ZERO)
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1, 0))
		st.add_vertex(Vector3(a.x, 0, a.y))
		st.set_normal(Vector3.UP)
		st.set_uv(Vector2(1, 0))
		st.add_vertex(Vector3(b.x, 0, b.y))
	var m := st.commit()
	_fix_winding(m)
	_cache[ck] = m
	return m


## Contorno di un fiore di 7 esagoni (solo gli spigoli esterni), per i posti non esplorati.
static func flower_outline_mesh(w := 0.05) -> ArrayMesh:
	var ck := "flout|%s" % w
	if _cache.has(ck):
		return _cache[ck]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var centers := []
	for h in flower(Vector2i.ZERO):
		centers.append(to_world(h.x, h.y))
	for c in centers:
		for i in range(6):
			var a: Vector2 = c + corner(i)
			var b: Vector2 = c + corner((i + 1) % 6)
			var mid := (a + b) / 2.0
			var other: Vector2 = c + (mid - c) * 2.0
			var inner := false
			for c2 in centers:
				if c2.distance_to(other) < 0.01:
					inner = true
			# spigoli interni più sottili
			var ww := w if not inner else w * 0.45
			var ai: Vector2 = c + corner(i, 1.0 - ww)
			var bi: Vector2 = c + corner((i + 1) % 6, 1.0 - ww)
			for p in [a, b, bi, a, bi, ai]:
				st.set_normal(Vector3.UP)
				st.set_color(Color(1, 1, 1, 1.0 if not inner else 0.55))
				st.add_vertex(Vector3(p.x, 0, p.y))
	var m := st.commit()
	_fix_winding(m)
	_cache[ck] = m
	return m


## Disco (segnalino nemico): faccia superiore con UV sul cerchio inscritto della texture quadrata,
## superficie 0 = sopra, 1 = bordo, 2 = sotto (per il dorso quando è coperto si scambia la texture).
static func disc_mesh(r := 0.4, h := 0.05, seg := 40, uv_scale := 0.985) -> ArrayMesh:
	var ck := "disc|%s|%s|%s|%s" % [r, h, seg, uv_scale]
	if _cache.has(ck):
		return _cache[ck]
	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rim := SurfaceTool.new()
	rim.begin(Mesh.PRIMITIVE_TRIANGLES)
	var bot := SurfaceTool.new()
	bot.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(seg):
		var a0 := TAU * i / seg
		var a1 := TAU * (i + 1) / seg
		var p0 := Vector2(cos(a0), sin(a0))
		var p1 := Vector2(cos(a1), sin(a1))
		for p in [Vector2.ZERO, p0, p1]:
			top.set_normal(Vector3.UP)
			top.set_uv(Vector2(0.5, 0.5) + p * 0.5 * uv_scale)
			top.add_vertex(Vector3(p.x * r, h, p.y * r))
		for p in [Vector2.ZERO, p1, p0]:
			bot.set_normal(Vector3.DOWN)
			bot.set_uv(Vector2(0.5, 0.5) + Vector2(-p.x, p.y) * 0.5 * uv_scale)
			bot.add_vertex(Vector3(p.x * r, 0, p.y * r))
		var n0 := Vector3(p0.x, 0, p0.y)
		var n1 := Vector3(p1.x, 0, p1.y)
		var v := [[Vector3(p0.x * r, h, p0.y * r), n0], [Vector3(p1.x * r, h, p1.y * r), n1], [Vector3(p1.x * r, 0, p1.y * r), n1],
			[Vector3(p0.x * r, h, p0.y * r), n0], [Vector3(p1.x * r, 0, p1.y * r), n1], [Vector3(p0.x * r, 0, p0.y * r), n0]]
		for t in v:
			rim.set_normal(t[1])
			rim.set_uv(Vector2(0, 0))
			rim.add_vertex(t[0])
	var m := top.commit()
	rim.commit(m)
	bot.commit(m)
	_fix_winding(m)
	_cache[ck] = m
	return m
