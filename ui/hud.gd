extends CanvasLayer
## In-run HUD: health, dash pips, special cooldown, boons, boss bar, banners,
## boon choice cards, pause menu and touch controls.

const TouchScript := preload("res://ui/touch.gd")
const GOLD := Color(1.0, 0.82, 0.4)
const INK := Color(0.05, 0.02, 0.06)

var arena: Node
var local_heroes: Array = []
var touch: Control = null
var root: Control
var drawer: Control
var room_label: Label
var banner: Label
var boon_panel: PanelContainer
var pause_panel: PanelContainer
var _portraits: Array = []
var _boon_labels: Array = []
var _banner_t := 0.0

func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS

func add_local_hero(h: Node) -> void:
	local_heroes.append(h)

func _style(bg: Color, border: Color, w := 3) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border
	sb.set_border_width_all(w)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(14)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 6
	return sb

func _label(text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 6)
	return l

func build() -> void:
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	drawer = Control.new()
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.draw.connect(_draw_bars)
	root.add_child(drawer)
	for i in range(local_heroes.size()):
		var h: Node = local_heroes[i]
		var tex: Texture2D = load("res://art/%s.png" % h.hero_id)
		var at := AtlasTexture.new()
		at.atlas = tex
		var w := float(tex.get_width())
		at.region = Rect2(w * 0.3, 0, w * 0.42, w * 0.42)
		var tr := TextureRect.new()
		tr.texture = at
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		tr.position = Vector2(20, 18 + i * 110)
		tr.size = Vector2(76, 76)
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(tr)
		_portraits.append(tr)
		var bl := _label("", 15, Color(0.95, 0.9, 0.8))
		bl.position = Vector2(108, 78 + i * 110)
		root.add_child(bl)
		_boon_labels.append(bl)
	room_label = _label("", 22, GOLD)
	room_label.set_anchors_preset(Control.PRESET_CENTER_TOP)
	room_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	room_label.position = Vector2(-300, 14)
	room_label.size = Vector2(600, 30)
	root.add_child(room_label)
	banner = _label("", 44, GOLD)
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	banner.position = Vector2(-500, -160)
	banner.size = Vector2(1000, 60)
	banner.modulate.a = 0.0
	root.add_child(banner)
	var pause_btn := Button.new()
	pause_btn.text = "II"
	pause_btn.add_theme_font_size_override("font_size", 26)
	pause_btn.add_theme_stylebox_override("normal", _style(Color(0.1, 0.05, 0.12, 0.8), GOLD, 2))
	pause_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	pause_btn.position = Vector2(-84, 14)
	pause_btn.size = Vector2(64, 64)
	pause_btn.focus_mode = Control.FOCUS_NONE
	pause_btn.pressed.connect(_toggle_pause)
	root.add_child(pause_btn)
	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		touch = TouchScript.new()
		root.add_child(touch)
		for h in local_heroes:
			if h.local_index == 0:
				touch.hero = h
	refresh()

func refresh() -> void:
	for i in range(min(local_heroes.size(), _boon_labels.size())):
		var h: Node = local_heroes[i]
		if not is_instance_valid(h):
			continue
		var names: Array = []
		for id in h.boons.keys():
			if String(id).begins_with("_"):
				continue
			var b := Game.boon_by_id(id)
			names.append("%s %s" % [b.get("name", id), "I".repeat(int(h.boons[id]["level"]))])
		_boon_labels[i].text = "  ·  ".join(names)

func set_room_name(t: String) -> void:
	if room_label:
		room_label.text = t

func float_banner(text: String, color: Color) -> void:
	if banner == null:
		return
	banner.text = text
	banner.add_theme_color_override("font_color", color)
	banner.modulate.a = 1.0
	banner.scale = Vector2(1.15, 1.15)
	banner.pivot_offset = banner.size / 2
	var tw := create_tween()
	tw.tween_property(banner, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_interval(1.4)
	tw.tween_property(banner, "modulate:a", 0.0, 0.5)

func _process(_delta: float) -> void:
	if drawer:
		drawer.queue_redraw()

func _draw_bars() -> void:
	var font := ThemeDB.fallback_font
	for i in range(local_heroes.size()):
		var h: Node = local_heroes[i]
		if not is_instance_valid(h):
			continue
		var y := 18.0 + i * 110.0
		drawer.draw_rect(Rect2(18, y - 2, 80, 80), GOLD, false, 3.0)
		var x := 108.0
		var w := 260.0
		var frac := clampf(h.hp / float(h.max_hp), 0.0, 1.0)
		drawer.draw_rect(Rect2(x - 3, y + 4, w + 6, 30), INK)
		drawer.draw_rect(Rect2(x, y + 7, w, 24), Color(0.25, 0.05, 0.08))
		drawer.draw_rect(Rect2(x, y + 7, w * frac, 24), Color(0.85, 0.15, 0.2) if frac > 0.3 else Color(1, 0.35, 0.2))
		drawer.draw_rect(Rect2(x, y + 7, w * frac, 7), Color(1, 1, 1, 0.25))
		var hp_text := "%d / %d" % [int(ceil(h.hp)), h.max_hp]
		if h.downed:
			hp_text = "DOWNED"
		drawer.draw_string_outline(font, Vector2(x + 8, y + 26), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, INK)
		drawer.draw_string(font, Vector2(x + 8, y + 26), hp_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		var maxd: int = 1 + int(h.stats.get("dash_charges", 0))
		for d in range(maxd):
			var c := Vector2(x + 10 + d * 24, y + 52)
			drawer.draw_circle(c, 9, INK)
			drawer.draw_circle(c, 7, Color(0.55, 0.85, 1.0) if d < h.dash_charges else Color(0.2, 0.25, 0.3))
		var sp := 1.0 - clampf(h.special_cd / 2.6, 0.0, 1.0)
		var sc := Vector2(x + w - 14, y + 52)
		drawer.draw_circle(sc, 12, INK)
		drawer.draw_arc(sc, 9, -PI / 2, -PI / 2 + TAU * sp, 24, Color(0.85, 0.5, 1.0), 5.0)
		if local_heroes.size() > 1:
			drawer.draw_string_outline(font, Vector2(x + w + 12, y + 26), "P%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, 5, INK)
			drawer.draw_string(font, Vector2(x + w + 12, y + 26), "P%d" % (i + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, GOLD)
	var vs := drawer.size
	var shard_text := "Veil Shards: %d" % Game.run_shards
	if Net.online:
		shard_text += "   Ping: %d ms" % Net.ping_ms if not Net.is_host() else "   Hosting"
	drawer.draw_string_outline(font, Vector2(vs.x - 520, 52), shard_text, HORIZONTAL_ALIGNMENT_RIGHT, 410, 20, 5, INK)
	drawer.draw_string(font, Vector2(vs.x - 520, 52), shard_text, HORIZONTAL_ALIGNMENT_RIGHT, 410, 20, GOLD)
	# Boss bar.
	if arena:
		for e in arena.enemies():
			if e.kind == "regent":
				var bw := minf(720.0, vs.x - 200.0)
				var bx := (vs.x - bw) / 2.0
				var by := 54.0
				var f := clampf(e.hp / e.max_hp, 0.0, 1.0)
				drawer.draw_rect(Rect2(bx - 4, by - 4, bw + 8, 26), INK)
				drawer.draw_rect(Rect2(bx, by, bw, 18), Color(0.2, 0.05, 0.25))
				drawer.draw_rect(Rect2(bx, by, bw * f, 18), Color(0.7, 0.3, 0.95))
				drawer.draw_rect(Rect2(bx + bw * 0.5 - 1, by, 2, 18), GOLD)
				drawer.draw_string_outline(font, Vector2(bx, by + 44), "THE HOLLOW REGENT", HORIZONTAL_ALIGNMENT_CENTER, bw, 20, 5, INK)
				drawer.draw_string(font, Vector2(bx, by + 44), "THE HOLLOW REGENT", HORIZONTAL_ALIGNMENT_CENTER, bw, 20, Color(0.9, 0.75, 1.0))
				break

# ---------------------------------------------------------------- boon choice

func show_boon_choice(hero: Node, choices: Array, on_pick: Callable) -> void:
	if boon_panel and is_instance_valid(boon_panel):
		boon_panel.queue_free()
	var first: Dictionary = Game.boon_by_id(choices[0]["id"])
	var patron: Dictionary = Game.PATRONS[first["patron"]]
	boon_panel = PanelContainer.new()
	boon_panel.add_theme_stylebox_override("panel", _style(Color(0.06, 0.03, 0.08, 0.94), patron["color"], 3))
	boon_panel.set_anchors_preset(Control.PRESET_CENTER)
	boon_panel.custom_minimum_size = Vector2(760, 0)
	boon_panel.position = Vector2(-380, -250)
	root.add_child(boon_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	boon_panel.add_child(v)
	var who := ""
	if local_heroes.size() > 1:
		who = "Player %d: " % (local_heroes.find(hero) + 1)
	var title := _label("%sThe Wardens offer a gift" % who, 28, GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(title)
	var story = load("res://data/story.gd")
	if story and story.has_method("warden_line"):
		var line := _label("“%s”" % str(story.warden_line(first["patron"])), 18, patron["color"].lightened(0.3))
		line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(line)
	var first_btn: Button = null
	for c in choices:
		var b := Game.boon_by_id(c["id"])
		var pat: Dictionary = Game.PATRONS[b["patron"]]
		var r: int = c["rarity"]
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(0, 92)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_stylebox_override("normal", _style(Color(0.12, 0.07, 0.14), pat["color"].darkened(0.2), 2))
		btn.add_theme_stylebox_override("hover", _style(Color(0.2, 0.12, 0.22), pat["color"], 3))
		btn.add_theme_stylebox_override("focus", _style(Color(0.2, 0.12, 0.22), GOLD, 3))
		btn.add_theme_stylebox_override("pressed", _style(Color(0.3, 0.18, 0.3), GOLD, 3))
		var up := "  (Upgrade)" if c["upgrade"] else ""
		btn.text = "%s  —  %s%s\n%s   ·   %s" % [b["name"], Game.RARITY_NAMES[r], up, Game.boon_text(c["id"], r), pat["name"]]
		btn.add_theme_color_override("font_color", Game.RARITY_COLORS[r].lightened(0.2))
		btn.pressed.connect(func():
			if is_instance_valid(boon_panel):
				boon_panel.queue_free()
			boon_panel = null
			on_pick.call(c["id"], r))
		v.add_child(btn)
		if first_btn == null:
			first_btn = btn
	boon_panel.scale = Vector2(0.85, 0.85)
	boon_panel.pivot_offset = Vector2(380, 250)
	create_tween().tween_property(boon_panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if first_btn:
		first_btn.call_deferred("grab_focus")

# ---------------------------------------------------------------- pause

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_toggle_pause()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_toggle_pause()

func _toggle_pause() -> void:
	if pause_panel and is_instance_valid(pause_panel):
		pause_panel.queue_free()
		pause_panel = null
		get_tree().paused = false
		return
	if not Net.online:
		get_tree().paused = true
	pause_panel = PanelContainer.new()
	pause_panel.add_theme_stylebox_override("panel", _style(Color(0.06, 0.03, 0.08, 0.95), GOLD))
	pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	pause_panel.position = Vector2(-200, -150)
	pause_panel.custom_minimum_size = Vector2(400, 0)
	root.add_child(pause_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	pause_panel.add_child(v)
	var t := _label("Paused" if not Net.online else "Menu (co-op keeps running)", 28, GOLD)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var resume := _menu_button("Resume")
	resume.pressed.connect(_toggle_pause)
	v.add_child(resume)
	var quit := _menu_button("Abandon run")
	quit.pressed.connect(func():
		_toggle_pause()
		if arena: arena.abandon())
	v.add_child(quit)
	resume.call_deferred("grab_focus")

func _menu_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_stylebox_override("normal", _style(Color(0.12, 0.07, 0.14), GOLD.darkened(0.3), 2))
	b.add_theme_stylebox_override("hover", _style(Color(0.2, 0.12, 0.22), GOLD, 3))
	b.add_theme_stylebox_override("focus", _style(Color(0.2, 0.12, 0.22), GOLD, 3))
	return b

func _exit_tree() -> void:
	get_tree().paused = false
