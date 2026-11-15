extends Node3D

# Dresses the arena for a level from data/themes.json: sky, fog and sun, ground colour, a rampart
# for the top row of answer soldiers, era props around the arena, and background soldiers that
# play out a battle (they never attack; see enemy.gd for the soldiers that do).
# Everything is built from a few primitive meshes with flat colours (low-poly style, cheap on the web).

const Soldier := preload("res://soldier.gd")
const Projectile := preload("res://projectile.gd")
# Background exchange of fire: one harmless shot every this many seconds (scenery only).
const BATTLE_SHOT_EVERY := Vector2(0.9, 2.2)
const THEMES_FILE := "res://data/themes.json"
const LEDGE_TOP := 3.1
const LEDGE_FRONT_Z := -9.0
const ARENA_HALF := 16.0
# The rampart only spans the answer rows, so the battle beyond stays visible on both sides.
const LEDGE_WIDTH := 15.0

var theme: Dictionary = {}
var rng := RandomNumberGenerator.new()
var background_soldiers: Array = []
var background_enemies: Array = []  # Distant enemy soldiers (used for the wrong-answer reaction).
var background_allies: Array = []  # Allies beside the player who shoot at the distant enemy line.
var battle_left: float = 1.5

static var _materials := {}


static func load_themes() -> Dictionary:
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(THEMES_FILE)) != OK or not json.data is Dictionary:
		push_error("Cannot read " + THEMES_FILE)
		return {}
	return json.data.get("themes", {})


func apply(theme_name: String, level_id: int, world: WorldEnvironment, sun: DirectionalLight3D, ground: MeshInstance3D) -> void:
	theme = load_themes().get(theme_name, {})
	if theme.is_empty():
		return
	rng.seed = level_id * 7919
	_sky_and_light(world, sun)
	ground.set_surface_override_material(0, _material(theme["ground"]))
	_box(Vector3(400, 0.1, 400), Vector3(0, 0.0, 0), _color(theme["ground"]).darkened(0.06))
	_ledge()
	for entry in theme.get("props", []):
		for i in range(int(entry[1])):
			_prop(entry[0], i)
	_background()


func _sky_and_light(world: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var environment: Environment = world.environment.duplicate()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = _color(theme["sky_top"])
	sky_material.sky_horizon_color = _color(theme["sky_horizon"])
	sky_material.ground_horizon_color = _color(theme["sky_horizon"])
	sky_material.ground_bottom_color = _color(theme["ground"]).darkened(0.3)
	var sky := Sky.new()
	sky.sky_material = sky_material
	environment.sky = sky
	environment.fog_enabled = true
	environment.fog_light_color = _color(theme["fog_color"])
	environment.fog_density = theme["fog_density"]
	environment.fog_sky_affect = 0.25
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	world.environment = environment

	sun.light_color = _color(theme["sun_color"])
	sun.light_energy = theme["sun_energy"]
	sun.rotation_degrees = Vector3(theme["sun_pitch"], theme["sun_yaw"], 0)


# The raised ground behind the answer row; the top row of answer soldiers stands on it.
func _ledge() -> void:
	var color: Color = _color(theme["ledge"])
	var depth := 2.4
	var center := Vector3(0, LEDGE_TOP / 2.0, LEDGE_FRONT_Z - depth / 2.0)
	match theme.get("ledge_style", "earth"):
		"fortress":
			_box(Vector3(LEDGE_WIDTH, LEDGE_TOP, depth), center, color)
			for x in range(-7, 8, 2):
				_box(Vector3(0.9, 0.7, 0.5), Vector3(x, LEDGE_TOP + 0.35, LEDGE_FRONT_Z - 0.25), color.darkened(0.1))
			for side in [-1, 1]:
				_box(Vector3(3.0, 6.5, 3.0), Vector3(side * 9.0, 3.25, LEDGE_FRONT_Z - 1.2), color.darkened(0.08))
		"palisade":
			_box(Vector3(LEDGE_WIDTH, LEDGE_TOP - 0.4, depth), center - Vector3(0, 0.2, 0), color.darkened(0.15))
			for i in range(28):
				var stake := _cylinder(0.14, 0.14, LEDGE_TOP + 0.6, Vector3(-7.4 + i * 0.55, (LEDGE_TOP + 0.6) / 2.0, LEDGE_FRONT_Z - 0.1), color)
				stake.rotation.z = rng.randf_range(-0.04, 0.04)
		"sandbags":
			_box(Vector3(LEDGE_WIDTH, LEDGE_TOP - 0.5, depth), center - Vector3(0, 0.25, 0), _color(theme["ground"]).darkened(0.2))
			for row in range(2):
				for i in range(15):
					_box(Vector3(0.95, 0.28, 0.5), Vector3(-7.0 + i + (row % 2) * 0.5, LEDGE_TOP - 0.36 + row * 0.28, LEDGE_FRONT_Z - 0.3), color.lightened(0.05 * row))
		"stand":
			_box(Vector3(LEDGE_WIDTH, LEDGE_TOP, depth), center, color)
			for i in range(7):
				_box(Vector3(1.0, 0.25, 0.06), Vector3(-6 + i * 2, LEDGE_TOP - 0.4, LEDGE_FRONT_Z + 0.01), Color.WHITE)
		"rock":
			_box(Vector3(LEDGE_WIDTH, LEDGE_TOP, depth), center, color)
			for i in range(5):
				var rock := _sphere(Vector3(rng.randf_range(2.5, 4.0), rng.randf_range(2.0, 3.2), 2.2), Vector3(-6 + i * 3, 1.2, LEDGE_FRONT_Z - 0.6), color.darkened(rng.randf_range(0.0, 0.15)))
				rock.rotation.y = rng.randf() * TAU
		"mound":
			# A grassy burial mound instead of a wall: the top row stands on its crest.
			_sphere(Vector3(20.0, LEDGE_TOP * 2.0, 4.2), Vector3(0, 0, LEDGE_FRONT_Z - 1.5), _color(theme["ground"]).darkened(0.12))
			for i in range(6):
				var stone := _sphere(Vector3(0.8, 0.5, 0.7), Vector3(rng.randf_range(-8.0, 8.0), 0.2, LEDGE_FRONT_Z + 2.4 + rng.randf_range(-0.3, 0.3)), color.darkened(0.2))
				stone.rotation.y = rng.randf() * TAU
		"range":
			# A modern shooting range: no wall, lane lines on the ground, a low earth backstop far
			# behind the targets and a firing-line bench in front of the player.
			for i in range(8):
				_box(Vector3(0.12, 0.02, 14.0), Vector3(-12.6 + i * 3.6, 0.07, -4.0), Color(0.95, 0.95, 0.95))
			_box(Vector3(30.0, 0.04, 0.3), Vector3(0, 0.07, 3.0), Color(0.95, 0.85, 0.2))
			_box(Vector3(40.0, 4.0, 3.0), Vector3(0, 2.0, -24.0), _color(theme["ground"]).darkened(0.25))
			for i in range(5):
				_box(Vector3(5.0, 0.9, 0.8), Vector3(-12.0 + i * 6.0, 0.45, 4.5), Color(0.55, 0.42, 0.3))
		_:
			_box(Vector3(LEDGE_WIDTH, LEDGE_TOP, depth), center, color)


# Props go outside the playable square, in a ring around the arena.
func _ring_point(min_r: float, max_r: float) -> Vector3:
	for attempt in range(20):
		var angle := rng.randf() * TAU
		var r := rng.randf_range(min_r, max_r)
		var p := Vector3(cos(angle) * r, 0.0, sin(angle) * r)
		if absf(p.x) > ARENA_HALF + 2.0 or absf(p.z) > ARENA_HALF + 2.0:
			return p
	return Vector3(min_r, 0, -min_r)


func _prop(kind: String, index: int) -> void:
	var trim: Color = _color(theme.get("ally_look", {}).get("trim", "#c9a24a"))
	match kind:
		"kurgan":
			var r := rng.randf_range(3.0, 5.5)
			_sphere(Vector3(r * 2, r * 0.7, r * 2), _ring_point(24, 55), _color(theme["ground"]).darkened(0.15))
		"hill":
			var r := rng.randf_range(10.0, 20.0)
			_sphere(Vector3(r * 2, r * 0.45, r * 2), _ring_point(45, 110), _color(theme["ground"]).darkened(rng.randf_range(0.05, 0.2)))
		"mountain":
			var p := _ring_point(110, 170)
			var h := rng.randf_range(35, 70)
			_cylinder(0.0, rng.randf_range(25, 45), h, p + Vector3(0, h / 2.0, 0), Color(0.45, 0.5, 0.58).lerp(_color(theme["fog_color"]), 0.3))
			_cylinder(0.0, 9.0, h * 0.2, p + Vector3(0, h * 0.9, 0), Color(0.93, 0.95, 0.97))
		"yurt":
			var p := _ring_point(22, 45)
			_cylinder(2.4, 2.4, 1.7, p + Vector3(0, 0.85, 0), Color(0.93, 0.9, 0.82))
			_cylinder(0.3, 2.5, 1.3, p + Vector3(0, 2.35, 0), Color(0.86, 0.82, 0.72))
			var toward_arena := (-p).normalized()
			var door := _box(Vector3(0.9, 1.4, 0.1), p + toward_arena * 2.42 + Vector3(0, 0.7, 0), trim.darkened(0.3))
			door.rotation.y = atan2(toward_arena.x, toward_arena.z)
		"tent":
			var p := _ring_point(22, 45)
			_cylinder(0.0, 1.8, 2.8, p + Vector3(0, 1.4, 0), trim.lerp(Color(0.85, 0.8, 0.7), 0.5))
		"banner":
			var p := _ring_point(19, 32)
			_cylinder(0.07, 0.07, 6.0, p + Vector3(0, 3.0, 0), Color(0.35, 0.25, 0.15))
			_box(Vector3(1.6, 1.0, 0.06), p + Vector3(0.8, 5.3, 0), trim)
		"balbal":
			var p := _ring_point(20, 40)
			_box(Vector3(0.7, 1.7, 0.45), p + Vector3(0, 0.85, 0), Color(0.6, 0.6, 0.57))
			_box(Vector3(0.5, 0.5, 0.4), p + Vector3(0, 1.95, 0), Color(0.62, 0.62, 0.6))
		"stele":
			var p := _ring_point(22, 36)
			_box(Vector3(1.1, 4.0, 0.45), p + Vector3(0, 2.0, 0), Color(0.68, 0.68, 0.64))
		"tower":
			var p := _ring_point(26, 50)
			_box(Vector3(4, 10, 4), p + Vector3(0, 5, 0), _color(theme["ledge"]).darkened(0.05))
			for corner in [Vector3(-1.6, 0, -1.6), Vector3(1.6, 0, -1.6), Vector3(-1.6, 0, 1.6), Vector3(1.6, 0, 1.6)]:
				_box(Vector3(0.8, 0.8, 0.8), p + corner + Vector3(0, 10.4, 0), _color(theme["ledge"]).darkened(0.12))
		"wall":
			var p := _ring_point(28, 50)
			var wall := _box(Vector3(12, 6, 1.8), p + Vector3(0, 3, 0), _color(theme["ledge"]).darkened(0.08))
			wall.rotation.y = atan2(p.x, p.z)
		"dome":
			var p := _ring_point(30, 60) if index > 0 else Vector3(-26, 0, -38)
			_box(Vector3(8, 7, 8), p + Vector3(0, 3.5, 0), Color(0.82, 0.72, 0.55))
			_cylinder(3.3, 3.3, 1.2, p + Vector3(0, 7.6, 0), Color(0.75, 0.66, 0.5))
			_sphere(Vector3(6.4, 6.0, 6.4), p + Vector3(0, 8.4, 0), Color(0.18, 0.62, 0.68))
		"rock":
			var r := rng.randf_range(1.0, 3.0)
			var rock := _sphere(Vector3(r * 2, r * 1.3, r * 1.7), _ring_point(20, 50), Color(0.5, 0.5, 0.48).lerp(_color(theme["ground"]), 0.2))
			rock.rotation.y = rng.randf() * TAU
		"palisade":
			var p := _ring_point(24, 40)
			for i in range(8):
				_cylinder(0.15, 0.15, 3.2, p + Vector3(i * 0.4, 1.6, 0), Color(0.42, 0.3, 0.18))
		"birch":
			var p := _ring_point(19, 45)
			_cylinder(0.18, 0.22, 6.0, p + Vector3(0, 3.0, 0), Color(0.92, 0.92, 0.88))
			_sphere(Vector3(3.0, 3.6, 3.0), p + Vector3(0, 6.2, 0), Color(0.55, 0.6, 0.4).lerp(Color(0.85, 0.9, 0.9), 0.4))
		"tree":
			var p := _ring_point(20, 45)
			_cylinder(0.2, 0.25, 3.0, p + Vector3(0, 1.5, 0), Color(0.4, 0.28, 0.18))
			_sphere(Vector3(3.2, 3.2, 3.2), p + Vector3(0, 4.0, 0), Color(0.3, 0.6, 0.3))
		"sandbags":
			var p := _ring_point(20, 36)
			for i in range(5):
				_box(Vector3(1.0, 0.3, 0.55), p + Vector3(i * 1.0, 0.15 + (i % 2) * 0.3, 0), Color(0.62, 0.58, 0.42))
		"flag":
			var p := _ring_point(19, 30)
			_cylinder(0.06, 0.06, 7.0, p + Vector3(0, 3.5, 0), Color(0.85, 0.85, 0.88))
			_box(Vector3(1.8, 1.0, 0.05), p + Vector3(0.9, 6.4, 0), Color(0.0, 0.69, 0.79))
		"booth":
			var p := Vector3((index - 2.5) * 6.0, 0, 20.0) if index < 6 else _ring_point(22, 40)
			_box(Vector3(4.5, 2.6, 2.5), p + Vector3(0, 1.3, 0), Color(0.95, 0.95, 0.92))
			for s in range(5):
				_box(Vector3(0.9, 0.15, 3.0), p + Vector3(-1.8 + s * 0.9, 2.85, 0), Color(0.85, 0.2, 0.2) if s % 2 == 0 else Color.WHITE)
		"monument":
			var p := Vector3(10, 0, -75)
			_cylinder(1.2, 3.2, 26.0, p + Vector3(0, 13.0, 0), Color(0.95, 0.95, 0.95))
			for i in range(8):
				var rib := _cylinder(0.25, 0.25, 9.0, p + Vector3(cos(i * TAU / 8.0) * 3.0, 28.0, sin(i * TAU / 8.0) * 3.0), Color(0.95, 0.95, 0.95))
				rib.rotation = Vector3(sin(i * TAU / 8.0) * 0.35, 0, -cos(i * TAU / 8.0) * 0.35)
			_sphere(Vector3(6.0, 6.0, 6.0), p + Vector3(0, 31.0, 0), Color(0.93, 0.76, 0.3))


func _background() -> void:
	var setup: Dictionary = theme.get("background", {})
	var allies := int(setup.get("allies", 0))
	var enemies := int(setup.get("enemies", 0))
	var motion: String = setup.get("motion", "idle")
	var ally_look: Dictionary = theme.get("ally_look", {})
	var enemy_look: Dictionary = theme.get("enemy_look", {})

	# Allies line up beside the player and shoot at the enemy line beyond the rampart.
	for i in range(allies / 2):
		for side in [-1, 1]:
			var ally := _soldier(ally_look, Vector3(side * rng.randf_range(12.5, 14.5), 0.1, rng.randf_range(-7.0, -2.0)), 0.0, "idle")
			if ally:
				background_allies.append(ally)

	# The battle beyond the rampart: duels on the flanks, troops marching in the distance.
	for i in range(enemies):
		var x := (1.0 if i % 2 == 0 else -1.0) * rng.randf_range(9.5, 26.0)
		var z := rng.randf_range(-30.0, -13.0)
		if motion == "fight" and i % 2 == 0 and not ally_look.is_empty():
			_soldier(ally_look, Vector3(x, 0.1, z + 1.1), 0.0, "fight")
			background_enemies.append(_soldier(enemy_look, Vector3(x, 0.1, z), PI, "fight"))
		else:
			background_enemies.append(_soldier(enemy_look, Vector3(x, 0.1, z), PI, motion if motion != "fight" else "march"))


# The battle in the background: an ally fires at a distant enemy (or, now and then, the reverse).
# Shots are scenery: they hit nothing and nobody falls.
func _process(delta: float) -> void:
	if background_allies.is_empty() or background_enemies.is_empty():
		return
	battle_left -= delta
	if battle_left > 0.0:
		return
	battle_left = rng.randf_range(BATTLE_SHOT_EVERY.x, BATTLE_SHOT_EVERY.y)
	var ally: Node3D = background_allies.pick_random()
	var enemy: Node3D = background_enemies.pick_random()
	if not is_instance_valid(ally) or not is_instance_valid(enemy):
		return
	var outgoing := rng.randf() < 0.7
	var shooter := ally if outgoing else enemy
	var look: Dictionary = theme.get("ally_look" if outgoing else "enemy_look", {})
	var kind := "bullet" if look.get("weapon", "") == "rifle" else "arrow"
	var from := shooter.global_position + Vector3(0, 1.5, 0)
	var to := (enemy if outgoing else ally).global_position + Vector3(rng.randf_range(-1.0, 1.0), 1.0, 0)
	if outgoing:
		shooter.rotation.y = atan2(-(to.x - from.x), -(to.z - from.z))
		shooter.set_motion("aim")
		_back_to_idle(shooter)
	var projectile := Projectile.new()
	add_child(projectile)
	projectile.launch(from, to, 45.0 if kind == "bullet" else 26.0, kind, func(_point): pass)


func _back_to_idle(soldier: Node3D) -> void:
	await get_tree().create_timer(0.8, false).timeout
	if is_instance_valid(soldier):
		soldier.set_motion("idle")
		soldier.rotation.y = 0.0


func _soldier(look: Dictionary, at: Vector3, facing: float, motion: String) -> Node3D:
	if look.is_empty():
		return null
	var soldier := Soldier.new()
	soldier.position = at
	soldier.rotation.y = facing
	add_child(soldier)
	soldier.build(look)
	soldier.set_motion(motion, rng.randf_range(0.8, 1.2), rng.randf_range(2.0, 5.0))
	background_soldiers.append(soldier)
	return soldier


func _box(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	return _add(mesh, at, color)


func _cylinder(top: float, bottom: float, height: float, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = top
	mesh.bottom_radius = bottom
	mesh.height = height
	mesh.radial_segments = 8
	mesh.rings = 1
	return _add(mesh, at, color)


func _sphere(size: Vector3, at: Vector3, color: Color) -> MeshInstance3D:
	var mesh := SphereMesh.new()
	mesh.radius = 0.5
	mesh.height = 1.0
	mesh.radial_segments = 10
	mesh.rings = 5
	var instance := _add(mesh, at, color)
	instance.scale = size
	return instance


func _add(mesh: Mesh, at: Vector3, color: Color) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = _material(color)
	add_child(instance)
	return instance


static func _material(value) -> StandardMaterial3D:
	var color := _color(value)
	var key := color.to_html()
	if not _materials.has(key):
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 1.0
		_materials[key] = material
	return _materials[key]


static func _color(value) -> Color:
	return Color.html(value) if value is String else value
