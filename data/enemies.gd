extends RefCounted
## Enemy roster per chapter + display names. Pure data: arena/run code picks spawns from here,
## entities/enemy.gd KINDS holds the stats, entities/enemies/<brain>.gd the behaviour.
## Boss names follow docs/STORY.md (generals of the Hollow Regent).

const NAMES := {
	"shade": "Shade", "spitter": "Spitter", "brute": "Brute",
	"bogwraith": "Bog Wraith", "sporeling": "Sporeling", "thornknight": "Thorn Knight",
	"forgegolem": "Forge Golem", "cinderimp": "Cinder Imp", "hammerwarden": "Hammer Warden",
	"hollowpike": "Hollow Pike", "voidcaster": "Void Caster", "hollowchampion": "Hollow Champion",
	"gen_seneschal": "Osric the Gravekeeper",
	"gen_bloom": "Maren of the Drowned Garden",
	"gen_anvil": "Hollis the Forgemaster",
	"regent": "The Hollow Regent",
	"wisp": "Wisp",
}

## Story speaker id for each boss (Story.BOSSES / after_death_by keys).
const BOSS_SPEAKER := {"gen_seneschal": "osric", "gen_bloom": "maren", "gen_anvil": "hollis", "regent": "regent"}

## chapter -> {kinds: regular spawns (weighted equally), elites: one per later room, boss: chapter boss kind}
const CHAPTER_ENEMIES := {
	1: {"area": "The Catacombs", "kinds": ["shade", "spitter", "brute"], "elites": ["brute"], "boss": "gen_seneschal"},
	2: {"area": "The Drowned Garden", "kinds": ["bogwraith", "sporeling"], "elites": ["thornknight"], "boss": "gen_bloom"},
	3: {"area": "The Ember Forge", "kinds": ["forgegolem", "cinderimp"], "elites": ["hammerwarden"], "boss": "gen_anvil"},
	4: {"area": "The Hollow Throne", "kinds": ["hollowpike", "voidcaster"], "elites": ["hollowchampion"], "boss": "regent"},
}

## Role tags (for wave composition: mix one "front" with one "back" so rooms ask for different answers).
const ROLES := {
	"shade": "rush", "spitter": "ranged", "brute": "tank",
	"bogwraith": "rush", "sporeling": "area", "thornknight": "shield",
	"forgegolem": "tank", "cinderimp": "ranged", "hammerwarden": "area",
	"hollowpike": "area", "voidcaster": "summon", "hollowchampion": "rush",
}


static func chapter(ch: int) -> Dictionary:
	return CHAPTER_ENEMIES.get(clampi(ch, 1, 4), CHAPTER_ENEMIES[1])
