extends CanvasLayer
## Checks the repo's downloads branch for a newer build on launch and offers a one-tap update.
## The URLs never change, so one link always installs the newest version.

const VERSION_CODE := 11
const VERSION_NAME := "0.6.1"
const REPO := "hakipowered/veilborne"
## Cloudflare Worker that serves the newest build (no size limit; see tools/cloudflare/worker.js).
const DL := "https://veilborne-download.hakipowered.workers.dev"
const MANIFEST_URL := DL + "/version.json"
const APK_URL := DL + "/Veilborne.apk"
const DOWNLOAD_PAGE := DL + "/"

const APK_PATH := "user://update.apk"

var _http: HTTPRequest
var _panel: Control
var _status: Label
var _bar: ProgressBar
var _row: HBoxContainer

func _ready() -> void:
	layer = 90
	process_mode = Node.PROCESS_MODE_ALWAYS
	var ver := Label.new()
	ver.text = "v" + VERSION_NAME
	ver.add_theme_font_size_override("font_size", 14)
	ver.add_theme_color_override("font_color", Color(1, 1, 1, 0.45))
	ver.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	ver.position += Vector2(8, -24)
	ver.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ver)
	if OS.has_feature("editor") or DisplayServer.get_name() == "headless":
		return
	_http = HTTPRequest.new()
	_http.timeout = 8.0
	_http.max_redirects = 10
	add_child(_http)
	_http.request_completed.connect(_on_manifest)
	await get_tree().create_timer(1.5).timeout
	check()

func check() -> void:
	if _http and _http.get_http_client_status() == HTTPClient.STATUS_DISCONNECTED:
		_http.request(MANIFEST_URL)

func _on_manifest(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return # offline or no release yet: never block the game
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary) or int(data.get("version_code", 0)) <= running_code():
		return
	_show(str(data.get("version_name", "?")), str(data.get("notes", "")), _plan(data))

## The version actually running: the APK's, or the content pack's if one is loaded.
## (This file is part of every pack, so VERSION_CODE already reflects the pack.)
func running_code() -> int:
	return VERSION_CODE

## Picks the smallest download that gets this install to the new version.
func _plan(data: Dictionary) -> Dictionary:
	var pack = data.get("pack")
	var boot_base: int = Boot.BASE_CODE
	if pack is Dictionary and int(pack.get("base_code", -1)) == boot_base and pack.get("chunks") is Array:
		return {"kind": "pack", "code": int(data["version_code"]), "name": str(data.get("version_name", "")),
			"size": int(pack["size"]), "sha256": str(pack.get("sha256", "")), "chunks": pack["chunks"], "url": str(pack.get("url", ""))}
	var apk = data.get("apk")
	if apk is Dictionary and apk.get("chunks") is Array:
		return {"kind": "apk", "size": int(apk["size"]), "sha256": str(apk.get("sha256", "")), "chunks": apk["chunks"], "url": str(apk.get("url", ""))}
	return {"kind": "apk", "size": int(data.get("size", 0)), "sha256": "",
		"chunks": [{"url": str(data.get("apk_url", APK_URL)), "size": int(data.get("size", 0))}], "url": ""}

static func _mb(bytes: int) -> String:
	if bytes < 1048576:
		return "%d KB" % maxi(1, bytes / 1024)
	return "%d MB" % int(round(bytes / 1048576.0))

func _show(vname: String, notes: String, plan: Dictionary) -> void:
	# Remove the previous update file once we are running something new.
	if FileAccess.file_exists(APK_PATH) and _active.is_empty():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(APK_PATH))
	if _panel and is_instance_valid(_panel):
		return
	var gold := Color(1.0, 0.82, 0.4)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.07, 0.03, 0.09, 0.97)
	sb.border_color = gold
	sb.set_border_width_all(3)
	sb.set_corner_radius_all(8)
	sb.set_content_margin_all(22)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	_panel = dim
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.add_child(center)
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(620, 0)
	center.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 14)
	p.add_child(v)
	var t := Label.new()
	t.text = "Update available: v%s" % vname
	t.add_theme_font_size_override("font_size", 30)
	t.add_theme_color_override("font_color", gold)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var n := Label.new()
	n.text = notes if notes != "" else "New improvements are ready."
	n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	n.add_theme_font_size_override("font_size", 20)
	v.add_child(n)
	var hint := Label.new()
	hint.text = "You're on v%s. Tap Update, then open the downloaded file and tap Install. Your saves are kept." % VERSION_NAME
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.add_theme_font_size_override("font_size", 16)
	hint.add_theme_color_override("font_color", Color(0.8, 0.75, 0.85))
	v.add_child(hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	v.add_child(row)
	for spec in [["Update now", true], ["Later", false]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(220, 68)
		b.add_theme_font_size_override("font_size", 24)
		var bs := sb.duplicate()
		bs.bg_color = Color(0.25, 0.12, 0.1) if spec[1] else Color(0.14, 0.08, 0.16)
		bs.set_content_margin_all(10)
		b.add_theme_stylebox_override("normal", bs)
		var hs := bs.duplicate()
		hs.bg_color = bs.bg_color.lightened(0.15)
		b.add_theme_stylebox_override("hover", hs)
		b.add_theme_stylebox_override("focus", hs)
		var go: bool = spec[1]
		b.pressed.connect(func():
			if go:
				_start(plan)
			else:
				_panel.queue_free()
				_panel = null)
		row.add_child(b)
	_row = row
	_bar = ProgressBar.new()
	_bar.custom_minimum_size = Vector2(0, 26)
	_bar.show_percentage = false
	_bar.visible = false
	v.add_child(_bar)
	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_font_size_override("font_size", 18)
	_status.visible = false
	v.add_child(_status)
	if plan["kind"] == "pack":
		hint.text = "You're on v%s. This update is only %s: tap Update now, then reopen the game. Your saves are kept." % [VERSION_NAME, _mb(plan["size"])]
	else:
		hint.text = "You're on v%s. Tap Update now: the game downloads the update (%s) and Android asks you to install it. Your saves are kept." % [VERSION_NAME, _mb(plan["size"])]

## Downloads the update in several pieces at once (much faster on phones),
## joins them, checks the result, then installs it.
const PARALLEL := 4
const TMP_DIR := "user://update_parts/"

var _plan_now: Dictionary = {}
var _queue: Array = []
var _active: Array = [] # [{req, idx}]
var _done_bytes := 0
var _failed := false
var _tries := {}

func _start(plan: Dictionary) -> void:
	_plan_now = plan
	_row.visible = false
	_bar.visible = true
	_bar.value = 0.0
	_status.visible = true
	_status.text = "Downloading update..."
	_failed = false
	_tries.clear()
	_done_bytes = 0
	for a in _active:
		a["req"].cancel_request()
		a["req"].queue_free()
	_active.clear()
	DirAccess.make_dir_recursive_absolute(TMP_DIR)
	_queue.clear()
	for i in plan["chunks"].size():
		var part := TMP_DIR + "%03d" % i
		var want := int(plan["chunks"][i].get("size", 0))
		# Keep pieces that finished before (resume after a dropped connection).
		if want > 0 and FileAccess.file_exists(part) and _file_size(part) == want:
			_done_bytes += want
			continue
		_queue.append(i)
	_pump()

func _pump() -> void:
	while not _failed and _active.size() < PARALLEL and not _queue.is_empty():
		var i: int = _queue.pop_front()
		var req := HTTPRequest.new()
		req.use_threads = true
		req.download_chunk_size = 1 << 20
		req.max_redirects = 10
		req.timeout = 0.0
		add_child(req)
		var part := TMP_DIR + "%03d" % i
		DirAccess.remove_absolute(ProjectSettings.globalize_path(part))
		req.download_file = part
		var entry := {"req": req, "idx": i}
		_active.append(entry)
		req.request_completed.connect(func(result: int, code: int, _h, _b): _on_piece(entry, result, code))
		if req.request(str(_plan_now["chunks"][i]["url"])) != OK:
			_on_piece(entry, HTTPRequest.RESULT_CANT_CONNECT, 0)
	if _active.is_empty() and _queue.is_empty() and not _failed:
		_finish()

func _on_piece(entry: Dictionary, result: int, code: int) -> void:
	_active.erase(entry)
	var req: HTTPRequest = entry["req"]
	req.queue_free()
	var i: int = entry["idx"]
	var part := TMP_DIR + "%03d" % i
	var want := int(_plan_now["chunks"][i].get("size", 0))
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not FileAccess.file_exists(part) or (want > 0 and _file_size(part) != want):
		var tries: int = _tries.get(i, 0)
		_tries[i] = tries + 1
		if tries < 2 and not _failed:
			_queue.push_front(i) # retry this piece
			_pump()
			return
		_failed = true
		for a in _active:
			a["req"].cancel_request()
		_fail()
		return
	_done_bytes += _file_size(part)
	_pump()

func _finish() -> void:
	_status.text = "Checking the download..."
	await get_tree().process_frame
	var out := APK_PATH if _plan_now["kind"] == "apk" else "user://update.pck.part"
	DirAccess.remove_absolute(ProjectSettings.globalize_path(out))
	var f := FileAccess.open(out, FileAccess.WRITE)
	if f == null:
		_fail()
		return
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	for i in _plan_now["chunks"].size():
		var part := TMP_DIR + "%03d" % i
		var src := FileAccess.open(part, FileAccess.READ)
		if src == null:
			f.close()
			_fail()
			return
		while src.get_position() < src.get_length():
			var buf := src.get_buffer(4 << 20)
			f.store_buffer(buf)
			hc.update(buf)
			await get_tree().process_frame # keep the screen responsive
		src.close()
	f.close()
	var sha: String = _plan_now.get("sha256", "")
	if sha != "" and hc.finish().hex_encode() != sha:
		_clear_parts()
		_status.text = "The download was damaged. Tap Retry."
		_fail()
		return
	_clear_parts()
	_bar.value = 100.0
	if _plan_now["kind"] == "pack":
		if Boot.install_pack(out, int(_plan_now["code"]), str(_plan_now["name"])):
			_ready_to_restart()
		else:
			_fail()
		return
	_status.text = "Download complete. Tap Install on the next screen."
	_install()

func _ready_to_restart() -> void:
	_status.text = "Update ready. Close the game and open it again to play v%s." % str(_plan_now["name"])
	_row.visible = true
	for c in _row.get_children():
		c.queue_free()
	for spec in [["Close game", true], ["Later", false]]:
		var b := Button.new()
		b.text = spec[0]
		b.custom_minimum_size = Vector2(220, 68)
		b.add_theme_font_size_override("font_size", 24)
		var quit: bool = spec[1]
		b.pressed.connect(func():
			if quit:
				get_tree().quit()
			elif _panel:
				_panel.queue_free()
				_panel = null)
		_row.add_child(b)

func _clear_parts() -> void:
	var d := DirAccess.open(TMP_DIR)
	if d:
		for fn in d.get_files():
			d.remove(fn)

static func _file_size(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n

func _install() -> void:
	# Godot opens local files through its FileProvider, so Android's package installer receives the APK.
	var err := OS.shell_open(ProjectSettings.globalize_path(APK_PATH))
	_row.visible = true
	for c in _row.get_children():
		c.queue_free()
	var again := Button.new()
	again.text = "Install"
	again.custom_minimum_size = Vector2(220, 68)
	again.add_theme_font_size_override("font_size", 24)
	again.pressed.connect(_install)
	_row.add_child(again)
	if err != OK:
		_status.text = "Couldn't open the installer. Allow Veilborne to install apps in Android settings, then tap Install."

func _fail() -> void:
	if not _status.text.begins_with("The download was damaged"):
		_status.text = "Download failed. Check your connection and tap Retry: it continues where it stopped."
	_bar.visible = false
	_row.visible = true
	for c in _row.get_children():
		c.queue_free()
	var retry := Button.new()
	retry.text = "Retry"
	retry.custom_minimum_size = Vector2(220, 68)
	retry.add_theme_font_size_override("font_size", 24)
	retry.pressed.connect(func(): _start(_plan_now))
	_row.add_child(retry)

func _process(_delta: float) -> void:
	if _bar == null or not _bar.visible or _active.is_empty():
		return
	var got := _done_bytes
	for a in _active:
		got += maxi(0, a["req"].get_downloaded_bytes())
	var total: int = maxi(1, int(_plan_now.get("size", 1)))
	_bar.value = 100.0 * got / total
	_status.text = "Downloading update... %s / %s" % [_mb(got), _mb(total)]
