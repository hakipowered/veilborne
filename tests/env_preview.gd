extends Node2D
## Environment preview + micro benchmark (ENVIRONMENT agent).
## xvfb-run -a -s "-screen 0 2400x1080x24" $G --rendering-driver opengl3 --path . --resolution 2400x1080 \
##   res://tests/env_preview.tscn -- --out=/mnt/project-files/veilborne/previews --tag=2400
## Options: --rooms=0,1,2,3,4  --bench  --quit
const EnvScript := preload("res://scenes/environment.gd")

var out := "/tmp"
var tag := "shot"
var rooms := [0, 1, 2, 3, 4]
var bench := false
var env: Node2D
var entities: Node2D
var cam: Camera2D
var hero: Sprite2D
var foe: Sprite2D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--tag="): tag = a.substr(6)
		elif a.begins_with("--rooms="):
			rooms = []
			for s in a.substr(8).split(","): rooms.append(int(s))
		elif a == "--bench": bench = true
	env = EnvScript.new()
	add_child(env)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	hero = _char("res://art/kaela.png", 132.0)
	foe = _char("res://art/shade.png", 110.0)
	cam = Camera2D.new()
	cam.zoom = Vector2(1.1, 1.1)
	add_child(cam)
	cam.make_current()
	_run()

func _char(path: String, h: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = load(path)
	s.centered = false
	s.offset = Vector2(-s.texture.get_width() * 0.5, -s.texture.get_height())
	s.scale = Vector2.ONE * h / s.texture.get_height()
	entities.add_child(s)
	return s

func _shot(name: String, wait := 1.0) -> void:
	await get_tree().create_timer(wait).timeout
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/env_%s_%s.png" % [out, tag, name])
	print("shot ", name, " ", img.get_size())

func _build(i: int) -> void:
	var key := "throne" if i == 4 else "catacomb"
	env.build(key, i, 1234 + i)
	env.add_ysorted_props_to(entities)
	hero.position = env.get_player_start()
	var sp: Array = env.get_spawn_points()
	foe.position = sp[0] if sp.size() > 0 else Vector2(200, 0)
	cam.position = hero.position + Vector2(0, -50)
	cam.reset_smoothing()

func _run() -> void:
	await get_tree().process_frame
	for i in rooms:
		_build(i)
		await _shot("room%d_start" % i, 1.2)
		cam.position = Vector2(0, -60)
		await _shot("room%d_center" % i, 0.4)
		if i < 4:
			cam.position = env.get_door_pos() + Vector2(0, 120)
			hero.position = env.get_door_pos() + Vector2(-90, 150)
			await _shot("room%d_door_closed" % i, 0.3)
			env.set_door_open(true)
			await _shot("room%d_door_open" % i, 2.6)
		else:
			cam.position = Vector2(0, -420)
			await _shot("room%d_throne" % i, 0.4)
			env.set_door_open(true)
			cam.position = Vector2(0, -60)
			await _shot("room%d_cleared" % i, 1.4)
	for i in rooms:
		_build(i)
		cam.zoom = Vector2(0.42, 0.42)
		cam.position = Vector2(0, -250)
		await _shot("room%d_overview" % i, 0.8)
		cam.zoom = Vector2(1.1, 1.1)
	if bench:
		await _bench()
	get_tree().quit()

func _bench() -> void:
	# baseline: the old single painted JPG floor scaled 1.6x (what arena.gd draws today)
	env.build("catacomb", 0, 1)
	env.visible = false
	for p in env._ysorted: p.visible = false
	env._vignette.visible = false
	var old := Sprite2D.new()
	old.texture = load("res://art/floor_catacomb.jpg")
	old.scale = Vector2.ONE * 1.6
	add_child(old)
	move_child(old, 0)
	await get_tree().create_timer(0.5).timeout
	var t0 := Time.get_ticks_usec()
	for f in range(240):
		cam.position = Vector2(sin(f * 0.03) * 600.0, 0)
		await get_tree().process_frame
	print("BENCH baseline_old_floor avg_frame_ms=%.2f" % ((Time.get_ticks_usec() - t0) / 1000.0 / 240.0))
	old.queue_free()
	env.visible = true
	for i in [0, 4]:
		_build(i)
		var ys := [env.get_player_start().y, 0.0, -300.0]
		await get_tree().create_timer(1.0).timeout
		var frames := 0
		var t0 := Time.get_ticks_usec()
		var maxdc := 0
		while frames < 240:
			cam.position = Vector2(sin(frames * 0.03) * 600.0, ys[(frames / 80) % 3])
			await get_tree().process_frame
			frames += 1
			maxdc = maxi(maxdc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		var dt := (Time.get_ticks_usec() - t0) / 1000.0 / frames
		var parts := 0
		for n in env.find_children("*", "CPUParticles2D", true, false):
			parts += n.amount
		for n in entities.find_children("*", "CPUParticles2D", true, false):
			parts += n.amount
		print("BENCH room=%d avg_frame_ms=%.2f fps=%.1f draw_calls_max=%d objects=%d tex_mem_MB=%.1f particles_max=%d nodes=%d" % [
			i, dt, 1000.0 / dt, maxdc, int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, parts, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
