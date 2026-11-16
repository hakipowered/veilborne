extends Control
## Multi-touch controls: floating joystick on the left, action buttons on the right.

var move := Vector2.ZERO
var attack := false
var special := false
var dash := false

const JOY_RADIUS := 90.0
var _touches := {} ## index -> {"role": String, "origin": Vector2, "pos": Vector2}
var hero: Node = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE

## Screen size in canvas units (robust even if this Control's own rect is not laid out yet).
func _screen() -> Vector2:
	return get_viewport_rect().size

func _buttons() -> Dictionary:
	var s := _screen()
	return {
		"attack": [Vector2(s.x - 140, s.y - 140), 78.0, "ATTACK", Color(1.0, 0.55, 0.25)],
		"dash": [Vector2(s.x - 300, s.y - 95), 56.0, "DASH", Color(0.55, 0.85, 1.0)],
		"special": [Vector2(s.x - 120, s.y - 310), 56.0, "SPECIAL", Color(0.85, 0.5, 1.0)],
	}

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			var role := "joy"
			for k in _buttons().keys():
				var b: Array = _buttons()[k]
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
	for t in _touches.values():
		match t["role"]:
			"joy":
				var d: Vector2 = (t["pos"] - t["origin"]) / JOY_RADIUS
				move = d.limit_length(1.0) if d.length() > 0.15 else Vector2.ZERO
			"attack": attack = true
			"special": special = true
			"dash": dash = true
	queue_redraw()

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		_touches.clear()
		_recompute()

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var joy_drawn := false
	for t in _touches.values():
		if t["role"] == "joy":
			joy_drawn = true
			draw_circle(t["origin"], JOY_RADIUS, Color(0, 0, 0, 0.3))
			draw_arc(t["origin"], JOY_RADIUS, 0, TAU, 48, Color(1, 0.85, 0.5, 0.6), 3.0)
			draw_circle(t["origin"] + move * JOY_RADIUS, 38, Color(1, 0.85, 0.5, 0.55))
	if not joy_drawn:
		var c := Vector2(170, _screen().y - 160)
		draw_arc(c, JOY_RADIUS, 0, TAU, 48, Color(1, 0.85, 0.5, 0.25), 3.0)
		draw_circle(c, 34, Color(1, 0.85, 0.5, 0.15))
	var b := _buttons()
	for k in b.keys():
		var info: Array = b[k]
		var held: bool = get(k)
		var col: Color = info[3]
		var ready := 1.0
		if is_instance_valid(hero):
			if k == "special":
				ready = 1.0 - clampf(hero.special_cd / 2.6, 0.0, 1.0)
			elif k == "dash":
				ready = 1.0 if hero.dash_charges > 0 else 0.3
		draw_circle(info[0], info[1] + 4, Color(0.05, 0.02, 0.06, 0.7))
		draw_circle(info[0], info[1], Color(col, 0.55 if held else 0.28))
		draw_arc(info[0], info[1], -PI / 2, -PI / 2 + TAU * ready, 48, Color(col, 0.95), 5.0)
		draw_string_outline(font, info[0] + Vector2(-60, 8), info[2], HORIZONTAL_ALIGNMENT_CENTER, 120, 20, 5, Color(0, 0, 0, 0.8))
		draw_string(font, info[0] + Vector2(-60, 8), info[2], HORIZONTAL_ALIGNMENT_CENTER, 120, 20, Color.WHITE)

func _process(_delta: float) -> void:
	if is_instance_valid(hero) and (hero.special_cd > 0.0 or hero.dash_charges == 0):
		queue_redraw()
