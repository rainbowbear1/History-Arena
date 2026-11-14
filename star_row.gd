extends Control

# Draws 0–3 filled stars out of 3 as shapes (the bundled font has no star glyph, and the web
# build has no system fonts to fall back on).

const FILLED := Color(0.91, 0.78, 0.5)
const EMPTY := Color(1, 1, 1, 0.25)

@export var stars: int = 0:
	set(value):
		stars = clampi(value, 0, 3)
		queue_redraw()

@export var star_size: float = 28.0:
	set(value):
		star_size = value
		custom_minimum_size = Vector2(star_size * 3.4, star_size)
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(star_size * 3.4, star_size)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var gap := star_size * 0.2
	var total := star_size * 3 + gap * 2
	var left := (size.x - total) / 2.0
	for i in range(3):
		var center := Vector2(left + star_size / 2.0 + i * (star_size + gap), size.y / 2.0)
		draw_colored_polygon(_star_points(center, star_size / 2.0), FILLED if i < stars else EMPTY)


static func _star_points(center: Vector2, radius: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(10):
		var r := radius if i % 2 == 0 else radius * 0.45
		var angle := -PI / 2.0 + i * PI / 5.0
		points.append(center + Vector2(cos(angle), sin(angle)) * r)
	return points
