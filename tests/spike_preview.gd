extends Node2D
## Floor spike trap preview: renders the trap cycle frame by frame in every chapter that has traps.
## xvfb-run -a -s "-screen 0 900x600x24" $G --rendering-driver opengl3 --path . --resolution 900x600 \
##   res://tests/spike_preview.tscn -- --out=/tmp/spikes [--fps=20] [--chapters=garden,forge,hollow]
const EnvScript := preload("res://scenes/environment.gd")
const VARIANT := {"garden": 3, "forge": 1, "hollow": 0}

var out := "/tmp"
var fps := 20.0
var chapters := ["garden", "forge", "hollow"]
var env: Node2D
var entities: Node2D
var cam: Camera2D

func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
		elif a.begins_with("--fps="): fps = float(a.substr(6))
		elif a.begins_with("--chapters="): chapters = Array(a.substr(11).split(","))
	env = EnvScript.new()
	add_child(env)
	entities = Node2D.new()
	entities.y_sort_enabled = true
	add_child(entities)
	cam = Camera2D.new()
	cam.zoom = Vector2(2.2, 2.2)
	add_child(cam)
	cam.make_current()
	_run()

func _run() -> void:
	await get_tree().process_frame
	for ch in chapters:
		env.force_variant = VARIANT[ch]
		env.build(ch, 1, 77)
		env.add_ysorted_props_to(entities)
		var sn: Array = env._spike_nodes[0]
		var trap: Node2D = sn[1]
		cam.position = trap.position + Vector2(0, -22)
		cam.reset_smoothing()
		env.set_process(false)
		await get_tree().create_timer(0.3).timeout
		var period: float = env.SPIKE_PERIOD
		# start just before the warning, run one full cycle
		var start: float = period - env.SPIKE_UP - env.SPIKE_WARN - 0.2
		var n := int(period * fps)
		for f in range(n):
			var ph := fmod(start + f / fps, period)
			var act: bool = trap.step(ph)
			await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			img.save_png("%s/%s_%03d.png" % [out, ch, f])
			print("%s f%03d ph=%.2f active=%s" % [ch, f, ph, act])
	get_tree().quit()
