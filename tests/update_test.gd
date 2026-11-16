extends Node
func _ready() -> void:
	var u = get_node("/root/Updater")
	u._show("9.9", "test", u.APK_URL)
	u._download(u.APK_URL)
	var t := 0.0
	while t < 240.0:
		await get_tree().create_timer(2.0).timeout
		t += 2.0
		print("status: ", u._status.text, " bar ", u._bar.value)
		if u._status.text.begins_with("Download complete") or u._status.text.begins_with("Download failed") or u._status.text.begins_with("Couldn't"):
			break
	print("file exists: ", FileAccess.file_exists(u.APK_PATH), " size ", FileAccess.get_file_as_bytes(u.APK_PATH).size() if FileAccess.file_exists(u.APK_PATH) else 0)
	get_tree().quit()
