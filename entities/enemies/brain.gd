class_name EnemyBrain
extends RefCounted
## Data-driven behaviour for one enemy kind (entities/enemy.gd owns movement, damage, networking, drawing).
## Runs on every device: the host calls think() (decides + spawns hazards), every device calls the read-only
## helpers (anim_for, windup_len, telegraph drawing) from replicated state, so clients render the same thing.
##
## Attack table (ATTACKS, override attacks()): id -> {
##   "w": windup s, "a": active s, "r": recovery s (punish window), "cd": own cooldown s,
##   "range": [min, max] px to target, "weight": pick weight, "phase": min phase (bosses), "max_phase": optional,
##   "aw": windup anim, "aa": strike anim, "ar": optional recovery anim,
##   "track": 0..1 fraction of the windup during which aim follows the target (then it locks = dodgeable),
##   "tele": "line" | "cone" | "ring" | "aux" | "" (local ground marker during windup; arena slams draw their own),
##   "tele_len", "tele_w", "tele_arc" (deg), "tele_r",
##   "speed": move speed during the strike (along aim), "hit_r": contact hitbox radius while active, "dmg": its damage,
##   "charge": true = stops (and stuns for "stun" s) when it hits a wall, "leap": px height arc while active,
##   "next": id of a follow-up attack (combo; "next_p" chance), "lob": true draws a pod flying to aux during a+r,
##   "rep": most times in a row it may be picked (default 2) }

const S_IDLE := 0
const S_MOVE := 1
const S_WINDUP := 2
const S_ATTACK := 3
const S_RECOVER := 4
const S_HURT := 5
const S_ROAR := 12
const S_STUN := 16

var e: Node2D = null   # the enemy (entities/enemy.gd)
var A: Dictionary = {}  # attack table
var ids: Array = []     # attack ids in table order (index is what gets replicated)
var _cds := {}          # host: per-attack cooldown left
var _last := ""         # host: last chosen attack and how many times in a row ("rep" caps the streak)
var _streak := 0


func _init() -> void:
	A = attacks()
	ids = A.keys()


## --------------------------------------------------------------- overridables

func attacks() -> Dictionary:
	return {}


## Locomotion when not attacking (host). Return a velocity.
func locomote(_delta: float, has_t: bool, dir: Vector2, dist: float) -> Vector2:
	if not has_t:
		return Vector2.ZERO
	return dir * e.speed() if dist > 70.0 else Vector2.ZERO


## Host: once, when the windup starts (place replicated slams so the ground marker fills up until the hit).
func on_windup(_id: String) -> void:
	pass


## Host: once, at the strike frame (projectiles, short-fuse slams, spawns).
func on_strike(_id: String) -> void:
	pass


## Host: movement during the strike in addition to "speed" (return Vector2.ZERO for none).
func strike_move(_id: String, _t: float) -> Vector2:
	return Vector2.ZERO


## Host: damage filter (shields). Return the damage actually taken.
func filter_damage(amount: float, _from_pos: Vector2) -> float:
	return amount


## Every device: extra drawing in enemy local space (after the generic telegraphs).
func draw_extra() -> void:
	pass


## Host: a phase change just started (roar beat is playing).
func on_phase(_p: int) -> void:
	pass


## Pause between attacks (divided by the phase speed-up).
func base_cd() -> float:
	return 0.7 + randf() * 0.5


## Locomotion anim name.
func move_anim() -> String:
	return "move"


## Extra always-on contact hitbox [radius, damage] (e.g. wisps), or [] for none.
func contact() -> Array:
	return []


## Combo follow-ups ignore their own cooldown but respect phase gates.
func usable_chain(id: String) -> bool:
	if not A.has(id):
		return false
	var a: Dictionary = A[id]
	return int(a.get("phase", 0)) <= e.phase


## Host: chooses what to do next; default = weighted random among usable attacks.
func choose(dist: float) -> String:
	var total := 0.0
	var cands := []
	for id in ids:
		var a: Dictionary = A[id]
		if not usable(id, dist):
			continue
		var w: float = float(a.get("weight", 1.0))
		total += w
		cands.append([id, w])
	if cands.is_empty():
		_last = ""   # nothing else was usable: let the capped attack come back next time
		return ""
	var r := randf() * total
	var pick: String = cands[-1][0]
	for c in cands:
		r -= c[1]
		if r <= 0.0:
			pick = c[0]
			break
	_streak = _streak + 1 if pick == _last else 1
	_last = pick
	return pick


func usable(id: String, dist: float) -> bool:
	var a: Dictionary = A[id]
	if _cds.get(id, 0.0) > 0.0:
		return false
	if id == _last and _streak >= int(a.get("rep", 2 if e.is_boss else 99)):
		return false
	if int(a.get("phase", 0)) > e.phase or int(a.get("max_phase", 99)) < e.phase:
		return false
	var rg: Array = a.get("range", [0.0, 99999.0])
	return dist >= float(rg[0]) and dist <= float(rg[1])


## --------------------------------------------------------------- shared helpers (host)

func tick_cooldowns(delta: float) -> void:
	for k in _cds:
		_cds[k] = maxf(0.0, _cds[k] - delta)


func set_cd(id: String) -> void:
	_cds[id] = float(A[id].get("cd", 0.0))


func atk_index(id: String) -> int:
	return ids.find(id)


func atk_id(i: int) -> String:
	return ids[i] if i >= 0 and i < ids.size() else ""


func spec(i: int) -> Dictionary:
	return A[ids[i]] if i >= 0 and i < ids.size() else {}


## world point in front of the enemy along its aim
func ahead(d: float) -> Vector2:
	return e.position + e.aim * d


## arc of slams: n circles of radius r at distance reach, spanning arc_deg around the aim
func slam_arc(reach: float, arc_deg: float, n: int, r: float, delay: float, dmg: float, col: Color) -> void:
	for i in n:
		var u := 0.5 if n == 1 else float(i) / float(n - 1)
		var ang := deg_to_rad(-arc_deg * 0.5 + arc_deg * u)
		e.arena.telegraph_slam(e.position + e.aim.rotated(ang) * reach, r, delay, dmg, col)


## line of slams along the aim (or dir), each one later than the previous (a travelling wave)
func slam_line(from: Vector2, dir: Vector2, n: int, spacing: float, r: float, delay: float, step: float, dmg: float, col: Color) -> void:
	for i in n:
		e.arena.telegraph_slam(from + dir * spacing * (i + 1), r, delay + step * i, dmg, col)


## ring of slams around c
func slam_ring(c: Vector2, radius: float, n: int, r: float, delay: float, dmg: float, col: Color, rot := 0.0) -> void:
	for i in n:
		var p := c + Vector2.RIGHT.rotated(rot + TAU * i / n) * Vector2(radius, radius * 0.62)
		e.arena.telegraph_slam(e.arena.resolve_collision(p, 0.0), r, delay, dmg, col)


func fan(n: int, spread_deg: float, speed: float, dmg: float, col: Color, r := 11.0, dir := Vector2.ZERO) -> void:
	var d0: Vector2 = e.aim if dir == Vector2.ZERO else dir
	var base: Vector2 = e.position + Vector2(0.0, -6.0)
	for i in n:
		var u := 0.5 if n == 1 else float(i) / float(n - 1)
		var d := d0.rotated(deg_to_rad(-spread_deg * 0.5 + spread_deg * u))
		e.arena.spawn_projectile(base + d * (e.radius + 6.0), d * speed, dmg, col, r)


func ring(n: int, speed: float, dmg: float, col: Color, offset := 0.0, r := 12.0) -> void:
	var base: Vector2 = e.position + Vector2(0.0, -6.0)
	for i in n:
		var d := Vector2.RIGHT.rotated(offset + TAU * i / n)
		e.arena.spawn_projectile(base + d * e.radius, d * speed, dmg, col, r)


## spawn up to `n` adds of `kind` while fewer than `cap` of them are alive
func summon(kind: String, n: int, cap: int, dist := 120.0) -> int:
	var alive := 0
	for o in e.arena.enemies():
		if o.kind == kind and not o.is_dead():
			alive += 1
	var made := 0
	for i in n:
		if alive + made >= cap:
			break
		var off := Vector2.RIGHT.rotated(randf() * TAU) * Vector2(dist, dist * 0.6)
		if e.arena.spawn_enemy(kind, e.arena.resolve_collision(e.position + off, 24.0)) != null:
			made += 1
	return made


## live heroes (not downed)
func live_heroes() -> Array:
	var out := []
	for h in e.arena.heroes():
		if is_instance_valid(h) and not h.downed:
			out.append(h)
	return out


## predicted target position `t` seconds ahead (heroes expose vel on their owner; elsewhere it is zero)
func lead(t: float) -> Vector2:
	var tg = e.target_node()
	if tg == null:
		return e.position + e.aim * 200.0
	var v = tg.get("vel")
	var p: Vector2 = tg.position
	if v is Vector2:
		p += v * t * 0.6
	return e.arena.resolve_collision(p, 10.0)
