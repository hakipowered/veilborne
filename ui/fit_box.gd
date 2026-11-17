extends Container
## Fills its rect with each child. When a child's minimum size does not fit (a narrow or short
## screen, big safe-area insets), the child is laid out at its minimum and scaled down uniformly
## so nothing is ever cut off at the screen edge. Input follows the scale, so it stays tappable.

## Never scale below this; past it the layout must reflow instead.
@export var min_scale := 0.55


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _notification(what: int) -> void:
	if what == NOTIFICATION_SORT_CHILDREN:
		for ch in get_children():
			var c := ch as Control
			if c == null or not c.visible or c.top_level:
				continue
			var need := c.get_combined_minimum_size()
			var s := 1.0
			if need.x > size.x and size.x > 0.0:
				s = minf(s, size.x / need.x)
			if need.y > size.y and size.y > 0.0:
				s = minf(s, size.y / need.y)
			s = maxf(s, min_scale)
			# fit_child_in_rect() resets scale to 1, so scale afterwards
			fit_child_in_rect(c, Rect2(Vector2.ZERO, size / s))
			c.pivot_offset = Vector2.ZERO
			c.scale = Vector2(s, s)


func _get_minimum_size() -> Vector2:
	return Vector2.ZERO
