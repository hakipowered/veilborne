extends "res://entities/enemies/brain.gd"
## Hollow Pike (ch4 area/reach): spear soldier that holds you at spear length. Wide reaping sweep (two arcs of
## markers) and a tracked thrust that skewers a line; both leave a long recovery to punish.

const COL := Color(0.72, 0.4, 1.0)


func attacks() -> Dictionary:
	return {
		"sweep": {"w": 0.7, "a": 0.25, "r": 0.75, "cd": 2.2, "range": [0.0, 200.0], "weight": 1.5,
			"aw": "sweep_w", "aa": "sweep", "track": 0.5, "tele": "cone", "tele_len": 190.0, "tele_arc": 160.0, "col": COL},
		"thrust": {"w": 0.55, "a": 0.2, "r": 0.6, "cd": 1.5, "range": [60.0, 270.0], "weight": 2.0,
			"aw": "thrust_w", "aa": "thrust", "track": 0.7, "tele": "line", "tele_len": 270.0, "tele_w": 40.0, "col": COL,
			"speed": 220.0},
	}


func on_strike(id: String) -> void:
	match id:
		"sweep":
			slam_arc(150.0, 160.0, 5, 44.0, 0.03, 13.0, COL)
			slam_arc(85.0, 150.0, 3, 40.0, 0.03, 13.0, COL)
		"thrust":
			slam_line(e.position, e.aim, 4, 62.0, 34.0, 0.02, 0.03, 14.0, COL)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	if dist > 170.0:
		return dir * e.speed()
	if dist < 110.0:
		return -dir * e.speed() * 0.6
	return Vector2.ZERO
