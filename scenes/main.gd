extends Node
## Veilborne front-end: title, chronicles (save slots), co-op gate, Sanctum hub, results, and run start.
## All UI is built in code. Only one screen exists at a time; the old screen fades out and is freed.

const VTheme = preload("res://ui/theme.gd")
const Settings = preload("res://ui/settings.gd")
const StoryData = preload("res://data/story.gd")
const StoryDB = preload("res://data/story_db.gd")
const DialogueScript = preload("res://ui/dialogue.gd")
const ARENA_PATH := "res://scenes/arena.gd"

const TEX_TITLE := "res://art/title.jpg"
const TEX_FLOOR := "res://art/floor_catacomb.jpg"
const GAME_VERSION := "0.3"

## Screens: title, slots, coop, connecting, sanctum, results, intro, arena
var screen := ""
var coop_kind := "" ## "", "local", "host", "join"
var p2_hero := "liora"
var arena: Node = null

var _ui_layer: CanvasLayer
var _root: Control          ## current screen root (freed on change)
var _modal: Control = null  ## confirm / message overlay
var _dialogue: CanvasLayer = null
var _connect_token := 0
var _pending_notice := ""

# sanctum widgets refreshed in place
var _shard_label: Label
var _shop_box: VBoxContainer
var _hero_tiles := {}
var _hero_info: Label
var _weapon_btns := {}
var _weapon_info: Label
var _aspect_btn: Button
var _unlock_btn: Button
var _lobby_box: VBoxContainer
var _begin_btn: Button
var _p2_label: Label
var _status_label: Label
var _mode_text := ""


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
	Settings.load_settings()
	_ui_layer = CanvasLayer.new()
	_ui_layer.layer = 10
	add_child(_ui_layer)
	Net.connection_failed.connect(_on_net_failed)
	Net.connected_ok.connect(_on_net_connected)
	Net.disconnected.connect(_on_net_disconnected)
	Net.lobby_changed.connect(_on_lobby_changed)
	show_title()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		go_back()
	elif what == NOTIFICATION_WM_CLOSE_REQUEST:
		_quit()


func _unhandled_input(event: InputEvent) -> void:
	if screen != "arena" and event.is_action_pressed("ui_cancel") and not event.is_echo():
		get_viewport().set_input_as_handled()
		go_back()


func _quit() -> void:
	if Net.online:
		Net.close()
	get_tree().quit()


## One step back through the menus (Android back button / Escape).
func go_back() -> void:
	if is_instance_valid(_dialogue):
		_dialogue.skip_all()
		return
	if is_instance_valid(_modal):
		VTheme.sound("back")
		_close_modal()
		return
	if screen != "arena":
		VTheme.sound("back")
	match screen:
		"title":
			_quit()
		"slots":
			show_title()
		"coop":
			show_slots(Game.mode)
		"connecting":
			_cancel_connect()
		"sanctum":
			_leave_sanctum()
		"results":
			show_sanctum()
		"intro":
			show_slots(Game.mode)
		"arena":
			if is_instance_valid(arena) and arena.has_method("on_back_pressed"):
				arena.on_back_pressed()


# =====================================================================  helpers

func _new_screen(name_: String) -> Control:
	_close_modal()
	if is_instance_valid(_root):
		var old := _root
		old.name = "Old_" + old.name
		_disable_input(old)
		var tw := old.create_tween()
		tw.tween_property(old, "modulate:a", 0.0, 0.22)
		tw.tween_callback(old.queue_free)
	_shard_label = null
	_shop_box = null
	_hero_tiles = {}
	_hero_info = null
	_weapon_info = null
	_weapon_btns = {}
	_lobby_box = null
	_begin_btn = null
	_p2_label = null
	_status_label = null
	screen = name_
	_ui_layer.visible = true
	_root = Control.new()
	_root.name = "Screen_" + name_
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.theme = VTheme.get_theme()
	_ui_layer.add_child(_root)
	return _root


func _disable_input(c: Node) -> void:
	if c is Control:
		(c as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
		(c as Control).focus_mode = Control.FOCUS_NONE
	for ch in c.get_children():
		_disable_input(ch)


func _bg(parent: Control, path: String, dim: float, drift := false) -> TextureRect:
	var r := ColorRect.new()
	r.color = Color(0.04, 0.025, 0.055)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	var tex := VTheme.tex(path)
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = Color(dim, dim * 0.97, dim * 1.02)
	parent.add_child(tr)
	if drift:
		# Oversize and slowly pan: the furthest parallax layer.
		tr.anchor_left = -0.04; tr.anchor_right = 1.04; tr.anchor_top = -0.04; tr.anchor_bottom = 1.04
		var tw := tr.create_tween().set_loops()
		tw.tween_property(tr, "position", Vector2(-22, -10), 14.0).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(tr, "position", Vector2(22, 10), 14.0).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tr


func _vignette(parent: Control, top_a: float, bottom_a: float, radial := 0.75) -> void:
	var tr := VTheme.image(VTheme.vgrad_tex(Color(0.03, 0.01, 0.04, top_a), Color(0.03, 0.01, 0.04, bottom_a), Color(0.03, 0.01, 0.04, min(top_a, bottom_a) * 0.25)), Vector2.ZERO, false)
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(tr)
	if radial > 0.0:
		var v := VTheme.image(VTheme.vignette_tex(Color(0.02, 0.0, 0.03, radial), 0.5), Vector2.ZERO, false)
		v.set_anchors_preset(Control.PRESET_FULL_RECT)
		parent.add_child(v)


func _embers(parent: Control, amount := 34, near := false) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = VTheme.tex("dot")
	p.amount = amount
	p.lifetime = 9.0 if not near else 6.0
	p.preprocess = 8.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	var w := _vw()
	p.emission_rect_extents = Vector2(w * 0.55, 10)
	p.position = Vector2(w * 0.5, 740)
	p.direction = Vector2(0.15, -1)
	p.spread = 22.0
	p.gravity = Vector2(4, -5)
	p.initial_velocity_min = 22.0 if not near else 50.0
	p.initial_velocity_max = 55.0 if not near else 95.0
	p.angular_velocity_min = -40
	p.angular_velocity_max = 40
	p.orbit_velocity_min = -0.01
	p.orbit_velocity_max = 0.01
	p.scale_amount_min = 0.08 if not near else 0.16
	p.scale_amount_max = 0.18 if not near else 0.34
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.75, 0.35, 0.0))
	ramp.add_point(0.12, Color(1.0, 0.68, 0.28, 0.95))
	ramp.add_point(0.7, Color(1.0, 0.42, 0.14, 0.6))
	ramp.set_color(ramp.get_point_count() - 1, Color(0.9, 0.2, 0.08, 0.0))
	p.color_ramp = ramp
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	p.material = mat
	parent.add_child(p)
	return p


func _vw() -> float:
	return get_viewport().get_visible_rect().size.x


func _button(text: String, cb: Callable, variation := "", min_w := 280.0, sound := "click") -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	var h := 64.0
	if variation == "BigButton":
		h = 76.0
	elif variation == "SmallButton" or variation == "DangerButton":
		h = 54.0
	b.custom_minimum_size = Vector2(min_w, h)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	VTheme.juice(b, 1.04, sound)
	b.pressed.connect(cb)
	return b


func _label(text: String, variation := "Body", size := 0) -> Label:
	return VTheme.label(text, variation, size)


func _margin(parent: Control, l: int, t: int, r: int, b: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_theme_constant_override("margin_left", l)
	m.add_theme_constant_override("margin_top", t)
	m.add_theme_constant_override("margin_right", r)
	m.add_theme_constant_override("margin_bottom", b)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(m)
	return m


func _fade_in(c: Control, dur := 0.35) -> void:
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, dur)


## Rise-in animation for a list of controls (staggered). Uses scale + fade only, so it never
## fights container layout (positions inside containers are owned by the container).
func _rise_in(items: Array, delay := 0.0, step := 0.07, _dist := 40.0) -> void:
	var i := 0
	for c in items:
		if not (c is Control):
			continue
		var ctl: Control = c
		ctl.modulate.a = 0.0
		ctl.scale = Vector2(0.94, 0.94)
		ctl.resized.connect(func(): ctl.pivot_offset = Vector2(ctl.size.x * 0.5, ctl.size.y))
		var tw := ctl.create_tween().set_parallel()
		tw.tween_property(ctl, "modulate:a", 1.0, 0.35).set_delay(delay + i * step)
		tw.tween_property(ctl, "scale", Vector2.ONE, 0.45).set_delay(delay + i * step).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		i += 1


func _focus_first(b: Control) -> void:
	if is_instance_valid(b):
		b.call_deferred("grab_focus")


## Header: back button, centered title with divider, optional right widget.
func _header(parent: Control, title: String, back_cb: Callable, right: Control = null) -> Control:
	var top := Control.new()
	top.custom_minimum_size = Vector2(0, 96)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(top)
	var t := VTheme.title_label(title, VTheme.FS_H1, VTheme.GOLD_BRIGHT, 9)
	t.set_anchors_preset(Control.PRESET_CENTER_TOP)
	t.anchor_left = 0.0; t.anchor_right = 1.0
	t.offset_left = 0; t.offset_right = 0; t.offset_top = -2; t.offset_bottom = 58
	top.add_child(t)
	var d := VTheme.divider(460, 34)
	d.anchor_left = 0.5; d.anchor_right = 0.5
	d.offset_left = -230; d.offset_right = 230; d.offset_top = 56; d.offset_bottom = 90
	top.add_child(d)
	if back_cb.is_valid():
		var b := _button("Back", back_cb, "SmallButton", 150, "back")
		b.position = Vector2(0, 8)
		top.add_child(b)
	if right:
		right.anchor_left = 1.0; right.anchor_right = 1.0
		right.grow_horizontal = Control.GROW_DIRECTION_BEGIN
		right.offset_top = 4
		top.add_child(right)
	return top


# =====================================================================  modal overlays

func _close_modal() -> void:
	if is_instance_valid(_modal):
		var m := _modal
		_disable_input(m)
		var tw := m.create_tween()
		tw.tween_property(m, "modulate:a", 0.0, 0.15)
		tw.tween_callback(m.queue_free)
	_modal = null


func _modal_shell(content: Control) -> Control:
	_close_modal()
	var m := Control.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.theme = VTheme.get_theme()
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.03, 0.74)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	center.add_child(content)
	_ui_layer.add_child(m)
	_modal = m
	_fade_in(m, 0.18)
	content.resized.connect(func(): content.pivot_offset = content.size * 0.5)
	content.scale = Vector2(0.9, 0.9)
	content.create_tween().tween_property(content, "scale", Vector2.ONE, 0.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	VTheme.sound("open")
	return m


func _open_modal(title: String, body: String, buttons: Array) -> void:
	## buttons: [[text, Callable, variation]]
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(600, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	panel.add_child(v)
	var t := _label(title, "H2")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(VTheme.divider(360, 30))
	var bl := _label(body, "Body")
	bl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	bl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bl.custom_minimum_size = Vector2(520, 0)
	v.add_child(bl)
	var h := HBoxContainer.new()
	h.alignment = BoxContainer.ALIGNMENT_CENTER
	h.add_theme_constant_override("separation", 20)
	v.add_child(h)
	var first: Button = null
	for spec in buttons:
		var cb: Callable = spec[1]
		var b := _button(spec[0], func():
			_close_modal()
			cb.call(), spec[2] if spec.size() > 2 else "", 220)
		h.add_child(b)
		if first == null:
			first = b
	_modal_shell(panel)
	_focus_first(first)


func show_message(title: String, body: String) -> void:
	_open_modal(title, body, [["Understood", func(): pass]])


func show_settings() -> void:
	var p := Settings.build_panel(func():
		_modal = null
		_close_modal())
	var m := _modal_shell(p)
	p.tree_exited.connect(func():
		if is_instance_valid(m):
			if _modal == m:
				_modal = null
			m.queue_free()
		if screen == "title" and is_instance_valid(_root):
			var f := _root.find_child("Menu_Settings", true, false)
			if f: _focus_first(f))


func _version() -> String:
	var up := get_node_or_null("/root/Updater")
	if up and up.get_script():
		var cm: Dictionary = up.get_script().get_script_constant_map()
		if cm.has("VERSION_NAME"):
			return String(cm["VERSION_NAME"])
	return GAME_VERSION


func show_about() -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(700, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var logo := VTheme.image("logo", Vector2(380, 100))
	logo.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(logo)
	var sub := _label("An original co-op descent beneath the Shattered Veil", "Quote", 22)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(VTheme.divider(380, 28))
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.scroll_active = false
	body.custom_minimum_size = Vector2(620, 0)
	body.add_theme_font_size_override("normal_font_size", 20)
	body.add_theme_font_size_override("italics_font_size", 20)
	body.add_theme_font_size_override("bold_font_size", 20)
	body.text = "[center]Version %s\n[b][color=#ffd98a]Design, code & art direction[/color][/b]  Veilborne team\n[b][color=#ffd98a]Typefaces[/color][/b]  Cinzel & Cinzel Decorative by Natanael Gama; Alegreya & Alegreya Sans by Huerta Tipográfica. SIL Open Font License 1.1.\n[b][color=#ffd98a]Engine[/color][/b]  Godot Engine (MIT)\n[i]All characters, places and Wardens are original creations.[/i][/center]" % _version()
	v.add_child(body)
	var b := _button("Close", func(): _close_modal(), "", 240, "back")
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(b)
	_modal_shell(panel)
	_focus_first(b)


# =====================================================================  1. title

func show_title() -> void:
	coop_kind = ""
	var r := _new_screen("title")
	VTheme.music("title")
	_bg(r, TEX_TITLE, 0.95, true)
	# mid layer: drifting mist bands (parallax), cheap tweened textures
	for i in 2:
		var fog := VTheme.image(VTheme.vgrad_tex(Color(0.5, 0.35, 0.7, 0.0), Color(0.5, 0.35, 0.7, 0.0), Color(0.55, 0.4, 0.75, 0.16 - i * 0.05)), Vector2.ZERO, false)
		fog.anchor_left = -0.2; fog.anchor_right = 1.2
		fog.anchor_top = 0.42 + i * 0.2; fog.anchor_bottom = 0.78 + i * 0.2
		r.add_child(fog)
		var tw := fog.create_tween().set_loops()
		var dx := 70.0 if i == 0 else -110.0
		tw.tween_property(fog, "position:x", dx, 9.0 + i * 3.0).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(fog, "position:x", -dx, 9.0 + i * 3.0).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_embers(r, 28, false)
	_vignette(r, 0.45, 0.92, 0.8)
	_embers(r, 10, true)

	# logo reveal
	var logo := VTheme.image("logo", Vector2.ZERO)
	logo.material = VTheme.material("shine")
	logo.anchor_left = 0.5; logo.anchor_right = 0.5
	logo.offset_left = -400; logo.offset_right = 400; logo.offset_top = 34; logo.offset_bottom = 248
	r.add_child(logo)
	logo.pivot_offset = Vector2(400, 107)
	logo.modulate.a = 0.0
	logo.scale = Vector2(1.18, 1.18)
	var lt := logo.create_tween().set_parallel()
	lt.tween_property(logo, "modulate:a", 1.0, 1.1).set_delay(0.15)
	lt.tween_property(logo, "scale", Vector2.ONE, 1.6).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)

	var sub := VTheme.title_label("DESCENT BENEATH THE SHATTERED VEIL", 19, Color(0.96, 0.84, 0.66), 5, "caps_wide")
	sub.anchor_left = 0; sub.anchor_right = 1
	sub.offset_top = 236; sub.offset_bottom = 266
	r.add_child(sub)
	var div := VTheme.divider(520, 40)
	div.anchor_left = 0.5; div.anchor_right = 0.5
	div.offset_left = -260; div.offset_right = 260; div.offset_top = 262; div.offset_bottom = 302
	r.add_child(div)
	for c in [sub, div]:
		c.modulate.a = 0.0
		c.create_tween().tween_property(c, "modulate:a", 1.0, 0.8).set_delay(0.9)

	# menu, over a soft pool of shadow so it reads on top of the key art
	var pool := VTheme.image(VTheme.vignette_tex(Color(0, 0, 0, 0), 0.0), Vector2.ZERO, false)
	var pg := Gradient.new()
	pg.set_color(0, Color(0.02, 0.0, 0.03, 0.72))
	pg.set_color(1, Color(0.02, 0.0, 0.03, 0.0))
	var pgt := GradientTexture2D.new()
	pgt.gradient = pg
	pgt.fill = GradientTexture2D.FILL_RADIAL
	pgt.fill_from = Vector2(0.5, 0.5)
	pgt.fill_to = Vector2(0.5, 0.0)
	pool.texture = pgt
	pool.anchor_left = 0.5; pool.anchor_right = 0.5; pool.anchor_top = 1; pool.anchor_bottom = 1
	pool.offset_left = -420; pool.offset_right = 420; pool.offset_top = -420; pool.offset_bottom = 20
	r.add_child(pool)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.anchor_left = 0.5; v.anchor_right = 0.5; v.anchor_top = 1; v.anchor_bottom = 1
	v.offset_left = -240; v.offset_right = 240; v.offset_top = -372; v.offset_bottom = -36
	r.add_child(v)
	var items := [
		["Solo Descent", func(): show_slots("solo"), "Solo"],
		["Co-op Descent", func(): show_slots("coop"), "Coop"],
		["Settings", show_settings, "Settings"],
		["About", show_about, "About"],
		["Quit", _quit, "Quit"],
	]
	var made: Array = []
	for it in items:
		var mi := _menu_item(it[0], it[1])
		mi.name = "Menu_" + String(it[2])
		v.add_child(mi)
		made.append(mi)
	_rise_in(made, 1.0, 0.08, 26)

	var ver := _label("AN ORIGINAL TALE OF THE VEIL", "Caps", 13)
	ver.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	ver.anchor_left = 1; ver.anchor_right = 1; ver.anchor_top = 1; ver.anchor_bottom = 1
	ver.offset_left = -500; ver.offset_top = -32; ver.offset_right = -22; ver.offset_bottom = -8
	ver.modulate.a = 0.75
	r.add_child(ver)
	_fade_in(r, 0.6)
	_focus_first(made[0])
	if _pending_notice != "":
		var n := _pending_notice
		_pending_notice = ""
		show_message("The Veil Wavers", n)


## Title menu entry: engraved caps text; gold flourish blooms beneath on hover/focus.
func _menu_item(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text.to_upper()
	b.theme_type_variation = "GhostButton"
	b.custom_minimum_size = Vector2(480, 60)
	b.focus_mode = Control.FOCUS_ALL
	var glow := VTheme.image(VTheme.vignette_tex(Color(0, 0, 0, 0), 0.0), Vector2.ZERO, false)
	# soft ember halo behind text (radial gradient inverted: bright center)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.55, 0.2, 0.32))
	g.set_color(1, Color(1.0, 0.45, 0.15, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	gt.width = 64
	gt.height = 64
	glow.texture = gt
	glow.set_anchors_preset(Control.PRESET_FULL_RECT)
	glow.offset_left = 30; glow.offset_right = -30; glow.offset_top = -6; glow.offset_bottom = 6
	glow.modulate.a = 0.0
	glow.show_behind_parent = true
	b.add_child(glow)
	var flo := VTheme.divider(300, 26)
	flo.anchor_left = 0.5; flo.anchor_right = 0.5; flo.anchor_top = 1; flo.anchor_bottom = 1
	flo.offset_left = -150; flo.offset_right = 150; flo.offset_top = -18; flo.offset_bottom = 8
	flo.pivot_offset = Vector2(150, 13)
	flo.scale = Vector2(0.2, 1)
	flo.modulate.a = 0.0
	b.add_child(flo)
	var on := func():
		var tw := b.create_tween().set_parallel()
		tw.tween_property(flo, "modulate:a", 1.0, 0.18)
		tw.tween_property(flo, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(glow, "modulate:a", 1.0, 0.2)
	var off := func():
		if b.has_focus() or b.is_hovered():
			return
		var tw := b.create_tween().set_parallel()
		tw.tween_property(flo, "modulate:a", 0.0, 0.2)
		tw.tween_property(flo, "scale", Vector2(0.2, 1), 0.2)
		tw.tween_property(glow, "modulate:a", 0.0, 0.2)
	b.focus_entered.connect(on)
	b.mouse_entered.connect(func():
		b.grab_focus())
	b.focus_exited.connect(off)
	b.mouse_exited.connect(off)
	VTheme.juice(b, 1.06, "confirm")
	b.pressed.connect(cb)
	return b


# =====================================================================  2. chronicles (slots)

func show_slots(mode: String) -> void:
	if Net.online:
		Net.close()
	Game.mode = mode
	var r := _new_screen("slots")
	VTheme.music("title")
	_bg(r, TEX_TITLE, 0.32, true)
	_vignette(r, 0.55, 0.85, 0.7)
	_embers(r, 16)
	var m := _margin(r, 32, 22, 32, 18)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	m.add_child(v)
	_header(v, "Solo Chronicles" if mode == "solo" else "Co-op Chronicles", show_title)
	var hint := _label("Choose a chronicle. Each keeps its own shards, vows and story." if mode == "solo" else "Co-op chronicles are kept apart from solo ones. Shards and vows travel with you.", "Quote", 21)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_color", Color(0.9, 0.82, 0.72))
	v.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 30)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var first: Button = null
	var cards: Array = []
	for i in Game.SLOT_COUNT:
		var res: Array = _chronicle(row, mode, i)
		cards.append(res[0])
		if first == null:
			first = res[1]
	_rise_in(cards, 0.1, 0.09, 50)
	_fade_in(r)
	_focus_first(first)


func _chronicle(parent: Control, mode: String, i: int) -> Array:
	var d: Dictionary = Game.peek_slot(mode, i)
	var empty := d.is_empty()
	var card := VBoxContainer.new()
	card.custom_minimum_size = Vector2(380, 0)
	card.add_theme_constant_override("separation", 0)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(card)

	# the tome
	var top := Control.new()
	top.custom_minimum_size = Vector2(380, 268)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(top)
	var halo := VTheme.image(VTheme.vignette_tex(Color(0, 0, 0, 0), 0.0), Vector2.ZERO, false)
	var g := Gradient.new()
	g.set_color(0, Color(1.0, 0.6, 0.25, 0.0 if empty else 0.35))
	g.set_color(1, Color(1.0, 0.5, 0.2, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	halo.texture = gt
	halo.position = Vector2(40, -10)
	halo.size = Vector2(300, 280)
	top.add_child(halo)
	var tome := VTheme.image("tome", Vector2.ZERO)
	tome.position = Vector2(100, 0)
	tome.size = Vector2(180, 246)
	tome.pivot_offset = Vector2(90, 123)
	if empty:
		tome.modulate = Color(0.42, 0.38, 0.44)
	top.add_child(tome)
	var plate := PanelContainer.new()
	plate.theme_type_variation = "Plate"
	plate.position = Vector2(40, 196)
	plate.size = Vector2(300, 68)
	plate.custom_minimum_size = Vector2(300, 68)
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if empty:
		plate.self_modulate = Color(0.6, 0.55, 0.6)
	top.add_child(plate)
	var pl := VTheme.title_label("Chronicle %s" % VTheme.roman(i + 1), 24, VTheme.GOLD_BRIGHT if not empty else Color(0.85, 0.78, 0.7), 5)
	plate.add_child(pl)

	var info := PanelContainer.new()
	info.theme_type_variation = "PanelSm"
	info.custom_minimum_size = Vector2(380, 150)
	card.add_child(info)
	var main_btn: Button
	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 10)
	if empty:
		var e := _label("An unwritten chronicle.\nThe Veil awaits a new tale.", "Quote", 21)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		e.add_theme_color_override("font_color", VTheme.TEXT_DIM)
		info.add_child(e)
		main_btn = _button("Begin Anew", func(): _select_slot(mode, i), "BigButton", 300, "confirm")
		actions.add_child(main_btn)
	else:
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 26)
		grid.add_theme_constant_override("v_separation", 2)
		info.add_child(grid)
		var hero_id := String(d.get("last_hero", "kaela"))
		var hero_name: String = String(Game.HEROES.get(hero_id, {}).get("name", hero_id)).split(" ")[0]
		_stat_cell(grid, "Heroine", hero_name, StoryData.speaker(hero_id).get("color", VTheme.GOLD_BRIGHT))
		_stat_cell(grid, "Veil Shards", str(int(d.get("shards", 0))))
		_stat_cell(grid, "Descents", str(int(d.get("runs", 0))))
		_stat_cell(grid, "Victories", str(int(d.get("wins", 0))))
		_stat_cell(grid, "Deepest", "Chamber %d" % int(d.get("best_room", 0)))
		var lp := String(d.get("last_played", "")).replace("T", " ")
		_stat_cell(grid, "Last read", lp.substr(0, 10) if lp != "" else "-")
		main_btn = _button("Continue", func(): _select_slot(mode, i), "BigButton", 230, "confirm")
		actions.add_child(main_btn)
		var del := _button("Erase", func(): _confirm_delete(mode, i), "DangerButton", 120, "click")
		del.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		actions.add_child(del)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 12)
	card.add_child(gap)
	card.add_child(actions)
	# lift the tome when its button is hovered / focused
	var lift := func(up: bool):
		var tw := tome.create_tween().set_parallel()
		tw.tween_property(tome, "position:y", -10.0 if up else 0.0, 0.25).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(tome, "rotation", -0.03 if up else 0.0, 0.25)
		tw.tween_property(halo, "modulate:a", 1.6 if up else 1.0, 0.25)
	main_btn.focus_entered.connect(lift.bind(true))
	main_btn.focus_exited.connect(lift.bind(false))
	return [card, main_btn]


func _stat_cell(grid: GridContainer, k: String, val: String, col := VTheme.GOLD_BRIGHT) -> void:
	var c := VBoxContainer.new()
	c.add_theme_constant_override("separation", -4)
	c.custom_minimum_size = Vector2(150, 0)
	grid.add_child(c)
	c.add_child(_label(k.to_upper(), "Caps", 14))
	var vl := _label(val, "Gold", 22)
	vl.add_theme_color_override("font_color", col)
	c.add_child(vl)


func _confirm_delete(mode: String, i: int) -> void:
	_open_modal("Erase Chronicle %s?" % VTheme.roman(i + 1),
		"Every shard, vow and memory in this chronicle will be lost to the Veil. This cannot be undone.",
		[["Erase", func():
			Game.delete_slot(mode, i)
			show_slots(mode), "DangerButton"],
		["Keep it", func(): pass]])


func _select_slot(mode: String, i: int) -> void:
	Game.load_slot(mode, i)
	if not bool(Game.data.get("intro_seen", false)):
		var r := _new_screen("intro")
		_bg(r, TEX_TITLE, 0.4, true)
		_vignette(r, 0.5, 0.9)
		play_dialogue(StoryData.INTRO, func():
			Game.data["intro_seen"] = true
			Game.save_slot()
			_after_slot())
	else:
		_after_slot()


func _after_slot() -> void:
	if Game.mode == "coop":
		show_coop()
	else:
		show_sanctum()


# =====================================================================  3. co-op gate

func show_coop() -> void:
	if Net.online:
		Net.close()
	coop_kind = ""
	var r := _new_screen("coop")
	_bg(r, TEX_TITLE, 0.28, true)
	_vignette(r, 0.6, 0.85, 0.7)
	_embers(r, 16)
	var m := _margin(r, 32, 22, 32, 18)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	_header(v, "Gather Your Companion", func(): show_slots("coop"))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 22)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)

	var local := _mode_card(row, "glyph_attack", "Same Device", "Two heroines, one screen. Player 2 plays with a gamepad, or the arrow keys with comma, period and slash.")
	var lb := _button("Play Local", _start_local, "BigButton", 290, "confirm")
	lb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	local.add_child(lb)

	var host := _mode_card(row, "glyph_special", "Host", "Open the Sanctum gate on this device. Friends on the same Wi-Fi join with your address.")
	var hb := _button("Host Game", _start_host, "BigButton", 290, "confirm")
	hb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	host.add_child(hb)

	var join := _mode_card(row, "glyph_dash", "Join", "Enter the address shown on the host's Sanctum screen.")
	var ip := LineEdit.new()
	ip.placeholder_text = "192.168.1.20"
	ip.text = String(Game.data.get("last_ip", ""))
	ip.custom_minimum_size = Vector2(290, 58)
	ip.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	ip.text_submitted.connect(func(s: String): _start_join(s))
	join.add_child(ip)
	var jb := _button("Join Game", func(): _start_join(ip.text), "BigButton", 290, "confirm")
	jb.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	join.add_child(jb)
	_rise_in(row.get_children(), 0.05, 0.08, 40)
	_fade_in(r)
	_focus_first(lb)


func _mode_card(parent: Control, glyph: String, title: String, desc: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = Vector2(380, 440)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	card.add_child(v)
	var medal := Control.new()
	medal.custom_minimum_size = Vector2(0, 104)
	medal.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(medal)
	var orb := VTheme.image("orb")
	orb.anchor_left = 0.5; orb.anchor_right = 0.5
	orb.offset_left = -52; orb.offset_right = 52; orb.offset_top = 0; orb.offset_bottom = 104
	medal.add_child(orb)
	var gl := VTheme.image(glyph)
	gl.anchor_left = 0.5; gl.anchor_right = 0.5
	gl.offset_left = -34; gl.offset_right = 34; gl.offset_top = 18; gl.offset_bottom = 86
	medal.add_child(gl)
	var t := _label(title, "H3")
	t.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var d := _label(desc, "Body", 21)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.custom_minimum_size = Vector2(290, 0)
	d.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(d)
	return v


func _my_hero() -> String:
	var h := String(Game.data.get("last_hero", "kaela"))
	return h if Game.HEROES.has(h) else "kaela"


func _other_hero(h: String) -> String:
	for k in Game.HEROES.keys():
		if k != h:
			return k
	return h


func _start_local() -> void:
	coop_kind = "local"
	p2_hero = _other_hero(_my_hero())
	show_sanctum()


func _start_host() -> void:
	var err: Error = Net.host_game(_my_hero())
	if err != OK:
		show_message("The Gate Will Not Open", "Could not host on port %d (error %d). Another game may be using it." % [Net.PORT, err])
		return
	coop_kind = "host"
	show_sanctum()


func _start_join(ip: String) -> void:
	ip = ip.strip_edges()
	if ip == "":
		show_message("No Address", "Enter the host's address, for example 192.168.1.20.")
		return
	var err: Error = Net.join_game(ip, _my_hero())
	if err != OK:
		show_message("Cannot Reach the Gate", "Could not start a connection to %s (error %d)." % [ip, err])
		return
	Game.data["last_ip"] = ip
	Game.save_slot()
	coop_kind = "join"
	_connect_token += 1
	var token := _connect_token
	var r := _new_screen("connecting")
	_bg(r, TEX_TITLE, 0.25, true)
	_vignette(r, 0.6, 0.85)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(560, 0)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var ringbox := Control.new()
	ringbox.custom_minimum_size = Vector2(0, 120)
	v.add_child(ringbox)
	var ring := VTheme.image("ring")
	ring.anchor_left = 0.5; ring.anchor_right = 0.5
	ring.offset_left = -60; ring.offset_right = 60; ring.offset_bottom = 120
	ring.pivot_offset = Vector2(60, 60)
	ringbox.add_child(ring)
	ring.create_tween().set_loops().tween_property(ring, "rotation", TAU, 6.0).as_relative()
	var t := _label("Crossing the Veil...", "H2")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l := _label("Connecting to %s : %d" % [ip, Net.PORT], "Body")
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var cancel := _button("Cancel", _cancel_connect, "", 260, "back")
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(cancel)
	_fade_in(r)
	_focus_first(cancel)
	var lt := l.create_tween().set_loops()
	lt.tween_property(l, "modulate:a", 0.4, 0.7)
	lt.tween_property(l, "modulate:a", 1.0, 0.7)
	get_tree().create_timer(12.0).timeout.connect(func():
		if token == _connect_token and screen == "connecting":
			Net.close()
			show_coop()
			show_message("No Answer", "The host at %s did not answer. Check the address and that both devices share a network." % ip))


func _cancel_connect() -> void:
	_connect_token += 1
	Net.close()
	show_coop()


func _on_net_connected() -> void:
	if screen == "connecting":
		_connect_token += 1
		show_sanctum()


func _on_net_failed() -> void:
	_connect_token += 1
	if screen == "connecting" or screen == "coop":
		show_coop()
		show_message("Connection Failed", "Could not reach the host. Check the address and your network.")


func _on_net_disconnected() -> void:
	_connect_token += 1
	if screen == "arena" or is_instance_valid(arena):
		_free_arena()
		Game.end_run(false)
		_pending_notice = "The host has left. Your shards from this descent were kept."
		show_title()
	elif coop_kind == "join" or screen == "sanctum" or screen == "connecting":
		_pending_notice = "Lost connection to the host."
		show_title()


func _on_lobby_changed() -> void:
	if screen == "sanctum" and is_instance_valid(_lobby_box):
		_refresh_lobby()


# =====================================================================  5. sanctum

func _is_online() -> bool:
	return Game.mode == "coop" and Net.online and (coop_kind == "host" or coop_kind == "join")


func show_sanctum() -> void:
	var r := _new_screen("sanctum")
	VTheme.music("sanctum")
	_bg(r, TEX_FLOOR, 0.3, true)
	_vignette(r, 0.5, 0.8, 0.85)
	_embers(r, 14)
	var vw := _vw()

	# Ysolde, a ghostly presence drifting at the left edge (decoration behind the layout)
	var ys := VTheme.image(VTheme.portrait_tex("ysolde"))
	ys.material = VTheme.material("fade_bottom")
	ys.anchor_top = 1; ys.anchor_bottom = 1
	ys.offset_left = -40; ys.offset_right = 300; ys.offset_top = -590; ys.offset_bottom = -104
	ys.modulate = Color(0.8, 1.0, 0.96, 0.85)
	r.add_child(ys)
	var tw := ys.create_tween().set_loops()
	tw.tween_property(ys, "position:y", -12.0, 2.8).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(ys, "position:y", 12.0, 2.8).as_relative().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var m := _margin(r, 24, 16, 24, 14)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 4)
	m.add_child(outer)

	# --- top bar with shard purse
	var purse := PanelContainer.new()
	purse.theme_type_variation = "Plate"
	purse.custom_minimum_size = Vector2(360, 74)
	var ph := HBoxContainer.new()
	ph.alignment = BoxContainer.ALIGNMENT_CENTER
	ph.add_theme_constant_override("separation", 8)
	purse.add_child(ph)
	ph.add_child(VTheme.shard_icon(34))
	_shard_label = _label("", "Gold", 26)
	ph.add_child(_shard_label)
	_header(outer, "The Sanctum", _leave_sanctum, purse)
	purse.offset_left = -360

	# --- body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	outer.add_child(body)

	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(250, 0)
	left.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(left)
	var mode_txt := "Solo descent"
	match coop_kind:
		"local": mode_txt = "Co-op on this device"
		"host": mode_txt = "Hosting online co-op"
		"join": mode_txt = "Joined online co-op"
	_mode_text = mode_txt
	var ysn := _label("MATRON YSOLDE", "Caps", 15)
	ysn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ysn.add_theme_color_override("font_color", StoryData.speaker("ysolde")["color"])
	left.add_child(ysn)
	left.add_child(_button("Speak with her", _talk_ysolde, "SmallButton", 250, "open"))

	# center: heroines
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mid.add_theme_constant_override("separation", 0)
	body.add_child(mid)
	var hl := _label("CHOOSE YOUR HEROINE", "Caps", 18)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(hl)
	var heroes_row := HBoxContainer.new()
	heroes_row.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes_row.add_theme_constant_override("separation", 0)
	heroes_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(heroes_row)
	var center_w := vw - 48 - 250 - 420 - 28
	var tile_w := clampf(center_w * 0.5, 240.0, 380.0)
	for hid in Game.HEROES.keys():
		_hero_tiles[hid] = _hero_tile(heroes_row, hid, tile_w)
	_hero_info = _label("", "Caps", 16)
	_hero_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hero_info.add_theme_color_override("font_color", VTheme.TEXT)
	mid.add_child(_hero_info)
	_build_weapon_picker(mid)
	if coop_kind == "local":
		var p2 := HBoxContainer.new()
		p2.alignment = BoxContainer.ALIGNMENT_CENTER
		mid.add_child(p2)
		_p2_label = _label("", "Gold", 20)
		p2.add_child(_p2_label)
		p2.add_child(_button("Swap", _toggle_p2, "SmallButton", 130))

	# right: lobby (online) + vow ledger
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(420, 0)
	right.add_theme_constant_override("separation", 6)
	body.add_child(right)
	if _is_online():
		var lp := PanelContainer.new()
		lp.theme_type_variation = "PanelSm"
		right.add_child(lp)
		_lobby_box = VBoxContainer.new()
		_lobby_box.add_theme_constant_override("separation", 2)
		lp.add_child(_lobby_box)
	var ledger := PanelContainer.new()
	ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(ledger)
	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 2)
	ledger.add_child(lv)
	var vt := _label("The Vow Ledger", "H3")
	vt.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	vt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lv.add_child(vt)
	var vs := _label("Bind Veil Shards into lasting oaths", "Quote", 17)
	vs.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vs.add_theme_color_override("font_color", VTheme.TEXT_DIM)
	lv.add_child(vs)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	lv.add_child(scroll)
	_shop_box = VBoxContainer.new()
	_shop_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_box.add_theme_constant_override("separation", 0)
	scroll.add_child(_shop_box)

	# --- bottom bar
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	bottom.add_theme_constant_override("separation", 18)
	outer.add_child(bottom)
	_status_label = _label("", "Quote", 20)
	_status_label.add_theme_color_override("font_color", VTheme.TEXT_DIM)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_status_label)
	_begin_btn = _button("Begin Descent", _begin, "BigButton", 420, "confirm")
	bottom.add_child(_begin_btn)
	# a slow breathing glow on the call to action
	var bt := _begin_btn.create_tween().set_loops()
	bt.tween_property(_begin_btn, "self_modulate", Color(1.15, 1.05, 0.9), 1.3).set_trans(Tween.TRANS_SINE)
	bt.tween_property(_begin_btn, "self_modulate", Color(1, 1, 1), 1.3).set_trans(Tween.TRANS_SINE)

	_refresh_sanctum()
	_fade_in(r)
	_rise_in([ledger, _begin_btn], 0.1, 0.08, 30)
	_focus_first(_begin_btn)


# ---- weapon + aspect picker (temporary home until the armory exists)

func _build_weapon_picker(parent: Control) -> void:
	_weapon_btns = {}
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	parent.add_child(row)
	var wl := _label("WEAPON", "Caps", 15)
	wl.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	row.add_child(wl)
	for wid in Game.WEAPON_ORDER:
		var b := Button.new()
		b.theme_type_variation = "IconButton"
		b.custom_minimum_size = Vector2(58, 58)
		b.focus_mode = Control.FOCUS_ALL
		b.tooltip_text = String(Game.WEAPONS[wid]["name"])
		var orb := VTheme.image("orb", Vector2.ZERO, false)
		orb.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(orb)
		var ic := VTheme.image(String(Game.WEAPONS[wid]["icon"]))
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 10; ic.offset_top = 10; ic.offset_right = -10; ic.offset_bottom = -10
		b.add_child(ic)
		VTheme.juice(b, 1.08, "click")
		b.pressed.connect(func(): _pick_weapon(wid))
		row.add_child(b)
		_weapon_btns[wid] = b
	var arow := HBoxContainer.new()
	arow.alignment = BoxContainer.ALIGNMENT_CENTER
	arow.add_theme_constant_override("separation", 8)
	row.add_child(arow)
	_aspect_btn = _button("", _cycle_aspect, "SmallButton", 300)
	arow.add_child(_aspect_btn)
	_unlock_btn = _button("", _unlock_aspect, "SmallButton", 150, "confirm")
	arow.add_child(_unlock_btn)
	_weapon_info = _label("", "Body", 15)
	_weapon_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_weapon_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_weapon_info.custom_minimum_size = Vector2(520, 0)
	_weapon_info.add_theme_color_override("font_color", VTheme.TEXT)
	parent.add_child(_weapon_info)


func _cur_weapon() -> String:
	return Game.weapon_for(_my_hero())


## Aspect shown in the picker (may be a locked one being previewed).
var _aspect_view := -1


func _pick_weapon(wid: String) -> void:
	VTheme.sound("confirm")
	Game.set_loadout(wid, 0)
	_aspect_view = 0
	_apply_loadout()


func _cycle_aspect() -> void:
	var w := _cur_weapon()
	var n: int = Game.WEAPONS[w]["aspects"].size()
	var cur := _aspect_view if _aspect_view >= 0 else Game.run_aspect
	_aspect_view = (cur + 1) % n
	if Game.aspect_unlocked(w, _aspect_view):
		Game.set_loadout(w, _aspect_view)
	_apply_loadout()


func _unlock_aspect() -> void:
	var w := _cur_weapon()
	if _aspect_view < 0 or not Game.unlock_aspect(w, _aspect_view):
		return
	Game.set_loadout(w, _aspect_view)
	_apply_loadout()
	if is_instance_valid(_shard_label):
		_shard_label.text = str(int(Game.data.get("shards", 0)))
	_refresh_shop()


func _apply_loadout() -> void:
	Game.save_slot()
	if Net.online:
		Net.change_my_loadout(_cur_weapon(), Game.run_aspect)
	_refresh_weapons()


func _refresh_weapons() -> void:
	if not is_instance_valid(_weapon_info):
		return
	var w := _cur_weapon()
	var wd: Dictionary = Game.WEAPONS[w]
	for wid in _weapon_btns.keys():
		var b: Button = _weapon_btns[wid]
		if is_instance_valid(b):
			b.modulate = Color(1, 1, 1) if wid == w else Color(0.55, 0.5, 0.58)
			b.scale = Vector2.ONE * (1.08 if wid == w else 1.0)
			b.pivot_offset = b.custom_minimum_size * 0.5
	var av := _aspect_view if _aspect_view >= 0 else Game.run_aspect
	var ad := Game.aspect_def(w, av)
	var unlocked := Game.aspect_unlocked(w, av)
	_aspect_btn.text = "%s  ▸" % String(ad.get("name", "")) if unlocked else "%s  (locked)  ▸" % String(ad.get("name", ""))
	var cost := Game.aspect_cost(w, av)
	_unlock_btn.visible = not unlocked
	_unlock_btn.text = "Unlock · %d" % cost
	_unlock_btn.disabled = int(Game.data.get("shards", 0)) < cost
	_weapon_info.text = "%s  ·  ATTACK %d  ·  %s %d\n%s" % [String(wd["name"]).to_upper(), int(wd["attack"]), String(wd["special_name"]).to_upper(), int(wd["special"]), String(ad.get("desc", ""))]
	_weapon_info.tooltip_text = String(wd["desc"])


func _hero_tile(parent: Control, hid: String, w: float) -> Button:
	var b := Button.new()
	b.theme_type_variation = "IconButton"
	b.custom_minimum_size = Vector2(w, 300)
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.focus_mode = Control.FOCUS_ALL
	b.pressed.connect(func(): _pick_hero(hid))
	b.mouse_entered.connect(func(): VTheme.sound("hover"))
	parent.add_child(b)
	# pedestal glow
	var col: Color = StoryData.speaker(hid).get("color", VTheme.GOLD)
	var g := Gradient.new()
	g.set_color(0, Color(col.r, col.g, col.b, 0.55))
	g.set_color(1, Color(col.r, col.g, col.b, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var glow := VTheme.image(gt, Vector2.ZERO, false)
	glow.name = "Glow"
	glow.anchor_left = 0.5; glow.anchor_right = 0.5; glow.anchor_top = 1; glow.anchor_bottom = 1
	glow.offset_left = -170; glow.offset_right = 170; glow.offset_top = -140; glow.offset_bottom = -20
	b.add_child(glow)
	var art := VTheme.image(VTheme.portrait_tex(hid))
	art.name = "Art"
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.anchor_left = 0.5; art.anchor_right = 0.5; art.anchor_top = 0; art.anchor_bottom = 1
	art.offset_left = -190; art.offset_right = 190; art.offset_top = 0; art.offset_bottom = -54
	b.add_child(art)
	art.resized.connect(func(): art.pivot_offset = Vector2(art.size.x * 0.5, art.size.y))
	var plate := PanelContainer.new()
	plate.name = "Plate"
	plate.theme_type_variation = "Plate"
	plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	plate.anchor_left = 0.5; plate.anchor_right = 0.5; plate.anchor_top = 1; plate.anchor_bottom = 1
	plate.offset_left = -150; plate.offset_right = 150; plate.offset_top = -70; plate.offset_bottom = -4
	b.add_child(plate)
	var nv := VBoxContainer.new()
	nv.add_theme_constant_override("separation", -6)
	plate.add_child(nv)
	var n := VTheme.title_label(String(Game.HEROES[hid]["name"]).split(" ")[0], 25, col.lightened(0.25), 5)
	nv.add_child(n)
	var tg := _label("", "Caps", 14)
	tg.name = "Tag"
	tg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tg.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	tg.anchor_left = 0; tg.anchor_right = 1
	tg.offset_top = 6; tg.offset_bottom = 30
	b.add_child(tg)
	b.focus_entered.connect(func(): _hero_hover(hid, true))
	b.focus_exited.connect(func(): _hero_hover(hid, false))
	return b


func _hero_hover(hid: String, on: bool) -> void:
	var b: Button = _hero_tiles.get(hid)
	if not is_instance_valid(b):
		return
	var sel := hid == _my_hero()
	var art: Control = b.get_node("Art")
	if not sel:
		art.create_tween().tween_property(art, "modulate", Color(0.75, 0.72, 0.78) if on else Color(0.45, 0.42, 0.5), 0.2)


func _pick_hero(hid: String) -> void:
	if String(Game.data.get("last_hero", "")) == hid:
		return
	VTheme.sound("confirm")
	Game.data["last_hero"] = hid
	Game.save_slot()
	if coop_kind == "local" and p2_hero == hid:
		p2_hero = _other_hero(hid)
	if Net.online:
		Net.change_my_hero(hid)
	_refresh_heroes()


func _toggle_p2() -> void:
	var keys := Game.HEROES.keys()
	var idx := keys.find(p2_hero)
	p2_hero = keys[(idx + 1) % keys.size()]
	_refresh_heroes()


func _refresh_sanctum() -> void:
	if is_instance_valid(_shard_label):
		_shard_label.text = str(int(Game.data.get("shards", 0)))
	_refresh_heroes()
	_refresh_shop()
	_refresh_lobby()


func _refresh_heroes() -> void:
	var mine := _my_hero()
	for hid in _hero_tiles.keys():
		var b: Button = _hero_tiles[hid]
		if not is_instance_valid(b):
			continue
		var sel: bool = hid == mine
		var art: Control = b.get_node("Art")
		var glow: Control = b.get_node("Glow")
		var plate: Control = b.get_node("Plate")
		var tag: Label = b.get_node("Tag")
		b.z_index = 1 if sel else 0
		var tw := b.create_tween().set_parallel()
		tw.tween_property(art, "modulate", Color(1, 1, 1) if sel else Color(0.45, 0.42, 0.5), 0.3)
		tw.tween_property(art, "scale", Vector2.ONE if sel else Vector2(0.9, 0.9), 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tw.tween_property(glow, "modulate:a", 1.0 if sel else 0.0, 0.3)
		tw.tween_property(plate, "modulate", Color(1, 1, 1) if sel else Color(0.6, 0.55, 0.6, 0.85), 0.3)
		# idle breathing on the chosen heroine only
		if art.has_meta("breath"):
			var old: Tween = art.get_meta("breath")
			if old and old.is_valid():
				old.kill()
			art.remove_meta("breath")
		if sel:
			var br := art.create_tween().set_loops()
			br.tween_interval(0.35)
			br.tween_property(art, "scale", Vector2(1.0, 1.018), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			br.tween_property(art, "scale", Vector2(1.0, 1.0), 1.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			art.set_meta("breath", br)
		var t := ""
		if coop_kind == "local":
			if sel:
				t = "PLAYER 1"
			if hid == p2_hero:
				t = (t + "  +  P2") if t != "" else "PLAYER 2"
		elif sel:
			t = "CHOSEN"
		tag.text = t
	if is_instance_valid(_hero_info):
		var def: Dictionary = Game.HEROES[mine]
		_hero_info.text = "%s  ·  HEALTH %d  ·  SPEED %d" % [String(def["title"]).to_upper(), int(def["hp"]), int(def["speed"])]
	_refresh_weapons()
	if is_instance_valid(_p2_label):
		_p2_label.text = "Player 2: %s" % String(Game.HEROES[p2_hero]["name"]).split(" ")[0]


func _refresh_shop() -> void:
	if not is_instance_valid(_shop_box):
		return
	for c in _shop_box.get_children():
		c.queue_free()
	var shards := int(Game.data.get("shards", 0))
	var first := true
	for id in Game.META.keys():
		var def: Dictionary = Game.META[id]
		var rank := Game.meta_rank(id)
		var mx := int(def["max"])
		if not first:
			var dv := VTheme.divider(300, 16)
			dv.modulate.a = 0.55
			_shop_box.add_child(dv)
		first = false
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_shop_box.add_child(row)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", -2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(info)
		var n := _label(String(def["name"]), "Gold", 21)
		info.add_child(n)
		var d := _label(String(def["desc"]), "Dim", 17)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(190, 0)
		info.add_child(d)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 3)
		info.add_child(pips)
		for k in mx:
			var pip := VTheme.shard_icon(18)
			pip.modulate = Color(1, 1, 1) if k < rank else Color(0.25, 0.22, 0.28, 0.9)
			pips.add_child(pip)
		var b: Button
		if rank >= mx:
			var sw := _label("SWORN", "Caps", 17)
			sw.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
			sw.custom_minimum_size = Vector2(124, 0)
			sw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(sw)
		else:
			var cost := int(def["cost"][rank])
			b = _button(str(cost), func(): _buy(id), "SmallButton", 124, "")
			b.icon = VTheme.tex("shard")
			b.expand_icon = false
			b.add_theme_constant_override("icon_max_width", 16)
			b.disabled = shards < cost
			b.tooltip_text = "Costs %d Veil Shards" % cost
			b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(b)


func _buy(id: String) -> void:
	if Game.buy_meta(id):
		VTheme.sound("purchase")
		var fe := get_viewport().gui_get_focus_owner()
		var focus_idx := -1
		if fe and is_instance_valid(_shop_box) and _shop_box.is_ancestor_of(fe):
			focus_idx = fe.get_parent().get_index()
		_refresh_sanctum()
		if is_instance_valid(_shard_label):
			var tw := _shard_label.create_tween()
			_shard_label.pivot_offset = _shard_label.size * 0.5
			tw.tween_property(_shard_label, "scale", Vector2(1.3, 1.3), 0.08)
			tw.tween_property(_shard_label, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if focus_idx >= 0:
			_refocus_shop.call_deferred(focus_idx)
	else:
		VTheme.sound("back")


func _refocus_shop(idx: int) -> void:
	if not is_instance_valid(_shop_box):
		return
	var live: Array = []
	for c in _shop_box.get_children():
		if not c.is_queued_for_deletion():
			live.append(c)
	if idx < live.size():
		for b in (live[idx] as Node).find_children("*", "Button", true, false):
			if not (b as Button).disabled:
				(b as Button).grab_focus()
				return
	if is_instance_valid(_begin_btn):
		_begin_btn.grab_focus()


func _refresh_lobby() -> void:
	var online := _is_online()
	if online and is_instance_valid(_lobby_box):
		for c in _lobby_box.get_children():
			c.queue_free()
		if Net.is_host():
			var ipl := _label("Your address  %s : %d" % [Net.local_ip(), Net.PORT], "Gold", 20)
			_lobby_box.add_child(ipl)
		var head := _label("COMPANIONS  %d / %d" % [Net.lobby.size(), Net.MAX_PLAYERS], "Caps", 15)
		_lobby_box.add_child(head)
		for i in Net.lobby.size():
			var p: Dictionary = Net.lobby[i]
			var hid := String(p.get("hero", "kaela"))
			var hname := String(Game.HEROES.get(hid, {}).get("name", hid)).split(" ")[0]
			var who := "Host" if int(p.get("peer", 0)) == 1 else "Player %d" % (i + 1)
			if int(p.get("peer", 0)) == Net.my_id():
				who += " (you)"
			var l := _label("%s  —  %s" % [who, hname], "Body", 20)
			l.add_theme_color_override("font_color", StoryData.speaker(hid).get("color", VTheme.TEXT))
			_lobby_box.add_child(l)
	if not is_instance_valid(_begin_btn):
		return
	if online:
		if Net.is_host():
			var ok := Net.lobby.size() >= 2
			_begin_btn.disabled = not ok
			_begin_btn.text = "Begin Descent"
			_status_label.text = "" if ok else "Waiting for a companion to join..."
		else:
			_begin_btn.disabled = true
			_begin_btn.text = "Waiting for host"
			_status_label.text = "The host will begin the descent."
	else:
		_begin_btn.disabled = false
		_begin_btn.text = "Begin Descent"
		_status_label.text = _mode_text


func _talk_ysolde() -> void:
	play_dialogue(StoryData.one("ysolde", StoryData.chatter_line()), Callable())


func _leave_sanctum() -> void:
	if Net.online:
		Net.close()
	if Game.mode == "coop":
		show_coop()
	else:
		show_slots("solo")


func _begin() -> void:
	var hero := _my_hero()
	if _is_online():
		if not Net.is_host() or Net.lobby.size() < 2:
			return
		_begin_btn.disabled = true
		Net.begin_run.rpc(randi(), Net.lobby.duplicate(true))
		return
	if coop_kind == "local":
		Game.players = [
			{"peer": 1, "local_index": 0, "hero": hero},
			{"peer": 1, "local_index": 1, "hero": p2_hero},
		]
	else:
		Game.players = [{"peer": 1, "local_index": 0, "hero": hero}]
	Game.start_run(randi())
	start_arena()


# =====================================================================  6. arena

func start_arena() -> void:
	if is_instance_valid(_dialogue):
		_dialogue.abort()
		_dialogue = null
	_close_modal()
	_free_arena()
	var script: Script = load(ARENA_PATH) if ResourceLoader.exists(ARENA_PATH) else null
	if script == null or not script.can_instantiate():
		push_error("Main: arena script missing or failed to load: " + ARENA_PATH)
		show_sanctum()
		show_message("The Way Is Sealed", "The Catacombs could not be opened (arena failed to load).")
		return
	var a = script.new()
	if a == null or not (a is Node):
		show_sanctum()
		show_message("The Way Is Sealed", "The Catacombs could not be opened.")
		return
	# free menus immediately (no fade: the arena takes over the screen)
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_shard_label = null
	_shop_box = null
	_hero_tiles = {}
	_hero_info = null
	_weapon_info = null
	_weapon_btns = {}
	_lobby_box = null
	_begin_btn = null
	_p2_label = null
	_status_label = null
	_ui_layer.visible = false
	screen = "arena"
	arena = a
	add_child(a)
	a.setup(Game.players)
	a.run_finished.connect(_on_run_finished)


func _free_arena() -> void:
	if is_instance_valid(arena):
		if arena.run_finished.is_connected(_on_run_finished):
			arena.run_finished.disconnect(_on_run_finished)
		arena.queue_free()
	if Net.arena == arena:
		Net.arena = null
	arena = null


func _on_run_finished(victory: bool) -> void:
	if screen != "arena":
		return
	var earned := Game.end_run(victory)
	call_deferred("_free_arena")
	if is_instance_valid(_dialogue):
		_dialogue.abort()
		_dialogue = null
	_show_results(victory, earned)


func _show_results(victory: bool, earned: int) -> void:
	var r := _new_screen("results")
	VTheme.music("victory" if victory else "defeat")
	_bg(r, TEX_FLOOR if not victory else TEX_TITLE, 0.24, true)
	_vignette(r, 0.5, 0.85, 0.85)
	if victory:
		_embers(r, 40)
		_embers(r, 12, true)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(760, 0)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	var tcol := VTheme.GOLD_BRIGHT if victory else Color(0.82, 0.62, 1.0)
	var title := VTheme.title_label("Victory" if victory else "Fallen", 82, tcol, 12, "display")
	v.add_child(title)
	var sub := _label("The Hollow Regent is unmade." if victory else "The Veil returns you to the Sanctum.", "Quote", 24)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	v.add_child(VTheme.divider(440, 34))

	var stats := HBoxContainer.new()
	stats.alignment = BoxContainer.ALIGNMENT_CENTER
	stats.add_theme_constant_override("separation", 56)
	v.add_child(stats)
	var shard_col := VBoxContainer.new()
	shard_col.add_theme_constant_override("separation", -4)
	stats.add_child(shard_col)
	shard_col.add_child(_center(_label("SHARDS EARNED", "Caps", 15)))
	var sh := HBoxContainer.new()
	sh.alignment = BoxContainer.ALIGNMENT_CENTER
	sh.add_theme_constant_override("separation", 8)
	shard_col.add_child(sh)
	sh.add_child(VTheme.shard_icon(40))
	var sl := VTheme.title_label("+0", 44, VTheme.GOLD_BRIGHT, 8)
	sh.add_child(sl)
	var rooms := VBoxContainer.new()
	rooms.add_theme_constant_override("separation", -4)
	stats.add_child(rooms)
	rooms.add_child(_center(_label("CHAMBERS CLEARED", "Caps", 15)))
	rooms.add_child(VTheme.title_label(str(Game.run_room), 44, VTheme.TEXT, 8))
	var deep := VBoxContainer.new()
	deep.add_theme_constant_override("separation", -4)
	stats.add_child(deep)
	deep.add_child(_center(_label("DEEPEST", "Caps", 15)))
	deep.add_child(VTheme.title_label(str(int(Game.data.get("best_room", 0))), 44, VTheme.TEXT, 8))
	var cnt := sl.create_tween()
	cnt.tween_interval(0.5)
	cnt.tween_method(func(x: float): sl.text = "+%d" % int(x), 0.0, float(earned), clampf(earned / 40.0, 0.6, 1.6)).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	cnt.tween_callback(func(): VTheme.sound("purchase"))

	# Ysolde's verdict
	var qrow := HBoxContainer.new()
	qrow.add_theme_constant_override("separation", 16)
	qrow.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(qrow)
	var face := _round_portrait("ysolde", 104)
	qrow.add_child(face)
	var qv := VBoxContainer.new()
	qv.add_theme_constant_override("separation", 0)
	qrow.add_child(qv)
	var quote_txt := StoryData.VICTORY[3]["text"] if victory else _death_narration()
	var quote := _label("“%s”" % quote_txt, "Quote", 22)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.custom_minimum_size = Vector2(540, 0)
	quote.add_theme_color_override("font_color", StoryData.speaker("ysolde")["color"].lightened(0.25))
	qv.add_child(quote)
	var who := _label("— MATRON YSOLDE" if victory else "— THE NARRATOR", "Caps", 14)
	qv.add_child(who)
	var btn := _button("Return to the Sanctum", func():
		if victory:
			var vl: Array = StoryDB.next_lines("victory", StoryDB.from_save(Game.data))
			Game.save_slot()
			play_dialogue(vl if not vl.is_empty() else StoryData.VICTORY, show_sanctum)
		else:
			show_sanctum(), "BigButton", 440, "confirm")
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(btn)
	_fade_in(r, 0.6)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	p.scale = Vector2(0.92, 0.92)
	p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	title.resized.connect(func(): title.pivot_offset = title.size * 0.5)
	title.scale = Vector2(1.4, 1.4)
	title.modulate.a = 0.0
	var tt := title.create_tween().set_parallel()
	tt.tween_property(title, "scale", Vector2.ONE, 0.7).set_delay(0.15).set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	tt.tween_property(title, "modulate:a", 1.0, 0.4).set_delay(0.15)
	_focus_first(btn)


## The narrator on the death screen (voice clip when one exists), in the killer's context.
func _death_narration() -> String:
	var coop := Game.players.size() > 1
	var ctx := StoryDB.death_context(Game.run_killer, coop, coop and Game.run_both_down)
	var audio := get_node_or_null("/root/Audio")
	var t := ""
	if audio and audio.has_method("voice"):
		t = String(audio.voice("narrator", ctx))
	if t == "":
		t = StoryDB.narration(ctx)
	return t if t != "" else StoryData.death_line()


func _center(c: Control) -> Control:
	if c is Label:
		(c as Label).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return c


## Round painted face inside the gilded ring.
func _round_portrait(id: String, size: float) -> Control:
	var holder := Control.new()
	holder.custom_minimum_size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := VTheme.image(VTheme.tex("face_" + id), Vector2.ZERO, false)
	face.position = Vector2(size * 0.1, size * 0.1)
	face.size = Vector2(size * 0.8, size * 0.8)
	holder.add_child(face)
	var ring := VTheme.image("ring", Vector2.ZERO, false)
	ring.size = Vector2(size, size)
	holder.add_child(ring)
	return holder


# =====================================================================  7. dialogue

func play_dialogue(lines: Array, on_done: Callable) -> void:
	if is_instance_valid(_dialogue):
		_dialogue.abort()
	var d: CanvasLayer = DialogueScript.new()
	_dialogue = d
	add_child(d)
	d.finished.connect(func():
		if _dialogue == d:
			_dialogue = null)
	d.start(lines, on_done)
