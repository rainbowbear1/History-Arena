extends Control

# Screen-space answer labels for soldier and shooting-range targets. Each label keeps the same text
# size at any distance, is hidden when its target is behind the camera, off screen or behind an
# obstacle, and has a pointer to its target. Labels of one row share a band: "above" floats over
# the heads, "below" hangs under the feet, so a front row and a rampart row behind it never mix;
# "on:<track>" is printed on a gallery plaque (no pointer), one band per gallery track.
# Within a band a label is never wider than the gap to its neighbours (long answers wrap onto
# more lines instead) and labels are pushed sideways until none overlap.

const FONT_SIZE := 18
const MAX_TEXT_WIDTH := 260.0
const MIN_TEXT_WIDTH := 110.0
# Gap between the label and the target, filled by the pointer.
const POINTER_GAP := 22.0
const LABEL_SPACING := 8.0
const SCREEN_MARGIN := 8.0
# Room left free at the bottom of the screen for the character and ability line.
const BOTTOM_MARGIN := 64.0
# Panel border and margins around the text.
const PANEL_PADDING := 24.0

var entries: Array = []  # [{target, panel, label, style, placement, anchor, foot, visible}]
var _font: Font


func _ready() -> void:
	_font = get_theme_default_font()


func track(target, placement: String = "above") -> void:
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
	entries.append({"target": target, "panel": panel, "label": label, "style": style, "placement": placement,
		"anchor": Vector2.ZERO, "foot": Vector2.ZERO, "visible": false})


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


# The target whose label covers `point` (the crosshair), so shooting a label counts as shooting
# its target.
func target_at(point: Vector2):
	for entry in entries:
		if entry["visible"] and Rect2(entry["panel"].position, entry["panel"].size).has_point(point):
			return entry["target"]
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
		entry["foot"] = camera.unproject_position(target.foot_anchor()) if entry["placement"] == "below" else point
		entry["visible"] = true

	# Lower bands first; a band that would touch one placed before it steps away from it.
	var placed: Array[Rect2] = []
	var tracks := []
	for entry in entries:
		if entry["placement"].begins_with("on:") and not tracks.has(entry["placement"]):
			tracks.append(entry["placement"])
	tracks.sort_custom(func(a, b): return a > b)  # "on:2" (lowest track) before "on:0".
	var bands := ["below"] + tracks + ["above"]
	for placement in bands:
		var row := entries.filter(func(e): return e["visible"] and e["placement"] == placement)
		row.sort_custom(func(a, b): return a["anchor"].x < b["anchor"].x)
		_fit_widths(row)
		_place_row(row, placement, placed, screen)

	for entry in entries:
		if not entry["visible"]:
			entry["panel"].hide()
	queue_redraw()


# Each label may be as wide as the gap to its nearest neighbour in the band (never narrower than
# MIN_TEXT_WIDTH); longer text wraps onto more lines.
func _fit_widths(row: Array) -> void:
	for i in range(row.size()):
		var room := MAX_TEXT_WIDTH
		for j in [i - 1, i + 1]:
			if j >= 0 and j < row.size():
				room = minf(room, absf(row[j]["anchor"].x - row[i]["anchor"].x) - LABEL_SPACING - PANEL_PADDING)
		var label: Label = row[i]["label"]
		var text_width := _font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x + 2.0
		var width := minf(text_width, maxf(room, MIN_TEXT_WIDTH))
		if absf(label.custom_minimum_size.x - width) > 0.5:
			label.custom_minimum_size.x = width
			row[i]["panel"].reset_size()


# Places one band left to right: each label centred on its target and pushed right past the
# previous one if they would touch; then the band is pulled back inside the screen.
func _place_row(row: Array, placement: String, placed: Array[Rect2], screen: Vector2) -> void:
	var rects: Array[Rect2] = []
	var top := top_limit()
	for entry in row:
		var size: Vector2 = entry["panel"].get_combined_minimum_size()
		var y: float = entry["foot"].y + POINTER_GAP
		if placement == "above":
			y = entry["anchor"].y - size.y - POINTER_GAP
		elif placement.begins_with("on:"):
			y = entry["anchor"].y - size.y / 2.0
		y = clampf(y, top, maxf(top, screen.y - BOTTOM_MARGIN - size.y))
		var rect := Rect2(Vector2(entry["anchor"].x - size.x / 2.0, y), size)
		if not rects.is_empty():
			rect.position.x = maxf(rect.position.x, rects[-1].end.x + LABEL_SPACING)
		rects.append(rect)
	if rects.is_empty():
		return
	# Right edge first, then each label keeps clear of its left neighbour and of the left edge.
	var limit := screen.x - SCREEN_MARGIN
	for i in range(rects.size() - 1, -1, -1):
		rects[i].position.x = minf(rects[i].position.x, limit - rects[i].size.x)
		limit = rects[i].position.x - LABEL_SPACING
	for i in range(rects.size()):
		var left := SCREEN_MARGIN if i == 0 else rects[i - 1].end.x + LABEL_SPACING
		rects[i].position.x = maxf(rects[i].position.x, left)
		# A band never covers another one: "above" labels step up, "below" labels step down.
		for other in placed:
			if rects[i].grow(LABEL_SPACING / 2.0).intersects(other):
				if placement != "below":
					rects[i].position.y = maxf(top, other.position.y - rects[i].size.y - LABEL_SPACING)
				else:
					rects[i].position.y = other.end.y + LABEL_SPACING
		var panel: PanelContainer = row[i]["panel"]
		panel.position = rects[i].position
		panel.size = rects[i].size
		panel.show()
	placed.append_array(rects)


# Lowest point of the HUD's top bar (question, score, timer) or of an image task's photo; labels
# stay below it.
func top_limit() -> float:
	var limit := 0.0
	for name in ["../TopBar", "../ImagePanel"]:
		var panel := get_node_or_null(name) as Control
		if panel and panel.visible:
			limit = maxf(limit, panel.get_global_rect().end.y)
	return limit + SCREEN_MARGIN


func _draw() -> void:
	for entry in entries:
		if not entry["visible"]:
			continue
		if entry["placement"].begins_with("on:"):
			continue  # Printed on its plaque: no pointer.
		var panel: PanelContainer = entry["panel"]
		var color: Color = entry["style"].border_color
		var below: bool = entry["placement"] == "below"
		# The pointer runs from the label's edge nearest the target to the head (or the feet).
		var tip: Vector2 = entry["foot"] if below else entry["anchor"]
		var x := clampf(tip.x, panel.position.x + 10.0, panel.position.x + panel.size.x - 10.0)
		var from := Vector2(x, panel.position.y if below else panel.position.y + panel.size.y)
		var head := 12.0 if below else -12.0
		var stem_end := tip + Vector2(0, head * 0.6)
		draw_line(from, stem_end, Color(0, 0, 0, 0.7), 5.0)
		draw_line(from, stem_end, color, 3.0)
		draw_colored_polygon(PackedVector2Array([tip, tip + Vector2(-8, head), tip + Vector2(8, head)]), color)


func _update_text(entry: Dictionary) -> void:
	var target = entry["target"]
	var label: Label = entry["label"]
	var text: String = target.answer_label.text
	if label.text != text:
		label.text = text
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
	return hit.is_empty() or hit["collider"] == target or hit["collider"].has_method("label_anchor") or hit["collider"].has_method("take_hit") \
		or hit["collider"].is_in_group("obstacle")
