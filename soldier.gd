extends Node3D

# A low-poly soldier built from a handful of primitive meshes (feet at y = 0, about 1.9 m tall).
# The look comes from data/themes.json: coat/pants/skin colours, headgear, weapon, shield, robe.
# Meshes and materials are shared between all soldiers, so a crowd stays cheap in the browser.

const HEADGEAR := ["none", "pointed", "fur", "helmet", "turban", "cap", "steel_helmet", "kalpak"]
const WEAPONS := ["none", "bow", "spear", "sword", "rifle"]

# Background motion: "idle" sways, "march" walks back and forth, "fight" lunges at a partner;
# "aim" raises the weapon arm, "march_in_place" swings the arms while the body is moved elsewhere.
var motion: String = "idle"
var motion_speed: float = 1.0
var motion_range: float = 3.0
var speed_scale: float = 1.0
var _time: float = 0.0
var _origin: Vector3
var _body: Node3D
var _arm: Node3D

static var _materials := {}
static var _meshes := {}
static var _outlines := {}
const OUTLINE_SHADER := preload("res://outline.gdshader")


func build(look: Dictionary) -> void:
	_body = Node3D.new()
	add_child(_body)
	var coat := _color(look.get("coat", "#7a5230"))
	var pants := _color(look.get("pants", "#3d2b1f"))
	var skin := _color(look.get("skin", "#c99a6e"))
	var trim := _color(look.get("trim", look.get("headgear_color", "#c9a24a")))

	_part("box", Vector3(0.36, 0.8, 0.24), Vector3(0, 0.4, 0), pants)
	if look.get("robe", false):
		_part("robe", Vector3.ONE, Vector3(0, 0.62, 0), coat)
	_part("box", Vector3(0.52, 0.62, 0.3), Vector3(0, 1.1, 0), coat)
	_part("box", Vector3(0.54, 0.08, 0.32), Vector3(0, 0.84, 0), trim)
	_part("box", Vector3(0.15, 0.56, 0.15), Vector3(-0.34, 1.1, 0), coat)
	_arm = Node3D.new()
	_arm.position = Vector3(0.34, 1.36, 0)
	_body.add_child(_arm)
	_part("box", Vector3(0.15, 0.56, 0.15), Vector3(0, -0.26, 0), coat, _arm)
	_part("box", Vector3(0.3, 0.3, 0.3), Vector3(0, 1.58, 0), skin)
	_headgear(look.get("headgear", "none"), _color(look.get("headgear_color", "#6b4a2b")))
	_weapon(look.get("weapon", "none"), _color(look.get("weapon_color", "#5a3d22")))
	if look.get("shield", false):
		_part("shield", Vector3.ONE, Vector3(-0.44, 1.05, -0.05), trim)
	_origin = position


# Coloured rim around the whole body (answer targets). Materials are shared per colour.
func set_outline(color: Color) -> void:
	var key := color.to_html()
	if not _outlines.has(key):
		var material := ShaderMaterial.new()
		material.shader = OUTLINE_SHADER
		material.set_shader_parameter("color", color)
		_outlines[key] = material
	for part in find_children("*", "MeshInstance3D", true, false):
		part.material_overlay = _outlines[key]


func set_motion(kind: String, speed: float = 1.0, distance: float = 3.0) -> void:
	motion = kind
	motion_speed = speed
	motion_range = distance
	_origin = position
	_time = randf() * TAU


func _process(delta: float) -> void:
	if _body == null or motion == "none":
		return
	_time += delta * motion_speed * speed_scale
	match motion:
		"idle":
			_body.position.y = absf(sin(_time * 1.3)) * 0.03
			_arm.rotation.x = sin(_time) * 0.15
		"march":
			position.x = _origin.x + sin(_time * 0.35) * motion_range
			_body.position.y = absf(sin(_time * 4.0)) * 0.08
			rotation.y = PI / 2.0 if cos(_time * 0.35) > 0.0 else -PI / 2.0
		"fight":
			position.z = _origin.z + sin(_time * 2.2) * 0.35
			_arm.rotation.x = -absf(sin(_time * 2.2)) * 1.6
		"aim":
			_arm.rotation.x = lerpf(_arm.rotation.x, -1.5, minf(1.0, delta * 8.0))
		"march_in_place":
			_body.position.y = absf(sin(_time * 4.0)) * 0.08
			_arm.rotation.x = sin(_time * 4.0) * 0.5


func _headgear(kind: String, color: Color) -> void:
	match kind:
		"pointed":
			_part("cone", Vector3(0.36, 0.62, 0.36), Vector3(0, 2.02, 0), color)
		"fur":
			_part("box", Vector3(0.38, 0.12, 0.38), Vector3(0, 1.76, 0), color.darkened(0.25))
			_part("cone", Vector3(0.3, 0.22, 0.3), Vector3(0, 1.92, 0), color)
		"helmet":
			_part("cone", Vector3(0.36, 0.34, 0.36), Vector3(0, 1.88, 0), color)
		"turban":
			_part("sphere", Vector3(0.38, 0.24, 0.38), Vector3(0, 1.78, 0), color)
		"cap":
			_part("box", Vector3(0.32, 0.1, 0.34), Vector3(0, 1.77, 0), color)
		"steel_helmet":
			_part("sphere", Vector3(0.4, 0.26, 0.42), Vector3(0, 1.76, 0), color)
		"kalpak":
			_part("box", Vector3(0.34, 0.08, 0.34), Vector3(0, 1.75, 0), color.lightened(0.3))
			_part("cone", Vector3(0.3, 0.3, 0.3), Vector3(0, 1.93, 0), color)


func _weapon(kind: String, color: Color) -> void:
	match kind:
		"bow":
			_part("box", Vector3(0.05, 1.1, 0.05), Vector3(0.06, -0.2, -0.16), color, _arm)
			_part("box", Vector3(0.02, 1.0, 0.02), Vector3(0.06, -0.2, -0.04), Color(0.9, 0.88, 0.8), _arm)
		"spear":
			_part("box", Vector3(0.05, 2.2, 0.05), Vector3(0.05, 0.1, -0.12), color, _arm)
			_part("cone", Vector3(0.1, 0.22, 0.1), Vector3(0.05, 1.3, -0.12), Color(0.75, 0.75, 0.78), _arm)
		"sword":
			_part("box", Vector3(0.06, 0.8, 0.03), Vector3(0.0, -0.75, -0.08), Color(0.78, 0.78, 0.82), _arm)
		"rifle":
			_part("box", Vector3(0.06, 0.08, 1.1), Vector3(0.0, -0.45, -0.35), color, _arm)


func _part(shape: String, size: Vector3, at: Vector3, color: Color, parent: Node3D = null) -> void:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _mesh(shape)
	mesh_instance.scale = size if shape != "robe" and shape != "shield" else Vector3.ONE
	mesh_instance.position = at
	if shape == "shield":
		mesh_instance.rotation.x = PI / 2.0
	mesh_instance.material_override = _material(color)
	(parent if parent else _body).add_child(mesh_instance)


static func _mesh(shape: String) -> Mesh:
	if _meshes.has(shape):
		return _meshes[shape]
	var mesh: Mesh
	match shape:
		"box":
			mesh = BoxMesh.new()
		"cone":
			var cone := CylinderMesh.new()
			cone.top_radius = 0.0
			cone.bottom_radius = 0.5
			cone.height = 1.0
			cone.radial_segments = 6
			cone.rings = 1
			mesh = cone
		"sphere":
			var sphere := SphereMesh.new()
			sphere.radius = 0.5
			sphere.height = 1.0
			sphere.radial_segments = 8
			sphere.rings = 4
			mesh = sphere
		"robe":
			var robe := CylinderMesh.new()
			robe.top_radius = 0.26
			robe.bottom_radius = 0.34
			robe.height = 0.5
			robe.radial_segments = 6
			robe.rings = 1
			mesh = robe
		"shield":
			var shield := CylinderMesh.new()
			shield.top_radius = 0.26
			shield.bottom_radius = 0.26
			shield.height = 0.05
			shield.radial_segments = 8
			shield.rings = 1
			mesh = shield
	_meshes[shape] = mesh
	return mesh


static func _material(color: Color) -> StandardMaterial3D:
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		_materials[key] = material
	return _materials[key]


static func _color(value) -> Color:
	return Color.html(value) if value is String else value
