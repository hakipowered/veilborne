extends Node2D
## A playable heroine. The owning device simulates her (prediction); other devices
## interpolate her streamed state.

const OUTLINE := Color(0.06, 0.03, 0.06)
const STATES := ["idle", "run", "attack", "dash", "special", "hurt", "downed", "draw"]
const AIM_RANGE := 420.0 ## max distance of the aimed special's landing point
const DRAW_TIME := 0.6   ## bow: seconds to a full draw

var key := ""
var hero_id := "kaela"
var def: Dictionary
var weapon_id := "spear"
var aspect := 0
var wdef: Dictionary
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
var attack_len := 0.3
var special_cd := 0.0
var special_cd_max := 2.6
var dash_charges := 1
var dash_recharge := 0.0
var iframes := 0.0
var flash := 0.0
var downed := false
var revive_progress := 0.0
var defiance_left := 0
var seq := 0
var boons := {} ## id -> {level, rarity}; "_forge" -> {id: {level, rarity}}, "_weapon", "_aspect"
var stats := {}
## Aimed special: while the special button is held the heroine aims a landing point.
var aiming := false
var aim_point := Vector2.ZERO
var special_from := Vector2.ZERO
var special_to := Vector2.ZERO
var special_time := 0.6
var special_hit := 0.4
var hop := 0.0 ## leap height (visual)
var charge := 0.0 ## bow draw 0..1
var _send_timer := 0.0
var _buffer: Array = [] ## [[time, state_array]]
var touch = null ## TouchControls (or any object with move/attack/special/dash[/special_aim]) for local_index 0
var _buffer_t := {"attack": 0.0, "special": 0.0, "dash": 0.0}
var _held := {"attack": false, "special": false, "dash": false}
var _prev_held := {"attack": false, "special": false, "dash": false}
var _pressed := {"attack": false, "special": false, "dash": false}
var _pr := {"attack": false, "special": false, "dash": false}
var _in_move := Vector2.ZERO
var _in_aim := Vector2.ZERO        ## -1..1 aim offset from touch drag / right stick (ZERO = none)
var _in_aim_world := Vector2.INF   ## mouse aim in world space
var _ghosts: Array = [] ## [pos, flipped, life] dash afterimages
var _ghost_timer := 0.0
static var _mouse_seen := false

func setup(p_key: String, p_hero: String, p_controlled: bool, p_local: int, p_arena: Node, p_weapon := "", p_aspect := 0) -> void:
	key = p_key
	hero_id = p_hero
	def = Game.HEROES[p_hero]
	controlled = p_controlled
	local_index = p_local
	arena = p_arena
	set_process_input(controlled and local_index == 0)
	_apply_weapon(p_weapon, p_aspect)
	recompute_stats()
	var rt: Dictionary = Game.hero_runtime.get(key, {})
	if rt.is_empty():
		hp = max_hp
		defiance_left = Game.meta_rank("defiance") if controlled else 0
	else:
		boons = rt["boons"]
		_apply_weapon(String(boons.get("_weapon", weapon_id)), int(boons.get("_aspect", aspect)))
		recompute_stats()
		hp = min(rt["hp"], max_hp)
		defiance_left = rt["defiance"]

func _apply_weapon(w: String, a: int) -> void:
	if not Game.WEAPONS.has(w):
		w = Game.default_weapon(hero_id)
	weapon_id = w
	wdef = Game.WEAPONS[w]
	aspect = clampi(a, 0, wdef["aspects"].size() - 1)
	boons["_weapon"] = weapon_id
	boons["_aspect"] = aspect
	special_cd_max = float(wdef["special_cd"])
	special_time = float(wdef["special_time"])
	special_hit = float(wdef["special_hit"])

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse_seen = true

func save_runtime() -> void:
	Game.hero_runtime[key] = {"hp": max(hp, max_hp * 0.3), "boons": boons, "defiance": defiance_left}

func recompute_stats() -> void:
	stats = {"attack_mult": 0, "special_mult": 0, "burn": 0, "dash_shock": 0, "chain": 0,
		"speed_mult": 0, "max_hp_bonus": 0, "lifesteal": 0, "special_size": 0, "crit": 5,
		"armor": 0, "dash_charges": 0,
		# weapon stats (forge upgrades + aspects)
		"w_range": 0.0, "w_area": 0.0, "w_reach": 0.0, "w_speed": 0.0, "w_twice": 0.0, "w_dash_strike": 0.0,
		"w_pool": 0.0, "w_whirl": 0.0, "w_return": 0.0, "w_multi": 0.0, "w_pierce": 0.0, "w_split": 0.0,
		"w_charge": 0.0, "w_pulses": 0.0, "w_ricochet": 0.0, "w_anchor": 0.0, "w_rush": 0.0, "w_yank": 0.0,
		"w_soul": 0.0, "w_detonate": 0.0}
	if boons.has("_weapon") and String(boons["_weapon"]) != weapon_id:
		_apply_weapon(String(boons["_weapon"]), int(boons.get("_aspect", 0)))
	for id in boons.keys():
		if String(id).begins_with("_"):
			continue
		var b := Game.boon_by_id(id)
		if b.is_empty():
			continue
		var info: Dictionary = boons[id]
		var v: int = b["values"][int(info["rarity"])]
		stats[b["stat"]] += v * int(info["level"])
	var forge: Dictionary = boons.get("_forge", {})
	for id in forge.keys():
		var f := Game.forge_by_id(String(id))
		if f.is_empty() or not stats.has(f["stat"]):
			continue
		var info: Dictionary = forge[id]
		stats[f["stat"]] += f["values"][clampi(int(info["rarity"]), 0, 2)] * int(info["level"])
	var mods: Dictionary = Game.aspect_def(weapon_id, aspect).get("mods", {})
	for k in mods.keys():
		if stats.has(k):
			stats[k] += mods[k]
	var meta_on := controlled
	var old_max := max_hp
	max_hp = int(def["hp"]) + stats["max_hp_bonus"] + (10 * Game.meta_rank("vitality") if meta_on else 0)
	if max_hp > old_max and hp > 0:
		hp += max_hp - old_max
	stats["dmg_meta"] = 1.0 + (0.06 * Game.meta_rank("fury") if meta_on else 0.0)
	if not meta_on and boons.has("_dmg_meta"):
		stats["dmg_meta"] = float(boons["_dmg_meta"])
	stats["speed_meta"] = 1.0 + (0.04 * Game.meta_rank("swift") if meta_on else 0.0)
	dash_charges = 1 + int(stats["dash_charges"])

func add_boon(id: String, rarity: int) -> void:
	if boons.has(id):
		boons[id]["level"] += 1
		boons[id]["rarity"] = max(boons[id]["rarity"], rarity)
	else:
		boons[id] = {"level": 1, "rarity": rarity}
	recompute_stats()
	sync_boons()

## In-run weapon upgrade from the Forge. Synced to peers with the boons.
func add_forge(id: String, rarity: int) -> void:
	if not boons.has("_forge"):
		boons["_forge"] = {}
	var forge: Dictionary = boons["_forge"]
	if forge.has(id):
		forge[id]["level"] += 1
		forge[id]["rarity"] = max(forge[id]["rarity"], rarity)
	else:
		forge[id] = {"level": 1, "rarity": rarity}
	recompute_stats()
	sync_boons()

func sync_boons() -> void:
	if Net.online and controlled:
		boons["_dmg_meta"] = stats["dmg_meta"]
		Net.hero_boons.rpc(key, boons, max_hp)

## kind: "attack" or "special"; finisher: third hit of the combo lands harder.
func attack_damage(kind: String, finisher := false) -> float:
	var base: float = wdef["attack"] if kind == "attack" else wdef["special"]
	var mult: float = 1.0 + (stats["attack_mult"] if kind == "attack" else stats["special_mult"]) / 100.0
	if kind == "attack" and finisher:
		mult *= 1.6
		if weapon_id == "shield":
			mult *= 1.0 + stats["w_rush"] / 100.0
	return base * mult * stats["dmg_meta"]

func area_mult() -> float:
	return 1.0 + (float(stats["w_area"]) + float(stats["special_size"])) / 100.0

func reach_mult() -> float:
	return 1.0 + float(stats["w_reach"]) / 100.0

# ---------------------------------------------------------------- input

## Fills _in_move, _held, _pressed, _in_aim, _in_aim_world (no per-frame allocation).
func _read_input() -> void:
	var mv := Vector2.ZERO
	var at := false
	var sp := false
	var da := false
	_in_aim = Vector2.ZERO
	_in_aim_world = Vector2.INF
	if local_index == 0:
		mv.x = int(Input.is_physical_key_pressed(KEY_D)) - int(Input.is_physical_key_pressed(KEY_A))
		mv.y = int(Input.is_physical_key_pressed(KEY_S)) - int(Input.is_physical_key_pressed(KEY_W))
		at = Input.is_physical_key_pressed(KEY_J)
		sp = Input.is_physical_key_pressed(KEY_K)
		da = Input.is_physical_key_pressed(KEY_SPACE) or Input.is_physical_key_pressed(KEY_L)
		if touch:
			mv += touch.move
			at = at or touch.attack
			sp = sp or touch.special
			da = da or touch.dash
			var sa = touch.get("special_aim")
			if sa is Vector2:
				_in_aim = sa
	else:
		mv.x = int(Input.is_physical_key_pressed(KEY_RIGHT)) - int(Input.is_physical_key_pressed(KEY_LEFT))
		mv.y = int(Input.is_physical_key_pressed(KEY_DOWN)) - int(Input.is_physical_key_pressed(KEY_UP))
		at = Input.is_physical_key_pressed(KEY_KP_1) or Input.is_physical_key_pressed(KEY_COMMA)
		sp = Input.is_physical_key_pressed(KEY_KP_2) or Input.is_physical_key_pressed(KEY_PERIOD)
		da = Input.is_physical_key_pressed(KEY_KP_0) or Input.is_physical_key_pressed(KEY_SLASH)
	# Gamepad N drives local player N; the right stick aims the special.
	var pads := Input.get_connected_joypads()
	if local_index < pads.size():
		var d: int = pads[local_index]
		var stick := Vector2(Input.get_joy_axis(d, JOY_AXIS_LEFT_X), Input.get_joy_axis(d, JOY_AXIS_LEFT_Y))
		if stick.length() > 0.2:
			mv += stick
		var rs := Vector2(Input.get_joy_axis(d, JOY_AXIS_RIGHT_X), Input.get_joy_axis(d, JOY_AXIS_RIGHT_Y))
		if rs.length() > 0.3:
			_in_aim = rs.limit_length(1.0)
		at = at or Input.is_joy_button_pressed(d, JOY_BUTTON_X)
		sp = sp or Input.is_joy_button_pressed(d, JOY_BUTTON_Y)
		da = da or Input.is_joy_button_pressed(d, JOY_BUTTON_A) or Input.is_joy_button_pressed(d, JOY_BUTTON_RIGHT_SHOULDER)
	if local_index == 0 and _mouse_seen and _in_aim == Vector2.ZERO:
		_in_aim_world = get_global_mouse_position()
	_held["attack"] = at
	_held["special"] = sp
	_held["dash"] = da
	for k in _held:
		_pressed[k] = _held[k] and not _prev_held[k]
		_prev_held[k] = _held[k]
	_in_move = mv.limit_length(1.0)

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

func _swing_cd() -> float:
	return float(wdef["cd"]) / (1.0 + float(stats["w_speed"]) / 100.0)

func _simulate(delta: float) -> void:
	_read_input()
	var mv: Vector2 = _in_move
	# Input buffer: a press stays valid for a short window so combos and dash-cancels feel crisp.
	for k in _buffer_t:
		if _pressed[k]:
			_buffer_t[k] = 0.16
		_buffer_t[k] = maxf(0.0, _buffer_t[k] - delta)
		_pr[k] = _buffer_t[k] > 0.0 or _pressed[k]
	state_t += delta
	for g in _ghosts:
		g[2] -= delta
	attack_cd = max(0.0, attack_cd - delta)
	special_cd = max(0.0, special_cd - delta)
	iframes = max(0.0, iframes - delta)
	combo_window = max(0.0, combo_window - delta)
	if combo_window <= 0.0:
		combo = 0
	if dash_charges < 1 + int(stats["dash_charges"]):
		dash_recharge -= delta
		if dash_recharge <= 0.0:
			dash_charges += 1
			dash_recharge = 0.55

	if downed:
		state = "downed"
		vel = Vector2.ZERO
		aiming = false
		hop = 0.0
		charge = 0.0
		_update_revive(delta)
		return

	var speed: float = def["speed"] * (1.0 + stats["speed_mult"] / 100.0) * stats["speed_meta"]
	if aiming:
		speed *= 0.8
	if mv.length() > 0.1 and state in ["idle", "run"]:
		facing = mv.normalized()

	# Aimed special: press starts aiming, release casts (a quick tap casts at the auto-aim point).
	var aim_new := false
	if _pr["special"] and not aiming and special_cd <= 0.0 and state in ["idle", "run", "attack", "draw"]:
		aiming = true
		aim_new = true
		_buffer_t["special"] = 0.0
		if state == "draw":
			_set_state("idle")
			charge = 0.0
	if aiming:
		if _held["special"] or aim_new:
			_update_aim() # on release keep the last aimed point
		if not _held["special"]:
			aiming = false
			if state in ["idle", "run", "attack"]:
				_cast_special()

	if _pr["dash"] and dash_charges > 0 and state != "dash" and state != "special":
		dash_charges -= 1
		dash_recharge = 0.55
		var dir := mv.normalized() if mv.length() > 0.1 else facing
		facing = dir
		charge = 0.0
		_set_state("dash")
		iframes = 0.22
		vel = dir * speed * 3.4
		_buffer_t["dash"] = 0.0
		_ghost_timer = 0.0
		_act("dash", position, dir)
	elif _pr["attack"] and attack_cd <= 0.0 and state in ["idle", "run", "attack"]:
		_buffer_t["attack"] = 0.0
		facing = _aim(mv)
		if weapon_id == "bow":
			charge = 0.0
			_set_state("draw")
		else:
			_swing()

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
			if state_t > attack_len + 0.02:
				_set_state("idle")
		"draw":
			charge = minf(1.0, charge + delta * (1.0 + float(stats["w_charge"]) / 100.0) / DRAW_TIME)
			if mv.length() > 0.1:
				facing = _aim(mv)
			vel = vel.lerp(mv * speed * 0.45, min(1.0, 18.0 * delta))
			if not _held["attack"]:
				_loose_arrow()
		"special":
			vel = Vector2.ZERO
			if weapon_id == "spear":
				# Ember Leap: the heroine flies to the aimed point and lands on the hit frame.
				var k := clampf((state_t - 0.05) / maxf(0.05, special_hit - 0.05), 0.0, 1.0)
				var e := k * k * (3.0 - 2.0 * k)
				position = arena.resolve_collision(special_from.lerp(special_to, e), 16.0)
				hop = sin(k * PI) * 90.0 if k < 1.0 else 0.0
			if state_t > special_time:
				hop = 0.0
				_set_state("idle")
		"hurt":
			hop = 0.0
			vel = vel.move_toward(Vector2.ZERO, 1200 * delta)
			if state_t > 0.18:
				_set_state("idle")
		_:
			vel = vel.lerp(mv * speed, min(1.0, 18.0 * delta))
			_set_state("run" if mv.length() > 0.1 else "idle", false)

	position += vel * delta
	position = arena.resolve_collision(position, 16.0)

func _swing() -> void:
	combo = (combo + 1) % 3
	combo_window = 0.6 + _swing_cd()
	attack_cd = _swing_cd()
	attack_len = attack_cd
	_set_state("attack")
	var lunge: float = float(wdef["lunge"]) * (1.4 if combo == 0 else 1.0)
	if weapon_id == "shield" and combo == 0:
		# third strike: a charging shield rush
		lunge = 820.0 * (1.0 + float(stats["w_rush"]) / 250.0)
		attack_cd = _swing_cd() * 1.35
		attack_len = attack_cd
		iframes = maxf(iframes, 0.18)
	vel = facing * lunge
	_act("attack%d" % combo, position, facing)

## Bow: release the drawn arrow. Charge travels in aim.x so the host scales damage the same way.
func _loose_arrow() -> void:
	combo = 1
	attack_cd = _swing_cd()
	attack_len = 0.2
	_set_state("attack")
	vel = -facing * 90.0
	_act("shot", position, facing, Vector2(charge, 0.0))
	charge = 0.0

func _cast_special() -> void:
	var to := aim_point - position
	if to.length() > 8.0:
		facing = to.normalized()
	special_cd = special_cd_max
	special_from = position
	special_to = aim_point
	vel = Vector2.ZERO
	charge = 0.0
	if weapon_id == "spear":
		iframes = maxf(iframes, special_hit + 0.05) # airborne during the leap
	_set_state("special")
	_act("special", position, facing, aim_point)

## Landing point for the aimed special: touch drag / right stick offset, mouse, or auto-aim.
func _update_aim() -> void:
	var rng := aim_range()
	var p: Vector2
	if _in_aim != Vector2.ZERO:
		p = position + _in_aim * rng
	elif _in_aim_world != Vector2.INF:
		p = _in_aim_world
	else:
		p = _auto_aim_point(rng)
	aim_point = arena.resolve_collision(position + (p - position).limit_length(rng), 12.0)

func aim_range() -> float:
	return AIM_RANGE * (1.0 + float(stats["w_range"]) / 100.0)

func _auto_aim_point(rng: float) -> Vector2:
	var best := Vector2.INF
	var bs := INF
	for e in arena.enemies():
		if e.hp <= 0:
			continue
		var to: Vector2 = e.position - position
		var d := to.length()
		if d > rng + 60.0:
			continue
		var score := d + absf(facing.angle_to(to)) * 120.0
		if score < bs:
			bs = score
			best = e.position
	if best != Vector2.INF:
		return best
	return position + facing * minf(240.0, rng)

## Aim assist for touch: snap toward the nearest enemy in front, else use the stick.
func _aim(mv: Vector2) -> Vector2:
	var want := mv.normalized() if mv.length() > 0.1 else facing
	var best := Vector2.ZERO
	var reach := 520.0 if weapon_id == "bow" else 230.0
	var bd := reach * reach
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
		state_t = 0.0
	state = s

func _act(action: String, pos: Vector2, dir: Vector2, aim := Vector2.ZERO) -> void:
	seq += 1
	arena.hero_action_local(self, action, pos, dir, seq, aim)
	if Net.online:
		Net.hero_action.rpc(key, action, pos, dir, seq, aim)

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
	return [position.x, position.y, facing.x, facing.y, STATES.find(state), state_t, hp, max_hp, downed, combo, revive_progress, hop, charge]

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
	if sb.size() > 12:
		hop = sb[11]
		charge = sb[12]

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
	body.position.y = -hop
	if downed:
		body.play("death")
		return
	match state:
		"attack":
			if entered:
				body.set_speed_scale(1.0)
				var cd := _swing_cd()
				if weapon_id == "bow":
					body.play_timed("attack2", 0.24)
				elif weapon_id == "shield" and combo == 0:
					body.play_timed("attack3", 0.5)
				else:
					var an := "attack%d" % (3 if combo == 0 else combo)
					body.play_timed(an, cd * (1.55 if combo == 0 else 1.12))
		"draw":
			if entered:
				body.set_speed_scale(1.0)
				# the swing's wind-up doubles as the draw; its hit frame lands at a full draw
				var ht := body.get_event_time("attack1", "hit")
				var n := body.get_anim_length("attack1")
				var full := DRAW_TIME / (1.0 + float(stats.get("w_charge", 0.0)) / 100.0)
				body.play_timed("attack1", (full * n / ht) if ht > 0.0 else full * 2.0)
		"special":
			if entered:
				body.set_speed_scale(1.0)
				# time-fit so the anim's hit frame lands exactly when the effect triggers
				var ht := body.get_event_time("special", "hit")
				var n := body.get_anim_length("special")
				body.play_timed("special", (special_hit * n / ht) if ht > 0.0 else special_time)
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
	if aiming and state in ["idle", "run"] and controlled:
		var to := aim_point - position
		if to.length() > 20.0 and _in_move.length() < 0.1:
			facing = to.normalized()
	body.set_facing(facing)
	_drive_anim()
	body.flash = flash
	var blink := iframes > 0.0 and state != "dash" and state != "special" and not downed and int(anim_t * 20) % 2 == 0
	var a := 0.5 if blink else (0.6 if state == "dash" else 1.0)
	body.tint = Color(0.55, 0.55, 0.7, a) if downed else Color(1, 1, 1, a)

func _draw() -> void:
	var trim: Color = def["trim"]
	# Ground shadow and player ring (VFX only; the body is the painted sprite).
	var sh := 1.0 - clampf(hop / 160.0, 0.0, 0.5)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(sh, 0.42 * sh))
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

## Weapon smears drawn additively in the fx layer (light, not paint).
func _draw_weapon_fx(_trim: Color) -> void:
	var col: Color = wdef.get("color", _trim)
	var ang := facing.angle()
	var center := Vector2(0, -50 - hop)
	match state:
		"attack":
			match weapon_id:
				"bow":
					var k := clampf(state_t / 0.2, 0.0, 1.0)
					var a := 1.0 - k
					var tip := center + facing * (60.0 + 220.0 * k)
					fx.draw_line(center + facing * 30.0, tip, Color(col, 0.8 * a), 7.0)
					fx.draw_line(center + facing * 30.0, tip, Color(1, 1, 1, a), 2.5)
					fx.draw_circle(center + facing * 40.0, 22.0 * (1.0 - k * 0.5), Color(col, 0.5 * a))
				"shield":
					if combo == 0:
						# rush: streaks behind and a blazing shield face in front
						var k := clampf(state_t / attack_len, 0.0, 1.0)
						var a := 1.0 - k * k
						var perp := facing.orthogonal()
						for i in range(4):
							var o := perp * (-36.0 + 24.0 * i)
							fx.draw_line(center + o - facing * 40.0, center + o - facing * (120.0 + 20.0 * i), Color(col, 0.55 * a), 4.0)
						_shield_face(center + facing * 52.0, 44.0, ang, col, a)
					else:
						var k := clampf(state_t / attack_len, 0.0, 1.0)
						var a := 1.0 - k * k
						_smear(center, ang, deg_to_rad(80.0), 96.0 * reach_mult(), k, a, col)
						_shield_face(center + facing * (40.0 + 30.0 * k), 40.0, ang, col, a)
				_:
					var dur := attack_len
					var k := clampf(state_t / dur, 0.0, 1.0)
					var alpha := 1.0 - k * k
					var reach: float = float(wdef["reach"]) * reach_mult() * 0.88
					var arc := deg_to_rad(minf(float(wdef["arc"]) * 1.66, 170.0))
					if combo == 0:
						reach *= 1.15
					_smear(center, ang, arc, reach, k, alpha * (0.6 if weapon_id == "scythe" else 1.0), col)
					if weapon_id == "spear":
						var tip := center + facing * reach * (0.8 + 0.3 * (1.0 - k))
						fx.draw_line(center, tip, Color(1, 0.9, 0.6, alpha), 6.0)
					elif weapon_id == "scythe":
						# the chain: a whipping line out to the blade
						var bt := center + Vector2.RIGHT.rotated(ang - arc / 2 + arc * minf(1.0, k * 1.6)) * reach
						fx.draw_line(center, bt, Color(0.75, 0.6, 1.0, 0.7 * alpha), 3.0)
						fx.draw_circle(bt, 10.0, Color(1, 0.85, 1, alpha))
		"draw":
			# bow: light gathers at the arrow tip as the draw fills
			var c := charge
			var tip := center + facing * 46.0
			fx.draw_arc(center + facing * 10.0, 46.0, ang - 1.1, ang + 1.1, 18, Color(col, 0.35 + 0.5 * c), 3.0)
			fx.draw_circle(tip, 6.0 + 14.0 * c, Color(col, 0.35 + 0.45 * c))
			if c >= 1.0:
				var pulse := 0.5 + 0.5 * sin(anim_t * 24.0)
				fx.draw_arc(tip, 26.0 + 6.0 * pulse, 0, TAU, 24, Color(1, 1, 1, 0.8), 3.0)
		"special":
			var k := clampf(state_t / maxf(0.05, special_hit), 0.0, 1.0)
			if k < 1.0:
				# wind-up: a gathering ring of the weapon's light
				var r := 70.0 * (1.0 - k) + 18.0
				fx.draw_arc(center, r, 0, TAU, 32, Color(col, 0.35 + 0.6 * k), 4.0)
				fx.draw_circle(center + facing * 30.0, 10.0 + 18.0 * k, Color(col, 0.5 * k))
				if weapon_id == "spear":
					# ember trail from the airborne heroine down to her shadow
					for i in range(4):
						fx.draw_circle(Vector2(0, -30.0 - hop * (1.0 - i * 0.25)), 22.0 - i * 4.0, Color(col, 0.25 * (1.0 - i * 0.2)))

func _smear(center: Vector2, ang: float, arc: float, reach: float, k: float, alpha: float, col: Color) -> void:
	# Bold smear crescent: bright core, white edge, fades fast.
	var steps := 12
	_pts.resize((steps + 1) * 2)
	for i in range(steps + 1):
		_pts[i] = center + Vector2.RIGHT.rotated(ang - arc / 2 + arc * i / steps) * reach
	for i in range(steps + 1):
		_pts[steps + 1 + i] = center + Vector2.RIGHT.rotated(ang - arc / 2 + arc * (steps - i) / steps) * (reach * ((0.62 if weapon_id == "scythe" else 0.35) + 0.3 * k))
	fx.draw_colored_polygon(_pts, Color(col.lightened(0.1), 0.85 * alpha))
	_edge.resize(steps + 1)
	for i in range(steps + 1):
		_edge[i] = _pts[i]
	fx.draw_polyline(_edge, Color(1, 1, 1, alpha), 5.0, true)

func _shield_face(at: Vector2, r: float, ang: float, col: Color, a: float) -> void:
	fx.draw_set_transform(at, ang, Vector2(0.45, 1.0))
	fx.draw_circle(Vector2.ZERO, r, Color(col, 0.35 * a))
	fx.draw_arc(Vector2.ZERO, r, 0, TAU, 28, Color(1, 1, 1, 0.9 * a), 4.0)
	fx.draw_set_transform(Vector2.ZERO)

var _pts := PackedVector2Array()
var _edge := PackedVector2Array()
