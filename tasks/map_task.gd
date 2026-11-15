extends "res://tasks/quiz_task.gd"

# map: numbered markers on the HUD map (map_overlay.gd); shoot the marker at the asked location.
# Each marker stands for an answer target kept out of sight under the arena, so scoring, 50/50
# and the reveal work as for any other one-answer task.

const PIN_SIZE := 0.25
const HIDDEN_AT := Vector3(0, -50, 0)


func hint() -> String:
	return tr("Картадағы дұрыс белгіні атыңыз")


func _build() -> void:
	quiz.show_map()

	var locations: Array = question["locations"].duplicate()
	locations.shuffle()

	for i in range(locations.size()):
		var location: Dictionary = locations[i]
		var target = quiz.spawn_target(location["name"], HIDDEN_AT, false, PIN_SIZE)
		target.hide()
		target.get_node("CollisionShape3D").disabled = true
		target.set_label(str(i + 1))
		target.is_correct = location["name"] == question["correct"]
		quiz.map_overlay.add_marker(target, location["x"], location["y"], i + 1)


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
	for pin in quiz.targets:
		if pin.is_correct:
			pin.set_state(Target.State.DONE)
