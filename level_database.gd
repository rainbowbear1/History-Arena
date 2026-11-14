extends Node

# Loads the arena list from data/levels.json. The format is described in docs/data-format.md.

const LEVELS_FILE := "res://data/levels.json"
const INT_FIELDS := ["id", "stars", "extra_decoys", "enemies", "revive_hp", "revivals"]
const NUMBER_FIELDS := ["time_per_question", "target_speed", "pass_percent"]

var levels: Array = []


func _ready() -> void:
	load_levels()


func load_levels(path: String = LEVELS_FILE) -> void:
	levels = []

	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return

	if not json.data is Dictionary or not json.data.get("levels") is Array:
		push_error("Level file must contain a \"levels\" array: " + path)
		return

	for i in range(json.data["levels"].size()):
		var level = json.data["levels"][i]
		var problem := validate_level(level)

		if problem.is_empty() and int(level["id"]) != levels.size() + 1:
			problem = "ids must run 1, 2, 3... in order"

		if not problem.is_empty():
			push_error("Level %d in %s: %s" % [i, path, problem])
			continue

		for field in INT_FIELDS:
			level[field] = int(level[field])
		level["boss"] = level.get("boss", false)
		levels.append(level)


func get_level(id: int) -> Dictionary:
	if id >= 1 and id <= levels.size():
		return levels[id - 1]
	return {}


# A level is playable once its question file exists.
func is_playable(id: int) -> bool:
	var level := get_level(id)
	return not level.is_empty() and FileAccess.file_exists(level["question_file"])


# Returns an empty string if the level entry is usable, otherwise the reason it is not.
static func validate_level(level) -> String:
	if not level is Dictionary:
		return "entry is not an object"

	for field in INT_FIELDS:
		var value = level.get(field)
		if not (value is float or value is int) or value != floor(value):
			return "\"%s\" must be a whole number" % field

	for field in NUMBER_FIELDS:
		if not (level.get(field) is float or level.get(field) is int):
			return "\"%s\" must be a number" % field

	if not level.get("title") is String or level["title"].strip_edges().is_empty():
		return "missing \"title\""

	if not level.get("question_file") is String or not level["question_file"].begins_with("res://"):
		return "\"question_file\" must be a res:// path"

	if level.has("boss") and not level["boss"] is bool:
		return "\"boss\" must be true or false"

	if level["stars"] < 1 or level["stars"] > 5:
		return "\"stars\" must be 1 to 5"

	if level["time_per_question"] <= 0 or level["target_speed"] <= 0:
		return "\"time_per_question\" and \"target_speed\" must be above 0"

	if level["extra_decoys"] < 0 or level["enemies"] < 0 or level["revivals"] < 0:
		return "\"extra_decoys\", \"enemies\" and \"revivals\" cannot be negative"

	if level["revive_hp"] < 1 or level["revive_hp"] > 100:
		return "\"revive_hp\" must be 1 to 100"

	if level["pass_percent"] < 0 or level["pass_percent"] > 100:
		return "\"pass_percent\" must be 0 to 100"

	return ""
