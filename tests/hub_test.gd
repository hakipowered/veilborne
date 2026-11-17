extends Node
## Headless bot for the manor hub. Walks the heroine (through the doorways) to every station, opens each
## interaction, hits a training dummy with the aimed special and with attacks, unlocks an aspect, swears a
## vow, buys a renovation, gives a gift, swaps sisters and finally takes the gate into a run.
##   godot --headless res://tests/hub_test.tscn
##   xvfb-run godot res://tests/hub_test.tscn --resolution 1920x1080 -- --shots=/path/dir   (area screenshots)

const ManorScript := preload("res://scenes/manor.gd")

class FakePad:
	var move := Vector2.ZERO
	var attack := false
	var special := false
	var dash := false
	var special_aim := Vector2.ZERO

var hub: Node
var arena: Node
var pad := FakePad.new()
var frame := 0
var step := 0
var step_frames := 0
var fails: Array = []
var log_lines: Array = []
var shot_dir := ""
var _path: Array = []
var _started := false
var _run_frames := 0
var _dummy_before := 0.0
var _hits_before := 0

const DOORS := {
	"hall|kitchen": Vector2(-500, 0), "hall|armory": Vector2(0, -500),
	"kitchen|courtyard": Vector2(-1000, -500), "armory|courtyard": Vector2(-500, -1000),
}
const LINKS := {"hall": ["kitchen", "armory"], "kitchen": ["hall", "courtyard"], "armory": ["hall", "courtyard"], "courtyard": ["kitchen", "armory"]}


func _ready() -> void:
	name = "Main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shots="):
			shot_dir = a.substr(8)
	Game.load_slot("solo", 2)
	Game.data["shards"] = 500
	Game.data["gold"] = 400
	Game.data["decor"] = {}
	Game.data["aspects"] = {}
	Game.data["meta"] = {}
	Game.data["hub_gifts"] = {}
	Game.data["last_hero"] = "kaela"
	Game.set_loadout("bow", 0)
	Game.save_slot()
	if shot_dir != "":
		Engine.max_physics_steps_per_frame = 1
		Game.data["decor"] = {"lanterns": true, "rugs": true, "banners": true, "fountain": true, "statues": true}
	hub = load("res://scenes/hub.gd").new()
	add_child(hub)
	hub.start_requested.connect(_on_start)
	hub.setup_hub("kaela", false)
	hub.hero.touch = pad
	print("HUB: built, %d stations, %d dummies" % [hub.stations.size(), hub.dummies.size()])


func play_dialogue(lines: Array, done: Callable) -> void:
	log_lines.append(lines.size())
	done.call()


func _station(id: String) -> Dictionary:
	for s in hub.stations:
		if s["id"] == id:
			return s
	return {}


## Plans waypoints from the heroine to a world point through the doorways.
func _plan(to: Vector2) -> void:
	_path.clear()
	var from_area: String = hub.manor.area_at(hub.hero.position)
	var to_area: String = hub.manor.area_at(to)
	var route := _route(from_area, to_area)
	for i in range(route.size() - 1):
		var a: String = route[i]
		var b: String = route[i + 1]
		var key := a + "|" + b if DOORS.has(a + "|" + b) else b + "|" + a
		var d: Vector2 = DOORS[key]
		var ca: Vector2 = ManorScript.AREAS[a]["g"]
		var cb: Vector2 = ManorScript.AREAS[b]["g"]
		_path.append(ManorScript.w(d.x, d.y).lerp(ManorScript.w(ca.x, ca.y), 0.12))
		_path.append(ManorScript.w(d.x, d.y).lerp(ManorScript.w(cb.x, cb.y), 0.12))
	_path.append(to)


func _route(a: String, b: String) -> Array:
	if a == b:
		return [a]
	var q := [[a]]
	var seen := {a: true}
	while not q.is_empty():
		var p: Array = q.pop_front()
		for n in LINKS[p[-1]]:
			if seen.has(n):
				continue
			var np := p + [n]
			if n == b:
				return np
			seen[n] = true
			q.append(np)
	return [a, b]


var _last_pos := Vector2.ZERO
var _stuck := 0
var _side := 0
var _side_sign := 1.0


## Walks along the planned path (sidestepping when blocked by furniture); true when arrived.
func _walk(tol := 40.0) -> bool:
	if _path.is_empty():
		pad.move = Vector2.ZERO
		return true
	var tgt: Vector2 = _path[0]
	var d: Vector2 = tgt - hub.hero.position
	if _side > 0:
		_side -= 1
		pad.move = d.normalized().rotated(PI * 0.5 * _side_sign)
		return false
	if hub.hero.position.distance_to(_last_pos) < 0.5 and pad.move != Vector2.ZERO:
		_stuck += 1
		if _stuck > 12:
			_stuck = 0
			_side = 40
			_side_sign = -_side_sign
	else:
		_stuck = 0
	_last_pos = hub.hero.position
	if d.length() < tol:
		_path.pop_front()
		pad.move = Vector2.ZERO
		return _path.is_empty()
	pad.move = d.normalized()
	return false


func _fail(msg: String) -> void:
	fails.append(msg)
	print("HUB FAIL: " + msg)


func _shot(name_: String) -> void:
	if shot_dir == "":
		return
	var vs := get_viewport().get_visible_rect().size
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%dx%d.png" % [shot_dir, name_, int(img.get_width()), int(img.get_height())])
	print("HUB: shot %s (%s)" % [name_, vs])


func _physics_process(_delta: float) -> void:
	frame += 1
	step_frames += 1
	if frame > 20000:
		_fail("timeout at step %d" % step)
		_finish()
		return
	if _started:
		_run_frames += 1
		if _run_frames == 240:
			print("HUB: run started, room %d, enemies %d" % [arena.room_index, arena.enemies().size()])
			_finish()
		return
	if shot_dir != "":
		_shots_script()
		return
	_script()


## Screenshot tour: each area, a panel and a conversation prompt.
var _shot_plan := [
	["hall", Vector2(60, 120)], ["hall_gran", Vector2(-160, 380)], ["kitchen", Vector2(-1040, 230)],
	["armory", Vector2(-80, -930)], ["armory_racks", Vector2(130, -1240)], ["courtyard", Vector2(-860, -860)],
	["courtyard_gate", Vector2(-1180, -1150)],
]


func _shots_script() -> void:
	var i := step
	if i < _shot_plan.size():
		if step_frames == 1:
			var gp: Vector2 = _shot_plan[i][1]
			hub.hero.position = ManorScript.w(gp.x, gp.y)
			hub.camera.position = hub.hero.position
			hub.camera.reset_smoothing()
			pad.move = Vector2(0.01, 0.01)
		if step_frames == 4:
			pad.move = Vector2.ZERO
		if step_frames == 70:
			_shot(String(_shot_plan[i][0]))
			step += 1
			step_frames = 0
		return
	if i == _shot_plan.size():
		if step_frames == 2:
			var gp: Vector2 = Vector2(0, -1250)
			hub.hero.position = ManorScript.w(gp.x, gp.y)
			hub.open_armory("bow")
		if step_frames == 40:
			_shot("panel_armory")
			hub._close_panel()
			hub.open_renovations()
		if step_frames == 80:
			_shot("panel_renovate")
			hub._close_panel()
			hub.open_vows()
		if step_frames == 120:
			_shot("panel_vows")
			hub._close_panel()
			step += 1
			step_frames = 0
		return
	_finish()


## The functional bot.
func _script() -> void:
	match step:
		0: _goto_and("ysolde", "talk")
		1: _goto_and("wren", "talk")
		2: _goto_and("wren", "gift")
		3: _goto_and("odo", "talk")
		4:
			if _goto("board"):
				hub._do("renovate")
				if hub._panel == null:
					_fail("renovation panel did not open")
				if not hub.buy_decor("lanterns"):
					_fail("buy_decor failed")
				if not bool(Game.data["decor"].get("lanterns", false)):
					_fail("decor not saved")
				var saved := Game.peek_slot("solo", 2)
				if not bool(saved.get("decor", {}).get("lanterns", false)):
					_fail("decor not persisted to disk")
				hub._close_panel()
				_next()
		5: _goto_and("bram", "talk")
		6:
			if _goto("rack_bow"):
				hub._do("armory")
				if hub._panel == null:
					_fail("armory panel did not open")
				if not hub.unlock_aspect("bow", 1):
					_fail("unlock_aspect failed")
				if not Game.aspect_unlocked("bow", 1) or Game.run_aspect != 1 or hub.hero.aspect != 1:
					_fail("aspect not unlocked/equipped on the heroine")
				hub._close_panel()
				_next()
		7:
			# special on a dummy (aimed volley auto-aims the nearest foe)
			if step_frames == 1:
				_plan(hub.dummies[0].position + Vector2(-260, 60))
			if _walk(30.0) or step_frames > 900:
				pad.move = Vector2.ZERO
				_dummy_before = _dummy_total()
				_hits_before = _dummy_hits()
				pad.special = true
				_next()
		8:
			if step_frames == 4:
				pad.special = false
			if step_frames == 100:
				var dealt := _dummy_total() - _dummy_before
				print("HUB: special dealt %.1f to dummies (casts now %d)" % [dealt, hub.casts.size()])
				if dealt <= 0.0:
					_fail("special did not damage a dummy")
				_next()
		9:
			# melee / shots until a dummy breaks or 600 frames
			if step_frames == 1:
				_plan(hub.dummies[1].position + Vector2(-120, 20))
			if _walk(30.0) or step_frames > 900:
				_next()
		10:
			var d: Node2D = hub.dummies[1]
			pad.move = Vector2.ZERO
			pad.attack = step_frames % 6 < 3
			if step_frames % 90 == 0:
				pad.special = true
			elif step_frames % 90 == 5:
				pad.special = false
			if hub.dummy_breaks > 0 or step_frames > 900:
				pad.attack = false
				pad.special = false
				print("HUB: dummy hits %d, total %.0f, breaks %d" % [_dummy_hits(), _dummy_total(), hub.dummy_breaks])
				if _dummy_hits() <= _hits_before:
					_fail("attacks did not hit a dummy")
				_next()
		11:
			if step_frames > 120:
				var back := 0
				for d in hub.dummies:
					if d.hp >= d.max_hp:
						back += 1
				if back < hub.dummies.size():
					_fail("dummies did not stand back up")
				_next()
		12:
			if _goto("altar"):
				hub._do("vows")
				if hub._panel == null:
					_fail("vows panel did not open")
				var mh: int = hub.hero.max_hp
				if not hub.buy_vow("vitality"):
					_fail("buy_vow failed")
				if hub.hero.max_hp <= mh:
					_fail("vitality vow did not raise max health")
				hub._close_panel()
				_next()
		13: _goto_and("corwin", "talk")
		14: _goto_and("ysolde", "swap")
		15:
			hub.hero.touch = pad # the new sister listens to the bot's pad too
			if hub.hero_id != "liora" or String(Game.data["last_hero"]) != "liora":
				_fail("sister swap failed")
			if hub.hero.weapon_id != "bow":
				_fail("loadout lost on swap")
			_next()
		16:
			if _goto("gate"):
				hub._do("descend")
				_next()
		17:
			if step_frames > 200:
				_fail("gate did not start a run")
				_finish()


func _dummy_total() -> float:
	var t := 0.0
	for d in hub.dummies:
		t += d.total
	return t


func _dummy_hits() -> int:
	var t := 0
	for d in hub.dummies:
		t += d.hits
	return t


func _next() -> void:
	step += 1
	step_frames = 0


func _goto(id: String) -> bool:
	var s := _station(id)
	if s.is_empty():
		_fail("no station " + id)
		_next()
		return false
	if step_frames == 1:
		_plan(s["pos"])
	var arrived := _walk(30.0)
	if hub.near_id() == id and (arrived or _path.size() <= 1):
		pad.move = Vector2.ZERO
		print("HUB: reached %s at frame %d (%d frames)" % [id, frame, step_frames])
		return true
	if step_frames > 1500:
		_fail("could not reach %s (at %s, area %s, near %s)" % [id, hub.hero.position, hub.manor.area_at(hub.hero.position), hub.near_id()])
		_next()
	return false


func _goto_and(id: String, action: String) -> void:
	if _goto(id):
		var n := log_lines.size()
		var gold := int(Game.data.get("gold", 0))
		hub._do(action)
		if action == "talk" and log_lines.size() <= n:
			_fail("talking to %s played no lines" % id)
		if action == "gift" and int(Game.data.get("gold", 0)) != gold - hub.GIFT_COST:
			_fail("gift to %s did not spend gold" % id)
		if hub.busy:
			_fail("%s:%s left the hub paused" % [id, action])
		_next()


func _on_start() -> void:
	print("HUB: gate -> start_requested; opened %s" % [hub.opened])
	var hid := String(Game.data.get("last_hero", "kaela"))
	hub.queue_free()
	Game.players = [{"peer": 1, "local_index": 0, "hero": hid}]
	Game.start_run(4242)
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	_started = true


func _finish() -> void:
	set_physics_process(false)
	print("HUB: opened %s" % [hub.opened if is_instance_valid(hub) else "-"])
	print("HUB: decor %s gold %d shards %d" % [Game.data.get("decor"), int(Game.data.get("gold", 0)), int(Game.data.get("shards", 0))])
	if fails.is_empty():
		print("HUB: PASS")
	else:
		print("HUB: FAILED %d: %s" % [fails.size(), fails])
	get_tree().quit(0 if fails.is_empty() else 1)
