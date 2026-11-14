
extends CharacterBody3D

@export var speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D
@onready var shoot_ray: RayCast3D = $Camera3D/ShootRay
@onready var quiz_manager = $"../QuizManager"

var gravity: float = 9.8

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * mouse_sensitivity)
		camera.rotate_x(-event.relative.y * mouse_sensitivity)
		camera.rotation.x = clamp(camera.rotation.x, -1.5, 1.5)
	
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
				shoot()


	
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			if get_tree().paused:
				return

			if quiz_manager.overlay_open():
				return

			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta

	if Input.is_action_pressed("jump") and is_on_floor():
		velocity.y = jump_velocity

	# Actions are bound to physical key positions, so WASD works on any keyboard layout.
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := transform.basis * Vector3(input.x, 0, input.y)

	direction.y = 0
	direction = direction.normalized()

	velocity.x = direction.x * speed
	velocity.z = direction.z * speed

	move_and_slide()


func shoot() -> void:
	play_recoil()
	shoot_ray.force_raycast_update()

	if shoot_ray.is_colliding():
		var target = shoot_ray.get_collider()

		if target.has_method("hit"):
			target.hit()
		else:
			print("Hit: ", target.name)
	else:
		print("Miss!")

@onready var weapon_holder: Node3D = $Camera3D/WeaponHolder

var recoil_tween: Tween

func play_recoil() -> void:
	if recoil_tween and recoil_tween.is_running():
		recoil_tween.kill()

	weapon_holder.position.z = -0.7

	recoil_tween = create_tween()
	recoil_tween.tween_property(
		weapon_holder,
		"position:z",
		-0.5,
		0.08
	)
	recoil_tween.tween_property(
		weapon_holder,
		"position:z",
		-0.7,
		0.18
	)
