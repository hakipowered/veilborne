extends RefCounted
## Auto-rig for non-humanoid static meshes (shade, spitter): builds a Skeleton3D from a bone spec
## and skins the mesh with distance-based weights, so the offline renderer can pose bones procedurally.
## Bone spec: [{name, parent ("" = root), head: [x,y,z], tail: [x,y,z], reach?: float, only_if?: {axis, op, value}}]
## Coordinates are in the normalised model space (feet/ground at y=0, height = cfg height, facing +Z).


static func normalize(model: Node3D, height: float) -> Array:
	## Bakes every MeshInstance3D into model space scaled to `height`, returns [meshes(Array of ArrayMesh), aabb]
	var mis: Array = []
	_collect(model, mis)
	var aabb := AABB()
	var first := true
	for mi in mis:
		var m: MeshInstance3D = mi
		var xf: Transform3D = model.global_transform.affine_inverse() * m.global_transform if m.is_inside_tree() else _rel(model, m)
		var b: AABB = xf * m.mesh.get_aabb()
		aabb = b if first else aabb.merge(b)
		first = false
	var s := height / maxf(aabb.size.y, 0.001)
	var c := aabb.get_center()
	var off := Vector3(-c.x, -aabb.position.y, -c.z)
	var outs: Array = []
	for mi in mis:
		var m: MeshInstance3D = mi
		var xf: Transform3D = _rel(model, m)
		var nm := ArrayMesh.new()
		for si in m.mesh.get_surface_count():
			var arr: Array = m.mesh.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var n: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
			var basis := xf.basis
			for i in v.size():
				v[i] = ((xf * v[i]) + off) * s
				if n.size() > i:
					n[i] = (basis * n[i]).normalized()
			arr[Mesh.ARRAY_VERTEX] = v
			if n.size() > 0:
				arr[Mesh.ARRAY_NORMAL] = n
			arr[Mesh.ARRAY_TANGENT] = null
			nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			nm.surface_set_material(si, m.get_active_material(si))
		outs.append(nm)
	return [outs, AABB((aabb.position + off) * s, aabb.size * s)]


static func _collect(n: Node, out: Array) -> void:
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		_collect(c, out)


static func _rel(root: Node3D, n: Node3D) -> Transform3D:
	var xf := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			xf = (cur as Node3D).transform * xf
		cur = cur.get_parent()
	return xf


static func _seg_dist(p: Vector3, a: Vector3, b: Vector3) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func build(meshes: Array, bones: Array, sharp := 4.0) -> Node3D:
	## Returns a Node3D containing Skeleton3D "Skel" with skinned MeshInstance3D children.
	var root := Node3D.new()
	var skel := Skeleton3D.new()
	skel.name = "Skel"
	root.add_child(skel)
	var idx := {}
	var heads: Array[Vector3] = []
	var tails: Array[Vector3] = []
	for b in bones:
		var bi := skel.get_bone_count()
		skel.add_bone(b["name"])
		idx[b["name"]] = bi
		heads.append(Vector3(b["head"][0], b["head"][1], b["head"][2]))
		tails.append(Vector3(b["tail"][0], b["tail"][1], b["tail"][2]))
	for b in bones:
		var bi: int = idx[b["name"]]
		var p: String = b.get("parent", "")
		var ph := Vector3.ZERO
		if p != "":
			skel.set_bone_parent(bi, idx[p])
			ph = heads[idx[p]]
		var rest := Transform3D(Basis(), heads[bi] - ph)
		skel.set_bone_rest(bi, rest)
		skel.set_bone_pose_position(bi, rest.origin)
	var skin := Skin.new()
	for bi in bones.size():
		skin.add_named_bind(bones[bi]["name"], Transform3D(Basis(), -heads[bi]))
	for m in meshes:
		var am: ArrayMesh = m
		var nm := ArrayMesh.new()
		for si in am.get_surface_count():
			var arr: Array = am.surface_get_arrays(si)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			var bw := PackedInt32Array()
			var ww := PackedFloat32Array()
			bw.resize(v.size() * 4)
			ww.resize(v.size() * 4)
			for i in v.size():
				var p := v[i]
				var best := [[-1, 0.0], [-1, 0.0], [-1, 0.0], [-1, 0.0]]
				for bi in bones.size():
					var b: Dictionary = bones[bi]
					if b.has("only_if"):
						var cond: Dictionary = b["only_if"]
						var val: float = p[int(cond["axis"])]
						var ok: bool = val > float(cond["value"]) if cond["op"] == ">" else val < float(cond["value"])
						if not ok:
							continue
					var d := _seg_dist(p, heads[bi], tails[bi]) / float(b.get("reach", 1.0))
					var w := 1.0 / pow(d + 0.02, sharp)
					# insert into top 4
					for k in 4:
						if best[k][0] == -1 or w > best[k][1]:
							best.insert(k, [bi, w])
							best.pop_back()
							break
				var tot := 0.0
				for k in 4:
					if best[k][0] >= 0:
						tot += best[k][1]
				for k in 4:
					bw[i * 4 + k] = maxi(best[k][0], 0)
					ww[i * 4 + k] = best[k][1] / tot if best[k][0] >= 0 and tot > 0.0 else 0.0
			arr[Mesh.ARRAY_BONES] = bw
			arr[Mesh.ARRAY_WEIGHTS] = ww
			nm.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
			nm.surface_set_material(si, am.surface_get_material(si))
		var mi := MeshInstance3D.new()
		mi.mesh = nm
		skel.add_child(mi)
		mi.skin = skin
		mi.skeleton = NodePath("..")
	return root
