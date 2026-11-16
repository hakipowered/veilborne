extends "res://entities/enemies/brain.gd"
## Thorn Knight (ch2 elite, shield): walks in with its bark shield raised (frontal hits mostly blocked, gold arc).
## The shield drops during its swings and the long recovery after the thorn chop: flank it or bait the chop.

const COL := Color(0.55, 1.0, 0.4)
const GUARD_MUL := 0.2


func attacks() -> Dictionary:
	return {
		"bash": {"w": 0.5, "a": 0.2, "r": 0.6, "cd": 2.2, "range": [0.0, 115.0], "weight": 1.5,
			"aw": "bash_w", "aa": "bash", "track": 0.6, "tele": "cone", "tele_len": 120.0, "tele_arc": 90.0, "col": COL,
			"speed": 280.0, "hit_r": 46.0, "dmg": 14.0},
		"slash": {"w": 0.45, "a": 0.2, "r": 0.5, "cd": 1.6, "range": [0.0, 130.0], "weight": 2.0,
			"aw": "slash_w", "aa": "slash", "track": 0.6, "tele": "cone", "tele_len": 140.0, "tele_arc": 130.0, "col": COL,
			"next": "chop", "next_p": 0.45},
		"chop": {"w": 0.95, "a": 0.25, "r": 1.2, "cd": 4.0, "range": [0.0, 170.0], "weight": 1.0,
			"aw": "chop_w", "aa": "chop", "track": 0.5, "tele": "line", "tele_len": 250.0, "tele_w": 70.0, "col": COL},
		"thorns": {"w": 1.0, "a": 0.2, "r": 0.8, "cd": 7.0, "range": [150.0, 700.0], "weight": 1.0,
			"aw": "guard", "aa": "bash", "col": COL},
	}


func on_windup(id: String) -> void:
	e.guarding = id == "bash"
	if id == "thorns":
		for h in live_heroes():
			e.arena.telegraph_slam(e.arena.resolve_collision(h.position, 10.0), 64.0, e.windup_len(), 12.0, COL)


func on_strike(id: String) -> void:
	e.guarding = false
	match id:
		"slash":
			slam_arc(86.0, 130.0, 3, 48.0, 0.03, 14.0, COL)
		"chop":
			slam_line(e.position, e.aim, 4, 58.0, 46.0, 0.02, 0.07, 18.0, COL)
			e.arena.shake(6.0)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	e.guarding = true
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 90.0 else Vector2.ZERO


func filter_damage(amount: float, from_pos: Vector2) -> float:
	if e.guarding and e.aim.dot((from_pos - e.position).normalized()) > 0.25:
		return amount * GUARD_MUL
	return amount


func draw_extra() -> void:
	if not e.guarding or e.is_dead():
		return
	var a0: float = e.aim.angle()
	e.draw_set_transform(Vector2(0, -20), 0.0, Vector2(1.0, 0.55))
	e.draw_arc(Vector2.ZERO, e.radius + 18.0, a0 - 1.0, a0 + 1.0, 18, Color(1.0, 0.85, 0.35, 0.75), 4.0)
	e.draw_set_transform(Vector2.ZERO)
