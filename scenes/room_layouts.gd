extends RefCounted
## Veilborne chamber shapes (ENVIRONMENT). Every chamber is one of the templates below: an irregular floor
## (L-halls, T and cross shapes, a long gallery with alcoves, a ledge along a chasm, an island on bridges,
## a ring round a pit, a crescent, broken steps, an hourglass, pillared naves, boss halls...).
##
## A template is a list of floor primitives in iso GRID units (one unit = one floor slab of the painted
## floor: world x = (u - v) * TW, y = (u + v) * TH). Ops run in order and build a signed distance field:
##   "add"  grows the floor           "sub"  carves a chasm (shots still fly over it)
##   "cut"  removes floor for good (outer void: shots stop there too)
## Primitives: ["rect", u0, v0, u1, v1]  ["crect", u0, v0, u1, v1, chamfer]  ["circle", u, v, r]
##   ["capsule", u0, v0, u1, v1, r]  ["spoly", [[X, Y], ...]] (screen units: X * TW, Y * TH)
## Added pieces must OVERLAP (by a unit or so), never just touch: the field is a min() of the pieces'
## distances, so a seam where two edges meet edge to edge would read as a zero-width ridge foes can't cross.
## The field is sampled on a grid (RES) and drives everything environment.gd needs:
##   floor fill (marching squares, jagged lip), every edge with its outward normal (cliff faces, walls on
##   the back envelope), resolve() (heroes and foes stay on the floor), spawn / prop / hazard spots,
##   a coarse flow field (steer) so foes walk round chasms instead of pressing against the edge.
## Pick per room with pick(kind, run_seed, room_index): kind combat | elite | boss | small; consecutive
## rooms never repeat a template (disjoint pools, and a seeded permutation inside each pool).

const TW := 104.0        ## half width of one floor slab (world px), matches the floor shader's iso cell
const TH := 55.47        ## half height (TW * 0.5333)
const UNIT := 152.0      ## ground px (x, y * 2) per grid unit
const RES := 0.25        ## field sample spacing (grid units)
const MARGIN := 30.0     ## ground px kept between a walker's edge and the painted lip
const NAV := 0.5         ## flow-field cell (grid units)

const TEMPLATES := {
	# ------------------------------------------------------------------ combat
	"ell": {"title": "L-Hall", "kind": "combat", "start": [-2.6, 4.2], "rough": 0.8,
		"ops": [["add", "rect", -6.0, -5.5, 0.0, 5.5], ["add", "rect", -1.0, -5.5, 6.0, 0.0]],
		"pillars": [[3.6, -3.0]]},
	"tee": {"title": "Tee", "kind": "combat", "start": [0.0, 5.4], "rough": 0.7,
		"ops": [["add", "rect", -7.0, -6.0, 7.0, -1.4], ["add", "rect", -2.3, -2.6, 2.3, 6.6],
			["sub", "circle", -4.4, -3.6, 1.0]]},
	"cross": {"title": "Cross", "kind": "combat", "start": [5.6, 0.0], "rough": 0.7,
		"ops": [["add", "rect", -2.5, -7.0, 2.5, 7.0], ["add", "rect", -7.0, -2.5, 7.0, 2.5],
			["add", "crect", -4.2, -4.2, 4.2, 4.2, 2.2]]},
	"gallery": {"title": "Gallery", "kind": "combat", "start": [7.2, 0.2], "rough": 0.6,
		"ops": [["add", "rect", -8.5, -2.5, 8.5, 2.5], ["add", "rect", -6.2, 1.5, -2.8, 4.9],
			["add", "rect", 1.6, 1.5, 5.0, 4.9], ["add", "rect", -2.4, -5.0, 1.4, -1.5], ["add", "rect", -8.5, -5.0, -5.4, -1.5]],
		"pillars": [[-3.2, 0.0], [3.0, 0.0]]},
	"isle": {"title": "Sundered Isle", "kind": "combat", "start": [5.4, 5.4], "rough": 1.0,
		"ops": [["add", "crect", -6.6, -6.6, 6.6, 6.6, 1.4], ["sub", "circle", 0.0, 0.0, 5.1], ["add", "circle", 0.0, 0.0, 3.1],
			["add", "rect", -1.15, -6.6, 1.15, 6.6], ["add", "rect", -6.6, -1.15, 6.6, 1.15]]},
	"ledge": {"title": "Chasm Ledge", "kind": "combat", "start": [-0.5, 5.6], "rough": 1.4,
		"ops": [["add", "spoly", [[-13.0, -1.0], [0.0, -14.0], [13.0, -1.0], [11.5, 1.5], [7.5, 2.6], [5.0, 6.4], [0.5, 7.6],
			[-3.5, 5.0], [-8.0, 4.0], [-11.5, 1.6]]], ["sub", "circle", 4.6, -3.2, 1.25], ["sub", "circle", -3.6, 2.6, 1.1]]},
	"ring": {"title": "Ring of the Pit", "kind": "combat", "start": [4.1, 4.1], "rough": 1.0,
		"ops": [["add", "circle", 0.0, 0.0, 6.7], ["sub", "circle", 0.0, 0.0, 2.6]]},
	"crescent": {"title": "Crescent", "kind": "combat", "start": [-1.4, 5.7], "rough": 1.2,
		"ops": [["add", "circle", 0.0, 0.0, 7.0], ["cut", "circle", 3.4, 3.4, 4.3]],
		"pillars": [[-2.4, -2.4]]},
	"steps": {"title": "Broken Steps", "kind": "combat", "start": [4.2, 4.0], "rough": 1.0,
		"ops": [["add", "rect", -7.6, -6.4, -1.2, -1.0], ["add", "rect", -4.2, -3.0, 2.2, 2.4], ["add", "rect", -0.6, 0.4, 5.6, 5.6]]},
	"hourglass": {"title": "Hourglass", "kind": "combat", "start": [4.2, 3.8], "rough": 1.0,
		"ops": [["add", "circle", -3.5, -3.5, 4.5], ["add", "circle", 3.0, 3.0, 3.6], ["add", "capsule", -3.0, -3.0, 3.0, 3.0, 1.5]]},
	# ------------------------------------------------------------------ elite (medium, more open)
	"nave": {"title": "Pillared Nave", "kind": "elite", "start": [3.9, 3.9], "rough": 0.6,
		"ops": [["add", "crect", -6.2, -6.2, 6.2, 6.2, 2.6]],
		"pillars": [[-2.6, -2.6], [2.6, -2.6], [-2.6, 2.6], [2.6, 2.6]]},
	"twin": {"title": "Twin Chasms", "kind": "elite", "start": [4.2, 4.2], "rough": 0.9,
		"ops": [["add", "crect", -6.4, -6.4, 6.4, 6.4, 2.2], ["sub", "circle", -2.8, 1.6, 1.6], ["sub", "circle", 1.6, -2.8, 1.6]]},
	# ------------------------------------------------------------------ boss halls (big, mostly open)
	# Boss halls are about 1.6x a combat room across (the reference's boss rooms run ~1.8x), so set pieces and
	# adds have space and a heroine can always run out of a ring.
	"boss_round": {"title": "Round Hall", "kind": "boss", "start": [7.2, 7.2], "rough": 0.9,
		"ops": [["add", "circle", 0.0, 0.0, 11.2], ["add", "crect", -10.4, -10.4, 0.0, 0.0, 0.0],
			["sub", "circle", 7.3, -2.9, 1.3], ["sub", "circle", -2.9, 7.3, 1.3]]},
	"boss_octagon": {"title": "Great Octagon", "kind": "boss", "start": [6.7, 6.7], "rough": 0.7,
		"ops": [["add", "crect", -10.9, -10.9, 10.9, 10.9, 4.6], ["cut", "rect", 9.4, -1.5, 11.7, 1.5], ["cut", "rect", -1.5, 9.4, 1.5, 11.7]],
		"pillars": [[-6.0, -1.3], [-1.3, -6.0]]},
	# ------------------------------------------------------------------ small rooms (shop, rewards, rest)
	"small_round": {"title": "Alcove", "kind": "small", "start": [2.6, 2.6], "rough": 0.9,
		"ops": [["add", "circle", 0.0, 0.0, 5.0], ["add", "rect", -4.6, -4.6, 0.0, 0.0]]},
	"small_nook": {"title": "Nook", "kind": "small", "start": [2.8, 2.8], "rough": 0.7,
		"ops": [["add", "crect", -4.8, -4.8, 4.8, 4.8, 1.8], ["cut", "rect", 3.0, -5.0, 5.0, -3.0]]},
}

## Template ids per room kind, in a stable order (the per-run permutation shuffles them).
static func pool(kind: String) -> Array:
	var k := kind if kind in ["combat", "elite", "boss", "small"] else "combat"
	var a: Array = []
	for id in TEMPLATES:
		if TEMPLATES[id]["kind"] == k:
			a.append(id)
	return a

## Template for a room: a seeded permutation of the kind's pool walked by room index, so consecutive rooms
## of one kind always differ (the pools are disjoint, so a kind change differs too).
static func pick(kind: String, run_seed: int, room_index: int) -> String:
	var ids := pool(kind)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("layouts:%d:%s" % [run_seed, kind])
	for i in range(ids.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = ids[i]
		ids[i] = ids[j]
		ids[j] = t
	return ids[posmod(room_index, ids.size())]

# =============================================================== instance

var id := ""
var title := ""
var data: Dictionary = {}
var _u0 := 0.0               ## grid origin of the field samples
var _v0 := 0.0
var _nu := 0
var _nv := 0
var _f := PackedFloat32Array()    ## floor field (grid units, < 0 inside)
var _h := PackedFloat32Array()    ## hull field: floor plus chasms (shots fly there)
var _w := PackedFloat32Array()    ## walk field: floor minus solid props (steering / flow field only)
var bounds := Rect2()             ## world bounds of the floor
var start := Vector2.ZERO         ## heroes' entry (world)
var loops: Array = []             ## visual outlines: [{pts: PackedVector2Array (world, jagged), ids: Array, hole: bool}]
var edges: Array = []             ## [{a, b, n (outward world normal), type: "wall"|"cliff"|"side", loop, i}]
var wall_runs: Array = []         ## [PackedVector2Array] contiguous wall polylines (world, left to right along the wall)
var wall_normals: Array = []      ## per run: Array of outward normals per segment
var fill_verts := PackedVector2Array()
var fill_polys: Array = []
var pillars: Array = []           ## world positions of pillar clusters
var _cross := {}                  ## crossing id -> world point (jagged)
var _nav_w := 0
var _nav_h := 0
var _nav_ok := PackedByteArray()
var _nav_cache := {}
var _nav_order: Array = []

static func to_grid(p: Vector2) -> Vector2:
	return Vector2((p.x / TW + p.y / TH) * 0.5, (p.y / TH - p.x / TW) * 0.5)

static func to_world(g: Vector2) -> Vector2:
	return Vector2((g.x - g.y) * TW, (g.x + g.y) * TH)

func build(template_id: String, rng: RandomNumberGenerator, wall_h: float) -> void:
	id = template_id if TEMPLATES.has(template_id) else "ell"
	data = TEMPLATES[id]
	title = data["title"]
	_sample_fields()
	_contour()
	_classify(wall_h, rng)
	_w = _f.duplicate()
	_build_nav()
	var st: Array = data["start"]
	start = resolve(to_world(Vector2(st[0], st[1])), 60.0)
	pillars = []
	for p in data.get("pillars", []):
		pillars.append(to_world(Vector2(p[0], p[1])))

# --------------------------------------------------------------- field
func _prim_bounds(pr: Array) -> Rect2:
	match String(pr[1]):
		"rect", "crect":
			return Rect2(pr[2], pr[3], pr[4] - pr[2], pr[5] - pr[3])
		"circle":
			return Rect2(pr[2] - pr[4], pr[3] - pr[4], pr[4] * 2.0, pr[4] * 2.0)
		"capsule":
			return Rect2(Vector2(pr[2], pr[3]), Vector2.ZERO).expand(Vector2(pr[4], pr[5])).grow(pr[6])
		"spoly":
			var r := Rect2()
			var first := true
			for q in pr[2]:
				var g := Vector2((q[1] + q[0]) * 0.5, (q[1] - q[0]) * 0.5)
				if first:
					r = Rect2(g, Vector2.ZERO)
					first = false
				else:
					r = r.expand(g)
			return r
	return Rect2()

func _prim_sd(pr: Array, p: Vector2) -> float:
	match String(pr[1]):
		"rect", "crect":
			var c := Vector2(pr[2] + pr[4], pr[3] + pr[5]) * 0.5
			var hh := Vector2(pr[4] - pr[2], pr[5] - pr[3]) * 0.5
			var q := (p - c).abs() - hh
			var d := Vector2(maxf(q.x, 0.0), maxf(q.y, 0.0)).length() + minf(maxf(q.x, q.y), 0.0)
			if pr[1] == "crect" and pr[6] > 0.0:
				var dd := p - c
				d = maxf(d, (absf(dd.x) + absf(dd.y) - (hh.x + hh.y - pr[6])) / sqrt(2.0))
			return d
		"circle":
			return p.distance_to(Vector2(pr[2], pr[3])) - pr[4]
		"capsule":
			return p.distance_to(Geometry2D.get_closest_point_to_segment(p, Vector2(pr[2], pr[3]), Vector2(pr[4], pr[5]))) - pr[6]
		"spoly":
			var poly := PackedVector2Array()
			for q in pr[2]:
				poly.append(Vector2((q[1] + q[0]) * 0.5, (q[1] - q[0]) * 0.5))
			var best := INF
			for i in range(poly.size()):
				var q := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()])
				best = minf(best, p.distance_to(q))
			return -best if Geometry2D.is_point_in_polygon(p, poly) else best
	return INF

func _eval(p: Vector2) -> Vector2:
	var d := INF
	var h := INF
	for pr in data["ops"]:
		var s := _prim_sd(pr, p)
		match String(pr[0]):
			"add":
				d = minf(d, s)
				h = minf(h, s)
			"sub":
				d = maxf(d, -s)
			"cut":
				d = maxf(d, -s)
				h = maxf(h, -s)
	return Vector2(d, h)

func _sample_fields() -> void:
	var bb := Rect2()
	var first := true
	for pr in data["ops"]:
		if pr[0] != "add":
			continue
		var r := _prim_bounds(pr)
		bb = r if first else bb.merge(r)
		first = false
	bb = bb.grow(1.5)
	# offset off the quarter grid so straight template edges never sit exactly on a sample
	_u0 = floor(bb.position.x) + 0.0625
	_v0 = floor(bb.position.y) + 0.0625
	_nu = int(ceil((bb.end.x - _u0) / RES)) + 1
	_nv = int(ceil((bb.end.y - _v0) / RES)) + 1
	_f.resize(_nu * _nv)
	_h.resize(_nu * _nv)
	for j in range(_nv):
		for i in range(_nu):
			var e := _eval(Vector2(_u0 + i * RES, _v0 + j * RES))
			_f[j * _nu + i] = e.x
			_h[j * _nu + i] = e.y

func _samp(a: PackedFloat32Array, g: Vector2) -> float:
	var x := (g.x - _u0) / RES
	var y := (g.y - _v0) / RES
	var extra := 0.0
	var cx := clampf(x, 0.0, _nu - 1.001)
	var cy := clampf(y, 0.0, _nv - 1.001)
	if cx != x or cy != y:
		extra = Vector2(x - cx, y - cy).length() * RES
	var i := int(cx)
	var j := int(cy)
	var fx := cx - i
	var fy := cy - j
	var k := j * _nu + i
	var a0 := lerpf(a[k], a[k + 1], fx)
	var a1 := lerpf(a[k + _nu], a[k + _nu + 1], fx)
	return lerpf(a0, a1, fy) + extra

func _grad(a: PackedFloat32Array, g: Vector2) -> Vector2:
	var e := RES * 0.5
	var v := Vector2(_samp(a, g + Vector2(e, 0)) - _samp(a, g - Vector2(e, 0)), _samp(a, g + Vector2(0, e)) - _samp(a, g - Vector2(0, e)))
	if v.length_squared() < 1e-10:
		return g.normalized() if g.length_squared() > 1e-6 else Vector2(1, 0)
	return v.normalized()

## Signed ground distance (px) from a world point to the floor's edge: negative on the floor.
func floor_dist(p: Vector2) -> float:
	return _samp(_f, to_grid(p)) * UNIT

func on_floor(p: Vector2, margin := 0.0) -> bool:
	return _samp(_f, to_grid(p)) * UNIT <= -margin

## In the room's hull (floor or chasm): shots may fly here.
func in_hull(p: Vector2) -> bool:
	return _samp(_h, to_grid(p)) <= 0.0

## Keeps a walker of ground radius `radius` on the floor; radius <= 0 probes (shots) only stay in the hull.
## Returns pos unchanged when it is already fine.
func resolve(pos: Vector2, radius: float) -> Vector2:
	var shot := radius <= 0.0
	var a := _h if shot else _f
	var need := -0.08 if shot else -(radius + MARGIN) / UNIT
	var g := to_grid(pos)
	var d := _samp(a, g)
	if d <= need:
		return pos
	for _it in range(6):
		g -= _grad(a, g) * (d - need + 0.006)
		d = _samp(a, g)
		if d <= need + 0.01:
			return to_world(g)
	# stuck on a ridge (between two chasms): the nearest flow-field cell deep enough
	var best := g
	var bd := INF
	for j in range(_nav_h):
		for i in range(_nav_w):
			var c := _nav_center(i, j)
			if _samp(a, c) <= need:
				var q := c.distance_squared_to(g)
				if q < bd:
					bd = q
					best = c
	return to_world(best)

# --------------------------------------------------------------- contour: floor fill + outlines
func _cid_h(i: int, j: int) -> int:
	return (j * _nu + i) * 2

func _cid_v(i: int, j: int) -> int:
	return (j * _nu + i) * 2 + 1

func _cross_pt(cid: int) -> Vector2:
	var k := cid >> 1
	var i := k % _nu
	var j := k / _nu
	var f0 := _f[k]
	var f1 := _f[k + 1] if (cid & 1) == 0 else _f[k + _nu]
	var t := clampf(f0 / (f0 - f1), 0.0, 1.0)
	var g := Vector2(_u0 + i * RES, _v0 + j * RES)
	g += Vector2(t * RES, 0.0) if (cid & 1) == 0 else Vector2(0.0, t * RES)
	return g

func _contour() -> void:
	var nxt := {}         # exit crossing -> next entry crossing (floor kept on one side)
	var cells: Array = [] # [corner points / crossing ids] per partial cell (filled later with jittered points)
	fill_verts = PackedVector2Array()
	fill_polys = []
	for j in range(_nv - 1):
		for i in range(_nu - 1):
			var k := j * _nu + i
			var cv := [_f[k], _f[k + 1], _f[k + _nu + 1], _f[k + _nu]]
			var ins := [cv[0] < 0.0, cv[1] < 0.0, cv[2] < 0.0, cv[3] < 0.0]
			var n_in := int(ins[0]) + int(ins[1]) + int(ins[2]) + int(ins[3])
			if n_in == 0:
				continue
			var corners := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			var eids := [_cid_h(i, j), _cid_v(i + 1, j), _cid_h(i, j + 1), _cid_v(i, j)]
			if n_in == 4:
				cells.append([["c", corners[0]], ["c", corners[1]], ["c", corners[2]], ["c", corners[3]]])
				continue
			var saddle: bool = n_in == 2 and ins[0] == ins[2]
			if saddle and (cv[0] + cv[1] + cv[2] + cv[3]) * 0.25 >= 0.0:
				# two separate corners: a triangle each
				for c in range(4):
					if not ins[c]:
						continue
					var e_in: int = eids[(c + 3) % 4]
					var e_out: int = eids[c]
					cells.append([["x", e_in], ["c", corners[c]], ["x", e_out]])
					nxt[e_out] = e_in
				continue
			var poly: Array = []
			var last_exit := -1
			var first_exit := -1
			var pend: Array = [] # exits waiting for their entry
			for c in range(4):
				var c2 := (c + 1) % 4
				if ins[c]:
					poly.append(["c", corners[c]])
				if ins[c] != ins[c2]:
					poly.append(["x", eids[c]])
					if ins[c]:
						pend.append(eids[c])
					else:
						# entry: pairs with the most recent exit (wraps for the first one)
						if pend.is_empty():
							first_exit = eids[c] # entry before any exit: pair with the last exit later
						else:
							nxt[pend.pop_back()] = eids[c]
			if first_exit >= 0 and not pend.is_empty():
				nxt[pend.pop_back()] = first_exit
			cells.append(poly)
	# chain the outline loops (grid points, then jitter outward on everything but the walls later)
	var raw: Array = []
	var seen := {}
	for s in nxt:
		if seen.has(s):
			continue
		var ids: Array = []
		var c = s
		var guard := 0
		while not seen.has(c) and guard < 100000:
			seen[c] = true
			ids.append(c)
			c = nxt.get(c, -1)
			if c == -1:
				break
			guard += 1
		if ids.size() >= 3:
			raw.append(ids)
	_raw_loops = raw
	_cells = cells

var _raw_loops: Array = []
var _cells: Array = []

## Edge types, wall runs, jagged lip, fill.
func _classify(wall_h: float, rng: RandomNumberGenerator) -> void:
	# floor y range (world) for the "back half" rule
	var ymin := INF
	var ymax := -INF
	bounds = Rect2()
	var first := true
	for ids in _raw_loops:
		for c in ids:
			var w := to_world(_cross_pt(c))
			ymin = minf(ymin, w.y)
			ymax = maxf(ymax, w.y)
			if first:
				bounds = Rect2(w, Vector2.ZERO)
				first = false
			else:
				bounds = bounds.expand(w)
	var back_limit := ymin + (ymax - ymin) * 0.55
	var reach := wall_h + 460.0
	edges = []
	loops = []
	var jit := {}
	var rough: float = data.get("rough", 0.8)
	var ph := rng.randf_range(0.0, 10.0)
	var li := 0
	for ids in _raw_loops:
		var n: int = ids.size()
		var pts := PackedVector2Array()
		for c in ids:
			pts.append(to_world(_cross_pt(c)))
		var area := 0.0
		for i in range(n):
			var a := pts[i]
			var b := pts[(i + 1) % n]
			area += a.x * b.y - b.x * a.y
		var types: Array = []
		var nrms: Array = []
		for i in range(n):
			var a := pts[i]
			var b := pts[(i + 1) % n]
			var nrm := (b - a).orthogonal().normalized()
			if on_floor((a + b) * 0.5 + nrm * 4.0):
				nrm = -nrm
			nrms.append(nrm)
			var t := "side"
			if nrm.y > 0.05:
				t = "cliff"
			elif nrm.y < -0.2 and (a.y + b.y) * 0.5 < back_limit and _envelope(a, b, reach):
				t = "wall"
			types.append(t)
		# drop wall runs too short to read as a wall
		_prune_walls(types, pts, 1.6 * UNIT * 0.7)
		var jag := PackedVector2Array()
		for i in range(n):
			var p := pts[i]
			var t_prev: String = types[(i - 1 + n) % n]
			var t_next: String = types[i]
			var disp := Vector2.ZERO
			if t_prev != "wall" and t_next != "wall":
				var vn: Vector2 = (nrms[(i - 1 + n) % n] + nrms[i]).normalized()
				var s := sin(p.x * 0.011 + ph) * 0.5 + sin(p.y * 0.037 + p.x * 0.004 + ph * 1.7) * 0.35 + sin(p.x * 0.047 - p.y * 0.02) * 0.25
				disp = vn * maxf(0.0, (s * 0.5 + 0.55) * 26.0 * rough + rng_jitter(p) * 6.0 * rough)
			jag.append(p + disp)
			jit[ids[i]] = p + disp
		for i in range(n):
			edges.append({"a": jag[i], "b": jag[(i + 1) % n], "n": nrms[i], "type": types[i], "loop": li, "i": i})
		loops.append({"pts": jag, "ids": ids, "area": area})
		li += 1
	_cross = jit
	_build_wall_runs()
	_build_fill()

func rng_jitter(p: Vector2) -> float:
	return fposmod(sin(p.x * 12.9898 + p.y * 78.233) * 43758.5453, 1.0)

## Straight up from the edge (over the wall's height plus a cliff's depth) there is no floor:
## the edge is on the room's back envelope, so a wall standing on it hides nothing.
func _envelope(a: Vector2, b: Vector2, reach: float) -> bool:
	for t in [0.1, 0.5, 0.9]:
		var p: Vector2 = a.lerp(b, t)
		var y := 24.0
		while y < reach:
			if on_floor(p - Vector2(0, y), -6.0):
				return false
			y += 26.0
	return true

func _prune_walls(types: Array, pts: PackedVector2Array, min_len: float) -> void:
	var n := types.size()
	if not "wall" in types:
		return
	# start scanning just after a non-wall edge
	var s0 := -1
	for i in range(n):
		if types[i] != "wall":
			s0 = i
			break
	if s0 < 0:
		return
	var i := (s0 + 1) % n
	var cnt := 0
	while cnt < n:
		if types[i] == "wall":
			var run: Array = []
			var length := 0.0
			while types[i] == "wall" and cnt < n:
				run.append(i)
				length += pts[i].distance_to(pts[(i + 1) % n])
				i = (i + 1) % n
				cnt += 1
			if length < min_len:
				for k in run:
					types[k] = "side"
		else:
			i = (i + 1) % n
			cnt += 1

func _build_wall_runs() -> void:
	wall_runs = []
	wall_normals = []
	for li in range(loops.size()):
		var pts: PackedVector2Array = loops[li]["pts"]
		var n := pts.size()
		var es: Array = []
		for e in edges:
			if e["loop"] == li:
				es.append(e)
		if es.is_empty():
			continue
		var s0 := -1
		for i in range(n):
			if es[i]["type"] != "wall":
				s0 = i
				break
		if s0 < 0:
			s0 = 0
		var i := (s0 + 1) % n
		var cnt := 0
		while cnt < n:
			if es[i]["type"] == "wall":
				var run := PackedVector2Array([es[i]["a"]])
				var nr: Array = []
				while es[i]["type"] == "wall" and cnt < n:
					run.append(es[i]["b"])
					nr.append(es[i]["n"])
					i = (i + 1) % n
					cnt += 1
				# run left to right on screen (walls read the same way round)
				if run[0].x > run[run.size() - 1].x:
					run.reverse()
					nr.reverse()
				wall_runs.append(run)
				wall_normals.append(nr)
			else:
				i = (i + 1) % n
				cnt += 1

func _build_fill() -> void:
	fill_verts = PackedVector2Array()
	fill_polys = []
	var corner_idx := {}
	var cross_idx := {}
	for cell in _cells:
		var idx := PackedInt32Array()
		for v in cell:
			if v[0] == "c":
				var ci: Vector2i = v[1]
				if not corner_idx.has(ci):
					corner_idx[ci] = fill_verts.size()
					fill_verts.append(to_world(Vector2(_u0 + ci.x * RES, _v0 + ci.y * RES)))
				idx.append(corner_idx[ci])
			else:
				var cid: int = v[1]
				if not cross_idx.has(cid):
					cross_idx[cid] = fill_verts.size()
					fill_verts.append(_cross.get(cid, to_world(_cross_pt(cid))))
				idx.append(cross_idx[cid])
		if idx.size() >= 3:
			fill_polys.append(idx)
	_cells = []

# --------------------------------------------------------------- spots
## Floor points on a grid (spacing in grid units) at least `depth` ground px from the edge.
func spots(spacing: float, depth: float, max_depth := INF) -> Array:
	var out: Array = []
	var bb := Rect2(Vector2(_u0, _v0), Vector2((_nu - 1) * RES, (_nv - 1) * RES))
	var v := bb.position.y + spacing * 0.5
	while v < bb.end.y:
		var u := bb.position.x + spacing * 0.5
		while u < bb.end.x:
			var d := _samp(_f, Vector2(u, v)) * UNIT
			if d <= -depth and d >= -max_depth:
				out.append(to_world(Vector2(u, v)))
			u += spacing
		v += spacing
	return out

## The floor point deepest inside the room (sigil, rewards, boss entry fallbacks).
func deepest(near := Vector2.INF) -> Vector2:
	var best := Vector2.ZERO
	var bd := INF
	for j in range(1, _nv - 1, 2):
		for i in range(1, _nu - 1, 2):
			var d := _f[j * _nu + i]
			var w := to_world(Vector2(_u0 + i * RES, _v0 + j * RES))
			if near != Vector2.INF:
				d += w.distance_to(near) / UNIT * 0.35
			if d < bd:
				bd = d
				best = w
	return best

## True when a walker of ground radius r can walk the straight line a -> b (props included).
func line_clear(a: Vector2, b: Vector2, r: float) -> bool:
	var ga := to_grid(a)
	var gb := to_grid(b)
	var need := -(r + MARGIN * 0.5) / UNIT
	var n := int(ga.distance_to(gb) / 0.25) + 1
	for k in range(1, n + 1):
		if _samp(_w, ga.lerp(gb, float(k) / n)) > need:
			return false
	return true

## True when a solid prop / pit of ground radius r at pos would cut part of the floor off from the
## heroes' entry (a pit plugging the neck of an hourglass, a furnace in a bridge...).
func would_split(pos: Vector2, r: float) -> bool:
	var before := _unreached()
	var saved_w := _w.duplicate()
	var saved_ok := _nav_ok.duplicate()
	add_obstacle(pos, r)
	var after := _unreached()
	_w = saved_w
	_nav_ok = saved_ok
	_nav_cache = {}
	_nav_order = []
	return after > before + 2

## Open flow cells that cannot be reached from the entry.
func _unreached() -> int:
	var sk := _nav_cell(start)
	if sk < 0:
		return 0
	var seen := PackedByteArray()
	seen.resize(_nav_w * _nav_h)
	seen[sk] = 1
	var q := PackedInt32Array([sk])
	var head := 0
	while head < q.size():
		var k := q[head]
		head += 1
		var i := k % _nav_w
		var j := k / _nav_w
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var ii: int = i + d.x
			var jj: int = j + d.y
			if ii < 0 or jj < 0 or ii >= _nav_w or jj >= _nav_h:
				continue
			var kk := jj * _nav_w + ii
			if _nav_ok[kk] == 1 and seen[kk] == 0:
				seen[kk] = 1
				q.append(kk)
	var open := 0
	for v in _nav_ok:
		open += v
	return open - q.size()

## A solid prop or pit (ground radius r): carved out of the walk field so the steering goes round it.
## Rebuilds the flow field.
func add_obstacle(pos: Vector2, r: float) -> void:
	var g := to_grid(pos)
	var reach := (r + 160.0) / UNIT
	var i0 := maxi(0, int((g.x - reach - _u0) / RES))
	var i1 := mini(_nu - 1, int((g.x + reach - _u0) / RES) + 1)
	var j0 := maxi(0, int((g.y - reach - _v0) / RES))
	var j1 := mini(_nv - 1, int((g.y + reach - _v0) / RES) + 1)
	for j in range(j0, j1 + 1):
		for i in range(i0, i1 + 1):
			var w := to_world(Vector2(_u0 + i * RES, _v0 + j * RES)) - pos
			var d := (Vector2(w.x, w.y * 2.0).length() - r) / UNIT
			var k := j * _nu + i
			_w[k] = maxf(_w[k], -d)
	_build_nav()

# --------------------------------------------------------------- flow field (foes and the bot walk round chasms)
func _nav_center(i: int, j: int) -> Vector2:
	return Vector2(_u0 + (i + 0.5) * NAV, _v0 + (j + 0.5) * NAV)

func _build_nav() -> void:
	_nav_w = int(((_nu - 1) * RES) / NAV)
	_nav_h = int(((_nv - 1) * RES) / NAV)
	_nav_ok.resize(_nav_w * _nav_h)
	var need := -(MARGIN + 16.0) / UNIT
	for j in range(_nav_h):
		for i in range(_nav_w):
			_nav_ok[j * _nav_w + i] = 1 if _samp(_w, _nav_center(i, j)) <= need else 0
	_nav_cache = {}
	_nav_order = []

func _nav_cell(w: Vector2) -> int:
	var g := to_grid(w)
	var i := clampi(int(floor((g.x - _u0) / NAV)), 0, _nav_w - 1)
	var j := clampi(int(floor((g.y - _v0) / NAV)), 0, _nav_h - 1)
	var k := j * _nav_w + i
	if _nav_ok[k] == 1:
		return k
	# nearest walkable cell (closest centre within the first ring that has one)
	for r in range(1, 6):
		var best := -1
		var bd := INF
		for dj in range(-r, r + 1):
			for di in range(-r, r + 1):
				if absi(di) != r and absi(dj) != r:
					continue
				var ii := i + di
				var jj := j + dj
				if ii < 0 or jj < 0 or ii >= _nav_w or jj >= _nav_h:
					continue
				if _nav_ok[jj * _nav_w + ii] == 1:
					var dd := _nav_center(ii, jj).distance_squared_to(g)
					if dd < bd:
						bd = dd
						best = jj * _nav_w + ii
		if best >= 0:
			return best
	return -1

## Walking distance (grid units) from every flow cell to the target cell: 8-way chamfer sweeps until
## stable (handles any concave floor); blocked / unreachable cells stay at BIG.
const BIG := 1.0e9

func _nav_field(target: int) -> PackedFloat32Array:
	if _nav_cache.has(target):
		return _nav_cache[target]
	var w := _nav_w
	var dist := PackedFloat32Array()
	dist.resize(w * _nav_h)
	dist.fill(BIG)
	dist[target] = 0.0
	var dg := NAV * 1.4142
	var fwd := [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(1, -1)]
	var bwd := [Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(-1, 1)]
	for _pass in range(12):
		var changed := false
		for dir in range(2):
			var offs: Array = fwd if dir == 0 else bwd
			for jj in range(_nav_h):
				var j := jj if dir == 0 else _nav_h - 1 - jj
				for ii in range(w):
					var i := ii if dir == 0 else w - 1 - ii
					var k := j * w + i
					if _nav_ok[k] == 0:
						continue
					var best := dist[k]
					for o in offs:
						var ni: int = i + o.x
						var nj: int = j + o.y
						if ni < 0 or nj < 0 or ni >= w or nj >= _nav_h:
							continue
						var nk := nj * w + ni
						if _nav_ok[nk] == 0:
							continue
						var diag: bool = o.x != 0 and o.y != 0
						if diag and (_nav_ok[j * w + ni] == 0 or _nav_ok[nj * w + i] == 0):
							continue
						var c: float = dist[nk] + (dg if diag else NAV)
						if c < best:
							best = c
					if best < dist[k]:
						dist[k] = best
						changed = true
		if not changed:
			break
	_nav_cache[target] = dist
	_nav_order.append(target)
	if _nav_order.size() > 8:
		_nav_cache.erase(_nav_order.pop_front())
	return dist

## Interpolated walking distance at grid point g (blocked corners read as a little farther than their
## neighbours, so the gradient leads away from them).
func _nav_at(dist: PackedFloat32Array, g: Vector2) -> float:
	var x := (g.x - _u0) / NAV - 0.5
	var y := (g.y - _v0) / NAV - 0.5
	var i := clampi(int(floor(x)), 0, _nav_w - 2)
	var j := clampi(int(floor(y)), 0, _nav_h - 2)
	var fx := clampf(x - i, 0.0, 1.0)
	var fy := clampf(y - j, 0.0, 1.0)
	var v := [dist[j * _nav_w + i], dist[j * _nav_w + i + 1], dist[(j + 1) * _nav_w + i], dist[(j + 1) * _nav_w + i + 1]]
	var mx := -1.0
	for q in v:
		if q < BIG:
			mx = maxf(mx, q)
	if mx < 0.0:
		return BIG
	for n in range(4):
		if v[n] >= BIG:
			v[n] = mx + NAV * 2.0
	return lerpf(lerpf(v[0], v[1], fx), lerpf(v[2], v[3], fx), fy)

## Direction a walker at `from` should take to reach `to` round chasms, void and props: down the
## walking-distance field (ZERO when there is no path).
func flow_dir(from: Vector2, to: Vector2, _r: float) -> Vector2:
	var tk := _nav_cell(to)
	if tk < 0:
		return Vector2.ZERO
	var dist := _nav_field(tk)
	var g := to_grid(from)
	if _nav_at(dist, g) >= BIG:
		# off the field (inside a prop's ring): head for the nearest walkable cell
		var fk := _nav_cell(from)
		if fk < 0:
			return Vector2.ZERO
		return (to_world(_nav_center(fk % _nav_w, fk / _nav_w)) - from).normalized()
	var e := NAV * 0.35
	var gr := Vector2(_nav_at(dist, g + Vector2(e, 0)) - _nav_at(dist, g - Vector2(e, 0)),
		_nav_at(dist, g + Vector2(0, e)) - _nav_at(dist, g - Vector2(0, e)))
	if gr.length_squared() > 1e-8:
		var dg := -gr.normalized()
		# the slope is only trusted when a short step down it stays on open cells (it can point
		# into a chasm at a saddle between two equal routes, or into a prop dead ahead)
		var probe := g + dg * NAV * 0.9
		var pi := int(floor((probe.x - _u0) / NAV))
		var pj := int(floor((probe.y - _v0) / NAV))
		if pi >= 0 and pj >= 0 and pi < _nav_w and pj < _nav_h and dist[pj * _nav_w + pi] < BIG \
				and dist[pj * _nav_w + pi] < _nav_at(dist, g):
			return (to_world(dg)).normalized()
	# discrete fallback: the lowest neighbouring open cell (first one wins ties)
	var ci := clampi(int(floor((g.x - _u0) / NAV)), 0, _nav_w - 1)
	var cj := clampi(int(floor((g.y - _v0) / NAV)), 0, _nav_h - 1)
	var here := _nav_at(dist, g)
	var bk := -1
	var bv := here
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
		var ii: int = ci + d.x
		var jj: int = cj + d.y
		if ii < 0 or jj < 0 or ii >= _nav_w or jj >= _nav_h:
			continue
		var v := dist[jj * _nav_w + ii]
		if v < bv - 0.01:
			bv = v
			bk = jj * _nav_w + ii
	if bk < 0:
		return Vector2.ZERO
	return (to_world(_nav_center(bk % _nav_w, bk / _nav_w)) - from).normalized()
