extends Node2D
## Enemy of the Veil. Host simulates AI via simulate(); clients interpolate packed snapshots via client_update().
## Legacy kinds (shade, spitter, brute) keep their hand-written AI below. Every other kind is driven by a
## behaviour script in res://entities/enemies/<brain>.gd (EnemyBrain: attack table + hooks). Bosses add phases
## (roar transition, speed-up, new attacks) and threat-based aggro for co-op.
## Visuals: AnimSprite frames (art/anim/<kind>), ground shadow, telegraphs, target marker and hp bar drawn in _draw.

# ---------------------------------------------------------------- state codes (packed as ints)
const S_IDLE := 0
const S_MOVE := 1
const S_WINDUP := 2      # attack windup (telegraph)
const S_ATTACK := 3      # strike / active frames
const S_RECOVER := 4     # punish window
const S_HURT := 5        # light stagger (small foes only)
const S_W_BURST := 6     # (legacy codes, kept for old snapshots)
const S_BURST := 7
const S_W_CHARGE := 8
const S_CHARGE := 9
const S_W_SLAM := 10
const S_SUMMON := 11
const S_ROAR := 12       # boss phase change / target switch beat
const S_STUN := 16       # dazed (charged into a wall): free hits

## Replicated kind index (arena.gd KINDS covers the first four; pack() carries the rest so clients self-correct).
const KIND_IDS := ["shade", "spitter", "brute", "regent",
	"bogwraith", "sporeling", "thornknight",
	"forgegolem", "cinderimp", "hammerwarden",
	"hollowpike", "voidcaster", "hollowchampion",
	"gen_bloom", "gen_anvil", "gen_seneschal", "wisp"]

## h: on-screen standing height px, r: body radius, mass: knockback resistance (>1 = no stagger)
## brain: behaviour script, boss/elite flags, phases: hp fractions that start the next phase, aggro: threat targeting
const KINDS := {
	"shade": {"h": 110.0, "hp": 34.0, "r": 18.0, "speed": 150.0, "hover": 12.0, "mass": 1.0},
	"spitter": {"h": 80.0, "hp": 24.0, "r": 18.0, "speed": 120.0, "hover": 0.0, "mass": 1.0},
	"brute": {"h": 150.0, "hp": 95.0, "r": 30.0, "speed": 70.0, "hover": 0.0, "mass": 3.0},
	"regent": {"h": 260.0, "hp": 1500.0, "r": 48.0, "speed": 95.0, "hover": 6.0, "mass": 8.0, "brain": "boss_regent",
		"boss": true, "aggro": true, "phases": [0.66, 0.33]},
	# Chapter 2: Drowned Garden
	"bogwraith": {"h": 150.0, "hp": 46.0, "r": 20.0, "speed": 165.0, "hover": 8.0, "mass": 1.0, "brain": "bogwraith"},
	"sporeling": {"h": 118.0, "hp": 40.0, "r": 22.0, "speed": 85.0, "hover": 0.0, "mass": 1.2, "brain": "sporeling"},
	"thornknight": {"h": 186.0, "hp": 175.0, "r": 30.0, "speed": 78.0, "hover": 0.0, "mass": 4.0, "brain": "thornknight", "elite": true},
	# Chapter 3: Ember Forge
	"forgegolem": {"h": 200.0, "hp": 140.0, "r": 34.0, "speed": 70.0, "hover": 0.0, "mass": 5.0, "brain": "forgegolem"},
	"cinderimp": {"h": 104.0, "hp": 36.0, "r": 18.0, "speed": 175.0, "hover": 0.0, "mass": 0.8, "brain": "cinderimp"},
	"hammerwarden": {"h": 206.0, "hp": 215.0, "r": 32.0, "speed": 80.0, "hover": 0.0, "mass": 5.0, "brain": "hammerwarden", "elite": true},
	# Chapter 4: Hollow Throne
	"hollowpike": {"h": 182.0, "hp": 85.0, "r": 24.0, "speed": 95.0, "hover": 0.0, "mass": 2.0, "brain": "hollowpike"},
	"voidcaster": {"h": 166.0, "hp": 60.0, "r": 20.0, "speed": 92.0, "hover": 0.0, "mass": 1.0, "brain": "voidcaster"},
	"hollowchampion": {"h": 200.0, "hp": 260.0, "r": 30.0, "speed": 112.0, "hover": 0.0, "mass": 5.0, "brain": "hollowchampion", "elite": true},
	# The Hollow Regent's generals (chapter bosses)
	"gen_bloom": {"h": 270.0, "hp": 1100.0, "r": 44.0, "speed": 108.0, "hover": 0.0, "mass": 9.0, "brain": "boss_bloom",
		"boss": true, "aggro": true, "phases": [0.5]},
	"gen_anvil": {"h": 290.0, "hp": 1300.0, "r": 50.0, "speed": 92.0, "hover": 0.0, "mass": 10.0, "brain": "boss_anvil",
		"boss": true, "aggro": true, "phases": [0.5]},
	"gen_seneschal": {"h": 280.0, "hp": 1400.0, "r": 42.0, "speed": 118.0, "hover": 0.0, "mass": 9.0, "brain": "boss_seneschal",
		"boss": true, "aggro": true, "phases": [0.5]},
	# homing seeker orb spawned by bosses (VFX body, no sprite)
	"wisp": {"h": 40.0, "hp": 6.0, "r": 12.0, "speed": 200.0, "hover": 34.0, "mass": 0.6, "brain": "wisp", "sprite": false},
}

const TELEGRAPH_COLOR := Color(1.0, 0.18, 0.12)
const SPIT_COLOR := Color(1.0, 0.55, 0.15)
const BOSS_COLOR := Color(0.75, 0.35, 1.0)
const SLAM_COLOR := Color(1.0, 0.25, 0.15)
const TARGET_COLOR := Color(1.0, 0.32, 0.22)
const BRAIN_DIR := "res://entities/enemies/"

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

# ---------------------------------------------------------------- shared (replicated) state
var arena: Node = null
var state := S_IDLE
var state_t := 0.0
var facing_sign := 1.0
var aim := Vector2.RIGHT          # attack direction (replicated as angle)
var burning := false
var phase := 0                    # boss phase (0-based)
var phase2 := false               # phase >= 1 (legacy name)
var atk := -1                     # current attack index into brain.ids; -2 short roar (target switch), -3 phase roar
var aux := Vector2.ZERO           # world point an attack aims at (leap landing, lobbed pod)
var tgt_pos := Vector2.INF        # aggro target position (for the target marker)
var guarding := false             # shield up (frontal hits mostly blocked)
var is_boss := false
var is_elite := false
var brain = null                  # EnemyBrain or null (legacy kinds)

var _dead := false
var _target: Node2D = null
var _retarget_t := 0.0
var _cd := 1.0                    # global attack cooldown
var _knock := Vector2.ZERO
var _last_attacker := ""
var _burn_t := 0.0
var _speed := 100.0
var _mass := 1.0
var _hover := 0.0
var _height := 100.0
var _sep_frame := 0
var _phases: Array = []
var _pending_phase := 0
var _roar_pending := false

# aggro (host)
var _aggro := false
var _threat := {}                 # hero key -> recent damage (decays)
var _since_switch := 99.0
var _switch_every := 5.0
var _big_hit_key := ""

# visuals
var body: AnimSprite
var _last_vis_state := -1
var _last_vis_atk := -99
var _anim_t := 0.0
var _flash := 0.0
var _hit_sq := 0.0
var _show_bar := false
var _tgt_flash := 0.0
var _base_tint := Color.WHITE
var _tgt_node: Node2D = null
var _last_sfx_state := -1
var _block_t := 0.0

# client interpolation
var _buffer: Array = []           # [[ticks_msec, packed]]
var _client_ready := false


func setup(p_eid: int, p_kind: String, p_arena: Node, hp_scale: float) -> void:
	eid = p_eid
	arena = p_arena
	_apply_kind(p_kind, hp_scale)
	_cd = 0.8 + randf() * 1.2
	_anim_t = randf() * 10.0
	_sep_frame = eid % 3


func _apply_kind(p_kind: String, hp_scale: float) -> void:
	kind = p_kind if KINDS.has(p_kind) else "shade"
	var d: Dictionary = KINDS[kind]
	max_hp = float(d["hp"]) * maxf(hp_scale, 0.05)
	hp = max_hp
	radius = d["r"]
	_speed = d["speed"]
	_mass = d["mass"]
	_hover = d["hover"]
	_height = d["h"]
	is_boss = d.get("boss", false)
	is_elite = d.get("elite", false)
	_aggro = d.get("aggro", false)
	_phases = d.get("phases", [])
	brain = null
	if d.has("brain"):
		var scr: GDScript = load(BRAIN_DIR + String(d["brain"]) + ".gd")
		if scr:
			brain = scr.new()
			brain.e = self
	_sync_hitbox()
	if body != null:
		body.queue_free()
		body = null
	# "art": reuse another kind's atlas (recoloured with "tint") until a kind gets its own rig
	_base_tint = d.get("tint", Color.WHITE)
	if d.get("sprite", true):
		body = AnimSprite.new()
		add_child(body)
		var art: String = kind if ResourceLoader.exists("res://art/anim/%s/data.gd" % kind) else String(d.get("art", "shade"))
		body.setup(art, _height)
		body.tint = _base_tint
	_last_vis_state = -1


## Display name for HUD/boss bars (rename in data/enemies.gd).
func display_name() -> String:
	var names: Dictionary = load("res://data/enemies.gd").NAMES
	return String(names.get(kind, kind.capitalize()))


func speed() -> float:
	return _speed * spd_mul()


## Phase speed-up multiplier (bosses get faster each phase).
func spd_mul() -> float:
	return 1.0 + 0.28 * phase


func target_node() -> Node2D:
	return _target if _target != null and is_instance_valid(_target) else null


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
	body.tint = _base_tint
	body.position = Vector2.ZERO
	body.set_speed_scale(1.0)
	body.play("death", true)
	body.anim_finished.connect(func(_a): queue_free())
	get_tree().create_timer(2.5).timeout.connect(func(): if is_instance_valid(self): queue_free())


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

	if brain != null:
		move = _brain_think(delta, has_t, dir, dist)
	else:
		match kind:
			"shade":
				move = _ai_shade(delta, has_t, dir, dist)
			"spitter":
				move = _ai_spitter(delta, has_t, dir, dist)
			"brute":
				move = _ai_brute(delta, has_t, dir, dist)

	if state == S_HURT and state_t > 0.18:
		_set_state(S_MOVE)

	# Knockback decays; heavy foes barely budge.
	_knock = _knock.move_toward(Vector2.ZERO, 1400.0 * delta)
	var step := (move + _knock) * delta
	if _sep_frame == Engine.get_physics_frames() % 3:
		step += _separation() * delta * 3.0
	var want := position + step
	position = arena.resolve_collision(want, radius)
	if brain != null and state == S_ATTACK and position.distance_squared_to(want) > 4.0:
		var sp: Dictionary = brain.spec(atk)
		if sp.get("charge", false):
			# slammed into a wall: dazed, free hits
			_set_state(S_STUN)
			arena.shake(8.0)
			arena.spark(position + aim * radius + Vector2(0, -40), Color(1, 0.8, 0.5), 14)
			arena.sfx("slam_impact", position)
	if has_t and (state <= S_MOVE or (state == S_WINDUP and brain == null)) and absf(to_t.x) > 4.0:
		facing_sign = signf(to_t.x)
	elif state >= S_WINDUP and state <= S_ATTACK and absf(aim.x) > 0.05:
		facing_sign = signf(aim.x)
	if _aggro and _target != null:
		tgt_pos = _target.position
	_sync_hitbox()
	_update_visuals(delta)


func _acquire_target(delta: float) -> void:
	if _target != null and (not is_instance_valid(_target) or not _target.is_inside_tree() or _target.get("downed") == true):
		_target = null
	if _aggro:
		_aggro_tick(delta)
		return
	_retarget_t -= delta
	if _target == null or _retarget_t <= 0.0:
		_retarget_t = 0.5
		var h = arena.nearest_hero(position)
		_target = h as Node2D if h != null and is_instance_valid(h) else null


# ---------------------------------------------------------------- aggro (bosses, host)
## Threat = recent damage dealt (decays over ~4 s) + closeness + a big bonus for reviving a downed partner.
## The boss re-evaluates every 0.4 s but only switches every 4-6.5 s, or at once after a big hit from someone else.
## A switch plays a short turn-and-roar beat and a marker over the new target (both replicated).

func _aggro_tick(delta: float) -> void:
	_since_switch += delta
	var decay := exp(-delta / 4.0)
	for k in _threat:
		_threat[k] *= decay
	_retarget_t -= delta
	if _target != null and _retarget_t > 0.0 and _big_hit_key == "":
		return
	_retarget_t = 0.4
	var best: Node2D = null
	var bs := -INF
	var all: Array = arena.heroes()
	for h in all:
		if not is_instance_valid(h) or h.downed:
			continue
		var s := threat_score(h, all)
		if s > bs:
			bs = s
			best = h
	if best == null:
		_target = null
		return
	if _target == null:
		_switch_to(best, false)
	elif best != _target:
		var forced: bool = _big_hit_key != "" and String(best.get("key")) == _big_hit_key and _since_switch > 1.2
		if forced or _since_switch >= _switch_every:
			_switch_to(best, true)
	_big_hit_key = ""


func threat_score(h: Node2D, all: Array) -> float:
	var s: float = _threat.get(String(h.get("key")), 0.0)
	s += clampf(1.0 - position.distance_to(h.position) / 900.0, 0.0, 1.0) * 30.0
	for o in all:
		if o != h and is_instance_valid(o) and o.downed and o.position.distance_to(h.position) < 95.0:
			s += 90.0   # punish the rescuer
	if h == _target:
		s += 14.0       # stickiness
	return s


func _switch_to(h: Node2D, roar: bool) -> void:
	_target = h
	_since_switch = 0.0
	_switch_every = randf_range(4.0, 6.5)
	tgt_pos = h.position
	_tgt_flash = 1.6
	if roar and is_boss and arena.heroes().size() > 1:
		_roar_pending = true


# ---------------------------------------------------------------- brain driver (host)

func _brain_think(delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	brain.tick_cooldowns(delta)
	# phase transitions wait for the current strike to land
	if _pending_phase > phase and state != S_ATTACK and state != S_ROAR:
		phase = _pending_phase
		phase2 = phase >= 1
		atk = -3
		_set_state(S_ROAR)
		if has_t:
			aim = dir
		brain.on_phase(phase)
		arena.shake(16.0)
		return Vector2.ZERO
	if _roar_pending and (state == S_IDLE or state == S_MOVE):
		_roar_pending = false
		atk = -2
		if has_t:
			aim = dir
		_set_state(S_ROAR)
		return Vector2.ZERO
	match state:
		S_IDLE, S_MOVE:
			if not has_t:
				_set_state(S_IDLE)
				return Vector2.ZERO
			state = S_MOVE
			if _cd <= 0.0:
				var id: String = brain.choose(dist)
				if id != "":
					_begin(id, dir)
					return Vector2.ZERO
				_cd = 0.25
			return brain.locomote(delta, has_t, dir, dist)
		S_WINDUP:
			var sp: Dictionary = brain.spec(atk)
			var w := windup_len()
			if has_t and state_t < w * float(sp.get("track", 0.0)):
				aim = dir
			if state_t >= w:
				_set_state(S_ATTACK)
				if sp.get("leap", 0.0) > 0.0:
					_leap_from = position
				brain.on_strike(brain.atk_id(atk))
			return -aim * float(sp.get("back", 0.0))
		S_ATTACK:
			var sp: Dictionary = brain.spec(atk)
			var a: float = float(sp.get("a", 0.3)) / maxf(spd_mul(), 1.0) if sp.get("leap", 0.0) <= 0.0 else float(sp.get("a", 0.3))
			var mv: Vector2 = aim * float(sp.get("speed", 0.0)) * (1.0 + 0.15 * phase)
			mv += brain.strike_move(brain.atk_id(atk), state_t)
			if sp.get("leap", 0.0) > 0.0:
				var k := clampf(state_t / a, 0.0, 1.0)
				var want: Vector2 = _leap_from.lerp(aux, _ease_leap(k))
				mv = (want - position) / maxf(get_physics_process_delta_time(), 0.001)
			if state_t >= a:
				var nx: String = sp.get("next", "")
				if nx != "" and randf() < float(sp.get("next_p", 1.0)) and brain.usable_chain(nx):
					_begin(nx, dir if has_t else aim)
				else:
					_set_state(S_RECOVER)
			return mv
		S_RECOVER:
			var sp: Dictionary = brain.spec(atk)
			if state_t >= float(sp.get("r", 0.5)) / sqrt(spd_mul()):
				_set_state(S_MOVE)
				_cd = brain.base_cd() / spd_mul()
		S_ROAR:
			if has_t and state_t < 0.2:
				aim = dir
			if state_t >= (1.35 if atk == -3 else 0.6):
				_set_state(S_MOVE)
				_cd = minf(_cd, 0.3)
		S_STUN:
			if state_t >= float(brain.spec(atk).get("stun", 1.4)):
				_set_state(S_MOVE)
				_cd = 0.4
	return Vector2.ZERO


var _leap_from := Vector2.ZERO


static func _ease_leap(k: float) -> float:
	return k * k * (3.0 - 2.0 * k)


func _begin(id: String, dir: Vector2) -> void:
	atk = brain.atk_index(id)
	aim = dir
	_set_state(S_WINDUP)
	brain.set_cd(id)
	brain.on_windup(id)


func _set_state(s: int) -> void:
	state = s
	state_t = 0.0


# ---------------------------------------------------------------- legacy AI (chapter 1 foes)

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
	if brain != null:
		var got: float = brain.filter_damage(amount, from_pos)
		if got < amount * 0.6:
			_block_t = 0.25
			if arena != null:
				arena.spark(position + (from_pos - position).normalized() * radius + Vector2(0, -50), Color(0.9, 1.0, 0.7), 6)
				arena.float_text(position + Vector2(0, -_height - 10.0), "BLOCKED", Color(0.85, 1.0, 0.7))
		amount = got
	if _aggro and attacker_key != "":
		_threat[attacker_key] = float(_threat.get(attacker_key, 0.0)) + amount
		if (amount >= max_hp * 0.035 or crit) and (_target == null or String(_target.get("key")) != attacker_key):
			_big_hit_key = attacker_key
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


## HOST only: drag toward a point (chain scythe yank, vortex). Heavy foes resist.
func pull(target: Vector2, strength: float) -> void:
	if _dead:
		return
	var to := target - position
	var d := to.length()
	if d < 8.0:
		return
	_knock += to / d * minf(strength, sqrt(2800.0 * d) * 0.85) / _mass


func _apply_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	_show_bar = true
	if _phases.size() > _pending_phase and hp > 0.0 and hp <= max_hp * float(_phases[_pending_phase]):
		_pending_phase += 1
	if hp <= 0.0:
		hp = 0.0
		_dead = true
		hitbox_active = false
		if arena != null:
			arena.on_enemy_killed(self, _last_attacker)


## HOST: remove this enemy without a killer (self-destructing wisps).
func expire() -> void:
	_last_attacker = ""
	_apply_damage(hp + 1.0)


func is_dead() -> bool:
	return _dead


func flash_hit() -> void:
	_flash = 1.0
	_hit_sq = 1.0


func _sync_hitbox() -> void:
	if brain != null:
		var on := false
		hitbox_radius = radius
		contact_damage = 0.0
		if state == S_ATTACK:
			var sp: Dictionary = brain.spec(atk)
			if float(sp.get("hit_r", 0.0)) > 0.0:
				on = true
				hitbox_radius = float(sp["hit_r"])
				contact_damage = float(sp.get("dmg", 10.0))
		var bh: Array = brain.contact()
		if not bh.is_empty():
			on = true
			hitbox_radius = bh[0]
			contact_damage = bh[1]
		hitbox_active = on and not _dead
		return
	match kind:
		"shade":
			hitbox_active = state == S_ATTACK
			hitbox_radius = radius + 14.0
			contact_damage = 10.0
		_:
			hitbox_active = false
			hitbox_radius = radius
			contact_damage = 0.0
	if _dead:
		hitbox_active = false


# ---------------------------------------------------------------- networking
## [x, y, hp, max_hp, state, state_t, facing, hitbox, burning, aim_angle,  kind_id, atk, phase, aux.x, aux.y, tgt.x, tgt.y, guard]

func pack() -> Array:
	var tp := tgt_pos if tgt_pos != Vector2.INF else Vector2(-99999.0, -99999.0)
	return [position.x, position.y, hp, max_hp, state, state_t, facing_sign, hitbox_active, burning, aim.angle(),
		KIND_IDS.find(kind), atk, phase, aux.x, aux.y, tp.x, tp.y, guarding]


func apply_packed(a: Array) -> void:
	if a.size() < 9:
		return
	if a.size() > 10:
		var ki := int(a[10])
		if ki >= 0 and ki < KIND_IDS.size() and KIND_IDS[ki] != kind:
			_apply_kind(KIND_IDS[ki], 1.0)   # arena only knows the first kinds: become the right one
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
		var natk := int(sb[11]) if sb.size() > 11 else atk
		if ns != state or natk != atk:
			state = ns
			atk = natk
			state_t = float(sb[5])
		else:
			state_t += delta
		facing_sign = float(sb[6])
		burning = bool(sb[8])
		if sb.size() > 9:
			aim = Vector2.RIGHT.rotated(float(sb[9]))
		if sb.size() > 17:
			phase = int(sb[12])
			aux = Vector2(sb[13], sb[14])
			var tp := Vector2(sb[15], sb[16])
			tgt_pos = tp if tp.x > -99990.0 else Vector2.INF
			guarding = bool(sb[17])
		phase2 = phase >= 1
		_sync_hitbox()
		hitbox_active = bool(sb[7])
	else:
		state_t += delta
	if _aggro:
		_client_target()
	_update_visuals(delta)


## client: the marker follows the real heroine nearest to the host's target position
func _client_target() -> void:
	if tgt_pos == Vector2.INF:
		_tgt_node = null
		return
	var best: Node2D = null
	var bd := 160.0 * 160.0
	for h in arena.heroes():
		var d: float = h.position.distance_squared_to(tgt_pos)
		if d < bd:
			bd = d
			best = h
	if best != _tgt_node and best != null and _tgt_node != null:
		_tgt_flash = 1.6
	_tgt_node = best


# ---------------------------------------------------------------- visuals

func _is_windup() -> bool:
	return state == S_WINDUP or state == S_W_BURST or state == S_W_CHARGE or state == S_W_SLAM or state == S_SUMMON


func windup_len() -> float:
	if brain != null:
		var sp: Dictionary = brain.spec(atk)
		return float(sp.get("w", 0.6)) / spd_mul()
	match kind:
		"shade":
			return 0.4
		"spitter":
			return 0.5
	return 0.8


func _update_visuals(delta: float) -> void:
	_anim_t += delta
	_flash = maxf(0.0, _flash - delta * 7.0)
	_hit_sq = maxf(0.0, _hit_sq - delta * 6.0)
	_tgt_flash = maxf(0.0, _tgt_flash - delta)
	_block_t = maxf(0.0, _block_t - delta)
	if state != _last_sfx_state:
		_last_sfx_state = state
		_state_sfx()
	if body == null:
		queue_redraw()
		return
	var bob := 0.0
	if _hover > 0.0:
		bob = _hover + sin(_anim_t * 3.0) * _hover * 0.5
	if brain != null and state == S_ATTACK:
		var sp: Dictionary = brain.spec(atk)
		var lh: float = float(sp.get("leap", 0.0))
		if lh > 0.0:
			bob += sin(PI * clampf(state_t / float(sp.get("a", 0.5)), 0.0, 1.0)) * lh
	body.position = Vector2(0.0, -bob)
	var attacking := state == S_WINDUP or state == S_ATTACK or state == S_ROAR or _is_windup()
	if brain != null and state == S_RECOVER:
		attacking = true
	body.set_facing(aim if attacking else Vector2(facing_sign, 0.35))
	if brain != null:
		_brain_anim()
	elif state == S_HURT and _last_vis_state != S_HURT:
		body.play("hurt", true)
	else:
		body.play_enemy_state(state, windup_len() if _is_windup() else 0.0)
	_last_vis_state = state
	_last_vis_atk = atk
	body.flash = _flash
	if burning:
		var p := 0.5 + 0.5 * sin(_anim_t * 12.0)
		body.tint = Color(1.0, 0.78 - 0.18 * p, 0.55 - 0.3 * p)
	elif state == S_STUN:
		var ps := 0.5 + 0.5 * sin(_anim_t * 16.0)
		body.tint = Color(1.0, 1.0, 0.75 + 0.25 * ps)
	elif is_boss and phase > 0:
		var p2 := 0.5 + 0.5 * sin(_anim_t * (3.0 + phase * 2.0))
		body.tint = Color(1.0, 0.86 - 0.08 * phase * p2, 0.9 - 0.12 * phase * p2)
	else:
		body.tint = _base_tint
	queue_redraw()


func _play_any(names: Array, restart: bool) -> String:
	for n in names:
		if n != "" and body.has_anim(n):
			body.play(n, restart)
			return n
	return ""


func _brain_anim() -> void:
	var entered := state != _last_vis_state or atk != _last_vis_atk
	var sp: Dictionary = brain.spec(atk)
	body.set_speed_scale(1.0)
	match state:
		S_IDLE:
			_play_any(["idle"], false)
		S_MOVE:
			_play_any([brain.move_anim(), "move", "idle"], false)
			body.set_speed_scale(clampf(spd_mul(), 1.0, 1.6))
		S_WINDUP:
			if entered:
				var an: String = sp.get("aw", "windup")
				if not body.has_anim(an):
					an = "windup" if body.has_anim("windup") else "idle"
				body.play_timed(an, windup_len())
		S_ATTACK:
			if entered:
				_play_any([sp.get("aa", "attack"), "attack"], true)
				if sp.get("loop_a", false) or sp.get("leap", 0.0) > 0.0:
					body.play_timed(body.current, float(sp.get("a", 0.4)))
				elif spd_mul() > 1.0:
					body.set_speed_scale(spd_mul())
		S_RECOVER:
			if entered and sp.has("ar"):
				_play_any([sp["ar"]], true)
			elif body.is_playing_done() or body.current == "idle" or body.current == brain.move_anim():
				_play_any(["idle"], false)
		S_HURT:
			if entered:
				_play_any(["hurt"], true)
		S_ROAR:
			if entered:
				var an2 := _play_any(["roar", "cast", "windup"], true)
				if an2 != "":
					body.play_timed(an2, 1.35 if atk == -3 else 0.6)
		S_STUN:
			if entered:
				_play_any(["stun", "hurt"], true)
				body.play_timed(body.current, float(sp.get("stun", 1.4)) * 0.5)


func _state_sfx() -> void:
	if arena == null or brain == null:
		return
	var nm := ""
	match state:
		S_WINDUP:
			nm = brain.spec(atk).get("sfx_w", "")
		S_ATTACK:
			var sp: Dictionary = brain.spec(atk)
			nm = sp.get("sfx", _default_sfx(sp))
		S_ROAR:
			nm = "regent_roar" if is_boss or atk == -3 else ""
			if atk == -3:
				arena.shake(14.0)
	if nm != "":
		arena.sfx(nm, position)


## strike sound when an attack spec names none (keeps every brain audible with the shared sfx set)
static func _default_sfx(sp: Dictionary) -> String:
	var aa: String = sp.get("aa", "")
	if sp.get("charge", false) or aa == "dash":
		return "regent_charge"
	if sp.get("leap", 0.0) > 0.0:
		return "dash"
	if aa.contains("slam") or aa.contains("stomp") or aa.contains("chop"):
		return "brute_slam"
	if aa.contains("cast") or aa.contains("bolt") or aa.contains("volley") or aa.contains("throw") or aa.contains("puff"):
		return "spitter_shoot"
	if aa == "roar":
		return "regent_summon"
	return "shade_lunge"


func _draw() -> void:
	# Soft ground shadow (shrinks while hovering / leaping high).
	var hov := 0.0
	if _hover > 0.0:
		hov = sin(_anim_t * 3.0) * 0.08
	if brain != null and state == S_ATTACK and float(brain.spec(atk).get("leap", 0.0)) > 0.0:
		hov = 0.35 * sin(PI * clampf(state_t / float(brain.spec(atk).get("a", 0.5)), 0.0, 1.0))
	var sr := radius * 1.35 * (1.0 - hov)
	if kind != "wisp":
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.42))
		draw_circle(Vector2.ZERO, sr * 1.25, Color(0, 0, 0, 0.14))
		draw_circle(Vector2.ZERO, sr, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO)

	if brain != null:
		_draw_brain_tele()
		brain.draw_extra()
	elif _is_windup():
		var k := clampf(state_t / windup_len(), 0.0, 1.0)
		if kind == "shade":
			_ring(aim * 70.0, radius + 26.0, k, TELEGRAPH_COLOR)
		elif kind == "spitter":
			_ring(Vector2.ZERO, radius + 18.0, k, TELEGRAPH_COLOR)
	draw_set_transform(Vector2.ZERO)

	if _aggro:
		_draw_target_marker()

	# hp bar for damaged non-boss enemies (elites: wider, gold trim)
	if _show_bar and not is_boss and kind != "wisp" and hp > 0.0 and hp < max_hp:
		var w := 46.0
		if is_elite:
			w = 96.0
		elif _mass >= 3.0:
			w = 70.0
		var y := -_height - 14.0 - _hover
		var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
		draw_rect(Rect2(-w * 0.5 - 2.0, y - 2.0, w + 4.0, 9.0), Color(0.05, 0.02, 0.04, 0.85))
		if is_elite:
			draw_rect(Rect2(-w * 0.5 - 3.0, y - 3.0, w + 6.0, 11.0), Color(1.0, 0.8, 0.35, 0.9), false, 1.5)
		draw_rect(Rect2(-w * 0.5, y, w * frac, 5.0), Color(0.9, 0.18, 0.2) if not burning else Color(1.0, 0.55, 0.15))


func _draw_brain_tele() -> void:
	if state != S_WINDUP:
		return
	var sp: Dictionary = brain.spec(atk)
	var k := clampf(state_t / maxf(windup_len(), 0.01), 0.0, 1.0)
	var col: Color = sp.get("col", TELEGRAPH_COLOR)
	match String(sp.get("tele", "")):
		"line":
			var ln: float = float(sp.get("tele_len", 300.0))
			var wd: float = float(sp.get("tele_w", radius * 1.6))
			var end := aim * ln
			draw_line(Vector2.ZERO, end, Color(col, 0.16), wd)
			draw_line(Vector2.ZERO, end * k, Color(col, 0.42), wd)
			var side := aim.orthogonal() * wd * 0.5
			draw_line(side, end + side, Color(col, 0.85), 2.0)
			draw_line(-side, end - side, Color(col, 0.85), 2.0)
		"cone":
			var reach: float = float(sp.get("tele_len", 130.0))
			var arc := deg_to_rad(float(sp.get("tele_arc", 100.0)))
			_cone(reach, arc, k, col)
		"ring":
			_ring(Vector2.ZERO, float(sp.get("tele_r", 120.0)), k, col)
		"aux":
			_ring(aux - position, float(sp.get("tele_r", 120.0)), k, col)


func _draw_target_marker() -> void:
	var tg: Node2D = _target if is_authority_side() else _tgt_node
	if tg == null or not is_instance_valid(tg) or _dead:
		return
	if arena == null or arena.heroes().size() < 2:
		return   # only meaningful in co-op
	var off := tg.position - position
	var pulse := 0.5 + 0.5 * sin(_anim_t * 6.0)
	var big := clampf(_tgt_flash / 1.6, 0.0, 1.0)
	# ground ring under the hunted heroine
	draw_set_transform(off, 0.0, Vector2(1.0, 0.45))
	draw_arc(Vector2.ZERO, 46.0 + 8.0 * pulse, 0.0, TAU, 32, Color(TARGET_COLOR, 0.5 + 0.3 * big), 3.0)
	draw_set_transform(Vector2.ZERO)
	# chevron over her head (large right after a switch)
	var head := off + Vector2(0.0, -190.0 - 10.0 * pulse)
	var s := 12.0 + 14.0 * big
	var pts := PackedVector2Array([head + Vector2(-s, -s * 0.9), head + Vector2(s, -s * 0.9), head + Vector2(0, s * 0.4)])
	draw_colored_polygon(pts, Color(TARGET_COLOR, 0.65 + 0.35 * big))
	draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0.08, 0.02, 0.03, 0.9), 2.0)
	if big > 0.0:
		# a quick tether from the boss to the new prey
		var from := Vector2(0.0, -_height * 0.6)
		draw_line(from, from.lerp(head, 1.0 - big * 0.5), Color(TARGET_COLOR, 0.35 * big), 3.0)


func is_authority_side() -> bool:
	return arena != null and arena.is_authority()


## Ellipse ring at local ground position c (pre-squash coords), filling with k in [0,1].
func _ring(c: Vector2, r: float, k: float, col: Color) -> void:
	draw_set_transform(Vector2(c.x, c.y), 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2.ZERO, r * k, Color(col, 0.22 + 0.2 * k))
	draw_arc(Vector2.ZERO, r, 0.0, TAU, 40, Color(col, 0.85), 3.0)
	draw_set_transform(Vector2.ZERO)


## Ground cone (sweep) along aim, squashed for the iso floor, filling with k.
func _cone(reach: float, arc: float, k: float, col: Color) -> void:
	var a0 := aim.angle() - arc * 0.5
	var outer := PackedVector2Array([Vector2.ZERO])
	var inner := PackedVector2Array([Vector2.ZERO])
	var n := 14
	for i in n + 1:
		var d := Vector2.RIGHT.rotated(a0 + arc * i / n)
		outer.append(Vector2(d.x, d.y * 0.55) * reach)
		inner.append(Vector2(d.x, d.y * 0.55) * reach * k)
	draw_colored_polygon(outer, Color(col, 0.14))
	if k > 0.02:
		draw_colored_polygon(inner, Color(col, 0.32))
	outer.append(Vector2.ZERO)
	draw_polyline(outer, Color(col, 0.85), 2.5)
