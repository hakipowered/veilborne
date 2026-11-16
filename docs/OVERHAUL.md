# Veilborne v0.3 overhaul — shared brief (read fully; CONTRACT.md still applies)

The person (owner) reviewed v0.2 on their phone (Samsung S21 Ultra, Android, landscape) and was blunt:
"character movements and animation are bad", "the arena is dead, has no life, low quality image",
"where are the sounds?", "basic UI; text and menus suck". Reference for QUALITY BAR is the genre leader
(painterly hand-inked look, very readable, juicy, alive), but ALL content must stay ORIGINAL: never use or imitate
that game's names, characters, logos, UI layouts or assets. Characters are glamorous curvy ADULT women; keep it
non-explicit. Priorities: stability + 60fps on Android, then quality.

Project: /home/claude/veilborne (Godot 4.3, GDScript). Godot: /tmp/Godot_v4.3-stable_linux.x86_64
- Re-import after adding assets: `$G --headless --path . --import`
- Bot playtest (must stay green): `$G --headless --path . res://tests/harness.tscn --fixed-fps 60 -- --role=solo --frames=30000`
- Rendering/screenshots: `xvfb-run -a -s "-screen 0 1600x720x24" $G --rendering-driver opengl3 --path . --resolution 1600x720 <scene>`
  (tests/touch_test.tscn and tests/menu_shots.tscn are examples that save PNGs). LOOK at your screenshots and iterate.
- Image generation: Whiteboard_Images MCP (load via ToolSearch "select:mcp__Whiteboard_Images__generate_image,..."),
  engine "premium" returns a fal.media URL you can curl; generated images are also saved locally (see tool output path).
  For transparent sprites, paint on flat pure #00FF00 and key it (see /tmp/claude-0/key.py for the keyer used so far).
- DO NOT run git. DO NOT edit files owned by another agent (ownership below); if you need a hook in someone else's
  file, put a clearly named function in YOUR file and describe the one-line call needed in your final report.
- Keep total APK growth reasonable (< ~120 MB total): prefer .webp/.jpg for opaque art, PNG only where alpha needed,
  OGG Vorbis for audio, sprite sheets sized sensibly (frames ~256px tall for characters is plenty).

## Ownership
- LEAD (integration, combat feel): scenes/arena.gd, entities/hero.gd, entities/enemy.gd, autoload/game.gd, autoload/net.gd,
  autoload/updater.gd, tests/*, tools/*, project.godot (ask lead for autoload registration: say it in your report).
- ANIMATION agent: art/anim/**, entities/anim_sprite.gd, tools/anim/** (render pipeline).
- ENVIRONMENT agent: art/env/**, scenes/environment.gd, shaders/env_*.gdshader.
- AUDIO agent: audio/**, autoload/audio.gd.
- UI agent: scenes/main.gd, ui/** (including hud.gd and touch.gd), data/story.gd, art/ui/**, fonts/**.

## Interfaces
### AnimSprite (entities/anim_sprite.gd, extends Node2D) — ANIMATION agent
func setup(character_id: String, target_height_px: float) -> void   # loads art/anim/<id>/...
func play(anim: String, restart := false) -> void   # "idle","run","attack1","attack2","attack3","dash","special","hurt","death" (enemies: "idle","move","windup","attack","hurt","death", boss also "cast","charge")
func set_facing(dir: Vector2) -> void               # picks one of 8 directions, mirrors where appropriate
func set_speed_scale(s: float) -> void
var flash: float  (0..1 white hit flash), var tint: Color
signal anim_finished(anim: String); signal anim_event(name: String)   # e.g. "hit" frame for attacks
func get_anim_length(anim: String) -> float
Character ids: "kaela", "liora", "shade", "spitter", "brute", "regent". Feet at node origin.
### Environment (scenes/environment.gd, extends Node2D) — ENVIRONMENT agent
func build(floor_key: String, room_index: int, seed_value: int) -> void   # floor_key "catacomb" | "throne"
func get_bounds_half() -> Vector2     # diamond half extents in world px (arena clamps with |x|/W+|y|/H<=1)
func get_obstacles() -> Array         # [{pos: Vector2, radius: float}] solid props (pillars etc.) for circle collision
func get_door_pos() -> Vector2; func set_door_open(open: bool) -> void
func get_spawn_points() -> Array; func get_player_start() -> Vector2
func add_ysorted_props_to(parent: Node2D) -> void   # props that characters walk behind (lead passes the y-sorted entity layer)
Background layers draw under entities (z < 0); foreground silhouettes/fog/vignette above (z > 10). Must look great on
1600x720 and 2400x1080 phones with camera zoom ~1.1 following the player; the camera never shows outside the room art.
### Audio (autoload Audio, autoload/audio.gd) — AUDIO agent
func sfx(name: String, pos := Vector2.INF, pitch_var := 0.08, volume_db := 0.0) -> void   # pooled, never allocates per call
func music(track: String, fade := 1.0) -> void        # "title","sanctum","catacombs","boss","victory","defeat"; ""=stop
func ui(name: String) -> void                          # "click","hover","confirm","back","boon","purchase","open"
func set_volumes(master: float, music: float, sfx: float) -> void
Required sfx names: swing_spear, swing_blades, hit_flesh, hit_crit, dash, special_ember, special_moon, hero_hurt,
hero_down, revive, enemy_die, shade_lunge, spitter_shoot, projectile_hit, brute_slam, slam_impact, regent_burst,
regent_charge, regent_summon, regent_roar, regent_die, boon_pickup, door_open, room_clear, shard_pickup, footstep.
