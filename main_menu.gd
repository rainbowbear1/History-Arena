
extends Control

@onready var play_button: Button = $MenuCenter/MenuVBox/PlayButton
@onready var settings_button: Button = $MenuCenter/MenuVBox/SettingsButton
@onready var settings_container: CenterContainer = $SettingsContainer
@onready var demo_check: CheckButton = %DemoCheck
@onready var reset_button: Button = %ResetButton
@onready var settings_status: Label = %SettingsStatus
@onready var close_button: Button = %CloseButton

@onready var leaderboard_button: Button = $MenuCenter/MenuVBox/LeaderboardButton
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
var language_buttons := {}

func _ready() -> void:
	play_button.focus_mode = Control.FOCUS_ALL
	settings_button.focus_mode = Control.FOCUS_ALL

	play_button.pressed.connect(_on_play_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	leaderboard_button.pressed.connect(_on_leaderboard_pressed)
	credits_button.pressed.connect(_on_credits_pressed)
	sign_out_button.pressed.connect(_on_sign_out_pressed)
	user_label.text = tr("Ойыншы: ") + Backend.display_name() if Backend.is_signed_in() else ""
	%CreditsCloseButton.pressed.connect(_close_credits)

	demo_check.toggled.connect(_on_demo_toggled)
	reset_button.pressed.connect(_on_reset_pressed)
	close_button.pressed.connect(_close_settings)

	_build_language_switch()
	play_button.grab_focus.call_deferred()


# KZ / EN switch in the top-right corner. Kazakh is the default; the choice is saved (Locale) and
# applies at once to every menu, the questions and the results.
func _build_language_switch() -> void:
	var box := HBoxContainer.new()
	box.name = "LanguageSwitch"
	box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, 16)
	box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	box.add_theme_constant_override("separation", 6)
	var caption := Label.new()
	caption.text = "Тіл"
	box.add_child(caption)
	var group := ButtonGroup.new()
	for code in Locale.LANGUAGES:
		var button := Button.new()
		button.text = "KZ" if code == "kk" else "EN"
		button.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		button.toggle_mode = true
		button.button_group = group
		button.custom_minimum_size = Vector2(56, 40)
		button.button_pressed = Locale.language == code
		button.pressed.connect(_on_language_pressed.bind(code))
		box.add_child(button)
		language_buttons[code] = button
	add_child(box)


func _on_language_pressed(code: String) -> void:
	Locale.set_language(code)
	user_label.text = tr("Ойыншы: ") + Backend.display_name() if Backend.is_signed_in() else ""


func _on_play_pressed() -> void:
	get_tree().change_scene_to_file("res://level_select.tscn")


func _on_leaderboard_pressed() -> void:
	get_tree().change_scene_to_file("res://leaderboard.tscn")


func _on_settings_pressed() -> void:
	demo_check.set_pressed_no_signal(ProgressStore.demo_unlock_all)
	reset_armed = false
	reset_button.text = tr("Прогресті тазалау")
	settings_status.text = ""
	$MenuCenter.hide()
	settings_container.show()
	demo_check.grab_focus()


func _on_sign_out_pressed() -> void:
	Backend.sign_out()
	get_tree().change_scene_to_file("res://startup_screen.tscn")


func _on_credits_pressed() -> void:
	credits_text.text = tr(CREDITS)
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
	settings_status.text = tr("Барлық деңгей ашық") if enabled else tr("Деңгейлер кезекпен ашылады")


# Two presses: the first asks for confirmation, the second clears saved results.
func _on_reset_pressed() -> void:
	if not reset_armed:
		reset_armed = true
		reset_button.text = tr("Растау: барлық нәтиже өшіріледі")
		return
	ProgressStore.reset()
	demo_check.set_pressed_no_signal(false)
	reset_armed = false
	reset_button.text = tr("Прогресті тазалау")
	settings_status.text = tr("Прогресс тазаланды")
