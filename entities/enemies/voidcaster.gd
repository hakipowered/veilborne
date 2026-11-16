extends "res://entities/enemies/brain.gd"
## Void Caster (ch4 summoner/ranged): stays back, fires void bolts, opens runes under every heroine (filling
## markers = step off), raises shades, and blinks away when cornered.

const COL := Color(0.65, 0.3, 1.0)


func attacks() -> Dictionary:
	return {
		"bolt": {"w": 0.5, "a": 0.2, "r": 0.5, "cd": 1.7, "range": [100.0, 680.0], "weight": 2.0,
			"aw": "bolt_w", "aa": "bolt", "track": 0.85, "tele": "line", "tele_len": 340.0, "tele_w": 16.0, "col": COL},
		"runes": {"w": 1.1, "a": 0.2, "r": 0.6, "cd": 4.5, "range": [0.0, 760.0], "weight": 1.5,
			"aw": "cast_w", "aa": "cast", "col": COL},
		"summon": {"w": 1.0, "a": 0.3, "r": 0.8, "cd": 10.0, "range": [0.0, 900.0], "weight": 1.0,
			"aw": "cast_w", "aa": "cast", "tele": "ring", "tele_r": 90.0, "col": COL},
		"blink": {"w": 0.35, "a": 0.1, "r": 0.25, "cd": 5.0, "range": [0.0, 140.0], "weight": 4.0,
			"aw": "cast_w", "aa": "cast", "tele": "ring", "tele_r": 50.0, "col": COL},
	}


func on_windup(id: String) -> void:
	if id == "runes":
		for h in live_heroes():
			e.arena.telegraph_slam(e.arena.resolve_collision(h.position, 10.0), 70.0, e.windup_len(), 13.0, COL)


func on_strike(id: String) -> void:
	match id:
		"bolt":
			fan(3, 14.0, 360.0, 10.0, COL, 12.0)
		"summon":
			summon("shade", 2, 3)
		"blink":
			e.arena.spark(e.position + Vector2(0, -60), COL, 14)
			var away: Vector2 = -e.aim.rotated(randf_range(-0.9, 0.9))
			e.position = e.arena.resolve_collision(e.position + away * 280.0, e.radius)
			e.arena.spark(e.position + Vector2(0, -60), COL, 14)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	if dist < 260.0:
		return -dir * e.speed()
	if dist > 480.0:
		return dir * e.speed()
	return dir.orthogonal() * e.speed() * 0.3
