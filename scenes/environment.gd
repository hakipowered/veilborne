extends Node2D
## Veilborne chamber environment (ENVIRONMENT agent).
## Builds one painted isometric chamber: parallax abyss, ledges, iso slab floor with a Warden sigil,
## back walls, exit gate, y-sorted props with collision, animated fire / light pools / particles,
## foreground silhouettes and a vignette. See docs/OVERHAUL.md "Environment" for the interface.
##
## Layers (z_index, relative to this node which should sit at the arena origin with z 0):
##   -100 abyss backdrop (opaque, parallax)   -95 void particles   -80 ledges   -70 floor
##   -60 walls  -58 wall banners  -55 gate  -54 gate light rays   0 y-sorted props (lead's entity layer)
##   +20 foreground silhouettes / debris    CanvasLayer 2: vignette (below HUD layer 10)

const ENV := "res://art/env/"
const MAX_LIGHTS := 16
const SHADER_LIGHTS := 6

const THEMES := {
	"oriel": {
		"sigil": "oriel", "sigil_color": Color(1.0, 0.56, 0.2), "statue": "statue_oriel",
		"flame": [Color(1.0, 0.95, 0.7), Color(1.0, 0.55, 0.15), Color(0.8, 0.14, 0.04)],
		"light": Color(1.0, 0.58, 0.26), "tint": Color(1.06, 1.0, 0.92), "fog": Color(0.42, 0.34, 0.26),
		"mist": Color(0.22, 0.36, 0.33), "particles": "embers", "name": "Hall of Embers",
	},
	"vessa": {
		"sigil": "vessa", "sigil_color": Color(0.55, 0.8, 1.0), "statue": "statue_vessa",
		"flame": [Color(0.9, 0.97, 1.0), Color(0.4, 0.7, 1.0), Color(0.12, 0.22, 0.85)],
		"light": Color(0.5, 0.7, 1.0), "tint": Color(0.92, 0.98, 1.08), "fog": Color(0.32, 0.4, 0.55),
		"mist": Color(0.2, 0.28, 0.42), "particles": "sparks", "name": "Stormwell Crypt",
	},
	"mireth": {
		"sigil": "mireth", "sigil_color": Color(0.32, 0.95, 0.85), "statue": "statue_mireth",
		"flame": [Color(0.85, 1.0, 0.95), Color(0.25, 0.85, 0.8), Color(0.05, 0.3, 0.45)],
		"light": Color(0.35, 0.9, 0.82), "tint": Color(0.9, 1.04, 1.04), "fog": Color(0.3, 0.5, 0.52),
		"mist": Color(0.16, 0.4, 0.42), "particles": "bubbles", "name": "Drowned Ossuary",
	},
	"sable": {
		"sigil": "sable", "sigil_color": Color(1.0, 0.38, 0.52), "statue": "statue_sable",
		"flame": [Color(1.0, 0.85, 0.88), Color(1.0, 0.3, 0.45), Color(0.55, 0.04, 0.18)],
		"light": Color(1.0, 0.42, 0.5), "tint": Color(1.04, 0.94, 0.96), "fog": Color(0.45, 0.28, 0.33),
		"mist": Color(0.32, 0.2, 0.26), "particles": "petals", "name": "Briar Sepulchre",
	},
	"regent": {
		"sigil": "regent", "sigil_color": Color(0.78, 0.52, 1.0), "statue": "",
		"flame": [Color(1.0, 0.9, 1.0), Color(0.75, 0.4, 1.0), Color(0.3, 0.06, 0.6)],
		"light": Color(0.72, 0.48, 1.0), "tint": Color(1.0, 1.0, 1.0), "fog": Color(0.35, 0.25, 0.5),
		"mist": Color(0.3, 0.2, 0.45), "particles": "motes_violet", "name": "Throne of the Hollow Regent",
	},
}

## kind -> texture, world height, collision radius (0 = walk-through), foot (fraction of texture height
## from the bottom where the object touches the floor), shadow width (world px)
const PROPS := {
	"pillar": {"tex": "props/pillar.png", "h": 430.0, "r": 42.0, "foot": 0.02, "shadow": 140.0},
	"pillar_frame": {"tex": "props/pillar.png", "h": 560.0, "r": 0.0, "foot": 0.02, "shadow": 160.0},
	"pillar_big": {"tex": "props/pillar.png", "h": 760.0, "r": 0.0, "foot": 0.02, "shadow": 220.0},
	"broken_column": {"tex": "props/broken_column.png", "h": 220.0, "r": 44.0, "foot": 0.12, "shadow": 190.0},
	"brazier": {"tex": "props/brazier.png", "h": 120.0, "r": 34.0, "foot": 0.03, "shadow": 110.0},
	"urns": {"tex": "props/urns.png", "h": 150.0, "r": 40.0, "foot": 0.05, "shadow": 140.0},
	"skulls": {"tex": "props/skulls.png", "h": 120.0, "r": 40.0, "foot": 0.06, "shadow": 150.0},
	"statue_oriel": {"tex": "props/statue_oriel.png", "h": 340.0, "r": 52.0, "foot": 0.03, "shadow": 160.0},
	"statue_vessa": {"tex": "props/statue_vessa.png", "h": 340.0, "r": 52.0, "foot": 0.03, "shadow": 160.0},
	"statue_mireth": {"tex": "props/statue_mireth.png", "h": 340.0, "r": 52.0, "foot": 0.03, "shadow": 160.0},
	"statue_sable": {"tex": "props/statue_sable.png", "h": 340.0, "r": 52.0, "foot": 0.03, "shadow": 160.0},
	"crystals": {"tex": "props/crystals.png", "h": 170.0, "r": 46.0, "foot": 0.08, "shadow": 160.0},
	"candelabra": {"tex": "props/candelabra.png", "h": 230.0, "r": 26.0, "foot": 0.02, "shadow": 90.0},
	"throne": {"tex": "props/throne.png", "h": 520.0, "r": 130.0, "foot": 0.06, "shadow": 420.0},
}

## Room layouts in diamond units (u = x / W, v = y / H of the PLAYABLE half extents).
const LAYOUTS := {
	"oriel": [
		["pillar", -0.38, -0.12], ["pillar", 0.38, -0.12],
		["brazier", -0.64, 0.06], ["brazier", 0.64, 0.06], ["brazier", -0.24, 0.52], ["brazier", 0.24, 0.52],
		["statue_oriel", -0.5, -0.40], ["urns", 0.52, -0.38], ["skulls", 0.74, -0.16], ["broken_column", -0.74, -0.14],
	],
	"vessa": [
		["pillar", -0.3, -0.3], ["pillar", 0.3, -0.3], ["pillar", -0.3, 0.3], ["pillar", 0.3, 0.3],
		["brazier", -0.66, 0.0], ["brazier", 0.66, 0.0], ["brazier", 0.0, -0.62],
		["statue_vessa", 0.5, -0.40], ["broken_column", -0.52, -0.36], ["skulls", -0.62, 0.26], ["urns", 0.64, 0.24],
	],
	"mireth": [
		["statue_mireth", 0.0, -0.06],
		["brazier", -0.46, -0.34], ["brazier", 0.46, -0.34], ["brazier", -0.46, 0.36], ["brazier", 0.46, 0.36],
		["broken_column", -0.76, 0.0], ["urns", 0.76, 0.0], ["skulls", -0.2, -0.66], ["pillar", 0.24, -0.62],
	],
	"sable": [
		["statue_sable", -0.48, -0.42], ["pillar", -0.64, 0.26],
		["broken_column", -0.36, 0.08], ["broken_column", 0.36, 0.08],
		["brazier", -0.62, -0.16], ["brazier", 0.62, -0.16], ["brazier", -0.26, 0.5], ["brazier", 0.26, 0.5],
		["urns", 0.5, -0.4], ["skulls", 0.72, 0.1],
	],
	"regent": [
		["throne", 0.0, -0.76],
		["candelabra", -0.26, -0.6], ["candelabra", 0.26, -0.6],
		["crystals", -0.56, -0.22], ["crystals", 0.58, -0.2], ["crystals", -0.4, 0.42], ["crystals", 0.42, 0.44],
		["brazier", -0.72, 0.04], ["brazier", 0.72, 0.04],
		["pillar", -0.42, 0.0], ["pillar", 0.42, 0.0],
	],
}

# --------------------------------------------------------------- state
var floor_key := "catacomb"
var room_index := 0
var theme_id := "oriel"
var theme: Dictionary = {}
var half := Vector2(1050, 560)   ## playable diamond half extents
var vhalf := Vector2(1140, 608)  ## visual floor half extents
var wall_h := 640.0

var _obstacles: Array = []
var _spawns: Array = []
var _start := Vector2.ZERO
var _door := Vector2.ZERO
var _has_gate := true
var _door_open := false
var _door_t := 0.0
var _lit := 0.0
var _wave := 1.0
var _tween: Tween

var _ysort_parent: Node2D
var _ysorted: Array = []     ## props living in the lead's y-sorted layer
var _halos: Array = []       ## [Node2D, base_scale, phase, base_alpha]
var _swingers: Array = []    ## [Node2D pivot, phase]
var _silhouettes: Array = [] ## Node2D (fade near camera)
var _occluders: Array = []   ## [Node2D, half width, height] tall props that fade when the focus is behind them
var _cam_followers: Array = [] ## particle emitters that follow the camera
var _rng := RandomNumberGenerator.new()

var _noise: Texture2D
var _dot: Texture2D
var _glow: Texture2D
var _shadow: Texture2D
var _white: Texture2D
var _petal: Texture2D
var _rock: Texture2D

var _backdrop: Sprite2D
var _void_mat: ShaderMaterial
var _floor_mat: ShaderMaterial
var _wall_mats: Array = []
var _gate: Sprite2D
var _gate_mat: ShaderMaterial
var _rays: Polygon2D
var _gate_motes: CPUParticles2D
var _vignette: CanvasLayer
var _lights_a := PackedVector4Array()
var _lights_b := PackedVector4Array()
var _sa := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
var _sb := PackedVector4Array([Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO, Vector4.ZERO])
var _door_light := -1
var _sigil_light := -1
var _flash := 0.0
var _low := false
var _max_shader_lights := SHADER_LIGHTS
var _flash_timer := 3.0

func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS

# =============================================================== public API

## Build (or rebuild) the chamber. floor_key "catacomb" | "throne". Deterministic for a seed.
func build(p_floor_key: String, p_room_index: int, seed_value: int) -> void:
	_clear()
	floor_key = p_floor_key
	room_index = p_room_index
	_rng.seed = seed_value
	if floor_key == "throne":
		theme_id = "regent"
		half = Vector2(1150, 620)
		wall_h = 700.0
		_has_gate = false
	else:
		theme_id = ["oriel", "vessa", "mireth", "sable"][posmod(room_index, 4)]
		half = Vector2(1050, 560)
		wall_h = 640.0
		_has_gate = true
	theme = THEMES[theme_id]
	var m := 90.0
	vhalf = Vector2(half.x + m, half.y + m * half.y / half.x)
	_door = Vector2(0, -half.y + 70.0)
	_start = Vector2(0, half.y * 0.6)
	_door_open = false
	_door_t = 0.0
	_lit = 0.0
	_wave = 1.0
	_make_shared_textures()
	_build_backdrop()
	_build_rims()
	_build_floor()
	_build_walls()
	if _has_gate:
		_build_gate()
	_build_layout()
	_build_particles()
	_build_foreground()
	_build_vignette()
	_compute_spawns()
	_push_lights()
	if _low:
		_apply_low()
	if is_instance_valid(_ysort_parent):
		add_ysorted_props_to(_ysort_parent)

func get_bounds_half() -> Vector2:
	return half

func get_obstacles() -> Array:
	return _obstacles

func get_door_pos() -> Vector2:
	return _door

func set_door_open(open: bool) -> void:
	if open == _door_open:
		return
	_door_open = open
	if _tween and _tween.is_valid():
		_tween.kill()
	if not open:
		_door_t = 0.0
		_lit = 0.0
		_wave = 1.0
		if _gate_motes:
			_gate_motes.emitting = false
		_apply_dynamic()
		return
	_tween = create_tween().set_parallel(true)
	_tween.tween_method(func(v: float): _wave = v; _apply_dynamic(), 0.0, 1.0, 1.8).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.tween_method(func(v: float): _lit = v; _apply_dynamic(), 0.0, 1.0, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if _has_gate:
		_tween.tween_method(func(v: float): _door_t = v; _apply_dynamic(), 0.0, 1.0, 1.7).set_delay(0.45).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN_OUT)
		if _gate_motes:
			_gate_motes.emitting = true

func is_door_open() -> bool:
	return _door_open

func get_spawn_points() -> Array:
	return _spawns

func get_player_start() -> Vector2:
	return _start

## Moves every y-sorted prop (pillars, statues, braziers...) into the lead's y-sorted entity layer.
## Idempotent; props are re-added automatically on later build() calls.
func add_ysorted_props_to(parent: Node2D) -> void:
	_ysort_parent = parent
	for p in _ysorted:
		if not is_instance_valid(p):
			continue
		if p.get_parent() == parent:
			continue
		if p.get_parent():
			p.get_parent().remove_child(p)
		parent.add_child(p)

## Convenience: diamond clamp + push out of solid props (same rule as arena.resolve_collision).
func resolve(pos: Vector2, radius: float) -> Vector2:
	var w := half.x - radius
	var hh := half.y - radius * 0.5
	var k := absf(pos.x) / w + absf(pos.y) / hh
	if k > 1.0:
		pos /= k
	for o in _obstacles:
		var d: Vector2 = pos - o["pos"]
		d.y *= 2.0 # obstacles are flat ellipses on the iso floor
		var rr: float = o["radius"] + radius
		var l := d.length()
		if l < rr:
			if l < 0.001:
				d = Vector2(1, 0)
				l = 1.0
			d = d / l * rr
			d.y *= 0.5
			pos = o["pos"] + d
	return pos

## World rect the camera may show without leaving painted space (optional camera limits).
func get_camera_limits() -> Rect2:
	return Rect2(-vhalf.x - 700.0, -vhalf.y - wall_h, (vhalf.x + 700.0) * 2.0, vhalf.y * 2.0 + wall_h + 500.0)

## Optional low-end mode: plain backdrop (no mist shader), 3 shader lights, fewer particles, no vignette.
## Call after build(); persists for later builds.
func set_low_quality(on: bool) -> void:
	if on == _low:
		return
	_low = on
	_apply_low()

func _apply_low() -> void:
	var on := _low
	if _backdrop == null:
		return
	_backdrop.material = null if on else _void_mat
	if _vignette:
		_vignette.visible = not on
	for n in find_children("*", "CPUParticles2D", true, false):
		n.amount = maxi(2, n.amount / 2) if on else n.amount
	_max_shader_lights = 3 if on else SHADER_LIGHTS

func get_room_title() -> String:
	return theme.get("name", "")

func get_theme_id() -> String:
	return theme_id

# =============================================================== build helpers

func _clear() -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	for p in _ysorted:
		if is_instance_valid(p):
			p.queue_free()
	_ysorted.clear()
	for c in get_children():
		c.queue_free()
	_obstacles.clear()
	_spawns.clear()
	_halos.clear()
	_swingers.clear()
	_silhouettes.clear()
	_occluders.clear()
	_cam_followers.clear()
	_wall_mats.clear()
	_lights_a.clear()
	_lights_b.clear()
	_door_light = -1
	_sigil_light = -1
	_gate = null
	_gate_mat = null
	_rays = null
	_gate_motes = null
	_vignette = null

func _tex(path: String) -> Texture2D:
	return load(ENV + path) as Texture2D

func _make_shared_textures() -> void:
	if _noise:
		return
	_noise = _tex("noise.png")
	_white = _solid_tex(8, 8, Color.WHITE)
	_dot = _radial(32, Color(1, 1, 1, 1), Color(1, 1, 1, 0), 0.0)
	_glow = _radial(128, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0), 0.0)
	_shadow = _radial(64, Color(0, 0, 0, 0.75), Color(0, 0, 0, 0), 0.25)
	# petal: soft ellipse
	var img := Image.create(24, 12, false, Image.FORMAT_RGBA8)
	for y in range(12):
		for x in range(24):
			var d := Vector2((x - 11.5) / 12.0, (y - 5.5) / 6.0).length()
			img.set_pixel(x, y, Color(1, 1, 1, clampf((1.0 - d) * 3.0, 0, 1)))
	_petal = ImageTexture.create_from_image(img)
	# rock chip: irregular dark polygon
	var rimg := Image.create(20, 20, false, Image.FORMAT_RGBA8)
	for y in range(20):
		for x in range(20):
			var a := atan2(y - 9.5, x - 9.5)
			var rr := 8.0 + 2.0 * sin(a * 3.0) + 1.5 * cos(a * 5.0)
			var dd := Vector2(x - 9.5, y - 9.5).length()
			var shade := 0.5 + 0.3 * (1.0 - (y / 20.0))
			rimg.set_pixel(x, y, Color(shade, shade * 0.95, shade * 1.05, 1.0 if dd < rr else 0.0))
	_rock = ImageTexture.create_from_image(rimg)

func _solid_tex(w: int, h: int, c: Color) -> Texture2D:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(c)
	return ImageTexture.create_from_image(img)

func _radial(size: int, inner: Color, outer: Color, hold: float) -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, inner)
	g.set_color(1, outer)
	if hold > 0.0:
		g.add_point(hold, inner)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t

func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

func _shader(name: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/env_%s.gdshader" % name)
	return m

func _add_light(pos: Vector2, color: Color, radius: float, intensity: float, flicker: float) -> int:
	if _lights_a.size() >= MAX_LIGHTS:
		return -1
	_lights_a.append(Vector4(pos.x, pos.y, radius, intensity))
	_lights_b.append(Vector4(color.r, color.g, color.b, flicker))
	return _lights_a.size() - 1

## Culls lights to the camera view, applies flicker on the CPU and uploads at most SHADER_LIGHTS.
func _push_lights() -> void:
	var t := Time.get_ticks_msec() * 0.001
	var cam := get_viewport().get_camera_2d() if is_inside_tree() else null
	var c := cam.get_screen_center_position() if cam else Vector2.ZERO
	var ext := get_viewport_rect().size * 0.5 / (cam.zoom if cam else Vector2.ONE) if is_inside_tree() else Vector2(2000, 1000)
	var n := 0
	for i in range(_lights_a.size()):
		var la := _lights_a[i]
		if la.w <= 0.001:
			continue
		if absf(la.x - c.x) > ext.x + la.z or absf(la.y - c.y) > ext.y + la.z * 0.6:
			continue
		var lb := _lights_b[i]
		var fl := 1.0 - lb.w * (0.5 + 0.5 * sin(t * (6.3 + i * 1.7) + i * 2.1)) * (0.6 + 0.4 * sin(t * 13.1 + i))
		_sa[n] = Vector4(la.x, la.y, la.z, la.w * fl)
		_sb[n] = lb
		n += 1
		if n >= _max_shader_lights:
			break
	for m in _wall_mats:
		m.set_shader_parameter("light_count", n)
		m.set_shader_parameter("light_a", _sa)
		m.set_shader_parameter("light_b", _sb)
	if _floor_mat:
		_floor_mat.set_shader_parameter("light_count", n)
		_floor_mat.set_shader_parameter("light_a", _sa)
		_floor_mat.set_shader_parameter("light_b", _sb)

func _apply_dynamic() -> void:
	if _floor_mat:
		_floor_mat.set_shader_parameter("sigil_lit", _lit)
		_floor_mat.set_shader_parameter("sigil_wave", _wave)
	if _gate_mat:
		_gate_mat.set_shader_parameter("open_t", _door_t)
		_gate_mat.set_shader_parameter("glow", _door_t)
	if _rays:
		_rays.modulate.a = _door_t
	if _door_light >= 0:
		var v := _lights_a[_door_light]
		_lights_a[_door_light] = Vector4(v.x, v.y, v.z, 1.5 * _door_t)
	if _sigil_light >= 0:
		var s := _lights_a[_sigil_light]
		_lights_a[_sigil_light] = Vector4(s.x, s.y, s.z, 0.15 + 0.55 * _lit)
	_push_lights()

# --------------------------------------------------------------- backdrop / void
func _build_backdrop() -> void:
	_backdrop = Sprite2D.new()
	_backdrop.texture = _tex("abyss_throne.webp" if floor_key == "throne" else "abyss_catacomb.webp")
	_backdrop.z_index = -100
	_backdrop.scale = Vector2.ONE * 1.8
	_void_mat = _shader("void")
	_void_mat.set_shader_parameter("noise_tex", _noise)
	_void_mat.set_shader_parameter("mist_color", theme["mist"])
	_void_mat.set_shader_parameter("mist", 0.4)
	_void_mat.set_shader_parameter("darken", 0.8 if floor_key == "throne" else 0.72)
	_void_mat.set_shader_parameter("stars", 0.9 if theme_id == "regent" else 0.0)
	_void_mat.set_shader_parameter("caustics", 0.45 if theme_id == "mireth" else 0.0)
	_void_mat.set_shader_parameter("flash_color", Color(0.55, 0.72, 1.0))
	_backdrop.material = _void_mat
	add_child(_backdrop)

# --------------------------------------------------------------- ledges
func _build_rims() -> void:
	var tex := _tex("rim_throne.webp" if floor_key == "throne" else "rim_catacomb.webp")
	var depth := 520.0 if floor_key == "throne" else 430.0
	var rep_w := float(tex.get_width()) * depth / float(tex.get_height())
	var L := Vector2(-vhalf.x, 0)
	var B := Vector2(0, vhalf.y)
	var R := Vector2(vhalf.x, 0)
	for pair in [[L, B, 0.8], [B, R, 0.62]]:
		var a: Vector2 = pair[0]
		var b: Vector2 = pair[1]
		var len := a.distance_to(b)
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([a, b, b + Vector2(0, depth), a + Vector2(0, depth)])
		var u := len / rep_w
		var ts := tex.get_size() # Polygon2D UVs are in texture pixels
		p.uv = PackedVector2Array([Vector2(0, 0), Vector2(u, 0) * ts, Vector2(u, 1) * ts, Vector2(0, 1) * ts])
		p.texture = tex
		p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		p.z_index = -80
		var m := _shader("rim")
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("noise_tex", _noise)
		m.set_shader_parameter("shade", pair[2])
		m.set_shader_parameter("glow_key", Color(0.65, 0.3, 1.0))
		m.set_shader_parameter("glow_strength", 0.6 if floor_key == "throne" else 0.0)
		m.set_shader_parameter("abyss_color", Color(theme["mist"]).darkened(0.8))
		p.material = m
		add_child(p)

# --------------------------------------------------------------- floor
func _build_floor() -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([Vector2(-vhalf.x, 0), Vector2(0, -vhalf.y), Vector2(vhalf.x, 0), Vector2(0, vhalf.y)])
	p.z_index = -70
	_floor_mat = _shader("floor")
	var throne := floor_key == "throne"
	_floor_mat.set_shader_parameter("atlas", _tex("floor_throne.webp" if throne else "floor_catacomb.webp"))
	_floor_mat.set_shader_parameter("noise_tex", _noise)
	_floor_mat.set_shader_parameter("sigil_tex", _tex("sigil_%s.webp" % theme["sigil"]))
	_floor_mat.set_shader_parameter("iso", Vector2(104.0, 104.0 * half.y / half.x))
	_floor_mat.set_shader_parameter("half_size", vhalf)
	_floor_mat.set_shader_parameter("inset", 0.004 if throne else 0.006)
	_floor_mat.set_shader_parameter("seam_color", Color(0.55, 0.42, 0.22, 0.35) if throne else Color(0.85, 0.66, 0.3, 0.8))
	_floor_mat.set_shader_parameter("seam_width", 0.006 if throne else 0.013)
	_floor_mat.set_shader_parameter("seam_ink", 0.008)
	_floor_mat.set_shader_parameter("tint", Color(1.3, 1.2, 1.35) if throne else theme["tint"])
	_floor_mat.set_shader_parameter("grime", Color(0.12, 0.08, 0.16, 1.0) if throne else Color(0.09, 0.15, 0.1, 1.0))
	_floor_mat.set_shader_parameter("ambient", 0.95 if throne else 0.7)
	var sc := Vector2(0, -half.y * 0.02)
	var sr := 470.0
	if theme_id == "mireth":
		sc = Vector2(0, -half.y * 0.06)
		sr = 420.0
	elif theme_id == "regent":
		sc = Vector2(0, half.y * 0.04)
		sr = 560.0
	_floor_mat.set_shader_parameter("sigil_center", sc)
	_floor_mat.set_shader_parameter("sigil_radius", sr)
	_floor_mat.set_shader_parameter("sigil_color", theme["sigil_color"])
	_floor_mat.set_shader_parameter("sigil_base", 0.42)
	_floor_mat.set_shader_parameter("sigil_lit", 0.0)
	_floor_mat.set_shader_parameter("sigil_wave", 1.0)
	_floor_mat.set_shader_parameter("fog_color", theme["fog"])
	_floor_mat.set_shader_parameter("fog_amount", 0.2)
	p.material = _floor_mat
	add_child(p)
	_sigil_light = _add_light(sc, theme["sigil_color"], sr * 1.25, 0.15, 0.0)

# --------------------------------------------------------------- walls
func _build_walls() -> void:
	var throne := floor_key == "throne"
	var tex := _tex("wall_throne.webp" if throne else "wall_catacomb.webp")
	var rep_w := float(tex.get_width()) * wall_h / float(tex.get_height())
	var L := Vector2(-vhalf.x, 0)
	var T := Vector2(0, -vhalf.y)
	var R := Vector2(vhalf.x, 0)
	var up := Vector2(0, -wall_h)
	var off := _rng.randf() * 0.5
	for side in [[L, T, 0.95, Vector2(0.12, 0.0)], [T, R, 0.7, Vector2(0.0, 0.12)]]:
		var a: Vector2 = side[0]
		var b: Vector2 = side[1]
		var u0 := off
		var u1 := off + a.distance_to(b) / rep_w
		var p := Polygon2D.new()
		p.polygon = PackedVector2Array([a + up, b + up, b, a])
		var ts := tex.get_size() # Polygon2D UVs are in texture pixels
		p.uv = PackedVector2Array([Vector2(u0, 0) * ts, Vector2(u1, 0) * ts, Vector2(u1, 1) * ts, Vector2(u0, 1) * ts])
		p.texture = tex
		p.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		p.z_index = -60
		var m := _shader("wall")
		m.set_shader_parameter("tex", tex)
		m.set_shader_parameter("noise_tex", _noise)
		m.set_shader_parameter("shade", side[2])
		m.set_shader_parameter("span", u1)
		m.set_shader_parameter("u_start", u0)
		m.set_shader_parameter("end_fade", side[3])
		m.set_shader_parameter("top_dark", 0.32)
		m.set_shader_parameter("glow_key", Color(0.45, 0.3, 1.0))
		m.set_shader_parameter("glow_strength", 0.55 if throne else 0.0)
		m.set_shader_parameter("ambient", 0.8)
		p.material = m
		add_child(p)
		_wall_mats.append(m)
	# skirting shadow where walls meet the floor
	var s := Polygon2D.new()
	var d := 46.0
	s.polygon = PackedVector2Array([L, T, R, R + Vector2(-d * 2.0, 0), T + Vector2(0, d), L + Vector2(d * 2.0, 0)])
	s.vertex_colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.6), Color(0, 0, 0, 0.55), Color(0, 0, 0, 0), Color(0, 0, 0, 0), Color(0, 0, 0, 0)])
	s.z_index = -69
	add_child(s)
	# banners hung on the walls
	if not throne:
		var banner := _tex("props/banner.png")
		for t in [0.32, 0.68]:
			_wall_banner(banner, L, T, t, 0.55)
			_wall_banner(banner, T, R, 1.0 - t, 0.55)

func _wall_banner(tex: Texture2D, a: Vector2, b: Vector2, t: float, height_frac: float) -> void:
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, 0)
	var sc := 150.0 / tex.get_width()
	s.scale = Vector2(sc, sc)
	var dir := (b - a).normalized()
	var ang := dir.angle()
	s.rotation = ang
	s.skew = -ang
	s.position = a.lerp(b, t) + Vector2(0, -wall_h * height_frac - 120.0)
	s.z_index = -58
	s.modulate = Color(0.85, 0.82, 0.85) if b.x <= 0.0 else Color(0.65, 0.62, 0.68)
	var m := _shader("sway")
	m.set_shader_parameter("amp", 5.0)
	m.set_shader_parameter("seed", _rng.randf() * 10.0)
	s.material = m
	add_child(s)

# --------------------------------------------------------------- gate
func _build_gate() -> void:
	var tex := _tex("gate_closed.png")
	var width := 400.0
	var sc := width / tex.get_width()
	_gate = Sprite2D.new()
	_gate.texture = tex
	_gate.centered = false
	_gate.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())
	_gate.scale = Vector2(sc, sc)
	_gate.position = Vector2(0, -vhalf.y + 40.0)
	_gate.z_index = -55
	_gate_mat = _shader("gate")
	_gate_mat.set_shader_parameter("open_tex", _tex("gate_open.png"))
	_gate_mat.set_shader_parameter("mask_tex", _tex("gate_mask.png"))
	_gate_mat.set_shader_parameter("open_t", 0.0)
	_gate.material = _gate_mat
	add_child(_gate)
	# step / threshold shadow under the gate
	var sh := Sprite2D.new()
	sh.texture = _shadow
	sh.position = _gate.position + Vector2(0, -6)
	sh.scale = Vector2(width * 1.1 / 64.0, 70.0 / 64.0)
	sh.z_index = -56
	add_child(sh)
	# light rays spilling out onto the floor (vertex-colour fade, additive)
	var base_y := _gate.position.y - 8.0
	_rays = Polygon2D.new()
	var warm := Color(1.0, 0.86, 0.6)
	var top := base_y - 40.0
	var bot := base_y + 300.0
	# soft fan: bright core fading to transparent sides and far end
	_rays.polygon = PackedVector2Array([Vector2(-105, top), Vector2(0, top), Vector2(105, top), Vector2(330, bot), Vector2(0, bot + 40.0), Vector2(-330, bot)])
	_rays.vertex_colors = PackedColorArray([Color(warm, 0.0), Color(warm, 0.42), Color(warm, 0.0), Color(warm, 0.0), Color(warm, 0.0), Color(warm, 0.0)])
	_rays.polygons = [PackedInt32Array([0, 1, 4, 5]), PackedInt32Array([1, 2, 3, 4])]
	_rays.material = _additive()
	_rays.z_index = -54
	_rays.modulate.a = 0.0
	add_child(_rays)
	_door_light = _add_light(Vector2(0, base_y + 60.0), Color(1.0, 0.85, 0.6), 520.0, 0.0, 0.05)
	# motes drifting out of the open gate
	_gate_motes = _particles(28, 2.6, _dot, Color(1.0, 0.9, 0.65), 1)
	_gate_motes.position = Vector2(0, base_y - 120)
	_gate_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_gate_motes.emission_rect_extents = Vector2(90, 110)
	_gate_motes.direction = Vector2(0, 1)
	_gate_motes.spread = 40.0
	_gate_motes.initial_velocity_min = 20.0
	_gate_motes.initial_velocity_max = 70.0
	_gate_motes.gravity = Vector2(0, -6)
	_gate_motes.scale_amount_min = 0.12
	_gate_motes.scale_amount_max = 0.3
	_gate_motes.z_index = -53
	_gate_motes.emitting = false
	add_child(_gate_motes)

# --------------------------------------------------------------- props
func _uv(u: float, v: float) -> Vector2:
	return Vector2(u * half.x, v * half.y)

func _build_layout() -> void:
	# frame pillars at the side corners and flanking the gate (outside the playable area)
	_prop("pillar_big", Vector2(-vhalf.x + 30.0, -10.0))
	_prop("pillar_big", Vector2(vhalf.x - 30.0, -10.0))
	if _has_gate:
		var k := 290.0
		_prop("pillar_frame", Vector2(-k, -vhalf.y + k * vhalf.y / vhalf.x + 6.0))
		_prop("pillar_frame", Vector2(k, -vhalf.y + k * vhalf.y / vhalf.x + 6.0))
	else:
		_prop("pillar_frame", Vector2(-330, -vhalf.y + 330.0 * vhalf.y / vhalf.x + 6.0))
		_prop("pillar_frame", Vector2(330, -vhalf.y + 330.0 * vhalf.y / vhalf.x + 6.0))
	for e in LAYOUTS[theme_id]:
		_prop(e[0], _uv(e[1], e[2]))
	# lanterns hanging from the vault
	var lpos := [Vector2(-0.18, -0.25), Vector2(0.55, 0.22), Vector2(-0.6, 0.3)]
	for i in range(2 if floor_key == "throne" else 3):
		var lp: Vector2 = lpos[i]
		_lantern(_uv(lp.x, lp.y))

func _prop(kind: String, pos: Vector2) -> Node2D:
	var d: Dictionary = PROPS[kind]
	var tex := _tex(d["tex"])
	var root := Node2D.new()
	root.position = pos
	root.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var th := float(tex.get_height())
	var sc: float = d["h"] / th
	# contact shadow
	var sh := Sprite2D.new()
	sh.texture = _shadow
	sh.scale = Vector2(d["shadow"] / 64.0, d["shadow"] * 0.42 / 64.0)
	sh.z_index = -1
	root.add_child(sh)
	var s := Sprite2D.new()
	s.texture = tex
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -th * (1.0 - d["foot"]))
	s.scale = Vector2(sc, sc)
	if _rng.randf() < 0.5 and kind in ["urns", "skulls", "broken_column", "crystals", "brazier"]:
		s.scale.x = -sc
	root.add_child(s)
	if floor_key == "throne" and kind.begins_with("pillar"):
		s.modulate = Color(0.78, 0.66, 0.95) # violet-stained marble in the Regent's hall
	var r: float = d["r"]
	var inside := absf(pos.x) / half.x + absf(pos.y) / half.y < 1.05
	if r > 0.0 and inside:
		_obstacles.append({"pos": pos, "radius": r})
	match kind:
		"brazier":
			_fire(root, Vector2(0, -d["h"] * 0.86), Vector2(62, 96), 1.0)
			_add_light(pos + Vector2(0, 10), theme["light"], 430.0, 0.95, 0.35)
			_embers(root, Vector2(0, -d["h"] * 0.95))
		"statue_oriel":
			_halo(root, Vector2(-d["h"] * 0.21, -d["h"] * 0.93), 120.0, Color(1.0, 0.6, 0.25), 0.55)
			_fire(root, Vector2(-d["h"] * 0.215, -d["h"] * 0.9), Vector2(26, 40), 0.8)
		"candelabra":
			_halo(root, Vector2(0, -d["h"] * 0.82), 210.0, theme["light"].lerp(Color(1, 0.8, 0.5), 0.5), 0.5)
			_add_light(pos, Color(1.0, 0.75, 0.45), 300.0, 0.6, 0.25)
		"crystals":
			_halo(root, Vector2(0, -d["h"] * 0.5), 260.0, Color(0.7, 0.4, 1.0), 0.38)
		"throne":
			_halo(root, Vector2(0, -d["h"] * 0.55), 620.0, Color(0.6, 0.35, 1.0), 0.32)
		"statue_mireth":
			_halo(root, Vector2(d["h"] * 0.05, -d["h"] * 0.25), 220.0, Color(0.4, 0.9, 1.0), 0.35)
	if kind.begins_with("statue") and theme_id != "oriel":
		_add_light(pos + Vector2(0, 30), theme["sigil_color"], 260.0, 0.35, 0.0)
	if d["h"] >= 200.0:
		_occluders.append([root, tex.get_width() * sc * 0.42, float(d["h"])])
	_ysorted.append(root)
	add_child(root)
	return root

func _fire(parent: Node2D, at: Vector2, size: Vector2, intensity: float) -> void:
	var f := Sprite2D.new()
	f.texture = _white
	f.centered = false
	f.offset = Vector2(-4, -8)
	f.scale = size / 8.0
	f.position = at + Vector2(0, size.y * 0.12)
	var m := _shader("flame")
	var fc: Array = theme["flame"]
	m.set_shader_parameter("noise_tex", _noise)
	m.set_shader_parameter("core", fc[0])
	m.set_shader_parameter("mid", fc[1])
	m.set_shader_parameter("outer", fc[2])
	m.set_shader_parameter("seed", _rng.randf())
	m.set_shader_parameter("intensity", 1.0 * intensity)
	f.material = m
	parent.add_child(f)
	_halo(parent, at + Vector2(0, -size.y * 0.25), size.x * 4.2, fc[1], 0.55)

func _halo(parent: Node2D, at: Vector2, diameter: float, color: Color, alpha: float) -> void:
	var h := Sprite2D.new()
	h.texture = _glow
	h.material = _additive()
	h.position = at
	var bs := diameter / 128.0
	h.scale = Vector2(bs, bs)
	h.modulate = Color(color, alpha)
	parent.add_child(h)
	_halos.append([h, bs, _rng.randf() * TAU, alpha])

func _lantern(pos: Vector2) -> void:
	var tex := _tex("props/lantern.png")
	var root := Node2D.new()
	root.position = pos
	var hang := 470.0
	var pivot := Node2D.new()
	pivot.position = Vector2(0, -hang)
	root.add_child(pivot)
	var s := Sprite2D.new()
	s.texture = tex
	var sc := 300.0 / tex.get_height()
	s.scale = Vector2(sc, sc)
	s.centered = false
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * 0.45)
	s.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	pivot.add_child(s)
	_halo(pivot, Vector2(0, 300.0 * 0.45), 180.0, Color(0.6, 1.0, 0.7) if floor_key != "throne" else Color(0.7, 0.5, 1.0), 0.45)
	var sh := Sprite2D.new()
	sh.texture = _glow
	sh.material = _additive()
	sh.scale = Vector2(2.2, 0.9)
	sh.modulate = Color(0.5, 0.9, 0.6, 0.12) if floor_key != "throne" else Color(0.6, 0.4, 1.0, 0.12)
	sh.z_index = -1
	root.add_child(sh)
	_swingers.append([pivot, _rng.randf() * TAU])
	_ysorted.append(root)
	add_child(root)

# --------------------------------------------------------------- particles
func _particles(amount: int, lifetime: float, tex: Texture2D, color: Color, additive: int) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.amount = amount
	p.lifetime = lifetime
	p.texture = tex
	p.local_coords = false
	p.preprocess = lifetime
	p.randomness = 0.5
	p.lifetime_randomness = 0.4
	var g := Gradient.new()
	g.set_color(0, Color(color, 0.0))
	g.set_color(1, Color(color, 0.0))
	g.add_point(0.2, Color(color, 1.0))
	g.add_point(0.7, Color(color, 0.8))
	p.color_ramp = g
	if additive == 1:
		p.material = _additive()
	return p

func _embers(parent: Node2D, at: Vector2) -> void:
	var fc: Array = theme["flame"]
	var e := _particles(6, 1.8, _dot, fc[1].lerp(Color.WHITE, 0.25), 1)
	e.position = at
	e.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	e.emission_sphere_radius = 14.0
	e.direction = Vector2(0, -1)
	e.spread = 25.0
	e.initial_velocity_min = 40.0
	e.initial_velocity_max = 95.0
	e.gravity = Vector2(0, -18)
	e.angular_velocity_min = 0
	e.scale_amount_min = 0.08
	e.scale_amount_max = 0.18
	e.orbit_velocity_min = -0.05
	e.orbit_velocity_max = 0.05
	parent.add_child(e)

func _build_particles() -> void:
	# ambient motes around the camera (emitter follows the camera; particles stay in world space)
	var col: Color = theme["sigil_color"].lerp(Color(1, 0.95, 0.85), 0.55)
	var motes := _particles(34, 7.0, _dot, col, 1)
	motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	motes.emission_rect_extents = Vector2(900, 480)
	motes.direction = Vector2(0.3, -1)
	motes.spread = 60.0
	motes.initial_velocity_min = 6.0
	motes.initial_velocity_max = 22.0
	motes.gravity = Vector2(0, -2)
	motes.scale_amount_min = 0.06
	motes.scale_amount_max = 0.16
	motes.z_index = 12
	add_child(motes)
	_cam_followers.append(motes)
	match theme["particles"]:
		"petals":
			var p := _particles(26, 8.0, _petal, Color(0.95, 0.3, 0.42), 0)
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			p.emission_rect_extents = Vector2(900, 420)
			p.direction = Vector2(1, 0.4)
			p.spread = 30.0
			p.initial_velocity_min = 18.0
			p.initial_velocity_max = 40.0
			p.gravity = Vector2(4, 9)
			p.angular_velocity_min = -90.0
			p.angular_velocity_max = 90.0
			p.angle_min = 0.0
			p.angle_max = 360.0
			p.scale_amount_min = 0.5
			p.scale_amount_max = 0.9
			p.z_index = 13
			add_child(p)
			_cam_followers.append(p)
		"sparks":
			var s := _particles(18, 1.2, _dot, Color(0.6, 0.85, 1.0), 1)
			s.position = Vector2(0, -half.y * 0.02)
			s.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			s.emission_rect_extents = Vector2(420, 220)
			s.direction = Vector2(0, -1)
			s.spread = 180.0
			s.initial_velocity_min = 30.0
			s.initial_velocity_max = 120.0
			s.damping_min = 60.0
			s.damping_max = 120.0
			s.scale_amount_min = 0.05
			s.scale_amount_max = 0.12
			s.z_index = -65
			add_child(s)
		"bubbles":
			var b := _particles(22, 5.0, _dot, Color(0.45, 0.95, 0.9), 1)
			b.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			b.emission_rect_extents = Vector2(900, 480)
			b.direction = Vector2(0, -1)
			b.spread = 15.0
			b.initial_velocity_min = 14.0
			b.initial_velocity_max = 34.0
			b.scale_amount_min = 0.1
			b.scale_amount_max = 0.24
			b.z_index = 12
			add_child(b)
			_cam_followers.append(b)
		"motes_violet":
			# rubble falling past the island into the void (behind the floor)
			var d := _particles(22, 3.5, _rock, Color(0.55, 0.5, 0.6), 0)
			d.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			d.emission_rect_extents = Vector2(1000, 120)
			d.position = Vector2(0, -560)
			d.direction = Vector2(0, 1)
			d.spread = 8.0
			d.initial_velocity_min = 60.0
			d.initial_velocity_max = 160.0
			d.gravity = Vector2(0, 260)
			d.angular_velocity_min = -180.0
			d.angular_velocity_max = 180.0
			d.scale_amount_min = 0.5
			d.scale_amount_max = 1.6
			d.z_index = -95
			add_child(d)
			_cam_followers.append(d)
			# rising veil sparks
			var v := _particles(20, 4.0, _dot, Color(0.75, 0.55, 1.0), 1)
			v.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
			v.emission_rect_extents = Vector2(half.x * 0.7, half.y * 0.5)
			v.direction = Vector2(0, -1)
			v.spread = 20.0
			v.initial_velocity_min = 20.0
			v.initial_velocity_max = 60.0
			v.scale_amount_min = 0.06
			v.scale_amount_max = 0.16
			v.z_index = 12
			add_child(v)
	if theme_id == "oriel":
		var a := _particles(18, 4.0, _dot, Color(1.0, 0.6, 0.25), 1)
		a.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		a.emission_rect_extents = Vector2(900, 480)
		a.direction = Vector2(0.2, -1)
		a.spread = 25.0
		a.initial_velocity_min = 25.0
		a.initial_velocity_max = 60.0
		a.scale_amount_min = 0.06
		a.scale_amount_max = 0.14
		a.z_index = 12
		add_child(a)
		_cam_followers.append(a)

# --------------------------------------------------------------- foreground
func _build_foreground() -> void:
	var tex := _tex("props/pillar.png")
	var sc := 700.0 / tex.get_height()
	# bases far below the front ledges: only the tops rise into view when the camera nears the front
	var spots := [Vector2(-vhalf.x * 0.45, vhalf.y * 0.55 + 980.0), Vector2(vhalf.x * 0.52, vhalf.y * 0.48 + 1000.0), Vector2(-vhalf.x * 1.0, 1010.0), Vector2(vhalf.x * 1.02, 1040.0)]
	for i in range(spots.size()):
		var s := Sprite2D.new()
		s.texture = tex
		s.centered = false
		s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())
		s.scale = Vector2(sc, sc) * (1.0 + 0.12 * i)
		s.position = spots[i]
		s.modulate = Color(0.03, 0.025, 0.04, 0.92)
		s.z_index = 20
		add_child(s)
		_silhouettes.append(s)
	if floor_key == "throne":
		# a few large dark fragments drifting down in front of everything
		var d := _particles(4, 6.0, _rock, Color(0.08, 0.06, 0.1), 0)
		d.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
		d.emission_rect_extents = Vector2(900, 60)
		d.position = Vector2(0, -520)
		d.direction = Vector2(0, 1)
		d.spread = 5.0
		d.initial_velocity_min = 90.0
		d.initial_velocity_max = 150.0
		d.angular_velocity_min = -60.0
		d.angular_velocity_max = 60.0
		d.scale_amount_min = 2.5
		d.scale_amount_max = 4.0
		d.z_index = 21
		add_child(d)
		_cam_followers.append(d)

func _build_vignette() -> void:
	_vignette = CanvasLayer.new()
	_vignette.layer = 2
	var r := ColorRect.new()
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var m := _shader("vignette")
	m.set_shader_parameter("color", Color(theme["mist"]).darkened(0.9))
	m.set_shader_parameter("strength", 0.8)
	r.material = m
	_vignette.add_child(r)
	add_child(_vignette)

# --------------------------------------------------------------- spawns
func _compute_spawns() -> void:
	var cands: Array = []
	for ring in [0.68, 0.45]:
		for i in range(10):
			var a := TAU * (i + (0.5 if ring < 0.5 else 0.0)) / 10.0
			cands.append(Vector2(cos(a) * half.x * ring, sin(a) * half.y * ring))
	for c in cands:
		var ok := true
		for o in _obstacles:
			var d: Vector2 = c - o["pos"]
			d.y *= 2.0
			if d.length() < o["radius"] + 70.0:
				ok = false
				break
		if ok and c.distance_to(_start) > 330.0 and c.distance_to(_door) > 140.0:
			_spawns.append(c)

# =============================================================== per-frame life

func _process(delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	_push_lights()
	var cam := get_viewport().get_camera_2d()
	var cpos := Vector2.ZERO
	if cam:
		cpos = cam.get_screen_center_position()
	if _backdrop:
		_backdrop.position = cpos * 0.86
		var vs := get_viewport_rect().size
		var z := cam.zoom if cam else Vector2.ONE
		var ts := _backdrop.texture.get_size()
		var need := maxf(vs.x / z.x / ts.x, vs.y / z.y / ts.y) * 1.4
		_backdrop.scale = Vector2.ONE * maxf(need, 1.2)
	for f in _cam_followers:
		if is_instance_valid(f):
			f.position = cpos if f.z_index > 0 else Vector2(cpos.x, f.position.y)
	for h in _halos:
		var n: Node2D = h[0]
		if is_instance_valid(n):
			var ph: float = h[2]
			var k := 1.0 + 0.06 * sin(t * 7.3 + ph) + 0.04 * sin(t * 13.7 + ph * 2.0)
			n.scale = Vector2.ONE * h[1] * k
			n.modulate.a = h[3] * (0.85 + 0.15 * k)
	for s in _swingers:
		var p: Node2D = s[0]
		if is_instance_valid(p):
			p.rotation = sin(t * 0.9 + s[1]) * 0.035
	# tall props turn translucent while the focus (camera follows the heroes) is behind them
	var focus := cpos + Vector2(0, 50)
	for o in _occluders:
		var n: Node2D = o[0]
		if is_instance_valid(n):
			var behind: bool = focus.y < n.position.y - 10.0 and focus.y > n.position.y - o[2] and absf(focus.x - n.position.x) < o[1] + 50.0
			n.modulate.a = move_toward(n.modulate.a, 0.45 if behind else 1.0, delta * 4.0)
	# foreground silhouettes fade when they cover the middle of the view
	for s in _silhouettes:
		if is_instance_valid(s):
			var top: Vector2 = s.position + Vector2(0, -s.texture.get_height() * s.scale.y)
			var dx := absf(s.position.x - cpos.x)
			var near := dx < 520.0 and top.y < cpos.y + 260.0
			s.modulate.a = move_toward(s.modulate.a, 0.35 if near else 0.92, delta * 2.0)
	# storm flashes
	if theme_id == "vessa" and _void_mat:
		_flash_timer -= delta
		if _flash_timer <= 0.0:
			_flash = 1.0
			_flash_timer = randf_range(3.0, 7.0)
		_flash = maxf(0.0, _flash - delta * 3.5)
		var f2 := _flash * (0.6 + 0.4 * sin(t * 60.0))
		_void_mat.set_shader_parameter("flash", f2 * 0.6)
