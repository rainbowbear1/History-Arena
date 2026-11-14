
extends Control

@onready var level_grid: GridContainer = $CenterContainer/VBoxContainer/LevelGrid
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

func _ready() -> void:
	for i in range(10):
		var button: Button = level_grid.get_child(i)
		var level_number := i + 1

		if level_number <= 3:
			button.focus_mode = Control.FOCUS_ALL
			button.pressed.connect(_on_level_selected.bind(level_number))
		else:
			button.text = str(level_number) + " 🔒"
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
	
	back_button.pressed.connect(_on_back_pressed)

	level_grid.get_child(0).grab_focus.call_deferred()




func _on_level_selected(level_number: int) -> void:
	GameState.selected_level = level_number
	get_tree().change_scene_to_file("res://main.tscn")




func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")
