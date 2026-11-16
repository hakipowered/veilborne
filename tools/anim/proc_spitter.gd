extends RefCounted
## Procedural rig + poses for the Spitter (lava gargoyle quadruped). Offline renderer only.
## Model space: ground y=0, height 1.1 m, facing +Z.


func bones(_aabb: AABB) -> Array:
	var b := [
		{"name": "root", "head": [0, 0.45, -0.15], "tail": [0, 0.5, 0.15], "reach": 1.6},
		{"name": "chest", "parent": "root", "head": [0, 0.5, 0.12], "tail": [0, 0.55, 0.32], "reach": 1.2},
		{"name": "head", "parent": "chest", "head": [0, 0.62, 0.28], "tail": [0, 0.55, 0.62], "reach": 1.1},
	]
	for s in [-1.0, 1.0]:
		var n := "l" if s < 0 else "r"
		b.append({"name": "wing_" + n, "parent": "root", "head": [0.18 * s, 0.78, -0.12], "tail": [0.45 * s, 1.08, -0.25],
			"only_if": {"axis": 1, "op": ">", "value": 0.7}, "reach": 0.9})
		b.append({"name": "leg_f" + n, "parent": "chest", "head": [0.3 * s, 0.4, 0.25], "tail": [0.36 * s, 0.02, 0.38],
			"only_if": {"axis": 1, "op": "<", "value": 0.45}, "reach": 0.8})
		b.append({"name": "leg_b" + n, "parent": "root", "head": [0.3 * s, 0.4, -0.32], "tail": [0.34 * s, 0.02, -0.28],
			"only_if": {"axis": 1, "op": "<", "value": 0.45}, "reach": 0.8})
	return b


static func _rot(skel: Skeleton3D, b: String, x_deg: float, y_deg := 0.0, z_deg := 0.0) -> void:
	var i := skel.find_bone(b)
	if i >= 0:
		skel.set_bone_pose_rotation(i, Quaternion.from_euler(Vector3(deg_to_rad(x_deg), deg_to_rad(y_deg), deg_to_rad(z_deg))))


static func _move(skel: Skeleton3D, b: String, off: Vector3) -> void:
	var i := skel.find_bone(b)
	skel.set_bone_pose_position(i, skel.get_bone_rest(i).origin + off)


static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0, 1), 3.0)


static func ease_in(t: float) -> float:
	return pow(clampf(t, 0, 1), 2.2)


func _wings(skel: Skeleton3D, ang: float, fold := 0.0) -> void:
	_rot(skel, "wing_l", fold, 0, ang)
	_rot(skel, "wing_r", fold, 0, -ang)


func pose(skel: Skeleton3D, model: Node3D, anim: String, u: float) -> void:
	var w := TAU * u
	match anim:
		"idle":
			_move(skel, "root", Vector3(0, 0.015 * sin(w), 0))
			_rot(skel, "chest", -3 * sin(w))
			_rot(skel, "head", 4 * sin(w + 0.8), 8 * sin(w * 0.5))
			_wings(skel, 8 * sin(w + 0.5))
			_rot(skel, "leg_fl", 3 * sin(w))
			_rot(skel, "leg_fr", -3 * sin(w))
		"move":
			var s := sin(w)
			_move(skel, "root", Vector3(0, 0.03 * absf(sin(2.0 * w)), 0))
			_rot(skel, "root", 6, 4 * s)
			_rot(skel, "chest", -4 * cos(2 * w))
			_rot(skel, "head", -6 + 5 * cos(2 * w))
			_rot(skel, "leg_fl", 32 * s)
			_rot(skel, "leg_br", 32 * s)
			_rot(skel, "leg_fr", -32 * s)
			_rot(skel, "leg_bl", -32 * s)
			_wings(skel, 18 * sin(2 * w))
		"windup":
			var t := ease_out(u)
			var sh := 1.5 * sin(u * 70.0) * t
			_move(skel, "root", Vector3(0, 0.06 * t, -0.12 * t))
			_rot(skel, "root", -10 * t)
			_rot(skel, "chest", -18 * t + sh)
			_rot(skel, "head", -28 * t, 0, sh)
			_wings(skel, 40 * t, -10 * t)
			_rot(skel, "leg_fl", -18 * t)
			_rot(skel, "leg_fr", -18 * t)
		"attack":
			var a := ease_out(clampf(u / 0.3, 0, 1))
			var r := ease_in(clampf((u - 0.45) / 0.55, 0, 1))
			var k := a * (1.0 - r)
			var wind := 1.0 - a
			_move(skel, "root", Vector3(0, 0.06 * wind, 0.14 * k - 0.12 * wind))
			_rot(skel, "root", 12 * k - 10 * wind)
			_rot(skel, "chest", 10 * k - 18 * wind)
			_rot(skel, "head", 30 * k - 28 * wind)
			_wings(skel, -20 * k + 40 * wind, 15 * k)
			_rot(skel, "leg_bl", 15 * k)
			_rot(skel, "leg_br", 15 * k)
		"hurt":
			var k := sin(PI * clampf(u * 1.3, 0, 1))
			_move(skel, "root", Vector3(0.02 * sin(u * 45.0) * (1 - u), 0.02 * k, -0.15 * k))
			_rot(skel, "root", -14 * k, 0, 6 * k)
			_rot(skel, "head", -30 * k, 12 * k)
			_wings(skel, 30 * k)
		"death":
			var k := ease_out(clampf(u / 0.35, 0, 1))
			var c := ease_in(clampf((u - 0.25) / 0.75, 0, 1))
			_move(skel, "root", Vector3(0.1 * c, 0.08 * k - 0.2 * c, -0.1 * k))
			_rot(skel, "root", -15 * k, 0, 85 * c)
			_rot(skel, "head", -35 * k + 50 * c)
			_wings(skel, 40 * k - 30 * c)
			_rot(skel, "leg_fl", -40 * c)
			_rot(skel, "leg_fr", 30 * c)
			_rot(skel, "leg_bl", 30 * c)
			_rot(skel, "leg_br", -40 * c)
