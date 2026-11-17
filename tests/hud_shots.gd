extends Node
## xvfb-run -a -s "-screen 0 2448x1848x24" godot --rendering-driver opengl3 --path . res://tests/hud_shots.tscn -- --resolution=2448x1848 --out=/dir [--safe=l,t,r,b]
## In-run HUD screenshots: combat HUD + touch controls, low health, boon choice, forge choice, pause,
## pause settings, boss bar. Prints a layout audit (CLIP / OVERLAP lines) for each.
const Audit = preload("res://tests/layout_audit.gd")
const VTheme = preload("res://ui/theme.gd")
var out := "/tmp"
var arena
var problems := 0
func _ready() -> void:
	name = "Main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		if a.begins_with("--resolution="):
			var p := a.substr(13).split("x")
			get_window().mode = Window.MODE_WINDOWED
			get_window().position = Vector2i.ZERO
			get_window().size = Vector2i(int(p[0]), int(p[1]))
		if a.begins_with("--safe="):
			var s := a.substr(7).split(",")
			VTheme.debug_insets = Vector4(float(s[0]), float(s[1]), float(s[2]), float(s[3]))
	DirAccess.make_dir_recursive_absolute(out)
	Game.load_slot("solo", 2)
	Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
	Game.start_run(7)
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	_run()
func play_dialogue(_l, done: Callable) -> void: done.call()
func _snap(n: String, wait := 1.0) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/ui_%s.png" % [out, n])
	var issues := Audit.audit(get_tree())
	problems += issues.size()
	print("shot ", n, "  ", get_viewport().get_visible_rect().size, "  issues=", issues.size())
	for s in issues:
		print("   ", s)
func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	var hud = arena.hud
	if hud.touch == null:
		# desktop run: add the touch controls anyway so they are in the shots
		hud.touch = hud.TouchScript.new()
		hud.root.add_child(hud.touch)
		hud.touch.hero = arena.heroes()[0]
	var h = arena.heroes()[0]
	for id in ["ember_strike", "chain_arc", "tidal_heart", "thorn_crit", "gale_feet"]:
		h.boons[id] = {"level": 1 + (1 if id == "chain_arc" else 0), "rarity": randi() % 3}
	hud.refresh()
	Game.run_shards = 37
	await _snap("hud", 1.5)
	h.hp = h.max_hp * 0.25
	h.special_cd = 1.4
	h.dash_charges = 0
	await _snap("hud_lowhp", 0.9)
	h.hp = h.max_hp
	var choices := [{"id": "kindle", "rarity": 0, "upgrade": false}, {"id": "chain_arc", "rarity": 1, "upgrade": true}, {"id": "briar_ward", "rarity": 2, "upgrade": false}]
	hud.show_boon_choice(h, choices, func(_id, _r): print("picked ", _id))
	await _snap("boon_choice", 1.4)
	await _pick_first()
	var fc := [{"id": "spear_echo", "rarity": 0, "forge": true}, {"id": "spear_comet", "rarity": 1, "forge": true}, {"id": "spear_cinder", "rarity": 2, "forge": true}]
	hud.show_forge_choice(h, fc, func(_id, _r): print("forged ", _id))
	await _snap("forge_choice", 1.4)
	await _pick_first()
	hud._toggle_pause()
	await _snap("pause", 0.8)
	for b in hud.pause_panel.find_children("*", "Button", true, false):
		if (b as Button).text == "Settings":
			b.pressed.emit()
			break
	await _snap("pause_settings", 0.6)
	hud._toggle_pause()
	var boss = arena.spawn_enemy("regent", h.position + Vector2(260, -60))
	if boss:
		boss.hp = boss.max_hp * 0.62
	await _snap("boss", 2.0)
	print("LAYOUT ISSUES TOTAL ", problems)
	get_tree().quit()
func _pick_first() -> void:
	if arena.hud.boon_panel:
		for b in arena.hud.boon_panel.find_children("*", "Button", true, false):
			b.pressed.emit()
			break
	await get_tree().create_timer(0.6).timeout
