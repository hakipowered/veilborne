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
		"name": "Liora Moonbrand", "title": "the Moonlit Blade", "weapon": "twin",
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
	hero_runtime.clear()
	data["runs"] += 1
	save_slot()

func end_run(victory: bool) -> int:
	var mult := 1.0 + 0.2 * meta_rank("fortune")
	var earned := int(round((run_shards + run_room * 4 + (40 if victory else 0)) * mult))
	data["shards"] += earned
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
