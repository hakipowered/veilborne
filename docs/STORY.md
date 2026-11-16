# Veilborne: story bible

Plain-language guide to the story. All dialogue lives in `data/story.gd`. The logic that picks what plays next is in `data/story_db.gd`.

## The premise in 5 lines

1. Larkhill is a small town built at the edge of a deep pit called **the Hollow**. The land of the dead is at the bottom.
2. One night the King of the Dead, **the Hollow Regent**, climbed out and dragged 9-year-old **Teo** down alive.
3. His big sisters **Kaela** (spear) and **Liora** (twin blades) go down after him. Every time they die, they wake up in Gran **Ysolde**'s manor.
4. They wake up there because of an old deal Gran made with the dead. She is hiding what it cost, and who paid.
5. Each run goes through 4 chapters to the Regent. The plan starts as "kill him". It ends as "talk him into letting go".

## Plain words (terms the game uses)

| Term | What it means |
|---|---|
| **The Hollow** | The pit under Larkhill. The land of the dead is at the bottom. |
| **The Veil** | An old seal across the pit that kept the dead down there. The Regent cracked it. |
| **Veil Shards** | Glowing chips of that broken seal. The sisters bring them home, and Gran turns them into lasting upgrades. |
| **Vows** | Those upgrades: lasting boosts bought with Veil Shards. They stay between runs. |
| **Gems** | Real gems from old tombs below. Odo spends them fixing up the manor. |
| **The Wardens** | The spirits of four of Larkhill's old guardians (Oriel, Vessa, Mireth, Sable). They give out **boons**, powers that last one run. |
| **The Sanctum** | Gran's name for the manor. It's the one house the dead can't walk into. The game's home hub. |
| **Shades** | Weak dead things: the sad leftovers of people. Regular enemies, with spitters and brutes. |

## The family

### Kaela Ashveil (24), heroine, spear
- **Who:** The older sister. Loud, blunt and brave, and she gets angry fast. She raised Teo after their parents died.
- **Wants:** Teo home tonight. She'll deal with feelings later, or never.
- **Speech:** Short, punchy jokes. She swears when she's scared.
- **With Liora:** They bicker all the time and love each other fiercely. She takes the hits so Liora doesn't have to.

### Liora Ashveil (21), heroine, twin blades
- **Who:** The younger sister. Calm and dry, and she notices everything. She is the one who asks "why?".
- **Wants:** Teo back, and the truth about why this happened.
- **Speech:** Deadpan, with wry comebacks. She goes soft at the important moments.
- **With Kaela:** She's the brakes to Kaela's engine. She gets the last word in nearly every argument.

### Teo Ashveil (9)
- **Who:** The little brother, and the person both sisters love most. He's chatty and brave in a small-kid way.
- **Wants:** To go home, and for cake. He's also sorry for the sad old man who keeps calling him Emmet.
- **Speech:** Simple, honest kid lines that land harder than he means them to.

### Gran Ysolde (72), keeper of the hub
- **Who:** Their grandmother, who owns the old manor at the edge of the pit. She's funny and bossy, and she makes bad tea.
- **Wants:** To get Teo home without ever explaining why he was taken.
- **Secret:** The deal. See "The arc" below.
- **Speech:** Dry Yorkshire one-liners. She dodges hard questions with soup. She is also the game's narrator, telling the tale afterwards.
- **With the sisters:** She loves them and lies to them. Once the truth comes out, they stay mad at her for a while, then forgive her.

## The residents (people at the manor)

Everyone here lost someone to the pit, so they moved in to help.

| Id | Name | Job | Lost to the pit | Want | Speech | With the sisters |
|---|---|---|---|---|---|---|
| `bram` | **Bram** (45) | Weapon-smith, runs the armory | His big brother Hollis, who walked in on purpose | To get Hollis back, or at least clip his ear | Slow and warm, dad jokes, Welsh | Fusses over their weapons like a dad |
| `odo` | **Odo Penhallow** (52) | Renovator: spends gems to fix up the manor | His inn, the Crooked Lantern, and his husband Fitz | To rebuild something, since he can't rebuild his life | Chirpy, fast and salesy, sad underneath | Treats them like his best (only) customers |
| `corwin` | **Sergeant Corwin Hale** (ghost) | Guide and lore-keeper. Was the Regent's soldier | His captain, Aldric, to grief | To get his old boss back to who he was | Clipped and deadpan, military | Respects them like soldiers, protects them like nieces |
| `wren` | **Wren** (17) | Cook | Her mum Maren, pulled in while she was gardening at the edge | To feed everyone, and to know if her mum is OK | Fast, cheeky and bossy about food | Bossy little sister to both of them |

## The Wardens (boon givers)

They are the spirits of Larkhill's old guardians. They used to help Lord Aldric keep the seal shut. Now they help the sisters from beyond the grave. Each one speaks a short line when their boon card appears (`Story.BARKS`).

- **Oriel** (fire, damage): the booming old captain of the town watch. She's bossy and loves a scrap.
- **Vessa** (storms, speed): the young town postwoman. She's quick, chirpy and impatient.
- **Mireth** (tides, healing): the old ferryman. A slow, worried grandad.
- **Sable** (thorns, crits and defense): a retired town thief. She's sly and teasing. She once picked Gran's pocket.

## Chapters and bosses

The Regent has three generals. Each one was a real person from Larkhill, and each is tied to someone at the manor.

| Ch | Area | What it is | Boss | Personality | Personal link |
|---|---|---|---|---|---|
| 1 | **The Catacombs** | Old graves under the town | **Osric the Gravekeeper** | Fussy, petty clerk who loves forms and rules | He buried Emmet and witnessed Gran's deal. He told Aldric about it. |
| 2 | **The Drowned Garden** | A garden that sank into the pit and kept growing | **Maren of the Drowned Garden** | Dreamy, kind and distracted. She snaps at you for stepping on her plants | Wren's mum, with her memory fogged. Wren's honey cake brings it back. |
| 3 | **The Ember Forge** | A giant furnace that makes the Regent's weapons | **Hollis the Forgemaster** | Booming and boastful, with a big laugh | Bram's brother. He made the chains that hold Teo, and he can give the key. |
| 4 | **The Hollow Throne** | The bottom of the pit, the Regent's hall | **The Hollow Regent** | Tired, bitter and grieving, not evil | He was Lord Aldric, Larkhill's protector. Gran's deal cost him his son. |

Each boss has a first-meeting scene, a few random intro lines, a taunt when they kill a heroine and a line when beaten (`Story.BOSSES`).

## The arc (the full truth, told in order)

- **40 years ago:** The grey fever hit Larkhill. Ysolde's baby daughter (the sisters' mum) and Lord Aldric's son **Emmet** (9) were both dying.
- The dead at the bottom of the pit would trade one life. Ysolde got there first and chose her daughter. Emmet died two days later.
- **The price of the deal:** the dead can never keep anyone of Ysolde's blood. That's why the sisters wake up at the manor when they die.
- Osric witnessed the deal and told Aldric. In grief, Aldric walked down into the pit, sat on the empty throne and became the Hollow Regent.
- **Now:** Teo turned 9, the same age as Emmet. The Regent broke the seal and took him: "a son for a son". Teo was taken alive, so the deal doesn't send him home.

## Beats unlocked by progress

`StoryDB` picks the highest-priority conversation that hasn't played yet and whose conditions are met. Repeatable reactions and idle chatter fill the gaps.

| # | Unlocks when | Where | What happens | Sets flag |
|---|---|---|---|---|
| 1 | New save | INTRO | They wake up after dying. Gran explains they'll keep coming back, but not why. | |
| 2 | Run 1+ | Hub | They meet Gran, Bram and Wren. Odo and Corwin turn up from run 2. | `met_*` |
| 3 | Reach chapter 1 boss | Boss | Osric: "Your gran still owes." | `met_osric` |
| 4 | After meeting Osric | Ysolde | Gran dodges the question with soup. | `ysolde_dodged` |
| 5 | Run 4+, met Osric | Corwin | The Regent was Lord Aldric, the town hero. | `corwin_aldric` |
| 6 | Reach chapter 2 | Boss → Wren | Maren is Wren's mum. Wren takes it hard. | `met_maren`, `wren_knows` |
| 7 | Chapter 2 reached, run 5+ | Odo | Fitz is a calm ghost in the garden, humming badly. | `odo_fitz` |
| 8 | Maren beaten once | Wren | Wren gives them her mum's honey cake (gift). | `gift_honey_cake` |
| 9 | Carrying the cake | Boss Maren | Maren remembers Wren and sends love, and a pepper complaint. | `maren_remembers` |
| 10 | Reach chapter 3 | Boss → Bram | Hollis is Bram's brother and made Teo's chains. | `met_hollis` |
| 11 | Reach chapter 4 | Boss | The Regent: "Tell her I kept the receipt." | `met_regent` |
| 12 | Met Regent + beat 5 | Corwin | The story of Emmet and the failed bargain. | `corwin_emmet` |
| 13 | First Regent win | VICTORY | They hear Teo behind a chained door. The pit pulls them home. | |
| 14 | 1 win + beat 12 | Ysolde | **Gran confesses the deal.** | `ysolde_confessed` |
| 15 | After the confession | Bram | Bram gives them their dad's hammer tag for Hollis (gift). | `gift_hammer_tag` |
| 16 | After the confession | Corwin | Corwin hands over Emmet's wooden horse (gift). | `gift_wooden_horse` |
| 17 | Carrying the tag | Boss Hollis | Hollis gives them the key to Teo's chains. | `hollis_key` |
| 18 | 2nd Regent win | Victory | Teo: "He calls me Emmet. I tell him my name's Teo." | `teo_talked` |
| 19 | 3+ wins + confession, horse and key | Victory | **The ending.** | `ending_done` |
| 20 | After the ending | Ysolde | **The epilogue.** | `epilogue_done` |

Hub reactions: every resident has a short repeatable line for the last run's result: death by Osric, Maren, Hollis or the Regent, death by a regular enemy, or a win. The sisters also have run-start banter that changes with progress.

## The ending

After the third win (or later) with the key, the horse and Gran's confession, the Regent doesn't get back up to fight. He's tired. Liora shows him Emmet's wooden horse, Captain. Kaela reminds him he used to fix bridges and hand out apples. They tell him Gran is sorry, and that she means it. Teo invites him round for cake. Aldric admits he has always known that taking Teo wouldn't bring Emmet back. He lets them use Hollis's key, then goes deeper to finally find his son. Emmet's spirit says "Dad? You took ages." Teo goes home, and asks for cake first.

## The epilogue

One month later, the manor has a full table and a new roof. Hollis's ghost criticises Bram at the forge. Maren's ghost has taken over the garden. Odo lets Teo choose the colour for his room (orange). Gran thanks the girls and apologises. Kaela is "still a bit mad. Pass the cake." Teo asks them to be quicker if something grabs him again.

## Voice notes

- Every line is short and casual: banter, never speeches. No line is over about 110 characters.
- `Story.SPEAKERS[id].voice` holds the gender, age, tone and accent for each speaker, for the voice and TTS pass.
- `Story.BARKS` (Warden lines on boon cards) and `Story.NARRATION` (Gran narrating deaths, run starts and chapters) are plain strings, ready for text-to-speech.
