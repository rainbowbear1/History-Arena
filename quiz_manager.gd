extends Node

const QuestionValidator := preload("res://question_validator.gd")

# Question types the arena can play so far; other valid types are skipped.
const PLAYABLE_TYPES := ["single_choice"]

var score: int = 0
var health: int = 100
var question_index: int = 0
var accepting_answers: bool = true


@export_file("*.json") var question_file: String = "res://questions/saka.json"

var questions: Array = []

@onready var targets = [
	$"../AnswerTarget",
	$"../AnswerTarget2",
	$"../AnswerTarget3",
	$"../AnswerTarget4"
]


@onready var question_label: Label = $"../HUD/QuestionLabel"
@onready var score_label: Label = $"../HUD/ScoreLabel"
@onready var health_label: Label = $"../HUD/HealthLabel"
@onready var results_container: CenterContainer = $"../HUD/ResultsContainer"
@onready var results_label: Label = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/ResultsLabel"
@onready var feedback_label: Label = $"../HUD/FeedbackLabel"



func _ready() -> void:
	var level := LevelDatabase.get_level(GameState.selected_level)
	if not level.is_empty():
		question_file = level["question_file"]

	load_questions_from_file()

	if questions.is_empty():
		push_error("No questions loaded!")
		accepting_answers = false
		question_label.text = "Сұрақтар жүктелмеді"
		return

	load_question()




func load_question() -> void:
	accepting_answers = true

	if question_index >= questions.size():
		show_results("Тест аяқталды!")
		return

	var question = questions[question_index]
	var answers = question["answers"].duplicate()
	answers.shuffle()

	question_label.text = question["question"]
	update_hud()

	print("QUESTION: ", question["question"])

	for i in range(targets.size()):
		targets[i].answer_text = answers[i]
		targets[i].is_correct = answers[i] == question["correct"]
		targets[i].get_node("TargetVisual/AnswerLabel").text = answers[i]



func answer_selected(correct: bool) -> void:
	if not accepting_answers:
		return

	accepting_answers = false

	if correct:
		score += 100
		feedback_label.text = "Дұрыс!"
		feedback_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		health -= 10
		feedback_label.text = "Қате!"
		feedback_label.add_theme_color_override("font_color", Color.RED)

	update_hud()
	feedback_label.show()

	await get_tree().create_timer(1.0, false).timeout

	feedback_label.hide()

	if health <= 0:
		show_results("Ойын аяқталды!")
		return

	question_index += 1
	load_question()


func show_results(title: String) -> void:
	accepting_answers = false
	question_label.text = ""
	results_label.text = title + "\n\nЖалпы ұпай: " + str(score)
	results_container.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE



func update_hud() -> void:
	score_label.text = "Ұпай саны: " + str(score)
	health_label.text = "HP: " + str(health)


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()


func _on_levels_button_pressed() -> void:
	get_tree().change_scene_to_file("res://level_select.tscn")



func load_questions_from_file() -> void:
	var result := QuestionValidator.load_file(question_file)

	for error in result.errors:
		push_warning(error)

	questions = []
	for question in result.questions:
		if PLAYABLE_TYPES.has(QuestionValidator.get_type(question)):
			questions.append(question)
		else:
			push_warning("Skipping %s question (not playable yet) in %s" % [QuestionValidator.get_type(question), question_file])

	print("Loaded ", questions.size(), " questions from ", question_file)
