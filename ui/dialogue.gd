extends CanvasLayer
## Story dialogue overlay. Created by Main.play_dialogue(lines, on_done).
## Tap / click / ui_accept: finish the current line, or advance. "Skip" ends the scene.

const VTheme = preload("res://ui/theme.gd")
const StoryData = preload("res://data/story.gd")
const CHARS_PER_SEC := 48.0
const LEFT_SPEAKERS := ["kaela", "liora", "ysolde"]

signal finished

static var _portraits := {}

var _lines: Array = []
var _index := -1
var _on_done: Callable
var _typing := false
var _shown := 0.0
var _total := 0
var _ignore_until := 0
var _closing := false
var _last_speaker := ""

var _root: Control
var _portrait: TextureRect
var _sigil: Control
var _box: PanelContainer
var _plate: PanelContainer
var _name: Label
var _text: Label
var _arrow: Control
var _portrait_tween: Tween


class Sigil extends Control:
	## Glowing warden sigil drawn with primitives (VFX only). Rotated by a tween, not redrawn per frame.
	var col := Color.WHITE
	func _draw() -> void:
		var c := size * 0.5
		var r: float = min(size.x, size.y) * 0.5 - 6.0
		for i in 6:
			draw_circle(c, r * (1.0 - i * 0.06), Color(col.r, col.g, col.b, 0.05))
		draw_circle(c, r * 0.62, Color(0.04, 0.02, 0.05, 0.85))
		draw_arc(c, r * 0.95, 0, TAU, 64, col, 4.0, true)
		draw_arc(c, r * 0.78, 0, TAU, 48, Color(col.r, col.g, col.b, 0.6), 2.0, true)
		draw_arc(c, r * 0.6, 0, TAU, 48, col.lightened(0.3), 3.0, true)
		var pts := PackedVector2Array()
		for i in 6:
			var a := TAU * i / 6.0 - PI / 2.0
			pts.append(c + Vector2(cos(a), sin(a)) * r * 0.78)
		for i in 6:
			draw_line(pts[i], pts[(i + 2) % 6], Color(col.r, col.g, col.b, 0.75), 2.0, true)
			draw_circle(pts[i], 6.0, col.lightened(0.4))
		draw_circle(c, r * 0.16, col.lightened(0.5))
		draw_circle(c, r * 0.1, Color(1, 1, 1, 0.9))


class Arrow extends Control:
	var col := Color(1.0, 0.84, 0.46)
	func _draw() -> void:
		var w := size.x
		var h := size.y
		draw_colored_polygon(PackedVector2Array([Vector2(0, 0), Vector2(w, 0), Vector2(w * 0.5, h)]), col)


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	set_process(false)


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.theme = VTheme.get_theme()
	_root.gui_input.connect(_on_root_input)
	add_child(_root)

	# bottom shade so text reads over gameplay
	var grad := Gradient.new()
	grad.set_color(0, Color(0, 0, 0, 0))
	grad.set_color(1, Color(0.02, 0.0, 0.03, 0.9))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 4
	gt.height = 64
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	var shade := TextureRect.new()
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.anchor_left = 0; shade.anchor_right = 1; shade.anchor_top = 0.45; shade.anchor_bottom = 1
	_root.add_child(shade)

	_portrait = TextureRect.new()
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait.anchor_top = 1; _portrait.anchor_bottom = 1
	_root.add_child(_portrait)

	_sigil = Sigil.new()
	_sigil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sigil.size = Vector2(240, 240)
	_sigil.pivot_offset = Vector2(120, 120)
	_sigil.anchor_top = 1; _sigil.anchor_bottom = 1
	_sigil.visible = false
	_root.add_child(_sigil)

	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.anchor_left = 0; _box.anchor_right = 1; _box.anchor_top = 1; _box.anchor_bottom = 1
	_box.offset_left = 48; _box.offset_right = -48; _box.offset_top = -210; _box.offset_bottom = -24
	_root.add_child(_box)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.add_child(v)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_text.add_theme_font_size_override("font_size", 28)
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.visible_characters_behavior = TextServer.VC_CHARS_AFTER_SHAPING
	v.add_child(_text)

	_plate = PanelContainer.new()
	_plate.theme_type_variation = "NamePlate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.anchor_top = 1; _plate.anchor_bottom = 1
	_plate.offset_left = 80; _plate.offset_top = -238; _plate.offset_bottom = -192
	_root.add_child(_plate)
	_name = VTheme.title_label("", 28, Color.WHITE, 8)
	_plate.add_child(_name)

	_arrow = Arrow.new()
	_arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_arrow.size = Vector2(24, 16)
	_arrow.anchor_left = 1; _arrow.anchor_right = 1; _arrow.anchor_top = 1; _arrow.anchor_bottom = 1
	_arrow.offset_left = -96; _arrow.offset_top = -60; _arrow.offset_right = -72; _arrow.offset_bottom = -44
	_root.add_child(_arrow)
	var at := _arrow.create_tween().set_loops()
	at.tween_property(_arrow, "modulate:a", 0.25, 0.5)
	at.tween_property(_arrow, "modulate:a", 1.0, 0.5)

	var skip := Button.new()
	skip.text = "Skip"
	skip.theme_type_variation = "SmallButton"
	skip.custom_minimum_size = Vector2(140, 64)
	skip.focus_mode = Control.FOCUS_NONE
	skip.anchor_left = 1; skip.anchor_right = 1
	skip.offset_left = -164; skip.offset_right = -24; skip.offset_top = 20; skip.offset_bottom = 84
	skip.pressed.connect(skip_all)
	_root.add_child(skip)


## Begin a scene. lines: [{speaker, text}]
func start(lines: Array, on_done: Callable) -> void:
	_lines = lines
	_on_done = on_done
	_index = -1
	_ignore_until = Time.get_ticks_msec() + 180
	if not is_node_ready():
		await ready
	_next()


func _next() -> void:
	_index += 1
	if _index >= _lines.size():
		_finish(true)
		return
	var line = _lines[_index]
	if not (line is Dictionary):
		_next()
		return
	var sid := String(line.get("speaker", "narrator"))
	var spk: Dictionary = StoryData.speaker(sid)
	_show_speaker(sid, spk)
	_text.text = String(line.get("text", ""))
	_total = _text.get_total_character_count()
	_shown = 0.0
	_text.visible_characters = 0
	_typing = true
	_arrow.visible = false
	set_process(true)


func _show_speaker(sid: String, spk: Dictionary) -> void:
	var col: Color = spk.get("color", Color.WHITE)
	var nm := String(spk.get("name", ""))
	_plate.visible = nm != ""
	_name.text = nm
	_name.add_theme_color_override("font_color", col)
	var sb := VTheme.box(Color(0.07, 0.03, 0.08, 0.96), col, 2, 5, 8, Color(col.r, col.g, col.b, 0.3), 18, 6)
	_plate.add_theme_stylebox_override("panel", sb)
	var left := sid in LEFT_SPEAKERS
	var vp := _root.size if _root.size.x > 0 else Vector2(1280, 720)
	# name plate side
	if left:
		_plate.anchor_left = 0; _plate.anchor_right = 0
		_plate.offset_left = 80; _plate.offset_right = 80
		_plate.grow_horizontal = Control.GROW_DIRECTION_END
	else:
		_plate.anchor_left = 1; _plate.anchor_right = 1
		_plate.offset_left = -80; _plate.offset_right = -80
		_plate.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	if sid == _last_speaker:
		return
	_last_speaker = sid
	if _portrait_tween and _portrait_tween.is_valid():
		_portrait_tween.kill()
	var path := String(spk.get("portrait", ""))
	var tex: Texture2D = _get_portrait(path)
	_portrait.visible = tex != null
	_sigil.visible = tex == null and StoryData.SPEAKERS.has(sid) and sid != "narrator"
	var target: Control = null
	if tex:
		_portrait.texture = tex
		var h: float = min(520.0, vp.y * 0.78)
		var w: float = h * float(tex.get_width()) / max(1.0, float(tex.get_height()))
		_portrait.size = Vector2(w, h)
		_portrait.offset_top = -h - 150
		_portrait.offset_bottom = -150
		_portrait.flip_h = not left and sid != "regent"
		if left:
			_portrait.anchor_left = 0; _portrait.anchor_right = 0
			_portrait.offset_left = 40; _portrait.offset_right = 40 + w
		else:
			_portrait.anchor_left = 1; _portrait.anchor_right = 1
			_portrait.offset_left = -40 - w; _portrait.offset_right = -40
		target = _portrait
	elif _sigil.visible:
		(_sigil as Sigil).col = col
		_sigil.queue_redraw()
		_sigil.anchor_left = 1; _sigil.anchor_right = 1
		_sigil.offset_left = -300; _sigil.offset_right = -60
		_sigil.offset_top = -470; _sigil.offset_bottom = -230
		target = _sigil
	if target:
		var base_x := target.position.x
		target.modulate.a = 0.0
		target.position.x = base_x + (-40.0 if left else 40.0)
		_portrait_tween = create_tween().set_parallel()
		_portrait_tween.tween_property(target, "modulate:a", 1.0, 0.25)
		_portrait_tween.tween_property(target, "position:x", base_x, 0.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		if target == _sigil:
			_portrait_tween.tween_property(_sigil, "rotation", _sigil.rotation + PI / 3.0, 0.6).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _get_portrait(path: String) -> Texture2D:
	if path == "":
		return null
	if _portraits.has(path):
		return _portraits[path]
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	_portraits[path] = tex
	return tex


func _process(delta: float) -> void:
	if not _typing:
		set_process(false)
		return
	_shown += delta * CHARS_PER_SEC
	if _shown >= _total:
		_complete_line()
	else:
		_text.visible_characters = int(_shown)


func _complete_line() -> void:
	_typing = false
	_text.visible_characters = -1
	_arrow.visible = true
	set_process(false)


func advance() -> void:
	if _closing or Time.get_ticks_msec() < _ignore_until:
		return
	if _typing:
		_complete_line()
	else:
		_next()


func skip_all() -> void:
	if not _closing:
		_finish(true)


## Close without invoking on_done (used when the scene changes underneath, e.g. a run starts).
func abort() -> void:
	_finish(false)


func _finish(call_done: bool) -> void:
	if _closing:
		return
	_closing = true
	set_process(false)
	finished.emit()
	var cb := _on_done
	_on_done = Callable()
	queue_free()
	if call_done and cb.is_valid():
		cb.call()


func _on_root_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_root.accept_event()
		advance()


func _input(event: InputEvent) -> void:
	if _closing:
		return
	if event.is_action_pressed("ui_accept") and not event.is_echo():
		get_viewport().set_input_as_handled()
		advance()
