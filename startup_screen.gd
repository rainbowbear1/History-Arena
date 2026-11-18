extends Control

# Sign-in screen: Google (Firebase Authentication), or play offline as a guest.

const OFFLINE_NOTE := "Онлайн режим қосылмаған. Қонақ ретінде ойнаңыз: нәтижелер тек осы құрылғыда сақталады."
const GUEST_NOTE := "Қонақ нәтижелері рейтингке түспейді."
# What is recorded, and for whom (the teacher dashboard, web/admin.html). Also shown in Settings.
const RECORDING_NOTICE := "Бұл ойын — «Қазақстан тарихы» пәні бойынша университет тапсырмасы. Google арқылы кірген ойыншылардың прогресі мен белсенділігі (нәтижелер, ойын уақыты, соңғы кіру) жазылып, оқытушыға көрсетіледі. Қонақ ойыны тек осы құрылғыда қалады."

@onready var google_button: Button = %GoogleButton
@onready var guest_button: Button = %GuestButton
@onready var status_label: Label = %StatusLabel


func _ready() -> void:
	var notice := Label.new()
	notice.name = "RecordingNotice"
	notice.text = tr(RECORDING_NOTICE)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	notice.custom_minimum_size = Vector2(440, 0)
	notice.add_theme_font_size_override("font_size", 14)
	notice.add_theme_color_override("font_color", Color(0.72, 0.75, 0.8))
	status_label.add_sibling(notice)
	google_button.pressed.connect(_on_google_pressed)
	guest_button.pressed.connect(_on_guest_pressed)

	if Backend.online_available():
		# Firebase restores a saved session asynchronously; wait before offering the buttons.
		google_button.disabled = true
		guest_button.disabled = true
		status_label.text = tr("Сессия тексерілуде...")
		if await Backend.restore_session():
			_enter_game()
			return
		guest_button.disabled = false

	google_button.disabled = not Backend.online_available()
	status_label.text = tr(GUEST_NOTE if Backend.online_available() else OFFLINE_NOTE)
	(google_button if Backend.online_available() else guest_button).grab_focus.call_deferred()


func _on_google_pressed() -> void:
	google_button.disabled = true
	guest_button.disabled = true
	status_label.text = tr("Google арқылы кіру...")

	var error := await Backend.sign_in_with_google()
	if error.is_empty():
		_enter_game()
		return

	status_label.text = error
	google_button.disabled = not Backend.online_available()
	guest_button.disabled = false


func _on_guest_pressed() -> void:
	Backend.continue_as_guest()
	_enter_game()


func _enter_game() -> void:
	get_tree().change_scene_to_file.call_deferred("res://main_menu.tscn")
