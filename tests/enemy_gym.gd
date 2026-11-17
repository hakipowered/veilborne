extends "res://tests/harness.gd"
## Headless enemy gym: spawns every enemy kind and boss, one at a time, against the harness bot heroine (kept alive).
## Each one must start attacks (state ATTACK), take damage from the bot, change phase (bosses) and die cleanly.
##   godot --headless --path . res://tests/enemy_gym.tscn --fixed-fps 60 [-- --only=kind,kind]
## Prints "GYM: PASS" or "GYM: FAIL <reasons>" and quits. SCRIPT ERRORs show up in the log as usual.

const EnemyScript := preload("res://entities/enemy.gd")

var queue: Array = []
var cur: Node2D = null
var cur_kind := ""
var t0 := 0
var seen := {}
var hurt := false
var phases := 0
var fails: Array = []
var report: Array = []
var _forced := false
var _last_missing: Array = []


func _ready() -> void:
	frames = 1 << 30
	seed(4242) # deterministic brain choices so the gym result is repeatable
	var only := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7)
	for k in EnemyScript.KIND_IDS:
		if k == "wisp":
			continue
		if only == "" or k in only.split(","):
			queue.append(k)
	# killing the Regent ends the run (victory), so he goes last
	if queue.has("regent"):
		queue.erase("regent")
		queue.append("regent")
	super._ready()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if arena == null or not is_instance_valid(arena):
		return
	arena.wave_delay = 9999.0
	for h in arena.heroes():
		h.hp = h.max_hp
	if frame < 90:
		return
	if cur == null:
		_next()
		return
	var lim := 2400 if cur.is_boss else 1800
	# first half: the bot only circles the enemy at alternating near/far distances (no hits), so every
	# range-gated attack gets a chance to show
	if (frame - t0 < lim / 2 or (not _last_missing.is_empty() and frame - t0 < lim)) and is_instance_valid(cur):
		for h in pads:
			var p = pads[h]
			p.attack = false
			p.special = false
			p.hold = 0
			p.dash = false
			var want := 80.0 if (frame / 150) % 2 == 0 else 330.0
			var to: Vector2 = cur.position - h.position
			var radial: float = clampf((to.length() - want) / 80.0, -1.0, 1.0)
			p.move = (to.normalized() * radial + to.normalized().orthogonal() * 0.7).normalized()
	if is_instance_valid(cur) and not cur.is_dead():
		if cur.brain != null and cur.state == EnemyScript.S_ATTACK and cur.atk >= 0:
			seen[cur.brain.atk_id(cur.atk)] = true
		if cur.hp < cur.max_hp:
			hurt = true
		phases = maxi(phases, cur.phase)
		if cur.brain != null:
			_last_missing = _missing()
		# after a stretch of free behaviour, start any attack the brain has not picked yet, so the
		# "every attack runs" check does not depend on the random choices / bot positioning
		if cur.brain != null and frame - t0 >= lim / 4 and frame % 15 == 0 \
				and (cur.state == EnemyScript.S_IDLE or cur.state == EnemyScript.S_MOVE):
			var miss := _last_missing
			if not miss.is_empty():
				var tg = cur.target_node()
				var d: Vector2 = cur.aim if tg == null else (tg.position - cur.position).normalized()
				cur._begin(miss[0], d)
		# bosses: push through the phase thresholds so every phase gets exercised
		if cur.is_boss and frame - t0 == lim / 3:
			cur.take_damage(cur.max_hp * 0.4, false, cur.position + Vector2(50, 0), "gym")
		if cur.is_boss and cur._phases.size() > 1 and frame - t0 == 2 * lim / 3:
			cur.take_damage(cur.max_hp * 0.3, false, cur.position + Vector2(50, 0), "gym")
		if frame - t0 >= lim and not _forced:
			_forced = true
			cur.take_damage(cur.hp + 1.0, false, cur.position + Vector2(50, 0), "gym")
		if frame - t0 >= lim + 400:
			_finish("did not die")
		return
	if not _forced:
		hurt = true # one-shot by the bot
	_finish("")


var _reported := false


func _quit() -> void:
	if not _reported:
		_reported = true
		if cur != null:
			_finish("")
		if not queue.is_empty():
			fails.append("not run: " + str(queue))
		print("GYM: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
		for r in report:
			print("GYM  ", r)
	super._quit()


func _next() -> void:
	if queue.is_empty():
		_quit()
		return
	# clean the floor: leftover adds/projectiles from the previous kind
	for en in arena.enemies():
		en.take_damage(99999.0, false, en.position, "gym")
	cur_kind = queue.pop_front()
	var h = arena.heroes()[0]
	cur = arena.spawn_enemy(cur_kind, h.position + Vector2(320, -60))
	t0 = frame
	seen = {}
	_last_missing = []
	hurt = false
	phases = 0
	_forced = false
	if cur == null:
		fails.append(cur_kind + ": spawn failed")
		return
	if cur.kind != cur_kind:
		fails.append(cur_kind + ": spawned as " + cur.kind)


## attacks the brain can pick at its current phase (weight > 0) that have not run yet
func _missing() -> Array:
	var out := []
	for id in cur.brain.ids:
		var a: Dictionary = cur.brain.A[id]
		if float(a.get("weight", 1.0)) <= 0.0 or int(a.get("phase", 0)) > cur.phase:
			continue
		if not seen.has(id):
			out.append(id)
	return out


func _finish(err: String) -> void:
	var line := "%s: attacks %s hurt=%s phase=%d killed_by_bot=%s" % [cur_kind, seen.keys(), hurt, phases, not _forced]
	report.append(line)
	if err != "":
		fails.append(cur_kind + ": " + err)
	if not _last_missing.is_empty():
		fails.append(cur_kind + ": attacks never ran " + str(_last_missing))
	if not hurt:
		fails.append(cur_kind + ": never took damage")
	if is_instance_valid(cur) and cur.is_boss and phases < cur._phases.size():
		fails.append(cur_kind + ": phase %d/%d" % [phases, cur._phases.size()])
	cur = null
