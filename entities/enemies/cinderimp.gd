extends "res://entities/enemies/brain.gd"
## Cinder Imp (ch3 ranged): circles at range, spits 3-ember fans (aim locks at 80%), drops fire pools under you,
## and hops away when you get close.

const COL := Color(1.0, 0.55, 0.15)
var _orbit := 1.0 if randf() < 0.5 else -1.0


func attacks() -> Dictionary:
	return {
		"volley": {"w": 0.6, "a": 0.2, "r": 0.55, "cd": 2.0, "range": [110.0, 560.0], "weight": 2.0,
			"aw": "volley_w", "aa": "volley", "track": 0.8, "tele": "line", "tele_len": 300.0, "tele_w": 18.0, "col": COL},
		"pool": {"w": 0.75, "a": 0.2, "r": 0.6, "cd": 4.0, "range": [90.0, 520.0], "weight": 1.0,
			"aw": "cast_w", "aa": "cast", "tele": "aux", "tele_r": 62.0, "col": COL},
		"hop": {"w": 0.15, "a": 0.42, "r": 0.3, "cd": 3.0, "range": [0.0, 120.0], "weight": 3.0,
			"aw": "idle", "aa": "hop", "leap": 60.0},
	}


func on_windup(id: String) -> void:
	match id:
		"pool":
			e.aux = lead(e.windup_len())
			e.arena.telegraph_slam(e.aux, 62.0, e.windup_len(), 10.0, COL)
		"hop":
			var away: Vector2 = -e.aim.rotated(randf_range(-0.6, 0.6))
			e.aux = e.arena.resolve_collision(e.position + away * 180.0, e.radius)


func on_strike(id: String) -> void:
	if id == "volley":
		fan(3, 26.0, 330.0, 8.0, COL, 10.0)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	var radial := 0.0
	if dist > 300.0:
		radial = 1.0
	elif dist < 200.0:
		radial = -1.0
	return (dir * radial + dir.orthogonal() * _orbit * 0.8).normalized() * e.speed()
