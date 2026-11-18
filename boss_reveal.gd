extends Control

# "BOSS UNLOCKED" surprise shown once over the results after level 10 is passed for the first time:
# a dark band with the title punching in, a short hold, then it fades and the results stay.

const HOLD := 2.2


func play() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var band := ColorRect.new()
	band.color = Color(0.05, 0.03, 0.04, 0.88)
	band.anchor_left = 0.0
	band.anchor_right = 1.0
	band.anchor_top = 0.5
	band.anchor_bottom = 0.5
	band.offset_top = -90
	band.offset_bottom = 90
	band.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(band)
	var title := Label.new()
	title.text = tr("BOSS АШЫЛДЫ!")
	title.theme_type_variation = &"Heading"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", Color(0.95, 0.3, 0.2))
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	title.add_theme_constant_override("outline_size", 10)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	band.add_child(title)
	var hint := Label.new()
	hint.text = tr("Деңгейлер тізімінде 8-деңгейдің астында")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint.offset_top = -34
	hint.offset_bottom = -8
	band.add_child(hint)

	await get_tree().process_frame
	title.pivot_offset = title.size / 2.0
	title.scale = Vector2.ONE * 2.2
	modulate.a = 0.0
	var tween := create_tween()
	tween.set_parallel()
	tween.tween_property(self, "modulate:a", 1.0, 0.15)
	tween.tween_property(title, "scale", Vector2.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.chain().tween_interval(HOLD)
	tween.chain().tween_property(self, "modulate:a", 0.0, 0.5)
	tween.chain().tween_callback(queue_free)
