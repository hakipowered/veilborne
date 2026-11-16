# Veilborne code contract (Godot 4.3, GDScript, typed where practical)

Project root: /home/claude/veilborne . Godot binary: /tmp/Godot_v4.3-stable_linux.x86_64
Parse-check one script:  /tmp/Godot_v4.3-stable_linux.x86_64 --headless --path /home/claude/veilborne --check-only --script res://path/file.gd
Priorities from the person: STABILITY and SPEED (60 fps on mid Android). No per-frame allocations in hot loops
where avoidable, no physics bodies (manual circle collision), cap entity counts, null-check everything that can be freed
(use is_instance_valid). Art: painted sprites in res://art/*.png (green-screen keyed, transparent). NEVER draw
characters/enemies as primitive blocks; primitives are allowed only for VFX (smears, rings, sparks, telegraphs, shadows).

Autoloads (already written, read them): Game (res://autoload/game.gd), Net (res://autoload/net.gd).
Hero: res://entities/hero.gd (owner-simulated, interpolated elsewhere).

## Arena (res://scenes/arena.gd, extends Node2D) — owned by lead
const INTERP_DELAY_MS := 100
signal run_finished(victory: bool)
func setup(players: Array) -> void          # Game.players format [{peer, local_index, hero}]
func heroes() -> Array                      # all hero nodes (valid, in tree)
func enemies() -> Array                     # all enemy nodes
func is_authority() -> bool                 # true on host / solo
func resolve_collision(pos: Vector2, radius: float) -> Vector2  # keep inside room + out of pillars
func spawn_enemy(kind: String, pos: Vector2) -> Node          # HOST only; arena assigns eid, broadcasts via snapshot
func spawn_projectile(pos: Vector2, vel: Vector2, dmg: float, color: Color, radius := 10.0) -> void  # HOST only; replicated
func telegraph_slam(pos: Vector2, radius: float, delay: float, dmg: float, color: Color) -> void       # HOST only; replicated; every device damages its OWN heroes when it detonates
func on_enemy_killed(enemy: Node, attacker_key: String) -> void  # HOST only; called by enemy when hp <= 0 (enemy must not free itself; arena frees)
func float_text(pos: Vector2, text: String, color: Color) -> void
func spark(pos: Vector2, color: Color, count := 8) -> void       # hit particles
func shake(amount: float) -> void
func nearest_hero(pos: Vector2) -> Node   # nearest non-downed hero or null

## Enemy (res://entities/enemy.gd, extends Node2D) — owned by enemies agent
var eid: int; var kind: String   # "shade" | "spitter" | "brute" | "regent"
var hp: float; var max_hp: float; var radius: float
var hitbox_active: bool; var hitbox_radius: float; var contact_damage: float   # arena checks local heroes vs these on every device
var burn_dps: float              # set by arena for Kindle boon; enemy ticks it on host
func setup(p_eid: int, p_kind: String, p_arena: Node, hp_scale: float) -> void
func simulate(delta: float) -> void         # HOST only, AI + movement; arena calls it each physics frame
func take_damage(amount: float, crit: bool, from_pos: Vector2, attacker_key: String) -> void  # HOST only; knockback, flash, calls arena.on_enemy_killed at 0 hp
func flash_hit() -> void                    # visual only (used for predicted hits on clients)
func pack() -> Array                        # compact snapshot (floats/ints/bools only)
func apply_packed(a: Array) -> void         # client: push into interpolation buffer (render INTERP_DELAY_MS in past, like hero.gd)
func client_update(delta: float) -> void    # client: interpolate + visual timers; arena calls instead of simulate
Boss "regent": phases (radial projectile bursts, telegraphed charge, slam rings, summons shades at 50% hp). Emits nothing; arena reads hp for boss bar.

## Main (res://scenes/main.gd, extends Node; scene res://scenes/main.tscn) — owned by UI agent
func start_arena() -> void       # called by Net.begin_run on every device AND for solo/local. Frees menus, instances arena:
                                  #   var a = preload("res://scenes/arena.gd").new(); add_child(a); a.setup(Game.players); a.run_finished.connect(_on_run_finished)
func play_dialogue(lines: Array, on_done: Callable) -> void   # lines: [{speaker, text}] ; speaker id in Story.SPEAKERS; overlay above game
