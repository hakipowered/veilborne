# Veilborne

An original isometric action roguelike for Android, built in Godot 4.3. Play it solo or in co-op.

Two heroines go down through the Gilded Catacombs to take back the stars that the Hollow Regent stole. Each run has
4 combat chambers and a boss throne room. Between chambers you pick boons from four Wardens. Shards you earn
buy permanent Vows in the Sanctum, and each death sends you back there.

## What's in this vertical slice
- **Heroines:** Kaela Ashveil (ember spear, heavy hits) and Liora Moonbrand (twin moon blades, fast). Each has a
  3-hit combo with a heavier third hit, a dash with i-frames (extra charges come from boons) and a special with a cooldown.
- **Enemies:** Gilded Shade (lunging wraith), Ember Spitter (ranged gargoyle) and Vault Brute (telegraphed ground slam).
- **Boss:** The Hollow Regent. Phase 1 has radial bursts, a telegraphed charge and slam rings. At 50% health it summons
  shades and turns faster.
- **Boons:** 12 boons from 4 Wardens, in Common, Rare and Epic rarity. Taking one you already have upgrades it. Effects
  include burn, chain lightning, dash shock, lifesteal, crits, armor, extra dash charges and more.
- **Meta progression:** 5 Vows (Vitality, Fury, Swiftness, Defiance revive, Fortune) bought with Veil Shards.
- **Story:** an intro, pre-boss and victory scenes, lines from Ysolde in the Sanctum and Warden greetings. All of it is
  played in a typewriter dialogue box with portraits.
- **Save slots:** 3 solo and 3 co-op "Chronicles". Each tracks shards, vows, runs, wins, best room and story progress.
- **Co-op:**
  - **Local co-op** on one device. Player 2 uses a gamepad, or arrows plus `,` `.` `/` on keyboard.
  - **Online/LAN co-op** for up to 4 players over ENet UDP. One player hosts and the others join by IP.
- **Hit feel:** painted sprites with squash and stretch, glowing additive weapon smears, white hit flash, sparks,
  damage numbers, crits, screen shake, hit-stop in solo, and vibration on hit.

## Netcode (why co-op doesn't feel laggy)
- **Your own heroine is simulated on your phone.** Movement, dashes and attacks start the moment you press. Nothing
  waits for the network (client-side prediction).
- **Your hits show immediately.** Sparks, flashes and damage numbers appear on your screen at once. Crits come from a
  deterministic hash, so the host's result matches what you already saw.
- **The host owns enemies and loot.** Enemy snapshots stream at 30 Hz on an unreliable channel (channel 1), so state
  never queues behind reliable events. Clients draw them 100 ms in the past with interpolation, which smooths over
  jitter and lost packets.
- **Damage to you is decided on your device ("favor the defender").** If a dodge looked clean on your screen, it
  was clean.
- **Stability:** the boss and every enemy are driven by the same code path in solo and co-op. The bot test runs
  host and client as two processes over localhost and clears the whole run with both stats in sync.

## Controls
- **Touch:** floating joystick on the left half. ATTACK, DASH and SPECIAL buttons on the right; their rings show
  cooldowns.
- **Keyboard P1:** WASD to move, J attack, K special, Space or L dash, Esc to pause.
- **Keyboard P2:** arrows to move, `,` attack, `.` special, `/` dash (numpad 1/2/0 also work).
- **Gamepad N** controls player N: left stick, X attack, Y special, A or RB dash.

## Running / building
1. Open the folder in **Godot 4.3** (Project > Import > `project.godot`) and press F5.
2. For Android, install the Android export templates. Then go to Project > Export > Android, set your SDK path in
   Editor Settings and export. `export_presets.cfg` is already set up for arm64, landscape, immersive mode and
   network permissions.
3. **Online co-op:** both phones on the same Wi-Fi. One picks Co-op > Host and reads the IP shown in the Sanctum;
   the other picks Co-op > Join with that IP. Over the internet the host has to forward UDP port 24680 (see
   ROADMAP for relay plans).

## Tests (headless bots)
```
godot --headless --path . res://tests/harness.tscn --fixed-fps 60 -- --role=solo   # or local
godot --headless --path . res://tests/harness.tscn -- --role=host &
godot --headless --path . res://tests/harness.tscn -- --role=client
```
A bot plays the whole run: it fights, picks boons, uses the doors and fights the boss. It prints progress and the result.
Game logic costs about 0.25 ms per frame on desktop, which leaves plenty of room on mid-range Android.

## Layout
- `autoload/game.gd`: heroes, boons, vows, saves
- `autoload/net.gd`: ENet co-op and RPCs
- `scenes/main.gd`: menus, slots, lobby, Sanctum, results
- `scenes/arena.gd`: rooms, waves, combat resolution, FX, sync
- `entities/hero.gd`, `entities/enemy.gd`
- `ui/hud.gd`, `ui/touch.gd`, `ui/dialogue.gd`, `ui/theme.gd`
- `data/story.gd`
- `art/`: painted sprites and backgrounds; `art/raw` holds the sources and is excluded from builds
