extends Node2D
## Enemy of the Veil: "shade" | "spitter" | "brute" | "regent" (boss).
## Host simulates AI via simulate(); clients interpolate packed snapshots via client_update().
## Visuals: painted Sprite2D + shared flash shader; shadow, telegraphs and hp bar drawn in _draw.

# ---------------------------------------------------------------- state codes (packed as ints)
const S_IDLE := 0
const S_MOVE := 1
const S_WINDUP := 2      # shade lunge / spitter spit / brute slam windup
const S_ATTACK := 3      # shade lunge / spitter release / brute smash follow-through
const S_RECOVER := 4
const S_HURT := 5        # light stagger (small foes only)
const S_W_BURST := 6     # regent
const S_BURST := 7
const S_W_CHARGE := 8
const S_CHARGE := 9
const S_W_SLAM := 10
const S_SUMMON := 11

const KINDS := {
	"shade": {"h": 110.0, "hp": 34.0, "r": 18.0, "speed": 150.0, "hover": 12.0, "mass": 1.0},
	"spitter": {"h": 80.0, "hp": 24.0, "r": 18.0, "speed": 120.0, "hover": 0.0, "mass": 1.0},
	"brute": {"h": 150.0, "hp": 95.0, "r": 30.0, "speed": 70.0, "hover": 0.0, "mass": 3.0},
	"regent": {"h": 260.0, "hp": 900.0, "r": 48.0, "speed": 90.0, "hover": 6.0, "mass": 8.0},
}

const TELEGRAPH_COLOR := Color(1.0, 0.18, 0.12)
const SPIT_COLOR := Color(1.0, 0.55, 0.15)
const BOSS_COLOR := Color(0.75, 0.35, 1.0)
const SLAM_COLOR := Color(1.0, 0.25, 0.15)
const P_FLASH := &"flash"

const SHADER_CODE := """
shader_type canvas_item;
uniform float flash : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.rgb = mix(c.rgb, vec3(1.0), flash);
	COLOR = c;
}
"""

static var _shader: Shader = null
static var _textures := {}

# ---------------------------------------------------------------- contract fields
var eid := 0
var kind := "shade"
var hp := 1.0
var max_hp := 1.0
var radius := 18.0
var hitbox_active := false
var hitbox_radius := 0.0
var contact_damage := 0.0
var burn_dps := 0.0

# ---------------------------------------------------------------- internals
var arena: Node = null
var state := S_IDLE
var state_t := 0.0
var facing_sign := 1.0
var aim := Vector2.RIGHT          # attack direction (replicated as angle)
var burning := false
var phase2 := false

var _dead := false
var _target: Node2D = null
var _retarget_t := 0.0
var _cd := 1.0                    # attack cooldown
var _knock := Vector2.ZERO
var _last_attacker := ""
var _burn_t := 0.0
var _boss_step := 0
var _burst2_done := false
var _speed := 100.0
var _mass := 1.0
var _hover := 0.0
var _height := 100.0
var _sep_frame := 0

# visuals
var _sprite: Sprite2D
var body: AnimSprite
var _last_vis_state := -1
var _mat: ShaderMaterial
var _base_scale := 1.0
var _anim_t := 0.0
var _flash := 0.0
var _flash_set := -1.0
var _hit_sq := 0.0
var _show_bar := false

# client interpolation
var _buffer: Array = []           # [[ticks_msec, packed]]
var _client_ready := false


func setup(p_eid: int, p_kind: String, p_arena: Node, hp_scale: float) -> void:
	eid = p_eid
	kind = p_kind if KINDS.has(p_kind) else "shade"
	arena = p_arena
	var d: Dictionary = KINDS[kind]
	max_hp = float(d["hp"]) * maxf(hp_scale, 0.05)
	hp = max_hp
	radius = d["r"]
	_speed = d["speed"]
	_mass = d["mass"]
	_hover = d["hover"]
	_height = d["h"]
	_cd = 0.8 + randf() * 1.2
	_anim_t = randf() * 10.0
	_sep_frame = eid % 3
	_sync_hitbox()
	_build_sprite(d)


func _build_sprite(d: Dictionary) -> void:
	body = AnimSprite.new()
	add_child(body)
	body.setup(kind, _height)


## Death: play the real death animation, then free (the arena has already forgotten this enemy).
func die_visual() -> void:
	_dead = true
	hitbox_active = false
	_show_bar = false
	queue_redraw()
	if body == null or not body.has_anim("death"):
		queue_free()
		return
	body.flash = 0.0
	body.tint = Color.WHITE
	body.play("death", true)
	body.anim_finished.connect(func(_a): queue_free())
	get_tree().create_timer(2.0).timeout.connect(func(): if is_instance_valid(self): queue_free())


# ---------------------------------------------------------------- host simulation

func simulate(delta: float) -> void:
	if _dead or arena == null:
		return
	state_t += delta
	_cd -= delta
	_tick_burn(delta)
	if _dead:
		return
	_acquire_target(delta)

	var move := Vector2.ZERO
	var has_t := _target != null
	var to_t := (_target.position - position) if has_t else Vector2.ZERO
	var dist := to_t.length()
	var dir := to_t / dist if dist > 0.001 else aim

	match kind:
		"shade":
			move = _ai_shade(delta, has_t, dir, dist)
		"spitter":
			move = _ai_spitter(delta, has_t, dir, dist)
		"brute":
			move = _ai_brute(delta, has_t, dir, dist)
		"regent":
			move = _ai_regent(delta, has_t, dir, dist)

	if state == S_HURT and state_t > 0.18:
		_set_state(S_MOVE)

	# Knockback decays; heavy foes barely budge.
	_knock = _knock.move_toward(Vector2.ZERO, 1400.0 * delta)
	var step := (move + _knock) * delta
	if _sep_frame == Engine.get_physics_frames() % 3:
		step += _separation() * delta * 3.0
	var want := position + step
	position = arena.resolve_collision(want, radius)
	if state == S_CHARGE and position.distance_squared_to(want) > 4.0:
		_set_state(S_RECOVER)   # slammed into a wall
		_cd = 0.9
	if has_t and (state <= S_WINDUP or _is_windup()) and absf(to_t.x) > 4.0:
		facing_sign = signf(to_t.x)
	_sync_hitbox()
	_update_visuals(delta)


func _acquire_target(delta: float) -> void:
	_retarget_t -= delta
	if _target != null and (not is_instance_valid(_target) or not _target.is_inside_tree() or _target.get("downed") == true):
		_target = null
	if _target == null or _retarget_t <= 0.0:
		_retarget_t = 0.5
		var h = arena.nearest_hero(position)
		_target = h as Node2D if h != null and is_instance_valid(h) else null


func _set_state(s: int) -> void:
	state = s
	state_t = 0.0


func _ai_shade(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	match state:
		S_IDLE, S_MOVE:
			if not has_t:
				_set_state(S_IDLE)
				return Vector2.ZERO
			state = S_MOVE
			if dist < 150.0 and _cd <= 0.0:
				aim = dir
				_set_state(S_WINDUP)
				return Vector2.ZERO
			return dir * _speed
		S_WINDUP:
			if has_t:
				aim = dir
			if state_t >= 0.4:
				_set_state(S_ATTACK)
			return -aim * 25.0   # draw back before the lunge
		S_ATTACK:
			if state_t >= 0.24:
				_set_state(S_RECOVER)
				_cd = 0.9 + randf() * 0.5
			return aim * 640.0
		S_RECOVER:
			if state_t >= 0.45:
				_set_state(S_MOVE)
	return Vector2.ZERO


func _ai_spitter(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	match state:
		S_IDLE, S_MOVE:
			if not has_t:
				_set_state(S_IDLE)
				return Vector2.ZERO
			state = S_MOVE
			if _cd <= 0.0 and dist < 620.0:
				aim = dir
				_set_state(S_WINDUP)
				return Vector2.ZERO
			if dist < 250.0:
				return -dir * _speed
			if dist > 350.0:
				return dir * _speed
			var side := 1.0 if (eid & 1) == 0 else -1.0
			return dir.orthogonal() * side * _speed * 0.4
		S_WINDUP:
			if has_t:
				aim = dir
			if state_t >= 0.5:
				arena.spawn_projectile(position + aim * (radius + 8.0), aim * 330.0, 8.0, SPIT_COLOR, 10.0)
				_set_state(S_ATTACK)
				_cd = 2.2 + randf() * 0.4
		S_ATTACK:
			if state_t >= 0.25:
				_set_state(S_MOVE)
	return Vector2.ZERO


func _ai_brute(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	match state:
		S_IDLE, S_MOVE:
			if not has_t:
				_set_state(S_IDLE)
				return Vector2.ZERO
			state = S_MOVE
			if dist < 160.0 and _cd <= 0.0:
				aim = dir
				_set_state(S_WINDUP)
				arena.telegraph_slam(position + aim * 60.0, 120.0, 0.8, 18.0, SLAM_COLOR)
				return Vector2.ZERO
			return dir * _speed
		S_WINDUP:
			if state_t >= 0.8:
				_set_state(S_ATTACK)
		S_ATTACK:
			if state_t >= 0.3:
				_set_state(S_RECOVER)
				_cd = 1.6 + randf() * 0.6
		S_RECOVER:
			if state_t >= 0.9:
				_set_state(S_MOVE)
	return Vector2.ZERO


func _ai_regent(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	var spd_mul := 1.35 if phase2 else 1.0
	if not phase2 and hp <= max_hp * 0.5 and state != S_CHARGE:
		phase2 = true
		_set_state(S_SUMMON)
		for i in range(3):
			var off := Vector2.RIGHT.rotated(TAU * i / 3.0 + randf()) * 110.0
			arena.spawn_enemy("shade", arena.resolve_collision(position + off, 18.0))
		return Vector2.ZERO
	match state:
		S_IDLE, S_MOVE:
			if not has_t:
				_set_state(S_IDLE)
				return Vector2.ZERO
			state = S_MOVE
			if _cd <= 0.0:
				aim = dir
				match _boss_step % 3:
					0:
						_set_state(S_W_BURST)
					1:
						_set_state(S_W_CHARGE)
					_:
						_set_state(S_W_SLAM)
				_boss_step += 1
				return Vector2.ZERO
			if dist > 220.0:
				return dir * _speed * spd_mul
			return dir.orthogonal() * _speed * 0.5 * spd_mul
		S_W_BURST:
			if state_t >= 0.7 / spd_mul:
				_radial_burst(0.0)
				_burst2_done = not phase2
				_set_state(S_BURST)
		S_BURST:
			if not _burst2_done and state_t >= 0.35:
				_burst2_done = true
				_radial_burst(PI / 16.0)
			if state_t >= 0.7:
				_end_boss_attack(spd_mul)
		S_W_CHARGE:
			if state_t < 0.55 and has_t:
				aim = dir   # track, then lock for the last beat
			if state_t >= 0.85 / spd_mul:
				_set_state(S_CHARGE)
		S_CHARGE:
			if state_t >= 0.55:
				_set_state(S_RECOVER)
				_cd = 0.6
			return aim * 900.0 * spd_mul
		S_W_SLAM:
			if state_t >= 0.5:
				if has_t:
					var c: Vector2 = _target.position
					arena.telegraph_slam(c, 110.0, 1.0, 16.0, BOSS_COLOR)
					for i in range(2):
						var o := Vector2.RIGHT.rotated(randf() * TAU) * (90.0 + randf() * 80.0)
						arena.telegraph_slam(c + o, 100.0, 1.25 + 0.3 * i, 16.0, BOSS_COLOR)
				_end_boss_attack(spd_mul)
		S_SUMMON:
			if state_t >= 1.0:
				_end_boss_attack(spd_mul)
		S_RECOVER:
			if state_t >= 0.7:
				_end_boss_attack(spd_mul)
	return Vector2.ZERO


func _end_boss_attack(spd_mul: float) -> void:
	_set_state(S_MOVE)
	_cd = (1.6 if not phase2 else 1.0) + randf() * 0.4 / spd_mul


func _radial_burst(offset: float) -> void:
	var base := position + Vector2(0.0, -10.0)
	for i in range(16):
		var d := Vector2.RIGHT.rotated(offset + TAU * i / 16.0)
		arena.spawn_projectile(base + d * radius, d * 250.0, 10.0, BOSS_COLOR, 12.0)


func _separation() -> Vector2:
	var push := Vector2.ZERO
	var list = arena.enemies()
	if list == null:
		return push
	for e in list:
		if e == self or not is_instance_valid(e):
			continue
		var d: Vector2 = position - e.position
		var min_d: float = radius + float(e.radius)
		var l2 := d.length_squared()
		if l2 < min_d * min_d and l2 > 0.01:
			var l := sqrt(l2)
			push += d / l * (min_d - l) * 8.0 / _mass
	return push


func _tick_burn(delta: float) -> void:
	if burn_dps <= 0.0:
		burning = false
		return
	if _burn_t <= 0.0:
		_burn_t = 3.0   # arena set burn_dps directly: start a 3s burn
	_burn_t -= delta
	burning = true
	_apply_damage(burn_dps * delta)
	if _burn_t <= 0.0:
		burn_dps = 0.0
		burning = false


func apply_burn(dps: float) -> void:
	burn_dps = maxf(burn_dps, dps)
	_burn_t = 3.0
	burning = true


func take_damage(amount: float, crit: bool, from_pos: Vector2, attacker_key: String) -> void:
	if _dead:
		return
	if attacker_key != "":
		_last_attacker = attacker_key
	var away := position - from_pos
	if away.length_squared() < 0.01:
		away = Vector2(-facing_sign, 0.0)
	_knock += away.normalized() * (420.0 if crit else 300.0) / _mass
	flash_hit()
	# Small foes are staggered out of windups; big ones shrug it off.
	if _mass <= 1.0 and state in [S_WINDUP, S_MOVE, S_IDLE]:
		_set_state(S_HURT)
		_cd = maxf(_cd, 0.35)
	_apply_damage(amount)


func _apply_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	_show_bar = true
	if hp <= 0.0:
		hp = 0.0
		_dead = true
		hitbox_active = false
		if arena != null:
			arena.on_enemy_killed(self, _last_attacker)


func is_dead() -> bool:
	return _dead


func flash_hit() -> void:
	_flash = 1.0
	_hit_sq = 1.0


func _sync_hitbox() -> void:
	match kind:
		"shade":
			hitbox_active = state == S_ATTACK
			hitbox_radius = radius + 14.0
			contact_damage = 10.0
		"regent":
			hitbox_active = state == S_CHARGE
			hitbox_radius = radius + 16.0
			contact_damage = 20.0
		_:
			hitbox_active = false
			hitbox_radius = radius
			contact_damage = 0.0
	if _dead:
		hitbox_active = false


# ---------------------------------------------------------------- networking

func pack() -> Array:
	return [position.x, position.y, hp, max_hp, state, state_t, facing_sign, hitbox_active, burning, aim.angle()]


func apply_packed(a: Array) -> void:
	if a.size() < 9:
		return
	_buffer.append([Time.get_ticks_msec(), a])
	while _buffer.size() > 12:
		_buffer.pop_front()
	if not _client_ready:
		_client_ready = true
		position = Vector2(a[0], a[1])
		hp = a[2]
		max_hp = a[3]


func client_update(delta: float) -> void:
	if not _buffer.is_empty() and arena != null:
		var render_t: int = Time.get_ticks_msec() - int(arena.INTERP_DELAY_MS)
		var a: Array = _buffer[0]
		var b: Array = _buffer[_buffer.size() - 1]
		for i in range(_buffer.size() - 1):
			if _buffer[i][0] <= render_t and _buffer[i + 1][0] >= render_t:
				a = _buffer[i]
				b = _buffer[i + 1]
				break
		var t := 1.0
		if b[0] != a[0]:
			t = clampf(float(render_t - a[0]) / float(b[0] - a[0]), 0.0, 1.0)
		var sa: Array = a[1]
		var sb: Array = b[1]
		position = Vector2(sa[0], sa[1]).lerp(Vector2(sb[0], sb[1]), t)
		var new_hp: float = sb[2]
		if new_hp < hp - 0.01:
			_show_bar = true
			if new_hp < hp - 1.0:
				_hit_sq = maxf(_hit_sq, 0.6)
		hp = new_hp
		max_hp = sb[3]
		var ns := int(sb[4])
		if ns != state:
			state = ns
			state_t = float(sb[5])
		else:
			state_t += delta
		facing_sign = float(sb[6])
		burning = bool(sb[8])
		if sb.size() > 9:
			aim = Vector2.RIGHT.rotated(float(sb[9]))
		phase2 = kind == "regent" and hp <= max_hp * 0.5
		_sync_hitbox()
		hitbox_active = bool(sb[7])
	else:
		state_t += delta
	_update_visuals(delta)


# ---------------------------------------------------------------- visuals

func _is_windup() -> bool:
	return state == S_WINDUP or state == S_W_BURST or state == S_W_CHARGE or state == S_W_SLAM or state == S_SUMMON


func _windup_len() -> float:
	var m := 1.35 if phase2 else 1.0
	match state:
		S_WINDUP:
			match kind:
				"shade":
					return 0.4
				"spitter":
					return 0.5
				_:
					return 0.8
		S_W_BURST:
			return 0.7 / m
		S_W_CHARGE:
			return 0.85 / m
		S_W_SLAM:
			return 0.5
		S_SUMMON:
			return 1.0
	return 1.0


func _update_visuals(delta: float) -> void:
	_anim_t += delta
	_flash = maxf(0.0, _flash - delta * 7.0)
	_hit_sq = maxf(0.0, _hit_sq - delta * 6.0)
	if body == null:
		return
	var bob := 0.0
	if _hover > 0.0:
		bob = _hover + sin(_anim_t * 3.0) * _hover * 0.5
	body.position = Vector2(0.0, -bob)
	var attacking := _is_windup() or state == S_ATTACK or state == S_BURST or state == S_CHARGE
	body.set_facing(aim if attacking else Vector2(facing_sign, 0.35))
	if state == S_HURT and _last_vis_state != S_HURT:
		body.play("hurt", true)
	else:
		body.play_enemy_state(state, _windup_len() if _is_windup() else 0.0)
	_last_vis_state = state
	body.flash = _flash
	if burning:
		var p := 0.5 + 0.5 * sin(_anim_t * 12.0)
		body.tint = Color(1.0, 0.78 - 0.18 * p, 0.55 - 0.3 * p)
	elif phase2 and kind == "regent":
		var p2 := 0.5 + 0.5 * sin(_anim_t * 4.0)
		body.tint = Color(1.0, 0.75 + 0.1 * p2, 0.95)
	else:
		body.tint = Color.WHITE
	queue_redraw()


func _draw() -> void:
	# Soft ground shadow (shrinks while hovering high).
	var hov := 0.0
	if _hover > 0.0:
		hov = sin(_anim_t * 3.0) * 0.08
	var sr := radius * 1.35 * (1.0 - hov)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
	draw_circle(Vector2.ZERO, sr * 1.25, Color(0, 0, 0, 0.14))
	draw_circle(Vector2.ZERO, sr, Color(0, 0, 0, 0.3))

	# Ground telegraphs.
	if _is_windup():
		var k := clampf(state_t / _windup_len(), 0.0, 1.0)
		var col := BOSS_COLOR if state == S_SUMMON else TELEGRAPH_COLOR
		match state:
			S_WINDUP:
				if kind == "shade":
					_ring(aim * 70.0, radius + 26.0, k, col)
				elif kind == "spitter":
					_ring(Vector2.ZERO, radius + 18.0, k, col)
				# brute: arena draws the replicated slam ring
			S_W_BURST:
				_ring(Vector2.ZERO, 120.0, k, col)
			S_W_SLAM, S_SUMMON:
				_ring(Vector2.ZERO, radius + 30.0, k, col)
			S_W_CHARGE:
				draw_set_transform(Vector2.ZERO)
				var end := aim * 540.0
				draw_line(Vector2.ZERO, end, Color(col, 0.18), radius * 1.6)
				draw_line(Vector2.ZERO, end * k, Color(col, 0.45), radius * 1.6)
				draw_line(Vector2.ZERO, end, Color(col, 0.8), 2.0)
	draw_set_transform(Vector2.ZERO)

	# Small hp bar for damaged non-boss enemies.
	if _show_bar and kind != "regent" and hp > 0.0 and hp < max_hp:
		var w := 70.0 if kind == "brute" else 46.0
		var y := -_height - 14.0 - _hover
		var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(-w * 0.5 - 2.0, y - 2.0, w + 4.0, 9.0), Color(0.05, 0.02, 0.04, 0.85))
		draw_rect(Rect2(-w * 0.5, y, w * frac, 5.0), Color(0.9, 0.18, 0.2) if not burning else Color(1.0, 0.55, 0.15))


## Ellipse ring at local ground position c (pre-squash coords), filling with k in [0,1].
func _ring(c: Vector2, r: float, k: float, col: Color) -> void:
	draw_set_transform(Vector2(c.x, c.y), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, r * k, Color(col, 0.22 + 0.2 * k))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(col, 0.85), 3.0)
