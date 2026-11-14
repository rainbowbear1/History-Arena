
extends Control

const StarRow := preload("res://star_row.gd")

@onready var level_grid: GridContainer = $CenterContainer/VBoxContainer/LevelGrid
@onready var level_info_label: Label = $CenterContainer/VBoxContainer/LevelInfoLabel
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

func _ready() -> void:
	for level in LevelDatabase.levels:
		var level_number: int = level["id"]
		var button := Button.new()
		button.custom_minimum_size = Vector2(90, 90)
		button.text = str(level_number)
		level_grid.add_child(button)

		var earned := StarRow.new()
		earned.star_size = 18.0
		earned.stars = ProgressStore.level_result(level_number)["stars"]
		earned.position = Vector2(0, 64)
		earned.size = Vector2(90, 20)
		button.add_child(earned)

		if LevelDatabase.is_playable(level_number) and ProgressStore.is_unlocked(level_number):
			button.focus_mode = Control.FOCUS_ALL
			button.pressed.connect(_on_level_selected.bind(level_number))
			button.focus_entered.connect(_show_level_info.bind(level_number))
		else:
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE

		button.mouse_entered.connect(_show_level_info.bind(level_number))

	back_button.pressed.connect(_on_back_pressed)

	if level_grid.get_child_count() > 0:
		level_grid.get_child(0).grab_focus.call_deferred()
		_show_level_info(1)




func _show_level_info(level_number: int) -> void:
	var level := LevelDatabase.get_level(level_number)
	var difficulty := "BOSS" if level["boss"] else "%d/5" % level["stars"]
	var text := "%d. %s\nҚиындық: %s" % [level_number, level["title"], difficulty]

	if not LevelDatabase.is_playable(level_number):
		text += " · дайындалуда"
	elif not ProgressStore.is_unlocked(level_number):
		text += " · жабық: алдыңғы деңгейді өтіңіз"
	else:
		var result := ProgressStore.level_result(level_number)
		if result["attempts"] > 0:
			text += "
Үздік ұпай: %d" % result["best_score"]

	level_info_label.text = text


func _on_level_selected(level_number: int) -> void:
	GameState.selected_level = level_number
	get_tree().change_scene_to_file("res://main.tscn")




func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://character_select.tscn")
