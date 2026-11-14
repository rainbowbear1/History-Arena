extends Node

const QuestionValidator := preload("res://question_validator.gd")
const QuizTask := preload("res://tasks/quiz_task.gd")
const Abilities := preload("res://abilities.gd")
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
const IMAGE_HEIGHT := 3.0
const MAP_SIZE := Vector2(12.0, 6.0)
# Drop a real map here and it replaces the placeholder board.
const MAP_TEXTURE := "res://assets/maps/kazakhstan.svg"

const DAMAGE := 10
# Matching and chronology take several shots, so they get more time.
const MULTI_STEP_TYPES := ["matching", "chronology"]
const MULTI_STEP_TIME := 2.0
# Image tasks keep the top row free for the picture, so they get no decoys.
const DECOY_TYPES := ["single_choice", "fill_blank"]
const POINTS := 100
const ABILITY_COLOR := Color(0.91, 0.78, 0.5)
const FADE_SECONDS := 0.6
const ProgressStoreScript := preload("res://progress_store.gd")
# Question types that can be asked on the medical-help screen (plain four-button answers).
const REVIVAL_TYPES := ["single_choice", "fill_blank"]

var score: int = 0
var level: Dictionary = {}

# Run statistics saved with the result (and later sent to the Game Hub).
var correct_count: int = 0
var wrong_count: int = 0
var playtime: float = 0.0
var revivals_used: int = 0
var run_active: bool = true
var last_attempt: Dictionary = {}
var time_limit: float = 0.0
var time_left: float = 0.0
var max_health: int = 100
var health: int = 100
var revive_hp: int = 50
var revivals_left: int = 1
var question_index: int = 0
var accepting_answers: bool = true

# Questions the player got wrong this run; asked first on the medical-help screen.
var missed_questions: Array = []
var used_revival_questions: Array = []

# Chosen character and the state of its E ability.
var character: Dictionary = {}
var ability_uses: int = 0
var shield_active: bool = false
var double_score_active: bool = false
var slow_active: bool = false
var slow_token: int = 0


@export_file("*.json") var question_file: String = "res://questions/saka.json"

var questions: Array = []
var current_task: QuizTask
var targets: Array = []
var feedback_token: int = 0


@onready var targets_root: Node3D = $"../Targets"
@onready var image_board: Sprite3D = $"../ImageBoard"
@onready var map_board: MeshInstance3D = $"../MapBoard"
@onready var enemy_spawner: Node3D = $"../Enemies"


@onready var question_label: Label = $"../HUD/QuestionLabel"
@onready var hint_label: Label = $"../HUD/HintLabel"
@onready var progress_label: Label = $"../HUD/ProgressLabel"
@onready var score_label: Label = $"../HUD/ScoreLabel"
@onready var health_label: Label = $"../HUD/HealthLabel"
@onready var timer_label: Label = $"../HUD/TimerLabel"
@onready var character_label: Label = $"../HUD/CharacterLabel"
@onready var ability_label: Label = $"../HUD/AbilityLabel"
@onready var revival_panel: CenterContainer = $"../HUD/RevivalContainer"
@onready var results_container: CenterContainer = $"../HUD/ResultsContainer"
@onready var results_label: Label = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/ResultsLabel"
@onready var results_title: Label = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/ResultsTitle"
@onready var results_stars: Control = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/ResultsStars"
@onready var next_button: Button = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/NextButton"
@onready var fade_rect: ColorRect = $"../HUD/FadeRect"
@onready var feedback_label: Label = $"../HUD/FeedbackLabel"



func _ready() -> void:
	_setup_map_board()

	level = LevelDatabase.get_level(GameState.selected_level)
	if not level.is_empty():
		question_file = level["question_file"]
		revive_hp = level["revive_hp"]
		revivals_left = level["revivals"]

	character = CharacterDatabase.get_character(GameState.selected_character)
	if not character.is_empty():
		max_health = character["hp"]
		# Resources shrink on harder levels: one use fewer every two stars.
		ability_uses = maxi(1, character["ability"]["uses"] - (level.get("stars", 1) - 1) / 2)
	health = max_health

	revival_panel.revived.connect(_on_revived)
	revival_panel.help_failed.connect(_record_defeat)
	enemy_spawner.configure(self, $"../Player", level)

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
		finish_level()
		return

	var question: Dictionary = questions[question_index]
	current_task = TASK_SCRIPTS[QuestionValidator.get_type(question)].new()

	question_label.text = question["question"]
	update_hud()

	current_task.start(question, self)
	hint_label.text = current_task.hint()
	update_progress()

	time_limit = 0.0
	if not level.is_empty():
		var multi_step := MULTI_STEP_TYPES.has(QuestionValidator.get_type(question))
		time_limit = level["time_per_question"] * (MULTI_STEP_TIME if multi_step else 1.0)
	time_left = time_limit
	update_timer()
	enemy_spawner.start()


func _process(delta: float) -> void:
	if run_active:
		playtime += delta
	if not timer_running():
		return
	time_left = maxf(time_left - delta, 0.0)
	update_timer()
	if time_left <= 0.0:
		_on_time_up()


# Running out of time counts as a wrong answer.
func _on_time_up() -> void:
	if current_task.has_method("reveal_correct"):
		missed_questions.append(current_task.question)
		current_task.reveal_correct()
	wrong_count += 1
	var blocked := take_damage(DAMAGE)
	finish_task("Уақыт бітті! Қалқан қорғады" if blocked else "Уақыт бітті!", Color.RED)


func update_timer() -> void:
	timer_label.text = "Уақыт: %d" % ceili(time_left) if time_limit > 0.0 else ""
	timer_label.add_theme_color_override("font_color", Color.RED if time_left <= 5.0 else Color.WHITE)



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
			wrong_count += 1
			var blocked := take_damage(DAMAGE)
			if health <= 0:
				finish_task("Қате!", Color.RED)
			elif blocked:
				show_feedback("Қалқан қорғады!", ABILITY_COLOR, 1.0)
			else:
				show_feedback(message if not message.is_empty() else "Қате!", Color.RED, 1.0)
		QuizTask.Outcome.SOLVED:
			correct_count += 1
			var doubled := double_score_active
			double_score_active = false
			score += POINTS * (2 if doubled else 1)
			update_hud()
			finish_task("Дұрыс! ×2" if doubled else "Дұрыс!", Color.GREEN)
		QuizTask.Outcome.FAILED:
			missed_questions.append(current_task.question)
			wrong_count += 1
			var blocked := take_damage(DAMAGE)
			finish_task("Қате! Қалқан қорғады" if blocked else "Қате!", Color.RED)


# Applies damage unless the shield ability absorbs it. Returns true if the shield blocked it.
func take_damage(amount: int) -> bool:
	if shield_active:
		shield_active = false
		update_hud()
		return true
	health = maxi(health - amount, 0)
	update_hud()
	return false


# An enemy strike: the character's defense blocks part of it (at least 1 HP gets through).
func enemy_attack(amount: int) -> void:
	if not accepting_answers:
		return
	var defense: int = character.get("defense", 0)
	var reduced := maxi(1, roundi(amount * (100 - defense) / 100.0))
	var blocked := take_damage(reduced)
	if health <= 0:
		finish_task("Жау жеңді!", Color.RED)
	elif blocked:
		show_feedback("Қалқан қорғады!", ABILITY_COLOR, 0.8)
	else:
		show_feedback("Жау шабуылы! −%d HP" % reduced, Color.RED, 0.8)


func use_ability() -> void:
	if not accepting_answers or current_task == null or ability_uses <= 0:
		return

	var text := Abilities.apply(character["ability"]["id"], self)
	if text.is_empty():
		show_feedback("Қазір қолдануға болмайды", Color.WHITE, 1.0)
		return

	ability_uses -= 1
	update_hud()
	show_feedback(text, ABILITY_COLOR, 1.2)


# Slows answer targets (and later enemies) for a few seconds.
func set_slow(enabled: bool) -> void:
	slow_active = enabled
	for target in targets:
		target.speed_scale = Abilities.SLOW_FACTOR if enabled else 1.0
	enemy_spawner.set_speed_scale(Abilities.SLOW_FACTOR if enabled else 1.0)

	if enabled:
		slow_token += 1
		var token := slow_token
		await get_tree().create_timer(Abilities.SLOW_SECONDS, false).timeout
		if token == slow_token:
			set_slow(false)


# True while a task's countdown is running.
func timer_running() -> bool:
	return accepting_answers and current_task != null and time_limit > 0.0


func extra_decoys() -> int:
	return level.get("extra_decoys", 0)


# Wrong answers borrowed from other questions in this level, to use as decoy targets.
# Prefers answers of the same kind (dates with dates, names with names).
func decoy_answers(question: Dictionary, count: int) -> Array:
	var wants_digits := _has_digit(question["correct"])
	# Compare by meaning, so "552" is never a decoy beside "552 ж.".
	var taken := {}
	for answer in question["answers"]:
		taken[_answer_key(answer)] = true

	var same_kind := []
	var other_kind := []
	for other in questions:
		if other == question or not DECOY_TYPES.has(QuestionValidator.get_type(other)):
			continue
		for answer in other["answers"]:
			var key := _answer_key(answer)
			if taken.has(key):
				continue
			taken[key] = true
			if _has_digit(answer) == wants_digits:
				same_kind.append(answer)
			else:
				other_kind.append(answer)

	same_kind.shuffle()
	other_kind.shuffle()
	return (same_kind + other_kind).slice(0, count)


static func _has_digit(text: String) -> bool:
	for c in text:
		if c >= "0" and c <= "9":
			return true
	return false


# Answers with numbers compare by their digits ("552 ж." == "552"); others by lowercase letters.
static func _answer_key(text: String) -> String:
	var key := ""
	var digits_only := _has_digit(text)
	for c in text.to_lower():
		if (c >= "0" and c <= "9") or (not digits_only and c.to_upper() != c.to_lower()):
			key += c
	return key


func remove_target(target) -> void:
	targets.erase(target)
	target.queue_free()


# Shows the final feedback for a task, then moves on (or to the defeat screen at 0 HP).
func finish_task(text: String, color: Color) -> void:
	accepting_answers = false
	show_feedback(text, color, 1.0)

	await get_tree().create_timer(1.0, false).timeout

	if health <= 0:
		show_defeat()
		return

	question_index += 1
	load_question()


func show_defeat() -> void:
	accepting_answers = false
	clear_arena()
	enemy_spawner.stop()
	question_label.text = ""

	var help_question := {}
	if revivals_left > 0:
		help_question = pick_revival_question()
		if not help_question.is_empty():
			revivals_left -= 1
			used_revival_questions.append(help_question)

	if help_question.is_empty():
		_record_defeat()
	revival_panel.open(score, help_question, revive_hp)


# The run ends in defeat (no medical help left, or a wrong medical-help answer).
func _record_defeat() -> void:
	run_active = false
	last_attempt = build_attempt(false)
	ProgressStore.record_attempt(last_attempt)


# Never the task being retried (its answer may have just been shown). Prefers a
# question missed earlier this run, then one not asked yet, so the medical-help
# task reinforces what the player got wrong.
func pick_revival_question() -> Dictionary:
	var current = questions[question_index] if question_index < questions.size() else null
	var eligible := questions.filter(func(q): return q != current and REVIVAL_TYPES.has(QuestionValidator.get_type(q)))
	var unused := eligible.filter(func(q): return not used_revival_questions.has(q))

	var missed := unused.filter(func(q): return missed_questions.has(q))
	if not missed.is_empty():
		return missed.pick_random()
	if not unused.is_empty():
		return unused.pick_random()
	if not eligible.is_empty():
		return eligible.pick_random()
	return {}


# Medical help succeeded: restore the level's revive_hp and retry the task the
# player was on (answers reshuffled). Score and completed tasks are kept.
func _on_revived() -> void:
	revivals_used += 1
	health = mini(revive_hp, max_health)
	update_hud()

	if OS.has_feature("web"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	else:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

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


# All tasks done: save the result, fade to white, then show the results screen.
func finish_level() -> void:
	accepting_answers = false
	run_active = false
	clear_arena()
	enemy_spawner.stop()
	question_label.text = ""

	last_attempt = build_attempt(true)
	var new_best := ProgressStore.record_attempt(last_attempt)

	var fade_in := create_tween()
	fade_in.tween_property(fade_rect, "modulate:a", 1.0, FADE_SECONDS)
	await fade_in.finished

	show_results(last_attempt, new_best)

	var fade_out := create_tween()
	fade_out.tween_property(fade_rect, "modulate:a", 0.0, FADE_SECONDS)


func build_attempt(completed: bool) -> Dictionary:
	var max_score := questions.size() * POINTS
	var pass_percent: float = level.get("pass_percent", 60)
	var stars := ProgressStoreScript.stars_for(score, max_score, pass_percent, revivals_used) if completed else 0
	return {
		"level": GameState.selected_level,
		"character": character.get("id", ""),
		"score": score,
		"max_score": max_score,
		"correct": correct_count,
		"wrong": wrong_count,
		"playtime_sec": roundi(playtime),
		"stars": stars,
		"passed": stars > 0,
		"completed": completed,
		"revivals_used": revivals_used,
		"finished_at": int(Time.get_unix_time_from_system()),
	}


func show_results(attempt: Dictionary, new_best: bool) -> void:
	var best: Dictionary = ProgressStore.level_result(attempt["level"])
	results_title.text = "Деңгей өтілді!" if attempt["passed"] else "Деңгей өтілмеді"
	results_stars.stars = attempt["stars"]

	var seconds: int = attempt["playtime_sec"]
	var lines := [
		"Ұпай: %d / %d" % [attempt["score"], attempt["max_score"]],
		"Дұрыс: %d    Қате: %d" % [attempt["correct"], attempt["wrong"]],
		"Уақыт: %02d:%02d" % [seconds / 60, seconds % 60],
		"Жаңа рекорд!" if new_best else "Үздік нәтиже: %d" % best["best_score"],
	]
	if not attempt["passed"]:
		lines.append("Өту үшін кемінде %d%% ұпай керек" % level.get("pass_percent", 60))
	results_label.text = "\n".join(lines)

	var next_id: int = attempt["level"] + 1
	next_button.visible = attempt["passed"] and LevelDatabase.is_playable(next_id) and ProgressStore.is_unlocked(next_id)

	results_container.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(next_button if next_button.visible else results_container.get_node("ResultsPanel/ResultsVBox/RestartButton")).grab_focus()



func update_progress() -> void:
	if current_task == null or current_task.total == 0:
		progress_label.text = ""
		return
	progress_label.text = "%s: %d/%d" % [current_task.progress_name, current_task.done, current_task.total]


func update_hud() -> void:
	score_label.text = "Ұпай саны: " + str(score)
	health_label.text = "HP: %d/%d" % [health, max_health]
	if character.is_empty():
		return
	character_label.text = "%s · %s" % [character["name"], character["weapon"]["name"]]
	var ability_name: String = Abilities.INFO[character["ability"]["id"]]["name"]
	ability_label.text = "[E] %s ×%d%s" % [ability_name, ability_uses, "  · Қалқан белсенді" if shield_active else ""]


func spawn_target(text: String, at: Vector3, sways: bool = true, size: float = 1.0):
	var target = TARGET_SCENE.instantiate()
	target.answer_text = text
	target.is_correct = false
	target.position = at
	if not sways:
		target.move_distance = 0.0
	target.move_speed *= level.get("target_speed", 1.0)

	target.speed_scale = Abilities.SLOW_FACTOR if slow_active else 1.0
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
	time_limit = 0.0
	timer_label.text = ""
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


func _on_next_button_pressed() -> void:
	GameState.selected_level += 1
	get_tree().change_scene_to_file("res://character_select.tscn")


func _on_levels_button_pressed() -> void:
	get_tree().change_scene_to_file("res://level_select.tscn")



func load_questions_from_file() -> void:
	var result := QuestionValidator.load_file(question_file)

	for error in result.errors:
		push_warning(error)

	questions = result.questions
	print("Loaded ", questions.size(), " questions from ", question_file)
