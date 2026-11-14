
extends Control

const VALID_USERNAME := "<removed>"
const VALID_PASSWORD := "<removed>"

@onready var username_input: LineEdit = $LoginCenter/LoginPanel/LoginVBox/UsernameInput
@onready var password_input: LineEdit = $LoginCenter/LoginPanel/LoginVBox/PasswordInput
@onready var enter_button: Button = $LoginCenter/LoginPanel/LoginVBox/EnterButton



var logged_in: bool = false




func _ready() -> void:
	enter_button.pressed.connect(_on_enter_pressed)
	username_input.text_submitted.connect(_on_username_submitted)
	password_input.text_submitted.connect(_on_password_submitted)






func _on_enter_pressed() -> void:
	var username := username_input.text.strip_edges()
	var password := password_input.text

	if username == VALID_USERNAME and password == VALID_PASSWORD:
		logged_in = true
		enter_button.text = "Кірдіңіз!"
		enter_button.disabled = true
		print("Login successful!")
		try_enter_game()
	
	else:
		enter_button.text = "Қате!"
		enter_button.disabled = true

		await get_tree().create_timer(1.0).timeout

		password_input.clear()
		password_input.grab_focus()

		enter_button.text = "Кіру"
		enter_button.disabled = false





var transitioning: bool = false


func try_enter_game() -> void:
	if not logged_in or transitioning:
		return

	transitioning = true

	await get_tree().create_timer(1.0).timeout

	get_tree().change_scene_to_file("res://main_menu.tscn")





func _on_username_submitted(_text: String) -> void:
	print("Username Enter detected!")

	if enter_button.disabled:
		return

	if password_input.text.is_empty():
		password_input.grab_focus.call_deferred()
	else:
		_on_enter_pressed()



func _on_password_submitted(_text: String) -> void:
	if not enter_button.disabled:
		_on_enter_pressed()


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		if event.pressed and not event.echo:
			if event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER:
				print("ENTER DETECTED")
				print("Focused control: ", get_viewport().gui_get_focus_owner())
