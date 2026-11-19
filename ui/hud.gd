extends CanvasLayer
## In-run HUD: heroine medallions, health, dash pips, special cooldown, boon row (+ tooltips), room banner,
## boss bar, low-health vignette, banners, boon choice cards, pause / settings, touch controls.
## Public API used by arena.gd: add_local_hero, build, refresh, set_room_name, float_banner,
## show_boon_choice(hero, choices, on_pick), touch, boon_panel, arena, _toggle_pause.

const TouchScript := preload("res://ui/touch.gd")
const VTheme = preload("res://ui/theme.gd")
const Settings = preload("res://ui/settings.gd")
const FitBox = preload("res://ui/fit_box.gd")
const StoryData = preload("res://data/story.gd")
const GOLD := Color(1.0, 0.82, 0.4)
const INK := Color(0.05, 0.02, 0.06)
const SPECIAL_CD := 2.6
const ROW_H := 112.0
const BAR_X := 106.0
const LOW_HP := 0.35

var arena: Node
var local_heroes: Array = []
var touch: Control = null
var root: Control
var drawer: Control
var room_plate: PanelContainer
var room_label: Label
var banner: Control
var banner_label: Label
var boon_panel: Control = null
var pause_panel: Control = null
var _boon_rows: Array = []        ## HBoxContainer per local hero
var _tooltip: PanelContainer = null
var _tooltip_tw: Tween
var _vignette: TextureRect
var _vig_tw: Tween
var _low := false
var _last_hp: Array = []
var _sig := 0
var _boss: Node = null
var _boss_trail := 1.0
var _hp_trail: Array = []
var _shard_label: Label
var _gold_label: Label
var _card: Control = null
var _sub: Label = null
var _ping_label: Label
var _font: Font
var _font_caps: Font
var _tex_frame: Texture2D
var _tex_boss: Texture2D
var _tex_shard: Texture2D
var _tex_orb: Texture2D
var _tex_special: Texture2D


func _init() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS


func add_local_hero(h: Node) -> void:
	local_heroes.append(h)


func build() -> void:
	_font = VTheme.font("head")
	_font_caps = VTheme.font("caps")
	_tex_frame = VTheme.tex("hp_frame")
	_tex_boss = VTheme.tex("boss_frame")
	_tex_shard = VTheme.tex("shard")
	_tex_orb = VTheme.tex("orb")
	_tex_special = VTheme.tex("glyph_special")
	# root is the safe area (notches / cutouts); full-screen washes bleed past it
	root = Control.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = VTheme.get_theme()
	add_child(root)
	VTheme.fit_safe(root)

	_vignette = VTheme.image(VTheme.vignette_tex(Color(0.62, 0.0, 0.05, 1.0), 0.3), Vector2.ZERO, false)
	_vignette.modulate.a = 0.0
	root.add_child(_vignette)
	VTheme.bleed(_vignette)

	drawer = Control.new()
	drawer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	drawer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	drawer.draw.connect(_draw_bars)
	root.add_child(drawer)

	for i in range(local_heroes.size()):
		var h: Node = local_heroes[i]
		var y := 10.0 + i * ROW_H
		root.add_child(_medallion(String(h.hero_id), Vector2(10, y), 92.0, i))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.position = Vector2(BAR_X + 10, y + 74)
		row.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(row)
		_boon_rows.append(row)
		_last_hp.append(float(h.hp))
		_hp_trail.append(1.0)

	# room title ribbon
	room_plate = PanelContainer.new()
	room_plate.theme_type_variation = "Plate"
	room_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	room_plate.anchor_left = 0.5; room_plate.anchor_right = 0.5
	room_plate.grow_horizontal = Control.GROW_DIRECTION_BOTH
	room_plate.offset_top = 8; room_plate.offset_bottom = 64
	room_plate.custom_minimum_size = Vector2(320, 56)
	room_plate.modulate.a = 0.0
	root.add_child(room_plate)
	room_label = VTheme.title_label("", 20, VTheme.GOLD_BRIGHT, 5)
	room_plate.add_child(room_label)

	# centre banner
	banner = VBoxContainer.new()
	banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	banner.set_anchors_preset(Control.PRESET_CENTER)
	banner.offset_left = -600; banner.offset_right = 600; banner.offset_top = -200; banner.offset_bottom = -90
	banner.pivot_offset = Vector2(600, 55)
	banner.add_theme_constant_override("separation", -6)
	banner.modulate.a = 0.0
	root.add_child(banner)
	banner_label = VTheme.title_label("", 46, GOLD, 10, "display")
	banner.add_child(banner_label)
	banner.add_child(VTheme.divider(460, 34))

	# shard purse + pause (top right)
	var purse := HBoxContainer.new()
	purse.mouse_filter = Control.MOUSE_FILTER_IGNORE
	purse.add_theme_constant_override("separation", 6)
	purse.anchor_left = 1; purse.anchor_right = 1
	purse.offset_left = -430; purse.offset_right = -96; purse.offset_top = 18; purse.offset_bottom = 58
	purse.alignment = BoxContainer.ALIGNMENT_END
	root.add_child(purse)
	var gi := VTheme.image("reward_gold", Vector2(34, 34))
	gi.mouse_filter = Control.MOUSE_FILTER_IGNORE
	purse.add_child(gi)
	_gold_label = VTheme.title_label("0", 28, Color(1.0, 0.85, 0.35), 6)
	purse.add_child(_gold_label)
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(14, 0)
	purse.add_child(gap)
	purse.add_child(VTheme.shard_icon(32))
	_shard_label = VTheme.title_label("0", 28, VTheme.GOLD_BRIGHT, 6)
	purse.add_child(_shard_label)
	_ping_label = VTheme.label("", "Dim", 16)
	_ping_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_ping_label.anchor_left = 1; _ping_label.anchor_right = 1
	_ping_label.offset_left = -300; _ping_label.offset_right = -96; _ping_label.offset_top = 58; _ping_label.offset_bottom = 80
	root.add_child(_ping_label)

	var pause_btn := Button.new()
	pause_btn.theme_type_variation = "IconButton"
	pause_btn.anchor_left = 1; pause_btn.anchor_right = 1
	pause_btn.offset_left = -88; pause_btn.offset_right = -14; pause_btn.offset_top = 8; pause_btn.offset_bottom = 82
	pause_btn.focus_mode = Control.FOCUS_NONE
	var orb := VTheme.image("orb", Vector2.ZERO, false)
	orb.set_anchors_preset(Control.PRESET_FULL_RECT)
	pause_btn.add_child(orb)
	var pg := VTheme.image("glyph_pause")
	pg.set_anchors_preset(Control.PRESET_FULL_RECT)
	pg.offset_left = 22; pg.offset_right = -22; pg.offset_top = 20; pg.offset_bottom = -20
	pause_btn.add_child(pg)
	VTheme.juice(pause_btn, 1.08, "open")
	pause_btn.pressed.connect(_toggle_pause)
	root.add_child(pause_btn)

	if DisplayServer.is_touchscreen_available() or OS.has_feature("mobile"):
		touch = TouchScript.new()
		root.add_child(touch)
		for h in local_heroes:
			if h.local_index == 0:
				touch.hero = h
	refresh()


## Round portrait in a gilded ring.
func _medallion(hid: String, pos: Vector2, size: float, idx: int) -> Control:
	var holder := Control.new()
	holder.position = pos
	holder.size = Vector2(size, size)
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var face := VTheme.image(VTheme.tex("face_" + hid), Vector2.ZERO, false)
	face.position = Vector2(size * 0.1, size * 0.1)
	face.size = Vector2(size * 0.8, size * 0.8)
	holder.add_child(face)
	var ring := VTheme.image("ring", Vector2.ZERO, false)
	ring.size = Vector2(size, size)
	holder.add_child(ring)
	if local_heroes.size() > 1:
		var tag := VTheme.title_label("P%d" % (idx + 1), 16, VTheme.GOLD_BRIGHT, 5)
		tag.position = Vector2(0, size - 22)
		tag.size = Vector2(size, 22)
		holder.add_child(tag)
	return holder


func refresh() -> void:
	for i in range(min(local_heroes.size(), _boon_rows.size())):
		var h: Node = local_heroes[i]
		var row: HBoxContainer = _boon_rows[i]
		if not is_instance_valid(h):
			continue
		for c in row.get_children():
			c.queue_free()
		for id in h.boons.keys():
			if String(id).begins_with("_"):
				continue
			var info: Dictionary = h.boons[id]
			row.add_child(_boon_chip(String(id), int(info.get("level", 1)), int(info.get("rarity", 0))))
		var forge: Dictionary = h.boons.get("_forge", {})
		for id in forge.keys():
			var info: Dictionary = forge[id]
			row.add_child(_boon_chip(String(id), int(info.get("level", 1)), int(info.get("rarity", 0)), true))


func _boon_chip(id: String, level: int, rarity: int, forge := false) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(42, 42)
	c.mouse_filter = Control.MOUSE_FILTER_STOP
	var ring := Panel.new()
	ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ring.set_anchors_preset(Control.PRESET_FULL_RECT)
	var rc: Color = Game.RARITY_COLORS[clampi(rarity, 0, 2)]
	var sb := VTheme.box(Color(0.06, 0.03, 0.07, 0.85), rc.lerp(VTheme.GOLD, 0.35), 2, 21, 4, Color(0, 0, 0, 0.5), 0, 0)
	ring.add_theme_stylebox_override("panel", sb)
	c.add_child(ring)
	var ictex := VTheme.boon_icon(id)
	if forge:
		ictex = VTheme.tex(String(Game.WEAPONS.get(String(Game.forge_by_id(id).get("weapon", "")), {}).get("icon", "reward_forge")))
	var ic := VTheme.image(ictex, Vector2.ZERO, forge)
	ic.set_anchors_preset(Control.PRESET_FULL_RECT)
	ic.offset_left = 3; ic.offset_top = 3; ic.offset_right = -3; ic.offset_bottom = -3
	c.add_child(ic)
	if level > 1:
		var lv := VTheme.title_label(VTheme.roman(level), 13, VTheme.GOLD_BRIGHT, 4)
		lv.position = Vector2(20, 26)
		lv.size = Vector2(24, 16)
		c.add_child(lv)
	c.gui_input.connect(func(e: InputEvent):
		if (e is InputEventMouseButton and e.pressed) or (e is InputEventScreenTouch and e.pressed):
			c.accept_event()
			_show_tooltip(id, level, rarity, c, forge))
	return c


func _show_tooltip(id: String, level: int, rarity: int, at: Control, forge := false) -> void:
	if is_instance_valid(_tooltip):
		_tooltip.queue_free()
	var b := Game.boon_by_id(id) if not forge else Game.forge_by_id(id)
	var pat: Dictionary = Game.PATRONS.get(b.get("patron", ""), {}) if not forge else {"name": "Forge"}
	var t := PanelContainer.new()
	t.theme_type_variation = "PanelSm"
	t.mouse_filter = Control.MOUSE_FILTER_IGNORE
	t.custom_minimum_size = Vector2(330, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 0)
	t.add_child(v)
	var n := VTheme.label("%s %s" % [b.get("name", id), VTheme.roman(level)], "Gold", 22)
	v.add_child(n)
	var r := VTheme.label("%s  ·  %s" % [String(Game.RARITY_NAMES[rarity]).to_upper(), String(pat.get("name", "")).to_upper()], "Caps", 13)
	r.add_theme_color_override("font_color", Game.RARITY_COLORS[rarity])
	v.add_child(r)
	var d := VTheme.label(Game.boon_text(id, rarity, level) if not forge else Game.forge_text(id, rarity, level), "Body", 19)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(270, 0)
	v.add_child(d)
	root.add_child(t)
	t.position = at.global_position + Vector2(-8, 50)
	_tooltip = t
	t.modulate.a = 0.0
	if _tooltip_tw and _tooltip_tw.is_valid():
		_tooltip_tw.kill()
	_tooltip_tw = t.create_tween()
	_tooltip_tw.tween_property(t, "modulate:a", 1.0, 0.15)
	_tooltip_tw.tween_interval(2.6)
	_tooltip_tw.tween_property(t, "modulate:a", 0.0, 0.3)
	_tooltip_tw.tween_callback(t.queue_free)
	VTheme.sound("hover")


func set_room_name(t: String) -> void:
	if room_label == null:
		return
	room_label.text = t
	room_plate.visible = true
	room_plate.position.y = -40
	room_plate.modulate.a = 0.0
	var tw := room_plate.create_tween().set_parallel()
	tw.tween_property(room_plate, "position:y", 8.0, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(room_plate, "modulate:a", 1.0, 0.3)


## Chapter title card: big title, the narrator's line under it; fades by itself, never blocks input.
func show_chapter_card(title: String, line := "") -> void:
	if root == null:
		return
	if is_instance_valid(_card):
		_card.queue_free()
	var c := Control.new()
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	_card = c
	var band := ColorRect.new()
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	band.color = Color(0.02, 0.01, 0.03, 0.62)
	band.anchor_right = 1.0
	band.anchor_top = 0.5; band.anchor_bottom = 0.5
	band.offset_top = -150; band.offset_bottom = 120
	c.add_child(band)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_theme_constant_override("separation", 2)
	v.anchor_right = 1.0
	v.anchor_top = 0.5; v.anchor_bottom = 0.5
	v.offset_top = -150; v.offset_bottom = 120
	c.add_child(v)
	var parts := title.split(":", false, 1)
	if parts.size() == 2:
		var pre := VTheme.title_label(parts[0].strip_edges().to_upper(), 24, Color(0.85, 0.75, 0.95), 6, "caps")
		pre.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(pre)
	var t := VTheme.title_label(parts[parts.size() - 1].strip_edges(), 64, GOLD, 12, "display")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var dv := VTheme.divider(520, 34)
	dv.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	v.add_child(dv)
	if line != "":
		var q := VTheme.label("“%s”" % line, "Quote", 22)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		q.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		q.custom_minimum_size = Vector2(minf(900.0, root.size.x - 80.0), 0)
		q.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		v.add_child(q)
	c.modulate.a = 0.0
	var tw := c.create_tween()
	tw.tween_property(c, "modulate:a", 1.0, 0.6)
	tw.tween_interval(3.4)
	tw.tween_property(c, "modulate:a", 0.0, 0.9)
	tw.tween_callback(c.queue_free)


## A spoken line at the bottom of the screen (boss taunts, last words).
func subtitle(text: String, color := Color(0.95, 0.85, 1.0)) -> void:
	if root == null or text == "":
		return
	if is_instance_valid(_sub):
		_sub.queue_free()
	var l := VTheme.label(text, "Quote", 24, color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.anchor_left = 0.5; l.anchor_right = 0.5; l.anchor_top = 1.0; l.anchor_bottom = 1.0
	l.offset_left = -460; l.offset_right = 460; l.offset_top = -250; l.offset_bottom = -170
	l.add_theme_color_override("font_outline_color", INK)
	l.add_theme_constant_override("outline_size", 8)
	root.add_child(l)
	_sub = l
	var tw := l.create_tween()
	l.modulate.a = 0.0
	tw.tween_property(l, "modulate:a", 1.0, 0.25)
	tw.tween_interval(3.2)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


## A patron's line for the boon card, in context (Audio.voice also plays a clip when one exists).
func _patron_quote(patron_id: String) -> String:
	var ctx := "greet"
	var sdb = load("res://data/story_db.gd")
	var p: Dictionary = sdb.from_save(Game.data)
	if not sdb.has_flag(p, "warden_met_" + patron_id):
		ctx = "first_meeting"
		sdb.set_flag(p, "warden_met_" + patron_id)
	elif arena and arena.plan_room.get("type", "") == "boss":
		ctx = "boss_floor"
	elif _any_low():
		ctx = "low_health"
	elif Net.online or local_heroes.size() > 1:
		ctx = "coop"
	var audio := get_node_or_null("/root/Audio")
	var t := ""
	if audio and audio.has_method("voice"):
		t = String(audio.voice(patron_id, ctx))
	if t == "":
		t = str(StoryData.warden_line(patron_id))
	return t


func _any_low() -> bool:
	for h in local_heroes:
		if is_instance_valid(h) and h.hp < h.max_hp * 0.35:
			return true
	return false


func float_banner(text: String, color: Color) -> void:
	if banner == null:
		return
	banner_label.text = text
	banner_label.add_theme_color_override("font_color", color)
	banner.modulate.a = 0.0
	banner.scale = Vector2(1.25, 1.25)
	var tw := banner.create_tween()
	tw.set_parallel()
	tw.tween_property(banner, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(banner, "modulate:a", 1.0, 0.2)
	tw.chain().tween_interval(1.4)
	tw.chain().tween_property(banner, "modulate:a", 0.0, 0.5)


# ---------------------------------------------------------------- per-frame (cheap; redraw only on change)

func _process(delta: float) -> void:
	if drawer == null:
		return
	var sig := 17
	for i in range(local_heroes.size()):
		var h: Node = local_heroes[i]
		if not is_instance_valid(h):
			continue
		var frac := clampf(h.hp / float(max(1, h.max_hp)), 0.0, 1.0)
		sig = sig * 31 + int(h.hp * 4.0)
		sig = sig * 31 + int(h.max_hp)
		sig = sig * 31 + int(h.dash_charges)
		sig = sig * 31 + int(h.special_cd * 20.0)
		sig = sig * 31 + (1 if h.downed else 0)
		if h.hp < _last_hp[i] - 0.5 and h.local_index == 0:
			_hit_flash()
		_last_hp[i] = h.hp
		if _hp_trail[i] > frac:
			_hp_trail[i] = maxf(frac, _hp_trail[i] - delta * 0.6)
			sig = sig * 31 + int(_hp_trail[i] * 400.0)
		else:
			_hp_trail[i] = frac
	_update_low_hp()
	# boss
	if not is_instance_valid(_boss):
		_boss = null
		if arena and Engine.get_process_frames() % 15 == 0:
			for e in arena.enemies():
				if e.get("is_boss"):
					_boss = e
					_boss_trail = 1.0
					_on_boss_appear()
					break
	if _boss:
		var bf := clampf(_boss.hp / _boss.max_hp, 0.0, 1.0)
		if _boss_trail > bf:
			_boss_trail = maxf(bf, _boss_trail - delta * 0.35)
		else:
			_boss_trail = bf
		sig = sig * 31 + int(_boss.hp)
		if _boss.has_method("shielded") and _boss.shielded():
			sig = sig * 31 + Time.get_ticks_msec() / 50
		sig = sig * 31 + int(_boss_trail * 500.0)
	var sh := Game.run_shards
	var gold := Game.run_gold
	if arena and arena.has_method("purse"): # the manor hub shows the banked purse
		var pv: Array = arena.purse()
		sh = int(pv[0])
		gold = int(pv[1])
	sig = sig * 31 + sh
	sig = sig * 31 + gold
	if sig != _sig:
		_sig = sig
		_shard_label.text = str(sh)
		_gold_label.text = str(gold)
		drawer.queue_redraw()
	if Net.online and Engine.get_process_frames() % 30 == 0:
		_ping_label.text = "Hosting" if Net.is_host() else "Ping %d ms" % Net.ping_ms


func _on_boss_appear() -> void:
	if room_plate:
		var tw := room_plate.create_tween()
		tw.tween_property(room_plate, "modulate:a", 0.0, 0.3)
		tw.tween_callback(func(): room_plate.visible = false)


func _hit_flash() -> void:
	if _vig_tw and _vig_tw.is_valid() and not _low:
		_vig_tw.kill()
	if _low:
		return
	_vignette.modulate.a = 0.55
	_vig_tw = _vignette.create_tween()
	_vig_tw.tween_property(_vignette, "modulate:a", 0.0, 0.45)


func _update_low_hp() -> void:
	var low := false
	for h in local_heroes:
		if is_instance_valid(h) and h.local_index == 0 and not h.downed and h.hp / float(max(1, h.max_hp)) < LOW_HP:
			low = true
	if low == _low:
		return
	_low = low
	if _vig_tw and _vig_tw.is_valid():
		_vig_tw.kill()
	_vig_tw = _vignette.create_tween()
	if low:
		_vig_tw.set_loops()
		_vig_tw.tween_property(_vignette, "modulate:a", 0.75, 0.45).set_trans(Tween.TRANS_SINE)
		_vig_tw.tween_property(_vignette, "modulate:a", 0.35, 0.65).set_trans(Tween.TRANS_SINE)
	else:
		_vig_tw.tween_property(_vignette, "modulate:a", 0.0, 0.4)


func _draw_bars() -> void:
	for i in range(local_heroes.size()):
		var h: Node = local_heroes[i]
		if not is_instance_valid(h):
			continue
		var y := 10.0 + i * ROW_H
		var bx := BAR_X
		var by := y + 10.0
		var frac := clampf(h.hp / float(max(1, h.max_hp)), 0.0, 1.0)
		# interior of hp_frame.png (400x35): x 28..372, y 9..26
		var ix := bx + 26.0
		var iw := 348.0
		var iy := by + 8.0
		var ih := 19.0
		drawer.draw_rect(Rect2(ix, iy, iw, ih), Color(0.09, 0.02, 0.04, 0.92))
		var trail: float = _hp_trail[i] if i < _hp_trail.size() else frac
		if trail > frac:
			drawer.draw_rect(Rect2(ix + iw * frac, iy, iw * (trail - frac), ih), Color(1.0, 0.85, 0.6, 0.85))
		var c1 := Color(0.86, 0.12, 0.16) if frac > LOW_HP else Color(1.0, 0.32, 0.14)
		drawer.draw_rect(Rect2(ix, iy, iw * frac, ih), c1)
		drawer.draw_rect(Rect2(ix, iy, iw * frac, ih * 0.38), Color(1, 0.75, 0.65, 0.28))
		drawer.draw_rect(Rect2(ix, iy + ih - 4, iw * frac, 4), Color(0.3, 0.0, 0.05, 0.45))
		if _tex_frame:
			drawer.draw_texture_rect(_tex_frame, Rect2(bx, by, 400, 35), false)
		var hp_text := "%d / %d" % [int(ceil(h.hp)), h.max_hp]
		if h.downed:
			hp_text = "DOWNED"
		_text_c(Vector2(ix, by + 25), iw, hp_text, 16, Color(1, 0.95, 0.88))
		# dash pips (shard gems)
		var maxd: int = 1 + int(h.stats.get("dash_charges", 0))
		var px := bx + 28.0
		for d in range(maxd):
			var lit: bool = d < h.dash_charges
			if _tex_shard:
				drawer.draw_texture_rect(_tex_shard, Rect2(px + d * 20.0, by + 35.0, 15, 26), false, Color(1, 1, 1) if lit else Color(0.22, 0.2, 0.26, 0.9))
		# special: gilded orb + cooldown ring
		var sp := 1.0 - clampf(h.special_cd / maxf(0.1, float(h.special_cd_max)), 0.0, 1.0)
		var sc := Vector2(bx + 400.0 + 26.0, by + 18.0)
		if _tex_orb:
			drawer.draw_texture_rect(_tex_orb, Rect2(sc - Vector2(26, 26), Vector2(52, 52)), false)
		if _tex_special:
			var a := 1.0 if sp >= 1.0 else 0.35
			drawer.draw_texture_rect(_tex_special, Rect2(sc - Vector2(15, 15), Vector2(30, 30)), false, Color(1, 1, 1, a))
		if sp < 1.0:
			drawer.draw_arc(sc, 19.0, -PI / 2, -PI / 2 + TAU * sp, 32, Color(0.95, 0.6, 1.0, 0.95), 4.0, true)
	# boss bar
	if _boss and is_instance_valid(_boss):
		var vs := drawer.size
		# top centre between the heroine cluster and the purse; on narrow screens drop to the bottom centre
		var top_room := vs.x - 2.0 * 575.0
		var bw := clampf(top_room, 480.0, 760.0)
		var by2 := 2.0
		if top_room < 480.0:
			bw = clampf(vs.x - 2.0 * 400.0, 380.0, 640.0)
		var s := bw / 760.0
		var bh := 119.0 * s
		var bx2 := (vs.x - bw) * 0.5
		if top_room < 480.0:
			by2 = vs.y - bh - 40.0
		var f := clampf(_boss.hp / _boss.max_hp, 0.0, 1.0)
		# interior of boss_frame.png (760x119): x 60..700, y 63..91
		var ix2 := bx2 + 60.0 * s
		var iw2 := 640.0 * s
		var iy2 := by2 + 63.0 * s
		var ih2 := 28.0 * s
		drawer.draw_rect(Rect2(ix2, iy2, iw2, ih2), Color(0.06, 0.02, 0.08, 0.95))
		if _boss_trail > f:
			drawer.draw_rect(Rect2(ix2 + iw2 * f, iy2, iw2 * (_boss_trail - f), ih2), Color(1.0, 0.9, 0.7, 0.85))
		drawer.draw_rect(Rect2(ix2, iy2, iw2 * f, ih2), Color(0.62, 0.24, 0.9))
		drawer.draw_rect(Rect2(ix2, iy2, iw2 * f, ih2 * 0.4), Color(0.95, 0.75, 1.0, 0.3))
		# one tick per stage break; a passed break dims
		var marks: Array = _boss.phase_marks() if _boss.has_method("phase_marks") else [0.5]
		for m in marks:
			var mx := ix2 + iw2 * float(m)
			var on := f > float(m)
			drawer.draw_rect(Rect2(mx - 1.5, iy2 - 3.0, 3.0, ih2 + 6.0), Color(1, 0.85, 0.5, 0.9 if on else 0.3))
		if _boss.has_method("shielded") and _boss.shielded():
			drawer.draw_rect(Rect2(ix2, iy2, iw2, ih2), Color(1.0, 0.9, 0.6, 0.25 + 0.15 * sin(Time.get_ticks_msec() * 0.012)), false, 3.0)
		if _tex_boss:
			drawer.draw_texture_rect(_tex_boss, Rect2(bx2, by2, bw, bh), false)
		_text_c(Vector2(bx2, by2 + bh + 16), bw, (_boss.display_name() if _boss.has_method("display_name") else "The Hollow Regent").to_upper(), 20, Color(0.92, 0.8, 1.0), _font_caps)


func _text_c(pos: Vector2, width: float, text: String, size: int, col: Color, f: Font = null) -> void:
	var fo: Font = f if f else _font
	drawer.draw_string_outline(fo, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, 6, INK)
	drawer.draw_string(fo, pos, text, HORIZONTAL_ALIGNMENT_CENTER, width, size, col)


# ---------------------------------------------------------------- boon choice

## Forge reward: 3 weapon upgrades as cards (same card layout as boons). choices: Game.roll_forge().
func show_forge_choice(hero: Node, choices: Array, on_pick: Callable) -> void:
	show_boon_choice(hero, choices, on_pick)


func show_boon_choice(hero: Node, choices: Array, on_pick: Callable) -> void:
	if boon_panel and is_instance_valid(boon_panel):
		boon_panel.queue_free()
	if choices.is_empty():
		return
	var forge := bool(choices[0].get("forge", false))
	var first: Dictionary = Game.boon_by_id(choices[0]["id"])
	var patron_id := String(first.get("patron", "oriel"))
	var patron: Dictionary = Game.PATRONS.get(patron_id, {"name": "", "color": GOLD})
	if forge:
		var wd: Dictionary = Game.WEAPONS.get(String(hero.weapon_id), {})
		patron = {"name": String(wd.get("name", "")), "color": wd.get("color", GOLD)}
	var pcol: Color = patron["color"]
	var vs := root.size if root.size.x > 0.0 else root.get_viewport_rect().size
	# on tall screens (4:3, 16:10) the gift sits in the middle instead of hugging the top
	var oy := maxf(0.0, (vs.y - 720.0) * 0.5)
	VTheme.sound("boon")

	var ov := Control.new()
	ov.name = "BoonChoice"
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(ov)
	boon_panel = ov
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.03, 0.62)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ov.add_child(dim)
	VTheme.bleed(dim)
	var tint := VTheme.image(VTheme.vignette_tex(Color(pcol.r, pcol.g, pcol.b, 0.45), 0.3), Vector2.ZERO, false)
	ov.add_child(tint)
	VTheme.bleed(tint)
	_fade_node(ov, 0.25)

	# the Warden herself, sliding in from the left
	var wt := VTheme.warden_tex(patron_id) if not forge else null
	var cards_w := 3.0 * 300.0 + 2.0 * 22.0
	var card_x0 := (vs.x - cards_w) * 0.5
	if wt:
		var ph := 640.0
		var pw := ph * float(wt.get_width()) / float(wt.get_height())
		var room_left := card_x0
		var por := VTheme.image(wt, Vector2.ZERO, false)
		por.material = VTheme.material("fade_bottom")
		por.size = Vector2(pw, ph)
		var px := minf(room_left - pw * 0.55, 10.0)
		if vs.x >= 1500.0:
			card_x0 = maxf(card_x0, pw * 0.55)
			px = card_x0 - pw * 0.62
		por.position = Vector2(px - 120.0, vs.y - ph + 40.0)
		por.modulate.a = 0.0
		ov.add_child(por)
		var pt := por.create_tween().set_parallel()
		pt.tween_property(por, "position:x", px, 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		pt.tween_property(por, "modulate:a", 1.0, 0.35)

	var who := ""
	if local_heroes.size() > 1:
		who = "PLAYER %d  ·  " % (local_heroes.find(hero) + 1)
	var head_txt := "%sA GIFT FROM %s" % [who, String(patron["name"]).to_upper()]
	if forge:
		head_txt = "%sTHE FORGE  ·  TEMPER YOUR %s" % [who, String(patron["name"]).to_upper()]
	var head := VTheme.title_label(head_txt, 26, pcol.lightened(0.35), 7, "caps")
	head.position = Vector2(0, 16 + oy)
	head.size = Vector2(vs.x, 40)
	ov.add_child(head)
	var line_txt := _patron_quote(patron_id) if not forge else "Steel remembers every hand that shaped it. Choose what it becomes."
	var line := VTheme.label("“%s”" % line_txt, "Quote", 21)
	line.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	line.position = Vector2(vs.x * 0.5 - minf(420.0, vs.x * 0.5 - 20.0), 56 + oy)
	line.size = Vector2(minf(840.0, vs.x - 40.0), 60)
	line.add_theme_color_override("font_color", Color(0.96, 0.9, 0.82))
	ov.add_child(line)
	for c in [head, line]:
		_fade_node(c, 0.4, 0.15)

	var first_btn: Button = null
	var picked := [false]
	var card_y := 128.0 + oy
	for k in range(choices.size()):
		var c: Dictionary = choices[k]
		var card := _boon_card(c, hero)
		ov.add_child(card)
		var target := Vector2(card_x0 + k * 322.0, card_y)
		card.position = target + Vector2(0, 380)
		card.rotation = deg_to_rad(-6.0 + k * 6.0)
		card.modulate.a = 0.0
		var ct := card.create_tween().set_parallel()
		ct.tween_property(card, "position", target, 0.5).set_delay(0.12 + k * 0.09).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		ct.tween_property(card, "rotation", 0.0, 0.5).set_delay(0.12 + k * 0.09).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		ct.tween_property(card, "modulate:a", 1.0, 0.25).set_delay(0.12 + k * 0.09)
		var cid := String(c["id"])
		var rar := int(c["rarity"])
		card.pressed.connect(func():
			if picked[0]:
				return
			picked[0] = true
			VTheme.sound("confirm")
			_dismiss_choice(ov, card)
			if boon_panel == ov:
				boon_panel = null
			on_pick.call(cid, rar))
		if first_btn == null:
			first_btn = card
	if first_btn:
		first_btn.call_deferred("grab_focus")


func _boon_card(c: Dictionary, _hero: Node) -> Button:
	var forge := bool(c.get("forge", false))
	var b := Game.boon_by_id(c["id"]) if not forge else Game.forge_by_id(c["id"])
	var pid := String(b.get("patron", "oriel"))
	var pat: Dictionary = Game.PATRONS.get(pid, {"name": "", "color": GOLD})
	if forge:
		var wd: Dictionary = Game.WEAPONS.get(String(b.get("weapon", "")), {})
		pat = {"name": "Forge", "color": wd.get("color", GOLD)}
	var r: int = int(c["rarity"])
	var rcol: Color = VTheme.RARITY_TINT[clampi(r, 0, 2)]
	var btn := Button.new()
	btn.theme_type_variation = "IconButton"
	btn.custom_minimum_size = Vector2(300, 446)
	btn.size = Vector2(300, 446)
	btn.pivot_offset = Vector2(150, 223)
	btn.focus_mode = Control.FOCUS_ALL
	VTheme.juice(btn, 1.04, "")
	var frame := PanelContainer.new()
	frame.add_theme_stylebox_override("panel", VTheme.card_style(rcol))
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(frame)
	# patron glow behind icon
	var g := Gradient.new()
	var pc: Color = pat["color"]
	g.set_color(0, Color(pc.r, pc.g, pc.b, 0.55))
	g.set_color(1, Color(pc.r, pc.g, pc.b, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(0.5, 0.0)
	var glow := VTheme.image(gt, Vector2.ZERO, false)
	glow.position = Vector2(40, 50)
	glow.size = Vector2(220, 200)
	btn.add_child(glow)
	var ic := VTheme.image(VTheme.boon_icon(String(c["id"])) if not forge else VTheme.tex(String(Game.WEAPONS.get(String(b.get("weapon", "")), {}).get("icon", "reward_forge"))), Vector2.ZERO)
	ic.position = Vector2(82, 66)
	ic.size = Vector2(136, 136)
	btn.add_child(ic)
	# tiny warden face in the crest socket
	var face := VTheme.image(VTheme.tex("face_" + pid) if not forge else VTheme.tex("reward_forge"), Vector2.ZERO, forge)
	face.position = Vector2(150 - 20, 20)
	face.size = Vector2(40, 40)
	btn.add_child(face)
	var v := VBoxContainer.new()
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.add_theme_constant_override("separation", 2)
	v.position = Vector2(26, 222)
	v.size = Vector2(248, 200)
	btn.add_child(v)
	var name_l := VTheme.title_label(String(b.get("name", c["id"])), 26, Color(1, 0.94, 0.82), 6)
	name_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	v.add_child(name_l)
	var short := String(pat["name"]).split(",")[0].split(" ")[0]
	var rl := VTheme.label("%s  ·  %s" % [String(Game.RARITY_NAMES[r]).to_upper(), short.to_upper()], "Caps", 15)
	rl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rl.add_theme_color_override("font_color", Game.RARITY_COLORS[r].lightened(0.15))
	v.add_child(rl)
	var dv := VTheme.divider(220, 22)
	v.add_child(dv)
	# an owned card comes back as its next level: show the value it has now → the value it will have
	var lvl := int(c.get("level", 2 if bool(c.get("upgrade", false)) else 1))
	var up_from := lvl - 1 if bool(c.get("upgrade", false)) else 0
	var d := VTheme.label(Game.card_text(b, r, lvl, up_from, int(c.get("from_rarity", r))), "Body", 21)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	d.custom_minimum_size = Vector2(236, 0)
	v.add_child(d)
	if bool(c.get("upgrade", false)):
		var up := PanelContainer.new()
		up.theme_type_variation = "Plate"
		up.mouse_filter = Control.MOUSE_FILTER_IGNORE
		up.position = Vector2(40, 172)
		up.size = Vector2(220, 44)
		up.custom_minimum_size = Vector2(220, 44)
		btn.add_child(up)
		var ul := VTheme.title_label("LEVEL %s  →  %s" % [VTheme.roman(up_from), VTheme.roman(lvl)], 16, Color(0.75, 1.0, 0.6), 5, "caps")
		up.add_child(ul)
		var ut := ul.create_tween().set_loops()
		ut.tween_property(ul, "modulate", Color(1.3, 1.3, 1.1), 0.6)
		ut.tween_property(ul, "modulate", Color(1, 1, 1), 0.6)
	# focus outline glow (rarity color)
	btn.focus_entered.connect(func(): frame.self_modulate = Color(1.25, 1.2, 1.1))
	btn.focus_exited.connect(func(): frame.self_modulate = Color(1, 1, 1))
	btn.mouse_entered.connect(func(): btn.grab_focus())
	return btn


func _dismiss_choice(ov: Control, chosen: Control) -> void:
	if not is_instance_valid(ov):
		return
	ov.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for ch in ov.get_children():
		if ch is Button:
			(ch as Button).disabled = true
			(ch as Button).focus_mode = Control.FOCUS_NONE
	var tw := ov.create_tween().set_parallel()
	tw.tween_property(chosen, "scale", Vector2(1.12, 1.12), 0.18).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(ov, "modulate:a", 0.0, 0.3).set_delay(0.15)
	tw.chain().tween_callback(ov.queue_free)


func _fade_node(c: CanvasItem, d: float, delay := 0.0) -> void:
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, d).set_delay(delay)


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
		VTheme.sound("back")
		pause_panel.queue_free()
		pause_panel = null
		get_tree().paused = false
		return
	if not Net.online:
		get_tree().paused = true
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	ov.theme = VTheme.get_theme()
	root.add_child(ov)
	pause_panel = ov
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.0, 0.03, 0.66)
	ov.add_child(dim)
	VTheme.bleed(dim)
	var fit: Container = FitBox.new()
	fit.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.add_child(fit)
	var cc := CenterContainer.new()
	fit.add_child(cc)
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(520, 0)
	cc.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	p.add_child(v)
	var t := VTheme.title_label("Paused" if not Net.online else "Menu", 46, VTheme.GOLD_BRIGHT, 9)
	v.add_child(t)
	if Net.online:
		var n := VTheme.label("Co-op keeps running while this is open.", "Quote", 19)
		n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		v.add_child(n)
	v.add_child(VTheme.divider(340, 30))
	var in_hub: bool = arena != null and bool(arena.get("is_hub"))
	var room := VTheme.label("GRAN YSOLDE'S MANOR" if in_hub else "CHAMBER %d  ·  %d SHARDS GATHERED" % [Game.run_room + 1, Game.run_shards], "Caps", 15)
	room.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(room)
	var resume := _menu_button("Resume", "BigButton")
	resume.pressed.connect(_toggle_pause)
	v.add_child(resume)
	var st := _menu_button("Settings", "")
	st.pressed.connect(func():
		p.visible = false
		var sp := Settings.build_panel(func():
			if is_instance_valid(p):
				p.visible = true
				st.grab_focus())
		cc.add_child(sp))
	v.add_child(st)
	var quit := _menu_button("Leave the Manor" if in_hub else "Abandon Run", "DangerButton")
	quit.pressed.connect(func():
		_toggle_pause()
		if arena: arena.abandon())
	v.add_child(quit)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	p.scale = Vector2(0.9, 0.9)
	p.create_tween().tween_property(p, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_fade_node(ov, 0.15)
	resume.call_deferred("grab_focus")


func _menu_button(text: String, variation: String) -> Button:
	var b := Button.new()
	b.text = text
	if variation != "":
		b.theme_type_variation = variation
	b.custom_minimum_size = Vector2(340, 70 if variation == "BigButton" else 60)
	b.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	VTheme.juice(b)
	return b


func _exit_tree() -> void:
	get_tree().paused = false
