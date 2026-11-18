extends Node
## Loads the newest content pack before anything else in the game is loaded.
##
## Between full releases the game updates with small content packs (.pck files
## holding only what changed since the installed APK). This autoload is first
## in the list, so its _init runs before the other autoloads' scripts are
## loaded, and the pack's files replace the APK's copies.
##
## Launch update (APK 18+): before loading the pack, _init asks the download
## server for a newer content pack. If one exists for this APK and is small
## enough, it is downloaded and checked right here (the splash screen stays up),
## then loaded like any other pack, so the game simply starts on the new
## version: no restart, no button. Offline, slow or big updates are skipped
## within a few seconds and left to the in-game updater (autoload/updater.gd).
##
## Safety: a pack only loads if it was built for this exact APK (BASE_CODE).
## If the game fails to get past startup twice in a row with a pack, the pack
## is switched off and the game runs from the APK alone.

## Version code of the APK this file shipped in. tools/release.sh --base sets it.
const BASE_CODE := 18
const DIR := "user://packs/"
const STATE := DIR + "current.json"
const GUARD := DIR + "starting"

var pack_code := 0
var pack_name := ""

## Download server (tools/cloudflare/worker.js). VEIL_UPDATE_URL overrides it for tests.
const SERVER := "https://veilborne-download.hakipowered.workers.dev"
const QUICK_MAX_BYTES := 48 * 1048576 ## bigger packs go through the in-game updater
const CHECK_MS := 2500                  ## version check budget
const DOWNLOAD_MS := 40000              ## whole launch-update budget

var launch_update := "" ## "" = none, else what happened (shown by the updater label / logs)

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
	_launch_update()
	var state := read_state()
	if state.is_empty():
		return
	if int(state.get("base_code", -1)) != BASE_CODE:
		clear_packs() # a new APK was installed: its own files are newer
		return
	var path := DIR + str(state.get("file", ""))
	_remove_other_packs(str(state.get("file", "")))
	if not FileAccess.file_exists(path):
		clear_packs()
		return
	var tries := 0
	if FileAccess.file_exists(GUARD):
		tries = int(FileAccess.get_file_as_string(GUARD))
	if tries >= 2:
		push_warning("Boot: content pack failed to start twice, running without it")
		clear_packs()
		return
	var g := FileAccess.open(GUARD, FileAccess.WRITE)
	if g:
		g.store_string(str(tries + 1))
		g.close()
	if ProjectSettings.load_resource_pack(path, true):
		pack_code = int(state.get("code", 0))
		pack_name = str(state.get("name", ""))
	else:
		clear_packs()

func _ready() -> void:
	# Reaching here a few seconds after launch means the pack started fine.
	get_tree().create_timer(6.0).timeout.connect(func():
		if FileAccess.file_exists(GUARD):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(GUARD)))

static func read_state() -> Dictionary:
	if not FileAccess.file_exists(STATE):
		return {}
	var d = JSON.parse_string(FileAccess.get_file_as_string(STATE))
	return d if d is Dictionary else {}

static func _remove_other_packs(keep: String) -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		if (f.ends_with(".pck") or f.ends_with(".part")) and f != keep:
			d.remove(f)

static func clear_packs() -> void:
	var d := DirAccess.open(DIR)
	if d == null:
		return
	for f in d.get_files():
		d.remove(f)

## Called by the updater once a pack is downloaded and verified.
static func install_pack(tmp_path: String, code: int, vname: String) -> bool:
	var file := "content-%d.pck" % code
	var d := DirAccess.open(DIR)
	if d == null:
		return false
	if d.rename(ProjectSettings.globalize_path(tmp_path), ProjectSettings.globalize_path(DIR + file)) != OK:
		return false
	# Older packs are removed on the next launch: the running game still reads from its pack.
	var s := FileAccess.open(STATE, FileAccess.WRITE)
	if s == null:
		return false
	s.store_string(JSON.stringify({"base_code": BASE_CODE, "code": code, "name": vname, "file": file}))
	s.close()
	if FileAccess.file_exists(GUARD):
		d.remove("starting")
	return true


# ---------------------------------------------------------------- launch update

## Version code of what will run if nothing new is installed: the current pack's, or this APK's.
static func _installed_code() -> int:
	var st := read_state()
	if int(st.get("base_code", -1)) == BASE_CODE and FileAccess.file_exists(DIR + str(st.get("file", ""))):
		return int(st.get("code", BASE_CODE))
	return BASE_CODE

func _launch_update() -> void:
	var server := OS.get_environment("VEIL_UPDATE_URL")
	if server == "":
		if OS.has_feature("editor") or DisplayServer.get_name() == "headless":
			return
		server = SERVER
	var t0 := Time.get_ticks_msec()
	var body := _http_get(server + "/version.json", t0 + CHECK_MS, "")
	if body.is_empty():
		launch_update = "offline"
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not (data is Dictionary):
		return
	var code := int(data.get("version_code", 0))
	if code <= _installed_code():
		return
	var pack = data.get("pack")
	if not (pack is Dictionary) or int(pack.get("base_code", -1)) != BASE_CODE or int(pack.get("code", 0)) != code:
		launch_update = "needs_apk"
		return
	var size := int(pack.get("size", 0))
	if size <= 0 or size > QUICK_MAX_BYTES:
		launch_update = "too_big"
		return
	var tmp := DIR + "incoming.part"
	var got := _http_get(str(pack.get("url", "")), t0 + DOWNLOAD_MS, tmp)
	if got.size() != 1 or _file_len(tmp) != size or _sha256(tmp) != str(pack.get("sha256", "")):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(tmp))
		launch_update = "failed"
		return
	if install_pack(tmp, code, str(data.get("version_name", ""))):
		launch_update = "installed %s" % str(data.get("version_name", ""))
		print("Boot: updated to ", data.get("version_name", ""), " at launch in ", Time.get_ticks_msec() - t0, " ms")

static func _file_len(path: String) -> int:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return -1
	var n := f.get_length()
	f.close()
	return n

static func _sha256(path: String) -> String:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return ""
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	while f.get_position() < f.get_length():
		hc.update(f.get_buffer(1 << 20))
	f.close()
	return hc.finish().hex_encode()

## Blocking GET (we are inside _init, before the game exists). Follows redirects.
## to_file == "": returns the body. Otherwise streams it into to_file and returns [1] on success.
## Returns an empty array on any error, non-200 status or when `deadline` (ticks ms) passes.
static func _http_get(url: String, deadline: int, to_file: String) -> PackedByteArray:
	for _hop in range(4):
		var m := RegEx.create_from_string("^(https?)://([^/:]+)(?::(\\d+))?(/.*)?$").search(url)
		if m == null:
			return PackedByteArray()
		var tls := m.get_string(1) == "https"
		var port := int(m.get_string(3)) if m.get_string(3) != "" else (443 if tls else 80)
		var path := m.get_string(4) if m.get_string(4) != "" else "/"
		var c := HTTPClient.new()
		if c.connect_to_host(m.get_string(2), port, TLSOptions.client() if tls else null) != OK:
			return PackedByteArray()
		while c.get_status() in [HTTPClient.STATUS_RESOLVING, HTTPClient.STATUS_CONNECTING]:
			c.poll()
			if Time.get_ticks_msec() > deadline:
				return PackedByteArray()
			OS.delay_msec(5)
		if c.get_status() != HTTPClient.STATUS_CONNECTED:
			return PackedByteArray()
		if c.request(HTTPClient.METHOD_GET, path, ["User-Agent: Veilborne", "Accept-Encoding: identity"]) != OK:
			return PackedByteArray()
		while c.get_status() == HTTPClient.STATUS_REQUESTING:
			c.poll()
			if Time.get_ticks_msec() > deadline:
				return PackedByteArray()
			OS.delay_msec(5)
		if not c.has_response():
			return PackedByteArray()
		var status := c.get_response_code()
		if status in [301, 302, 303, 307, 308]:
			var loc := str(c.get_response_headers_as_dictionary().get("Location", c.get_response_headers_as_dictionary().get("location", "")))
			if loc == "":
				return PackedByteArray()
			if loc.begins_with("/"):
				loc = "%s://%s%s%s" % [m.get_string(1), m.get_string(2), (":" + m.get_string(3)) if m.get_string(3) != "" else "", loc]
			url = loc
			continue
		if status != 200:
			return PackedByteArray()
		var f: FileAccess = null
		if to_file != "":
			f = FileAccess.open(to_file, FileAccess.WRITE)
			if f == null:
				return PackedByteArray()
		var out := PackedByteArray()
		while c.get_status() == HTTPClient.STATUS_BODY:
			c.poll()
			var chunk := c.read_response_body_chunk()
			if chunk.is_empty():
				if Time.get_ticks_msec() > deadline:
					if f:
						f.close()
					return PackedByteArray()
				OS.delay_msec(2)
			elif f:
				f.store_buffer(chunk)
			else:
				out.append_array(chunk)
		if f:
			f.close()
			return PackedByteArray([1])
		return out
	return PackedByteArray()
