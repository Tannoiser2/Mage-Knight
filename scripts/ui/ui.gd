class_name MKUI
extends RefCounted
## Tavolozza, font, tema e caricamento delle immagini/modelli per l'interfaccia di Mage Knight.
## Stile: fantasy scuro, accenti oro, titoli in Cinzel, testi in Barlow Condensed.
## Tutto statico: MKUI.make_theme(), MKUI.label(...), MKUI.tex(...), MKUI.tex3d(...), MKUI.mesh(...).

const GOLD := Color("#d9b45a")
const GOLD_LIGHT := Color("#f2d78c")
const GOLD_DARK := Color("#8a6d2c")
const BONE := Color("#efe3c8")
const INK := Color("#0c0b10")
const DARK := Color("#110f14")
const PANEL := Color("#16131a")
const PANEL_2 := Color("#1f1a22")
const BORDER := Color("#5c4a2c")
const RED := Color("#d8473a")
const BLOOD := Color("#8e1f1a")
const BLUE := Color("#4f8fd8")
const GREEN := Color("#6fbf5f")
const MUTED := Color("#a59c8a")

## Colori degli eroi (basetta, scudi, cornici).
const HERO_COL := {
	"arythea": Color("#c8323c"), "goldyx": Color("#3f9a4a"), "norowas": Color("#e8e2d0"),
	"tovak": Color("#3a6fc8"), "wolfhawk": Color("#7a5ac8"), "krang": Color("#c87a2a"),
	"braevalar": Color("#2aa8a0"),
}
const HERO_NAME := {
	"arythea": "Arythea", "goldyx": "Goldyx", "norowas": "Norowas", "tovak": "Tovak",
	"wolfhawk": "Wolfhawk", "krang": "Krang", "braevalar": "Braevalar",
}
## Colori dei nemici (dorso dei segnalini) per i ripieghi.
const ENEMY_COL := {
	"green": Color("#7fa03a"), "gray": Color("#8a8a8a"), "brown": Color("#8a5a2a"),
	"violet": Color("#7a4aa8"), "red": Color("#b03030"), "white": Color("#e0e0e0"),
	"ruins": Color("#d8b030"),
}
const MANA_COL := {
	"red": Color("#d8392f"), "blue": Color("#3f7fe0"), "green": Color("#3fae4a"),
	"white": Color("#f0f0f0"), "gold": Color("#f0c040"), "black": Color("#2a2a2a"),
}

const TERRAIN_IT := {
	"plains": "Pianura", "hills": "Colline", "forest": "Foresta", "wasteland": "Landa desolata",
	"desert": "Deserto", "swamp": "Palude", "lake": "Lago", "mountain": "Montagna",
	"ocean": "Oceano", "city": "Città",
}
const SITE_IT := {
	"village": "Villaggio", "monastery": "Monastero", "keep": "Fortezza", "mage_tower": "Torre magica",
	"dungeon": "Dungeon", "tomb": "Tomba", "monster_den": "Tana dei mostri",
	"spawning_grounds": "Terreno di nidificazione", "ruin": "Rovine antiche", "ruins": "Rovine antiche", "ancient_ruins": "Rovine antiche",
	"glade": "Radura magica", "magical_glade": "Radura magica", "mine": "Miniera di cristalli",
	"crystal_mine": "Miniera di cristalli", "city": "Città", "portal": "Portale",
	"rampaging": "Predoni orchi", "orcs": "Predoni orchi", "draconum": "Draconum",
	"camp": "Accampamento", "maze": "Labirinto", "labyrinth": "Labirinto",
}

static var _tex := {}
static var _mesh := {}
static var font_title: Font
static var font_body: Font
static var font_bold: Font
static var font_italic: Font


static func init_fonts() -> void:
	if font_title != null:
		return
	var fv := FontVariation.new()
	fv.base_font = load("res://assets/fonts/Cinzel.ttf")
	fv.variation_opentype = {"wght": 700}
	font_title = fv
	font_body = load("res://assets/fonts/BarlowCondensed-Medium.ttf")
	font_bold = load("res://assets/fonts/BarlowCondensed-SemiBold.ttf")
	font_italic = load("res://assets/fonts/BarlowCondensed-BoldItalic.ttf")
	# frecce e simboli (→ ▲ ♥ ✔ …) mancano nei font del gioco: sul web non ci sono font di sistema
	var sym: Font = load("res://assets/fonts/SimboliDejaVu.ttf")
	for f in [fv, font_body, font_bold, font_italic]:
		if f != null and sym != null:
			f.fallbacks = [sym]


static func norm(s) -> String:
	return str(s).strip_edges().to_lower().replace(" ", "_")


static func terrain_it(t) -> String:
	return TERRAIN_IT.get(norm(t), str(t).capitalize())


static func site_it(s) -> String:
	return SITE_IT.get(norm(s), str(s).replace("_", " ").capitalize())


static func hero_col(hero: String) -> Color:
	return HERO_COL.get(hero, GOLD)


# ------------------------------------------------------------------ file e immagini

## Percorso che esiste davvero (res:// importato o file assoluto nel container durante lo sviluppo).
static func exists(path: String) -> bool:
	if path == "":
		return false
	if path.begins_with("res://"):
		return ResourceLoader.exists(path) or FileAccess.file_exists(path)
	return FileAccess.file_exists(path)


## Primo percorso esistente tra i candidati.
static func first(paths: Array) -> String:
	for p in paths:
		if exists(str(p)):
			return str(p)
	return ""


## Texture 2D (interfaccia). Accetta res:// (importate) e percorsi assoluti (solo sviluppo).
static func tex(path: String) -> Texture2D:
	if path == "":
		return null
	if _tex.has(path):
		return _tex[path]
	var t: Texture2D = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		t = load(path)
	elif FileAccess.file_exists(path):
		var img := Image.load_from_file(path)
		if img != null and not img.is_empty():
			t = ImageTexture.create_from_image(img)
	_tex[path] = t
	return t


## Texture per il 3D: con mipmap (altrimenti le tessere viste da lontano sfarfallano) e lato massimo
## limitato. Se l'import non ha generato le mipmap le genera qui una volta sola.
static func tex3d(path: String, max_side := 2048) -> Texture2D:
	if path == "":
		return null
	var key := "3d|%s|%d" % [path, max_side]
	if _tex.has(key):
		return _tex[key]
	var t: Texture2D = null
	var img: Image = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var src: Texture2D = load(path)
		if src != null:
			img = src.get_image()
			if img != null and img.has_mipmaps() and max(img.get_width(), img.get_height()) <= max_side:
				t = src
				img = null
	elif FileAccess.file_exists(path):
		img = Image.load_from_file(path)
	if t == null and img != null and not img.is_empty():
		if img.is_compressed():
			img.decompress()
		var m: int = max(img.get_width(), img.get_height())
		if m > max_side:
			var k := float(max_side) / float(m)
			img.resize(int(img.get_width() * k), int(img.get_height() * k), Image.INTERPOLATE_LANCZOS)
		img.generate_mipmaps()
		t = ImageTexture.create_from_image(img)
	_tex[key] = t
	return t


## Manifesto degli asset (data/assets.json, scritto dall'agente WORLD) — può mancare.
static var _assets = null

static func assets() -> Dictionary:
	if _assets == null:
		_assets = {}
		for p in ["res://data/assets.json"]:
			if FileAccess.file_exists(p):
				var j = JSON.parse_string(FileAccess.get_file_as_string(p))
				if j is Dictionary:
					_assets = j
	return _assets


## Percorso dal manifesto piatto data/assets.json ("tile_c01" → "res://assets/tiles/c01.webp"); "" se manca.
static func asset(key: String) -> String:
	var v = assets().get(key, null)
	if v is String:
		return _resify(v)
	if v is Dictionary:
		for k in ["img", "path", "file"]:
			if v.get(k) is String:
				return _resify(v[k])
	return ""


## Cerca nel manifesto per sezione e id: chiave piatta "<prefisso>_<id>" (tiles→tile_, enemies→enemy_,
## models→model_) oppure sezione annidata. Restituisce "" se manca.
static func asset_path(section: String, id: String) -> String:
	var pre: String = {"tiles": "tile", "enemies": "enemy", "models": "model", "heroes": "hero_token", "ruins": "ruin"}.get(section, section)
	var flat := asset("%s_%s" % [pre, id])
	if flat != "":
		return flat
	var a := assets()
	var sec = a.get(section, null)
	if sec is Dictionary and sec.has(id):
		var v = sec[id]
		if v is String:
			return _resify(v)
		if v is Dictionary:
			for k in ["img", "path", "front", "tex", "file"]:
				if v.has(k) and v[k] is String:
					return _resify(v[k])
	return ""


static func _resify(p: String) -> String:
	if p.begins_with("res://") or p.begins_with("/"):
		return p
	return "res://" + p


static var _fixtures := {}

## Mappe id → file grezzo del modulo per lo sviluppo (tests/fixtures_ui/raw_*.json; nel web non ci sono).
static func fixture_path(kind: String, id: String) -> String:
	var v = fixture(kind, id)
	return str(v) if v is String else ""


static func fixture(kind: String, id: String) -> Variant:
	if not _fixtures.has(kind):
		_fixtures[kind] = {}
		var p := "res://tests/fixtures_ui/raw_%s.json" % kind
		if FileAccess.file_exists(p):
			var j = JSON.parse_string(FileAccess.get_file_as_string(p))
			if j is Dictionary:
				_fixtures[kind] = j
	return _fixtures[kind].get(id, null)


# ------------------------------------------------------------------ modelli OBJ

## Mesh da un file .obj: res:// importato (Godot) oppure, durante lo sviluppo, un .obj grezzo letto qui.
static func mesh(path: String) -> Mesh:
	if path == "":
		return null
	if _mesh.has(path):
		return _mesh[path]
	var m: Mesh = null
	if path.begins_with("res://") and ResourceLoader.exists(path):
		var r = load(path)
		if r is Mesh:
			m = r
		elif r is PackedScene:
			var inst: Node = r.instantiate()
			for c in inst.find_children("*", "MeshInstance3D", true, false):
				m = (c as MeshInstance3D).mesh
				break
			inst.free()
	elif FileAccess.file_exists(path):
		m = parse_obj(path)
	_mesh[path] = m
	return m


## Lettore OBJ minimale (v/vt/vn/f, triangoli o poligoni convessi) per i file grezzi del modulo.
## Usato solo come ripiego quando gli asset non sono ancora stati importati.
static func parse_obj(path: String) -> ArrayMesh:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var vs := PackedVector3Array()
	var vts := PackedVector2Array()
	var vns := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var has_n := false
	while not f.eof_reached():
		var line := f.get_line()
		if line.length() < 2:
			continue
		var c0 := line.unicode_at(0)
		if c0 == 118: # v
			var c1 := line.unicode_at(1)
			var p := line.split(" ", false)
			if c1 == 32:
				vs.append(Vector3(p[1].to_float(), p[2].to_float(), p[3].to_float()))
			elif c1 == 116:
				vts.append(Vector2(p[1].to_float(), 1.0 - p[2].to_float()))
			elif c1 == 110:
				vns.append(Vector3(p[1].to_float(), p[2].to_float(), p[3].to_float()))
		elif c0 == 102: # f
			var p2 := line.split(" ", false)
			var idx := []
			for k in range(1, p2.size()):
				idx.append(p2[k].split("/"))
			for k in range(1, idx.size() - 1):
				# OBJ antiorario → Godot vuole i triangoli in senso orario visti dal davanti
				for tri in [idx[0], idx[k + 1], idx[k]]:
					if tri.size() > 2 and tri[2] != "":
						st.set_normal(vns[int(tri[2]) - 1])
						has_n = true
					if tri.size() > 1 and tri[1] != "":
						st.set_uv(vts[int(tri[1]) - 1])
					st.add_vertex(vs[int(tri[0]) - 1])
	if not has_n:
		st.generate_normals()
	return st.commit()


# ------------------------------------------------------------------ widget

static func panel_style(bg: Color, border: Color, bw := 1, radius := 6, margin := 10) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(bw)
	sb.set_corner_radius_all(radius)
	sb.set_content_margin_all(margin)
	sb.anti_aliasing = true
	return sb


## Pannello «Mage Knight»: fondo scuro quasi opaco, bordo oro sottile, ombra.
static func frame_style(alpha := 0.92, radius := 8) -> StyleBoxFlat:
	var sb := panel_style(Color(PANEL, alpha), Color(GOLD_DARK, 0.9), 2, radius, 12)
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 10
	return sb


static func label(text: String, size := 20, col := Color("#ece4d2"), font: Font = null) -> Label:
	init_fonts()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if font != null:
		l.add_theme_font_override("font", font)
	return l


static func title(text: String, size := 40, col := GOLD) -> Label:
	init_fonts()
	var l := label(text, size, col, font_title)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", max(4, size / 8))
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_y", 3)
	return l


static func rich(size := 20) -> RichTextLabel:
	init_fonts()
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", size)
	r.add_theme_font_size_override("bold_font_size", size)
	r.add_theme_font_size_override("italics_font_size", size)
	return r


static func icon_rect(t: Texture2D, sz: Vector2) -> TextureRect:
	var r := TextureRect.new()
	r.texture = t
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.custom_minimum_size = sz
	r.size = sz
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Bottone grande (menu): Cinzel, alto almeno 64 px per il tocco.
static func big_button(text: String, w := 420.0, primary_style := false, h := 72.0) -> Button:
	init_fonts()
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(w, h)
	b.add_theme_font_override("font", font_title)
	b.add_theme_font_size_override("font_size", 28)
	if primary_style:
		primary(b)
	return b


static func primary(b: Button) -> Button:
	var n := panel_style(GOLD, GOLD_LIGHT, 2, 6)
	n.shadow_color = Color(0.85, 0.65, 0.2, 0.35)
	n.shadow_size = 8
	b.add_theme_stylebox_override("normal", n)
	var h := panel_style(GOLD_LIGHT, Color.WHITE, 2, 6)
	h.shadow_color = Color(1, 0.8, 0.3, 0.5)
	h.shadow_size = 12
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", panel_style(GOLD_DARK, GOLD_LIGHT, 2, 6))
	b.add_theme_color_override("font_color", INK)
	b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_pressed_color", BONE)
	return b


## Bottone tondo con un simbolo (comandi della telecamera, pulsanti per il tocco).
static func icon_button(sym: String, tip := "", sz := 56) -> Button:
	init_fonts()
	var b := Button.new()
	b.text = sym
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(sz, sz)
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", int(sz * 0.5))
	var n := panel_style(Color(PANEL, 0.85), Color(GOLD_DARK, 0.9), 2, sz / 2, 4)
	b.add_theme_stylebox_override("normal", n)
	var h := panel_style(Color(PANEL_2, 0.95), GOLD, 2, sz / 2, 4)
	b.add_theme_stylebox_override("hover", h)
	b.add_theme_stylebox_override("pressed", panel_style(GOLD, GOLD_LIGHT, 2, sz / 2, 4))
	b.add_theme_color_override("font_color", BONE)
	b.add_theme_color_override("font_hover_color", GOLD_LIGHT)
	b.add_theme_color_override("font_pressed_color", INK)
	return b


static func make_theme() -> Theme:
	init_fonts()
	var th := Theme.new()
	th.default_font = font_body
	th.default_font_size = 20
	var sb := panel_style(Color("#1c1720"), Color("#6b5530"), 2, 5)
	sb.content_margin_left = 14
	sb.content_margin_right = 14
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	th.set_stylebox("normal", "Button", sb)
	var sbh := sb.duplicate()
	sbh.bg_color = Color("#2c2330")
	sbh.border_color = GOLD
	th.set_stylebox("hover", "Button", sbh)
	var sbp := sb.duplicate()
	sbp.bg_color = GOLD
	sbp.border_color = GOLD_LIGHT
	th.set_stylebox("pressed", "Button", sbp)
	var sbd := sb.duplicate()
	sbd.bg_color = Color("#141117")
	sbd.border_color = Color("#3a3438")
	th.set_stylebox("disabled", "Button", sbd)
	th.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	th.set_color("font_color", "Button", BONE)
	th.set_color("font_hover_color", "Button", GOLD_LIGHT)
	th.set_color("font_pressed_color", "Button", INK)
	th.set_color("font_disabled_color", "Button", Color("#6a6460"))
	th.set_font("font", "Button", font_bold)
	th.set_font_size("font_size", "Button", 22)
	th.set_color("font_color", "Label", Color("#ece4d2"))
	var pn := StyleBoxFlat.new()
	pn.bg_color = PANEL
	pn.border_color = Color("#000000")
	pn.set_border_width_all(1)
	th.set_stylebox("panel", "Panel", pn)
	th.set_stylebox("panel", "PanelContainer", frame_style())
	th.set_font("normal_font", "RichTextLabel", font_body)
	th.set_font("bold_font", "RichTextLabel", font_bold)
	th.set_font("italics_font", "RichTextLabel", font_italic)
	th.set_font_size("normal_font_size", "RichTextLabel", 20)
	th.set_font_size("bold_font_size", "RichTextLabel", 20)
	th.set_font_size("italics_font_size", "RichTextLabel", 20)
	th.set_color("default_color", "RichTextLabel", Color("#e8e0cc"))
	th.set_font("font", "LineEdit", font_bold)
	th.set_font_size("font_size", "LineEdit", 24)
	th.set_stylebox("normal", "LineEdit", panel_style(Color("#0c0a0e"), Color("#5a4a30"), 1, 4))
	th.set_stylebox("focus", "LineEdit", panel_style(Color("#0c0a0e"), GOLD, 2, 4))
	th.set_font("font", "TooltipLabel", font_body)
	th.set_font_size("font_size", "TooltipLabel", 19)
	var tp := StyleBoxFlat.new()
	tp.bg_color = Color("#0e0c10ee")
	tp.border_color = GOLD
	tp.set_border_width_all(1)
	tp.set_content_margin_all(8)
	th.set_stylebox("panel", "TooltipPanel", tp)
	var vs := StyleBoxFlat.new()
	vs.bg_color = Color("#6b5530")
	vs.set_corner_radius_all(4)
	th.set_stylebox("grabber", "VScrollBar", vs)
	th.set_stylebox("grabber_highlight", "VScrollBar", vs)
	th.set_stylebox("grabber_pressed", "VScrollBar", vs)
	var vbg := StyleBoxFlat.new()
	vbg.bg_color = Color("#00000055")
	th.set_stylebox("scroll", "VScrollBar", vbg)
	th.set_color("font_color", "OptionButton", BONE)
	th.set_stylebox("separator", "HSeparator", _line_style())
	return th


static func _line_style() -> StyleBoxLine:
	var l := StyleBoxLine.new()
	l.color = Color(GOLD_DARK, 0.7)
	l.thickness = 1
	return l


## Sfondo sfumato verticale.
static func shade(a0 := 0.3, a1 := 0.94, col := Color(0.03, 0.02, 0.04)) -> TextureRect:
	var r := TextureRect.new()
	var grad := GradientTexture2D.new()
	var g := Gradient.new()
	g.set_color(0, Color(col, a0))
	g.set_color(1, Color(col, a1))
	grad.gradient = g
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	r.texture = grad
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Vignettatura radiale (bordi scuri), per i menu sopra al tavolo 3D.
static func vignette(strength := 0.85) -> TextureRect:
	var r := TextureRect.new()
	var grad := GradientTexture2D.new()
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.5)
	grad.fill_to = Vector2(1.05, 1.05)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.0))
	g.set_color(1, Color(0.01, 0.0, 0.02, strength))
	grad.gradient = g
	r.texture = grad
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_SCALE
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


## Linea decorativa oro (ornamento sotto i titoli).
static func ornament(w := 420.0) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(w, 18)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var y := 9.0
		var mid := w / 2.0
		c.draw_line(Vector2(0, y), Vector2(mid - 14, y), Color(GOLD, 0.0), 1.0)
		var pts := PackedVector2Array([Vector2(0, y), Vector2(mid - 16, y)])
		c.draw_polyline_colors(pts, PackedColorArray([Color(GOLD, 0.0), Color(GOLD, 0.9)]), 2.0, true)
		pts = PackedVector2Array([Vector2(mid + 16, y), Vector2(w, y)])
		c.draw_polyline_colors(pts, PackedColorArray([Color(GOLD, 0.9), Color(GOLD, 0.0)]), 2.0, true)
		var d := PackedVector2Array([Vector2(mid, y - 8), Vector2(mid + 8, y), Vector2(mid, y + 8), Vector2(mid - 8, y)])
		c.draw_colored_polygon(d, GOLD)
		var d2 := PackedVector2Array([Vector2(mid, y - 4), Vector2(mid + 4, y), Vector2(mid, y + 4), Vector2(mid - 4, y)])
		c.draw_colored_polygon(d2, INK))
	return c
