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
# Answer formation (answer_layout): up to MAX_FRONT_ROW answers stand in one row on the ground;
# more use the ground row and the rampart. Spacing keeps every label at least ~190 px wide at
# 1280x720, so long Kazakh or English answers wrap instead of overlapping.
const MAX_FRONT_ROW := 4
const FRONT_SPACING := 3.6
const WIDE_FRONT_SPACING := 4.4
const BACK_SPACING := 4.6
# Answer placards: the bottom row is held by soldiers on the ground, the top row by soldiers
# standing on the rampart behind them (see environment_builder.gd).
const CHOICE_ROW_Y := 2.6
const TOP_ROW_Y := 5.6
# Shooting range (level 10): one wide row on the lanes; a second row (matching) stands further back.
const RANGE_SPACING := 3.6
const RANGE_BACK_ROW := Vector2(4.4, -12.0)
const TOP_ROW_Z := -10.0
const GROUND_Y := 0.1
const LEDGE_TOP := 3.1
# Drop a real map here and it replaces the placeholder board.
const ImagePanelScript := preload("res://image_panel.gd")
const GalleryScript := preload("res://gallery.gd")
const MapOverlayScript := preload("res://map_overlay.gd")

const DAMAGE := 10
# Matching and chronology take several shots, so they get more time.
const MULTI_STEP_TYPES := ["matching", "chronology"]
const MULTI_STEP_TIME := 2.0
# Image tasks keep the top row free for the picture, so they get no decoys.
const DECOY_TYPES := ["single_choice", "fill_blank"]
const POINTS := 100
const BossReveal := preload("res://boss_reveal.gd")
const ABILITY_COLOR := Color(0.91, 0.78, 0.5)
const HP_HIGH := Color(0.3, 0.75, 0.35)
const HP_MID := Color(0.9, 0.75, 0.2)
const HP_LOW := Color(0.85, 0.2, 0.15)
const FADE_SECONDS := 0.6
const ProgressStoreScript := preload("res://progress_store.gd")
# Question types that can be asked on the medical-help screen (plain four-button answers).
# Medical help asks from its own bank, never from the level's tasks.
const MEDICAL_FILE := "res://questions/medical.json"
const QuestionPools := preload("res://question_pools.gd")
const SOURCE_COLOR := Color(0.84, 0.68, 0.38)
const MAX_FRAME_TIME := 0.25

var score: int = 0
var level: Dictionary = {}
var theme: Dictionary = {}

# Run statistics saved with the result and sent to the online leaderboard.
var correct_count: int = 0
var wrong_count: int = 0
var playtime: float = 0.0
var revivals_used: int = 0
# BOSS and All-in-One: medkits restore HP on the H key; one more is earned every few tasks.
var medkits: int = 0
var medkit_stage: int = 0
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
var medical_questions: Array = []

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
# Photo and map of image and map tasks live in the HUD (image_panel.gd, map_overlay.gd).
var image_panel: PanelContainer
# Mixed runs (BOSS, All-in-One): "Сұрақ 12 / 50 · 6-деңгей — Қазақ хандығы" above the question.
var source_label: Label
var map_overlay: Control
# The Independence level's moving tracks and ducks (gallery.gd); null on other levels.
var gallery: Node3D
var music: AudioStreamPlayer
@onready var enemy_spawner: Node3D = $"../Enemies"
@onready var environment: Node3D = $"../Environment"
@onready var damage_flash: ColorRect = $"../HUD/DamageFlash"


@onready var question_panel: PanelContainer = $"../HUD/TopBar/Row/QuestionPanel"
@onready var question_label: Label = $"../HUD/TopBar/Row/QuestionPanel/QuestionVBox/QuestionLabel"
@onready var hint_label: Label = $"../HUD/TopBar/Row/QuestionPanel/QuestionVBox/HintLabel"
@onready var progress_label: Label = $"../HUD/TopBar/Row/QuestionPanel/QuestionVBox/ProgressLabel"
@onready var score_label: Label = $"../HUD/TopBar/Row/Stats/ScoreLabel"
@onready var health_bar: ProgressBar = $"../HUD/TopBar/Row/Stats/HealthBar"
@onready var health_label: Label = $"../HUD/TopBar/Row/Stats/HealthBar/HealthLabel"
@onready var timer_label: Label = $"../HUD/TopBar/Row/TimerLabel"
@onready var character_label: Label = $"../HUD/Loadout/CharacterLabel"
@onready var ability_label: Label = $"../HUD/Loadout/AbilityLabel"
@onready var answer_labels: Control = $"../HUD/AnswerLabels"
@onready var revival_panel: CenterContainer = $"../HUD/RevivalContainer"
@onready var results_container: CenterContainer = $"../HUD/ResultsContainer"
@onready var results_label: Label = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/ResultsLabel"
@onready var results_title: Label = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/ResultsTitle"
@onready var results_stars: Control = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/ResultsStars"
@onready var next_button: Button = $"../HUD/ResultsContainer/ResultsPanel/ResultsVBox/NextButton"
@onready var fade_rect: ColorRect = $"../HUD/FadeRect"
@onready var feedback_label: Label = $"../HUD/FeedbackLabel"



func _ready() -> void:
	_build_overlays()
	# Own copy of the bar's fill, recoloured as HP changes.
	health_bar.add_theme_stylebox_override("fill", health_bar.get_theme_stylebox("fill").duplicate())

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
	environment.apply(level.get("theme", ""), level.get("id", 0), $"../WorldEnvironment", $"../Sun", $"../Ground")
	theme = environment.theme
	if is_range():
		gallery = GalleryScript.new()
		get_parent().add_child.call_deferred(gallery)
	_start_music()
	enemy_spawner.configure(self, $"../Player", level, theme)
	enemy_spawner.background_shooters = environment.background_enemies

	load_questions_from_file()
	medical_questions = QuestionValidator.load_file(MEDICAL_FILE).questions.map(func(q): return Locale.localize_question(q))

	if questions.is_empty():
		push_error("No questions loaded!")
		accepting_answers = false
		set_question(tr("Сұрақтар жүктелмеді"))
		return

	load_question()




# The BOSS gets harder as it goes: 0.0 on the first task, 1.0 on the last. 0 on normal levels.
func boss_progress() -> float:
	if not level.get("boss", false) or questions.size() < 2:
		return 0.0
	return clampf(float(question_index) / (questions.size() - 1), 0.0, 1.0)


func is_boss() -> bool:
	return level.get("boss", false)


# All-in-One: every campaign task once, in a random order, with no difficulty ramp.
func is_all_in_one() -> bool:
	return level.get("all_in_one", false)


func has_medkits() -> bool:
	return is_boss() or is_all_in_one()


func load_question() -> void:
	clear_arena()
	accepting_answers = true

	if question_index >= questions.size():
		finish_level()
		return

	var question: Dictionary = questions[question_index]
	current_task = TASK_SCRIPTS[QuestionValidator.get_type(question)].new()

	# BOSS and All-in-One: a new medkit every medkit_every tasks (once per stage, also after a retry).
	var every: int = level.get("medkit_every", 0)
	if has_medkits() and every > 0 and question_index > 0 and question_index % every == 0 and medkit_stage < question_index:
		medkit_stage = question_index
		medkits += 1
		show_feedback(tr("+1 аптечка [H]"), HP_HIGH, 1.2)

	set_question(question["question"])
	update_source_label()
	update_hud()

	if gallery:
		gallery.set_progress(question_index, questions.size())
	current_task.start(question, self)
	hint_label.text = current_task.hint()
	hint_label.visible = not hint_label.text.is_empty()
	update_progress()

	time_limit = 0.0
	if not level.is_empty():
		var multi_step := MULTI_STEP_TYPES.has(QuestionValidator.get_type(question))
		time_limit = level["time_per_question"] * (MULTI_STEP_TIME if multi_step else 1.0)
		# BOSS: the timer shrinks to time_floor of its start by the last task.
		time_limit *= lerpf(1.0, level.get("time_floor", 1.0), boss_progress())
	time_left = time_limit
	update_timer()
	enemy_spawner.start()


func _process(delta: float) -> void:
	# Active time only: the arena does not run while paused, and a long frame (a hidden browser tab)
	# adds at most MAX_FRAME_TIME.
	if run_active:
		playtime += minf(delta, MAX_FRAME_TIME)
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
	enemy_spawner.reaction_shot()
	var blocked := take_damage(DAMAGE)
	finish_task(tr("Уақыт бітті! Қалқан қорғады") if blocked else tr("Уақыт бітті!"), Color.RED)


func update_timer() -> void:
	timer_label.text = tr("Уақыт: %d") % ceili(time_left) if time_limit > 0.0 else ""
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
			show_feedback(tr("Дұрыс! %d/%d") % [current_task.done, current_task.total], Color.GREEN, 0.6)
		QuizTask.Outcome.MISTAKE:
			wrong_count += 1
			enemy_spawner.reaction_shot()
			var blocked := take_damage(DAMAGE)
			if health <= 0:
				finish_task(tr("Қате!"), Color.RED)
			elif blocked:
				show_feedback(tr("Қалқан қорғады!"), ABILITY_COLOR, 1.0)
			else:
				show_feedback(message if not message.is_empty() else tr("Қате!"), Color.RED, 1.0)
		QuizTask.Outcome.SOLVED:
			correct_count += 1
			var doubled := double_score_active
			double_score_active = false
			score += POINTS * (2 if doubled else 1)
			update_hud()
			finish_task(tr("Дұрыс! ×2") if doubled else tr("Дұрыс!"), Color.GREEN)
		QuizTask.Outcome.FAILED:
			missed_questions.append(current_task.question)
			wrong_count += 1
			enemy_spawner.reaction_shot()
			var blocked := take_damage(DAMAGE)
			finish_task(tr("Қате! Қалқан қорғады") if blocked else tr("Қате!"), Color.RED)


# Applies damage unless the shield ability absorbs it. Returns true if the shield blocked it.
func take_damage(amount: int) -> bool:
	if shield_active:
		shield_active = false
		update_hud()
		return true
	health = maxi(health - amount, 0)
	update_hud()
	flash_damage()
	return false


func flash_damage() -> void:
	damage_flash.color.a = 0.35
	create_tween().tween_property(damage_flash, "color:a", 0.0, 0.45)


# An enemy strike: the character's defense blocks part of it (at least 1 HP gets through).
func enemy_attack(amount: int) -> void:
	if not accepting_answers:
		return
	var defense: int = character.get("defense", 0)
	var reduced := maxi(1, roundi(amount * (100 - defense) / 100.0))
	var blocked := take_damage(reduced)
	if health <= 0:
		finish_task(tr("Жау жеңді!"), Color.RED)
	elif blocked:
		show_feedback(tr("Қалқан қорғады!"), ABILITY_COLOR, 0.8)
	else:
		show_feedback(tr("Жау шабуылы! −%d HP") % reduced, Color.RED, 0.8)


func use_ability() -> void:
	if not accepting_answers or current_task == null or ability_uses <= 0:
		return

	var text := Abilities.apply(character["ability"]["id"], self)
	if text.is_empty():
		show_feedback(tr("Қазір қолдануға болмайды"), Color.WHITE, 1.0)
		return

	ability_uses -= 1
	update_hud()
	show_feedback(text, ABILITY_COLOR, 1.2)


# Slows answer targets (and later enemies) for a few seconds.
func set_slow(enabled: bool) -> void:
	if gallery:
		gallery.slowed = enabled
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


# Extra wrong answers for decoy targets. They come only from the question's own hand-written
# "extra_answers" (checked by QuestionValidator), never from other questions: a question without
# them gets fewer targets rather than an unrelated one.
func decoy_answers(question: Dictionary, count: int) -> Array:
	var extras: Array = question.get("extra_answers", []).duplicate()
	extras.shuffle()
	return extras.slice(0, count)


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
	set_question("")

	var help_question := {}
	if revivals_left > 0:
		help_question = pick_revival_question()
		if not help_question.is_empty():
			revivals_left -= 1
			used_revival_questions.append(help_question)

	if help_question.is_empty():
		_record_defeat()
		if is_all_in_one():
			return
	revival_panel.open(score, help_question, revive_hp)


# The run ends in defeat (no medical help left, or a wrong medical-help answer).
func _record_defeat() -> void:
	run_active = false
	last_attempt = build_attempt(false)
	var new_best := ProgressStore.record_attempt(last_attempt)
	Backend.submit_attempt(last_attempt)
	# All-in-One ends when the health runs out: its results replace the defeat screen.
	if is_all_in_one():
		if revival_panel.visible:
			await get_tree().create_timer(1.5, false).timeout
			revival_panel.hide()
		show_results(last_attempt, new_best)


# A random question from the medical-help bank (questions/medical.json), which tests other facts
# than the level, so it never repeats a task of the run. Never twice in one run, and not one of
# the questions recent defeats asked (GameState.recent_medical), so a failed help question cannot
# simply be answered again after Restart.
func pick_revival_question() -> Dictionary:
	var fresh := medical_questions.filter(func(q): return not used_revival_questions.has(q))
	var unseen := fresh.filter(func(q): return not GameState.recent_medical.has(q.get("id")))
	var pool := unseen if not unseen.is_empty() else fresh
	if pool.is_empty():
		return {}
	var question: Dictionary = pool.pick_random()
	GameState.remember_medical(question.get("id"))
	return question


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
	# A short pop: the message grows in and settles, so right and wrong register at a glance.
	feedback_label.pivot_offset = feedback_label.size / 2.0
	feedback_label.scale = Vector2.ONE * 1.35
	feedback_label.modulate.a = 0.0
	var pop := create_tween().set_parallel().set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	pop.tween_property(feedback_label, "scale", Vector2.ONE, 0.25)
	pop.tween_property(feedback_label, "modulate:a", 1.0, 0.12)

	await get_tree().create_timer(duration, false).timeout

	if token == feedback_token:
		feedback_label.hide()


# All tasks done: save the result, fade to white, then show the results screen.
func finish_level() -> void:
	accepting_answers = false
	run_active = false
	clear_arena()
	enemy_spawner.stop()
	set_question("")

	last_attempt = build_attempt(true)
	var unlock_before := ProgressStore.unlock_everything_earned
	var new_best := ProgressStore.record_attempt(last_attempt)
	# The BOSS is not a leaderboard level; a victory is a permanent achievement of the account.
	if is_boss():
		if last_attempt["passed"]:
			Backend.record_boss_victory(last_attempt["score"])
	else:
		Backend.submit_attempt(last_attempt)  # All-in-One goes to its own leaderboard.
	var earned_unlock: bool = is_boss() and ProgressStore.unlock_everything_earned and not unlock_before

	var fade_in := create_tween()
	fade_in.tween_property(fade_rect, "modulate:a", 1.0, FADE_SECONDS)
	await fade_in.finished

	show_results(last_attempt, new_best, earned_unlock)

	var fade_out := create_tween()
	fade_out.tween_property(fade_rect, "modulate:a", 0.0, FADE_SECONDS)
	# Passing level 10 for the first time: a short surprise after the results.
	if ProgressStore.boss_just_unlocked and not is_boss():
		await fade_out.finished
		var reveal := BossReveal.new()
		results_container.get_parent().add_child(reveal)
		reveal.play()


func build_attempt(completed: bool) -> Dictionary:
	var max_score := questions.size() * POINTS
	var pass_percent: float = level.get("pass_percent", 60)
	var stars := ProgressStoreScript.stars_for(score, max_score, pass_percent, revivals_used) if completed else 0
	if is_all_in_one():
		# Counted in tasks: the task on which the health ran out counts as answered (wrongly).
		var answered := questions.size() if completed else mini(question_index + 1, questions.size())
		return {
			"level": GameState.selected_level,
			"character": character.get("id", ""),
			"score": score,
			"max_score": max_score,
			"correct": correct_count,
			"wrong": answered - correct_count,
			"answered": answered,
			"playtime_sec": roundi(playtime),
			"stars": 0,
			"passed": false,
			"completed": completed,
			"revivals_used": revivals_used,
			"finished_at": int(Time.get_unix_time_from_system()),
		}
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


func show_results(attempt: Dictionary, new_best: bool, earned_unlock: bool = false) -> void:
	if is_boss():
		_show_boss_results(attempt, new_best, earned_unlock)
		return
	if is_all_in_one():
		_show_all_in_one_results(attempt, new_best)
		return
	var best: Dictionary = ProgressStore.level_result(attempt["level"])
	results_title.text = tr("Деңгей өтілді!") if attempt["passed"] else tr("Деңгей өтілмеді")
	results_stars.stars = attempt["stars"]

	var seconds: int = attempt["playtime_sec"]
	var lines := [
		tr("Ұпай: %d / %d") % [attempt["score"], attempt["max_score"]],
		tr("Дұрыс: %d    Қате: %d") % [attempt["correct"], attempt["wrong"]],
		tr("Уақыт: %02d:%02d") % [seconds / 60, seconds % 60],
		tr("Жаңа рекорд!") if new_best else tr("Үздік нәтиже: %d") % best["best_score"],
	]
	if not attempt["passed"]:
		lines.append(tr("Өту үшін кемінде %d%% ұпай керек") % level.get("pass_percent", 60))
	lines.append(tr("Жалпы ұпай: %d") % ProgressStore.total_score())
	for id in ProgressStore.just_opened:
		lines.append(tr("Жаңа деңгей ашылды: %d. %s") % [id, tr(LevelDatabase.get_level(id)["title"])])
	if Backend.is_online_player():
		lines.append(tr("Нәтиже онлайн рейтингке жіберілді"))
	elif Backend.is_guest():
		lines.append(tr("Қонақ: нәтиже рейтингке түспейді"))
	results_label.text = "\n".join(lines)

	var next_id: int = attempt["level"] + 1
	next_button.visible = LevelDatabase.is_playable(next_id) and ProgressStore.is_unlocked(next_id)

	results_container.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	(next_button if next_button.visible else results_container.get_node("ResultsPanel/ResultsVBox/RestartButton")).grab_focus()



func _show_boss_results(attempt: Dictionary, new_best: bool, earned_unlock: bool) -> void:
	results_title.text = tr("BOSS жеңілді!") if attempt["passed"] else tr("BOSS жеңілмеді")
	results_stars.stars = attempt["stars"]
	var seconds: int = attempt["playtime_sec"]
	var lines := [
		tr("Ұпай: %d / %d") % [attempt["score"], attempt["max_score"]],
		tr("Дұрыс: %d    Қате: %d") % [attempt["correct"], attempt["wrong"]],
		tr("Уақыт: %02d:%02d") % [seconds / 60, seconds % 60],
		tr("Жаңа рекорд!") if new_best else tr("Үздік нәтиже: %d") % ProgressStore.boss["best_score"],
	]
	if not attempt["passed"]:
		lines.append(tr("Жеңу үшін кемінде %d%% ұпай керек") % level.get("pass_percent", 60))
	if earned_unlock:
		lines.append(tr("Тұрақты жетістік: «Барлығын ашу» мүмкіндігі ашылды (Баптаулар)"))
	results_label.text = "\n".join(lines)
	next_button.visible = false
	results_container.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	results_container.get_node("ResultsPanel/ResultsVBox/RestartButton").grab_focus()


func _show_all_in_one_results(attempt: Dictionary, new_best: bool) -> void:
	results_title.text = tr("Барлық сұрақ орындалды!") if attempt["completed"] else tr("«Бәрі бірге» аяқталды")
	results_stars.hide()
	var best: Dictionary = ProgressStore.all_in_one_best
	var lines := [
		tr("Жауап берілген сұрақтар: %d / %d") % [attempt["answered"], questions.size()],
		tr("Дұрыс: %d    Қате: %d") % [attempt["correct"], attempt["wrong"]],
		tr("Дәлдік: %d%%") % roundi(ProgressStoreScript.accuracy_permille(attempt["correct"], attempt["answered"]) / 10.0),
		tr("Ұпай: %d") % attempt["score"],
		tr("Белсенді ойын уақыты: %s") % ProgressStoreScript.format_duration(attempt["playtime_sec"]),
		tr("Бүкіл сұрақ қоры аяқталды") if attempt["completed"] else tr("Сұрақ қоры толық аяқталмады"),
		tr("Жаңа үздік нәтиже!") if new_best else tr("Үздік нәтиже: %d дұрыс жауап") % int(best.get("correct", 0)),
	]
	if Backend.is_online_player():
		lines.append(tr("Нәтиже «Бәрі бірге» рейтингіне жіберілді"))
	elif Backend.is_guest():
		lines.append(tr("Қонақ: нәтиже рейтингке түспейді"))
	results_label.text = "\n".join(lines)
	next_button.visible = false
	results_container.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	results_container.get_node("ResultsPanel/ResultsVBox/RestartButton").grab_focus()


# H: a medkit restores medkit_hp HP (BOSS and All-in-One).
func use_medkit() -> void:
	if not has_medkits() or not accepting_answers:
		return
	if medkits <= 0 or health >= max_health:
		show_feedback(tr("Қазір қолдануға болмайды"), Color.WHITE, 1.0)
		return
	medkits -= 1
	health = mini(health + int(level.get("medkit_hp", 35)), max_health)
	update_hud()
	show_feedback(tr("Аптечка: +%d HP") % int(level.get("medkit_hp", 35)), HP_HIGH, 1.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_H:
		use_medkit()


func set_question(text: String) -> void:
	question_label.text = text
	question_panel.visible = not text.is_empty()


# Mixed runs name each task's position in the run and the campaign level and era it comes from.
func update_source_label() -> void:
	var question: Dictionary = questions[question_index] if question_index < questions.size() else {}
	if not question.has("source_level"):
		source_label.text = ""
	else:
		source_label.text = tr("Сұрақ %d / %d") % [question_index + 1, questions.size()] + "  ·  " + LevelDatabase.source_label(int(question["source_level"]))
	source_label.visible = not source_label.text.is_empty()


func update_progress() -> void:
	if current_task == null or current_task.total == 0:
		progress_label.text = ""
	else:
		progress_label.text = "%s: %d/%d" % [tr(current_task.progress_name), current_task.done, current_task.total]
	progress_label.visible = not progress_label.text.is_empty()


func update_hud() -> void:
	score_label.text = tr("Ұпай саны: %d") % score
	health_label.text = "HP %d/%d" % [health, max_health]
	health_bar.max_value = max_health
	health_bar.value = health
	var ratio := float(health) / max_health
	var fill: StyleBoxFlat = health_bar.get_theme_stylebox("fill")
	fill.bg_color = HP_LOW.lerp(HP_MID, clampf(ratio * 2.0, 0.0, 1.0)) if ratio < 0.5 else HP_MID.lerp(HP_HIGH, (ratio - 0.5) * 2.0)
	if character.is_empty():
		return
	character_label.text = "%s · %s" % [tr(character["name"]), tr(character["weapon"]["name"])]
	var ability_name: String = tr(Abilities.INFO[character["ability"]["id"]]["name"])
	ability_label.text = "[E] %s ×%d%s" % [ability_name, ability_uses, tr("  · Қалқан белсенді") if shield_active else ""]
	if has_medkits():
		ability_label.text += tr("   [H] Аптечка ×%d") % medkits


# `placement` is where its screen label goes: "above" the head or "below" the feet (answer_labels.gd).
func spawn_target(text: String, at: Vector3, sways: bool = true, size: float = 1.0, placement: String = "above"):
	var target = TARGET_SCENE.instantiate()
	target.answer_text = text
	target.is_correct = false
	target.position = at
	if not sways:
		target.move_distance = 0.0
	target.move_speed *= level.get("target_speed", 1.0) * (1.0 + level.get("speed_ramp", 0.0) * boss_progress())

	target.speed_scale = Abilities.SLOW_FACTOR if slow_active else 1.0
	targets_root.add_child(target)
	if size != 1.0:
		target.set_size(size)
	elif not theme.is_empty():
		# Positions are 32-bit floats, so compare against the midpoint between the rows.
		var on_ledge := at.y > (CHOICE_ROW_Y + TOP_ROW_Y) / 2.0 and not is_range()
		var feet_y := (LEDGE_TOP if on_ledge else GROUND_Y) - at.y
		target.apply_style(theme.get("target_style", "board"), theme.get("enemy_look", {}), Color.html(theme.get("placard", "#f2e6c4")), feet_y)
		if target.uses_screen_label():
			answer_labels.track(target, placement)
		if gallery and placement.begins_with("on:"):
			gallery.add(target, int(placement.trim_prefix("on:")))

	targets.append(target)
	return target


# Where `count` answers stand: [{"at": Vector3, "placement": "above"/"below"}], left to right per
# row. Up to four answers share the ground row with their labels above the heads. Five or six use
# the ground row (three, labels hanging below the feet) and the rampart behind it (the rest,
# labels above the heads, standing in the gaps of the front row), so the two rows' labels never
# meet and no soldier hides another.
# `labels_below` hangs a single row's labels under the feet (image tasks keep the space above free
# for the photo).
func answer_layout(count: int, labels_below: bool = false) -> Array:
	if is_range():
		# Gallery: answers take turns on the three tracks, spread evenly along each loop.
		var per_track := [0, 0, 0]
		for i in range(count):
			per_track[i % 3] += 1
		var spots := []
		var next := [0, 0, 0]
		for i in range(count):
			var track: int = i % 3
			spots.append(_track_spot(track, GalleryScript.spread(per_track[track], track * 3.3)[next[track]]))
			next[track] += 1
		return spots
	if count <= MAX_FRONT_ROW:
		return _row(count, FRONT_SPACING, CHOICE_ROW_Y, TARGET_Z, "below" if labels_below else "above")
	var front := ceili(count / 2.0)
	return _row(front, WIDE_FRONT_SPACING, CHOICE_ROW_Y, TARGET_Z, "below") \
		+ _row(count - front, BACK_SPACING, TOP_ROW_Y, TOP_ROW_Z, "above")


# The two rows of a matching task: left items on the rampart (labels above), right items on the
# ground (labels below).
func matching_layout(count: int) -> Dictionary:
	if is_range():
		# Gallery: left items on the top track, their partners on the bottom track.
		return {"top": GalleryScript.spread(count).map(func(x): return _track_spot(0, x)),
			"bottom": GalleryScript.spread(count, 2.5).map(func(x): return _track_spot(2, x))}
	return {"top": _row(count, BACK_SPACING if count < 4 else FRONT_SPACING + 0.4, TOP_ROW_Y, TOP_ROW_Z, "above"),
		"bottom": _row(count, FRONT_SPACING, CHOICE_ROW_Y, TARGET_Z, "below")}


func _track_spot(track: int, x: float) -> Dictionary:
	var lane: Dictionary = GalleryScript.TRACKS[track]
	return {"at": Vector3(x, lane["y"], lane["z"]), "placement": "on:%d" % track}


func _row(count: int, spacing: float, y: float, z: float, placement: String) -> Array:
	var spots := []
	for i in range(count):
		spots.append({"at": Vector3((i - (count - 1) / 2.0) * spacing, y, z), "placement": placement})
	return spots


# Evenly spaced positions for a row of targets centred in front of the player.
func row_positions(count: int, y: float) -> Array:
	var positions := []
	var spacing := RANGE_SPACING if is_range() else ROW_SPACING
	var z := TOP_ROW_Z if y == TOP_ROW_Y else TARGET_Z
	if is_range() and y == TOP_ROW_Y:
		y = RANGE_BACK_ROW.x
		z = RANGE_BACK_ROW.y
	for i in range(count):
		positions.append(Vector3((i - (count - 1) / 2.0) * spacing, y, z))
	return positions


# The answer target whose label is under `point` (the crosshair), if any.
func label_target_at(point: Vector2):
	return answer_labels.target_at(point) if accepting_answers else null


# A level may name its own music (levels.json "music", a res:// audio file); it loops while the
# level is played. Nothing plays when the field is empty or the file is not there yet.
func _start_music() -> void:
	var path: String = level.get("music", "")
	if path.is_empty() or not ResourceLoader.exists(path):
		return
	music = AudioStreamPlayer.new()
	music.stream = load(path)
	music.bus = "Master"
	music.finished.connect(music.play)
	add_child(music)
	music.play()


# The peaceful shooting range uses round targets in one wide row instead of soldiers on two rows.
func is_range() -> bool:
	return theme.get("target_style", "") == "gallery"


func show_image(path: String) -> void:
	image_panel.show_image(path)


func show_map() -> void:
	map_overlay.open()


# True while the map overlay is open: the mouse aims on the map and shots hit its markers.
func map_aiming() -> bool:
	return map_overlay != null and map_overlay.visible


# A shot fired while the map is open: hits the marker under the reticle, if any.
func shoot_map() -> void:
	var target = map_overlay.target_under_reticle()
	if target:
		target.hit()


func clear_arena() -> void:
	for target in targets:
		target.queue_free()
	targets.clear()
	answer_labels.clear()
	current_task = null
	hint_label.text = ""
	hint_label.hide()
	progress_label.text = ""
	progress_label.hide()
	time_limit = 0.0
	timer_label.text = ""
	image_panel.hide()
	map_overlay.close()
	if gallery:
		gallery.clear()


# The photo panel and the map overlay sit in the HUD above the answer labels and below the
# defeat, results and pause screens.
func _build_overlays() -> void:
	var hud := answer_labels.get_parent()
	image_panel = ImagePanelScript.new()
	map_overlay = MapOverlayScript.new()
	for overlay in [image_panel, map_overlay]:
		hud.add_child(overlay)
		hud.move_child(overlay, answer_labels.get_index() + 1)
	source_label = Label.new()
	source_label.name = "SourceLabel"
	source_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	source_label.add_theme_font_size_override("font_size", 17)
	source_label.add_theme_color_override("font_color", SOURCE_COLOR)
	source_label.hide()
	question_label.get_parent().add_child(source_label)
	question_label.get_parent().move_child(source_label, 0)


func _on_restart_button_pressed() -> void:
	get_tree().reload_current_scene()


func _on_next_button_pressed() -> void:
	GameState.selected_level += 1
	get_tree().change_scene_to_file("res://character_select.tscn")


func _on_levels_button_pressed() -> void:
	get_tree().change_scene_to_file("res://level_select.tscn")



# The BOSS asks its phases one after another (levels.json "phases": tasks 1–15 from levels 1–3,
# 16–35 from levels 4–7, 36–50 from levels 8–10), each a new random mix of the audited banks with
# no task twice. Too few tasks for a phase is an error in the banks, reported here, never padded.
func load_boss_questions() -> void:
	var run := QuestionPools.boss_run(level.get("phases", []), QuestionPools.load_banks(LevelDatabase.levels), GameState.shuffle_questions)
	for problem in run["problems"]:
		push_error(problem)
	questions = run["questions"].map(func(q): return Locale.localize_question(q))
	medkits = level.get("medkits", 0)


# All-in-One asks every task of the ten audited banks exactly once, in a new random order on
# every attempt. The total follows the banks (never a fixed number).
func load_all_in_one_questions() -> void:
	questions = QuestionPools.all_in_one(QuestionPools.load_banks(LevelDatabase.levels), GameState.shuffle_questions).map(func(q): return Locale.localize_question(q))
	medkits = level.get("medkits", 0)


func load_questions_from_file() -> void:
	if is_boss():
		load_boss_questions()
		return
	if is_all_in_one():
		load_all_in_one_questions()
		return
	var result := QuestionValidator.load_file(question_file)

	for error in result.errors:
		push_warning(error)

	# Tasks in the chosen language (Locale swaps in each task's English text by position).
	questions = result.questions.map(func(q): return Locale.localize_question(q))
	# A new order on every attempt (Retry reloads the scene), so a level cannot be memorised by
	# its sequence. Every task is still asked exactly once.
	if GameState.shuffle_questions:
		questions.shuffle()
	print("Loaded ", questions.size(), " questions from ", question_file)
