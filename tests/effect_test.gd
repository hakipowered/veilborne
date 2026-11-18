extends Node
## Effect test: every card (Warden boons, forge cards), every aspect, the weapons' signature moves, the Vows,
## Mister Wick's wares and the chamber rewards, MEASURED in a real arena. Dummy foes stand at known spots
## (they never move or act), the heroine's actions run through the same code as in play (arena._resolve_action,
## _start_cast, _spawn_arrows, hero._simulate with a fake pad), and the damage numbers / hit counts / durations /
## speeds / heals that come out are compared with what the card's text promises, with and without the card,
## at every level. Run by tests/boon_test.tscn (prints EFFECT lines and an audit table).

const DT := 1.0 / 60.0

class Pad:
	var move := Vector2.ZERO
	var attack := false
	var special := false
	var dash := false
	var special_aim := Vector2.ZERO

class Ware extends Node2D:
	var kind := ""
	var price := 1
	var taken := false

var fails: Array = []
var checks := 0
var table := {} ## id -> [status, note]
var arena: Node
var hero: Node
var pad := Pad.new()
var START := Vector2.ZERO
var D := Vector2.RIGHT ## the open direction from START (lines of dummies go this way)
var P := Vector2.DOWN  ## perpendicular
var _seq := 1000
var _cur := ""


func run() -> void:
	Game.load_slot("solo", 2)
	Game.data["meta"] = {}
	var asp := {}
	for w in Game.WEAPON_ORDER:
		asp[w] = [1, 2]
	Game.data["aspects"] = asp
	Game.set_loadout("spear", 0)
	Game.players = [{"peer": 1, "local_index": 0, "hero": "kaela"}]
	Game.start_run(4242)
	arena = load("res://scenes/arena.gd").new()
	add_child(arena)
	arena.setup(Game.players)
	arena.set_physics_process(false)
	hero = arena.heroes()[0]
	hero.set_physics_process(false)
	hero.touch = pad
	# find a chamber with open floor for the dummy lines (rebuilding room 0 with other seeds)
	for sd in [4242, 1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144, 233, 377]:
		Game.run_seed = sd
		arena._load_room(0)
		arena.set_physics_process(false)
		if _find_open_spot() >= 780.0:
			break
	_test_boons()
	_test_forge()
	_test_aspects()
	_test_signatures()
	_test_meta()
	_test_shop_and_rewards()
	Engine.time_scale = 1.0


# ---------------------------------------------------------------- plumbing

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails.append("%s: %s" % [_cur, what])
		var row: Array = table.get(_cur, ["OK", ""])
		row[0] = "FAIL"
		row[1] = (row[1] + "; " if row[1] != "" else "") + what
		table[_cur] = row

func _begin(id: String) -> void:
	_cur = id
	if OS.get_environment("EFFECT_TRACE") != "":
		print("EFFECT> ", id)
	if not table.has(id):
		table[id] = ["OK", ""]

func _near(a: float, b: float, tol := 0.02) -> bool:
	return absf(a - b) <= maxf(0.01, absf(b) * tol)

## A spot with open floor: 760 px ahead along D, 300 px back and to either side.
func _find_open_spot() -> float:
	var env = arena.env
	var half: Vector2 = arena.room_half
	var best := -1.0
	for gx in range(-6, 7):
		for gy in range(-4, 5):
			var c := Vector2(gx * half.x / 7.0, gy * half.y / 5.0)
			if env.resolve(c, 20.0).distance_to(c) > 0.5:
				continue
			for d in [Vector2.RIGHT, Vector2.LEFT]:
				if _clear(c, -d, 300.0) < 300.0 or _clear(c, Vector2.UP, 200.0) < 200.0 or _clear(c, Vector2.DOWN, 200.0) < 200.0:
					continue
				var sc := _clear(c, d, 800.0)
				if sc > best:
					best = sc
					START = c
					D = d
	P = Vector2(-D.y, D.x)
	print("EFFECT: open spot %s dir %s (clear %d)" % [START, D, best])
	return best

func _clear(c: Vector2, d: Vector2, maxd: float) -> float:
	var t := 0.0
	while t < maxd:
		t += 20.0
		var p := c + d * t
		if arena.env.resolve(p, 20.0).distance_to(p) > 0.5:
			return t - 20.0
	return maxd

## Equips weapon/aspect with exactly these cards: {id: [rarity, level]} (boon ids and forge ids alike).
func _equip(w: String, a := 0, cards := {}) -> void:
	_clear_world()
	var b := {}
	var f := {}
	for id in cards:
		var rl: Array = cards[id]
		var e := {"level": int(rl[1]), "rarity": int(rl[0])}
		if not Game.forge_by_id(id).is_empty():
			f[id] = e
		else:
			b[id] = e
	if not f.is_empty():
		b["_forge"] = f
	b["_weapon"] = w
	b["_aspect"] = a
	hero.boons = b
	hero._apply_weapon(w, a)
	hero.recompute_stats()
	hero.stats["crit"] = 0
	hero.hp = hero.max_hp
	hero.position = START
	hero.facing = D
	hero.vel = Vector2.ZERO
	hero.state = "idle"
	hero.state_t = 0.0
	hero.move_kind = ""
	hero.move_count = {}
	hero.blocks = 0
	hero.attack_cd = 0.0
	hero.special_cd = 0.0
	hero.iframes = 0.0
	hero.combo = 0
	hero.combo_window = 0.0
	hero.charge = 0.0
	hero.full_t = -1.0
	hero.souls = 0.0
	hero.hold_t = 0.0
	hero.aiming = false
	hero.downed = false
	hero.defiance_left = 0
	hero.dash_charges = 1 + int(hero.stats["dash_charges"])
	hero._since_dash = 9.0
	for k in hero._buffer_t:
		hero._buffer_t[k] = 0.0
		hero._prev_held[k] = false
	_pad_clear()

func _pad_clear() -> void:
	pad.move = Vector2.ZERO
	pad.attack = false
	pad.special = false
	pad.dash = false
	pad.special_aim = Vector2.ZERO

func _clear_world() -> void:
	for e in arena.enemy_nodes.values():
		if is_instance_valid(e):
			e.queue_free()
	arena.enemy_nodes.clear()
	arena._ecache.clear()
	arena.casts.clear()
	arena.hshots.clear()
	arena.pools.clear()
	arena.projectiles.clear()
	arena.slams.clear()

## A dummy foe at START + off that never moves or acts, with a deep pool of health.
func _dummy(off: Vector2, kind := "shade", hp := 100000.0) -> Node:
	var e = arena.spawn_enemy(kind, START + off, 1.0)
	e.hp = hp
	e.max_hp = hp
	e.set_physics_process(false)
	if e.position.distance_to(START + off) > 1.0:
		fails.append("%s: dummy at %s blocked (put at %s)" % [_cur, START + off, e.position])
	_rebuild()
	return e

func _rebuild() -> void:
	arena._ecache.clear()
	for e in arena.enemy_nodes.values():
		if is_instance_valid(e) and not e.is_queued_for_deletion():
			arena._ecache.append(e)

func _taken(e: Node) -> float:
	return float(e.max_hp) - float(e.hp)

func _step(n: int, drive := false) -> void:
	for i in range(n):
		_rebuild()
		if drive:
			hero._simulate(DT)
		arena._update_casts(DT)
		arena._update_hshots(DT)

func _act(action: String, dir := Vector2.INF, aim := Vector2.ZERO) -> void:
	_seq += 1
	_rebuild()
	arena._resolve_action(hero, action, hero.position, D if dir == Vector2.INF else dir, _seq, aim, arena.MODE_AUTH)

func _cast(aim: Vector2, frames := 600) -> void:
	_seq += 1
	_rebuild()
	arena._start_cast(hero, hero.position, (aim - hero.position).normalized(), aim, _seq, arena.MODE_AUTH)
	for i in range(frames):
		if arena.casts.is_empty():
			return
		_step(1)

func _shoot(charge: float) -> void:
	_seq += 1
	arena._spawn_arrows(hero, hero.position, D, charge, _seq, arena.MODE_AUTH)
	for i in range(120):
		if arena.hshots.is_empty():
			return
		_step(1)

func _levels(def: Dictionary) -> Array:
	## [rarity, level] configs to measure: every level at Common, plus the Epic max.
	return [[0, 1], [0, 2], [0, 3], [2, 3]]

func _v(def: Dictionary, rl: Array) -> float:
	return float(Game.card_value(def, int(rl[0]), int(rl[1])))

## Whether the card's text at this rarity/level states this value.
func _text_has(def: Dictionary, rl: Array, v: float) -> void:
	var t := Game.card_text(def, int(rl[0]), int(rl[1]))
	var s := ("%.1f" % v) if String(def["desc"]).contains("%.1f") else ("%d" % int(v))
	_check(t.contains(s), "text '%s' shows %s" % [t, s])

## Ground-ellipse distance -> offset along a direction (the floor is squashed 0.5).
func _ell(dir: Vector2, r: float) -> Vector2:
	return dir * r / Vector2(dir.x, dir.y * 2.0).length()


# ---------------------------------------------------------------- Warden boons

func _test_boons() -> void:
	for b in Game.BOONS:
		_begin(String(b["id"]))
		for rl in _levels(b):
			var v := _v(b, rl)
			_text_has(b, rl, v)
			call("_boon_" + String(b["stat"]), b, rl, v)

## Attack damage +v%: a thrust on a dummy.
func _boon_attack_mult(b: Dictionary, rl: Array, v: float) -> void:
	_equip("spear")
	var e := _dummy(D * 60.0)
	_act("attack1")
	var base := _taken(e)
	_equip("spear", 0, {b["id"]: rl})
	e = _dummy(D * 60.0)
	_act("attack1")
	_check(_near(_taken(e), base * (1.0 + v / 100.0)), "thrust %.1f vs %.1f x %.2f" % [_taken(e), base, 1.0 + v / 100.0])
	# and on arrows
	_equip("bow", 0, {b["id"]: rl})
	e = _dummy(D * 200.0)
	_shoot(0.0)
	_check(_near(_taken(e), 20.0 * (1.0 + v / 100.0)), "arrow %.1f" % _taken(e))

func _boon_burn(b: Dictionary, rl: Array, v: float) -> void:
	_equip("spear")
	var e := _dummy(D * 60.0)
	_act("attack1")
	_check(float(e.burn_dps) == 0.0, "no burn without the card")
	_equip("spear", 0, {b["id"]: rl})
	e = _dummy(D * 60.0)
	_act("attack1")
	_check(_near(float(e.burn_dps), v), "burn %.1f/s" % float(e.burn_dps))
	# burning really deals v per second
	var hp0: float = e.hp
	for i in range(60):
		e._tick_burn(DT)
	_check(_near(hp0 - float(e.hp), v, 0.05), "burn dealt %.1f in 1 s" % (hp0 - float(e.hp)))
	# specials burn too ("your hits")
	_equip("bow", 0, {b["id"]: rl})
	e = _dummy(D * 250.0)
	_cast(START + D * 250.0)
	_check(_near(float(e.burn_dps), v), "volley burns %.1f/s" % float(e.burn_dps))

func _boon_special_mult(b: Dictionary, rl: Array, v: float) -> void:
	for w in Game.WEAPON_ORDER:
		_equip(w)
		var base := _special_total(w)
		_equip(w, 0, {b["id"]: rl})
		var got := _special_total(w)
		_check(_near(got, base * (1.0 + v / 100.0)), "%s special %.1f vs %.1f" % [w, got, base])

## Total damage of one special on a dummy standing where it lands.
func _special_total(w: String) -> float:
	var at := START + D * 250.0
	var e := _dummy(D * 250.0)
	if w == "twin" or w == "scythe":
		e = _dummy(D * 150.0)
	if w == "twin":
		_blink(START + D * 300.0)
	else:
		_cast(at, 120)
		if w == "spear":
			_act("recall")
			_step(120)
	_step(400)
	return _taken(e)

## Drives a real Moonstep with the pad: hold SPECIAL dragged to `to`, let go.
func _blink(to: Vector2) -> void:
	pad.special = true
	pad.special_aim = (to - hero.position) / hero.aim_range()
	_step(2, true)
	pad.special = false
	_step(3, true)
	pad.special_aim = Vector2.ZERO
	_step(90, true)

func _boon_dash_shock(b: Dictionary, rl: Array, v: float) -> void:
	_equip("spear")
	var e := _dummy(-D * 80.0)
	_act("dash")
	_check(_taken(e) == 0.0, "no dash damage without the card")
	_equip("spear", 0, {b["id"]: rl})
	e = _dummy(-D * 80.0)
	var far := _dummy(-D * 260.0)
	_act("dash")
	_check(_near(_taken(e), v), "dash strike %.1f" % _taken(e))
	_check(_taken(far) == 0.0, "only nearby foes")

func _boon_chain(b: Dictionary, rl: Array, v: float) -> void:
	for mode in ["thrust", "arrow"]:
		_equip("spear" if mode == "thrust" else "bow", 0, {b["id"]: rl})
		# a line of foes: only the first is struck (the thrust's reach / a quick arrow stops there)
		var first := _dummy(D * 70.0)
		var others := []
		for k in range(6):
			others.append(_dummy(D * (250.0 + 95.0 * k)))
		if mode == "thrust":
			_act("attack1")
		else:
			_shoot(0.0)
		var n := 0
		for o in others:
			if _taken(o) > 0.0:
				n += 1
		_check(_taken(first) > 0.0 and n == mini(int(v), 6), "%s arcs to %d (want %d)" % [mode, n, mini(int(v), 6)])

func _boon_speed_mult(b: Dictionary, rl: Array, v: float) -> void:
	var base := _run_dist({})
	var got := _run_dist({b["id"]: rl})
	_check(_near(got, base * (1.0 + v / 100.0), 0.03), "ran %.1f vs %.1f" % [got, base])

func _run_dist(cards: Dictionary) -> float:
	_equip("spear", 0, cards)
	pad.move = D
	_step(30, true)
	var p0: Vector2 = hero.position
	_step(30, true)
	_pad_clear()
	return hero.position.distance_to(p0)

func _boon_max_hp_bonus(b: Dictionary, rl: Array, v: float) -> void:
	_equip("spear")
	var m0: int = hero.max_hp
	hero.hp = 50.0
	hero.boons[b["id"]] = {"level": int(rl[1]), "rarity": int(rl[0])}
	hero.recompute_stats()
	_check(hero.max_hp == m0 + int(v), "max health %d -> %d" % [m0, hero.max_hp])
	_check(_near(hero.hp, 50.0 + v), "healed by the gain (%.1f)" % hero.hp)

func _boon_lifesteal(b: Dictionary, rl: Array, v: float) -> void:
	_equip("spear", 0, {b["id"]: rl})
	hero.hp = 40.0
	var e := _dummy(D * 60.0, "shade", 1.0)
	_act("attack1")
	_check(e.hp <= 0.0, "dummy died")
	_check(_near(hero.hp, 40.0 + v), "healed to %.1f on the kill" % hero.hp)

func _boon_special_size(b: Dictionary, rl: Array, v: float) -> void:
	for w in Game.WEAPON_ORDER:
		_equip(w)
		var r0: float = arena.special_radius(hero)
		_equip(w, 0, {b["id"]: rl})
		_check(_near(arena.special_radius(hero), r0 * (1.0 + v / 100.0)), "%s radius" % w)
	# and it really reaches: the bow's rain hits a foe just outside its usual ring
	_equip("bow")
	var r0: float = arena.special_radius(hero)
	var out := _ell(P, r0 + 18.0 + r0 * v / 200.0)
	var e := _dummy(D * 250.0 + out)
	_cast(START + D * 250.0)
	_check(_taken(e) == 0.0, "outside the rain without the card")
	_equip("bow", 0, {b["id"]: rl})
	e = _dummy(D * 250.0 + out)
	_cast(START + D * 250.0)
	_check(_taken(e) > 0.0, "inside the wider rain")

func _boon_crit(b: Dictionary, rl: Array, v: float) -> void:
	_equip("spear", 0, {b["id"]: rl})
	hero.recompute_stats()
	var chance: float = hero.stats["crit"]
	_check(_near(chance, 5.0 + v), "crit chance %.1f" % chance)
	var n := 0
	for s in range(4000):
		if arena._crit(hero.key, s, 7, chance):
			n += 1
	_check(absf(n / 40.0 - chance) < 2.5, "crit rate %.1f%% (want %.0f%%)" % [n / 40.0, chance])

func _boon_armor(b: Dictionary, rl: Array, v: float) -> void:
	_equip("spear", 0, {b["id"]: rl})
	hero.take_hit(100.0, hero.position + D * 50.0)
	_check(_near(hero.max_hp - hero.hp, 100.0 * (1.0 - v / 100.0)), "took %.1f of 100" % (hero.max_hp - hero.hp))

func _boon_dash_charges(b: Dictionary, rl: Array, v: float) -> void:
	_equip("spear", 0, {b["id"]: rl})
	var n := 0
	for i in range(6):
		pad.dash = true
		_step(1, true)
		pad.dash = false
		if hero.state == "dash":
			n += 1
		_step(12, true)
		hero.dash_recharge = 99.0 # no refill during the test
	_check(n == 1 + int(v), "dashed %d times in a row (want %d)" % [n, 1 + int(v)])


# ---------------------------------------------------------------- forge cards

func _test_forge() -> void:
	for f in Game.FORGE:
		_begin(String(f["id"]))
		for rl in _levels(f):
			var v := _v(f, rl)
			_text_has(f, rl, v)
			call("_forge_" + String(f["id"]), f, rl, v)

func _forge_spear_echo(f: Dictionary, rl: Array, v: float) -> void:
	_equip("spear")
	var base := _special_total("spear")
	_equip("spear", 0, {f["id"]: rl})
	var got := _special_total("spear")
	_check(_near(got - base, 30.0 * v / 100.0), "second flare %.1f" % (got - base))

func _dash_strike(f: Dictionary, rl: Array, v: float, w: String) -> void:
	_equip(w)
	var e := _dummy(D * 120.0)
	_act("dash")
	_check(_taken(e) == 0.0, "no strike without the card")
	_equip(w, 0, {f["id"]: rl})
	e = _dummy(D * 120.0)
	_act("dash")
	_check(_near(_taken(e), v), "dash strike %.1f" % _taken(e))

func _forge_spear_comet(f: Dictionary, rl: Array, v: float) -> void:
	_dash_strike(f, rl, v, "spear")

func _forge_twin_step(f: Dictionary, rl: Array, v: float) -> void:
	_dash_strike(f, rl, v, "twin")

func _reach_test(f: Dictionary, rl: Array, v: float, w: String) -> void:
	_equip(w)
	var reach: float = float(hero.wdef["reach"])
	# a foe just beyond the usual reach, inside the longer one
	var d := reach + 18.0 + reach * v / 200.0
	var off := D * sqrt(maxf(0.0, d * d - 400.0)) + Vector2(0, 0)
	var e := _dummy(off)
	_act("attack1")
	_check(_taken(e) == 0.0, "out of reach without the card")
	_equip(w, 0, {f["id"]: rl})
	e = _dummy(off)
	_act("attack1")
	_check(_taken(e) > 0.0, "reached with +%d%%" % int(v))

func _forge_spear_haft(f: Dictionary, rl: Array, v: float) -> void:
	_reach_test(f, rl, v, "spear")
	# Cinder Whirl reaches farther too
	_equip("spear")
	var r0: float = hero.whirl_radius()
	var off := _ell(D, r0 + 18.0 + r0 * v / 200.0)
	var e := _dummy(off)
	_act("whirl", D, Vector2(1.0, 0.0))
	_check(_taken(e) == 0.0, "outside the whirl without the card")
	_equip("spear", 0, {f["id"]: rl})
	e = _dummy(off)
	_act("whirl", D, Vector2(1.0, 0.0))
	_check(_taken(e) > 0.0, "inside the longer whirl")

func _forge_scythe_chain(f: Dictionary, rl: Array, v: float) -> void:
	_reach_test(f, rl, v, "scythe")

func _forge_spear_cinder(f: Dictionary, rl: Array, v: float) -> void:
	var got := []
	for cards in [{}, {f["id"]: rl}]:
		_equip("spear", 0, cards)
		var e := _dummy(D * 250.0)
		_seq += 1
		arena._start_cast(hero, hero.position, D, START + D * 250.0, _seq, arena.MODE_AUTH)
		_step(60) # thrown and lodged
		var h0 := _taken(e)
		_step(180) # 3 s lodged
		got.append(_taken(e) - h0)
		_check(not arena.casts.is_empty(), "lance still lodged")
	_check(_near(got[1] - got[0], 3.0 * v, 0.12), "burning ground %.1f in 3 s (want ~%.1f)" % [got[1] - got[0], 3.0 * v])

func _forge_twin_wane(f: Dictionary, rl: Array, v: float) -> void:
	_equip("twin")
	var base := _special_total("twin")
	_equip("twin", 0, {f["id"]: rl})
	var got := _special_total("twin")
	# one afterimage cut (half the special) grows by v%
	_check(_near(got - base, 26.0 * 0.5 * v / 100.0), "afterimage cut +%.1f" % (got - base))

func _forge_twin_home(f: Dictionary, rl: Array, v: float) -> void:
	_equip("twin")
	var base := _special_total("twin")
	_equip("twin", 0, {f["id"]: rl})
	var got := _special_total("twin")
	_check(_near(got - base, 26.0 * v / 100.0), "homeward crescent %.1f" % (got - base))

func _forge_twin_quick(f: Dictionary, rl: Array, v: float) -> void:
	var n0 := _flurry({})
	var n1 := _flurry({f["id"]: rl})
	_equip("twin", 0, {f["id"]: rl})
	var want := 0.2 / (1.0 + v / 100.0)
	_check(_near(hero._swing_cd(), want), "swing time %.3f" % hero._swing_cd())
	# a swing every ceil(cd / frame) frames while ATTACK is held
	var expect: float = 240.0 / ceil(want / DT - 0.001)
	_check(absf(n1 - expect) <= 1.5 and absf(n0 - 240.0 / 12.0) <= 1.5, "%d swings in 4 s (base %d, want ~%.1f)" % [n1, n0, expect])

## Swings in 4 s of holding ATTACK (Moonfang's flurry).
func _flurry(cards: Dictionary) -> int:
	_equip("twin", 0, cards)
	var s0: int = hero.seq
	pad.attack = true
	_step(240, true)
	_pad_clear()
	return hero.seq - s0

func _forge_bow_pierce(f: Dictionary, rl: Array, v: float) -> void:
	for full in [false, true]:
		_equip("bow", 0, {f["id"]: rl})
		var line := []
		for k in range(10):
			line.append(_dummy(D * (100.0 + 58.0 * k)))
		_shoot(1.0 if full else 0.0)
		var n := 0
		for e in line:
			if _taken(e) > 0.0:
				n += 1
		var want := (1 + int(v)) + (1 if full else 0)
		_check(n == mini(want, 10), "%s shot hit %d foes (want %d)" % ["drawn" if full else "quick", n, want])

func _forge_bow_split(f: Dictionary, rl: Array, v: float) -> void:
	_equip("bow", 0, {f["id"]: rl})
	_seq += 1
	arena._spawn_arrows(hero, hero.position, D, 1.0, _seq, arena.MODE_AUTH)
	_check(arena.hshots.size() == 1 + int(v), "drawn shot: %d arrows" % arena.hshots.size())
	arena.hshots.clear()
	arena._spawn_arrows(hero, hero.position, D, 0.0, _seq + 1, arena.MODE_AUTH)
	_check(arena.hshots.size() == 1, "quick shot stays single")
	arena.hshots.clear()

func _draw_frames(cards: Dictionary, w := "bow", a := 0) -> int:
	_equip(w, a, cards)
	pad.attack = true
	var n := 0
	for i in range(300):
		_step(1, true)
		if hero.state in ["draw", "hold"]:
			n += 1
			if hero.charge >= 1.0:
				break
	_pad_clear()
	_step(5, true)
	return n

func _forge_bow_draw(f: Dictionary, rl: Array, v: float) -> void:
	var n0 := _draw_frames({})
	var n1 := _draw_frames({f["id"]: rl})
	_check(absf(n1 - n0 / (1.0 + v / 100.0)) <= 1.5, "full draw in %d frames (base %d)" % [n1, n0])

func _volley_waves(cards: Dictionary, a := 0) -> int:
	_equip("bow", a, cards)
	var e := _dummy(D * 250.0)
	_cast(START + D * 250.0)
	return int(round(_taken(e) / (22.0 * 0.55)))

func _forge_bow_rain(f: Dictionary, rl: Array, v: float) -> void:
	_check(_volley_waves({}) == 3, "base volley 3 waves")
	_check(_volley_waves({f["id"]: rl}) == 3 + int(v), "volley %d waves" % _volley_waves({f["id"]: rl}))

func _ricochets(cards: Dictionary, a := 0) -> int:
	_equip("shield", a, cards)
	var tgt := _dummy(D * 250.0)
	var others := []
	for k in range(7):
		var ang := -1.2 + 2.4 * k / 6.0
		others.append(_dummy(D * 250.0 + D.rotated(ang) * 170.0))
	_cast(START + D * 250.0, 900)
	var n := 0
	for o in others:
		if _taken(o) > 0.0:
			n += 1
	_check(_taken(tgt) > 0.0, "the aimed foe is struck")
	return n

func _forge_shield_rebound(f: Dictionary, rl: Array, v: float) -> void:
	_check(_ricochets({}) == 2, "base: 2 ricochets")
	var n := _ricochets({f["id"]: rl})
	_check(n == mini(2 + int(v), 7), "ricochets to %d foes (want %d)" % [n, 2 + int(v)])

func _spin_time(cards: Dictionary, a := 0) -> float:
	_equip("shield", a, cards)
	_dummy(D * 250.0)
	_seq += 1
	arena._start_cast(hero, hero.position, D, START + D * 250.0, _seq, arena.MODE_AUTH)
	var t := 0.0
	for i in range(1200):
		_step(1)
		if arena.casts.is_empty():
			break
		if int(arena.casts[0]["stage"]) == 3:
			t += DT
	return t

func _forge_shield_anchor(f: Dictionary, rl: Array, v: float) -> void:
	_check(_spin_time({}) == 0.0, "no spin without the card")
	var t := _spin_time({f["id"]: rl})
	_check(absf(t - v) <= 0.05, "spun %.2f s (want %.1f)" % [t, v])

func _forge_shield_rush(f: Dictionary, rl: Array, v: float) -> void:
	for act in ["attack0", "dawn"]:
		var got := []
		for cards in [{}, {f["id"]: rl}]:
			_equip("shield", 0, cards)
			var e := _dummy(D * 120.0)
			_act(act, D, Vector2(1.0, 0.0))
			got.append(_taken(e))
		_check(_near(got[1], got[0] * (1.0 + v / 100.0)), "%s %.1f vs %.1f" % [act, got[1], got[0]])
	# and farther: a foe beyond the plain rush lane is reached
	_equip("shield")
	var e := _dummy(D * 262.0)
	_act("attack0")
	var plain := _taken(e)
	_equip("shield", 0, {f["id"]: rl})
	e = _dummy(D * 262.0)
	_act("attack0")
	_check(plain == 0.0 and _taken(e) > 0.0, "the rush reaches farther")

func _forge_shield_guard(f: Dictionary, rl: Array, v: float) -> void:
	var n0 := _draw_frames({}, "shield")
	var n1 := _draw_frames({f["id"]: rl}, "shield")
	_check(absf(n1 - n0 / (1.0 + v / 100.0)) <= 1.5, "Dawnbreak charged in %d frames (base %d)" % [n1, n0])

func _forge_scythe_hook(f: Dictionary, rl: Array, v: float) -> void:
	_equip("scythe")
	var e := _dummy(D * 110.0)
	_act("attack1")
	var base := _taken(e)
	var knock0: Vector2 = e._knock
	_equip("scythe", 0, {f["id"]: rl})
	e = _dummy(D * 110.0)
	_act("attack1")
	_check(_near(_taken(e), base * (1.0 + v / 100.0)), "sweep %.1f vs %.1f" % [_taken(e), base])
	_check(knock0.dot(D) > 0.0 and e._knock.dot(D) < 0.0, "dragged toward her (knock %s, plain %s)" % [e._knock, knock0])

func _hook(cards: Dictionary, far: float) -> Array:
	_equip("scythe", 0, cards)
	hero.hp = 30.0
	var a := _dummy(D * 150.0)
	var b := _dummy(D * far)
	pad.special = true
	pad.special_aim = D
	_step(2, true)
	pad.special = false
	_step(70, true)
	_pad_clear()
	return [_taken(a) > 0.0, _taken(b) > 0.0, hero.hp - 30.0, a, b]

func _forge_scythe_maw(f: Dictionary, rl: Array, v: float) -> void:
	var far := 380.0 + 80.0 + 380.0 * v / 200.0 # beyond the plain chain's catch, inside the longer one
	var r0 := _hook({}, far)
	_check(r0[0] and not r0[1], "plain chain stops short")
	var r1 := _hook({f["id"]: rl}, far)
	_check(r1[0] and r1[1], "the longer chain hooks the far foe")

func _forge_scythe_soul(f: Dictionary, rl: Array, v: float) -> void:
	var r0 := _hook({}, 250.0)
	_check(r0[0] and r0[1] and r0[2] == 0.0, "no heal without the card")
	var r1 := _hook({f["id"]: rl}, 250.0)
	_check(_near(r1[2], 2.0 * v), "healed %.1f for 2 foes" % r1[2])


# ---------------------------------------------------------------- aspects

func _test_aspects() -> void:
	# Emberlance
	_begin("aspect spear 0 Cinders")
	_equip("spear", 0)
	_check(hero.aim_range() == 420.0, "plain throw range")
	_begin("aspect spear 1 Comet")
	_equip("spear", 0)
	var r0: float = arena.special_radius(hero)
	_equip("spear", 1)
	_check(_near(hero.aim_range(), 420.0 * 1.35), "throw range %.0f" % hero.aim_range())
	_check(_near(arena.special_radius(hero), r0 * 1.3), "flare radius")
	var e := _dummy(_ell(D, 400.0) + _ell(P, r0 * 1.15 + 18.0))
	_cast(START + _ell(D, 400.0), 120)
	_check(_taken(e) > 0.0, "the wider flare reaches")
	_begin("aspect spear 2 Pyre")
	_equip("spear", 2)
	e = _dummy(D * 60.0)
	_act("attack1")
	_check(_near(float(e.burn_dps), 6.0), "strikes burn 6/s")
	_equip("spear", 2)
	e = _dummy(D * 250.0)
	_seq += 1
	arena._start_cast(hero, hero.position, D, START + D * 250.0, _seq, arena.MODE_AUTH)
	_step(60)
	_check(arena.pools.size() == 1 and _near(float(arena.pools[0][2]), 12.0), "lodged lance burns the ground (12/s)")
	# Moonfang
	_begin("aspect twin 0 Moonfall")
	_equip("twin", 0)
	_check(int(hero.stats["w_multi"]) == 0, "no twist")
	_begin("aspect twin 1 Eclipse")
	_equip("twin", 0)
	var base := _special_total("twin")
	_equip("twin", 1)
	hero.stats["crit"] = 0
	var got := _special_total("twin")
	_check(_near(got - base, 13.0), "one more afterimage cut (+%.1f)" % (got - base))
	_equip("twin", 1)
	hero.recompute_stats()
	_check(_near(hero.stats["crit"], 15.0), "crit 5+10")
	_begin("aspect twin 2 Tidewane")
	_equip("twin", 2)
	_check(hero.dash_charges == 2, "2 dash charges")
	e = _dummy(D * 120.0)
	_act("dash")
	_check(_near(_taken(e), 20.0), "dash slash 20 (%.1f)" % _taken(e))
	# Starwhisper
	_begin("aspect bow 0 Huntress")
	_check(_volley_waves({}, 0) == 3, "3 waves")
	_begin("aspect bow 1 Starfall")
	_equip("bow", 0)
	r0 = arena.special_radius(hero)
	_equip("bow", 1)
	_check(_near(arena.special_radius(hero), r0 * 1.4), "rain 40% wider")
	_check(_volley_waves({}, 1) == 4, "one more wave")
	_begin("aspect bow 2 Gale")
	var n0 := _draw_frames({}, "bow", 0)
	var n1 := _draw_frames({}, "bow", 2)
	_check(absf(n1 - n0 / 1.35) <= 1.5, "draws 35%% faster (%d vs %d frames)" % [n1, n0])
	_equip("bow", 2)
	var line := []
	for k in range(10):
		line.append(_dummy(D * (100.0 + 58.0 * k)))
	_shoot(1.0)
	var n := 0
	for x in line:
		if _taken(x) > 0.0:
			n += 1
	_check(n == 10, "drawn shot pierces every foe (%d/10)" % n)
	_equip("bow", 2)
	line = []
	for k in range(4):
		line.append(_dummy(D * (100.0 + 58.0 * k)))
	_shoot(0.0)
	n = 0
	for x in line:
		if _taken(x) > 0.0:
			n += 1
	_check(n == 1, "quick shots do not pierce (%d)" % n)
	# Aegis
	_begin("aspect shield 0 Bulwark")
	_equip("shield", 0)
	hero.take_hit(100.0, hero.position - D * 50.0) # from behind: not blocked
	_check(_near(hero.max_hp - hero.hp, 90.0), "takes 10%% less (%.1f)" % (hero.max_hp - hero.hp))
	_check(_ricochets({}, 0) == 2, "ricochets to 2")
	_begin("aspect shield 1 Rebound")
	_check(_ricochets({}, 1) == 4, "ricochets to 4")
	_begin("aspect shield 2 Bastion")
	var t := _spin_time({}, 2)
	_check(absf(t - 4.0) <= 0.05, "spins %.2f s" % t)
	# Gravechain
	_begin("aspect scythe 0 Gravewarden")
	_equip("scythe", 0)
	e = _dummy(D * 110.0)
	_act("attack1")
	_check(e._knock.dot(D) > 0.0, "plain sweeps knock back")
	_begin("aspect scythe 1 Tollkeeper")
	_equip("scythe", 1)
	e = _dummy(D * 110.0)
	_act("attack1")
	_check(e._knock.dot(D) < 0.0, "sweeps drag toward her")
	_equip("scythe", 1)
	hero.hp = 40.0
	e = _dummy(D * 110.0, "shade", 1.0)
	_act("attack1")
	_check(_near(hero.hp, 42.0), "kills heal 2 (%.1f)" % hero.hp)
	_begin("aspect scythe 2 Hollow Moon")
	var h0 := _harvest(0, 50.0, 150.0)
	var h1 := _harvest(2, 50.0, 150.0)
	_check(_near(h1, h0 * 2.0), "harvest double damage %.1f vs %.1f" % [h1, h0])
	_equip("scythe", 0)
	r0 = hero.harvest_radius()
	var off := r0 + 18.0 + r0 * 0.15
	_check(_harvest(0, 50.0, off) == 0.0 and _harvest(2, 50.0, off) > 0.0, "harvest 30% wider")

func _harvest(a: int, souls: float, dist: float) -> float:
	_equip("scythe", a)
	var e := _dummy(_ell(D, dist))
	_act("harvest", D, Vector2(souls, 0.0))
	return _taken(e)


# ---------------------------------------------------------------- signature moves (driven with the pad)

func _test_signatures() -> void:
	# Aegis: hold to guard; frontal blows and projectiles are blocked, the back is not; full charge -> Dawnbreak
	_begin("move shield guard")
	_equip("shield")
	pad.attack = true
	_step(50, true)
	_check(hero.state == "hold", "holding ATTACK raises the shield (state %s)" % hero.state)
	var hp0: float = hero.hp
	hero.take_hit(30.0, hero.position + D * 60.0)
	_check(hero.hp == hp0 and hero.blocks == 1 and hero.state == "hold", "a frontal blow is blocked")
	arena.projectiles.append({"id": 1, "pos": hero.position + D * 70.0, "vel": -D * 600.0, "dmg": 20.0, "color": Color.RED, "r": 10.0, "life": 2.0, "src": ""})
	for i in range(12):
		arena._local_damage_checks(DT)
	_check(hero.hp == hp0 and arena.projectiles.is_empty(), "a frontal bolt is stopped")
	hero.take_hit(30.0, hero.position - D * 60.0)
	_check(hero.hp < hp0, "a blow from behind gets through")
	_begin("move shield dawnbreak")
	_equip("shield")
	var e := _dummy(D * 250.0)
	pad.attack = true
	var frames := 0
	for i in range(200):
		_step(1, true)
		if hero.state == "hold" and hero.charge >= 1.0:
			break
		frames += 1
	pad.attack = false
	_step(1, true)
	_check(int(hero.move_count.get("dawn", 0)) == 1, "letting go at full charge unleashes Dawnbreak")
	_check(_near(_taken(e), hero.move_damage("dawn", 1.0)) and _near(_taken(e), 15.0 * 3.0), "Dawnbreak hits %.1f" % _taken(e))
	_equip("shield")
	pad.attack = true
	_step(40, true)
	pad.attack = false
	_step(1, true)
	_check(int(hero.move_count.get("dawn", 0)) == 0 and hero.state == "idle", "an early release just lowers the shield")
	# Emberlance: hold -> Cinder Whirl hits all round; the lance lodges and comes back on SPECIAL
	_begin("move spear whirl")
	_equip("spear")
	var ring := []
	for k in range(4):
		ring.append(_dummy(_ell(D.rotated(k * PI * 0.5 + 0.3), 110.0)))
	hero.attack_cd = 0.25 # (no tap thrust first: only the whirl is measured)
	pad.attack = true
	_step(120, true)
	pad.attack = false
	_step(1, true)
	var all_hit := true
	for x in ring:
		all_hit = all_hit and _near(_taken(x), 14.0 * 3.0)
	_check(int(hero.move_count.get("whirl", 0)) == 1 and all_hit, "a full Cinder Whirl hits all round for 42 (%s)" % [_taken(ring[0])])
	_begin("move spear lance")
	_equip("spear")
	var mid := _dummy(D * 160.0)
	pad.special = true
	pad.special_aim = D * (300.0 / 420.0)
	_step(2, true)
	pad.special = false
	_step(60, true)
	_check(arena.lance_of(hero) != null and int(arena.lance_of(hero)["stage"]) == 2, "the lance lodges")
	var before := _taken(mid)
	pad.special = true
	_step(2, true)
	pad.special = false
	_step(60, true)
	_check(arena.lance_of(hero) == null, "SPECIAL calls it back to her hand")
	_check(_near(_taken(mid) - before, 30.0 * 0.8), "the returning lance cuts %.1f" % (_taken(mid) - before))
	# Moonfang: Moonstep blinks her along the line; ATTACK out of a dash lunges
	_begin("move twin moonstep")
	_equip("twin")
	var lane := _dummy(D * 150.0)
	_blink(START + D * 300.0)
	_check(hero.position.distance_to(START + D * 300.0) < 2.0, "she blinks to the aimed point (%s)" % (hero.position - START))
	_check(_near(_taken(lane), 26.0 + 13.0), "cut + afterimage cut = 39 (%.1f)" % _taken(lane))
	_begin("move twin lunge")
	_equip("twin")
	e = _dummy(D * 300.0)
	pad.dash = true
	_step(1, true)
	pad.dash = false
	_step(4, true)
	pad.attack = true
	_step(1, true)
	pad.attack = false
	_step(30, true)
	_check(int(hero.move_count.get("lunge", 0)) == 1, "ATTACK out of a dash is a Fang Lunge")
	# Starwhisper: a release in the flash after a full draw is a Perfect Shot
	_begin("move bow perfect")
	_equip("bow")
	var line := []
	for k in range(6):
		line.append(_dummy(D * (100.0 + 58.0 * k)))
	pad.attack = true
	for i in range(200):
		_step(1, true)
		if hero.perfect_window():
			break
	pad.attack = false
	_step(60, true)
	var all6 := true
	for x in line:
		all6 = all6 and _near(_taken(x), 20.0 * 2.6 * 1.5)
	_check(all6, "Perfect Shot: 78 to every foe in line (%.1f)" % _taken(line[5]))
	_equip("bow")
	line = []
	for k in range(3):
		line.append(_dummy(D * (100.0 + 58.0 * k)))
	pad.attack = true
	_step(60, true)
	pad.attack = false
	_step(60, true)
	_check(_near(_taken(line[0]), 52.0) and _taken(line[2]) == 0.0, "a late release is a plain drawn shot (52, pierces 1)")
	# Gravechain: sweeps reap Souls; Soul Harvest spends them
	_begin("move scythe souls")
	_equip("scythe")
	for k in range(3):
		_dummy(D.rotated(-0.5 + 0.5 * k) * 100.0)
	_act("attack1")
	_check(_near(hero.souls, 30.0), "3 foes cut -> 30 Souls (%.1f)" % hero.souls)
	e = _dummy(-D * 120.0)
	hero.attack_cd = 0.25
	pad.attack = true
	_step(60, true)
	pad.attack = false
	_step(2, true)
	_check(int(hero.move_count.get("harvest", 0)) == 1 and hero.souls == 0.0, "Soul Harvest spends the Souls")
	_check(_near(_taken(e), 12.0 * (1.0 + 3.0 * 0.3)), "harvest with 30 Souls hits %.1f" % _taken(e))
	_begin("move scythe hook")
	var r := _hook({}, 250.0)
	_check(r[0] and r[1], "the hook catches both foes on its line")
	_check(r[3]._knock.dot(D) < 0.0 and r[4]._knock.dot(D) < 0.0, "and drags them to her")
	_check(_near(_taken(r[3]), 18.0 * 1.5), "hook + rend = 27 (%.1f)" % _taken(r[3]))


# ---------------------------------------------------------------- Vows (meta upgrades)

func _test_meta() -> void:
	_begin("vow vitality")
	Game.data["meta"] = {}
	_equip("spear")
	var m0: int = hero.max_hp
	for rank in range(1, 6):
		Game.data["meta"] = {"vitality": rank}
		hero.recompute_stats()
		_check(hero.max_hp == m0 + 10 * rank, "rank %d: %d" % [rank, hero.max_hp])
	_begin("vow fury")
	for rank in range(0, 6):
		Game.data["meta"] = {"fury": rank}
		_equip("spear")
		var e := _dummy(D * 60.0)
		_act("attack1")
		_check(_near(_taken(e), 14.0 * (1.0 + 0.06 * rank)), "rank %d thrust %.2f" % [rank, _taken(e)])
	_begin("vow swiftness")
	Game.data["meta"] = {}
	var base := _run_dist({})
	for rank in range(1, 4):
		Game.data["meta"] = {"swift": rank}
		_check(_near(_run_dist({}), base * (1.0 + 0.04 * rank), 0.03), "rank %d" % rank)
	_begin("vow defiance")
	Game.data["meta"] = {"defiance": 1}
	_equip("spear")
	hero.defiance_left = Game.meta_rank("defiance")
	hero.hp = 5.0
	hero.take_hit(50.0, hero.position - D * 40.0)
	_check(not hero.downed and _near(hero.hp, hero.max_hp * 0.5), "revived at half health (%.1f)" % hero.hp)
	hero.hp = 5.0
	hero.iframes = 0.0
	hero.take_hit(50.0, hero.position - D * 40.0)
	_check(hero.downed, "only once")
	_begin("vow fortune")
	for rank in range(0, 4):
		Game.data["meta"] = {"fortune": rank}
		Game.run_shards = 50
		Game.run_room = 5
		var s0 := int(Game.data["shards"])
		var earned := Game.end_run(false)
		_check(earned == int(round((50 + 5 * 4) * (1.0 + 0.2 * rank))) and int(Game.data["shards"]) == s0 + earned, "rank %d earned %d" % [rank, earned])
	Game.data["meta"] = {}
	_equip("spear")


# ---------------------------------------------------------------- Mister Wick's wares, chamber rewards

func _ware(kind: String) -> Node2D:
	var o := Ware.new()
	o.kind = kind
	o.price = 1
	add_child(o)
	return o

func _test_shop_and_rewards() -> void:
	var rw = arena.rewards
	const ShopScript := preload("res://scenes/shop.gd")
	_begin("ware Red Draught")
	_equip("spear")
	Game.run_gold = 1000
	hero.hp = 10.0
	rw._buy(_ware("heal"), hero)
	_check(_near(hero.hp, 10.0 + hero.max_hp * 0.5), "restores half (%.1f)" % hero.hp)
	_check(ShopScript.WARES["heal"]["desc"].contains("half"), "text says half")
	_begin("ware Tidal Heart")
	_equip("spear")
	var m0: int = hero.max_hp
	for k in range(1, 5):
		rw._buy(_ware("vigor"), hero)
		_check(hero.max_hp == m0 + 20 * k and hero.hp == hero.max_hp, "draught %d: max %d" % [k, hero.max_hp])
	_begin("ware Pouch of Shards")
	var s0 := Game.run_shards
	rw._buy(_ware("shards"), hero)
	_check(Game.run_shards == s0 + 30 and ShopScript.WARES["shards"]["desc"].contains("30"), "+30 shards")
	_begin("ware Warden's Favour")
	rw._buy(_ware("boon"), hero)
	_check(is_instance_valid(arena.hud.boon_panel), "a boon choice opens")
	_close_panel()
	_begin("ware Forge Token")
	rw._buy(_ware("forge"), hero)
	_check(is_instance_valid(arena.hud.boon_panel), "a forge choice opens")
	_close_panel()
	_begin("ware price")
	var g0 := Game.run_gold
	var w := _ware("heal")
	w.price = 40
	rw._buy(w, hero)
	_check(Game.run_gold == g0 - 40, "gold spent")
	Game.run_gold = 5
	hero.hp = 10.0
	_check(not rw._buy(w, hero) and hero.hp == 10.0 and Game.run_gold == 5, "no coin, no deal")
	_begin("reward Healing Chalice")
	_equip("spear")
	hero.hp = 10.0
	arena._apply_reward("heal", [hero])
	_check(_near(hero.hp, 10.0 + hero.max_hp * Game.REWARD_HEAL_FRAC), "restores %d%%" % int(Game.REWARD_HEAL_FRAC * 100))
	for kind in ["gold", "shards"]:
		_begin("reward " + kind)
		arena.room_clear = true
		rw.spawn(kind, [hero])
		var o = rw.objects.back()
		var before := Game.run_gold if kind == "gold" else Game.run_shards
		_check(String(o.desc).contains(str(o.amount)), "text shows the amount (%s)" % o.desc)
		rw._use(o, hero)
		var after := Game.run_gold if kind == "gold" else Game.run_shards
		_check(after - before == int(o.amount), "+%d" % (after - before))

func _close_panel() -> void:
	if is_instance_valid(arena.hud.boon_panel):
		arena.hud.boon_panel.free()
	arena.hud.boon_panel = null
