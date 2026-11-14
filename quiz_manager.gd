extends Node

var score: int = 0
var health: int = 100
var question_index: int = 0
var accepting_answers: bool = true


@export_file("*.json") var question_file: String = "res://questions/saka.json"

var questions: Array = []


const LEVEL_FILES = {
	1: "res://questions/saka.json",
	2: "res://questions/huns.json",
	3: "res://questions/turkic.json"
}


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
	randomize()

	question_file = LEVEL_FILES.get(
		GameState.selected_level,
        "res://questions/saka.json"
	)

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
	if not FileAccess.file_exists(question_file):
		push_error("Question file not found: " + question_file)
		return

	var file := FileAccess.open(question_file, FileAccess.READ)

	if file == null:
		push_error("Cannot open question file: " + question_file)
		return

	var json := JSON.new()
	var error := json.parse(file.get_as_text())

	if error != OK:
		push_error("JSON error: " + json.get_error_message())
		return

	if not json.data is Array:
		push_error("Question file must contain an array.")
		return

	questions = []
	for i in range(json.data.size()):
		var question = json.data[i]
		var problem := validate_question(question)
		if problem.is_empty():
			questions.append(question)
		else:
			push_warning("Skipping question %d in %s: %s" % [i, question_file, problem])

	print("Loaded ", questions.size(), " questions from ", question_file)


# Returns an empty string if the question is usable, otherwise the reason it is not.
func validate_question(question) -> String:
	if not question is Dictionary:
		return "entry is not an object"

	if not question.get("question") is String or question["question"].strip_edges().is_empty():
		return "missing or empty \"question\" text"

	if not question.get("answers") is Array:
		return "missing \"answers\" array"

	var answers: Array = question["answers"]
	if answers.size() != targets.size():
		return "expected %d answers, got %d" % [targets.size(), answers.size()]

	for answer in answers:
		if not answer is String or answer.strip_edges().is_empty():
			return "every answer must be a non-empty string"

	if has_duplicates(answers):
		return "answers must be unique"

	if not question.get("correct") is String:
		return "missing \"correct\" answer"

	if not answers.has(question["correct"]):
		return "\"correct\" answer is not one of the answers"

	return ""


func has_duplicates(values: Array) -> bool:
	var seen := {}
	for value in values:
		if seen.has(value):
			return true
		seen[value] = true
	return false
