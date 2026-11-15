extends "res://tasks/quiz_task.gd"

# matching: left items on the top row, right items on the bottom row. Shoot a
# top item to select it, then its partner below. A wrong partner costs HP.

var pair_of := {}  # target -> pair index
var top_row := {}  # targets on the top (left) row
var selected = null


func hint() -> String:
	return tr("1) Жоғарғы қатардан біреуін атыңыз   2) Оның жұбын төменгі қатардан атыңыз")


func _build() -> void:
	var pairs: Array = question["pairs"]
	progress_name = "Табылған жұптар"
	total = pairs.size()
	var order := range(pairs.size())

	var layout: Dictionary = quiz.matching_layout(pairs.size())
	order.shuffle()
	for i in range(order.size()):
		var spot: Dictionary = layout["top"][i]
		var target = quiz.spawn_target(pairs[order[i]]["left"], spot["at"], true, 1.0, spot["placement"])
		pair_of[target] = order[i]
		top_row[target] = true

	order.shuffle()
	for i in range(order.size()):
		var spot: Dictionary = layout["bottom"][i]
		var target = quiz.spawn_target(pairs[order[i]]["right"], spot["at"], true, 1.0, spot["placement"])
		pair_of[target] = order[i]


func on_target_hit(target) -> Outcome:
	if target.state == Target.State.DONE:
		return Outcome.NONE

	if top_row.has(target):
		if selected:
			selected.set_state(Target.State.NORMAL)
		selected = target
		target.set_state(Target.State.SELECTED)
		return Outcome.NONE

	if selected == null:
		message = tr("Алдымен жоғарғы қатардан таңдаңыз")
		return Outcome.NONE

	if pair_of[selected] != pair_of[target]:
		target.flash_wrong()
		selected.set_state(Target.State.NORMAL)
		selected = null
		message = tr("Қате жұп!")
		return Outcome.MISTAKE

	selected.set_state(Target.State.DONE)
	target.set_state(Target.State.DONE)
	selected = null
	done += 1

	if done == total:
		return Outcome.SOLVED
	return Outcome.PROGRESS
