extends StaticBody3D


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

var state: State = State.NORMAL
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


# Briefly tints the target red, then returns to its current state colour.
func flash_wrong() -> void:
	_set_color(WRONG_COLOR)
	await get_tree().create_timer(0.4, false).timeout
	if is_inside_tree():
		set_state(state)


func _set_color(color) -> void:
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

	target_visual.rotation_degrees.x = 0.0

	hit_tween = create_tween()
	hit_tween.tween_property(
		target_visual,
		"rotation_degrees:x",
		-12.0,
		0.1
	)
	hit_tween.tween_property(
		target_visual,
		"rotation_degrees:x",
		0.0,
		0.2
	)




func _physics_process(delta: float) -> void:
	movement_time += delta * move_speed * speed_scale

	position.x = starting_position.x + sin(movement_time) * move_distance
