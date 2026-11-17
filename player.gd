
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
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and quiz_manager.map_aiming():
		# The map overlay is open: the mouse moves its reticle, the camera stays still.
		quiz_manager.map_overlay.move_reticle(event.relative)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
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
	_update_shot_effects(delta)
	if _nocked_arrow and cooldown_left == 0.0 and not _nocked_arrow.visible:
		_nocked_arrow.show()
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
# The bow is drawn for a moment first (the shot leaves on release); the fire rate is unchanged,
# because the cooldown starts with the click.
func shoot() -> void:
	if cooldown_left > 0.0 or _drawing:
		return
	cooldown_left = weapon["cooldown"]
	shots_fired += 1
	if _nock and bow_draw_time > 0.0:
		_drawing = true
		var draw := create_tween().set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		draw.tween_property(_nock, "position:z", BOW_DRAW_DISTANCE, bow_draw_time)
		await draw.finished
		_drawing = false
		if not is_inside_tree():
			return
	_release()


func _release() -> void:
	play_recoil()
	if _nock:
		_nock.position.z = 0.0
		_nocked_arrow.hide()  # Back on the string when the bow is ready again.
	if quiz_manager.map_aiming():
		quiz_manager.shoot_map()
		return
	shoot_ray.force_raycast_update()
	var target = shoot_ray.get_collider() if shoot_ray.is_colliding() else null
	var hit_point: Vector3 = shoot_ray.get_collision_point() if target else shoot_ray.to_global(shoot_ray.target_position)
	_shot_effect(hit_point)

	# Enemies first; otherwise an answer label under the crosshair counts as a hit on its target,
	# so a player aiming at the text is never punished for missing the soldier.
	if target and target.has_method("take_hit"):
		target.take_hit(weapon["damage"])
		return
	# Gallery ducks block the shot (no penalty); wait for them to pass.
	if target and target.is_in_group("obstacle"):
		target.hit()
		return
	var labelled = quiz_manager.label_target_at(get_viewport().get_visible_rect().size / 2.0)
	if labelled:
		labelled.hit()
	elif target and target.has_method("hit"):
		target.hit()


# Only the look of a shot: a flying arrow, or a muzzle flash and a short tracer. Hits are decided
# by the ray at once, as before.
func _shot_effect(to: Vector3) -> void:
	var from: Vector3 = _muzzle.global_position if _muzzle else camera.global_position
	var scene := get_tree().current_scene
	if scene == null:
		return
	if weapon.get("model", "") == "bow":
		var arrow := Projectile.new()
		scene.add_child(arrow)
		arrow.launch(from, to, ARROW_SPEED, "arrow", func(_point): pass)
		return
	if _flash == null:
		return
	# The flash and a few tracers are built once and reused: a machine gun fires about seven times a
	# second, and new meshes and materials on every shot made the game stutter.
	_flash.scale = Vector3.ONE * randf_range(0.8, 1.2)
	_flash.show()
	_flash_left = FLASH_TIME
	var length := from.distance_to(to)
	if length < 0.5:
		return
	var tracer: MeshInstance3D = _tracers[_next_tracer]
	_next_tracer = (_next_tracer + 1) % _tracers.size()
	var up := Vector3.UP if absf((to - from).normalized().y) < 0.99 else Vector3.RIGHT
	tracer.look_at_from_position((from + to) / 2.0, to, up)
	tracer.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	tracer.scale = Vector3(1, length, 1)
	tracer.set_meta("left", TRACER_TIME)
	tracer.show()


# Muzzle flash and a small pool of tracers for the guns, made once when the weapon is built.
func _build_shot_effects() -> void:
	_flash = MeshInstance3D.new()
	var ball := SphereMesh.new()
	ball.radius = 0.07
	ball.height = 0.11
	ball.radial_segments = 6
	ball.rings = 3
	_flash.mesh = ball
	_flash.material_override = _glow(Color(1.0, 0.75, 0.3))
	_flash.hide()
	_muzzle.add_child(_flash)
	var rod := CylinderMesh.new()
	rod.top_radius = 0.012
	rod.bottom_radius = 0.012
	rod.height = 1.0
	rod.radial_segments = 4
	rod.rings = 1
	var glow := _glow(Color(1.0, 0.9, 0.55))
	for i in range(TRACER_POOL):
		var tracer := MeshInstance3D.new()
		tracer.mesh = rod
		tracer.material_override = glow
		tracer.top_level = true  # Placed in world space, not following the weapon.
		tracer.hide()
		add_child(tracer)
		_tracers.append(tracer)


# Hides the flash and tracers when their moment is over.
func _update_shot_effects(delta: float) -> void:
	if _flash and _flash.visible:
		_flash_left -= delta
		if _flash_left <= 0.0:
			_flash.hide()
	for tracer in _tracers:
		if tracer.visible:
			var left: float = tracer.get_meta("left") - delta
			tracer.set_meta("left", left)
			if left <= 0.0:
				tracer.hide()


static func _glow(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

@onready var weapon_holder: Node3D = $Camera3D/WeaponHolder

var _model: Node3D
var _muzzle: Node3D  # End of the barrel (or the arrow tip): where shots and flashes start.
var _nock: Node3D  # Bowstring and nocked arrow, pulled back while the bow is drawn.
var _nocked_arrow: Node3D
var _drawing := false
# Seconds the bow is drawn before the arrow leaves (tests set 0 to shoot at once).
var bow_draw_time := 0.12
var _flash: MeshInstance3D
var _flash_left := 0.0
var _tracers: Array = []
var _next_tracer := 0
const TRACER_POOL := 4

const Projectile := preload("res://projectile.gd")
const WOOD := Color(0.45, 0.28, 0.14)
const BOW_SEGMENTS := 10
const BOW_DRAW_DISTANCE := 0.22
const BOW_OFFSET := Vector3(-0.17, 0.08, 0.0)  # From the weapon holder (right, below the view).
const BOW_AIM_DISTANCE := 30.0
const BOW_CANT := -10.0  # Degrees of tilt around the arrow (top of the bow leans right).
const METAL := Color(0.32, 0.33, 0.36)
const BRASS := Color(0.72, 0.56, 0.25)
const ARROW_SPEED := 70.0
const FLASH_TIME := 0.05
const TRACER_TIME := 0.09
const ALONG := Vector3(PI / 2.0, 0, 0)  # Turns a rod to point along the weapon (-z).


# First-person weapon from a few primitives: a recurve bow for early eras, a flintlock musket,
# a scoped bolt-action rifle and a pan-fed machine gun for later ones.
func _build_weapon(model: String) -> void:
	if model.is_empty():
		return
	var old := weapon_holder.get_node_or_null("WeaponMesh")
	if old:
		old.queue_free()
	_model = Node3D.new()
	_model.scale = Vector3.ONE * (0.4 if model == "bow" else 0.6)
	if model == "bow":
		# Held a little nearer the middle of the view; its arrow points at the crosshair (a point far
		# down the camera's line of sight) and the bow is canted a few degrees, as archers hold it.
		_model.position = BOW_OFFSET
		var aim_from: Vector3 = weapon_holder.position + BOW_OFFSET
		var forward := (Vector3(0, 0, -BOW_AIM_DISTANCE) - aim_from).normalized()
		var facing := Basis.looking_at(forward, Vector3.UP)
		_model.basis = (Basis(forward, deg_to_rad(BOW_CANT)) * facing).scaled(Vector3.ONE * 0.4)
	weapon_holder.add_child(_model)
	_muzzle = Node3D.new()
	_model.add_child(_muzzle)
	match model:
		"bow":
			# A recurve bow: one continuous curved limb from tip to tip (segments meet end to end),
			# a leather grip, and the string with a nocked arrow, which pull back when drawn.
			var points := []
			for i in range(BOW_SEGMENTS + 1):
				var t := -1.0 + 2.0 * i / BOW_SEGMENTS
				var z := -0.14 * (1.0 - t * t)
				if absf(t) > 0.8:
					z += 0.09 * (absf(t) - 0.8) / 0.2  # Tips curl forward again (recurve).
				points.append(Vector3(0, 0.6 * t, z))
			for i in range(BOW_SEGMENTS):
				var a: Vector3 = points[i]
				var b: Vector3 = points[i + 1]
				var thickness := lerpf(0.05, 0.028, absf((a.y + b.y) / 1.2))
				_weapon_part(Vector3(thickness, a.distance_to(b) + 0.01, thickness * 1.3), (a + b) / 2.0, WOOD, Vector3(atan2(b.z - a.z, b.y - a.y), 0, 0))
			_weapon_part(Vector3(0.065, 0.16, 0.075), points[BOW_SEGMENTS / 2], Color(0.3, 0.18, 0.1), Vector3.ZERO)
			var tip: Vector3 = points[0]
			_nock = Node3D.new()
			_model.add_child(_nock)
			_nocked_arrow = Node3D.new()
			_nock.add_child(_nocked_arrow)
			_weapon_part(Vector3(0.008, 1.2, 0.008), Vector3(0, 0, tip.z), Color(0.92, 0.9, 0.82), Vector3.ZERO, false, _nock)
			_weapon_part(Vector3(0.02, 0.75, 0.0), Vector3(0.03, 0.0, tip.z - 0.33), WOOD.lightened(0.3), ALONG, true, _nocked_arrow)
			_weapon_part(Vector3(0.045, 0.07, 0.001), Vector3(0.03, 0.0, tip.z - 0.73), METAL, ALONG, true, _nocked_arrow)
			_weapon_part(Vector3(0.005, 0.05, 0.1), Vector3(0.03, 0.0, tip.z - 0.02), Color(0.85, 0.2, 0.15), Vector3.ZERO, false, _nocked_arrow)
			_muzzle.position = Vector3(0.03, 0.0, tip.z - 0.75)
		"musket":
			# Flintlock: long round barrel with a muzzle ring, full wooden stock with a curved butt,
			# lock plate and hammer, ramrod under the barrel, brass butt plate.
			_weapon_part(Vector3(0.07, 0.075, 0.95), Vector3(0, 0.0, -0.27), WOOD, Vector3.ZERO)
			_weapon_part(Vector3(0.06, 0.09, 0.2), Vector3(0, -0.03, 0.27), WOOD, Vector3(0.18, 0, 0))
			_weapon_part(Vector3(0.075, 0.18, 0.3), Vector3(0, -0.1, 0.47), WOOD.darkened(0.08), Vector3(0.28, 0, 0))
			_weapon_part(Vector3(0.078, 0.19, 0.025), Vector3(0, -0.12, 0.62), BRASS, Vector3(0.28, 0, 0))
			_weapon_part(Vector3(0.044, 1.15, 0.0), Vector3(0, 0.055, -0.38), METAL, ALONG, true)
			_weapon_part(Vector3(0.056, 0.04, 0.0), Vector3(0, 0.055, -0.94), METAL.darkened(0.3), ALONG, true)
			_weapon_part(Vector3(0.012, 0.8, 0.0), Vector3(0, 0.012, -0.42), WOOD.darkened(0.3), ALONG, true)
			_weapon_part(Vector3(0.018, 0.05, 0.13), Vector3(0.042, 0.03, 0.1), METAL, Vector3.ZERO)
			_weapon_part(Vector3(0.014, 0.07, 0.022), Vector3(0.046, 0.08, 0.14), METAL.darkened(0.2), Vector3(-0.45, 0, 0))
			_weapon_part(Vector3(0.012, 0.04, 0.09), Vector3(0, -0.06, 0.12), BRASS, Vector3.ZERO)
			_muzzle.position = Vector3(0, 0.055, -0.97)
		"rifle":
			# Bolt-action sniper rifle: round barrel, receiver with a bolt handle, box magazine,
			# telescopic sight on mounts, wooden stock.
			_weapon_part(Vector3(0.068, 0.07, 0.8), Vector3(0, 0.0, -0.2), WOOD, Vector3.ZERO)
			_weapon_part(Vector3(0.055, 0.09, 0.18), Vector3(0, -0.035, 0.27), WOOD, Vector3(0.2, 0, 0))
			_weapon_part(Vector3(0.072, 0.17, 0.28), Vector3(0, -0.1, 0.46), WOOD.darkened(0.08), Vector3(0.25, 0, 0))
			_weapon_part(Vector3(0.038, 0.95, 0.0), Vector3(0, 0.05, -0.45), METAL, ALONG, true)
			_weapon_part(Vector3(0.05, 0.05, 0.0), Vector3(0, 0.05, -0.93), METAL.darkened(0.3), ALONG, true)
			_weapon_part(Vector3(0.056, 0.24, 0.0), Vector3(0, 0.06, 0.05), METAL.darkened(0.1), ALONG, true)
			_weapon_part(Vector3(0.014, 0.08, 0.0), Vector3(0.05, 0.05, 0.13), METAL, Vector3(0, 0, PI / 2.0), true)
			_weapon_part(Vector3(0.03, 0.03, 0.03), Vector3(0.09, 0.05, 0.13), METAL.darkened(0.2), Vector3.ZERO)
			_weapon_part(Vector3(0.05, 0.07, 0.1), Vector3(0, -0.06, 0.0), METAL.darkened(0.2), Vector3.ZERO)
			_weapon_part(Vector3(0.044, 0.28, 0.0), Vector3(0, 0.14, 0.02), Color(0.12, 0.12, 0.13), ALONG, true)
			_weapon_part(Vector3(0.058, 0.035, 0.0), Vector3(0, 0.14, -0.13), Color(0.12, 0.12, 0.13), ALONG, true)
			_weapon_part(Vector3(0.054, 0.035, 0.0), Vector3(0, 0.14, 0.17), Color(0.12, 0.12, 0.13), ALONG, true)
			for z in [-0.06, 0.1]:
				_weapon_part(Vector3(0.02, 0.06, 0.03), Vector3(0, 0.1, z), METAL, Vector3.ZERO)
			_muzzle.position = Vector3(0, 0.05, -0.96)
		"mg":
			# Pan-fed light machine gun: receiver, round finned barrel jacket, a conical flash hider
			# with a round dark opening, flat drum magazine on top, pistol grip and stock.
			_weapon_part(Vector3(0.09, 0.1, 0.36), Vector3(0, 0, 0.02), METAL, Vector3.ZERO)
			_weapon_part(Vector3(0.08, 0.46, 0.0), Vector3(0, 0.0, -0.39), METAL.darkened(0.15), ALONG, true)
			for z in [-0.24, -0.36, -0.48, -0.58]:
				_weapon_part(Vector3(0.095, 0.02, 0.0), Vector3(0, 0.0, z), METAL.darkened(0.3), ALONG, true)
			_weapon_part(Vector3(0.034, 0.16, 0.0), Vector3(0, 0.0, -0.69), METAL.darkened(0.25), ALONG, true)
			_weapon_part(Vector3(0.042, 0.07, 0.06), Vector3(0, 0.0, -0.8), METAL.darkened(0.35), ALONG, true)
			_weapon_part(Vector3(0.022, 0.012, 0.0), Vector3(0, 0.0, -0.836), Color(0.03, 0.03, 0.03), ALONG, true)
			_weapon_part(Vector3(0.3, 0.035, 0.0), Vector3(0, 0.08, -0.02), METAL.lightened(0.1), Vector3.ZERO, true)
			_weapon_part(Vector3(0.1, 0.02, 0.0), Vector3(0, 0.1, -0.02), METAL, Vector3.ZERO, true)
			_weapon_part(Vector3(0.045, 0.11, 0.05), Vector3(0, -0.1, 0.12), WOOD, Vector3(0.35, 0, 0))
			_weapon_part(Vector3(0.07, 0.13, 0.28), Vector3(0, -0.04, 0.33), WOOD, Vector3(0.12, 0, 0))
			_muzzle.position = Vector3(0, 0.0, -0.86)
	if model != "bow":
		_build_shot_effects()


# A box, or a round rod (`round`: x is the diameter, y the length, and a z above 0 the diameter
# at the far end, for cones) of the given size.
func _weapon_part(size: Vector3, at: Vector3, color: Color, tilt: Vector3, round: bool = false, parent: Node3D = null) -> void:
	var part := MeshInstance3D.new()
	if round:
		var rod := CylinderMesh.new()
		rod.bottom_radius = size.x / 2.0
		rod.top_radius = size.z / 2.0 if size.z > 0.0 else size.x / 2.0
		rod.height = size.y
		rod.radial_segments = 12
		rod.rings = 1
		part.mesh = rod
	else:
		var mesh := BoxMesh.new()
		mesh.size = size
		part.mesh = mesh
	part.position = at
	part.rotation = tilt
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6 if color == METAL or color == BRASS else 1.0
	part.material_override = material
	(parent if parent else _model).add_child(part)


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
