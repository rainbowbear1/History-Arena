extends CharacterBody3D

# An enemy soldier. It marches in from the edge of the arena to its post on the flank and holds it;
# it does not chase the player. When the spawner orders a volley it aims for a moment (a red "!"
# appears) and fires an arrow or bullet at where the player stood: step aside to dodge, or shoot it
# first. The marks over its head are the hits it can still take.

signal died(enemy)

const GRAVITY := 9.8
const AIM_TIME := 0.9
const HIT_RADIUS := 1.1
const MARCH_SPEED := 3.0
const Soldier := preload("res://soldier.gd")
const Projectile := preload("res://projectile.gd")

var quiz
var player: Node3D
var max_hp: int = 1
var hp: int = 1
var damage: int = 5
var hit_value: int = 1  # Damage of one hit of the player's weapon, for the hit marks.
var speed_scale: float = 1.0
var attacks: int = 0
var shot_kind: String = "arrow"
var aim_left: float = -1.0
var post: Vector3 = Vector3.INF  # Where it stands guard; it marches there after spawning.
var soldier: Node3D
var _pips: Node3D

static var PIP_MESH := _pip_mesh()
static var PIP_FULL := _pip_material(Color(0.9, 0.15, 0.1))
static var PIP_EMPTY := _pip_material(Color(0.15, 0.15, 0.15))


static func _pip_mesh() -> BoxMesh:
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.18, 0.18, 0.18)
	return mesh


static func _pip_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return material

@onready var hp_label: Label3D = $HPLabel
@onready var aim_label: Label3D = $AimLabel


func setup(new_quiz, new_player: Node3D, new_hp: int, new_damage: int, look: Dictionary, new_hit_value: int = 1) -> void:
	quiz = new_quiz
	player = new_player
	max_hp = new_hp
	hp = new_hp
	damage = new_damage
	hit_value = maxi(1, new_hit_value)
	shot_kind = "bullet" if look.get("weapon", "") == "rifle" else "arrow"


func _ready() -> void:
	if post == Vector3.INF:
		post = position
	_update_label()
	aim_label.hide()


func build_look(look: Dictionary) -> void:
	if look.is_empty():
		return
	soldier = Soldier.new()
	add_child(soldier)
	soldier.build(look)
	soldier.set_motion("idle")


func at_post() -> bool:
	return Vector2(position.x - post.x, position.z - post.z).length() < 0.15


# Only an enemy standing at its post, not already aiming, can be ordered to shoot.
func ready_to_aim() -> bool:
	return aim_left < 0.0 and at_post()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta
	var to_post := Vector3(post.x - position.x, 0.0, post.z - position.z)
	var marching := not at_post()
	var march := to_post.normalized() * minf(MARCH_SPEED * speed_scale, to_post.length() / maxf(delta, 0.001)) if marching else Vector3.ZERO
	velocity.x = march.x
	velocity.z = march.z
	move_and_slide()
	if soldier:
		soldier.motion = "march_in_place" if marching else ("aim" if aim_left >= 0.0 else "idle")

	var facing := to_post if marching else player.global_position - global_position
	facing.y = 0.0
	if facing.length() > 0.1:
		rotation.y = atan2(-facing.x, -facing.z)

	if aim_left < 0.0:
		return
	if not quiz.accepting_answers:
		_stop_aiming()
		return
	aim_left -= delta * speed_scale
	if aim_left <= 0.0:
		_stop_aiming()
		fire(true)


# Starts a visible aim; the shot follows after AIM_TIME. Returns false if it cannot shoot.
func begin_aim() -> bool:
	if not ready_to_aim():
		return false
	aim_left = AIM_TIME
	aim_label.show()
	return true


func _stop_aiming() -> void:
	aim_left = -1.0
	aim_label.hide()


# Shoots at the player's chest. A damaging shot hurts only if the player is still there on arrival;
# a cosmetic shot (the wrong-answer reaction) always lands but deals no damage itself.
func fire(damaging: bool) -> void:
	var from := global_position + Vector3(0, 1.4, 0)
	var aim_point := player.global_position + Vector3(0, 0.4, 0)
	var projectile := Projectile.new()
	get_tree().current_scene.add_child(projectile)
	projectile.speed_scale = speed_scale
	projectile.launch(from, aim_point, 40.0 if shot_kind == "bullet" else 22.0, shot_kind,
		func(point: Vector3): _on_shot_arrived(point, damaging))
	attacks += 1


func _on_shot_arrived(point: Vector3, damaging: bool) -> void:
	if damaging and is_instance_valid(player) and player.global_position.distance_to(point - Vector3(0, 0.4, 0)) <= HIT_RADIUS:
		quiz.enemy_attack(damage)


func take_hit(amount: int) -> void:
	hp -= amount
	_update_label()
	if hp <= 0:
		died.emit(self)
		queue_free()
		return
	if soldier:
		soldier.set_outline(Color(1, 1, 0.5))
		await get_tree().create_timer(0.12, false).timeout
		if is_inside_tree():
			for part in soldier.find_children("*", "MeshInstance3D", true, false):
				part.material_overlay = null


# One pip per hit over its head: red for hits it can still take, dark for hits already landed.
func _update_label() -> void:
	if not is_inside_tree():
		return
	hp_label.hide()
	var total := ceili(float(max_hp) / hit_value)
	var left := ceili(float(maxi(hp, 0)) / hit_value)
	if _pips == null:
		_pips = Node3D.new()
		_pips.position.y = 2.35
		add_child(_pips)
		for i in range(total):
			var pip := MeshInstance3D.new()
			pip.mesh = PIP_MESH
			pip.position.x = (i - (total - 1) / 2.0) * 0.26
			_pips.add_child(pip)
	for i in range(_pips.get_child_count()):
		_pips.get_child(i).material_override = PIP_FULL if i < left else PIP_EMPTY


func hits_left() -> int:
	return ceili(float(maxi(hp, 0)) / hit_value)
