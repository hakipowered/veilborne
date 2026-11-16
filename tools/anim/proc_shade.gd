extends RefCounted
## Procedural rig + poses for the Shade (floating wraith). Used by tools/anim/render.gd (offline only).
## Model space: ground y=0, height 1.8 m, facing +Z. u = normalised time 0..1 within the anim.


func bones(_aabb: AABB) -> Array:
	return [
		{"name": "root", "head": [0, 0.82, 0], "tail": [0, 1.0, 0], "reach": 1.4},
		{"name": "spine", "parent": "root", "head": [0, 1.0, 0], "tail": [0, 1.3, 0]},
		{"name": "head", "parent": "spine", "head": [0, 1.36, 0.02], "tail": [0, 1.75, 0.02], "reach": 1.2},
		{"name": "arm_l", "parent": "spine", "head": [-0.26, 1.3, 0.05], "tail": [-0.46, 1.05, 0.12]},
		{"name": "fore_l", "parent": "arm_l", "head": [-0.46, 1.05, 0.12], "tail": [-0.72, 0.75, 0.2]},
		{"name": "arm_r", "parent": "spine", "head": [0.26, 1.3, 0.05], "tail": [0.46, 1.05, 0.12]},
		{"name": "fore_r", "parent": "arm_r", "head": [0.46, 1.05, 0.12], "tail": [0.72, 0.72, 0.2]},
		{"name": "tail1", "parent": "root", "head": [0, 0.82, 0], "tail": [0.08, 0.45, 0], "reach": 1.3},
		{"name": "tail2", "parent": "tail1", "head": [0.08, 0.45, 0], "tail": [0.35, 0.2, 0], "reach": 1.2},
		{"name": "tail3", "parent": "tail2", "head": [0.35, 0.2, 0], "tail": [0.75, 0.15, 0]},
	]


static func _rot(skel: Skeleton3D, b: String, x_deg: float, y_deg := 0.0, z_deg := 0.0) -> void:
	var i := skel.find_bone(b)
	if i < 0:
		return
	skel.set_bone_pose_rotation(i, Quaternion.from_euler(Vector3(deg_to_rad(x_deg), deg_to_rad(y_deg), deg_to_rad(z_deg))))


static func _move(skel: Skeleton3D, b: String, off: Vector3) -> void:
	var i := skel.find_bone(b)
	skel.set_bone_pose_position(i, skel.get_bone_rest(i).origin + off)


static func ease_out(t: float) -> float:
	return 1.0 - pow(1.0 - clampf(t, 0, 1), 3.0)


static func ease_in(t: float) -> float:
	return pow(clampf(t, 0, 1), 2.2)


func pose(skel: Skeleton3D, model: Node3D, anim: String, u: float) -> void:
	var w := TAU * u
	match anim:
		"rest":
			pass
		"idle":
			_move(skel, "root", Vector3(0, 0.06 * sin(w), 0))
			_rot(skel, "spine", 4 * sin(w + 0.6))
			_rot(skel, "head", -12 - 4 * sin(w + 1.2), 6 * sin(w * 0.5))
			_rot(skel, "arm_l", 6 * sin(w + 0.3), 0, -6 * sin(w))
			_rot(skel, "arm_r", 6 * sin(w + 0.9), 0, 6 * sin(w + 0.5))
			_rot(skel, "fore_l", 0, 0, -10 * sin(w + 1.0))
			_rot(skel, "fore_r", 0, 0, 10 * sin(w + 1.6))
			_rot(skel, "tail1", 4 * sin(w), 0, 6 * sin(w + 0.4))
			_rot(skel, "tail2", 0, 10 * sin(w + 1.0), 12 * sin(w + 1.0))
			_rot(skel, "tail3", 0, 15 * sin(w + 2.0), 18 * sin(w + 2.0))
		"move":
			_move(skel, "root", Vector3(0, 0.08 + 0.05 * sin(2 * w), 0))
			_rot(skel, "root", 16)
			_rot(skel, "spine", 4 + 3 * sin(2 * w))
			_rot(skel, "head", -24)
			_rot(skel, "arm_l", -25 + 10 * sin(w), 0, 20)
			_rot(skel, "arm_r", -25 - 10 * sin(w), 0, -20)
			_rot(skel, "fore_l", -20, 0, 10)
			_rot(skel, "fore_r", -20, 0, -10)
			_rot(skel, "tail1", -25 + 6 * sin(w * 2), 0, 8 * sin(w))
			_rot(skel, "tail2", -20, 18 * sin(w + 1.0), 15 * sin(w + 1.0))
			_rot(skel, "tail3", -10, 25 * sin(w + 2.0), 20 * sin(w + 2.0))
		"windup":
			var t := ease_out(u)
			var shake := 2.0 * sin(u * 60.0) * t
			_move(skel, "root", Vector3(0, 0.12 * t, -0.15 * t))
			_rot(skel, "root", -18 * t)
			_rot(skel, "spine", -14 * t + shake)
			_rot(skel, "head", 10 * t, 0, shake)
			_rot(skel, "arm_l", -70 * t, 0, -40 * t)
			_rot(skel, "arm_r", -70 * t, 0, 40 * t)
			_rot(skel, "fore_l", -40 * t, 0, -30 * t)
			_rot(skel, "fore_r", -40 * t, 0, 30 * t)
			_rot(skel, "tail1", 20 * t)
			_rot(skel, "tail2", 25 * t, 0, 10 * t)
		"attack":
			# lunge: snap forward on the first frames, hold, settle back
			var a := ease_out(clampf(u / 0.35, 0, 1))
			var r := ease_in(clampf((u - 0.55) / 0.45, 0, 1))
			var k := a * (1.0 - r)
			_move(skel, "root", Vector3(0, 0.1 - 0.06 * k, 0.55 * k))
			_rot(skel, "root", 18 * k)
			_rot(skel, "spine", 8 * k)
			_rot(skel, "head", -12 - 22 * k)
			_rot(skel, "arm_l", 75 * k - 70 * (1 - a), 0, 25 * k)
			_rot(skel, "arm_r", 75 * k - 70 * (1 - a), 0, -25 * k)
			_rot(skel, "fore_l", 20 * k, 0, 30 * k)
			_rot(skel, "fore_r", 20 * k, 0, -30 * k)
			_rot(skel, "tail1", -45 * k)
			_rot(skel, "tail2", -35 * k, 0, 15 * k)
			_rot(skel, "tail3", -25 * k, 0, 25 * k)
		"hurt":
			var k := sin(PI * clampf(u * 1.4, 0, 1))
			_move(skel, "root", Vector3(0.03 * sin(u * 40.0) * (1 - u), 0.04 * k, -0.25 * k))
			_rot(skel, "root", -22 * k)
			_rot(skel, "spine", -15 * k)
			_rot(skel, "head", 25 * k, 0, 10 * k)
			_rot(skel, "arm_l", -30 * k, 0, -35 * k)
			_rot(skel, "arm_r", -30 * k, 0, 35 * k)
			_rot(skel, "tail1", 25 * k)
			_rot(skel, "tail2", 20 * k)
		"death":
			var k := ease_out(clampf(u / 0.5, 0, 1))
			var c := ease_in(clampf((u - 0.3) / 0.7, 0, 1))
			_move(skel, "root", Vector3(0, 0.15 * k - 0.6 * c, -0.2 * k))
			_rot(skel, "root", -25 * k + 40 * c, 50 * c)
			_rot(skel, "spine", -20 * k + 30 * c)
			_rot(skel, "head", 35 * k - 10 * c, 0, 25 * c)
			_rot(skel, "arm_l", -80 * k + 60 * c, 0, -50 * k)
			_rot(skel, "arm_r", -80 * k + 60 * c, 0, 50 * k)
			_rot(skel, "fore_l", -40 * k)
			_rot(skel, "fore_r", -40 * k)
			_rot(skel, "tail1", 30 * k + 30 * c)
			_rot(skel, "tail2", 30 * c)
			var sc := 1.0 - 0.75 * c
			model.scale = Vector3(1.0 + 0.3 * c, sc, 1.0 + 0.3 * c)
