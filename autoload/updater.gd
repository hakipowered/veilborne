extends CanvasLayer
## Checks the repo's downloads branch for a newer build on launch and offers a one-tap update.
## The URLs never change, so one link always installs the newest version.

const VERSION_CODE := 7
const VERSION_NAME := "0.4.0"
const REPO := "hakipowered/veilborne"
## Cloudflare Worker that serves the newest build (no size limit; see tools/cloudflare/worker.js).
const DL := "https://veilborne-download.hakipowered.workers.dev"
const MANIFEST_URL := DL + "/version.json"
const APK_URL := DL + "/Veilborne.apk"
const DOWNLOAD_PAGE := DL + "/"

const APK_PATH := "user://update.apk"

var _http: HTTPRequest
var _dl: HTTPRequest
var _panel: Control
var _status: Label
var _bar: ProgressBar
var _row: HBoxContainer
var _url := ""

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
	if not (data is Dictionary) or int(data.get("version_code", 0)) <= VERSION_CODE:
		return
	_show(str(data.get("version_name", "?")), str(data.get("notes", "")), str(data.get("apk_url", APK_URL)))

func _show(vname: String, notes: String, url: String) -> void:
	# Remove the previous update file once we are running something new.
	if FileAccess.file_exists(APK_PATH) and _dl == null:
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
				_download(url)
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
	hint.text = "You're on v%s. Tap Update now: the game downloads the update and Android asks you to install it. Your saves are kept." % VERSION_NAME

## Downloads the APK inside the game, then hands it to Android's installer.
func _download(url: String) -> void:
	_url = url
	_row.visible = false
	_bar.visible = true
	_status.visible = true
	_status.text = "Downloading update..."
	if _dl == null:
		_dl = HTTPRequest.new()
		_dl.use_threads = true
		_dl.max_redirects = 10
		_dl.timeout = 0.0
		add_child(_dl)
		_dl.request_completed.connect(_on_apk)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(APK_PATH))
	_dl.download_file = APK_PATH
	if _dl.request(url) != OK:
		_fail()

func _on_apk(result: int, code: int, _h: PackedStringArray, _b: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or code != 200 or not FileAccess.file_exists(APK_PATH):
		_fail()
		return
	_bar.value = 100.0
	_status.text = "Download complete. Tap Install on the next screen."
	_install()

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
	_status.text = "Download failed. Check your connection and try again."
	_bar.visible = false
	_row.visible = true
	for c in _row.get_children():
		c.queue_free()
	var retry := Button.new()
	retry.text = "Retry"
	retry.custom_minimum_size = Vector2(220, 68)
	retry.add_theme_font_size_override("font_size", 24)
	retry.pressed.connect(func(): _download(_url))
	_row.add_child(retry)

func _process(_delta: float) -> void:
	if _dl and _bar and _bar.visible and _dl.get_http_client_status() == HTTPClient.STATUS_BODY:
		var total := _dl.get_body_size()
		if total > 0:
			_bar.value = 100.0 * _dl.get_downloaded_bytes() / total
			_status.text = "Downloading update... %d / %d MB" % [_dl.get_downloaded_bytes() / 1048576, total / 1048576]
