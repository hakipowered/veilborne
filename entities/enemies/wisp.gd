extends "res://entities/enemies/brain.gd"
## Wisp: homing seeker orb spawned by bosses. Slow to turn, pops on contact or after a few seconds. No sprite.

var _life := 0.0
var _pop := -1.0
var _vel := Vector2.ZERO


func contact() -> Array:
	return [16.0, 9.0]


func locomote(delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	_life += delta
	if _pop >= 0.0:
		_pop += delta
		if _pop > 0.12:
			e.expire()
		return _vel
	if _life > 6.0:
		e.expire()
		return Vector2.ZERO
	if has_t:
		var want: Vector2 = dir * e.speed() * minf(1.0, 0.4 + _life)
		_vel = _vel.lerp(want, clampf(delta * 2.2, 0.0, 1.0))
		if dist < 26.0:
			_pop = 0.0
	return _vel


func draw_extra() -> void:
	var t: float = Time.get_ticks_msec() * 0.001
	var c := Vector2(0, -34.0 + sin(t * 6.0 + e.eid) * 4.0)
	var col := Color(0.75, 0.45, 1.0) if e.phase == 0 else Color(0.9, 0.5, 1.0)
	e.draw_circle(c, 20.0, Color(col, 0.18))
	e.draw_circle(c, 12.0, Color(col, 0.5))
	e.draw_circle(c, 7.0, Color(1.0, 0.92, 1.0))
	e.draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
	e.draw_circle(Vector2.ZERO, 10.0, Color(col, 0.25))
	e.draw_set_transform(Vector2.ZERO)
