extends Control

const Abilities := preload("res://abilities.gd")

# Bars are drawn relative to these maxima.
const STAT_ROWS := [
	["hp", "HP", 150.0],
	["speed", "Жылдамдық", 8.0],
	["defense", "Қорғаныс", 40.0],
]

var selected_id: String = ""
var stat_bars := {}
var stat_values := {}

@onready var character_grid: GridContainer = %CharacterGrid
@onready var name_label: Label = %NameLabel
@onready var title_label: Label = %CharacterTitleLabel
@onready var description_label: Label = %DescriptionLabel
@onready var stats_grid: GridContainer = %Stats
@onready var weapon_label: Label = %WeaponLabel
@onready var ability_label: Label = %AbilityLabel
@onready var back_button: Button = %BackButton
@onready var choose_button: Button = %ChooseButton


func _ready() -> void:
	_build_stat_rows()

	var group := ButtonGroup.new()
	for character in CharacterDatabase.characters:
		var button := Button.new()
		button.text = character["name"]
		button.custom_minimum_size = Vector2(220, 52)
		button.toggle_mode = true
		button.button_group = group
		button.pressed.connect(_select.bind(character["id"]))
		button.focus_entered.connect(_show.bind(character["id"]))
		button.mouse_entered.connect(_show.bind(character["id"]))
		button.mouse_exited.connect(func(): _show(selected_id))
		character_grid.add_child(button)

	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://main_menu.tscn"))
	choose_button.pressed.connect(_on_choose_pressed)

	var current := CharacterDatabase.get_character(GameState.selected_character)
	if not current.is_empty():
		var index := CharacterDatabase.characters.find(current)
		var button: Button = character_grid.get_child(index)
		button.button_pressed = true
		_select(current["id"])
		button.grab_focus.call_deferred()


func _select(id: String) -> void:
	selected_id = id
	_show(id)


# Shows a character's details; leaving the hover returns to the selected one.
func _show(id: String) -> void:
	var character := CharacterDatabase.get_character(id)
	name_label.text = character["name"]
	title_label.text = character["title"]
	description_label.text = character["description"]

	for row in STAT_ROWS:
		stat_bars[row[0]].value = character[row[0]]
		stat_values[row[0]].text = str(character[row[0]])

	var weapon: Dictionary = character["weapon"]
	weapon_label.text = "Қару: %s — зақым %d, атыс аралығы %.2f с%s" % [
		weapon["name"], weapon["damage"], weapon["cooldown"], " (автомат)" if weapon["auto"] else ""]

	var ability: Dictionary = character["ability"]
	var info: Dictionary = Abilities.INFO[ability["id"]]
	ability_label.text = "Қабілет [E]: %s ×%d — %s" % [info["name"], ability["uses"], info["description"]]


func _on_choose_pressed() -> void:
	GameState.selected_character = selected_id
	get_tree().change_scene_to_file("res://level_select.tscn")


func _build_stat_rows() -> void:
	for row in STAT_ROWS:
		var label := Label.new()
		label.text = row[1]
		label.custom_minimum_size = Vector2(120, 0)
		stats_grid.add_child(label)

		var bar := ProgressBar.new()
		bar.max_value = row[2]
		bar.show_percentage = false
		bar.custom_minimum_size = Vector2(200, 18)
		bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		stats_grid.add_child(bar)
		stat_bars[row[0]] = bar

		var value := Label.new()
		value.custom_minimum_size = Vector2(40, 0)
		stats_grid.add_child(value)
		stat_values[row[0]] = value
