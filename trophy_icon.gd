extends Control

# A BOSS trophy drawn as shapes (like star_row.gd): a cup on a stem and base. Bronze, silver and gold
# differ in colour and in the number of bands on the base (1, 2, 3), so they stay apart without colour.
# Level 0 draws nothing.

const COLORS := [Color(0, 0, 0, 0), Color(0.72, 0.45, 0.24), Color(0.78, 0.8, 0.84), Color(0.96, 0.78, 0.25)]
const SHADES := [Color(0, 0, 0, 0), Color(0.48, 0.28, 0.13), Color(0.52, 0.55, 0.6), Color(0.72, 0.52, 0.08)]
const NAMES := ["", "Қола жүлде", "Күміс жүлде", "Алтын жүлде"]

@export var level: int = 0:
	set(value):
		level = clampi(value, 0, 3)
		tooltip_text = tr(NAMES[level])
		queue_redraw()

@export var icon_size: float = 24.0:
	set(value):
		icon_size = value
		custom_minimum_size = Vector2(icon_size, icon_size)
		queue_redraw()


func _ready() -> void:
	custom_minimum_size = Vector2(icon_size, icon_size)


func _draw() -> void:
	if level == 0:
		return
	var s := icon_size
	var o := Vector2((size.x - s) / 2.0, (size.y - s) / 2.0)
	var color: Color = COLORS[level]
	var shade: Color = SHADES[level]
	# Handles, then the bowl over them.
	draw_arc(o + Vector2(s * 0.24, s * 0.3), s * 0.15, PI * 0.5, PI * 1.5, 12, shade, maxf(1.5, s * 0.07))
	draw_arc(o + Vector2(s * 0.76, s * 0.3), s * 0.15, -PI * 0.5, PI * 0.5, 12, shade, maxf(1.5, s * 0.07))
	var bowl := PackedVector2Array([o + Vector2(s * 0.2, s * 0.08), o + Vector2(s * 0.8, s * 0.08), o + Vector2(s * 0.7, s * 0.42),
		o + Vector2(s * 0.56, s * 0.56), o + Vector2(s * 0.44, s * 0.56), o + Vector2(s * 0.3, s * 0.42)])
	draw_colored_polygon(bowl, color)
	draw_colored_polygon(PackedVector2Array([o + Vector2(s * 0.3, s * 0.12), o + Vector2(s * 0.38, s * 0.12), o + Vector2(s * 0.4, s * 0.4), o + Vector2(s * 0.35, s * 0.38)]),
		Color(1, 1, 1, 0.35))
	# Stem and base; the base carries one band per tier.
	draw_rect(Rect2(o + Vector2(s * 0.45, s * 0.55), Vector2(s * 0.1, s * 0.16)), color)
	var base := Rect2(o + Vector2(s * 0.26, s * 0.71), Vector2(s * 0.48, s * 0.22))
	draw_rect(base, color)
	var band_width := base.size.x / 7.0
	for i in range(level):
		var x := base.position.x + band_width * (1 + i * 2)
		draw_rect(Rect2(Vector2(x, base.position.y + s * 0.04), Vector2(band_width, base.size.y - s * 0.08)), shade)
