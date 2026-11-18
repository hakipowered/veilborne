extends Node
## xvfb-run -a -s "-screen 0 2400x1080x24" godot --rendering-driver opengl3 --path . res://tests/shop_debug.tscn -- --resolution=2400x1080 --out=/dir
## Mister Wick's stall with its collision (red), ware buy spots (green) and reach, plus a purchase
## with the cards open. Prints which ware the prompt picks for a heroine standing at each ware.
var out := "/tmp"
var arena
var _dbg: Node2D


func _ready() -> void:
	name = "Main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--resolution="):
			var p := a.substr(13).split("x")
			get_window().mode = Window.MODE_WINDOWED
			get_window().position = Vector2i.ZERO
			get_window().size = Vector2i(int(p[0]), int(p[1]))
	DirAccess.make_dir_recursive_absolute(out)
	Game.load_slot("solo", 2)
	Game.data["story"]["flags"]["met_wick"] = true
	Game.chapter_rooms_override = 6
	Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
	Game.start_run(4242)
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	_run()


func play_dialogue(_lines: Array, done: Callable) -> void:
	done.call()


func _hero() -> Node:
	for h in arena.heroes():
		if h.controlled:
			return h
	return null


func _snap(n: String, wait := 0.8) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("shot ", n)


func _draw_dbg() -> void:
	var sh: Node2D = arena.rewards.shop
	for c in sh.obstacles():
		var pts := PackedVector2Array()
		for k in range(41):
			var a := TAU * k / 40.0
			pts.append(c["pos"] + Vector2(cos(a), sin(a) * 0.5) * c["radius"])
		_dbg.draw_polyline(pts, Color(1, 0.2, 0.2), 3.0)
	for o in sh.items:
		_dbg.draw_circle(o.use_point(), 8, Color(0.2, 1, 0.2))
		_dbg.draw_arc(o.use_point(), o.reach, 0, TAU, 40, Color(0.2, 1, 0.2, 0.5), 2.0)
		_dbg.draw_circle(o.global_position + o.art_offset, 6, Color(0.3, 0.6, 1))


func _run() -> void:
	var si := -1
	for i in range(Game.run_plan.size()):
		if Game.run_plan[i]["type"] == "shop":
			si = i
			break
	arena._load_room(si, "shop")
	arena._waves = []
	arena.wave_delay = 0.1
	arena.boss_pending = false
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(arena.hud._card):
		arena.hud._card.visible = false
	var h := _hero()
	var sh: Node2D = arena.rewards.shop
	_dbg = Node2D.new()
	_dbg.z_index = 50
	_dbg.draw.connect(_draw_dbg)
	sh.get_parent().add_child(_dbg)
	arena.camera.position = sh.position + Vector2(0, -90)
	arena.camera.reset_smoothing()
	# where does each ware's art sit, and what does the prompt pick standing right in front of it?
	for i in range(sh.items.size()):
		var o: Node2D = sh.items[i]
		var art: Vector2 = o.global_position + o.art_offset
		for dy in [60.0, 100.0, 140.0]:
			var nrm := Vector2(-o.use_axis.y, o.use_axis.x)
			var p: Vector2 = arena.resolve_collision(o.use_point() + nrm * (dy - 60.0) + o.use_axis * 30.0, 30.0)
			h.position = p
			var picked: Node = arena.rewards._nearest(h)
			print("in front of ware %d (%s) dy %d at %s -> %s" % [i, o.kind, int(dy), p, picked.kind if picked else "none"])
		h.position = arena.resolve_collision(Vector2(art.x, o.global_position.y + 60.0), 30.0)
		h.facing = Vector2(0, -1)
		await _snap("shop_dbg_%d" % i, 0.5)
	# standing behind the stall
	h.position = arena.resolve_collision(sh.position + Vector2(-150, -170), 30.0)
	await _snap("shop_dbg_behind", 0.5)
	# walk up into the counter from below each ware and see where she stops
	for x in [-200.0, -100.0, 0.0, 100.0, 200.0]:
		var p := Vector2(sh.position.x + x, sh.position.y + 200.0)
		for k in range(60):
			p = arena.resolve_collision(p + Vector2(0, -10), 30.0)
		h.position = p
		print("walking up at x %+d stops at y %.0f (shop y %.0f)" % [int(x), p.y, sh.position.y])
	# buy the boon ware with cards open
	Game.run_gold = 400
	for o in sh.items:
		if o.kind == "boon" or o.kind == "forge" or o == sh.items[0]:
			h.position = o.use_point()
			await get_tree().create_timer(0.3).timeout
			arena.rewards.interact(h)
			break
	await get_tree().create_timer(0.3).timeout
	if not is_instance_valid(arena.hud.boon_panel):
		arena._offer_next([h], "boon")
	print("panel open: ", is_instance_valid(arena.hud.boon_panel))
	h.position = sh.items[2].use_point()
	await _snap("shop_cards", 1.0)
	get_tree().quit()
