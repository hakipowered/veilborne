extends Node
## Screenshots of the heroine holding each weapon.
##   xvfb-run godot --rendering-driver opengl3 res://tests/weapon_shots.tscn --resolution 2448x1848 -- --out=/dir [--hero=kaela] [--tag=after]
##     manor armory: idle + mid-swing + running, one pair per weapon
##   ... -- --out=/dir --sheet [--hero=kaela]
##     pose sheet per weapon: 8 facings x (idle, run, attack1-3 hit frames, special, dash)

const ManorScript := preload("res://scenes/manor.gd")
const AnimSpriteScript := preload("res://entities/anim_sprite.gd")

class FakePad:
	var move := Vector2.ZERO
	var attack := false
	var special := false
	var dash := false
	var special_aim := Vector2.ZERO

var out := ""
var tag := "shot"
var hero_id := "kaela"
var sheet := false
var hub: Node
var pad := FakePad.new()
var wi := 0
var f := 0


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--hero="):
			hero_id = a.substr(7)
		elif a.begins_with("--tag="):
			tag = a.substr(6)
		elif a == "--sheet":
			sheet = true
	DirAccess.make_dir_recursive_absolute(out)
	if sheet:
		return
	Engine.max_physics_steps_per_frame = 1
	Game.load_slot("solo", 2)
	Game.data["decor"] = {"lanterns": true, "rugs": true, "banners": true, "fountain": true, "statues": true}
	Game.data["last_hero"] = hero_id
	hub = load("res://scenes/hub.gd").new()
	add_child(hub)
	hub.setup_hub(hero_id, false)
	hub.hero.touch = pad


func _shot(name_: String) -> void:
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s_%s_%s.png" % [out, tag, hero_id, name_])
	print("SHOT ", name_)


func _process(_d: float) -> void:
	if sheet:
		_sheet_step()


func _physics_process(_d: float) -> void:
	if sheet:
		return
	f += 1
	if wi >= Game.WEAPON_ORDER.size():
		get_tree().quit()
		return
	var w: String = Game.WEAPON_ORDER[wi]
	if f == 1:
		hub._equip(w, 0)
		var gp := Vector2(-60, -960)
		hub.hero.position = ManorScript.w(gp.x, gp.y)
		hub.hero.facing = Vector2(1, 0.5).normalized()
		hub.camera.position = hub.hero.position
		hub.camera.reset_smoothing()
		pad.move = Vector2(0.01, 0.01)
	if f == 4:
		pad.move = Vector2.ZERO
	if f == 50:
		_shot(w + "_idle")
		pad.attack = true
	if f == 54:
		pad.attack = false
	if f == 60:
		_shot(w + "_attack")
	if f == 90:
		pad.move = Vector2(-1, 0.3).normalized()
	if f == 112:
		_shot(w + "_run")
		pad.move = Vector2.ZERO
	if f == 130:
		wi += 1
		f = 0


# ---------------------------------------------------------------- pose sheet

const COLS := [["idle", 0], ["run", 2], ["run", 8], ["attack1", -1], ["attack2", -1], ["attack3", -1], ["special", -1], ["dash", 3]]
var _sheet_nodes: Array = []
var _sheet_w := 0
var _sheet_f := 0


func _sheet_step() -> void:
	_sheet_f += 1
	if _sheet_f == 1:
		_build_sheet(Game.WEAPON_ORDER[_sheet_w])
	elif _sheet_f == 6:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/sheet_%s_%s.png" % [out, hero_id, Game.WEAPON_ORDER[_sheet_w]])
		print("SHEET ", Game.WEAPON_ORDER[_sheet_w])
		for n in _sheet_nodes:
			n.queue_free()
		_sheet_nodes.clear()
		_sheet_w += 1
		_sheet_f = 0
		if _sheet_w >= Game.WEAPON_ORDER.size():
			get_tree().quit()


func _build_sheet(w: String) -> void:
	var vs := get_viewport().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color(0.36, 0.32, 0.34)
	bg.size = vs
	add_child(bg)
	_sheet_nodes.append(bg)
	var cw := vs.x / COLS.size()
	var rh := vs.y / 8.0
	var h := rh * 0.78
	for r in 8:
		var ang := PI * 0.5 + r * PI * 0.25    # screen-down first, then clockwise
		var dir := Vector2(cos(ang), sin(ang) * 0.64)
		for c in COLS.size():
			var s = AnimSpriteScript.new()
			s.position = Vector2(cw * (c + 0.5), rh * (r + 0.95))
			add_child(s)
			s.setup(hero_id, h)
			if s.has_method("set_weapon"):
				s.set_weapon(w)
			s.set_facing(dir)
			var an: String = COLS[c][0]
			s.play(an, true)
			var fr: int = COLS[c][1]
			if fr < 0:
				fr = maxi(0, s.get_event_frame(an, "hit"))
			s.frame = mini(fr, int(s._anim.get("n", 1)) - 1)
			s._show()
			s.set_speed_scale(0.0)
			_sheet_nodes.append(s)
