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
const Projectile := preload("res://projectile.gd")
const Soldier := preload("res://soldier.gd")
const EnvironmentBuilder := preload("res://environment_builder.gd")
const QuestionAudit := preload("res://question_audit.gd")

var failures := 0
var checks := 0

# Autoloads are not compile-time globals in a --script run, so fetch them from the tree.
var level_db: Node
var game_state: Node
var char_db: Node
var progress: Node
var backend: Node


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
	# Fixed task order for the tests that expect it; test_quiz_integrity turns shuffling back on.
	game_state.shuffle_questions = false
	char_db = root.get_node("CharacterDatabase")
	# Use a separate save file so tests never touch real progress; demo mode opens levels 1-3.
	progress = root.get_node("ProgressStore")
	progress.base_path = "user://test_progress.json"
	progress.path = progress.base_path
	for file in ["user://test_progress_u1.json", "user://test_progress_u2.json"]:
		DirAccess.remove_absolute(file)
	progress.reset()
	progress.set_demo_unlock(true)
	backend = root.get_node("Backend")
	backend.outbox_path = "user://test_outbox.json"
	backend.outbox = []
	backend.save_outbox()

	print("== Level data")
	test_level_data()
	print("== Question format")
	test_question_types()
	test_question_files()
	print("== Question audit: repeats, leaks, difficulty, translations")
	test_question_audit()
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

	var themes: Dictionary = EnvironmentBuilder.load_themes()
	for id in range(1, 11):
		check(level_db.is_playable(id), "level %d is playable (question file exists)" % id)
		var theme: Dictionary = themes.get(level_db.get_level(id).get("theme", ""), {})
		var keys_ok := ["sky_top", "sky_horizon", "ground", "fog_color", "fog_density", "sun_color", "sun_energy", "ledge", "placard", "target_style", "props", "ally_look", "enemy_look", "background"].all(func(k): return theme.has(k))
		var colors_ok := ["sky_top", "sky_horizon", "ground", "fog_color", "sun_color", "ledge", "placard"].all(func(k): return theme.get(k, "") is String and Color.html_is_valid(theme.get(k, "")))
		check(keys_ok and colors_ok, "level %d has a complete theme" % id)
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
		["map with overlapping pins rejected", _map_with(1, "x", 0.13)],
		["extra answer repeating an option rejected", _with(single, "extra_answers", ["A "])],
		["extra date beside a name rejected", _with(single, "extra_answers", ["1465"])],
		["extra name beside a date rejected", _with(_with(_with(single, "answers", ["1465", "1456", "1505", "1511"]), "correct", "1465"), "extra_answers", ["Керей"])],
		["extra date restating an option rejected", _with(_with(_with(single, "answers", ["1465", "1456", "1505", "1511"]), "correct", "1465"), "extra_answers", ["1456 ж."])],
		["five extra answers rejected", _with(single, "extra_answers", ["e", "f", "g", "h", "i"])],
		["empty extra answers rejected", _with(single, "extra_answers", [])],
		["extra answers on an image task rejected", _with(_with(_with(single, "type", "image"), "image", "res://icon.svg"), "extra_answers", ["e"])],
	]
	for case in cases:
		check(QuestionValidator.validate(case[1]) != "", case[0])

	check(QuestionValidator.validate(_pairs_question(4)) == "", "matching with 4 pairs accepted")
	check(QuestionValidator.validate({"type": "chronology", "question": "Q", "items": ["a", "b", "c"]}) == "", "chronology with 3 items accepted")
	check(QuestionValidator.validate(_with(_map_with(0, "x", 0.1), "correct", "B")) == "", "spread-out map accepted")
	check(QuestionValidator.validate(_with(single, "extra_answers", ["e", "f"])) == "", "same-kind extra answers accepted")
	check(QuestionValidator.answer_key("552 ж.") == QuestionValidator.answer_key("552") and QuestionValidator.answer_key("Мөде") == QuestionValidator.answer_key("мөде"), "answer keys ignore formatting")

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


# Content quality (question_audit.gd): within a level no task repeats another, tests the same
# fact twice or gives away an answer; difficulty rises from the early levels to the final one;
# every task has an English version; medical help has its own bank.
func test_question_audit() -> void:
	var bands := [[], [], [], []]  # Levels 1-3, 4-6, 7-9, 10.
	var level_texts := []
	for level in level_db.levels:
		var questions: Array = QuestionValidator.load_file(level["question_file"]).questions
		var issues := QuestionAudit.audit(questions)
		check(issues.is_empty(), "level %d: no repeated facts or leaked answers %s" % [level["id"], str(issues)])
		var untagged := questions.filter(func(q): return not q.has("difficulty") or not q.has("en"))
		check(untagged.is_empty(), "level %d: every task has a difficulty and an English version" % level["id"])
		var easy := questions.filter(func(q): return q.get("difficulty", 1) == 1).size()
		if level["id"] >= 7:
			check(easy == 0, "level %d: no introductory questions on the hard levels (%d)" % [level["id"], easy])
		elif level["id"] >= 4:
			check(easy * 5 <= questions.size(), "level %d: at most a fifth introductory questions (%d)" % [level["id"], easy])
		bands[mini((level["id"] - 1) / 3, 3)].append(QuestionAudit.average_difficulty(questions))
		for q in questions:
			level_texts.append(QuestionAudit.stems(q["question"]))
	var averages: Array = bands.map(func(b): return b.reduce(func(a, x): return a + x, 0.0) / b.size())
	check(averages[0] < averages[1] and averages[1] < averages[2] and averages[2] < averages[3],
		"difficulty rises by band: %s" % str(averages.map(func(a): return snappedf(a, 0.01))))

	var medical := QuestionValidator.load_file("res://questions/medical.json")
	check(medical.errors.is_empty(), "medical bank loads without errors %s" % str(medical.errors))
	check(medical.questions.size() >= 30, "medical bank has at least 30 questions (%d)" % medical.questions.size())
	check(medical.questions.all(func(q): return QuestionValidator.get_type(q) == "single_choice" and q.has("en")),
		"medical questions are bilingual single-choice tasks")
	check(QuestionAudit.audit(medical.questions).is_empty(), "medical bank: no repeats or leaks %s" % str(QuestionAudit.audit(medical.questions)))
	var copies: Array = medical.questions.filter(func(m):
		var mine := QuestionAudit.stems(m["question"])
		return level_texts.any(func(t): return QuestionAudit.jaccard(mine, t) >= QuestionAudit.NEAR_DUPLICATE))
	check(copies.is_empty(), "medical questions are not copies of level tasks %s" % str(copies.map(func(q): return q["id"])))

	# The audit itself catches the problems it is meant to catch.
	var leaked := {"id": "a", "question": "Абай Құнанбайұлы қай жылы туған?", "answers": ["1845 ж.", "1835 ж.", "1855 ж.", "1865 ж."], "correct": "1845 ж."}
	var reveal := {"id": "b", "type": "matching", "question": "Сәйкестендіріңіз", "pairs": [{"left": "Абай", "right": "1845 жылы туды"}, {"left": "x", "right": "y"}]}
	check(not QuestionAudit.audit([leaked, reveal]).is_empty(), "audit: a pair that states another task's year is caught")
	var self_leak := {"id": "c", "question": "Күлтегін ескерткіші кімге арналған?", "answers": ["Күлтегінге", "Бумынға", "Аттилаға", "Мөдеге"], "correct": "Күлтегінге"}
	check(not QuestionAudit.audit([self_leak]).is_empty(), "audit: a prompt that contains its own answer is caught")
	var near := {"id": "d", "question": "Алтын адам қай қорғаннан табылды?", "answers": ["Есік", "Берел", "Шілікті", "Бесшатыр"], "correct": "Есік"}
	var near2 := {"id": "e", "question": "Алтын адам қай қорғаннан табылған?", "answers": ["Есік қорғаны", "Берел", "Шілікті", "Бесшатыр"], "correct": "Есік қорғаны"}
	check(not QuestionAudit.audit([near, near2]).is_empty(), "audit: near-duplicate prompts are caught")
	var bad_en := {"question": "Q", "answers": ["a", "b", "c", "d"], "correct": "a", "en": {"question": "Q", "answers": ["a", "b", "c"]}}
	check(not QuestionValidator.validate(bad_en).is_empty(), "an English version with a missing answer is rejected")
	check(not QuestionValidator.validate(_with(bad_en, "difficulty", 4)).is_empty(), "difficulty outside 1-3 is rejected")


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
	check(xs.map(func(x): return snappedf(x, 0.01)) == [-5.4, -1.8, 1.8, 5.4], "four answers stand in one row, 3.6 m apart")
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
	await test_quiz_integrity()
	await test_hud_and_labels()
	await test_answer_layout()
	await test_shooting_range()
	test_total_score_unlocks()
	await test_progress()
	await test_full_playthrough()
	await test_backend()
	backend.outbox_path = backend.OUTBOX_PATH
	backend.load_outbox()
	progress.base_path = ProgressStoreScript.SAVE_PATH
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
		check(is_equal_approx(_by_text(quiz, pair["left"]).starting_position.y, quiz.TOP_ROW_Y), "left item \"%s\" on the top row" % pair["left"])

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
	check(quiz.health == 100 and quiz.health_label.text == "HP 100/100" and quiz.health_bar.value == 100, "run starts with 100 HP")
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
	check(quiz.health == 50 and quiz.health_label.text == "HP 50/100" and quiz.health_bar.value == 50, "medical help restores the level's 50 HP")
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
	check(quiz.health_label.text == "HP 130/130" and quiz.health_bar.max_value == 130 and quiz.health_bar.value == 130, "HUD shows HP out of the character's maximum")
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

	game_state.selected_character = "kaiyrkhan"
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


func test_quiz_integrity() -> void:
	print("== Quiz integrity: decoys, answer kinds, task order, pause screen")
	game_state.selected_character = ""
	for level in level_db.levels:
		game_state.selected_level = level["id"]
		var arena := await _load_arena()
		var quiz = arena.get_node("QuizManager")

		# Every option set is one kind of answer: all dates, or no dates.
		var mixed := []
		for q in quiz.questions:
			if q.has("answers"):
				var kinds := {}
				for answer in q["answers"] + q.get("extra_answers", []):
					kinds[QuestionValidator.has_digit(answer)] = true
				if kinds.size() > 1:
					mixed.append(q["id"])
		check(mixed.is_empty(), "level %d: dates are only offered beside dates %s" % [level["id"], str(mixed)])

		# Play every choice task: decoys only from that task's own extra answers, one correct target.
		var wrong := []
		var choice_tasks := 0
		var without_extras := 0
		for i in range(quiz.questions.size()):
			var q: Dictionary = quiz.questions[i]
			if not quiz.DECOY_TYPES.has(QuestionValidator.get_type(q)):
				continue
			choice_tasks += 1
			if not q.has("extra_answers"):
				without_extras += 1
			quiz.question_index = i
			quiz.load_question()
			var expected: int = 4 + mini(level["extra_decoys"], q.get("extra_answers", []).size())
			var stray: Array = quiz.targets.filter(func(t): return not q["answers"].has(t.answer_text) and not q.get("extra_answers", []).has(t.answer_text))
			var correct: Array = quiz.targets.filter(func(t): return t.is_correct)
			if quiz.targets.size() != expected or not stray.is_empty() or correct.size() != 1 or correct[0].answer_text != q["correct"]:
				wrong.append(q["id"])
		check(wrong.is_empty(), "level %d: every choice task shows only its own options and extra answers %s" % [level["id"], str(wrong)])
		if level["extra_decoys"] > 0:
			# Some tasks have no sensible extra answer (the three law codes, "how many zhuzes"); they
			# show four options rather than an unrelated one.
			check(without_extras * 2 <= choice_tasks, "level %d: most choice tasks have hand-written extra answers (%d of %d without)" % [level["id"], without_extras, choice_tasks])
		arena.queue_free()
		await process_frame

	# A new task order on every attempt, each task exactly once; Retry reshuffles.
	game_state.shuffle_questions = true
	game_state.selected_level = 5
	var file_ids: Array = QuestionValidator.load_file(level_db.get_level(5)["question_file"]).questions.map(func(q): return q["id"])
	var sorted_file_ids := file_ids.duplicate()
	sorted_file_ids.sort()
	var orders := []
	var arena := await _load_arena()
	for attempt in range(3):
		var ids: Array = arena.get_node("QuizManager").questions.map(func(q): return q["id"])
		var sorted_ids := ids.duplicate()
		sorted_ids.sort()
		check(sorted_ids == sorted_file_ids, "attempt %d asks every task exactly once" % (attempt + 1))
		orders.append(ids)
		arena.get_node("QuizManager")._on_restart_button_pressed()
		await process_frame
		await process_frame
		arena = current_scene
	check(orders[0] != orders[1] or orders[1] != orders[2], "Retry gives a new task order")
	check(orders.any(func(o): return o != file_ids), "tasks are not asked in file order")
	var quiz = arena.get_node("QuizManager")
	var positions := {}
	for attempt in range(12):
		quiz.questions = [quiz.questions.filter(func(q): return QuestionValidator.get_type(q) == "single_choice")[0]]
		quiz.question_index = 0
		quiz.load_question()
		positions[quiz.targets.filter(func(t): return t.is_correct)[0].starting_position.x] = true
	check(positions.size() > 1, "the correct answer moves between positions")
	arena.queue_free()
	await process_frame
	game_state.shuffle_questions = false

	# Pausing hides the whole quiz behind an opaque screen and keeps the task as it was.
	game_state.selected_level = 1
	arena = await _load_arena()
	quiz = arena.get_node("QuizManager")
	var pause_menu: Control = arena.get_node("HUD/PauseMenu")
	var backdrop: ColorRect = pause_menu.get_node("Backdrop")
	var task_text: String = quiz.question_label.text
	var task_index: int = quiz.question_index
	var answers: Array = quiz.targets.map(func(t): return t.answer_text)
	pause_menu.pause_game()
	await process_frame
	var left: float = quiz.time_left
	await create_timer(0.4, true).timeout
	check(paused and pause_menu.visible and quiz.time_left == left, "pause freezes the game and the timer")
	check(backdrop.color.a == 1.0 and backdrop.get_global_rect().size == arena.get_viewport().get_visible_rect().size, "pause screen is opaque and covers the whole window")
	check(pause_menu.get_index() == arena.get_node("HUD").get_child_count() - 1, "pause screen is drawn above every HUD element")
	pause_menu.resume_game()
	await process_frame
	check(not paused and quiz.question_index == task_index and quiz.question_label.text == task_text and quiz.targets.map(func(t): return t.answer_text) == answers, "resume continues the same task")
	arena.queue_free()
	await process_frame


# Answer formations for 3-6 answers and 2-4 matching pairs, in several window shapes, with long
# Kazakh and English answers: every label is shown, inside the screen and below the top bar, and
# no two labels touch, also while the soldiers sway.
func test_answer_layout() -> void:
	print("== Answer layout: 3-6 answers, matching rows, window shapes, long text")
	game_state.selected_character = ""
	game_state.selected_level = 7
	var long := ["Азиядағы өзара іс-қимыл және сенім шаралары кеңесі", "Conference on Interaction and Confidence-Building Measures in Asia",
		"Майдан маңындағы қара жұмысқа адам алу", "Drafting men for labour behind the front", "Мұхаммед Хайдар Дулати",
		"Ядролық сынақтарға қарсы іс-қимыл күні", "Single-chamber parliament of the first years of independence", "Жанқожа Нұрмұхамедұлы"]
	var tasks := [
		{"type": "chronology", "question": "Q", "items": long.slice(0, 3)},
		{"type": "single_choice", "question": "Q", "answers": long.slice(0, 4), "correct": long[0]},
		{"type": "chronology", "question": "Q", "items": long.slice(0, 5)},
		{"type": "single_choice", "question": "Q", "answers": long.slice(0, 4), "correct": long[0], "extra_answers": long.slice(4, 6)},
		{"type": "matching", "question": "Q", "pairs": [{"left": long[4], "right": long[1]}, {"left": long[7], "right": long[6]}]},
		{"type": "matching", "question": "Q", "pairs": [{"left": long[4], "right": long[1]}, {"left": long[7], "right": long[6]}, {"left": long[5], "right": long[3]}]},
		{"type": "matching", "question": "Q", "pairs": [{"left": long[4], "right": long[1]}, {"left": long[7], "right": long[6]}, {"left": long[5], "right": long[3]}, {"left": long[0], "right": long[2]}]},
	]
	var names := ["3 events", "4 answers", "5 events", "6 answers", "2 pairs", "3 pairs", "4 pairs"]
	for window_size in [Vector2i(1280, 720), Vector2i(1024, 768), Vector2i(1366, 768), Vector2i(1920, 1080), Vector2i(800, 600)]:
		root.size = window_size
		var arena := await _load_arena()
		var quiz = arena.get_node("QuizManager")
		var screen: Rect2 = arena.get_viewport().get_visible_rect()
		var bad := []
		for t in range(tasks.size()):
			quiz.questions = [tasks[t]]
			quiz.question_index = 0
			quiz.load_question()
			var gaps := []
			for i in range(quiz.targets.size()):
				for j in range(i + 1, quiz.targets.size()):
					gaps.append(quiz.targets[i].starting_position.distance_to(quiz.targets[j].starting_position))
			if gaps.min() < 3.0:
				bad.append("%s: soldiers %.1f m apart" % [names[t], gaps.min()])
			# Several moments of the sway.
			for sample in range(4):
				for f in range(8 if sample > 0 else 3):
					await process_frame
				var panels: Array = quiz.targets.map(func(x): return quiz.answer_labels.label_for(x))
				if not panels.all(func(p): return p != null and p.visible):
					bad.append("%s: a label is hidden" % names[t])
					break
				var rects: Array = panels.map(func(p): return p.get_global_rect())
				if not rects.all(func(r): return screen.encloses(r) and r.position.y >= quiz.answer_labels.top_limit() - 8.5):
					bad.append("%s: a label leaves the screen or covers the top bar" % names[t])
					break
				var touching := 0
				for i in range(rects.size()):
					for j in range(i + 1, rects.size()):
						if rects[i].intersects(rects[j]):
							touching += 1
				if touching > 0:
					bad.append("%s: %d overlapping labels" % [names[t], touching])
					break
		check(bad.is_empty(), "%dx%d: all formations readable %s" % [window_size.x, window_size.y, str(bad)])
		arena.queue_free()
		await process_frame
	root.size = Vector2i(1152, 648)


func test_hud_and_labels() -> void:
	print("== HUD layout and answer labels")
	game_state.selected_character = ""
	game_state.selected_level = 7
	var long_text := "Ұзын сұрақ: " + "Қазақ хандығының тарихындағы маңызды оқиғаларды еске түсіріп, дұрыс жауапты таңдаңыз. ".repeat(3)
	for window_size in [Vector2i(800, 600), Vector2i(1280, 720), Vector2i(1920, 1080)]:
		root.size = window_size
		var arena := await _load_arena()
		var quiz = arena.get_node("QuizManager")
		quiz.set_question(long_text)
		await process_frame
		await process_frame
		var panel: Rect2 = quiz.question_panel.get_global_rect()
		var corners: Array[Rect2] = [quiz.score_label.get_global_rect(), quiz.health_bar.get_global_rect(), quiz.timer_label.get_global_rect()]
		var screen: Rect2 = arena.get_viewport().get_visible_rect()
		check(corners.all(func(r): return not r.intersects(panel)), "%dx%d: a long question never covers score, HP or timer" % [window_size.x, window_size.y])
		check(quiz.question_label.get_line_count() > 1 and screen.encloses(panel), "%dx%d: a long question wraps and stays on screen" % [window_size.x, window_size.y])
		check(not quiz.character_label.get_global_rect().intersects(panel) and screen.encloses(quiz.ability_label.get_global_rect()), "%dx%d: loadout stays at the bottom left" % [window_size.x, window_size.y])
		arena.queue_free()
		await process_frame
	root.size = Vector2i(1152, 648)

	var arena := await _load_arena()
	var quiz = arena.get_node("QuizManager")
	quiz.take_damage(30)
	check(quiz.health_bar.value == 70 and quiz.health_label.text == "HP 70/100", "HP bar drops at once on damage")
	var fill: StyleBoxFlat = quiz.health_bar.get_theme_stylebox("fill")
	quiz.health = 20
	quiz.update_hud()
	check(quiz.health_bar.value == 20 and fill.bg_color.r > fill.bg_color.g, "HP bar turns red when low")

	await process_frame
	await process_frame
	var labels: Control = quiz.answer_labels
	var panels: Array = quiz.targets.map(func(t): return labels.label_for(t))
	check(panels.size() == 6 and panels.all(func(p): return p != null and p.visible), "every answer soldier has a floating label")
	check(quiz.targets.all(func(t): return labels.label_for(t).get_child(0).text == t.answer_text and not t.answer_label.visible and not t.target_mesh.visible), "labels show the answers; no placards")
	var overlaps := 0
	for i in range(panels.size()):
		for j in range(i + 1, panels.size()):
			if panels[i].get_global_rect().intersects(panels[j].get_global_rect()):
				overlaps += 1
	check(overlaps == 0, "answer labels never overlap (%d overlaps)" % overlaps)
	var camera: Camera3D = arena.get_viewport().get_camera_3d()
	check(quiz.targets.all(func(t):
		var rect: Rect2 = labels.label_for(t).get_global_rect()
		var below: bool = is_equal_approx(t.starting_position.y, quiz.CHOICE_ROW_Y)
		return rect.position.y >= camera.unproject_position(t.foot_anchor()).y if below else rect.end.y <= camera.unproject_position(t.label_anchor()).y),
		"front-row labels hang below the feet, rampart labels float above the heads")
	var parts: Array = quiz.targets[0].soldier.find_children("*", "MeshInstance3D", true, false)
	check(parts.all(func(p): return p.material_overlay != null and p.material_overlay.get_shader_parameter("color") == quiz.targets[0].OUTLINE_COLOR), "answer soldiers have a red outline")
	var correct = quiz.targets.filter(func(t): return t.is_correct)[0]
	correct.set_state(Target.State.DONE)
	check(correct.soldier.find_children("*", "MeshInstance3D", true, false)[0].material_overlay.get_shader_parameter("color") == Target.STATE_COLORS[Target.State.DONE], "outline turns green when answered")
	check(labels.get_index() < arena.get_node("HUD/PauseMenu").get_index(), "labels are hidden under the pause screen")
	correct.set_state(Target.State.NORMAL)

	# Shooting a soldier's body selects its answer: aim the real camera and fire the real ray.
	var space := camera.get_world_3d().direct_space_state
	var hittable: Array = quiz.targets.filter(func(t):
		var query := PhysicsRayQueryParameters3D.create(camera.global_position, t.label_anchor() - Vector3(0, 0.9, 0))
		query.exclude = [arena.get_node("Player").get_rid()]
		var hit := space.intersect_ray(query)
		return not hit.is_empty() and hit["collider"] == t)
	check(hittable.size() == quiz.targets.size(), "every answer soldier's body can be shot (%d of %d)" % [hittable.size(), quiz.targets.size()])
	camera.look_at(correct.label_anchor() - Vector3(0, 0.9, 0))
	arena.get_node("Player").cooldown_left = 0.0
	arena.get_node("Player").shoot()
	check(quiz.score == 100 and correct.state == Target.State.DONE, "shooting the right soldier answers the task")
	camera.rotation = Vector3.ZERO
	await wait(1.3)
	await process_frame
	panels = quiz.targets.map(func(t): return labels.label_for(t))
	check(quiz.question_index == 1 and panels.size() > 0 and panels.all(func(p): return p != null and p.visible), "the next task gets fresh labels")

	var player: Node3D = arena.get_node("Player")
	player.rotation.y += PI
	await process_frame
	await process_frame
	check(panels.all(func(p): return not p.visible), "labels hide when their soldiers are behind the camera")
	player.rotation.y -= PI
	await process_frame
	await process_frame
	check(panels.all(func(p): return p.visible), "labels come back when the soldiers are in view")
	quiz.clear_arena()
	await process_frame
	check(labels.get_child_count() == 0 or labels.get_children().all(func(c): return c.is_queued_for_deletion()), "labels go away with their task")
	arena.queue_free()
	await process_frame


func test_shooting_range() -> void:
	print("== Level 10 shooting range")
	game_state.selected_level = 10
	var arena := await _load_arena()
	var quiz = arena.get_node("QuizManager")
	await process_frame
	await process_frame
	var xs: Array = quiz.targets.map(func(t): return t.starting_position.x)
	xs.sort()
	var one_row: bool = quiz.targets.all(func(t): return is_equal_approx(t.starting_position.y, quiz.CHOICE_ROW_Y))
	var spaced := true
	for i in range(1, xs.size()):
		spaced = spaced and xs[i] - xs[i - 1] >= quiz.RANGE_SPACING - 0.01
	check(quiz.targets.size() == 6 and one_row and spaced, "range: answers and decoys stand in one wide row")
	var panels: Array = quiz.targets.map(func(t): return quiz.answer_labels.label_for(t))
	var overlaps := 0
	for i in range(panels.size()):
		for j in range(i + 1, panels.size()):
			if panels[i].get_global_rect().intersects(panels[j].get_global_rect()):
				overlaps += 1
	check(panels.all(func(p): return p.visible) and overlaps == 0, "range: every label visible, none overlapping")
	check(level_db.get_level(10)["target_speed"] <= 1.5 and quiz.enemy_spawner.enemies.is_empty(), "range: calm target movement, no enemies")
	arena.queue_free()
	await process_frame
	game_state.selected_level = 1


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
	game_state.selected_character = "kaiyrkhan"
	for case in [[1, 3], [3, 3], [5, 2]]:
		game_state.selected_level = case[0]
		var probe := await _load_arena()
		check(probe.get_node("QuizManager").ability_uses == case[1], "level %d: 50/50 has %d uses" % case)
		probe.queue_free()
		await process_frame
	game_state.selected_character = ""

	# Level 3: faster targets, no decoys yet (the assignment's table: 3 wrong answers on levels 1-4).
	game_state.selected_level = 3
	var arena := await _load_arena()
	quiz = arena.get_node("QuizManager")
	check(quiz.targets.all(func(t): return t.move_speed >= 1.25 * 0.8 - 0.001 and t.move_speed <= 1.25 * 1.2 + 0.001), "targets sway 1.25x faster on level 3")
	check(quiz.targets.size() == 4, "level 3 shows the four options only (got %d)" % quiz.targets.size())
	arena.queue_free()
	await process_frame

	# Level 7: two decoys, both from the question's own hand-written extra answers.
	game_state.selected_level = 7
	arena = await _load_arena()
	quiz = arena.get_node("QuizManager")
	var question: Dictionary = quiz.questions[0]
	check(question.has("extra_answers") and quiz.targets.size() == 6, "level 7 adds two decoy targets (got %d)" % quiz.targets.size())
	var decoys: Array = quiz.targets.filter(func(t): return not question["answers"].has(t.answer_text))
	check(decoys.size() == 2 and decoys.all(func(t): return question["extra_answers"].has(t.answer_text) and not t.is_correct), "decoys are the question's own extra answers")
	var front: Array = quiz.targets.filter(func(t): return is_equal_approx(t.starting_position.y, quiz.CHOICE_ROW_Y))
	check(front.size() == 3 and quiz.targets.size() - front.size() == 3, "six answers stand three on the ground and three on the rampart")
	check(quiz.targets.filter(func(t): return t.is_correct).size() == 1, "still exactly one correct target")
	check(quiz.decoy_answers({"answers": ["a", "b", "c", "d"], "correct": "a"}, 2).is_empty(), "a question without extra answers gets no decoys")
	check(quiz.decoy_answers(_with(question, "extra_answers", ["x"]), 2) == ["x"], "fewer extra answers give fewer decoys")
	quiz.questions = [samples["image"]]
	quiz.question_index = 0
	quiz.load_question()
	check(quiz.targets.size() == 4, "image tasks get no decoys")
	arena.queue_free()
	await process_frame

	print("== Enemies and the battle scene")
	game_state.selected_level = 3
	arena = await _load_arena()
	quiz = arena.get_node("QuizManager")
	var player = arena.get_node("Player")
	var spawner = quiz.enemy_spawner
	check(spawner.enemies.size() == 1, "level 3 has one enemy")
	var enemy = spawner.enemies[0]
	check(spawner.hits_to_kill() == 1 and enemy.max_hp == player.weapon["damage"] and enemy.damage == 5, "easy level: an enemy falls to one hit (hp %d, damage %d)" % [enemy.max_hp, enemy.damage])
	check(absf(enemy.post.x) >= 8.0 and absf(enemy.position.x) > absf(enemy.post.x), "enemy marches in from the edge to a post on the flank")
	check(not enemy.begin_aim(), "a marching enemy cannot shoot yet")
	check(enemy.soldier != null, "enemy is a low-poly soldier")
	check(not quiz.environment.background_soldiers.is_empty(), "background soldiers fill the scene")
	for i in range(60):
		if enemy.at_post():
			break
		await wait(0.1)
	check(enemy.at_post(), "the enemy reaches its post")
	await physics_frame
	var posted_at: Vector3 = enemy.global_position
	var posted_post: Vector3 = enemy.post
	await wait(1.0)
	check(Vector2(enemy.global_position.x, enemy.global_position.z).distance_to(Vector2(posted_at.x, posted_at.z)) < 0.05, "enemies do not chase the player")

	var expected: int = maxi(1, roundi(enemy.damage * (100 - quiz.character["defense"]) / 100.0))
	var hp_before: int = quiz.health
	spawner.volley_left = 0.05
	await wait(0.15)
	check(enemy.aim_left >= 0.0 and enemy.aim_label.visible, "the enemy line orders a shot: enemy aims with a visible warning")
	quiz.accepting_answers = false
	await wait(0.1)
	check(enemy.aim_left < 0.0 and not enemy.aim_label.visible, "aiming stops between tasks")
	await wait(enemy.AIM_TIME + 0.6)
	check(quiz.health == hp_before, "no shot between tasks")
	quiz.accepting_answers = true

	enemy.begin_aim()
	await wait(enemy.AIM_TIME + 0.8)
	check(quiz.health == hp_before - expected, "an aimed shot hits a standing player for %d (damage minus defense)" % expected)
	check(quiz.feedback_label.text == "Жау шабуылы! −%d HP" % expected, "enemy hit announced")

	hp_before = quiz.health
	enemy.begin_aim()
	await wait(enemy.AIM_TIME + 0.02)
	player.global_position += Vector3(3.0, 0, 0)
	await wait(0.8)
	check(quiz.health == hp_before, "stepping aside dodges the shot")
	player.global_position -= Vector3(3.0, 0, 0)

	# Wrong answer: a visible reaction shot, but only the usual 10 HP.
	var projectiles_before: int = current_scene.get_children().filter(func(c): return c.get_script() == Projectile).size()
	hp_before = quiz.health
	_wrong_target(quiz).hit()
	await process_frame
	var projectiles_after: int = current_scene.get_children().filter(func(c): return c.get_script() == Projectile).size()
	check(projectiles_after > projectiles_before, "a wrong answer shows an enemy landing a shot")
	check(quiz.damage_flash.color.a > 0.05, "the screen flashes red")
	await wait(0.8)
	check(quiz.health == hp_before - 10, "the reaction shot adds no damage beyond the wrong answer")
	await wait(1.2)

	await physics_frame
	await physics_frame
	var score_before: int = quiz.score
	player.get_node("Camera3D").look_at(enemy.global_position + Vector3(0, 1.0, 0))
	player.cooldown_left = 0.0
	player.shoot()
	await process_frame
	check(spawner.enemies.is_empty(), "the shot brings the enemy down")
	check(quiz.score == score_before, "killing enemies gives no points (no score farming)")
	await wait(spawner.REINFORCE_DELAY - 1.0)
	check(spawner.enemies.is_empty(), "no instant respawn")
	await wait(1.3)
	check(spawner.enemies.size() == 1 and spawner.enemies[0].post != posted_post, "one reinforcement arrives later, at a different post")
	spawner.enemies[0].take_hit(99)
	await wait(spawner.REINFORCE_DELAY + 0.3)
	check(spawner.enemies.is_empty(), "the line can be cleared: one reinforcement per task")
	spawner.start()
	check(spawner.enemies.size() == 1, "the next task brings a new wave")

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

	# Level 10 is a peaceful shooting range: no enemies at all.
	game_state.selected_level = 10
	arena = await _load_arena()
	quiz = arena.get_node("QuizManager")
	spawner = quiz.enemy_spawner
	check(spawner.enemies.is_empty(), "the shooting range has no enemies")
	check(quiz.targets.all(func(t): return t.style == "gallery" and t.get_node("TargetVisual").get_children().all(func(c): return c.get_script() != Soldier)), "range targets are round targets, not soldiers")
	hp_before = quiz.health
	await wait(3.0)
	check(quiz.health == hp_before, "nothing damages the player in the gallery")
	arena.queue_free()
	await process_frame
	game_state.selected_level = 3

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

	arena.queue_free()
	await process_frame

	# Later levels: at most three enemies, spread over different posts, new posts every wave, and
	# toughness that takes about a second of fire whatever the weapon.
	game_state.selected_level = 7
	for id in ["tomyris", "kultegin", "kabanbay", "aliya", "manshuk"]:
		game_state.selected_character = id
		arena = await _load_arena()
		spawner = arena.get_node("QuizManager").enemy_spawner
		var weapon: Dictionary = arena.get_node("Player").weapon
		var seconds: float = (spawner.hits_to_kill() - 1) * weapon["cooldown"]
		check(seconds >= 0.8 and seconds <= 1.5 and spawner.enemies[0].max_hp == spawner.hits_to_kill() * weapon["damage"],
			"level 7, %s: an enemy takes %d hits (%.2f s of fire)" % [weapon["name"], spawner.hits_to_kill(), seconds])
		if id == "kabanbay":
			var posts: Array = spawner.enemies.map(func(e): return e.post)
			check(spawner.enemies.size() == 3 and posts.size() == 3 and posts[0] != posts[1] and posts[1] != posts[2] and posts[0] != posts[2], "level 7: three enemies at three different posts")
			spawner.stop()
			spawner.start()
			check(spawner.enemies.all(func(e): return not posts.has(e.post)), "the next wave takes different posts")
			spawner.configure(arena.get_node("QuizManager"), arena.get_node("Player"), {"enemies": 8, "stars": 5}, {"enemy_look": {"coat": "#000000"}})
			check(spawner.count == spawner.MAX_ACTIVE, "never more than %d active enemies" % spawner.MAX_ACTIVE)
		arena.queue_free()
		await process_frame
	game_state.selected_character = ""
	game_state.selected_level = 1


func test_total_score_unlocks() -> void:
	print("== Total-score unlocking")
	var was_demo: bool = progress.demo_unlock_all
	progress.reset()
	# Thresholds: rising, reachable by passing every earlier level at its pass mark, and from level 3
	# on more than any single level can give (so one easy level cannot be farmed to skip ahead).
	var passing := 0
	var best_single := 0
	var sane := true
	for level in level_db.levels:
		var id: int = level["id"]
		var max_score: int = QuestionValidator.load_file(level["question_file"]).questions.size() * 100
		var needed: int = progress.unlock_score(id)
		if id == 1:
			sane = sane and needed == 0
		else:
			sane = sane and needed <= passing and needed > progress.unlock_score(id - 1) and (id < 3 or needed > best_single)
		passing += ceili(max_score * level["pass_percent"] / 100.0)
		best_single = maxi(best_single, max_score)
	check(sane, "thresholds rise, are reachable at the pass marks, and need more than one level")

	var run := func(id: int, score: int): return {"level": id, "score": score, "stars": 1, "passed": true, "completed": true}
	check(progress.is_unlocked(1) and not progress.is_unlocked(2), "only level 1 open at the start")
	progress.record_attempt(run.call(1, 700))
	check(progress.total_score() == 700 and not progress.is_unlocked(2), "700 is not enough for level 2 (750)")
	progress.record_attempt(run.call(1, 500))
	check(progress.total_score() == 700, "a worse replay does not change the total")
	progress.record_attempt(run.call(1, 1300))
	check(progress.total_score() == 1300 and progress.is_unlocked(2) and progress.just_opened == [2], "beating the best raises the total and opens level 2")
	for i in range(5):
		progress.record_attempt(run.call(1, 1300))
	check(progress.total_score() == 1300 and not progress.is_unlocked(3), "farming level 1 again adds nothing")
	progress.record_attempt(run.call(2, 300))
	check(progress.total_score() == 1600 and progress.is_unlocked(3), "level 3 opens at 1500 from two levels")
	level_db.get_level(3)["unlock_score"] = 99999
	check(progress.is_unlocked(3), "an opened level stays open")
	level_db.get_level(3)["unlock_score"] = 1600
	progress.reset()
	progress.levels = {"1": {"best_score": 900, "stars": 1, "passed": true, "attempts": 1}, "2": {"best_score": 100, "stars": 1, "passed": true, "attempts": 1}}
	progress.save_data()
	progress.load_data()
	check(progress.is_unlocked(3), "levels opened under the old pass-to-unlock rule stay open")
	progress.reset()
	progress.set_demo_unlock(was_demo)


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
	check(not quiz.next_button.visible and quiz.results_label.text.contains("Жалпы ұпай: 100"), "results show the total; level 2 stays closed below 900")
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
	check(screen.level_info_label.text.contains("жалпы ұпай 1600 керек (қазір 900, тағы 700)"), "locked level shows the total it needs")
	check(grid.get_child(2).text == "3\n1600" and screen.total_label.text == "Жалпы ұпай: 900", "locked buttons show their threshold; the total is shown")
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


class FakeTransport:
	extends RefCounted
	var configured := true
	var user := {}
	var sign_in_result := {"uid": "u1", "name": "Тест Оқушы"}
	var accept := true
	var received: Array = []
	var signed_out := false
	var progress := {"ok": true, "levels": {}}
	var board := {"ok": true, "rows": [{"name": "Айгерім", "total": 2400, "me": false}, {"name": "Тест Оқушы", "total": 1100, "me": true}], "me": {"total": 1100, "rank": 2}}

	func is_configured() -> bool:
		return configured

	func wait_user() -> Dictionary:
		await Engine.get_main_loop().process_frame
		return user

	func sign_in() -> Dictionary:
		await Engine.get_main_loop().process_frame
		user = sign_in_result
		return sign_in_result

	func sign_out() -> void:
		signed_out = true
		user = {}

	func submit_result(payload: Dictionary) -> bool:
		await Engine.get_main_loop().process_frame
		if accept:
			received.append(payload)
		return accept

	func my_progress() -> Dictionary:
		await Engine.get_main_loop().process_frame
		return progress

	func leaderboard(_limit: int) -> Dictionary:
		await Engine.get_main_loop().process_frame
		return board


func test_backend() -> void:
	print("== Sign-in and online leaderboard")
	var source := FileAccess.get_file_as_string("res://startup_screen.gd")
	check(not source.contains("PASSWORD") and not source.contains("VALID_USERNAME"), "no hard-coded login or password in the game")
	backend.upload_gap = 0.0

	# Offline (no bridge configured): guest play, nothing queued for upload.
	backend.transport = null
	backend._set_user({})
	backend.outbox = []
	backend.save_outbox()
	check(not backend.online_available(), "desktop/test build has no online bridge")
	var error: String = await backend.sign_in_with_google()
	check(error == backend.OFFLINE_MESSAGE and not backend.is_signed_in(), "Google sign-in explains online mode is not set up")
	backend.continue_as_guest()
	check(backend.is_guest() and backend.display_name() == "Қонақ (офлайн)", "guest mode")
	var attempt := {"level": 2, "character": "mode", "score": 1100, "max_score": 1300, "correct": 11, "wrong": 2,
		"playtime_sec": 190, "stars": 2, "passed": true, "completed": true, "revivals_used": 0, "finished_at": 5}
	backend.submit_attempt(attempt)
	check(backend.outbox.is_empty(), "guest results stay on the device, not in the upload queue")
	var guest_board: Dictionary = await backend.fetch_leaderboard()
	check(guest_board.has("error"), "guests are asked to sign in for the leaderboard")

	# Signed in: per-account progress, online bests merged in, results uploaded in order.
	var fake := FakeTransport.new()
	fake.progress = {"ok": true, "levels": {"3": {"score": 1200, "stars": 2}, "4": {"score": 0, "stars": 0}}}
	backend.transport = fake
	backend._set_user({})
	progress.record_attempt({"level": 1, "score": 300, "stars": 0, "passed": false})
	error = await backend.sign_in_with_google()
	check(error.is_empty() and backend.user["uid"] == "u1" and backend.display_name() == "Тест Оқушы", "Google sign-in shows the player's name")
	check(progress.path != progress.base_path and progress.level_result(1)["attempts"] == 0, "each account has its own progress")
	check(progress.level_result(3)["best_score"] == 1200 and progress.level_result(3)["passed"] and progress.is_unlocked(2) and not progress.is_unlocked(4), "best results saved online are merged after sign-in and count toward unlocking")

	backend.submit_attempt(attempt)
	await wait(0.1)
	check(fake.received.size() == 1 and backend.outbox.is_empty(), "result uploaded")
	check(fake.received[0]["game_id"] == "history-arena" and not fake.received[0].has("owner") and not fake.received[0].has("uid"), "upload carries no user id (the server takes it from the session)")
	var second := attempt.duplicate()
	second["level"] = 3
	var third := attempt.duplicate()
	third["level"] = 4
	fake.accept = false
	backend.submit_attempt(second)
	await wait(0.1)
	check(backend.outbox.size() == 1 and fake.received.size() == 1 and backend.pending_uploads() == 1, "a failed upload stays queued")
	fake.accept = true
	backend.submit_attempt(third)
	await wait(0.2)
	check(backend.outbox.is_empty() and fake.received.map(func(p): return int(p["level"])) == [2, 3, 4], "uploads keep their order after a failure")

	# A run queued by one account is never uploaded under another.
	fake.accept = false
	backend.submit_attempt(attempt)
	await wait(0.1)
	backend.sign_out()
	check(not backend.is_signed_in() and fake.signed_out and progress.path == progress.base_path, "sign out returns to guest progress")
	fake.accept = true
	fake.received.clear()
	fake.progress = {"ok": true, "levels": {}}
	fake.sign_in_result = {"uid": "u2", "name": "Екінші Оқушы"}
	await backend.sign_in_with_google()
	await wait(0.1)
	check(fake.received.is_empty() and backend.outbox.size() == 1 and backend.pending_uploads() == 0, "another account's queued run is not sent")
	check(progress.level_result(3)["best_score"] == 0, "the second account does not see the first one's progress")
	backend.sign_out()
	fake.user = {"uid": "u1", "name": "Тест Оқушы"}
	check(await backend.restore_session() and backend.user["uid"] == "u1", "a saved session is restored")
	await wait(0.1)
	check(fake.received.size() == 1 and backend.outbox.is_empty(), "the first account's queued run is sent when it returns")
	var board: Dictionary = await backend.fetch_leaderboard()
	check(board.get("ok") == true and board["rows"].size() == 2 and int(board["me"]["rank"]) == 2, "leaderboard and personal best fetched")
	fake.sign_in_result = {"error": "кіру терезесі жабылды"}
	backend.sign_out()
	error = await backend.sign_in_with_google()
	check(error.contains("терезесі жабылды") and not backend.is_signed_in(), "failed sign-in reported, nobody signed in")

	# Screens: offline login, guest -> menu shows the player, sign out returns to login.
	backend.transport = null
	backend._set_user({})
	var screen: Node = load("res://startup_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await process_frame
	check(screen.google_button.disabled and screen.status_label.text == screen.OFFLINE_NOTE, "login screen explains offline mode")
	screen.guest_button.pressed.emit()
	await process_frame
	await process_frame
	check(current_scene.name == "MainMenu" and current_scene.user_label.text == "Ойыншы: Қонақ (офлайн)", "guest reaches the menu")
	current_scene.leaderboard_button.pressed.emit()
	await process_frame
	await process_frame
	check(current_scene.name == "Leaderboard" and current_scene.status_label.text.contains("Google"), "leaderboard asks guests to sign in")
	current_scene.back_button.pressed.emit()
	await process_frame
	await process_frame
	current_scene.sign_out_button.pressed.emit()
	await process_frame
	await process_frame
	check(current_scene.name == "StartupScreen" and not backend.is_signed_in(), "sign out returns to the login screen")
	current_scene.queue_free()
	await process_frame

	fake = FakeTransport.new()
	backend.transport = fake
	screen = load("res://startup_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await wait(0.1)
	check(not screen.google_button.disabled and screen.status_label.text == screen.GUEST_NOTE, "Google button active when online mode is set up")
	screen.google_button.pressed.emit()
	await wait(0.1)
	check(current_scene.name == "MainMenu" and current_scene.user_label.text == "Ойыншы: Тест Оқушы", "Google sign-in reaches the menu with the player's name")
	current_scene.leaderboard_button.pressed.emit()
	await wait(0.1)
	var names: Array = current_scene.rows.get_children().map(func(l): return l.text)
	check(current_scene.name == "Leaderboard" and names.has("Айгерім") and names.has("Тест Оқушы"), "leaderboard lists players and scores")
	check(current_scene.me_label.text.contains("1100") and current_scene.me_label.text.contains("орын: 2"), "leaderboard shows the player's personal best and rank")
	current_scene.queue_free()
	await process_frame

	fake.user = {"uid": "u1", "name": "Тест Оқушы"}
	screen = load("res://startup_screen.tscn").instantiate()
	root.add_child(screen)
	current_scene = screen
	await wait(0.1)
	check(current_scene.name == "MainMenu", "a returning signed-in player skips the login screen")
	current_scene.queue_free()
	await process_frame

	# Finishing a level sends the result.
	var samples := {}
	for q in QuestionValidator.load_file("res://tests/fixtures/all_types.json").questions:
		samples[QuestionValidator.get_type(q)] = q
	fake.received.clear()
	var quiz = await _start_task(samples["single_choice"])
	quiz.targets.filter(func(t): return t.is_correct)[0].hit()
	await wait(1.8)
	await wait(0.1)
	check(fake.received.size() == 1 and fake.received[0]["score"] == 100 and fake.received[0]["game_id"] == "history-arena", "finished level uploaded")
	check(quiz.results_label.text.contains("рейтингке жіберілді"), "results screen says the result went to the leaderboard")
	quiz.get_parent().queue_free()
	await process_frame

	backend.transport = null
	backend._set_user({})
	backend.outbox = []
	backend.save_outbox()
	test_security_rules()


# firestore.rules caps each level's score; the caps must match the question files and abilities.
func test_security_rules() -> void:
	var rules := FileAccess.get_file_as_string("res://firestore.rules")
	var all_match := true
	for level in level_db.levels:
		var count: int = QuestionValidator.load_file(level["question_file"]).questions.size()
		all_match = all_match and rules.contains("'%d': %d" % [level["id"], count * 100])
	check(all_match, "security rules know each level's maximum score")
	var max_doubles := 0
	for character in char_db.characters:
		if character["ability"]["id"] == "double_score":
			max_doubles = maxi(max_doubles, int(character["ability"]["uses"]))
	var bonus := RegEx.create_from_string("doubleBonus\\(\\) \\{\\s*return (\\d+);").search(rules)
	check(bonus != null and int(bonus.get_string(1)) == max_doubles * 100, "security rules allow exactly the double-score bonus")
	check(rules.contains("request.auth.uid == uid") and not rules.contains("allow write: if true"), "security rules tie writes to the signed-in account")
	var bridge := FileAccess.get_file_as_string("res://web/firebase-bridge.js")
	check(bridge.contains("requireUser().uid") and not bridge.contains("a.uid") and not bridge.contains("payload.uid"), "the bridge takes the user id from the Firebase session only")


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
