extends Node2D
## Mister Wick's stall: the wandering peddler of the Hollow, his counter and three wares for gold.
## Placed by scenes/room_rewards.gd in a shop chamber (in the arena's y-sorted entity layer).
##
## Who he is (docs/STORY.md): Larkhill's old lamp-oil seller. He fell into the pit years ago and never
## left. The dead drop things; he picks them up and sells them to the only folk who still carry gold.

const RewardObject := preload("res://scenes/reward_object.gd")
const SPEAKER := "wick"
const COUNTER_TEX := preload("res://art/env/shop/counter.png")
const MERCHANT_TEX := preload("res://art/env/shop/merchant.png")
const COUNTER_W := 600.0 ## world width of the counter
const MERCHANT_H := 236.0
const IMG_FLOOR_Y := 500.0 ## counter.png row that sits on the stall's origin

## First meeting (dialogue). "{hero}" lines are said by the heroine.
const INTRO := [
	["wick", "Customers! Living ones! Oh, this is a good day. Mister Wick, at your service."],
	["{hero}", "Why are you smiling like that? Why is anyone smiling down here?"],
	["wick", "I sold lamp oil up in Larkhill. Then I fell in the pit. Long story. Short fall."],
	["wick", "Folk drop things down here. I pick them up, dust them off and sell them on."],
	["wick", "Gold's no use to the dead, see. So I only trade with you lot. Have a look!"],
]
## Said as you walk in (subtitle).
const GREET := [
	"Back again! Mister Wick never forgets a face. Or a purse.",
	"Mind the lantern. It's the only light I've got, and I'm not sharing.",
	"Everything here fell down the pit at some point. Good as new. Mostly.",
	"The Regent's lot never buy anything. Rude, if you ask me.",
	"Tell Odo Penhallow he still owes me for six barrels of lamp oil.",
]
const THANKS := [
	"Pleasure doing business! Come back alive. Or not. I'm not fussy.",
	"Lovely choice. That one's barely haunted.",
	"Sold! Don't tell the Regent where you got it.",
]
const BROKE := "No coin, no deal. I'm cheerful, not charitable."

## Wares: kind -> art (ui icon or path), price, title, desc. Rolled 3 per shop (seeded).
const WARES := {
	"boon": {"tex": "reward_boon", "price": 80, "title": "Warden's Favour", "desc": "A boon from one of the Wardens. Choose one of three."},
	"forge": {"tex": "reward_forge", "price": 95, "title": "Forge Token", "desc": "Upgrade your weapon. Choose one of three."},
	"heal": {"tex": "reward_heal", "price": 40, "title": "Red Draught", "desc": "Restores half of your health."},
	"vigor": {"tex": "boon_tidal_heart", "price": 65, "title": "Tidal Heart", "desc": "Mireth's gift: +20 max health, healed at once."},
	"shards": {"tex": "shard", "price": 45, "title": "Pouch of Shards", "desc": "30 Veil Shards to take home to Gran."},
}
const WARE_SHARDS := 30
const WARE_HEAL := 0.5

var items: Array = [] ## RewardObject wares on the counter
var merchant: Sprite2D
var _t := 0.0
var _lamp: Sprite2D


## Builds the stall around `position` (the counter's front-centre on the floor).
func build(seed_value: int) -> void:
	y_sort_enabled = true
	var sc := COUNTER_W / COUNTER_TEX.get_width()
	# Mister Wick stands behind the left half of the counter (drawn first: the counter hides his boots)
	var holder := Node2D.new()
	holder.name = "Wick"
	holder.position = Vector2(-60, -175)
	add_child(holder)
	var shadow := Sprite2D.new()
	shadow.texture = RewardObject.glow_tex()
	shadow.modulate = Color(0, 0, 0, 0.6)
	shadow.scale = Vector2(1.6, 0.5)
	holder.add_child(shadow)
	_lamp = Sprite2D.new()
	_lamp.texture = RewardObject.glow_tex()
	_lamp.material = RewardObject.additive()
	_lamp.modulate = Color(0.6, 1.0, 0.45, 0.55)
	_lamp.scale = Vector2(1.3, 1.3)
	_lamp.position = Vector2(-95, -120)
	holder.add_child(_lamp)
	merchant = Sprite2D.new()
	merchant.texture = MERCHANT_TEX
	merchant.centered = false
	var ms := MERCHANT_H / MERCHANT_TEX.get_height()
	merchant.scale = Vector2(ms, ms)
	merchant.offset = Vector2(-MERCHANT_TEX.get_width() * 0.5, -MERCHANT_TEX.get_height() * 0.98)
	holder.add_child(merchant)
	# the counter, cut into upright slices so each one depth-sorts at its own front edge: the stall runs
	# diagonally across the floor, so one sort point would draw a heroine standing in front of its far end
	# behind it (she seemed to walk under the table)
	var tw := COUNTER_TEX.get_width()
	var slice := 125
	var x0 := 0
	while x0 < tw:
		var w: int = mini(slice, tw - x0)
		var spr := Sprite2D.new()
		spr.texture = COUNTER_TEX
		spr.centered = false
		spr.region_enabled = true
		spr.region_rect = Rect2(x0, 0, w, COUNTER_TEX.get_height())
		spr.scale = Vector2(sc, sc)
		var sy := front_y(x0 + w * 0.5) - 22.0
		spr.position = Vector2(0, sy)
		spr.offset = Vector2(x0 - tw * 0.5, -IMG_FLOOR_Y - sy / sc)
		add_child(spr)
		x0 += w
	# wares along the table top (image coords of the top surface's centre line)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var pool: Array = WARES.keys()
	var picks: Array = []
	while picks.size() < 3 and not pool.is_empty():
		picks.append(pool.pop_at(rng.randi_range(0, pool.size() - 1)))
	var top := [Vector2(285, 238), Vector2(435, 196), Vector2(585, 154)]
	var ox := COUNTER_TEX.get_width() * 0.5
	for i in range(picks.size()):
		var k := String(picks[i])
		var w: Dictionary = WARES[k]
		var on_top: Vector2 = (top[i] - Vector2(ox, IMG_FLOOR_Y)) * sc
		var o := RewardObject.new()
		# sorted just in front of the counter (the art sits up on the table top); bought from the floor
		# straight in front of where it is displayed
		var fx: float = top[i].x + 60.0
		o.position = Vector2((fx - ox) * sc, front_y(fx) + 4.0)
		o.setup(k, {"tex": w["tex"], "h": 74.0, "price": int(w["price"]), "title": w["title"], "desc": w["desc"],
			"color": Color(1.0, 0.85, 0.45), "art_offset": on_top + Vector2(0, 8) - o.position, "verb": "Buy", "auto": false})
		o.use_axis = Vector2(510, -175).normalized() # the counter's long front, left to right
		o.use_offset = Vector2(-o.use_axis.y, o.use_axis.x) * 50.0
		o.reach = 70.0
		add_child(o)
		items.append(o)


## Local y of the floor line along the counter's front (the near side of its footprint) below image column ix:
## the short left end runs from the back-left leg (115, 465) to the front corner (240, 505), the long front
## from there to the right-hand post (750, 330).
static func front_y(ix: float) -> float:
	var iy := 505.0 - 0.32 * (240.0 - ix) if ix < 240.0 else 505.0 - 0.343 * (ix - 240.0)
	return (iy - IMG_FLOOR_Y) * COUNTER_W / COUNTER_TEX.get_width()


## Collision (world) for the counter, for env.get_obstacles(): flat ellipses down the middle of its footprint
## (front corner, right post and back-left leg in image px: (240, 505), (750, 330), (115, 465)), close enough
## together that no gap lets a heroine slip under the table, plus Mister Wick.
func obstacles() -> Array:
	var sc := COUNTER_W / COUNTER_TEX.get_width()
	var f := (Vector2(240, 505) - Vector2(COUNTER_TEX.get_width() * 0.5, IMG_FLOOR_Y)) * sc
	var r := (Vector2(750, 330) - Vector2(COUNTER_TEX.get_width() * 0.5, IMG_FLOOR_Y)) * sc
	var depth := (Vector2(115, 465) - Vector2(240, 505)) * sc
	var a: Array = []
	var n := 9
	for i in range(n):
		var t := float(i) / float(n - 1)
		a.append({"pos": position + f.lerp(r, t) + depth * 0.5, "radius": 48.0})
	a.append({"pos": position + f + depth * 0.15 + Vector2(-20, 0), "radius": 48.0})
	a.append({"pos": position + Vector2(-60, -175), "radius": 40.0})
	return a


func _process(delta: float) -> void:
	_t += delta
	if merchant:
		var ms := MERCHANT_H / MERCHANT_TEX.get_height()
		merchant.scale = Vector2(ms * (1.0 - 0.01 * sin(_t * 2.0)), ms * (1.0 + 0.015 * sin(_t * 2.0)))
		merchant.position.y = -3.0 * absf(sin(_t * 1.0))
		merchant.rotation = sin(_t * 0.8) * 0.02
	if _lamp:
		_lamp.modulate.a = 0.3 + 0.08 * sin(_t * 9.0) + 0.06 * sin(_t * 23.0)


static func line_for(lines: Array) -> String:
	return String(lines[randi() % lines.size()])
