class_name AnimSprite
extends Node2D
## Frame-by-frame directional sprite (pre-rendered sheets from tools/anim). Feet at node origin.
## Data: res://art/anim/<id>/data.gd (DATA const) + <id>_<page>.webp atlas pages.
## 5 rendered directions (S, SE, E, NE, N); SW/W/NW are mirrored.
## Cheap at runtime: one Sprite2D, region_rect swaps from cached arrays, no per-frame allocations.

signal anim_finished(anim: String)
signal anim_event(name: String)

const ISO_SIN := 0.64      # sin(render elevation 40deg): un-squash screen y to ground direction
const SHADER_CODE := "shader_type canvas_item;\nuniform float flash = 0.0;\nuniform vec4 flash_color : source_color = vec4(1.0);\nvoid fragment(){ vec4 c = texture(TEXTURE, UV) * COLOR; c.rgb = mix(c.rgb, flash_color.rgb, flash * c.a); COLOR = c; }"

## 0..1 white hit flash (per instance; shared material when 0 so sprites still batch)
var flash: float = 0.0:
	set(v):
		flash = clampf(v, 0.0, 1.0)
		_apply_flash()
## multiplies the sprite colour (alpha too)
var tint: Color = Color.WHITE:
	set(v):
		tint = v
		if _spr:
			_spr.self_modulate = v
		for w in _wspr:
			w.self_modulate = v
var flash_color: Color = Color.WHITE

var character_id := ""
var current := ""
var frame := 0
var speed_scale := 1.0
var dir_index := 0          # 0..4 rendered dir
var mirrored := false

static var _cache := {}      # id -> {anims: {name: {fps, loop, events: {frame: name}, n, rects: [5][n] Rect2, offs: [5][n] Vector2, pages: [5][n] int}}, tex: [Texture2D], ref_h}
static var _shader: Shader
static var _shared_mat: ShaderMaterial

var _spr: Sprite2D
var _own_mat: ShaderMaterial
var _data: Dictionary = {}
var _anim: Dictionary = {}
var _t := 0.0
var _scale := 1.0
var _done := false
var _facing := Vector2.DOWN
var _fit := 1.0             # per-anim time stretch from play_timed(); reset by play()

## Weapon in hand (heroines): the equipped weapon's painted sprite follows the hand frame by frame, using the
## per-frame transforms in art/anim/<id>/hands.gd (tools/anim/hands.py). Two layers: behind and in front of the body.
var weapon := ""
var _wback: Node2D
var _wfront: Node2D
var _wspr: Array[Sprite2D] = []   # per grip: [back sprite, front sprite, back, front, ...]

## enemy.gd state code (S_IDLE..S_SUMMON) -> anim; "" = recover (let the attack finish, then idle)
const ENEMY_STATE_ANIM := ["idle", "move", "windup", "attack", "", "hurt", "windup", "attack", "windup", "charge", "windup", "cast"]


func setup(p_character_id: String, target_height_px: float) -> void:
	character_id = p_character_id
	_data = _load(p_character_id)
	if _data.is_empty():
		push_warning("AnimSprite: no data for " + p_character_id)
		return
	if _spr == null:
		_spr = Sprite2D.new()
		_spr.centered = false
		_spr.region_enabled = true
		_spr.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		add_child(_spr)
	if _shader == null:
		_shader = Shader.new()
		_shader.code = SHADER_CODE
		_shared_mat = ShaderMaterial.new()
		_shared_mat.shader = _shader
	_spr.material = _shared_mat
	_spr.self_modulate = tint
	var ref_h: float = _data["ref_h"]
	_scale = target_height_px / maxf(ref_h, 1.0)
	_apply_scale()
	current = ""
	var first: String = "idle" if _data["anims"].has("idle") else String(_data["anims"].keys()[0])
	play(first, true)
	if weapon != "":
		set_weapon(weapon)


static func _load(id: String) -> Dictionary:
	if _cache.has(id):
		return _cache[id]
	var path := "res://art/anim/%s/data.gd" % id
	if not ResourceLoader.exists(path):
		return {}
	var scr: GDScript = load(path)
	var raw: Dictionary = scr.get("DATA") if scr else {}
	if raw.is_empty():
		var c := scr.get_script_constant_map()
		raw = c.get("DATA", {})
	var tex: Array[Texture2D] = []
	for p in int(raw["pages"]):
		tex.append(load("res://art/anim/%s/%s_%d.webp" % [id, id, p]) as Texture2D)
	var anims := {}
	for an in raw["anims"]:
		var a: Dictionary = raw["anims"][an]
		var rects := []
		var offs := []
		var pages := []
		var n := 0
		for d in a["dirs"]:
			var r: Array[Rect2] = []
			var o: Array[Vector2] = []
			var pg: PackedInt32Array = PackedInt32Array()
			for f in d:
				r.append(Rect2(f[1], f[2], f[3], f[4]))
				o.append(Vector2(f[5], f[6]))
				pg.append(int(f[0]))
			rects.append(r)
			offs.append(o)
			pages.append(pg)
			n = maxi(n, r.size())
		var ev := {}
		var src_ev: Dictionary = a.get("events", {})
		for k in src_ev:
			var v = src_ev[k]
			if v is Array:
				for fi in v:
					ev[int(fi)] = StringName(k)
			else:
				ev[int(v)] = StringName(k)
		anims[an] = {"fps": float(a["fps"]), "loop": bool(a["loop"]), "events": ev, "n": n,
			"rects": rects, "offs": offs, "pages": pages}
	var res := {"anims": anims, "tex": tex, "ref_h": float(raw["ref_h"]), "hands": {}, "hand_art": {}}
	var hp := "res://art/anim/%s/hands.gd" % id
	if ResourceLoader.exists(hp):
		var hs: GDScript = load(hp)
		var hraw: Dictionary = hs.get_script_constant_map().get("DATA", {}) if hs else {}
		var art: Dictionary = hraw.get("art", {})
		for w in art:
			var texs: Array[Texture2D] = []
			for ap in art[w]:
				texs.append(load(String(ap)) as Texture2D)
			res["hand_art"][w] = texs
		var ha: Dictionary = hraw.get("anims", {})
		for an in ha:
			var per := {}
			for w in ha[an]:
				var dirs := []
				for d in ha[an][w]:
					var frames := []
					for fr in d:
						var grips := []
						for g in fr:
							grips.append([Transform2D(Vector2(g[0], g[1]), Vector2(g[2], g[3]), Vector2(g[4], g[5])), int(g[6]) == 1])
						frames.append(grips)
					dirs.append(frames)
				per[w] = dirs
			res["hands"][an] = per
	_cache[id] = res
	return res


## Shows `wid` (a Game.WEAPONS id) in her hands; "" or a weapon without hand data hides it.
func set_weapon(wid: String) -> void:
	weapon = wid
	if _spr == null:
		return
	for w in _wspr:
		w.queue_free()
	_wspr.clear()
	var texs: Array = _data.get("hand_art", {}).get(wid, [])
	if texs.is_empty():
		_show_weapon()
		return
	if _wback == null:
		_wback = Node2D.new()
		_wfront = Node2D.new()
		add_child(_wback)
		move_child(_wback, _spr.get_index())
		add_child(_wfront)
	for t in texs:
		for layer in [_wback, _wfront]:
			var ws := Sprite2D.new()
			ws.texture = t
			ws.centered = false
			ws.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
			ws.material = _spr.material
			ws.self_modulate = tint
			ws.visible = false
			layer.add_child(ws)
			_wspr.append(ws)
	_apply_scale()
	_show_weapon()


func _show_weapon() -> void:
	if _wspr.is_empty():
		return
	var per: Dictionary = _data["hands"].get(current, {})
	var dirs: Array = per.get(weapon, [])
	var grips: Array = []
	if dir_index < dirs.size():
		var frames: Array = dirs[dir_index]
		if not frames.is_empty():
			grips = frames[mini(frame, frames.size() - 1)]
	for gi in _wspr.size() >> 1:
		var back: Sprite2D = _wspr[gi * 2]
		var front: Sprite2D = _wspr[gi * 2 + 1]
		if gi >= grips.size():
			back.visible = false
			front.visible = false
			continue
		var g: Array = grips[gi]
		var on_top: bool = g[1]
		var s: Sprite2D = front if on_top else back
		s.transform = g[0]
		s.visible = true
		(back if on_top else front).visible = false


func has_anim(anim: String) -> bool:
	return not _data.is_empty() and _data["anims"].has(anim)


func play(anim: String, restart := false) -> void:
	if _data.is_empty():
		return
	if anim == current and not restart:
		return
	if not _data["anims"].has(anim):
		# graceful fallbacks between hero/enemy naming
		var alt := {"move": "run", "run": "move", "windup": "attack1", "cast": "attack", "charge": "move", "special": "attack3"}
		if alt.has(anim) and _data["anims"].has(alt[anim]):
			anim = alt[anim]
		else:
			return
	current = anim
	_fit = 1.0
	_anim = _data["anims"][anim]
	_t = 0.0
	frame = 0
	_done = false
	_show()
	_fire_events(-1, 0)


## play an anim stretched/squeezed to last `seconds` (e.g. an AI windup of variable length).
func play_timed(anim: String, seconds: float, restart := true) -> void:
	play(anim, restart)
	var n := get_anim_length(current)
	if seconds > 0.01 and n > 0.0:
		_fit = n / seconds


## Holds a pose: shows `anim` frozen at frame index f (a wind-up held while a charge builds).
func pose(anim: String, f: int) -> void:
	if current != anim:
		play(anim, true)
	if _anim.is_empty():
		return
	f = clampi(f, 0, int(_anim["n"]) - 1)
	_t = float(f)
	_done = true # stop advancing until the next play()
	if f != frame:
		frame = f
		_show()


## hero.gd helper: state ("idle","run","attack","dash","special","hurt","downed") + combo counter.
## hero.gd increments combo BEFORE acting, so combo 1 -> attack1, 2 -> attack2, 0 -> attack3 (finisher).
func play_hero_state(state: String, combo: int) -> void:
	match state:
		"attack":
			play("attack%d" % (3 if combo == 0 else combo))
		"downed", "dead":
			play("death")
		_:
			play(state)


## enemy.gd helper: packed state code -> anim. Windups can be fitted to the AI's windup length.
func play_enemy_state(code: int, windup_seconds := 0.0) -> void:
	if code < 0 or code >= ENEMY_STATE_ANIM.size():
		return
	var a: String = ENEMY_STATE_ANIM[code]
	if a == "":
		if (current == "attack" or current == "cast" or current == "charge") and not _done:
			return
		a = "idle"
	if a == "windup" and windup_seconds > 0.0:
		if current != "windup":
			play_timed("windup", windup_seconds)
		return
	play(a)


func set_facing(dir: Vector2) -> void:
	if dir.length_squared() < 0.0001:
		return
	_facing = dir
	# screen dir -> ground dir -> yaw (0 = facing camera / screen-down, 90 = screen-right)
	var yaw := atan2(dir.x, dir.y / ISO_SIN)
	var oct := int(roundf(yaw / (PI * 0.25)))   # -4..4
	var m := oct < 0
	var di := absi(oct)
	if di == 4:
		m = false
	if di != dir_index or m != mirrored:
		dir_index = di
		mirrored = m
		_apply_scale()
		_show()


func get_facing() -> Vector2:
	return _facing


func set_speed_scale(s: float) -> void:
	speed_scale = s


func get_anim_length(anim: String) -> float:
	if _data.is_empty() or not _data["anims"].has(anim):
		return 0.0
	var a: Dictionary = _data["anims"][anim]
	return float(a["n"]) / maxf(float(a["fps"]), 0.001)


## frame index (0-based) of a named event such as "hit", or -1
func get_event_frame(anim: String, event_name: String) -> int:
	if _data.is_empty() or not _data["anims"].has(anim):
		return -1
	var ev: Dictionary = _data["anims"][anim]["events"]
	var best := -1
	for k in ev:
		if String(ev[k]) == event_name and (best < 0 or int(k) < best):
			best = int(k)
	return best


## seconds from anim start until the named event fires, or -1
func get_event_time(anim: String, event_name: String) -> float:
	var f := get_event_frame(anim, event_name)
	if f < 0:
		return -1.0
	return float(f) / maxf(float(_data["anims"][anim]["fps"]), 0.001)


func is_playing_done() -> bool:
	return _done


## visual height of the standing character in px (after scaling)
func get_scale_factor() -> float:
	return _scale


func _process(delta: float) -> void:
	if _anim.is_empty() or _done:
		return
	_t += delta * speed_scale * _fit * float(_anim["fps"])
	var n: int = _anim["n"]
	var f := int(_t)
	if f >= n:
		if _anim["loop"]:
			_t = fmod(_t, float(n))
			f = int(_t)
			if f != frame:
				_fire_events(-1, f)
		else:
			f = n - 1
			_done = true
	if f != frame:
		var prev := frame
		frame = f
		_show()
		_fire_events(prev, f)
	if _done:
		anim_finished.emit(current)


func _fire_events(prev: int, now: int) -> void:
	var ev: Dictionary = _anim["events"]
	if ev.is_empty():
		return
	for k in range(prev + 1, now + 1):
		if ev.has(k):
			anim_event.emit(ev[k])


func _show() -> void:
	if _spr == null or _anim.is_empty():
		return
	var rects: Array = _anim["rects"][dir_index]
	if rects.is_empty():
		return
	var f := mini(frame, rects.size() - 1)
	var pg: int = _anim["pages"][dir_index][f]
	var tex: Texture2D = _data["tex"][pg]
	if _spr.texture != tex:
		_spr.texture = tex
	_spr.region_rect = rects[f]
	_spr.offset = _anim["offs"][dir_index][f]
	_show_weapon()


func _apply_scale() -> void:
	if _spr:
		_spr.scale = Vector2(-_scale if mirrored else _scale, _scale)
		if _wback:
			_wback.scale = _spr.scale
			_wfront.scale = _spr.scale


func _apply_flash() -> void:
	if _spr == null:
		return
	if flash <= 0.0:
		if _spr.material != _shared_mat:
			_spr.material = _shared_mat
			for w in _wspr:
				w.material = _shared_mat
		return
	if _own_mat == null:
		_own_mat = ShaderMaterial.new()
		_own_mat.shader = _shader
	_own_mat.set_shader_parameter("flash", flash)
	_own_mat.set_shader_parameter("flash_color", flash_color)
	if _spr.material != _own_mat:
		_spr.material = _own_mat
		for w in _wspr:
			w.material = _own_mat
