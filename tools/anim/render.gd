extends Node
## Offline sprite renderer (ANIMATION agent). Renders rigged GLB characters to frames.
## Usage (xvfb):
##   xvfb-run -a -s "-screen 0 1280x1024x24" $G --rendering-driver opengl3 --path . res://tools/anim/render.tscn -- --char=kaela [--anims=idle,run] [--dirs=0,2] [--still]
## Config: res://tools/anim/chars.json. Sources: tools/anim/src/<id>/*.glb (gdignored, loaded with GLTFDocument).
## Output: tools/anim/out/<id>/<anim>/d<dir>_<frame>.png (raw, supersampled); tools/anim/pack.py makes the sheets.

const DIR_YAW := [0.0, 45.0, 90.0, 135.0, 180.0]   # S, SE, E, NE, N (W side is mirrored at runtime)

var cfg: Dictionary
var char_id := "kaela"
var vp: SubViewport
var cam: Camera3D
var model: Node3D
var player: AnimationPlayer
var skel: Skeleton3D
var toon_shader: Shader
var outline_shader: Shader
var ss := 2
var hands_only := false   ## --hands: only export hand data (no images)


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	char_id = args.get("char", "kaela")
	hands_only = args.has("hands")
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://tools/anim/chars.json"))
	cfg = all[char_id]
	ss = int(cfg.get("ss", 2))
	toon_shader = load("res://tools/anim/toon.gdshader")
	outline_shader = load("res://tools/anim/outline.gdshader")
	_build_stage()
	_load_model()
	var anims: Array = cfg["anims"].keys()
	if args.has("anims"):
		anims = Array(args["anims"].split(","))
	var dirs: Array = [0, 1, 2, 3, 4]
	if args.has("dirs"):
		dirs = []
		for d in args["dirs"].split(","):
			dirs.append(int(d))
	if args.has("probe"):
		await _probe(args["probe"])
		get_tree().quit()
		return
	if args.has("stride"):
		_stride(args["stride"], args.get("rfile", ""))
		get_tree().quit()
		return
	if args.has("list"):
		print("CLIPS: ", player.get_animation_list())
		get_tree().quit()
		return
	await _render(anims, dirs, args.has("still"))
	get_tree().quit()


func _build_stage() -> void:
	var cell: int = int(cfg.get("cell", 256)) * ss
	vp = SubViewport.new()
	vp.size = Vector2i(cell, cell)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_DISABLED
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	var we := WorldEnvironment.new()
	we.environment = env
	vp.add_child(we)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = float(cfg.get("cam_size", 2.6))
	var elev := deg_to_rad(float(cfg.get("elev", 40.0)))
	var cy: float = float(cfg.get("center_y", 0.85))
	var dist := 20.0
	cam.position = Vector3(0, cy + sin(elev) * dist, cos(elev) * dist)
	cam.rotation = Vector3(-elev, 0, 0)
	cam.near = 0.1
	cam.far = 60.0
	vp.add_child(cam)


func _gltf(path: String) -> Node3D:
	if path.begins_with("res://"):
		var ps: PackedScene = load(path)
		return ps.instantiate() as Node3D if ps else null
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	var abs := ProjectSettings.globalize_path("res://tools/anim/src/" + path)
	var err := doc.append_from_file(abs, st)
	if err != OK:
		push_error("gltf load failed %s %d" % [abs, err])
		return null
	return doc.generate_scene(st) as Node3D


func _find(n: Node, cls: String) -> Array:
	var out := []
	if n.is_class(cls):
		out.append(n)
	for c in n.get_children():
		out.append_array(_find(c, cls))
	return out


func _toonify(root: Node, overrides: Dictionary) -> void:
	for mi in _find(root, "MeshInstance3D"):
		var m: MeshInstance3D = mi
		for s in m.mesh.get_surface_count():
			var src: Material = m.get_active_material(s)
			var sm := ShaderMaterial.new()
			sm.shader = toon_shader
			if src is BaseMaterial3D:
				var bm: BaseMaterial3D = src
				sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
				sm.set_shader_parameter("albedo_color", bm.albedo_color)
			for k in overrides:
				sm.set_shader_parameter(k, overrides[k])
			if m.has_meta("emit"):
				sm.set_shader_parameter("emission_boost", float(m.get_meta("emit")))
				sm.set_shader_parameter("emission_color", m.get_meta("emit_col"))
				sm.set_shader_parameter("rim_strength", 0.8)
			if not m.has_meta("emit"):
				var ol := ShaderMaterial.new()
				ol.shader = outline_shader
				ol.set_shader_parameter("width", float(cfg.get("ink_width", 0.010)))
				sm.next_pass = ol
			m.set_surface_override_material(s, sm)


var proc: Object = null


func _load_model() -> void:
	if cfg.has("procedural"):
		_load_procedural()
		return
	model = _gltf(cfg["model"])
	vp.add_child(model)
	model.scale = Vector3.ONE * float(cfg.get("model_scale", 1.0))
	_toonify(model, cfg.get("shade", {}))
	var sks := _find(model, "Skeleton3D")
	skel = sks[0] if sks.size() > 0 else null
	var aps := _find(model, "AnimationPlayer")
	if aps.size() > 0:
		player = aps[0]
	else:
		player = AnimationPlayer.new()
		model.add_child(player)
	# merge clips from every extra GLB
	var lib_main: AnimationLibrary = AnimationLibrary.new()
	var files: Array = cfg.get("clip_files", [])
	for f in files:
		var sc := _gltf(f)
		if sc == null:
			continue
		var ap: Array = _find(sc, "AnimationPlayer")
		if ap.is_empty():
			continue
		var p: AnimationPlayer = ap[0]
		# remap track paths relative to our player's root
		var src_root: Node = p.get_node(p.root_node)
		for lname in p.get_animation_library_list():
			var lib := p.get_animation_library(lname)
			for an in lib.get_animation_list():
				var a: Animation = lib.get_animation(an).duplicate(true)
				var key: String = String(f.get_file().get_basename()) + "/" + String(an)
				lib_main.add_animation(key.replace("/", "__").replace(" ", "_").replace("|", "_"), a)
		sc.free()
	if player.has_animation_library("x"):
		player.remove_animation_library("x")
	player.add_animation_library("x", lib_main)
	_attach_props()


func _load_procedural() -> void:
	## static GLB -> normalised -> auto-rigged with bones from the proc script; poses are computed per frame
	var src := _gltf(cfg["model"])
	var AR = load("res://tools/anim/autorig.gd")
	var res: Array = AR.normalize(src, float(cfg.get("height_m", 1.8)))
	proc = load(cfg["procedural"]).new()
	var bones: Array = proc.bones(res[1])
	print("AABB ", res[1])
	model = AR.build(res[0], bones, float(cfg.get("weight_sharp", 4.0)))
	vp.add_child(model)
	_toonify(model, cfg.get("shade", {}))
	skel = model.get_node("Skel")
	player = AnimationPlayer.new()
	model.add_child(player)
	player.add_animation_library("x", AnimationLibrary.new())
	src.free()


var _holders := []   # [holder, bone index, base rotation_degrees]


## anims[an]["prop_lock"] = [[rx, ry, rz], ...] (one per prop, degrees, character space: +Z forward, +Y up):
## keeps the weapon at that orientation while it follows the hand (a steady spear instead of one flailing with the
## arm swing). Without it the props keep their grip rotation.
func _lock_props(ad: Dictionary) -> void:
	var locks: Array = ad.get("prop_lock", [])
	for k in _holders.size():
		var h: Node3D = _holders[k][0]
		if k >= locks.size() or locks[k] == null:
			h.rotation_degrees = _holders[k][2]
			continue
		var r: Array = locks[k]
		var want := model.global_transform.basis.orthonormalized() * Basis.from_euler(Vector3(deg_to_rad(r[0]), deg_to_rad(r[1]), deg_to_rad(r[2])))
		var att := (skel.global_transform * skel.get_bone_global_pose(_holders[k][1])).basis.orthonormalized()
		h.basis = (att.inverse() * want).orthonormalized()


func _attach_props() -> void:
	if skel == null:
		return
	var props: Array = cfg.get("props", [])
	for p in props:
		var bone: String = p["bone"]
		var bi := skel.find_bone(bone)
		if bi < 0:
			push_error("bone not found " + bone)
			continue
		var ba := BoneAttachment3D.new()
		ba.bone_name = bone
		skel.add_child(ba)
		var holder := Node3D.new()
		ba.add_child(holder)
		var off: Array = p.get("pos", [0, 0, 0])
		var rot: Array = p.get("rot", [0, 0, 0])
		var ov := OS.get_cmdline_user_args()
		for a in ov:
			if a.begins_with("--proprot="):
				var parts: PackedStringArray = a.substr(10).split(",")
				rot = [float(parts[0]), float(parts[1]), float(parts[2])]
		holder.position = Vector3(off[0], off[1], off[2])
		holder.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
		_holders.append([holder, bi, holder.rotation_degrees])
		var w := _gltf(p["file"]) if p.has("file") else _proc_prop(p)
		if w:
			holder.add_child(w)
			var sc: float = float(p.get("scale", 1.0))
			w.scale = Vector3.ONE * sc
			_toonify(w, p.get("shade", {}))


func _proc_prop(p: Dictionary) -> Node3D:
	return load("res://tools/anim/props.gd").build(p)


func _strip_root(a: Animation) -> void:
	# keep the character in place: hips XZ follow the first key
	var hips: String = cfg.get("root_bone", "Hips")
	for t in a.get_track_count():
		if a.track_get_type(t) != Animation.TYPE_POSITION_3D:
			continue
		var path := String(a.track_get_path(t))
		if not path.ends_with(":" + hips):
			continue
		var n := a.track_get_key_count(t)
		if n == 0:
			continue
		var v0: Vector3 = a.track_get_key_value(t, 0)
		var up: int = int(cfg.get("up_axis", 1))
		for k in n:
			var v: Vector3 = a.track_get_key_value(t, k)
			var w := v0
			w[up] = v[up]
			a.track_set_key_value(t, k, w)


func _render(anims: Array, dirs: Array, still: bool) -> void:
	var out_root := ProjectSettings.globalize_path("res://tools/anim/out/" + char_id)
	DirAccess.make_dir_recursive_absolute(out_root)
	var lib := player.get_animation_library("x")
	for an in anims:
		var ad: Dictionary = cfg["anims"][an]
		var clip: String = ad.get("clip", "")
		if ad.has("retarget"):
			await _render_retarget(an, ad, dirs, still, out_root)
			continue
		if proc != null and clip == "":
			var nf: int = int(ad.get("frames", 8))
			var lp: bool = ad.get("loop", false)
			DirAccess.make_dir_recursive_absolute(out_root + "/" + an)
			for d in dirs:
				model.rotation_degrees.y = DIR_YAW[d] + float(cfg.get("yaw_offset", 0.0)) + float(ad.get("yaw", 0.0))
				for i in nf:
					var u: float = float(i) / float(nf) if lp else float(i) / float(max(nf - 1, 1))
					skel.reset_bone_poses()
					model.position = Vector3.ZERO
					model.scale = Vector3.ONE
					proc.pose(skel, model, String(ad.get("pose", an)), u)
					await RenderingServer.frame_post_draw
					await RenderingServer.frame_post_draw
					vp.get_texture().get_image().save_png("%s/%s/d%d_%02d.png" % [out_root, an, d, i])
					if still:
						break
			print("rendered ", an)
			continue
		if clip == "":
			DirAccess.make_dir_recursive_absolute(out_root + "/" + an)
			for d in dirs:
				model.rotation_degrees.y = DIR_YAW[d] + float(cfg.get("yaw_offset", 0.0))
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				vp.get_texture().get_image().save_png("%s/%s/d%d_00.png" % [out_root, an, d])
			continue
		var full := ""
		for nm in lib.get_animation_list():
			if String(nm).begins_with(clip + "__") or String(nm).contains(clip):
				full = nm
				break
		if full == "":
			push_error("clip not found %s for %s; have %s" % [clip, an, lib.get_animation_list()])
			continue
		var a: Animation = lib.get_animation(full)
		if not ad.get("keep_root", false):
			_strip_root(a)
		var length := a.length
		var t0: float = float(ad.get("from", 0.0)) * length
		var t1: float = float(ad.get("to", 1.0)) * length
		var frames: int = int(ad.get("frames", 8))
		var loop: bool = ad.get("loop", false)
		var times: Array = ad.get("times", [])   # optional explicit normalized times (0..1 of [from,to])
		player.play("x/" + full)
		player.pause()
		DirAccess.make_dir_recursive_absolute(out_root + "/" + an)
		for d in dirs:
			model.rotation_degrees.y = DIR_YAW[d] + float(cfg.get("yaw_offset", 0.0)) + float(ad.get("yaw", 0.0))
			for i in frames:
				var u: float
				if times.size() == frames:
					u = float(times[i])
				elif loop:
					u = float(i) / float(frames)
				else:
					u = float(i) / float(max(frames - 1, 1))
				player.seek(t0 + (t1 - t0) * u, true)
				_lock_props(ad)
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				if not hands_only:
					var img := vp.get_texture().get_image()
					img.save_png("%s/%s/d%d_%02d.png" % [out_root, an, d, i])
				_export_hands("%s/%s/d%d_%02d.json" % [out_root, an, d, i])
				if still:
					break
		print("rendered ", an)


func _probe(clip: String) -> void:
	## prints hand/foot/hips positions over time for picking segment boundaries
	var lib := player.get_animation_library("x")
	for nm in lib.get_animation_list():
		if not String(nm).contains(clip):
			continue
		var a: Animation = lib.get_animation(nm)
		player.play("x/" + nm)
		player.pause()
		var n := int(a.length * 30.0)
		print("PROBE ", nm, " len ", a.length)
		for i in n + 1:
			player.seek(a.length * i / n, true)
			await get_tree().process_frame
			var row := "%.3f" % (float(i) / n)
			for b in ["RightHand", "LeftHand", "Hips", "RightFoot", "LeftFoot", "Head"]:
				var bi := skel.find_bone(b)
				var gp: Vector3 = (skel.global_transform * skel.get_bone_global_pose(bi)).origin
				row += " %.3f %.3f %.3f" % [gp.x, gp.y, gp.z]
			print("P ", row)



# ---------------------------------------------------------------- retargeting (meshyrig -> meshyrig)
## anims[an]["retarget"] = {"file": <clip file>, "clip": <name part>}. Every Meshy auto-rig shares the same 24-bone
## layout but with different rest poses, so clips are moved through world-space rotation deltas:
##   W_tgt(bone) = (W_src_pose * W_src_rest^-1) * W_tgt_rest   (then converted back to the target's local space)
## Hips translation (bob / crouch) is scaled by the hip-height ratio. Root XZ travel is dropped (in-place).

var _rt_cache := {}   # file -> [scene, skel, player]


func _rt_source(file: String) -> Array:
	if _rt_cache.has(file):
		return _rt_cache[file]
	var sc := _gltf(file)
	vp.add_child(sc)
	sc.visible = false
	var sk: Skeleton3D = _find(sc, "Skeleton3D")[0]
	var ap: AnimationPlayer = _find(sc, "AnimationPlayer")[0]
	_rt_cache[file] = [sc, sk, ap]
	return _rt_cache[file]


func _rt_anim(ap: AnimationPlayer, clip: String) -> String:
	for nm in ap.get_animation_list():
		if String(nm).contains(clip):
			return nm
	return ""


## character-space transform of a skeleton (relative to its scene root, so the render yaw does not leak in)
func _cs(sk: Skeleton3D, root: Node3D) -> Transform3D:
	return root.global_transform.affine_inverse() * sk.global_transform


func _wrot(sk: Skeleton3D, cs: Transform3D, i: int, rest: bool) -> Quaternion:
	var g := sk.get_bone_global_rest(i) if rest else sk.get_bone_global_pose(i)
	return (cs.basis.orthonormalized() * g.basis.orthonormalized()).get_rotation_quaternion()


func _apply_retarget(src: Skeleton3D, src_root: Node3D, dst: Skeleton3D) -> void:
	var cs := _cs(src, src_root)
	var cd := _cs(dst, model)
	var n := dst.get_bone_count()
	var wt := {}
	var dst_node := cd.basis.orthonormalized().get_rotation_quaternion()
	for i in n:
		var si := src.find_bone(dst.get_bone_name(i))
		var par := dst.get_bone_parent(i)
		var pw: Quaternion = wt[par] if par >= 0 else dst_node
		var w: Quaternion
		if si < 0:
			w = pw * dst.get_bone_rest(i).basis.get_rotation_quaternion()
		else:
			var d := _wrot(src, cs, si, false) * _wrot(src, cs, si, true).inverse()
			w = d * _wrot(dst, cd, i, true)
		wt[i] = w
		dst.set_bone_pose_rotation(i, (pw.inverse() * w).normalized())
	var hs := src.find_bone("Hips")
	var hd := dst.find_bone("Hips")
	if hs >= 0 and hd >= 0:
		var s_rest := cs * src.get_bone_global_rest(hs).origin
		var s_pose := cs * src.get_bone_global_pose(hs).origin
		var d_rest := cd * dst.get_bone_global_rest(hd).origin
		var ratio := d_rest.y / maxf(s_rest.y, 0.001)
		var delta := (s_pose - s_rest) * ratio
		delta.x = 0.0
		delta.z = 0.0
		var par := dst.get_bone_parent(hd)
		var parent_g := cd * (dst.get_bone_global_pose(par) if par >= 0 else Transform3D())
		dst.set_bone_pose_position(hd, parent_g.affine_inverse() * (d_rest + delta))


func _render_retarget(an: String, ad: Dictionary, dirs: Array, still: bool, out_root: String) -> void:
	var rt: Dictionary = ad["retarget"]
	var src: Array = _rt_source(rt["file"])
	var sap: AnimationPlayer = src[2]
	var full := _rt_anim(sap, rt["clip"])
	if full == "":
		push_error("clip not found %s in %s: %s" % [rt["clip"], rt["file"], sap.get_animation_list()])
		return
	var a: Animation = sap.get_animation(full)
	var length := a.length
	var t0: float = float(ad.get("from", 0.0)) * length
	var t1: float = float(ad.get("to", 1.0)) * length
	var frames: int = int(ad.get("frames", 8))
	var loop: bool = ad.get("loop", false)
	var times: Array = ad.get("times", [])
	player.stop()
	sap.play(full)
	sap.pause()
	DirAccess.make_dir_recursive_absolute(out_root + "/" + an)
	for d in dirs:
		model.rotation_degrees.y = DIR_YAW[d] + float(cfg.get("yaw_offset", 0.0)) + float(ad.get("yaw", 0.0))
		for i in frames:
			var u: float
			if times.size() == frames:
				u = float(times[i])
			elif loop:
				u = float(i) / float(frames)
			else:
				u = float(i) / float(max(frames - 1, 1))
			sap.seek(t0 + (t1 - t0) * u, true)
			_apply_retarget(src[1], src[0], skel)
			_lock_props(ad)
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			if not hands_only:
				vp.get_texture().get_image().save_png("%s/%s/d%d_%02d.png" % [out_root, an, d, i])
			_export_hands("%s/%s/d%d_%02d.json" % [out_root, an, d, i])
			if still:
				break
	print("rendered ", an)


## Per-frame hand data for weapons drawn at runtime (cfg "export_hands"): camera-space (x right, y up, z toward the
## camera, metres) origin + basis columns of each hand bone, the chest and the character root. tools/anim/hands.py
## turns them into per-weapon sprite transforms.
func _export_hands(path: String) -> void:
	if not cfg.get("export_hands", false) or skel == null:
		return
	var inv := cam.global_transform.affine_inverse()
	var out := {}
	for b in ["RightHand", "LeftHand", "RightForeArm", "LeftForeArm", "Spine02", "Spine01", "Spine", "Hips"]:
		var bi := skel.find_bone(b)
		if bi < 0:
			continue
		var g := inv * skel.global_transform * skel.get_bone_global_pose(bi)
		var bs := g.basis.orthonormalized()
		out[b] = [g.origin.x, g.origin.y, g.origin.z, bs.x.x, bs.x.y, bs.x.z, bs.y.x, bs.y.y, bs.y.z, bs.z.x, bs.z.y, bs.z.z]
	var m := (inv * model.global_transform)
	var mb := m.basis.orthonormalized()
	out["root"] = [m.origin.x, m.origin.y, m.origin.z, mb.x.x, mb.x.y, mb.x.z, mb.y.x, mb.y.y, mb.y.z, mb.z.x, mb.z.y, mb.z.z]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))


## --stride=<clip> [--rfile=<file>]: root travel of a clip (metres, world), hip height and length, for foot-plant fps.
func _stride(clip: String, rfile: String) -> void:
	var sk: Skeleton3D = skel
	var ap: AnimationPlayer = player
	var full := ""
	if rfile != "":
		var src := _rt_source(rfile)
		sk = src[1]
		ap = src[2]
		full = _rt_anim(ap, clip)
	else:
		for nm in ap.get_animation_list():
			if String(nm).contains(clip):
				full = nm
				break
	if full == "":
		print("STRIDE clip not found ", clip, " ", ap.get_animation_list())
		return
	var a: Animation = ap.get_animation(full)
	var hb := sk.find_bone("Hips")
	ap.play(full)
	ap.pause()
	var n := 60
	var prev := Vector3.ZERO
	var rows := []
	for i in n + 1:
		ap.seek(a.length * i / n, true)
		var g := sk.global_transform
		var hp := g * sk.get_bone_global_pose(hb).origin
		var lf := g * sk.get_bone_global_pose(sk.find_bone("LeftFoot")).origin
		var rf := g * sk.get_bone_global_pose(sk.find_bone("RightFoot")).origin
		rows.append("%.3f hips %.3f %.3f %.3f  LF %.3f %.3f %.3f  RF %.3f %.3f %.3f" % [float(i) / n, hp.x, hp.y, hp.z, lf.x, lf.y, lf.z, rf.x, rf.y, rf.z])
	print("STRIDE ", full, " len ", a.length)
	for r in rows:
		print("S ", r)
