extends Control

# The map task's HUD overlay: the map of Kazakhstan in the middle of the screen with numbered
# markers. While it is open the mouse moves a reticle over the map instead of turning the camera,
# and a shot hits the marker under the reticle (player.gd). Each marker stands for an answer target
# of the task and mirrors its state: dark when waiting, gold when picked, green when right, red
# flash when wrong.

const MAP_TEXTURE := "res://assets/maps/kazakhstan.svg"
const MAP_ASPECT := 2.0
const WIDTH_SHARE := 0.88
const MARGIN := 10.0
# Room kept free at the bottom for the character and ability line.
const BOTTOM_MARGIN := 60.0
const MARKER_SHARE := 0.016  # Marker radius as a share of the map width.
const NUMBER_SIZE := 16

var markers: Array = []  # [{target, uv: Vector2, number: int}]
var reticle := Vector2(0.5, 0.5)  # In map units (0,0 = top-left, 1,1 = bottom-right).
var map_rect := Rect2()
var texture: Texture2D


func _ready() -> void:
	name = "MapOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	if ResourceLoader.exists(MAP_TEXTURE):
		texture = load(MAP_TEXTURE)
	hide()


func open() -> void:
	markers.clear()
	reticle = Vector2(0.5, 0.5)
	show()
	_layout()


func close() -> void:
	markers.clear()
	hide()


func add_marker(target, x: float, y: float, number: int) -> void:
	markers.append({"target": target, "uv": Vector2(x, y), "number": number})


# Mouse movement in screen pixels moves the reticle by the same distance on the map.
func move_reticle(relative: Vector2) -> void:
	if map_rect.size.x <= 0.0:
		return
	reticle = (reticle + relative / map_rect.size).clamp(Vector2.ZERO, Vector2.ONE)
	queue_redraw()


func marker_radius() -> float:
	return clampf(map_rect.size.x * MARKER_SHARE, 10.0, 20.0)


func marker_position(marker: Dictionary) -> Vector2:
	return map_rect.position + marker["uv"] * map_rect.size


func reticle_position() -> Vector2:
	return map_rect.position + reticle * map_rect.size


# The target of the marker under the reticle (a little forgiving around the marker's edge).
func target_under_reticle():
	var best = null
	var best_distance := marker_radius() * 1.3
	for marker in markers:
		if not is_instance_valid(marker["target"]):
			continue
		var distance := marker_position(marker).distance_to(reticle_position())
		if distance <= best_distance:
			best_distance = distance
			best = marker["target"]
	return best


func _process(_delta: float) -> void:
	if visible:
		markers = markers.filter(func(m): return is_instance_valid(m["target"]))
		_layout()
		queue_redraw()


# The largest 2:1 map that fits between the question bar and the bottom line, centred.
func _layout() -> void:
	var screen := get_viewport_rect().size
	var bar := get_node_or_null("../TopBar") as Control
	var top := (bar.get_global_rect().end.y if bar else 0.0) + MARGIN
	var bottom := screen.y - BOTTOM_MARGIN
	var width := minf(screen.x * WIDTH_SHARE, (bottom - top) * MAP_ASPECT)
	var height := width / MAP_ASPECT
	map_rect = Rect2(Vector2((screen.x - width) / 2.0, top + (bottom - top - height) / 2.0), Vector2(width, height))


func _draw() -> void:
	draw_rect(map_rect.grow(14.0).grow_individual(0, 0, 0, 4), Color(0, 0, 0, 0.35))
	draw_rect(map_rect.grow(6.0), Color(0.95, 0.92, 0.85))
	if texture:
		draw_texture_rect(texture, map_rect, false)
	else:
		draw_rect(map_rect, Color(0.6, 0.75, 0.85))
	draw_rect(map_rect, Color(0.3, 0.22, 0.12), false, 2.0)

	var font := get_theme_default_font()
	var radius := marker_radius()
	for marker in markers:
		var target = marker["target"]
		var at := marker_position(marker)
		var fill := Color(0.12, 0.13, 0.17)
		if target.flashing:
			fill = target.WRONG_COLOR
		elif target.state != target.State.NORMAL:
			fill = target.accent_color()
		draw_circle(at, radius + 3.0, Color(1, 1, 1, 0.95))
		draw_circle(at, radius, fill)
		var text := str(marker["number"])
		var size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_CENTER, -1, NUMBER_SIZE)
		draw_string(font, at + Vector2(-size.x / 2.0, size.y * 0.32), text, HORIZONTAL_ALIGNMENT_CENTER, -1, NUMBER_SIZE, Color.WHITE)

	# Reticle: a ring with four ticks, dark outline under a light line so it shows on any colour.
	var aim := reticle_position()
	for pass_color in [[Color(0, 0, 0, 0.8), 4.0], [Color(1, 0.95, 0.6), 2.0]]:
		draw_arc(aim, 12.0, 0.0, TAU, 32, pass_color[0], pass_color[1])
		for direction in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(aim + direction * 6.0, aim + direction * 18.0, pass_color[0], pass_color[1])
