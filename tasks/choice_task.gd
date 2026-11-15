extends "res://tasks/quiz_task.gd"

# single_choice, fill_blank and image: shoot the one correct answer out of four.


func hint() -> String:
	match question.get("type"):
		"fill_blank":
			return tr("Бос орынға сәйкес жауапты атыңыз")
		"image":
			return tr("Суретке қарап, дұрыс жауапты атыңыз")
	return ""


func _build() -> void:
	if question.get("type") == "image":
		quiz.show_image(question["image"])

	# Harder levels add the task's own extra answers; every answer, real or extra, can stand
	# anywhere in the formation.
	var answers: Array = question["answers"].duplicate()
	if quiz.DECOY_TYPES.has(question.get("type", "single_choice")) and quiz.extra_decoys() > 0:
		answers += quiz.decoy_answers(question, quiz.extra_decoys())
	answers.shuffle()
	var spots: Array = quiz.answer_layout(answers.size(), question.get("type") == "image")

	for i in range(answers.size()):
		var target = quiz.spawn_target(answers[i], spots[i]["at"], true, 1.0, spots[i]["placement"])
		target.is_correct = answers[i] == question["correct"]


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
