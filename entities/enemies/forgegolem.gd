extends "res://entities/enemies/brain.gd"
## Forge Golem (ch3 tank): slow, heavy. Long-telegraphed head-down charge (wide line, locks at 55%) that stuns it
## when it hits a wall; up close a two-handed slam with a delayed shockwave ring.

const COL := Color(1.0, 0.45, 0.12)


func attacks() -> Dictionary:
	return {
		"charge": {"w": 1.0, "a": 1.1, "r": 0.9, "cd": 4.5, "range": [160.0, 720.0], "weight": 1.5,
			"aw": "charge_w", "aa": "charge", "loop_a": true, "track": 0.55, "tele": "line", "tele_len": 520.0,
			"tele_w": 72.0, "col": COL, "speed": 520.0, "hit_r": 54.0, "dmg": 16.0, "charge": true, "stun": 1.6},
		"slam": {"w": 0.85, "a": 0.25, "r": 0.9, "cd": 2.4, "range": [0.0, 175.0], "weight": 2.0,
			"aw": "slam_w", "aa": "slam", "col": COL},
	}


func on_windup(id: String) -> void:
	if id == "slam":
		e.arena.telegraph_slam(ahead(80.0), 110.0, e.windup_len(), 18.0, COL)


func on_strike(id: String) -> void:
	if id == "slam":
		e.arena.shake(8.0)
		slam_ring(ahead(80.0), 175.0, 9, 32.0, 0.3, 8.0, COL)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 110.0 else Vector2.ZERO
