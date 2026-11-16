extends "res://entities/enemies/brain.gd"
## Hollow Champion (ch4 elite, rush): the Regent's sword. Three-beat combo (three arcs of markers, timed apart),
## a dash slash along a locked line that may chain into a rising cut, and a judgment wave that travels along a line.

const COL := Color(0.8, 0.45, 1.0)


func attacks() -> Dictionary:
	return {
		"combo": {"w": 0.55, "a": 0.9, "r": 0.9, "cd": 2.6, "range": [0.0, 150.0], "weight": 2.0,
			"aw": "combo_w", "aa": "combo", "track": 0.6, "tele": "cone", "tele_len": 150.0, "tele_arc": 140.0, "col": COL,
			"speed": 80.0},
		"dash": {"w": 0.6, "a": 0.4, "r": 0.7, "cd": 3.5, "range": [160.0, 540.0], "weight": 2.0,
			"aw": "slash_w", "aa": "dash", "loop_a": true, "track": 0.6, "tele": "line", "tele_len": 420.0, "tele_w": 56.0,
			"col": COL, "speed": 820.0, "hit_r": 44.0, "dmg": 16.0, "next": "upslash", "next_p": 0.6},
		"upslash": {"w": 0.25, "a": 0.2, "r": 0.8, "cd": 0.0, "range": [0.0, 0.0], "weight": 0.0,
			"aw": "upslash_w", "aa": "upslash", "tele": "cone", "tele_len": 120.0, "tele_arc": 120.0, "col": COL},
		"wave": {"w": 0.9, "a": 0.3, "r": 1.0, "cd": 5.0, "range": [0.0, 620.0], "weight": 1.0,
			"aw": "judgment_w", "aa": "judgment", "track": 0.5, "tele": "line", "tele_len": 560.0, "tele_w": 60.0, "col": COL},
	}


func on_strike(id: String) -> void:
	match id:
		"combo":
			slam_arc(82.0, 130.0, 3, 46.0, 0.05, 13.0, COL)
			slam_arc(92.0, 150.0, 3, 46.0, 0.35, 13.0, COL)
			slam_arc(100.0, 110.0, 3, 50.0, 0.65, 15.0, COL)
		"upslash":
			slam_arc(80.0, 120.0, 3, 48.0, 0.02, 15.0, COL)
		"wave":
			slam_line(e.position, e.aim, 8, 68.0, 40.0, 0.05, 0.06, 16.0, COL)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 100.0 else Vector2.ZERO
