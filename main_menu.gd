
extends Control

@onready var play_button: Button = $MenuCenter/MenuVBox/PlayButton
@onready var settings_button: Button = $MenuCenter/MenuVBox/SettingsButton
@onready var settings_container: CenterContainer = $SettingsContainer
@onready var demo_check: CheckButton = %DemoCheck
@onready var reset_button: Button = %ResetButton
@onready var settings_status: Label = %SettingsStatus
@onready var close_button: Button = %CloseButton

var reset_armed: bool = false

func _ready() -> void:
	play_button.focus_mode = Control.FOCUS_ALL
	settings_button.focus_mode = Control.FOCUS_ALL

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)

	demo_check.toggled.connect(_on_demo_toggled)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(_close_settings)

	play_button.grab_focus.call_deferred()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://character_select.tscn")


func _on_settings_pressed() -> void:
	demo_check.set_pressed_no_signal(ProgressStore.demo_unlock_all)
	reset_armed = false
	reset_button.text = "Прогресті тазалау"
	settings_status.text = ""
	$MenuCenter.hide()
	settings_container.show()
	demo_check.grab_focus()


func _close_settings() -> void:
	settings_container.hide()
	$MenuCenter.show()
	settings_button.grab_focus()


# Demo mode opens every level that has questions, for presentations.
func _on_demo_toggled(enabled: bool) -> void:
	ProgressStore.set_demo_unlock(enabled)
	settings_status.text = "Барлық деңгей ашық" if enabled else "Деңгейлер кезекпен ашылады"


# Two presses: the first asks for confirmation, the second clears saved results.
func _on_reset_pressed() -> void:
	if not reset_armed:
		reset_armed = true
		reset_button.text = "Растау: барлық нәтиже өшіріледі"
		return
	ProgressStore.reset()
	demo_check.set_pressed_no_signal(false)
	reset_armed = false
	reset_button.text = "Прогресті тазалау"
	settings_status.text = "Прогресс тазаланды"
