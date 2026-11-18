extends Node
## xvfb-run -a -s "-screen 0 2448x1848x24" godot --rendering-driver opengl3 --path . res://tests/menu_shots.tscn -- --resolution=2448x1848 --out=/dir [--only=name,name] [--safe=l,t,r,b]
## Saves ui_<screen>.png for every front-end screen and prints a layout audit (CLIP / OVERLAP lines)
## for each one. --resolution resizes the window (the xvfb screen must be at least that big);
## --safe simulates notch insets in canvas units.
const Audit = preload("res://tests/layout_audit.gd")
const VTheme = preload("res://ui/theme.gd")
var out := "/tmp"
var only: PackedStringArray = []
var main: Node
var problems := 0

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--only="): only = a.substr(7).split(",")
		if a.begins_with("--resolution="):
			var p := a.substr(13).split("x")
			get_window().mode = Window.MODE_WINDOWED
			get_window().position = Vector2i.ZERO
			get_window().size = Vector2i(int(p[0]), int(p[1]))
		if a.begins_with("--safe="):
			var s := a.substr(7).split(",")
			VTheme.debug_insets = Vector4(float(s[0]), float(s[1]), float(s[2]), float(s[3]))
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	_run()

func _want(n: String) -> bool:
	return only.is_empty() or n in only

func _snap(n: String, wait := 1.2) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/ui_%s.png" % [out, n])
	var issues := Audit.audit(get_tree())
	problems += issues.size()
	print("shot ", n, "  ", get_viewport().get_visible_rect().size, "  issues=", issues.size())
	for s in issues:
		print("   ", s)

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
	if _want("erase"):
		main._confirm_delete("solo", 1)
		await _snap("erase", 0.8)
		main.go_back()
	if _want("coop"):
		main.show_coop()
		await _snap("coop", 1.2)
	if _want("sanctum"):
		main.coop_kind = ""
		main.show_sanctum()
		await _snap("sanctum", 1.4)
	if _want("sanctum_host"):
		Game.mode = "coop"
		Net.online = true
		Net.room_code = "QR7KM"
		Net.lobby = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
		main.coop_kind = "host"
		main.show_sanctum()
		await _snap("sanctum_host", 1.4)
		Net.online = false
		Net.room_code = ""
		main.coop_kind = ""
	if _want("sanctum_locked"):
		# preview a locked aspect: the Unlock button joins the row (widest state of the picker)
		main._cycle_aspect()
		await _snap("sanctum_locked", 0.6)
		main._aspect_view = -1
		main._refresh_weapons()
	if _want("sanctum_local"):
		main.coop_kind = "local"
		main.show_sanctum()
		await _snap("sanctum_local", 1.2)
		main.coop_kind = ""
	if _want("resize"):
		# fold / rotate while in the Sanctum: the layout is rebuilt for the new aspect
		main.show_sanctum()
		await get_tree().create_timer(0.6).timeout
		var w0 := get_window().size
		var w1 := Vector2i(w0.y * 4 / 3, w0.y) if float(w0.x) / w0.y > 1.5 else Vector2i(w0.x, w0.x * 9 / 20)
		get_window().size = w1
		await _snap("sanctum_resized", 1.4)
		get_window().size = w0
		await get_tree().create_timer(0.8).timeout
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
	print("LAYOUT ISSUES TOTAL ", problems)
	get_tree().quit()
