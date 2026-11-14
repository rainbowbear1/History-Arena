extends CharacterBody3D

# A simple enemy that walks toward the player and strikes in melee range.
# It only moves and attacks while a task is being answered.

signal died(enemy)

const GRAVITY := 9.8
const ATTACK_RANGE := 1.7
const ATTACK_COOLDOWN := 1.2
const HIT_COLOR := Color(1.0, 0.9, 0.4)

var quiz
var player: Node3D
var max_hp: int = 1
var hp: int = 1
var move_speed: float = 2.5
var damage: int = 6
var speed_scale: float = 1.0
var attack_cooldown: float = 0.5
var attacks: int = 0

@onready var body_mesh: MeshInstance3D = $BodyMesh
@onready var hp_label: Label3D = $HPLabel


func setup(new_quiz, new_player: Node3D, new_hp: int, new_speed: float, new_damage: int, boss: bool = false) -> void:
	quiz = new_quiz
	player = new_player
	max_hp = new_hp
	hp = new_hp
	move_speed = new_speed
	damage = new_damage
	if boss:
		scale = Vector3.ONE * 1.6


func _ready() -> void:
	_update_label()


func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	attack_cooldown = maxf(attack_cooldown - delta, 0.0)
	var to_player := player.global_position - global_position
	to_player.y = 0.0

	if not quiz.accepting_answers or to_player.length() <= ATTACK_RANGE:
		velocity.x = 0.0
		velocity.z = 0.0
	else:
		var direction := to_player.normalized()
		velocity.x = direction.x * move_speed * speed_scale
		velocity.z = direction.z * move_speed * speed_scale
		look_at(global_position + direction, Vector3.UP)

	move_and_slide()

	if quiz.accepting_answers and to_player.length() <= ATTACK_RANGE and attack_cooldown <= 0.0:
		attack_cooldown = ATTACK_COOLDOWN
		attacks += 1
		quiz.enemy_attack(damage)


func take_hit(amount: int) -> void:
	hp -= amount
	_update_label()
	if hp <= 0:
		died.emit(self)
		queue_free()
		return

	var material := StandardMaterial3D.new()
	material.albedo_color = HIT_COLOR
	body_mesh.material_overlay = material
	await get_tree().create_timer(0.15, false).timeout
	if is_inside_tree():
		body_mesh.material_overlay = null


func _update_label() -> void:
	if hp_label:
		hp_label.text = "%d/%d" % [maxi(hp, 0), max_hp]
