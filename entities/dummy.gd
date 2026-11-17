extends Node2D
## Training dummy for the manor's yard (scenes/hub.gd). Speaks the enemy interface the arena's combat
## code uses (eid, kind, hp, radius, take_damage, flash_hit, pull, apply_burn, ...), never attacks,
## wobbles when struck, topples at 0 health and stands back up a moment later.

const TEX := preload("res://art/env/manor/dummy.png")
const MAX_HP := 400.0
const RESPAWN := 1.6
const SCALE := 0.46

var eid := 0
var kind := "dummy"
var hp := MAX_HP
var max_hp := MAX_HP
var radius := 30.0
var is_boss := false
var is_elite := false
var hitbox_active := false
var hitbox_radius := 0.0
var contact_damage := 0.0
var state := 0
var arena: Node = null
var hits := 0 ## tests: blows taken
var total := 0.0 ## tests: damage taken

var _sprite: Sprite2D
var _wobble := 0.0
var _wobble_v := 0.0
var _flash := 0.0
var _down_t := 0.0
var _burn := 0.0
var _burn_t := 0.0
var _recent: Array = [] ## [time, amount] for the damage-per-second readout
var _home := Vector2.ZERO
var _font: Font


func setup(p_eid: int, p_arena: Node, at: Vector2) -> void:
	eid = p_eid
	arena = p_arena
	position = at
	_home = at


func _ready() -> void:
	_font = ThemeDB.fallback_font
	var sh := Sprite2D.new()
	sh.texture = _shadow_tex()
	sh.scale = Vector2(1.6, 0.55)
	sh.modulate = Color(0, 0, 0, 0.55)
	sh.show_behind_parent = true
	add_child(sh)
	_sprite = Sprite2D.new()
	_sprite.texture = TEX
	_sprite.centered = false
	_sprite.scale = Vector2(SCALE, SCALE)
	_sprite.offset = Vector2(-TEX.get_width() * 0.42, -TEX.get_height() + 14.0)
	add_child(_sprite)


static func _shadow_tex() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = 64
	t.height = 64
	return t


func take_damage(amount: float, _crit: bool, from_pos: Vector2, _attacker_key: String) -> void:
	if hp <= 0.0:
		return
	hits += 1
	_wobble_v += signf(position.x - from_pos.x + 0.01) * clampf(amount * 0.12, 1.5, 6.0)
	_apply_damage(amount)


func _apply_damage(amount: float) -> void:
	if hp <= 0.0:
		return
	total += amount
	_recent.append([Time.get_ticks_msec(), amount])
	flash_hit()
	hp -= amount
	if hp <= 0.0:
		hp = 0.0
		_down_t = RESPAWN
		_wobble_v += 9.0
		if arena and arena.has_method("on_dummy_broken"):
			arena.on_dummy_broken(self)


func flash_hit() -> void:
	_flash = 1.0


func pull(target: Vector2, strength: float) -> void:
	_wobble_v += signf(target.x - position.x) * clampf(strength / 200.0, 1.0, 5.0)


func apply_burn(dps: float) -> void:
	_burn = maxf(_burn, dps)
	_burn_t = 3.0


func simulate(delta: float) -> void:
	if _burn_t > 0.0 and hp > 0.0:
		_burn_t -= delta
		_apply_damage(_burn * delta)
	# a quiet dummy mends itself (so every test starts from full health)
	if hp > 0.0 and hp < max_hp and not _recent.is_empty() and Time.get_ticks_msec() - int(_recent[-1][0]) > 2500:
		hp = max_hp
		_recent.clear()
	elif hp > 0.0 and hp < max_hp and _recent.is_empty():
		hp = max_hp
	if _down_t > 0.0:
		_down_t -= delta
		if _down_t <= 0.0:
			hp = max_hp
			_recent.clear()
			_wobble = -0.6
			_wobble_v = 4.0


func client_update(delta: float) -> void:
	simulate(delta)


func pack() -> Array:
	return [position.x, position.y, hp, max_hp, 0]


func die_visual() -> void:
	pass


func dps() -> float:
	var now := Time.get_ticks_msec()
	var sum := 0.0
	var first := now
	var i := _recent.size() - 1
	while i >= 0:
		if now - int(_recent[i][0]) > 4000:
			_recent.remove_at(i)
		else:
			sum += float(_recent[i][1])
			first = mini(first, int(_recent[i][0]))
		i -= 1
	if sum <= 0.0:
		return 0.0
	return sum / maxf(1.0, (now - first) / 1000.0 + 0.4)


func _process(delta: float) -> void:
	# springy wobble on the post; toppled while broken
	var target := 1.25 if hp <= 0.0 else 0.0
	_wobble_v += (target - _wobble) * 60.0 * delta
	_wobble_v *= pow(0.02, delta)
	_wobble += _wobble_v * delta
	_sprite.rotation = _wobble * 0.35 if hp > 0.0 else _wobble
	_sprite.modulate = Color(1, 1, 1, 0.55 if hp <= 0.0 else 1.0).lerp(Color(2.2, 1.8, 1.4), _flash * 0.6)
	_flash = maxf(0.0, _flash - delta * 5.0)
	queue_redraw()


func _draw() -> void:
	if hp <= 0.0:
		draw_string_outline(_font, Vector2(-80, -200), "Standing back up...", HORIZONTAL_ALIGNMENT_CENTER, 160, 16, 5, Color(0.05, 0.02, 0.05, 0.9))
		draw_string(_font, Vector2(-80, -200), "Standing back up...", HORIZONTAL_ALIGNMENT_CENTER, 160, 16, Color(1, 0.9, 0.7))
		return
	if hp < max_hp:
		var w := 90.0
		var r := Rect2(-w * 0.5, -212, w, 9)
		draw_rect(r.grow(2), Color(0.05, 0.02, 0.05, 0.85))
		draw_rect(Rect2(r.position, Vector2(w * hp / max_hp, r.size.y)), Color(1.0, 0.72, 0.3))
	var d := dps()
	if d > 0.5:
		var t := "%d DPS" % int(round(d))
		draw_string_outline(_font, Vector2(-60, -222), t, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, 5, Color(0.05, 0.02, 0.05, 0.9))
		draw_string(_font, Vector2(-60, -222), t, HORIZONTAL_ALIGNMENT_CENTER, 120, 18, Color(1, 0.88, 0.55))
