extends CharacterBody3D

# An enemy soldier. It marches in from the edge of the arena to its post on the flank and holds it;
# it does not chase the player. When the spawner orders a volley it aims for a moment (a red "!"
# appears) and fires an arrow or bullet at where the player stood: step aside to dodge, or shoot it
# first. A health bar over its head shows what it has left; when killed it collapses and sinks away.

signal died(enemy)

const GRAVITY := 9.8
const AIM_TIME := 0.9
const HIT_RADIUS := 1.1
const MARCH_SPEED := 3.0
const Soldier := preload("res://soldier.gd")
const Projectile := preload("res://projectile.gd")
const HEALTH_BAR_SHADER := preload("res://health_bar.gdshader")
const BAR_SIZE := Vector2(0.9, 0.11)
const BAR_HEIGHT := 2.4
const FALL_TIME := 0.55
const SINK_TIME := 0.7

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
var dead := false
var health_bar: MeshInstance3D
var _bar_material: ShaderMaterial
var _bar_tween: Tween

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
	hp_label.hide()
	aim_label.hide()
	_build_health_bar()


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
	return not dead and aim_left < 0.0 and at_post()


func _physics_process(delta: float) -> void:
	if dead:
		return
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
	if dead:
		return
	hp -= amount
	_update_bar()
	if hp <= 0:
		_die()
		return
	if soldier:
		soldier.set_outline(Color(1, 1, 0.5))
		await get_tree().create_timer(0.12, false).timeout
		if is_inside_tree():
			for part in soldier.find_children("*", "MeshInstance3D", true, false):
				part.material_overlay = null


# The same small bar for every enemy, whatever its toughness: the fill shows the share of health
# left, so a machine-gun enemy that takes seven hits looks no busier than a one-hit one.
func _build_health_bar() -> void:
	health_bar = MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = BAR_SIZE
	health_bar.mesh = quad
	health_bar.position.y = BAR_HEIGHT
	health_bar.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bar_material = ShaderMaterial.new()
	_bar_material.shader = HEALTH_BAR_SHADER
	_bar_material.set_shader_parameter("ratio", 1.0)
	_bar_material.set_shader_parameter("trail", 1.0)
	health_bar.material_override = _bar_material
	add_child(health_bar)


func health_ratio() -> float:
	return clampf(float(hp) / max_hp, 0.0, 1.0)


# The fill drops at once; the pale trail behind it drains a moment later.
func _update_bar() -> void:
	if _bar_material == null:
		return
	_bar_material.set_shader_parameter("ratio", health_ratio())
	if _bar_tween:
		_bar_tween.kill()
	_bar_tween = create_tween()
	_bar_tween.tween_interval(0.15)
	_bar_tween.tween_property(_bar_material, "shader_parameter/trail", health_ratio(), 0.35)


# Killed: stops fighting at once (the spawner may send a replacement), drops its weapon arm,
# topples backwards and sinks into the ground before it is removed.
func _die() -> void:
	dead = true
	_stop_aiming()
	died.emit(self)
	$CollisionShape3D.set_deferred("disabled", true)
	health_bar.hide()
	var body: Node3D = soldier if soldier else self
	if soldier:
		soldier.motion = "idle"
		for part in soldier.find_children("*", "MeshInstance3D", true, false):
			part.material_overlay = null
	var side := 1.0 if randf() < 0.5 else -1.0
	var fall := create_tween()
	fall.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	fall.tween_property(body, "rotation", Vector3(-PI / 2.0 * 0.95, body.rotation.y, side * 0.25), FALL_TIME)
	fall.set_ease(Tween.EASE_IN_OUT)
	fall.tween_interval(0.35)
	fall.tween_property(body, "position:y", body.position.y - 0.6, SINK_TIME)
	fall.tween_callback(queue_free)


func hits_left() -> int:
	return ceili(float(maxi(hp, 0)) / hit_value)
