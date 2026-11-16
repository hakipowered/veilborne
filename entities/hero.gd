extends Node2D
## A playable heroine. The owning device simulates her (prediction); other devices
## interpolate her streamed state.

const OUTLINE := Color(0.06, 0.03, 0.06)
const STATES := ["idle", "run", "attack", "dash", "special", "hurt", "downed"]

var key := ""
var hero_id := "kaela"
var def: Dictionary
var controlled := false
var local_index := 0
var arena: Node

var hp := 100.0
var max_hp := 100
var vel := Vector2.ZERO
var facing := Vector2.RIGHT
var state := "idle"
var state_t := 0.0
var anim_t := 0.0
var combo := 0
var combo_window := 0.0
var attack_cd := 0.0
var special_cd := 0.0
var dash_charges := 1
var dash_recharge := 0.0
var iframes := 0.0
var flash := 0.0
var downed := false
var revive_progress := 0.0
var defiance_left := 0
var seq := 0
var boons := {} ## id -> {level, rarity}
var stats := {}
var _send_timer := 0.0
var _buffer: Array = [] ## [[time, state_array]]
var touch = null ## TouchControls (or any object with move/attack/special/dash) for local_index 0
var _prev_buttons := {}
var _buffer_t := {"attack": 0.0, "special": 0.0, "dash": 0.0}
var _ghosts: Array = [] ## [pos, flipped, life] dash afterimages
var _ghost_timer := 0.0

func setup(p_key: String, p_hero: String, p_controlled: bool, p_local: int, p_arena: Node) -> void:
	key = p_key
	hero_id = p_hero
	def = Game.HEROES[p_hero]
	controlled = p_controlled
	local_index = p_local
	arena = p_arena
	recompute_stats()
	var rt: Dictionary = Game.hero_runtime.get(key, {})
	if rt.is_empty():
		hp = max_hp
		defiance_left = Game.meta_rank("defiance") if controlled else 0
	else:
		boons = rt["boons"]
		recompute_stats()
		hp = min(rt["hp"], max_hp)
		defiance_left = rt["defiance"]

func save_runtime() -> void:
	Game.hero_runtime[key] = {"hp": max(hp, max_hp * 0.3), "boons": boons, "defiance": defiance_left}

func recompute_stats() -> void:
	stats = {"attack_mult": 0, "special_mult": 0, "burn": 0, "dash_shock": 0, "chain": 0,
		"speed_mult": 0, "max_hp_bonus": 0, "lifesteal": 0, "special_size": 0, "crit": 5,
		"armor": 0, "dash_charges": 0}
	for id in boons.keys():
		if String(id).begins_with("_"):
			continue
		var b := Game.boon_by_id(id)
		var info: Dictionary = boons[id]
		var v: int = b["values"][int(info["rarity"])]
		stats[b["stat"]] += v * int(info["level"])
	var meta_on := controlled
	var old_max := max_hp
	max_hp = int(def["hp"]) + stats["max_hp_bonus"] + (10 * Game.meta_rank("vitality") if meta_on else 0)
	if max_hp > old_max and hp > 0:
		hp += max_hp - old_max
	stats["dmg_meta"] = 1.0 + (0.06 * Game.meta_rank("fury") if meta_on else 0.0)
	if not meta_on and boons.has("_dmg_meta"):
		stats["dmg_meta"] = float(boons["_dmg_meta"])
	stats["speed_meta"] = 1.0 + (0.04 * Game.meta_rank("swift") if meta_on else 0.0)
	dash_charges = 1 + stats["dash_charges"]

func add_boon(id: String, rarity: int) -> void:
	if boons.has(id):
		boons[id]["level"] += 1
		boons[id]["rarity"] = max(boons[id]["rarity"], rarity)
	else:
		boons[id] = {"level": 1, "rarity": rarity}
	recompute_stats()
	sync_boons()

func sync_boons() -> void:
	if Net.online and controlled:
		boons["_dmg_meta"] = stats["dmg_meta"]
		Net.hero_boons.rpc(key, boons, max_hp)

## kind: "attack" or "special"; finisher: third hit of the combo lands harder.
func attack_damage(kind: String, finisher := false) -> float:
	var base: float = def["attack"] if kind == "attack" else def["special"]
	var mult: float = 1.0 + (stats["attack_mult"] if kind == "attack" else stats["special_mult"]) / 100.0
	if kind == "attack" and finisher:
		mult *= 1.6
	return base * mult * stats["dmg_meta"]

# ---------------------------------------------------------------- input

func _read_input() -> Dictionary:
	var mv := Vector2.ZERO
	var b := {"attack": false, "special": false, "dash": false}
	if local_index == 0:
		mv.x = int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
		mv.y = int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
		b["attack"] = Input.is_physical_key_pressed(KEY_J)
		b["special"] = Input.is_physical_key_pressed(KEY_K)
		b["dash"] = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_L)
		if touch:
			mv += touch.move
			b["attack"] = b["attack"] or touch.attack
			b["special"] = b["special"] or touch.special
			b["dash"] = b["dash"] or touch.dash
	else:
		mv.x = int(Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_LEFT))
		mv.y = int(Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_UP))
		b["attack"] = Input.is_physical_key_pressed(KEY_KP_1) or Input.is_physical_key_pressed(KEY_COMMA)
		b["special"] = Input.is_physical_key_pressed(KEY_KP_2) or Input.is_physical_key_pressed(KEY_PERIOD)
		b["dash"] = Input.is_physical_key_pressed(KEY_KP_0) or Input.is_physical_key_pressed(KEY_SLASH)
	# Gamepad N drives local player N.
	var pads := Input.get_connected_joypads()
	if local_index < pads.size():
		var d: int = pads[local_index]
		var stick := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		if stick.length() > 0.2:
			mv += stick
		b["attack"] = b["attack"] or Input.is_joy_button_pressed(d, JOY_BUTTON_X)
		b["special"] = b["special"] or Input.is_joy_button_pressed(d, JOY_BUTTON_Y)
		b["dash"] = b["dash"] or Input.is_joy_button_pressed(d, JOY_BUTTON_A) or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER)
	var pressed := {}
	for k in b.keys():
		pressed[k] = b[k] and not _prev_buttons.get(k, false)
	_prev_buttons = b
	return {"move": mv.limit_length(1.0), "pressed": pressed}

# ---------------------------------------------------------------- simulation

func _physics_process(delta: float) -> void:
	anim_t += delta
	flash = max(0.0, flash - delta * 4.0)
	if controlled:
		_simulate(delta)
		_send_timer -= delta
		if Net.online and _send_timer <= 0.0:
			_send_timer = 1.0 / 30.0
			Net.hero_state.rpc(key, pack_state())
	else:
		_interpolate()
	queue_redraw()

func _simulate(delta: float) -> void:
	var inp := _read_input()
	var mv: Vector2 = inp["move"]
	# Input buffer: a press stays valid for a short window so combos and dash-cancels feel crisp.
	for k in inp["pressed"].keys():
		if inp["pressed"][k]:
			_buffer_t[k] = 0.16
	var pr := {}
	for k in _buffer_t.keys():
		_buffer_t[k] = maxf(0.0, _buffer_t[k] - delta)
		pr[k] = _buffer_t[k] > 0.0
	state_t += delta
	for g in _ghosts:
		g[2] -= delta
	attack_cd = max(0.0, attack_cd - delta)
	special_cd = max(0.0, special_cd - delta)
	iframes = max(0.0, iframes - delta)
	combo_window = max(0.0, combo_window - delta)
	if combo_window <= 0.0:
		combo = 0
	if dash_charges < 1 + stats["dash_charges"]:
		dash_recharge -= delta
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = 0.55

	if downed:
		state = "downed"
		vel = Vector2.ZERO
		_update_revive(delta)
		return

	var speed: float = def["speed"] * (1.0 + stats["speed_mult"] / 100.0) * stats["speed_meta"]
	if mv.length() > 0.1 and state in ["idle", "run"]:
		facing = mv.normalized()

	if pr["dash"] and dash_charges > 0 and state != "dash":
		dash_charges -= 1
		dash_recharge = 0.55
		var dir := mv.normalized() if mv.length() > 0.1 else facing
		facing = dir
		_set_state("dash")
		iframes = 0.22
		vel = dir * speed * 3.4
		_buffer_t["dash"] = 0.0
		_ghost_timer = 0.0
		_act("dash", position, dir)
	elif pr["attack"] and attack_cd <= 0.0 and state in ["idle", "run", "attack"]:
		facing = _aim(mv)
		_buffer_t["attack"] = 0.0
		combo = (combo + 1) % 3
		combo_window = 0.6
		var spd := 0.32 if def["weapon"] == "spear" else 0.2
		attack_cd = spd
		_set_state("attack")
		vel = facing * (260.0 if def["weapon"] == "spear" else 200.0) * (1.4 if combo == 0 else 1.0)
		_act("attack%d" % combo, position, facing)
	elif pr["special"] and special_cd <= 0.0 and state in ["idle", "run", "attack"]:
		facing = _aim(mv)
		_buffer_t["special"] = 0.0
		special_cd = 2.6
		_set_state("special")
		vel = Vector2.ZERO
		_act("special", position, facing)

	match state:
		"dash":
			_ghost_timer -= delta
			if _ghost_timer <= 0.0:
				_ghost_timer = 0.035
				_ghosts.append([position, facing.x < -0.05, 0.25])
			if state_t > 0.18:
				_set_state("idle")
				vel *= 0.25
		"attack":
			vel = vel.move_toward(Vector2.ZERO, 900 * delta)
			if state_t > attack_cd + 0.02:
				_set_state("idle")
		"special":
			if state_t > 0.35:
				_set_state("idle")
		"hurt":
			vel = vel.move_toward(Vector2.ZERO, 1200 * delta)
			if state_t > 0.18:
				_set_state("idle")
		_:
			vel = vel.lerp(mv * speed, min(1.0, 18.0 * delta))
			_set_state("run" if mv.length() > 0.1 else "idle", false)

	position += vel * delta
	position = arena.resolve_collision(position, 16.0)

## Aim assist for touch: snap toward the nearest enemy in front, else use the stick.
func _aim(mv: Vector2) -> Vector2:
	var want := mv.normalized() if mv.length() > 0.1 else facing
	var best := Vector2.ZERO
	var bd := 230.0 * 230.0
	for e in arena.enemies():
		if e.hp <= 0:
			continue
		var to: Vector2 = e.position - position
		var d := to.length_squared()
		if d < bd and absf(want.angle_to(to)) < deg_to_rad(70.0):
			bd = d
			best = to
	return best.normalized() if best != Vector2.ZERO else want

func _set_state(s: String, reset := true) -> void:
	if s != state or reset:
		if s != state or reset:
			state_t = 0.0
	state = s

func _act(action: String, pos: Vector2, dir: Vector2) -> void:
	seq += 1
	arena.hero_action_local(self, action, pos, dir, seq)
	if Net.online:
		Net.hero_action.rpc(key, action, pos, dir, seq)

func take_hit(amount: float, from: Vector2) -> void:
	if not controlled or downed or iframes > 0.0 or state == "dash":
		return
	amount *= 1.0 - stats["armor"] / 100.0
	hp -= amount
	iframes = 0.6
	flash = 1.0
	vel = (position - from).normalized() * 380.0
	_set_state("hurt")
	arena.on_local_hero_hurt(self, amount)
	if hp <= 0.0:
		if defiance_left > 0:
			defiance_left -= 1
			hp = max_hp * 0.5
			iframes = 1.5
			arena.float_text(position + Vector2(0, -80), "DEFIANCE!", Color(1, 0.85, 0.3))
		else:
			hp = 0.0
			downed = true
			revive_progress = 0.0

func heal(amount: float) -> void:
	if downed or not controlled:
		return
	hp = min(float(max_hp), hp + amount)

func revive(frac: float) -> void:
	if controlled and downed:
		arena.sfx("revive", position)
		downed = false
		hp = max_hp * frac
		iframes = 1.2
		_set_state("idle")

func _update_revive(delta: float) -> void:
	# A partner standing close revives a downed heroine.
	var near := false
	for h in arena.heroes():
		if h != self and not h.downed and h.position.distance_to(position) < 70.0:
			near = true
	revive_progress = clamp(revive_progress + (delta if near else -delta * 0.5), 0.0, 2.0)
	if revive_progress >= 2.0:
		revive(0.4)

# ---------------------------------------------------------------- network state

func pack_state() -> Array:
	return [position.x, position.y, facing.x, facing.y, STATES.find(state), state_t, hp, max_hp, downed, combo, revive_progress]

func apply_state(s: Array) -> void:
	_buffer.append([Time.get_ticks_msec(), s])
	while _buffer.size() > 20:
		_buffer.pop_front()

func _interpolate() -> void:
	if _buffer.is_empty():
		return
	var render_t: int = Time.get_ticks_msec() - arena.INTERP_DELAY_MS
	var a: Array = _buffer[0]
	var b: Array = _buffer[_buffer.size() - 1]
	for i in range(_buffer.size() - 1):
		if _buffer[i][0] <= render_t and _buffer[i + 1][0] >= render_t:
			a = _buffer[i]
			b = _buffer[i + 1]
			break
	var t := 1.0
	if b[0] != a[0]:
		t = clamp(float(render_t - a[0]) / float(b[0] - a[0]), 0.0, 1.0)
	var sa: Array = a[1]
	var sb: Array = b[1]
	position = Vector2(sa[0], sa[1]).lerp(Vector2(sb[0], sb[1]), t)
	facing = Vector2(sb[2], sb[3])
	var new_state: String = STATES[int(sb[4])]
	if new_state != state:
		state_t = 0.0
	else:
		state_t += get_physics_process_delta_time()
	state = new_state
	hp = sb[6]
	max_hp = int(sb[7])
	downed = sb[8]
	combo = int(sb[9])
	revive_progress = sb[10]

# ---------------------------------------------------------------- drawing

const SPRITE_HEIGHT := 160.0
const ONE_SHOTS := ["attack1", "attack2", "attack3", "special", "hurt"]
var body: AnimSprite
var fx: Node2D
var _last_state := ""
var _last_state_t := 0.0
var _last_combo := -1

func _ensure_sprite() -> void:
	if body:
		return
	body = AnimSprite.new()
	add_child(body)
	body.setup(hero_id, SPRITE_HEIGHT)
	body.anim_event.connect(_on_anim_event)
	# Additive layer for weapon smears so they glow like light, not paint.
	fx = Node2D.new()
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	fx.material = add
	fx.draw.connect(func(): _draw_weapon_fx(def["trim"]))
	add_child(fx)

func _on_anim_event(ev: String) -> void:
	if ev == "step" and state == "run" and is_instance_valid(arena) and arena.has_method("footstep"):
		arena.footstep(self)

## Plays the real animation for the current state. One-shot swings are time-fitted
## to feel snappy, and their recovery frames keep playing while the heroine stands still.
func _drive_anim() -> void:
	var entered := state != _last_state or state_t + 0.0001 < _last_state_t or (state == "attack" and combo != _last_combo)
	_last_state = state
	_last_state_t = state_t
	_last_combo = combo
	if downed:
		body.play("death")
		return
	var spear: bool = def["weapon"] == "spear"
	match state:
		"attack":
			var an := "attack%d" % (3 if combo == 0 else combo)
			if entered:
				body.play_timed(an, (0.5 if spear else 0.4) if combo == 0 else (0.36 if spear else 0.28))
		"special":
			if entered:
				body.play_timed("special", 0.55)
		"dash":
			if entered:
				body.play_timed("dash", 0.24)
		"hurt":
			if entered:
				body.play_timed("hurt", 0.26)
		"run":
			body.play("run")
			body.set_speed_scale(clampf(vel.length() / maxf(1.0, float(def["speed"])), 0.6, 1.3))
		_:
			if body.current in ONE_SHOTS and not body.is_playing_done():
				return # let the swing's follow-through finish
			body.set_speed_scale(1.0)
			body.play("idle")

func _process(_delta: float) -> void:
	_ensure_sprite()
	body.set_facing(facing)
	_drive_anim()
	body.flash = flash
	var blink := iframes > 0.0 and state != "dash" and not downed and int(anim_t * 20) % 2 == 0
	var a := 0.5 if blink else (0.6 if state == "dash" else 1.0)
	body.tint = Color(0.55, 0.55, 0.7, a) if downed else Color(1, 1, 1, a)

func _draw() -> void:
	var trim: Color = def["trim"]
	# Ground shadow and player ring (VFX only; the body is the painted sprite).
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1, 0.42))
	draw_circle(Vector2.ZERO, 30, Color(0, 0, 0, 0.4))
	draw_arc(Vector2.ZERO, 36, 0, TAU, 40, Color(trim, 0.75), 3.0)
	if controlled:
		draw_arc(Vector2.ZERO, 36, facing.angle() - 0.35, facing.angle() + 0.35, 10, Color.WHITE, 5.0)
	draw_set_transform(Vector2.ZERO)
	while not _ghosts.is_empty() and _ghosts[0][2] <= 0.0:
		_ghosts.pop_front()
	if downed:
		var frac := revive_progress / 2.0
		draw_arc(Vector2(0, -70), 20, -PI / 2, -PI / 2 + TAU * frac, 32, Color(0.4, 1.0, 0.6), 6.0)
		return
	if state == "dash":
		for i in range(3):
			var o := -facing * (22.0 * (i + 1))
			draw_set_transform(o, 0.0, Vector2(1, 0.42))
			draw_circle(Vector2.ZERO, 26 - i * 6, Color(trim, 0.3 - i * 0.08))
		draw_set_transform(Vector2.ZERO)
	if fx:
		fx.queue_redraw()

func _draw_weapon_fx(trim: Color) -> void:
	var ang := facing.angle()
	var center := Vector2(0, -50)
	var spear: bool = def["weapon"] == "spear"
	if state == "attack":
		var dur := 0.32 if spear else 0.2
		var k := clampf(state_t / dur, 0.0, 1.0)
		var alpha := 1.0 - k * k
		var reach := 110.0 if spear else 86.0
		var arc := deg_to_rad(70.0 if spear else 140.0)
		if combo == 0:
			reach *= 1.15
		# Bold smear crescent: bright core, ink edge, fades fast.
		var pts := PackedVector2Array()
		var steps := 12
		for i in range(steps + 1):
			pts.append(center + Vector2.RIGHT.rotated(ang - arc / 2 + arc * i / steps) * reach)
		for i in range(steps, -1, -1):
			pts.append(center + Vector2.RIGHT.rotated(ang - arc / 2 + arc * i / steps) * (reach * (0.35 + 0.35 * k)))
		fx.draw_colored_polygon(pts, Color(trim.lightened(0.1), 0.85 * alpha))
		fx.draw_polyline(pts.slice(0, steps + 1), Color(1, 1, 1, alpha), 5.0, true)
		if spear:
			var tip := center + facing * reach * (0.8 + 0.3 * (1.0 - k))
			fx.draw_line(center, tip, Color(1, 0.9, 0.6, alpha), 6.0)
	elif state == "special":
		var k := clampf(state_t / 0.35, 0.0, 1.0)
		var r: float = (120.0 if not spear else 90.0) * (1.0 + stats.get("special_size", 0) / 100.0)
		var c := Vector2.ZERO if not spear else facing * 150.0
		fx.draw_set_transform(c, 0.0, Vector2(1, 0.55))
		fx.draw_circle(Vector2.ZERO, r * k, Color(trim, 0.35 * (1.0 - k)))
		fx.draw_arc(Vector2.ZERO, r * k, 0, TAU, 40, Color(1, 1, 1, 1.0 - k), 6.0)
		fx.draw_arc(Vector2.ZERO, r * k * 0.7, 0, TAU, 40, Color(trim.lightened(0.3), 1.0 - k), 3.0)
		fx.draw_set_transform(Vector2.ZERO)
