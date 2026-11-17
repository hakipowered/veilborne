extends Node
## xvfb-run -a -s "-screen 0 2448x1848x24" godot --rendering-driver opengl3 --path . res://tests/reward_shots.tscn -- --resolution=2448x1848 --out=/dir
## Screenshots of the visible rewards: exit emblems (boon / forge / heal / gold / shards / shop / boss / elite),
## each reward object in a cleared chamber, and Mister Wick's shop (first-meeting dialogue + a ware's prompt).
## Prints "REWARD_SHOTS: PASS" when every reward appeared and could be used.
const DialogueScript := preload("res://ui/dialogue.gd")
var out := "/tmp"
var arena
var fails := 0
var _dlg: CanvasLayer = null


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
	Game.data["story"]["flags"].erase("met_wick")
	Game.chapter_rooms_override = 6
	Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
	Game.start_run(4242)
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	_run()


func play_dialogue(lines: Array, done: Callable) -> void:
	if not str(lines).contains("wick"):
		done.call() # only Mister Wick's first meeting is shown
		return
	_dlg = DialogueScript.new()
	add_child(_dlg)
	_dlg.start(lines, done)


func _hero() -> Node:
	for h in arena.heroes():
		if h.controlled:
			return h
	return null


func _snap(n: String, wait := 0.8) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("shot ", n)


## Loads chamber idx (no foes) and waits until it is cleared and its reward is in the room.
func _room(idx: int, reward: String) -> void:
	arena._load_room(idx, reward)
	arena._waves = []
	arena.wave_delay = 0.1
	arena.boss_pending = false
	await get_tree().create_timer(2.0).timeout
	if is_instance_valid(arena.hud._card):
		arena.hud._card.visible = false


## Stands the heroine below the exits so the camera frames them.
func _near_doors(h: Node) -> void:
	var c := Vector2.ZERO
	for p in arena.door_points:
		c += p
	c /= maxf(1.0, arena.door_points.size())
	h.position = arena.resolve_collision(c + Vector2(0, 150), 30.0)
	h.facing = Vector2(0, -1)
	arena.camera.position = h.position + Vector2(0, -150)
	arena.camera.reset_smoothing()


func _idx(floor_key: String, type := "combat") -> int:
	for i in range(Game.run_plan.size()):
		if Game.run_plan[i]["floor"] == floor_key and Game.run_plan[i]["type"] == type:
			return i
	return 0


func _run() -> void:
	await get_tree().create_timer(0.6).timeout
	var h := _hero()
	# ---- every reward object, in a garden chamber
	var gi := _idx("garden")
	for kind in ["boon", "forge", "heal", "gold", "shards"]:
		await _room(gi, kind)
		var objs: Array = arena.rewards.objects
		if objs.is_empty():
			print("FAIL: no %s object" % kind)
			fails += 1
			continue
		var o: Node2D = objs[0]
		h.position = o.position + Vector2(170, 130)
		h.facing = Vector2(-1, -0.5).normalized()
		arena.camera.position = o.position + Vector2(60, 0)
		arena.camera.reset_smoothing()
		await _snap("reward_%s" % kind, 1.2)
		if o.auto:
			h.position = o.position
			await get_tree().create_timer(0.3).timeout
		else:
			h.position = o.position + Vector2(60, 50)
			await get_tree().create_timer(0.3).timeout
			if kind == "heal":
				await _snap("reward_heal_prompt", 0.2)
			if not arena.rewards.interact(h):
				print("FAIL: could not use %s" % kind)
				fails += 1
		await get_tree().create_timer(0.4).timeout
		if kind == "boon" and is_instance_valid(arena.hud.boon_panel):
			await _snap("reward_boon_cards", 0.6)
		for i in range(4):
			if is_instance_valid(arena.hud.boon_panel):
				for b in arena.hud.boon_panel.find_children("*", "Button", true, false):
					b.pressed.emit()
					break
			await get_tree().create_timer(0.5).timeout
		if not arena.door_open:
			print("FAIL: exits did not open after %s" % kind)
			fails += 1
	# ---- exit emblems: two gates (garden), then the other kinds, then the single gate before an elite / boss
	for pair in [["boon", "forge"], ["heal", "shop"], ["gold", "shards"]]:
		arena.door_rewards = pair
		_near_doors(h)
		await _snap("doors_%s_%s" % pair, 0.8)
	var ei := _idx("forge", "elite")
	await _room(ei - 1, "gold")
	h.position = arena.rewards.objects[0].position if not arena.rewards.objects.is_empty() else h.position
	await get_tree().create_timer(0.5).timeout
	arena.door_rewards = ["forge", "boon"]
	_near_doors(h)
	await _snap("doors_elite_next", 1.0)
	# ---- the shop (first meeting plays the intro)
	var si := _idx("forge", "shop")
	await _room(si, "shop")
	if not is_instance_valid(arena.rewards.shop):
		print("FAIL: no shop")
		fails += 1
	else:
		var sh: Node2D = arena.rewards.shop
		print("shop at ", sh.position, " clutter score ", arena.rewards.shop_score)
		h.position = sh.position + Vector2(-20, 130)
		arena.camera.position = sh.position + Vector2(0, -60)
		arena.camera.reset_smoothing()
		if is_instance_valid(_dlg):
			await _snap("shop_intro", 1.5)
			for i in range(3):
				_dlg.advance()
				_dlg.advance()
				await get_tree().create_timer(0.3).timeout
			await _snap("shop_intro_2", 0.8)
			for i in range(12):
				if is_instance_valid(_dlg):
					_dlg.advance()
				await get_tree().create_timer(0.15).timeout
		h.position = sh.position + Vector2(40, 110)
		await _snap("shop", 1.2)
		Game.run_gold = 200
		var ware: Node2D = sh.items[1]
		h.position = ware.global_position + Vector2(10, 30)
		await _snap("shop_prompt", 0.8)
		var before := Game.run_gold
		if not arena.rewards.interact(h) or Game.run_gold != before - ware.price:
			print("FAIL: could not buy")
			fails += 1
		await _snap("shop_bought", 1.0)
		for i in range(4):
			if is_instance_valid(arena.hud.boon_panel):
				for b in arena.hud.boon_panel.find_children("*", "Button", true, false):
					b.pressed.emit()
					break
			await get_tree().create_timer(0.4).timeout
		arena.door_rewards = ["boss"]
		h.position = arena.door_points[0] + Vector2(0, 170)
		arena.camera.position = arena.door_points[0] + Vector2(0, 40)
		arena.camera.reset_smoothing()
		await _snap("doors_boss", 1.0)
	print("REWARD_SHOTS: %s (%d failures)" % ["PASS" if fails == 0 else "FAIL", fails])
	get_tree().quit()
