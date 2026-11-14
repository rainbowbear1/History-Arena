
extends Control

@onready var play_button: Button = $MenuCenter/MenuVBox/PlayButton
@onready var settings_button: Button = $MenuCenter/MenuVBox/SettingsButton
@onready var settings_container: CenterContainer = $SettingsContainer
@onready var demo_check: CheckButton = %DemoCheck
@onready var reset_button: Button = %ResetButton
@onready var settings_status: Label = %SettingsStatus
@onready var close_button: Button = %CloseButton

@onready var credits_button: Button = $MenuCenter/MenuVBox/CreditsButton
@onready var user_label: Label = $MenuCenter/MenuVBox/UserLabel
@onready var sign_out_button: Button = $MenuCenter/MenuVBox/SignOutButton
@onready var credits_container: CenterContainer = $CreditsContainer
@onready var credits_text: Label = %CreditsText

# Required attribution for third-party assets (full list: assets/CREDITS.md).
const CREDITS := """Ойын: Тарих Аренасы — Godot Engine 4.7 (MIT).
Карта: Natural Earth (public domain).
Суреттер (Wikimedia Commons):
«Алтын адам» — eggry, CC BY-SA 2.0
Күлтегін ескерткіші — Vezirtonyukuk, CC BY-SA 4.0
Отырар қалашығы — Coopypasted, CC BY-SA 4.0
Қожа Ахмет Ясауи кесенесі — Petar Milošević, CC BY-SA 4.0
Жошы хан кесенесі — Aeon32, public domain
Абай Құнанбайұлы — public domain
Байқоңыр, «Союз» ұшырылуы — NASA, public domain
«Бәйтерек» — Quarot, CC0
Лицензиялар: creativecommons.org/licenses"""

var reset_armed: bool = false

func _ready() -> void:
	play_button.focus_mode = Control.FOCUS_ALL
	settings_button.focus_mode = Control.FOCUS_ALL

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	sign_out_button.pressed.connect(_on_sign_out_pressed)
	user_label.text = "Ойыншы: " + Backend.display_name() if Backend.is_signed_in() else ""
	%CreditsCloseButton.pressed.connect(_close_credits)

	demo_check.toggled.connect(_on_demo_toggled)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(_close_settings)

	play_button.grab_focus.call_deferred()


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://level_select.tscn")


func _on_settings_pressed() -> void:
	demo_check.set_pressed_no_signal(ProgressStore.demo_unlock_all)
	reset_armed = false
	reset_button.text = "Прогресті тазалау"
	settings_status.text = ""
	$MenuCenter.hide()
	settings_container.show()
	demo_check.grab_focus()


func _on_sign_out_pressed() -> void:
	Backend.sign_out()
	get_tree().change_scene_to_file("res://startup_screen.tscn")


func _on_credits_pressed() -> void:
	credits_text.text = CREDITS
	$MenuCenter.hide()
	credits_container.show()
	%CreditsCloseButton.grab_focus()


func _close_credits() -> void:
	credits_container.hide()
	$MenuCenter.show()
	credits_button.grab_focus()


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
