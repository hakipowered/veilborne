extends Node2D
## One run through the Gilded Catacombs: rooms, waves, boons, boss, co-op sync.

signal run_finished(victory: bool)

const INTERP_DELAY_MS := 100
const HeroScript := preload("res://entities/hero.gd")
const HudScript := preload("res://ui/hud.gd")
const MAX_PARTICLES := 260
const MAX_TEXTS := 40
const MAX_PROJECTILES := 120
const MAX_CASTS := 24
const MAX_HSHOTS := 60
const RETICLE_TEX := preload("res://art/fx/reticle.webp")
const ARCH_TEX := preload("res://art/fx/veil_arch.webp")
const VTheme = preload("res://ui/theme.gd")

const ROOMS := [
	{"floor": "catacomb", "name": "Gilded Catacombs I", "waves": [["shade", "shade", "shade"], ["shade", "spitter", "shade", "spitter"]]},
	{"floor": "catacomb", "name": "Gilded Catacombs II", "waves": [["spitter", "spitter", "shade", "shade"], ["brute", "shade", "shade"]]},
	{"floor": "catacomb", "name": "Gilded Catacombs III", "waves": [["brute", "spitter", "spitter"], ["shade", "shade", "shade", "shade", "spitter"]]},
	{"floor": "catacomb", "name": "Gilded Catacombs IV", "waves": [["brute", "brute", "spitter"], ["shade", "shade", "spitter", "spitter", "brute"]]},
	{"floor": "throne", "name": "Throne of the Hollow Regent", "boss": true, "waves": []},
]
const KINDS := ["shade", "spitter", "brute", "regent"]

var EnemyScript: GDScript
var env: Node2D
var entities: Node2D
var overlay: Node2D
var camera: Camera2D
var hud: CanvasLayer

var hero_nodes := {} ## key -> hero
var enemy_nodes := {} ## eid -> enemy
var next_eid := 1
var room_index := 0
var room_half := Vector2(900, 480)
var wave_index := 0
var wave_delay := 0.0
var room_clear := false
var door_open := false
var boss_pending := false
var run_over := false
var _snap_timer := 0.0
var _shake := 0.0
var _rng := RandomNumberGenerator.new()
var _pending_picks := 0

var projectiles: Array = [] ## {id, pos, vel, dmg, color, r, life}
var next_proj := 1
var slams: Array = [] ## {pos, r, t, delay, dmg, color}
var particles: Array = [] ## [pos, vel, life, max_life, color, size]
var texts: Array = [] ## [pos, text, color, life]
var arcs: Array = [] ## lightning [a, b, life]
var casts: Array = [] ## aimed specials in flight (see _start_cast)
var hshots: Array = [] ## heroine arrows
var pools: Array = [] ## burning ground [pos, r, dps, life, hero, mode, tick, n, seq]
var _rings: Array = [] ## impact rings [pos, r, life, max_life, color]
var _ecache: Array = [] ## enemies alive this frame (rebuilt once per physics frame)
var _targets: Array = []
var groundfx: Node2D ## additive layer on the floor: reticles, telegraphs, impact rings
var airfx: Node2D ## additive layer above characters: blade glows, arrows
## Rewards / exits ("choose your next chamber")
var room_reward := "boon" ## reward granted when THIS chamber is cleared
var door_rewards: Array = [] ## reward per exit, parallel to door_points
var door_points: Array = []
var _arch: Sprite2D
var _door_req_t := 0.0
var _icons := {}

func _ready() -> void:
	EnemyScript = load("res://entities/enemy.gd")
	Net.arena = self
	env = preload("res://scenes/environment.gd").new()
	add_child(env)
	var add_mat := CanvasItemMaterial.new()
	add_mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	groundfx = Node2D.new()
	groundfx.material = add_mat
	groundfx.draw.connect(_draw_groundfx)
	add_child(groundfx)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	_arch = Sprite2D.new()
	_arch.texture = ARCH_TEX
	_arch.centered = false
	_arch.offset = Vector2(-ARCH_TEX.get_width() * 0.5, -ARCH_TEX.get_height() + 18.0)
	_arch.scale = Vector2(0.78, 0.78)
	_arch.visible = false
	entities.add_child(_arch)
	overlay = Node2D.new()
	overlay.z_index = 5
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
	airfx = Node2D.new()
	airfx.z_index = 6
	airfx.material = add_mat
	airfx.draw.connect(_draw_airfx)
	add_child(airfx)
	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.zoom = Vector2(1.1, 1.1)
	add_child(camera)
	camera.make_current()
	hud = HudScript.new()
	add_child(hud)
	hud.arena = self

func _exit_tree() -> void:
	if Net.arena == self:
		Net.arena = null
	Engine.time_scale = 1.0

func setup(players: Array) -> void:
	_rng.seed = Game.run_seed
	for p in players:
		var key := "p%d_%d" % [int(p["peer"]), int(p["local_index"])]
		var h: Node2D = HeroScript.new()
		var controlled: bool = int(p["peer"]) == Net.my_id()
		var wp := String(p.get("weapon", ""))
		var asp := int(p.get("aspect", 0))
		if controlled and int(p["local_index"]) == 0 and wp == "":
			wp = Game.weapon_for(String(p["hero"]))
			asp = Game.run_aspect
		h.setup(key, p["hero"], controlled, int(p["local_index"]), self, wp, asp)
		entities.add_child(h)
		hero_nodes[key] = h
		if controlled:
			hud.add_local_hero(h)
	hud.build()
	for h in hero_nodes.values():
		if h.controlled and int(h.local_index) == 0:
			h.touch = hud.touch
		h.sync_boons()
	_load_room(0)

# ---------------------------------------------------------------- audio

var _audio: Node = null
var _enemy_states := {} ## eid -> last state code (to voice enemy actions on every device)
var _step_t := 0.0

func sfx(name: String, pos := Vector2.INF) -> void:
	if _audio == null:
		_audio = get_node_or_null("/root/Audio")
	if _audio:
		_audio.sfx(name, pos)

func _music(track: String) -> void:
	if _audio == null:
		_audio = get_node_or_null("/root/Audio")
	if _audio:
		_audio.music(track)

## Plays enemy action sounds from state changes, so host and clients hear the same thing.
func _voice_enemies() -> void:
	for e in enemy_nodes.values():
		if not is_instance_valid(e):
			continue
		var st: int = e.state
		var prev: int = _enemy_states.get(e.eid, -1)
		if st == prev:
			continue
		_enemy_states[e.eid] = st
		if prev == -1 and e.kind == "regent":
			sfx("regent_roar", e.position)
			shake(14.0)
		match e.kind:
			"shade":
				if st == 3: sfx("shade_lunge", e.position)
			"spitter":
				if st == 3: sfx("spitter_shoot", e.position)
			"brute":
				if st == 2: sfx("brute_slam", e.position)
			"regent":
				match st:
					6: sfx("regent_burst", e.position)
					8: sfx("regent_charge", e.position)
					11: sfx("regent_summon", e.position)

# ---------------------------------------------------------------- queries

func is_authority() -> bool:
	return Net.is_host()

func heroes() -> Array:
	var out := []
	for h in hero_nodes.values():
		if is_instance_valid(h):
			out.append(h)
	return out

func enemies() -> Array:
	var out := []
	for e in enemy_nodes.values():
		if is_instance_valid(e):
			out.append(e)
	return out

func nearest_hero(pos: Vector2) -> Node:
	var best: Node = null
	var bd := INF
	for h in hero_nodes.values():
		if is_instance_valid(h) and not h.downed:
			var d: float = pos.distance_squared_to(h.position)
			if d < bd:
				bd = d
				best = h
	return best

func resolve_collision(pos: Vector2, radius: float) -> Vector2:
	return env.resolve(pos, radius)

# ---------------------------------------------------------------- rooms

func _load_room(idx: int, reward := "") -> void:
	room_index = idx
	room_reward = reward if reward != "" else ("boon" if idx == 0 else "")
	door_rewards.clear()
	door_points.clear()
	casts.clear()
	hshots.clear()
	pools.clear()
	_rings.clear()
	if _arch:
		_arch.visible = false
	Game.run_room = idx
	var room: Dictionary = ROOMS[idx]
	env.build(room["floor"], idx, Game.run_seed + idx)
	env.add_ysorted_props_to(entities)
	room_half = env.get_bounds_half()
	for e in enemy_nodes.values():
		if is_instance_valid(e):
			e.queue_free()
	enemy_nodes.clear()
	projectiles.clear()
	slams.clear()
	wave_index = 0
	wave_delay = 1.2
	room_clear = false
	door_open = false
	boss_pending = room.get("boss", false)
	var i := 0
	var n := hero_nodes.size()
	var start: Vector2 = env.get_player_start()
	for h in heroes():
		h.position = start + (Vector2(-120 + 240.0 * i / max(1, n - 1), 0) if n > 1 else Vector2.ZERO)
		h.vel = Vector2.ZERO
		h._buffer.clear()
		i += 1
	camera.position = start
	camera.reset_smoothing()
	hud.set_room_name("%s  ·  %d/%d" % [room["name"], idx + 1, ROOMS.size()])
	_music("boss" if room.get("boss", false) else "catacombs")
	if boss_pending:
		wave_delay = 999.0
		_play_dialogue("PRE_BOSS", func():
			if is_authority() and boss_pending:
				wave_delay = 0.6)

func _play_dialogue(const_name: String, done: Callable) -> void:
	var main := get_tree().root.get_node_or_null("Main")
	var story = load("res://data/story.gd")
	var lines = null
	if story:
		lines = story.get_script_constant_map().get(const_name)
	if main and main.has_method("play_dialogue") and lines is Array:
		main.play_dialogue(lines, done)
	else:
		done.call()

func _update_waves(delta: float) -> void:
	if room_clear or run_over:
		return
	var alive := 0
	for e in enemy_nodes.values():
		if is_instance_valid(e):
			alive += 1
	if alive > 0:
		return
	wave_delay -= delta
	if wave_delay > 0.0:
		return
	var room: Dictionary = ROOMS[room_index]
	if boss_pending:
		boss_pending = false
		spawn_enemy("regent", Vector2(0, -room_half.y * 0.35))
		wave_delay = 0.5
		return
	if room.get("boss", false):
		return # boss dead is handled in on_enemy_killed
	var waves: Array = room["waves"]
	if wave_index < waves.size():
		for kind in waves[wave_index]:
			var sp: Array = env.get_spawn_points()
			var pos := Vector2.ZERO
			if sp.size() > 0:
				pos = sp[_rng.randi() % sp.size()] + Vector2(_rng.randf_range(-60, 60), _rng.randf_range(-30, 30))
			else:
				var ang := _rng.randf() * TAU
				pos = Vector2(cos(ang) * room_half.x * 0.55, sin(ang) * room_half.y * 0.45)
			pos = resolve_collision(pos, 30.0)
			spawn_enemy(kind, pos)
		wave_index += 1
		wave_delay = 0.9
	else:
		_broadcast("clear", [])

## Host: move everyone through exit `door` (its reward is granted when the next chamber is cleared).
func try_advance(door := 0) -> void:
	if not room_clear or run_over:
		return
	if room_index + 1 >= ROOMS.size():
		return
	var reward := ""
	if door >= 0 and door < door_rewards.size():
		reward = String(door_rewards[door])
	if reward == "boss":
		reward = ""
	_broadcast("room", [room_index + 1, reward])

# ---------------------------------------------------------------- spawning (host)

func _hp_scale() -> float:
	return (1.0 + 0.65 * (hero_nodes.size() - 1)) * (1.0 + room_index * 0.12)

func spawn_enemy(kind: String, pos: Vector2) -> Node:
	if not is_authority() or EnemyScript == null:
		return null
	if enemy_nodes.size() >= 24:
		return null
	var e = _make_enemy(next_eid, kind)
	next_eid += 1
	e.position = resolve_collision(pos, 20.0)
	spark(e.position + Vector2(0, -30), Color(0.8, 0.5, 1.0), 14)
	return e

func _make_enemy(eid: int, kind: String) -> Node:
	var e: Node2D = EnemyScript.new()
	e.setup(eid, kind, self, _hp_scale())
	entities.add_child(e)
	enemy_nodes[eid] = e
	return e

func spawn_projectile(pos: Vector2, vel: Vector2, dmg: float, color: Color, radius := 10.0) -> void:
	if not is_authority() or projectiles.size() >= MAX_PROJECTILES:
		return
	_broadcast("proj", [next_proj, pos, vel, dmg, color, radius])
	next_proj += 1

func telegraph_slam(pos: Vector2, radius: float, delay: float, dmg: float, color: Color) -> void:
	if not is_authority():
		return
	_broadcast("slam", [pos, radius, delay, dmg, color])

func remove_projectile(id: int) -> void:
	for i in range(projectiles.size()):
		if projectiles[i]["id"] == id:
			projectiles.remove_at(i)
			return

## Runs an event locally and sends it to every other peer.
func _broadcast(kind: String, args: Array) -> void:
	net_event(kind, args)
	if Net.online:
		Net.world_event.rpc(kind, args)

# ---------------------------------------------------------------- combat

const MODE_AUTH := 0    ## host: applies damage
const MODE_PREDICT := 1 ## attacker's own client: flashes + numbers right away
const MODE_VISUAL := 2  ## everyone else: effect visuals only (host "hit" events show damage)

func _action_sound(hero: Node, action: String, pos: Vector2) -> void:
	var w: Dictionary = hero.wdef
	if action.begins_with("attack") or action == "shot":
		sfx(String(w["swing"]), pos)
	elif action == "special":
		sfx(String(w["cast"]), pos)
	elif action == "dash":
		sfx("dash", pos)

func hero_action_local(hero: Node, action: String, pos: Vector2, dir: Vector2, seq: int, aim := Vector2.ZERO) -> void:
	_action_sound(hero, action, pos)
	_resolve_action(hero, action, pos, dir, seq, aim, MODE_AUTH if is_authority() else MODE_PREDICT)

func _crit(hero_key: String, seq: int, eid: int, chance: float) -> bool:
	return (hash("%s:%d:%d" % [hero_key, seq, eid]) & 0xffff) % 100 < int(chance)

## One weapon hit on one enemy: applied on the host, predicted on the attacker's client.
func _apply_hit(hero: Node, e: Node, amount: float, salt: int, mode: int, from: Vector2, pull := Vector2.INF, pull_strength := 0.0) -> bool:
	var st: Dictionary = hero.stats
	var crit := _crit(hero.key, salt, e.eid, st["crit"])
	amount *= 2.0 if crit else 1.0
	var hit_pos: Vector2 = e.position + Vector2(0, -40)
	spark(hit_pos, Color(1, 0.95, 0.7) if not crit else Color(1, 0.4, 0.3), 10 if not crit else 18)
	sfx("hit_crit" if crit else "hit_flesh", e.position)
	if mode == MODE_PREDICT:
		e.flash_hit()
		_damage_number(hit_pos, amount, crit)
	elif mode == MODE_AUTH:
		e.take_damage(amount, crit, from, hero.key)
		if pull != Vector2.INF and e.has_method("pull"):
			e.pull(pull, pull_strength)
		if st["burn"] > 0 and e.has_method("apply_burn"):
			e.apply_burn(float(st["burn"]))
		_damage_number(hit_pos, amount, crit)
		if Net.online:
			Net.world_event.rpc("hit", [e.eid, amount, crit, hero.key])
	return crit

## Applies (host), predicts (attacker's client) or just shows (others) a heroine's action.
func _resolve_action(hero: Node, action: String, pos: Vector2, dir: Vector2, seq: int, aim: Vector2, mode: int) -> void:
	if action == "special":
		_start_cast(hero, pos, dir, aim, seq, mode)
		return
	if action == "shot":
		_spawn_arrows(hero, pos, dir, aim.x, seq, mode)
		return
	if mode == MODE_VISUAL:
		return
	var st: Dictionary = hero.stats
	var w: String = hero.weapon_id
	var wd: Dictionary = hero.wdef
	var targets: Array = _targets
	targets.clear()
	var dmg := 0.0
	var origin := pos + Vector2(0, -20)
	var pull := Vector2.INF
	var pull_s := 0.0
	if action.begins_with("attack"):
		var finisher := action == "attack0"
		dmg = hero.attack_damage("attack", finisher)
		if w == "shield" and finisher:
			# shield rush: everything along the charge lane
			var lane := 170.0 * (1.0 + float(st["w_rush"]) / 250.0)
			for e in _ecache:
				if e.hp > 0 and _seg_dist(e.position, pos, pos + dir * lane) <= 60.0 + e.radius:
					targets.append(e)
		else:
			var reach: float = float(wd["reach"]) * hero.reach_mult() * (1.15 if finisher else 1.0)
			var half_arc := deg_to_rad(float(wd["arc"]))
			for e in _ecache:
				if e.hp <= 0:
					continue
				var to: Vector2 = e.position - origin
				var d := to.length()
				if d <= reach + e.radius and (d < 40.0 or absf(dir.angle_to(to)) <= half_arc):
					targets.append(e)
			if w == "scythe" and (finisher or float(st["w_yank"]) > 0.0):
				pull = pos + dir * 50.0
				pull_s = 520.0 + 260.0 * float(st["w_yank"]) + (300.0 if finisher else 0.0)
	elif action == "dash":
		var shock := float(st["dash_shock"])
		var strike := float(st["w_dash_strike"])
		if shock <= 0.0 and strike <= 0.0:
			return
		dmg = (shock + strike) * st["dmg_meta"]
		for e in _ecache:
			if e.hp <= 0:
				continue
			var near: bool = shock > 0.0 and e.position.distance_to(pos) <= 110.0 + e.radius
			var lane: bool = strike > 0.0 and _seg_dist(e.position, pos, pos + dir * 190.0) <= 55.0 + e.radius
			if near or lane:
				targets.append(e)
		if strike > 0.0:
			_rings.append([pos + dir * 150.0, 50.0, 0.25, 0.25, hero.wdef["color"]])
	if targets.is_empty():
		return
	var big := false
	for e in targets:
		big = _apply_hit(hero, e, dmg, seq, mode, pos, pull, pull_s) or big
	if mode == MODE_AUTH and st["chain"] > 0:
		_chain(hero, targets[0], dmg * 0.5, int(st["chain"]))
	if hero.controlled:
		shake(6.0 if big else 3.0)
		if big and not Net.online and hero_nodes.size() == 1:
			_hitstop(0.05)

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var l2 := ab.length_squared()
	if l2 < 0.001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / l2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

# ---------------------------------------------------------------- aimed specials (every device runs the same timeline)

## Radius of a heroine's special at its landing point (for the reticle).
func special_radius(hero: Node) -> float:
	var am: float = hero.area_mult()
	match String(hero.weapon_id):
		"spear": return 125.0 * am
		"twin": return 100.0 * am
		"bow": return 135.0 * am
		"shield": return (115.0 if float(hero.stats["w_anchor"]) > 0.0 else 75.0) * am
		"scythe": return 175.0 * am
	return 100.0

func _start_cast(hero: Node, pos: Vector2, dir: Vector2, aim: Vector2, seq: int, mode: int) -> void:
	if aim == Vector2.ZERO:
		aim = pos + dir * 240.0
	var st: Dictionary = hero.stats
	var c := {"kind": String(hero.weapon_id), "hero": hero, "from": pos, "to": aim, "dir": dir, "t": 0.0,
		"hit": float(hero.special_hit), "seq": seq, "mode": mode, "dmg": hero.attack_damage("special"),
		"r": special_radius(hero), "stage": 0, "tick": 0.0, "n": 0, "pos": pos, "hits": {},
		"color": hero.wdef["color"], "local": hero.controlled, "life": 6.0, "bounces": 0, "target": null,
		"twice": float(st["w_twice"]), "pool": float(st["w_pool"]), "whirl": float(st["w_whirl"]),
		"ret": float(st["w_return"]), "pulses": 3 + int(st["w_pulses"]), "anchor": float(st["w_anchor"]),
		"ricochet": 2 + int(st["w_ricochet"]), "soul": float(st["w_soul"]), "det": float(st["w_detonate"])}
	if casts.size() >= MAX_CASTS:
		casts.pop_front()
	casts.append(c)
	if c["kind"] == "twin" and float(st["w_multi"]) > 0.0:
		# Eclipse: a second crescent mirrored across the aim line
		var perp := (aim - pos).normalized().orthogonal() * 70.0
		c["to"] = aim + perp
		var c2 := c.duplicate()
		c2["hits"] = {}
		c2["to"] = aim - perp
		c2["seq"] = seq + 50000
		casts.append(c2)

func _update_casts(delta: float) -> void:
	var i := casts.size() - 1
	while i >= 0:
		var c: Dictionary = casts[i]
		var hero = c["hero"]
		c["t"] += delta
		c["life"] -= delta
		var done: bool = c["life"] <= 0.0 or not is_instance_valid(hero)
		if not done:
			match String(c["kind"]):
				"spear": done = _cast_slam(c, hero, delta)
				"twin": done = _cast_crescent(c, hero, delta)
				"bow": done = _cast_volley(c, hero, delta)
				"shield": done = _cast_aegis(c, hero, delta)
				"scythe": done = _cast_vortex(c, hero, delta)
				_: done = true
		if done:
			casts.remove_at(i)
		i -= 1
	i = pools.size() - 1
	while i >= 0:
		var p: Array = pools[i]
		p[3] -= delta
		p[6] -= delta
		if p[6] <= 0.0 and is_instance_valid(p[4]):
			p[6] = 0.3
			p[7] += 1
			if int(p[5]) != MODE_VISUAL:
				for e in _ecache:
					if e.hp > 0 and _in_ellipse(e.position, p[0], p[1] + e.radius):
						_apply_hit(p[4], e, p[2] * 0.3, int(p[8]) * 97 + p[7], p[5], p[0])
		if p[3] <= 0.0 or not is_instance_valid(p[4]):
			pools.remove_at(i)
		i -= 1
	i = _rings.size() - 1
	while i >= 0:
		_rings[i][2] -= delta
		if _rings[i][2] <= 0.0:
			_rings.remove_at(i)
		i -= 1

## Ground-plane test (the floor is drawn squashed 0.5 vertically).
static func _in_ellipse(p: Vector2, c: Vector2, r: float) -> bool:
	var d := p - c
	d.y *= 2.0
	return d.length_squared() <= r * r

## Hits everything in the ring at `at` (ground ellipse). Returns how many were caught.
func _area_hit(c: Dictionary, hero: Node, at: Vector2, r: float, dmg: float, salt: int, once := false, pull := Vector2.INF, pull_s := 0.0) -> int:
	var n := 0
	if int(c["mode"]) == MODE_VISUAL:
		return 0
	var hits: Dictionary = c["hits"]
	for e in _ecache:
		if e.hp <= 0 or not _in_ellipse(e.position, at, r + e.radius):
			continue
		if once:
			if hits.has(e.eid):
				continue
			hits[e.eid] = true
		_apply_hit(hero, e, dmg, salt, c["mode"], at, pull, pull_s)
		n += 1
	return n

func _impact(c: Dictionary, at: Vector2, r: float, strength: float) -> void:
	var col: Color = c["color"]
	_rings.append([at, r, 0.45, 0.45, col])
	_rings.append([at, r * 0.55, 0.3, 0.3, Color(1, 1, 1)])
	spark(at + Vector2(0, -20), col, int(18 + 14 * strength))
	spark(at + Vector2(0, -30), Color(1, 0.95, 0.8), 10)
	sfx("slam_impact", at)
	if c["local"]:
		shake(8.0 + 8.0 * strength)
		_hitstop(0.06)
	else:
		shake(3.0 + 3.0 * strength)

## Kaela-style spear: the heroine leaps (hero.gd moves her) and slams the aimed point.
func _cast_slam(c: Dictionary, hero: Node, _delta: float) -> bool:
	var t: float = c["t"]
	var hit: float = c["hit"]
	if c["stage"] == 0 and t >= hit:
		c["stage"] = 1
		_impact(c, c["to"], c["r"], 1.0)
		sfx("brute_slam", c["to"])
		_area_hit(c, hero, c["to"], c["r"], c["dmg"], c["seq"] * 8)
		if c["pool"] > 0.0:
			pools.append([c["to"], c["r"] * 0.8, c["pool"], 2.2, hero, c["mode"], 0.15, 0, c["seq"]])
	if c["stage"] == 1 and c["twice"] > 0.0 and t >= hit + 0.32:
		c["stage"] = 2
		_impact(c, c["to"], c["r"] * 0.85, 0.6)
		_area_hit(c, hero, c["to"], c["r"] * 0.85, c["dmg"] * c["twice"] / 100.0, c["seq"] * 8 + 1)
	return t > hit + (0.75 if c["twice"] > 0.0 else 0.45)

## Moving projectile helper: moves c.pos toward `goal`; true when it arrives.
func _fly(c: Dictionary, goal: Vector2, speed: float, delta: float) -> bool:
	var p: Vector2 = c["pos"]
	var to := goal - p
	var step := speed * delta
	if to.length() <= step:
		c["pos"] = goal
		return true
	c["pos"] = p + to / to.length() * step
	return false

## Twin blades: a crescent flies to the point, whirls there, and (Homeward) flies back.
func _cast_crescent(c: Dictionary, hero: Node, delta: float) -> bool:
	var t: float = c["t"]
	match int(c["stage"]):
		0:
			if t >= c["hit"]:
				c["stage"] = 1
				c["pos"] = c["from"] + Vector2(0, 0)
		1:
			var arrived := _fly(c, c["to"], 1300.0, delta)
			_area_hit(c, hero, c["pos"], 50.0, c["dmg"] * 0.5, c["seq"] * 64, true)
			if arrived:
				c["stage"] = 2
				c["tick"] = 0.0
				c["n"] = 0
				c["t2"] = 0.0
				_rings.append([c["to"], c["r"], 0.3, 0.3, c["color"]])
				sfx("special_moon", c["to"])
		2:
			c["t2"] += delta
			c["tick"] -= delta
			if c["tick"] <= 0.0:
				c["tick"] = 0.16
				c["n"] += 1
				_area_hit(c, hero, c["to"], c["r"], c["dmg"] * 0.3, c["seq"] * 64 + 1 + c["n"])
				spark(c["to"] + Vector2(0, -30), c["color"], 4)
			if c["t2"] >= 0.7 * (1.0 + c["whirl"] / 100.0):
				if c["ret"] > 0.0:
					c["stage"] = 3
					c["hits"] = {}
				else:
					return true
		3:
			var home: Vector2 = hero.position
			_area_hit(c, hero, c["pos"], 55.0, c["dmg"] * 0.5 * c["ret"] / 100.0, c["seq"] * 64 + 40, true)
			if _fly(c, home, 1400.0, delta):
				return true
	return false

## Bow: an arrow arcs up and a volley rains on the point in waves.
func _cast_volley(c: Dictionary, hero: Node, _delta: float) -> bool:
	var t: float = c["t"]
	var land: float = c["hit"] + 0.35
	if c["stage"] == 0 and t >= c["hit"]:
		c["stage"] = 1
		spark(c["from"] + Vector2(0, -90), c["color"], 8)
	if c["stage"] >= 1 and t >= land + 0.13 * (c["stage"] - 1):
		var k: int = c["stage"]
		if k - 1 < c["pulses"]:
			c["stage"] = k + 1
			_area_hit(c, hero, c["to"], c["r"], c["dmg"] * 0.55, c["seq"] * 16 + k)
			var off: Vector2 = Vector2(randf_range(-0.5, 0.5), randf_range(-0.25, 0.25)) * float(c["r"])
			spark(c["to"] + off, c["color"], 8)
			sfx("projectile_hit", c["to"])
			if k == 1:
				_impact(c, c["to"], c["r"], 0.6)
		else:
			return t > land + 0.13 * c["pulses"] + 0.3
	return false

## Shield: thrown to the point, then either ricochets between foes or lodges there spinning; then returns.
func _cast_aegis(c: Dictionary, hero: Node, delta: float) -> bool:
	var t: float = c["t"]
	match int(c["stage"]):
		0:
			if t >= c["hit"]:
				c["stage"] = 1
		1:
			var arrived := _fly(c, c["to"], 1150.0, delta)
			_area_hit(c, hero, c["pos"], 55.0, c["dmg"] * 0.6, c["seq"] * 64, true)
			if arrived:
				_impact(c, c["to"], c["r"], 0.7)
				c["hits"] = {}
				_area_hit(c, hero, c["to"], c["r"], c["dmg"], c["seq"] * 64 + 1, true)
				if c["anchor"] > 0.0:
					c["stage"] = 3
					c["t2"] = 0.0
					c["tick"] = 0.1
				else:
					c["stage"] = 2
					c["hits"] = {}
		2:
			# ricochet: hop to the nearest foe not yet struck
			var tgt = c["target"]
			if tgt == null or not is_instance_valid(tgt) or tgt.hp <= 0:
				c["target"] = null
				if c["bounces"] >= c["ricochet"]:
					c["stage"] = 4
				else:
					var best = null
					var bd := 380.0 * 380.0
					var p: Vector2 = c["pos"]
					var hits: Dictionary = c["hits"]
					for e in _ecache:
						if e.hp <= 0 or hits.has(e.eid):
							continue
						var d: float = e.position.distance_squared_to(p)
						if d < bd and d > 100.0:
							bd = d
							best = e
					if best == null:
						c["stage"] = 4
					else:
						c["target"] = best
			else:
				if _fly(c, tgt.position, 1250.0, delta):
					c["hits"][tgt.eid] = true
					c["bounces"] += 1
					c["target"] = null
					spark(tgt.position + Vector2(0, -40), c["color"], 10)
					sfx("slam_impact", tgt.position)
					if int(c["mode"]) != MODE_VISUAL:
						_apply_hit(hero, tgt, c["dmg"] * 0.7, c["seq"] * 64 + 2 + c["bounces"], c["mode"], c["pos"])
		3:
			# Bastion: lodged and spinning, grinding everything around it
			c["t2"] += delta
			c["tick"] -= delta
			if c["tick"] <= 0.0:
				c["tick"] = 0.2
				c["n"] += 1
				_area_hit(c, hero, c["to"], c["r"], c["dmg"] * 0.28, c["seq"] * 64 + 10 + c["n"])
				spark(c["to"] + Vector2(0, -25), c["color"], 3)
			if c["t2"] >= c["anchor"]:
				c["stage"] = 4
		4:
			if _fly(c, hero.position, 1400.0, delta):
				return true
	return false

## Chain scythe: hurled to the point, spins into a vortex that drags foes in, then bursts.
func _cast_vortex(c: Dictionary, hero: Node, delta: float) -> bool:
	var t: float = c["t"]
	match int(c["stage"]):
		0:
			if t >= c["hit"]:
				c["stage"] = 1
		1:
			if _fly(c, c["to"], 1200.0, delta):
				c["stage"] = 2
				c["t2"] = 0.0
				c["tick"] = 0.0
				_rings.append([c["to"], c["r"], 0.35, 0.35, c["color"]])
		2:
			c["t2"] += delta
			c["tick"] -= delta
			var dur: float = 1.0 * (1.0 + c["whirl"] / 100.0)
			if c["tick"] <= 0.0:
				c["tick"] = 0.15
				c["n"] += 1
				var caught := _area_hit(c, hero, c["to"], c["r"], c["dmg"] * 0.45, c["seq"] * 64 + c["n"], false, c["to"], 260.0 * (1.0 + c["whirl"] / 200.0))
				if caught > 0 and c["soul"] > 0.0 and hero.controlled and c["n"] % 3 == 1:
					hero.heal(c["soul"] * caught)
			if c["t2"] >= dur:
				var dm: float = c["dmg"] * (1.0 + 2.0 * c["det"] / 100.0)
				_impact(c, c["to"], c["r"], 1.0 if c["det"] > 0.0 else 0.5)
				_area_hit(c, hero, c["to"], c["r"], dm, c["seq"] * 64 + 60)
				c["stage"] = 3
		3:
			if _fly(c, hero.position, 1500.0, delta):
				return true
	return false

# ---------------------------------------------------------------- bow arrows (every device simulates; host damages)

func _spawn_arrows(hero: Node, pos: Vector2, dir: Vector2, charge: float, seq: int, mode: int) -> void:
	var st: Dictionary = hero.stats
	var full := charge >= 0.999
	var dmg: float = hero.attack_damage("attack") * (1.0 + 1.6 * clampf(charge, 0.0, 1.0))
	var pierce: int = (1 + int(st["w_pierce"])) if full else mini(int(st["w_pierce"]), 3)
	var speed := 1500.0 if full else 1150.0
	var n := 1 + (int(st["w_split"]) if full else 0)
	for k in range(n):
		if hshots.size() >= MAX_HSHOTS:
			hshots.pop_front()
		var off := 0.0
		if k > 0:
			off = deg_to_rad(9.0 * ((k + 1) / 2)) * (1.0 if k % 2 == 1 else -1.0)
		var d := dir.rotated(off)
		hshots.append({"pos": pos + d * 30.0, "vel": d * speed, "dmg": dmg, "pierce": pierce, "life": 0.62,
			"hero": hero, "mode": mode, "seq": seq * 8 + k, "hits": {}, "full": full, "color": hero.wdef["color"]})

func _update_hshots(delta: float) -> void:
	var i := hshots.size() - 1
	while i >= 0:
		var s: Dictionary = hshots[i]
		var hero = s["hero"]
		s["pos"] += s["vel"] * delta
		s["life"] -= delta
		var dead: bool = s["life"] <= 0.0 or not is_instance_valid(hero) or resolve_collision(s["pos"], 0.0) != s["pos"]
		if not dead and int(s["mode"]) != MODE_VISUAL:
			var hits: Dictionary = s["hits"]
			for e in _ecache:
				if e.hp <= 0 or hits.has(e.eid):
					continue
				if e.position.distance_squared_to(s["pos"]) < (e.radius + 16.0) * (e.radius + 16.0):
					hits[e.eid] = true
					_apply_hit(hero, e, s["dmg"], s["seq"], s["mode"], s["pos"] - s["vel"] * 0.05)
					s["pierce"] -= 1
					if s["pierce"] < 0:
						dead = true
						break
		elif not dead:
			for e in _ecache:
				if e.hp > 0 and e.position.distance_squared_to(s["pos"]) < (e.radius + 16.0) * (e.radius + 16.0) and not s["full"]:
					dead = true
					break
		if dead:
			if s["life"] > 0.0:
				spark(s["pos"] + Vector2(0, -30), s["color"], 5)
			hshots.remove_at(i)
		i -= 1

func _chain(hero: Node, from: Node, dmg: float, count: int) -> void:
	var cur: Node = from
	var hit := {from: true}
	for i in range(count):
		var best: Node = null
		var bd := 240.0 * 240.0
		for e in enemies():
			if hit.has(e) or e.hp <= 0 or not is_instance_valid(cur):
				continue
			var d: float = e.position.distance_squared_to(cur.position)
			if d < bd:
				bd = d
				best = e
		if best == null:
			return
		hit[best] = true
		_broadcast("arc", [cur.position + Vector2(0, -40), best.position + Vector2(0, -40)])
		best.take_damage(dmg, false, cur.position, hero.key)
		if Net.online: Net.world_event.rpc("hit", [best.eid, dmg, false, ""])
		_damage_number(best.position + Vector2(0, -50), dmg, false)
		cur = best

func on_enemy_killed(enemy: Node, attacker_key: String) -> void:
	if not is_authority() or not is_instance_valid(enemy):
		return
	_broadcast("kill", [enemy.eid, attacker_key, enemy.position, enemy.kind])

func on_local_hero_hurt(_hero: Node, amount: float) -> void:
	shake(10.0)
	sfx("hero_down" if _hero.downed else "hero_hurt", _hero.position)
	float_text(_hero.position + Vector2(0, -110), "-%d" % int(amount), Color(1, 0.3, 0.3))
	if OS.has_feature("mobile"):
		Input.vibrate_handheld(40)

func on_peer_left(peer_id: int) -> void:
	for key in hero_nodes.keys():
		if String(key).begins_with("p%d_" % peer_id):
			var h = hero_nodes[key]
			if is_instance_valid(h):
				h.queue_free()
			hero_nodes.erase(key)
	hud.float_banner("Your partner left the run", Color(1, 0.6, 0.4))

func _hitstop(t: float) -> void:
	Engine.time_scale = 0.05
	await get_tree().create_timer(t, true, false, true).timeout
	Engine.time_scale = 1.0

# ---------------------------------------------------------------- network in

func net_hero_state(key: String, s: Array) -> void:
	var h = hero_nodes.get(key)
	if is_instance_valid(h) and not h.controlled:
		h.apply_state(s)

func net_hero_action(key: String, action: String, pos: Vector2, dir: Vector2, seq: int, aim := Vector2.ZERO) -> void:
	var h = hero_nodes.get(key)
	if not is_instance_valid(h):
		return
	_action_sound(h, action, pos)
	_resolve_action(h, action, pos, dir, seq, aim, MODE_AUTH if is_authority() else MODE_VISUAL)

func net_hero_boons(key: String, b: Dictionary, max_hp: int) -> void:
	var h = hero_nodes.get(key)
	if is_instance_valid(h) and not h.controlled:
		h.boons = b
		h.recompute_stats() # also picks up "_weapon"/"_aspect"/"_forge"
		h.max_hp = max_hp
		hud.refresh()

func net_snapshot(list: Array) -> void:
	if is_authority():
		return
	var seen := {}
	for entry in list:
		var eid: int = entry[0]
		seen[eid] = true
		var e = enemy_nodes.get(eid)
		if not is_instance_valid(e):
			if EnemyScript == null:
				continue
			e = _make_enemy(eid, KINDS[int(entry[1])])
			var pk: Array = entry[2]
			e.position = Vector2(pk[0], pk[1])
		e.apply_packed(entry[2])
	for eid in enemy_nodes.keys():
		if not seen.has(eid):
			var e = enemy_nodes[eid]
			if is_instance_valid(e):
				e.queue_free()
			enemy_nodes.erase(eid)

func net_event(kind: String, a: Array) -> void:
	match kind:
		"proj":
			projectiles.append({"id": a[0], "pos": a[1], "vel": a[2], "dmg": a[3], "color": a[4], "r": a[5], "life": 5.0})
		"slam":
			slams.append({"pos": a[0], "r": a[1], "t": 0.0, "delay": maxf(0.05, a[2]), "dmg": a[3], "color": a[4]})
		"hit":
			# Host-confirmed hit. The attacker's own device already showed it.
			var attacker = hero_nodes.get(a[3])
			var e = enemy_nodes.get(a[0])
			if is_instance_valid(e) and not (is_instance_valid(attacker) and attacker.controlled):
				e.flash_hit()
				sfx("hit_crit" if a[2] else "hit_flesh", e.position)
				_damage_number(e.position + Vector2(0, -50), a[1], a[2])
		"arc":
			arcs.append([a[0], a[1], 0.25])
		"kill":
			_on_kill(a[0], a[1], a[2], a[3])
		"clear":
			_on_room_clear()
		"room":
			_load_room(int(a[0]), String(a[1]) if a.size() > 1 else "")
		"victory":
			_finish(true)
		"defeat":
			_finish(false)

func _on_kill(eid: int, killer: String, pos: Vector2, kind: String) -> void:
	sfx("regent_die" if kind == "regent" else "enemy_die", pos)
	_enemy_states.erase(eid)
	spark(pos + Vector2(0, -40), Color(0.85, 0.5, 1.0), 26)
	shake(5.0 if kind != "regent" else 22.0)
	Game.run_shards += 1 if kind != "regent" else 25
	var h = hero_nodes.get(killer)
	if is_instance_valid(h) and h.controlled and h.stats["lifesteal"] > 0:
		h.heal(h.stats["lifesteal"])
		float_text(h.position + Vector2(0, -120), "+%d" % int(h.stats["lifesteal"]), Color(0.4, 1, 0.6))
	var e = enemy_nodes.get(eid)
	if is_instance_valid(e):
		e.die_visual()
	enemy_nodes.erase(eid)
	if kind == "regent" and is_authority():
		for other in enemies():
			other.queue_free()
		enemy_nodes.clear()
		_broadcast("victory", [])

func _on_room_clear() -> void:
	if room_clear:
		return
	room_clear = true
	sfx("room_clear")
	hud.float_banner("Chamber cleared", Color(1, 0.85, 0.4))
	var local := []
	for h in heroes():
		if h.controlled:
			h.revive(0.3)
			local.append(h)
	if room_index + 1 >= ROOMS.size():
		return
	# Exits are known right away (deterministic), so the host can take a door while others still pick.
	if bool(ROOMS[room_index + 1].get("boss", false)):
		door_rewards = ["boss"]
		door_points = [env.get_door_pos()]
	else:
		door_rewards = Game.roll_door_rewards(room_index + 1)
		door_points = env.get_door_positions() if env.has_method("get_door_positions") else [env.get_door_pos()]
		if door_points.size() < door_rewards.size():
			door_rewards.resize(door_points.size())
	for k in range(door_points.size()):
		door_points[k] = resolve_collision(door_points[k], 16.0)
	_grant_reward(room_reward, local)

## Grants this chamber's reward to this device's heroines, then opens the exits.
func _grant_reward(kind: String, local: Array) -> void:
	match kind:
		"boon", "forge":
			_offer_next(local, kind)
			return
		"heal":
			for h in local:
				var amt: float = h.max_hp * Game.REWARD_HEAL_FRAC
				h.heal(amt)
				float_text(h.position + Vector2(0, -130), "+%d" % int(amt), Color(0.45, 1, 0.6))
				spark(h.position + Vector2(0, -60), Color(1, 0.4, 0.45), 18)
			sfx("boon_pickup")
			hud.float_banner("The chalice restores you", Color(1, 0.55, 0.55))
		"shards":
			Game.run_shards += Game.REWARD_SHARDS
			sfx("shard_pickup")
			hud.float_banner("+%d Veil Shards" % Game.REWARD_SHARDS, Color(0.6, 0.85, 1.0))
		"gold":
			Game.run_gold += Game.REWARD_GOLD
			sfx("shard_pickup")
			hud.float_banner("+%d Gilded Coin" % Game.REWARD_GOLD, Color(1.0, 0.85, 0.35))
	_open_doors()

func _offer_next(queue: Array, kind := "boon") -> void:
	if queue.is_empty():
		_open_doors()
		return
	var h = queue.pop_front()
	if not is_instance_valid(h):
		_offer_next(queue, kind)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%s:%s" % [Game.run_seed, room_index, h.key, kind])
	if kind == "forge":
		var fc := Game.roll_forge(rng, h.weapon_id, h.boons.get("_forge", {}))
		if fc.is_empty():
			_offer_next(queue, kind)
			return
		hud.show_forge_choice(h, fc, func(id: String, rarity: int):
			if is_instance_valid(h):
				h.add_forge(id, rarity)
				sfx("boon_pickup")
				hud.refresh()
			_offer_next(queue, kind))
		return
	var choices := Game.roll_boons(rng, h.boons)
	hud.show_boon_choice(h, choices, func(id: String, rarity: int):
		if is_instance_valid(h):
			h.add_boon(id, rarity)
			sfx("boon_pickup")
			hud.refresh()
		_offer_next(queue, kind))

func _open_doors() -> void:
	if door_open or run_over or not room_clear:
		return
	door_open = true
	env.set_door_open(true)
	if door_points.size() > 1 and _arch:
		_arch.position = door_points[1] + Vector2(0, -6)
		_arch.visible = true
		_arch.modulate = Color(1, 1, 1, 0)
		var tw := _arch.create_tween()
		tw.tween_property(_arch, "modulate:a", 1.0, 0.8)
		spark(door_points[1] + Vector2(0, -120), Color(0.8, 0.55, 1.0), 26)
	sfx("door_open")
	hud.float_banner("Choose your path" if door_points.size() > 1 else "The way forward opens", Color(0.6, 0.9, 1.0))

func _finish(victory: bool) -> void:
	if run_over:
		return
	run_over = true
	Engine.time_scale = 1.0
	_music("victory" if victory else "defeat")
	hud.float_banner("THE REGENT FALLS" if victory else "THE VEIL CLAIMS YOU", Color(1, 0.85, 0.3) if victory else Color(1, 0.3, 0.3))
	await get_tree().create_timer(2.2).timeout
	if not is_inside_tree():
		return
	if victory:
		_play_dialogue("VICTORY", func(): run_finished.emit(true))
	else:
		run_finished.emit(false)

func abandon() -> void:
	if Net.online and not is_authority():
		run_finished.emit(false)
	else:
		_broadcast("defeat", [])

# ---------------------------------------------------------------- frame

func _physics_process(delta: float) -> void:
	_ecache.clear()
	for e in enemy_nodes.values():
		if is_instance_valid(e):
			_ecache.append(e)
	if is_authority():
		for e in enemy_nodes.values():
			if is_instance_valid(e):
				e.simulate(delta)
		_update_waves(delta)
		_check_defeat()
		_snap_timer -= delta
		if Net.online and _snap_timer <= 0.0:
			_snap_timer = 1.0 / 30.0
			var list := []
			for e in enemy_nodes.values():
				if is_instance_valid(e):
					list.append([e.eid, KINDS.find(e.kind), e.pack()])
			Net.world_snapshot.rpc(list)
	else:
		for e in enemy_nodes.values():
			if is_instance_valid(e):
				e.client_update(delta)
	_voice_enemies()
	_step_t -= delta
	if _step_t <= 0.0:
		_step_t = 0.28
		for h in hero_nodes.values():
			if is_instance_valid(h) and h.controlled and h.state == "run":
				sfx("footstep", h.position)
	_local_damage_checks(delta)
	_update_casts(delta)
	_update_hshots(delta)
	_update_fx(delta)
	_update_door()
	_update_camera(delta)
	overlay.queue_redraw()
	groundfx.queue_redraw()
	airfx.queue_redraw()
	queue_redraw()

func _check_defeat() -> void:
	if run_over or hero_nodes.is_empty():
		return
	for h in hero_nodes.values():
		if is_instance_valid(h) and not h.downed:
			return
	_broadcast("defeat", [])

## Every device decides damage to its OWN heroines (favor the defender).
func _local_damage_checks(delta: float) -> void:
	var locals := []
	for h in hero_nodes.values():
		if is_instance_valid(h) and h.controlled and not h.downed:
			locals.append(h)
	for e in enemy_nodes.values():
		if not is_instance_valid(e) or not e.hitbox_active:
			continue
		for h in locals:
			if h.position.distance_to(e.position) < e.hitbox_radius + 16.0:
				h.take_hit(e.contact_damage, e.position)
	var i := projectiles.size() - 1
	while i >= 0:
		var p: Dictionary = projectiles[i]
		p["pos"] += p["vel"] * delta
		p["life"] -= delta
		var dead: bool = p["life"] <= 0.0 or resolve_collision(p["pos"], 0.0) != p["pos"]
		if not dead:
			for h in locals:
				if h.position.distance_to(p["pos"]) < p["r"] + 18.0 and h.iframes <= 0.0 and h.state != "dash":
					h.take_hit(p["dmg"], p["pos"])
					spark(p["pos"], p["color"], 8)
					sfx("projectile_hit", p["pos"])
					dead = true
					if Net.online:
						Net.projectile_consumed.rpc(p["id"])
					break
		if dead:
			projectiles.remove_at(i)
		i -= 1
	i = slams.size() - 1
	while i >= 0:
		var s: Dictionary = slams[i]
		s["t"] += delta
		if s["t"] >= s["delay"]:
			for h in locals:
				if h.position.distance_to(s["pos"]) < s["r"]:
					h.take_hit(s["dmg"], s["pos"])
			spark(s["pos"], s["color"], 16)
			sfx("slam_impact", s["pos"])
			shake(6.0)
			slams.remove_at(i)
		i -= 1

func _update_door() -> void:
	_door_req_t = maxf(0.0, _door_req_t - get_physics_process_delta_time())
	if not door_open or run_over or door_points.is_empty():
		return
	for h in hero_nodes.values():
		if not (is_instance_valid(h) and h.controlled and not h.downed):
			continue
		for k in range(door_points.size()):
			if h.position.distance_to(door_points[k]) < 80.0:
				if is_authority():
					door_open = false
					try_advance(k)
				elif _door_req_t <= 0.0:
					_door_req_t = 0.5
					Net.request_door.rpc_id(1, k) # host moves everyone
				return

func _door_pos() -> Vector2:
	return door_points[0] if not door_points.is_empty() else env.get_door_pos()

func _update_camera(delta: float) -> void:
	var sum := Vector2.ZERO
	var n := 0
	for h in hero_nodes.values():
		if is_instance_valid(h) and h.controlled:
			sum += h.position
			n += 1
	if n == 0:
		for h in hero_nodes.values():
			if is_instance_valid(h):
				sum += h.position
				n += 1
	if n > 0:
		camera.position = sum / n + Vector2(0, -50)
	_shake = maxf(0.0, _shake - delta * 40.0)
	camera.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * _shake

# ---------------------------------------------------------------- fx

func shake(amount: float) -> void:
	_shake = minf(24.0, maxf(_shake, amount))

func spark(pos: Vector2, color: Color, count := 8) -> void:
	for i in range(count):
		if particles.size() >= MAX_PARTICLES:
			particles.pop_front()
		var a := randf() * TAU
		var sp := randf_range(120.0, 420.0)
		var life := randf_range(0.2, 0.45)
		particles.append([pos, Vector2(cos(a), sin(a) * 0.6) * sp, life, life, color, randf_range(2.5, 6.0)])

func float_text(pos: Vector2, text: String, color: Color) -> void:
	if texts.size() >= MAX_TEXTS:
		texts.pop_front()
	texts.append([pos, text, color, 0.9])

func _damage_number(pos: Vector2, amount: float, crit: bool) -> void:
	float_text(pos + Vector2(randf_range(-14, 14), 0), ("%d!" if crit else "%d") % int(round(amount)), Color(1, 0.35, 0.25) if crit else Color(1, 0.95, 0.75))

func _update_fx(delta: float) -> void:
	var i := particles.size() - 1
	while i >= 0:
		var p: Array = particles[i]
		p[2] -= delta
		if p[2] <= 0.0:
			particles.remove_at(i)
		else:
			p[0] += p[1] * delta
			p[1] *= 0.9
		i -= 1
	i = texts.size() - 1
	while i >= 0:
		var t: Array = texts[i]
		t[3] -= delta
		t[0].y -= 60.0 * delta
		if t[3] <= 0.0:
			texts.remove_at(i)
		i -= 1
	i = arcs.size() - 1
	while i >= 0:
		arcs[i][2] -= delta
		if arcs[i][2] <= 0.0:
			arcs.remove_at(i)
		i -= 1

## Ground layer: telegraphs and the exit door (under characters).
func _draw() -> void:
	for s in slams:
		var k: float = clampf(s["t"] / s["delay"], 0.0, 1.0)
		var c: Color = s["color"]
		draw_set_transform(s["pos"], 0.0, Vector2(1, 0.5))
		draw_circle(Vector2.ZERO, s["r"], Color(c, 0.12))
		draw_circle(Vector2.ZERO, s["r"] * k, Color(c, 0.3))
		draw_arc(Vector2.ZERO, s["r"], 0, TAU, 48, Color(c, 0.9), 4.0)
	draw_set_transform(Vector2.ZERO)

## Air layer: projectiles, sparks, lightning, numbers (over characters).
func _draw_overlay() -> void:
	_draw_weapon_overlay()
	for p in projectiles:
		var c: Color = p["color"]
		var pos: Vector2 = p["pos"] + Vector2(0, -30)
		overlay.draw_circle(pos, p["r"] + 6.0, Color(c, 0.25))
		overlay.draw_circle(pos, p["r"] + 2.0, Color(0.05, 0.02, 0.05))
		overlay.draw_circle(pos, p["r"], c)
		overlay.draw_circle(pos - p["vel"].normalized() * 4.0, p["r"] * 0.45, Color(1, 1, 1, 0.9))
	for p in particles:
		var a: float = p[2] / p[3]
		var c: Color = p[4]
		overlay.draw_line(p[0], p[0] - p[1] * 0.03, Color(c, a), p[5] * a + 1.0)
	for arc in arcs:
		var a: Vector2 = arc[0]
		var b: Vector2 = arc[1]
		var pts := PackedVector2Array([a])
		for j in range(1, 6):
			pts.append(a.lerp(b, j / 6.0) + Vector2(randf_range(-12, 12), randf_range(-12, 12)))
		pts.append(b)
		overlay.draw_polyline(pts, Color(0.7, 0.9, 1.0, arc[2] * 4.0), 4.0)
		overlay.draw_polyline(pts, Color(1, 1, 1, arc[2] * 4.0), 1.5)
	var font := ThemeDB.fallback_font
	for t in texts:
		var a: float = clampf(t[3] * 2.0, 0.0, 1.0)
		var size := 30 if String(t[1]).ends_with("!") else 24
		overlay.draw_string_outline(font, t[0] - Vector2(30, 0), t[1], HORIZONTAL_ALIGNMENT_CENTER, 60, size, 6, Color(0.05, 0.02, 0.05, a))
		overlay.draw_string(font, t[0] - Vector2(30, 0), t[1], HORIZONTAL_ALIGNMENT_CENTER, 60, size, Color(t[2], a))

# ---------------------------------------------------------------- weapon / special / exit drawing

func _icon(name: String) -> Texture2D:
	if not _icons.has(name):
		_icons[name] = VTheme.tex(name)
	return _icons[name]

## A painted rune ring lying on the floor (additive).
func _reticle(at: Vector2, r: float, col: Color, spin: float) -> void:
	groundfx.draw_set_transform_matrix(Transform2D(0.0, Vector2(1.0, 0.5), 0.0, at) * Transform2D(spin, Vector2.ZERO))
	groundfx.draw_texture_rect(RETICLE_TEX, Rect2(-r * 1.12, -r * 1.12, r * 2.24, r * 2.24), false, col)
	groundfx.draw_set_transform(Vector2.ZERO)

func _draw_groundfx() -> void:
	var now := Time.get_ticks_msec() * 0.001
	# the local heroine's aim: path dots + reticle at the landing point
	for h in hero_nodes.values():
		if not (is_instance_valid(h) and h.controlled and h.aiming):
			continue
		var col: Color = h.wdef["color"]
		var r := special_radius(h)
		var a: Vector2 = h.position
		var b: Vector2 = h.aim_point
		var n := int(clampf(a.distance_to(b) / 34.0, 2.0, 16.0))
		var leap: bool = h.weapon_id == "spear"
		for k in range(1, n):
			var f := float(k) / n
			var p := a.lerp(b, f)
			if leap:
				p.y -= sin(f * PI) * 70.0
			groundfx.draw_circle(p, 4.0, Color(col, 0.55))
		_reticle(b, r, Color(col.r, col.g, col.b, 0.85 + 0.15 * sin(now * 8.0)), now * 0.8)
	# telegraphs of specials about to land (every device sees them)
	for c in casts:
		var col: Color = c["color"]
		var r: float = c["r"]
		var k: String = c["kind"]
		var st: int = c["stage"]
		if (k == "spear" and st == 0) or (k == "bow" and st <= 1):
			var land: float = c["hit"] + (0.35 if k == "bow" else 0.0)
			var f := clampf(c["t"] / land, 0.0, 1.0)
			_reticle(c["to"], r * (1.25 - 0.25 * f), Color(col, 0.5 + 0.5 * f), now * 1.6)
			groundfx.draw_set_transform(c["to"], 0.0, Vector2(1, 0.5))
			groundfx.draw_circle(Vector2.ZERO, r * f, Color(col, 0.18))
			groundfx.draw_set_transform(Vector2.ZERO)
		elif (k == "twin" and st == 2) or (k == "shield" and st == 3) or (k == "scythe" and st == 2):
			var p: Vector2 = c["to"]
			groundfx.draw_set_transform(p, 0.0, Vector2(1, 0.5))
			groundfx.draw_circle(Vector2.ZERO, r, Color(col, 0.16))
			for j in range(3):
				var a0: float = now * (7.0 if k != "scythe" else -5.0) + j * TAU / 3.0
				groundfx.draw_arc(Vector2.ZERO, r * (0.55 + 0.15 * j), a0, a0 + 1.9, 18, Color(col, 0.7), 5.0)
			groundfx.draw_set_transform(Vector2.ZERO)
		elif st == 0 and (k == "twin" or k == "shield" or k == "scythe"):
			_reticle(c["to"], r, Color(col, 0.6), now)
	for p in pools:
		var a: float = clampf(p[3], 0.0, 1.0)
		groundfx.draw_set_transform(p[0], 0.0, Vector2(1, 0.5))
		groundfx.draw_circle(Vector2.ZERO, p[1], Color(1.0, 0.35, 0.08, 0.22 * a))
		groundfx.draw_arc(Vector2.ZERO, p[1] * (0.85 + 0.08 * sin(now * 9.0)), 0, TAU, 32, Color(1.0, 0.65, 0.2, 0.6 * a), 6.0)
		groundfx.draw_set_transform(Vector2.ZERO)
	for ring in _rings:
		var f: float = 1.0 - ring[2] / ring[3]
		var col: Color = ring[4]
		groundfx.draw_set_transform(ring[0], 0.0, Vector2(1, 0.5))
		groundfx.draw_circle(Vector2.ZERO, ring[1] * (0.3 + 0.8 * f), Color(col, 0.35 * (1.0 - f)))
		groundfx.draw_arc(Vector2.ZERO, ring[1] * (0.3 + 0.8 * f), 0, TAU, 40, Color(col.lightened(0.3), 1.0 - f), 10.0 * (1.0 - f) + 2.0)
		groundfx.draw_set_transform(Vector2.ZERO)
	# glow under open exits
	if door_open:
		for k in range(door_points.size()):
			var rc: Color = Game.REWARDS.get(String(door_rewards[k]) if k < door_rewards.size() else "", {}).get("color", Color(1, 0.85, 0.55))
			groundfx.draw_set_transform(door_points[k], 0.0, Vector2(1, 0.5))
			groundfx.draw_circle(Vector2.ZERO, 70.0, Color(rc, 0.16 + 0.06 * sin(now * 3.0)))
			groundfx.draw_set_transform(Vector2.ZERO)

## Additive: blade glows, crescents, arrow trails, volley rain.
func _draw_airfx() -> void:
	var now := Time.get_ticks_msec() * 0.001
	for s in hshots:
		var p: Vector2 = s["pos"] + Vector2(0, -50)
		var v: Vector2 = s["vel"]
		var col: Color = s["color"]
		var tail := p - v * (0.06 if s["full"] else 0.04)
		airfx.draw_line(tail, p, Color(col, 0.55), 10.0 if s["full"] else 6.0)
		airfx.draw_line(tail.lerp(p, 0.4), p, Color(1, 1, 1, 0.9), 2.5)
	for c in casts:
		var col: Color = c["color"]
		var k: String = c["kind"]
		var st: int = c["stage"]
		var p: Vector2 = c["pos"] + Vector2(0, -50)
		match k:
			"twin":
				if st >= 1:
					var at: Vector2 = c["to"] + Vector2(0, -50) if st == 2 else p
					_crescent(at, now * 22.0, 46.0, col)
					_crescent(at, now * 22.0 + PI, 46.0, col)
			"bow":
				if st >= 1:
					var land: float = c["hit"] + 0.35
					var t: float = c["t"]
					if t < land:
						var f: float = (t - float(c["hit"])) / 0.35
						var top: Vector2 = c["from"] + Vector2(0, -60 - 500.0 * f)
						airfx.draw_line(top + Vector2(0, 40), top, Color(col, 0.8), 6.0)
					# falling streaks over the area (seeded per cast so it is stable)
					var r: float = c["r"]
					for j in range(10):
						var h := float((int(c["seq"]) * 7919 + j * 104729) % 1000) / 1000.0
						var h2 := float((int(c["seq"]) * 31 + j * 7907) % 1000) / 1000.0
						var ph := fmod(t * 3.0 + h, 1.0)
						var gx: Vector2 = c["to"] + Vector2((h - 0.5) * r * 1.6, (h2 - 0.5) * r * 0.8)
						if t > land - 0.25 and t < land + 0.13 * c["pulses"] + 0.1:
							var y := -420.0 * (1.0 - ph)
							airfx.draw_line(gx + Vector2(-8, y - 50), gx + Vector2(0, y), Color(col, 0.75), 4.0)
			"shield":
				if st >= 1:
					var at: Vector2 = c["to"] + Vector2(0, -40) if st == 3 else p
					airfx.draw_circle(at, 52.0, Color(col, 0.25))
					if st == 3:
						for j in range(3):
							var a0 := now * 12.0 + j * TAU / 3.0
							airfx.draw_arc(at, 70.0, a0, a0 + 1.2, 12, Color(col, 0.65), 5.0)
			"scythe":
				if st >= 1:
					var at: Vector2 = c["to"] + Vector2(0, -40) if st == 2 else p
					airfx.draw_circle(at, 46.0, Color(col, 0.25))
					if st == 1 or st == 3:
						var hp_: Vector2 = c["hero"].position + Vector2(0, -50) if is_instance_valid(c["hero"]) else at
						airfx.draw_line(hp_, at, Color(0.7, 0.55, 1.0, 0.55), 3.0)

func _crescent(at: Vector2, ang: float, r: float, col: Color) -> void:
	var steps := 10
	_cpts.resize((steps + 1) * 2)
	for j in range(steps + 1):
		var a := ang - 1.3 + 2.6 * j / steps
		_cpts[j] = at + Vector2(cos(a), sin(a) * 0.6) * r
	for j in range(steps + 1):
		var a := ang + 1.3 - 2.6 * j / steps
		_cpts[steps + 1 + j] = at + Vector2(cos(a), sin(a) * 0.6) * r * 0.62 + Vector2(cos(ang), sin(ang) * 0.6) * r * 0.18
	airfx.draw_colored_polygon(_cpts, Color(col, 0.85))
	airfx.draw_circle(at, r * 0.3, Color(1, 1, 1, 0.35))

var _cpts := PackedVector2Array()

## Painted pieces drawn with normal blending in the overlay: thrown shield / scythe, arrows' ink, exit rewards.
func _draw_weapon_overlay() -> void:
	var now := Time.get_ticks_msec() * 0.001
	for s in hshots:
		var p: Vector2 = s["pos"] + Vector2(0, -50)
		var d: Vector2 = s["vel"].normalized()
		overlay.draw_line(p - d * 34.0, p, Color(0.08, 0.04, 0.05, 0.9), 4.0)
		overlay.draw_line(p - d * 32.0, p - d * 2.0, Color(0.85, 0.7, 0.45), 2.0)
	for c in casts:
		var k: String = c["kind"]
		var st: int = c["stage"]
		if st < 1 or (k != "shield" and k != "scythe"):
			continue
		var lodged: bool = (k == "shield" and st == 3) or (k == "scythe" and st == 2)
		var at: Vector2 = (c["to"] + Vector2(0, -40)) if lodged else (c["pos"] + Vector2(0, -50))
		var tex := _icon("weapon_" + k)
		if tex == null:
			continue
		var sz := 92.0 if k == "shield" else 110.0
		var spin := now * (16.0 if k == "shield" else -14.0)
		overlay.draw_set_transform_matrix(Transform2D(spin, Vector2(1.0, 0.62 if k == "shield" else 0.7), 0.0, at))
		overlay.draw_texture_rect(tex, Rect2(-sz * 0.5, -sz * 0.5, sz, sz), false)
		overlay.draw_set_transform(Vector2.ZERO)
	# exits: floating reward icons above each open door
	if door_open and not door_points.is_empty():
		var orb := _icon("orb")
		var font := VTheme.font("caps")
		for k in range(door_points.size()):
			var rid := String(door_rewards[k]) if k < door_rewards.size() else ""
			var info: Dictionary = Game.REWARDS.get(rid, {})
			var top: Vector2 = door_points[k] + Vector2(0, -105.0 if k == 0 else -190.0) + Vector2(0, sin(now * 2.2 + k) * 8.0)
			if orb:
				overlay.draw_texture_rect(orb, Rect2(top - Vector2(52, 52), Vector2(104, 104)), false)
			var tex: Texture2D = _icon(String(info.get("icon", "face_regent"))) if rid != "boss" else _icon("face_regent")
			if tex:
				var s := 70.0 / maxf(tex.get_width(), tex.get_height())
				var sz := Vector2(tex.get_width(), tex.get_height()) * s
				overlay.draw_texture_rect(tex, Rect2(top - sz * 0.5, sz), false)
			var label := String(info.get("name", "The Regent awaits" if rid == "boss" else "")).to_upper()
			if font and label != "":
				overlay.draw_string_outline(font, top + Vector2(-140, 78), label, HORIZONTAL_ALIGNMENT_CENTER, 280, 20, 7, Color(0.03, 0.01, 0.04, 0.95))
				overlay.draw_string(font, top + Vector2(-140, 78), label, HORIZONTAL_ALIGNMENT_CENTER, 280, 20, Color(info.get("color", Color(1, 0.85, 0.5)), 1.0).lightened(0.25))
