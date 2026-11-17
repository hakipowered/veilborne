extends "res://entities/enemies/brain.gd"
## Bog Wraith (ch2 rush): a reed-and-water spirit that weaves in fast, telegraphs a straight lunge
## (line marker, aim locks at 70% of the windup), then hangs exposed. Up close it rakes a short arc.

const COL := Color(0.35, 1.0, 0.75)
var _weave := randf() * TAU


func attacks() -> Dictionary:
	return {
		"lunge": {"w": 0.5, "a": 0.32, "r": 0.6, "cd": 1.8, "range": [70.0, 330.0], "weight": 2.0,
			"aw": "lunge_w", "aa": "lunge", "track": 0.7, "tele": "line", "tele_len": 250.0, "tele_w": 40.0, "col": COL,
			"speed": 640.0, "hit_r": 34.0, "dmg": 11.0},
		"rake": {"w": 0.38, "a": 0.18, "r": 0.5, "cd": 1.2, "range": [0.0, 95.0], "weight": 1.5,
			"aw": "rake_w", "aa": "rake", "track": 0.5, "tele": "cone", "tele_len": 110.0, "tele_arc": 120.0, "col": COL},
	}


func on_strike(id: String) -> void:
	if id == "rake":
		slam_arc(66.0, 100.0, 3, 40.0, 0.04, 9.0, COL)


func locomote(delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	_weave += delta * 4.0
	var side := dir.orthogonal() * sin(_weave) * 0.55
	return (dir + side).normalized() * e.speed() if dist > 60.0 else Vector2.ZERO
