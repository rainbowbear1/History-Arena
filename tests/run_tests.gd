extends SceneTree

# Headless test runner. From the project folder:
#   godot --headless --path . --import
#   godot --headless --path . --script res://tests/run_tests.gd
# Exit code is the number of failed checks (0 = all passed).

const QuestionValidator := preload("res://question_validator.gd")
const LevelDatabaseScript := preload("res://level_database.gd")
const Target := preload("res://answer_target.gd")
const CharacterDatabaseScript := preload("res://character_database.gd")
const Abilities := preload("res://abilities.gd")
const ProgressStoreScript := preload("res://progress_store.gd")

var failures := 0
var checks := 0

# Autoloads are not compile-time globals in a --script run, so fetch them from the tree.
var level_db: Node
var game_state: Node
var char_db: Node
var progress: Node


func _initialize() -> void:
	run.call_deferred()


func check(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		print("  PASS ", label)
	else:
		failures += 1
		print("  FAIL ", label)


func wait(seconds: float) -> void:
	await create_timer(seconds).timeout


func run() -> void:
	level_db = root.get_node("LevelDatabase")
	game_state = root.get_node("GameState")
	char_db = root.get_node("CharacterDatabase")
	# Use a separate save file so tests never touch real progress; demo mode opens levels 1-3.
	progress = root.get_node("ProgressStore")
	progress.path = "user://test_progress.json"
	progress.reset()
	progress.set_demo_unlock(true)

	print("== Level data")
	test_level_data()
	print("== Question format")
	test_question_types()
	test_question_files()
	print("== Level select")
	await test_level_select()
	print("== Arena gameplay")
	await test_arena()

	print("\n%d checks, %d failed" % [checks, failures])
	quit(failures)


func test_level_data() -> void:
	var levels: Array = level_db.levels
	check(levels.size() == 10, "10 levels loaded (got %d)" % levels.size())

	for i in range(levels.size()):
		check(levels[i]["id"] == i + 1, "level %d has id %d" % [i + 1, i + 1])

	check(level_db.get_level(10).get("boss") == true, "level 10 is the boss level")
	check(level_db.get_level(0).is_empty() and level_db.get_level(11).is_empty(), "out-of-range ids return {}")

	for id in range(1, 11):
		check(level_db.is_playable(id), "level %d is playable (question file exists)" % id)
		var protagonist: String = level_db.get_level(id).get("protagonist", "")
		check(protagonist.is_empty() or char_db.get_character(protagonist)["id"] == protagonist,
			"level %d protagonist \"%s\" is a real character" % [id, protagonist])

	var good := {"id": 1, "title": "T", "stars": 1, "question_file": "res://q.json", "time_per_question": 30,
		"target_speed": 1.0, "extra_decoys": 0, "enemies": 0, "revive_hp": 50, "revivals": 2, "pass_percent": 60}
	check(LevelDatabaseScript.validate_level(good) == "", "valid level accepted")
	for broken in [
		["stars", 6], ["stars", 0], ["revive_hp", 0], ["revive_hp", 101], ["pass_percent", 120], ["target_speed", 0],
		["enemies", -1], ["id", 1.5], ["question_file", "questions/x.json"], ["title", " "], ["boss", "yes"],
	]:
		var level := good.duplicate()
		level[broken[0]] = broken[1]
		check(LevelDatabaseScript.validate_level(level) != "", "level with %s = %s rejected" % [broken[0], str(broken[1])])
	var missing := good.duplicate()
	missing.erase("time_per_question")
	check(LevelDatabaseScript.validate_level(missing) != "", "level missing time_per_question rejected")


func test_question_types() -> void:
	var result := QuestionValidator.load_file("res://tests/fixtures/all_types.json")
	check(result.errors.is_empty(), "sample file has no errors %s" % str(result.errors))
	check(result.questions.size() == 6, "all 6 sample types load")
	var types := []
	for question in result.questions:
		types.append(QuestionValidator.get_type(question))
	types.sort()
	var expected := QuestionValidator.TYPES.duplicate()
	expected.sort()
	check(types == expected, "samples cover every type")

	check(QuestionValidator.get_type({"question": "Q"}) == "single_choice", "missing type defaults to single_choice")

	var single := {"question": "Q", "answers": ["a", "b", "c", "d"], "correct": "a"}
	var cases := [
		["non-object rejected", "x"],
		["unknown type rejected", _with(single, "type", "essay")],
		["empty question rejected", _with(single, "question", "  ")],
		["empty id rejected", _with(single, "id", "")],
		["3 answers rejected", _with(single, "answers", ["a", "b", "c"])],
		["5 answers rejected", _with(single, "answers", ["a", "b", "c", "d", "e"])],
		["non-string answer rejected", _with(single, "answers", ["a", "b", "c", 4])],
		["duplicate answers rejected", _with(single, "answers", ["a", "a", "c", "d"])],
		["correct not in answers rejected", _with(single, "correct", "z")],
		["missing correct rejected", _without(single, "correct")],
		["fill_blank without ___ rejected", _with(single, "type", "fill_blank")],
		["image without path rejected", _with(single, "type", "image")],
		["image with missing file rejected", _with(_with(single, "type", "image"), "image", "res://nope.png")],
		["matching with 1 pair rejected", {"type": "matching", "question": "Q", "pairs": [{"left": "a", "right": "b"}]}],
		["matching with 5 pairs rejected", {"type": "matching", "question": "Q", "pairs": _pairs(5)}],
		["matching with repeated right side rejected", {"type": "matching", "question": "Q",
			"pairs": [{"left": "a", "right": "x"}, {"left": "b", "right": "x"}]}],
		["matching pair without right rejected", {"type": "matching", "question": "Q",
			"pairs": [{"left": "a"}, {"left": "b", "right": "y"}]}],
		["chronology with 2 items rejected", {"type": "chronology", "question": "Q", "items": ["a", "b"]}],
		["chronology with 6 items rejected", {"type": "chronology", "question": "Q", "items": ["a", "b", "c", "d", "e", "f"]}],
		["chronology with repeated item rejected", {"type": "chronology", "question": "Q", "items": ["a", "b", "a"]}],
		["map with coordinate above 1 rejected", _map_with(0, "x", 1.5)],
		["map with missing coordinate rejected", _map_with(0, "y", null)],
		["map with wrong correct rejected", _with(_map_with(0, "x", 0.1), "correct", "Нет")],
		["map with overlapping pins rejected", _map_with(1, "x", 0.15)],
	]
	for case in cases:
		check(QuestionValidator.validate(case[1]) != "", case[0])

	check(QuestionValidator.validate(_pairs_question(4)) == "", "matching with 4 pairs accepted")
	check(QuestionValidator.validate({"type": "chronology", "question": "Q", "items": ["a", "b", "c"]}) == "", "chronology with 3 items accepted")
	check(QuestionValidator.validate(_with(_map_with(0, "x", 0.1), "correct", "B")) == "", "spread-out map accepted")

	# File-level problems
	var dir := "user://test_fixtures"
	DirAccess.make_dir_recursive_absolute(dir)
	_write(dir + "/dup.json", JSON.stringify([_with(single, "id", "q1"), _with(single, "id", "q1")]))
	result = QuestionValidator.load_file(dir + "/dup.json")
	check(result.questions.size() == 1 and result.errors.size() == 1, "duplicate id skipped")
	_write(dir + "/broken.json", "[{\"question\": ")
	result = QuestionValidator.load_file(dir + "/broken.json")
	check(result.questions.is_empty() and result.errors.size() == 1, "broken JSON reported")
	_write(dir + "/object.json", "{\"question\": \"Q\"}")
	result = QuestionValidator.load_file(dir + "/object.json")
	check(result.questions.is_empty() and result.errors.size() == 1, "non-array file reported")
	result = QuestionValidator.load_file("res://questions/does_not_exist.json")
	check(result.errors.size() == 1, "missing file reported")


func test_question_files() -> void:
	var type_counts := {}
	var ids := {}
	for level in level_db.levels:
		var result := QuestionValidator.load_file(level["question_file"])
		check(result.errors.is_empty(), "%s has no errors %s" % [level["question_file"], str(result.errors)])
		check(result.questions.size() >= 12, "%s has at least 12 tasks (got %d)" % [level["question_file"], result.questions.size()])
		var level_types := {}
		for question in result.questions:
			var type := QuestionValidator.get_type(question)
			level_types[type] = true
			type_counts[type] = type_counts.get(type, 0) + 1
			check(not ids.has(question.get("id")), "task id %s is unique across levels" % question.get("id"))
			ids[question.get("id")] = true
			if type == "image":
				check(load(question["image"]) is Texture2D, "%s image loads" % question["id"])
			if type == "map":
				for location in question["locations"]:
					# Same projection as tools/build_map.py: the cos(48°) factor cancels out for x.
					var x: float = (location["lon"] - 40.75) / (93.05 - 40.75)
					var y: float = (56.5 - location["lat"]) / (56.5 - 39.0)
					check(absf(x - location["x"]) < 0.002 and absf(y - location["y"]) < 0.002,
						"%s: %s pin matches its latitude/longitude" % [question["id"], location["name"]])
		for type in ["single_choice", "fill_blank", "matching", "chronology"]:
			check(level_types.has(type), "level %d has a %s task" % [level["id"], type])
	for type in QuestionValidator.TYPES:
		check(type_counts.get(type, 0) >= (5 if type in ["map", "image"] else 10), "%s tasks across the game: %d" % [type, type_counts.get(type, 0)])
	check(ResourceLoader.exists("res://assets/maps/kazakhstan.svg") and load("res://assets/maps/kazakhstan.svg") is Texture2D, "Kazakhstan map loads")


func test_level_select() -> void:
	var scene: Node = load("res://level_select.tscn").instantiate()
	root.add_child(scene)
	current_scene = scene
	await process_frame
	var grid: GridContainer = scene.get_node("CenterContainer/VBoxContainer/LevelGrid")
	check(grid.get_child_count() == 10, "10 level buttons built from data")
	var enabled := 0
	for button in grid.get_children():
		if not button.disabled:
			enabled += 1
	check(enabled == 10, "demo mode: all 10 level buttons enabled (got %d)" % enabled)
	var info: Label = scene.get_node("CenterContainer/VBoxContainer/LevelInfoLabel")
	check(info.text.begins_with("1. Сақтар дәуірі"), "info label shows level 1")
	scene._show_level_info(10)
	check(info.text.contains("BOSS") and not info.text.contains("дайындалуда"), "level 10 shows BOSS and is ready")
	scene.queue_free()
	await process_frame


func test_arena() -> void:
	for level in [1, 2, 3]:
		game_state.selected_level = level
		var arena := await _load_arena()
		var quiz = arena.get_node("QuizManager")
		check(quiz.question_file == level_db.get_level(level)["question_file"], "level %d uses its question file" % level)
		check(quiz.questions.size() == QuestionValidator.load_file(quiz.question_file).questions.size(), "level %d loads all its tasks" % level)
		var types := {}
		for question in quiz.questions:
			types[QuestionValidator.get_type(question)] = true
		check(types.has("fill_blank") and types.has("matching") and types.has("chronology"),
			"level %d mixes in fill_blank, matching and chronology" % level)
		arena.queue_free()
		await process_frame

	game_state.selected_level = 1
	var arena := await _load_arena()
	var quiz = arena.get_node("QuizManager")

	check(quiz.targets.size() == 4, "first question spawns 4 targets")
	var xs: Array = quiz.targets.map(func(t): return t.starting_position.x)
	xs.sort()
	check(xs == [-4.5, -1.5, 1.5, 4.5], "targets keep the original row positions")
	var correct_targets: Array = quiz.targets.filter(func(t): return t.is_correct)
	check(correct_targets.size() == 1, "exactly one correct target")

	correct_targets[0].hit()
	check(quiz.score == 100, "correct hit scores 100 once (score=%d)" % quiz.score)
	correct_targets[0].hit()
	check(quiz.score == 100, "second hit during feedback ignored")
	await wait(1.3)
	check(quiz.question_index == 1, "advanced to next question")
	check(quiz.targets.size() == 4 and is_instance_valid(quiz.targets[0]), "fresh targets for the next question")


	var ray: RayCast3D = arena.get_node("Player/Camera3D/ShootRay")
	check(ray.target_position == Vector3(0, 0, -100), "ray points along camera -Z")

	var event := InputEventKey.new()
	event.physical_keycode = KEY_W
	event.keycode = 0x0426  # Cyrillic capital TSE, what W types on a Russian/Kazakh layout
	event.pressed = true
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	check(Input.is_action_pressed("move_forward"), "physical W triggers move_forward on a Cyrillic layout")
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)
	Input.flush_buffered_events()

	arena.queue_free()
	await process_frame

	print("== Task types")
	var samples := {}
	for question in QuestionValidator.load_file("res://tests/fixtures/all_types.json").questions:
		samples[QuestionValidator.get_type(question)] = question
	await test_choice_types(samples)
	await test_chronology(samples["chronology"])
	await test_matching(samples["matching"])
	await test_map(samples["map"])
	await test_hp_and_medical_help()
	await test_characters()
	await test_difficulty()
	await test_progress()
	await test_full_playthrough()
	progress.path = ProgressStoreScript.SAVE_PATH
	progress.load_data()


func test_choice_types(samples: Dictionary) -> void:
	for type in ["fill_blank", "image"]:
		var quiz = await _start_task(samples[type])
		check(quiz.targets.size() == 4, "%s spawns 4 targets" % type)
		check(quiz.progress_label.text.is_empty(), "%s shows no progress counter" % type)
		check(not quiz.hint_label.text.is_empty(), "%s shows a hint" % type)
		check(quiz.image_board.visible == (type == "image"), "%s image board visibility" % type)
		if type == "image":
			check(quiz.image_board.texture != null, "image task loads its picture")
		var wrong = quiz.targets.filter(func(t): return not t.is_correct)[0]
		wrong.hit()
		check(quiz.health == 90 and quiz.score == 0, "%s wrong answer costs 10 HP" % type)
		var correct = quiz.targets.filter(func(t): return t.is_correct)[0]
		check(correct.state == Target.State.DONE, "%s reveals the correct answer after a miss" % type)
		await wait(1.8)
		check(quiz.results_container.visible, "%s ends after one answer" % type)
		quiz.get_parent().queue_free()
		await process_frame


func test_chronology(question: Dictionary) -> void:
	var quiz = await _start_task(question)
	var items: Array = question["items"]
	check(quiz.targets.size() == items.size(), "chronology spawns one target per item")
	check(quiz.progress_label.text == "Ретімен қойылды: 0/%d" % items.size(), "chronology shows 0/%d progress" % items.size())

	_by_text(quiz, items[0]).hit()
	check(quiz.score == 0 and quiz.health == 100 and quiz.accepting_answers, "first correct item is progress only")
	check(_by_text(quiz, items[0]).answer_label.text == "1. " + items[0], "placed item shows its order number")
	check(quiz.progress_label.text == "Ретімен қойылды: 1/%d" % items.size(), "progress counts the placed item")
	_by_text(quiz, items[0]).hit()
	check(quiz.health == 100, "re-shooting a placed item does nothing")

	_by_text(quiz, items[2]).hit()
	check(quiz.health == 90, "out-of-order item costs 10 HP")
	check(quiz.current_task.next_index == 0, "mistake restarts the sequence")
	check(quiz.progress_label.text == "Ретімен қойылды: 0/%d" % items.size(), "mistake resets the progress counter")
	check(_by_text(quiz, items[0]).state == Target.State.NORMAL, "mistake unlocks placed items")
	check(quiz.accepting_answers, "chronology continues after a mistake")

	for item in items:
		_by_text(quiz, item).hit()
	check(quiz.score == 100, "completing the order scores 100")
	await wait(1.8)
	check(quiz.results_container.visible, "chronology moves on when solved")
	quiz.get_parent().queue_free()
	await process_frame


func test_matching(question: Dictionary) -> void:
	var quiz = await _start_task(question)
	var pairs: Array = question["pairs"]
	check(quiz.targets.size() == pairs.size() * 2, "matching spawns two targets per pair")
	check(quiz.progress_label.text == "Табылған жұптар: 0/%d" % pairs.size(), "matching shows 0/%d progress" % pairs.size())
	for pair in pairs:
		check(_by_text(quiz, pair["left"]).starting_position.y == quiz.TOP_ROW_Y, "left item \"%s\" on the top row" % pair["left"])

	_by_text(quiz, pairs[0]["right"]).hit()
	check(quiz.health == 100 and quiz.feedback_label.text.begins_with("Алдымен"), "bottom first shows a hint, no penalty")

	_by_text(quiz, pairs[0]["left"]).hit()
	check(_by_text(quiz, pairs[0]["left"]).state == Target.State.SELECTED, "top item becomes selected")
	_by_text(quiz, pairs[1]["left"]).hit()
	check(_by_text(quiz, pairs[0]["left"]).state == Target.State.NORMAL
		and _by_text(quiz, pairs[1]["left"]).state == Target.State.SELECTED, "selecting another top item switches selection")

	_by_text(quiz, pairs[0]["right"]).hit()
	check(quiz.health == 90, "wrong partner costs 10 HP")
	check(quiz.current_task.selected == null, "wrong partner clears the selection")
	check(quiz.feedback_label.text == "Қате жұп!", "wrong partner says so")

	_by_text(quiz, pairs[0]["left"]).hit()
	_by_text(quiz, pairs[0]["right"]).hit()
	check(quiz.progress_label.text == "Табылған жұптар: 1/%d" % pairs.size(), "progress counts the first pair")
	check(quiz.feedback_label.text == "Дұрыс! 1/%d" % pairs.size(), "feedback shows pairs found so far")

	for i in range(pairs.size()):
		_by_text(quiz, pairs[i]["left"]).hit()
		_by_text(quiz, pairs[i]["right"]).hit()
	check(_by_text(quiz, pairs[0]["right"]).state == Target.State.DONE, "matched pair locks")
	check(quiz.score == 100, "all pairs matched scores 100")
	await wait(1.8)
	check(quiz.results_container.visible, "matching moves on when solved")
	quiz.get_parent().queue_free()
	await process_frame


func test_map(question: Dictionary) -> void:
	var quiz = await _start_task(question)
	check(quiz.map_board.visible, "map board shown")
	check(quiz.targets.size() == 4, "map spawns 4 pins")
	var labels: Array = quiz.targets.map(func(t): return t.answer_label.text)
	labels.sort()
	check(labels == ["1", "2", "3", "4"], "pins are labelled 1-4, not with the answer")
	check(quiz.targets.all(func(t): return t.move_distance == 0.0), "pins do not sway")
	var location: Dictionary = question["locations"].filter(func(l): return l["name"] == question["correct"])[0]
	var pin = quiz.targets.filter(func(t): return t.is_correct)[0]
	check(pin.position.is_equal_approx(quiz.map_point(location["x"], location["y"])), "correct pin sits at its map coordinate")
	# Fire the player's real raycast at the small pin rather than calling hit() directly.
	await physics_frame
	var camera: Camera3D = quiz.get_parent().get_node("Player/Camera3D")
	camera.look_at(pin.global_position)
	quiz.get_parent().get_node("Player").shoot()
	check(quiz.score == 100, "shooting the correct pin through the crosshair scores 100")
	await wait(1.8)
	check(not quiz.map_board.visible, "map board hidden after the task")
	quiz.get_parent().queue_free()
	await process_frame


func test_hp_and_medical_help() -> void:
	print("== HP and medical help")
	print("   (levels 5 and 9 have no question files yet: their 'No questions loaded' errors are expected)")
	for level in [1, 5, 9]:
		var data: Dictionary = level_db.get_level(level)
		game_state.selected_level = level
		var probe := await _load_arena()
		var probe_quiz = probe.get_node("QuizManager")
		check(probe_quiz.revive_hp == data["revive_hp"] and probe_quiz.revivals_left == data["revivals"],
			"level %d: medical help restores %d HP, %d times (from level data)" % [level, data["revive_hp"], data["revivals"]])
		probe.queue_free()
		await process_frame
	check([1, 2, 3, 4].all(func(l): return level_db.get_level(l)["revive_hp"] == 50), "levels 1-4 restore 50 HP")
	check([5, 6, 7, 8].all(func(l): return level_db.get_level(l)["revive_hp"] == 40), "levels 5-8 restore 40 HP")
	check([9, 10].all(func(l): return level_db.get_level(l)["revive_hp"] == 30), "levels 9-10 restore 30 HP")

	# One HP pool: ten mistakes from 100 HP reach defeat.
	game_state.selected_level = 1
	var arena := await _load_arena()
	var quiz = arena.get_node("QuizManager")
	check(quiz.health == 100 and quiz.health_label.text == "HP: 100/100", "run starts with 100 HP")
	check(not arena.has_node("HUD/LivesLabel"), "no lives counter in the HUD")
	_wrong_target(quiz).hit()
	check(quiz.health == 90, "a wrong answer costs 10 HP")
	await wait(1.8)
	check(quiz.question_index == 1 and not quiz.revival_panel.visible, "play continues above 0 HP")

	# Reaching 0 HP opens the defeat screen with a medical-help question.
	quiz.score = 300
	quiz.health = 10
	var earlier_miss: Dictionary = quiz.questions[0]
	quiz.missed_questions = [earlier_miss]
	var retry_index: int = quiz.question_index
	var retry_question: Dictionary = quiz.questions[retry_index]
	_wrong_target(quiz).hit()
	check(quiz.health == 0, "HP reaches 0")
	check(not quiz.revival_panel.visible, "defeat waits for the feedback")
	await wait(1.8)
	var panel = quiz.revival_panel
	check(panel.visible, "defeat screen shown at 0 HP")
	check(quiz.overlay_open(), "defeat screen counts as an open overlay")
	check(not quiz.results_container.visible, "results screen not shown on defeat")
	check(quiz.targets.is_empty(), "arena cleared on defeat")
	check(Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, "mouse released on defeat")
	check(panel.question != retry_question, "medical help never asks the task being retried")
	check(panel.question == earlier_miss, "medical help prefers a question missed earlier")
	check(panel.question_label.visible and panel.question_label.text == earlier_miss["question"], "help question shown")
	var shown: Array = panel.answer_buttons.map(func(b): return b.text)
	shown.sort()
	var expected: Array = earlier_miss["answers"].duplicate()
	expected.sort()
	check(shown == expected, "help answers shown on four buttons")
	check(quiz.revivals_left == 1, "offering help uses one medical-help attempt")

	_press_correct(panel)
	check(panel.result_label.text.begins_with("Дұрыс! +50 HP"), "correct help answer announces +50 HP")
	check(panel.answer_buttons.all(func(b): return b.disabled), "answers locked after choosing")
	await wait(1.7)
	check(not panel.visible, "defeat screen closes after a correct answer")
	check(quiz.health == 50 and quiz.health_label.text == "HP: 50/100", "medical help restores the level's 50 HP")
	check(quiz.score == 300, "score kept after medical help (score=%d)" % quiz.score)
	check(quiz.question_index == retry_index, "the failed task is retried, not skipped")
	check(quiz.question_label.text == retry_question["question"], "retried task is shown again")
	check(quiz.accepting_answers and quiz.targets.size() == 4, "arena is live again with fresh targets")
	_correct_target(quiz).hit()
	check(quiz.score == 400, "solving the retried task scores normally")
	await wait(1.8)
	check(quiz.question_index == retry_index + 1, "after the retry the run moves on")

	# Second defeat: a wrong medical-help answer gives no help.
	quiz.health = 10
	var second_retry: Dictionary = quiz.questions[quiz.question_index]
	_wrong_target(quiz).hit()
	await wait(1.8)
	check(panel.visible and quiz.revivals_left == 0, "second defeat uses the last medical-help attempt")
	check(panel.question != earlier_miss and panel.question != second_retry, "a fresh help question is asked")
	_press_wrong(panel)
	check(panel.result_label.text == "Медициналық көмек көрсетілмеді.", "wrong help answer: no medical help")
	await wait(1.7)
	check(panel.visible and quiz.health == 0, "no HP restored after a wrong help answer")
	check(panel.restart_button.visible and panel.levels_button.visible, "restart and levels offered")

	# Escape must not open the pause menu over the defeat screen.
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	escape.pressed = true
	arena.get_viewport().push_input(escape)
	check(not arena.get_node("HUD/PauseMenu").visible and not paused, "Esc ignored on the defeat screen")
	arena.queue_free()
	await process_frame

	# No medical help left: defeat screen without a question.
	arena = await _load_arena()
	quiz = arena.get_node("QuizManager")
	quiz.revivals_left = 0
	quiz.health = 10
	_wrong_target(quiz).hit()
	await wait(1.8)
	check(quiz.revival_panel.visible and not quiz.revival_panel.question_label.visible, "no help question when attempts are used up")
	check(quiz.revival_panel.message_label.text.begins_with("Медициналық көмек мүмкіндігі қалмады"), "says medical help is used up")
	arena.queue_free()
	await process_frame

	# Multi-step task: a mistake at 0 HP ends in defeat; after medical help the task restarts from scratch.
	var samples := {}
	for q in QuestionValidator.load_file("res://tests/fixtures/all_types.json").questions:
		samples[QuestionValidator.get_type(q)] = q
	var chronology: Dictionary = samples["chronology"]
	quiz = await _start_task(chronology)
	quiz.questions = [chronology, samples["single_choice"]]
	_by_text(quiz, chronology["items"][0]).hit()
	quiz.health = 20
	_by_text(quiz, chronology["items"][2]).hit()
	check(quiz.health == 10 and quiz.accepting_answers, "chronology mistake above 0 HP: task continues")
	_by_text(quiz, chronology["items"][0]).hit()
	_by_text(quiz, chronology["items"][3]).hit()
	check(quiz.health == 0 and not quiz.accepting_answers, "chronology mistake at 0 HP ends the task")
	await wait(1.8)
	check(quiz.revival_panel.visible and quiz.revival_panel.question == samples["single_choice"], "help question comes from another task")
	_press_correct(quiz.revival_panel)
	await wait(1.7)
	check(quiz.question_index == 0 and quiz.current_task.done == 0, "chronology retried from the start")
	check(quiz.progress_label.text == "Ретімен қойылды: 0/%d" % chronology["items"].size(), "retried chronology progress reset")
	quiz.get_parent().queue_free()
	await process_frame

	# Only the retried task is eligible: no medical-help question.
	quiz = await _start_task(samples["single_choice"])
	quiz.questions = [samples["single_choice"], samples["matching"], samples["chronology"]]
	check(quiz.pick_revival_question().is_empty(), "no help question when only the retried task qualifies")
	quiz.get_parent().queue_free()
	await process_frame


func _wrong_target(quiz):
	return quiz.targets.filter(func(t): return not t.is_correct)[0]


func _correct_target(quiz):
	return quiz.targets.filter(func(t): return t.is_correct)[0]


func _press_correct(panel) -> void:
	for button in panel.answer_buttons:
		if button.text == panel.question["correct"]:
			button.pressed.emit()
			return


func _press_wrong(panel) -> void:
	for button in panel.answer_buttons:
		if button.text != panel.question["correct"]:
			button.pressed.emit()
			return


func test_characters() -> void:
	print("== Characters")
	var characters: Array = char_db.characters
	check(characters.size() == 10, "10 characters loaded (got %d)" % characters.size())
	var ids := {}
	var abilities := {}
	for c in characters:
		ids[c["id"]] = true
		abilities[c["ability"]["id"]] = true
		check(CharacterDatabaseScript.validate_character(c) == "", "%s is valid" % c["name"])
	check(ids.size() == 10, "character ids are unique")
	check(abilities.size() == Abilities.INFO.size(), "every ability is used by some character")
	check(char_db.get_character("nope") == characters[0], "unknown id falls back to the first character")

	var good: Dictionary = characters[0].duplicate(true)
	for broken in [["hp", 40], ["hp", 250], ["hp", 100.5], ["speed", 2], ["defense", 70], ["name", ""]]:
		var c := good.duplicate(true)
		c[broken[0]] = broken[1]
		check(CharacterDatabaseScript.validate_character(c) != "", "character with %s = %s rejected" % [broken[0], str(broken[1])])
	for broken in [["cooldown", 0], ["damage", 0], ["auto", "yes"]]:
		var c := good.duplicate(true)
		c["weapon"][broken[0]] = broken[1]
		check(CharacterDatabaseScript.validate_character(c) != "", "weapon with %s = %s rejected" % [broken[0], str(broken[1])])
	for broken in [["id", "fly"], ["uses", 0]]:
		var c := good.duplicate(true)
		c["ability"][broken[0]] = broken[1]
		check(CharacterDatabaseScript.validate_character(c) != "", "ability with %s = %s rejected" % [broken[0], str(broken[1])])

	# Character select screen
	game_state.selected_character = ""
	var screen: Node = load("res://character_select.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await process_frame
	var grid: GridContainer = screen.get_node("%CharacterGrid")
	check(grid.get_child_count() == 10, "10 character buttons")
	check(screen.selected_id == characters[0]["id"] and grid.get_child(0).button_pressed, "first character preselected")
	grid.get_child(7).pressed.emit()
	check(screen.selected_id == "kabanbay", "pressing a button selects that character")
	check(screen.get_node("%NameLabel").text == "Қабанбай батыр", "details show the selected character")
	check(screen.stat_bars["hp"].value == 130 and screen.stat_values["defense"].text == "30", "stat bars show HP and defense")
	check(screen.get_node("%WeaponLabel").text.contains("Мылтық"), "weapon shown")
	check(screen.get_node("%AbilityLabel").text.contains("Емдеу"), "ability shown")
	screen.get_node("%ChooseButton").pressed.emit()
	check(game_state.selected_character == "kabanbay", "choosing stores the character")
	await process_frame
	await process_frame
	check(current_scene != null and current_scene.name == "Main", "choosing starts the level")
	current_scene.queue_free()
	await process_frame

	# Each level preselects its historical protagonist; levels without one keep the last choice.
	game_state.selected_level = 7
	screen = load("res://character_select.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await process_frame
	check(screen.selected_id == "kabanbay", "level 7 preselects Қабанбай батыр")
	check(screen.level_label.text.contains("Деңгей кейіпкері: Қабанбай батыр"), "screen names the level's protagonist")
	screen.get_node("%CharacterGrid").get_child(9).pressed.emit()
	check(screen.selected_id == "manshuk", "any character can still be chosen")
	screen.queue_free()
	await process_frame
	game_state.selected_level = 5
	game_state.selected_character = "kasym"
	screen = load("res://character_select.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await process_frame
	check(screen.selected_id == "kasym", "level without a protagonist keeps the last choice")
	screen.queue_free()
	await process_frame
	game_state.selected_level = 1
	game_state.selected_character = "kabanbay"

	# Stats in the arena
	game_state.selected_level = 1
	var arena := await _load_arena()
	var quiz = arena.get_node("QuizManager")
	var player = arena.get_node("Player")
	check(quiz.max_health == 130 and quiz.health == 130, "character HP sets the HP pool")
	check(quiz.health_label.text == "HP: 130/130", "HUD shows HP out of the character's maximum")
	check(quiz.character_label.text == "Қабанбай батыр · Мылтық", "HUD shows character and weapon")
	check(quiz.ability_label.text == "[E] Емдеу ×2", "HUD shows the ability and its uses")
	check(player.speed == 5.5, "character speed applied")
	check(player.weapon["damage"] == 3, "character weapon applied")

	player.cooldown_left = 0.0
	player.shoot()
	player.shoot()
	check(player.shots_fired == 1, "weapon cooldown blocks an immediate second shot")
	player.cooldown_left = 0.0
	player.shoot()
	check(player.shots_fired == 2, "weapon fires again once ready")
	arena.queue_free()
	await process_frame

	# Abilities
	var samples := {}
	for q in QuestionValidator.load_file("res://tests/fixtures/all_types.json").questions:
		samples[QuestionValidator.get_type(q)] = q

	game_state.selected_character = "kabanbay"
	quiz = await _start_task(samples["single_choice"])
	quiz.use_ability()
	check(quiz.ability_uses == 2 and quiz.feedback_label.text == "Қазір қолдануға болмайды", "heal at full HP is refused without using it")
	quiz.health = 50
	quiz.use_ability()
	check(quiz.health == 75 and quiz.ability_uses == 1, "heal restores 25 HP and uses one charge")
	quiz.health = 120
	quiz.use_ability()
	check(quiz.health == 130 and quiz.ability_uses == 0, "heal never exceeds maximum HP")
	quiz.health = 50
	quiz.use_ability()
	check(quiz.health == 50, "no charges left: nothing happens")
	quiz.get_parent().queue_free()
	await process_frame

	game_state.selected_character = "al_farabi"
	quiz = await _start_task(samples["single_choice"])
	quiz.use_ability()
	await process_frame
	check(quiz.targets.size() == 2 and quiz.targets.any(func(t): return t.is_correct), "50/50 removes two wrong answers")
	check(quiz.ability_uses == 2, "50/50 uses one charge")
	quiz.use_ability()
	check(quiz.targets.size() == 2 and quiz.ability_uses == 2, "50/50 refused when only one wrong answer is left")
	quiz.get_parent().queue_free()
	await process_frame
	quiz = await _start_task(samples["map"])
	quiz.use_ability()
	await process_frame
	check(quiz.targets.size() == 2, "50/50 works on map pins")
	quiz.get_parent().queue_free()
	await process_frame
	quiz = await _start_task(samples["matching"])
	quiz.use_ability()
	check(quiz.ability_uses == 3 and quiz.targets.size() == 6, "50/50 refused on matching tasks")
	quiz.get_parent().queue_free()
	await process_frame

	game_state.selected_character = "mode"
	quiz = await _start_task(samples["single_choice"])
	quiz.use_ability()
	check(quiz.shield_active and quiz.ability_label.text.contains("Қалқан белсенді"), "shield activates and shows in the HUD")
	quiz.use_ability()
	check(quiz.ability_uses == 1, "shield cannot stack")
	_wrong_target(quiz).hit()
	check(quiz.health == quiz.max_health and not quiz.shield_active, "shield absorbs the next mistake")
	check(quiz.feedback_label.text == "Қате! Қалқан қорғады", "shield block announced")
	quiz.get_parent().queue_free()
	await process_frame

	game_state.selected_character = "kultegin"
	quiz = await _start_task(samples["single_choice"])
	quiz.use_ability()
	_correct_target(quiz).hit()
	check(quiz.score == 200 and quiz.feedback_label.text == "Дұрыс! ×2", "double score doubles the next solved task")
	check(not quiz.double_score_active, "double score is spent")
	quiz.get_parent().queue_free()
	await process_frame

	game_state.selected_character = "kasym"
	quiz = await _start_task(samples["single_choice"])
	quiz.time_limit = 0.0
	quiz.use_ability()
	check(quiz.ability_uses == 3, "extra time refused while no timer runs")
	quiz.get_parent().queue_free()
	await process_frame

	game_state.selected_character = "tomyris"
	quiz = await _start_task(samples["single_choice"])
	var e_key := InputEventKey.new()
	e_key.physical_keycode = KEY_E
	e_key.pressed = true
	quiz.get_viewport().push_input(e_key)
	check(quiz.slow_active and quiz.ability_uses == 1, "E key uses the ability")
	check(quiz.targets.all(func(t): return t.speed_scale == Abilities.SLOW_FACTOR), "slow time slows the targets")
	_correct_target(quiz).hit()
	await wait(1.8)
	check(quiz.results_container.visible, "task finishes while slowed")
	quiz.question_index = 0
	quiz.results_container.hide()
	quiz.load_question()
	check(quiz.targets.all(func(t): return t.speed_scale == Abilities.SLOW_FACTOR), "targets spawned during slow time are slow too")
	await wait(Abilities.SLOW_SECONDS)
	check(not quiz.slow_active and quiz.targets.all(func(t): return t.speed_scale == 1.0), "slow time wears off")
	quiz.accepting_answers = false
	quiz.use_ability()
	check(quiz.ability_uses == 1, "ability ignored between tasks")
	quiz.get_parent().queue_free()
	await process_frame
	game_state.selected_character = ""


func test_difficulty() -> void:
	print("== Difficulty: timer, speed, decoys")
	var samples := {}
	for q in QuestionValidator.load_file("res://tests/fixtures/all_types.json").questions:
		samples[QuestionValidator.get_type(q)] = q
	game_state.selected_character = ""

	# Timer
	var quiz = await _start_task(samples["single_choice"])
	check(quiz.time_limit == 30.0 and quiz.timer_label.text == "Уақыт: 30", "level 1 gives 30 s per task")
	await wait(1.1)
	check(quiz.time_left < 29.5 and quiz.time_left > 27.0, "timer counts down (%.1f s left)" % quiz.time_left)
	paused = true
	var frozen: float = quiz.time_left
	await create_timer(0.5, true).timeout
	check(quiz.time_left == frozen, "timer stops while the game is paused")
	paused = false
	quiz.time_left = 4.0
	await wait(0.1)
	check(quiz.timer_label.get_theme_color("font_color") == Color.RED, "timer turns red in the last 5 s")
	quiz.time_left = 0.1
	await wait(0.3)
	check(quiz.health == 90 and quiz.feedback_label.text == "Уақыт бітті!", "running out of time costs 10 HP")
	check(quiz.targets.filter(func(t): return t.is_correct)[0].state == Target.State.DONE, "time-out reveals the correct answer")
	check(quiz.missed_questions.has(samples["single_choice"]), "time-out counts as a missed question")
	var after_timeout: float = quiz.time_left
	await wait(0.5)
	check(quiz.time_left == after_timeout and not quiz.timer_running(), "timer stops during feedback")
	quiz.get_parent().queue_free()
	await process_frame

	quiz = await _start_task(samples["chronology"])
	check(quiz.time_limit == 60.0, "multi-step tasks get double time")
	quiz.get_parent().queue_free()
	await process_frame

	game_state.selected_character = "kasym"
	quiz = await _start_task(samples["single_choice"])
	var before: float = quiz.time_left
	quiz.use_ability()
	check(quiz.time_left > before + 9.0 and quiz.ability_uses == 2, "extra time adds 10 s")
	quiz.get_parent().queue_free()
	await process_frame

	# Fewer ability uses on harder levels (level 5 has no questions yet; its error is expected).
	game_state.selected_character = "al_farabi"
	for case in [[1, 3], [3, 3], [5, 2]]:
		game_state.selected_level = case[0]
		var probe := await _load_arena()
		check(probe.get_node("QuizManager").ability_uses == case[1], "level %d: 50/50 has %d uses" % case)
		probe.queue_free()
		await process_frame
	game_state.selected_character = ""

	# Level 3: faster targets, one decoy, one enemy.
	game_state.selected_level = 3
	var arena := await _load_arena()
	quiz = arena.get_node("QuizManager")
	check(quiz.targets.all(func(t): return t.move_speed >= 1.25 * 0.8 - 0.001 and t.move_speed <= 1.25 * 1.2 + 0.001), "targets sway 1.25x faster on level 3")
	var question: Dictionary = quiz.questions[0]
	check(quiz.targets.size() == 5, "level 3 adds one decoy target (got %d)" % quiz.targets.size())
	var decoys: Array = quiz.targets.filter(func(t): return not question["answers"].has(t.answer_text))
	check(decoys.size() == 1 and not decoys[0].is_correct, "decoy is a wrong answer from another question")
	check(decoys[0].starting_position.y == quiz.TOP_ROW_Y, "decoy sits on the top row")
	check(quiz.targets.filter(func(t): return t.is_correct).size() == 1, "still exactly one correct target")
	var year_question: Dictionary = quiz.questions.filter(func(q): return q.get("correct") == "751")[0]
	var year_decoys: Array = quiz.decoy_answers(year_question, 2)
	check(year_decoys.size() == 2 and year_decoys.all(func(a): return quiz._has_digit(a)), "date questions get date decoys %s" % str(year_decoys))
	check(not year_decoys.any(func(a): return year_question["answers"].has(a)), "decoys never repeat the real options")
	var founding: Dictionary = quiz.questions[0]
	for attempt in range(20):
		var picked: Array = quiz.decoy_answers(founding, 4)
		if picked.any(func(a): return quiz._answer_key(a) in ["552", "603", "704", "751"]):
			check(false, "decoys never restate an option in another form %s" % str(picked))
			break
	check(quiz._answer_key("552 ж.") == quiz._answer_key("552") and quiz._answer_key("Мөде") == quiz._answer_key("мөде"), "answer keys ignore formatting")
	quiz.questions = [samples["image"]]
	quiz.question_index = 0
	quiz.load_question()
	check(quiz.targets.size() == 4, "image tasks get no decoys")
	arena.queue_free()
	await process_frame

	print("== Enemies")
	game_state.selected_level = 3
	arena = await _load_arena()
	quiz = arena.get_node("QuizManager")
	var player = arena.get_node("Player")
	var spawner = quiz.enemy_spawner
	check(spawner.enemies.size() == 1, "level 3 has one enemy")
	var enemy = spawner.enemies[0]
	check(enemy.max_hp == 2 and enemy.damage == 8 and is_equal_approx(enemy.move_speed, 2.6), "enemy stats scale with stars")
	check(absf(absf(enemy.position.x) - 13.0) < 0.5 or absf(enemy.position.z - 13.0) < 0.5, "enemy enters from the side or back")
	await physics_frame
	var start_distance: float = enemy.global_position.distance_to(player.global_position)
	await wait(1.0)
	check(enemy.global_position.distance_to(player.global_position) < start_distance - 1.0, "enemy walks toward the player")

	quiz.accepting_answers = false
	var frozen_at: Vector3 = enemy.global_position
	await wait(0.5)
	check(Vector2(enemy.global_position.x, enemy.global_position.z).distance_to(Vector2(frozen_at.x, frozen_at.z)) < 0.01, "enemies freeze between tasks")
	quiz.accepting_answers = true

	enemy.global_position = player.global_position + Vector3(1.2, 0, 0)
	enemy.attack_cooldown = 0.0
	var hp_before: int = quiz.health
	await wait(0.3)
	check(quiz.health == hp_before - 7, "enemy hit deals 8 minus Томирис' 10%% defense = 7 (HP %d -> %d)" % [hp_before, quiz.health])
	check(quiz.feedback_label.text == "Жау шабуылы! −7 HP", "enemy hit announced")
	await wait(0.6)
	check(quiz.health == hp_before - 7, "attacks have a cooldown")

	enemy.global_position = player.global_position + Vector3(0, 0, 6)
	# physics_frame fires before the physics step, so wait two for the move to reach the physics space.
	await physics_frame
	await physics_frame
	var score_before: int = quiz.score
	player.get_node("Camera3D").look_at(enemy.global_position + Vector3(0, 0.9, 0))
	player.cooldown_left = 0.0
	player.shoot()
	check(enemy.hp == 1, "shooting an enemy deals weapon damage")
	player.cooldown_left = 0.0
	player.shoot()
	await process_frame
	check(spawner.enemies.is_empty(), "enemy dies at 0 HP")
	check(quiz.score == score_before, "killing enemies gives no points (no score farming)")
	await wait(spawner.RESPAWN_DELAY + 0.3)
	check(spawner.enemies.size() == 1, "a new enemy arrives after a delay")

	quiz.set_slow(true)
	check(spawner.enemies[0].speed_scale == Abilities.SLOW_FACTOR, "slow time slows enemies")
	quiz.set_slow(false)

	# Death by enemy: defeat, enemies cleared; after medical help the task is retried and enemies return.
	quiz.health = 5
	var retry_index: int = quiz.question_index
	quiz.enemy_attack(8)
	check(quiz.health == 0 and not quiz.accepting_answers, "enemy can finish the player")
	await wait(1.8)
	check(quiz.revival_panel.visible and spawner.enemies.is_empty(), "defeat screen, enemies removed")
	_press_correct(quiz.revival_panel)
	await wait(1.7)
	check(quiz.question_index == retry_index and spawner.enemies.size() == 1, "after medical help the task is retried and enemies return")
	arena.queue_free()
	await process_frame

	game_state.selected_character = "kabanbay"
	arena = await _load_arena()
	quiz = arena.get_node("QuizManager")
	quiz.enemy_attack(8)
	check(quiz.health == 130 - 6, "Қабанбай's 30% defense: 8 -> 6 damage")
	quiz.enemy_attack(1)
	check(quiz.health == 130 - 7, "defense never blocks the last 1 HP of a hit")
	quiz.accepting_answers = false
	quiz.enemy_attack(8)
	check(quiz.health == 130 - 7, "no enemy damage between tasks")
	quiz.accepting_answers = true

	var wall_hit: Dictionary = arena.get_world_3d().direct_space_state.intersect_ray(
		PhysicsRayQueryParameters3D.create(Vector3(0, 1, 0), Vector3(40, 1, 0)))
	check(not wall_hit.is_empty() and wall_hit["position"].x < 15.5, "arena walls stop players and enemies at the edge")

	# Boss level
	spawner = quiz.enemy_spawner
	spawner.stop()
	spawner.configure(quiz, arena.get_node("Player"), {"enemies": 0, "stars": 5, "boss": true})
	spawner.start()
	check(spawner.enemies.size() == 1 and spawner.enemies[0].get_meta("boss"), "boss level spawns a boss")
	var boss = spawner.enemies[0]
	check(boss.max_hp == spawner.BOSS_HP and boss.damage == spawner.BOSS_DAMAGE and boss.scale.x > 1.5, "boss is bigger and tougher")
	boss.take_hit(spawner.BOSS_HP)
	await wait(spawner.RESPAWN_DELAY + 0.3)
	spawner.start()
	check(spawner.enemies.is_empty() and spawner.boss_defeated, "a defeated boss stays defeated")
	arena.queue_free()
	await process_frame
	game_state.selected_character = ""
	game_state.selected_level = 1


func test_progress() -> void:
	print("== Progress, stars and results")
	var S = ProgressStoreScript
	check(S.stars_for(1300, 1300, 60, 0) == 3, "95%+ without medical help: 3 stars")
	check(S.stars_for(1300, 1300, 60, 1) == 2, "medical help caps a perfect run at 2 stars")
	check(S.stars_for(1100, 1300, 60, 0) == 2, "80%+: 2 stars")
	check(S.stars_for(800, 1300, 60, 0) == 1, "pass mark reached: 1 star")
	check(S.stars_for(700, 1300, 60, 0) == 0, "below the pass mark: 0 stars")
	check(S.stars_for(900, 1300, 75, 0) == 0 and S.stars_for(1000, 1300, 75, 0) == 1, "level pass mark respected")
	check(S.stars_for(2600, 1300, 60, 0) == 3, "double-score bonuses cannot exceed 100%")

	progress.reset()
	check(progress.is_unlocked(1) and not progress.is_unlocked(2), "fresh save: only level 1 open")
	var attempt := {"level": 1, "character": "tomyris", "score": 900, "max_score": 1300, "correct": 9, "wrong": 4,
		"playtime_sec": 200, "stars": 1, "passed": true, "completed": true, "revivals_used": 0, "finished_at": 1}
	check(progress.record_attempt(attempt), "first result is a new best")
	check(progress.is_unlocked(2) and not progress.is_unlocked(3), "passing level 1 opens level 2 only")
	var worse := attempt.duplicate()
	worse["score"] = 500
	worse["stars"] = 0
	worse["passed"] = false
	check(not progress.record_attempt(worse), "a lower score is not a new best")
	var best: Dictionary = progress.level_result(1)
	check(best["best_score"] == 900 and best["stars"] == 1 and best["passed"] and best["attempts"] == 2, "best score, stars, passed and attempts kept")

	var reloaded = S.new()
	reloaded.path = progress.path
	reloaded.load_data()
	check(reloaded.level_result(1)["best_score"] == 900 and reloaded.history.size() == 2, "progress survives a reload")
	check(reloaded.history[0]["correct"] == 9 and reloaded.history[0]["playtime_sec"] == 200, "attempt keeps correct/wrong/playtime for the Hub")
	var better := attempt.duplicate()
	better["score"] = 1000
	check(reloaded.record_attempt(better) and reloaded.level_result(1)["best_score"] == 1000, "recording after a reload still works")
	check(reloaded.level_result(1)["best_score"] is int, "saved counters stay whole numbers")
	progress.load_data()
	reloaded.free()

	for i in range(60):
		progress.record_attempt(worse)
	check(progress.history.size() == progress.MAX_HISTORY, "history is capped at %d attempts" % progress.MAX_HISTORY)

	progress.set_demo_unlock(true)
	check(progress.is_unlocked(10), "demo mode opens every level")
	progress.reset()
	check(not progress.is_unlocked(2) and not progress.demo_unlock_all, "reset clears results and demo mode")

	_write(progress.path, "{ not json")
	progress.load_data()
	check(progress.levels.is_empty() and progress.is_unlocked(1), "unreadable save starts fresh")
	progress.reset()

	# A finished level: fade, results, saved result, next level.
	var samples := {}
	for q in QuestionValidator.load_file("res://tests/fixtures/all_types.json").questions:
		samples[QuestionValidator.get_type(q)] = q
	var quiz = await _start_task(samples["chronology"])
	quiz.questions = [samples["chronology"]]
	var items: Array = samples["chronology"]["items"]
	_by_text(quiz, items[1]).hit()
	for item in items:
		_by_text(quiz, item).hit()
	check(quiz.correct_count == 1 and quiz.wrong_count == 1, "correct and wrong answers counted")
	paused = true
	var frozen: float = quiz.playtime
	await create_timer(0.3, true).timeout
	check(quiz.playtime == frozen, "playtime stops while paused")
	paused = false
	await wait(1.3)
	check(quiz.fade_rect.modulate.a > 0.3 and not quiz.results_container.visible, "level ends with a fade to white")
	await wait(0.6)
	check(quiz.results_container.visible, "results appear after the fade")
	check(quiz.results_title.text == "Деңгей өтілді!", "results title for a pass")
	check(quiz.results_stars.stars == 3, "3 stars shown")
	check(quiz.results_label.text.contains("Ұпай: 100 / 100") and quiz.results_label.text.contains("Дұрыс: 1    Қате: 1"), "results show score, correct and wrong")
	check(quiz.results_label.text.contains("Уақыт: 00:0"), "results show playtime")
	check(quiz.results_label.text.contains("Жаңа рекорд!"), "new best announced")
	check(progress.level_result(1)["passed"] and progress.history[-1]["completed"], "result saved")
	check(progress.history[-1]["playtime_sec"] >= 1, "playtime saved in whole seconds")
	check(quiz.next_button.visible, "next level offered once level 2 is open")
	await wait(0.7)
	check(quiz.fade_rect.modulate.a < 0.05, "fade clears to show the results")
	quiz.next_button.pressed.emit()
	await process_frame
	await process_frame
	check(game_state.selected_level == 2 and current_scene.name == "CharacterSelect" and current_scene.selected_id == "mode", "next level goes to level 2's character screen with Мөде preselected")
	current_scene.queue_free()
	await process_frame

	progress.reset()
	quiz = await _start_task(samples["single_choice"])
	_wrong_target(quiz).hit()
	await wait(1.8)
	check(quiz.results_title.text == "Деңгей өтілмеді" and quiz.results_stars.stars == 0, "failing the pass mark: no stars")
	check(quiz.results_label.text.contains("кемінде 60%"), "results explain the pass mark")
	check(not quiz.next_button.visible and not progress.is_unlocked(2), "next level stays locked")
	quiz.get_parent().queue_free()
	await process_frame

	# Defeats are saved as unfinished attempts.
	progress.reset()
	quiz = await _start_task(samples["single_choice"])
	quiz.questions = [samples["single_choice"], samples["fill_blank"]]
	quiz.revivals_left = 0
	quiz.health = 10
	_wrong_target(quiz).hit()
	await wait(1.8)
	check(progress.history.size() == 1 and not progress.history[0]["completed"] and not progress.history[0]["passed"], "defeat without medical help is saved")
	quiz.get_parent().queue_free()
	await process_frame

	progress.reset()
	quiz = await _start_task(samples["single_choice"])
	quiz.questions = [samples["single_choice"], samples["fill_blank"]]
	quiz.health = 10
	_wrong_target(quiz).hit()
	await wait(1.8)
	check(progress.history.is_empty(), "nothing saved while medical help is still possible")
	_press_wrong(quiz.revival_panel)
	check(progress.history.size() == 1 and not progress.history[0]["completed"], "a wrong medical-help answer saves the defeat")
	quiz.get_parent().queue_free()
	await process_frame

	# Level select shows unlocks and earned stars.
	progress.reset()
	progress.record_attempt(attempt.merged({"stars": 2}, true))
	var screen: Node = load("res://level_select.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await process_frame
	var grid: GridContainer = screen.get_node("CenterContainer/VBoxContainer/LevelGrid")
	var enabled: Array = grid.get_children().filter(func(b): return not b.disabled)
	check(enabled.size() == 2, "levels 1-2 open after passing level 1 (got %d)" % enabled.size())
	check(grid.get_child(0).get_child(0).stars == 2, "level 1 button shows 2 earned stars")
	screen._show_level_info(1)
	check(screen.level_info_label.text.contains("Үздік ұпай: 900"), "best score shown")
	screen._show_level_info(3)
	check(screen.level_info_label.text.contains("алдыңғы деңгейді өтіңіз"), "locked level says to pass the previous one")
	screen.queue_free()
	await process_frame

	# Settings: demo mode and two-step reset.
	var menu: Node = load("res://main_menu.tscn").instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	menu.settings_button.pressed.emit()
	check(menu.settings_container.visible, "Settings opens")
	menu.demo_check.button_pressed = true
	check(progress.demo_unlock_all, "demo toggle opens all levels")
	menu.reset_button.pressed.emit()
	check(progress.level_result(1)["attempts"] == 1, "first reset press only asks for confirmation")
	menu.reset_button.pressed.emit()
	check(progress.levels.is_empty() and not progress.demo_unlock_all and not menu.demo_check.button_pressed, "second press clears progress")
	menu.close_button.pressed.emit()
	check(not menu.settings_container.visible, "Settings closes")
	menu.queue_free()
	await process_frame
	progress.reset()


func test_full_playthrough() -> void:
	print("== Play-through: every level answered correctly")
	progress.reset()
	progress.set_demo_unlock(true)
	Engine.time_scale = 5.0
	for level in level_db.levels:
		game_state.selected_level = level["id"]
		game_state.selected_character = level.get("protagonist", "")
		var arena := await _load_arena()
		var quiz = arena.get_node("QuizManager")
		var total: int = quiz.questions.size()
		for i in range(total):
			var guard := 0
			while not quiz.accepting_answers and guard < 200:
				await process_frame
				guard += 1
			if quiz.results_container.visible or quiz.revival_panel.visible:
				break
			_solve(quiz)
			await wait(1.1)
		var guard := 0
		while not quiz.results_container.visible and guard < 300:
			await process_frame
			guard += 1
		check(quiz.results_container.visible and quiz.results_title.text == "Деңгей өтілді!",
			"level %d (%s) can be completed" % [level["id"], level["title"]])
		check(quiz.score == total * 100 and quiz.results_stars.stars == 3,
			"level %d: perfect run scores %d with 3 stars (got %d, %d stars)" % [level["id"], total * 100, quiz.score, quiz.results_stars.stars])
		check(progress.level_result(level["id"])["passed"], "level %d result saved" % level["id"])
		arena.queue_free()
		await process_frame
	Engine.time_scale = 1.0
	progress.reset()
	progress.set_demo_unlock(true)
	game_state.selected_level = 1
	game_state.selected_character = ""


# Answers the current task correctly by hitting the right targets in the right order.
func _solve(quiz) -> void:
	var question: Dictionary = quiz.current_task.question
	match QuestionValidator.get_type(question):
		"chronology":
			for item in question["items"]:
				_by_text(quiz, item).hit()
		"matching":
			for pair in question["pairs"]:
				_by_text(quiz, pair["left"]).hit()
				_by_text(quiz, pair["right"]).hit()
		_:
			quiz.targets.filter(func(t): return t.is_correct)[0].hit()


# Loads the arena and replaces its questions with a single task.
func _start_task(question: Dictionary):
	game_state.selected_level = 1
	var arena := await _load_arena()
	var quiz = arena.get_node("QuizManager")
	quiz.questions = [question]
	quiz.question_index = 0
	quiz.load_question()
	await process_frame
	return quiz


func _by_text(quiz, text: String):
	for target in quiz.targets:
		if target.answer_text == text:
			return target
	return null


func _load_arena() -> Node:
	var arena: Node = load("res://main.tscn").instantiate()
	root.add_child(arena)
	current_scene = arena
	await process_frame
	return arena


func _with(base: Dictionary, key: String, value) -> Dictionary:
	var copy := base.duplicate(true)
	copy[key] = value
	return copy


func _without(base: Dictionary, key: String) -> Dictionary:
	var copy := base.duplicate(true)
	copy.erase(key)
	return copy


func _pairs(count: int) -> Array:
	var pairs := []
	for i in range(count):
		pairs.append({"left": "L%d" % i, "right": "R%d" % i})
	return pairs


func _pairs_question(count: int) -> Dictionary:
	return {"type": "matching", "question": "Q", "pairs": _pairs(count)}


func _map_with(index: int, axis: String, value) -> Dictionary:
	var locations := []
	for i in range(4):
		locations.append({"name": "ABCD"[i], "x": 0.1 + i * 0.25, "y": 0.5})
	if value == null:
		locations[index].erase(axis)
	else:
		locations[index][axis] = value
	return {"type": "map", "question": "Q", "locations": locations, "correct": "A"}


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
