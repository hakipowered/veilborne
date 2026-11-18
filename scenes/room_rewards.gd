extends Node2D
## Rewards you can see (Hades-style), owned by the arena (scenes/arena.gd: `rewards`):
## - exit emblems: a glowing painted medallion floats in front of every open exit showing what lies
##   behind it (the Warden's face for a boon, forge, chalice, gold, shards, Mister Wick's purse, the
##   next boss), a champion badge when the chamber holds an elite, a coloured light and a small label;
## - reward objects: a cleared chamber's reward appears in the room (scenes/reward_object.gd) and is
##   applied when a heroine walks up and uses it (gold and shards are picked up by walking over them);
## - the shop: Mister Wick's stall (scenes/shop.gd), three wares bought with gold.
## Rewards are per device (each device's own heroines collect them), like the old instant grant.
##
## arena calls: clear() on room load, spawn(kind, local_heroes) when the chamber is cleared,
## bias_boons(choices) before a boon offer. Tests: bot_target(hero), interact(hero), shop, objects.

const RewardObject := preload("res://scenes/reward_object.gd")
const ShopScript := preload("res://scenes/shop.gd")
const VTheme = preload("res://ui/theme.gd")
const PATRON_IDS := ["oriel", "vessa", "mireth", "sable"]
const GOLD_BASE := 45 ## gold pile: GOLD_BASE + GOLD_PER_CHAPTER * chapter
const GOLD_PER_CHAPTER := 15
const SHARDS_BASE := 15

var arena: Node2D
var objects: Array = [] ## RewardObject nodes waiting to be used (room rewards + shop wares)
var shop: Node2D = null
var boon_patron := "" ## the Warden whose boon this chamber's orb offers ("" = any)
var purchases := 0 ## tests / stats
var used_count := 0
var shop_score := 0.0 ## tests: how cluttered the stall's spot is (0 = clear)

var _local: Array = []
var _glow: Node2D ## additive emblem light (world space)
var _emb: Node2D ## emblem medallions (world space)
var _ui: CanvasLayer
var _prompt_box: PanelContainer
var _prompt_title: Label
var _prompt_desc: Label
var _prompt_btn: Button
var _near: Node2D = null
var _near_hero: Node = null
var _t := 0.0
var _talked := false


func _ready() -> void:
	# the emblems ride a world-following layer above the chamber's edge vignette (layer 2), so the exits
	# glow at full strength at the top of the screen; the HUD (layer 10) stays on top
	var layer := CanvasLayer.new()
	layer.layer = 3
	layer.follow_viewport_enabled = true
	add_child(layer)
	_glow = Node2D.new()
	_glow.material = RewardObject.additive()
	_glow.draw.connect(_draw_glow)
	layer.add_child(_glow)
	_emb = Node2D.new()
	_emb.draw.connect(_draw_emblems)
	layer.add_child(_emb)
	_build_ui()


## The Warden behind a boon reward for chamber `idx` (same on every device).
static func patron_for(idx: int) -> String:
	return PATRON_IDS[posmod(hash("patron:%d:%d" % [Game.run_seed, idx]), PATRON_IDS.size())]


func clear() -> void:
	for o in objects:
		if is_instance_valid(o):
			o.queue_free()
	objects.clear()
	if is_instance_valid(shop):
		shop.queue_free()
	shop = null
	_local = []
	_near = null
	_talked = false
	boon_patron = ""
	_set_prompt()


## The chamber is cleared: put its reward in the room (or open the shop). kind "" opens the exits.
func spawn(kind: String, local: Array) -> void:
	_local = local
	if kind == "shop":
		_open_shop()
		arena._apply_reward("", local)
		return
	if kind == "" or local.is_empty() or not RewardObject.ART.has(kind):
		arena._apply_reward(kind, local)
		return
	var ch := int(arena.plan_room.get("chapter", 1))
	var opts := {}
	match kind:
		"boon":
			boon_patron = patron_for(arena.room_index)
			opts = {"patron": boon_patron, "color": Game.PATRONS[boon_patron]["color"]}
		"heal":
			opts = {"amount": int(round(Game.REWARD_HEAL_FRAC * 100.0))}
		"gold":
			opts = {"amount": GOLD_BASE + GOLD_PER_CHAPTER * ch}
		"shards":
			opts = {"amount": SHARDS_BASE}
	var o := RewardObject.new()
	o.setup(kind, opts)
	o.position = _free_spot()
	arena.entities.add_child(o)
	objects.append(o)
	o.modulate.a = 0.0
	o.scale = Vector2(0.6, 0.6)
	var tw := o.create_tween().set_parallel()
	tw.tween_property(o, "modulate:a", 1.0, 0.5)
	tw.tween_property(o, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	arena.spark(o.position + Vector2(0, -80), o.color, 22)
	arena.hud.float_banner("%s appears" % o.title if kind != "boon" else "A Warden's gift awaits", o.color.lightened(0.2))


## A clear floor spot near the middle of the chamber (off hazards and props, not under the heroines).
func _free_spot() -> Vector2:
	var hero_at := Vector2.INF
	for h in _local:
		if is_instance_valid(h):
			hero_at = h.position
	var half: Vector2 = arena.room_half
	var best := Vector2.ZERO
	var bs := INF
	for i in range(24):
		var ang := i * TAU / 12.0
		var rr := 0.0 if i == 0 else (0.18 if i < 12 else 0.34)
		var p := Vector2(cos(ang) * half.x * rr, sin(ang) * half.y * rr + half.y * 0.05)
		var q: Vector2 = arena.resolve_collision(p, 60.0)
		var score := q.distance_to(p) * 3.0 + q.length() * 0.4
		for probe in [q, q + Vector2(0, 40), q + Vector2(70, 0), q - Vector2(70, 0), q + Vector2(0, 100)]:
			if _hazard_near(probe) or not _on_floor(probe):
				score += 3000.0
		if hero_at != Vector2.INF and q.distance_to(hero_at) < 140.0:
			score += 300.0
		if score < bs:
			bs = score
			best = q
	return best


# ---------------------------------------------------------------- shop

## Mister Wick sets up shop: props and urns standing where the stall goes are moved aside (hidden).
func _clear_props(at: Vector2) -> void:
	var env: Node2D = arena.env
	var area := Rect2(at + Vector2(-400, -300), Vector2(800, 540))
	var ys = env.get("_ysorted")
	if ys is Array:
		for n in ys:
			if is_instance_valid(n) and area.has_point(n.position):
				n.visible = false
	var obs: Array = env.get_obstacles()
	for i in range(obs.size() - 1, -1, -1):
		if not obs[i].has("pit") and area.has_point(obs[i]["pos"]):
			obs.remove_at(i)
	var br = env.get("_breakables")
	if br is Array:
		for b in br:
			if area.has_point(b["pos"]):
				b["broken"] = true
	arena._refresh_props()


## Any floor hazard (lava, water, spikes even while retracted) under p.
## Solid floor (irregular room shapes: not over a chasm or the void), `margin` px in from the edge.
func _on_floor(p: Vector2, margin := 30.0) -> bool:
	var sh = arena.env.get("_shape")
	return sh == null or sh.on_floor(p, margin)


func _hazard_near(p: Vector2) -> bool:
	for hz in arena.env.get_hazards():
		var rc: Rect2 = hz["rect"]
		if rc.grow(30.0).has_point(p) and (Geometry2D.is_point_in_polygon(p, hz["poly"]) or rc.has_point(p)):
			return true
	return false

## Where the stall stands: near the middle, with dry, safe floor in front of the counter and around it.
func _shop_spot() -> Vector2:
	var half: Vector2 = arena.room_half
	var best := Vector2(40, -half.y * 0.12)
	var bs := INF
	var sh = arena.env.get("_shape")
	var area := Rect2(-half, half * 2.0) if sh == null else Rect2(sh.bounds)
	var mid := area.get_center()
	for gy in range(1, 14):
		for gx in range(1, 16):
			var p := area.position + area.size * Vector2(gx / 16.0, gy / 14.0)
			var q: Vector2 = arena.resolve_collision(p, 80.0)
			var score := q.distance_to(p) * 4.0 + q.distance_to(mid) * 0.15
			for off in [Vector2(-220, 60), Vector2(0, 60), Vector2(200, 30), Vector2(0, 180), Vector2(-150, 160),
					Vector2(150, 160), Vector2(-60, -180), Vector2(0, -60), Vector2(280, -80), Vector2(-300, 20),
					Vector2(-200, -40), Vector2(200, -140), Vector2(100, -110), Vector2(-100, 0)]:
				if _hazard_near(q + off) or not _on_floor(q + off, 20.0):
					score += 2000.0
				if arena.resolve_collision(q + off, 40.0).distance_to(q + off) > 6.0:
					score += 25.0 # props are cleared away for the stall (_clear_props); walls are not
			if score < bs:
				bs = score
				best = q
	shop_score = bs
	return best


func _open_shop() -> void:
	shop = ShopScript.new()
	var at := _shop_spot()
	_clear_props(at)
	shop.position = at
	arena.entities.add_child(shop)
	shop.build(hash("shop:%d:%d" % [Game.run_seed, arena.room_index]))
	var obs: Array = arena.env.get_obstacles()
	for o in shop.obstacles():
		obs.append(o)
	for it in shop.items:
		objects.append(it)
	for h in _local:
		if is_instance_valid(h):
			h.position = arena.resolve_collision(h.position, 30.0)
	arena.hud.float_banner("Mister Wick's Wares", Color(0.75, 1.0, 0.55))
	_greet()


func _greet() -> void:
	if _talked:
		return
	_talked = true
	var story: Dictionary = Game.data.get("story", {}) if Game.data.has("story") else {}
	var flags: Dictionary = story.get("flags", {}) if story.get("flags", null) is Dictionary else {}
	if not flags.get("met_wick", false):
		flags["met_wick"] = true
		story["flags"] = flags
		if Game.data.has("story"):
			Game.data["story"] = story
			Game.save_slot()
		var hero_id := "kaela"
		for h in _local:
			if is_instance_valid(h):
				hero_id = String(h.hero_id)
		var lines: Array = []
		for l in ShopScript.INTRO:
			lines.append({"speaker": hero_id if l[0] == "{hero}" else l[0], "text": l[1]})
		arena._play_lines(lines, func(): pass)
	else:
		_say(ShopScript.line_for(ShopScript.GREET))


func _say(text: String) -> void:
	arena.hud.subtitle("“%s”  — Mister Wick" % text, Color(0.78, 1.0, 0.6))


func _buy(o: Node2D, h: Node) -> bool:
	if Game.run_gold < o.price:
		_say(ShopScript.BROKE)
		VTheme.sound("back")
		return false
	Game.run_gold -= o.price
	purchases += 1
	VTheme.sound("purchase")
	match o.kind:
		"boon":
			boon_patron = ""
			arena._offer_next([h], "boon")
		"forge":
			arena._offer_next([h], "forge")
		"heal":
			var amt: float = h.max_hp * ShopScript.WARE_HEAL
			h.heal(amt)
			arena.float_text(h.position + Vector2(0, -130), "+%d" % int(amt), Color(0.45, 1, 0.6))
		"vigor":
			# a flat +20 max health every time (not a Tidal Heart card level, which would give +15 or nothing)
			h.boons["_vigor"] = int(h.boons.get("_vigor", 0)) + 1
			h.recompute_stats()
			h.sync_boons()
			h.heal(h.max_hp)
			arena.hud.refresh()
			arena.float_text(h.position + Vector2(0, -130), "+max health", Color(0.45, 1, 0.8))
		"shards":
			Game.run_shards += ShopScript.WARE_SHARDS
			arena.float_text(h.position + Vector2(0, -130), "+%d shards" % ShopScript.WARE_SHARDS, Color(0.6, 0.85, 1.0))
	_say(ShopScript.line_for(ShopScript.THANKS))
	return true


# ---------------------------------------------------------------- using rewards

## Uses the reward / ware nearest to heroine h (within reach). Returns true when something was used.
func interact(h: Node = null) -> bool:
	if h == null:
		h = _near_hero
	var o := _nearest(h)
	if o == null or not is_instance_valid(h):
		return false
	_use(o, h)
	return true


func _use(o: Node2D, h: Node) -> void:
	if o.taken:
		return
	if o.price > 0:
		if not _buy(o, h):
			return
	else:
		used_count += 1
		_grant(o, h)
	o.consume()
	objects.erase(o)
	arena.spark(o.position + o.art_offset + Vector2(0, -60), o.color, 26)
	if _near == o:
		_near = null
		_set_prompt()


func _grant(o: Node2D, h: Node) -> void:
	match o.kind:
		"gold":
			Game.run_gold += o.amount
			arena.sfx("shard_pickup")
			arena.float_text(o.position + Vector2(0, -110), "+%d gold" % o.amount, Color(1.0, 0.85, 0.35))
			arena.hud.float_banner("+%d Gilded Coin" % o.amount, Color(1.0, 0.85, 0.35))
			arena._open_doors()
		"shards":
			Game.run_shards += o.amount
			arena.sfx("shard_pickup")
			arena.float_text(o.position + Vector2(0, -110), "+%d shards" % o.amount, Color(0.6, 0.85, 1.0))
			arena.hud.float_banner("+%d Veil Shards" % o.amount, Color(0.6, 0.85, 1.0))
			arena._open_doors()
		_:
			# boon / forge / heal: the arena's grant (cards for every local heroine, or the heal)
			var who: Array = []
			for x in _local:
				if is_instance_valid(x):
					who.append(x)
			if who.is_empty():
				who = [h]
			arena._apply_reward(o.kind, who)


## Keeps the boon orb's promise: the offer leads with a card from the Warden shown on the exit.
func bias_boons(choices: Array) -> Array:
	if boon_patron == "" or choices.is_empty():
		return choices
	for i in range(choices.size()):
		if String(Game.boon_by_id(String(choices[i]["id"])).get("patron", "")) == boon_patron:
			if i > 0:
				var c = choices[i]
				choices.remove_at(i)
				choices.push_front(c)
			return choices
	var ids: Array = []
	for c in choices:
		ids.append(String(c["id"]))
	var owned: Dictionary = {}
	for h in _local:
		if is_instance_valid(h):
			owned = h.boons
	var max_lvl: int = Game.CARD_MAX_LEVEL
	var pool: Array = []
	for b in Game.BOONS:
		if String(b["patron"]) == boon_patron and not ids.has(String(b["id"])) \
				and int(owned.get(b["id"], {}).get("level", 0)) < max_lvl:
			pool.append(b)
	if pool.is_empty():
		return choices
	var b: Dictionary = pool[posmod(hash("%d:%d" % [Game.run_seed, arena.room_index]), pool.size())]
	var r := int(choices[0].get("rarity", 0))
	choices[0] = Game._choice(String(b["id"]), r, owned.get(b["id"], {}))
	return choices


func _nearest(h: Node) -> Node2D:
	if not is_instance_valid(h):
		return null
	var best: Node2D = null
	var bd := INF
	for o in objects:
		if not is_instance_valid(o) or o.taken:
			continue
		var d: float = h.position.distance_to(o.global_position)
		if d < o.reach and d < bd:
			bd = d
			best = o
	return best


## Tests / bot: where heroine h should walk next (Vector2.INF when nothing is left to collect or buy).
## In a shop the bot buys the first ware it can afford, once.
func bot_target(h: Node) -> Vector2:
	for o in objects:
		if not is_instance_valid(o) or o.taken:
			continue
		if o.price > 0 and (Game.run_gold < o.price or purchases > 0):
			continue
		return o.global_position
	return Vector2.INF


func has_pending() -> bool:
	for o in objects:
		if is_instance_valid(o) and not o.taken and o.price <= 0:
			return true
	return false


func _physics_process(delta: float) -> void:
	_t += delta
	if arena == null or arena.run_over:
		return
	var nh: Node = null
	var no: Node2D = null
	var bd := INF
	for h in arena.heroes():
		if not (is_instance_valid(h) and h.controlled and not h.downed):
			continue
		var o := _nearest(h)
		if o == null:
			continue
		if o.auto:
			_use(o, h)
			continue
		var d: float = h.position.distance_to(o.global_position)
		if d < bd:
			bd = d
			no = o
			nh = h
	_near_hero = nh
	if no != _near:
		if is_instance_valid(_near):
			_near.set_near(false)
		_near = no
		if _near:
			_near.set_near(true)
		_set_prompt()
	elif _near and _near.price > 0 and Engine.get_physics_frames() % 15 == 0:
		_refresh_buy()
	_glow.queue_redraw()
	_emb.queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if _near == null or get_tree().paused:
		return
	var go := false
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		go = k == KEY_E or k == KEY_F or k == KEY_ENTER or k == KEY_KP_ENTER
	elif event is InputEventJoypadButton and event.pressed:
		go = event.button_index == JOY_BUTTON_B
	if go:
		get_viewport().set_input_as_handled()
		interact(_near_hero)


# ---------------------------------------------------------------- prompt (the manor's style)

func _build_ui() -> void:
	_ui = CanvasLayer.new()
	_ui.layer = 11
	add_child(_ui)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = VTheme.get_theme()
	_ui.add_child(root)
	_prompt_box = PanelContainer.new()
	_prompt_box.theme_type_variation = "PanelSm"
	_prompt_box.visible = false
	root.add_child(_prompt_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	_prompt_box.add_child(v)
	_prompt_title = VTheme.label("", "Caps", 15)
	_prompt_title.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	_prompt_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_prompt_title)
	_prompt_desc = VTheme.label("", "Dim", 15)
	_prompt_desc.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_prompt_desc.custom_minimum_size = Vector2(300, 0)
	v.add_child(_prompt_desc)
	_prompt_btn = Button.new()
	_prompt_btn.theme_type_variation = "SmallButton"
	_prompt_btn.custom_minimum_size = Vector2(0, 54)
	_prompt_btn.focus_mode = Control.FOCUS_NONE
	_prompt_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_prompt_btn.pressed.connect(func(): interact(_near_hero))
	VTheme.juice(_prompt_btn, 1.05, "click")
	v.add_child(_prompt_btn)
	root.resized.connect(_fit_prompt)


func _touch_ui() -> bool:
	return arena != null and arena.hud != null and arena.hud.touch != null


func _set_prompt() -> void:
	if _prompt_box == null:
		return
	if _near == null or not is_instance_valid(_near):
		_prompt_box.visible = false
		return
	_prompt_box.visible = true
	_prompt_title.text = _near.title.to_upper()
	_prompt_desc.text = _near.desc
	_refresh_buy()
	_fit_prompt()
	_fit_prompt.call_deferred()
	_prompt_box.modulate.a = 0.0
	_prompt_box.create_tween().tween_property(_prompt_box, "modulate:a", 1.0, 0.15)


func _refresh_buy() -> void:
	if _near == null or not is_instance_valid(_near):
		return
	var label: String = _near.verb
	if _near.price > 0:
		label = "%s (%d gold)" % [_near.verb, _near.price]
		_prompt_btn.disabled = Game.run_gold < _near.price
	else:
		_prompt_btn.disabled = false
	_prompt_btn.text = ("[E] " if not _touch_ui() else "") + label


func _fit_prompt() -> void:
	if not is_instance_valid(_prompt_box):
		return
	var vs := get_viewport().get_visible_rect().size
	_prompt_box.reset_size()
	var sz := _prompt_box.get_combined_minimum_size()
	_prompt_box.size = sz
	_prompt_box.position = Vector2(roundf((vs.x - sz.x) * 0.5), vs.y - clampf(vs.y * 0.27, 190.0, 300.0) - sz.y)


# ---------------------------------------------------------------- exit emblems

## What an exit leads to: {icon: Texture2D, face: bool, color, label, elite}
func _door_info(k: int) -> Dictionary:
	var rid := String(arena.door_rewards[k]) if k < arena.door_rewards.size() else ""
	var nxt: Dictionary = Game.plan_room(arena.room_index + 1)
	var info: Dictionary = Game.REWARDS.get(rid, {})
	var out := {"color": info.get("color", Color(1, 0.85, 0.55)), "label": String(info.get("name", "")), "face": false,
		"elite": String(nxt.get("type", "")) == "elite" and rid != "shop", "icon": null}
	match rid:
		"boss":
			var spk: String = arena._boss_speaker(arena._boss_kind(int(nxt["chapter"])))
			out["icon"] = VTheme.tex("face_" + spk)
			out["face"] = out["icon"] != null
			if out["icon"] == null:
				out["icon"] = VTheme.tex("portrait_" + spk)
			out["color"] = Color(1.0, 0.35, 0.3)
			out["label"] = arena._enemy_name(arena._boss_kind(int(nxt["chapter"])))
		"boon":
			var p := patron_for(arena.room_index + 1)
			out["icon"] = VTheme.tex("face_" + p)
			out["face"] = true
			out["color"] = Game.PATRONS[p]["color"]
			out["label"] = "%s's Boon" % String(Game.PATRONS[p]["name"]).get_slice(",", 0).get_slice(" ", 0)
		"":
			out["icon"] = VTheme.tex("orb")
		_:
			out["icon"] = VTheme.tex(String(info.get("icon", "orb")))
	return out


func _emblem_at(k: int) -> Vector2:
	var bob := sin(_t * 2.2 + k * 1.7) * 8.0
	return arena.door_points[k] + Vector2(0, -160.0 + bob)


func _emblem_alpha() -> float:
	return 1.0 if arena.door_open else 0.0


func _draw_glow() -> void:
	if arena == null or _emblem_alpha() <= 0.0:
		return
	var g := RewardObject.glow_tex()
	for k in range(arena.door_points.size()):
		var info := _door_info(k)
		var c: Color = info["color"]
		var at := _emblem_at(k)
		var pulse := 0.5 + 0.5 * sin(_t * 2.6 + k)
		var r := 150.0 + 16.0 * pulse
		_glow.draw_texture_rect(g, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c, 0.85 + 0.15 * pulse))
		var r2 := 95.0
		_glow.draw_texture_rect(g, Rect2(at - Vector2(r2, r2), Vector2(r2, r2) * 2.0), false, Color(c.lightened(0.3), 0.7))
		# a soft beam down to the threshold and a light pool on the floor
		var fp: Vector2 = arena.door_points[k]
		_glow.draw_texture_rect(g, Rect2(fp + Vector2(-150, -55), Vector2(300, 110)), false, Color(c, 0.7 + 0.15 * pulse))
		var col := PackedColorArray([Color(c, 0.0), Color(c, 0.0), Color(c, 0.16), Color(c, 0.16)])
		_glow.draw_polygon(PackedVector2Array([at + Vector2(-34, 40), at + Vector2(34, 40), fp + Vector2(70, 0), fp + Vector2(-70, 0)]), col)
		# motes circling the medallion
		for j in range(6):
			var a := _t * 1.3 + j * TAU / 6.0 + k
			var p := at + Vector2(cos(a) * 82.0, sin(a) * 30.0 + sin(_t * 3.0 + j) * 10.0)
			var s := 10.0 + 4.0 * sin(_t * 4.0 + j)
			_glow.draw_texture_rect(g, Rect2(p - Vector2(s, s), Vector2(s, s) * 2.0), false, Color(c.lightened(0.4), 0.8))


func _draw_emblems() -> void:
	if arena == null or _emblem_alpha() <= 0.0:
		return
	var ring := VTheme.tex("ring")
	var font := VTheme.font("caps")
	for k in range(arena.door_points.size()):
		var info := _door_info(k)
		var c: Color = info["color"]
		var at := _emblem_at(k)
		var r := 50.0
		_emb.draw_circle(at, r + 6.0, Color(0.03, 0.01, 0.05, 0.92))
		_emb.draw_circle(at, r + 2.0, Color(c.darkened(0.35), 0.9))
		var tex: Texture2D = info["icon"]
		if tex:
			if info["face"]:
				_emb.draw_texture_rect(tex, Rect2(at - Vector2(r, r), Vector2(r, r) * 2.0), false)
			else:
				var sc := (r * 1.55) / maxf(tex.get_width(), tex.get_height())
				var sz := Vector2(tex.get_width(), tex.get_height()) * sc
				_emb.draw_texture_rect(tex, Rect2(at - sz * 0.5, sz), false)
		if ring:
			var rr := r * 1.36
			_emb.draw_texture_rect(ring, Rect2(at - Vector2(rr, rr), Vector2(rr, rr) * 2.0), false)
		if info["elite"]:
			var sk := VTheme.tex("reward_elite")
			if sk:
				var bs := 54.0
				_emb.draw_texture_rect(sk, Rect2(at + Vector2(r * 0.55, -r * 1.25), Vector2(bs, bs * sk.get_height() / sk.get_width())), false)
		var label := String(info["label"]).to_upper()
		if font and label != "":
			var fs := 19
			var p := at + Vector2(-240, r * 1.36 + 22.0)
			_emb.draw_string_outline(font, p, label, HORIZONTAL_ALIGNMENT_CENTER, 480, fs, 7, Color(0.03, 0.01, 0.04, 0.95))
			_emb.draw_string(font, p, label, HORIZONTAL_ALIGNMENT_CENTER, 480, fs, c.lightened(0.35))
