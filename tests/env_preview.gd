extends Node2D
## Environment preview + micro benchmark (ENVIRONMENT agent).
## xvfb-run -a -s "-screen 0 2400x1080x24" $G --rendering-driver opengl3 --path . --resolution 2400x1080 \
##   res://tests/env_preview.tscn -- --out=/mnt/project-files/veilborne/previews --tag=2400
## Options: --rooms=0,1,2,3,4  --bench  --quit
## Chapter layouts: --chapters[=garden,forge,hollow]  renders every variant + the boss room of each
##   chapter (overview, close-up, doors with reward icons, low-quality); --lowq; --hazards (debug outlines)
const EnvScript := preload("res://scenes/environment.gd")

var out := "/tmp"
var tag := "shot"
var rooms := [0, 1, 2, 3, 4]
var bench := false
var hide := []
var chapters := []
var lowq := false
var show_hazards := false
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
		elif a.begins_with("--hide="): hide = a.substr(7).split(",")
		elif a == "--chapters": chapters = ["garden", "forge", "hollow"]
		elif a.begins_with("--chapters="): chapters = Array(a.substr(11).split(","))
		elif a == "--lowq": lowq = true
		elif a == "--hazards": show_hazards = true
	env = EnvScript.new()
	add_child(env)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	hero = _char("kaela")
	foe = _char("shade")
	cam = Camera2D.new()
	cam.zoom = Vector2(1.1, 1.1)
	add_child(cam)
	cam.make_current()
	_run()

func _char(id: String) -> Sprite2D:
	# first idle frame of the packed animation atlas (art/anim/<id>/data.gd)
	var s := Sprite2D.new()
	var data: Dictionary = load("res://art/anim/%s/data.gd" % id).DATA
	var anims: Dictionary = data["anims"]
	var fr: Array = anims["idle"]["dirs"][0][0] if anims.has("idle") else anims.values()[0]["dirs"][0][0]
	var at := AtlasTexture.new()
	at.atlas = load("res://art/anim/%s/%s_%d.webp" % [id, id, int(fr[0])])
	at.region = Rect2(fr[1], fr[2], fr[3], fr[4])
	s.texture = at
	s.centered = false
	s.offset = Vector2(fr[5], fr[6])
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
	if not chapters.is_empty():
		await _run_chapters()
		if bench:
			await _bench_chapters()
		get_tree().quit()
		return
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
	var tb := Time.get_ticks_usec()
	for f in range(240):
		cam.position = Vector2(sin(f * 0.03) * 600.0, 0)
		await get_tree().process_frame
	print("BENCH baseline_old_floor avg_frame_ms=%.2f" % ((Time.get_ticks_usec() - tb) / 1000.0 / 240.0))
	old.queue_free()
	env.visible = true
	for i in [0, 4]:
		_build(i)
		var ys := [env.get_player_start().y, 0.0, -300.0]
		if "backdrop" in hide: env._backdrop.visible = false
		if "floor" in hide: env._floor_mat.shader = null
		if "vignette" in hide: env._vignette.visible = false
		if "particles" in hide:
			for n in env.find_children("*", "CPUParticles2D", true, false): n.visible = false
			for n in entities.find_children("*", "CPUParticles2D", true, false): n.visible = false
		if "halos" in hide:
			for h in env._halos: h[0].visible = false
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


# ------------------------------------------------------------------ chapter layouts
var _dbg: Node2D

func _build_key(key: String, variant: int, room: int) -> void:
	env.force_variant = variant
	env.build(key, room, 777 + room)
	env.set_low_quality(lowq)
	env.add_ysorted_props_to(entities)
	hero.position = env.get_player_start()
	var sp: Array = env.get_spawn_points()
	foe.position = sp[0] if sp.size() > 0 else Vector2(200, 0)
	var icons := []
	for r in ["boon", "gold", "heal", "forge"]:
		icons.append(load("res://art/ui/reward_%s.png" % r))
	if env.has_method("set_door_rewards"):
		env.set_door_rewards([icons[room % 4], icons[(room + 1) % 4]])
	if _dbg:
		_dbg.queue_free()
		_dbg = null
	if show_hazards:
		_dbg = Node2D.new()
		_dbg.z_index = 50
		add_child(_dbg)
		var cols := {"water": Color(0.3, 0.7, 1), "lava": Color(1, 0.4, 0.1), "spikes": Color(1, 1, 0.2), "debris": Color(1, 0.2, 0.9), "pit": Color(0.2, 1, 0.3)}
		for h in env.get_hazards():
			var l := Line2D.new()
			l.width = 4
			l.default_color = cols.get(h["type"], Color.WHITE)
			var poly: PackedVector2Array = h["poly"]
			for q in poly: l.add_point(q)
			if poly.size() > 0: l.add_point(poly[0])
			_dbg.add_child(l)
		for o in env.get_obstacles():
			var c := Line2D.new()
			c.width = 3
			c.default_color = Color(1, 0, 0)
			for k in range(17):
				var a := TAU * k / 16.0
				c.add_point(o["pos"] + Vector2(cos(a), sin(a) * 0.5) * o["radius"])
			_dbg.add_child(c)
	cam.position = hero.position + Vector2(0, -50)
	cam.reset_smoothing()

func _run_chapters() -> void:
	for ch in chapters:
		var n: int = env.get_layout_count(ch)
		var specs := []
		for v in range(n):
			specs.append([ch, v, v + 1])
		specs.append([ch + "_boss", 0, 5])
		for sp in specs:
			var nm := "%s_v%d" % [sp[0], sp[1]]
			cam.zoom = Vector2(0.36, 0.36)
			_build_key(sp[0], sp[1], sp[2])
			print(nm, " ", env.get_chapter_title(sp[0]), " | ", env.get_room_title(), " doors=", env.get_door_positions().size(), " hazards=", env.get_hazards().size(), " obstacles=", env.get_obstacles().size())
			cam.position = Vector2(0, -200)
			await _shot(nm + "_overview", 1.2)
			cam.zoom = Vector2(0.95, 0.95)
			cam.position = Vector2(0, 0)
			await _shot(nm + "_center", 0.5)
			if env.get_door_positions().size() > 0 and sp[0].find("boss") < 0:
				env.set_door_open(true)
				var dp: Vector2 = env.get_door_positions()[0]
				cam.position = dp + Vector2(0, 160)
				await _shot(nm + "_door", 2.4)
			cam.zoom = Vector2(1.1, 1.1)

func _bench_chapters() -> void:
	for ch in chapters:
		for key in [ch, ch + "_boss"]:
			for lq in [false, true]:
				env.force_variant = 0
				env.build(key, 1, 99)
				env.set_low_quality(lq)
				env.add_ysorted_props_to(entities)
				cam.zoom = Vector2(1.1, 1.1)
				await get_tree().create_timer(1.0).timeout
				var frames := 0
				var t0 := Time.get_ticks_usec()
				var maxdc := 0
				while frames < 180:
					cam.position = Vector2(sin(frames * 0.03) * 600.0, cos(frames * 0.02) * 300.0)
					await get_tree().process_frame
					frames += 1
					maxdc = maxi(maxdc, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
				var dt := (Time.get_ticks_usec() - t0) / 1000.0 / frames
				var parts := 0
				for n in env.find_children("*", "CPUParticles2D", true, false):
					if n.visible: parts += n.amount
				print("BENCH %s lowq=%s avg_frame_ms=%.2f draw_calls_max=%d tex_mem_MB=%.1f particles=%d nodes=%d" % [
					key, lq, dt, maxdc, Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0, parts,
					int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
