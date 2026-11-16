extends CanvasLayer
## Story dialogue overlay. Created by Main.play_dialogue(lines, on_done).
## Tap / click / ui_accept: finish the current line, or advance. "Skip" ends the scene.
## Large painted portraits slide in from the speaker's side; the listener stays dimmed on the other side.

const VTheme = preload("res://ui/theme.gd")
const StoryData = preload("res://data/story.gd")
const CHARS_PER_SEC := 52.0
const LEFT_SPEAKERS := ["kaela", "liora", "ysolde"]
const FULL_BODY := ["kaela", "liora", "regent"] ## shown large so only the upper body clears the text box
const PAUSE_LONG := ".!?"
const PAUSE_SHORT := ",;:—"

signal finished

var _lines: Array = []
var _index := -1
var _on_done: Callable
var _typing := false
var _shown := 0.0
var _hold := 0.0
var _total := 0
var _ignore_until := 0
var _closing := false

var _root: Control
var _slots := {"left": null, "right": null}       ## side -> TextureRect
var _slot_ids := {"left": "", "right": ""}
var _box: PanelContainer
var _plate: PanelContainer
var _name: Label
var _text: Label
var _arrow: Control
var _speaker_side := "left"


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

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.03, 0.28)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)
	var shade := VTheme.image(VTheme.vgrad_tex(Color(0.02, 0, 0.03, 0.0), Color(0.02, 0, 0.03, 0.92)), Vector2.ZERO, false)
	shade.anchor_left = 0; shade.anchor_right = 1; shade.anchor_top = 0.4; shade.anchor_bottom = 1
	_root.add_child(shade)

	for side in ["left", "right"]:
		var p := TextureRect.new()
		p.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		p.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		p.mouse_filter = Control.MOUSE_FILTER_IGNORE
		p.material = VTheme.material("fade_bottom")
		p.visible = false
		_root.add_child(p)
		_slots[side] = p

	_box = PanelContainer.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.anchor_left = 0.5; _box.anchor_right = 0.5; _box.anchor_top = 1; _box.anchor_bottom = 1
	_box.offset_left = -560; _box.offset_right = 560; _box.offset_top = -214; _box.offset_bottom = -14
	_root.add_child(_box)
	_text = Label.new()
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_text.add_theme_font_override("font", VTheme.font("body_med"))
	_text.add_theme_font_size_override("font_size", 27)
	_text.add_theme_constant_override("line_spacing", 4)
	_text.add_theme_constant_override("outline_size", 0)
	_text.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_text.visible_characters_behavior = TextServer.VC_CHARS_BEFORE_SHAPING
	_box.add_child(_text)

	_plate = PanelContainer.new()
	_plate.theme_type_variation = "Plate"
	_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_plate.anchor_left = 0.5; _plate.anchor_right = 0.5; _plate.anchor_top = 1; _plate.anchor_bottom = 1
	_plate.offset_top = -252; _plate.offset_bottom = -186
	_root.add_child(_plate)
	_name = VTheme.title_label("", 26, Color.WHITE, 6)
	_plate.add_child(_name)

	_arrow = VTheme.shard_icon(30)
	_arrow.rotation = PI * 0.5
	_arrow.anchor_left = 0.5; _arrow.anchor_right = 0.5; _arrow.anchor_top = 1; _arrow.anchor_bottom = 1
	_arrow.offset_left = 500; _arrow.offset_right = 519; _arrow.offset_top = -62; _arrow.offset_bottom = -32
	_root.add_child(_arrow)
	var at := _arrow.create_tween().set_loops()
	at.tween_property(_arrow, "position:y", 6.0, 0.45).as_relative().set_trans(Tween.TRANS_SINE)
	at.tween_property(_arrow, "position:y", -6.0, 0.45).as_relative().set_trans(Tween.TRANS_SINE)

	var skip := Button.new()
	skip.text = "Skip"
	skip.theme_type_variation = "SmallButton"
	skip.custom_minimum_size = Vector2(150, 54)
	skip.focus_mode = Control.FOCUS_NONE
	skip.anchor_left = 1; skip.anchor_right = 1
	skip.offset_left = -174; skip.offset_right = -24; skip.offset_top = 20; skip.offset_bottom = 74
	VTheme.juice(skip, 1.05, "back")
	skip.pressed.connect(skip_all)
	_root.add_child(skip)

	_root.modulate.a = 0.0
	_root.create_tween().tween_property(_root, "modulate:a", 1.0, 0.25)


## Begin a scene. lines: [{speaker, text}]
func start(lines: Array, on_done: Callable) -> void:
	_lines = lines
	_on_done = on_done
	_index = -1
	_ignore_until = Time.get_ticks_msec() + 220
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
	var narr := sid == "narrator"
	_text.text = String(line.get("text", ""))
	_text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if narr else HORIZONTAL_ALIGNMENT_LEFT
	_text.add_theme_font_override("font", VTheme.font("italic" if narr else "body_med"))
	_text.add_theme_color_override("font_color", Color(0.98, 0.9, 0.74) if narr else VTheme.TEXT)
	_total = _text.text.length()
	_shown = 0.0
	_hold = 0.0
	_text.visible_characters = 0
	_typing = true
	_arrow.visible = false
	set_process(true)


func _vp() -> Vector2:
	return get_viewport().get_visible_rect().size


func _show_speaker(sid: String, spk: Dictionary) -> void:
	var col: Color = spk.get("color", Color.WHITE)
	var nm := String(spk.get("name", ""))
	_plate.visible = nm != ""
	_name.text = nm
	_name.add_theme_color_override("font_color", col.lightened(0.2))
	_plate.add_theme_stylebox_override("panel", VTheme.plate_style(Color(1, 1, 1).lerp(col, 0.25)))
	var side := "left" if sid in LEFT_SPEAKERS else "right"
	_speaker_side = side
	var vw := _vp().x
	var bw: float = minf(1120.0, vw - 80.0)
	_box.offset_left = -bw * 0.5
	_box.offset_right = bw * 0.5
	_arrow.offset_left = bw * 0.5 - 60
	_arrow.offset_right = bw * 0.5 - 41
	var pw := maxf(300.0, _name.get_minimum_size().x + 200.0)
	if side == "left":
		_plate.offset_left = -bw * 0.5 + 30
		_plate.offset_right = -bw * 0.5 + 30 + pw
	else:
		_plate.offset_right = bw * 0.5 - 30
		_plate.offset_left = bw * 0.5 - 30 - pw
	if _plate.visible:
		_plate.pivot_offset = Vector2(pw * 0.5, 33)
		_plate.scale = Vector2(0.92, 0.92)
		_plate.create_tween().tween_property(_plate, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	var other := "right" if side == "left" else "left"
	var tex: Texture2D = VTheme.portrait_tex(sid) if sid != "narrator" else null
	# dim listener
	var op: TextureRect = _slots[other]
	if op.visible:
		op.create_tween().tween_property(op, "modulate", Color(0.42, 0.4, 0.48, 1), 0.25)
	var p: TextureRect = _slots[side]
	if tex == null:
		if p.visible:
			p.create_tween().tween_property(p, "modulate", Color(0.42, 0.4, 0.48, 1), 0.25)
		return
	if _slot_ids[side] == sid and p.visible:
		p.create_tween().tween_property(p, "modulate", Color(1, 1, 1, 1), 0.2)
		return
	_slot_ids[side] = sid
	if p.visible:
		# outgoing portrait on the same side: replace with a fresh rect so the old one can fade away
		var old := p
		var np := p.duplicate() as TextureRect
		_root.add_child(np)
		_root.move_child(np, old.get_index() + 1)
		_slots[side] = np
		p = np
		var ot := old.create_tween().set_parallel()
		ot.tween_property(old, "modulate:a", 0.0, 0.2)
		ot.tween_property(old, "position:x", old.position.x + (-60.0 if side == "left" else 60.0), 0.2)
		ot.chain().tween_callback(old.queue_free)
	p.texture = tex
	var full := sid in FULL_BODY
	p.material = VTheme.material("fade_full" if full else "fade_bottom")
	var h: float = 1010.0 if full else 640.0
	var top: float = 34.0 if full else 76.0
	var w: float = h * float(tex.get_width()) / maxf(1.0, float(tex.get_height()))
	p.size = Vector2(w, h)
	var x: float = (vw * 0.5 - bw * 0.5 - w * 0.18) if side == "left" else (vw * 0.5 + bw * 0.5 - w * 0.82)
	x = clampf(x, -w * 0.3, vw - w * 0.7)
	p.position = Vector2(x + (-90.0 if side == "left" else 90.0), top)
	p.flip_h = side == "right" and sid in ["kaela", "liora"]
	p.visible = true
	p.modulate = Color(1, 1, 1, 0)
	var tw := p.create_tween().set_parallel()
	tw.tween_property(p, "modulate", Color(1, 1, 1, 1), 0.3)
	tw.tween_property(p, "position:x", x, 0.42).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not _typing:
		set_process(false)
		return
	if _hold > 0.0:
		_hold -= delta
		return
	var before := int(_shown)
	_shown += delta * CHARS_PER_SEC
	var now := int(_shown)
	if now >= _total:
		_complete_line()
		return
	if now != before:
		_text.visible_characters = now
		var ch := _text.text[now - 1]
		var nxt := _text.text[now] if now < _total else " "
		if PAUSE_LONG.contains(ch) and nxt == " ":
			_hold = 0.26
			_shown = float(now)
		elif PAUSE_SHORT.contains(ch):
			_hold = 0.11
			_shown = float(now)


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
		VTheme.sound("click")
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
