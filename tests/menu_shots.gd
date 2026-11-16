extends Node
## xvfb-run godot --path . res://tests/menu_shots.tscn -- --out=/dir
var out := "/tmp"
var main: Node
func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	_run()
func _snap(n: String) -> void:
	await get_tree().create_timer(1.5).timeout
	get_viewport().get_texture().get_image().save_png("%s/menu_%s.png" % [out, n])
	print("shot ", n)
func _run() -> void:
	await _snap("title")
	Game.load_slot("solo", 1)
	Game.data["intro_seen"] = true
	Game.data["shards"] = 140
	main.show_sanctum()
	await _snap("sanctum")
	main.show_slots("solo")
	await _snap("slots")
	main.play_dialogue(load("res://data/story.gd").INTRO, func(): pass)
	await get_tree().create_timer(2.5).timeout
	await _snap("dialogue")
	Game.delete_slot("solo", 1)
	get_tree().quit()
