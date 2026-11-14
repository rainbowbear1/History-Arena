extends RefCounted

# Loads and checks question files. The format is described in docs/data-format.md.

const TYPES := ["single_choice", "fill_blank", "matching", "chronology", "map", "image"]
const DEFAULT_TYPE := "single_choice"
const OPTION_COUNT := 4
const BLANK := "___"
# Smallest distance between two map locations (0–1 map units) so their pins don't overlap.
const MIN_PIN_GAP := 0.08


static func get_type(question: Dictionary) -> String:
	return question.get("type", DEFAULT_TYPE)


# Returns {"questions": Array, "errors": Array[String]}. Invalid entries are left out
# of "questions" and described in "errors"; a file-level problem leaves "questions" empty.
static func load_file(path: String) -> Dictionary:
	var result := {"questions": [], "errors": []}

	if not FileAccess.file_exists(path):
		result.errors.append("Question file not found: " + path)
		return result

	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		result.errors.append("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return result

	if not json.data is Array:
		result.errors.append("Question file must contain an array: " + path)
		return result

	var seen_ids := {}
	for i in range(json.data.size()):
		var question = json.data[i]
		var problem := validate(question)

		if problem.is_empty() and question.has("id"):
			if seen_ids.has(question["id"]):
				problem = "duplicate id \"%s\"" % question["id"]
			seen_ids[question["id"]] = true

		if problem.is_empty():
			result.questions.append(question)
		else:
			result.errors.append("Question %d in %s: %s" % [i, path, problem])

	return result


# Returns an empty string if the question is usable, otherwise the reason it is not.
static func validate(question) -> String:
	if not question is Dictionary:
		return "entry is not an object"

	if question.has("id") and not _is_text(question["id"]):
		return "\"id\" must be a non-empty string"

	if question.has("explanation") and not question["explanation"] is String:
		return "\"explanation\" must be a string"

	if not _is_text(question.get("question")):
		return "missing or empty \"question\" text"

	var type = question.get("type", DEFAULT_TYPE)
	if not type is String or not TYPES.has(type):
		return "unknown type \"%s\"" % str(type)

	match type:
		"single_choice":
			return _check_options(question)
		"fill_blank":
			if not question["question"].contains(BLANK):
				return "fill_blank question must contain \"%s\"" % BLANK
			return _check_options(question)
		"image":
			if not _is_text(question.get("image")):
				return "missing \"image\" path"
			if not ResourceLoader.exists(question["image"]):
				return "image not found: " + str(question["image"])
			return _check_options(question)
		"matching":
			return _check_matching(question)
		"chronology":
			return _check_chronology(question)
		"map":
			return _check_map(question)

	return ""


static func _check_options(question: Dictionary) -> String:
	if not question.get("answers") is Array:
		return "missing \"answers\" array"

	var answers: Array = question["answers"]
	if answers.size() != OPTION_COUNT:
		return "expected %d answers, got %d" % [OPTION_COUNT, answers.size()]

	for answer in answers:
		if not _is_text(answer):
			return "every answer must be a non-empty string"

	if _has_duplicates(answers):
		return "answers must be unique"

	if not question.get("correct") is String:
		return "missing \"correct\" answer"

	if not answers.has(question["correct"]):
		return "\"correct\" answer is not one of the answers"

	return ""


static func _check_matching(question: Dictionary) -> String:
	if not question.get("pairs") is Array:
		return "missing \"pairs\" array"

	var pairs: Array = question["pairs"]
	if pairs.size() < 2 or pairs.size() > 4:
		return "matching needs 2 to 4 pairs, got %d" % pairs.size()

	var lefts := []
	var rights := []
	for pair in pairs:
		if not pair is Dictionary or not _is_text(pair.get("left")) or not _is_text(pair.get("right")):
			return "every pair needs non-empty \"left\" and \"right\" text"
		lefts.append(pair["left"])
		rights.append(pair["right"])

	if _has_duplicates(lefts) or _has_duplicates(rights):
		return "pair sides must be unique"

	return ""


static func _check_chronology(question: Dictionary) -> String:
	if not question.get("items") is Array:
		return "missing \"items\" array"

	var items: Array = question["items"]
	if items.size() < 3 or items.size() > 5:
		return "chronology needs 3 to 5 items, got %d" % items.size()

	for item in items:
		if not _is_text(item):
			return "every item must be a non-empty string"

	if _has_duplicates(items):
		return "items must be unique"

	return ""


static func _check_map(question: Dictionary) -> String:
	if not question.get("locations") is Array:
		return "missing \"locations\" array"

	var locations: Array = question["locations"]
	if locations.size() != OPTION_COUNT:
		return "expected %d locations, got %d" % [OPTION_COUNT, locations.size()]

	var names := []
	for location in locations:
		if not location is Dictionary or not _is_text(location.get("name")):
			return "every location needs a non-empty \"name\""
		for axis in ["x", "y"]:
			var value = location.get(axis)
			if not (value is float or value is int) or value < 0.0 or value > 1.0:
				return "location \"%s\" needs \"%s\" between 0 and 1" % [location["name"], axis]
		names.append(location["name"])

	if _has_duplicates(names):
		return "location names must be unique"

	for i in range(locations.size()):
		for j in range(i + 1, locations.size()):
			var a := Vector2(locations[i]["x"], locations[i]["y"])
			var b := Vector2(locations[j]["x"], locations[j]["y"])
			if a.distance_to(b) < MIN_PIN_GAP:
				return "locations \"%s\" and \"%s\" are too close together" % [names[i], names[j]]

	if not question.get("correct") is String or not names.has(question["correct"]):
		return "\"correct\" must be one of the location names"

	return ""


static func _is_text(value) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func _has_duplicates(values: Array) -> bool:
	var seen := {}
	for value in values:
		if seen.has(value):
			return true
		seen[value] = true
	return false
