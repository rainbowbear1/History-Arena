
extends Control

@onready var resume_button: Button = $CenterContainer/PausePanel/PauseVBox/ResumeButton
@onready var restart_button: Button = $CenterContainer/PausePanel/PauseVBox/RestartButton
@onready var levels_button: Button = $CenterContainer/PausePanel/PauseVBox/LevelsButton
@onready var results_container: Control = $"../ResultsContainer"

func _ready() -> void:
	hide()

	resume_button.pressed.connect(resume_game)
	restart_button.pressed.connect(restart_game)
	levels_button.pressed.connect(return_to_levels)



func _unhandled_key_input(event: InputEvent) -> void:
	if event.pressed and not event.echo and event.keycode == KEY_ESCAPE:

		if results_container.visible:
			return

		if get_tree().paused:
			resume_game()
		else:
			pause_game()

		get_viewport().set_input_as_handled()



func pause_game() -> void:
	get_tree().paused = true
	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	resume_button.grab_focus()



func resume_game() -> void:
	hide()
	get_tree().paused = false

	if OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED



func restart_game() -> void:
	get_tree().paused = false
	get_tree().reload_current_scene()


func return_to_levels() -> void:
	get_tree().paused = false
	get_tree().change_scene_to_file("res://level_select.tscn")
