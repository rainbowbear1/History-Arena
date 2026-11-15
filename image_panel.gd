extends PanelContainer

# The photograph of an image task, shown in the HUD under the question (not in the 3D arena):
# centred, aspect ratio kept, at most MAX_WIDTH_SHARE of the screen wide and MAX_HEIGHT_SHARE
# high, in a light frame with the photo's credit underneath. The answer soldiers stay in the arena
# and their labels keep clear of the panel (answer_labels.gd).

const MAX_WIDTH_SHARE := 0.42
const MAX_HEIGHT_SHARE := 0.3
const GAP := 8.0
# Opacity while an answer soldier stands behind the photo (the player has turned), so the photo
# never hides a target.
const SEE_THROUGH := 0.3
# Author and licence of each photo (full details in assets/CREDITS.md).
const CREDITS := {
	"golden_man.jpg": "eggry · CC BY-SA 2.0",
	"kultegin_monument.jpg": "Vezirtonyukuk · CC BY-SA 4.0",
	"otrar_aerial.jpg": "Coopypasted · CC BY-SA 4.0",
	"jochi_mausoleum.jpg": "Aeon32 · Public domain",
	"yasawi_mausoleum.jpg": "Petar Milošević · CC BY-SA 4.0",
	"abai.jpg": "Public domain",
	"baikonur_launch.jpg": "NASA · Public domain",
	"bayterek.jpg": "Quarot · CC0",
}

var picture: TextureRect
var credit: Label


func _ready() -> void:
	name = "ImagePanel"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.95, 0.92, 0.85)
	style.set_corner_radius_all(6)
	style.set_content_margin_all(6)
	style.shadow_color = Color(0, 0, 0, 0.45)
	style.shadow_size = 10
	style.shadow_offset = Vector2(0, 4)
	add_theme_stylebox_override("panel", style)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	add_child(column)
	picture = TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	column.add_child(picture)
	credit = Label.new()
	credit.add_theme_font_size_override("font_size", 11)
	credit.add_theme_color_override("font_color", Color(0.35, 0.32, 0.28))
	credit.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	column.add_child(credit)
	hide()


# Follows the question bar (its height changes with the question) and the window size, and turns
# see-through while an answer soldier is behind it.
func _process(delta: float) -> void:
	_layout()
	var covering := false
	var labels := get_node_or_null("../AnswerLabels")
	if visible and labels:
		var rect := get_global_rect()
		for entry in labels.entries:
			if entry["visible"] and (rect.has_point(entry["anchor"]) or rect.has_point(entry["foot"])):
				covering = true
	modulate.a = move_toward(modulate.a, SEE_THROUGH if covering else 1.0, delta * 4.0)


func show_image(path: String) -> void:
	picture.texture = load(path)
	credit.text = tr("Фото: ") + CREDITS[path.get_file()] if CREDITS.has(path.get_file()) else ""
	credit.visible = not credit.text.is_empty()
	show()
	_layout()


# Scales the photo to fit the allowed box and centres the panel just under the question bar.
func _layout() -> void:
	if not visible or picture.texture == null:
		return
	var screen := get_viewport_rect().size
	var size_px := Vector2(picture.texture.get_size())
	var fit := minf(screen.x * MAX_WIDTH_SHARE / size_px.x, screen.y * MAX_HEIGHT_SHARE / size_px.y)
	picture.custom_minimum_size = (size_px * fit).floor()
	reset_size()
	var bar := get_node_or_null("../TopBar") as Control
	var top := (bar.get_global_rect().end.y if bar else 0.0) + GAP
	position = Vector2(roundf((screen.x - size.x) / 2.0), top)
