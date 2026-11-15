extends "res://tasks/quiz_task.gd"

# chronology: shoot the events from earliest to latest. A wrong pick costs HP
# and the sequence starts over.

var next_index: int = 0


func hint() -> String:
	return tr("Оқиғаларды ең ертесінен бастап ретімен атыңыз")


func _build() -> void:
	var items: Array = question["items"].duplicate()
	progress_name = "Ретімен қойылды"
	total = items.size()
	items.shuffle()
	var spots: Array = quiz.answer_layout(items.size())

	for i in range(items.size()):
		quiz.spawn_target(items[i], spots[i]["at"], true, 1.0, spots[i]["placement"])


func on_target_hit(target) -> Outcome:
	if target.state == Target.State.DONE:
		return Outcome.NONE

	var items: Array = question["items"]
	if target.answer_text != items[next_index]:
		target.flash_wrong()
		_reset()
		message = tr("Қате рет! Басынан бастаңыз")
		return Outcome.MISTAKE

	next_index += 1
	done = next_index
	target.set_state(Target.State.DONE)
	target.set_label("%d. %s" % [next_index, target.answer_text])

	if next_index == items.size():
		return Outcome.SOLVED
	return Outcome.PROGRESS


func _reset() -> void:
	next_index = 0
	done = 0
	for target in quiz.targets:
		target.set_state(Target.State.NORMAL)
		target.set_label(target.answer_text)
