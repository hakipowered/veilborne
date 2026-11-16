extends Node2D
## AnimSprite preview grid (ANIMATION agent).
## xvfb-run -a -s "-screen 0 1600x900x24" $G --rendering-driver opengl3 --path . --resolution 1600x900 res://tests/anim_preview.tscn -- --out=/dir [--chars=kaela,liora] [--mode=grid|dirs]
## grid: one row per character, one column per animation, every cell looping its anim; screenshots at several times.
## dirs: each character running in all 8 directions (checks 5-dir + mirroring).

const HERO_ANIMS := ["idle", "run", "attack1", "attack2", "attack3", "dash", "special", "hurt", "death"]
const ENEMY_ANIMS := ["idle", "move", "windup", "attack", "hurt", "death", "cast", "charge"]
const HEIGHTS := {"gen_bloom": 270.0, "gen_anvil": 290.0, "gen_seneschal": 280.0, "kaela": 132.0, "liora": 132.0, "shade": 110.0, "spitter": 80.0, "brute": 150.0, "regent": 260.0}

var out := "/tmp"
var chars: Array = ["kaela", "liora", "shade", "spitter", "brute", "regent"]
var mode := "grid"
var sprites: Array = []
var labels_font: Font


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--chars="):
			chars = Array(a.substr(8).split(","))
		elif a.begins_with("--mode="):
			mode = a.substr(7)
	labels_font = ThemeDB.fallback_font
	RenderingServer.set_default_clear_color(Color(0.16, 0.14, 0.16))
	var present: Array = []
	for c in chars:
		if ResourceLoader.exists("res://art/anim/%s/data.gd" % c):
			present.append(c)
	chars = present
	if mode == "dirs":
		_build_dirs()
	else:
		_build_grid()
	_run()


func _anims_for(c: String) -> Array:
	if c == "kaela" or c == "liora":
		return HERO_ANIMS
	var keys: Array = AnimSprite._load(c).get("anims", {}).keys()
	return keys.slice(0, 12) if keys.size() > 0 else ENEMY_ANIMS


func _build_grid() -> void:
	var vs := get_viewport_rect().size
	var cols := 12
	var cw := vs.x / cols
	var rh := vs.y / maxf(chars.size(), 1)
	for r in chars.size():
		var c: String = chars[r]
		var anims := _anims_for(c)
		var h: float = minf(HEIGHTS.get(c, 120.0), rh * 0.78)
		for i in anims.size():
			var s := AnimSprite.new()
			add_child(s)
			s.position = Vector2(cw * (i + 0.5), rh * (r + 1) - 14)
			s.setup(c, h)
			if not s.has_anim(anims[i]):
				s.queue_free()
				continue
			s.set_facing(Vector2(1, 0.5))
			s.play(anims[i], true)
			s.set_meta("anim", anims[i])
			s.anim_finished.connect(_on_finished.bind(s))
			s.anim_event.connect(_on_event.bind(s))
			sprites.append(s)
			_label(Vector2(cw * i + 6, rh * r + 16), "%s %s %.2fs" % [c, anims[i], s.get_anim_length(anims[i])])


func _build_dirs() -> void:
	var vs := get_viewport_rect().size
	var rh := vs.y / maxf(chars.size(), 1)
	for r in chars.size():
		var c: String = chars[r]
		var h: float = minf(HEIGHTS.get(c, 120.0), rh * 0.78)
		for i in 8:
			var ang := TAU * i / 8.0
			var d := Vector2(cos(ang), sin(ang))
			var s := AnimSprite.new()
			add_child(s)
			s.position = Vector2(vs.x / 8.0 * (i + 0.5), rh * (r + 1) - 14)
			s.setup(c, h)
			s.play("run" if s.has_anim("run") else "move", true)
			s.set_facing(d)
			sprites.append(s)
			_label(Vector2(vs.x / 8.0 * i + 6, rh * r + 16), "%s dir (%.1f,%.1f)" % [c, d.x, d.y])


func _label(p: Vector2, t: String) -> void:
	var l := Label.new()
	l.text = t
	l.position = p
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", Color(0.85, 0.8, 0.75))
	add_child(l)


func _on_finished(anim: String, s: AnimSprite) -> void:
	# hold the last frame briefly, then loop for the preview
	if not is_instance_valid(s):
		return
	await get_tree().create_timer(0.5).timeout
	if is_instance_valid(s):
		s.play(anim, true)


func _on_event(ev: String, s: AnimSprite) -> void:
	if ev == "hit" and is_instance_valid(s):
		s.flash = 0.8
		var tw := create_tween()
		tw.tween_property(s, "flash", 0.0, 0.15)


func _draw() -> void:
	for s in sprites:
		if is_instance_valid(s):
			draw_set_transform(s.position, 0, Vector2(1, 0.45))
			draw_circle(Vector2.ZERO, 26, Color(0, 0, 0, 0.35))
	draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)


func _run() -> void:
	queue_redraw()
	var times := [0.25, 0.3, 0.3, 0.3]
	for i in times.size():
		await get_tree().create_timer(times[i]).timeout
		var img := get_viewport().get_texture().get_image()
		var fn := "%s/anim_%s_%d.png" % [out, mode, i]
		img.save_png(fn)
		print("shot ", fn)
	get_tree().quit()
