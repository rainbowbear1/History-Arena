extends Control

# Online leaderboard: the top players by total score (sum of each level's best), plus the current
# player's personal best and rank. Data comes from Cloud Firestore through Backend.

const LIMIT := 20
const ME_COLOR := Color(0.84, 0.68, 0.38)

@onready var status_label: Label = %StatusLabel
@onready var me_label: Label = %MeLabel
@onready var rows: GridContainer = %Rows
@onready var refresh_button: Button = %RefreshButton
@onready var back_button: Button = %BackButton


func _ready() -> void:
	refresh_button.pressed.connect(refresh)
	back_button.pressed.connect(func(): get_tree().change_scene_to_file("res://main_menu.tscn"))
	back_button.grab_focus.call_deferred()
	refresh()


func refresh() -> void:
	for child in rows.get_children():
		child.queue_free()
	me_label.text = ""
	refresh_button.disabled = true
	status_label.text = tr("Жүктелуде...")

	var result: Dictionary = await Backend.fetch_leaderboard(LIMIT)
	if not is_inside_tree():
		return
	refresh_button.disabled = not Backend.is_online_player()
	if result.has("error"):
		status_label.text = str(result["error"])
		return

	var list: Array = result.get("rows", [])
	status_label.text = tr("Әлі нәтиже жоқ. Деңгейді өтіп, бірінші болыңыз!") if list.is_empty() else ""
	if not list.is_empty():
		_add_row("#", tr("Ойыншы"), tr("Ұпай"), Color(0.7, 0.7, 0.7))
	for i in list.size():
		var row: Dictionary = list[i]
		var color := ME_COLOR if row.get("me", false) else Color.WHITE
		_add_row(str(i + 1), str(row.get("name", "?")), str(int(row.get("total", 0))), color)

	var me: Dictionary = result.get("me", {})
	var pending := Backend.pending_uploads()
	if int(me.get("rank", 0)) > 0:
		me_label.text = tr("%s · үздік жалпы ұпай: %d · орын: %d") % [Backend.display_name(), int(me["total"]), int(me["rank"])]
	else:
		me_label.text = tr("%s · рейтингте әлі нәтиже жоқ") % Backend.display_name()
	if pending > 0:
		me_label.text += tr("\nЖіберілуді күтуде: %d нәтиже") % pending


func _add_row(rank: String, player: String, total: String, color: Color) -> void:
	var cells := [rank, player, total]
	for column in cells.size():
		var label := Label.new()
		label.text = cells[column]
		label.add_theme_color_override("font_color", color)
		label.clip_text = true
		label.custom_minimum_size.x = 380 if column == 1 else 70
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT if column == 1 else HORIZONTAL_ALIGNMENT_RIGHT
		rows.add_child(label)
