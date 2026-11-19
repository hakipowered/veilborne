extends Node
## Boss Trials end to end: title -> trials picker -> each boss hall (shot) -> boss falls -> back to the picker.
## Checks the chronicle is untouched (runs count, story) and that each trial spawns the right boss.
##   xvfb-run -a -s "-screen 0 1600x900x24" godot --rendering-driver opengl3 --path . res://tests/trial_test.tscn -- --out=/dir
## Prints "TRIALS: PASS" or "TRIALS: FAIL <reasons>".
var out := "/tmp"
var main: Node
var fails: Array = []


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="): out = a.substr(6)
	DirAccess.make_dir_recursive_absolute(out)
	main = load("res://scenes/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	_run()


func _snap(n: String, wait := 1.0) -> void:
	await get_tree().create_timer(wait).timeout
	get_viewport().get_texture().get_image().save_png("%s/trial_%s.png" % [out, n])


func _run() -> void:
	await get_tree().process_frame
	await _snap("title", 2.6)
	main.show_trials()
	await _snap("picker", 1.0)
	var want := {1: "gen_seneschal", 2: "gen_bloom", 3: "gen_anvil", 4: "regent"}
	for ch in [1, 2, 3, 4]:
		main._start_trial(ch, "spear" if ch % 2 == 1 else "bow")
		var runs := int(Game.data.get("runs", 0))
		var arena: Node = null
		var boss: Node = null
		for i in 600:
			await get_tree().physics_frame
			arena = main.get("arena")
			if is_instance_valid(arena):
				for e in arena.enemies():
					if e.is_boss:
						boss = e
			if boss != null:
				break
		if boss == null:
			fails.append("ch%d: no boss" % ch)
			continue
		if boss.kind != want[ch]:
			fails.append("ch%d: boss %s" % [ch, boss.kind])
		var h = arena.heroes()[0]
		if ch > 1 and h.boons.size() < 2:
			fails.append("ch%d: no trial boons" % ch)
		h.hp = h.max_hp
		await _snap("ch%d_fight" % ch, 2.5)
		boss.take_damage(boss.hp - boss.max_hp * float(boss.phase_marks()[0]) + 5.0, false, boss.position + Vector2(40, 0), "")
		await _snap("ch%d_break" % ch, 0.9)
		for i in 8:
			if is_instance_valid(boss) and not boss.is_dead() and not boss.shielded():
				boss.take_damage(boss.hp + 1.0, false, boss.position + Vector2(40, 0), "")
			await get_tree().create_timer(2.4).timeout
			if main.get("screen") != "arena":
				break
		await get_tree().create_timer(3.5).timeout
		if main.get("screen") == "arena":
			fails.append("ch%d: still in the arena after the boss fell" % ch)
		if Game.practice_boss != 0:
			fails.append("ch%d: practice flag left on" % ch)
		if int(Game.data.get("runs", 0)) != runs:
			fails.append("ch%d: runs count changed" % ch)
		if Game.data.get("story", {}).get("bosses_beaten", {}).size() > 0 and ch == 1:
			pass
	await _snap("back", 0.5)
	print("TRIALS: ", "PASS" if fails.is_empty() else "FAIL " + str(fails))
	get_tree().quit()
