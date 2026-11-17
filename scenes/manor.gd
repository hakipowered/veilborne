extends Node2D
## Gran Ysolde's manor at the edge of the Hollow: the walkable home hub's world (floors, walls, props,
## light, particles, collision). Gameplay (residents, stations, dummies, menus) lives in scenes/hub.gd.
##
## Space: a 2000 x 2000 "ground" square seen in 2:1 isometric. world = (u - v, (u + v) / 2).
## Four areas share it, split by low wainscot partitions with doorways:
##   Entrance Hall (front, u,v in [-500, 500])     Kitchen & Dining (left, u in [-1500, -500])
##   Armory & Training Yard (right, v in [-1500, -500])   Courtyard at the pit's edge (back corner)
## The environment speaks the subset of scenes/environment.gd the arena code calls (resolve, hazard_at,
## get_breakables, break_prop, get_bounds_half, add_ysorted_props_to).

signal debris_impact(pos: Vector2, radius: float, damage: float) ## unused (arena interface)
signal prop_broken(id: int, pos: Vector2)                        ## unused (arena interface)

const M := "res://art/env/manor/"
const ENV := "res://art/env/"
const LIT_SHADER := preload("res://shaders/manor_lit.gdshader")
const U_MIN := -1500.0
const U_MAX := 500.0
const WALL_H := 520.0
const PART_H := 150.0
const MAX_SHADER_LIGHTS := 8
const AMBIENT := 0.5

## Area centers (ground) and titles, for the area name ribbon and tests.
const AREAS := {
	"hall": {"title": "The Entrance Hall", "g": Vector2(0, 0)},
	"kitchen": {"title": "Kitchen & Dining", "g": Vector2(-1000, 0)},
	"armory": {"title": "Armory & Training Yard", "g": Vector2(0, -1000)},
	"courtyard": {"title": "The Courtyard at the Pit's Edge", "g": Vector2(-1000, -1000)},
}

## Odo's renovations: id -> {name, desc, gold}. Built pieces are tagged with their id (set_decor).
const DECOR := {
	"lanterns": {"name": "Hanging Lanterns", "desc": "Iron lanterns along the doorways and the pit walk. More light, fewer shins barked.", "gold": 30},
	"rugs": {"name": "Runner Rugs", "desc": "Woven runners for the kitchen and the armory. Wren stops slipping on flour.", "gold": 60},
	"banners": {"name": "House Banners", "desc": "The old Larkhill star, hung proud on the walls again.", "gold": 90},
	"fountain": {"name": "Mended Fountain", "desc": "Odo patches the courtyard fountain. The water still glows. Nobody asks why.", "gold": 140},
	"statues": {"name": "Warden Statues", "desc": "The four old guardians, carved and set along the pit walk.", "gold": 220},
}

var _mats: Array = []          ## lit ShaderMaterials (floors, walls, lips)
var _lights: Array = []        ## [pos, color, radius, intensity, flicker, decor_id]
var _la := PackedVector4Array()
var _lb := PackedVector4Array()
var _obstacles: Array = []     ## [ground center, radius, decor_id or ""]
var _segments: Array = []      ## [ground a, ground b, half thickness]
var _ysorted: Array = []
var _decor_nodes := {}         ## id -> [CanvasItem]
var _decor_off_nodes := {}     ## id -> [CanvasItem] shown only while the decor is NOT built
var _decor_on := {}
var _flickers: Array = []      ## [CanvasItem, base alpha, phase, amount]
var _floaters: Array = []      ## [Node2D, base y, phase]
var _motes: CPUParticles2D
var _parent: Node2D
var _noise: Texture2D
var _dot: Texture2D
var _glow: Texture2D
var _shadow: Texture2D
var _low := false
var _occluders: Array = []     ## [Node2D, half width]: fade when the focus walks behind them
var focus := Vector2.INF       ## the heroine (set by the hub each frame)


static func w(u: float, v: float) -> Vector2:
	return Vector2(u - v, (u + v) * 0.5)


static func g(p: Vector2) -> Vector2:
	return Vector2(p.x * 0.5 + p.y, p.y - p.x * 0.5)


func _tex(path: String) -> Texture2D:
	return load(path) as Texture2D


## Builds everything. ysort_parent: the arena's y-sorted entity layer (props are sorted with heroes).
func build(ysort_parent: Node2D, decor: Dictionary) -> void:
	_parent = ysort_parent
	_decor_on = decor.duplicate()
	_noise = _tex(ENV + "noise.png")
	_dot = _radial(32, Color(1, 1, 1, 1), Color(1, 1, 1, 0))
	_glow = _radial(128, Color(1, 1, 1, 0.9), Color(1, 1, 1, 0))
	_shadow = _radial(64, Color(0, 0, 0, 0.7), Color(0, 0, 0, 0))
	_low = OS.has_feature("mobile") and RenderingServer.get_video_adapter_name().to_lower().contains("mali-4")
	_build_backdrop()
	_build_floors()
	_build_lips()
	_build_walls()
	_build_partitions()
	_build_hall()
	_build_kitchen()
	_build_armory()
	_build_courtyard()
	_build_particles()
	_apply_prop_light()
	for id in DECOR.keys():
		set_decor(id, bool(_decor_on.get(id, false)))


# ---------------------------------------------------------------- arena interface

func get_bounds_half() -> Vector2:
	return Vector2(2000, 1000)


func get_breakables() -> Array:
	return []


func break_prop(_id: int) -> bool:
	return false


func hazard_at(_pos: Vector2) -> Dictionary:
	return {"dps": 0.0, "slow": 0.0}


func get_spawn_points() -> Array:
	return []


func get_door_pos() -> Vector2:
	return w(-1430, -1430)


func add_ysorted_props_to(parent: Node2D) -> void:
	for p in _ysorted:
		if is_instance_valid(p) and p.get_parent() != parent:
			if p.get_parent():
				p.get_parent().remove_child(p)
			parent.add_child(p)


func set_low_quality(on: bool) -> void:
	_low = on
	if _motes:
		_motes.amount = 14 if on else 36


## Clamp into the manor square, then out of props and partition walls (all in ground space).
func resolve(pos: Vector2, radius: float) -> Vector2:
	var p := g(pos)
	var r := radius * 1.3
	if radius <= 0.0:
		# projectiles: only the outer bounds stop them
		if p.x < U_MIN or p.x > U_MAX or p.y < U_MIN or p.y > U_MAX:
			return w(clampf(p.x, U_MIN, U_MAX), clampf(p.y, U_MIN, U_MAX))
		return pos
	p.x = clampf(p.x, U_MIN + r, U_MAX - r)
	p.y = clampf(p.y, U_MIN + r, U_MAX - r)
	for o in _obstacles:
		var id: String = o[2]
		if id != "" and not bool(_decor_on.get(id, false)):
			continue
		var d: Vector2 = p - o[0]
		var rr: float = o[1] + r
		var l := d.length()
		if l < rr:
			if l < 0.001:
				d = Vector2(1, 0)
				l = 1.0
			p = o[0] + d / l * rr
	for s in _segments:
		var a: Vector2 = s[0]
		var b: Vector2 = s[1]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
		var c := a + ab * t
		var d2 := p - c
		var rr2: float = s[2] + r
		var l2 := d2.length()
		if l2 < rr2:
			if l2 < 0.001:
				d2 = Vector2(-ab.y, ab.x).normalized()
				l2 = 1.0
			p = c + d2 / l2 * rr2
	return w(p.x, p.y)


## Which area a world point lies in ("hall", "kitchen", "armory", "courtyard").
func area_at(pos: Vector2) -> String:
	var p := g(pos)
	if p.x >= -500.0:
		return "hall" if p.y >= -500.0 else "armory"
	return "kitchen" if p.y >= -500.0 else "courtyard"


func is_decor_on(id: String) -> bool:
	return bool(_decor_on.get(id, false))


## Shows / hides a renovation and its light (with a little sparkle when it appears).
func set_decor(id: String, on: bool) -> void:
	_decor_on[id] = on
	for n in _decor_nodes.get(id, []):
		if is_instance_valid(n):
			n.visible = on
	for n in _decor_off_nodes.get(id, []):
		if is_instance_valid(n):
			n.visible = not on


func reveal_decor(id: String) -> void:
	set_decor(id, true)
	for n in _decor_nodes.get(id, []):
		if is_instance_valid(n) and n is Node2D:
			var nd := n as Node2D
			var s := nd.scale
			nd.scale = s * 0.6
			nd.modulate.a = 0.0
			var tw := nd.create_tween().set_parallel()
			tw.tween_property(nd, "scale", s, 0.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(nd, "modulate:a", 1.0, 0.35)


# ---------------------------------------------------------------- helpers

func _radial(size: int, inner: Color, outer: Color) -> Texture2D:
	var gr := Gradient.new()
	gr.set_color(0, inner)
	gr.set_color(1, outer)
	var t := GradientTexture2D.new()
	t.gradient = gr
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	t.width = size
	t.height = size
	return t


func _lit_mat(is_ground: bool, tile := 620.0) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = LIT_SHADER
	m.set_shader_parameter("ground", is_ground)
	m.set_shader_parameter("tile", tile)
	m.set_shader_parameter("ambient", AMBIENT)
	m.set_shader_parameter("noise_tex", _noise)
	_mats.append(m)
	return m


func _add_light(pos: Vector2, color: Color, radius: float, intensity: float, flicker := 0.0, decor := "") -> void:
	_lights.append([pos, color, radius, intensity, flicker, decor])
	# a soft additive pool on the floor so the light reads even where the shader culls it
	var pool := Sprite2D.new()
	pool.texture = _glow
	pool.position = pos
	pool.scale = Vector2(radius / 64.0, radius / 128.0) * 0.75
	pool.modulate = Color(color, 0.16 * intensity)
	pool.material = _additive()
	pool.z_index = -40
	add_child(pool)
	if flicker > 0.0:
		_flickers.append([pool, pool.modulate.a, randf() * TAU, flicker])
	_tag(pool, decor)


func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


func _tag(n: CanvasItem, decor: String, inverse := false) -> void:
	if decor == "":
		return
	var d: Dictionary = _decor_off_nodes if inverse else _decor_nodes
	if not d.has(decor):
		d[decor] = []
	d[decor].append(n)


## A painted prop standing on the floor, sorted with the heroines by its base. at: ground position.
func prop(path: String, at: Vector2, height: float, block := 0.0, decor := "", flip := false, shadow := 1.0, base_frac := 0.96) -> Node2D:
	var tex := _tex(path)
	var holder := Node2D.new()
	holder.position = w(at.x, at.y)
	if shadow > 0.0:
		var sh := Sprite2D.new()
		sh.texture = _shadow
		var sw := tex.get_width() * (height / tex.get_height()) * 0.9
		sh.scale = Vector2(sw / 64.0, sw / 64.0 * 0.38) * shadow
		sh.modulate.a = 0.75
		holder.add_child(sh)
	var s := Sprite2D.new()
	s.name = "Art"
	s.texture = tex
	s.centered = false
	var sc := height / tex.get_height()
	s.scale = Vector2(sc * (-1.0 if flip else 1.0), sc)
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * base_frac)
	holder.add_child(s)
	_ysorted.append(holder)
	_parent.add_child(holder)
	if block > 0.0:
		_obstacles.append([at, block, decor])
	_tag(holder, decor)
	return holder


## A flat painted decal on the floor (rugs). Square textures map onto the iso diamond of ground size.
func decal(path: String, at: Vector2, size: Vector2, decor := "", rot := 0.0) -> Node2D:
	var tex := _tex(path)
	var n := Node2D.new()
	n.position = w(at.x, at.y)
	n.z_index = -45
	var s := Sprite2D.new()
	s.texture = tex
	# ground axes: +u -> (1, 0.5), +v -> (-1, 0.5)
	var xa := Vector2(1, 0.5) * (size.x / tex.get_width())
	var ya := Vector2(-1, 0.5) * (size.y / tex.get_height())
	var tr := Transform2D(xa, ya, Vector2.ZERO)
	if rot != 0.0:
		tr = Transform2D(xa.rotated(0), ya, Vector2.ZERO) * Transform2D(rot, Vector2.ZERO)
	s.transform = tr
	n.add_child(s)
	add_child(n)
	_tag(n, decor)
	return n


## A sheared vertical quad standing on the ground segment a->b (ground coords), textured with tex.
func _facade(a: Vector2, b: Vector2, height: float, tex: Texture2D, u0: float, mat: ShaderMaterial) -> Polygon2D:
	var wa := w(a.x, a.y)
	var wb := w(b.x, b.y)
	var len := wa.distance_to(wb)
	var px_per_unit := tex.get_height() / height
	var poly := Polygon2D.new()
	poly.polygon = PackedVector2Array([wa + Vector2(0, -height), wb + Vector2(0, -height), wb, wa])
	poly.uv = PackedVector2Array([Vector2(u0 * px_per_unit, 0), Vector2((u0 + len) * px_per_unit, 0),
		Vector2((u0 + len) * px_per_unit, tex.get_height()), Vector2(u0 * px_per_unit, tex.get_height())])
	poly.texture = tex
	poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	poly.material = mat
	return poly


# ---------------------------------------------------------------- shell

func _build_backdrop() -> void:
	# the Hollow yawns behind the courtyard; the rest of the void is the same painting, darker
	var far := Sprite2D.new()
	far.texture = _tex(ENV + "hollow/abyss.webp")
	far.position = Vector2(0, -400)
	far.scale = Vector2(6.0, 6.0)
	far.modulate = Color(0.22, 0.16, 0.22)
	far.z_index = -100
	add_child(far)
	var pit := Sprite2D.new()
	pit.texture = _tex(ENV + "hollow/abyss.webp")
	pit.position = Vector2(0, -1900)
	pit.scale = Vector2(2.6, 2.0)
	pit.modulate = Color(0.75, 0.62, 0.78)
	pit.z_index = -99
	add_child(pit)
	_floaters.append([pit, pit.position.y, 0.0])


func _floor_poly(u0: float, u1: float, v0: float, v1: float, tex_path: String, tile: float) -> void:
	var p := Polygon2D.new()
	p.polygon = PackedVector2Array([w(u0, v0), w(u1, v0), w(u1, v1), w(u0, v1)])
	p.texture = _tex(tex_path)
	p.material = _lit_mat(true, tile)
	p.z_index = -60
	add_child(p)


func _build_floors() -> void:
	_floor_poly(-500, 500, -500, 500, M + "floor_wood.webp", 520.0)        # hall
	_floor_poly(-1500, -500, -500, 500, M + "floor_wood.webp", 520.0)      # kitchen
	_floor_poly(-500, 500, -1500, -500, M + "floor_stone.webp", 640.0)     # armory yard
	_floor_poly(-1500, -500, -1500, -500, M + "floor_stone.webp", 640.0)   # courtyard
	# inked edge on the pit side of the courtyard
	var ink := Line2D.new()
	ink.points = PackedVector2Array([w(-1500, -500), w(-1500, -1500), w(-500, -1500)])
	ink.width = 5.0
	ink.default_color = Color(0.05, 0.02, 0.05, 0.9)
	ink.z_index = -58
	add_child(ink)


## The house floor's thickness hanging under the front edges (stone foundations into the dark).
func _build_lips() -> void:
	var tex := _tex(ENV + "rim_catacomb.webp")
	var mat := _lit_mat(false)
	mat.set_shader_parameter("bottom_dark", 0.85)
	mat.set_shader_parameter("light_squash", 1.0)
	for e in [[Vector2(500, -1500), Vector2(500, 500)], [Vector2(500, 500), Vector2(-1500, 500)]]:
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		var wa := w(a.x, a.y)
		var wb := w(b.x, b.y)
		var h := 300.0
		var len := wa.distance_to(wb)
		var ppu := tex.get_height() / h
		var poly := Polygon2D.new()
		poly.polygon = PackedVector2Array([wa, wb, wb + Vector2(0, h), wa + Vector2(0, h)])
		poly.uv = PackedVector2Array([Vector2(0, 0), Vector2(len * ppu, 0), Vector2(len * ppu, tex.get_height()), Vector2(0, tex.get_height())])
		poly.texture = tex
		poly.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		poly.material = mat
		poly.z_index = -61
		add_child(poly)
	var ink := Line2D.new()
	ink.points = PackedVector2Array([w(500, -1500), w(500, 500), w(-1500, 500)])
	ink.width = 4.0
	ink.default_color = Color(0.05, 0.02, 0.05, 0.85)
	ink.z_index = -58
	add_child(ink)


func _build_walls() -> void:
	var tex := _tex(M + "wall.webp")
	var mat := _lit_mat(false)
	mat.set_shader_parameter("top_dark", 0.55)
	mat.set_shader_parameter("light_squash", 0.8)
	# kitchen back wall (upper left) and armory back wall (upper right)
	var kw := _facade(Vector2(-1500, 500), Vector2(-1500, -500), WALL_H, tex, 0.0, mat)
	kw.z_index = -50
	add_child(kw)
	var aw := _facade(Vector2(-500, -1500), Vector2(500, -1500), WALL_H, tex, 300.0, mat)
	aw.z_index = -50
	add_child(aw)
	# dark crown along the wall tops
	for e in [[Vector2(-1500, 500), Vector2(-1500, -500)], [Vector2(-500, -1500), Vector2(500, -1500)]]:
		var ln := Line2D.new()
		var a: Vector2 = e[0]
		var b: Vector2 = e[1]
		ln.points = PackedVector2Array([w(a.x, a.y) + Vector2(0, -WALL_H), w(b.x, b.y) + Vector2(0, -WALL_H)])
		ln.width = 18.0
		ln.default_color = Color(0.12, 0.07, 0.05)
		ln.z_index = -49
		add_child(ln)
	# stone pillars capping each wall end (where the walls give way to the pit walk)
	for at in [Vector2(-1500, 500), Vector2(-1500, -500), Vector2(-500, -1500), Vector2(500, -1500)]:
		var p := prop(ENV + "props/pillar.png", at + Vector2(14, 14), 600.0, 40.0)
		p.z_index = 0
	# banners on the walls (renovation)
	for at in [Vector2(-1497, 280), Vector2(-1497, -280)]:
		_wall_hanging(ENV + "props/banner.png", at, 230.0, 330.0, "banners")
	for at in [Vector2(-300, -1497), Vector2(330, -1497)]:
		_wall_hanging(ENV + "props/banner.png", at, 230.0, 330.0, "banners")


## Something hung on a back wall: drawn just in front of the wall, behind everything on the floor.
func _wall_hanging(path: String, at: Vector2, height: float, lift: float, decor := "") -> Sprite2D:
	var tex := _tex(path)
	var s := Sprite2D.new()
	s.texture = tex
	var sc := height / tex.get_height()
	s.scale = Vector2(sc, sc)
	s.position = w(at.x, at.y) + Vector2(0, -lift)
	s.z_index = -48
	s.modulate = Color(0.85, 0.78, 0.72)
	add_child(s)
	_tag(s, decor)
	return s


## Low wainscot partitions between the areas, cut into short y-sorted pieces so heroines walk in
## front of and behind them correctly. Doorways are gaps flanked by pillars.
func _build_partitions() -> void:
	var tex := _tex(M + "wainscot.webp")
	var mat := _lit_mat(false)
	mat.set_shader_parameter("top_dark", 0.0)
	mat.set_shader_parameter("light_squash", 1.0)
	var lines := [
		# [fixed axis ("u"/"v"), fixed value, from, to, gap_from, gap_to]
		["u", -500.0, -500.0, 500.0, -170.0, 170.0],     # hall | kitchen
		["v", -500.0, -500.0, 500.0, -170.0, 170.0],     # hall | armory
		["v", -500.0, -1500.0, -500.0, -1170.0, -830.0], # kitchen | courtyard
		["u", -500.0, -1500.0, -500.0, -1170.0, -830.0], # armory | courtyard
	]
	var acc := 0.0
	for ln in lines:
		var axis: String = ln[0]
		var fixed: float = ln[1]
		for run in [[ln[2], ln[4]], [ln[5], ln[3]]]:
			var s0: float = run[0]
			var s1: float = run[1]
			var ga := Vector2(fixed, s0) if axis == "u" else Vector2(s0, fixed)
			var gb := Vector2(fixed, s1) if axis == "u" else Vector2(s1, fixed)
			_segments.append([ga, gb, 22.0])
			var n := int(ceil((s1 - s0) / 50.0))
			for i in range(n):
				var t0 := s0 + (s1 - s0) * i / n
				var t1 := s0 + (s1 - s0) * (i + 1) / n
				var a := Vector2(fixed, t0) if axis == "u" else Vector2(t0, fixed)
				var b := Vector2(fixed, t1) if axis == "u" else Vector2(t1, fixed)
				var mid := (a + b) * 0.5
				var holder := Node2D.new()
				holder.position = w(mid.x, mid.y)
				var poly := _facade(a, b, PART_H, tex, acc, mat)
				poly.position = -holder.position
				holder.add_child(poly)
				var cap := Line2D.new()
				cap.points = PackedVector2Array([w(a.x, a.y) + Vector2(0, -PART_H) - holder.position, w(b.x, b.y) + Vector2(0, -PART_H) - holder.position])
				cap.width = 10.0
				cap.default_color = Color(0.2, 0.11, 0.06)
				holder.add_child(cap)
				acc += w(a.x, a.y).distance_to(w(b.x, b.y))
				_occluders.append([holder, 70.0])
				_ysorted.append(holder)
				_parent.add_child(holder)
		# doorway posts + the junction post
		for at in [Vector2(fixed, ln[4]), Vector2(fixed, ln[5]), Vector2(fixed, ln[2]), Vector2(fixed, ln[3])]:
			var gp: Vector2 = at if axis == "u" else Vector2(at.y, at.x)
			if gp.x >= 499.0 or gp.y >= 499.0 or gp.x <= -1499.0 or gp.y <= -1499.0:
				continue
			_occluders.append([prop(ENV + "props/pillar.png", gp, 330.0, 30.0), 60.0])
	# lanterns hanging by each doorway (renovation)
	for gp in [Vector2(-500, -230), Vector2(-500, 230), Vector2(-230, -500), Vector2(230, -500),
			Vector2(-1230, -500), Vector2(-770, -500), Vector2(-500, -1230), Vector2(-500, -770)]:
		var l := prop(ENV + "props/lantern.png", gp, 150.0, 0.0, "lanterns", false, 0.0)
		l.get_node("Art").position.y = -170.0
		_occluders.append([l, 50.0])
		_add_light(w(gp.x, gp.y) + Vector2(0, -30), Color(1.0, 0.7, 0.4), 330.0, 0.55, 0.25, "lanterns")


# ---------------------------------------------------------------- areas

func _build_hall() -> void:
	decal(M + "rug_round.png", Vector2(0, 0), Vector2(620, 620))
	# Gran's reading corner
	prop(M + "armchair.png", Vector2(-420, 300), 170.0, 55.0)
	prop(M + "bookshelf.png", Vector2(-450, 450), 270.0, 50.0)
	prop(ENV + "props/candelabra.png", Vector2(-260, 460), 210.0, 22.0)
	_add_light(w(-260, 460) + Vector2(0, -20), Color(1.0, 0.72, 0.42), 520.0, 0.9, 0.18)
	# Odo's corner
	prop(ENV + "props/urns.png", Vector2(430, -430), 150.0, 50.0)
	prop(ENV + "props/candelabra.png", Vector2(420, 330), 210.0, 22.0)
	_add_light(w(420, 330) + Vector2(0, -20), Color(1.0, 0.72, 0.42), 520.0, 0.9, 0.18)
	prop(ENV + "props/brazier.png", Vector2(-380, -380), 150.0, 55.0)
	_add_light(w(-380, -380), Color(1.0, 0.55, 0.25), 560.0, 1.0, 0.3)
	_fire_glow(w(-380, -380) + Vector2(0, -120), Color(1.0, 0.55, 0.2), 1.0)
	_add_light(Vector2(0, 0), Color(1.0, 0.8, 0.55), 700.0, 0.35, 0.0)


func _build_kitchen() -> void:
	prop(M + "fireplace.png", Vector2(-1440, -20), 400.0, 110.0)
	_add_light(w(-1440, -20) + Vector2(0, -60), Color(1.0, 0.52, 0.2), 900.0, 1.5, 0.35)
	_fire_glow(w(-1440, -20) + Vector2(-20, -140), Color(1.0, 0.5, 0.15), 1.6)
	_embers(w(-1440, -20) + Vector2(-20, -150), 70.0, 14)
	prop(M + "shelf.png", Vector2(-1420, 360), 250.0, 70.0)
	prop(M + "table.png", Vector2(-820, 300), 300.0, 0.0)
	_obstacles.append([Vector2(-900, 240), 110.0, ""])
	_obstacles.append([Vector2(-750, 360), 110.0, ""])
	prop(ENV + "forge/crucible.png", Vector2(-1300, -330), 140.0, 55.0)
	_add_light(w(-1300, -330), Color(1.0, 0.6, 0.3), 300.0, 0.4, 0.3)
	prop(ENV + "props/candelabra.png", Vector2(-1100, 440), 200.0, 22.0)
	_add_light(w(-1100, 440) + Vector2(0, -20), Color(1.0, 0.72, 0.42), 480.0, 0.85, 0.18)
	decal(M + "rug_runner.png", Vector2(-1180, -50), Vector2(300, 440), "rugs")


func _build_armory() -> void:
	prop(ENV + "forge/furnace.png", Vector2(-430, -1440), 330.0, 70.0)
	_add_light(w(-430, -1440) + Vector2(0, -40), Color(1.0, 0.45, 0.15), 720.0, 1.3, 0.3)
	_fire_glow(w(-430, -1440) + Vector2(0, -70), Color(1.0, 0.45, 0.12), 1.1)
	_embers(w(-430, -1440) + Vector2(0, -200), 30.0, 8)
	prop(ENV + "forge/anvil.png", Vector2(-370, -1230), 130.0, 50.0)
	prop(ENV + "forge/barrel.png", Vector2(450, -1080), 120.0, 40.0)
	_add_light(w(450, -1080), Color(1.0, 0.5, 0.2), 380.0, 0.6, 0.35)
	prop(ENV + "forge/chainpost.png", Vector2(430, -620), 210.0, 30.0)
	_add_light(w(80, -950), Color(1.0, 0.82, 0.6), 650.0, 0.35, 0.0)
	decal(M + "rug_runner.png", Vector2(140, -1270), Vector2(720, 230), "rugs")


func _build_courtyard() -> void:
	# chain posts along the pit's edge, with lanterns hung on some (renovation)
	var edge := [Vector2(-1480, -560), Vector2(-1480, -800), Vector2(-1480, -1050), Vector2(-1480, -1300),
		Vector2(-1300, -1480), Vector2(-1050, -1480), Vector2(-800, -1480), Vector2(-560, -1480)]
	for i in range(edge.size()):
		prop(ENV + "forge/chainpost.png", edge[i], 170.0, 24.0, "", i % 2 == 1)
	for gp in [Vector2(-1440, -680), Vector2(-1440, -1180), Vector2(-1180, -1440), Vector2(-680, -1440)]:
		var l := prop(ENV + "props/lantern.png", gp, 140.0, 0.0, "lanterns", false, 0.0)
		l.get_node("Art").position.y = -120.0
		_add_light(w(gp.x, gp.y) + Vector2(0, -20), Color(1.0, 0.72, 0.45), 360.0, 0.6, 0.25, "lanterns")
	# the fountain: broken until Odo mends it
	var broken := prop(M + "fountain_broken.png", Vector2(-950, -950), 210.0, 110.0)
	_tag(broken, "fountain", true)
	prop(ENV + "garden/fountain.png", Vector2(-950, -950), 250.0, 0.0, "fountain")
	_add_light(w(-950, -950) + Vector2(0, -40), Color(0.35, 0.95, 0.85), 480.0, 0.8, 0.12, "fountain")
	var spray := _embers(w(-950, -950) + Vector2(0, -170), 40.0, 16, Color(0.6, 1.0, 0.95), true)
	_tag(spray, "fountain")
	# statues of the four Wardens along the pit walk (renovation)
	var st := ["statue_oriel", "statue_vessa", "statue_mireth", "statue_sable"]
	var spots := [Vector2(-1420, -920), Vector2(-1420, -1180), Vector2(-1180, -1420), Vector2(-920, -1420)]
	for i in range(4):
		prop(ENV + "props/%s.png" % st[i], spots[i], 260.0, 45.0, "statues", i >= 2)
	# a ghostly willow by Corwin's post
	prop(ENV + "garden/willow.png", Vector2(-620, -1400), 330.0, 60.0)
	_add_light(w(-620, -1400) + Vector2(0, -120), Color(0.55, 0.9, 1.0), 380.0, 0.4, 0.1)
	_add_light(w(-1000, -1000), Color(0.75, 0.6, 1.0), 900.0, 0.3, 0.0)
	# mist rising out of the Hollow
	var mist := CPUParticles2D.new()
	mist.position = w(-1500, -1500) + Vector2(0, -60)
	mist.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	mist.emission_rect_extents = Vector2(1100, 40)
	mist.amount = 14
	mist.lifetime = 7.0
	mist.texture = _glow
	mist.direction = Vector2(0, -1)
	mist.spread = 20.0
	mist.gravity = Vector2.ZERO
	mist.initial_velocity_min = 8.0
	mist.initial_velocity_max = 22.0
	mist.scale_amount_min = 2.0
	mist.scale_amount_max = 4.0
	mist.color = Color(0.6, 0.45, 0.85, 0.08)
	mist.z_index = -95
	add_child(mist)


func _fire_glow(at: Vector2, col: Color, size: float) -> void:
	var s := Sprite2D.new()
	s.texture = _glow
	s.position = at
	s.scale = Vector2(2.2, 1.7) * size
	s.modulate = Color(col, 0.5)
	s.material = _additive()
	s.z_index = 2
	add_child(s)
	_flickers.append([s, 0.5, randf() * TAU, 0.45])


func _embers(at: Vector2, spread_x: float, amount: int, col := Color(1.0, 0.6, 0.25), fountain := false) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.position = at
	p.amount = amount
	p.lifetime = 1.6 if not fountain else 1.1
	p.texture = _dot
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(spread_x, 8)
	p.direction = Vector2(0, -1)
	p.spread = 25.0 if not fountain else 30.0
	p.gravity = Vector2(0, -20) if not fountain else Vector2(0, 240)
	p.initial_velocity_min = 30.0 if not fountain else 90.0
	p.initial_velocity_max = 80.0 if not fountain else 160.0
	p.scale_amount_min = 0.12
	p.scale_amount_max = 0.3
	p.color = col
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	p.material = _additive()
	p.z_index = 3
	add_child(p)
	return p


func _build_particles() -> void:
	# warm dust motes drifting through the candlelight, following the camera
	_motes = CPUParticles2D.new()
	_motes.amount = 36
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0
	_motes.texture = _dot
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	_motes.emission_rect_extents = Vector2(1100, 650)
	_motes.direction = Vector2(0.3, -1)
	_motes.spread = 60.0
	_motes.gravity = Vector2.ZERO
	_motes.initial_velocity_min = 4.0
	_motes.initial_velocity_max = 14.0
	_motes.scale_amount_min = 0.06
	_motes.scale_amount_max = 0.16
	_motes.color = Color(1.0, 0.85, 0.6, 0.55)
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.3, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	_motes.color_ramp = ramp
	_motes.local_coords = false
	_motes.material = _additive()
	_motes.z_index = 8
	add_child(_motes)


## Props take the light of the room they stand in (computed once; cheap on mobile).
func _apply_prop_light() -> void:
	for n in _ysorted:
		if not is_instance_valid(n):
			continue
		var c := _light_at(n.position)
		n.modulate = Color(c.r, c.g, c.b, n.modulate.a)


func _light_at(pos: Vector2, include_decor := false) -> Color:
	var l := Color(1.0, 0.86, 0.74) * (AMBIENT + 0.12)
	for li in _lights:
		if String(li[5]) != "" and not include_decor:
			continue
		var d: Vector2 = pos - li[0]
		d.y *= 2.0
		var f := 1.0 - clampf(d.length() / float(li[2]), 0.0, 1.0)
		var c: Color = li[1]
		l += c * float(li[3]) * f * f * 0.9
	return Color(minf(l.r, 1.25), minf(l.g, 1.2), minf(l.b, 1.15))


func light_at(pos: Vector2) -> Color:
	return _light_at(pos, true)


# ---------------------------------------------------------------- frame

func _process(_delta: float) -> void:
	var t := Time.get_ticks_msec() * 0.001
	for f in _flickers:
		var n: CanvasItem = f[0]
		if not is_instance_valid(n):
			continue
		var ph: float = f[2]
		var k := 1.0 - float(f[3]) * (0.5 + 0.5 * sin(t * 7.3 + ph)) * (0.6 + 0.4 * sin(t * 13.7 + ph * 2.0))
		n.modulate.a = float(f[1]) * k
	if focus != Vector2.INF:
		for o in _occluders:
			var nd: Node2D = o[0]
			if not is_instance_valid(nd):
				continue
			var dy := nd.position.y - focus.y
			var behind := dy > 0.0 and dy < 360.0 and absf(nd.position.x - focus.x) < float(o[1]) + 110.0
			nd.modulate.a = move_toward(nd.modulate.a, 0.38 if behind else 1.0, _delta * 4.0)
	for fl in _floaters:
		var nd: Node2D = fl[0]
		nd.position.y = float(fl[1]) + sin(t * 0.25 + float(fl[2])) * 18.0
	var cam := get_viewport().get_camera_2d()
	var c := cam.get_screen_center_position() if cam else Vector2.ZERO
	if _motes:
		_motes.position = c
	_push_lights(c, t)


func _push_lights(c: Vector2, t: float) -> void:
	var ext := get_viewport_rect().size * 0.5 / 0.8
	_la.clear()
	_lb.clear()
	var cands: Array = []
	for i in range(_lights.size()):
		var li: Array = _lights[i]
		var id: String = li[5]
		if id != "" and not bool(_decor_on.get(id, false)):
			continue
		var p: Vector2 = li[0]
		var r: float = li[2]
		if absf(p.x - c.x) > ext.x + r or absf(p.y - c.y) > ext.y + r * 0.6:
			continue
		cands.append([p.distance_squared_to(c) / maxf(1.0, float(li[3])), i])
	cands.sort_custom(func(a, b): return a[0] < b[0])
	for k in range(mini(cands.size(), MAX_SHADER_LIGHTS)):
		var i: int = cands[k][1]
		var li: Array = _lights[i]
		var fl := 1.0 - float(li[4]) * (0.5 + 0.5 * sin(t * (6.3 + i * 1.7) + i * 2.1)) * (0.6 + 0.4 * sin(t * 13.1 + i))
		var p: Vector2 = li[0]
		var col: Color = li[1]
		_la.append(Vector4(p.x, p.y, float(li[2]), float(li[3]) * fl))
		_lb.append(Vector4(col.r, col.g, col.b, 0.0))
	while _la.size() < MAX_SHADER_LIGHTS:
		_la.append(Vector4.ZERO)
		_lb.append(Vector4.ZERO)
	var n := mini(cands.size(), MAX_SHADER_LIGHTS)
	for m in _mats:
		m.set_shader_parameter("light_count", n)
		m.set_shader_parameter("light_a", _la)
		m.set_shader_parameter("light_b", _lb)
