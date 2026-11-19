extends "res://entities/enemies/brain.gd"
## Maren of the Drowned Garden (chapter 2 general). Scythe-gardener.
## Phase 1: reaping swing, three-beat combo, crushing leap (landing marked), spore fan, thorn field under each
##          heroine, calls sporelings / a bog wraith.
## Stage 2 (66% HP, shielded roar + bog wraiths): faster; seeds wisps, bloom rings (projectile ring + two
##          ripples of markers), the leap chains into a second leap.
## Stage 3 (33% HP, shielded roar + sporelings): creeping vines (three thorn rows race out at the heroine),
##          the petal storm (she drifts after you shedding two counter-turning spirals), a long breather after each.

const COL := Color(0.4, 1.0, 0.7)
const COL2 := Color(1.0, 0.5, 0.75)


func attacks() -> Dictionary:
	return {
		"reap": {"w": 0.7, "a": 0.25, "r": 0.8, "cd": 1.8, "range": [0.0, 210.0], "weight": 2.0,
			"aw": "reap_w", "aa": "reap", "track": 0.55, "tele": "cone", "tele_len": 200.0, "tele_arc": 170.0, "col": COL},
		"combo": {"w": 0.5, "a": 1.0, "r": 1.0, "cd": 3.0, "range": [0.0, 170.0], "weight": 1.5,
			"aw": "combo_w", "aa": "combo", "track": 0.6, "tele": "cone", "tele_len": 170.0, "tele_arc": 150.0, "col": COL,
			"speed": 110.0},
		"leap": {"w": 0.8, "a": 0.7, "r": 0.9, "cd": 5.0, "range": [180.0, 760.0], "weight": 1.5,
			"aw": "leap_w", "aa": "leap", "leap": 140.0, "tele": "aux", "tele_r": 130.0, "col": COL,
			"next": "leap2", "next_p": 1.0},
		"leap2": {"w": 0.45, "a": 0.6, "r": 1.0, "cd": 0.0, "range": [0.0, 0.0], "weight": 0.0, "phase": 1,
			"aw": "leap_w", "aa": "leap", "leap": 140.0, "tele": "aux", "tele_r": 130.0, "col": COL2},
		"sporefan": {"w": 0.7, "a": 0.3, "r": 0.7, "cd": 3.5, "range": [150.0, 900.0], "weight": 1.5,
			"aw": "cast_w", "aa": "cast", "track": 0.8, "tele": "line", "tele_len": 300.0, "tele_w": 30.0, "col": COL},
		"thorns": {"w": 1.0, "a": 0.3, "r": 0.8, "cd": 6.0, "range": [0.0, 900.0], "weight": 1.0,
			"aw": "cast_w", "aa": "cast", "col": COL},
		"summon": {"w": 1.0, "a": 0.4, "r": 0.8, "cd": 13.0, "range": [0.0, 900.0], "weight": 1.0, "max_phase": 1,
			"aw": "cast_w", "aa": "roar", "tele": "ring", "tele_r": 110.0, "col": COL},
		"seeds": {"w": 0.8, "a": 0.3, "r": 0.7, "cd": 7.0, "range": [0.0, 900.0], "weight": 1.2, "phase": 1,
			"aw": "cast_w", "aa": "cast", "tele": "ring", "tele_r": 90.0, "col": COL2},
		"bloomring": {"w": 0.9, "a": 0.3, "r": 0.9, "cd": 5.0, "range": [0.0, 900.0], "weight": 1.5, "phase": 1,
			"aw": "cast_w", "aa": "cast", "tele": "ring", "tele_r": 150.0, "col": COL2},
		"vines": {"w": 0.9, "a": 0.4, "r": 1.6, "cd": 6.0, "range": [0.0, 900.0], "weight": 1.6, "phase": 2,
			"aw": "reap_w", "aa": "reap", "track": 0.7, "tele": "cone", "tele_len": 260.0, "tele_arc": 60.0, "col": COL2},
		"petals": {"w": 0.8, "a": 2.2, "r": 1.5, "cd": 9.0, "range": [0.0, 900.0], "weight": 1.3, "phase": 2, "rep": 1,
			"aw": "cast_w", "aa": "cast", "loop_a": true, "tele": "ring", "tele_r": 130.0, "col": COL2},
	}


var _emit_t := 0.0
var _emit_a := 0.0


func base_cd() -> float:
	return 0.55 + randf() * 0.45


func on_windup(id: String) -> void:
	match id:
		"petals":
			_emit_t = 0.0
			_emit_a = randf() * TAU
		"leap", "leap2":
			e.aux = lead(e.windup_len() + 0.5)
			e.arena.telegraph_slam(e.aux, 130.0, e.windup_len() + float(A[id]["a"]), 22.0, COL if id == "leap" else COL2)
		"thorns":
			for h in live_heroes():
				for i in 5:
					var off := Vector2.RIGHT.rotated(TAU * i / 5.0 + randf()) * Vector2(70.0, 44.0) * (0.0 if i == 0 else 1.0)
					e.arena.telegraph_slam(e.arena.resolve_collision(h.position + off, 10.0), 58.0, e.windup_len() + i * 0.12, 12.0, COL)


func on_strike(id: String) -> void:
	match id:
		"vines":
			for k in 3:
				var d: Vector2 = e.aim.rotated(deg_to_rad(-26.0 + 26.0 * k))
				slam_line(e.position, d, 9, 72.0, 40.0, 0.25, 0.07, 14.0, COL2 if k == 1 else COL)
		"reap":
			slam_arc(125.0, 170.0, 5, 52.0, 0.03, 16.0, COL)
		"combo":
			slam_arc(95.0, 140.0, 3, 50.0, 0.05, 14.0, COL)
			slam_arc(105.0, 150.0, 3, 50.0, 0.38, 14.0, COL)
			slam_arc(115.0, 120.0, 3, 56.0, 0.72, 17.0, COL)
		"sporefan":
			fan(7 + 2 * e.phase, 70.0, 300.0, 10.0, COL, 12.0)
		"summon":
			summon("sporeling", 2, 3)
			summon("bogwraith", 1, 2)
		"seeds":
			summon("wisp", 3, 5, 90.0)
		"bloomring":
			ring(16, 240.0, 10.0, COL2, randf() * TAU, 12.0)
			slam_ring(e.position, 170.0, 9, 42.0, 0.3, 12.0, COL2)
			slam_ring(e.position, 280.0, 13, 42.0, 0.65, 12.0, COL2, PI / 13.0)


## petal storm: two counter-turning spirals while she drifts after the target (host only)
func strike_move(id: String, _t: float) -> Vector2:
	if id != "petals":
		return Vector2.ZERO
	_emit_t += e.get_physics_process_delta_time()
	if _emit_t >= 0.16:
		_emit_t -= 0.16
		_emit_a += 0.4
		ring(2, 230.0, 10.0, COL2, _emit_a, 12.0)
		ring(2, 200.0, 10.0, COL, -_emit_a + PI * 0.5, 11.0)
	var tg = e.target_node()
	if tg != null:
		return (tg.position - e.position).normalized() * 70.0
	return Vector2.ZERO


func on_phase(p: int) -> void:
	ring(20, 220.0, 10.0, COL2, 0.0, 12.0)
	if p >= 2:
		slam_ring(e.position, 220.0, 12, 42.0, 0.9, 12.0, COL)
		summon("sporeling", 3, 4)
	else:
		summon("bogwraith", 2, 3)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 150.0 else Vector2.ZERO
