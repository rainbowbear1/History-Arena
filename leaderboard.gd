extends Control

# Online leaderboards, read from Cloud Firestore through Backend:
#   Campaign   — players by total score (sum of each level's best);
#   All-in-One — personal bests ranked by correct answers, then accuracy, then active time
#                (character score bonuses never decide the order).
# Each board shows the top players and the current player's own best and rank; a bronze, silver or
# gold cup beside a name is that player's highest BOSS trophy.

const LIMIT := 20
const ME_COLOR := Color(0.84, 0.68, 0.38)
const HEADER_COLOR := Color(0.7, 0.7, 0.7)
const BOARDS := ["campaign", "allinone"]
const ProgressStoreScript := preload("res://progress_store.gd")
const TrophyIcon := preload("res://trophy_icon.gd")

var board := "campaign"
var board_buttons := {}

@onready var status_label: Label = %StatusLabel
@onready var me_label: Label = %MeLabel
@onready var rows: GridContainer = %Rows
@onready var refresh_button: Button = %RefreshButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	_build_board_switch()
	refresh_button.pressed.connect(refresh)
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://main_menu.tscn"))
	back_button.grab_focus.call_deferred()
	refresh()


# «Науқан» / «Бәрі бірге» tabs above the table.
func _build_board_switch() -> void:
	var box := HBoxContainer.new()
	box.name = "BoardSwitch"
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 8)
	var group := ButtonGroup.new()
	for id in BOARDS:
		var button := Button.new()
		button.text = tr("Науқан") if id == "campaign" else tr("Бәрі бірге")
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = id == board
		button.custom_minimum_size = Vector2(180, 40)
		button.pressed.connect(show_board.bind(id))
		box.add_child(button)
		board_buttons[id] = button
	me_label.add_sibling(box)
	me_label.get_parent().move_child(box, me_label.get_index())


func show_board(id: String) -> void:
	board = id
	board_buttons[id].set_pressed_no_signal(true)
	refresh()


func refresh() -> void:
	for child in rows.get_children():
		child.queue_free()
	me_label.text = ""
	refresh_button.disabled = true
	status_label.text = tr("Жүктелуде...")
	var shown := board

	var result: Dictionary = await Backend.fetch_leaderboard(LIMIT, board)
	if not is_inside_tree() or shown != board:
		return
	refresh_button.disabled = not Backend.is_online_player()
	if result.has("error"):
		status_label.text = str(result["error"])
		return

	var list: Array = result.get("rows", [])
	var pool := board == "allinone"
	rows.columns = 6 if pool else 4
	if list.is_empty():
		status_label.text = tr("Әлі нәтиже жоқ. «Бәрі бірге» сынағын өтіп, бірінші болыңыз!") if pool else tr("Әлі нәтиже жоқ. Деңгейді өтіп, бірінші болыңыз!")
	else:
		status_label.text = ""
		_add_row(["#", tr("Ойыншы"), tr("Дұрыс"), tr("Дәлдік"), tr("Уақыт")] if pool else ["#", tr("Ойыншы"), tr("Ұпай")], HEADER_COLOR, 0)
	for i in list.size():
		var row: Dictionary = list[i]
		_add_row(_cells(str(i + 1), row), ME_COLOR if row.get("me", false) else Color.WHITE, int(row.get("trophy", 0)))

	var me: Dictionary = result.get("me", {})
	var pending := Backend.pending_uploads()
	if int(me.get("rank", 0)) <= 0:
		me_label.text = tr("%s · рейтингте әлі нәтиже жоқ") % Backend.display_name()
	elif pool:
		me_label.text = tr("%s · үздік нәтиже: %d дұрыс, дәлдік %s · орын: %d") % [Backend.display_name(), int(me["correct"]), _percent(me), int(me["rank"])]
	else:
		me_label.text = tr("%s · үздік жалпы ұпай: %d · орын: %d") % [Backend.display_name(), int(me["total"]), int(me["rank"])]
	if pending > 0:
		me_label.text += tr("\nЖіберілуді күтуде: %d нәтиже") % pending


func _cells(rank: String, row: Dictionary) -> Array:
	var name := str(row.get("name", "?"))
	if board != "allinone":
		return [rank, name, str(int(row.get("total", 0)))]
	var correct := "%d / %d" % [int(row.get("correct", 0)), int(row.get("answered", 0))]
	return [rank, name, correct, _percent(row), ProgressStoreScript.format_duration(int(row.get("time", 0)))]


# Accuracy is stored per thousand answered tasks.
static func _percent(row: Dictionary) -> String:
	return "%d%%" % roundi(int(row.get("acc", 0)) / 10.0)


# One table row; the trophy cup sits between the rank and the name.
func _add_row(cells: Array, color: Color, trophy: int) -> void:
	for column in cells.size():
		if column == 1:
			var cup := TrophyIcon.new()
			cup.name = "Trophy%d" % rows.get_child_count()
			cup.icon_size = 22.0
			cup.level = trophy
			rows.add_child(cup)
		var label := Label.new()
		label.text = cells[column]
		label.add_theme_color_override("font_color", color)
		label.clip_text = true
		label.custom_minimum_size.x = (300 if board == "allinone" else 380) if column == 1 else (90 if column > 1 else 50)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if column == 1 else HORIZONTAL_ALIGNMENT_RIGHT
		rows.add_child(label)
