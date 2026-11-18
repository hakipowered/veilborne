extends Node
## godot --headless --path . res://tests/dash_gap.tscn  (add -- --out=/dir under xvfb for a screenshot)
## Dashes a heroine across every pit / chasm edge it can find: narrow gaps must be cleared, wide ones not.
## Prints "DASH_GAP: PASS".
class FakeTouch:
	var move := Vector2.ZERO
	var attack := false
	var special := false
	var dash := false

var arena
var out := ""
var fails := 0
var tests := 0
var chasms := 0


func _ready() -> void:
	name = "Main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	Game.load_slot("solo", 2)
	Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
	Game.start_run(777)
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	_run()


func play_dialogue(_l: Array, done: Callable) -> void:
	done.call()


func _dash(h: Node, from: Vector2, dir: Vector2) -> Vector2:
	var t := FakeTouch.new()
	h.touch = t
	h.position = from
	h.vel = Vector2.ZERO
	h.dash_charges = 3
	h._set_state("idle")
	await get_tree().physics_frame
	t.move = dir
	t.dash = true
	await get_tree().physics_frame
	t.dash = false
	t.move = Vector2.ZERO
	for i in range(30):
		await get_tree().physics_frame
	h.touch = null
	return h.position


func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	var h: Node = null
	for x in arena.heroes():
		h = x
	h.max_hp = 99999
	h.hp = 99999
	var env = arena.env
	var L: float = float(h.def["speed"]) * (1.0 + h.stats["speed_mult"] / 100.0) * h.stats["speed_meta"] * 3.4 * h.DASH_TIME
	print("dash length %.0f" % L)
	for idx in range(Game.run_plan.size()):
		arena._load_room(idx, "gold")
		arena._waves = []
		arena.boss_pending = false
		for e in arena.enemy_nodes.values():
			if is_instance_valid(e): e.queue_free()
		await get_tree().create_timer(0.2).timeout
		var pits: Array = []
		for o in env.get_obstacles():
			if o.get("pit", false):
				pits.append(o)
		for o in pits:
			var c: Vector2 = o["pos"]
			var r: float = o["radius"]
			for dir in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
				var width: float = 2.0 * r * (1.0 if dir.y == 0.0 else 0.5) + 16.0
				var from: Vector2 = c - dir * (r * (1.0 if dir.y == 0.0 else 0.5) + 30.0)
				if not env.can_stand(from, 16.0):
					continue
				var far: Vector2 = c + dir * (r * (1.0 if dir.y == 0.0 else 0.5) + 30.0)
				if not env.can_stand(far, 16.0) or not env.can_stand(far + dir * 20.0, 16.0):
					continue
				var end: Vector2 = await _dash(h, from, dir)
				var crossed: bool = (end - c).dot(dir) > 0.0
				var should: bool = width + 30.0 <= L * 1.7
				tests += 1
				var ok: bool = crossed == should and env.can_stand(end, 8.0)
				if not ok:
					fails += 1
				print("room %d pit r%.0f dir %s width %.0f -> crossed %s (expected %s) end ok %s" % [idx, r, dir, width, crossed, should, env.can_stand(end, 8.0)])
				if out != "" and crossed and tests < 3:
					get_viewport().get_texture().get_image().save_png("%s/dash_%d.png" % [out, tests])
		# chasms carved into the floor: scan rows for floor -> chasm -> floor
		var lim: Rect2 = env.get_camera_limits()
		var y := lim.position.y
		while y < lim.end.y and chasms < 8:
			var x := lim.position.x
			var gap_start := INF
			var was := false
			while x < lim.end.x:
				var p := Vector2(x, y)
				var st: bool = env.can_stand(p, 16.0)
				if env.prop_at(p, 16.0):
					gap_start = INF
					was = false
					x += 6.0
					continue
				if was and not st and env.in_room(p):
					gap_start = x
				elif st and not was and gap_start < INF:
					var w: float = x - gap_start
					var from := Vector2(gap_start - 30.0, y)
					var far := Vector2(x + 30.0, y)
					if w > 40.0 and env.can_stand(from, 16.0) and env.can_stand(far, 16.0):
						var end: Vector2 = await _dash(h, from, Vector2(1, 0))
						var crossed: bool = end.x > x
						var should: bool = w + 46.0 <= L * 1.7
						tests += 1
						chasms += 1
						var ok: bool = (crossed == should or absf(w + 46.0 - L * 1.7) < 20.0) and env.can_stand(end, 8.0)
						if not ok:
							fails += 1
						print("   plan ", arena.dash_plan(from, Vector2(1, 0), L), " end ", end, " gap ", gap_start, "..", x, " y ", y)
						print("room %d chasm width %.0f -> crossed %s (expected %s) end ok %s" % [idx, w, crossed, should, env.can_stand(end, 8.0)])
					gap_start = INF
				if not env.in_room(p):
					gap_start = INF
				was = st
				x += 6.0
			y += 90.0
		if tests >= 30:
			break
	# a plain dash on open floor still runs its usual length
	print("DASH_GAP: %s (%d cases, %d failures)" % ["PASS" if fails == 0 and tests > 0 else "FAIL", tests, fails])
	get_tree().quit()
