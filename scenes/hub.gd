extends "res://scenes/arena.gd"
## The Manor: Gran Ysolde's house at the edge of the Hollow, walked between runs (solo).
## Same controls and combat as a run (it reuses the arena's heroine, specials, damage numbers and HUD),
## with the residents at their stations, weapon racks, training dummies, the Vows altar,
## Odo's renovation board and the gate down into the Hollow.
##
## main.gd: hub.setup_hub(hero_id, after_run); hub.start_requested -> start a run; hub.leave_requested -> menus.

signal start_requested
signal leave_requested

const ManorScript := preload("res://scenes/manor.gd")
const DummyScript := preload("res://entities/dummy.gd")
const StoryData := preload("res://data/story.gd")
const NPC_H := 196.0
const GIFT_COST := 15
const NPCS := ["ysolde", "bram", "wren", "odo", "corwin"]

## What the sisters can bring each resident (once per run, bought with gold) and how they take it.
const GIFTS := {
	"ysolde": {"item": "tea_tin", "name": "a tin of proper tea", "line": "Proper tea. Not my tea. Cheeky. ...Thank you, love."},
	"bram": {"item": "whetstone", "name": "a good whetstone", "line": "Oh, that's a lovely stone, that is. Sharp gift. Get it? Sharp."},
	"wren": {"item": "spice_jar", "name": "a jar of black pepper", "line": "Pepper! Real pepper! Don't tell Gran, she'll put it in the tea."},
	"odo": {"item": "lamp_oil", "name": "a flask of lamp oil", "line": "Lamp oil! Darling, you know the way to a renovator's heart."},
	"corwin": {"item": "brass_polish", "name": "brass polish", "line": "Brass polish. For a ghost. ...My buttons have never been so bright. Thank you."},
}

## Short lines when a resident has nothing new to say (story chatter covers the rest).
const IDLE := {
	"bram": ["Racks are oiled, edges are keen. Pick one and hit the dummy. It doesn't mind. Much.",
		"Try every aspect on the straw lad before you take it down the pit, mind."],
	"wren": ["Soup's on. It's always on. Eat before you go, I'm not scraping you off the stairs hungry.",
		"If you see my mum down there, tell her I'm doing the bread properly."],
	"odo": ["Gold in, glory out! Every coin you bring home, I turn into something lovely.",
		"Fitz always said a house needs light. So: lanterns. Lots of lanterns."],
	"corwin": ["The gate opens when you're ready, soldier. Not before. Check your kit.",
		"The pit doesn't sleep. Neither do I. Perks of being dead."],
	"ysolde": [],
}

var is_hub := true ## read by ui/hud.gd (pause menu wording, purse)
var manor: Node2D
var hero: Node2D
var stations: Array = [] ## {id, kind, pos, r, title, actions, node, npc, weapon}
var dummies: Array = []
var ui: CanvasLayer
var after_run := false
var hero_id := "kaela"
var busy := false ## a menu or conversation is open (the world is paused)
var opened: Array = [] ## tests: every station action performed ("bram:talk", "rack_spear:armory", ...)
var dummy_breaks := 0

var _near: Dictionary = {}
var _prompt: HBoxContainer
var _prompt_title: Label
var _prompt_box: PanelContainer
var _panel: Control = null
var _area := ""
var _marks := {} ## npc id -> Label "!"
var _npc_nodes := {} ## npc id -> Node2D
var _rack_icons := {} ## weapon id -> Sprite2D
var _t := 0.0
var _catcher: Node


class InputCatcher extends Node:
	var hub: Node
	func _input(event: InputEvent) -> void:
		if hub and is_instance_valid(hub):
			hub._ui_input(event)


func _ready() -> void:
	super._ready()
	# swap the arena's chamber builder for the manor
	if is_instance_valid(env):
		remove_child(env)
		env.free()
	manor = ManorScript.new()
	env = manor
	add_child(manor)
	move_child(manor, 0)
	camera.zoom = Vector2(0.86, 0.86)
	camera.position_smoothing_speed = 5.0
	_catcher = InputCatcher.new()
	_catcher.hub = self
	_catcher.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_catcher)


func _exit_tree() -> void:
	super._exit_tree()
	if is_inside_tree():
		get_tree().paused = false


## Called by main.gd (and tests) instead of setup().
func setup_hub(p_hero: String, p_after_run := false) -> void:
	after_run = p_after_run
	hero_id = p_hero if Game.HEROES.has(p_hero) else "kaela"
	Game.hero_runtime.clear()
	Game.run_seed = randi()
	Game.players = [{"peer": 1, "local_index": 0, "hero": hero_id}]
	if not (Game.data.get("decor") is Dictionary):
		Game.data["decor"] = {}
	manor.build(entities, Game.data["decor"])
	manor.add_ysorted_props_to(entities)
	room_half = manor.get_bounds_half()
	room_clear = true # no waves, no doors
	wave_delay = 999.0
	_build_stations()
	_spawn_hero(hero_id, ManorScript.w(150, 160))
	_build_ui()
	_music("home")
	_update_area(true)
	if after_run:
		var tw := create_tween()
		tw.tween_interval(0.7)
		tw.tween_callback(_gran_welcome)


func setup(players: Array) -> void:
	# a hub is never a run: route the arena's entry point here
	setup_hub(String(players[0].get("hero", "kaela")) if not players.is_empty() else "kaela")


## The HUD's purse shows the banked shards and gold here (not the run's).
func purse() -> Array:
	return [int(Game.data.get("shards", 0)), int(Game.data.get("gold", 0))]


func abandon() -> void:
	leave_requested.emit()


func on_back_pressed() -> void:
	if _panel:
		_close_panel()


# ---------------------------------------------------------------- heroine

func _spawn_hero(hid: String, at: Vector2) -> void:
	var old_hud := hud
	if is_instance_valid(hero):
		hero_nodes.erase(hero.key)
		hero.queue_free()
	if old_hud and old_hud.root != null:
		# rebuild the HUD for the new heroine (medallion, bars, touch controls)
		old_hud.queue_free()
		hud = HudScript.new()
		add_child(hud)
		hud.arena = self
	hero_id = hid
	var h: Node2D = HeroScript.new()
	h.setup("p1_0", hid, true, 0, self, Game.weapon_for(hid), Game.run_aspect)
	entities.add_child(h)
	h.position = at
	hero_nodes[h.key] = h
	hero = h
	hud.add_local_hero(h)
	hud.build()
	h.touch = hud.touch
	h.sync_boons()
	camera.position = at
	camera.reset_smoothing()
	if is_instance_valid(ui):
		move_child(ui, get_child_count() - 1)


func _swap_sister() -> void:
	var other := "liora" if hero_id == "kaela" else "kaela"
	Game.data["last_hero"] = other
	Game.set_loadout(Game.run_weapon, Game.run_aspect)
	Game.save_slot()
	var at := hero.position
	_spawn_hero(other, at)
	spark(at + Vector2(0, -60), Color(1, 0.85, 0.5), 26)
	hud.float_banner(String(Game.HEROES[other]["name"]).split(" ")[0], StoryData.speaker(other)["color"])
	_set_prompt_refresh()


func _equip(w: String, a: int) -> void:
	Game.set_loadout(w, a)
	Game.save_slot()
	if is_instance_valid(hero):
		hero._apply_weapon(Game.weapon_for(hero_id), Game.run_aspect)
		hero.recompute_stats()
		hero.special_cd = 0.0
		hero.sync_boons()
	for wid in _rack_icons.keys():
		var s: Sprite2D = _rack_icons[wid]
		s.modulate = Color(1.4, 1.25, 1.0) if wid == Game.weapon_for(hero_id) else Color(0.8, 0.75, 0.8, 0.85)


# ---------------------------------------------------------------- stations

func _station(id: String, kind: String, gpos: Vector2, r: float, title: String, actions: Array, extra := {}) -> Dictionary:
	var s := {"id": id, "kind": kind, "pos": ManorScript.w(gpos.x, gpos.y), "r": r, "title": title, "actions": actions}
	s.merge(extra)
	stations.append(s)
	return s


func _build_stations() -> void:
	# residents
	_npc("ysolde", Vector2(-270, 330), ["talk", "gift", "swap"], false)
	_npc("odo", Vector2(400, -200), ["talk", "gift", "renovate"], true)
	_npc("wren", Vector2(-1220, 120), ["talk", "gift"], false)
	_npc("bram", Vector2(-290, -1160), ["talk", "gift", "armory"], false)
	_npc("corwin", Vector2(-760, -1240), ["talk", "gift"], true)
	# Odo's renovation board
	manor.prop(ManorScript.M + "board.png", Vector2(330, -360), 210.0, 55.0)
	_station("board", "board", Vector2(330, -330), 170.0, "Odo's Renovation Board", ["renovate"])
	# weapon racks (one per weapon) along the armory's back wall
	var us := [-190, -30, 130, 290, 440]
	for i in range(Game.WEAPON_ORDER.size()):
		var wid: String = Game.WEAPON_ORDER[i]
		var gp := Vector2(us[i], -1430)
		manor.prop(ManorScript.ENV + "forge/rack.png", gp, 180.0, 50.0, "", i % 2 == 1)
		var icon := Sprite2D.new()
		icon.texture = VTheme.tex(String(Game.WEAPONS[wid]["icon"]))
		icon.position = ManorScript.w(gp.x, gp.y) + Vector2(0, -230)
		icon.scale = Vector2(0.42, 0.42)
		icon.z_index = 4
		add_child(icon)
		_rack_icons[wid] = icon
		_station("rack_" + wid, "rack", gp + Vector2(70, 70), 130.0, String(Game.WEAPONS[wid]["name"]), ["armory"], {"weapon": wid})
	# training dummies
	var spots := [Vector2(140, -820), Vector2(330, -930), Vector2(170, -1120)]
	for i in range(spots.size()):
		var d: Node2D = DummyScript.new()
		var eid := 900 + i
		d.setup(eid, self, ManorScript.w(spots[i].x, spots[i].y))
		entities.add_child(d)
		enemy_nodes[eid] = d
		dummies.append(d)
	# the Vows altar
	manor.prop(ManorScript.M + "altar.png", Vector2(-1220, -760), 230.0, 75.0)
	manor._add_light(ManorScript.w(-1220, -760) + Vector2(0, -60), Color(0.45, 0.75, 1.0), 460.0, 0.9, 0.15)
	_station("altar", "altar", Vector2(-1130, -680), 170.0, "The Vow Ledger", ["vows"])
	# the gate down into the Hollow
	manor.prop("res://art/fx/veil_arch.webp", Vector2(-1400, -1400), 400.0, 70.0)
	manor._add_light(ManorScript.w(-1400, -1400) + Vector2(0, -120), Color(0.7, 0.45, 1.0), 560.0, 1.1, 0.2)
	_station("gate", "gate", Vector2(-1270, -1270), 170.0, "The Gate to the Hollow", ["descend"])
	_equip(Game.weapon_for(hero_id), Game.run_aspect)


func _npc(id: String, gpos: Vector2, actions: Array, flip: bool) -> void:
	var tex: Texture2D = VTheme.portrait_tex(id)
	var h := NPC_H
	if id == "ysolde": # painted full-body sprite (the portrait is a bust)
		tex = load("res://art/env/manor/ysolde_full.png")
		h = NPC_H * 1.12
	var holder := Node2D.new()
	holder.position = ManorScript.w(gpos.x, gpos.y)
	var sh := Sprite2D.new()
	sh.texture = manor._shadow
	sh.scale = Vector2(1.9, 0.7)
	holder.add_child(sh)
	var s := Sprite2D.new()
	s.name = "Art"
	s.texture = tex
	s.centered = false
	var sc := h / tex.get_height()
	s.scale = Vector2(sc * (-1.0 if flip else 1.0), sc)
	s.offset = Vector2(-tex.get_width() * 0.5, -tex.get_height() * 0.985)
	if id == "corwin":
		s.modulate = Color(0.85, 1.0, 1.1, 0.88)
	holder.add_child(s)
	var mark := VTheme.title_label("!", 46, VTheme.GOLD_BRIGHT, 10, "display")
	mark.position = Vector2(-20, -NPC_H - 50)
	mark.size = Vector2(40, 60)
	mark.visible = false
	holder.add_child(mark)
	_marks[id] = mark
	entities.add_child(holder)
	_npc_nodes[id] = holder
	manor._obstacles.append([gpos, 34.0, ""])
	var nm := String(StoryData.speaker(id).get("name", id.capitalize()))
	_station(id, "npc", gpos + Vector2(40, 40), 150.0, nm, actions, {"npc": id})


# ---------------------------------------------------------------- frame

func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	_t += delta
	if is_instance_valid(hero):
		manor.focus = hero.position
	_update_near()
	_update_area()


func _process(delta: float) -> void:
	# idle life: residents breathe and sway, "!" marks bob, rack icons float
	var t := Time.get_ticks_msec() * 0.001
	var i := 0
	for id in _npc_nodes.keys():
		var n: Node2D = _npc_nodes[id]
		var art: Sprite2D = n.get_node("Art")
		var base := NPC_H / art.texture.get_height()
		art.scale.y = base * (1.0 + 0.012 * sin(t * 2.1 + i))
		art.position.y = -3.0 * absf(sin(t * 1.05 + i)) if id != "corwin" else -10.0 + 8.0 * sin(t * 1.4)
		var m: Label = _marks[id]
		m.position.y = -NPC_H - 50 + sin(t * 4.0 + i) * 6.0
		i += 1
	for wid in _rack_icons.keys():
		var s: Sprite2D = _rack_icons[wid]
		s.offset.y = sin(t * 2.0 + wid.length()) * 10.0
	if Engine.get_process_frames() % 30 == 0:
		_refresh_marks()


func _refresh_marks() -> void:
	var p := StoryDB.from_save(Game.data)
	for id in _marks.keys():
		_marks[id].visible = StoryDB.has_new(id, p)


func _update_area(force := false) -> void:
	if not is_instance_valid(hero):
		return
	var a: String = manor.area_at(hero.position)
	if a != _area or force:
		_area = a
		hud.set_room_name(String(ManorScript.AREAS[a]["title"]))


func _update_near() -> void:
	if busy or not is_instance_valid(hero):
		return
	var best := {}
	var bd := INF
	for s in stations:
		var d := hero.position.distance_to(s["pos"])
		if d < float(s["r"]) and d < bd:
			bd = d
			best = s
	if best.get("id", "") != _near.get("id", ""):
		_near = best
		_set_prompt()


## The nearest station's id ("" when none): tests / tools.
func near_id() -> String:
	return String(_near.get("id", ""))


# ---------------------------------------------------------------- UI: prompt, panels

const ACTION_NAMES := {"talk": "Talk", "gift": "Gift", "swap": "Swap Sister", "armory": "Armory",
	"renovate": "Renovate", "vows": "Vows", "descend": "Descend"}


func _build_ui() -> void:
	ui = CanvasLayer.new()
	ui.layer = 12
	ui.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(ui)
	var root := Control.new()
	root.name = "Root"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = VTheme.get_theme()
	ui.add_child(root)
	# warm vignette framing the house
	var vig := VTheme.image(VTheme.vignette_tex(Color(0.06, 0.02, 0.01, 1.0), 0.5), Vector2.ZERO, false)
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vig.modulate.a = 0.75
	root.add_child(vig)
	# interact prompt: right of centre, above the action buttons (clear of joystick and medallions)
	_prompt_box = PanelContainer.new()
	_prompt_box.theme_type_variation = "PanelSm"
	_prompt_box.visible = false
	root.add_child(_prompt_box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 2)
	_prompt_box.add_child(v)
	_prompt_title = VTheme.label("", "Caps", 15)
	_prompt_title.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	v.add_child(_prompt_title)
	_prompt = HBoxContainer.new()
	_prompt.add_theme_constant_override("separation", 8)
	v.add_child(_prompt)
	root.resized.connect(_fit_prompt)


func _fit_prompt() -> void:
	if not is_instance_valid(_prompt_box):
		return
	# centred, its bottom edge above the dash / attack medallions (which sit in the last ~180 px)
	var vs := get_viewport().get_visible_rect().size
	_prompt_box.reset_size()
	var sz := _prompt_box.get_combined_minimum_size()
	_prompt_box.size = sz
	_prompt_box.position = Vector2(roundf((vs.x - sz.x) * 0.5), vs.y - clampf(vs.y * 0.27, 190.0, 300.0) - sz.y)


func _set_prompt_refresh() -> void:
	_near = {}


func _set_prompt() -> void:
	for c in _prompt.get_children():
		_prompt.remove_child(c)
		c.queue_free()
	if _near.is_empty():
		_prompt_box.visible = false
		return
	_prompt_box.visible = true
	_prompt_title.text = String(_near["title"]).to_upper()
	var first := true
	for a in _near["actions"]:
		var label := String(ACTION_NAMES.get(a, a.capitalize()))
		if a == "gift":
			label = "Gift (%d gold)" % GIFT_COST
		var b := Button.new()
		b.text = ("[E] " if first and not _touch_ui() else "") + label
		b.theme_type_variation = "SmallButton"
		b.custom_minimum_size = Vector2(0, 54)
		b.focus_mode = Control.FOCUS_NONE
		if a == "gift" and not _can_gift(String(_near.get("npc", ""))):
			b.disabled = true
		var act: String = a
		b.pressed.connect(func(): _do(act))
		VTheme.juice(b, 1.05, "click")
		_prompt.add_child(b)
		first = false
	_fit_prompt()
	_fit_prompt.call_deferred()
	_prompt_box.modulate.a = 0.0
	_prompt_box.create_tween().tween_property(_prompt_box, "modulate:a", 1.0, 0.15)


func _touch_ui() -> bool:
	return hud != null and hud.touch != null


func _ui_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k: int = event.physical_keycode
		if busy and _panel and k == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_close_panel()
			return
		if not busy and not get_tree().paused and (k == KEY_E or k == KEY_F or k == KEY_ENTER or k == KEY_KP_ENTER):
			if not _near.is_empty():
				get_viewport().set_input_as_handled()
				_do(String(_near["actions"][0]))
	elif event is InputEventJoypadButton and event.pressed:
		if busy and _panel and event.button_index == JOY_BUTTON_B:
			get_viewport().set_input_as_handled()
			_close_panel()
		elif not busy and not get_tree().paused and event.button_index == JOY_BUTTON_B and not _near.is_empty():
			get_viewport().set_input_as_handled()
			_do(String(_near["actions"][0]))


## Performs one station action (also called by tests).
func _do(action: String) -> void:
	if busy or _near.is_empty():
		return
	var s: Dictionary = _near
	opened.append("%s:%s" % [s["id"], action])
	VTheme.sound("open")
	match action:
		"talk": _talk(String(s["npc"]))
		"gift": _gift(String(s["npc"]))
		"swap": _swap_sister()
		"armory": open_armory(String(s.get("weapon", Game.weapon_for(hero_id))))
		"renovate": open_renovations()
		"vows": open_vows()
		"descend": _descend()


func _pause(on: bool) -> void:
	busy = on
	get_tree().paused = on
	if on:
		_prompt_box.visible = false
		if is_instance_valid(hero):
			hero.vel = Vector2.ZERO
	else:
		_near = {}


func _lines(lines: Array) -> void:
	_pause(true)
	_play_lines(lines, func():
		_pause(false)
		_refresh_marks())


func _talk(npc: String) -> void:
	var p := StoryDB.from_save(Game.data)
	var lines: Array = StoryDB.next_lines(npc, p)
	Game.save_slot()
	if lines.is_empty():
		var idle: Array = IDLE.get(npc, [])
		var txt := StoryData.chatter_line() if idle.is_empty() else String(idle[randi() % idle.size()])
		lines = StoryData.one(npc, txt)
	_lines(lines)


func _gran_welcome() -> void:
	if busy or not is_inside_tree():
		return
	var p := StoryDB.from_save(Game.data)
	var lines: Array = StoryDB.next_lines("ysolde", p)
	Game.save_slot()
	if lines.is_empty():
		lines = StoryData.one("ysolde", StoryData.chatter_line())
	_lines(lines)


func _can_gift(npc: String) -> bool:
	if npc == "" or not GIFTS.has(npc):
		return false
	var given: Dictionary = Game.data.get("hub_gifts", {})
	return int(given.get(npc, -1)) != int(Game.data.get("runs", 0)) and int(Game.data.get("gold", 0)) >= GIFT_COST


func _gift(npc: String) -> void:
	if not _can_gift(npc):
		hud.float_banner("Once per descent · %d gold" % GIFT_COST, Color(1, 0.7, 0.5))
		return
	var gd: Dictionary = GIFTS[npc]
	Game.data["gold"] = int(Game.data.get("gold", 0)) - GIFT_COST
	if not (Game.data.get("hub_gifts") is Dictionary):
		Game.data["hub_gifts"] = {}
	Game.data["hub_gifts"][npc] = int(Game.data.get("runs", 0))
	StoryDB.give_gift(StoryDB.from_save(Game.data), String(gd["item"]))
	Game.save_slot()
	VTheme.sound("purchase")
	var at: Vector2 = _npc_nodes[npc].position + Vector2(0, -120)
	spark(at, Color(1, 0.8, 0.5), 22)
	float_text(at + Vector2(0, -60), "Gave %s" % String(gd["name"]), Color(1, 0.88, 0.6))
	_lines(StoryData.one(npc, String(gd["line"])))


func _descend() -> void:
	_pause(true)
	VTheme.sound("confirm")
	hud.float_banner("Into the Hollow", Color(0.8, 0.6, 1.0))
	var tw := create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_interval(0.6)
	tw.tween_callback(func():
		get_tree().paused = false
		start_requested.emit())


## A centred panel (fits any aspect from 4:3 to 21:9). Returns the content box.
func _open_panel(title: String, sub: String) -> VBoxContainer:
	if _panel:
		_close_panel(false)
	_pause(true)
	var root: Control = ui.get_node("Root")
	var ov := Control.new()
	ov.set_anchors_preset(Control.PRESET_FULL_RECT)
	ov.mouse_filter = Control.MOUSE_FILTER_STOP
	root.add_child(ov)
	_panel = ov
	var dim := TextureRect.new()
	dim.texture = VTheme.vignette_tex(Color(0.02, 0.0, 0.03, 1.0), 0.0)
	dim.stretch_mode = TextureRect.STRETCH_SCALE
	dim.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.modulate.a = 0.85
	ov.add_child(dim)
	var vs := get_viewport().get_visible_rect().size
	var pw := minf(vs.x - 32.0, 1060.0)
	var ph := minf(vs.y - 28.0, 700.0)
	var p := PanelContainer.new()
	p.anchor_left = 0.5; p.anchor_right = 0.5; p.anchor_top = 0.5; p.anchor_bottom = 0.5
	p.offset_left = -pw * 0.5; p.offset_right = pw * 0.5; p.offset_top = -ph * 0.5; p.offset_bottom = ph * 0.5
	ov.add_child(p)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	p.add_child(v)
	var head := HBoxContainer.new()
	v.add_child(head)
	var tv := VBoxContainer.new()
	tv.add_theme_constant_override("separation", -4)
	tv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(tv)
	var t := VTheme.title_label(title, 34 if vs.y > 700 else 28, VTheme.GOLD_BRIGHT, 8)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	tv.add_child(t)
	if sub != "":
		var sl := VTheme.label(sub, "Quote", 18)
		sl.add_theme_color_override("font_color", VTheme.TEXT_DIM)
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		tv.add_child(sl)
	var purse := HBoxContainer.new()
	purse.add_theme_constant_override("separation", 6)
	purse.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(purse)
	purse.add_child(VTheme.shard_icon(26))
	var sh := VTheme.title_label(str(int(Game.data.get("shards", 0))), 24, VTheme.GOLD_BRIGHT, 6)
	sh.name = "Shards"
	purse.add_child(sh)
	var gi := VTheme.image("reward_gold", Vector2(28, 28))
	purse.add_child(gi)
	var gl := VTheme.title_label(str(int(Game.data.get("gold", 0))), 24, Color(1.0, 0.85, 0.35), 6)
	gl.name = "Gold"
	purse.add_child(gl)
	var close := Button.new()
	close.text = "Close"
	close.theme_type_variation = "SmallButton"
	close.custom_minimum_size = Vector2(120, 52)
	close.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	close.pressed.connect(func(): _close_panel())
	VTheme.juice(close, 1.05, "back")
	head.add_child(close)
	v.add_child(VTheme.divider(minf(pw - 80.0, 520.0), 26))
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	v.add_child(scroll)
	var body := VBoxContainer.new()
	body.name = "Body"
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 6)
	scroll.add_child(body)
	p.resized.connect(func(): p.pivot_offset = p.size * 0.5)
	p.scale = Vector2(0.94, 0.94)
	var tw := p.create_tween()
	tw.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tw.tween_property(p, "scale", Vector2.ONE, 0.22).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return body


func _close_panel(unpause := true) -> void:
	if _panel:
		_panel.queue_free()
		_panel = null
		VTheme.sound("back")
	if unpause:
		_pause(false)


func _panel_purse() -> void:
	if not _panel:
		return
	for n in _panel.find_children("Shards", "Label", true, false):
		(n as Label).text = str(int(Game.data.get("shards", 0)))
	for n in _panel.find_children("Gold", "Label", true, false):
		(n as Label).text = str(int(Game.data.get("gold", 0)))


func _row(body: Control, icon: Texture2D, title: String, desc: String, title_col := VTheme.GOLD_BRIGHT) -> HBoxContainer:
	var pc := PanelContainer.new()
	pc.theme_type_variation = "PanelSm"
	body.add_child(pc)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	pc.add_child(row)
	if icon:
		var ir := VTheme.image(icon, Vector2(64, 64))
		ir.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(ir)
	var info := VBoxContainer.new()
	info.add_theme_constant_override("separation", -2)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var n := VTheme.label(title, "Gold", 21)
	n.add_theme_color_override("font_color", title_col)
	info.add_child(n)
	var d := VTheme.label(desc, "Dim", 17)
	d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d.custom_minimum_size = Vector2(200, 0)
	info.add_child(d)
	return row


func _btn(row: Control, text: String, cb: Callable, disabled := false, icon: Texture2D = null) -> Button:
	var b := Button.new()
	b.text = text
	b.theme_type_variation = "SmallButton"
	b.custom_minimum_size = Vector2(150, 54)
	b.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	b.disabled = disabled
	if icon:
		b.icon = icon
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 18)
	b.pressed.connect(cb)
	VTheme.juice(b, 1.05, "")
	row.add_child(b)
	return b


# ---- the armory (weapon racks / Bram): pick a weapon and its aspect, unlock aspects with shards

var _armory_weapon := ""


func open_armory(weapon := "") -> void:
	_armory_weapon = weapon if Game.WEAPONS.has(weapon) else Game.weapon_for(hero_id)
	var body := _open_panel("The Armory", "Pick a weapon and its aspect. Test them on the dummies in the yard.")
	_fill_armory(body)


func _fill_armory(body: VBoxContainer) -> void:
	for c in body.get_children():
		c.queue_free()
	var tabs := HBoxContainer.new()
	tabs.alignment = BoxContainer.ALIGNMENT_CENTER
	tabs.add_theme_constant_override("separation", 6)
	body.add_child(tabs)
	var cur := Game.weapon_for(hero_id)
	for wid in Game.WEAPON_ORDER:
		var b := Button.new()
		b.theme_type_variation = "IconButton"
		b.custom_minimum_size = Vector2(68, 68)
		b.tooltip_text = String(Game.WEAPONS[wid]["name"])
		var orb := VTheme.image("orb", Vector2.ZERO, false)
		orb.set_anchors_preset(Control.PRESET_FULL_RECT)
		b.add_child(orb)
		var ic := VTheme.image(String(Game.WEAPONS[wid]["icon"]))
		ic.set_anchors_preset(Control.PRESET_FULL_RECT)
		ic.offset_left = 11; ic.offset_top = 11; ic.offset_right = -11; ic.offset_bottom = -11
		b.add_child(ic)
		b.modulate = Color(1, 1, 1) if wid == _armory_weapon else Color(0.55, 0.5, 0.58)
		var w2: String = wid
		b.pressed.connect(func():
			_armory_weapon = w2
			VTheme.sound("click")
			_fill_armory(body))
		tabs.add_child(b)
	var wd: Dictionary = Game.WEAPONS[_armory_weapon]
	var hl := VTheme.label("%s  ·  %s" % [String(wd["name"]).to_upper(), String(wd["kind"]).to_upper()], "Caps", 17)
	hl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hl.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
	body.add_child(hl)
	var dl := VTheme.label("%s\nATTACK %d  ·  %s %d" % [String(wd["desc"]), int(wd["attack"]), String(wd["special_name"]).to_upper(), int(wd["special"])], "Body", 17)
	dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.add_child(dl)
	var shards := int(Game.data.get("shards", 0))
	var aspects: Array = wd["aspects"]
	for ai in range(aspects.size()):
		var ad: Dictionary = aspects[ai]
		var unlocked := Game.aspect_unlocked(_armory_weapon, ai)
		var equipped := cur == _armory_weapon and Game.run_aspect == ai
		var row := _row(body, VTheme.tex(String(wd["icon"])), String(ad["name"]) + ("   (equipped)" if equipped else ""), String(ad["desc"]),
			VTheme.GOLD_BRIGHT if unlocked else VTheme.TEXT_DIM)
		var a2 := ai
		if unlocked:
			_btn(row, "Equipped" if equipped else "Equip", func():
				_equip(_armory_weapon, a2)
				VTheme.sound("confirm")
				_fill_armory(body), equipped)
		else:
			var cost := Game.aspect_cost(_armory_weapon, ai)
			_btn(row, str(cost), func(): unlock_aspect(_armory_weapon, a2, body), shards < cost, VTheme.tex("shard"))


## Spends shards on an aspect and equips it (also used by tests). Returns true on success.
func unlock_aspect(weapon: String, aspect: int, body: VBoxContainer = null) -> bool:
	if not Game.unlock_aspect(weapon, aspect):
		VTheme.sound("back")
		return false
	VTheme.sound("purchase")
	_equip(weapon, aspect)
	if is_instance_valid(hero):
		spark(hero.position + Vector2(0, -80), Color(0.6, 0.85, 1.0), 24)
	if body and is_instance_valid(body):
		_fill_armory(body)
	_panel_purse()
	return true


# ---- the Vows altar: lasting oaths bought with Veil Shards

func open_vows() -> void:
	var body := _open_panel("The Vow Ledger", "Bind Veil Shards into lasting oaths.")
	_fill_vows(body)


func _fill_vows(body: VBoxContainer) -> void:
	for c in body.get_children():
		c.queue_free()
	var shards := int(Game.data.get("shards", 0))
	for id in Game.META.keys():
		var def: Dictionary = Game.META[id]
		var rank := Game.meta_rank(id)
		var mx := int(def["max"])
		var row := _row(body, VTheme.tex("shard"), "%s   %d / %d" % [String(def["name"]), rank, mx], String(def["desc"]))
		if rank >= mx:
			var sw := VTheme.label("SWORN", "Caps", 17)
			sw.add_theme_color_override("font_color", VTheme.GOLD_BRIGHT)
			sw.custom_minimum_size = Vector2(150, 0)
			sw.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			sw.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(sw)
		else:
			var cost := int(def["cost"][rank])
			var id2: String = id
			_btn(row, str(cost), func(): buy_vow(id2, body), shards < cost, VTheme.tex("shard"))


func buy_vow(id: String, body: VBoxContainer = null) -> bool:
	if not Game.buy_meta(id):
		VTheme.sound("back")
		return false
	VTheme.sound("purchase")
	if is_instance_valid(hero):
		var hp_frac: float = hero.hp / maxf(1.0, float(hero.max_hp))
		hero.recompute_stats()
		hero.hp = hero.max_hp * hp_frac
	if body and is_instance_valid(body):
		_fill_vows(body)
	_panel_purse()
	return true


# ---- Odo's renovations: spend gold on decor that appears around the house

func open_renovations() -> void:
	var body := _open_panel("Odo's Renovations", "Bring gold home from the Hollow. Odo turns it into a nicer house.")
	_fill_renovations(body)


func _fill_renovations(body: VBoxContainer) -> void:
	for c in body.get_children():
		c.queue_free()
	var gold := int(Game.data.get("gold", 0))
	for id in ManorScript.DECOR.keys():
		var def: Dictionary = ManorScript.DECOR[id]
		var built: bool = manor.is_decor_on(id)
		var row := _row(body, VTheme.tex("reward_gold"), String(def["name"]), String(def["desc"]), VTheme.GOLD_BRIGHT if not built else Color(0.7, 0.95, 0.7))
		if built:
			var dl := VTheme.label("BUILT", "Caps", 17)
			dl.add_theme_color_override("font_color", Color(0.7, 0.95, 0.7))
			dl.custom_minimum_size = Vector2(150, 0)
			dl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			dl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			row.add_child(dl)
		else:
			var cost := int(def["gold"])
			var id2: String = id
			_btn(row, str(cost), func(): buy_decor(id2, body), gold < cost, VTheme.tex("reward_gold"))


const ODO_THANKS := ["Done and dusted! Go on, have a look. Lovely, innit?", "Sold! To the nice lady with the pointy weapon!",
	"Oh, that's come up a treat. Fitz would've cried. Then complained about the colour."]


func buy_decor(id: String, body: VBoxContainer = null) -> bool:
	var def: Dictionary = ManorScript.DECOR.get(id, {})
	if def.is_empty() or manor.is_decor_on(id):
		return false
	var cost := int(def["gold"])
	if int(Game.data.get("gold", 0)) < cost:
		VTheme.sound("back")
		return false
	Game.data["gold"] = int(Game.data.get("gold", 0)) - cost
	if not (Game.data.get("decor") is Dictionary):
		Game.data["decor"] = {}
	Game.data["decor"][id] = true
	Game.save_slot()
	VTheme.sound("purchase")
	manor.reveal_decor(id)
	if body and is_instance_valid(body):
		_fill_renovations(body)
	_panel_purse()
	if is_instance_valid(hud):
		hud.float_banner(String(def["name"]), Color(1.0, 0.85, 0.4))
		hud.subtitle("“%s”  — Odo" % ODO_THANKS[randi() % ODO_THANKS.size()], StoryData.speaker("odo")["color"])
	return true


# ---------------------------------------------------------------- dummies

func on_dummy_broken(d: Node) -> void:
	dummy_breaks += 1
	spark(d.position + Vector2(0, -80), Color(1, 0.85, 0.5), 20)
	shake(5.0)
	sfx("enemy_die", d.position)
