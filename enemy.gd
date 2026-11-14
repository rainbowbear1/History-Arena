extends CharacterBody3D

# An enemy soldier holding a post on the flank of the battle. It does not chase the player:
# when the spawner orders a volley it aims for a moment (a red "!" appears) and fires an arrow
# or bullet at where the player stood. The player can step aside or shoot the enemy first.
# In "panel" mode (the peaceful shooting gallery) it is a sliding board that blocks shots.

signal died(enemy)

const GRAVITY := 9.8
const AIM_TIME := 0.9
const HIT_RADIUS := 1.1
const Soldier := preload("res://soldier.gd")
const Projectile := preload("res://projectile.gd")

var quiz
var player: Node3D
var max_hp: int = 1
var hp: int = 1
var damage: int = 5
var speed_scale: float = 1.0
var attacks: int = 0
var shot_kind: String = "arrow"
var mode: String = "soldier"
var aim_left: float = -1.0
var floating: bool = false  # Stands on scenery without collision (the boss on the rampart).
var soldier: Node3D
var _panel_time: float = 0.0
var _panel_origin: Vector3
var _panel_speed: float = 0.6

@onready var hp_label: Label3D = $HPLabel
@onready var aim_label: Label3D = $AimLabel


func setup(new_quiz, new_player: Node3D, new_hp: int, new_damage: int, look: Dictionary, boss: bool = false, new_mode: String = "soldier") -> void:
	quiz = new_quiz
	player = new_player
	max_hp = new_hp
	hp = new_hp
	damage = new_damage
	mode = new_mode
	shot_kind = "bullet" if look.get("weapon", "") == "rifle" else "arrow"
	if boss:
		scale = Vector3.ONE * 1.6


func _ready() -> void:
	if mode == "panel":
		var boss: bool = get_meta("boss", false)
		var size := Vector3(2.4, 1.1, 0.12) if boss else Vector3(1.4, 0.9, 0.12)
		var panel := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = size
		panel.mesh = mesh
		var material := StandardMaterial3D.new()
		material.albedo_color = Color(0.93, 0.76, 0.3) if boss else Color(0.85, 0.2, 0.2)
		panel.material_override = material
		panel.position.y = 1.0
		add_child(panel)
		$CollisionShape3D.position.y = 1.0
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x, size.y, 0.3)
		$CollisionShape3D.shape = shape
		hp_label.position.y = 1.0 - size.y / 2.0 - 0.3
		scale = Vector3.ONE
		_panel_origin = position
		_panel_time = randf() * TAU
		_panel_speed = randf_range(0.45, 0.8) if not boss else 0.3
	_update_label()
	aim_label.hide()


func build_look(look: Dictionary) -> void:
	if mode == "panel" or look.is_empty():
		return
	soldier = Soldier.new()
	add_child(soldier)
	soldier.build(look)
	soldier.set_motion("idle")


func _physics_process(delta: float) -> void:
	if mode == "panel":
		_panel_time += delta * speed_scale * (_panel_speed if quiz.accepting_answers else 0.0)
		position.x = _panel_origin.x + sin(_panel_time) * 6.0
		return

	if not floating and not is_on_floor():
		velocity.y -= GRAVITY * delta
	velocity.x = 0.0
	velocity.z = 0.0
	move_and_slide()

	var to_player := player.global_position - global_position
	to_player.y = 0.0
	if to_player.length() > 0.1:
		rotation.y = atan2(-to_player.x, -to_player.z)

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
	if mode == "panel" or aim_left >= 0.0:
		return false
	aim_left = AIM_TIME
	aim_label.show()
	if soldier:
		soldier.motion = "aim"
	return true


func _stop_aiming() -> void:
	aim_left = -1.0
	aim_label.hide()
	if soldier:
		soldier.motion = "idle"


# Shoots at the player's chest. A damaging shot hurts only if the player is still there on arrival;
# a cosmetic shot (the wrong-answer reaction) always lands but deals no damage itself.
func fire(damaging: bool) -> void:
	var from := global_position + Vector3(0, 1.4 * scale.y, 0)
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
	hp_label.modulate = Color(1, 1, 0.4)
	await get_tree().create_timer(0.15, false).timeout
	if is_inside_tree():
		hp_label.modulate = Color(1, 0.5, 0.45)


func _update_label() -> void:
	if hp_label:
		hp_label.text = "%d/%d" % [maxi(hp, 0), max_hp]
