extends "res://tasks/quiz_task.gd"

# single_choice, fill_blank and image: shoot the one correct answer out of four.


func hint() -> String:
	match question.get("type"):
		"fill_blank":
			return "Бос орынға сәйкес жауапты атыңыз"
		"image":
			return "Суретке қарап, дұрыс жауапты атыңыз"
	return ""


func _build() -> void:
	if question.get("type") == "image":
		quiz.show_image(question["image"])

	var answers: Array = question["answers"].duplicate()
	var decoys: Array = []
	if quiz.DECOY_TYPES.has(question.get("type", "single_choice")) and quiz.extra_decoys() > 0:
		decoys = quiz.decoy_answers(question, quiz.extra_decoys())
	# On the shooting range the decoys join the one row; elsewhere they stand on the top row.
	if quiz.is_range():
		answers += decoys
		decoys = []
	answers.shuffle()
	var positions: Array = quiz.row_positions(answers.size(), quiz.CHOICE_ROW_Y)

	for i in range(answers.size()):
		var target = quiz.spawn_target(answers[i], positions[i])
		target.is_correct = answers[i] == question["correct"]

	# Harder levels add fake answers on the top row.
	if not decoys.is_empty():
		var decoy_positions: Array = quiz.row_positions(decoys.size(), quiz.TOP_ROW_Y)
		for i in range(decoys.size()):
			quiz.spawn_target(decoys[i], decoy_positions[i])


func remove_wrong(count: int) -> bool:
	return _remove_wrong_targets(count)


func on_target_hit(target) -> Outcome:
	if target.is_correct:
		target.set_state(Target.State.DONE)
		return Outcome.SOLVED

	target.flash_wrong()
	reveal_correct()
	return Outcome.FAILED


func reveal_correct() -> void:
	for target in quiz.targets:
		if target.is_correct:
			target.set_state(Target.State.DONE)
