extends RefCounted
## Veilborne UI theme, built in code. Usage:
##   const VTheme = preload("res://ui/theme.gd")
##   root_control.theme = VTheme.get_theme()
## Type variations: TitleLabel, HeaderLabel, DimLabel, BigButton, SmallButton, DangerButton, CardPanel, CardPanelSelected.

const GOLD := Color(0.86, 0.66, 0.3)
const GOLD_BRIGHT := Color(1.0, 0.84, 0.46)
const GOLD_DIM := Color(0.58, 0.43, 0.22)
const EMBER := Color(1.0, 0.48, 0.16)
const INK := Color(0.05, 0.02, 0.06)
const PANEL_BG := Color(0.085, 0.045, 0.11, 0.94)
const CARD_BG := Color(0.12, 0.06, 0.15, 0.95)
const TEXT := Color(0.95, 0.88, 0.76)
const TEXT_DIM := Color(0.72, 0.64, 0.6)
const DANGER := Color(0.85, 0.2, 0.22)

static var _theme: Theme = null
static var _title_font: Font = null

static func get_theme() -> Theme:
	if _theme == null:
		_theme = build()
	return _theme

static func title_font() -> Font:
	if _title_font == null:
		var sf := SystemFont.new()
		sf.font_names = PackedStringArray(["Cinzel Decorative", "Cinzel", "Trajan Pro", "Palatino Linotype", "Book Antiqua", "Georgia", "Noto Serif", "DejaVu Serif", "serif"])
		sf.font_weight = 700
		sf.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_title_font = sf
	return _title_font

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

static func _button_styles(t: Theme, type: String, base_bg: Color, accent: Color, mh: float, mv: float) -> void:
	t.set_stylebox("normal", type, box(base_bg, GOLD_DIM, 2, 6, 6, Color(0, 0, 0, 0.5), mh, mv))
	t.set_stylebox("hover", type, box(base_bg.lightened(0.12), GOLD_BRIGHT, 3, 6, 10, Color(accent.r, accent.g, accent.b, 0.35), mh, mv))
	t.set_stylebox("pressed", type, box(accent.darkened(0.55), EMBER, 3, 6, 4, Color(accent.r, accent.g, accent.b, 0.45), mh, mv))
	t.set_stylebox("hover_pressed", type, box(accent.darkened(0.5), GOLD_BRIGHT, 3, 6, 6, Color(accent.r, accent.g, accent.b, 0.45), mh, mv))
	t.set_stylebox("disabled", type, box(Color(0.08, 0.06, 0.09, 0.9), Color(0.3, 0.25, 0.3), 2, 6, 0, Color(0, 0, 0, 0), mh, mv))
	var f := box(Color(0, 0, 0, 0), GOLD_BRIGHT, 3, 7, 0, Color(0, 0, 0, 0), mh, mv)
	f.draw_center = false
	f.expand_margin_left = 3
	f.expand_margin_right = 3
	f.expand_margin_top = 3
	f.expand_margin_bottom = 3
	t.set_stylebox("focus", type, f)

static func build() -> Theme:
	var t := Theme.new()
	t.default_font_size = 24

	# ---- Panels
	t.set_stylebox("panel", "Panel", box(PANEL_BG, GOLD, 2, 6, 12))
	t.set_stylebox("panel", "PanelContainer", box(PANEL_BG, GOLD, 2, 6, 12, Color(0, 0, 0, 0.6), 18, 16))
	t.set_type_variation("CardPanel", "PanelContainer")
	t.set_stylebox("panel", "CardPanel", box(CARD_BG, GOLD_DIM, 2, 8, 10, Color(0, 0, 0, 0.6), 16, 14))
	t.set_type_variation("CardPanelSelected", "PanelContainer")
	t.set_stylebox("panel", "CardPanelSelected", box(Color(0.2, 0.08, 0.14, 0.97), GOLD_BRIGHT, 3, 8, 16, Color(1.0, 0.5, 0.15, 0.4), 16, 14))
	t.set_type_variation("NamePlate", "PanelContainer")
	t.set_stylebox("panel", "NamePlate", box(Color(0.07, 0.03, 0.08, 0.96), GOLD, 2, 5, 6, Color(0, 0, 0, 0.6), 18, 6))

	# ---- Labels
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", INK)
	t.set_constant("outline_size", "Label", 4)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0.45))
	t.set_constant("shadow_offset_y", "Label", 2)

	t.set_type_variation("TitleLabel", "Label")
	t.set_font("font", "TitleLabel", title_font())
	t.set_font_size("font_size", "TitleLabel", 44)
	t.set_color("font_color", "TitleLabel", GOLD_BRIGHT)
	t.set_constant("outline_size", "TitleLabel", 10)

	t.set_type_variation("HeaderLabel", "Label")
	t.set_font("font", "HeaderLabel", title_font())
	t.set_font_size("font_size", "HeaderLabel", 30)
	t.set_color("font_color", "HeaderLabel", GOLD)
	t.set_constant("outline_size", "HeaderLabel", 6)

	t.set_type_variation("DimLabel", "Label")
	t.set_font_size("font_size", "DimLabel", 20)
	t.set_color("font_color", "DimLabel", TEXT_DIM)

	# ---- Buttons
	for type in ["Button"]:
		_button_styles(t, type, Color(0.15, 0.07, 0.16, 0.96), EMBER, 22, 12)
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, GOLD_BRIGHT)
		t.set_color("font_focus_color", type, GOLD_BRIGHT)
		t.set_color("font_pressed_color", type, Color(1, 0.97, 0.9))
		t.set_color("font_hover_pressed_color", type, Color(1, 0.97, 0.9))
		t.set_color("font_disabled_color", type, Color(0.5, 0.44, 0.5))
		t.set_color("font_outline_color", type, INK)
		t.set_constant("outline_size", type, 5)
		t.set_font_size("font_size", type, 26)
		t.set_font("font", type, title_font())
		t.set_constant("h_separation", type, 10)

	t.set_type_variation("BigButton", "Button")
	t.set_font_size("font_size", "BigButton", 32)
	t.set_type_variation("SmallButton", "Button")
	t.set_font_size("font_size", "SmallButton", 22)
	t.set_type_variation("DangerButton", "Button")
	t.set_stylebox("normal", "DangerButton", box(Color(0.22, 0.05, 0.07, 0.96), Color(0.7, 0.25, 0.22), 2, 6, 6, Color(0, 0, 0, 0.5), 22, 12))
	t.set_stylebox("hover", "DangerButton", box(Color(0.36, 0.07, 0.09, 0.98), Color(1.0, 0.45, 0.35), 3, 6, 10, Color(1, 0.2, 0.1, 0.35), 22, 12))
	t.set_color("font_hover_color", "DangerButton", Color(1, 0.8, 0.7))
	t.set_font_size("font_size", "DangerButton", 22)

	# ---- LineEdit
	t.set_stylebox("normal", "LineEdit", box(Color(0.04, 0.02, 0.05, 0.95), GOLD_DIM, 2, 6, 0, Color(0, 0, 0, 0), 16, 12))
	t.set_stylebox("focus", "LineEdit", box(Color(0.06, 0.03, 0.07, 0.95), GOLD_BRIGHT, 3, 6, 0, Color(0, 0, 0, 0), 16, 12))
	t.set_stylebox("read_only", "LineEdit", box(Color(0.06, 0.04, 0.07, 0.9), Color(0.3, 0.25, 0.3), 2, 6, 0, Color(0, 0, 0, 0), 16, 12))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", GOLD_BRIGHT)
	t.set_color("selection_color", "LineEdit", Color(0.8, 0.5, 0.2, 0.4))
	t.set_color("font_placeholder_color", "LineEdit", Color(0.55, 0.48, 0.5))
	t.set_font_size("font_size", "LineEdit", 28)

	# ---- Scrollbars (thick for touch)
	var track := box(Color(0.05, 0.02, 0.06, 0.6), Color(0, 0, 0, 0), 0, 6, 0, Color(0, 0, 0, 0), 4, 4)
	var grab := box(GOLD_DIM, Color(0, 0, 0, 0), 0, 6, 0, Color(0, 0, 0, 0), 6, 6)
	var grab_hi := box(GOLD, Color(0, 0, 0, 0), 0, 6, 0, Color(0, 0, 0, 0), 6, 6)
	for sb in ["VScrollBar", "HScrollBar"]:
		t.set_stylebox("scroll", sb, track)
		t.set_stylebox("grabber", sb, grab)
		t.set_stylebox("grabber_highlight", sb, grab_hi)
		t.set_stylebox("grabber_pressed", sb, grab_hi)

	# ---- Separators / containers
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 12)
	t.set_color("font_color", "RichTextLabel", TEXT)
	t.set_color("font_outline_color", "RichTextLabel", INK)
	t.set_constant("outline_size", "RichTextLabel", 4)
	t.set_font_size("normal_font_size", "RichTextLabel", 26)
	return t

## A big outlined title label (not themed via variation, so font size is free).
static func title_label(text: String, size: int, color := GOLD_BRIGHT, outline := 12) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", title_font())
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", outline)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	l.add_theme_constant_override("shadow_offset_y", 4)
	l.add_theme_constant_override("shadow_offset_x", 0)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l
