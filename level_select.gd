
extends Control

const StarRow := preload("res://star_row.gd")
const QuestionPools := preload("res://question_pools.gd")

@onready var level_grid: GridContainer = $CenterContainer/VBoxContainer/LevelGrid
@onready var level_info_label: Label = $CenterContainer/VBoxContainer/LevelInfoLabel
@onready var back_button: Button = $CenterContainer/VBoxContainer/BackButton

var total_label: Label


func _ready() -> void:
	# Current total (sum of each level's best score), which is what opens later levels.
	total_label = Label.new()
	total_label.text = tr("Жалпы ұпай: %d") % ProgressStore.total_score()
	total_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	total_label.add_theme_font_size_override("font_size", 22)
	level_grid.get_parent().add_child(total_label)
	level_grid.get_parent().move_child(total_label, level_grid.get_index())

	for level in LevelDatabase.levels:
		var level_number: int = level["id"]
		var button := Button.new()
		button.custom_minimum_size = Vector2(90, 90)
		button.text = str(level_number)
		level_grid.add_child(button)

		var earned := StarRow.new()
		earned.star_size = 18.0
		earned.stars = ProgressStore.level_result(level_number)["stars"]
		earned.position = Vector2(0, 64)
		earned.size = Vector2(90, 20)
		button.add_child(earned)

		if LevelDatabase.is_playable(level_number) and ProgressStore.is_unlocked(level_number):
			button.focus_mode = Control.FOCUS_ALL
			button.pressed.connect(_on_level_selected.bind(level_number))
			button.focus_entered.connect(_show_level_info.bind(level_number))
		else:
			button.disabled = true
			button.focus_mode = Control.FOCUS_NONE
			if LevelDatabase.is_playable(level_number):
				# Locked: show the total score that opens it.
				button.text = "%d\n%d" % [level_number, ProgressStore.unlock_score(level_number)]
				button.add_theme_font_size_override("font_size", 15)
				button.tooltip_text = tr("Ашу үшін жалпы ұпай: %d") % ProgressStore.unlock_score(level_number)

		button.mouse_entered.connect(_show_level_info.bind(level_number))

	_add_boss_tile()
	_add_all_in_one_tile()
	back_button.pressed.connect(_on_back_pressed)

	if level_grid.get_child_count() > 0:
		level_grid.get_child(0).grab_focus.call_deferred()
		_show_level_info(1)




# The BOSS tile, centred under the second row (beneath level 8), once level 10 has been passed.
func _add_boss_tile() -> void:
	if not ProgressStore.is_boss_unlocked() or not LevelDatabase.is_playable(LevelDatabase.BOSS_ID):
		return
	var row := CenterContainer.new()
	row.name = "BossRow"
	var tile := Button.new()
	tile.name = "BossTile"
	tile.text = "BOSS"
	tile.custom_minimum_size = Vector2(90, 90)
	tile.focus_mode = Control.FOCUS_ALL
	tile.theme_type_variation = &"BossButton"
	tile.add_theme_color_override("font_color", Color(1, 0.92, 0.85))
	tile.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.62, 0.12, 0.1)
	style.set_corner_radius_all(8)
	style.set_border_width_all(3)
	style.border_color = Color(0.95, 0.75, 0.3)
	tile.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.75, 0.16, 0.12)
	tile.add_theme_stylebox_override("hover", hover)
	tile.add_theme_stylebox_override("focus", hover)
	var best := StarRow.new()
	best.star_size = 18.0
	best.stars = 3 if ProgressStore.boss["defeated"] else 0
	best.position = Vector2(0, 64)
	best.size = Vector2(90, 20)
	tile.add_child(best)
	tile.pressed.connect(_on_level_selected.bind(LevelDatabase.BOSS_ID))
	tile.focus_entered.connect(_show_level_info.bind(LevelDatabase.BOSS_ID))
	tile.mouse_entered.connect(_show_level_info.bind(LevelDatabase.BOSS_ID))
	row.add_child(tile)
	level_grid.add_sibling(row)


# All-in-One, a wide gold-edged tile in its own row under the BOSS, once the BOSS has been defeated.
func _add_all_in_one_tile() -> void:
	var id := LevelDatabase.ALL_IN_ONE_ID
	if not ProgressStore.is_all_in_one_unlocked() or not LevelDatabase.is_playable(id):
		return
	var row := CenterContainer.new()
	row.name = "AllInOneRow"
	var tile := Button.new()
	tile.name = "AllInOneTile"
	tile.text = tr("Бәрі бірге")
	tile.custom_minimum_size = Vector2(240, 52)
	tile.focus_mode = Control.FOCUS_ALL
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.13, 0.2, 0.3)
	style.set_corner_radius_all(8)
	style.set_border_width_all(3)
	style.border_color = Color(0.84, 0.68, 0.38)
	tile.add_theme_stylebox_override("normal", style)
	var hover := style.duplicate()
	hover.bg_color = Color(0.19, 0.28, 0.4)
	tile.add_theme_stylebox_override("hover", hover)
	tile.add_theme_stylebox_override("focus", hover)
	tile.pressed.connect(_on_level_selected.bind(id))
	tile.focus_entered.connect(_show_level_info.bind(id))
	tile.mouse_entered.connect(_show_level_info.bind(id))
	row.add_child(tile)
	var boss_row := level_grid.get_parent().get_node_or_null("BossRow")
	(boss_row if boss_row else level_grid).add_sibling(row)


func _show_level_info(level_number: int) -> void:
	if level_number == LevelDatabase.ALL_IN_ONE_ID:
		var best: Dictionary = ProgressStore.all_in_one_best
		var lines := [tr("Бәрі бірге: барлық %d тапсырма кездейсоқ ретпен") % QuestionPools.all_in_one(QuestionPools.load_banks(LevelDatabase.levels), false).size(),
			tr("Денсаулық біткенде немесе барлық сұрақ біткенде аяқталады; [H] аптечкалар")]
		if not best.is_empty():
			lines.append(tr("Үздік нәтиже: %d дұрыс жауап") % int(best["correct"]))
		level_info_label.text = "\n".join(lines)
		return
	if level_number == LevelDatabase.BOSS_ID:
		var lines := [tr("BOSS: бүкіл тарих бойынша %d тапсырма") % LevelDatabase.boss.get("questions", 50),
			tr("Барған сайын қиындайды; [H] аптечкалар"), tr("Үздік ұпай: %d") % ProgressStore.boss["best_score"]]
		level_info_label.text = "\n".join(lines)
		return
	var level := LevelDatabase.get_level(level_number)
	var difficulty := "BOSS" if level["boss"] else "%d/5" % level["stars"]
	var text: String = tr("%d. %s\nҚиындық: %s") % [level_number, tr(level["title"]), difficulty]

	if not LevelDatabase.is_playable(level_number):
		text += tr(" · дайындалуда")
	elif not ProgressStore.is_unlocked(level_number):
		var needed := ProgressStore.unlock_score(level_number)
		text += tr("\nЖабық: жалпы ұпай %d керек (қазір %d, тағы %d)") % [needed, ProgressStore.total_score(), needed - ProgressStore.total_score()]
	else:
		var result := ProgressStore.level_result(level_number)
		if result["attempts"] > 0:
			text += tr("\nҮздік ұпай: %d") % result["best_score"]

	level_info_label.text = text


func _on_level_selected(level_number: int) -> void:
	GameState.selected_level = level_number
	get_tree().change_scene_to_file("res://character_select.tscn")




func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://main_menu.tscn")
