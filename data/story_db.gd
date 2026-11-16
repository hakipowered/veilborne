extends RefCounted
## Story picker: chooses which conversation plays next, based on story progress.
## Use via preload: const StoryDB = preload("res://data/story_db.gd")
##
## progress Dictionary (lives in the save as Game.data["story"]; get it with StoryDB.from_save(Game.data)):
##   runs: int, wins: int (copied from the save), flags: {name: true}, played: {conversation_id: times},
##   last_death_by: "" | "victory" | boss id ("osric", "maren", "hollis", "regent") | enemy kind ("shade", ...) | "trap",
##   chapter_reached: int (deepest chapter ever reached, 1..4), bosses_beaten: {boss_id: times}, gifts: {item: count}
##
## Typical calls:
##   var p := StoryDB.from_save(Game.data)
##   var lines := StoryDB.next_lines("wren", p)      # marks it played; [] when nothing to say
##   Game.save_slot()
##   StoryDB.record_run(p, victory, killer_kind, chapter, ["osric", "maren"])  # after each run

const Story = preload("res://data/story.gd")
const BOSS_IDS := ["osric", "maren", "hollis", "regent"]

static func default_progress() -> Dictionary:
	return {"runs": 0, "wins": 0, "flags": {}, "played": {}, "last_death_by": "", "chapter_reached": 0,
		"bosses_beaten": {}, "gifts": {}}

## Returns the save's story block (created/filled in place), with runs/wins synced from the save.
static func from_save(save: Dictionary) -> Dictionary:
	if not (save.get("story") is Dictionary):
		save["story"] = default_progress()
	var p: Dictionary = save["story"]
	var d := default_progress()
	for k in d.keys():
		if not p.has(k) or typeof(p[k]) != typeof(d[k]):
			p[k] = d[k]
	p["runs"] = int(save.get("runs", p["runs"]))
	p["wins"] = int(save.get("wins", p["wins"]))
	return p

static func has_flag(p: Dictionary, flag: String) -> bool:
	return bool(p.get("flags", {}).get(flag, false))

static func set_flag(p: Dictionary, flag: String, value := true) -> void:
	if not (p.get("flags") is Dictionary):
		p["flags"] = {}
	if value:
		p["flags"][flag] = true
	else:
		p["flags"].erase(flag)

static func times_played(p: Dictionary, conv_id: String) -> int:
	return int(p.get("played", {}).get(conv_id, 0))

## True when every condition of a conversation holds for this progress.
static func is_available(conv: Dictionary, p: Dictionary) -> bool:
	var c: Dictionary = conv.get("cond", {})
	var runs := int(p.get("runs", 0))
	if c.has("min_runs") and runs < int(c["min_runs"]):
		return false
	if c.has("max_runs") and runs > int(c["max_runs"]):
		return false
	if c.has("min_wins") and int(p.get("wins", 0)) < int(c["min_wins"]):
		return false
	for f in c.get("flags_required", []):
		if not has_flag(p, f):
			return false
	for f in c.get("flags_excluded", []):
		if has_flag(p, f):
			return false
	var last := String(p.get("last_death_by", ""))
	if c.has("after_victory") and bool(c["after_victory"]) != (last == "victory"):
		return false
	if c.has("after_death_by"):
		var want = c["after_death_by"]
		var wants: Array = want if want is Array else [want]
		if not _death_matches(last, wants):
			return false
	if c.has("chapter_reached") and int(p.get("chapter_reached", 0)) < int(c["chapter_reached"]):
		return false
	var beaten: Dictionary = p.get("bosses_beaten", {})
	var need_b: Dictionary = c.get("boss_beaten", {})
	for b in need_b.keys():
		if int(beaten.get(b, 0)) < int(need_b[b]):
			return false
	var gifts: Dictionary = p.get("gifts", {})
	var need_g: Dictionary = c.get("gifts", {})
	for g in need_g.keys():
		if int(gifts.get(g, 0)) < int(need_g[g]):
			return false
	return true

static func _death_matches(last: String, wants: Array) -> bool:
	if last == "" or last == "victory":
		return false
	if wants.has(last):
		return true
	return wants.has("enemy") and not BOSS_IDS.has(last)

## Best conversation for an owner (resident id, "run_start", "boss_<id>" or "victory") without marking it.
## Unplayed one-shot story beats beat repeatable chatter; ties among repeatables are picked at random.
static func best(owner: String, p: Dictionary) -> Dictionary:
	var top := -2147483648
	var picks: Array = []
	for conv in Story.CONVERSATIONS:
		if conv.get("owner", "") != owner:
			continue
		var once := bool(conv.get("once", true))
		if once and times_played(p, conv["id"]) > 0:
			continue
		if not is_available(conv, p):
			continue
		var pr := int(conv.get("priority", 0))
		if pr > top:
			top = pr
			picks = [conv]
		elif pr == top:
			picks.append(conv)
	if picks.is_empty():
		return {}
	for conv in picks:
		if bool(conv.get("once", true)):
			return conv
	return picks[randi() % picks.size()]

## Best conversation for an owner, marked as played (and its flags set). {} if none.
static func next_conversation(owner: String, p: Dictionary, mark := true) -> Dictionary:
	var conv := best(owner, p)
	if mark and not conv.is_empty():
		mark_played(conv, p)
	return conv

static func mark_played(conv: Dictionary, p: Dictionary) -> void:
	if not (p.get("played") is Dictionary):
		p["played"] = {}
	p["played"][conv["id"]] = times_played(p, conv["id"]) + 1
	for f in conv.get("sets", []):
		set_flag(p, f)

## Lines of a conversation in play_dialogue() format: [{speaker, text}].
static func lines(conv: Dictionary) -> Array:
	if conv.has("scene"):
		var scr: Script = Story
		var scene = scr.get_script_constant_map().get(conv["scene"])
		if scene is Array:
			return scene
	var out: Array = []
	for l in conv.get("lines", []):
		out.append({"speaker": l[0], "text": l[1]})
	return out

## Shortcut: pick, mark and return lines for an owner. [] when there's nothing to say.
static func next_lines(owner: String, p: Dictionary) -> Array:
	var conv := next_conversation(owner, p)
	return [] if conv.is_empty() else lines(conv)

## True when an owner has an unplayed one-shot beat waiting (for a "!" marker in the hub).
static func has_new(owner: String, p: Dictionary) -> bool:
	var conv := best(owner, p)
	return not conv.is_empty() and bool(conv.get("once", true))

## Lines before a boss fight: the next story scene if any, else one random intro line.
static func boss_intro(boss_id: String, p: Dictionary) -> Array:
	var l := next_lines("boss_" + boss_id, p)
	if not l.is_empty():
		return l
	var arr: Array = Story.BOSSES.get(boss_id, {}).get("intro", [])
	return [] if arr.is_empty() else [{"speaker": boss_id, "text": arr[randi() % arr.size()]}]

## A boss's gloat when it kills a heroine.
static func boss_taunt(boss_id: String) -> String:
	var arr: Array = Story.BOSSES.get(boss_id, {}).get("taunts", [])
	return "" if arr.is_empty() else arr[randi() % arr.size()]

## A boss's last line when beaten.
static func boss_defeat(boss_id: String) -> String:
	var arr: Array = Story.BOSSES.get(boss_id, {}).get("defeat", [])
	return "" if arr.is_empty() else arr[randi() % arr.size()]

## A spoken bark (plain string). Falls back to the speaker's "greet" lines.
static func bark(speaker_id: String, context := "greet") -> String:
	return Story.warden_line(speaker_id, context)

## A narrator line (plain string). Unknown "death_*" contexts fall back to death_enemy.
static func narration(context: String) -> String:
	var arr: Array = Story.NARRATION.get(context, [])
	if arr.is_empty() and context.begins_with("death_"):
		arr = Story.NARRATION.get("death_enemy", [])
	return "" if arr.is_empty() else arr[randi() % arr.size()]

## Narration context for a heroine's death. killer: enemy kind, boss id, or "trap".
static func death_context(killer: String, coop := false, both_down := false) -> String:
	if coop:
		return "death_coop_both" if both_down else "death_coop"
	return "death_" + (killer if killer != "" else "enemy")

## Call once when a run ends. killer: what dealt the final blow ("" if unknown, ignored on victory).
static func record_run(p: Dictionary, victory: bool, killer: String, chapter: int, bosses_beaten_this_run: Array) -> void:
	p["last_death_by"] = "victory" if victory else (killer if killer != "" else "enemy")
	p["chapter_reached"] = max(int(p.get("chapter_reached", 0)), chapter)
	if not (p.get("bosses_beaten") is Dictionary):
		p["bosses_beaten"] = {}
	for b in bosses_beaten_this_run:
		p["bosses_beaten"][b] = int(p["bosses_beaten"].get(b, 0)) + 1

## Record an item handed to a character (also sets flag "gift_<item>").
static func give_gift(p: Dictionary, item: String) -> void:
	if not (p.get("gifts") is Dictionary):
		p["gifts"] = {}
	p["gifts"][item] = int(p["gifts"].get(item, 0)) + 1
	set_flag(p, "gift_" + item)
