extends Node3D

# An arrow or bullet flying in a straight line to a point. When it arrives it calls `on_arrive`
# with the arrival point; the shooter decides whether it hit (the player may have moved away).

var target: Vector3
var speed: float = 20.0
var speed_scale: float = 1.0
var on_arrive: Callable

static var _mesh: BoxMesh
static var _material: StandardMaterial3D


func launch(from: Vector3, to: Vector3, travel_speed: float, kind: String, arrive: Callable) -> void:
	position = from
	target = to
	speed = travel_speed
	on_arrive = arrive
	if _mesh == null:
		_mesh = BoxMesh.new()
		_mesh.size = Vector3(0.05, 0.05, 0.9)
		_material = StandardMaterial3D.new()
		_material.albedo_color = Color(0.35, 0.22, 0.1)
		_material.roughness = 1.0
	var body := MeshInstance3D.new()
	body.mesh = _mesh
	body.material_override = _material
	if kind == "bullet":
		body.scale = Vector3(1.4, 1.4, 0.35)
	add_child(body)
	if not from.is_equal_approx(to):
		look_at_from_position(from, to, Vector3.UP)


func _process(delta: float) -> void:
	var step := speed * speed_scale * delta
	if position.distance_to(target) <= step:
		position = target
		if on_arrive.is_valid():
			on_arrive.call(target)
		queue_free()
		return
	position = position.move_toward(target, step)
