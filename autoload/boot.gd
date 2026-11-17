extends Node
## Loads the newest content pack before anything else in the game is loaded.
##
## Between full releases the game updates with small content packs (.pck files
## holding only what changed since the installed APK). This autoload is first
## in the list, so its _init runs before the other autoloads' scripts are
## loaded, and the pack's files replace the APK's copies.
##
## Safety: a pack only loads if it was built for this exact APK (BASE_CODE).
## If the game fails to get past startup twice in a row with a pack, the pack
## is switched off and the game runs from the APK alone.

## Version code of the APK this file shipped in. tools/release.sh --base sets it.
const BASE_CODE := 11
const DIR := "user://packs/"
const STATE := DIR + "current.json"
const GUARD := DIR + "starting"

var pack_code := 0
var pack_name := ""

func _init() -> void:
	DirAccess.make_dir_recursive_absolute(DIR)
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
