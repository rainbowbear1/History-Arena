extends Node

var selected_level: int = 1
var selected_character: String = ""
# Each attempt asks the level's tasks in a new random order. Tests turn this off to get a fixed order.
var shuffle_questions: bool = true
