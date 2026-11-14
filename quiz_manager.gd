extends Node

const QuestionValidator := preload("res://question_validator.gd")
const QuizTask := preload("res://tasks/quiz_task.gd")
const TARGET_SCENE := preload("res://answer_target.tscn")

const TASK_SCRIPTS := {
	"single_choice": preload("res://tasks/choice_task.gd"),
	"fill_blank": preload("res://tasks/choice_task.gd"),
	"image": preload("res://tasks/choice_task.gd"),
	"matching": preload("res://tasks/matching_task.gd"),
	"chronology": preload("res://tasks/chronology_task.gd"),
	"map": preload("res://tasks/map_task.gd"),
}

# Arena layout for spawned targets.
const TARGET_Z := -8.0
const ROW_SPACING := 3.0
const CHOICE_ROW_Y := 1.5
const TOP_ROW_Y := 4.0
const IMAGE_HEIGHT := 2.6
const MAP_SIZE := Vector2(12.0, 6.0)
# Drop a real map here and it replaces the placeholder board.
const MAP_TEXTURE := "res://assets/maps/kazakhstan.png"

var score: int = 0
var health: int = 100
var question_index: int = 0
var accepting_answers: bool = true


@export_file("*.json") var question_file: String = "res://questions/saka.json"

var questions: Array = []
var current_task: QuizTask
var targets: Array = []
var feedback_token: int = 0


@onready var targets_root: Node3D = $"../Targets"
@onready var image_board: Sprite3D = $"../ImageBoard"
@onready var map_board: MeshInstance3D = $"../MapBoard"


@onready var question_label: Label = $"../HUD/QuestionLabel"
@onready var hint_label: Label = $"../HUD/HintLabel"
@onready var score_label: Label = $"../HUD/ScoreLabel"
@onready var health_label: Label = $"../HUD/HealthLabel"
@onready var results_container: CenterContainer = $"../HUD/ResultsContainer"
@onready var results_label: Label = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/ResultsLabel"
@onready var feedback_label: Label = $"../HUD/FeedbackLabel"



func _ready() -> void:
	_setup_map_board()

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
	clear_arena()
	accepting_answers = true

	if question_index >= questions.size():
		show_results("Тест аяқталды!")
		return

	var question: Dictionary = questions[question_index]
	current_task = TASK_SCRIPTS[QuestionValidator.get_type(question)].new()

	question_label.text = question["question"]
	update_hud()

	current_task.start(question, self)
	hint_label.text = current_task.hint()



func target_hit(target) -> void:
	if not accepting_answers or current_task == null:
		return

	var outcome := current_task.on_target_hit(target)
	var message := current_task.message
	current_task.message = ""

	match outcome:
		QuizTask.Outcome.NONE:
			if not message.is_empty():
				show_feedback(message, Color.WHITE, 1.0)
		QuizTask.Outcome.PROGRESS:
			show_feedback("Дұрыс!", Color.GREEN, 0.6)
		QuizTask.Outcome.MISTAKE:
			health -= 10
			update_hud()
			if health <= 0:
				finish_task("Қате!", Color.RED)
			else:
				show_feedback(message if not message.is_empty() else "Қате!", Color.RED, 1.0)
		QuizTask.Outcome.SOLVED:
			score += 100
			update_hud()
			finish_task("Дұрыс!", Color.GREEN)
		QuizTask.Outcome.FAILED:
			health -= 10
			update_hud()
			finish_task("Қате!", Color.RED)


# Shows the final feedback for a task, then moves on (or ends the game at 0 HP).
func finish_task(text: String, color: Color) -> void:
	accepting_answers = false
	show_feedback(text, color, 1.0)

	await get_tree().create_timer(1.0, false).timeout

	if health <= 0:
		show_results("Ойын аяқталды!")
		return

	question_index += 1
	load_question()


func show_feedback(text: String, color: Color, duration: float) -> void:
	feedback_token += 1
	var token := feedback_token

	feedback_label.text = text
	feedback_label.add_theme_color_override("font_color", color)
	feedback_label.show()

	await get_tree().create_timer(duration, false).timeout

	if token == feedback_token:
		feedback_label.hide()


func show_results(title: String) -> void:
	accepting_answers = false
	clear_arena()
	question_label.text = ""
	results_label.text = title + "\n\nЖалпы ұпай: " + str(score)
	results_container.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE



func update_hud() -> void:
	score_label.text = "Ұпай саны: " + str(score)
	health_label.text = "HP: " + str(health)


func spawn_target(text: String, at: Vector3, sways: bool = true, size: float = 1.0):
	var target = TARGET_SCENE.instantiate()
	target.answer_text = text
	target.is_correct = false
	target.position = at
	if not sways:
		target.move_distance = 0.0

	targets_root.add_child(target)
	if size != 1.0:
		target.set_size(size)

	targets.append(target)
	return target


# Evenly spaced positions for a row of targets centred in front of the player.
func row_positions(count: int, y: float) -> Array:
	var positions := []
	for i in range(count):
		positions.append(Vector3((i - (count - 1) / 2.0) * ROW_SPACING, y, TARGET_Z))
	return positions


func show_image(path: String) -> void:
	var texture: Texture2D = load(path)
	image_board.texture = texture
	image_board.pixel_size = IMAGE_HEIGHT / texture.get_height()
	image_board.show()


func show_map() -> void:
	map_board.show()


# Converts a 0–1 map coordinate (0,0 = top-left) to a point just in front of the map board.
func map_point(x: float, y: float) -> Vector3:
	return map_board.position + Vector3((x - 0.5) * MAP_SIZE.x, (0.5 - y) * MAP_SIZE.y, 0.2)


func clear_arena() -> void:
	for target in targets:
		target.queue_free()
	targets.clear()
	current_task = null
	hint_label.text = ""
	image_board.hide()
	map_board.hide()


func _setup_map_board() -> void:
	if not ResourceLoader.exists(MAP_TEXTURE):
		return
	var material: StandardMaterial3D = map_board.get_surface_override_material(0).duplicate()
	material.albedo_color = Color.WHITE
	material.albedo_texture = load(MAP_TEXTURE)
	map_board.set_surface_override_material(0, material)
	map_board.get_node("PlaceholderLabel").hide()


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()


func _on_levels_button_pressed() -> void:
	get_tree().change_scene_to_file("res://level_select.tscn")



func load_questions_from_file() -> void:
	var result := QuestionValidator.load_file(question_file)

	for error in result.errors:
		push_warning(error)

	questions = result.questions
	print("Loaded ", questions.size(), " questions from ", question_file)
