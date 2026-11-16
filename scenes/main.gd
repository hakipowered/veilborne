extends Node
## Veilborne front-end: title, save slots, co-op lobby, Sanctum hub, results, and run start.
## All UI is built in code. Only one screen exists at a time; old screens are freed.

const VTheme = preload("res://ui/theme.gd")
const StoryData = preload("res://data/story.gd")
const DialogueScript = preload("res://ui/dialogue.gd")
const ARENA_PATH := "res://scenes/arena.gd"

const TEX_TITLE := "res://art/title.jpg"
const TEX_FLOOR := "res://art/floor_catacomb.jpg"
const TEX_YSOLDE := "res://art/ysolde.png"
const HERO_TEX := {"kaela": "res://art/kaela.png", "liora": "res://art/liora.png"}

## Screens: title, slots, coop, connecting, sanctum, results, arena
var screen := ""
var coop_kind := "" ## "", "local", "host", "join"
var p2_hero := "liora"
var arena: Node = null

var _ui_layer: CanvasLayer
var _root: Control          ## current screen root (freed on change)
var _modal: Control = null  ## confirm / message overlay
var _dialogue: CanvasLayer = null
var _tex_cache := {}
var _connect_token := 0
var _pending_notice := ""

# sanctum widgets refreshed in place
var _shard_label: Label
var _shop_box: VBoxContainer
var _hero_cards := {}
var _lobby_box: VBoxContainer
var _begin_btn: Button
var _p2_label: Label
var _status_label: Label
var _mode_text := ""


func _ready() -> void:
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
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
		_close_modal()
		return
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

func _tex(path: String) -> Texture2D:
	if _tex_cache.has(path):
		return _tex_cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = load(path) as Texture2D
	_tex_cache[path] = t
	return t


func _new_screen(name_: String) -> Control:
	_close_modal()
	if is_instance_valid(_root):
		_root.queue_free()
	_shard_label = null
	_shop_box = null
	_hero_cards = {}
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


func _bg(parent: Control, path: String, dim: float, kenburns := false) -> TextureRect:
	var r := ColorRect.new()
	r.color = Color(0.05, 0.03, 0.07)
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	var tex := _tex(path)
	if tex == null:
		return null
	var tr := TextureRect.new()
	tr.texture = tex
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tr.modulate = Color(dim, dim, dim * 0.95 + 0.02)
	parent.add_child(tr)
	if kenburns:
		tr.resized.connect(func(): tr.pivot_offset = tr.size * Vector2(0.55, 0.4))
		var tw := tr.create_tween().set_loops()
		tw.tween_property(tr, "scale", Vector2(1.12, 1.12), 18.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(tr, "scale", Vector2(1.0, 1.0), 18.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tr


func _vignette(parent: Control, top_a: float, bottom_a: float) -> void:
	var g := Gradient.new()
	g.set_color(0, Color(0.03, 0.01, 0.05, top_a))
	g.set_color(1, Color(0.03, 0.01, 0.05, bottom_a))
	g.add_point(0.5, Color(0.03, 0.01, 0.05, min(top_a, bottom_a) * 0.3))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 4
	gt.height = 128
	gt.fill_to = Vector2(0, 1)
	var tr := TextureRect.new()
	tr.texture = gt
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.set_anchors_preset(Control.PRESET_FULL_RECT)
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(tr)


func _embers(parent: Control) -> void:
	var p := CPUParticles2D.new()
	p.amount = 36
	p.lifetime = 7.0
	p.preprocess = 7.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(760, 10)
	p.position = Vector2(640, 760)
	p.direction = Vector2(0, -1)
	p.spread = 25.0
	p.gravity = Vector2(0, -6)
	p.initial_velocity_min = 30.0
	p.initial_velocity_max = 70.0
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.5
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.7, 0.3, 0.0))
	ramp.add_point(0.15, Color(1.0, 0.6, 0.2, 0.9))
	ramp.set_color(ramp.get_point_count() - 1, Color(1.0, 0.3, 0.1, 0.0))
	p.color_ramp = ramp
	parent.add_child(p)


func _button(text: String, cb: Callable, variation := "", min_w := 280.0) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(min_w, 72 if variation == "BigButton" else 64)
	b.mouse_filter = Control.MOUSE_FILTER_PASS
	b.pressed.connect(cb)
	return b


func _label(text: String, variation := "", size := 0) -> Label:
	var l := Label.new()
	l.text = text
	if variation != "":
		l.theme_type_variation = variation
	if size > 0:
		l.add_theme_font_size_override("font_size", size)
	return l


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


func _focus_first(b: Control) -> void:
	if is_instance_valid(b):
		b.call_deferred("grab_focus")


# =====================================================================  modal overlays

func _close_modal() -> void:
	if is_instance_valid(_modal):
		_modal.queue_free()
	_modal = null


func _open_modal(title: String, body: String, buttons: Array) -> void:
	## buttons: [[text, Callable, variation]]
	_close_modal()
	var m := Control.new()
	m.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.theme = VTheme.get_theme()
	m.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.03, 0.72)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	m.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	panel.add_child(v)
	var t := _label(title, "HeaderLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var bl := _label(body)
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
			cb.call(), spec[2] if spec.size() > 2 else "", 200)
		h.add_child(b)
		if first == null:
			first = b
	_ui_layer.add_child(m)
	_modal = m
	_fade_in(m, 0.2)
	_focus_first(first)


func show_message(title: String, body: String) -> void:
	_open_modal(title, body, [["Understood", func(): pass]])


# =====================================================================  1. title

func show_title() -> void:
	coop_kind = ""
	var r := _new_screen("title")
	_bg(r, TEX_TITLE, 1.0, true)
	_vignette(r, 0.35, 0.75)
	_embers(r)

	var top := VBoxContainer.new()
	top.anchor_left = 0; top.anchor_right = 1
	top.offset_top = 28; top.offset_bottom = 230
	top.add_theme_constant_override("separation", 0)
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.add_child(top)
	var title := VTheme.title_label("VEILBORNE", 104, VTheme.GOLD_BRIGHT, 16)
	top.add_child(title)
	var sub := VTheme.title_label("Descent Beneath the Shattered Veil", 28, Color(0.95, 0.85, 0.75), 8)
	top.add_child(sub)
	title.pivot_offset = Vector2(640, 60)
	var tw := title.create_tween().set_loops()
	tw.tween_property(title, "self_modulate", Color(1.0, 0.9, 0.75), 2.4).set_trans(Tween.TRANS_SINE)
	tw.tween_property(title, "self_modulate", Color(1, 1, 1), 2.4).set_trans(Tween.TRANS_SINE)

	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	v.anchor_left = 0.5; v.anchor_right = 0.5; v.anchor_top = 1; v.anchor_bottom = 1
	v.offset_left = -170; v.offset_right = 170; v.offset_top = -300; v.offset_bottom = -40
	v.grow_vertical = Control.GROW_DIRECTION_BEGIN
	r.add_child(v)
	var solo := _button("Solo", func(): show_slots("solo"), "BigButton", 340)
	v.add_child(solo)
	v.add_child(_button("Co-op", func(): show_slots("coop"), "BigButton", 340))
	v.add_child(_button("Quit", _quit, "", 340))
	_fade_in(r, 0.8)
	_focus_first(solo)
	if _pending_notice != "":
		var n := _pending_notice
		_pending_notice = ""
		show_message("The Veil Wavers", n)


# =====================================================================  2. slots

func show_slots(mode: String) -> void:
	if Net.online:
		Net.close()
	Game.mode = mode
	var r := _new_screen("slots")
	_bg(r, TEX_TITLE, 0.35)
	_vignette(r, 0.6, 0.85)
	var m := _margin(r, 40, 28, 40, 28)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 22)
	m.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(_button("Back", show_title, "SmallButton", 160))
	var t := VTheme.title_label("Solo Chronicles" if mode == "solo" else "Co-op Chronicles", 52)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(160, 0)
	head.add_child(spacer)
	var hint := _label("Choose a chronicle. Each keeps its own shards, vows and story." if mode == "solo" else "Co-op chronicles are kept apart from solo ones. Your shards and vows travel with you.", "DimLabel")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)
	var first: Button = null
	for i in Game.SLOT_COUNT:
		var b := _slot_card(row, mode, i)
		if first == null:
			first = b
	_fade_in(r)
	_focus_first(first)


func _slot_card(parent: Control, mode: String, i: int) -> Button:
	var d: Dictionary = Game.peek_slot(mode, i)
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel" if d.is_empty() else "CardPanelSelected"
	card.custom_minimum_size = Vector2(360, 440)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	var t := _label("Chronicle %d" % (i + 1), "HeaderLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", 4)
	info.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(info)
	var main_btn: Button
	if d.is_empty():
		var e := _label("An unwritten page.\nThe Veil awaits a new tale.", "DimLabel", 22)
		e.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		e.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		e.size_flags_vertical = Control.SIZE_EXPAND_FILL
		e.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		info.add_child(e)
		main_btn = _button("New Game", func(): _select_slot(mode, i), "BigButton", 300)
		v.add_child(main_btn)
	else:
		var hero_id := String(d.get("last_hero", "kaela"))
		var hero_name: String = Game.HEROES.get(hero_id, {}).get("name", hero_id)
		_stat_row(info, "Heroine", hero_name.split(" ")[0])
		_stat_row(info, "Descents", str(int(d.get("runs", 0))))
		_stat_row(info, "Victories", str(int(d.get("wins", 0))))
		_stat_row(info, "Veil Shards", str(int(d.get("shards", 0))))
		_stat_row(info, "Deepest room", str(int(d.get("best_room", 0))))
		var lp := String(d.get("last_played", "")).replace("T", "  ")
		if lp.length() > 17:
			lp = lp.substr(0, 17)
		var lpl := _label("Last played  " + (lp if lp != "" else "-"), "DimLabel")
		lpl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info.add_child(lpl)
		main_btn = _button("Continue", func(): _select_slot(mode, i), "BigButton", 300)
		v.add_child(main_btn)
		var del := _button("Delete", func(): _confirm_delete(mode, i), "DangerButton", 300)
		v.add_child(del)
	return main_btn


func _stat_row(parent: Control, k: String, val: String) -> void:
	var h := HBoxContainer.new()
	parent.add_child(h)
	var kl := _label(k, "DimLabel", 22)
	kl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(kl)
	var vl := _label(val, "", 24)
	vl.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	h.add_child(vl)


func _confirm_delete(mode: String, i: int) -> void:
	_open_modal("Erase Chronicle %d?" % (i + 1),
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


# =====================================================================  3. co-op connection

func show_coop() -> void:
	if Net.online:
		Net.close()
	coop_kind = ""
	var r := _new_screen("coop")
	_bg(r, TEX_TITLE, 0.3)
	_vignette(r, 0.6, 0.85)
	var m := _margin(r, 40, 28, 40, 28)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 20)
	m.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	head.add_child(_button("Back", func(): show_slots("coop"), "SmallButton", 160))
	var t := VTheme.title_label("Gather Your Companion", 48)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(t)
	var sp := Control.new()
	sp.custom_minimum_size = Vector2(160, 0)
	head.add_child(sp)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 26)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(row)

	var local := _mode_card(row, "Same Device", "Two heroines, one screen. Player 2 uses a gamepad or the arrow keys (attack , special . dash /).")
	var lb := _button("Play Local", _start_local, "BigButton", 300)
	local.add_child(lb)

	var host := _mode_card(row, "Host", "Open the Sanctum gate on this device. Friends on the same Wi-Fi join with your address.")
	host.add_child(_button("Host Game", _start_host, "BigButton", 300))

	var join := _mode_card(row, "Join", "Enter the host's address shown on their Sanctum screen.")
	var ip := LineEdit.new()
	ip.placeholder_text = "192.168.1.20"
	ip.text = String(Game.data.get("last_ip", ""))
	ip.custom_minimum_size = Vector2(300, 64)
	ip.alignment = HORIZONTAL_ALIGNMENT_CENTER
	ip.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_URL
	ip.text_submitted.connect(func(s: String): _start_join(s))
	join.add_child(ip)
	join.add_child(_button("Join Game", func(): _start_join(ip.text), "BigButton", 300))
	_fade_in(r)
	_focus_first(lb)


func _mode_card(parent: Control, title: String, desc: String) -> VBoxContainer:
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(360, 400)
	card.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	card.add_child(v)
	var t := _label(title, "HeaderLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var d := _label(desc, "", 22)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.custom_minimum_size = Vector2(320, 0)
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
	_bg(r, TEX_TITLE, 0.25)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.add_child(c)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(520, 0)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 18)
	p.add_child(v)
	var t := _label("Crossing the Veil...", "HeaderLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var l := _label("Connecting to %s : %d" % [ip, Net.PORT])
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(l)
	var cancel := _button("Cancel", _cancel_connect, "", 260)
	cancel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(cancel)
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
	_bg(r, TEX_FLOOR, 0.32)
	_vignette(r, 0.55, 0.8)

	# Ysolde, drifting gently on the left
	var ys_tex := _tex(TEX_YSOLDE)
	if ys_tex:
		var ys := TextureRect.new()
		ys.texture = ys_tex
		ys.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ys.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ys.mouse_filter = Control.MOUSE_FILTER_IGNORE
		ys.anchor_top = 1; ys.anchor_bottom = 1
		ys.offset_left = -10; ys.offset_right = 330; ys.offset_top = -590; ys.offset_bottom = -95
		ys.modulate = Color(0.85, 1.0, 0.97, 0.92)
		r.add_child(ys)
		var tw := ys.create_tween().set_loops()
		tw.tween_property(ys, "position:y", ys.position.y - 10.0, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(ys, "position:y", ys.position.y, 2.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

	var m := _margin(r, 24, 16, 24, 16)
	var outer := VBoxContainer.new()
	outer.add_theme_constant_override("separation", 10)
	m.add_child(outer)

	# --- top bar
	var top := HBoxContainer.new()
	outer.add_child(top)
	top.add_child(_button("Leave", _leave_sanctum, "SmallButton", 150))
	var title := VTheme.title_label("The Sanctum", 46)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var shard_panel := PanelContainer.new()
	shard_panel.theme_type_variation = "NamePlate"
	top.add_child(shard_panel)
	var sh := HBoxContainer.new()
	shard_panel.add_child(sh)
	var gem := _shard_icon()
	sh.add_child(gem)
	_shard_label = _label("", "", 26)
	_shard_label.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	sh.add_child(_shard_label)

	# --- body
	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 18)
	outer.add_child(body)

	# left column: space for Ysolde + talk button at the bottom
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(280, 0)
	left.alignment = BoxContainer.ALIGNMENT_END
	body.add_child(left)
	var mode_txt := "Solo descent"
	match coop_kind:
		"local": mode_txt = "Co-op on this device"
		"host": mode_txt = "Hosting online co-op"
		"join": mode_txt = "Joined online co-op"
	_mode_text = mode_txt
	left.add_child(_button("Talk to Ysolde", _talk_ysolde, "", 280))

	# middle: heroes
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(mid)
	var hl := _label("Choose your heroine", "HeaderLabel")
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mid.add_child(hl)
	var heroes_row := HBoxContainer.new()
	heroes_row.alignment = BoxContainer.ALIGNMENT_CENTER
	heroes_row.add_theme_constant_override("separation", 14)
	heroes_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	mid.add_child(heroes_row)
	for hid in Game.HEROES.keys():
		_hero_cards[hid] = _hero_card(heroes_row, hid)
	if coop_kind == "local":
		var p2 := HBoxContainer.new()
		p2.alignment = BoxContainer.ALIGNMENT_CENTER
		mid.add_child(p2)
		_p2_label = _label("", "", 22)
		p2.add_child(_p2_label)
		p2.add_child(_button("Swap", _toggle_p2, "SmallButton", 140))

	# right: lobby (online) + vows shop
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(400, 0)
	body.add_child(right)
	if _is_online():
		var lp := PanelContainer.new()
		right.add_child(lp)
		_lobby_box = VBoxContainer.new()
		_lobby_box.add_theme_constant_override("separation", 4)
		lp.add_child(_lobby_box)
	var vt := _label("Vows of the Sanctum", "HeaderLabel")
	vt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	right.add_child(vt)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	right.add_child(scroll)
	_shop_box = VBoxContainer.new()
	_shop_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shop_box.add_theme_constant_override("separation", 8)
	scroll.add_child(_shop_box)

	# --- bottom bar
	var bottom := HBoxContainer.new()
	bottom.alignment = BoxContainer.ALIGNMENT_END
	outer.add_child(bottom)
	_status_label = _label("", "DimLabel", 22)
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	bottom.add_child(_status_label)
	_begin_btn = _button("Begin Descent", _begin, "BigButton", 360)
	bottom.add_child(_begin_btn)

	_refresh_sanctum()
	_fade_in(r)
	_focus_first(_begin_btn)


func _shard_icon() -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(30, 30)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.draw.connect(func():
		var s := c.size
		var pts := PackedVector2Array([Vector2(s.x * 0.5, 2), Vector2(s.x - 4, s.y * 0.5), Vector2(s.x * 0.5, s.y - 2), Vector2(4, s.y * 0.5)])
		c.draw_colored_polygon(pts, Color(0.55, 0.85, 1.0))
		var outline := pts.duplicate()
		outline.append(pts[0])
		c.draw_polyline(outline, VTheme.INK, 2.5, true)
		c.draw_line(Vector2(s.x * 0.5, 2), Vector2(s.x * 0.5, s.y - 2), Color(1, 1, 1, 0.6), 1.5))
	return c


func _hero_card(parent: Control, hid: String) -> PanelContainer:
	var def: Dictionary = Game.HEROES[hid]
	var card := PanelContainer.new()
	card.theme_type_variation = "CardPanel"
	card.custom_minimum_size = Vector2(250, 0)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_pick_hero(hid))
	parent.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(v)
	var art := TextureRect.new()
	art.texture = _tex(HERO_TEX.get(hid, ""))
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.custom_minimum_size = Vector2(200, 200)
	art.size_flags_vertical = Control.SIZE_EXPAND_FILL
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_child(art)
	var n := _label(String(def["name"]), "", 24)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.add_theme_color_override("font_color", StoryData.speaker(hid).get("color", VTheme.GOLD))
	n.add_theme_font_override("font", VTheme.title_font())
	v.add_child(n)
	var t := _label(String(def["title"]), "DimLabel")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var st := _label("HP %d   SPD %d\nATK %d   SPECIAL %d" % [int(def["hp"]), int(def["speed"]), int(def["attack"]), int(def["special"])], "", 20)
	st.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(st)
	var tag := _label("", "", 22)
	tag.name = "Tag"
	tag.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tag.add_theme_color_override("font_color", VTheme.EMBER)
	v.add_child(tag)
	var pick := _button("Choose", func(): _pick_hero(hid), "SmallButton", 200)
	pick.name = "Pick"
	pick.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(pick)
	return card


func _pick_hero(hid: String) -> void:
	if String(Game.data.get("last_hero", "")) == hid:
		return
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
		_shard_label.text = "%d Veil Shards" % int(Game.data.get("shards", 0))
	_refresh_heroes()
	_refresh_shop()
	_refresh_lobby()


func _refresh_heroes() -> void:
	var mine := _my_hero()
	for hid in _hero_cards.keys():
		var card: PanelContainer = _hero_cards[hid]
		if not is_instance_valid(card):
			continue
		var sel: bool = hid == mine
		card.theme_type_variation = "CardPanelSelected" if sel else "CardPanel"
		var tag: Label = card.find_child("Tag", true, false)
		var pick: Button = card.find_child("Pick", true, false)
		var t := ""
		if sel and coop_kind == "local":
			t = "Player 1"
		if coop_kind == "local" and hid == p2_hero:
			t = (t + " + P2") if t != "" else "Player 2"
		if tag:
			tag.text = t
		if pick:
			pick.disabled = sel
			pick.text = "Chosen" if sel else "Choose"
	if is_instance_valid(_p2_label):
		_p2_label.text = "Player 2: %s" % String(Game.HEROES[p2_hero]["name"]).split(" ")[0]


func _refresh_shop() -> void:
	if not is_instance_valid(_shop_box):
		return
	for c in _shop_box.get_children():
		c.queue_free()
	var shards := int(Game.data.get("shards", 0))
	for id in Game.META.keys():
		var def: Dictionary = Game.META[id]
		var rank := Game.meta_rank(id)
		var mx := int(def["max"])
		var row := PanelContainer.new()
		row.theme_type_variation = "CardPanel"
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		_shop_box.add_child(row)
		var h := HBoxContainer.new()
		row.add_child(h)
		var info := VBoxContainer.new()
		info.add_theme_constant_override("separation", 2)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(info)
		var n := _label(String(def["name"]), "", 22)
		n.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
		info.add_child(n)
		var d := _label(String(def["desc"]), "DimLabel", 18)
		d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		d.custom_minimum_size = Vector2(200, 0)
		info.add_child(d)
		var pips := HBoxContainer.new()
		pips.add_theme_constant_override("separation", 5)
		info.add_child(pips)
		for k in mx:
			var pip := Panel.new()
			pip.custom_minimum_size = Vector2(18, 10)
			pip.mouse_filter = Control.MOUSE_FILTER_IGNORE
			pip.add_theme_stylebox_override("panel", VTheme.box(VTheme.EMBER if k < rank else Color(0.1, 0.05, 0.1), VTheme.GOLD if k < rank else VTheme.GOLD_DIM, 1, 3, 0, Color(0, 0, 0, 0), 0, 0))
			pips.add_child(pip)
		var b: Button
		if rank >= mx:
			b = _button("Sworn", func(): pass, "SmallButton", 120)
			b.disabled = true
		else:
			var cost := int(def["cost"][rank])
			b = _button("%d" % cost, func(): _buy(id), "SmallButton", 120)
			b.icon = null
			b.disabled = shards < cost
			b.tooltip_text = "Costs %d shards" % cost
		b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(b)


func _buy(id: String) -> void:
	if Game.buy_meta(id):
		_refresh_sanctum()
		if is_instance_valid(_shard_label):
			var tw := _shard_label.create_tween()
			_shard_label.pivot_offset = _shard_label.size * 0.5
			tw.tween_property(_shard_label, "scale", Vector2(1.2, 1.2), 0.1)
			tw.tween_property(_shard_label, "scale", Vector2.ONE, 0.2)


func _refresh_lobby() -> void:
	var online := _is_online()
	if online and is_instance_valid(_lobby_box):
		for c in _lobby_box.get_children():
			c.queue_free()
		if Net.is_host():
			var ipl := _label("Your address: %s   port %d" % [Net.local_ip(), Net.PORT], "", 22)
			ipl.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
			_lobby_box.add_child(ipl)
		var head := _label("Companions (%d/%d)" % [Net.lobby.size(), Net.MAX_PLAYERS], "DimLabel")
		_lobby_box.add_child(head)
		for i in Net.lobby.size():
			var p: Dictionary = Net.lobby[i]
			var hid := String(p.get("hero", "kaela"))
			var hname := String(Game.HEROES.get(hid, {}).get("name", hid)).split(" ")[0]
			var who := "Host" if int(p.get("peer", 0)) == 1 else "Player %d" % (i + 1)
			if int(p.get("peer", 0)) == Net.my_id():
				who += " (you)"
			var l := _label("%s  -  %s" % [who, hname], "", 22)
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
	# free menus
	if is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_shard_label = null
	_shop_box = null
	_hero_cards = {}
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
	_bg(r, TEX_FLOOR, 0.22)
	_vignette(r, 0.5, 0.85)
	if victory:
		_embers(r)
	var c := CenterContainer.new()
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.add_child(c)
	var p := PanelContainer.new()
	p.theme_type_variation = "CardPanelSelected" if victory else "PanelContainer"
	p.custom_minimum_size = Vector2(680, 0)
	c.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 16)
	p.add_child(v)
	var title := VTheme.title_label("VICTORY" if victory else "FALLEN", 84, VTheme.GOLD_BRIGHT if victory else Color(0.85, 0.55, 0.95), 14)
	v.add_child(title)
	var sub := _label("The Hollow Regent is unmade." if victory else "The Veil returns you to the Sanctum.", "HeaderLabel")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(sub)
	var sh := HBoxContainer.new()
	sh.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(sh)
	sh.add_child(_shard_icon())
	var sl := _label("+%d Veil Shards" % earned, "", 34)
	sl.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	sh.add_child(sl)
	var room := _label("Rooms cleared: %d      Deepest: %d" % [Game.run_room, int(Game.data.get("best_room", 0))], "DimLabel", 22)
	room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(room)
	var quote := _label("\"%s\"" % (StoryData.VICTORY[3]["text"] if victory else StoryData.death_line()), "", 24)
	quote.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	quote.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	quote.custom_minimum_size = Vector2(620, 0)
	quote.add_theme_color_override("font_color", StoryData.speaker("ysolde")["color"])
	v.add_child(quote)
	var who := _label("- Matron Ysolde", "DimLabel")
	who.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	v.add_child(who)
	var btn := _button("Return to the Sanctum", func():
		if victory:
			play_dialogue(StoryData.VICTORY, show_sanctum)
		else:
			show_sanctum(), "BigButton", 420)
	btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(btn)
	_fade_in(r, 0.6)
	_focus_first(btn)


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
