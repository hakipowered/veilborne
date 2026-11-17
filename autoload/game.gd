extends Node
## Global game state: heroes, boons, meta progression and save slots.

const SLOT_COUNT := 3
const SAVE_DIR := "user://saves"

const HEROES := {
	"kaela": {
		"name": "Kaela Ashveil", "title": "the Ember Duelist", "weapon": "spear",
		"outfit": Color(0.78, 0.16, 0.16), "trim": Color(1.0, 0.78, 0.3),
		"hair": Color(0.98, 0.45, 0.12), "skin": Color(0.95, 0.76, 0.62),
		"speed": 265.0, "hp": 100, "attack": 14, "special": 30,
	},
	"liora": {
		"name": "Liora Ashveil", "title": "the Moonlit Blade", "weapon": "twin",
		"outfit": Color(0.22, 0.24, 0.62), "trim": Color(0.75, 0.88, 1.0),
		"hair": Color(0.88, 0.9, 1.0), "skin": Color(0.62, 0.43, 0.32),
		"speed": 290.0, "hp": 85, "attack": 9, "special": 24,
	},
}

## Patrons are original "Wardens" of the Veil who grant boons.
const PATRONS := {
	"oriel": {"name": "Oriel, Ember Queen", "color": Color(1.0, 0.45, 0.15)},
	"vessa": {"name": "Vessa of Storms", "color": Color(0.45, 0.75, 1.0)},
	"mireth": {"name": "Mireth of Tides", "color": Color(0.2, 0.85, 0.7)},
	"sable": {"name": "Sable of Thorns", "color": Color(0.75, 0.3, 0.85)},
}

## stat: which hero stat it modifies; value: per-rarity amount.
const BOONS := [
	{"id": "ember_strike", "patron": "oriel", "name": "Ember Strike", "desc": "Attacks deal +%d%% damage.", "stat": "attack_mult", "values": [25, 40, 60]},
	{"id": "kindle", "patron": "oriel", "name": "Kindle", "desc": "Attacks burn foes for %d damage/sec.", "stat": "burn", "values": [6, 10, 15]},
	{"id": "flare_cast", "patron": "oriel", "name": "Solar Flare", "desc": "Special deals +%d%% damage.", "stat": "special_mult", "values": [40, 65, 100]},
	{"id": "thunder_step", "patron": "vessa", "name": "Thunder Step", "desc": "Dash strikes nearby foes for %d.", "stat": "dash_shock", "values": [15, 25, 40]},
	{"id": "chain_arc", "patron": "vessa", "name": "Chain Arc", "desc": "Hits arc lightning to %d extra foes.", "stat": "chain", "values": [1, 2, 3]},
	{"id": "gale_feet", "patron": "vessa", "name": "Gale Feet", "desc": "Move +%d%% faster.", "stat": "speed_mult", "values": [12, 20, 30]},
	{"id": "tidal_heart", "patron": "mireth", "name": "Tidal Heart", "desc": "+%d max health (and heal it).", "stat": "max_hp_bonus", "values": [20, 35, 55]},
	{"id": "undertow", "patron": "mireth", "name": "Undertow", "desc": "Heal %d health per kill.", "stat": "lifesteal", "values": [2, 4, 6]},
	{"id": "riptide", "patron": "mireth", "name": "Riptide", "desc": "Special knocks foes back and gains +%d%% size.", "stat": "special_size", "values": [30, 50, 80]},
	{"id": "thorn_crit", "patron": "sable", "name": "Thorned Kiss", "desc": "+%d%% critical hit chance.", "stat": "crit", "values": [10, 18, 28]},
	{"id": "briar_ward", "patron": "sable", "name": "Briar Ward", "desc": "Take %d%% less damage.", "stat": "armor", "values": [10, 18, 25]},
	{"id": "second_dash", "patron": "sable", "name": "Shadow Step", "desc": "+%d dash charge.", "stat": "dash_charges", "values": [1, 1, 2]},
]
## ---------------------------------------------------------------- weapons
## Weapons are separate from the heroine: any heroine can carry any weapon.
## Damage, timing and the special's shape come from here; the heroine sets health and speed.
## special_time: whole special pose; special_hit: when the effect is released / lands (anim hit frame is fitted to it).
## Each weapon has 3 aspects (forms). Aspect 0 is free; others are bought with Veil Shards (Game.unlock_aspect).
## Aspect "mods" add into hero stats (same keys as boons / forge, see hero.gd recompute_stats).
const WEAPONS := {
	"spear": {
		"name": "Emberlance", "kind": "Spear", "icon": "weapon_spear", "color": Color(1.0, 0.55, 0.2),
		"desc": "Long thrusts, a three-hit combo, and a leaping slam at the aimed point.",
		"attack": 14.0, "special": 32.0, "cd": 0.32, "reach": 125.0, "arc": 42.0, "lunge": 260.0,
		"special_cd": 2.6, "special_time": 0.62, "special_hit": 0.42, "special_name": "Ember Leap",
		"swing": "swing_spear", "cast": "special_ember",
		"aspects": [
			{"name": "Aspect of Cinders", "desc": "The lance as it was forged. Balanced reach and fire.", "cost": 0, "mods": {}},
			{"name": "Aspect of the Comet", "desc": "Ember Leap flies 35% farther and its blast is 30% wider.", "cost": 40, "mods": {"w_range": 35, "w_area": 30}},
			{"name": "Aspect of the Pyre", "desc": "Every strike sets foes ablaze, and the leap leaves burning ground.", "cost": 80, "mods": {"burn": 6, "w_pool": 12}},
		],
	},
	"twin": {
		"name": "Moonfang Blades", "kind": "Twin Blades", "icon": "weapon_twin", "color": Color(0.7, 0.85, 1.0),
		"desc": "Fast wide slashes. The special hurls a crescent that whirls at the aimed point.",
		"attack": 9.0, "special": 26.0, "cd": 0.2, "reach": 100.0, "arc": 75.0, "lunge": 200.0,
		"special_cd": 2.6, "special_time": 0.5, "special_hit": 0.33, "special_name": "Crescent Throw",
		"swing": "swing_blades", "cast": "special_moon",
		"aspects": [
			{"name": "Aspect of Moonfall", "desc": "Swift and true. No twist.", "cost": 0, "mods": {}},
			{"name": "Aspect of Eclipse", "desc": "Throw two crescents at once, and +10% critical chance.", "cost": 40, "mods": {"w_multi": 1, "crit": 10}},
			{"name": "Aspect of Tidewane", "desc": "+1 dash charge, and every dash slashes foes it passes.", "cost": 80, "mods": {"dash_charges": 1, "w_dash_strike": 20}},
		],
	},
	"bow": {
		"name": "Starwhisper Bow", "kind": "Bow", "icon": "weapon_bow", "color": Color(1.0, 0.9, 0.55),
		"desc": "Tap to loose an arrow, hold to draw a piercing charged shot. The special rains a volley on the aimed point.",
		"attack": 20.0, "special": 22.0, "cd": 0.25, "reach": 0.0, "arc": 0.0, "lunge": 0.0,
		"special_cd": 2.4, "special_time": 0.5, "special_hit": 0.33, "special_name": "Starfall Volley",
		"swing": "swing_blades", "cast": "special_moon",
		"aspects": [
			{"name": "Aspect of the Huntress", "desc": "Steady draw, steady aim. No twist.", "cost": 0, "mods": {}},
			{"name": "Aspect of Starfall", "desc": "The volley falls on a 40% wider area and lands one more wave.", "cost": 40, "mods": {"w_area": 40, "w_pulses": 1}},
			{"name": "Aspect of the Gale", "desc": "Draw 35% faster, and fully drawn shots pierce every foe.", "cost": 80, "mods": {"w_charge": 35, "w_pierce": 20}},
		],
	},
	"shield": {
		"name": "Aegis of Dawn", "kind": "Shield", "icon": "weapon_shield", "color": Color(1.0, 0.8, 0.4),
		"desc": "Heavy bashes; the third strike is a charging rush. The special throws the shield at the aimed point.",
		"attack": 15.0, "special": 28.0, "cd": 0.33, "reach": 105.0, "arc": 60.0, "lunge": 180.0,
		"special_cd": 2.6, "special_time": 0.48, "special_hit": 0.3, "special_name": "Aegis Throw",
		"swing": "swing_spear", "cast": "special_ember",
		"aspects": [
			{"name": "Aspect of the Bulwark", "desc": "Thrown shield ricochets between foes and returns. You take 10% less damage.", "cost": 0, "mods": {"armor": 10}},
			{"name": "Aspect of Rebound", "desc": "The thrown shield ricochets to 2 more foes.", "cost": 40, "mods": {"w_ricochet": 2}},
			{"name": "Aspect of the Bastion", "desc": "The thrown shield lodges at the aimed point, spinning for 4 s and grinding all around it, then returns.", "cost": 80, "mods": {"w_anchor": 4.0}},
		],
	},
	"scythe": {
		"name": "Gravechain Scythe", "kind": "Chain Scythe", "icon": "weapon_scythe", "color": Color(0.78, 0.5, 1.0),
		"desc": "Sweeping arcs on a long chain; the finisher yanks foes in. The special hurls a vortex that drags enemies to the aimed point.",
		"attack": 12.0, "special": 12.0, "cd": 0.4, "reach": 150.0, "arc": 150.0, "lunge": 120.0,
		"special_cd": 3.0, "special_time": 0.52, "special_hit": 0.34, "special_name": "Reaping Vortex",
		"swing": "swing_blades", "cast": "special_moon",
		"aspects": [
			{"name": "Aspect of the Gravewarden", "desc": "Wide reaping arcs. No twist.", "cost": 0, "mods": {}},
			{"name": "Aspect of the Tollkeeper", "desc": "Every hit drags foes toward you, and kills heal 2.", "cost": 40, "mods": {"w_yank": 1, "lifesteal": 2}},
			{"name": "Aspect of the Hollow Moon", "desc": "The vortex ends in a detonation for double damage on a 30% wider area.", "cost": 80, "mods": {"w_detonate": 100, "w_area": 30}},
		],
	},
}
const WEAPON_ORDER := ["spear", "twin", "bow", "shield", "scythe"]

## In-run weapon upgrades from the Forge reward. Stored per hero in boons["_forge"] = {id: {level, rarity}}.
const FORGE := [
	{"id": "spear_echo", "weapon": "spear", "name": "Echo Leap", "desc": "Ember Leap slams a second time for %d%% damage.", "stat": "w_twice", "values": [50, 75, 100]},
	{"id": "spear_comet", "weapon": "spear", "name": "Comet Thrust", "desc": "Each dash ends in a spear thrust for %d damage.", "stat": "w_dash_strike", "values": [18, 28, 40]},
	{"id": "spear_haft", "weapon": "spear", "name": "Long Haft", "desc": "Thrusts reach %d%% farther.", "stat": "w_reach", "values": [15, 25, 40]},
	{"id": "spear_cinder", "weapon": "spear", "name": "Trail of Cinders", "desc": "Ember Leap leaves burning ground (%d damage/sec).", "stat": "w_pool", "values": [10, 16, 24]},
	{"id": "twin_wane", "weapon": "twin", "name": "Lingering Moon", "desc": "The crescent whirls %d%% longer.", "stat": "w_whirl", "values": [40, 70, 100]},
	{"id": "twin_home", "weapon": "twin", "name": "Homeward Crescent", "desc": "The crescent flies back to you, cutting for %d%% damage.", "stat": "w_return", "values": [60, 90, 130]},
	{"id": "twin_step", "weapon": "twin", "name": "Moonlit Step", "desc": "Dashing slashes foes you pass for %d.", "stat": "w_dash_strike", "values": [14, 22, 32]},
	{"id": "twin_quick", "weapon": "twin", "name": "Quickened Edges", "desc": "Attack %d%% faster.", "stat": "w_speed", "values": [12, 20, 30]},
	{"id": "bow_pierce", "weapon": "bow", "name": "Piercing Fletch", "desc": "Arrows pierce %d more foes.", "stat": "w_pierce", "values": [1, 2, 3]},
	{"id": "bow_split", "weapon": "bow", "name": "Split Shot", "desc": "Fully drawn shots split into %d extra arrows.", "stat": "w_split", "values": [2, 2, 4]},
	{"id": "bow_draw", "weapon": "bow", "name": "Quick Draw", "desc": "Draw %d%% faster.", "stat": "w_charge", "values": [25, 40, 60]},
	{"id": "bow_rain", "weapon": "bow", "name": "Endless Rain", "desc": "The volley lands %d more waves.", "stat": "w_pulses", "values": [1, 2, 3]},
	{"id": "shield_rebound", "weapon": "shield", "name": "Rebound Rim", "desc": "The thrown shield ricochets to %d more foes.", "stat": "w_ricochet", "values": [1, 2, 3]},
	{"id": "shield_anchor", "weapon": "shield", "name": "Anchored Aegis", "desc": "The thrown shield lodges at the aimed point and spins there for %.1f s.", "stat": "w_anchor", "values": [2.5, 3.5, 4.5]},
	{"id": "shield_rush", "weapon": "shield", "name": "Vanguard Rush", "desc": "The rushing third strike deals +%d%% damage and goes farther.", "stat": "w_rush", "values": [40, 70, 100]},
	{"id": "shield_guard", "weapon": "shield", "name": "Sunlit Guard", "desc": "Take %d%% less damage.", "stat": "armor", "values": [6, 10, 15]},
	{"id": "scythe_chain", "weapon": "scythe", "name": "Longer Chain", "desc": "Sweeps reach %d%% farther.", "stat": "w_reach", "values": [15, 25, 40]},
	{"id": "scythe_hook", "weapon": "scythe", "name": "Hooked Edge", "desc": "Every sweep drags foes toward you (+%d pull).", "stat": "w_yank", "values": [1, 1, 2]},
	{"id": "scythe_maw", "weapon": "scythe", "name": "Hungry Maw", "desc": "The vortex lasts %d%% longer and pulls harder.", "stat": "w_whirl", "values": [40, 70, 100]},
	{"id": "scythe_soul", "weapon": "scythe", "name": "Soulreap", "desc": "Heal %d for each foe the vortex catches.", "stat": "w_soul", "values": [1, 2, 3]},
]
## Rewards offered on the exits of a cleared chamber (granted when the NEXT chamber is cleared).
const REWARDS := {
	"boon": {"name": "Warden's Boon", "icon": "reward_boon", "color": Color(0.85, 0.6, 1.0), "weight": 34},
	"forge": {"name": "Forge", "icon": "reward_forge", "color": Color(1.0, 0.6, 0.25), "weight": 26},
	"heal": {"name": "Healing Chalice", "icon": "reward_heal", "color": Color(1.0, 0.35, 0.4), "weight": 14},
	"shards": {"name": "Veil Shards", "icon": "shard", "color": Color(0.6, 0.85, 1.0), "weight": 14},
	"gold": {"name": "Gilded Coin", "icon": "reward_gold", "color": Color(1.0, 0.85, 0.35), "weight": 12},
}
const REWARD_HEAL_FRAC := 0.35
const REWARD_SHARDS := 15
const REWARD_GOLD := 40

const RARITY_NAMES := ["Common", "Rare", "Epic"]
const RARITY_COLORS := [Color(0.85, 0.85, 0.85), Color(0.35, 0.6, 1.0), Color(0.8, 0.4, 1.0)]

## Meta progression bought at the Sanctum with Veil Shards.
const META := {
	"vitality": {"name": "Vow of Vitality", "desc": "+10 max health per rank", "max": 5, "cost": [15, 30, 50, 80, 120]},
	"fury": {"name": "Vow of Fury", "desc": "+6% damage per rank", "max": 5, "cost": [20, 40, 70, 100, 150]},
	"swift": {"name": "Vow of Swiftness", "desc": "+4% move speed per rank", "max": 3, "cost": [20, 45, 80]},
	"defiance": {"name": "Vow of Defiance", "desc": "Revive once per run with 50% health", "max": 1, "cost": [60]},
	"fortune": {"name": "Vow of Fortune", "desc": "+20% shards earned per rank", "max": 3, "cost": [25, 55, 90]},
}

var mode := "solo" ## "solo" or "coop"
var slot := 0
var data := {}
## Run state shared across rooms. players: Array of {peer, local_index, hero}.
var players: Array = []
var run_room := 0
var run_seed := 0
var run_shards := 0
var hero_runtime := {} ## key -> {hp, boons} carried between rooms
var run_gold := 0 ## run currency for a future shop
## Weapon + aspect chosen before a run ("" = the heroine's default weapon).
var run_weapon := ""
var run_aspect := 0
## Chapters: the run plan (see build_run_plan), where we are, and what the story needs at the end.
const CHAPTER_FLOORS := ["catacomb", "garden", "forge", "hollow"]
const CHAPTER_BOSS_FLOORS := ["throne", "garden_boss", "forge_boss", "hollow_boss"]
const CHAPTER_NAMES := ["The Gilded Catacombs", "The Drowned Garden", "The Ember Forge", "The Hollow Throne"]
var run_plan: Array = [] ## [{floor, chapter (1..4), type: combat|elite|boss, n (1-based in chapter), count, final}]
var run_chapter := 1
var run_killer := "" ## enemy kind, boss speaker id or "trap" (StoryDB.record_run)
var run_bosses: Array = [] ## boss speaker ids beaten this run
var run_both_down := false
var chapter_rooms_override := 0 ## tests: combat rooms per chapter (0 = 6..8 from the seed)

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)

# ---------------------------------------------------------------- saves

func slot_path(m: String, s: int) -> String:
	return "%s/%s_%d.json" % [SAVE_DIR, m, s]

func default_save() -> Dictionary:
	return {
		"version": 1, "created": Time.get_datetime_string_from_system(),
		"last_played": "", "intro_seen": false, "story_chapter": 0,
		"shards": 0, "meta": {}, "runs": 0, "wins": 0, "best_room": 0,
		"last_hero": "kaela", "codex": [],
		"last_weapon": "", "last_aspect": 0, "aspects": {},
		"gold": 0, "decor": {}, ## manor hub: banked gold and Odo's renovations (scenes/hub.gd)
		# --- STORY (owned by data/story_db.gd; see StoryDB.default_progress) ---
		"story": {"flags": {}, "played": {}, "last_death_by": "", "chapter_reached": 0, "bosses_beaten": {}, "gifts": {}},
		# --- end STORY ---
	}

func peek_slot(m: String, s: int) -> Dictionary:
	var p := slot_path(m, s)
	if not FileAccess.file_exists(p):
		return {}
	var f := FileAccess.open(p, FileAccess.READ)
	var parsed = JSON.parse_string(f.get_as_text())
	return parsed if parsed is Dictionary else {}

func load_slot(m: String, s: int) -> void:
	mode = m
	slot = s
	data = peek_slot(m, s)
	if data.is_empty():
		data = default_save()
	var d := default_save()
	for k in d.keys():
		if not data.has(k):
			data[k] = d[k]
	set_loadout(String(data.get("last_weapon", "")), int(data.get("last_aspect", 0)))
	save_slot()

func save_slot() -> void:
	data["last_played"] = Time.get_datetime_string_from_system()
	var f := FileAccess.open(slot_path(mode, slot), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  "))

func delete_slot(m: String, s: int) -> void:
	var p := slot_path(m, s)
	if FileAccess.file_exists(p):
		DirAccess.remove_absolute(p)

func meta_rank(id: String) -> int:
	return int(data.get("meta", {}).get(id, 0))

func buy_meta(id: String) -> bool:
	var r := meta_rank(id)
	var def: Dictionary = META[id]
	if r >= def["max"]:
		return false
	var cost: int = def["cost"][r]
	if data["shards"] < cost:
		return false
	data["shards"] -= cost
	data["meta"][id] = r + 1
	save_slot()
	return true

# ---------------------------------------------------------------- runs

func start_run(seed_value: int) -> void:
	run_room = 0
	run_seed = seed_value
	run_shards = 0
	run_gold = 0
	run_chapter = 1
	run_killer = ""
	run_bosses = []
	run_both_down = false
	run_plan = build_run_plan(seed_value)
	hero_runtime.clear()
	data["runs"] += 1
	save_slot()

## Four chapters, each 6..8 chambers (the middle one holds an elite) and a boss hall. Same on every device.
func build_run_plan(seed_value: int) -> Array:
	var plan: Array = []
	for ci in range(4):
		var n := chapter_rooms_override
		if n <= 0:
			n = 6 + posmod(hash("chapter:%d:%d" % [seed_value, ci]), 3)
		var elite_at := n / 2
		for i in range(n):
			plan.append({"floor": CHAPTER_FLOORS[ci], "chapter": ci + 1, "type": "elite" if i == elite_at else "combat",
				"n": i + 1, "count": n + 1, "final": false})
		plan.append({"floor": CHAPTER_BOSS_FLOORS[ci], "chapter": ci + 1, "type": "boss", "n": n + 1, "count": n + 1, "final": ci == 3})
	return plan

func plan_room(idx: int) -> Dictionary:
	if run_plan.is_empty():
		run_plan = build_run_plan(run_seed)
	return run_plan[clampi(idx, 0, run_plan.size() - 1)]

func end_run(victory: bool) -> int:
	var mult := 1.0 + 0.2 * meta_rank("fortune")
	var earned := int(round((run_shards + run_room * 4 + (40 if victory else 0)) * mult))
	var sdb = load("res://data/story_db.gd")
	if sdb:
		sdb.record_run(sdb.from_save(data), victory, run_killer, run_chapter, run_bosses)
	data["shards"] += earned
	data["gold"] = int(data.get("gold", 0)) + run_gold ## gold is banked for Odo's renovations
	data["best_room"] = max(int(data["best_room"]), run_room)
	if victory:
		data["wins"] += 1
		data["story_chapter"] = max(int(data["story_chapter"]), 1)
	save_slot()
	return earned

func boon_by_id(id: String) -> Dictionary:
	for b in BOONS:
		if b["id"] == id:
			return b
	return {}

func roll_boons(rng: RandomNumberGenerator, owned: Dictionary, count := 3) -> Array:
	var pool := BOONS.duplicate()
	var out := []
	while out.size() < count and pool.size() > 0:
		var b: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var r := 0
		var roll := rng.randf()
		if roll > 0.9: r = 2
		elif roll > 0.65: r = 1
		var lvl: int = owned.get(b["id"], {}).get("level", 0)
		out.append({"id": b["id"], "rarity": r, "upgrade": lvl > 0})
	return out

func boon_text(id: String, rarity: int) -> String:
	var b := boon_by_id(id)
	return b["desc"] % b["values"][rarity]


# ---------------------------------------------------------------- weapons / aspects / forge

func default_weapon(hero_id: String) -> String:
	return String(HEROES.get(hero_id, HEROES["kaela"])["weapon"])

## Weapon for this device's player 1 (falls back to the heroine's default).
func weapon_for(hero_id: String) -> String:
	if run_weapon != "" and WEAPONS.has(run_weapon):
		return run_weapon
	return default_weapon(hero_id)

func set_loadout(weapon: String, aspect: int) -> void:
	if not WEAPONS.has(weapon):
		weapon = ""
	run_weapon = weapon
	run_aspect = aspect if weapon != "" and aspect_unlocked(weapon, aspect) else 0
	if not data.is_empty():
		data["last_weapon"] = run_weapon
		data["last_aspect"] = run_aspect

func aspect_unlocked(weapon: String, aspect: int) -> bool:
	if aspect <= 0:
		return true
	if data.is_empty():
		return false
	var a: Array = data.get("aspects", {}).get(weapon, [])
	return a.has(aspect)

func aspect_cost(weapon: String, aspect: int) -> int:
	var w: Dictionary = WEAPONS.get(weapon, {})
	var list: Array = w.get("aspects", [])
	if aspect < 0 or aspect >= list.size():
		return 0
	return int(list[aspect]["cost"])

## Spends Veil Shards to unlock an aspect. Returns true when newly unlocked.
func unlock_aspect(weapon: String, aspect: int) -> bool:
	if not WEAPONS.has(weapon) or aspect_unlocked(weapon, aspect) or data.is_empty():
		return false
	var cost := aspect_cost(weapon, aspect)
	if int(data.get("shards", 0)) < cost:
		return false
	data["shards"] = int(data["shards"]) - cost
	if not data.has("aspects") or not (data["aspects"] is Dictionary):
		data["aspects"] = {}
	var a: Array = data["aspects"].get(weapon, [])
	a.append(aspect)
	data["aspects"][weapon] = a
	save_slot()
	return true

func aspect_def(weapon: String, aspect: int) -> Dictionary:
	var list: Array = WEAPONS.get(weapon, {}).get("aspects", [])
	if list.is_empty():
		return {}
	return list[clampi(aspect, 0, list.size() - 1)]

func forge_by_id(id: String) -> Dictionary:
	for f in FORGE:
		if f["id"] == id:
			return f
	return {}

func forge_text(id: String, rarity: int) -> String:
	var f := forge_by_id(id)
	if f.is_empty():
		return ""
	return f["desc"] % f["values"][clampi(rarity, 0, 2)]

## owned: hero.boons["_forge"] (id -> {level, rarity}).
func roll_forge(rng: RandomNumberGenerator, weapon: String, owned: Dictionary, count := 3) -> Array:
	var pool := []
	for f in FORGE:
		if f["weapon"] == weapon:
			pool.append(f)
	var out := []
	while out.size() < count and pool.size() > 0:
		var f: Dictionary = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var r := 0
		var roll := rng.randf()
		if roll > 0.88: r = 2
		elif roll > 0.6: r = 1
		var lvl: int = owned.get(f["id"], {}).get("level", 0)
		out.append({"id": f["id"], "rarity": r, "upgrade": lvl > 0, "forge": true})
	return out

## Two different reward types for the exits out of chamber `room` (deterministic: same on every device).
## One exit always carries power (a boon or the forge); the other is drawn from the rest by weight.
func roll_door_rewards(room: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("doors:%d:%d" % [run_seed, room])
	var first := "forge" if rng.randf() < 0.45 else "boon"
	var out := [first]
	var total := 0
	for k in REWARDS.keys():
		if k != first:
			total += int(REWARDS[k]["weight"])
	var pick := rng.randi_range(0, total - 1)
	for k in REWARDS.keys():
		if k == first:
			continue
		pick -= int(REWARDS[k]["weight"])
		if pick < 0:
			out.append(k)
			break
	if rng.randf() < 0.5:
		out.reverse()
	return out
