extends Node
var arena
var f := 0
var start := Vector2.ZERO
func _ready() -> void:
	name = "Main"
	Game.load_slot("solo", 2)
	Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
	Game.start_run(1)
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	print("touch ctrl: ", arena.hud.touch, " touchscreen=", DisplayServer.is_touchscreen_available())
func play_dialogue(_l, done: Callable) -> void: done.call()
func _physics_process(_d: float) -> void:
	f += 1
	var h = arena.heroes()[0]
	if f == 30:
		start = h.position
		var e := InputEventScreenTouch.new(); e.index = 0; e.position = Vector2(200, 500); e.pressed = true
		Input.parse_input_event(e)
	if f == 32:
		var d := InputEventScreenDrag.new(); d.index = 0; d.position = Vector2(320, 500); d.relative = Vector2(120, 0)
		Input.parse_input_event(d)
	if f == 60:
		var vs := get_viewport().get_visible_rect().size
		var a := InputEventScreenTouch.new(); a.index = 1; a.position = Vector2(vs.x - 140, vs.y - 140); a.pressed = true
		Input.parse_input_event(a)
	if f == 64:
		print("attack held=", arena.hud.touch.attack, " hero state=", h.state)
		get_viewport().get_texture().get_image().save_png("/tmp/claude-0/shots/touch_phone.png")
	if f == 90:
		print("touch.move=", arena.hud.touch.move if arena.hud.touch else null, " hero moved: ", h.position - start, " touch size=", arena.hud.touch.size if arena.hud.touch else null)
		get_tree().quit()
