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

const MAX_HEALTH := 100
const DAMAGE := 10
# Question types that can be asked on the medical-help screen (plain four-button answers).
const REVIVAL_TYPES := ["single_choice", "fill_blank"]

var score: int = 0
var health: int = MAX_HEALTH
var lives: int = 3
var revivals_left: int = 1
var question_index: int = 0
var accepting_answers: bool = true

# Questions the player got wrong this run; asked first on the medical-help screen.
var missed_questions: Array = []
var used_revival_questions: Array = []


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
@onready var progress_label: Label = $"../HUD/ProgressLabel"
@onready var score_label: Label = $"../HUD/ScoreLabel"
@onready var health_label: Label = $"../HUD/HealthLabel"
@onready var lives_label: Label = $"../HUD/LivesLabel"
@onready var revival_panel: CenterContainer = $"../HUD/RevivalContainer"
@onready var results_container: CenterContainer = $"../HUD/ResultsContainer"
@onready var results_label: Label = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/ResultsLabel"
@onready var feedback_label: Label = $"../HUD/FeedbackLabel"



func _ready() -> void:
	_setup_map_board()

	var level := LevelDatabase.get_level(GameState.selected_level)
	if not level.is_empty():
		question_file = level["question_file"]
		lives = level["lives"]
		revivals_left = level["revivals"]

	revival_panel.revived.connect(_on_revived)

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
	update_progress()



func target_hit(target) -> void:
	if not accepting_answers or current_task == null:
		return

	var outcome := current_task.on_target_hit(target)
	var message := current_task.message
	current_task.message = ""
	update_progress()

	match outcome:
		QuizTask.Outcome.NONE:
			if not message.is_empty():
				show_feedback(message, Color.WHITE, 1.0)
		QuizTask.Outcome.PROGRESS:
			show_feedback("Дұрыс! %d/%d" % [current_task.done, current_task.total], Color.GREEN, 0.6)
		QuizTask.Outcome.MISTAKE:
			var life_lost := take_damage()
			if lives <= 0:
				finish_task("Қате!", Color.RED)
			elif life_lost:
				show_feedback("Бір жан жоғалды!", Color.RED, 1.2)
			else:
				show_feedback(message if not message.is_empty() else "Қате!", Color.RED, 1.0)
		QuizTask.Outcome.SOLVED:
			score += 100
			update_hud()
			finish_task("Дұрыс!", Color.GREEN)
		QuizTask.Outcome.FAILED:
			missed_questions.append(current_task.question)
			var life_lost := take_damage()
			finish_task("Қате! Бір жан жоғалды!" if life_lost and lives > 0 else "Қате!", Color.RED)


# Applies one mistake. Returns true if it cost a life; HP refills while lives remain.
func take_damage() -> bool:
	health -= DAMAGE
	var life_lost := health <= 0
	if life_lost:
		lives -= 1
		health = MAX_HEALTH if lives > 0 else 0
	update_hud()
	return life_lost


# Shows the final feedback for a task, then moves on (or to the defeat screen with no lives left).
func finish_task(text: String, color: Color) -> void:
	accepting_answers = false
	show_feedback(text, color, 1.0)

	await get_tree().create_timer(1.0, false).timeout

	if lives <= 0:
		show_defeat()
		return

	question_index += 1
	load_question()


func show_defeat() -> void:
	accepting_answers = false
	clear_arena()
	question_label.text = ""

	var help_question := {}
	if revivals_left > 0:
		help_question = pick_revival_question()
		if not help_question.is_empty():
			revivals_left -= 1
			used_revival_questions.append(help_question)

	revival_panel.open(score, help_question)


# Prefers a question the player missed this run, then any unused one, so the
# medical-help task reinforces what they got wrong.
func pick_revival_question() -> Dictionary:
	var eligible := questions.filter(func(q): return REVIVAL_TYPES.has(QuestionValidator.get_type(q)))
	var unused := eligible.filter(func(q): return not used_revival_questions.has(q))

	var missed := unused.filter(func(q): return missed_questions.has(q))
	if not missed.is_empty():
		return missed.pick_random()
	if not unused.is_empty():
		return unused.pick_random()
	if not eligible.is_empty():
		return eligible.pick_random()
	return {}


# Medical help succeeded: one life back with full HP; score and progress are kept,
# and play continues with the next task.
func _on_revived() -> void:
	lives = 1
	health = MAX_HEALTH
	update_hud()

	if OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	question_index += 1
	load_question()


# True while a full-screen menu (results or defeat) is open.
func overlay_open() -> bool:
	return results_container.visible or revival_panel.visible


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



func update_progress() -> void:
	if current_task == null or current_task.total == 0:
		progress_label.text = ""
		return
	progress_label.text = "%s: %d/%d" % [current_task.progress_name, current_task.done, current_task.total]


func update_hud() -> void:
	score_label.text = "Ұпай саны: " + str(score)
	health_label.text = "HP: " + str(health)
	lives_label.text = "Жан: " + str(lives)


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
	progress_label.text = ""
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
