extends RefCounted
## Layout audit for the screenshot scenes: lists visible text / buttons / panels that run past the
## safe area, and buttons that overlap each other. Used by menu_shots.gd and hud_shots.gd.

const VTheme = preload("res://ui/theme.gd")
const TOL := 2.0


static func _alpha(n: Node) -> float:
	var a := (n as CanvasItem).self_modulate.a
	var p := n
	while p:
		if p is CanvasItem:
			a *= (p as CanvasItem).modulate.a
		p = p.get_parent()
	return a


static func _clipped_by_ancestor(n: Node) -> bool:
	var p := n.get_parent()
	while p:
		if p is ScrollContainer or (p is Control and (p as Control).clip_contents):
			return true
		p = p.get_parent()
	return false


static func _checked(c: Control) -> bool:
	return c is Button or c is Label or c is RichTextLabel or c is PanelContainer or c is LineEdit or c is Range


static func _path(c: Node) -> String:
	var s := String(c.name)
	var p := c.get_parent()
	var k := 0
	while p and k < 3:
		s = String(p.name) + "/" + s
		p = p.get_parent()
		k += 1
	return s


## The top control under the CanvasLayer / window: a screen, a modal, an overlay. Buttons on
## different ones are stacked on purpose (a modal over the menu), so they never count as overlap.
static func _layer_root(n: Node) -> Node:
	var p := n
	while p.get_parent() and p.get_parent() is Control:
		p = p.get_parent()
	return p


## On-screen bounding rect, scale and rotation included (FitBox scales whole screens down).
static func _screen_rect(c: Control) -> Rect2:
	return c.get_global_transform() * Rect2(Vector2.ZERO, c.size)


## Returns problem strings ("" list = clean).
static func audit(tree: SceneTree) -> PackedStringArray:
	var out := PackedStringArray()
	var vp := tree.root
	var safe := VTheme.safe_rect(vp).grow(TOL)
	var buttons: Array = []
	for n in tree.root.find_children("*", "Control", true, false):
		var c := n as Control
		if not c.is_visible_in_tree() or not _checked(c):
			continue
		if c.get_size().x < 1.0 or c.get_size().y < 1.0:
			continue
		if _alpha(c) < 0.05 or _clipped_by_ancestor(c):
			continue
		var r := _screen_rect(c)
		if c is Label and (c as Label).text.strip_edges() == "":
			continue
		if not safe.encloses(r):
			out.append("CLIP %s %s outside %s" % [_path(c), str(r), str(safe)])
		if c is Button and c.mouse_filter != Control.MOUSE_FILTER_IGNORE and not (c as Button).disabled:
			buttons.append(c)
	for i in buttons.size():
		for j in range(i + 1, buttons.size()):
			var a: Control = buttons[i]
			var b: Control = buttons[j]
			if a.is_ancestor_of(b) or b.is_ancestor_of(a) or _layer_root(a) != _layer_root(b):
				continue
			var ov := _screen_rect(a).grow(-TOL).intersection(_screen_rect(b).grow(-TOL))
			if ov.size.x > 0.0 and ov.size.y > 0.0:
				out.append("OVERLAP %s x %s" % [_path(a), _path(b)])
	return out
