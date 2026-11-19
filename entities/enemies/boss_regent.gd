extends "res://entities/enemies/brain.gd"
## The Hollow Regent (chapter 4 final boss, 4 stages: thresholds 75% / 50% / 25%; each break is a shielded roar
## that brings adds, and the speed-up is spread over the stages).
## Phase 1: void burst fan, throne-charge (wall stun), slam + scattered aftershocks.
## Phase 2: adds summons (pikes / casters), runes under every heroine, rotating spiral of bolts.
## Phase 3: adds wisp swarms, ripple ring waves; the charge chains into a second charge.
## Phase 4 (last quarter): the eclipse (two opposed arms of bolts turn round him for 3 s, the reference's long
##          beam cast in our own form, with a long recovery to punish), echoes of his three generals' creatures.

const COL := Color(0.75, 0.35, 1.0)
const COL2 := Color(1.0, 0.35, 0.55)

var _spiral_t := 0.0
var _spiral_a := 0.0


func attacks() -> Dictionary:
	return {
		"burst": {"w": 0.8, "a": 0.25, "r": 0.7, "cd": 2.5, "range": [0.0, 900.0], "weight": 2.0,
			"aw": "windup", "aa": "attack", "track": 0.8, "tele": "line", "tele_len": 300.0, "tele_w": 30.0, "col": COL, "sfx": "regent_burst"},
		"charge": {"w": 1.0, "a": 1.1, "r": 1.0, "cd": 5.0, "range": [200.0, 820.0], "weight": 1.5,
			"aw": "windup", "aa": "charge", "loop_a": true, "track": 0.55, "tele": "line", "tele_len": 580.0, "tele_w": 92.0,
			"col": COL, "speed": 600.0, "hit_r": 62.0, "dmg": 20.0, "charge": true, "stun": 1.6, "next": "charge2", "next_p": 1.0},
		"charge2": {"w": 0.55, "a": 1.0, "r": 1.2, "cd": 0.0, "range": [0.0, 0.0], "weight": 0.0, "phase": 2,
			"aw": "windup", "aa": "charge", "loop_a": true, "track": 0.6, "tele": "line", "tele_len": 580.0, "tele_w": 92.0,
			"col": COL2, "speed": 650.0, "hit_r": 62.0, "dmg": 20.0, "charge": true, "stun": 1.8},
		"slam": {"w": 1.0, "a": 0.3, "r": 0.9, "cd": 4.0, "range": [0.0, 300.0], "weight": 1.5,
			"aw": "slam_w", "aa": "slam", "col": COL},
		"summon": {"w": 1.0, "a": 0.4, "r": 0.8, "cd": 12.0, "range": [0.0, 900.0], "weight": 1.0, "phase": 1,
			"aw": "cast", "aa": "cast", "tele": "ring", "tele_r": 120.0, "col": COL},
		"runes": {"w": 1.0, "a": 0.2, "r": 0.7, "cd": 5.0, "range": [0.0, 900.0], "weight": 1.3, "phase": 1,
			"aw": "windup", "aa": "attack", "col": COL},
		"spiral": {"w": 0.8, "a": 1.8, "r": 0.8, "cd": 7.0, "range": [0.0, 900.0], "weight": 1.2, "phase": 1,
			"aw": "windup", "aa": "cast", "loop_a": true, "tele": "ring", "tele_r": 130.0, "col": COL},
		"wisps": {"w": 0.8, "a": 0.3, "r": 0.7, "cd": 6.0, "range": [0.0, 900.0], "weight": 1.3, "phase": 2,
			"aw": "windup", "aa": "cast", "tele": "ring", "tele_r": 90.0, "col": COL2},
		"waves": {"w": 0.9, "a": 0.3, "r": 0.9, "cd": 6.0, "range": [0.0, 900.0], "weight": 1.3, "phase": 2,
			"aw": "slam_w", "aa": "slam", "tele": "ring", "tele_r": 150.0, "col": COL2},
		"eclipse": {"w": 1.4, "a": 3.0, "r": 1.6, "cd": 11.0, "range": [0.0, 900.0], "weight": 1.8, "phase": 3, "rep": 1,
			"aw": "windup", "aa": "cast", "loop_a": true, "tele": "ring", "tele_r": 170.0, "col": COL2},
		"echoes": {"w": 1.0, "a": 0.4, "r": 1.0, "cd": 14.0, "range": [0.0, 900.0], "weight": 1.0, "phase": 3,
			"aw": "cast", "aa": "cast", "tele": "ring", "tele_r": 120.0, "col": COL2},
	}


func base_cd() -> float:
	return 0.5 + randf() * 0.45


func on_windup(id: String) -> void:
	match id:
		"slam":
			e.arena.telegraph_slam(ahead(95.0), 130.0, e.windup_len(), 24.0, COL)
		"runes":
			for h in live_heroes():
				e.arena.telegraph_slam(e.arena.resolve_collision(h.position, 10.0), 80.0, e.windup_len(), 16.0, COL)
				e.arena.telegraph_slam(e.arena.resolve_collision(lead(1.2), 10.0), 70.0, e.windup_len() + 0.5, 14.0, COL)
		"spiral", "eclipse":
			_spiral_t = 0.0
			_spiral_a = e.aim.angle() + PI * 0.5


func on_strike(id: String) -> void:
	match id:
		"burst":
			fan(9 + 2 * e.phase, 80.0, 300.0, 12.0, COL, 13.0)
		"slam":
			e.arena.shake(12.0)
			for i in 6 + 2 * e.phase:
				var p: Vector2 = e.position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(140.0, 380.0) * Vector2(1.0, 0.62)
				e.arena.telegraph_slam(e.arena.resolve_collision(p, 10.0), 60.0, 0.3 + i * 0.09, 12.0, COL)
		"summon":
			summon("hollowpike", 1, 2)
			summon("voidcaster", 1, 2)
		"wisps":
			summon("wisp", 5, 7, 110.0)
		"echoes":
			summon("shade", 2, 3)
			summon("sporeling", 1, 2)
			summon("cinderimp", 1, 2)
		"waves":
			ring(18, 230.0, 11.0, COL2, randf() * TAU, 13.0)
			slam_ring(e.position, 180.0, 10, 40.0, 0.3, 13.0, COL2)
			slam_ring(e.position, 280.0, 14, 40.0, 0.6, 13.0, COL2, PI / 14.0)
			slam_ring(e.position, 380.0, 18, 40.0, 0.9, 13.0, COL2)


## the spiral is emitted from the strike's per-frame movement hook (host only)
func strike_move(id: String, _t: float) -> Vector2:
	if id == "spiral":
		_spiral_t += e.get_physics_process_delta_time()
		if _spiral_t >= 0.13:
			_spiral_t -= 0.13
			_spiral_a += 0.33
			ring(3 + mini(e.phase, 2), 230.0, 10.0, COL, _spiral_a, 12.0)
	elif id == "eclipse":
		var dt := e.get_physics_process_delta_time()
		_spiral_t += dt
		_spiral_a += dt * 0.95
		if _spiral_t >= 0.09:
			_spiral_t -= 0.09
			for arm in 2:
				var d := Vector2.RIGHT.rotated(_spiral_a + PI * arm)
				e.arena.spawn_projectile(e.position + Vector2(0.0, -6.0) + d * (e.radius + 6.0), d * 420.0, 12.0, COL2 if arm == 0 else COL, 13.0)
	return Vector2.ZERO


func on_phase(p: int) -> void:
	ring(20 + 4 * p, 230.0, 11.0, COL2 if p >= 2 else COL, 0.0, 13.0)
	if p >= 3:
		slam_ring(e.position, 220.0, 12, 42.0, 1.0, 14.0, COL2)
		slam_ring(e.position, 360.0, 18, 42.0, 1.5, 14.0, COL, PI / 18.0)
		summon("hollowchampion", 1, 1)
		summon("wisp", 3, 6, 110.0)
	elif p >= 2:
		summon("wisp", 3, 6, 110.0)
	else:
		summon("voidcaster", 1, 2)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 170.0 else Vector2.ZERO
