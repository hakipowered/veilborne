extends RefCounted
## Procedural weapon props for the offline renderer (attached to hand bones).
## Local axis convention: weapon grip at origin, weapon extends along +Y.


static func _mi(mesh: Mesh, col: Color, pos: Vector3, rot := Vector3.ZERO, emit := 0.0, emit_col := Color.WHITE) -> MeshInstance3D:
	var m := MeshInstance3D.new()
	m.mesh = mesh
	var sm := StandardMaterial3D.new()
	sm.albedo_color = col
	m.material_override = null
	mesh.surface_set_material(0, sm)
	m.position = pos
	m.rotation_degrees = rot
	m.set_meta("emit", emit)   # props skip the hull outline (thin geometry); silhouette ink comes from post.py
	m.set_meta("emit_col", emit_col)
	return m


static func _cyl(r: float, h: float, sides := 10) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = r
	c.bottom_radius = r
	c.height = h
	c.radial_segments = sides
	c.rings = 1
	return c


static func _blade(w: float, h: float, t: float) -> ArrayMesh:
	# diamond/leaf blade along +Y, flat in X, thickness t in Z
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var pts := [Vector3(0, 0, 0), Vector3(w * 0.5, h * 0.3, 0), Vector3(0, h, 0), Vector3(-w * 0.5, h * 0.3, 0)]
	var f := Vector3(0, h * 0.3, t * 0.5)
	var b := Vector3(0, h * 0.3, -t * 0.5)
	for i in 4:
		var a: Vector3 = pts[i]
		var c: Vector3 = pts[(i + 1) % 4]
		st.add_vertex(a); st.add_vertex(c); st.add_vertex(f)
		st.add_vertex(c); st.add_vertex(a); st.add_vertex(b)
	st.generate_normals()
	return st.commit()


static func _crescent(r: float, w: float, t: float, arc_deg: float) -> ArrayMesh:
	# curved blade: arc of radius r from the grip, extends along +Y curving to +X
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := 12
	var rings := []
	for i in n + 1:
		var u := float(i) / n
		var ang := deg_to_rad(arc_deg) * u
		var center := Vector3(r - r * cos(ang), r * sin(ang), 0)
		var width := w * sin(PI * clampf(u * 1.05, 0.0, 1.0)) + 0.004
		var outward := Vector3(cos(ang), -sin(ang), 0) * -1.0
		rings.append([center, center + outward * width, width])
	for i in n:
		var a0: Vector3 = rings[i][0]; var a1: Vector3 = rings[i][1]
		var b0: Vector3 = rings[i + 1][0]; var b1: Vector3 = rings[i + 1][1]
		var mid_a := (a0 + a1) * 0.5; var mid_b := (b0 + b1) * 0.5
		for s in [1.0, -1.0]:
			var za := Vector3(0, 0, t * 0.5 * s)
			if s > 0:
				st.add_vertex(a0); st.add_vertex(b0); st.add_vertex(mid_a + za)
				st.add_vertex(b0); st.add_vertex(mid_b + za); st.add_vertex(mid_a + za)
				st.add_vertex(mid_a + za); st.add_vertex(mid_b + za); st.add_vertex(a1)
				st.add_vertex(mid_b + za); st.add_vertex(b1); st.add_vertex(a1)
			else:
				st.add_vertex(b0); st.add_vertex(a0); st.add_vertex(mid_a + za)
				st.add_vertex(mid_b + za); st.add_vertex(b0); st.add_vertex(mid_a + za)
				st.add_vertex(mid_b + za); st.add_vertex(mid_a + za); st.add_vertex(a1)
				st.add_vertex(b1); st.add_vertex(mid_b + za); st.add_vertex(a1)
	st.generate_normals()
	return st.commit()


static func build(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	match String(p.get("type", "")):
		"spear":
			var L: float = float(p.get("length", 1.75))
			var grip: float = float(p.get("grip", 0.4))   # fraction of shaft behind the hand
			var y0 := -L * grip
			root.add_child(_mi(_cyl(0.017, L), Color(0.32, 0.12, 0.08), Vector3(0, y0 + L * 0.5, 0)))
			# gold rings
			for f in [0.0, 0.62, 0.98]:
				root.add_child(_mi(_cyl(0.026, 0.05), Color(0.95, 0.72, 0.25), Vector3(0, y0 + L * f, 0)))
			# flame blade
			root.add_child(_mi(_blade(0.17, 0.42, 0.05), Color(1.0, 0.55, 0.12), Vector3(0, y0 + L, 0), Vector3.ZERO, 0.55, Color(1.0, 0.62, 0.18)))
			root.add_child(_mi(_blade(0.07, 0.30, 0.036), Color(1.0, 0.92, 0.55), Vector3(0, y0 + L + 0.03, 0), Vector3.ZERO, 0.8, Color(1.0, 0.95, 0.6)))
			# cross guard
			var g := BoxMesh.new(); g.size = Vector3(0.22, 0.04, 0.04)
			root.add_child(_mi(g, Color(0.95, 0.72, 0.25), Vector3(0, y0 + L - 0.01, 0)))
		"crescent":
			var hilt := _cyl(0.018, 0.13)
			root.add_child(_mi(hilt, Color(0.18, 0.18, 0.3), Vector3(0, 0, 0)))
			var gd := BoxMesh.new(); gd.size = Vector3(0.1, 0.025, 0.04)
			root.add_child(_mi(gd, Color(0.75, 0.78, 0.95), Vector3(0, 0.07, 0)))
			var bl := _crescent(float(p.get("radius", 0.55)), 0.075, 0.02, float(p.get("arc", 62.0)))
			var flip: float = float(p.get("curve", 1.0))
			var m := _mi(bl, Color(0.86, 0.9, 1.0), Vector3(0, 0.07, 0), Vector3(0, 0 if flip > 0 else 180, 0), 0.35, Color(0.7, 0.95, 1.0))
			root.add_child(m)
		"scythe":
			# long snath held a third of the way up, curved blade hanging off the top toward +X
			var L: float = float(p.get("length", 1.95))
			var y0: float = -L * float(p.get("grip", 0.35))
			root.add_child(_mi(_cyl(0.034, L), Color(0.26, 0.32, 0.2), Vector3(0, y0 + L * 0.5, 0)))
			for f in [0.3, 0.97]:
				root.add_child(_mi(_cyl(0.032, 0.06), Color(0.55, 0.75, 0.5), Vector3(0, y0 + L * f, 0)))
			var sb := _crescent(float(p.get("radius", 0.75)), 0.13, 0.025, 70.0)
			root.add_child(_mi(sb, Color(0.72, 0.95, 0.85), Vector3(0, y0 + L, 0), Vector3(0, 0, -90), 0.45, Color(0.45, 1.0, 0.75)))
		"hammer":
			# forge hammer held near the end of the haft, glowing head along +Y
			var H: float = float(p.get("length", 1.35))
			var y1: float = -H * float(p.get("grip", 0.12))
			var sz: float = float(p.get("head", 0.5))
			root.add_child(_mi(_cyl(0.03, H), Color(0.22, 0.16, 0.12), Vector3(0, y1 + H * 0.5, 0)))
			var hd := BoxMesh.new(); hd.size = Vector3(sz, sz * 0.6, sz * 0.6)
			root.add_child(_mi(hd, Color(0.16, 0.15, 0.16), Vector3(0, y1 + H, 0)))
			var fc := BoxMesh.new(); fc.size = Vector3(sz * 0.08, sz * 0.5, sz * 0.5)
			for sx in [-1.0, 1.0]:
				root.add_child(_mi(fc, Color(1.0, 0.45, 0.12), Vector3(sx * sz * 0.5, y1 + H, 0), Vector3.ZERO, 0.8, Color(1.0, 0.55, 0.15)))
			var bd := BoxMesh.new(); bd.size = Vector3(sz * 1.04, sz * 0.12, sz * 0.64)
			root.add_child(_mi(bd, Color(0.55, 0.3, 0.12), Vector3(0, y1 + H, 0)))
	return root
