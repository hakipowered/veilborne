extends "res://entities/enemies/brain.gd"
## Hammer Warden (ch3 elite, area): forge sentinel. Smash marks its impact, then quake rings ripple outward in two
## waves (stand between them or leave); a tracked hammer swing; a spinning advance late in the fight.

const COL := Color(1.0, 0.5, 0.15)


func attacks() -> Dictionary:
	return {
		"swing": {"w": 0.5, "a": 0.2, "r": 0.55, "cd": 1.4, "range": [0.0, 135.0], "weight": 2.0,
			"aw": "swing_w", "aa": "swing", "track": 0.6, "tele": "cone", "tele_len": 135.0, "tele_arc": 120.0, "col": COL},
		"smash": {"w": 0.85, "a": 0.25, "r": 0.95, "cd": 2.6, "range": [0.0, 190.0], "weight": 2.0,
			"aw": "slam_w", "aa": "slam", "col": COL},
		"spin": {"w": 0.6, "a": 1.3, "r": 1.0, "cd": 5.5, "range": [0.0, 220.0], "weight": 1.0,
			"aw": "spin_w", "aa": "spin", "loop_a": true, "tele": "ring", "tele_r": 110.0, "col": COL,
			"hit_r": 72.0, "dmg": 12.0},
	}


func on_windup(id: String) -> void:
	if id == "smash":
		e.arena.telegraph_slam(ahead(85.0), 96.0, e.windup_len(), 18.0, COL)


func on_strike(id: String) -> void:
	match id:
		"swing":
			slam_arc(80.0, 120.0, 3, 46.0, 0.03, 14.0, COL)
		"smash":
			e.arena.shake(8.0)
			var c := ahead(85.0)
			slam_ring(c, 160.0, 9, 32.0, 0.35, 10.0, COL)
			slam_ring(c, 250.0, 13, 32.0, 0.7, 10.0, COL, PI / 13.0)


func strike_move(id: String, _t: float) -> Vector2:
	if id == "spin":
		var tg = e.target_node()
		if tg != null:
			return (tg.position - e.position).normalized() * 95.0
	return Vector2.ZERO


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 110.0 else Vector2.ZERO
