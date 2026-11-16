extends Node
## Headless bot harness. Usage:
##   godot --headless --path . res://tests/harness.tscn --fixed-fps 60 -- --role=solo|host|client --frames=N
## A bot drives each local heroine: hunts enemies, attacks, dashes, picks boons, takes doors.

class FakePad:
	var move := Vector2.ZERO
	var attack := false
	var special := false
	var dash := false

var role := "solo"
var frames := 6000
var arena: Node
var pads := {}
var frame := 0
var result := ""
var max_room := 0
var fps_samples: Array = []
var shot_dir := ""

func _ready() -> void:
	name = "Main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="): role = a.substr(7)
		if a.begins_with("--frames="): frames = int(a.substr(9))
		if a.begins_with("--shots="): shot_dir = a.substr(8)
	Game.load_slot("coop" if role != "solo" else "solo", 2)
	Game.data["meta"] = {"vitality": 5, "fury": 3}
	if role == "solo":
		Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
		Game.start_run(12345)
		start_arena()
	elif role == "local":
		Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}, {"peer": 1, "local_index": 1, "hero": "liora"}]
		Game.start_run(777)
		start_arena()
	elif role == "host":
		Net.host_game("kaela")
		Net.lobby_changed.connect(func():
			if Net.lobby.size() >= 2 and arena == null:
				print("HOST: partner joined, starting")
				Net.begin_run.rpc(4242, Net.lobby))
	elif role == "client":
		Net.join_game("127.0.0.1", "liora")
		Net.connected_ok.connect(func(): print("CLIENT: connected"))

func start_arena() -> void:
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	arena.run_finished.connect(func(v):
		result = "VICTORY" if v else "DEFEAT"
		print("%s: run finished: %s at room %d, shards %d" % [role.to_upper(), result, Game.run_room, Game.run_shards])
		_quit())
	for h in arena.heroes():
		if h.controlled:
			var p := FakePad.new()
			pads[h] = p
			h.touch = p
			if h.local_index == 1:
				h.local_index = 0 # bot drives P2 through the same fake pad path

func play_dialogue(_lines: Array, done: Callable) -> void:
	done.call()

func _physics_process(delta: float) -> void:
	frame += 1
	if delta > 0: fps_samples.append(Engine.get_frames_per_second())
	if frame >= frames:
		print("%s: TIMEOUT at frame %d room %d result=%s" % [role.to_upper(), frame, Game.run_room, result])
		_quit()
		return
	if arena == null or not is_instance_valid(arena):
		return
	max_room = max(max_room, arena.room_index)
	if shot_dir != "" and frame in [240, 420, 700, 1500]:
		get_viewport().get_texture().get_image().save_png("%s/%s_%d.png" % [shot_dir, role, frame])
	if shot_dir != "" and arena.room_index == 4 and arena.enemies().size() > 0 and frame % 200 == 0 and frame < 99999:
		get_viewport().get_texture().get_image().save_png("%s/%s_boss_%d.png" % [shot_dir, role, frame])
	if frame % 600 == 0:
		var hp := []
		for h in arena.heroes(): hp.append("%s:%d%s" % [h.key, h.hp, " DOWN" if h.downed else ""])
		print("%s f%d room %d wave %d enemies %d proj %d heroes %s" % [role.to_upper(), frame, arena.room_index, arena.wave_index, arena.enemies().size(), arena.projectiles.size(), hp])
	# Auto-pick boons.
	if arena.hud.boon_panel and is_instance_valid(arena.hud.boon_panel) and frame % 20 == 0:
		for b in arena.hud.boon_panel.find_children("*", "Button", true, false):
			b.pressed.emit()
			break
	for h in pads.keys():
		if not is_instance_valid(h): continue
		var p: FakePad = pads[h]
		p.attack = false; p.special = false; p.dash = false
		var target: Vector2
		var e = null
		var bd := INF
		for en in arena.enemies():
			var d: float = en.position.distance_to(h.position)
			if d < bd: bd = d; e = en
		if e:
			target = e.position
			p.move = (target - h.position).normalized() if bd > 90 else Vector2.ZERO
			if bd < 140: 
				h.facing = (target - h.position).normalized()
				p.attack = frame % 4 < 2
				p.special = frame % 50 == 0
			p.dash = frame % 97 == 0
		elif arena.door_open:
			p.move = (arena._door_pos() - h.position).normalized()
		else:
			p.move = Vector2.ZERO

func _quit() -> void:
	var avg := 0.0
	for f in fps_samples: avg += f
	if fps_samples.size() > 0: avg /= fps_samples.size()
	print("%s: frames=%d max_room=%d" % [role.to_upper(), frame, max_room])
	get_tree().quit()
