
extends CharacterBody3D

@export var speed: float = 6.0
@export var jump_velocity: float = 4.5
@export var mouse_sensitivity: float = 0.002

@onready var camera: Camera3D = $Camera3D
@onready var shoot_ray: RayCast3D = $Camera3D/ShootRay
@onready var quiz_manager = $"../QuizManager"

var gravity: float = 9.8

# The chosen character's weapon (see data/characters.json).
var weapon: Dictionary = {"name": "", "cooldown": 0.3, "damage": 1, "auto": false}
var cooldown_left: float = 0.0
var shots_fired: int = 0

func _ready() -> void:
	var character := CharacterDatabase.get_character(GameState.selected_character)
	if not character.is_empty():
		speed = character["speed"]
		weapon = character["weapon"]

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

	if event.is_action_pressed("ability"):
		quiz_manager.use_ability()


	
	if event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			if get_tree().paused:
				return

			if quiz_manager.overlay_open():
				return

			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _physics_process(delta: float) -> void:
	cooldown_left = maxf(cooldown_left - delta, 0.0)
	if weapon["auto"] and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		shoot()

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


# Fires once if the weapon is ready. Enemies take the weapon's damage; answer targets are hit.
func shoot() -> void:
	if cooldown_left > 0.0:
		return
	cooldown_left = weapon["cooldown"]
	shots_fired += 1

	play_recoil()
	shoot_ray.force_raycast_update()

	if shoot_ray.is_colliding():
		var target = shoot_ray.get_collider()

		if target.has_method("take_hit"):
			target.take_hit(weapon["damage"])
		elif target.has_method("hit"):
			target.hit()

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
