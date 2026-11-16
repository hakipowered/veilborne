extends "res://entities/enemies/brain.gd"
## Sporeling (ch2 area denial): keeps its distance and lobs spore pods. The landing spot is marked the moment it
## starts the throw (filling ring), so the pod is dodgeable; a heroine who closes in gets a spore puff ring.

const COL := Color(0.75, 1.0, 0.35)
const FLIGHT := 0.45


func attacks() -> Dictionary:
	return {
		"lob": {"w": 0.75, "a": 0.25, "r": 0.75, "cd": 2.2, "range": [130.0, 640.0], "weight": 2.0,
			"aw": "throw_w", "aa": "throw", "tele": "aux", "tele_r": 72.0, "col": COL, "lob": true},
		"puff": {"w": 0.6, "a": 0.3, "r": 0.7, "cd": 3.2, "range": [0.0, 135.0], "weight": 3.0,
			"aw": "puff_w", "aa": "puff", "tele": "ring", "tele_r": 112.0, "col": COL},
	}


func on_windup(id: String) -> void:
	if id == "lob":
		e.aux = lead(e.windup_len() + FLIGHT)
		e.arena.telegraph_slam(e.aux, 72.0, e.windup_len() + FLIGHT, 12.0, COL)


func on_strike(id: String) -> void:
	if id == "puff":
		e.arena.telegraph_slam(e.position, 112.0, 0.05, 10.0, COL)
		ring(6, 150.0, 6.0, COL, randf() * TAU, 9.0)


func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	if dist < 200.0:
		return -dir * e.speed() * 0.9
	if dist > 420.0:
		return dir * e.speed()
	return dir.orthogonal() * e.speed() * 0.35


## the pod arcing from the hands to the marked spot (every device, from replicated aux + state)
func draw_extra() -> void:
	if e.atk < 0 or not spec(e.atk).get("lob", false):
		return
	var t := -1.0
	if e.state == S_ATTACK:
		t = e.state_t
	elif e.state == S_RECOVER:
		t = float(spec(e.atk).get("a", 0.25)) + e.state_t
	if t < 0.0 or t > FLIGHT:
		return
	var u := t / FLIGHT
	var to: Vector2 = e.aux - e.position
	var p := Vector2(0.0, -70.0).lerp(to, u) + Vector2(0.0, -170.0 * sin(PI * u))
	e.draw_circle(p, 11.0, Color(COL, 0.35))
	e.draw_circle(p, 7.0, COL)
	e.draw_circle(p + Vector2(-2, -2), 3.0, Color(1, 1, 0.85))
