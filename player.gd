
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
	_build_weapon(weapon.get("model", ""))

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

var _model: Node3D

const WOOD := Color(0.45, 0.28, 0.14)
const METAL := Color(0.32, 0.33, 0.36)


# First-person weapon from a few boxes: a bow for early eras, guns for later ones.
func _build_weapon(model: String) -> void:
	if model.is_empty():
		return
	var old := weapon_holder.get_node_or_null("WeaponMesh")
	if old:
		old.queue_free()
	_model = Node3D.new()
	_model.scale = Vector3.ONE * (0.4 if model == "bow" else 0.6)
	_model.rotation_degrees = Vector3(0, 0, -12) if model == "bow" else Vector3.ZERO
	weapon_holder.add_child(_model)
	match model:
		"bow":
			_weapon_part(Vector3(0.05, 0.75, 0.05), Vector3(0, 0, 0), WOOD, Vector3(0, 0, 0))
			_weapon_part(Vector3(0.05, 0.4, 0.05), Vector3(0, 0.48, 0.08), WOOD, Vector3(-0.5, 0, 0))
			_weapon_part(Vector3(0.05, 0.4, 0.05), Vector3(0, -0.48, 0.08), WOOD, Vector3(0.5, 0, 0))
			_weapon_part(Vector3(0.01, 1.3, 0.01), Vector3(0, 0, 0.2), Color(0.9, 0.88, 0.8), Vector3.ZERO)
			_weapon_part(Vector3(0.025, 0.025, 0.8), Vector3(0, 0.02, -0.15), WOOD.lightened(0.2), Vector3.ZERO)
		"musket", "rifle":
			_weapon_part(Vector3(0.07, 0.09, 0.9 if model == "musket" else 0.8), Vector3(0, 0, -0.05), WOOD, Vector3.ZERO)
			_weapon_part(Vector3(0.04, 0.04, 0.6), Vector3(0, 0.06, -0.55), METAL, Vector3.ZERO)
			_weapon_part(Vector3(0.08, 0.16, 0.25), Vector3(0, -0.07, 0.38), WOOD.darkened(0.1), Vector3(0.3, 0, 0))
			if model == "rifle":
				_weapon_part(Vector3(0.05, 0.05, 0.22), Vector3(0, 0.12, -0.05), METAL, Vector3.ZERO)
		"mg":
			_weapon_part(Vector3(0.12, 0.12, 0.6), Vector3(0, 0, 0), METAL, Vector3.ZERO)
			_weapon_part(Vector3(0.05, 0.05, 0.6), Vector3(0, 0.02, -0.55), METAL.darkened(0.2), Vector3.ZERO)
			_weapon_part(Vector3(0.3, 0.05, 0.3), Vector3(0, 0.1, -0.05), METAL.lightened(0.1), Vector3.ZERO)
			_weapon_part(Vector3(0.08, 0.14, 0.22), Vector3(0, -0.06, 0.35), WOOD, Vector3.ZERO)


func _weapon_part(size: Vector3, at: Vector3, color: Color, tilt: Vector3) -> void:
	var part := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	part.mesh = mesh
	part.position = at
	part.rotation = tilt
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 1.0
	part.material_override = material
	_model.add_child(part)

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
