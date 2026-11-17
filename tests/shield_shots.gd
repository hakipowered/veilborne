extends Node
## Screenshots of the thrown Aegis shield: in flight, lodged and spinning (Bastion), ricocheting home.
##   xvfb-run godot --rendering-driver opengl3 res://tests/shield_shots.tscn --resolution 2448x1848 -- --out=/dir

var out := ""
var arena: Node
var hero: Node
var f := 0
var shots := {8: "throw", 22: "flight", 25: "flight_b", 40: "lodged_a", 70: "lodged_b", 95: "lodged_c", 140: "lodged_d", 330: "return"}


func _ready() -> void:
	name = "Main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	Engine.max_physics_steps_per_frame = 1
	Game.load_slot("solo", 2)
	Game.data["aspects"] = {"shield": [1, 2]}
	Game.set_loadout("shield", 2)
	Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
	Game.start_run(4242)
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	for h in arena.heroes():
		if h.controlled:
			hero = h
	hero.add_forge("shield_rebound", 1)


func play_dialogue(_lines: Array, done: Callable) -> void:
	done.call()


func _physics_process(_d: float) -> void:
	f += 1
	if hero == null:
		return
	hero.hp = hero.max_hp
	if f == 1:
		hero.special_cd = 0.0
	if f == 2:
		var aim: Vector2 = hero.position + Vector2(300, 90)
		arena._start_cast(hero, hero.position, Vector2(1, 0.3).normalized(), aim, 9001, arena.MODE_AUTH)
	if shots.has(f - 330) and f > 330:
		_shot(String(shots[f - 330]))
	if f == 330:
		# re-throw after the scene has settled
		var aim2: Vector2 = hero.position + Vector2(230, 70)
		arena._start_cast(hero, hero.position, Vector2(1, 0.3).normalized(), aim2, 9002, arena.MODE_AUTH)
	if f > 720:
		get_tree().quit()


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/shield_%s.png" % [out, n])
	print("SHOT ", n)
