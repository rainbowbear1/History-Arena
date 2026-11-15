extends Node3D

# The Independence level's arcade shooting gallery (levels whose theme uses target_style "gallery").
# Answer plaques ride three horizontal tracks at different heights and depths, each moving the
# other way from its neighbour; a plaque leaving the stage slides behind the side curtain and comes
# back in on the other side. Plaques on one track keep the same distance, so their labels never
# bunch up. A row of mechanical ducks crosses the foreground now and then: ducks carry no answer,
# block a shot that hits them (no penalty) and leave gaps, so a clear shot is always a moment away.
# Speeds rise as the level goes on; the last tasks bring a second flock of ducks.

const TRACKS := [
	{"y": 5.6, "z": -12.5, "dir": 1.0, "speed": 1.25},
	{"y": 3.4, "z": -11.0, "dir": -1.0, "speed": 1.6},
	{"y": 1.3, "z": -9.5, "dir": 1.0, "speed": 1.05},
]
const LOOP := 20.0  # Track length; the stage between the curtains shows the middle 17 m.
const STAGE_HALF := 8.6
const RAIL_DROP := 0.95  # Rail below a plaque's centre.
const DUCK_TRACK := {"y": 0.95, "z": -7.0, "dir": -1.0, "speed": 2.0}
const DUCKS_PER_FLOCK := 3
const DUCK_GAP := 1.3
const FINALE_TASKS := 3  # The last tasks bring a second flock.
const SPEED_RAMP := 0.35  # Extra speed by the end of the level (+35 %).
const SLOW_FACTOR := 0.5

var entries: Array = []  # [{target, track, offset}]
var ducks: Array = []  # [{body, offset}]
var travelled := 0.0  # Metres a speed-1 track has moved since the gallery opened.
var speed_scale := 1.0
var slowed := false
var finale := false


func _ready() -> void:
	name = "Gallery"
	for track in TRACKS:
		_rail(track)
	_rail(DUCK_TRACK, 0.25)
	_add_flock(0.0)


# Puts an answer target on track `track` at its starting x (its place on the loop).
func add(target, track: int) -> void:
	target.move_distance = 0.0
	entries.append({"target": target, "track": track, "offset": target.starting_position.x})
	_move(entries[-1])


func clear() -> void:
	entries.clear()


# Progress through the level: speeds rise steadily; the last tasks are the finale.
func set_progress(index: int, count: int) -> void:
	speed_scale = 1.0 + SPEED_RAMP * (float(index) / maxf(1.0, count - 1))
	var now_finale := count > FINALE_TASKS and index >= count - FINALE_TASKS
	if now_finale and not finale:
		_add_flock(LOOP / 2.0)
	finale = now_finale


func track_speed(track: int) -> float:
	return TRACKS[track]["speed"] * speed_scale * (SLOW_FACTOR if slowed else 1.0)


# Where the starting places of `count` plaques on one track are, spread evenly over the loop.
static func spread(count: int, shift: float = 0.0) -> Array:
	var xs := []
	for i in range(count):
		xs.append(wrap_x(-LOOP / 2.0 + (i + 0.5) * LOOP / count + shift))
	return xs


static func wrap_x(x: float) -> float:
	return fposmod(x + LOOP / 2.0, LOOP) - LOOP / 2.0


func _physics_process(delta: float) -> void:
	travelled += delta * speed_scale * (SLOW_FACTOR if slowed else 1.0)
	entries = entries.filter(func(e): return is_instance_valid(e["target"]))
	for entry in entries:
		_move(entry)
	for duck in ducks:
		var x := wrap_x(duck["offset"] + DUCK_TRACK["dir"] * DUCK_TRACK["speed"] * travelled)
		duck["body"].position.x = x


func _move(entry: Dictionary) -> void:
	var track: Dictionary = TRACKS[entry["track"]]
	var target = entry["target"]
	target.starting_position.x = wrap_x(entry["offset"] + track["dir"] * track["speed"] * travelled)
	target.position.x = target.starting_position.x


# A flock of ducks on the foreground track, starting at `at` on the loop.
func _add_flock(at: float) -> void:
	for i in range(DUCKS_PER_FLOCK):
		var duck := Duck.new()
		duck.position = Vector3(0, DUCK_TRACK["y"], DUCK_TRACK["z"])
		add_child(duck)
		ducks.append({"body": duck, "offset": at + i * DUCK_GAP})


func _rail(track: Dictionary, drop: float = RAIL_DROP) -> void:
	var rail := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(STAGE_HALF * 2.0 + 0.6, 0.08, 0.12)
	rail.mesh = mesh
	rail.position = Vector3(0, track["y"] - drop, track["z"] - 0.1)
	rail.material_override = _flat(Color(0.55, 0.58, 0.62))
	add_child(rail)


static func _flat(color: Color, glow: bool = false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.6
	if glow:
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material


# A tin duck on a stick: blocks shots, tips over when hit and pops back up. Carries no answer.
class Duck extends StaticBody3D:
	var tipped := false

	func _ready() -> void:
		add_to_group("obstacle")
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(0.95, 0.85, 0.3)
		shape.shape = box
		shape.position.y = 0.42
		add_child(shape)
		var yellow := _mat(Color(0.98, 0.78, 0.15))
		_part(SphereMesh.new(), Vector3(0.9, 0.5, 0.3), Vector3(0, 0.3, 0), yellow)
		_part(SphereMesh.new(), Vector3(0.36, 0.36, 0.28), Vector3(-0.3, 0.68, 0), yellow)
		_part(BoxMesh.new(), Vector3(0.22, 0.08, 0.1), Vector3(-0.52, 0.66, 0), _mat(Color(0.95, 0.45, 0.1)))
		_part(SphereMesh.new(), Vector3(0.07, 0.07, 0.3), Vector3(-0.36, 0.75, 0), _mat(Color(0.05, 0.05, 0.05)))
		_part(BoxMesh.new(), Vector3(0.3, 0.12, 0.26), Vector3(0.34, 0.5, 0), _mat(Color(0.9, 0.62, 0.1)))
		_part(BoxMesh.new(), Vector3(0.06, 0.3, 0.06), Vector3(0, -0.05, 0), _mat(Color(0.55, 0.58, 0.62)))

	static func _mat(color: Color) -> StandardMaterial3D:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.5
		return material

	func _part(mesh: PrimitiveMesh, size: Vector3, at: Vector3, material: Material) -> void:
		var part := MeshInstance3D.new()
		if mesh is SphereMesh:
			mesh.radius = 0.5
			mesh.height = 1.0
			mesh.radial_segments = 10
			mesh.rings = 5
			part.scale = size
		else:
			mesh.size = size
		part.mesh = mesh
		part.position = at
		part.material_override = material
		add_child(part)

	# Hit by a shot: tips back and pops up again a moment later.
	func hit() -> void:
		if tipped:
			return
		tipped = true
		var tween := create_tween()
		tween.tween_property(self, "rotation:x", -1.3, 0.12)
		tween.tween_interval(0.8)
		tween.tween_property(self, "rotation:x", 0.0, 0.25)
		tween.tween_callback(func(): tipped = false)
