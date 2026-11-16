extends Node
## Veilborne audio runtime (autoload "Audio").
## - Buses Master/Music/SFX/UI (created in code when the project has no bus layout for them).
## - Pooled voices: positional AudioStreamPlayer2D + non-positional AudioStreamPlayer, voice stealing by
##   priority then age, per-sound cooldown and per-sound instance cap (no machine-gun stacking).
## - Two music players with an equal-power crossfade, driven from _process (no tweens, no allocs).
## - Volumes persisted to user://settings.cfg [audio] master/music/sfx (other sections are preserved).
## - All streams are loaded once in _ready (music lazily on first use, then cached). Missing files warn
##   once and every call becomes a silent no-op; nothing here can crash the game.

const SFX_DIR := "res://audio/sfx/"
const MUSIC_DIR := "res://audio/music/"
const SETTINGS_PATH := "user://settings.cfg"

const SFX_NAMES: PackedStringArray = [
	"swing_spear", "swing_blades", "hit_flesh", "hit_crit", "dash", "special_ember", "special_moon",
	"hero_hurt", "hero_down", "revive", "enemy_die", "shade_lunge", "spitter_shoot", "projectile_hit",
	"brute_slam", "slam_impact", "regent_burst", "regent_charge", "regent_summon", "regent_roar",
	"regent_die", "boon_pickup", "door_open", "room_clear", "shard_pickup", "footstep",
]
const UI_NAMES: PackedStringArray = ["click", "hover", "confirm", "back", "boon", "purchase", "open"]
const MUSIC_TRACKS: PackedStringArray = ["title", "sanctum", "catacombs", "boss", "victory", "defeat"]
const LOOPING_TRACKS: PackedStringArray = ["title", "sanctum", "catacombs", "boss"]

## Per-sound tuning: [base volume dB, priority (higher survives stealing), cooldown ms, max simultaneous]
const TUNING := {
	"swing_spear": [-4.0, 3, 45, 3],
	"swing_blades": [-4.0, 3, 45, 3],
	"hit_flesh": [-2.0, 4, 40, 4],
	"hit_crit": [0.0, 6, 50, 2],
	"dash": [-4.0, 4, 80, 2],
	"special_ember": [0.0, 7, 150, 2],
	"special_moon": [0.0, 7, 150, 2],
	"hero_hurt": [-1.0, 8, 120, 2],
	"hero_down": [0.0, 9, 300, 2],
	"revive": [0.0, 9, 300, 2],
	"enemy_die": [-3.0, 5, 50, 3],
	"shade_lunge": [-6.0, 3, 90, 2],
	"spitter_shoot": [-6.0, 3, 70, 3],
	"projectile_hit": [-7.0, 2, 50, 3],
	"brute_slam": [-3.0, 5, 120, 2],
	"slam_impact": [-1.0, 6, 80, 2],
	"regent_burst": [-1.0, 8, 150, 1],
	"regent_charge": [0.0, 8, 300, 1],
	"regent_summon": [0.0, 8, 400, 1],
	"regent_roar": [0.0, 9, 500, 1],
	"regent_die": [0.0, 10, 1000, 1],
	"boon_pickup": [-2.0, 7, 150, 2],
	"door_open": [-2.0, 6, 500, 1],
	"room_clear": [-1.0, 8, 500, 1],
	"shard_pickup": [-6.0, 4, 40, 3],
	"footstep": [-16.0, 0, 90, 2],
	"ui_click": [-4.0, 5, 30, 2],
	"ui_hover": [-12.0, 1, 60, 1],
	"ui_confirm": [-3.0, 6, 60, 2],
	"ui_back": [-4.0, 6, 60, 2],
	"ui_boon": [-2.0, 7, 120, 2],
	"ui_purchase": [-2.0, 7, 80, 2],
	"ui_open": [-5.0, 5, 80, 2],
}
const DEFAULT_TUNING := [-3.0, 3, 40, 3]

const POS_VOICES := 16      # positional (AudioStreamPlayer2D)
const FLAT_VOICES := 8      # non-positional gameplay sfx
const UI_VOICES := 4
const MAX_DISTANCE := 2200.0
const MUSIC_DB := -4.0      # headroom for the music bed under sfx

var master_volume := 1.0
var music_volume := 0.7
var sfx_volume := 0.9

var _streams := {}          # name -> AudioStream (or null when missing)
var _music_streams := {}    # track -> AudioStream (or null)
var _warned := {}
var _last_play_ms := {}     # name -> msec
var _tuning_cache := {}     # name -> Array

# voice pools: parallel arrays avoid per-call allocation
var _pos_players: Array[AudioStreamPlayer2D] = []
var _flat_players: Array[AudioStreamPlayer] = []
var _ui_players: Array[AudioStreamPlayer] = []
var _pos_name: Array = []      # (Arrays are shared by reference when passed to _pick_voice)
var _pos_prio: Array = []
var _pos_start: Array = []
var _flat_name: Array = []
var _flat_prio: Array = []
var _flat_start: Array = []
var _ui_next := 0
var _ui_keys := {}             # "click" -> "ui_click" (prebuilt, no string concat per call)

# music
var _mus: Array[AudioStreamPlayer] = []
var _mus_active := 0
var _mus_track := ""
var _fade_t := 1.0
var _fade_len := 1.0
var _fading := false

var _bus_master := 0
var _bus_music := 0
var _bus_sfx := 0
var _bus_ui := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_buses()
	_build_pools()
	_load_sfx()
	_load_settings()
	_apply_volumes()
	set_process(false)


# ---------------------------------------------------------------- public API

## Play a gameplay sfx. pos == Vector2.INF -> non-positional. Pooled; never allocates per call.
func sfx(name: String, pos := Vector2.INF, pitch_var := 0.08, volume_db := 0.0) -> void:
	_play(name, pos, pitch_var, volume_db, false)


## Play a UI sound: "click","hover","confirm","back","boon","purchase","open".
func ui(name: String) -> void:
	var key: String = _ui_keys.get(name, "")
	if key == "":
		_warn_once("ui:" + name, "Audio: unknown ui sound '%s'" % name)
		return
	_play(key, Vector2.INF, 0.03, 0.0, true)


## Switch music with a crossfade. "" (or unknown) stops music with a fade-out. Same track = no-op.
func music(track: String, fade := 1.0) -> void:
	if track == _mus_track and _mus.size() == 2 and _mus[_mus_active].playing:
		return
	var stream: AudioStream = null
	if track != "":
		stream = _get_music(track)
	if _mus.size() < 2:
		return
	if _fading:  # a crossfade is in flight: drop the outgoing voice immediately
		_mus[1 - _mus_active].stop()
	var old := _mus[_mus_active]
	_mus_active = 1 - _mus_active
	var nxt := _mus[_mus_active]
	_mus_track = track if stream != null else ""
	nxt.stop()
	if stream != null:
		nxt.stream = stream
		nxt.volume_db = -80.0 if fade > 0.01 else MUSIC_DB
		nxt.play()
	if fade <= 0.01:
		old.stop()
		_fading = false
		set_process(false)
		if stream != null:
			nxt.volume_db = MUSIC_DB
		return
	_fade_len = fade
	_fade_t = 0.0
	_fading = true
	set_process(true)


## Linear 0..1 volumes; persisted to user://settings.cfg.
func set_volumes(master: float, music_v: float, sfx_v: float) -> void:
	master_volume = clampf(master, 0.0, 1.0)
	music_volume = clampf(music_v, 0.0, 1.0)
	sfx_volume = clampf(sfx_v, 0.0, 1.0)
	_apply_volumes()
	_save_settings()


func get_volumes() -> Vector3:
	return Vector3(master_volume, music_volume, sfx_volume)


func current_music() -> String:
	return _mus_track


func stop_all_sfx() -> void:
	for p in _pos_players:
		p.stop()
	for p in _flat_players:
		p.stop()


## Names of sounds/tracks whose files are missing (for tests/diagnostics).
func missing() -> PackedStringArray:
	var out := PackedStringArray()
	for k in _streams:
		if _streams[k] == null:
			out.append(k)
	for t in MUSIC_TRACKS:
		if _get_music(t) == null:
			out.append("music:" + t)
	return out


# ---------------------------------------------------------------- internals

func _ensure_buses() -> void:
	_bus_master = 0
	_bus_music = _ensure_bus("Music")
	_bus_sfx = _ensure_bus("SFX")
	_bus_ui = _ensure_bus("UI")


func _ensure_bus(bus_name: String) -> int:
	var idx := AudioServer.get_bus_index(bus_name)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, "Master")
	return idx


func _build_pools() -> void:
	for i in POS_VOICES:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = MAX_DISTANCE
		p.attenuation = 1.2
		p.panning_strength = 0.6
		p.max_polyphony = 1
		add_child(p)
		_pos_players.append(p)
	_pos_name.resize(POS_VOICES)
	_pos_name.fill("")
	_pos_prio.resize(POS_VOICES)
	_pos_prio.fill(0)
	_pos_start.resize(POS_VOICES)
	_pos_start.fill(0)
	for i in FLAT_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_flat_players.append(p)
	_flat_name.resize(FLAT_VOICES)
	_flat_name.fill("")
	_flat_prio.resize(FLAT_VOICES)
	_flat_prio.fill(0)
	_flat_start.resize(FLAT_VOICES)
	_flat_start.fill(0)
	for i in UI_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "UI"
		add_child(p)
		_ui_players.append(p)
	for i in 2:
		var m := AudioStreamPlayer.new()
		m.bus = "Music"
		m.volume_db = MUSIC_DB
		add_child(m)
		_mus.append(m)


func _load_sfx() -> void:
	for n in SFX_NAMES:
		_streams[n] = _load_stream(SFX_DIR + n)
		_last_play_ms[n] = -100000
		_tuning_cache[n] = TUNING.get(n, DEFAULT_TUNING)
	for n in UI_NAMES:
		var key := "ui_" + n
		_ui_keys[n] = key
		_streams[key] = _load_stream(SFX_DIR + key)
		_last_play_ms[key] = -100000
		_tuning_cache[key] = TUNING.get(key, DEFAULT_TUNING)


func _load_stream(base: String) -> AudioStream:
	for ext in [".wav", ".ogg", ".mp3"]:
		var path: String = base + ext
		if ResourceLoader.exists(path):
			var s = load(path)
			if s is AudioStream:
				return s
	_warn_once(base, "Audio: missing sound '%s' (.wav/.ogg) - calls will be silent" % base)
	return null


func _get_music(track: String) -> AudioStream:
	if _music_streams.has(track):
		return _music_streams[track]
	var s: AudioStream = null
	if MUSIC_TRACKS.has(track):
		s = _load_stream(MUSIC_DIR + track)
	else:
		_warn_once("track:" + track, "Audio: unknown music track '%s'" % track)
	if s != null:
		var lp := LOOPING_TRACKS.has(track)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = lp
		elif s is AudioStreamMP3:
			(s as AudioStreamMP3).loop = lp
	_music_streams[track] = s
	return s


func _warn_once(key: String, msg: String) -> void:
	if _warned.has(key):
		return
	_warned[key] = true
	push_warning(msg)


func _play(name: String, pos: Vector2, pitch_var: float, volume_db: float, is_ui: bool) -> void:
	var stream: AudioStream = _streams.get(name)
	if stream == null:
		if not _streams.has(name):
			_warn_once(name, "Audio: unknown sound '%s'" % name)
		return
	var now := Time.get_ticks_msec()
	var tune: Array = _tuning_cache[name]
	if now - int(_last_play_ms[name]) < int(tune[2]):
		return
	_last_play_ms[name] = now
	var vol: float = float(tune[0]) + volume_db
	var pitch := 1.0
	if pitch_var > 0.0:
		pitch = 1.0 + randf_range(-pitch_var, pitch_var)
	if is_ui:
		var up := _ui_players[_ui_next]
		_ui_next = (_ui_next + 1) % UI_VOICES
		up.stream = stream
		up.volume_db = vol
		up.pitch_scale = pitch
		up.play()
		return
	var prio: int = int(tune[1])
	var cap: int = int(tune[3])
	if pos == Vector2.INF:
		var i := _pick_voice(_flat_players, _flat_name, _flat_prio, _flat_start, name, prio, cap, now)
		if i < 0:
			return
		var p := _flat_players[i]
		p.stream = stream
		p.volume_db = vol
		p.pitch_scale = pitch
		p.play()
	else:
		var j := _pick_voice(_pos_players, _pos_name, _pos_prio, _pos_start, name, prio, cap, now)
		if j < 0:
			return
		var q := _pos_players[j]
		q.global_position = pos
		q.stream = stream
		q.volume_db = vol
		q.pitch_scale = pitch
		q.play()


## Returns a voice index or -1. Prefers a free voice; enforces the per-sound cap by recycling the
## oldest instance of the same sound; otherwise steals the lowest-priority (then oldest) voice whose
## priority is <= the new sound's.
func _pick_voice(players: Array, names: Array, prios: Array,
		starts: Array, name: String, prio: int, cap: int, now: int) -> int:
	var free_i := -1
	var same_count := 0
	var same_oldest := -1
	var steal_i := -1
	var steal_prio := 1 << 30
	var steal_start := 1 << 62
	for i in players.size():
		var pl = players[i]
		if not pl.playing:
			if free_i < 0:
				free_i = i
			continue
		if names[i] == name:
			same_count += 1
			if same_oldest < 0 or int(starts[i]) < int(starts[same_oldest]):
				same_oldest = i
		var pr: int = prios[i]
		var st: int = starts[i]
		if pr < steal_prio or (pr == steal_prio and st < steal_start):
			steal_prio = pr
			steal_start = st
			steal_i = i
	var chosen := -1
	if same_count >= cap and same_oldest >= 0:
		chosen = same_oldest
	elif free_i >= 0:
		chosen = free_i
	elif steal_i >= 0 and steal_prio <= prio:
		chosen = steal_i
	if chosen < 0:
		return -1
	players[chosen].stop()
	names[chosen] = name
	prios[chosen] = prio
	starts[chosen] = now
	return chosen


func _process(delta: float) -> void:
	if not _fading:
		set_process(false)
		return
	_fade_t = minf(_fade_t + delta / maxf(_fade_len, 0.001), 1.0)
	var a := _mus[_mus_active]
	var b := _mus[1 - _mus_active]
	# equal-power crossfade
	var gin := sin(_fade_t * PI * 0.5)
	var gout := cos(_fade_t * PI * 0.5)
	if a.playing:
		a.volume_db = MUSIC_DB + linear_to_db(maxf(gin, 0.0001))
	if b.playing:
		b.volume_db = MUSIC_DB + linear_to_db(maxf(gout, 0.0001))
	if _fade_t >= 1.0:
		b.stop()
		if a.playing:
			a.volume_db = MUSIC_DB
		_fading = false
		set_process(false)


func _apply_volumes() -> void:
	_set_bus_linear(_bus_master, master_volume)
	_set_bus_linear(_bus_music, music_volume)
	_set_bus_linear(_bus_sfx, sfx_volume)
	_set_bus_linear(_bus_ui, sfx_volume)


func _set_bus_linear(idx: int, v: float) -> void:
	if idx < 0 or idx >= AudioServer.bus_count:
		return
	AudioServer.set_bus_mute(idx, v <= 0.001)
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.001)))


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	master_volume = clampf(float(cf.get_value("audio", "master", master_volume)), 0.0, 1.0)
	music_volume = clampf(float(cf.get_value("audio", "music", music_volume)), 0.0, 1.0)
	sfx_volume = clampf(float(cf.get_value("audio", "sfx", sfx_volume)), 0.0, 1.0)


func _save_settings() -> void:
	var cf := ConfigFile.new()
	cf.load(SETTINGS_PATH)  # keep other sections (ok if missing)
	cf.set_value("audio", "master", master_volume)
	cf.set_value("audio", "music", music_volume)
	cf.set_value("audio", "sfx", sfx_volume)
	var err := cf.save(SETTINGS_PATH)
	if err != OK:
		_warn_once("settings_save", "Audio: could not save %s (%d)" % [SETTINGS_PATH, err])


func _exit_tree() -> void:
	# stop every voice so no playback keeps streams alive at shutdown
	stop_all_sfx()
	for p in _ui_players:
		p.stop()
	for m in _mus:
		m.stop()
		m.stream = null
