
extends Control

@onready var play_button: Button = $MenuCenter/MenuVBox/PlayButton
@onready var settings_button: Button = $MenuCenter/MenuVBox/SettingsButton

func _ready() -> void:
	play_button.focus_mode = Control.FOCUS_ALL
	settings_button.focus_mode = Control.FOCUS_ALL

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

	play_button.grab_focus.call_deferred()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://character_select.tscn")


func _on_settings_pressed() -> void:
	print("Settings menu coming soon!")
