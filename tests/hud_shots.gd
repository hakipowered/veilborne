extends Node
## xvfb-run -a -s "-screen 0 1600x720x24" godot --rendering-driver opengl3 --path . --resolution 1600x720 res://tests/hud_shots.tscn -- --out=/dir
## In-run HUD screenshots: combat HUD + touch, low health, boon choice, pause, boss bar.
var out := "/tmp"
var arena
func _ready() -> void:
	name = "Main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
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
	print("shot ", n)
func _run() -> void:
	await get_tree().create_timer(0.5).timeout
	var h = arena.heroes()[0]
	for id in ["ember_strike", "chain_arc", "tidal_heart", "thorn_crit", "gale_feet"]:
		h.boons[id] = {"level": 1 + (1 if id == "chain_arc" else 0), "rarity": randi() % 3}
	arena.hud.refresh()
	Game.run_shards = 37
	await _snap("hud", 1.5)
	h.hp = h.max_hp * 0.25
	h.special_cd = 1.4
	h.dash_charges = 0
	await _snap("hud_lowhp", 0.9)
	h.hp = h.max_hp
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var choices := [{"id": "kindle", "rarity": 0, "upgrade": false}, {"id": "chain_arc", "rarity": 1, "upgrade": true}, {"id": "briar_ward", "rarity": 2, "upgrade": false}]
	arena.hud.show_boon_choice(h, choices, func(_id, _r): print("picked ", _id))
	await _snap("boon_choice", 1.4)
	for b in arena.hud.boon_panel.find_children("*", "Button", true, false):
		b.pressed.emit()
		break
	await get_tree().create_timer(0.6).timeout
	arena.hud._toggle_pause()
	await _snap("pause", 0.8)
	arena.hud._toggle_pause()
	var boss = arena.spawn_enemy("regent", h.position + Vector2(260, -60))
	if boss:
		boss.hp = boss.max_hp * 0.62
	await _snap("boss", 2.0)
	get_tree().quit()
