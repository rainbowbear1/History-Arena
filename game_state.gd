extends Node

var selected_level: int = 1
var selected_character: String = ""
# Each attempt asks the level's tasks in a new random order. Tests turn this off to get a fixed order.
var shuffle_questions: bool = true
# Ids of the last medical-help questions asked (this session, across restarts), so one is not
# offered again right after it was failed.
const RECENT_MEDICAL := 12
var recent_medical: Array = []


func remember_medical(id) -> void:
	recent_medical.erase(id)
	recent_medical.append(id)
	if recent_medical.size() > RECENT_MEDICAL:
		recent_medical.pop_front()
