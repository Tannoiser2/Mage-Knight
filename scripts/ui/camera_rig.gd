class_name MKCameraRig
extends Node3D
## Telecamera libera intorno a un punto del tavolo: orbita (tasto destro), panoramica (sinistro su
## spazio vuoto o centrale), zoom (rotella / pizzico), tastiera Q/E R/F WASD +/- Home, due dita sul
## touch (pizzico = zoom, rotazione = orbita, trascinamento = panoramica). Movimenti morbidi.

signal moved

var cam: Camera3D
## valori obiettivo (quelli correnti li inseguono in _process)
var yaw := 0.0
var pitch := 55.0
var dist := 14.0
var target := Vector3.ZERO
var _yaw := 0.0
var _pitch := 55.0
var _dist := 14.0
var _target := Vector3.ZERO
var bounds := Rect2(-30, -30, 60, 60)      # limiti del punto mirato (piano xz)
var min_dist := 3.0
var max_dist := 48.0
var min_pitch := 20.0
var max_pitch := 88.0
var smooth := 10.0
var ground_y := 0.1
var home := {"yaw": 0.0, "pitch": 55.0, "dist": 14.0, "target": Vector3.ZERO}
## rotazione lenta automatica (sfondo del menu)
var auto_spin := 0.0

var _drag_btn := 0
var _drag_from := Vector2.ZERO
var _drag_moved := false
var _grab := Vector3.ZERO
var _touches := {}
var _pinch_d := 0.0
var _pinch_a := 0.0
var _pinch_c := Vector2.ZERO


func _ready() -> void:
	cam = Camera3D.new()
	cam.fov = 40
	cam.near = 0.05
	cam.far = 400
	add_child(cam)
	cam.current = true
	snap()


func set_home(t: Vector3, d: float, p := 55.0, y := 0.0) -> void:
	home = {"yaw": y, "pitch": p, "dist": d, "target": t}


func reset(instant := false) -> void:
	yaw = home["yaw"]
	pitch = home["pitch"]
	dist = home["dist"]
	target = home["target"]
	if instant:
		snap()


## Porta subito i valori correnti sugli obiettivi.
func snap() -> void:
	_clamp()
	_yaw = yaw
	_pitch = pitch
	_dist = dist
	_target = target
	_apply()


func _clamp() -> void:
	pitch = clampf(pitch, min_pitch, max_pitch)
	dist = clampf(dist, min_dist, max_dist)
	target.x = clampf(target.x, bounds.position.x, bounds.end.x)
	target.z = clampf(target.z, bounds.position.y, bounds.end.y)
	target.y = ground_y


func _apply() -> void:
	if cam == null:
		return
	var r := deg_to_rad(_pitch)
	var y := deg_to_rad(_yaw)
	var off := Vector3(sin(y) * cos(r), sin(r), cos(y) * cos(r)) * _dist
	cam.position = _target + off
	cam.look_at(_target, Vector3.UP)


func _process(delta: float) -> void:
	if auto_spin != 0.0:
		yaw += auto_spin * delta
	_clamp()
	var k := 1.0 - exp(-smooth * delta)
	var before := cam.global_transform if cam else Transform3D()
	# lungo l'angolo si va per la via più breve
	_yaw = lerpf(_yaw, yaw, k)
	_pitch = lerpf(_pitch, pitch, k)
	_dist = lerpf(_dist, dist, k)
	_target = _target.lerp(target, k)
	_apply()
	if cam and not cam.global_transform.is_equal_approx(before):
		moved.emit()


# ------------------------------------------------------------------ comandi

func rotate_by(dyaw: float, dpitch: float) -> void:
	yaw += dyaw
	pitch += dpitch
	_clamp()


func zoom_by(f: float) -> void:
	dist *= f
	_clamp()


## Spostamento in unità relative alla distanza (tastiera, bottoni).
func pan_by(dx: float, dz: float) -> void:
	var y := deg_to_rad(yaw)
	var right := Vector3(cos(y), 0, -sin(y))
	var fwd := Vector3(-sin(y), 0, -cos(y))
	target += (right * dx + fwd * dz) * dist * 0.12
	_clamp()


## Centra dolcemente un punto (zoom opzionale: <=0 lascia la distanza).
func focus(p: Vector3, zoom := -1.0) -> void:
	target = Vector3(p.x, ground_y, p.z)
	if zoom > 0:
		dist = zoom
	_clamp()


## Punto del piano y=ground_y sotto lo schermo.
func ground_point(sp: Vector2, y := -INF) -> Variant:
	if cam == null:
		return null
	var gy := ground_y if y == -INF else y
	var o := cam.project_ray_origin(sp)
	var d := cam.project_ray_normal(sp)
	if absf(d.y) < 0.0001:
		return null
	var t := (gy - o.y) / d.y
	if t < 0:
		return null
	return o + d * t


# ------------------------------------------------------------------ input

## Gestisce l'input della telecamera. Restituisce "click" (con la posizione in click_pos) quando
## un tocco/clic sinistro breve va interpretato come selezione, true se consumato, false altrimenti.
var click_pos := Vector2.ZERO

func handle_input(ev: InputEvent) -> Variant:
	# ---- touch a due dita
	if ev is InputEventScreenTouch:
		if ev.pressed:
			_touches[ev.index] = ev.position
		else:
			_touches.erase(ev.index)
		if _touches.size() == 2:
			_pinch_start()
			_drag_btn = 0
		return _touches.size() >= 2
	if ev is InputEventScreenDrag:
		_touches[ev.index] = ev.position
		if _touches.size() >= 2:
			_pinch_update()
			return true
		return false
	if ev is InputEventMouseButton:
		if ev.button_index == MOUSE_BUTTON_WHEEL_UP and ev.pressed:
			_zoom_at(ev.position, 0.88)
			return true
		if ev.button_index == MOUSE_BUTTON_WHEEL_DOWN and ev.pressed:
			_zoom_at(ev.position, 1.0 / 0.88)
			return true
		if ev.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			if ev.pressed:
				if _touches.size() >= 2:
					return true
				_drag_btn = ev.button_index
				_drag_from = ev.position
				_drag_moved = false
				var g = ground_point(ev.position)
				_grab = g if g != null else Vector3.ZERO
				return true
			else:
				var was := _drag_btn
				_drag_btn = 0
				if was == MOUSE_BUTTON_LEFT and ev.button_index == MOUSE_BUTTON_LEFT and not _drag_moved and _touches.size() < 2:
					click_pos = ev.position
					return "click"
				return true
	if ev is InputEventMouseMotion:
		if _drag_btn == 0 or _touches.size() >= 2:
			return false
		if not _drag_moved and ev.position.distance_to(_drag_from) < 8:
			return true
		_drag_moved = true
		if _drag_btn == MOUSE_BUTTON_RIGHT:
			rotate_by(-ev.relative.x * 0.3, ev.relative.y * 0.25)
		else:
			_grab_pan(ev.position)
		return true
	if ev is InputEventMagnifyGesture:
		_zoom_at(ev.position, 1.0 / ev.factor)
		return true
	if ev is InputEventPanGesture:
		pan_by(ev.delta.x * 0.05, -ev.delta.y * 0.05)
		return true
	if ev is InputEventKey and ev.pressed:
		match ev.keycode:
			KEY_Q:
				rotate_by(-15, 0)
			KEY_E:
				rotate_by(15, 0)
			KEY_R:
				rotate_by(0, 6)
			KEY_F:
				rotate_by(0, -6)
			KEY_W, KEY_UP:
				pan_by(0, 1)
			KEY_S, KEY_DOWN:
				pan_by(0, -1)
			KEY_A, KEY_LEFT:
				pan_by(-1, 0)
			KEY_D, KEY_RIGHT:
				pan_by(1, 0)
			KEY_EQUAL, KEY_KP_ADD, KEY_PLUS:
				zoom_by(0.85)
			KEY_MINUS, KEY_KP_SUBTRACT:
				zoom_by(1.0 / 0.85)
			KEY_HOME:
				reset()
			_:
				return false
		return true
	return false


## Panoramica «afferra la mappa»: il punto preso resta sotto il puntatore.
func _grab_pan(sp: Vector2) -> void:
	# si ragiona sulla telecamera già allineata all'obiettivo (niente ritardo durante il trascinamento)
	_yaw = yaw
	_pitch = pitch
	_dist = dist
	_target = target
	_apply()
	var g = ground_point(sp)
	if g == null:
		return
	var d: Vector3 = _grab - g
	target += Vector3(d.x, 0, d.z)
	_clamp()
	_target = target
	_apply()


## Zoom verso il punto sotto il puntatore.
func _zoom_at(sp: Vector2, f: float) -> void:
	var g = ground_point(sp)
	var old := dist
	zoom_by(f)
	if g != null and old > 0:
		var k := 1.0 - dist / old
		target += Vector3(g.x - target.x, 0, g.z - target.z) * k
		_clamp()


func _pinch_start() -> void:
	var ps: Array = _touches.values()
	var a: Vector2 = ps[0]
	var b: Vector2 = ps[1]
	_pinch_d = a.distance_to(b)
	_pinch_a = (b - a).angle()
	_pinch_c = (a + b) / 2.0
	var g = ground_point(_pinch_c)
	_grab = g if g != null else target


func _pinch_update() -> void:
	var ps: Array = _touches.values()
	var a: Vector2 = ps[0]
	var b: Vector2 = ps[1]
	var d := a.distance_to(b)
	var ang := (b - a).angle()
	var c := (a + b) / 2.0
	if _pinch_d > 1 and d > 1:
		zoom_by(_pinch_d / d)
	var da := wrapf(ang - _pinch_a, -PI, PI)
	rotate_by(-rad_to_deg(da), 0)
	# due dita in verticale insieme = inclinazione
	rotate_by(0, (c.y - _pinch_c.y) * 0.15)
	_grab_pan(c)
	_pinch_d = d
	_pinch_a = ang
	_pinch_c = c


## Barra di bottoni per il tocco (rotazione, inclinazione, zoom, centro): la mette l'HUD dove vuole.
func make_buttons(extra_home: Callable = Callable()) -> Control:
	var box := GridContainer.new()
	box.columns = 4
	box.add_theme_constant_override("h_separation", 6)
	box.add_theme_constant_override("v_separation", 6)
	var defs := [
		["⟲", "Ruota a sinistra (Q)", func(): rotate_by(-30, 0)],
		["▲", "Più dall'alto (R)", func(): rotate_by(0, 10)],
		["⟳", "Ruota a destra (E)", func(): rotate_by(30, 0)],
		["+", "Avvicina (+)", func(): zoom_by(0.75)],
		["⌂", "Vista iniziale (Home)", func():
			if extra_home.is_valid():
				extra_home.call()
			else:
				reset()],
		["▼", "Più di lato (F)", func(): rotate_by(0, -10)],
		["◎", "Centra l'eroe di turno", Callable()],
		["−", "Allontana (−)", func(): zoom_by(1.0 / 0.75)],
	]
	for d in defs:
		var b := MKUI.icon_button(d[0], d[1], 52)
		if d[2] is Callable and (d[2] as Callable).is_valid():
			b.pressed.connect(d[2])
		b.name = "cam_%d" % box.get_child_count()
		box.add_child(b)
	return box
