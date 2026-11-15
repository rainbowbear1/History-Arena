extends StaticBody3D

const SoldierScript := preload("res://soldier.gd")


@export var answer_text: String = "1465"
@export var is_correct: bool = true
@export var move_speed: float = 1.0
@export var move_distance: float = 0.35


enum State { NORMAL, SELECTED, DONE }

const STATE_COLORS := {
	State.SELECTED: Color(0.91, 0.78, 0.5),
	State.DONE: Color(0.42, 0.72, 0.42),
}
const WRONG_COLOR := Color(0.85, 0.3, 0.3)
const OUTLINE_COLOR := Color(0.95, 0.15, 0.1)
const SOLDIER_HEIGHT := 2.0
# Gallery plaque (Independence level): face size and the frame colours it can get.
const PLAQUE_SIZE := Vector2(2.6, 1.0)
const PLAQUE_FRAMES := [Color(0.86, 0.2, 0.18), Color(0.16, 0.45, 0.82), Color(0.1, 0.6, 0.45), Color(0.95, 0.6, 0.1), Color(0.55, 0.3, 0.75)]
const PLAQUE_FACE := Color(0.98, 0.95, 0.86)

var style := "board"
var soldier: Node3D = null
var range_rim: MeshInstance3D = null
var frame_color := PLAQUE_FRAMES[0]
var _pose_tween: Tween
var head_height := 1.1
var feet_height := -1.0
var flashing := false

var state: State = State.NORMAL
# Board colour when not highlighted (null keeps the default grey).
var base_color = null
# Multiplies sway speed; lowered by the slow_time ability.
var speed_scale: float = 1.0


@onready var answer_label: Label3D = $TargetVisual/AnswerLabel
@onready var target_mesh: MeshInstance3D = $TargetVisual/TargetMesh

func _ready() -> void:
	starting_position = position
	movement_time = randf_range(0.0, TAU)
	move_speed *= randf_range(0.8, 1.2)
	answer_label.text = answer_text


func hit() -> void:
	play_hit_animation()
	var quiz_manager = get_tree().current_scene.get_node("QuizManager")
	quiz_manager.target_hit(self)


func set_label(text: String) -> void:
	answer_label.text = text


# "soldier": a low-poly soldier standing on the ground (feet_y below the target's centre) with a
# coloured outline; "gallery": a carnival plaque riding the gallery rail (gallery.gd). Both show
# their answer in a screen-space label (answer_labels.gd) instead of on the target. "board" (default, used for map
# pins) keeps the plain board with its own 3D text.
func apply_style(new_style: String, look: Dictionary, _placard_color: Color, feet_y: float) -> void:
	if new_style == "board" or (new_style == "soldier" and look.is_empty()):
		return
	style = new_style
	target_mesh.hide()
	answer_label.hide()
	var collision: CollisionShape3D = $CollisionShape3D
	var shape := BoxShape3D.new()
	if style == "soldier":
		soldier = SoldierScript.new()
		soldier.position = Vector3(0, feet_y, 0)
		target_visual.add_child(soldier)
		soldier.build(look)
		soldier.set_motion("idle")
		# Hitbox covers the soldier's body, a little wider than it looks.
		shape.size = Vector3(1.0, SOLDIER_HEIGHT, 0.8)
		collision.position.y = feet_y + SOLDIER_HEIGHT / 2.0
		head_height = feet_y + SOLDIER_HEIGHT + 0.15
		feet_height = feet_y
	else:
		_build_plaque()
		shape.size = Vector3(PLAQUE_SIZE.x + 0.15, PLAQUE_SIZE.y + 0.15, 0.3)
		head_height = 0.0  # The label is printed on the middle of the plaque.
		feet_height = -PLAQUE_SIZE.y / 2.0
	collision.shape = shape
	_set_color(null)


# A cream plaque in a coloured frame with a small bullseye at each end, on a post down to the
# rail. The frame (range_rim) shows the state colour.
func _build_plaque() -> void:
	frame_color = PLAQUE_FRAMES.pick_random()
	_plaque_part(BoxMesh.new(), Vector3(0.08, 0.9, 0.08), Vector3(0, -PLAQUE_SIZE.y / 2.0 - 0.4, -0.08), Color(0.5, 0.52, 0.56))
	range_rim = _plaque_part(BoxMesh.new(), Vector3(PLAQUE_SIZE.x + 0.15, PLAQUE_SIZE.y + 0.15, 0.08), Vector3(0, 0, -0.04), frame_color)
	_plaque_part(BoxMesh.new(), Vector3(PLAQUE_SIZE.x, PLAQUE_SIZE.y, 0.1), Vector3.ZERO, PLAQUE_FACE)
	for side in [-1.0, 1.0]:
		for ring in [[0.2, Color(0.85, 0.15, 0.12)], [0.13, Color(0.98, 0.98, 0.95)], [0.06, Color(0.85, 0.15, 0.12)]]:
			var disc := CylinderMesh.new()
			disc.top_radius = ring[0]
			disc.bottom_radius = ring[0]
			disc.height = 0.02
			disc.radial_segments = 16
			disc.rings = 1
			var part := _plaque_part(disc, Vector3.ONE, Vector3(side * (PLAQUE_SIZE.x / 2.0 - 0.22), 0, 0.06 + (0.2 - ring[0]) * 0.1), ring[1])
			part.rotation.x = PI / 2.0


func _plaque_part(mesh: PrimitiveMesh, size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	if mesh is BoxMesh:
		mesh.size = size
	var part := MeshInstance3D.new()
	part.mesh = mesh
	part.position = at
	part.material_override = _flat(color)
	target_visual.add_child(part)
	return part


static func _flat(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	return material


# Where the floating label points: just above the soldier's head or the target's rim.
func label_anchor() -> Vector3:
	return target_visual.global_transform * Vector3(0, head_height, 0)


# Where a label hung below the target points: the soldier's feet or the bottom of the rings.
func foot_anchor() -> Vector3:
	return target_visual.global_transform * Vector3(0, feet_height, 0)


func uses_screen_label() -> bool:
	return style != "board"


# Outline and label colour: red while waiting, gold when picked, green when right, red flash when wrong.
func accent_color() -> Color:
	if flashing:
		return WRONG_COLOR
	return STATE_COLORS.get(state, OUTLINE_COLOR)


# Scales the board and its hitbox; the label keeps its on-screen text size.
func set_size(factor: float) -> void:
	target_visual.scale = Vector3.ONE * factor
	var collision: CollisionShape3D = $CollisionShape3D
	var shape: BoxShape3D = collision.shape.duplicate()
	shape.size *= factor
	collision.shape = shape
	answer_label.font_size = roundi(answer_label.font_size / factor)


func set_state(new_state: State) -> void:
	state = new_state
	_set_color(STATE_COLORS.get(state, null))
	# Gallery plaques tip back like a carnival target when answered and stand up again on a reset.
	if style == "gallery":
		_pose(Vector3(-0.75 if state == State.DONE else 0.0, 0, 0), 0.25)


func _pose(rotation_to: Vector3, seconds: float) -> void:
	if _pose_tween:
		_pose_tween.kill()
	_pose_tween = create_tween()
	_pose_tween.tween_property(target_visual, "rotation", rotation_to, seconds)


# Briefly tints the target red, then returns to its current state colour.
func flash_wrong() -> void:
	flashing = true
	_set_color(WRONG_COLOR)
	if style == "gallery":
		var wobble := create_tween()
		for angle in [0.18, -0.14, 0.08, 0.0]:
			wobble.tween_property(target_visual, "rotation:z", angle, 0.08)
	await get_tree().create_timer(0.4, false).timeout
	flashing = false
	if is_inside_tree():
		set_state(state)


func _set_color(color) -> void:
	if style == "soldier":
		soldier.set_outline(color if color != null else OUTLINE_COLOR)
		return
	if style == "gallery":
		range_rim.material_override = _flat(color if color != null else frame_color)
		return
	if color == null:
		color = base_color
	if color == null:
		target_mesh.material_override = null
		return
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	target_mesh.material_override = material

@onready var target_visual: Node3D = $TargetVisual

var hit_tween: Tween

var starting_position: Vector3
var movement_time: float = 0.0

func play_hit_animation() -> void:
	if hit_tween and hit_tween.is_running():
		hit_tween.kill()

	target_visual.position.z = 0.0

	hit_tween = create_tween()
	hit_tween.tween_property(target_visual, "position:z", -0.25, 0.08)
	hit_tween.tween_property(target_visual, "position:z", 0.0, 0.2)




func _physics_process(delta: float) -> void:
	movement_time += delta * move_speed * speed_scale

	position.x = starting_position.x + sin(movement_time) * move_distance
