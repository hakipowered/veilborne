class_name Story
extends RefCounted
## All narrative text for Veilborne. Static data only; safe to use from any script.
## Line format everywhere: {"speaker": <id in SPEAKERS>, "text": String}

const SPEAKERS := {
	"kaela": {"name": "Kaela Ashveil", "color": Color(1.0, 0.52, 0.2), "portrait": "res://art/kaela.png"},
	"liora": {"name": "Liora Moonbrand", "color": Color(0.7, 0.84, 1.0), "portrait": "res://art/liora.png"},
	"ysolde": {"name": "Matron Ysolde", "color": Color(0.55, 0.95, 0.85), "portrait": "res://art/ysolde.png"},
	"regent": {"name": "The Hollow Regent", "color": Color(0.82, 0.62, 1.0), "portrait": "res://art/regent.png"},
	"oriel": {"name": "Oriel, Ember Queen", "color": Color(1.0, 0.45, 0.15), "portrait": ""},
	"vessa": {"name": "Vessa of Storms", "color": Color(0.45, 0.75, 1.0), "portrait": ""},
	"mireth": {"name": "Mireth of Tides", "color": Color(0.2, 0.85, 0.7), "portrait": ""},
	"sable": {"name": "Sable of Thorns", "color": Color(0.75, 0.3, 0.85), "portrait": ""},
	"narrator": {"name": "", "color": Color(0.95, 0.85, 0.6), "portrait": ""},
}

const INTRO := [
	{"speaker": "narrator", "text": "Above, the sky-city of Aurelith. Below, the drowned Undervault. Between them, the Veil: a shimmering skin of starlight that kept the living and the lost apart."},
	{"speaker": "narrator", "text": "Then a deposed king who refused to die tore it open. Now the Hollow Regent sits in the deep and drinks Aurelith's stars, one by one."},
	{"speaker": "ysolde", "text": "Oh, visitors! Living ones, even. Mind the candles, they're older than your grandmothers. Welcome to the Sanctum, the last dry room above the Gilded Catacombs."},
	{"speaker": "kaela", "text": "Kaela Ashveil. Ember-knight. Formerly of the Solar Guard, until they decided my temper was a fire hazard."},
	{"speaker": "liora", "text": "Liora Moonbrand. Sworn blade of the Moon-Oracle, who vanished the night the Veil broke. I intend to ask the Regent where she went. Firmly."},
	{"speaker": "ysolde", "text": "A disgraced firebrand and a widow of the moon. How wonderfully doomed. I'm Matron Ysolde, keeper of this place. Ghost, archivist, excellent listener."},
	{"speaker": "ysolde", "text": "Here is the arrangement. You descend. The Catacombs kill you. The Veil, being torn, can't take you, so it spits you back here to me. Every time."},
	{"speaker": "kaela", "text": "So dying is more of a... strongly worded suggestion."},
	{"speaker": "ysolde", "text": "Precisely. Bring back Veil Shards and I'll bind them into vows that make you harder to kill. The Four Wardens will lend you their gifts as well, if you flatter them."},
	{"speaker": "liora", "text": "Then we go down, we come back, and we go down again, until the Regent runs out of crown before we run out of stubbornness."},
	{"speaker": "kaela", "text": "Try to keep up, Moonbrand."},
	{"speaker": "liora", "text": "I'll be the one carrying you home, Ashveil. Again."},
]

const PRE_BOSS := [
	{"speaker": "regent", "text": "Little lights. You came all this way down to be swallowed. How considerate."},
	{"speaker": "liora", "text": "Where is the Moon-Oracle? You took her the night you tore the Veil."},
	{"speaker": "regent", "text": "I took everything that night. Kingdoms forget their kings. I simply declined to be forgotten."},
	{"speaker": "kaela", "text": "Funny. I'm about to make you very memorable."},
	{"speaker": "regent", "text": "Then burn bright, ember-girl. Bright things are the sweetest to drink."},
]

const VICTORY := [
	{"speaker": "regent", "text": "No... the stars were mine. I wore them. I was owed..."},
	{"speaker": "liora", "text": "You were owed a quiet grave, Regent. Consider this the overdue delivery."},
	{"speaker": "kaela", "text": "Look up. The Veil's knitting itself back together. I can see Aurelith's lights again."},
	{"speaker": "ysolde", "text": "Back so soon, and on your own feet? I nearly dropped my ledger. I've written 'victory' in the margin. In gold ink. Don't let it go to your heads."},
	{"speaker": "liora", "text": "He'll come back. Kings like that always find the crack."},
	{"speaker": "ysolde", "text": "Then the two of you will be waiting. And I'll put the kettle on."},
	{"speaker": "kaela", "text": "The kettle's a ghost too, isn't it."},
	{"speaker": "ysolde", "text": "The tea is excellent and entirely imaginary. Now, sit. Tell me everything."},
]

const DEATH_LINES := [
	"There you are. Slightly less alive than when you left. Sit, I'll fetch a blanket.",
	"The Catacombs send their regards. And your boots. Separately.",
	"Back already? I'd barely started missing you.",
	"Another chapter for the ledger. I'm calling this one 'Overconfidence, Part Nine'.",
	"Hush now, the Veil spat you out gently this time. Mostly gently.",
	"You fought beautifully. Briefly, but beautifully.",
	"Death looks good on you, dear. Don't make a habit of it. Well. More of one.",
	"Every fall teaches the stairs your name. Next time they'll be afraid of you.",
]

const YSOLDE_CHATTER := [
	"I was the Royal Archivist, once. I catalogued the Regent's coronation. Awful speech. Far too many adjectives.",
	"The Wardens are vain, all four of them. Compliment Oriel's fire and she'll give you anything.",
	"Vessa and Mireth haven't spoken in three centuries. Something about a rainstorm and a borrowed tide.",
	"Sable of Thorns sent you a rose. It bit me. I think that means she likes you.",
	"Spend your shards, darling. Hoarding is for dragons and accountants, and you are neither.",
	"You two bicker like an old married couple. I mean that as the highest compliment an archivist can give.",
	"The Undervault used to be a garden, you know. Before the drowning. I still dream of the lilies.",
	"Aurelith loses a star every night the Veil stays torn. I've stopped counting. You shouldn't.",
	"If you see my reading glasses down there, they're probably haunted. Bring them anyway.",
	"I'd come with you, but I'm bound to these walls. Also I'm dreadful with a sword. I tried once. The sword won.",
]

const WARDEN_GREETINGS := {
	"oriel": [
		"Kneel, little spark. Oriel, Ember Queen, has decided you may burn on my behalf.",
		"Ah, ash on your boots and fire in your eyes. Take my flame and make the dark regret its manners.",
	],
	"vessa": [
		"You walk slower than thunder, mortal. Let Vessa of Storms fix that.",
		"The sky remembers who tore it. Carry my lightning down to him, and do be loud about it.",
	],
	"mireth": [
		"Shh. The tide brought you to me. Mireth of Tides does not turn away the drowning.",
		"Every wound closes the way the sea closes over a stone. Let me show you how.",
	],
	"sable": [
		"Oh, you're pretty when you bleed. Sable of Thorns offers you a gift. It has teeth.",
		"Every rose has thorns, sweetling. I simply skipped the rose. Take them.",
	],
}

static func speaker(id: String) -> Dictionary:
	return SPEAKERS.get(id, {"name": id.capitalize(), "color": Color(0.95, 0.85, 0.6), "portrait": ""})

static func warden_line(patron_id: String) -> String:
	var arr: Array = WARDEN_GREETINGS.get(patron_id, [])
	if arr.is_empty():
		return ""
	return arr[randi() % arr.size()]

static func death_line() -> String:
	return DEATH_LINES[randi() % DEATH_LINES.size()]

static func chatter_line() -> String:
	return YSOLDE_CHATTER[randi() % YSOLDE_CHATTER.size()]

## Convenience: a one-line dialogue array for play_dialogue().
static func one(speaker_id: String, text: String) -> Array:
	return [{"speaker": speaker_id, "text": text}]
