extends CenterContainer

# "СІЗ ЖЕҢІЛДІҢІЗ!" screen shown when the player's HP runs out. Offers one
# historical question as medical help: a correct answer emits `revived`, a wrong
# one leaves only Restart and Levels.

signal revived
signal help_failed

const CORRECT_COLOR := Color(0.3, 0.75, 0.35)
const WRONG_COLOR := Color(0.85, 0.3, 0.3)
const REVIVE_DELAY := 1.5

var question: Dictionary = {}
var restore_hp: int = 0

@onready var message_label: Label = %MessageLabel
@onready var question_label: Label = %QuestionLabel
@onready var answers_grid: GridContainer = %AnswersGrid
@onready var result_label: Label = %ResultLabel
@onready var restart_button: Button = %RestartButton
@onready var levels_button: Button = %LevelsButton
@onready var answer_buttons: Array = answers_grid.get_children()


func _ready() -> void:
	hide()
	for button in answer_buttons:
		button.pressed.connect(_on_answer_pressed.bind(button))
	restart_button.pressed.connect(func(): get_tree().reload_current_scene())
	levels_button.pressed.connect(func(): get_tree().change_scene_to_file("res://level_select.tscn"))


# Shows the defeat screen. An empty `help_question` means no medical help is left.
func open(score: int, help_question: Dictionary, hp: int) -> void:
	question = help_question
	restore_hp = hp
	result_label.text = ""

	if question.is_empty():
		message_label.text = "Медициналық көмек мүмкіндігі қалмады.\nЖалпы ұпай: %d" % score
		question_label.hide()
		answers_grid.hide()
	else:
		message_label.text = "Бірақ тарихи біліміңіз Сізді құтқара алады.\nМедициналық көмек алу үшін тарихи тапсырманы орындаңыз."
		question_label.text = question["question"]
		question_label.show()
		answers_grid.show()

		var answers: Array = question["answers"].duplicate()
		answers.shuffle()
		for i in range(answer_buttons.size()):
			var button: Button = answer_buttons[i]
			button.text = answers[i]
			button.disabled = false
			button.remove_theme_color_override("font_disabled_color")

	show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if question.is_empty():
		restart_button.grab_focus()
	else:
		answer_buttons[0].grab_focus()


func _on_answer_pressed(button: Button) -> void:
	for other in answer_buttons:
		other.disabled = true
		if other.text == question["correct"]:
			other.add_theme_color_override("font_disabled_color", CORRECT_COLOR)

	if button.text != question["correct"]:
		button.add_theme_color_override("font_disabled_color", WRONG_COLOR)
		result_label.add_theme_color_override("font_color", WRONG_COLOR)
		result_label.text = "Медициналық көмек көрсетілмеді."
		restart_button.grab_focus()
		help_failed.emit()
		return

	result_label.add_theme_color_override("font_color", CORRECT_COLOR)
	result_label.text = "Дұрыс! +%d HP. Тапсырмаға қайта ораласыз." % restore_hp
	await get_tree().create_timer(REVIVE_DELAY, false).timeout
	hide()
	revived.emit()
