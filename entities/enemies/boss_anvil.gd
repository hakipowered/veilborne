extends "res://entities/enemies/brain.gd"
## Hollis the Forgemaster (chapter 3 general). Giant smith with a forge hammer.
## Phase 1: two-hit hammer combo, bull charge (stuns itself on walls), quake slam with three ripple waves,
##          stomp ring, calls cinder imps.
## Stage 2 (66% HP, shielded roar + imps): faster; meteor embers rain on the heroines, spinning advance, charge
##          chains into a second charge.
## Stage 3 (33% HP, shielded roar + quake ring): falling anvils hunt each heroine (three drops along her path,
##          each with a shock ring), forge fissures split the floor outward; both leave him open for 2+ s.

const COL := Color(1.0, 0.45, 0.12)
const COL2 := Color(1.0, 0.8, 0.25)


func attacks() -> Dictionary:
	return {
		"swing": {"w": 0.6, "a": 0.25, "r": 0.5, "cd": 1.7, "range": [0.0, 200.0], "weight": 2.0,
			"aw": "swing_w", "aa": "swing", "track": 0.6, "tele": "cone", "tele_len": 180.0, "tele_arc": 150.0, "col": COL,
			"next": "swing2", "next_p": 0.7},
		"swing2": {"w": 0.35, "a": 0.25, "r": 0.9, "cd": 0.0, "range": [0.0, 0.0], "weight": 0.0,
			"aw": "slam_w", "aa": "slam", "track": 1.0, "tele": "cone", "tele_len": 170.0, "tele_arc": 90.0, "col": COL},
		"charge": {"w": 1.0, "a": 1.2, "r": 1.0, "cd": 5.0, "range": [220.0, 820.0], "weight": 1.5,
			"aw": "charge_w", "aa": "charge", "loop_a": true, "track": 0.55, "tele": "line", "tele_len": 600.0,
			"tele_w": 92.0, "col": COL, "speed": 560.0, "hit_r": 64.0, "dmg": 20.0, "charge": true, "stun": 1.8,
			"next": "charge2", "next_p": 1.0},
		"charge2": {"w": 0.6, "a": 1.1, "r": 1.2, "cd": 0.0, "range": [0.0, 0.0], "weight": 0.0, "phase": 1,
			"aw": "charge_w", "aa": "charge", "loop_a": true, "track": 0.6, "tele": "line", "tele_len": 600.0,
			"tele_w": 92.0, "col": COL2, "speed": 600.0, "hit_r": 64.0, "dmg": 20.0, "charge": true, "stun": 2.0},
		"quake": {"w": 1.0, "a": 0.3, "r": 1.0, "cd": 4.5, "range": [0.0, 280.0], "weight": 1.5,
			"aw": "slam_w", "aa": "slam", "col": COL},
		"stomp": {"w": 0.6, "a": 0.2, "r": 0.6, "cd": 3.0, "range": [0.0, 150.0], "weight": 1.5,
			"aw": "stomp_w", "aa": "stomp", "tele": "ring", "tele_r": 160.0, "col": COL},
		"summon": {"w": 1.0, "a": 0.3, "r": 0.7, "cd": 12.0, "range": [0.0, 900.0], "weight": 1.0, "max_phase": 1,
			"aw": "roar", "aa": "stomp", "tele": "ring", "tele_r": 110.0, "col": COL},
		"meteor": {"w": 1.0, "a": 0.3, "r": 0.8, "cd": 6.0, "range": [0.0, 900.0], "weight": 1.5, "phase": 1,
			"aw": "roar", "aa": "stomp", "col": COL2},
		"spin": {"w": 0.6, "a": 1.6, "r": 1.1, "cd": 6.0, "range": [0.0, 280.0], "weight": 1.2, "phase": 1,
			"aw": "spin_w", "aa": "spin", "loop_a": true, "tele": "ring", "tele_r": 140.0, "col": COL2,
			"hit_r": 92.0, "dmg": 14.0},
		"anvils": {"w": 1.1, "a": 0.3, "r": 2.4, "cd": 8.0, "range": [0.0, 900.0], "weight": 1.6, "phase": 2, "rep": 1,
			"aw": "roar", "aa": "slam", "col": COL2},
		"fissures": {"w": 1.0, "a": 0.3, "r": 2.0, "cd": 7.0, "range": [0.0, 900.0], "weight": 1.4, "phase": 2, "rep": 1,
			"aw": "slam_w", "aa": "slam", "tele": "ring", "tele_r": 120.0, "col": COL},
	}


func base_cd() -> float:
	return 0.6 + randf() * 0.5


func on_windup(id: String) -> void:
	match id:
		"anvils":
			var w: float = e.windup_len()
			for h in live_heroes():
				var v = h.get("vel")
				var hv: Vector2 = v if v is Vector2 else Vector2.ZERO
				for k in 3:
					var p: Vector2 = e.arena.resolve_collision(h.position + hv * (0.35 + 0.45 * k) * 0.6, 10.0)
					var t: float = w + 0.25 + 0.5 * k
					e.arena.telegraph_slam(p, 110.0, t, 22.0, COL2)
					slam_ring(p, 190.0, 8, 34.0, t + 0.3, 10.0, COL, k * 0.4)
		"quake":
			e.arena.telegraph_slam(ahead(100.0), 125.0, e.windup_len(), 24.0, COL)
		"meteor":
			var hs := live_heroes()
			for i in 8:
				if hs.is_empty():
					break
				var h = hs[i % hs.size()]
				var p: Vector2 = h.position + Vector2.RIGHT.rotated(randf() * TAU) * randf_range(0.0, 150.0) * Vector2(1.0, 0.62)
				e.arena.telegraph_slam(e.arena.resolve_collision(p, 10.0), 68.0, e.windup_len() + 0.3 + i * 0.22, 16.0, COL2)


func on_strike(id: String) -> void:
	match id:
		"swing":
			slam_arc(110.0, 150.0, 4, 54.0, 0.03, 18.0, COL)
		"swing2":
			e.arena.telegraph_slam(ahead(110.0), 90.0, 0.03, 20.0, COL)
			e.arena.shake(6.0)
		"quake":
			e.arena.shake(12.0)
			var c := ahead(100.0)
			slam_ring(c, 190.0, 10, 36.0, 0.28, 12.0, COL)
			slam_ring(c, 290.0, 14, 36.0, 0.56, 12.0, COL, PI / 14.0)
			slam_ring(c, 390.0, 18, 36.0, 0.84, 12.0, COL)
		"stomp":
			e.arena.telegraph_slam(e.position, 160.0, 0.03, 16.0, COL)
			e.arena.shake(8.0)
		"summon":
			summon("cinderimp", 2, 3)
		"anvils":
			e.arena.shake(8.0)
		"fissures":
			e.arena.shake(12.0)
			var a0 := randf() * TAU
			for k in 6:
				var d := Vector2.RIGHT.rotated(a0 + TAU * k / 6.0) * Vector2(1.0, 0.62)
				slam_line(e.position, d, 7, 80.0, 40.0, 0.2, 0.08, 15.0, COL)


func strike_move(id: String, _t: float) -> Vector2:
	if id == "spin":
		var tg = e.target_node()
		if tg != null:
			return (tg.position - e.position).normalized() * 150.0
	return Vector2.ZERO


func on_phase(p: int) -> void:
	slam_ring(e.position, 200.0, 12, 40.0, 0.5, 14.0, COL2)
	if p >= 2:
		slam_ring(e.position, 330.0, 18, 40.0, 1.1, 14.0, COL, PI / 18.0)
		summon("forgegolem", 1, 2)
	summon("cinderimp", 2, 4)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 150.0 else Vector2.ZERO
