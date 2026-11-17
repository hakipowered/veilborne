extends Node2D
## Floor spike trap (built by scenes/environment.gd _spike_trap). Grated plate on the floor with a 5x5
## grid of holes; each hole hides its own procedurally drawn spike that slides out of it:
##   idle plate -> warning (holes glow, tips peek and rattle, grit) -> strike (staggered clusters thrust
##   up with overshoot, steel glint, dust puff) -> hold -> staggered retract back into the holes.
## Spikes are clipped at the hole (only the part above the plate is drawn) and split into one y-sorted
## node per screen row, so heroines / foes standing on the plate sort between the rows.
## This node itself lives on the floor layer (plate + hole glow); `rows` go to the y-sorted layer.
## step(phase) drives everything and returns whether the trap hurts at that moment.

const ISO := 0.53
const TEX_HOLES := [-57.0, -29.0, -1.0, 27.5, 55.5] ## hole centres in forge/trap.png (200 px), from its centre
const TEX_SIZE := 200.0
const HOLE_R := 7.6 ## hole radius in texture px
const RISE := 0.075 ## seconds for one spike to thrust up
const SETTLE := 0.16 ## overshoot settle after the thrust
const SLIDE := 0.24 ## seconds for one spike to slide back down

var period := 3.2
var warn := 0.6
var up := 1.0
var size := 150.0
var rows: Array = [] ## Node2D per screen row of holes, for the y-sorted layer

var _holes: Array = [] ## Vector2 offsets from the plate centre (world, iso-squashed)
var _spikes: Array = [] ## [row, x in row, len, lean, delay_up, delay_down, peek, seed]
var _ext := PackedFloat32Array()
var _shake := PackedFloat32Array()
var _glint := PackedFloat32Array()
var _row_spikes: Array = [] ## per row: spike indices
var _glow_node: Node2D
var _warn_spr: Sprite2D
var _dust: CPUParticles2D
var _grit: CPUParticles2D
var _glow_tex: Texture2D
var _glow_col := Color(1, 0.5, 0.2)
var _w := 0.0 ## seconds since the warning began (wraps every period)
var _warn_a := 0.0
var _struck := false
var _settled := false
var _hot := false ## forge: heads glow red during the warning
# palette (per chapter)
var _shaft_l := Color(0.16, 0.14, 0.19)
var _shaft_r := Color(0.34, 0.31, 0.38)
var _head_l := Color(0.56, 0.56, 0.62)
var _head_r := Color(0.9, 0.9, 0.93)
var _ink := Color(0.05, 0.04, 0.07)
var _pit := Color(0.03, 0.02, 0.03, 0.9)

func setup(c: Vector2, chapter: String, light: Color, plate_tex: Texture2D, glow_tex: Texture2D, dot_tex: Texture2D, smoke_tex: Texture2D, p_period: float, p_warn: float, p_up: float) -> void:
	period = p_period
	warn = p_warn
	up = p_up
	position = c
	z_index = -67
	_glow_tex = glow_tex
	_glow_col = Color(1.0, 0.35, 0.15) if chapter == "forge" else light
	var plate_mod := Color(0.9, 0.86, 0.86)
	var dust_col := Color(0.62, 0.56, 0.5)
	match chapter:
		"garden":
			plate_mod = Color(0.7, 0.85, 0.8)
			_shaft_l = Color(0.14, 0.2, 0.18)
			_shaft_r = Color(0.3, 0.42, 0.36)
			_head_l = Color(0.58, 0.6, 0.5)
			_head_r = Color(0.9, 0.92, 0.82)
			dust_col = Color(0.55, 0.6, 0.5)
		"forge":
			_shaft_l = Color(0.17, 0.12, 0.11)
			_shaft_r = Color(0.38, 0.27, 0.23)
			_head_l = Color(0.62, 0.55, 0.5)
			_head_r = Color(0.95, 0.88, 0.8)
			dust_col = Color(0.5, 0.4, 0.34)
			_hot = true
		"hollow":
			_shaft_l = Color(0.15, 0.11, 0.21)
			_shaft_r = Color(0.33, 0.27, 0.43)
			_head_l = Color(0.6, 0.55, 0.7)
			_head_r = Color(0.92, 0.88, 1.0)
			dust_col = Color(0.5, 0.45, 0.6)
	# --- floor layer: plate, hole glow, broad warning wash
	var holder := Node2D.new()
	holder.scale = Vector2(1.0, ISO)
	add_child(holder)
	var plate := Sprite2D.new()
	plate.texture = plate_tex
	plate.rotation = PI * 0.25
	plate.scale = Vector2.ONE * size / plate_tex.get_width()
	plate.modulate = plate_mod
	holder.add_child(plate)
	_warn_spr = Sprite2D.new()
	_warn_spr.texture = glow_tex
	_warn_spr.material = _additive()
	_warn_spr.scale = Vector2.ONE * size * 1.25 / 128.0
	_warn_spr.modulate = Color(_glow_col, 0.0)
	holder.add_child(_warn_spr)
	_glow_node = Node2D.new()
	_glow_node.rotation = PI * 0.25
	_glow_node.scale = Vector2.ONE * size / TEX_SIZE
	_glow_node.material = _additive()
	_glow_node.draw.connect(_draw_hole_glow)
	holder.add_child(_glow_node)
	# --- holes -> spikes, grouped by screen row (i + j after the 45 degree turn)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(Vector2i(roundi(c.x), roundi(c.y)))
	var k := size / TEX_SIZE
	var origin := Vector2(TEX_HOLES[rng.randi() % 5], TEX_HOLES[rng.randi() % 5]) ## strike wave starts here
	for ri in range(9):
		var row := Node2D.new()
		row.draw.connect(_draw_row.bind(ri))
		rows.append(row)
		_row_spikes.append([])
	for i in range(5):
		for j in range(5):
			var tp := Vector2(TEX_HOLES[i], TEX_HOLES[j])
			var w := (tp * k).rotated(PI * 0.25)
			w.y *= ISO
			_holes.append(w)
			var ri := i + j
			var d := tp.distance_to(origin) / (TEX_SIZE * 0.75)
			# three-ish clusters fire in a quick ripple from the origin hole
			var dup := snappedf(d * 0.11, 0.035) + rng.randf() * 0.012
			var ddown := (1.0 - d) * 0.13 + rng.randf() * 0.07
			var idx := _spikes.size()
			_spikes.append([ri, w.x, rng.randf_range(32.0, 46.0), rng.randf_range(-0.09, 0.09), dup, ddown, rng.randf_range(0.07, 0.15), rng.randf() * TAU])
			_row_spikes[ri].append(idx)
	for ri in range(9):
		var row: Node2D = rows[ri]
		# row node sits on the holes' ground line so y-sort matches the spikes' feet
		row.position = c + Vector2(0, _holes[_row_spikes[ri][0]].y)
	_ext.resize(_spikes.size())
	_shake.resize(_spikes.size())
	_glint.resize(_spikes.size())
	# --- dust: a burst on the strike (front row, so it billows over the spike feet) + grit in the tell
	_dust = _puff(smoke_tex, dust_col, 16, 0.75)
	_dust.emission_rect_extents = Vector2(size * 0.42, size * 0.42 * ISO * 0.8)
	_dust.initial_velocity_min = 30.0
	_dust.initial_velocity_max = 85.0
	_dust.scale_amount_min = 0.35
	_dust.scale_amount_max = 0.8
	var front: Node2D = rows[8]
	_dust.position = c - front.position + Vector2(0, -4)
	front.add_child(_dust)
	_grit = _puff(dot_tex, dust_col.lightened(0.15), 6, 0.5)
	_grit.one_shot = false
	_grit.explosiveness = 0.0
	_grit.emitting = false
	_grit.emission_rect_extents = Vector2(size * 0.36, size * 0.36 * ISO)
	_grit.initial_velocity_min = 12.0
	_grit.initial_velocity_max = 30.0
	_grit.scale_amount_min = 0.08
	_grit.scale_amount_max = 0.16
	_grit.position = _dust.position
	front.add_child(_grit)

func _additive() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	return m

func _puff(tex: Texture2D, col: Color, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = life
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = false
	p.local_coords = false
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.gravity = Vector2(0, 40)
	p.damping_min = 60.0
	p.damping_max = 120.0
	p.randomness = 0.5
	p.lifetime_randomness = 0.4
	var g := Gradient.new()
	g.set_color(0, Color(col, 0.0))
	g.set_color(1, Color(col, 0.0))
	g.add_point(0.15, Color(col, 0.7))
	g.add_point(0.6, Color(col, 0.35))
	p.color_ramp = g
	var sc := Curve.new()
	sc.add_point(Vector2(0, 0.5))
	sc.add_point(Vector2(1, 1.3))
	p.scale_amount_curve = sc
	return p

## Advance to cycle phase ph (0..period, same clock as before: warning at period - up - warn,
## strike at period - up). Returns true while the spikes are up (hazard active).
func step(ph: float) -> bool:
	var warn_at := period - up - warn
	var w := fposmod(ph - warn_at, period)
	var prev := _w
	_w = w
	var strike := warn
	var retract := warn + up - 0.12
	# warning wash + hole glow
	var g := 0.0
	if w < warn:
		g = w / warn
	elif w < retract + SLIDE:
		g = 1.0 - clampf((w - strike) / 0.35, 0.0, 0.75)
	if w > retract:
		g *= clampf(1.0 - (w - retract) / SLIDE, 0.0, 1.0)
	_warn_a = g
	_warn_spr.modulate.a = 0.42 * g
	# strike / tell effects (edge-triggered on the wrapped clock)
	if prev < strike and w >= strike:
		_dust.restart()
	_grit.emitting = w > 0.12 and w < strike
	var busy := w < retract + SLIDE + 0.3
	if not busy:
		if not _settled:
			_settled = true
			_ext.fill(0.0)
			_glint.fill(0.0)
			for r in rows:
				r.queue_redraw()
			_glow_node.queue_redraw()
		return false
	_settled = false
	var t := w
	var above := 0
	for i in range(_spikes.size()):
		var s: Array = _spikes[i]
		var e := 0.0
		var shake := 0.0
		var glint := 0.0
		var u: float = t - strike - float(s[4])
		var peek: float = s[6]
		if u < 0.0:
			# tell: tips creep up out of the holes and rattle
			var pk := clampf((t - 0.08 - float(s[4]) * 2.0) / 0.25, 0.0, 1.0)
			var rattle := sin(t * 55.0 + float(s[7])) * 0.5 + sin(t * 31.0 + float(s[7]) * 2.0) * 0.5
			e = peek * pk + 0.025 * rattle * pk
			shake = rattle * 0.9 * pk
		elif u < RISE:
			var k := u / RISE
			e = lerpf(peek, 1.16, 1.0 - (1.0 - k) * (1.0 - k))
		elif u < RISE + SETTLE:
			var k := (u - RISE) / SETTLE
			e = 1.0 + 0.16 * cos(k * PI * 1.5) * (1.0 - k)
		else:
			e = 1.0
		if u >= 0.0 and fmod(float(s[7]), 1.0) < 0.28:
			glint = clampf(1.0 - absf(u - RISE) / 0.12, 0.0, 1.0)
		var dn: float = t - retract - float(s[5])
		if dn > 0.0:
			# small unlock jolt, then slide back down
			var k := clampf(dn / SLIDE, 0.0, 1.0)
			e *= 1.0 - k * k * (3.0 - 2.0 * k)
			if dn < 0.05:
				e += 0.03 * sin(dn * 120.0)
		e = maxf(e, 0.0)
		_ext[i] = e
		_shake[i] = shake
		_glint[i] = glint
		if e > 0.5:
			above += 1
	for r in rows:
		r.queue_redraw()
	_glow_node.queue_redraw()
	return above * 2 >= _spikes.size()

func _draw_hole_glow() -> void:
	if _warn_a <= 0.01:
		return
	var col := Color(_glow_col, 0.75 * _warn_a)
	var r := HOLE_R * 2.6
	var flick := 0.85 + 0.15 * sin(_w * 40.0)
	for i in range(5):
		for j in range(5):
			var p := Vector2(TEX_HOLES[i], TEX_HOLES[j])
			_glow_node.draw_texture_rect(_glow_tex, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(col, col.a * flick))

func _draw_row(ri: int) -> void:
	var row: Node2D = rows[ri]
	for i in _row_spikes[ri]:
		var e: float = _ext[i]
		if e <= 0.004:
			continue
		var s: Array = _spikes[i]
		_draw_spike(row, Vector2(float(s[1]) + _shake[i], 0.0), float(s[2]), float(s[3]), e, _glint[i])

## One spike whose foot is at b (hole centre), extended e (0..~1.16) of its length L. Only the part that
## has left the hole is drawn: the profile is cut at the visible length, so it slides out of the grate.
func _draw_spike(ci: CanvasItem, b: Vector2, L: float, lean: float, e: float, glint: float) -> void:
	var v := L * e
	var dir := Vector2(sin(lean), -cos(lean))
	var side := Vector2(-dir.y, dir.x) ## points screen-right
	var tip := b + dir * v
	# profile along the spike from the tip: [distance from tip / L, half width]
	var prof := [[0.0, 0.0], [0.16, 1.5], [0.4, 2.5], [0.43, 3.1], [0.47, 2.7], [1.2, 3.9]]
	var pts_l := PackedVector2Array()
	var pts_r := PackedVector2Array()
	for n in range(prof.size()):
		var d: float = prof[n][0] * L
		var hw: float = prof[n][1]
		if d >= v:
			var pd: float = prof[n - 1][0] * L
			hw = lerpf(prof[n - 1][1], hw, (v - pd) / maxf(d - pd, 0.001))
			d = v
		var c := tip - dir * d
		pts_l.append(c - side * hw)
		pts_r.append(c + side * hw)
		if d >= v:
			break
	var cnt := pts_l.size()
	if cnt < 2:
		return
	# hole mouth shadow behind the foot
	var hw0 := (pts_r[cnt - 1] - pts_l[cnt - 1]).length() * 0.5 + 1.5
	ci.draw_set_transform(b, 0.0, Vector2(1.0, 0.45))
	ci.draw_circle(Vector2.ZERO, hw0, _pit)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	var hot := 0.0
	if _hot and _w < warn + 0.5:
		hot = clampf(_w / warn, 0.0, 1.0) * clampf(1.0 - (_w - warn) / 0.5, 0.0, 1.0)
	var head_l := _head_l.lerp(Color(1.0, 0.45, 0.15), hot * 0.7)
	var head_r := _head_r.lerp(Color(1.0, 0.75, 0.4), hot * 0.6)
	# shaft (below the neck): dark iron, darker still at the hole
	var neck := mini(3, cnt - 1)
	if cnt - 1 > neck:
		var sl := PackedVector2Array()
		var sr := PackedVector2Array()
		var cl := PackedColorArray()
		var cr := PackedColorArray()
		for n in range(neck, cnt):
			sl.append(pts_l[n])
			sr.append(pts_r[n])
		var mid_n := PackedVector2Array()
		for n in range(neck, cnt):
			mid_n.append((pts_l[n] + pts_r[n]) * 0.5)
		var poly_l := PackedVector2Array(sl)
		var poly_r := PackedVector2Array(mid_n)
		for n in range(mid_n.size() - 1, -1, -1):
			poly_l.append(mid_n[n])
			poly_r.append(sr[n])
		var mid_c := _shaft_l.lerp(_shaft_r, 0.45)
		for n in range(neck, cnt):
			cl.append(_shaft_l * _depth(n, cnt))
		for n in range(cnt - 1, neck - 1, -1):
			cl.append(mid_c * _depth(n, cnt))
		for n in range(neck, cnt):
			cr.append(mid_c * _depth(n, cnt))
		for n in range(cnt - 1, neck - 1, -1):
			cr.append(_shaft_r * _depth(n, cnt))
		ci.draw_polygon(poly_l, cl)
		ci.draw_polygon(poly_r, cr)
	# head: two-tone steel blade
	var hn := mini(neck, cnt - 1)
	var hl := PackedVector2Array()
	var hr := PackedVector2Array()
	for n in range(0, hn + 1):
		hl.append(pts_l[n])
		hr.append(pts_r[n])
	var ridge_end := (pts_l[hn] + pts_r[hn]) * 0.5
	var pl := PackedVector2Array(hl)
	pl.append(ridge_end)
	var pr := PackedVector2Array(hr)
	pr.append(ridge_end)
	if pl.size() >= 3:
		ci.draw_colored_polygon(pl, head_l)
		ci.draw_colored_polygon(pr, head_r)
	# ink outline round the visible part (open at the foot: it continues into the hole)
	var outline := PackedVector2Array()
	for n in range(cnt - 1, -1, -1):
		outline.append(pts_l[n])
	for n in range(1, cnt):
		outline.append(pts_r[n])
	ci.draw_polyline(outline, _ink, 1.3, true)
	if hn >= 2:
		ci.draw_line(pts_l[hn], pts_r[hn], Color(_ink, 0.7), 1.0)
	# ridge highlight + glint on the strike
	ci.draw_line(tip + dir * -1.5, ridge_end, Color(1, 1, 1, 0.35 + 0.5 * glint), 1.0)
	if glint > 0.05:
		var gp := tip - dir * (L * 0.2) + side * 1.0
		var a := Color(1.0, 1.0, 0.95, glint)
		var r := 3.5 * glint + 1.0
		ci.draw_line(gp - Vector2(r, 0), gp + Vector2(r, 0), a, 1.2)
		ci.draw_line(gp - Vector2(0, r * 1.3), gp + Vector2(0, r * 1.3), a, 1.2)
		ci.draw_circle(gp, 1.4 * glint + 0.5, a)

## Shaft shading: the foot (last profile point) sits in the hole's shadow.
func _depth(n: int, cnt: int) -> Color:
	return Color(0.5, 0.5, 0.5) if n == cnt - 1 else Color.WHITE
