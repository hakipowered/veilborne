extends Node
## xvfb-run -a -s "-screen 0 1600x720x24" godot --rendering-driver opengl3 --path . --resolution 1600x720 res://tests/menu_shots.tscn -- --out=/dir [--only=name,name]
## Saves ui_<screen>.png for every front-end screen.
var out := "/tmp"
var only: PackedStringArray = []
var main: Node

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--only="): only = a.substr(7).split(",")
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	_run()

func _want(n: String) -> bool:
	return only.is_empty() or n in only

func _snap(n: String, wait := 1.2) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/ui_%s.png" % [out, n])
	print("shot ", n)

func _run() -> void:
	await get_tree().process_frame
	await _snap("title", 2.8)
	if _want("settings"):
		main.show_settings()
		await _snap("settings", 0.8)
		main.go_back()
	if _want("about"):
		main.show_about()
		await _snap("about", 0.8)
		main.go_back()
	# chronicle 2 filled, others empty
	Game.load_slot("solo", 1)
	Game.data["intro_seen"] = true
	Game.data["shards"] = 140
	Game.data["runs"] = 7
	Game.data["wins"] = 1
	Game.data["best_room"] = 4
	Game.data["meta"] = {"vitality": 2, "fury": 1, "defiance": 1}
	Game.save_slot()
	if _want("slots"):
		main.show_slots("solo")
		await _snap("slots", 1.4)
	if _want("coop"):
		main.show_coop()
		await _snap("coop", 1.2)
	if _want("sanctum"):
		main.coop_kind = ""
		main.show_sanctum()
		await _snap("sanctum", 1.4)
	if _want("sanctum_local"):
		main.coop_kind = "local"
		main.show_sanctum()
		await _snap("sanctum_local", 1.2)
		main.coop_kind = ""
	if _want("dialogue"):
		main.play_dialogue(load("res://data/story.gd").INTRO.slice(2, 5), func(): pass)
		await _snap("dialogue", 2.0)
		main._dialogue.advance()
		main._dialogue.advance()
		await _snap("dialogue2", 1.6)
		main._dialogue.skip_all()
	if _want("dialogue_warden"):
		main.play_dialogue([{"speaker": "regent", "text": "Little lights. You came all this way down to be swallowed."}, {"speaker": "oriel", "text": "Kneel, little spark. Oriel, Ember Queen, has decided you may burn on my behalf."}], func(): pass)
		await get_tree().create_timer(0.6).timeout
		main._dialogue.advance()
		main._dialogue.advance()
		await _snap("dialogue_warden", 2.4)
		main._dialogue.skip_all()
	if _want("results"):
		Game.run_room = 5
		main.screen = "arena"
		main._show_results(true, 96)
		await _snap("results_victory", 2.6)
		main._show_results(false, 23)
		await _snap("results_defeat", 2.6)
	Game.delete_slot("solo", 1)
	get_tree().quit()
