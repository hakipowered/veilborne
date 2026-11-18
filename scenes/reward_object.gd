extends Node2D
## A reward you can see and walk up to: the Warden's boon orb, the forge anvil, the healing chalice,
## a heap of gold or Veil Shards, or a shop ware on Mister Wick's counter (price tag).
## Painted art with a soft coloured light, a bob and drifting motes. Lives in the arena's y-sorted
## entity layer; scenes/room_rewards.gd places it, shows its prompt and applies it on use.
##   var o = RewardObject.new(); o.setup("heal", {...}); entities.add_child(o)

const VTheme = preload("res://ui/theme.gd")

## kind -> art, height on screen (world px), light colour, prompt text
const ART := {
	"boon": {"tex": "", "h": 120.0, "float": 70.0, "title": "%s's Boon", "desc": "Choose one of three gifts.", "verb": "Take"},
	"forge": {"tex": "res://art/env/forge/anvil.png", "h": 170.0, "float": 0.0, "title": "The Forge", "desc": "Temper your weapon: choose one of three upgrades.", "verb": "Use"},
	"heal": {"tex": "res://art/env/rewards/chalice.png", "h": 190.0, "float": 0.0, "title": "Healing Chalice", "desc": "Drink to restore %d%% of your health.", "verb": "Drink"},
	"gold": {"tex": "res://art/ui/reward_gold.png", "h": 92.0, "float": 0.0, "title": "Gilded Coin", "desc": "Scoop up %d gold.", "verb": "Take"},
	"shards": {"tex": "res://art/env/rewards/shards.png", "h": 150.0, "float": 0.0, "title": "Veil Shards", "desc": "Gather %d Veil Shards.", "verb": "Take"},
}

signal used(obj: Node2D, hero: Node)

var kind := "boon"
var patron := "" ## boon: which Warden
var color := Color(1, 0.85, 0.5)
var title := ""
var desc := ""
var verb := "Take"
var price := 0 ## > 0: a shop ware (bought with gold)
var amount := 0 ## gold / shards / heal %
var auto := false ## picked up by walking over it
var taken := false
var reach := 120.0 ## interaction radius around `position` (the floor spot)
var art_offset := Vector2.ZERO ## art drawn away from the floor spot (wares sit up on the counter)
var use_offset := Vector2.ZERO ## where a heroine stands to use it, from `position` (wares: the floor in front of the counter)


var use_axis := Vector2.ZERO ## wares: unit vector along the counter; picking favours the ware she is level with


## World point a heroine walks to / is measured from to use this object.
func use_point() -> Vector2:
	return global_position + use_offset


## How far `p` is from using this object, compared with `reach`. Along a counter, sideways distance counts
## in full and distance out from the counter only a third, so standing in front of a ware picks that ware.
func use_distance(p: Vector2) -> float:
	var d := p - use_point()
	if use_axis == Vector2.ZERO:
		return d.length()
	var along := d.dot(use_axis)
	var out := d.dot(Vector2(-use_axis.y, use_axis.x))
	return Vector2(along, out * 0.33).length()

var _t := 0.0
var _ph := 0.0
var _art: Sprite2D
var _halo: Sprite2D
var _pool: Sprite2D
var _sigil: Sprite2D
var _orb: Node2D
var _motes: CPUParticles2D
var _tag: Node2D
var _near := 0.0
var _float := 0.0
var _art_y := 0.0

static var _glow_tex: Texture2D = null


static func glow_tex() -> Texture2D:
	if _glow_tex == null:
		# soft radial falloff baked into an image (white; tinted by modulate)
		var n := 128
		var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
		for y in range(n):
			for x in range(n):
				var d := Vector2(x + 0.5 - n * 0.5, y + 0.5 - n * 0.5).length() / (n * 0.5)
				var a := clampf(1.0 - d, 0.0, 1.0)
				img.set_pixel(x, y, Color(1, 1, 1, a * a * (3.0 - 2.0 * a)))
		_glow_tex = ImageTexture.create_from_image(img)
	return _glow_tex


static func additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m


## opts: patron, color, title, desc, price, amount, tex (override art), h (override height), art_offset
func setup(p_kind: String, opts := {}) -> void:
	kind = p_kind
	var a: Dictionary = ART.get(kind, ART["gold"])
	patron = String(opts.get("patron", ""))
	color = opts.get("color", Game.REWARDS.get(kind, {}).get("color", color))
	amount = int(opts.get("amount", 0))
	price = int(opts.get("price", 0))
	auto = bool(opts.get("auto", (kind == "gold" or kind == "shards") and price <= 0))
	art_offset = opts.get("art_offset", Vector2.ZERO)
	verb = String(opts.get("verb", a["verb"]))
	title = String(opts.get("title", a["title"]))
	if title.contains("%s"):
		title = title % String(Game.PATRONS.get(patron, {"name": "Warden"})["name"]).get_slice(",", 0).get_slice(" ", 0)
	desc = String(opts.get("desc", a["desc"]))
	if desc.contains("%d"):
		desc = desc % amount
	_ph = randf() * TAU
	_float = float(opts.get("float", a["float"]))
	_build(opts.get("tex", a["tex"]), float(opts.get("h", a["h"])))


func _build(tex_src, h: float) -> void:
	var add := additive()
	var base := art_offset
	# light pool on the floor
	_pool = Sprite2D.new()
	_pool.texture = glow_tex()
	_pool.material = add
	_pool.position = base
	_pool.scale = Vector2(2.6, 1.15) * (0.75 if price > 0 else 1.0)
	_pool.modulate = Color(color, 0.55)
	add_child(_pool)
	if kind == "boon" and price <= 0:
		# the Warden's sigil turning slowly on the floor (painted white lines on black: additive)
		var sp := "res://art/env/sigil_%s.webp" % patron
		if ResourceLoader.exists(sp):
			var holder := Node2D.new()
			holder.position = base
			holder.scale = Vector2(1.0, 0.5)
			add_child(holder)
			_sigil = Sprite2D.new()
			_sigil.texture = load(sp)
			_sigil.material = add
			_sigil.scale = Vector2.ONE * 230.0 / 1024.0
			_sigil.modulate = Color(color.lightened(0.2), 0.85)
			holder.add_child(_sigil)
	# soft shadow
	if _float <= 0.0:
		var sh := Sprite2D.new()
		sh.texture = glow_tex()
		sh.modulate = Color(0, 0, 0, 0.55)
		sh.scale = Vector2(1.5, 0.5) * (0.6 if price > 0 else 1.0)
		sh.position = base + Vector2(0, 2)
		add_child(sh)
	# halo behind the art
	_halo = Sprite2D.new()
	_halo.texture = glow_tex()
	_halo.material = add
	_halo.modulate = Color(color, 0.7)
	add_child(_halo)
	# the art itself
	var tex: Texture2D = null
	if tex_src is Texture2D:
		tex = tex_src
	elif String(tex_src) != "":
		var s := String(tex_src)
		tex = load(s) if s.begins_with("res://") else VTheme.tex(s)
	_art = Sprite2D.new()
	_art.centered = false
	if tex:
		_art.texture = tex
		var sc := h / float(tex.get_height())
		_art.scale = Vector2(sc, sc)
		_art.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height())
	add_child(_art)
	if kind == "boon" and tex == null:
		_orb = Node2D.new()
		_orb.draw.connect(_draw_orb)
		_art.add_child(_orb)
	_art_y = base.y - _float
	_art.position = Vector2(base.x, _art_y)
	_halo.position = base + Vector2(0, -h * 0.5 - _float)
	_halo.scale = Vector2.ONE * maxf(h, 90.0) / 128.0 * 2.0
	if price > 0: # wares: a small warm glint, not a floodlight over the stall
		_halo.scale *= 0.6
		_pool.scale *= 0.6
	# motes drifting up
	_motes = CPUParticles2D.new()
	_motes.amount = 14 if price <= 0 else 6
	_motes.lifetime = 1.8
	_motes.texture = glow_tex()
	_motes.material = add
	_motes.position = base + Vector2(0, -h * 0.35 - _float)
	_motes.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
	_motes.emission_sphere_radius = h * 0.4
	_motes.direction = Vector2(0, -1)
	_motes.spread = 25.0
	_motes.gravity = Vector2(0, -30)
	_motes.initial_velocity_min = 10.0
	_motes.initial_velocity_max = 40.0
	_motes.scale_amount_min = 0.05
	_motes.scale_amount_max = 0.12
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0))
	ramp.add_point(0.3, Color(1, 1, 1, 1))
	ramp.set_color(ramp.get_point_count() - 1, Color(1, 1, 1, 0))
	_motes.color_ramp = ramp
	_motes.color = color.lightened(0.35)
	add_child(_motes)
	if price > 0:
		_tag = Node2D.new()
		_tag.z_index = 2
		_tag.position = base + Vector2(0, 30)
		_tag.draw.connect(_draw_tag)
		add_child(_tag)


## The boon orb: the Warden's painted face in a gold ring over dark glass (child of _art, so it bobs).
func _draw_orb() -> void:
	var c := Vector2(0, -64.0)
	var r := 54.0
	var face := VTheme.tex("face_" + patron)
	var ring := VTheme.tex("ring")
	_orb.draw_circle(c, r + 4.0, Color(0.03, 0.01, 0.05, 0.95))
	if face:
		_orb.draw_texture_rect(face, Rect2(c - Vector2(r, r), Vector2(r, r) * 2.0), false)
	if ring:
		var rr := r * 1.32
		_orb.draw_texture_rect(ring, Rect2(c - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false, Color(1, 1, 1).lerp(color, 0.15))


func _bob() -> float:
	return sin(_t * 2.2 + _ph) * (9.0 if _float > 0.0 else 0.0)


func _draw_tag() -> void:
	var font := VTheme.font("caps")
	var txt := str(price)
	var fs := 22
	var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x if font else 30.0
	var w := tw + 52.0
	var rect := Rect2(-w * 0.5, -16, w, 34)
	var afford := Game.run_gold >= price
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.09, 0.04, 0.08, 0.92)
	sb.border_color = VTheme.GOLD if afford else Color(0.55, 0.3, 0.3)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(9)
	sb.shadow_color = Color(0, 0, 0, 0.5)
	sb.shadow_size = 5
	_tag.draw_style_box(sb, rect)
	var coin := VTheme.tex("reward_gold")
	if coin:
		_tag.draw_texture_rect(coin, Rect2(rect.position.x + 6, -12, 30, 24), false)
	if font:
		_tag.draw_string(font, Vector2(rect.position.x + 40, 9), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs,
			Color(1.0, 0.86, 0.45) if afford else Color(0.85, 0.5, 0.45))


func set_tag_visible(on: bool) -> void:
	if _tag:
		_tag.visible = on


func set_near(on: bool) -> void:
	_near = 1.0 if on else 0.0


func _process(delta: float) -> void:
	_t += delta
	var pulse := 0.5 + 0.5 * sin(_t * 2.4 + _ph)
	if taken:
		return
	if _art:
		_art.position.y = _art_y + _bob()
		_art.modulate = Color(1, 1, 1).lerp(Color(1.25, 1.2, 1.1), _near * 0.6)
	var dim := 0.45 if price > 0 else 1.0
	if _halo:
		_halo.modulate.a = (0.4 + 0.25 * pulse + 0.3 * _near) * dim
	if _pool:
		_pool.modulate.a = (0.35 + 0.2 * pulse + 0.3 * _near) * dim
	if _sigil:
		_sigil.rotation = _t * 0.35
	if _tag:
		_tag.position.y = art_offset.y + 30.0 + _bob()
		_tag.queue_redraw()


## Fades the object out after it was used (wares vanish off the counter, the chalice drains...).
func consume() -> void:
	if taken:
		return
	taken = true
	if _motes:
		_motes.emitting = false
	var tw := create_tween().set_parallel()
	tw.tween_property(self, "modulate:a", 0.0, 0.6)
	if _art:
		tw.tween_property(_art, "position:y", _art.position.y - 40.0, 0.6).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.chain().tween_callback(queue_free)
