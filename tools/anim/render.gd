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


func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var s: String = a.trim_prefix("--")
		var kv := s.split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else "1"
	char_id = args.get("char", "kaela")
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
			var ol := ShaderMaterial.new()
			ol.shader = outline_shader
			ol.set_shader_parameter("width", float(cfg.get("ink_width", 0.010)))
			sm.next_pass = ol
			m.set_surface_override_material(s, sm)


func _load_model() -> void:
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
		holder.position = Vector3(off[0], off[1], off[2])
		holder.rotation_degrees = Vector3(rot[0], rot[1], rot[2])
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
		var clip: String = ad["clip"]
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
				await RenderingServer.frame_post_draw
				await RenderingServer.frame_post_draw
				var img := vp.get_texture().get_image()
				img.save_png("%s/%s/d%d_%02d.png" % [out_root, an, d, i])
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
