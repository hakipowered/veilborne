extends Node2D
## One run through the Gilded Catacombs: rooms, waves, boons, boss, co-op sync.

signal run_finished(victory: bool)

const INTERP_DELAY_MS := 100
const HeroScript := preload("res://entities/hero.gd")
const HudScript := preload("res://ui/hud.gd")
const FLOOR_SCALE := 1.6
const MAX_PARTICLES := 260
const MAX_TEXTS := 40
const MAX_PROJECTILES := 120

const FLOORS := {
	"catacomb": {"tex": "res://art/floor_catacomb.jpg", "center": Vector2(690, 388), "half": Vector2(470, 245)},
	"throne": {"tex": "res://art/floor_throne.jpg", "center": Vector2(690, 388), "half": Vector2(560, 280)},
}
const ROOMS := [
	{"floor": "catacomb", "name": "Gilded Catacombs I", "waves": [["shade", "shade", "shade"], ["shade", "spitter", "shade", "spitter"]]},
	{"floor": "catacomb", "name": "Gilded Catacombs II", "waves": [["spitter", "spitter", "shade", "shade"], ["brute", "shade", "shade"]]},
	{"floor": "catacomb", "name": "Gilded Catacombs III", "waves": [["brute", "spitter", "spitter"], ["shade", "shade", "shade", "shade", "spitter"]]},
	{"floor": "catacomb", "name": "Gilded Catacombs IV", "waves": [["brute", "brute", "spitter"], ["shade", "shade", "spitter", "spitter", "brute"]]},
	{"floor": "throne", "name": "Throne of the Hollow Regent", "boss": true, "waves": []},
]
const KINDS := ["shade", "spitter", "brute", "regent"]

var EnemyScript: GDScript
var floor_sprite: Sprite2D
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

func _ready() -> void:
	EnemyScript = load("res://entities/enemy.gd")
	Net.arena = self
	floor_sprite = Sprite2D.new()
	floor_sprite.centered = false
	floor_sprite.z_index = -10
	add_child(floor_sprite)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	overlay = Node2D.new()
	overlay.z_index = 5
	overlay.draw.connect(_draw_overlay)
	add_child(overlay)
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
		h.setup(key, p["hero"], controlled, int(p["local_index"]), self)
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
	# Keep inside the diamond-shaped chamber: |x|/W + |y|/H <= 1.
	var w := room_half.x - radius
	var hh := room_half.y - radius * 0.5
	var k := absf(pos.x) / w + absf(pos.y) / hh
	if k > 1.0:
		pos /= k
	return pos

# ---------------------------------------------------------------- rooms

func _load_room(idx: int) -> void:
	room_index = idx
	Game.run_room = idx
	var room: Dictionary = ROOMS[idx]
	var fl: Dictionary = FLOORS[room["floor"]]
	floor_sprite.texture = load(fl["tex"])
	floor_sprite.scale = Vector2.ONE * FLOOR_SCALE
	floor_sprite.position = -fl["center"] * FLOOR_SCALE
	room_half = fl["half"] * FLOOR_SCALE
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
	for h in heroes():
		h.position = Vector2(-120 + 240.0 * i / max(1, n - 1), room_half.y * 0.55) if n > 1 else Vector2(0, room_half.y * 0.55)
		h.vel = Vector2.ZERO
		h._buffer.clear()
		i += 1
	camera.position = Vector2(0, room_half.y * 0.4)
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
			var ang := _rng.randf() * TAU
			var pos := Vector2(cos(ang) * room_half.x * 0.55, sin(ang) * room_half.y * 0.45)
			spawn_enemy(kind, pos)
		wave_index += 1
		wave_delay = 0.9
	else:
		_broadcast("clear", [])

func try_advance() -> void:
	if not room_clear or run_over:
		return
	if room_index + 1 >= ROOMS.size():
		return
	_broadcast("room", [room_index + 1])

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

func _action_sound(hero: Node, action: String, pos: Vector2) -> void:
	if action.begins_with("attack"):
		sfx("swing_spear" if hero.def["weapon"] == "spear" else "swing_blades", pos)
	elif action == "special":
		sfx("special_ember" if hero.def["weapon"] == "spear" else "special_moon", pos)
	elif action == "dash":
		sfx("dash", pos)

func hero_action_local(hero: Node, action: String, pos: Vector2, dir: Vector2, seq: int) -> void:
	_action_sound(hero, action, pos)
	if is_authority():
		_resolve_action(hero, action, pos, dir, seq, false)
	else:
		_resolve_action(hero, action, pos, dir, seq, true)

func _crit(hero_key: String, seq: int, eid: int, chance: float) -> bool:
	return (hash("%s:%d:%d" % [hero_key, seq, eid]) & 0xffff) % 100 < int(chance)

## Applies (host) or predicts (client) the damage of a heroine's action.
func _resolve_action(hero: Node, action: String, pos: Vector2, dir: Vector2, seq: int, predict: bool) -> void:
	var st: Dictionary = hero.stats
	var spear: bool = hero.def["weapon"] == "spear"
	var targets: Array = []
	var dmg := 0.0
	var kb := 160.0
	var origin := pos + Vector2(0, -20)
	if action.begins_with("attack"):
		var finisher := action == "attack0"
		dmg = hero.attack_damage("attack", finisher)
		var reach := (125.0 if spear else 100.0) * (1.15 if finisher else 1.0)
		var half_arc := deg_to_rad(42.0 if spear else 75.0)
		for e in enemies():
			if e.hp <= 0:
				continue
			var to: Vector2 = e.position - origin
			var d := to.length()
			if d <= reach + e.radius and (d < 40.0 or absf(dir.angle_to(to)) <= half_arc):
				targets.append(e)
		kb = 260.0 if finisher else 140.0
	elif action == "special":
		dmg = hero.attack_damage("special")
		var size: float = 1.0 + st["special_size"] / 100.0
		var c := pos + dir * 150.0 if spear else pos
		var r: float = (90.0 if spear else 120.0) * size
		for e in enemies():
			if e.hp > 0 and e.position.distance_to(c) <= r + e.radius:
				targets.append(e)
		kb = 320.0 if st["special_size"] > 0 else 200.0
	elif action == "dash":
		if st["dash_shock"] <= 0:
			return
		dmg = float(st["dash_shock"]) * st["dmg_meta"]
		for e in enemies():
			if e.hp > 0 and e.position.distance_to(pos) <= 110.0 + e.radius:
				targets.append(e)
		kb = 60.0
	if targets.is_empty():
		return
	var big := false
	for e in targets:
		var crit := _crit(hero.key, seq, e.eid, st["crit"])
		var amount := dmg * (2.0 if crit else 1.0)
		big = big or crit
		var hit_pos: Vector2 = e.position + Vector2(0, -40)
		spark(hit_pos, Color(1, 0.95, 0.7) if not crit else Color(1, 0.4, 0.3), 10 if not crit else 18)
		sfx("hit_crit" if crit else "hit_flesh", e.position)
		if predict:
			e.flash_hit()
			_damage_number(hit_pos, amount, crit)
		else:
			e.take_damage(amount, crit, pos, hero.key)
			if st["burn"] > 0 and e.has_method("apply_burn"):
				e.apply_burn(float(st["burn"]))
			_damage_number(hit_pos, amount, crit)
			if Net.online:
				Net.world_event.rpc("hit", [e.eid, amount, crit, hero.key])
	if not predict and st["chain"] > 0:
		_chain(hero, targets[0], dmg * 0.5, int(st["chain"]))
	if hero.controlled:
		shake(6.0 if big else 3.0)
		if big and not Net.online and hero_nodes.size() == 1:
			_hitstop(0.05)

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

func net_hero_action(key: String, action: String, pos: Vector2, dir: Vector2, seq: int) -> void:
	var h = hero_nodes.get(key)
	if is_instance_valid(h):
		_action_sound(h, action, pos)
	if is_instance_valid(h) and is_authority():
		_resolve_action(h, action, pos, dir, seq, false)

func net_hero_boons(key: String, b: Dictionary, max_hp: int) -> void:
	var h = hero_nodes.get(key)
	if is_instance_valid(h) and not h.controlled:
		h.boons = b
		h.recompute_stats()
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
			_load_room(int(a[0]))
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
		e.queue_free()
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
	_pending_picks = local.size()
	_offer_next(local)

func _offer_next(queue: Array) -> void:
	if queue.is_empty():
		door_open = true
		sfx("door_open")
		hud.float_banner("The way forward opens", Color(0.6, 0.9, 1.0))
		return
	var h = queue.pop_front()
	if not is_instance_valid(h):
		_offer_next(queue)
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("%d:%d:%s" % [Game.run_seed, room_index, h.key])
	var choices := Game.roll_boons(rng, h.boons)
	hud.show_boon_choice(h, choices, func(id: String, rarity: int):
		if is_instance_valid(h):
			h.add_boon(id, rarity)
			sfx("boon_pickup")
			hud.refresh()
		_offer_next(queue))

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
	_update_fx(delta)
	_update_door()
	_update_camera(delta)
	overlay.queue_redraw()
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
	if not door_open or run_over:
		return
	var door := _door_pos()
	for h in hero_nodes.values():
		if is_instance_valid(h) and h.controlled and not h.downed and h.position.distance_to(door) < 70.0:
			door_open = false
			if is_authority():
				try_advance()
			else:
				Net.request_door.rpc_id(1)
				door_open = true # stays open until the host moves everyone
			return

func _door_pos() -> Vector2:
	return Vector2(0, -room_half.y + 70.0)

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
	if door_open:
		var d := _door_pos()
		var t := Time.get_ticks_msec() / 1000.0
		draw_set_transform(d, 0.0, Vector2(1, 0.5))
		for r in range(4):
			var rr := 40.0 + r * 12.0 + sin(t * 3.0 + r) * 4.0
			draw_arc(Vector2.ZERO, rr, 0, TAU, 40, Color(0.6, 0.9, 1.0, 0.8 - r * 0.18), 4.0)
		draw_circle(Vector2.ZERO, 36, Color(0.5, 0.85, 1.0, 0.35))
		draw_set_transform(Vector2.ZERO)
		draw_line(d, d + Vector2(0, -140), Color(0.6, 0.9, 1.0, 0.25), 60.0)

## Air layer: projectiles, sparks, lightning, numbers (over characters).
func _draw_overlay() -> void:
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
