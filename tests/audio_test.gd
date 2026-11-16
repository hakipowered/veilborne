extends Node
## Headless audio smoke test: loads Audio (autoload or a local instance), plays every sfx, ui sound and
## music track briefly, exercises cooldown/stealing/crossfade/volumes, and exits 0 on success, 1 on failure.
##   $G --headless --path . res://tests/audio_test.tscn

var _audio: Node
var _fail := 0


func _ready() -> void:
	_audio = get_node_or_null("/root/Audio")
	if _audio == null:
		_audio = load("res://autoload/audio.gd").new()
		_audio.name = "AudioUnderTest"
		add_child(_audio)
	await get_tree().process_frame
	_run()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		_fail += 1
		printerr("FAIL: ", msg)


func _run() -> void:
	var miss: PackedStringArray = _audio.missing()
	_check(miss.is_empty(), "missing audio files: %s" % [miss])
	for bus in ["Music", "SFX", "UI"]:
		_check(AudioServer.get_bus_index(bus) >= 0, "bus %s missing" % bus)

	# every gameplay sfx, positional and flat
	var i := 0
	for n in _audio.SFX_NAMES:
		_audio.sfx(n)
		_audio.sfx(n, Vector2(100.0 * i, 50.0), 0.1, -3.0)
		i += 1
		await get_tree().process_frame
	# every ui sound
	for n in _audio.UI_NAMES:
		_audio.ui(n)
		await get_tree().process_frame
	# machine-gun spam: must not throw, cooldown/caps keep voices bounded
	for k in 200:
		_audio.sfx("hit_flesh", Vector2(k, 0))
		_audio.sfx("footstep")
	# unknown names must be silent no-ops
	_audio.sfx("does_not_exist")
	_audio.ui("nope")
	_audio.music("nope_track", 0.2)

	# every music track, with crossfades
	for t in _audio.MUSIC_TRACKS:
		_audio.music(t, 0.15)
		for f in 12:
			await get_tree().process_frame
		_check(_audio.current_music() == t, "music track %s not current" % t)
	_audio.music("catacombs", 0.3)
	_audio.music("boss", 0.3)  # interrupt a crossfade
	for f in 30:
		await get_tree().process_frame
	_audio.music("", 0.2)
	for f in 20:
		await get_tree().process_frame
	_check(_audio.current_music() == "", "music stop failed")

	# loop flags
	var s = load("res://audio/music/catacombs.ogg")
	_check(s is AudioStreamOggVorbis and s.loop, "catacombs should loop")

	# volumes persist
	var old: Vector3 = _audio.get_volumes()
	_audio.set_volumes(0.5, 0.25, 0.75)
	var cf := ConfigFile.new()
	_check(cf.load("user://settings.cfg") == OK, "settings.cfg not written")
	_check(is_equal_approx(float(cf.get_value("audio", "music", -1.0)), 0.25), "music volume not persisted")
	_audio.set_volumes(old.x, old.y, old.z)

	if _fail == 0:
		print("AUDIO TEST PASS: %d sfx, %d ui, %d music tracks" % [_audio.SFX_NAMES.size(), _audio.UI_NAMES.size(), _audio.MUSIC_TRACKS.size()])
	else:
		print("AUDIO TEST FAIL (%d)" % _fail)
	_audio.stop_all_sfx()
	_audio.music("", 0.0)
	s = null
	if _audio.get_parent() == self:
		_audio.queue_free()
	for f in 3:
		await get_tree().process_frame
	get_tree().quit(1 if _fail > 0 else 0)
