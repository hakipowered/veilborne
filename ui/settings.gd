extends RefCounted
## Persistent player settings (volumes) + the shared Settings panel used by the title screen and pause menu.

const VTheme = preload("res://ui/theme.gd")
const PATH := "user://settings.cfg"

static var values := {"master": 1.0, "music": 0.8, "sfx": 0.9}
static var _loaded := false


static func load_settings() -> void:
	if _loaded:
		return
	_loaded = true
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK:
		for k in values.keys():
			values[k] = clampf(float(cf.get_value("audio", k, values[k])), 0.0, 1.0)
	apply()


static func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in values.keys():
		cf.set_value("audio", k, values[k])
	cf.save(PATH)


static func apply() -> void:
	var ml := Engine.get_main_loop()
	if ml is SceneTree:
		var a: Node = (ml as SceneTree).root.get_node_or_null("Audio")
		if a and a.has_method("set_volumes"):
			a.set_volumes(values["master"], values["music"], values["sfx"])


## Builds the settings panel. on_close is called after the panel frees itself.
static func build_panel(on_close: Callable) -> Control:
	load_settings()
	var p := PanelContainer.new()
	p.theme = VTheme.get_theme()
	p.custom_minimum_size = Vector2(620, 0)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var t := VTheme.label("Settings", "H2")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	v.add_child(VTheme.divider(380, 30))
	var first: Control = null
	for spec in [["master", "Master Volume"], ["music", "Music"], ["sfx", "Effects"]]:
		var key: String = spec[0]
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 18)
		v.add_child(row)
		var l := VTheme.label(spec[1], "Caps", 19, VTheme.GOLD_BRIGHT)
		l.custom_minimum_size = Vector2(190, 0)
		row.add_child(l)
		var s := HSlider.new()
		s.min_value = 0.0
		s.max_value = 1.0
		s.step = 0.05
		s.value = values[key]
		s.custom_minimum_size = Vector2(280, 48)
		s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(s)
		var pct := VTheme.label("%d%%" % int(round(values[key] * 100)), "Gold", 20)
		pct.custom_minimum_size = Vector2(64, 0)
		pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		row.add_child(pct)
		s.value_changed.connect(func(val: float):
			values[key] = val
			pct.text = "%d%%" % int(round(val * 100))
			apply())
		s.drag_ended.connect(func(_c: bool): VTheme.sound("click"))
		if first == null:
			first = s
	var hint := VTheme.label("Volumes are kept on this device.", "Dim", 18)
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(hint)
	var done := Button.new()
	done.text = "Done"
	done.custom_minimum_size = Vector2(260, 64)
	done.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	VTheme.juice(done, 1.04, "back")
	done.pressed.connect(func():
		save_settings()
		p.queue_free()
		if on_close.is_valid():
			on_close.call())
	v.add_child(done)
	if first:
		first.call_deferred("grab_focus")
	return p
