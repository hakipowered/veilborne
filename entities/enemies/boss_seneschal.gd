extends "res://entities/enemies/brain.gd"
## Osric the Gravekeeper (chapter 1 general; kind id kept as gen_seneschal). The Regent's clerk with a grave-glaive.
## Phase 1: three-beat glaive combo, lunging judgment dash, void ring of bolts, grave marks under each heroine,
##          raises shades.
## Stage 2 (66% HP, shielded roar + shades): faster; judgment cross (lines of markers in a + then an x), wisps,
##          double void ring.
## Stage 3 (33% HP, shielded roar + wisps): the vigil (two clock hands of grave marks sweep round him),
##          the requiem (rotating volleys while he stands his ground), the judgment dash doubles back.
## Pacing follows the reference proportions: long recoveries after the big set pieces, no attack thrice in a row.

const COL := Color(0.85, 0.78, 0.55)
const VOID := Color(0.7, 0.4, 1.0)


func attacks() -> Dictionary:
	return {
		"combo": {"w": 0.5, "a": 1.0, "r": 1.0, "cd": 2.6, "range": [0.0, 180.0], "weight": 2.0,
			"aw": "combo_w", "aa": "combo", "track": 0.6, "tele": "cone", "tele_len": 170.0, "tele_arc": 140.0, "col": COL,
			"speed": 100.0},
		"dash": {"w": 0.7, "a": 0.35, "r": 0.8, "cd": 4.0, "range": [150.0, 620.0], "weight": 1.5,
			"aw": "judgment_w", "aa": "dash", "loop_a": true, "track": 0.6, "tele": "line", "tele_len": 430.0, "tele_w": 60.0,
			"col": COL, "speed": 900.0, "hit_r": 46.0, "dmg": 18.0, "next": "dash2", "next_p": 1.0},
		"dash2": {"w": 0.45, "a": 0.35, "r": 1.2, "cd": 0.0, "range": [0.0, 0.0], "weight": 0.0, "phase": 2,
			"aw": "judgment_w", "aa": "dash", "loop_a": true, "track": 0.8, "tele": "line", "tele_len": 430.0, "tele_w": 60.0,
			"col": VOID, "speed": 900.0, "hit_r": 46.0, "dmg": 18.0},
		"voidring": {"w": 0.8, "a": 0.3, "r": 0.7, "cd": 4.0, "range": [0.0, 900.0], "weight": 1.5,
			"aw": "cast_w", "aa": "cast", "tele": "ring", "tele_r": 120.0, "col": VOID},
		"graves": {"w": 1.0, "a": 0.2, "r": 0.7, "cd": 5.0, "range": [0.0, 900.0], "weight": 1.2,
			"aw": "cast_w", "aa": "cast", "col": COL},
		"summon": {"w": 1.0, "a": 0.3, "r": 0.8, "cd": 12.0, "range": [0.0, 900.0], "weight": 1.0, "max_phase": 1,
			"aw": "cast_w", "aa": "roar", "tele": "ring", "tele_r": 100.0, "col": VOID},
		"cross": {"w": 1.0, "a": 0.3, "r": 1.0, "cd": 6.0, "range": [0.0, 900.0], "weight": 1.5, "phase": 1,
			"aw": "judgment_w", "aa": "judgment", "col": COL},
		"wisps": {"w": 0.8, "a": 0.3, "r": 0.7, "cd": 7.0, "range": [0.0, 900.0], "weight": 1.2, "phase": 1,
			"aw": "cast_w", "aa": "cast", "tele": "ring", "tele_r": 90.0, "col": VOID},
		"vigil": {"w": 0.9, "a": 2.3, "r": 1.6, "cd": 9.0, "range": [0.0, 900.0], "weight": 1.6, "phase": 2, "rep": 1,
			"aw": "judgment_w", "aa": "judgment", "loop_a": true, "tele": "ring", "tele_r": 110.0, "col": COL},
		"requiem": {"w": 0.8, "a": 2.0, "r": 1.4, "cd": 9.0, "range": [0.0, 900.0], "weight": 1.4, "phase": 2, "rep": 1,
			"aw": "cast_w", "aa": "cast", "loop_a": true, "tele": "ring", "tele_r": 130.0, "col": VOID},
	}


var _emit_t := 0.0
var _emit_a := 0.0


func base_cd() -> float:
	return 0.55 + randf() * 0.45


func on_windup(id: String) -> void:
	match id:
		"vigil":
			# two clock hands of grave marks sweep a full half turn round him
			var a0: float = e.aim.angle()
			var spin := 1.0 if randf() < 0.5 else -1.0
			for k in 9:
				for arm in 2:
					var d := Vector2.RIGHT.rotated(a0 + PI * arm + spin * k * 0.36) * Vector2(1.0, 0.62)
					slam_line(e.position, d, 4, 88.0, 38.0, e.windup_len() + k * 0.24, 0.0, 15.0, COL if arm == 0 else VOID)
		"requiem":
			_emit_t = 0.0
			_emit_a = randf() * TAU
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


## the requiem's volleys come from the strike's per-frame hook (host only)
func strike_move(id: String, _t: float) -> Vector2:
	if id == "requiem":
		_emit_t += e.get_physics_process_delta_time()
		if _emit_t >= 0.2:
			_emit_t -= 0.2
			_emit_a += 0.29
			ring(6, 210.0, 10.0, VOID, _emit_a, 12.0)
			ring(6, 150.0, 10.0, COL, -_emit_a * 1.4, 11.0)
	return Vector2.ZERO


func on_phase(p: int) -> void:
	ring(18, 220.0, 10.0, VOID, 0.0, 12.0)
	if p >= 2:
		ring(18, 160.0, 10.0, COL, PI / 18.0, 12.0)
		summon("wisp", 4, 6, 110.0)
	else:
		summon("shade", 3, 4)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 140.0 else Vector2.ZERO
