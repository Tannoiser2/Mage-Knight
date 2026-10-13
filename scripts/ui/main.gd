class_name MKMain
extends Control
## Radice dell'applicazione: alterna il menu (MKMenu), la sala online (MKOnlineLobby, se presente) e la
## vista della partita (MKGameView) guidata da un MKController.

var current: Control
var menu_state := {}
var lobby := {}


func _ready() -> void:
	theme = MKUI.make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# niente sfondo 2D: coprirebbe il tavolo 3D (il 2D si disegna sopra al 3D)
	RenderingServer.set_default_clear_color(Color("#0b0a0d"))
	MKDB.ensure()
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


func back_to_menu() -> void:
	show_menu()


## Mostra un controllo qualsiasi a schermo intero (es. la sala online).
func show_screen(c: Control) -> void:
	_clear()
	if "main" in c:
		c.set("main", self)
	add_child(c)
	current = c


## cfg = configurazione per MKEngine.create (SPEC §4): nuova partita locale.
func start_game(cfg: Dictionary) -> void:
	var ctrl := MKController.new()
	ctrl.name = "Controller"
	MKController.clear_save()
	_open_game(ctrl, cfg)


## Apre la vista con un controllore già pronto (online: MKOnlineController già avviato o da avviare).
func start_game_with(ctrl: MKController) -> void:
	ctrl.autosave = false
	_open_game(ctrl, {})


## Riprende la partita salvata automaticamente.
func resume_game() -> bool:
	var d := MKController.load_save()
	if d.is_empty():
		return false
	var ctrl := MKController.new()
	ctrl.name = "Controller"
	if not ctrl.resume(d):
		ctrl.free()
		return false
	_open_game(ctrl, {})
	return true


func _open_game(ctrl: MKController, cfg: Dictionary) -> void:
	_clear()
	var g := MKGameView.new()
	g.name = "Game"
	g.main = self
	g.config = cfg
	if ctrl.get_parent() != null:
		ctrl.get_parent().remove_child(ctrl)
	g.add_child(ctrl)
	g.ctrl = ctrl
	add_child(g)
	current = g
	if ctrl.eng == null and not cfg.is_empty():
		ctrl.start(cfg)
