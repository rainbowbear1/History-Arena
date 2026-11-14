extends StaticBody3D


@export var answer_text: String = "1465"
@export var is_correct: bool = true
@export var move_speed: float = 1.0
@export var move_distance: float = 0.35


@onready var answer_label: Label3D = $TargetVisual/AnswerLabel 

func _ready() -> void:
	starting_position = position
	movement_time = randf_range(0.0, TAU)
	move_speed *= randf_range(0.8, 1.2)


func hit() -> void:
	play_hit_animation()
	var quiz_manager = get_tree().current_scene.get_node("QuizManager")
	quiz_manager.answer_selected(is_correct)

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
	movement_time += delta * move_speed

	position.x = starting_position.x + sin(movement_time) * move_distance
