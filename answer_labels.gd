extends Control

# Screen-space answer labels for soldier and shooting-range targets. Each label floats above its
# target's head with a pointer down to it, keeps the same text size at any distance, is hidden when
# the target is behind the camera, off screen or behind an obstacle, and is pushed clear of the
# other labels so they never overlap.

const FONT_SIZE := 18
const MAX_TEXT_WIDTH := 260.0
# Gap between the label and the target's head, filled by the pointer.
const POINTER_GAP := 22.0
const LABEL_SPACING := 6.0
const SCREEN_MARGIN := 8.0

var entries: Array = []  # [{target, panel, label, style, anchor, visible}]
var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()


func track(target) -> void:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.07, 0.07, 0.09, 0.88)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 4
	style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", style)
	var label := Label.new()
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	panel.hide()
	add_child(panel)
	entries.append({"target": target, "panel": panel, "label": label, "style": style, "anchor": Vector2.ZERO, "visible": false})


func clear() -> void:
	for entry in entries:
		entry["panel"].queue_free()
	entries.clear()
	queue_redraw()


func label_for(target) -> PanelContainer:
	for entry in entries:
		if entry["target"] == target:
			return entry["panel"]
	return null


func _process(_delta: float) -> void:
	entries = entries.filter(func(e):
		if is_instance_valid(e["target"]) and e["target"].is_inside_tree():
			return true
		e["panel"].queue_free()
		return false)
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var screen := get_viewport_rect().size
	var placed: Array[Rect2] = []

	for entry in entries:
		_update_text(entry)
		var target = entry["target"]
		var head: Vector3 = target.label_anchor()
		entry["visible"] = false
		if camera.is_position_behind(head) or not _can_see(camera, target, head):
			continue
		var point := camera.unproject_position(head)
		if point.x < 0.0 or point.x > screen.x or point.y < 0.0 or point.y > screen.y:
			continue
		entry["anchor"] = point
		entry["visible"] = true

	# Labels nearest the bottom of the screen are placed first. A label that would overlap one
	# already placed slides sideways if that clears it, otherwise moves up above it; it never
	# covers the HUD's top bar.
	var top := top_limit()
	var shown := entries.filter(func(e): return e["visible"])
	shown.sort_custom(func(a, b): return a["anchor"].y > b["anchor"].y)
	for entry in shown:
		var panel: PanelContainer = entry["panel"]
		var size := panel.get_combined_minimum_size()
		var rect := _place(entry["anchor"], size, placed, top, screen)
		placed.append(rect)
		panel.position = rect.position
		panel.size = size
		panel.show()

	for entry in entries:
		if not entry["visible"]:
			entry["panel"].hide()
	queue_redraw()


# Lowest point of the HUD's top bar (question, score, timer); labels stay below it.
func top_limit() -> float:
	var bar := get_node_or_null("../TopBar") as Control
	return (bar.get_global_rect().end.y if bar else 0.0) + SCREEN_MARGIN


func _place(anchor: Vector2, size: Vector2, placed: Array[Rect2], top: float, screen: Vector2) -> Rect2:
	var start := Rect2(anchor - Vector2(size.x / 2.0, size.y + POINTER_GAP), size)
	var candidates: Array[Rect2] = [start]
	# Sideways: just past each neighbour, as long as the pointer still lands under the label.
	for other in placed:
		for x in [other.end.x + LABEL_SPACING, other.position.x - size.x - LABEL_SPACING]:
			if absf(x + size.x / 2.0 - anchor.x) < size.x / 2.0 - 10.0:
				candidates.append(Rect2(Vector2(x, start.position.y), size))
	# Upwards: stacked above whatever is in the way.
	var up := start
	for i in range(placed.size()):
		var blocker = _first_overlap(up, placed)
		if blocker == null:
			break
		up.position.y = blocker.position.y - size.y - LABEL_SPACING
		candidates.append(up)
	for rect in candidates:
		rect.position.x = clampf(rect.position.x, SCREEN_MARGIN, screen.x - size.x - SCREEN_MARGIN)
		if rect.position.y >= top and _first_overlap(rect, placed) == null:
			return rect
	start.position.y = maxf(start.position.y, top)
	return start


func _first_overlap(rect: Rect2, placed: Array[Rect2]):
	for other in placed:
		if rect.grow(LABEL_SPACING / 2.0).intersects(other.grow(LABEL_SPACING / 2.0)):
			return other
	return null


func _draw() -> void:
	for entry in entries:
		if not entry["visible"]:
			continue
		var panel: PanelContainer = entry["panel"]
		var color: Color = entry["style"].border_color
		var from := Vector2(panel.position.x + panel.size.x / 2.0, panel.position.y + panel.size.y)
		var tip: Vector2 = entry["anchor"]
		draw_line(from, tip - Vector2(0, 8), Color(0, 0, 0, 0.7), 5.0)
		draw_line(from, tip - Vector2(0, 8), color, 3.0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-8, -12), tip + Vector2(8, -12)]), color)


func _update_text(entry: Dictionary) -> void:
	var target = entry["target"]
	var label: Label = entry["label"]
	var text: String = target.answer_label.text
	if label.text != text:
		label.text = text
		var width := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
		label.custom_minimum_size.x = minf(width + 2.0, MAX_TEXT_WIDTH)
	var accent: Color = target.accent_color()
	entry["style"].border_color = accent
	entry["style"].bg_color = Color(0.07, 0.07, 0.09, 0.88) if target.state == target.State.NORMAL and not target.flashing else accent.darkened(0.55)


# Hidden when something solid stands between the camera and the target's head.
func _can_see(camera: Camera3D, target, head: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, head)
	var exclude := [target.get_rid()]
	var player := camera.get_parent()
	if player is CollisionObject3D:
		exclude.append(player.get_rid())
	query.exclude = exclude
	var hit := camera.get_world_3d().direct_space_state.intersect_ray(query)
	# Other soldiers and enemies move about; only walls, rocks and buildings hide a label.
	return hit.is_empty() or hit["collider"] == target or hit["collider"].has_method("label_anchor") or hit["collider"].has_method("take_hit")
