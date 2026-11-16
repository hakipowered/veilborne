extends Node
## Headless bot harness. Usage:
##   godot --headless --path . res://tests/harness.tscn --fixed-fps 60 -- --role=solo|host|client --frames=N
## A bot drives each local heroine: hunts enemies, attacks, dashes, picks boons, takes doors.

class FakePad:
	var move := Vector2.ZERO
	var attack := false
	var special := false
	var dash := false
	var special_aim := Vector2.ZERO
	var hold := 0 ## frames left holding special (aimed special)

var role := "solo"
var frames := 6000
var arena: Node
var pads := {}
var frame := 0
var result := ""
var max_room := 0
var fps_samples: Array = []
var shot_dir := ""
var weapon := ""
var aspect := 0
var stats_specials := 0
var stats_forge := 0
var _logged_doors := -1
var _spec_state := {}
var god := false ## keep the bot alive to walk the whole run (balance runs leave it off)
var hazard_frames := 0
var _last_chapter := 0

func _ready() -> void:
	name = "Main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--role="): role = a.substr(7)
		if a.begins_with("--frames="): frames = int(a.substr(9))
		if a.begins_with("--shots="): shot_dir = a.substr(8)
		if a.begins_with("--weapon="): weapon = a.substr(9)
		if a.begins_with("--aspect="): aspect = int(a.substr(9))
		if a.begins_with("--chapter-rooms="): Game.chapter_rooms_override = int(a.substr(16))
		if a == "--god": god = true
	if shot_dir != "":
		Engine.max_physics_steps_per_frame = 1 # lockstep with rendering so screenshots match the state
	Game.load_slot("coop" if role != "solo" else "solo", 2)
	Game.data["meta"] = {"vitality": 5, "fury": 3}
	if weapon != "":
		Game.data["aspects"] = {weapon: [1, 2]}
	Game.set_loadout(weapon, aspect)
	print("%s: weapon=%s aspect=%d" % [role.to_upper(), Game.weapon_for("kaela" if role != "client" else "liora"), Game.run_aspect])
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
	if arena == null and Time.get_ticks_msec() < 30000:
		return # still connecting: the frame budget starts with the run
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
	if int(arena.plan_room.get("chapter", 1)) != _last_chapter:
		_last_chapter = int(arena.plan_room.get("chapter", 1))
		print("%s: CHAPTER %d at room %d (%s, %d rooms)" % [role.to_upper(), _last_chapter, arena.room_index, arena.plan_room.get("floor"), int(arena.plan_room.get("count", 0))])
	if shot_dir != "" and arena.boss_spawned and arena.enemies().size() > 0 and frame % 200 == 0 and frame < 99999:
		get_viewport().get_texture().get_image().save_png("%s/%s_boss_%d.png" % [shot_dir, role, frame])
	if shot_dir != "":
		_event_shots()
	if frame % 600 == 0:
		var hp := []
		for h in arena.heroes(): hp.append("%s:%d%s" % [h.key, h.hp, " DOWN" if h.downed else ""])
		var es := []
		for en in arena.enemies(): es.append("%s@%d,%d:%d" % [en.kind, en.position.x, en.position.y, en.hp])
		print("%s f%d room %d wave %d enemies %d proj %d heroes %s clear=%s door=%s panel=%s %s" % [role.to_upper(), frame, arena.room_index, arena.wave_index, arena.enemies().size(), arena.projectiles.size(), hp, arena.room_clear, arena.door_open, is_instance_valid(arena.hud.boon_panel), es if es.size() < 4 else []])
		for h in arena.heroes(): if h.controlled: print("   hero at %d,%d state %s" % [h.position.x, h.position.y, h.state])
	# Auto-pick boons.
	if arena.hud.boon_panel and is_instance_valid(arena.hud.boon_panel) and _panel_seen != arena.hud.boon_panel:
		_panel_seen = arena.hud.boon_panel
		_panel_frame = frame
	if arena.hud.boon_panel and is_instance_valid(arena.hud.boon_panel) and frame % 20 == 0 and frame - _panel_frame > (60 if shot_dir != "" else 0):
		for b in arena.hud.boon_panel.find_children("*", "Button", true, false):
			b.pressed.emit()
			break
	if arena.door_open and _logged_doors != arena.room_index:
		_logged_doors = arena.room_index
		print("%s: room %d (%s) exits %s (reward this room: %s) gold=%d shards=%d props_left=%d at %s" % [role.to_upper(), arena.room_index, arena.plan_room.get("type"), arena.door_rewards, arena.room_reward, Game.run_gold, Game.run_shards, arena._props.size(), arena.door_points])
	for h in pads.keys():
		if not is_instance_valid(h): continue
		if h.state == "special" and not _spec_state.get(h, false):
			stats_specials += 1
		_spec_state[h] = h.state == "special"
		stats_forge = h.boons.get("_forge", {}).size()
		var p: FakePad = pads[h]
		p.attack = false; p.dash = false
		if god and h.hp < h.max_hp * 0.4 and not h.downed:
			h.hp = h.max_hp
		var target: Vector2
		var e = null
		var bd := INF
		for en in arena.enemies():
			var d: float = en.position.distance_to(h.position)
			if d < bd: bd = d; e = en
		if p.hold > 0:
			p.hold -= 1
			p.special = p.hold > 0
		else:
			p.special = false
		if e:
			target = e.position
			var ranged: bool = h.weapon_id == "bow"
			var want := 380.0 if ranged else 90.0
			p.move = (target - h.position).normalized() if bd > want else Vector2.ZERO
			if ranged and bd < 200:
				p.move = (h.position - target).normalized() # kite, don't shoot
			elif ranged and bd <= want:
				p.move = Vector2.ZERO
			if bd < (520 if ranged else 140):
				h.facing = (target - h.position).normalized()
				if ranged:
					p.attack = (frame % 90) < 40 if (frame / 90) % 3 == 0 else frame % 6 < 2 # charged shots and quick taps
				else:
					p.attack = frame % 4 < 2
			# aimed special: hold the button and drag the reticle onto the foe, release to cast
			if frame % 70 == 0 and h.special_cd <= 0.0 and bd < 460 and p.hold == 0:
				p.hold = 14
				p.special = true
				p.special_aim = ((target - h.position) / h.aim_range()).limit_length(1.0)
				if (frame / 70) % 4 == 3:
					p.special_aim = Vector2.ZERO # quick tap: auto-aim
					p.hold = 2
			p.dash = frame % 97 == 0
		elif arena.door_open:
			# choose the exit: prefer the Forge to exercise it, otherwise alternate
			var k: int = arena.room_index % arena.door_points.size()
			var fi: int = arena.door_rewards.find("forge")
			if fi >= 0 and fi < arena.door_points.size(): k = fi
			p.move = (arena.door_points[k] - h.position).normalized()
		else:
			p.move = Vector2.ZERO
		_avoid_hazards(h, p)
		_unstick(h, p)

## Steer around lava / spikes: probe ahead and sidestep if the next steps are hot; walk out if standing in it.
func _avoid_hazards(h: Node, p: FakePad) -> void:
	var inside := float(arena.env.hazard_at(h.position)["dps"]) > 0.0
	if inside:
		hazard_frames += 1
	var want: Vector2 = p.move
	if want.length() < 0.1:
		if not inside:
			return
		want = Vector2.RIGHT.rotated(float(frame / 120) * 1.3) # pick some way out
	var reach := 140.0 if inside else 70.0
	for ang in [0.0, 0.6, -0.6, 1.2, -1.2, 1.9, -1.9, PI]:
		var d: Vector2 = want.rotated(ang)
		if float(arena.env.hazard_at(h.position + d * reach)["dps"]) <= 0.0:
			p.move = d
			return
	p.move = want

## Walking into a wall or pillar: slide sideways for a moment.
var _stuck := {}
func _unstick(h: Node, p: FakePad) -> void:
	var st: Array = _stuck.get(h, [h.position, frame, 0, 1.0])
	if st[2] > frame:
		p.move = (p.move.orthogonal() * float(st[3]) - p.move * 0.3).normalized() if p.move.length() > 0.1 else Vector2.UP
		_stuck[h] = st
		return
	if frame - int(st[1]) >= 45:
		if p.move.length() > 0.1 and h.state == "run" and h.position.distance_to(st[0]) < 12.0:
			st[2] = frame + 30 + (frame / 45) % 3 * 20
			st[3] = -float(st[3])
		st[0] = h.position
		st[1] = frame
	_stuck[h] = st

var _shot_n := {}
var _panel_seen = null
var _panel_frame := 0
var _shot_last := -1000
## Screenshots of the new combat moments: aiming, special impacts, the exits.
func _event_shots() -> void:
	if frame - _shot_last < 25:
		return
	var tag := ""
	for h in arena.heroes():
		if h.controlled and h.aiming:
			tag = "aim"
		if h.controlled and h.state == "special" and h.state_t > h.special_hit * 0.8:
			tag = "special"
	for c in arena.casts:
		if int(c["stage"]) >= 2:
			tag = "cast"
	if arena.door_open and arena.door_points.size() > 1:
		tag = "doors"
	if arena.hud.boon_panel and is_instance_valid(arena.hud.boon_panel) and arena.room_reward == "forge":
		tag = "forge"
	if is_instance_valid(arena.hud._card) and arena.hud._card.modulate.a > 0.95:
		tag = "chapter%d" % int(arena.plan_room.get("chapter", 1))
	if tag == "forge" and frame - _panel_frame < 45:
		return
	if tag == "" or _shot_n.get(tag, 0) >= (1 if tag.begins_with("chapter") else 4):
		return
	_shot_n[tag] = _shot_n.get(tag, 0) + 1
	_shot_last = frame
	get_viewport().get_texture().get_image().save_png("%s/%s_%s_%d.png" % [shot_dir, role, tag, frame])

func _quit() -> void:
	var avg := 0.0
	for f in fps_samples: avg += f
	if fps_samples.size() > 0: avg /= fps_samples.size()
	print("%s: hazard_frames=%d killer=%s bosses=%s chapter=%d props_broken=%d" % [role.to_upper(), hazard_frames, Game.run_killer, Game.run_bosses, Game.run_chapter, arena.props_broken if is_instance_valid(arena) else -1])
	print("%s: frames=%d max_room=%d specials=%d forge_upgrades=%d gold=%d" % [role.to_upper(), frame, max_room, stats_specials, stats_forge, Game.run_gold])
	get_tree().quit()
