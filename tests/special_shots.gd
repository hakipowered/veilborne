extends Node
## Screenshots / GIF frames of each weapon's hold move and special, driven with a fake pad.
##   xvfb-run godot --rendering-driver opengl3 res://tests/special_shots.tscn --resolution 2448x1848 -- --out=/dir [--weapon=spear]
## Writes <weapon>_<tag>.png stills and <weapon>_seq_NNN.png frames (tools turn the frames into GIFs).

const DT := 1.0 / 60.0

class Pad:
	var move := Vector2.ZERO
	var attack := false
	var special := false
	var dash := false
	var special_aim := Vector2.ZERO

var out := ""
var only := ""
var seq_on := false
var arena: Node
var hero: Node
var pad := Pad.new()
var f := 0
var wi := 0
var t0 := 0
var START := Vector2.ZERO
var D := Vector2.RIGHT
var _dummies: Array = []
## per weapon: [frame, what] (what: pad commands or "shot:tag")
const SCRIPT := {
	"spear": [[5, "cd"], [6, "atk+"], [30, "shot:hold"], [52, "shot:hold_full"], [56, "atk-"], [60, "shot:whirl"], [66, "shot:whirl_b"],
		[110, "aim+"], [118, "shot:aim"], [119, "aim-"], [128, "shot:throw"], [150, "shot:lodged"], [200, "spc+"], [202, "spc-"], [206, "shot:recall"], [240, "end"]],
	"twin": [[5, "atk+"], [20, "shot:flurry"], [40, "atk-"], [60, "dash+"], [61, "dash-"], [65, "atk+"], [66, "atk-"], [70, "shot:lunge"],
		[110, "aim+"], [118, "shot:aim"], [119, "aim-"], [126, "shot:blink"], [140, "shot:afterimages"], [152, "shot:afterimage_cut"], [200, "end"]],
	"bow": [[5, "atk+"], [20, "shot:draw"], [37, "shot:perfect_flash"], [38, "atk-"], [42, "shot:perfect_shot"],
		[90, "aim+"], [98, "shot:aim"], [99, "aim-"], [130, "shot:starfall"], [150, "shot:starfall_b"], [200, "end"]],
	"shield": [[5, "cd"], [6, "atk+"], [40, "shot:guard"], [60, "proj"], [66, "shot:block"], [86, "shot:guard_full"], [90, "atk-"], [94, "shot:dawnbreak"], [100, "shot:dawnbreak_b"],
		[140, "aim+"], [148, "shot:aim"], [149, "aim-"], [170, "shot:throw"], [230, "end"]],
	"scythe": [[5, "atk+"], [6, "atk-"], [12, "atk+"], [13, "atk-"], [30, "souls"], [40, "cd"], [41, "atk+"], [78, "shot:harvest_charge"], [98, "atk-"], [103, "shot:harvest"], [109, "shot:harvest_b"],
		[130, "aim+"], [138, "shot:aim"], [139, "aim-"], [156, "shot:hook_out"], [166, "shot:hook_back"], [180, "shot:hook_pulled"], [220, "end"]],
}


func _ready() -> void:
	name = "Main"
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		if a == "--seq":
			seq_on = true
		if a.begins_with("--weapon="):
			only = a.substr(9)
	DirAccess.make_dir_recursive_absolute(out)
	Engine.max_physics_steps_per_frame = 1
	Game.load_slot("solo", 2)
	Game.data["meta"] = {}
	Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
	Game.set_loadout("spear", 0)
	Game.start_run(4242)
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	arena.set_physics_process(false)
	hero = arena.heroes()[0]
	hero.set_physics_process(false)
	hero.touch = pad
	START = arena.env.get_player_start()
	if only != "":
		wi = Game.WEAPON_ORDER.find(only)
	_setup_weapon()


func play_dialogue(_lines: Array, done: Callable) -> void:
	done.call()


func _setup_weapon() -> void:
	var w: String = Game.WEAPON_ORDER[wi]
	for e in arena.enemy_nodes.values():
		if is_instance_valid(e):
			e.queue_free()
	arena.enemy_nodes.clear()
	arena.casts.clear()
	arena.hshots.clear()
	arena.pools.clear()
	hero.boons = {"_weapon": w, "_aspect": 0}
	hero._apply_weapon(w, 0)
	hero.recompute_stats()
	hero.position = START
	hero.facing = D
	hero.state = "idle"
	hero.souls = 0.0
	hero.special_cd = 0.0
	hero.hp = hero.max_hp
	_dummies.clear()
	var offs := [D * 230.0, D * 300.0 + Vector2(0, 70), D * 170.0 + Vector2(0, -80), -D * 160.0 + Vector2(0, 40), D * 380.0]
	for o in offs:
		var e = arena.spawn_enemy("shade", START + o, 1.0)
		if e:
			e.hp = 99999.0
			e.max_hp = 99999.0
			_dummies.append(e)
	t0 = f
	arena.hud.subtitle(String(hero.wdef.get("hint", "")), Color(1.0, 0.85, 0.6))
	print("SHOTS: ", w)


func _physics_process(_d: float) -> void:
	f += 1
	if hero == null:
		return
	var w: String = Game.WEAPON_ORDER[wi]
	var lf := f - t0
	for step in SCRIPT[w]:
		if int(step[0]) != lf:
			continue
		var what: String = step[1]
		match what:
			"atk+": pad.attack = true
			"atk-": pad.attack = false
			"dash+": pad.dash = true
			"dash-": pad.dash = false
			"spc+": pad.special = true
			"spc-": pad.special = false
			"cd": hero.attack_cd = 0.25
			"souls": hero.souls = 80.0
			"aim+":
				pad.special = true
				pad.special_aim = (D * 240.0 + Vector2(0, 30)) / hero.aim_range()
			"aim-":
				pad.special = false
				pad.special_aim = Vector2.ZERO
			"proj":
				arena.projectiles.append({"id": 9, "pos": hero.position + D * 260.0, "vel": -D * 700.0, "dmg": 10.0, "color": Color(0.6, 1.0, 0.4), "r": 12.0, "life": 2.0, "src": ""})
			"end":
				wi += 1
				if only != "" or wi >= Game.WEAPON_ORDER.size():
					get_tree().quit()
					return
				_setup_weapon()
				return
			_:
				if what.begins_with("shot:"):
					_shot("%s_%s" % [w, what.substr(5)])
	# keep the dummies standing still and alive
	for e in _dummies:
		if is_instance_valid(e):
			e.hp = 99999.0
			e._knock = Vector2.ZERO
	arena._ecache.clear()
	for e in arena.enemy_nodes.values():
		if is_instance_valid(e):
			arena._ecache.append(e)
	hero._simulate(DT)
	hero.anim_t += DT
	hero.queue_redraw()
	arena._local_damage_checks(DT)
	arena._update_casts(DT)
	arena._update_hshots(DT)
	arena._update_fx(DT)
	arena._update_camera(DT)
	arena.camera.zoom = Vector2(1.75, 1.75)
	if is_instance_valid(arena.hud._card):
		arena.hud._card.visible = false
	arena.overlay.queue_redraw()
	arena.groundfx.queue_redraw()
	arena.airfx.queue_redraw()
	arena.ghostfx.queue_redraw()
	arena.queue_redraw()
	if lf % 3 == 0 and lf > 0 and seq_on:
		_shot("%s_seq_%03d" % [w, lf / 3])


func _shot(n: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, n])
