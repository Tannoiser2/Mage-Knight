class_name MKMain
extends Control
## Radice dell'applicazione: alterna il menu (MKMenu) e la vista della partita (MKGameView).

var current: Control
var menu_state := {}
var lobby := {}


func _ready() -> void:
	theme = MKUI.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# niente sfondo 2D: coprirebbe il tavolo 3D (il 2D si disegna sopra al 3D)
	RenderingServer.set_default_clear_color(Color("#0b0a0d"))
	show_menu()


func _unhandled_input(ev: InputEvent) -> void:
	if ev is InputEventKey and ev.pressed and ev.keycode == KEY_F11:
		if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		else:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


func _clear() -> void:
	if current != null:
		current.queue_free()
		current = null


func show_menu() -> void:
	_clear()
	var m := MKMenu.new()
	m.name = "Menu"
	m.main = self
	add_child(m)
	current = m


## cfg = configurazione per MKEngine.create (SPEC §4).
func start_game(cfg: Dictionary) -> void:
	_clear()
	var g := MKGameView.new()
	g.name = "Game"
	g.main = self
	g.config = cfg
	add_child(g)
	current = g
