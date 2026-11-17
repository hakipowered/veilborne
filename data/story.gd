class_name Story
extends RefCounted
## All narrative text for Veilborne. Static data only; safe to use from any script.
## The plain-language story bible is docs/STORY.md. Picking and progress logic lives in data/story_db.gd.
##
## Two line formats live here:
##  - Scene arrays (INTRO, PRE_BOSS, VICTORY, ENDING, EPILOGUE): [{"speaker": id, "text": String}], ready for
##    Main.play_dialogue().
##  - CONVERSATIONS use a compact form [speaker_id, text]; StoryDB.lines() turns them into the scene format.
## BARKS and NARRATION are plain strings (one spoken line each) so they can go straight to text-to-speech.

# ------------------------------------------------------------------ speakers
## voice: spec for the voice actor / TTS pass.
const SPEAKERS := {
	"kaela": {"name": "Kaela", "color": Color(1.0, 0.52, 0.2), "portrait": "res://art/ui/hero_kaela.png",
		"voice": {"gender": "female", "age": "24", "tone": "blunt, loud, quick to laugh, quick to swear", "accent": "northern English"}},
	"liora": {"name": "Liora", "color": Color(0.7, 0.84, 1.0), "portrait": "res://art/ui/hero_liora.png",
		"voice": {"gender": "female", "age": "21", "tone": "calm, dry, deadpan jokes, soft when it matters", "accent": "northern English, softer"}},
	"ysolde": {"name": "Gran Ysolde", "color": Color(0.55, 0.95, 0.85), "portrait": "res://art/ui/hero_ysolde.png",
		"voice": {"gender": "female", "age": "72", "tone": "dry, wry storyteller, brisk, hides guilt behind jokes", "accent": "Yorkshire"}},
	"teo": {"name": "Teo", "color": Color(1.0, 0.86, 0.45), "portrait": "res://art/ui/portrait_teo.png",
		"voice": {"gender": "male", "age": "9", "tone": "bright, curious, braver than he feels", "accent": "northern English"}},
	"regent": {"name": "The Hollow Regent", "color": Color(0.82, 0.62, 1.0), "portrait": "res://art/ui/hero_regent.png",
		"voice": {"gender": "male", "age": "65", "tone": "deep, tired, bitter, grief under the anger", "accent": "standard southern English"}},
	"bram": {"name": "Bram", "color": Color(0.95, 0.66, 0.38), "portrait": "res://art/ui/portrait_bram.png",
		"voice": {"gender": "male", "age": "45", "tone": "big, warm, slow, dad jokes", "accent": "Welsh"}},
	"odo": {"name": "Odo", "color": Color(0.98, 0.82, 0.3), "portrait": "res://art/ui/portrait_odo.png",
		"voice": {"gender": "male", "age": "52", "tone": "chirpy, salesy, talks fast, sad underneath", "accent": "London"}},
	"corwin": {"name": "Sergeant Corwin", "color": Color(0.6, 0.85, 0.95), "portrait": "res://art/ui/portrait_corwin.png",
		"voice": {"gender": "male", "age": "55 (ghost)", "tone": "clipped, deadpan, military, secretly kind", "accent": "crisp standard English"}},
	"wick": {"name": "Mister Wick", "color": Color(0.72, 1.0, 0.55), "portrait": "res://art/ui/portrait_wick.png",
		"voice": {"gender": "male", "age": "60s (dead, he won't say)", "tone": "cheerful, creepy, sing-song salesman, cackles", "accent": "West Country"}},
	"wren": {"name": "Wren", "color": Color(0.95, 0.5, 0.55), "portrait": "res://art/ui/portrait_wren.png",
		"voice": {"gender": "female", "age": "17", "tone": "fast, cheeky, bossy about food", "accent": "Liverpool"}},
	"osric": {"name": "Osric the Gravekeeper", "color": Color(0.75, 0.72, 0.6), "portrait": "res://art/ui/portrait_osric.png",
		"voice": {"gender": "male", "age": "70 (dead)", "tone": "nasal, fussy clerk, petty, loves rules", "accent": "prim standard English"}},
	"maren": {"name": "Maren of the Drowned Garden", "color": Color(0.35, 0.85, 0.7), "portrait": "res://art/ui/portrait_maren.png",
		"voice": {"gender": "female", "age": "44 (drowned)", "tone": "dreamy, distracted, kind, sharp about her plants", "accent": "Liverpool, softer"}},
	"hollis": {"name": "Hollis the Forgemaster", "color": Color(1.0, 0.4, 0.2), "portrait": "res://art/ui/portrait_hollis.png",
		"voice": {"gender": "male", "age": "50 (dead)", "tone": "booming, boastful, big laugh, proud", "accent": "Welsh"}},
	"emmet": {"name": "Emmet", "color": Color(0.9, 0.95, 1.0), "portrait": "res://art/ui/portrait_emmet.png",
		"voice": {"gender": "male", "age": "9 (spirit)", "tone": "gentle, a bit cheeky, unbothered", "accent": "standard southern English"}},
	"oriel": {"name": "Oriel", "color": Color(1.0, 0.45, 0.15), "portrait": "res://art/ui/warden_oriel.png",
		"voice": {"gender": "female", "age": "55 (spirit)", "tone": "booming ex-captain, bossy, loves a scrap", "accent": "Scottish"}},
	"vessa": {"name": "Vessa", "color": Color(0.45, 0.75, 1.0), "portrait": "res://art/ui/warden_vessa.png",
		"voice": {"gender": "female", "age": "22 (spirit)", "tone": "fast, chirpy, impatient, giggly", "accent": "Irish"}},
	"mireth": {"name": "Mireth", "color": Color(0.2, 0.85, 0.7), "portrait": "res://art/ui/warden_mireth.png",
		"voice": {"gender": "male", "age": "75 (spirit)", "tone": "slow, warm, worried grandad", "accent": "West Country"}},
	"sable": {"name": "Sable", "color": Color(0.75, 0.3, 0.85), "portrait": "res://art/ui/warden_sable.png",
		"voice": {"gender": "female", "age": "35 (spirit)", "tone": "low, sly, teasing, sarcastic", "accent": "London"}},
	"narrator": {"name": "", "color": Color(0.95, 0.85, 0.6), "portrait": "",
		"voice": {"gender": "female", "age": "72", "tone": "Gran Ysolde telling the tale: dry, wry, fond", "accent": "Yorkshire"}},
}

# ------------------------------------------------------------------ fixed scenes
const INTRO := [
	{"speaker": "narrator", "text": "Larkhill is a small town with a big hole in it. Folk call the hole the Hollow."},
	{"speaker": "narrator", "text": "At the bottom is the land of the dead. An old seal, the Veil, kept the dead down there. Mostly."},
	{"speaker": "ysolde", "text": "Morning, girls. You were dead. Now you're not. Have some tea before you panic."},
	{"speaker": "kaela", "text": "Gran, we went down the pit after Teo. Something stabbed me. I felt it."},
	{"speaker": "ysolde", "text": "And then you woke up in your own bed. Yes. That'll keep happening."},
	{"speaker": "liora", "text": "People don't just come back from dying, Gran."},
	{"speaker": "ysolde", "text": "Ashveils do. The dead can't keep us. Long story. Not a nice one. Later."},
	{"speaker": "kaela", "text": "The King of the Dead took our little brother. I don't care about later."},
	{"speaker": "ysolde", "text": "The Hollow Regent. He climbed out last night, grabbed Teo, went back down."},
	{"speaker": "ysolde", "text": "Bring me Veil Shards, bits of that broken seal. I'll turn them into vows: lasting strength."},
	{"speaker": "liora", "text": "And if we die again?"},
	{"speaker": "ysolde", "text": "You wake up here and I put the kettle on. Go get your brother."},
]

## Played before the Regent's room every run (arena.gd reads this by name).
const PRE_BOSS := [
	{"speaker": "regent", "text": "You again. Ysolde's girls. Stubborn, just like her."},
	{"speaker": "kaela", "text": "Give us Teo and we'll stop hitting you."},
	{"speaker": "regent", "text": "He's safe. He's fed. Somebody reads to him. That's more than your gran gave mine."},
	{"speaker": "liora", "text": "Then this won't take long. Kaela, left side."},
	{"speaker": "regent", "text": "Go home, girls. You'll wake up there anyway."},
]

## Played after the Regent falls. main.gd shows VICTORY[3] as the results-screen quote: keep it Ysolde's.
const VICTORY := [
	{"speaker": "regent", "text": "Enough. Stop. ...You hit like her. Every bit as stubborn."},
	{"speaker": "kaela", "text": "Where's Teo? Where is he?"},
	{"speaker": "teo", "text": "Kaela? Liora? I'm behind the big door! There's chains, I can't get out!"},
	{"speaker": "ysolde", "text": "And then the pit, rude as ever, sent my girls home. So close."},
	{"speaker": "liora", "text": "He's alive, Gran. He talked to us. He's alive."},
	{"speaker": "ysolde", "text": "Course he is. He's an Ashveil. We're impossible to get rid of."},
	{"speaker": "kaela", "text": "There were chains. We couldn't break them."},
	{"speaker": "ysolde", "text": "Then we find who made them. One thing at a time. Sit. Wren's made cake."},
]

const ENDING := [
	{"speaker": "regent", "text": "Stop. Just stop. I'm tired of being hit by Ysolde's family."},
	{"speaker": "liora", "text": "Then let's talk instead. We brought you something."},
	{"speaker": "regent", "text": "That's Emmet's horse. Corwin, you thief. Where did you..."},
	{"speaker": "kaela", "text": "Corwin says you used to fix bridges and hand out apples. Not snatch kids."},
	{"speaker": "regent", "text": "Emmet called the horse Captain. He wanted to be a soldier. Ridiculous boy."},
	{"speaker": "liora", "text": "Teo isn't Emmet. Keeping him here won't make Emmet any less gone."},
	{"speaker": "regent", "text": "I know. I've known for forty years. Knowing it doesn't make it stop."},
	{"speaker": "kaela", "text": "Gran's carried it the whole time too. She says sorry. She means it."},
	{"speaker": "regent", "text": "...Does she. Huh."},
	{"speaker": "teo", "text": "Mister Aldric? You can visit. Gran makes bad tea, but Wren makes great cake."},
	{"speaker": "regent", "text": "Bad tea. Some things never change."},
	{"speaker": "regent", "text": "Use the key. Yes, I know Hollis gave it to you. I know everything down here."},
	{"speaker": "kaela", "text": "What will you do now?"},
	{"speaker": "regent", "text": "Look for my son. Properly. He went on further down. I never dared follow."},
	{"speaker": "emmet", "text": "Dad? You took ages."},
	{"speaker": "regent", "text": "I know, son. I'm sorry. I'm here now."},
	{"speaker": "liora", "text": "Come on, Teo. Let's go home."},
	{"speaker": "teo", "text": "Can we get cake first?"},
]

const EPILOGUE := [
	{"speaker": "narrator", "text": "One month later. The manor has a full table, and a new roof."},
	{"speaker": "ysolde", "text": "Well. Look at that. Every chair taken."},
	{"speaker": "teo", "text": "Gran, Wren says I have to eat the green things before cake."},
	{"speaker": "wren", "text": "Wren is right. Wren is always right."},
	{"speaker": "bram", "text": "Hollis's ghost turned up at the forge. Already told me I'm doing it wrong."},
	{"speaker": "odo", "text": "Every room's fixed but Teo's. He wanted to choose the colour."},
	{"speaker": "teo", "text": "Orange. Like Kaela's face when she's angry."},
	{"speaker": "kaela", "text": "My face doesn't go orange."},
	{"speaker": "liora", "text": "It absolutely does."},
	{"speaker": "corwin", "text": "Maren's ghost has taken the garden. Nobody touch the lilies. That's an order."},
	{"speaker": "ysolde", "text": "Girls. Thank you. For bringing him home, and for putting up with an old liar."},
	{"speaker": "kaela", "text": "Still a bit mad at you. Pass the cake."},
	{"speaker": "ysolde", "text": "That's fair. That's very fair."},
	{"speaker": "teo", "text": "If something grabs me again, can you be quicker next time?"},
	{"speaker": "liora", "text": "There's no next time, Teo."},
	{"speaker": "teo", "text": "Okay. But if there is."},
]

# ------------------------------------------------------------------ bosses
## chapter: which chapter they guard. intro/taunts/defeat are single lines (random pick).
## The first meeting and the story scenes are CONVERSATIONS with owner "boss_<id>".
const BOSSES := {
	"osric": {"name": "Osric the Gravekeeper", "chapter": 1, "area": "The Catacombs",
		"intro": [
			"Name? Purpose of visit? Cause of upcoming death? Speak clearly.",
			"Back again? I've already got your forms filled in. Saves time.",
			"No running in the Catacombs. Also, no living. Rules are rules.",
		],
		"taunts": [
			"Buried. Neat corners, too. I do take pride.",
			"Another one for the paperwork. Sign here. Oh, you can't.",
			"Tell Ysolde the interest is still going up.",
		],
		"defeat": [
			"Fine! Go! I'm writing you up for this!",
			"That was against regulations. All of it.",
		]},
	"maren": {"name": "Maren of the Drowned Garden", "chapter": 2, "area": "The Drowned Garden",
		"intro": [
			"Off the lilies! Do you know how hard it is to grow things underwater?",
			"Oh, visitors. Mind the roots. And the water. And me.",
			"I've just weeded here. Please don't bleed on it.",
		],
		"taunts": [
			"There. Now you're compost. Very useful, compost.",
			"Sorry, love. The water gets everyone in the end.",
			"Lie still. You'll make a lovely flowerbed.",
		],
		"defeat": [
			"Ouch. Fine. Go on through. Don't touch the roses.",
			"You're stronger than you look. Like dandelions.",
		]},
	"hollis": {"name": "Hollis the Forgemaster", "chapter": 3, "area": "The Ember Forge",
		"intro": [
			"Welcome to the best forge in the world! Hot, isn't it? Lovely.",
			"Visitors! Want to see my new hammer? Up close? Very close?",
			"Mind the sparks. Actually, don't. I like watching people dance.",
		],
		"taunts": [
			"Ha! Flat as a horseshoe. Tell Bram I said hello.",
			"Clang! That's the sound of a job well done.",
			"Too hot for you? Should've stayed upstairs with the soup spoon.",
		],
		"defeat": [
			"Ha! Good hit! Bram teach you that? No, too good for Bram.",
			"Alright, alright. You win. Mind the anvil on the way out.",
		]},
	"regent": {"name": "The Hollow Regent", "chapter": 4, "area": "The Hollow Throne",
		"intro": [
			"Ysolde's girls. Again. You never learn. Neither did she.",
			"I gave this town forty years of my life. I'm owed one boy.",
			"Turn back. He's happy here. Mostly.",
		],
		"taunts": [
			"Go home. Tell your gran I said goodnight.",
			"That's for the bridge I built you. Ungrateful town.",
			"You'll wake up in your bed. My son never did.",
		],
		"defeat": [
			"Not again. Why won't you stay down?",
			"Enough. You've made your point. Not that it changes anything.",
		]},
}

## Chapters of one run, top to bottom.
const CHAPTERS := [
	{"id": 1, "name": "The Catacombs", "boss": "osric", "blurb": "Old graves under the town. Lots of bones, all of them grumpy."},
	{"id": 2, "name": "The Drowned Garden", "boss": "maren", "blurb": "A garden that sank into the pit and kept growing underwater."},
	{"id": 3, "name": "The Ember Forge", "boss": "hollis", "blurb": "A giant furnace where the Regent's weapons and chains get made."},
	{"id": 4, "name": "The Hollow Throne", "boss": "regent", "blurb": "The bottom of the pit. The Regent's throne room, and Teo."},
]

# ------------------------------------------------------------------ conversations
## owner: who you talk to (resident id) or a scene slot: "run_start", "boss_<id>", "victory".
## cond keys (all optional): min_runs, max_runs, min_wins, flags_required [], flags_excluded [],
##   after_death_by (String or Array: a boss id, "enemy" for any regular foe, or an enemy kind),
##   after_victory (bool), chapter_reached (min chapter), boss_beaten {boss_id: min times}, gifts {item: min}.
## priority: higher plays first. once: play only once (default true). sets: flags set when it plays.
const CONVERSATIONS := [
	# ---------------- Gran Ysolde
	{"id": "ysolde_first_return", "owner": "ysolde", "priority": 90, "once": true, "cond": {"min_runs": 1},
		"sets": ["met_ysolde"], "lines": [
		["ysolde", "There you are. Dead, then back. Told you it'd work."],
		["kaela", "You said it'd 'probably' work, Gran."],
		["ysolde", "And it did. Probably is my favourite word. Kettle's on."],
		["liora", "Who are all these people in the kitchen?"],
		["ysolde", "Folk who lost someone to the pit too. They help. You'll like them. Mostly."],
	]},
	{"id": "ysolde_osric_dodge", "owner": "ysolde", "priority": 60, "cond": {"flags_required": ["met_osric"]},
		"sets": ["ysolde_dodged"], "lines": [
		["liora", "The gravekeeper down there knew your name, Gran."],
		["ysolde", "Osric? He knew everyone's name. He buried half of them."],
		["kaela", "He said you still owe. Owe what?"],
		["ysolde", "Money, probably. He charged me twice for a headstone once. Eat your soup."],
		["liora", "That's a dodge."],
		["ysolde", "It's a dodge with soup. Take the win."],
	]},
	{"id": "ysolde_aldric", "owner": "ysolde", "priority": 55, "cond": {"flags_required": ["corwin_aldric"]},
		"lines": [
		["kaela", "Corwin says the Regent used to be Lord Aldric. Our Aldric. Statue-in-the-square Aldric."],
		["ysolde", "He was a good man. Fixed the bridge. Gave out apples at harvest."],
		["liora", "You knew him well."],
		["ysolde", "Everyone knew him. Go to bed, girls. Big day of dying tomorrow."],
	]},
	{"id": "ysolde_confession", "owner": "ysolde", "priority": 95,
		"cond": {"min_wins": 1, "flags_required": ["corwin_emmet"]}, "sets": ["ysolde_confessed"], "lines": [
		["liora", "Gran. Corwin told us about Emmet. The fever. The bargain."],
		["ysolde", "Right. Sit down, both of you. No, Kaela, sit properly."],
		["ysolde", "Forty years ago the grey fever hit Larkhill. Your mum was a baby. She was dying."],
		["ysolde", "Aldric's boy Emmet had it too. Word was the dead at the bottom of the pit would trade."],
		["ysolde", "We both went down. I got there first. They'd give back one life. Just one."],
		["ysolde", "I picked my daughter. Emmet died two days later."],
		["kaela", "Gran..."],
		["ysolde", "The price: the dead can never keep anyone of my blood. That's why you wake up here."],
		["liora", "And Teo's your blood. So the Regent took him to even the score."],
		["ysolde", "A son for a son. I've known since the night he went. I was too ashamed to say."],
		["kaela", "You should've told us on day one."],
		["ysolde", "I know. I'm telling you now. Be angry later. Get him back first."],
	]},
	{"id": "ysolde_after_confession", "owner": "ysolde", "priority": 50,
		"cond": {"flags_required": ["ysolde_confessed"]}, "lines": [
		["kaela", "Still mad at you, by the way."],
		["ysolde", "Good. Mad keeps you warm. Here, more socks."],
		["liora", "For what it's worth, we'd have picked Mum too."],
		["ysolde", "Don't be nice to me, I'll cry in the jam."],
	]},
	{"id": "ysolde_epilogue", "owner": "ysolde", "priority": 1000, "cond": {"flags_required": ["ending_done"]},
		"sets": ["epilogue_done"], "scene": "EPILOGUE", "lines": []},
	{"id": "ysolde_react_osric", "owner": "ysolde", "priority": 20, "once": false,
		"cond": {"after_death_by": "osric"}, "lines": [
		["ysolde", "Osric got you? He's a gravekeeper. His big move is a shovel."]]},
	{"id": "ysolde_react_maren", "owner": "ysolde", "priority": 20, "once": false,
		"cond": {"after_death_by": "maren"}, "lines": [
		["ysolde", "Drowned again? I've put towels by the door. Permanently."]]},
	{"id": "ysolde_react_hollis", "owner": "ysolde", "priority": 20, "once": false,
		"cond": {"after_death_by": "hollis"}, "lines": [
		["ysolde", "You smell like a chimney. Hollis, I take it."]]},
	{"id": "ysolde_react_regent", "owner": "ysolde", "priority": 20, "once": false,
		"cond": {"after_death_by": "regent"}, "lines": [
		["ysolde", "You got all the way to him. Further than I ever wanted to go again. Rest."]]},
	{"id": "ysolde_react_enemy", "owner": "ysolde", "priority": 15, "once": false,
		"cond": {"after_death_by": "enemy"}, "lines": [
		["ysolde", "Done in by the small fry? Happens to the best of us. Not to me, but still."]]},
	{"id": "ysolde_react_win", "owner": "ysolde", "priority": 20, "once": false,
		"cond": {"after_victory": true}, "lines": [
		["ysolde", "You beat him. He'll be back on that throne by morning, but you beat him."]]},
	{"id": "ysolde_idle_1", "owner": "ysolde", "priority": 1, "once": false, "cond": {}, "lines": [
		["ysolde", "Spend your shards, girls. Hoarding's for dragons and accountants."]]},
	{"id": "ysolde_idle_2", "owner": "ysolde", "priority": 1, "once": false, "cond": {}, "lines": [
		["ysolde", "Teo hates his crusts. When he's back, I'm cutting them off. Don't tell anyone."]]},

	# ---------------- Bram, the smith
	{"id": "bram_intro", "owner": "bram", "priority": 90, "cond": {"min_runs": 1}, "sets": ["met_bram"], "lines": [
		["bram", "Bram. I do the weapons. Your spear's bent, by the way."],
		["kaela", "It's not bent. It's got character."],
		["bram", "It's got a curve like a banana. Leave it with me."],
		["liora", "Why's a smith living in a haunted manor?"],
		["bram", "My brother Hollis walked into the pit the night it opened. On purpose. Never came out."],
		["bram", "So I make the blades that'll fetch him back. Or at least smack him round the ear."],
	]},
	{"id": "bram_hollis", "owner": "bram", "priority": 70, "cond": {"flags_required": ["met_hollis"]},
		"lines": [
		["kaela", "We met your brother. He works for the Regent now. Runs a forge down there."],
		["bram", "Course he does. Did he look happy?"],
		["liora", "He looked very pleased with his anvil."],
		["bram", "Thirty years he wanted the biggest forge in the world. Somebody finally offered."],
		["kaela", "He said you hold a hammer like a soup spoon."],
		["bram", "Ha. That's Hollis for 'I miss you'."],
	]},
	{"id": "bram_tag", "owner": "bram", "priority": 75,
		"cond": {"flags_required": ["ysolde_confessed", "met_hollis"], "boss_beaten": {"hollis": 1}},
		"sets": ["gift_hammer_tag"], "lines": [
		["bram", "Those chains on Teo. Hollis made them, I'd bet my beard. Only he can open them."],
		["bram", "Give him this. Our dad's old hammer tag. He'll know what it means."],
		["liora", "And if he doesn't?"],
		["bram", "Then hit him with the spear I fixed. Lovingly."],
	]},
	{"id": "bram_after_key", "owner": "bram", "priority": 70, "cond": {"flags_required": ["hollis_key"]},
		"lines": [
		["kaela", "Hollis gave us the key. He said, 'Tell the soup spoon thanks.'"],
		["bram", "Right. Something in my eye. Forge smoke. Go on, go get your brother."],
	]},
	{"id": "bram_react_hollis", "owner": "bram", "priority": 20, "once": false, "cond": {"after_death_by": "hollis"},
		"lines": [["bram", "Scorched? Hollis always did love a big fire. Dodge his third swing, he's slow on it."]]},
	{"id": "bram_react_osric", "owner": "bram", "priority": 20, "once": false, "cond": {"after_death_by": "osric"},
		"lines": [["bram", "Beaten by a gravekeeper. Honestly, the spear's embarrassed."]]},
	{"id": "bram_react_maren", "owner": "bram", "priority": 20, "once": false, "cond": {"after_death_by": "maren"},
		"lines": [["bram", "Dry the blade before you leave it with me. Rust is not character either."]]},
	{"id": "bram_react_regent", "owner": "bram", "priority": 20, "once": false, "cond": {"after_death_by": "regent"},
		"lines": [["bram", "All the way to the bottom. Spear held up, at least. Proud of it. And you."]]},
	{"id": "bram_react_enemy", "owner": "bram", "priority": 15, "once": false, "cond": {"after_death_by": "enemy"},
		"lines": [["bram", "Those brutes hit like a dropped anvil. I'd know. I've dropped a few."]]},
	{"id": "bram_react_win", "owner": "bram", "priority": 20, "once": false, "cond": {"after_victory": true},
		"lines": [["bram", "You won! And the spear's still straight. Mostly straight."]]},
	{"id": "bram_idle", "owner": "bram", "priority": 1, "once": false, "cond": {}, "lines": [
		["bram", "If it's sharp, I made it. If it's blunt, you used it."]]},

	# ---------------- Odo, the renovator
	{"id": "odo_intro", "owner": "odo", "priority": 90, "cond": {"min_runs": 2}, "sets": ["met_odo"], "lines": [
		["odo", "Odo Penhallow! Owner of the Crooked Lantern, finest inn in Larkhill."],
		["odo", "Then the pit opened and swallowed it. With my husband Fitz inside. And the good chairs."],
		["liora", "I'm so sorry, Odo."],
		["odo", "Thank you. I cope by fixing things. This manor needs a LOT of coping."],
		["odo", "Bring me gems from the old tombs below. Real gems. I'll turn them into a roof."],
		["kaela", "The roof's fine."],
		["odo", "Kaela, a pigeon lives in your room. He has a family. They have opinions."],
	]},
	{"id": "odo_window", "owner": "odo", "priority": 40, "cond": {"min_runs": 4, "flags_required": ["met_odo"]},
		"lines": [
		["odo", "Fixed the east window! The pigeon's been moved. He was very rude about it."],
		["liora", "Where did he go?"],
		["odo", "Corwin's room. Corwin's a ghost. They deserve each other."],
	]},
	{"id": "odo_fitz", "owner": "odo", "priority": 65,
		"cond": {"chapter_reached": 2, "min_runs": 5, "flags_required": ["met_odo"]}, "sets": ["odo_fitz"], "lines": [
		["kaela", "Odo. In the Drowned Garden there's a ghost humming. Badly. Something about a lantern."],
		["odo", "Badly? Like a goose being sat on?"],
		["liora", "Exactly like that."],
		["odo", "That's Fitz. That's our song. He never once hit the high note."],
		["odo", "Is he... alright down there?"],
		["kaela", "He looked calm. Happy, even. He was trimming a hedge."],
		["odo", "He always wanted a garden. I always wanted the inn. Huh. Good for him."],
	]},
	{"id": "odo_react_maren", "owner": "odo", "priority": 20, "once": false, "cond": {"after_death_by": "maren"},
		"lines": [["odo", "Soaked! Mind the new rug. It's borrowed from a very nervous man."]]},
	{"id": "odo_react_regent", "owner": "odo", "priority": 20, "once": false, "cond": {"after_death_by": "regent"},
		"lines": [["odo", "Saw the big man's throne, did you? Bet it's tacky. Bet it's all skulls."]]},
	{"id": "odo_react_enemy", "owner": "odo", "priority": 15, "once": false, "cond": {"after_death_by": "enemy"},
		"lines": [["odo", "Back early! Perfect. I need someone to hold a plank."]]},
	{"id": "odo_react_boss", "owner": "odo", "priority": 15, "once": false,
		"cond": {"after_death_by": ["osric", "hollis"]},
		"lines": [["odo", "Did you at least pick up gems before you died? No? Priorities, ladies."]]},
	{"id": "odo_react_win", "owner": "odo", "priority": 20, "once": false, "cond": {"after_victory": true},
		"lines": [["odo", "A win! I'm putting up a plaque. A small plaque. Gems are tight."]]},
	{"id": "odo_idle", "owner": "odo", "priority": 1, "once": false, "cond": {}, "lines": [
		["odo", "Every gem you bring me is one less draught in this house. Think of the draughts."]]},

	# ---------------- Sergeant Corwin, the ghost
	{"id": "corwin_intro", "owner": "corwin", "priority": 90, "cond": {"min_runs": 2}, "sets": ["met_corwin"], "lines": [
		["corwin", "Sergeant Corwin Hale. Formerly of the Regent's guard. Currently a ghost. At ease."],
		["kaela", "You worked for the thing that took our brother?"],
		["corwin", "For forty years. Quit the night he took the boy. Taking children is bad form."],
		["liora", "So you just walked out of the land of the dead?"],
		["corwin", "Floated. Walking's for people with knees. I'll help where I can."],
	]},
	{"id": "corwin_aldric", "owner": "corwin", "priority": 70,
		"cond": {"min_runs": 4, "flags_required": ["met_corwin", "met_osric"]}, "sets": ["corwin_aldric"], "lines": [
		["corwin", "You should know who you're fighting. The Regent was Lord Aldric. Larkhill's protector."],
		["kaela", "The statue in the square? Big moustache, holding a lamb?"],
		["corwin", "That's him. The lamb was the sculptor's idea. He was more of a goat man."],
		["liora", "How does a town hero end up King of the Dead?"],
		["corwin", "Ask me again after you've met him. You'll want to hear it then."],
	]},
	{"id": "corwin_emmet", "owner": "corwin", "priority": 80,
		"cond": {"flags_required": ["corwin_aldric", "met_regent"]}, "sets": ["corwin_emmet"], "lines": [
		["corwin", "Right. Aldric had a son. Emmet. Nine years old. The grey fever took him, forty years back."],
		["corwin", "Aldric went down the pit to bargain for him. Came back up alone. And wrong."],
		["corwin", "Few years later he walked down for good, sat on the empty throne, and never left."],
		["kaela", "Emmet was nine. Teo's nine."],
		["corwin", "Yes. I noticed that too. I'd rather not have."],
		["liora", "Why did his bargain fail?"],
		["corwin", "Someone got to the table first. That part's your gran's story, not mine."],
	]},
	{"id": "corwin_horse", "owner": "corwin", "priority": 75, "cond": {"flags_required": ["ysolde_confessed"]},
		"sets": ["gift_wooden_horse"], "lines": [
		["corwin", "Took this when I left. Emmet's wooden horse. Aldric kept it by the throne for forty years."],
		["liora", "You stole a grieving man's toy?"],
		["corwin", "Borrowed. Show it to him at the right moment. He might remember who he was."],
	]},
	{"id": "corwin_react_osric", "owner": "corwin", "priority": 20, "once": false, "cond": {"after_death_by": "osric"},
		"lines": [["corwin", "Osric again? He docked my pay for muddy boots. For forty years. Get him for me."]]},
	{"id": "corwin_react_maren", "owner": "corwin", "priority": 20, "once": false, "cond": {"after_death_by": "maren"},
		"lines": [["corwin", "Maren's the kindest of the three. Even while she's drowning you."]]},
	{"id": "corwin_react_hollis", "owner": "corwin", "priority": 20, "once": false, "cond": {"after_death_by": "hollis"},
		"lines": [["corwin", "Hollis swings wide. Get behind him. He hates that, and he says so."]]},
	{"id": "corwin_react_regent", "owner": "corwin", "priority": 20, "once": false, "cond": {"after_death_by": "regent"},
		"lines": [["corwin", "I used to guard that throne room door. Terrible chairs. You did well."]]},
	{"id": "corwin_react_enemy", "owner": "corwin", "priority": 15, "once": false, "cond": {"after_death_by": "enemy"},
		"lines": [["corwin", "Shades are just sad leftover bits of people. Hit them anyway."]]},
	{"id": "corwin_react_win", "owner": "corwin", "priority": 20, "once": false, "cond": {"after_victory": true},
		"lines": [["corwin", "Good work. He'll be sulking now. He sulks loudly."]]},
	{"id": "corwin_idle", "owner": "corwin", "priority": 1, "once": false, "cond": {}, "lines": [
		["corwin", "Tried walking through a wall to scare Odo. He offered me a cushion."]]},

	# ---------------- Wren, the cook
	{"id": "wren_intro", "owner": "wren", "priority": 90, "cond": {"min_runs": 1}, "sets": ["met_wren"], "lines": [
		["wren", "Sit. Eat. Don't argue. I'm Wren, I cook, and you two look like toast."],
		["kaela", "Burnt toast or dry toast?"],
		["wren", "Both. Here, stew. Four kinds of pepper. Builds character."],
		["liora", "Why are you here, Wren?"],
		["wren", "The pit took my mum. She was weeding her garden right at the edge. I heard her shout."],
		["wren", "Gran Ysolde said I could stay. I said I'd cook. Best deal she ever made."],
	]},
	{"id": "wren_maren", "owner": "wren", "priority": 80, "cond": {"flags_required": ["met_maren", "met_wren"]},
		"sets": ["wren_knows"], "lines": [
		["liora", "Wren. The general in the Drowned Garden. She's called Maren."],
		["wren", "That's my mum's name."],
		["kaela", "She's down there, tending plants. She didn't remember anyone."],
		["wren", "Did she look okay? Was she wearing that awful yellow hat?"],
		["liora", "Yes. Yellow hat."],
		["wren", "Right. Okay. I'm going to chop onions very hard for a bit."],
	]},
	{"id": "wren_cake", "owner": "wren", "priority": 75,
		"cond": {"flags_required": ["wren_knows"], "boss_beaten": {"maren": 1}}, "sets": ["gift_honey_cake"], "lines": [
		["wren", "Take this. Honey cake. Mum's recipe. She made it every birthday, even when it flopped."],
		["wren", "Give it to her. If anything gets through the fog in her head, it's this cake."],
		["kaela", "And if she throws it at us?"],
		["wren", "Then she's definitely my mum."],
	]},
	{"id": "wren_remembered", "owner": "wren", "priority": 80, "cond": {"flags_required": ["maren_remembers"]},
		"lines": [
		["kaela", "She remembered you, Wren. She says go easy on the pepper."],
		["wren", "She did NOT. ...She did? Oh, that's her. That's so her."],
		["wren", "Okay. Extra pudding for everyone tonight. Nobody look at my face."],
	]},
	{"id": "wren_react_maren", "owner": "wren", "priority": 20, "once": false, "cond": {"after_death_by": "maren"},
		"lines": [["wren", "Drowned? Here, hot soup. Did you see her? ...Never mind. Eat."]]},
	{"id": "wren_react_osric", "owner": "wren", "priority": 20, "once": false, "cond": {"after_death_by": "osric"},
		"lines": [["wren", "That gravekeeper's all bones. Bet he'd sell his own shovel for a pie."]]},
	{"id": "wren_react_hollis", "owner": "wren", "priority": 20, "once": false, "cond": {"after_death_by": "hollis"},
		"lines": [["wren", "Roasting down there, was it? Cold milk. Drink. All of it."]]},
	{"id": "wren_react_regent", "owner": "wren", "priority": 20, "once": false, "cond": {"after_death_by": "regent"},
		"lines": [["wren", "You fought the King of the Dead on an empty stomach? Unbelievable."]]},
	{"id": "wren_react_enemy", "owner": "wren", "priority": 15, "once": false, "cond": {"after_death_by": "enemy"},
		"lines": [["wren", "You died hungry. I can tell. Eat first next time."]]},
	{"id": "wren_react_win", "owner": "wren", "priority": 20, "once": false, "cond": {"after_victory": true},
		"lines": [["wren", "You WON? Cake. Cake for everyone. Even Corwin, and he can't eat."]]},
	{"id": "wren_idle", "owner": "wren", "priority": 1, "once": false, "cond": {}, "lines": [
		["wren", "Teo's favourite is sausage pie. I make one every week. Just in case."]]},

	# ---------------- Sisters at run start
	{"id": "rs_first", "owner": "run_start", "priority": 90, "cond": {}, "lines": [
		["kaela", "Right. Down the hole, find Teo, bring him home. Easy."],
		["liora", "You said 'easy' about fixing the roof. Gran's still finding tiles."],
	]},
	{"id": "rs_after_osric", "owner": "run_start", "priority": 30, "cond": {"flags_required": ["met_osric"]}, "lines": [
		["kaela", "If that gravekeeper asks for a form again, I'm eating it."],
		["liora", "Please do. I want to see his face."],
	]},
	{"id": "rs_after_confession", "owner": "run_start", "priority": 40, "cond": {"flags_required": ["ysolde_confessed"]},
		"lines": [
		["kaela", "Still can't believe Gran."],
		["liora", "She did it to save Mum. We'd have done the same."],
		["kaela", "...Yeah. Probably. Doesn't mean I have to like it."],
	]},
	{"id": "rs_ready", "owner": "run_start", "priority": 5, "once": false, "cond": {}, "lines": [
		["liora", "Ready?"],
		["kaela", "Born ready."],
		["liora", "You were born three weeks late."],
	]},
	{"id": "rs_first_room", "owner": "run_start", "priority": 5, "once": false, "cond": {"min_runs": 3}, "lines": [
		["liora", "Try not to die in the first room this time."],
		["kaela", "That was one time."],
		["liora", "Four times."],
	]},
	{"id": "rs_teo_first", "owner": "run_start", "priority": 5, "once": false, "cond": {}, "lines": [
		["kaela", "If I go down, keep going. Teo first."],
		["liora", "Obviously. I'll mourn you later. Briefly."],
	]},
	{"id": "rs_sandwich", "owner": "run_start", "priority": 5, "once": false, "cond": {"flags_required": ["met_wren"]},
		"lines": [
		["kaela", "Wren packed us sandwiches. Mine has a note: 'Don't die.'"],
		["liora", "Mine says 'Don't let HER die.' Rude."],
	]},
	{"id": "rs_close", "owner": "run_start", "priority": 10, "once": false, "cond": {"after_death_by": "regent"}, "lines": [
		["kaela", "We were so close last time."],
		["liora", "Then we go a bit further this time. Same plan, less dying."],
	]},
	{"id": "rs_won", "owner": "run_start", "priority": 10, "once": false, "cond": {"after_victory": true}, "lines": [
		["liora", "He'll be waiting for us. And angry."],
		["kaela", "Good. So am I."],
	]},

	# ---------------- Boss first meetings and story scenes (owner boss_<id>, play before the fight)
	{"id": "osric_first", "owner": "boss_osric", "priority": 90, "cond": {}, "sets": ["met_osric"], "lines": [
		["osric", "Names? Purpose of visit? Write clearly, the dead can't read scribbles."],
		["kaela", "Kaela and Liora Ashveil. We're here for our brother."],
		["osric", "Ysolde's girls. Of course. Your gran still owes, you know. Big debt. Very old."],
		["liora", "Owes what?"],
		["osric", "Not my department. My department is burying you. Hold still."],
	]},
	{"id": "osric_after_confession", "owner": "boss_osric", "priority": 60, "cond": {"flags_required": ["ysolde_confessed"]},
		"lines": [
		["osric", "So she told you. Took her forty years. I'd have filed it in a week."],
		["kaela", "You were there? At the deal?"],
		["osric", "I witnessed it. In triplicate. And I told Aldric. Good record keeping matters."],
		["liora", "You're the reason he hates her."],
		["osric", "I'm the reason he KNOWS. Big difference. Now, shovel time."],
	]},
	{"id": "maren_first", "owner": "boss_maren", "priority": 90, "cond": {}, "sets": ["met_maren"], "lines": [
		["maren", "Careful! You're on the lilies. They've been underwater for months. They're sensitive."],
		["liora", "Sorry. We just need to get past."],
		["maren", "Everyone wants past. Nobody wants to stay and weed. Do I know you?"],
		["kaela", "No. But we know someone who misses you."],
		["maren", "That's nice. I don't remember anyone. Now get off my lilies."],
	]},
	{"id": "maren_cake", "owner": "boss_maren", "priority": 85, "cond": {"flags_required": ["gift_honey_cake"]},
		"sets": ["maren_remembers"], "lines": [
		["liora", "This is from Wren. Honey cake."],
		["maren", "Honey cake. It sinks in the middle. Mine always sinks in the middle."],
		["maren", "Wren. My Wren. Is she eating? She forgets to eat when she's feeding everyone else."],
		["kaela", "She's feeding a whole manor. Including us."],
		["maren", "Tell her I'm sorry I didn't come home. The water got so heavy."],
		["maren", "I still have to fight you. He's watching. But I'll go easy. Gardener's honour."],
	]},
	{"id": "hollis_first", "owner": "boss_hollis", "priority": 90, "cond": {}, "sets": ["met_hollis"], "lines": [
		["hollis", "Visitors! Look at this forge. Biggest in the world. Fire straight from the deep."],
		["kaela", "You're Bram's brother."],
		["hollis", "Bram! Still holding a hammer like a soup spoon? Tell him I've got a real forge now."],
		["liora", "You made something for the Regent. Chains, maybe."],
		["hollis", "Best work I've ever done. Unbreakable. Now, who wants to test my new hammer?"],
	]},
	{"id": "hollis_key", "owner": "boss_hollis", "priority": 85, "cond": {"flags_required": ["gift_hammer_tag"]},
		"sets": ["hollis_key"], "lines": [
		["kaela", "Bram sent this. Your dad's hammer tag."],
		["hollis", "He kept that? I told him I'd lost it. He had it the whole time. The rat."],
		["hollis", "The chains on the boy. I made them. Told myself it was just a job. A good one."],
		["hollis", "Here. The key. Don't tell the boss. And tell the soup spoon thanks."],
		["liora", "Come home with us."],
		["hollis", "I'm dead, love. Too late for home. Now we fight. For show. Mostly."],
	]},
	{"id": "regent_first", "owner": "boss_regent", "priority": 90, "cond": {}, "sets": ["met_regent"], "lines": [
		["regent", "Ysolde's granddaughters. You've got her chin. Unlucky."],
		["kaela", "Give us Teo back."],
		["regent", "He's safe. Fed. Read to. He sleeps in a proper bed. More than your gran left mine."],
		["liora", "What's that supposed to mean?"],
		["regent", "Ask her. Tell her I kept the receipt. Now go home. You'll wake up there anyway."],
	]},
	{"id": "regent_after_confession", "owner": "boss_regent", "priority": 70, "cond": {"flags_required": ["ysolde_confessed"]},
		"lines": [
		["liora", "Gran told us. About the fever. About the deal."],
		["regent", "Did she cry? She should have. I did, every night for forty years."],
		["kaela", "Taking Teo won't bring Emmet back."],
		["regent", "No. But it makes things even. Lift your spear, girl."],
	]},
	{"id": "regent_horse_seen", "owner": "boss_regent", "priority": 65, "cond": {"flags_required": ["gift_wooden_horse"]},
		"lines": [
		["regent", "Something's missing from beside my throne. Someone's been in here."],
		["liora", "Lose something?"],
		["regent", "Don't. Just don't. Fight me and go."],
	]},

	# ---------------- After beating the Regent (owner victory, played instead of VICTORY when available)
	## Condition note: wins already include the win that just happened.
	{"id": "victory_ending", "owner": "victory", "priority": 1000,
		"cond": {"min_wins": 3, "flags_required": ["ysolde_confessed", "gift_wooden_horse", "hollis_key"]},
		"sets": ["ending_done"], "scene": "ENDING", "lines": []},
	{"id": "victory_first", "owner": "victory", "priority": 90, "cond": {"min_wins": 1}, "scene": "VICTORY", "lines": []},
	{"id": "victory_second", "owner": "victory", "priority": 80, "cond": {"min_wins": 2}, "sets": ["teo_talked"], "lines": [
		["teo", "You came back! He said you would. He says you're just like Gran."],
		["liora", "Teo, is he hurting you?"],
		["teo", "No. He's sad, mostly. He calls me Emmet sometimes. I tell him my name's Teo."],
		["kaela", "Good lad. Keep telling him."],
		["teo", "He had a toy horse he always looked at. It went missing. He's been really grumpy."],
		["liora", "...Corwin."],
		["teo", "The floor's glowing. You're going again, aren't you? Come back quick."],
	]},
	{"id": "victory_repeat", "owner": "victory", "priority": 10, "once": false, "cond": {"min_wins": 2}, "lines": [
		["regent", "Again. You keep coming. She kept coming too, back then."],
		["teo", "I'm still here! Bring cake next time!"],
		["kaela", "We're nearly there, Teo. Hang on."],
	]},
	{"id": "victory_need_more", "owner": "victory", "priority": 20, "once": false,
		"cond": {"min_wins": 3, "flags_excluded": ["ending_done"]}, "lines": [
		["liora", "We can beat him all day. It won't free Teo. We need more than a spear."],
		["kaela", "The chains, the horse, Gran's story. Let's get every piece."],
	]},
]

# ------------------------------------------------------------------ voice barks (plain strings, TTS ready)
## BARKS[speaker][context] -> lines. Wardens speak when their boon card appears.
## Contexts: greet (default), first_meeting, low_health, boss_floor, coop.
const BARKS := {
	"oriel": {
		"greet": [
			"Fire's lit. Go hit something.",
			"Oriel here. Burn them for me, would you?",
			"Swing hard, aim low, shout loud. Works every time.",
			"You call that a fire? Here, let me help.",
			"Make them sweat. Then make them smoke.",
			"Hit first. Ask questions never.",
			"I guarded this town before your gran could walk.",
			"Take it. Burn bright. Don't get burned.",
		],
		"first_meeting": [
			"I'm Oriel. Captain of Larkhill's old watch. Dead, still on duty.",
			"Ashveil girls? Good. Let's go burn some dead things.",
		],
		"low_health": [
			"You're bleeding. Stop it. That's an order.",
			"On your feet, soldier. Burn it off.",
		],
		"boss_floor": [
			"Big one ahead. Light him up.",
			"Boss fight. Don't hold back. Never hold back.",
		],
		"coop": [
			"Two of you? Double the fire. Love it.",
			"Sisters side by side. Now that's a proper squad.",
		],
	},
	"vessa": {
		"greet": [
			"Vessa! Hi! Quick, take this, no time!",
			"Faster. You're slow. Lovely, but slow.",
			"Lightning, special delivery. No signature needed.",
			"Ten years delivering the post. Never once late.",
			"Zap them, dodge, repeat. Easy.",
			"Ooh, a fight. Can I watch? I'm watching.",
			"Run like the rain's chasing you.",
		],
		"first_meeting": [
			"Hiya! Vessa. I ran the town post. Now I run storms.",
			"New faces! Ashveils, right? Your gran owes me a stamp.",
		],
		"low_health": [
			"Ouch! Run away fast. Then come back faster.",
			"Don't die, I literally just got here!",
		],
		"boss_floor": [
			"Big boss. Don't stand still. Ever.",
			"Boss time! Keep moving, keep zapping.",
		],
		"coop": [
			"Both of you! Brilliant, twice the zapping.",
			"Two sisters, one storm. Go, go, go!",
		],
	},
	"mireth": {
		"greet": [
			"Easy now. Take a breath. Take this too.",
			"Mireth here, love. I'll patch you up.",
			"Slow down a bit. You're no use to him dead.",
			"A bit of water mends most things.",
			"Drink something. Then fight something.",
			"I rowed your gran across the lake once. She tipped badly.",
			"Steady hands, steady heart. There we go.",
		],
		"first_meeting": [
			"Hello, love. Mireth. I ran the ferry. Still look after folk.",
			"Ysolde's girls? You've got her stubborn look. Here, take this.",
		],
		"low_health": [
			"Oh dear, look at the state of you. Here.",
			"Sit tight, love. I've got you.",
		],
		"boss_floor": [
			"Big one coming. Keep your health up, please.",
			"Careful now. Bosses hit hard and don't say sorry.",
		],
		"coop": [
			"Look after each other, you two. That's the main thing.",
			"Two of you. Good. Nobody should go down there alone.",
		],
	},
	"sable": {
		"greet": [
			"Sable. Today I'm giving, not stealing. Don't get used to it.",
			"Aim for the soft bits.",
			"Free tip: stab first.",
			"Thorns. Very fashionable down here.",
			"I picked your gran's pocket once. She picked mine back.",
			"Don't get caught. That's all my advice.",
			"Lucky you. I'm feeling generous.",
		],
		"first_meeting": [
			"Sable. Town thief, retired. Death is a strict boss.",
			"An Ashveil. Hide the silver, everyone.",
		],
		"low_health": [
			"Ooh, you look awful. Here, cheer up.",
			"Bleeding's tacky, love. Stop it.",
		],
		"boss_floor": [
			"Big man ahead. Find his weak spot. Everyone has one.",
			"Boss up ahead. Go for the knees.",
		],
		"coop": [
			"Two Ashveils. Somebody's in trouble, and it isn't you.",
			"Double trouble. Share nicely.",
		],
	},
}

## NARRATION[context] -> lines spoken by the narrator (Gran Ysolde telling the tale).
## death_<kind> for each enemy kind and boss id; death_enemy is the fallback for new enemy kinds.
const NARRATION := {
	"death_shade": [
		"A shade got her. A shade. The sad leftovers of a person. Honestly.",
		"The shades swarmed her. They're like pigeons. Never just one.",
		"Done in by a shade. I won't tell the others. Well, I will.",
	],
	"death_spitter": [
		"A spitter got her from across the room. Rude, but accurate.",
		"She ignored the spitter. The spitter did not ignore her.",
		"Spat on and done for. Not her proudest moment.",
	],
	"death_brute": [
		"The brute hit her very hard. That was its whole plan, and it worked.",
		"She tried to out-muscle a brute. Brave. Not clever. Brave.",
		"One big swing from the brute, and home she came.",
	],
	"death_enemy": [
		"The small fry got her. Happens. Back up she came.",
		"Too many of them, not enough of her. Home again.",
		"Something ugly got lucky. Don't let it go to its head.",
	],
	"death_osric": [
		"Osric buried her. He's very good at his job, sadly.",
		"Beaten by a man with a shovel and a clipboard.",
		"Osric filed her under gone. Perfect paperwork, of course.",
	],
	"death_maren": [
		"Maren drowned her in the lily pond. Politely, mind.",
		"Into the water she went. Maren didn't even stop weeding.",
		"Maren's garden kept another visitor. The lilies looked thrilled.",
	],
	"death_hollis": [
		"Hollis caught her with that hammer. Clang, and home she went.",
		"Too close to the forge. She came back smelling of soot.",
		"Hollis was very proud of that swing. He would be.",
	],
	"death_regent": [
		"She reached the Regent. Further than most. Then he reached her.",
		"The King of the Dead won that round. Only that round.",
		"Aldric beat her. He looked sad about it. He always looks sad.",
	],
	"death_trap": [
		"She stepped on the one tile marked 'don't'. Classic Ashveil.",
		"Spikes. They don't even try, and they still got her.",
		"The floor did her in. Embarrassing, but common.",
	],
	"death_coop": [
		"One sister fell. The other kept going, swearing loudly.",
		"And then there was one. Usually the angry one.",
		"Down she went. Her sister had words about it. Rude ones.",
	],
	"death_coop_both": [
		"Both of them, at once. I had to make two cups of tea.",
		"Two sisters, one bad day. Home they came, arguing.",
		"Both down. They blamed each other the whole way up.",
	],
	"run_start": [
		"Off they went again, down the pit, after the boy.",
		"Another morning, another trip to the land of the dead. Packed lunch included.",
		"Back down the hole. Stubborn, those girls. They get it from me.",
		"Down they go. I put the kettle on. I always put the kettle on.",
	],
	"chapter_1": [
		"First, the Catacombs. Old graves under the town. Mind the bones.",
		"The Catacombs. Where Larkhill buries its dead, and its manners.",
	],
	"chapter_2": [
		"Then the Drowned Garden. A garden that sank and kept growing anyway.",
		"Next, the Drowned Garden. Wet feet guaranteed.",
	],
	"chapter_3": [
		"Then the Ember Forge. Hot, loud, and run by a man who never shuts up.",
		"The Ember Forge. Where the Regent's chains get made. Sweaty work.",
	],
	"chapter_4": [
		"And at the bottom, the Hollow Throne. Where the King of the Dead sulks.",
		"The Hollow Throne. Teo's somewhere in there. Go on, girls.",
	],
}

# ------------------------------------------------------------------ legacy helpers (used by main.gd / hud.gd)
const DEATH_LINES := [
	"There you are. Slightly less alive than when you left. Sit, I'll get a blanket.",
	"Back already? I'd barely started missing you.",
	"The pit sent you back. It always does. It's scared of me.",
	"You fought well. Briefly, but well.",
	"Every time you fall, you get a bit further. That's how stairs work.",
	"Tea's still warm. That's how quick that was.",
	"Teo's waiting. Get some sleep, then go again.",
]

const YSOLDE_CHATTER := [
	"Spend your shards, girls. Hoarding's for dragons and accountants.",
	"Wren's put pepper in the custard. Don't tell her I told you.",
	"Odo wants to paint the hall yellow. Over my dead body. Which, round here, means nothing.",
	"Corwin keeps saluting the coat rack. I think it outranks him.",
	"Bram sharpened my bread knife. I nearly lost a thumb on toast.",
	"Teo hates his crusts. When he's back, I'm cutting them off. Don't tell anyone.",
	"The Wardens are the town's old guardians. Dead, but still bossy. Take their gifts.",
	"I'd come down with you, but my knees are older than the pit.",
]

static func speaker(id: String) -> Dictionary:
	return SPEAKERS.get(id, {"name": id.capitalize(), "color": Color(0.95, 0.85, 0.6), "portrait": ""})

## A Warden's line when their boon card appears. context: greet | first_meeting | low_health | boss_floor | coop.
static func warden_line(patron_id: String, context := "greet") -> String:
	var ctx: Dictionary = BARKS.get(patron_id, {})
	var arr: Array = ctx.get(context, ctx.get("greet", []))
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
