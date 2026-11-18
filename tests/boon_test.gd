extends Node
## Headless check that boon and forge cards stack the Hades way: picking an owned card levels it up
## (Level I -> II -> III), the stat really grows by the card's step, the card text shows the real value,
## maxed cards stop being offered and cards that would do nothing for the weapon/aspect are never offered.
##   godot --headless res://tests/boon_test.tscn

const HeroScript := preload("res://entities/hero.gd")

var fails: Array = []
var checks := 0


func _ready() -> void:
	_test_boons()
	_test_forge()
	_test_offers()
	_test_text()
	# measured effects in a real arena (tests/effect_test.gd)
	var fx: Node = preload("res://tests/effect_test.gd").new()
	fx.name = "Effects"
	add_child(fx)
	fx.run()
	checks += fx.checks
	for f in fx.fails:
		fails.append("EFFECT " + f)
	print("EFFECT: card audit")
	for id in fx.table:
		var row: Array = fx.table[id]
		print("  %-26s %s %s" % [id, row[0], row[1]])
	for f in fails:
		print("BOON FAIL: ", f)
	print("BOON: %s (%d checks, %d failures)" % ["PASS" if fails.is_empty() else "FAIL", checks, fails.size()])
	get_tree().quit(0 if fails.is_empty() else 1)


func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails.append(what)


func _hero(weapon: String, aspect := 0) -> Node:
	var h: Node = HeroScript.new()
	h.setup("t", "kaela", false, 0, null, weapon, aspect)
	return h


func _near(a, b) -> bool:
	return absf(float(a) - float(b)) < 0.001


func _test_boons() -> void:
	for b in Game.BOONS:
		for r in range(3):
			var h := _hero("spear")
			var stat := String(b["stat"])
			var s0 := float(h.stats[stat])
			for lvl in range(1, Game.CARD_MAX_LEVEL + 1):
				h.add_boon(b["id"], r)
				var want := s0 + float(Game.card_value(b, r, lvl))
				if stat == "armor":
					want = minf(want, h.ARMOR_CAP)
				_check(_near(h.stats[stat], want), "%s r%d L%d: %s = %s, want %s" % [b["id"], r, lvl, stat, h.stats[stat], want])
				_check(int(h.boons[b["id"]]["level"]) == lvl, "%s level %d" % [b["id"], lvl])
				if lvl > 1:
					_check(float(Game.card_value(b, r, lvl)) > float(Game.card_value(b, r, lvl - 1)), "%s L%d grows" % [b["id"], lvl])
			# a further pick past the max changes nothing
			var top := float(h.stats[stat])
			h.add_boon(b["id"], r)
			_check(_near(h.stats[stat], top) and int(h.boons[b["id"]]["level"]) == Game.CARD_MAX_LEVEL, "%s capped at max level" % b["id"])
			h.free()
	# rarity never drops on a re-pick, and a better re-pick lifts it
	var h2 := _hero("spear")
	h2.add_boon("ember_strike", 2)
	h2.add_boon("ember_strike", 0)
	_check(int(h2.boons["ember_strike"]["rarity"]) == 2, "rarity kept on a lower re-pick")
	_check(_near(h2.stats["attack_mult"], 60 + 15), "ember_strike epic L2 = 75")
	h2.free()
	# Tidal Heart raises max health each level
	var h3 := _hero("spear")
	var hp0: int = h3.max_hp
	h3.add_boon("tidal_heart", 0)
	h3.add_boon("tidal_heart", 0)
	_check(h3.max_hp == hp0 + 20 + 15, "tidal_heart L2 max_hp %d" % h3.max_hp)
	h3.free()


func _test_forge() -> void:
	for f in Game.FORGE:
		var w := String(f["weapon"])
		for r in range(3):
			var h := _hero(w)
			var stat := String(f["stat"])
			var s0 := float(h.stats[stat])
			for lvl in range(1, Game.CARD_MAX_LEVEL + 1):
				h.add_forge(f["id"], r)
				var want := s0 + float(Game.card_value(f, r, lvl))
				if stat == "armor":
					want = minf(want, h.ARMOR_CAP)
				_check(_near(h.stats[stat], want), "%s r%d L%d: %s = %s, want %s" % [f["id"], r, lvl, stat, h.stats[stat], want])
			h.free()
	# the owner's case: Anchored Aegis taken twice really spins longer
	var h := _hero("shield")
	h.add_forge("shield_anchor", 2)
	_check(_near(h.stats["w_anchor"], 4.5), "anchor epic L1 = 4.5 s")
	h.add_forge("shield_anchor", 2)
	_check(_near(h.stats["w_anchor"], 5.5), "anchor epic L2 = 5.5 s (got %s)" % h.stats["w_anchor"])
	h.add_forge("shield_anchor", 2)
	_check(_near(h.stats["w_anchor"], 6.5), "anchor epic L3 = 6.5 s")
	h.free()
	# aspects add on top of cards
	var hb := _hero("shield", 2)
	hb.add_forge("shield_anchor", 0)
	_check(_near(hb.stats["w_anchor"], 4.0 + 2.5), "Bastion + anchor = 6.5 s")
	hb.free()
	# stacked armor (Bulwark + Briar Ward III Epic) adds up and stays under the cap
	var ha := _hero("shield", 0)
	for k in range(3):
		ha.add_boon("briar_ward", 2)
	_check(_near(ha.stats["armor"], minf(10.0 + 25.0 + 12.0, ha.ARMOR_CAP)), "armor stacks to %s" % ha.stats["armor"])
	ha.free()


func _test_offers() -> void:
	var rng := RandomNumberGenerator.new()
	# owned cards come back as their next level; maxed ones never come back
	var owned := {"ember_strike": {"level": 1, "rarity": 1}, "kindle": {"level": Game.CARD_MAX_LEVEL, "rarity": 0}}
	var saw_up := false
	for sd in range(300):
		rng.seed = sd
		for c in Game.roll_boons(rng, owned):
			_check(c["id"] != "kindle", "maxed kindle offered")
			if c["id"] == "ember_strike":
				saw_up = true
				_check(bool(c["upgrade"]) and int(c["level"]) == 2 and int(c["rarity"]) >= 1, "ember_strike offered as L2 upgrade: %s" % c)
			else:
				_check(not bool(c["upgrade"]) and int(c["level"]) == 1, "fresh card is L1: %s" % c)
	_check(saw_up, "an owned card is offered as an upgrade")
	# forge: maxed cards stop, and every offered card does something for this weapon + aspect
	for w in Game.WEAPON_ORDER:
		for a in range(3):
			var seen := {}
			for sd in range(200):
				rng.seed = sd
				for c in Game.roll_forge(rng, w, {}, 3, a):
					var f := Game.forge_by_id(c["id"])
					seen[c["id"]] = true
					_check(f["weapon"] == w, "forge %s offered for %s" % [c["id"], w])
					if w == "bow" and a == 2 and c["id"] == "bow_pierce":
						seen["gale_pierce"] = true
			_check(seen.size() >= 3, "%s aspect %d has forge cards to offer" % [w, a])
			if w == "bow" and a == 2:
				_check(seen.has("gale_pierce"), "Piercing Fletch still offered under the Gale (it adds pierce to quick shots)")
	var full := {}
	for f in Game.FORGE:
		if f["weapon"] == "shield":
			full[f["id"]] = {"level": Game.CARD_MAX_LEVEL, "rarity": 0}
	rng.seed = 1
	_check(Game.roll_forge(rng, "shield", full).is_empty(), "all shield forge cards maxed -> none offered")
	# Anchored Aegis + Rebound Rim no longer contradict: both are still offered together
	var both := {"shield_anchor": {"level": 1, "rarity": 0}}
	var saw_rebound := false
	for sd in range(100):
		rng.seed = sd
		for c in Game.roll_forge(rng, "shield", both):
			if c["id"] == "shield_rebound":
				saw_rebound = true
	_check(saw_rebound, "Rebound Rim still offered with Anchored Aegis (it ricochets after the spin)")


func _test_text() -> void:
	var a := Game.forge_by_id("shield_anchor")
	var t1 := Game.card_text(a, 2, 1)
	_check(t1.contains("4.5"), "anchor L1 text: " + t1)
	var t2 := Game.card_text(a, 2, 2, 1, 2)
	_check(t2.contains("4.5 → 5.5"), "anchor upgrade text: " + t2)
	var e := Game.boon_by_id("ember_strike")
	var t3 := Game.card_text(e, 0, 3, 2, 0)
	_check(t3.contains("40 → 55%") and not t3.contains("%%"), "ember upgrade text: " + t3)
	_check(Game.boon_text("ember_strike", 1, 2) == "Attacks deal +55% damage.", "boon_text L2: " + Game.boon_text("ember_strike", 1, 2))
	for b in Game.BOONS + Game.FORGE:
		for r in range(3):
			for lvl in range(1, 4):
				var s := Game.card_text(b, r, lvl, lvl - 1 if lvl > 1 else 0, r)
				_check(s != "" and not s.contains("%d") and not s.contains("%."), "%s text: %s" % [b["id"], s])
