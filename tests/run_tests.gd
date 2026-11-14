extends SceneTree

# Headless test runner. From the project folder:
#   godot --headless --path . --import
#   godot --headless --path . --script res://tests/run_tests.gd
# Exit code is the number of failed checks (0 = all passed).

const QuestionValidator := preload("res://question_validator.gd")
const LevelDatabaseScript := preload("res://level_database.gd")
const Target := preload("res://answer_target.gd")

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
		check(quiz.questions.size() == 13, "level %d loads 13 tasks" % level)
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
	check(quiz.targets.is_empty(), "targets cleared on results")

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


func test_choice_types(samples: Dictionary) -> void:
	for type in ["fill_blank", "image"]:
		var quiz = await _start_task(samples[type])
		check(quiz.targets.size() == 4, "%s spawns 4 targets" % type)
		check(not quiz.hint_label.text.is_empty(), "%s shows a hint" % type)
		check(quiz.image_board.visible == (type == "image"), "%s image board visibility" % type)
		if type == "image":
			check(quiz.image_board.texture != null, "image task loads its picture")
		var wrong = quiz.targets.filter(func(t): return not t.is_correct)[0]
		wrong.hit()
		check(quiz.health == 90 and quiz.score == 0, "%s wrong answer costs 10 HP" % type)
		var correct = quiz.targets.filter(func(t): return t.is_correct)[0]
		check(correct.state == Target.State.DONE, "%s reveals the correct answer after a miss" % type)
		await wait(1.2)
		check(quiz.results_container.visible, "%s ends after one answer" % type)
		quiz.get_parent().queue_free()
		await process_frame


func test_chronology(question: Dictionary) -> void:
	var quiz = await _start_task(question)
	var items: Array = question["items"]
	check(quiz.targets.size() == items.size(), "chronology spawns one target per item")

	_by_text(quiz, items[0]).hit()
	check(quiz.score == 0 and quiz.health == 100 and quiz.accepting_answers, "first correct item is progress only")
	check(_by_text(quiz, items[0]).answer_label.text == "1. " + items[0], "placed item shows its order number")
	_by_text(quiz, items[0]).hit()
	check(quiz.health == 100, "re-shooting a placed item does nothing")

	_by_text(quiz, items[2]).hit()
	check(quiz.health == 90, "out-of-order item costs 10 HP")
	check(quiz.current_task.next_index == 0, "mistake restarts the sequence")
	check(_by_text(quiz, items[0]).state == Target.State.NORMAL, "mistake unlocks placed items")
	check(quiz.accepting_answers, "chronology continues after a mistake")

	for item in items:
		_by_text(quiz, item).hit()
	check(quiz.score == 100, "completing the order scores 100")
	await wait(1.2)
	check(quiz.results_container.visible, "chronology moves on when solved")
	quiz.get_parent().queue_free()
	await process_frame


func test_matching(question: Dictionary) -> void:
	var quiz = await _start_task(question)
	var pairs: Array = question["pairs"]
	check(quiz.targets.size() == pairs.size() * 2, "matching spawns two targets per pair")
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

	for i in range(pairs.size()):
		_by_text(quiz, pairs[i]["left"]).hit()
		_by_text(quiz, pairs[i]["right"]).hit()
	check(_by_text(quiz, pairs[0]["right"]).state == Target.State.DONE, "matched pair locks")
	check(quiz.score == 100, "all pairs matched scores 100")
	await wait(1.2)
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
	await wait(1.2)
	check(not quiz.map_board.visible, "map board hidden after the task")
	quiz.get_parent().queue_free()
	await process_frame


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
