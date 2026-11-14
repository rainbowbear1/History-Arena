extends "res://tasks/quiz_task.gd"

# map: numbered pins on the map board; shoot the pin at the asked location.

const PIN_SIZE := 0.25


func hint() -> String:
	return "Картадағы дұрыс белгіні атыңыз"


func _build() -> void:
	quiz.show_map()

	var locations: Array = question["locations"].duplicate()
	locations.shuffle()

	for i in range(locations.size()):
		var location: Dictionary = locations[i]
		var target = quiz.spawn_target(
			location["name"], quiz.map_point(location["x"], location["y"]), false, PIN_SIZE)
		target.set_label(str(i + 1))
		target.answer_label.font_size *= 2  # Single digits; make them readable from the player's spot.
		target.is_correct = location["name"] == question["correct"]


func on_target_hit(target) -> Outcome:
	if target.is_correct:
		target.set_state(Target.State.DONE)
		return Outcome.SOLVED

	target.flash_wrong()
	for pin in quiz.targets:
		if pin.is_correct:
			pin.set_state(Target.State.DONE)
	return Outcome.FAILED
