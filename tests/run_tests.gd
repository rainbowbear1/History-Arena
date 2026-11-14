extends SceneTree

# Headless test runner. From the project folder:
#   godot --headless --path . --import
#   godot --headless --path . --script res://tests/run_tests.gd
# Exit code is the number of failed checks (0 = all passed).

const QuestionValidator := preload("res://question_validator.gd")
const LevelDatabaseScript := preload("res://level_database.gd")

var failures := 0
var checks := 0

# Autoloads are not compile-time globals in a --script run, so fetch them from the tree.
var level_db: Node
var game_state: Node


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

	for id in [1, 2, 3]:
		check(level_db.is_playable(id), "level %d is playable" % id)
	for id in range(4, 11):
		check(not level_db.is_playable(id), "level %d is locked until its question file exists" % id)

	var good := {"id": 1, "title": "T", "stars": 1, "question_file": "res://q.json", "time_per_question": 30,
		"target_speed": 1.0, "extra_decoys": 0, "enemies": 0, "lives": 3, "revivals": 2, "pass_percent": 60}
	check(LevelDatabaseScript.validate_level(good) == "", "valid level accepted")
	for broken in [
		["stars", 6], ["stars", 0], ["lives", 0], ["pass_percent", 120], ["target_speed", 0],
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
		["map with wrong correct rejected", _with(_map_with(0, "x", 0.5), "correct", "Нет")],
	]
	for case in cases:
		check(QuestionValidator.validate(case[1]) != "", case[0])

	check(QuestionValidator.validate(_pairs_question(4)) == "", "matching with 4 pairs accepted")
	check(QuestionValidator.validate({"type": "chronology", "question": "Q", "items": ["a", "b", "c"]}) == "", "chronology with 3 items accepted")

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
	for level in level_db.levels:
		if not FileAccess.file_exists(level["question_file"]):
			continue
		var result := QuestionValidator.load_file(level["question_file"])
		check(result.errors.is_empty(), "%s has no errors %s" % [level["question_file"], str(result.errors)])
		check(result.questions.size() >= 10, "%s has at least 10 questions" % level["question_file"])


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
	check(enabled == 3, "3 level buttons enabled (got %d)" % enabled)
	var info: Label = scene.get_node("CenterContainer/VBoxContainer/LevelInfoLabel")
	check(info.text.begins_with("1. Сақтар дәуірі"), "info label shows level 1")
	scene._show_level_info(10)
	check(info.text.contains("BOSS") and info.text.contains("жабық"), "level 10 shows BOSS and locked")
	scene.queue_free()
	await process_frame


func test_arena() -> void:
	for level in [1, 2, 3]:
		game_state.selected_level = level
		var arena := await _load_arena()
		var quiz = arena.get_node("QuizManager")
		check(quiz.question_file == level_db.get_level(level)["question_file"], "level %d uses its question file" % level)
		check(quiz.questions.size() == 10, "level %d loads 10 playable questions" % level)
		arena.queue_free()
		await process_frame

	game_state.selected_level = 1
	var arena := await _load_arena()
	var quiz = arena.get_node("QuizManager")

	var correct_targets: Array = quiz.targets.filter(func(t): return t.is_correct)
	check(correct_targets.size() == 1, "exactly one correct target")

	correct_targets[0].hit()
	check(quiz.score == 100, "correct hit scores 100 once (score=%d)" % quiz.score)
	correct_targets[0].hit()
	check(quiz.score == 100, "second hit during feedback ignored")
	await wait(1.3)
	check(quiz.question_index == 1, "advanced to next question")

	quiz.health = 20
	for i in range(5):
		var wrong = quiz.targets.filter(func(t): return not t.is_correct)[0]
		wrong.hit()
		await wait(1.2)
		if quiz.health <= 0:
			break
	check(quiz.health <= 0, "health reached 0")
	check(quiz.results_container.visible, "results shown on game over")
	check(quiz.results_label.text.begins_with("Ойын аяқталды!"), "game over title shown")
	check(not quiz.accepting_answers, "answers blocked after game over")

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
	for name in ["A", "B", "C", "D"]:
		locations.append({"name": name, "x": 0.5, "y": 0.5})
	if value == null:
		locations[index].erase(axis)
	else:
		locations[index][axis] = value
	return {"type": "map", "question": "Q", "locations": locations, "correct": "A"}


func _write(path: String, text: String) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
