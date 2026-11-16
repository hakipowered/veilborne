# What's left after the vertical slice

A full game on the scale of the genre's leaders takes a team years. This slice proves the core loop, the art
direction and the co-op tech. Below is what's left, roughly in priority order.

## 1. Animation (biggest visual gap)
- The heroines and enemies are currently single painted poses brought to life with procedural squash, stretch, lean,
  bob, flashes and smears. The next step is real frame animation: idle, run (8 directions), 3 attack frames per
  combo hit, dash, hurt and death. There are two ways to get there:
  - (a) Turn each painted character into a rigged 3D model and render sprite sheets from it. This is how the genre's
    leaders do it.
  - (b) Use Spine/DragonBones cut-out rigs made from the painted parts.
- Attack anticipation and recovery frames, so timing has weight.

## 2. Content
- 3 more biomes, each with its own floor art, 4 to 6 enemy types, a mini-boss and a boss.
- More chamber layouts with obstacles, traps and hazards, plus a branching door choice that shows the reward type
  (boon, shards, healing, shop).
- A shop room, healing fountains and elite enemies.
- 2 more heroines, plus weapon aspects for each one.
- Duo boons (two Wardens combined), legendary boons and boon prerequisites.
- Story: a chapter per biome, relationship and affinity dialogue, a codex, and a walkable Sanctum hub.

## 3. Audio
- Music per biome and for the boss, sound effects for every hit, dash and UI action, and voiced barks. There is no
  audio yet.

## 4. Online
- **Internet play without port forwarding:** a relay or NAT punch-through (Steam Networking, Epic Online
  Services, or a small UDP relay server), plus room codes instead of raw IPs.
- Reconnect after a short drop; for now a disconnect mid-run returns you to the title and keeps your shards.
- Joining a run in progress, and host migration.
- Server-side checks on client damage to stop cheating. Right now the host trusts clients' movement and hits within
  normal ranges, which is fine for friends.

## 5. Polish, performance and release
- Upscale the arena floor art to 2K (it's currently 1376px, scaled up 1.6x, so it looks a little soft on tablets).
- Settings: volume, vibration, screen shake, button size and layout, and left-handed mode.
- Accessibility: god mode or difficulty assist, colorblind telegraphs.
- Cloud saves (Google Play Games), achievements, signing and a Play Store listing.
- Profiling on low-end devices: texture atlasing and ETC2/ASTC compression are already enabled.
