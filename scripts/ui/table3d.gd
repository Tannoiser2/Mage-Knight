class_name MKTable3D
extends Node3D
## Il tavolo 3D di Mage Knight: tessere esagonali con le texture del modulo, contorni dei posti
## esplorabili, mare/terreno intorno, figure degli eroi, città 3D, segnalini dei nemici (dischi con
## la faccia stampata, impilati), scudi, evidenziazioni con costi, telecamera libera, giorno/notte.
##
## Uso:
##   var t := MKTable3D.new(); add_child(t)
##   t.refresh(s)                      # s = stato del motore (SPEC §3); si richiama a ogni cambio
##   t.set_highlights({"1,-2": {"kind": "move", "label": "2"}, "3,-9": "explore"})
##   t.hex_clicked.connect(func(k): ...)   # k = esagono "q,r" (o il posto, per un'evidenziazione "explore")
##   t.focus_hex("1,-3")               # centra dolcemente
## L'input arriva da _unhandled_input: i controlli dell'HUD lo consumano prima.

signal hex_clicked(key: String)
signal hex_hovered(key: String)          # "" quando il puntatore lascia la mappa

const TH := 0.09                         # spessore delle tessere (faccia superiore a y = TH)
const TOKEN_R := 0.40
const TOKEN_H := 0.05
const FIG_H := 0.95                      # altezza delle figure degli eroi
const KINDS := {
	"move": Color("#59d98a"), "explore": Color("#ffd36b"), "target": Color("#ff5a48"),
	"attack": Color("#ff5a48"), "danger": Color("#ff9a3a"), "select": Color("#f2ecd8"),
	"site": Color("#7fb8ff"), "info": Color("#b9a8ff"),
}

var rig: MKCameraRig
var s: Dictionary = {}
var day := true
var follow_active := true                # segue l'eroe di turno quando si muove
var animate := true                      # false = niente animazioni (screenshot, test)
var interactive := true                  # false = solo sfondo (menu)
var shadows := true

var env: Environment
var sun: DirectionalLight3D
var fill_light: DirectionalLight3D
var ground: MeshInstance3D
var ground_mat: ShaderMaterial
var tiles_root: Node3D
var slots_root: Node3D
var pieces_root: Node3D
var marks_root: Node3D
var fx_root: Node3D

var tiles := {}           # slot "q,r" -> {node, id}
var slot_nodes := {}      # slot -> nodo contorno
var enemy_nodes := {}     # eid -> nodo
var hero_nodes := {}      # indice giocatore -> nodo
var city_nodes := {}      # esagono -> nodo
var shield_nodes := {}    # "i|esagono|n" -> nodo
var ruin_nodes := {}      # esagono -> nodo
var lanterns := {}        # indice giocatore -> OmniLight3D (di notte)
var hl := {}              # chiave -> {kind, color, label, nodes:[...]}
var hl_hex := {}          # esagono -> chiave dell'evidenziazione (anche i 7 esagoni di un posto)
var hover_key := ""
var _hover_node: Node3D
var _hl_mats := {}
var _first := true
var _last_active_pos := ""
var _time := 0.0
var _mouse := Vector2(-1, -1)
var _tile_geo := {}       # id -> {w,h,cx,cy,r}
var _mat_cache := {}


func _ready() -> void:
	_build_environment()
	_build_ground()
	tiles_root = _child("Tiles")
	slots_root = _child("Slots")
	marks_root = _child("Marks")
	pieces_root = _child("Pieces")
	fx_root = _child("Fx")
	rig = MKCameraRig.new()
	rig.name = "CameraRig"
	rig.ground_y = TH
	add_child(rig)
	rig.moved.connect(func(): if _mouse.x >= 0: _update_hover(_mouse))
	_hover_node = _make_hl_node(Color(1, 1, 1), 0.16, 0.06)
	_hover_node.visible = false
	marks_root.add_child(_hover_node)
	set_day(true, true)


func _child(n: String) -> Node3D:
	var c := Node3D.new()
	c.name = n
	add_child(c)
	return c


# ================================================================== ambiente, luci, terreno

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	env.tonemap_exposure = 1.0
	env.glow_enabled = true
	env.glow_intensity = 0.3
	env.glow_bloom = 0.0
	env.glow_hdr_threshold = 1.1
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_depth_begin = 30.0
	env.fog_depth_end = 110.0
	env.fog_density = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.05
	env.adjustment_contrast = 1.04
	we.environment = env
	add_child(we)
	sun = DirectionalLight3D.new()
	sun.name = "Sun"
	sun.shadow_enabled = shadows
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.0
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45
	add_child(sun)
	# luce di riempimento dal lato opposto, senza ombre
	fill_light = DirectionalLight3D.new()
	fill_light.name = "Fill"
	fill_light.shadow_enabled = false
	add_child(fill_light)


const GROUND_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform vec3 deep_col : source_color = vec3(0.04, 0.12, 0.16);
uniform vec3 shallow_col : source_color = vec3(0.12, 0.30, 0.32);
uniform vec3 far_col : source_color = vec3(0.05, 0.05, 0.07);
uniform float night = 0.0;
uniform float fade_r = 70.0;

float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}
float fbm(vec2 p) {
	float v = 0.0; float a = 0.5;
	for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; }
	return v;
}
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 p = wpos.xz;
	float t = TIME * 0.03;
	float n = fbm(p * 0.18 + vec2(t, -t * 0.7));
	float n2 = fbm(p * 0.9 - vec2(t * 2.0, t));
	vec3 c = mix(deep_col, shallow_col, smoothstep(0.25, 0.85, n));
	c += vec3(0.05, 0.07, 0.07) * smoothstep(0.62, 0.9, n2) * (1.0 - night * 0.6);
	float d = length(p - vec2(4.0, -4.0));
	c = mix(c, far_col, smoothstep(fade_r * 0.35, fade_r, d));
	ALBEDO = c;
	ROUGHNESS = 0.35 + 0.4 * n2;
	METALLIC = 0.0;
	SPECULAR = 0.6;
}
"""


func _build_ground() -> void:
	ground = MeshInstance3D.new()
	ground.name = "Ground"
	var pm := PlaneMesh.new()
	pm.size = Vector2(320, 320)
	ground.mesh = pm
	ground.position = Vector3(0, -0.02, 0)
	var sh := Shader.new()
	sh.code = GROUND_SHADER
	ground_mat = ShaderMaterial.new()
	ground_mat.shader = sh
	ground.material_override = ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)


## Giorno (luce calda) / notte (luce fredda e blu). Con instant=false transizione morbida.
func set_day(is_day: bool, instant := false) -> void:
	day = is_day
	var P := {}
	if is_day:
		P = {"bg": Color("#16130f"), "amb": Color("#8c8070"), "amb_e": 0.40, "sun": Color("#fff0d6"), "sun_e": 0.92,
			"sun_rot": Vector3(-52, -38, 0), "fill": Color("#a8c0ff"), "fill_e": 0.14, "fog": Color("#16130f"),
			"deep": Color(0.03, 0.09, 0.12), "shallow": Color(0.08, 0.20, 0.22), "far": Color("#16130f"), "night": 0.0, "exp": 1.0}
	else:
		P = {"bg": Color("#05070e"), "amb": Color("#34466e"), "amb_e": 0.55, "sun": Color("#93aaff"), "sun_e": 0.55,
			"sun_rot": Vector3(-60, 140, 0), "fill": Color("#4a5a9a"), "fill_e": 0.18, "fog": Color("#05070e"),
			"deep": Color(0.01, 0.03, 0.07), "shallow": Color(0.04, 0.08, 0.16), "far": Color("#05070e"), "night": 1.0, "exp": 1.05}
	if instant or not animate or not is_inside_tree():
		_apply_light(P, 1.0, {})
	else:
		var from := _light_snapshot()
		var tw := create_tween()
		tw.tween_method(func(k: float): _apply_light(P, k, from), 0.0, 1.0, 1.4).set_trans(Tween.TRANS_SINE)
	_update_lanterns()


func _light_snapshot() -> Dictionary:
	return {"bg": env.background_color, "amb": env.ambient_light_color, "amb_e": env.ambient_light_energy,
		"sun": sun.light_color, "sun_e": sun.light_energy, "sun_rot": sun.rotation_degrees, "fill": fill_light.light_color,
		"fill_e": fill_light.light_energy, "fog": env.fog_light_color, "deep": ground_mat.get_shader_parameter("deep_col"),
		"shallow": ground_mat.get_shader_parameter("shallow_col"), "far": ground_mat.get_shader_parameter("far_col"),
		"night": ground_mat.get_shader_parameter("night"), "exp": env.tonemap_exposure}


func _apply_light(P: Dictionary, k: float, from: Dictionary) -> void:
	var L := func(key: String):
		if from.is_empty() or from.get(key) == null:
			return P[key]
		var a = from[key]
		var b = P[key]
		if a is Color:
			return (a as Color).lerp(b, k)
		if a is Vector3:
			return (a as Vector3).lerp(b, k)
		return lerpf(float(a), float(b), k)
	env.background_color = L.call("bg")
	env.ambient_light_color = L.call("amb")
	env.ambient_light_energy = L.call("amb_e")
	env.fog_light_color = L.call("fog")
	env.tonemap_exposure = L.call("exp")
	sun.light_color = L.call("sun")
	sun.light_energy = L.call("sun_e")
	sun.rotation_degrees = L.call("sun_rot")
	fill_light.light_color = L.call("fill")
	fill_light.light_energy = L.call("fill_e")
	fill_light.rotation_degrees = Vector3(-35, (sun.rotation_degrees.y + 180.0), 0)
	ground_mat.set_shader_parameter("deep_col", L.call("deep"))
	ground_mat.set_shader_parameter("shallow_col", L.call("shallow"))
	ground_mat.set_shader_parameter("far_col", L.call("far"))
	ground_mat.set_shader_parameter("night", L.call("night"))


# ================================================================== materiali

func _mat_tex(t: Texture2D, vcol := false, rough := 0.9, alpha := false) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s" % [t.get_rid() if t else "none", vcol, rough, alpha]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_texture = t
	m.roughness = rough
	m.vertex_color_use_as_albedo = vcol
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if alpha:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		m.alpha_scissor_threshold = 0.4
	_mat_cache[key] = m
	return m


func _mat_col(c: Color, rough := 0.75, metal := 0.0, emit := 0.0) -> StandardMaterial3D:
	var key := "c|%s|%s|%s|%s" % [c.to_html(), rough, metal, emit]
	if _mat_cache.has(key):
		return _mat_cache[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	if emit > 0:
		m.emission_enabled = true
		m.emission = c
		m.emission_energy_multiplier = emit
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat_cache[key] = m
	return m


## Materiale «luce»: senza ombreggiatura, trasparente (evidenziazioni, contorni).
func _mat_glow(c: Color, alpha: float, depth_test := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(c, alpha)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.vertex_color_use_as_albedo = true
	m.no_depth_test = not depth_test
	return m


# ================================================================== percorsi degli asset

## Texture della faccia di una tessera.
func _tile_tex_path(id: String) -> String:
	var p := MKUI.first([MKUI.asset_path("tiles", id), "res://assets/tiles/%s.webp" % id,
		"res://assets/tiles/%s.png" % id, "res://assets/tiles/%s.jpg" % id])
	if p == "":
		p = MKUI.fixture_path("tiles", id)
	return p


## Geometria della texture: da data/tiles.json (campo "tex" o "uv": {w,h,cx,cy,r}) oppure ricavata
## dalle proporzioni (immagine = fiore intero: larghezza 3√3·r, altezza 5·r).
func _tile_uvgeo(id: String, t: Texture2D) -> Dictionary:
	if _tile_geo.has(id):
		return _tile_geo[id]
	var g := {}
	var db := _tiles_db()
	var e = db.get(id, null)
	if e is Dictionary:
		for k in ["tex", "uv", "geo"]:
			if e.get(k) is Dictionary and e[k].has("r"):
				g = e[k]
	if g.is_empty() and t != null:
		var w := float(t.get_width())
		var h := float(t.get_height())
		g = {"w": w, "h": h, "cx": w / 2.0, "cy": h / 2.0, "r": h / 5.0}
	_tile_geo[id] = g
	return g


var _tdb = null

func _tiles_db() -> Dictionary:
	if _tdb == null:
		_tdb = {}
		if FileAccess.file_exists("res://data/tiles.json"):
			var j = JSON.parse_string(FileAccess.get_file_as_string("res://data/tiles.json"))
			if j is Dictionary:
				_tdb = j.get("tiles", j)
			elif j is Array:
				for e in j:
					if e is Dictionary and e.has("id"):
						_tdb[str(e["id"])] = e
	return _tdb


func _enemy_tex_path(type: String, color: String, face_up: bool) -> String:
	if face_up:
		var p := MKUI.first([MKUI.asset_path("enemies", type), "res://assets/enemies/%s.webp" % type,
			"res://assets/enemies/%s.png" % type])
		if p == "":
			p = MKUI.fixture_path("enemies", type)
		if p != "":
			return p
	var b := MKUI.first([MKUI.asset_path("enemies", "back_" + color), "res://assets/enemies/back_%s.webp" % color,
		"res://assets/enemies/back_%s.png" % color])
	if b == "":
		b = MKUI.fixture_path("enemies", "back_" + color)
	return b


## Modello: {mesh, tex} per "hero_arythea", "city_green"… (assets/models, poi i file grezzi del modulo).
func _model(name_id: String) -> Dictionary:
	var obj := MKUI.first([MKUI.asset_path("models", name_id), "res://assets/models/%s.obj" % name_id,
		"res://assets/models/%s.glb" % name_id])
	var tex := MKUI.first([MKUI.asset("model_tex_" + name_id), "res://assets/models/%s.webp" % name_id, "res://assets/models/%s.png" % name_id,
		"res://assets/models/%s.jpg" % name_id])
	# città: una sola mesh per i 4 colori
	if obj == "" and name_id.begins_with("city_"):
		obj = MKUI.first([MKUI.asset_path("models", "city"), "res://assets/models/city.obj"])
	var fx = MKUI.fixture("models", name_id)
	if fx is Dictionary:
		if obj == "":
			obj = str(fx.get("obj", ""))
		if tex == "":
			tex = str(fx.get("tex", ""))
	return {"mesh": MKUI.mesh(obj), "tex": MKUI.tex3d(tex, 1024) if tex != "" else null}


## Miniatura che sostituisce il modello predefinito (assets/miniatures/<id>.glb).
func _miniature(ids: Array) -> PackedScene:
	for id in ids:
		var p := "res://assets/miniatures/%s.glb" % id
		if ResourceLoader.exists(p):
			return load(p)
	return null


# ================================================================== coordinate

func hex_pos(k: String) -> Vector3:
	var w := MKHexMesh.key_world(k)
	return Vector3(w.x, TH, w.z)


## Posizione sullo schermo di un esagono (per ancorare finestre dell'HUD).
func screen_pos(k: String, lift := 0.0) -> Vector2:
	if rig == null or rig.cam == null:
		return Vector2.ZERO
	return rig.cam.unproject_position(hex_pos(k) + Vector3(0, lift, 0))


func pick_hex(sp: Vector2) -> String:
	var g = rig.ground_point(sp, TH)
	if g == null:
		return ""
	var a := MKHexMesh.from_world(g.x, g.z)
	return MKHexMesh.key(a.x, a.y)


func _map_hex() -> Dictionary:
	var m = s.get("map", {})
	if m is Dictionary:
		var h = m.get("hex", {})
		if h is Dictionary:
			return h
	return {}


## Descrizione italiana di un esagono (terreno · sito · nemici) per i suggerimenti dell'HUD.
func hex_info(k: String) -> String:
	var h = _map_hex().get(k, null)
	if not (h is Dictionary):
		return ""
	var parts := [MKUI.terrain_it(h.get("t", ""))]
	var site := str(h.get("site", ""))
	if site != "":
		var st := MKUI.site_it(site)
		if h.get("city") is Dictionary:
			st += " " + {"green": "verde", "blue": "blu", "red": "rossa", "white": "bianca"}.get(str(h["city"].get("color", "")), "")
		if str(h.get("mine", "")) != "":
			st += " (%s)" % str(h["mine"])
		parts.append(st)
	var n := 0
	for eid in h.get("enemies", []):
		n += 1
	if n > 0:
		parts.append("%d nemic%s" % [n, "o" if n == 1 else "i"])
	return " · ".join(parts)


# ================================================================== aggiornamento dallo stato

## Disegna lo stato s; si può richiamare a ogni cambio (aggiorna solo ciò che è cambiato).
func refresh(state: Dictionary) -> void:
	s = state
	var anim := animate and not _first
	if state.has("day") and bool(state["day"]) != day:
		set_day(bool(state["day"]), not anim)
	elif _first and state.has("day"):
		set_day(bool(state["day"]), true)
	_sync_tiles(anim)
	_sync_slots()
	_sync_cities()
	_sync_enemies(anim)
	_sync_heroes(anim)
	_sync_shields(anim)
	_sync_ruins()
	_update_bounds()
	if _first:
		_first = false
		rig.reset(true)
	_follow(anim)
	_update_lanterns()


func _tiles_list() -> Array:
	var m = s.get("map", {})
	if m is Dictionary and m.get("tiles") is Array:
		return m["tiles"]
	return []


func _sync_tiles(anim: bool) -> void:
	var seen := {}
	for t in _tiles_list():
		if not (t is Dictionary):
			continue
		var slot := str(t.get("slot", ""))
		var id := str(t.get("id", ""))
		seen[slot] = true
		if tiles.has(slot) and tiles[slot]["id"] == id:
			continue
		if tiles.has(slot):
			tiles[slot]["node"].queue_free()
		var n := _make_tile(id)
		n.position = MKHexMesh.key_world(slot)
		tiles_root.add_child(n)
		tiles[slot] = {"node": n, "id": id}
		if anim:
			_anim_reveal(n)
	for slot in tiles.keys():
		if not seen.has(slot):
			tiles[slot]["node"].queue_free()
			tiles.erase(slot)


func _make_tile(id: String) -> Node3D:
	var root := Node3D.new()
	root.name = "Tile_" + id
	var mi := MeshInstance3D.new()
	var t := MKUI.tex3d(_tile_tex_path(id), 2048)
	mi.mesh = MKHexMesh.tile_mesh(TH, 0.03, _tile_uvgeo(id, t))
	if t != null:
		mi.set_surface_override_material(0, _mat_tex(t, true, 0.92))
	else:
		# texture mancante: colore neutro (le texture arrivano dall'agente WORLD)
		var m := _mat_col(Color("#6f7a4a"), 0.9)
		var m2: StandardMaterial3D = m.duplicate()
		m2.vertex_color_use_as_albedo = true
		mi.set_surface_override_material(0, m2)
	mi.set_surface_override_material(1, _mat_col(Color("#2a2119"), 0.95))
	root.add_child(mi)
	return root


## Rivelazione: la tessera scende girandosi dall'alto.
func _anim_reveal(n: Node3D) -> void:
	var p := n.position
	n.position = p + Vector3(0, 2.5, 0)
	n.rotation = Vector3(0, 0, PI)
	n.scale = Vector3.ONE * 0.85
	var tw := create_tween().set_parallel(true)
	tw.tween_property(n, "position", p, 0.75).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(n, "rotation", Vector3.ZERO, 0.65).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(n, "scale", Vector3.ONE, 0.75)
	tw.chain().tween_callback(func(): fx_dust(p))


## Posti non ancora esplorati da mostrare con un contorno tenue: s.map.slots se il motore li fornisce,
## altrimenti i posti della forma liberi e adiacenti ad almeno una tessera.
func _free_slots() -> Array:
	var m = s.get("map", {})
	if m is Dictionary and m.get("slots") is Array:
		return m["slots"].filter(func(x): return not tiles.has(str(x)))
	var shape := str(m.get("shape", "wedge")) if m is Dictionary else "wedge"
	var out := {}
	for slot in tiles:
		var c := MKHexMesh.parse(slot)
		for d in MKHexMesh.MACRO:
			var n: Vector2i = c + d
			var k := MKHexMesh.key(n.x, n.y)
			if tiles.has(k) or out.has(k):
				continue
			if MKHexMesh.in_shape(n, shape):
				out[k] = true
	return out.keys()


func _sync_slots() -> void:
	var want := {}
	for k in _free_slots():
		want[str(k)] = true
	for k in slot_nodes.keys():
		if not want.has(k):
			slot_nodes[k].queue_free()
			slot_nodes.erase(k)
	for k in want:
		if slot_nodes.has(k):
			continue
		var mi := MeshInstance3D.new()
		mi.mesh = MKHexMesh.flower_outline_mesh(0.035)
		mi.material_override = _slot_mat()
		mi.position = MKHexMesh.key_world(k) + Vector3(0, 0.012, 0)
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		slots_root.add_child(mi)
		slot_nodes[k] = mi


var _slot_m: StandardMaterial3D

func _slot_mat() -> StandardMaterial3D:
	if _slot_m == null:
		_slot_m = _mat_glow(Color("#e8d9a8"), 0.28)
	return _slot_m


# ------------------------------------------------------------------ città

func _sync_cities() -> void:
	var seen := {}
	var H := _map_hex()
	for k in H:
		var h = H[k]
		if not (h is Dictionary) or MKUI.norm(h.get("site", "")) != "city":
			continue
		var col := "white"
		if h.get("city") is Dictionary:
			col = str(h["city"].get("color", "white"))
		var key := "%s|%s" % [k, col]
		seen[key] = true
		if city_nodes.has(key):
			continue
		var n := _make_city(col)
		n.position = hex_pos(k)
		pieces_root.add_child(n)
		city_nodes[key] = n
	for key in city_nodes.keys():
		if not seen.has(key):
			city_nodes[key].queue_free()
			city_nodes.erase(key)


func _make_city(col: String) -> Node3D:
	var root := Node3D.new()
	root.name = "City_" + col
	var ps := _miniature(["city_" + col, "city"])
	if ps != null:
		_fit_scene(root, ps.instantiate(), 1.25, 1.5)
		return root
	var md := _model("city_" + col)
	var mesh: Mesh = md["mesh"]
	if mesh == null:
		# ripiego: torre stilizzata del colore della città
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.45
		cm.height = 0.7
		var mi0 := MeshInstance3D.new()
		mi0.mesh = cm
		mi0.position.y = 0.35
		mi0.material_override = _mat_col(MKUI.MANA_COL.get(col, Color.WHITE), 0.6)
		root.add_child(mi0)
		return root
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if md["tex"] != null:
		mi.material_override = _mat_tex(md["tex"], false, 0.8)
	var ab := mesh.get_aabb()
	var sc := 1.2 / maxf(ab.size.x, ab.size.z)
	mi.scale = Vector3.ONE * sc
	mi.position = Vector3(-(ab.position.x + ab.size.x / 2) * sc, -ab.position.y * sc, -(ab.position.z + ab.size.z / 2) * sc)
	root.add_child(mi)
	return root


## Adatta una scena (glb) a una larghezza/altezza massima, appoggiata a y=0 e centrata.
func _fit_scene(root: Node3D, inst: Node3D, max_h: float, max_w := 99.0) -> void:
	var hold := Node3D.new()
	hold.add_child(inst)
	root.add_child(hold)
	var ab := _scene_aabb(inst)
	if ab.size.y > 0.0001:
		var sc := minf(max_h / ab.size.y, max_w / maxf(ab.size.x, ab.size.z))
		hold.scale = Vector3.ONE * sc
		hold.position = Vector3(-(ab.position.x + ab.size.x / 2) * sc, -ab.position.y * sc, -(ab.position.z + ab.size.z / 2) * sc)


func _scene_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for c in n.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = c
		var t := Transform3D.IDENTITY
		var p: Node = mi
		while p != null and p != n:
			if p is Node3D:
				t = (p as Node3D).transform * t
			p = p.get_parent()
		var a := t * mi.get_aabb()
		if first:
			out = a
			first = false
		else:
			out = out.merge(a)
	return out


# ------------------------------------------------------------------ nemici

func _enemies_by_hex() -> Dictionary:
	var by := {}
	var E = s.get("enemies", {})
	if not (E is Dictionary):
		return by
	var H := _map_hex()
	for eid in E:
		var e = E[eid]
		if not (e is Dictionary):
			continue
		var hk := str(e.get("hex", ""))
		if hk == "" or e.get("defeated", false):
			continue
		if not by.has(hk):
			by[hk] = []
		by[hk].append(str(eid))
	# ordine: quello dell'esagono (s.map.hex[k].enemies), poi gli altri
	for hk in by:
		var order: Array = []
		if H.get(hk) is Dictionary:
			order = H[hk].get("enemies", [])
		var arr: Array = by[hk]
		arr.sort_custom(func(a, b):
			var ia := order.find(a)
			var ib := order.find(b)
			if ia == -1:
				ia = 999
			if ib == -1:
				ib = 999
			return ia < ib if ia != ib else a < b)
	return by


func _sync_enemies(anim: bool) -> void:
	var E: Dictionary = s.get("enemies", {}) if s.get("enemies") is Dictionary else {}
	var by := _enemies_by_hex()
	var seen := {}
	for hk in by:
		var arr: Array = by[hk]
		var has_city := MKUI.norm(_map_hex().get(hk, {}).get("site", "")) == "city" if _map_hex().get(hk) is Dictionary else false
		for i in range(arr.size()):
			var eid: String = arr[i]
			var e: Dictionary = E[eid]
			seen[eid] = true
			var up := bool(e.get("face_up", true))
			var type := str(e.get("type", eid))
			var color := str(e.get("color", "green"))
			var n: Node3D = enemy_nodes.get(eid)
			if n == null:
				n = _make_token(type, color, up)
				n.name = "Enemy_" + eid
				pieces_root.add_child(n)
				enemy_nodes[eid] = n
				n.position = _token_pos(hk, i, arr.size(), has_city)
				n.scale = Vector3.ONE * (0.8 if has_city else 1.0)
				if anim:
					_anim_drop(n)
			else:
				if bool(n.get_meta("up")) != up:
					_flip_token(n, type, color, up, anim)
				_move_to(n, _token_pos(hk, i, arr.size(), has_city), anim, 0.35)
	for eid in enemy_nodes.keys():
		if not seen.has(eid):
			var n: Node3D = enemy_nodes[eid]
			enemy_nodes.erase(eid)
			if anim:
				var tw := create_tween()
				tw.tween_property(n, "position", n.position + Vector3(0, 0.6, 0), 0.25)
				tw.parallel().tween_property(n, "scale", Vector3.ONE * 0.05, 0.35).set_delay(0.1)
				tw.tween_callback(n.queue_free)
			else:
				n.queue_free()


## Pila di segnalini: si sale di spessore e si sposta un poco, così si vede quanti sono.
## Sulle città la pila sta di lato al modello.
func _token_pos(hk: String, i: int, n: int, has_city: bool) -> Vector3:
	var base := hex_pos(hk)
	var k := 1.0
	if has_city:
		base += Vector3(0.52, 0, 0.5)
		k = 0.8
	return base + (Vector3(0.06 * i, 0, -0.08 * i) - Vector3(0.03 * (n - 1), 0, -0.04 * (n - 1))) * k + Vector3(0, (TOKEN_H * k + 0.004) * i, 0)


func _make_token(type: String, color: String, up: bool) -> Node3D:
	var root := Node3D.new()
	var spin := Node3D.new()
	spin.name = "spin"
	spin.position.y = TOKEN_H / 2.0
	root.add_child(spin)
	var mi := MeshInstance3D.new()
	mi.name = "disc"
	mi.mesh = MKHexMesh.disc_mesh(TOKEN_R, TOKEN_H)
	mi.position.y = -TOKEN_H / 2.0
	spin.add_child(mi)
	root.set_meta("up", up)
	_paint_token(mi, type, color, up)
	# Miniatura 3D facoltativa (assets/miniatures/<tipo>.glb, generata con Meshy): sta in piedi sul segnalino,
	# visibile solo quando il nemico è scoperto.
	var mini: Node3D = MKMiniatures.enemy(type, 0.55, TOKEN_R * 1.8)
	if mini != null:
		mini.name = "mini"
		mini.position.y = TOKEN_H / 2.0
		mini.visible = up
		spin.add_child(mini)
	return root


func _paint_token(mi: MeshInstance3D, type: String, color: String, up: bool) -> void:
	var t := MKUI.tex3d(_enemy_tex_path(type, color, up), 512)
	var col: Color = MKUI.ENEMY_COL.get(color, Color("#888888"))
	if t != null:
		mi.set_surface_override_material(0, _mat_tex(t, false, 0.55))
	else:
		mi.set_surface_override_material(0, _mat_col(col, 0.6))
	mi.set_surface_override_material(1, _mat_col(col.darkened(0.55), 0.6))
	var back := MKUI.tex3d(_enemy_tex_path(type, color, false), 512)
	mi.set_surface_override_material(2, _mat_tex(back, false, 0.6) if back else _mat_col(col, 0.6))


func _flip_token(n: Node3D, type: String, color: String, up: bool, anim: bool) -> void:
	n.set_meta("up", up)
	var spin: Node3D = n.get_node("spin")
	var mi: MeshInstance3D = spin.get_node("disc")
	if not anim:
		_paint_token(mi, type, color, up)
		if spin.has_node("mini"):
			spin.get_node("mini").visible = up
		return
	var tw := create_tween()
	tw.tween_property(spin, "position:y", TOKEN_H / 2.0 + 0.5, 0.2).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(spin, "rotation:x", PI / 2.0, 0.2)
	tw.tween_callback(func():
		_paint_token(mi, type, color, up)
		if spin.has_node("mini"):
			spin.get_node("mini").visible = up
		spin.rotation.x = -PI / 2.0)
	tw.tween_property(spin, "rotation:x", 0.0, 0.2)
	tw.parallel().tween_property(spin, "position:y", TOKEN_H / 2.0, 0.25).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _anim_drop(n: Node3D) -> void:
	var p := n.position
	n.position = p + Vector3(0, 1.6, 0)
	var tw := create_tween()
	tw.tween_property(n, "position", p, 0.45).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func _move_to(n: Node3D, p: Vector3, anim: bool, dur := 0.4, hop := 0.0) -> void:
	if n.position.distance_to(p) < 0.001:
		return
	if n.has_meta("tw"):
		var old = n.get_meta("tw")
		if old is Tween and (old as Tween).is_valid():
			(old as Tween).kill()
	if not anim:
		n.position = p
		return
	var a := n.position
	var tw := create_tween()
	tw.tween_method(func(t: float):
		if is_instance_valid(n):
			n.position = a.lerp(p, t) + Vector3(0, sin(t * PI) * hop, 0), 0.0, 1.0, dur).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	n.set_meta("tw", tw)


# ------------------------------------------------------------------ eroi

func _players() -> Array:
	return s.get("players", []) if s.get("players") is Array else []


func _sync_heroes(anim: bool) -> void:
	var P := _players()
	var by_hex := {}
	for i in range(P.size()):
		var p = P[i]
		if not (p is Dictionary):
			continue
		var pos := str(p.get("pos", ""))
		if pos == "":
			continue
		if not by_hex.has(pos):
			by_hex[pos] = []
		by_hex[pos].append(i)
	var seen := {}
	for pos in by_hex:
		var arr: Array = by_hex[pos]
		for j in range(arr.size()):
			var i: int = arr[j]
			var hero := str(P[i].get("hero", "arythea"))
			seen[i] = true
			var n: Node3D = hero_nodes.get(i)
			if n != null and n.get_meta("hero", "") != hero:
				n.queue_free()
				n = null
			var dest := hex_pos(pos) + _hero_offset(j, arr.size())
			var fsc := 1.0 if arr.size() == 1 else 0.68
			var has_en := _enemies_by_hex().has(pos)
			if has_en:
				dest += Vector3(-0.3, 0, 0.25)
			if n == null:
				n = _make_hero(hero)
				n.name = "Hero_%d" % i
				pieces_root.add_child(n)
				hero_nodes[i] = n
				n.position = dest
				n.set_meta("pos", pos)
				n.scale = Vector3.ONE * fsc
				if anim:
					_anim_drop(n)
				continue
			if not is_equal_approx(n.scale.x, fsc):
				if anim:
					create_tween().tween_property(n, "scale", Vector3.ONE * fsc, 0.3)
				else:
					n.scale = Vector3.ONE * fsc
			if str(n.get_meta("pos", "")) != pos:
				var from_k := str(n.get_meta("pos", ""))
				n.set_meta("pos", pos)
				var steps := 1
				if from_k != "":
					steps = maxi(1, MKHexMesh.distance(MKHexMesh.parse(from_k), MKHexMesh.parse(pos)))
				# la figura si gira verso la direzione di marcia
				var d := dest - n.position
				if Vector2(d.x, d.z).length() > 0.01:
					var fig: Node3D = n.get_node_or_null("fig")
					if fig != null:
						var want := atan2(d.x, d.z)
						if anim:
							create_tween().tween_property(fig, "rotation:y", _near_angle(fig.rotation.y, want), 0.18)
						else:
							fig.rotation.y = want
				_move_to(n, dest, anim, clampf(0.42 * steps, 0.42, 1.4), 0.45)
			else:
				_move_to(n, dest, anim, 0.3)
	for i in hero_nodes.keys():
		if not seen.has(i):
			hero_nodes[i].queue_free()
			hero_nodes.erase(i)
	# anello dell'eroe di turno
	var act := int(s.get("active", -1))
	for i in hero_nodes:
		var ring: Node3D = hero_nodes[i].get_node_or_null("active")
		if ring:
			ring.visible = (i == act)


func _near_angle(cur: float, want: float) -> float:
	return cur + wrapf(want - cur, -PI, PI)


func _hero_offset(j: int, n: int) -> Vector3:
	if n <= 1:
		return Vector3.ZERO
	var a := TAU * j / n + PI / 4
	return Vector3(cos(a), 0, sin(a)) * 0.42


func _make_hero(hero: String) -> Node3D:
	var root := Node3D.new()
	root.set_meta("hero", hero)
	var col := MKUI.hero_col(hero)
	# basetta colorata dell'eroe
	var base := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.30
	cm.bottom_radius = 0.33
	cm.height = 0.05
	cm.radial_segments = 32
	base.mesh = cm
	base.position.y = 0.025
	base.material_override = _mat_col(col.darkened(0.25), 0.45, 0.3)
	root.add_child(base)
	# anello luminoso dell'eroe di turno
	var ring := MeshInstance3D.new()
	ring.name = "active"
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.48
	tm.rings = 32
	ring.mesh = tm
	ring.position.y = 0.035
	ring.material_override = _mat_col(Color("#ffd36b"), 0.4, 0.0, 2.2)
	ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ring.visible = false
	root.add_child(ring)
	var fig := Node3D.new()
	fig.name = "fig"
	fig.position.y = 0.05
	root.add_child(fig)
	var ps := _miniature([hero, "hero_" + hero])
	if ps != null:
		_fit_scene(fig, ps.instantiate(), FIG_H, 0.7)
		return root
	var md := _model("hero_" + hero)
	var mesh: Mesh = md["mesh"]
	if mesh == null:
		# ripiego: sagoma a cono del colore dell'eroe
		var c2 := CylinderMesh.new()
		c2.top_radius = 0.08
		c2.bottom_radius = 0.22
		c2.height = FIG_H * 0.8
		var mi0 := MeshInstance3D.new()
		mi0.mesh = c2
		mi0.position.y = FIG_H * 0.4
		mi0.material_override = _mat_col(col, 0.5)
		fig.add_child(mi0)
		return root
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	if md["tex"] != null:
		mi.material_override = _mat_tex(md["tex"], false, 0.65)
	else:
		mi.material_override = _mat_col(col, 0.6)
	var ab := mesh.get_aabb()
	var sc := minf(FIG_H / maxf(ab.size.y, 0.001), 0.95 / maxf(maxf(ab.size.x, ab.size.z), 0.001))
	mi.scale = Vector3.ONE * sc
	mi.position = Vector3(-(ab.position.x + ab.size.x / 2) * sc, -ab.position.y * sc, -(ab.position.z + ab.size.z / 2) * sc)
	fig.add_child(mi)
	return root


func _update_lanterns() -> void:
	if not is_inside_tree():
		return
	for i in hero_nodes:
		var n: Node3D = hero_nodes[i]
		var l: OmniLight3D = n.get_node_or_null("lantern")
		if not day and l == null:
			l = OmniLight3D.new()
			l.name = "lantern"
			l.light_color = Color("#ffb060")
			l.light_energy = 1.4
			l.omni_range = 3.2
			l.omni_attenuation = 1.6
			l.position = Vector3(0, 1.1, 0.2)
			l.shadow_enabled = false
			n.add_child(l)
		elif day and l != null:
			l.queue_free()


# ------------------------------------------------------------------ scudi e rovine

func _sync_shields(anim: bool) -> void:
	var seen := {}
	var P := _players()
	var count := {}
	for i in range(P.size()):
		var p = P[i]
		if not (p is Dictionary):
			continue
		for hk in p.get("shields", []):
			var k := str(hk)
			var nth: int = count.get(k, 0)
			count[k] = nth + 1
			var key := "%d|%s|%d" % [i, k, nth]
			seen[key] = true
			if shield_nodes.has(key):
				continue
			var n := _make_shield(MKUI.hero_col(str(p.get("hero", ""))), str(p.get("hero", "")))
			n.position = hex_pos(k) + Vector3(-0.42 + 0.2 * nth, 0, -0.5)
			pieces_root.add_child(n)
			shield_nodes[key] = n
			if anim:
				_anim_drop(n)
	# scudi sulle città (s.map.hex[k].city.shields = indici dei giocatori)
	var H := _map_hex()
	for k in H:
		var h = H[k]
		if not (h is Dictionary) or not (h.get("city") is Dictionary):
			continue
		var cs = h["city"].get("shields", [])
		if not (cs is Array):
			continue
		for j in range(cs.size()):
			var pi := int(cs[j])
			var key2 := "city|%s|%d|%d" % [k, j, pi]
			seen[key2] = true
			if shield_nodes.has(key2):
				continue
			var hero2 := str(P[pi].get("hero", "")) if pi >= 0 and pi < P.size() and P[pi] is Dictionary else ""
			var n2 := _make_shield(MKUI.hero_col(hero2), hero2)
			n2.position = hex_pos(k) + Vector3(-0.62 + 0.2 * j, 0, 0.45)
			pieces_root.add_child(n2)
			shield_nodes[key2] = n2
			if anim:
				_anim_drop(n2)
	for key in shield_nodes.keys():
		if not seen.has(key):
			shield_nodes[key].queue_free()
			shield_nodes.erase(key)


## Scudo: piccolo segnalino a forma di scudo (pentagono a punta in giù) nel colore dell'eroe.
func _make_shield(col: Color, hero := "") -> Node3D:
	var root := Node3D.new()
	var poly := PackedVector2Array([Vector2(-0.13, -0.14), Vector2(0.13, -0.14), Vector2(0.13, 0.02), Vector2(0, 0.16), Vector2(-0.13, 0.02)])
	var mi := MeshInstance3D.new()
	var pm := PolygonMesh_make(poly, 0.05)
	mi.mesh = pm
	var t := MKUI.tex3d(MKUI.first([MKUI.asset("hero_shield_" + hero), "res://assets/tokens/hero_%s_shield.webp" % hero]), 256) if hero != "" else null
	mi.material_override = _mat_tex(t, false, 0.45) if t != null else _mat_col(col, 0.4, 0.2)
	root.add_child(mi)
	var rim := MeshInstance3D.new()
	var poly2 := PackedVector2Array()
	for v in poly:
		poly2.append(v * 1.22)
	rim.mesh = PolygonMesh_make(poly2, 0.035)
	rim.material_override = _mat_col(MKUI.GOLD, 0.35, 0.7)
	root.add_child(rim)
	return root


## Prisma da un poligono convesso (xz), alto h, appoggiato a y=0.
func PolygonMesh_make(poly: PackedVector2Array, h: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := poly.size()
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for v in poly:
		mn = Vector2(minf(mn.x, v.x), minf(mn.y, v.y))
		mx = Vector2(maxf(mx.x, v.x), maxf(mx.y, v.y))
	for i in range(1, n - 1):
		for v in [poly[0], poly[i], poly[i + 1]]:
			st.set_normal(Vector3.UP)
			# UV: il poligono riempie l'immagine (lo scudo dell'eroe è un'immagine quadrata)
			st.set_uv(Vector2(lerpf(0.06, 0.94, (v.x - mn.x) / (mx.x - mn.x)), (v.y - mn.y) / (mx.y - mn.y)))
			st.add_vertex(Vector3(v.x, h, v.y))
	for i in range(n):
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var d := (b - a).normalized()
		var nn := Vector3(d.y, 0, -d.x)
		var c := Vector3.ZERO
		if nn.dot(Vector3(a.x + b.x, 0, a.y + b.y)) < 0:
			nn = -nn
		for v in [Vector3(a.x, h, a.y), Vector3(b.x, h, b.y), Vector3(b.x, 0, b.y), Vector3(a.x, h, a.y), Vector3(b.x, 0, b.y), Vector3(a.x, 0, a.y)]:
			st.set_normal(nn)
			st.add_vertex(v)
	var m := st.commit()
	MKHexMesh._fix_winding(m)
	return m


func _sync_ruins() -> void:
	var seen := {}
	var H := _map_hex()
	for k in H:
		var h = H[k]
		if not (h is Dictionary):
			continue
		var r = h.get("ruins", null)
		if r == null or str(r) == "":
			continue
		var rid := str(r.get("id", "")) if r is Dictionary else str(r)
		var up := bool(r.get("face_up", true)) if r is Dictionary else bool(h.get("ruins_face_up", true))
		var key := "%s|%s|%s" % [k, rid, up]
		seen[key] = true
		if ruin_nodes.has(key):
			continue
		var n := Node3D.new()
		var mi := MeshInstance3D.new()
		mi.mesh = MKHexMesh.disc_mesh(0.3, 0.04)
		var back := MKUI.first([MKUI.asset("ruin_back"), "res://assets/ruins/back.webp"])
		var p := MKUI.first([MKUI.asset("ruin_" + rid), "res://assets/ruins/%s.webp" % rid, back]) if up else back
		var t := MKUI.tex3d(p, 512)
		mi.set_surface_override_material(0, _mat_tex(t, false, 0.6) if t else _mat_col(MKUI.ENEMY_COL["ruins"], 0.6))
		mi.set_surface_override_material(1, _mat_col(Color("#5a4a20"), 0.6))
		mi.set_surface_override_material(2, _mat_col(Color("#5a4a20"), 0.6))
		n.add_child(mi)
		n.position = hex_pos(k) + Vector3(0.42, 0, 0.3)
		pieces_root.add_child(n)
		ruin_nodes[key] = n
	for key in ruin_nodes.keys():
		if not seen.has(key):
			ruin_nodes[key].queue_free()
			ruin_nodes.erase(key)


# ------------------------------------------------------------------ telecamera

func _update_bounds() -> void:
	if tiles.is_empty():
		return
	var mn := Vector2(INF, INF)
	var mx := Vector2(-INF, -INF)
	for slot in tiles:
		var w := MKHexMesh.key_world(slot)
		mn = Vector2(minf(mn.x, w.x), minf(mn.y, w.z))
		mx = Vector2(maxf(mx.x, w.x), maxf(mx.y, w.z))
	var r := Rect2(mn, mx - mn).grow(6.0)
	rig.bounds = r
	var c := (mn + mx) / 2.0
	var ext := maxf(mx.x - mn.x, mx.y - mn.y)
	rig.set_home(Vector3(c.x, TH, c.y + 0.5), clampf(ext * 1.15 + 9.0, 12.0, 40.0), 52.0, 0.0)
	rig.max_dist = clampf(ext * 2.2 + 14.0, 24.0, 60.0)


func _active_pos() -> String:
	var a := int(s.get("active", -1))
	var P := _players()
	if a >= 0 and a < P.size() and P[a] is Dictionary:
		return str(P[a].get("pos", ""))
	return ""


func _follow(anim: bool) -> void:
	var pos := _active_pos()
	if pos == "" or pos == _last_active_pos:
		return
	var first := _last_active_pos == ""
	_last_active_pos = pos
	if follow_active and not first and interactive:
		focus_hex(pos)


## Centra dolcemente l'esagono (zoom opzionale: distanza della telecamera).
func focus_hex(k: String, zoom := -1.0) -> void:
	rig.focus(hex_pos(k), zoom)


func focus_active(zoom := 11.0) -> void:
	var pos := _active_pos()
	if pos != "":
		focus_hex(pos, zoom)


func reset_camera() -> void:
	rig.reset()


## Bottoni della telecamera per il tocco (li posiziona l'HUD).
func make_camera_buttons() -> Control:
	var box := rig.make_buttons()
	var b: Button = box.get_node_or_null("cam_6")
	if b:
		b.pressed.connect(func(): focus_active())
	return box


# ================================================================== evidenziazioni

## d: {chiave: tipo | Color | {kind, color, label}}. Tipi: move, explore, target/attack, danger,
## select, site, info. Per "explore" la chiave è il posto (centro della tessera): si evidenziano i
## suoi 7 esagoni e un clic su uno qualsiasi emette hex_clicked(posto).
func set_highlights(d: Dictionary) -> void:
	clear_highlights()
	for k in d:
		var v = d[k]
		var kind := "select"
		var col := Color.WHITE
		var label := ""
		if v is String:
			kind = v
		elif v is Color:
			kind = "custom"
			col = v
		elif v is Dictionary:
			kind = str(v.get("kind", "select"))
			label = str(v.get("label", ""))
			if v.get("color") is Color:
				col = v["color"]
			elif v.get("color") is String:
				col = Color(v["color"])
		if kind != "custom" and not (v is Dictionary and v.has("color")):
			col = KINDS.get(kind, Color.WHITE)
		var key := str(k)
		var nodes := []
		var hexes := [key]
		if kind == "explore":
			hexes = []
			for h in MKHexMesh.flower(MKHexMesh.parse(key)):
				hexes.append(MKHexMesh.key(h.x, h.y))
		for hk in hexes:
			var n := _make_hl_node(col, 0.2 if kind != "explore" else 0.12, 0.07 if kind != "explore" else 0.04)
			n.position = hex_pos(hk) + Vector3(0, 0.006, 0)
			marks_root.add_child(n)
			nodes.append(n)
			hl_hex[hk] = key
		if label != "":
			var lb := _label3d(label, col, 72)
			lb.position = hex_pos(key) + Vector3(0, 0.32, 0)
			marks_root.add_child(lb)
			nodes.append(lb)
		hl[key] = {"kind": kind, "color": col, "label": label, "nodes": nodes}


func clear_highlights() -> void:
	for k in hl:
		for n in hl[k]["nodes"]:
			if is_instance_valid(n):
				n.queue_free()
	hl.clear()
	hl_hex.clear()


func _make_hl_node(col: Color, fill_a: float, ring_w: float) -> Node3D:
	var root := Node3D.new()
	var f := MeshInstance3D.new()
	f.mesh = MKHexMesh.fill_mesh(0.95)
	f.material_override = _hl_mat(col, fill_a, "f")
	f.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(f)
	var r := MeshInstance3D.new()
	r.mesh = MKHexMesh.ring_mesh(0.95, ring_w)
	r.material_override = _hl_mat(col, 0.95, "r")
	r.position.y = 0.002
	r.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(r)
	return root


func _hl_mat(col: Color, a: float, kind: String) -> StandardMaterial3D:
	var key := "%s|%s|%s" % [col.to_html(), a, kind]
	if not _hl_mats.has(key):
		var m := _mat_glow(col, a)
		m.vertex_color_use_as_albedo = false
		m.render_priority = 1
		_hl_mats[key] = {"m": m, "a": a}
	return _hl_mats[key]["m"]


func _label3d(text: String, col: Color, size := 64) -> Label3D:
	MKUI.init_fonts()
	var lb := Label3D.new()
	lb.text = text
	lb.font = MKUI.font_bold
	lb.font_size = size
	lb.pixel_size = 0.0045
	lb.modulate = col.lightened(0.35)
	lb.outline_size = 14
	lb.outline_modulate = Color(0, 0, 0, 0.9)
	lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lb.no_depth_test = true
	lb.render_priority = 3
	lb.outline_render_priority = 2
	return lb


# ================================================================== input e puntatore

func _unhandled_input(ev: InputEvent) -> void:
	if not interactive or rig == null or not is_visible_in_tree():
		return
	var r = rig.handle_input(ev)
	if ev is InputEventMouse:
		_mouse = ev.position
	if r is String and r == "click":
		var k := _resolve_click(rig.click_pos)
		if k != "":
			hex_clicked.emit(k)
		get_viewport().set_input_as_handled()
		return
	if ev is InputEventMouseMotion:
		_update_hover(ev.position)
	if r is bool and r:
		get_viewport().set_input_as_handled()


func _resolve_click(sp: Vector2) -> String:
	var k := pick_hex(sp)
	if k == "":
		return ""
	if hl_hex.has(k) and not hl.has(k):
		return str(hl_hex[k])
	return k


func _update_hover(sp: Vector2) -> void:
	var k := pick_hex(sp)
	if k != "" and not _map_hex().has(k) and not hl_hex.has(k):
		k = ""
	if k == hover_key:
		return
	hover_key = k
	if k == "":
		_hover_node.visible = false
	else:
		_hover_node.visible = true
		_hover_node.position = hex_pos(k) + Vector3(0, 0.01, 0)
	hex_hovered.emit(k)


func _process(delta: float) -> void:
	_time += delta
	# le evidenziazioni pulsano piano
	var p := 0.75 + 0.25 * sin(_time * 3.2)
	for key in _hl_mats:
		var e: Dictionary = _hl_mats[key]
		var m: StandardMaterial3D = e["m"]
		m.albedo_color.a = e["a"] * (p if key.ends_with("|r") else (0.6 + 0.4 * p))


# ================================================================== effetti

## Testo fluttuante su un esagono (danni, Fama, «Esplorato!»…).
func fx_text(k: String, text: String, col := Color("#ffd36b")) -> void:
	var lb := _label3d(text, col, 80)
	lb.position = hex_pos(k) + Vector3(0, 1.2, 0)
	fx_root.add_child(lb)
	var tw := create_tween()
	tw.tween_property(lb, "position", lb.position + Vector3(0, 0.9, 0), 1.6)
	tw.parallel().tween_property(lb, "modulate:a", 0.0, 1.0).set_delay(0.7)
	tw.tween_callback(lb.queue_free)


## Anello che si allarga su un esagono.
func fx_ring(k: String, col := Color("#ff5a3a")) -> void:
	var n := _make_hl_node(col, 0.0, 0.08)
	var m := _mat_glow(col, 0.9)
	m.vertex_color_use_as_albedo = false
	for c in n.get_children():
		(c as MeshInstance3D).material_override = m
	n.position = hex_pos(k) + Vector3(0, 0.02, 0)
	fx_root.add_child(n)
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 1.8, 0.8).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.8)
	tw.tween_callback(n.queue_free)


## Sbuffo di polvere quando una tessera atterra (anello chiaro che si allarga).
func fx_dust(p: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 2.4
	tm.outer_radius = 2.8
	mi.mesh = tm
	var m := _mat_glow(Color("#e8dcc0"), 0.45)
	m.vertex_color_use_as_albedo = false
	mi.material_override = m
	mi.position = p + Vector3(0, 0.05, 0)
	mi.scale = Vector3(1, 0.05, 1)
	fx_root.add_child(mi)
	var tw := create_tween()
	tw.tween_property(mi, "scale", Vector3(1.35, 0.05, 1.35), 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(m, "albedo_color:a", 0.0, 0.6)
	tw.tween_callback(mi.queue_free)
