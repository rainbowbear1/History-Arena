extends Node

# Loads the playable characters from data/characters.json. The format is described in docs/data-format.md.

const Abilities := preload("res://abilities.gd")
const CHARACTERS_FILE := "res://data/characters.json"

var characters: Array = []


func _ready() -> void:
	load_characters()


func load_characters(path: String = CHARACTERS_FILE) -> void:
	characters = []

	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		push_error("JSON error in %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return

	if not json.data is Dictionary or not json.data.get("characters") is Array:
		push_error("Character file must contain a \"characters\" array: " + path)
		return

	var seen_ids := {}
	for i in range(json.data["characters"].size()):
		var character = json.data["characters"][i]
		var problem := validate_character(character)

		if problem.is_empty() and seen_ids.has(character["id"]):
			problem = "duplicate id \"%s\"" % character["id"]

		if not problem.is_empty():
			push_error("Character %d in %s: %s" % [i, path, problem])
			continue

		seen_ids[character["id"]] = true
		character["hp"] = int(character["hp"])
		character["defense"] = int(character["defense"])
		character["weapon"]["damage"] = int(character["weapon"]["damage"])
		character["weapon"]["auto"] = character["weapon"].get("auto", false)
		character["ability"]["uses"] = int(character["ability"]["uses"])
		characters.append(character)


# Returns the character with this id, or the first character if there is none.
func get_character(id: String) -> Dictionary:
	for character in characters:
		if character["id"] == id:
			return character
	return characters[0] if not characters.is_empty() else {}


# Returns an empty string if the character entry is usable, otherwise the reason it is not.
static func validate_character(character) -> String:
	if not character is Dictionary:
		return "entry is not an object"

	for field in ["id", "name", "title", "description"]:
		if not character.get(field) is String or character[field].strip_edges().is_empty():
			return "missing \"%s\"" % field

	if not _is_number(character.get("hp")) or character["hp"] != floor(character["hp"]) or character["hp"] < 50 or character["hp"] > 200:
		return "\"hp\" must be a whole number from 50 to 200"

	if not _is_number(character.get("speed")) or character["speed"] < 3 or character["speed"] > 10:
		return "\"speed\" must be from 3 to 10"

	if not _is_number(character.get("defense")) or character["defense"] != floor(character["defense"]) or character["defense"] < 0 or character["defense"] > 60:
		return "\"defense\" must be a whole number from 0 to 60"

	var weapon = character.get("weapon")
	if not weapon is Dictionary or not weapon.get("name") is String or weapon["name"].strip_edges().is_empty():
		return "\"weapon\" needs a \"name\""
	if not _is_number(weapon.get("cooldown")) or weapon["cooldown"] <= 0:
		return "\"weapon.cooldown\" must be above 0"
	if not _is_number(weapon.get("damage")) or weapon["damage"] != floor(weapon["damage"]) or weapon["damage"] < 1:
		return "\"weapon.damage\" must be a whole number of at least 1"
	if weapon.has("model") and not weapon["model"] in ["bow", "musket", "rifle", "mg"]:
		return "\"weapon.model\" must be bow, musket, rifle or mg"
	if weapon.has("auto") and not weapon["auto"] is bool:
		return "\"weapon.auto\" must be true or false"

	var ability = character.get("ability")
	if not ability is Dictionary or not Abilities.INFO.has(ability.get("id")):
		return "\"ability.id\" must be one of " + ", ".join(Abilities.INFO.keys())
	if not _is_number(ability.get("uses")) or ability["uses"] != floor(ability["uses"]) or ability["uses"] < 1:
		return "\"ability.uses\" must be a whole number of at least 1"

	return ""


static func _is_number(value) -> bool:
	return value is float or value is int
