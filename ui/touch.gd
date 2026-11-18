extends Control
## Multi-touch controls: floating joystick on the left, gilded action medallions on the right.
## Positions are computed from get_viewport_rect() (robust even before this Control is laid out).

const VTheme = preload("res://ui/theme.gd")

var move := Vector2.ZERO
var attack := false
var special := false
var dash := false
## Aimed special: while the Special button is held, dragging moves the landing reticle.
## -1..1 offset (ZERO = no drag: the heroine auto-aims). Read by hero.gd.
var special_aim := Vector2.ZERO
const AIM_DRAG := 130.0

const JOY_RADIUS := 92.0
const SPECIAL_CD := 2.6
var _touches := {} ## index -> {"role": String, "origin": Vector2, "pos": Vector2}
var hero: Node = null

var _orb: Texture2D
var _ring: Texture2D
var _dot: Texture2D
var _glyphs := {}
var _last_sig := -1


func _ready() -> void:
	# covers the whole screen (so local == viewport coordinates) even inside the safe-area HUD root
	VTheme.bleed(self)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_orb = VTheme.tex("orb")
	_ring = VTheme.tex("ring")
	_dot = VTheme.tex("dot")
	_glyphs = {"attack": VTheme.tex("glyph_attack"), "dash": VTheme.tex("glyph_dash"), "special": VTheme.tex("glyph_special")}


## Screen size in canvas units (robust even if this Control's own rect is not laid out yet).
func _screen() -> Vector2:
	return get_viewport_rect().size


## [center, radius, label, accent color]. Anchored to the bottom-right corner of the safe area,
## so a notch or rounded corner never eats a button.
func _buttons() -> Dictionary:
	var s := VTheme.safe_rect(get_viewport()).end
	return {
		"attack": [Vector2(s.x - 150, s.y - 150), 84.0, "ATTACK", Color(1.0, 0.6, 0.25)],
		"dash": [Vector2(s.x - 322, s.y - 98), 62.0, "DASH", Color(0.55, 0.85, 1.0)],
		"special": [Vector2(s.x - 128, s.y - 328), 62.0, "SPECIAL", Color(0.88, 0.55, 1.0)],
	}


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var role := "joy"
			var bs := _buttons()
			for k in bs.keys():
				var b: Array = bs[k]
				if event.position.distance_to(b[0]) < b[1] * 1.25:
					role = k
			if role == "joy" and event.position.x > _screen().x * 0.5:
				return
			_touches[event.index] = {"role": role, "origin": event.position, "pos": event.position}
		else:
			_touches.erase(event.index)
		_recompute()
	elif event is InputEventScreenDrag and _touches.has(event.index):
		_touches[event.index]["pos"] = event.position
		_recompute()


func _recompute() -> void:
	move = Vector2.ZERO
	attack = false
	special = false
	dash = false
	special_aim = Vector2.ZERO
	for t in _touches.values():
		match t["role"]:
			"joy":
				var d: Vector2 = (t["pos"] - t["origin"]) / JOY_RADIUS
				move = d.limit_length(1.0) if d.length() > 0.15 else Vector2.ZERO
			"attack": attack = true
			"special":
				special = true
				var sd: Vector2 = (t["pos"] - t["origin"]) / AIM_DRAG
				special_aim = sd.limit_length(1.0) if sd.length() > 0.18 else Vector2.ZERO
			"dash": dash = true
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touches.clear()
		_recompute()


func _draw() -> void:
	var font := VTheme.font("caps")
	var joy_drawn := false
	for t in _touches.values():
		if t["role"] == "joy":
			joy_drawn = true
			var o: Vector2 = t["origin"]
			draw_circle(o, JOY_RADIUS, Color(0.03, 0.01, 0.04, 0.35))
			if _ring:
				draw_texture_rect(_ring, Rect2(o - Vector2.ONE * (JOY_RADIUS + 14), Vector2.ONE * (JOY_RADIUS + 14) * 2), false, Color(1, 1, 1, 0.85))
			var k := o + move * JOY_RADIUS
			if _dot:
				draw_texture_rect(_dot, Rect2(k - Vector2(56, 56), Vector2(112, 112)), false, Color(1.0, 0.6, 0.25, 0.35))
			if _orb:
				draw_texture_rect(_orb, Rect2(k - Vector2(40, 40), Vector2(80, 80)), false)
	if not joy_drawn:
		var sr := VTheme.safe_rect(get_viewport())
		var c := Vector2(sr.position.x + 180, sr.end.y - 170)
		if _ring:
			draw_texture_rect(_ring, Rect2(c - Vector2.ONE * (JOY_RADIUS + 14), Vector2.ONE * (JOY_RADIUS + 14) * 2), false, Color(1, 1, 1, 0.3))
		if _orb:
			draw_texture_rect(_orb, Rect2(c - Vector2(34, 34), Vector2(68, 68)), false, Color(1, 1, 1, 0.3))
	var b := _buttons()
	for key in b.keys():
		var info: Array = b[key]
		var held: bool = get(key)
		var col: Color = info[3]
		var ctr: Vector2 = info[0]
		var r: float = info[1] * (0.93 if held else 1.0)
		var ready := 1.0
		if is_instance_valid(hero):
			if key == "special":
				ready = 1.0 - clampf(hero.special_cd / maxf(0.1, float(hero.special_cd_max)), 0.0, 1.0)
			elif key == "dash":
				ready = 1.0 if hero.dash_charges > 0 else 0.3
		var a := 0.92 if ready >= 1.0 else 0.6
		if held and _dot:
			draw_texture_rect(_dot, Rect2(ctr - Vector2.ONE * r * 1.7, Vector2.ONE * r * 3.4), false, Color(col.r, col.g, col.b, 0.55))
		if _orb:
			draw_texture_rect(_orb, Rect2(ctr - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(1, 1, 1, a) if not held else Color(1.25, 1.15, 1.0, 1.0))
		var g: Texture2D = _glyphs.get(key)
		if g:
			var gs := r * 1.05
			var gw := gs * float(g.get_width()) / float(g.get_height())
			if gw > gs * 1.15:
				gw = gs * 1.15
				gs = gw * float(g.get_height()) / float(g.get_width())
			draw_texture_rect(g, Rect2(ctr - Vector2(gw, gs) * 0.5, Vector2(gw, gs)), false, Color(1, 1, 1, 1.0 if ready >= 1.0 else 0.4))
		if ready < 1.0:
			draw_arc(ctr, r * 0.66, -PI / 2, -PI / 2 + TAU * ready, 40, Color(col.r, col.g, col.b, 0.95), 5.0, true)
		if key == "attack" and is_instance_valid(hero) and String(hero.state) in ["hold", "draw"]:
			# the hold move's charge fills round the ATTACK medallion; it blazes white when it is time to let go
			var ch: float = clampf(float(hero.charge), 0.0, 1.0)
			var full: bool = ch >= 1.0
			draw_arc(ctr, r * 1.12, -PI / 2, -PI / 2 + TAU * ch, 48, Color(1, 0.95, 0.8) if full else Color(col.r, col.g, col.b, 0.95), 8.0 if full else 6.0, true)
			if full and _dot:
				draw_texture_rect(_dot, Rect2(ctr - Vector2.ONE * r * 2.0, Vector2.ONE * r * 4.0), false, Color(1, 0.95, 0.8, 0.5))
		if key == "special" and held:
			# aim stick: a gilded knob dragged out of the medallion
			var tip := ctr + special_aim * r * 1.5
			draw_arc(ctr, r * 1.5, 0, TAU, 40, Color(col.r, col.g, col.b, 0.45), 3.0, true)
			if special_aim != Vector2.ZERO:
				draw_line(ctr, tip, Color(col.r, col.g, col.b, 0.8), 5.0, true)
			if _orb:
				draw_texture_rect(_orb, Rect2(tip - Vector2(26, 26), Vector2(52, 52)), false)
		var ly := ctr.y + r + 18.0
		draw_string_outline(font, Vector2(ctr.x - 80, ly), info[2], HORIZONTAL_ALIGNMENT_CENTER, 160, 15, 5, Color(0.03, 0.01, 0.04, 0.85))
		draw_string(font, Vector2(ctr.x - 80, ly), info[2], HORIZONTAL_ALIGNMENT_CENTER, 160, 15, Color(1, 0.92, 0.78, 0.85))
		if key == "attack" and is_instance_valid(hero):
			# what holding ATTACK does with this weapon (HOLD: GUARD, HOLD: DRAW...)
			var hl := String(hero.wdef.get("hold", ""))
			if hl != "":
				draw_string_outline(font, Vector2(ctr.x - 90, ly + 18), hl, HORIZONTAL_ALIGNMENT_CENTER, 180, 12, 4, Color(0.03, 0.01, 0.04, 0.85))
				draw_string(font, Vector2(ctr.x - 90, ly + 18), hl, HORIZONTAL_ALIGNMENT_CENTER, 180, 12, Color(1, 0.8, 0.5, 0.75))


func _process(_delta: float) -> void:
	if not is_instance_valid(hero):
		return
	# redraw only while cooldown visuals are changing
	var sig := (int(hero.special_cd * 30.0) * 8 + int(hero.dash_charges)) * 64 + int(float(hero.charge) * 40.0) + (50 if String(hero.state) in ["hold", "draw"] else 0)
	if sig != _last_sig:
		_last_sig = sig
		queue_redraw()
