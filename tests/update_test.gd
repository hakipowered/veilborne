extends Node
## Headless test of the in-game updater: parallel piece download, join, sha check,
## content-pack install, and Boot loading the pack on the next launch.
## Run 1: --phase=download --base=http://127.0.0.1:PORT --sha=<hex> --size=N --n=K
## Run 2: --phase=verify
func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.get("phase") == "download":
		var n := int(args["n"])
		var size := int(args["size"])
		var chunks := []
		for i in n:
			chunks.append({"url": "%s/c%d" % [args["base"], i], "size": int(args["c%d" % i])})
		var up = get_node("/root/Updater")
		up._show("9.9.9", "test", {"kind": "pack", "code": 999, "name": "9.9.9", "size": size, "sha256": args["sha"], "chunks": chunks, "url": ""})
		up._start({"kind": "pack", "code": 999, "name": "9.9.9", "size": size, "sha256": args["sha"], "chunks": chunks, "url": ""})
		var t := 0.0
		while t < 60.0:
			await get_tree().process_frame
			t += get_process_delta_time()
			if up._status.text.begins_with("Update ready") or up._status.text.begins_with("Download failed") or up._status.text.begins_with("The download"):
				break
		print("UPDATE: status=", up._status.text)
		print("UPDATE: state=", FileAccess.get_file_as_string("user://packs/current.json"))
	else:
		print("UPDATE: boot pack_code=", Boot.pack_code, " probe V=", load("res://tests/pack_probe.gd").V, " updater=", Updater.VERSION_NAME)
	get_tree().quit()
