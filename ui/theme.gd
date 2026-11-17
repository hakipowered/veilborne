extends RefCounted
## Veilborne UI kit: fonts, painted 9-slice styles, shared textures, sounds and small helpers.
##   const VTheme = preload("res://ui/theme.gd")
##   root_control.theme = VTheme.get_theme()
## Label variations: H1, H2, H3, Caps, Body, Dim, Quote, Gold
## Button variations: BigButton, SmallButton, DangerButton, GhostButton, IconButton
## Panel variations: PanelSm, Card, Plate, Ledger, Tooltip

const GOLD := Color(0.88, 0.68, 0.32)
const GOLD_BRIGHT := Color(1.0, 0.86, 0.52)
const GOLD_DIM := Color(0.6, 0.45, 0.24)
const EMBER := Color(1.0, 0.5, 0.18)
const INK := Color(0.045, 0.02, 0.05)
const TEXT := Color(0.96, 0.9, 0.8)
const TEXT_DIM := Color(0.74, 0.66, 0.6)
const DANGER := Color(0.9, 0.28, 0.24)
const PANEL_BG := Color(0.07, 0.035, 0.08, 0.96)
const CARD_BG := Color(0.11, 0.055, 0.12, 0.95)
const RARITY_TINT := [Color(0.95, 0.93, 0.88), Color(0.55, 0.78, 1.0), Color(0.86, 0.55, 1.0)]

## Type scale (canvas units; the canvas is always 720 tall).
const FS_H1 := 48
const FS_H2 := 34
const FS_H3 := 26
const FS_BODY := 23
const FS_SMALL := 20
const FS_CAPTION := 17

const UI := "res://art/ui/"

static var _theme: Theme = null
static var _fonts := {}
static var _tex := {}
static var _mats := {}


# =====================================================================  fonts

static func font(kind: String) -> Font:
	if _fonts.has(kind):
		return _fonts[kind]
	var f: Font = null
	match kind:
		"display":
			f = _fv("res://fonts/CinzelDecorative-Bold.ttf", 0, 1)
		"head":
			f = _fv("res://fonts/Cinzel.ttf", 700, 1)
		"caps":
			f = _fv("res://fonts/Cinzel.ttf", 600, 3)
		"caps_wide":
			f = _fv("res://fonts/Cinzel.ttf", 700, 6)
		"body":
			f = _fv("res://fonts/AlegreyaSans-Regular.ttf", 0, 0)
		"body_med":
			f = _fv("res://fonts/AlegreyaSans-Medium.ttf", 0, 0)
		"body_bold":
			f = _fv("res://fonts/AlegreyaSans-Bold.ttf", 0, 0)
		"italic":
			f = _fv("res://fonts/AlegreyaItalic.ttf", 500, 0)
	if f == null:
		f = ThemeDB.fallback_font
	_fonts[kind] = f
	return f


static func _fv(path: String, weight: int, spacing: int) -> Font:
	if not ResourceLoader.exists(path):
		return null
	var base: FontFile = load(path)
	if base == null:
		return null
	var v := FontVariation.new()
	v.base_font = base
	if weight > 0:
		var ts := TextServerManager.get_primary_interface()
		v.variation_opentype = {ts.name_to_tag("wght"): weight}
	if spacing != 0:
		v.spacing_glyph = spacing
	return v


# =====================================================================  textures

static func tex(name: String) -> Texture2D:
	if _tex.has(name):
		return _tex[name]
	var path := name if name.begins_with("res://") else UI + name + ".png"
	var t: Texture2D = load(path) if ResourceLoader.exists(path) else null
	_tex[name] = t
	return t

static func boon_icon(id: String) -> Texture2D:
	return tex("boon_" + id)

static func warden_tex(id: String) -> Texture2D:
	return tex("warden_" + id)

static func portrait_tex(id: String) -> Texture2D:
	## Large painted portrait for heroines / Ysolde / Regent / Wardens.
	var t := tex("hero_" + id)
	if t == null:
		t = tex("warden_" + id)
	if t == null:
		t = tex("portrait_" + id)
	return t


static func nine(name: String, l: float, t: float, r: float, b: float, cl := -1.0, ct := -1.0, cr := -1.0, cb := -1.0, modulate := Color.WHITE) -> StyleBoxTexture:
	var s := StyleBoxTexture.new()
	s.texture = tex(name)
	s.texture_margin_left = l
	s.texture_margin_top = t
	s.texture_margin_right = r
	s.texture_margin_bottom = b
	s.content_margin_left = l if cl < 0 else cl
	s.content_margin_top = t if ct < 0 else ct
	s.content_margin_right = r if cr < 0 else cr
	s.content_margin_bottom = b if cb < 0 else cb
	s.modulate_color = modulate
	return s


static func panel_style(small := false) -> StyleBoxTexture:
	if small:
		return nine("panel_sm", 56, 56, 56, 56, 34, 26, 34, 26)
	return nine("panel", 96, 96, 96, 96, 44, 40, 44, 40)


static func card_style(tint := Color.WHITE) -> StyleBoxTexture:
	return nine("card", 149, 102, 149, 92, 26, 74, 26, 30, tint)


static func plate_style(tint := Color.WHITE) -> StyleBoxTexture:
	return nine("ribbon", 104, 32, 104, 32, 96, 10, 96, 14, tint)


static func box(bg: Color, border: Color, border_w := 2, radius := 6, shadow := 8, shadow_col := Color(0, 0, 0, 0.55), margin_h := 16.0, margin_v := 12.0) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(border_w)
	s.set_corner_radius_all(radius)
	s.shadow_size = shadow
	s.shadow_color = shadow_col
	s.shadow_offset = Vector2(0, 3) if shadow > 0 else Vector2.ZERO
	s.content_margin_left = margin_h
	s.content_margin_right = margin_h
	s.content_margin_top = margin_v
	s.content_margin_bottom = margin_v
	s.anti_aliasing = true
	return s


# =====================================================================  materials

const _CIRCLE_SHADER := """
shader_type canvas_item;
uniform float feather = 0.02;
uniform float radius = 0.5;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float d = distance(UV, vec2(0.5));
	c.a *= 1.0 - smoothstep(radius - feather, radius, d);
	COLOR = c;
}
"""

const _SHINE_SHADER := """
shader_type canvas_item;
uniform float period = 6.0;
uniform float width = 0.12;
uniform float strength = 0.55;
uniform vec4 shine_color : source_color = vec4(1.0, 0.95, 0.8, 1.0);
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	float t = mod(TIME, period) / period * 2.2 - 0.6;
	float x = UV.x + (1.0 - UV.y) * 0.25;
	float band = 1.0 - smoothstep(0.0, width, abs(x - t));
	float lum = max(c.r, max(c.g, c.b));
	c.rgb += shine_color.rgb * band * strength * c.a * step(0.35, lum);
	COLOR = c;
}
"""

const _FADE_BOTTOM_SHADER := """
shader_type canvas_item;
uniform float fade_start = 0.72;
uniform float fade_end = 1.0;
uniform float dim = 1.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.a *= 1.0 - smoothstep(fade_start, fade_end, UV.y);
	c.rgb *= dim;
	COLOR = c;
}
"""

static func material(kind: String) -> ShaderMaterial:
	## Shared materials (do not set per-instance parameters on these).
	if _mats.has(kind):
		return _mats[kind]
	var sh := Shader.new()
	match kind:
		"circle": sh.code = _CIRCLE_SHADER
		"shine": sh.code = _SHINE_SHADER
		"fade_bottom", "fade_full": sh.code = _FADE_BOTTOM_SHADER
	var m := ShaderMaterial.new()
	m.shader = sh
	if kind == "fade_full":
		m.set_shader_parameter("fade_start", 0.44)
		m.set_shader_parameter("fade_end", 0.66)
	_mats[kind] = m
	return m


# =====================================================================  sound

static func sound(name: String) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var a: Node = (ml as SceneTree).root.get_node_or_null("Audio")
		if a and a.has_method("ui"):
			a.ui(name)

static func music(track: String) -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var a: Node = (ml as SceneTree).root.get_node_or_null("Audio")
		if a and a.has_method("music"):
			a.music(track)


# =====================================================================  theme

static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme


static func build() -> Theme:
	var t := Theme.new()
	t.default_font = font("body")
	t.default_font_size = FS_BODY

	# ---- panels
	t.set_stylebox("panel", "PanelContainer", panel_style())
	t.set_stylebox("panel", "Panel", panel_style())
	t.set_type_variation("PanelSm", "PanelContainer")
	t.set_stylebox("panel", "PanelSm", panel_style(true))
	t.set_type_variation("Card", "PanelContainer")
	t.set_stylebox("panel", "Card", card_style())
	t.set_type_variation("Plate", "PanelContainer")
	t.set_stylebox("panel", "Plate", plate_style())
	t.set_type_variation("Ledger", "PanelContainer")
	var led := box(Color(0.03, 0.012, 0.035, 0.55), Color(GOLD_DIM, 0.45), 1, 4, 0, Color(0, 0, 0, 0), 16, 10)
	led.border_width_left = 0
	led.border_width_right = 0
	led.border_width_top = 0
	t.set_stylebox("panel", "Ledger", led)
	t.set_type_variation("Tooltip", "PanelContainer")
	t.set_stylebox("panel", "Tooltip", panel_style(true))
	t.set_stylebox("panel", "TooltipPanel", panel_style(true))
	t.set_color("font_color", "TooltipLabel", TEXT)
	t.set_font("font", "TooltipLabel", font("body"))
	t.set_font_size("font_size", "TooltipLabel", FS_SMALL)

	# ---- labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 3)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.5))
	t.set_constant("shadow_offset_y", "Label", 2)
	t.set_constant("shadow_offset_x", "Label", 0)
	t.set_constant("line_spacing", "Label", 2)
	_label_var(t, "H1", font("head"), FS_H1, GOLD_BRIGHT, 9)
	_label_var(t, "H2", font("head"), FS_H2, GOLD_BRIGHT, 7)
	_label_var(t, "H3", font("head"), FS_H3, GOLD, 5)
	_label_var(t, "Caps", font("caps"), FS_CAPTION, GOLD, 3)
	_label_var(t, "Body", font("body"), FS_BODY, TEXT, 3)
	_label_var(t, "Dim", font("body"), FS_SMALL, TEXT_DIM, 3)
	_label_var(t, "Quote", font("italic"), FS_BODY, TEXT, 3)
	_label_var(t, "Gold", font("body_bold"), FS_BODY, GOLD_BRIGHT, 4)

	# ---- buttons (painted plates)
	var mh := 72.0
	t.set_stylebox("normal", "Button", nine("button", 72, 18, 72, 18, mh, 10, mh, 12))
	t.set_stylebox("hover", "Button", nine("button_hover", 72, 18, 72, 18, mh, 10, mh, 12))
	t.set_stylebox("pressed", "Button", nine("button_pressed", 72, 18, 72, 18, mh, 12, mh, 10))
	t.set_stylebox("hover_pressed", "Button", nine("button_pressed", 72, 18, 72, 18, mh, 12, mh, 10))
	t.set_stylebox("disabled", "Button", nine("button_disabled", 72, 18, 72, 18, mh, 10, mh, 12))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_font("font", "Button", font("caps"))
	t.set_font_size("font_size", "Button", 22)
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", GOLD_BRIGHT)
	t.set_color("font_focus_color", "Button", GOLD_BRIGHT)
	t.set_color("font_pressed_color", "Button", Color(1, 0.93, 0.8))
	t.set_color("font_hover_pressed_color", "Button", Color(1, 0.93, 0.8))
	t.set_color("font_disabled_color", "Button", Color(0.55, 0.5, 0.5))
	t.set_color("font_outline_color", "Button", INK)
	t.set_constant("outline_size", "Button", 4)
	t.set_constant("h_separation", "Button", 10)

	t.set_type_variation("BigButton", "Button")
	t.set_font_size("font_size", "BigButton", 28)
	t.set_font("font", "BigButton", font("head"))
	for sv in ["SmallButton", "DangerButton"]:
		t.set_type_variation(sv, "Button")
		var tint := Color(1.0, 0.62, 0.56) if sv == "DangerButton" else Color.WHITE
		t.set_stylebox("normal", sv, nine("button_sm", 48, 14, 48, 14, 44, 8, 44, 9, tint))
		t.set_stylebox("hover", sv, nine("button_hover_sm", 48, 14, 48, 14, 44, 8, 44, 9, tint))
		t.set_stylebox("pressed", sv, nine("button_pressed_sm", 48, 14, 48, 14, 44, 9, 44, 8, tint))
		t.set_stylebox("hover_pressed", sv, nine("button_pressed_sm", 48, 14, 48, 14, 44, 9, 44, 8, tint))
		t.set_stylebox("disabled", sv, nine("button_disabled_sm", 48, 14, 48, 14, 44, 8, 44, 9))
	t.set_font_size("font_size", "SmallButton", 18)
	for sv in ["SmallButton", "DangerButton"]:
		t.set_font("font", sv, font("caps"))
		t.set_constant("outline_size", sv, 4)
		t.set_color("font_outline_color", sv, INK)
	t.set_font_size("font_size", "DangerButton", 18)
	t.set_color("font_color", "DangerButton", Color(1, 0.78, 0.72))
	t.set_color("font_hover_color", "DangerButton", Color(1, 0.86, 0.8))

	t.set_type_variation("GhostButton", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		var e := StyleBoxEmpty.new()
		e.content_margin_left = 20
		e.content_margin_right = 20
		e.content_margin_top = 6
		e.content_margin_bottom = 6
		t.set_stylebox(st, "GhostButton", e)
	t.set_font("font", "GhostButton", font("caps_wide"))
	t.set_font_size("font_size", "GhostButton", 27)
	t.set_color("font_color", "GhostButton", Color(0.93, 0.85, 0.72))
	t.set_constant("outline_size", "GhostButton", 6)

	t.set_type_variation("IconButton", "Button")
	for st in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
		t.set_stylebox(st, "IconButton", StyleBoxEmpty.new())

	# ---- line edit
	t.set_stylebox("normal", "LineEdit", box(Color(0.03, 0.015, 0.035, 0.95), GOLD_DIM, 2, 4, 0, Color(0, 0, 0, 0), 16, 12))
	t.set_stylebox("focus", "LineEdit", box(Color(0.05, 0.025, 0.055, 0.95), GOLD_BRIGHT, 2, 4, 0, Color(0, 0, 0, 0), 16, 12))
	t.set_stylebox("read_only", "LineEdit", box(Color(0.05, 0.035, 0.06, 0.9), Color(0.3, 0.25, 0.3), 2, 4, 0, Color(0, 0, 0, 0), 16, 12))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", GOLD_BRIGHT)
	t.set_color("selection_color", "LineEdit", Color(0.8, 0.5, 0.2, 0.4))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.55, 0.48, 0.5))
	t.set_font("font", "LineEdit", font("body_med"))
	t.set_font_size("font_size", "LineEdit", 26)

	# ---- sliders
	var track := box(Color(0.02, 0.01, 0.02, 0.9), GOLD_DIM, 1, 6, 0, Color(0, 0, 0, 0), 0, 5)
	var fill := box(Color(0.85, 0.5, 0.18), Color(1, 0.8, 0.45), 1, 6, 0, Color(0, 0, 0, 0), 0, 5)
	t.set_stylebox("slider", "HSlider", track)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_icon("grabber", "HSlider", tex("rosette_sm"))
	t.set_icon("grabber_highlight", "HSlider", tex("rosette_sm"))
	t.set_constant("center_grabber", "HSlider", 1)

	# ---- scrollbars
	var strack := box(Color(0.05, 0.02, 0.06, 0.5), Color(0, 0, 0, 0), 0, 4, 0, Color(0, 0, 0, 0), 3, 3)
	var grab := box(GOLD_DIM, Color(0, 0, 0, 0), 0, 4, 0, Color(0, 0, 0, 0), 4, 4)
	var grab_hi := box(GOLD, Color(0, 0, 0, 0), 0, 4, 0, Color(0, 0, 0, 0), 4, 4)
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, strack)
		t.set_stylebox("grabber", sb, grab)
		t.set_stylebox("grabber_highlight", sb, grab_hi)
		t.set_stylebox("grabber_pressed", sb, grab_hi)

	# ---- containers / rich text
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_font("normal_font", "RichTextLabel", font("body"))
	t.set_font("italics_font", "RichTextLabel", font("italic"))
	t.set_font("bold_font", "RichTextLabel", font("body_bold"))
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", INK)
	t.set_constant("outline_size", "RichTextLabel", 3)
	t.set_font_size("normal_font_size", "RichTextLabel", FS_BODY)
	t.set_font_size("italics_font_size", "RichTextLabel", FS_BODY)
	t.set_font_size("bold_font_size", "RichTextLabel", FS_BODY)
	return t


static func _label_var(t: Theme, name: String, f: Font, size: int, col: Color, outline: int) -> void:
	t.set_type_variation(name, "Label")
	t.set_font("font", name, f)
	t.set_font_size("font_size", name, size)
	t.set_color("font_color", name, col)
	t.set_constant("outline_size", name, outline)


# =====================================================================  widgets

static func label(text: String, variation := "Body", size := 0, color := Color(0, 0, 0, 0)) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	if color.a > 0.0:
		l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


## A big outlined display label (font size is free).
static func title_label(text: String, size: int, color := GOLD_BRIGHT, outline := 10, kind := "head") -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font(kind))
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.65))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.add_theme_constant_override("shadow_outline_size", outline + 4)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


static func image(name_or_tex, size := Vector2.ZERO, keep := true) -> TextureRect:
	var r := TextureRect.new()
	r.texture = name_or_tex if name_or_tex is Texture2D else tex(String(name_or_tex))
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if keep else TextureRect.STRETCH_SCALE
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if size != Vector2.ZERO:
		r.custom_minimum_size = size
	return r


static func divider(width := 420.0, height := 36.0) -> TextureRect:
	var d := image("divider", Vector2(width, height))
	d.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	return d


static func shard_icon(size := 30.0) -> TextureRect:
	return image("shard", Vector2(size * 0.62, size))


## Gives a button hover/press feedback + sounds. Safe to call once per button.
static func juice(b: BaseButton, hover_scale := 1.04, press_sound := "click") -> void:
	b.resized.connect(func(): b.pivot_offset = b.size * 0.5)
	b.pivot_offset = b.size * 0.5
	var on_enter := func():
		if b.disabled:
			return
		sound("hover")
		_scale_to(b, hover_scale, 0.12)
	var on_exit := func():
		if not b.has_focus() and not b.is_hovered():
			_scale_to(b, 1.0, 0.15)
	b.mouse_entered.connect(on_enter)
	b.focus_entered.connect(func():
		if b.is_hovered():
			return
		on_enter.call())
	b.mouse_exited.connect(on_exit)
	b.focus_exited.connect(func(): _scale_to(b, 1.0, 0.15))
	b.button_down.connect(func(): _scale_to(b, 0.94, 0.06))
	b.button_up.connect(func(): _scale_to(b, hover_scale if (b.is_hovered() or b.has_focus()) else 1.0, 0.18, true))
	if press_sound != "":
		b.pressed.connect(func(): sound(press_sound))


static func _scale_to(c: Control, s: float, d: float, bounce := false) -> void:
	if not is_instance_valid(c) or not c.is_inside_tree():
		return
	var tw := c.create_tween()
	var p := tw.tween_property(c, "scale", Vector2(s, s), d)
	if bounce:
		p.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		p.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)


## Radial vignette texture (cached), color at the edges.
static func vignette_tex(col: Color, inner := 0.45) -> Texture2D:
	var key := "vig_%s_%.2f" % [col.to_html(), inner]
	if _tex.has(key):
		return _tex[key]
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.0))
	g.set_offset(0, inner)
	g.set_color(1, col)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.05, 1.05)
	gt.width = 128
	gt.height = 128
	_tex[key] = gt
	return gt


static func vgrad_tex(top: Color, bottom: Color, mid := Color(0, 0, 0, -1)) -> Texture2D:
	var key := "vg_%s_%s_%s" % [top.to_html(), bottom.to_html(), mid.to_html()]
	if _tex.has(key):
		return _tex[key]
	var g := Gradient.new()
	g.set_color(0, top)
	g.set_color(1, bottom)
	if mid.a >= 0.0:
		g.add_point(0.5, mid)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4
	gt.height = 128
	gt.fill_to = Vector2(0, 1)
	_tex[key] = gt
	return gt


static func roman(n: int) -> String:
	const R := ["", "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X"]
	return R[clampi(n, 0, 10)]


# ---------------------------------------------------------------- safe area / layout

## Test hook: when x >= 0 these insets (left, top, right, bottom, canvas units) replace the display's.
static var debug_insets := Vector4(-1, 0, 0, 0)


## Safe-area insets (left, top, right, bottom) in canvas units of the viewport: notches, punch holes
## and rounded corners reported by DisplayServer.get_display_safe_area(). Zero on desktop.
static func safe_insets(vp: Viewport) -> Vector4:
	if debug_insets.x >= 0.0:
		return debug_insets
	if vp == null or not OS.has_feature("mobile"):
		return Vector4.ZERO
	var win := Vector2(DisplayServer.window_get_size())
	if win.x <= 0.0 or win.y <= 0.0:
		return Vector4.ZERO
	var safe := Rect2(DisplayServer.get_display_safe_area())
	var wpos := Vector2(DisplayServer.window_get_position())
	var vis := vp.get_visible_rect().size
	var k := vis / win
	var l := (safe.position.x - wpos.x) * k.x
	var t := (safe.position.y - wpos.y) * k.y
	var r := (wpos.x + win.x - safe.end.x) * k.x
	var b := (wpos.y + win.y - safe.end.y) * k.y
	return Vector4(clampf(l, 0.0, vis.x * 0.2), clampf(t, 0.0, vis.y * 0.2), clampf(r, 0.0, vis.x * 0.2), clampf(b, 0.0, vis.y * 0.2))


## The safe rect in canvas units (the visible rect minus notch insets).
static func safe_rect(vp: Viewport) -> Rect2:
	var vis := vp.get_visible_rect()
	var i := safe_insets(vp)
	return Rect2(vis.position + Vector2(i.x, i.y), vis.size - Vector2(i.x + i.z, i.y + i.w))


## Full-rect anchors with offsets inset to the safe area; kept up to date when the window resizes
## (rotation, fold / unfold).
static func fit_safe(c: Control) -> void:
	_track_insets(c, 1.0)


## Full-rect decoration that bleeds past a safe-inset parent out to the real screen edges.
static func bleed(c: Control) -> void:
	_track_insets(c, -1.0)


static func _track_insets(c: Control, sign_: float) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	var apply := func():
		if not is_instance_valid(c) or not c.is_inside_tree():
			return
		var i := safe_insets(c.get_viewport()) * sign_
		c.offset_left = i.x; c.offset_top = i.y; c.offset_right = -i.z; c.offset_bottom = -i.w
	var hook := func():
		apply.call()
		var vp := c.get_viewport()
		if vp and not vp.size_changed.is_connected(apply):
			vp.size_changed.connect(apply)
	c.tree_entered.connect(hook)
	c.tree_exiting.connect(func():
		var vp := c.get_viewport()
		if vp and vp.size_changed.is_connected(apply):
			vp.size_changed.disconnect(apply))
	if c.is_inside_tree():
		hook.call()
