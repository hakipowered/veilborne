extends "res://entities/enemies/brain.gd"
## Osric the Gravekeeper (chapter 1 general; kind id kept as gen_seneschal). The Regent's clerk with a grave-glaive.
## Phase 1: three-beat glaive combo, lunging judgment dash, void ring of bolts, grave marks under each heroine,
##          raises shades.
## Phase 2 (50% HP, roar): faster; judgment cross (lines of markers in a + then an x), wisps, double void ring.

const COL := Color(0.85, 0.78, 0.55)
const VOID := Color(0.7, 0.4, 1.0)


func attacks() -> Dictionary:
	return {
		"combo": {"w": 0.5, "a": 1.0, "r": 1.0, "cd": 2.6, "range": [0.0, 180.0], "weight": 2.0,
			"aw": "combo_w", "aa": "combo", "track": 0.6, "tele": "cone", "tele_len": 170.0, "tele_arc": 140.0, "col": COL,
			"speed": 100.0},
		"dash": {"w": 0.7, "a": 0.35, "r": 0.8, "cd": 4.0, "range": [150.0, 620.0], "weight": 1.5,
			"aw": "judgment_w", "aa": "dash", "loop_a": true, "track": 0.6, "tele": "line", "tele_len": 430.0, "tele_w": 60.0,
			"col": COL, "speed": 900.0, "hit_r": 46.0, "dmg": 18.0},
		"voidring": {"w": 0.8, "a": 0.3, "r": 0.7, "cd": 4.0, "range": [0.0, 900.0], "weight": 1.5,
			"aw": "cast_w", "aa": "cast", "tele": "ring", "tele_r": 120.0, "col": VOID},
		"graves": {"w": 1.0, "a": 0.2, "r": 0.7, "cd": 5.0, "range": [0.0, 900.0], "weight": 1.2,
			"aw": "cast_w", "aa": "cast", "col": COL},
		"summon": {"w": 1.0, "a": 0.3, "r": 0.8, "cd": 12.0, "range": [0.0, 900.0], "weight": 1.0,
			"aw": "cast_w", "aa": "roar", "tele": "ring", "tele_r": 100.0, "col": VOID},
		"cross": {"w": 1.0, "a": 0.3, "r": 1.0, "cd": 6.0, "range": [0.0, 900.0], "weight": 1.5, "phase": 1,
			"aw": "judgment_w", "aa": "judgment", "col": COL},
		"wisps": {"w": 0.8, "a": 0.3, "r": 0.7, "cd": 7.0, "range": [0.0, 900.0], "weight": 1.2, "phase": 1,
			"aw": "cast_w", "aa": "cast", "tele": "ring", "tele_r": 90.0, "col": VOID},
	}


func base_cd() -> float:
	return 0.55 + randf() * 0.45


func on_windup(id: String) -> void:
	match id:
		"graves":
			for h in live_heroes():
				e.arena.telegraph_slam(e.arena.resolve_collision(h.position, 10.0), 76.0, e.windup_len(), 16.0, COL)
		"cross":
			for i in 4:
				var d := Vector2.RIGHT.rotated(PI * 0.5 * i)
				slam_line(e.position, d * Vector2(1.0, 0.62), 7, 70.0, 40.0, e.windup_len(), 0.05, 18.0, COL)
			for i in 4:
				var d2 := Vector2.RIGHT.rotated(PI * 0.25 + PI * 0.5 * i)
				slam_line(e.position, d2 * Vector2(1.0, 0.62), 7, 70.0, 40.0, e.windup_len() + 0.55, 0.05, 18.0, VOID)


func on_strike(id: String) -> void:
	match id:
		"combo":
			slam_arc(90.0, 130.0, 3, 48.0, 0.05, 14.0, COL)
			slam_arc(100.0, 150.0, 3, 48.0, 0.38, 14.0, COL)
			slam_arc(110.0, 110.0, 3, 54.0, 0.72, 17.0, COL)
		"voidring":
			ring(14, 260.0, 11.0, VOID, randf() * TAU, 12.0)
			if e.phase >= 1:
				ring(14, 190.0, 11.0, VOID, randf() * TAU, 12.0)
		"summon":
			summon("shade", 3, 4)
		"wisps":
			summon("wisp", 4, 6, 100.0)


func on_phase(_p: int) -> void:
	ring(18, 220.0, 10.0, VOID, 0.0, 12.0)
	summon("shade", 2, 4)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 140.0 else Vector2.ZERO
