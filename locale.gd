extends Node

# Language of the game: Kazakh (default) or English, chosen in the main menu and kept between
# sessions. Interface text uses Godot's TranslationServer: scene texts translate automatically
# and code wraps its strings in tr(); the English strings live in locale/en.json, keyed by the
# Kazakh text. Question files carry their English text in each task's "en" block, and
# localize_question() swaps it in by position, so task ids and the correct answer are shared by
# both languages and the gameplay code never needs to know the language.

signal changed

const LANGUAGES := ["kk", "en"]
const STRINGS := {"en": "res://locale/en.json"}
const SETTINGS_FILE := "user://settings.cfg"

var language := "kk"
var settings_path := SETTINGS_FILE


func _ready() -> void:
	for code in STRINGS:
		var translation := Translation.new()
		translation.locale = code
		var data = JSON.parse_string(FileAccess.get_file_as_string(STRINGS[code]))
		if data is Dictionary:
			for key in data:
				translation.add_message(key, data[key])
		TranslationServer.add_translation(translation)
	var settings := ConfigFile.new()
	settings.load(settings_path)
	_apply(settings.get_value("game", "language", "kk"))


func set_language(code: String) -> void:
	if not LANGUAGES.has(code) or code == language:
		return
	_apply(code)
	var settings := ConfigFile.new()
	settings.load(settings_path)
	settings.set_value("game", "language", language)
	settings.save(settings_path)
	changed.emit()


func _apply(code: String) -> void:
	language = code if LANGUAGES.has(code) else "kk"
	TranslationServer.set_locale(language)


func is_english() -> bool:
	return language == "en"


# The task in the current language: a copy with the English fields swapped in by position (the
# correct answer and map name follow their Kazakh position). Kazakh, or a task without "en",
# is returned as it is.
func localize_question(question: Dictionary) -> Dictionary:
	if language != "en" or not question.has("en"):
		return question
	var en: Dictionary = question["en"]
	var result := question.duplicate(true)
	result["question"] = en["question"]
	if question.has("answers"):
		result["answers"] = en["answers"].duplicate()
		result["correct"] = en["answers"][question["answers"].find(question["correct"])]
	if question.has("extra_answers"):
		result["extra_answers"] = en["extra_answers"].duplicate()
	if question.has("pairs"):
		result["pairs"] = en["pairs"].duplicate(true)
	if question.has("items"):
		result["items"] = en["items"].duplicate()
	if question.has("locations"):
		for i in range(question["locations"].size()):
			result["locations"][i]["name"] = en["locations"][i]
			if question["locations"][i]["name"] == question.get("correct"):
				result["correct"] = en["locations"][i]
	return result
