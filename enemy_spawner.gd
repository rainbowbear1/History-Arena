extends Node3D

# Keeps the level's number of enemies in the arena (plus a boss on boss levels).
# Stats grow with the level's stars; killed enemies come back after a delay.

const ENEMY_SCENE := preload("res://enemy.tscn")
const RESPAWN_DELAY := 3.0
const ARENA_EDGE := 13.0
const BOSS_HP := 12
const BOSS_DAMAGE := 20
const BOSS_SPEED := 1.8

var quiz
var player: Node3D
var count: int = 0
var stars: int = 1
var has_boss: bool = false
var boss_defeated: bool = false
var enemies: Array = []
var running: bool = false
var speed_scale: float = 1.0
var respawn_token: int = 0


func configure(new_quiz, new_player: Node3D, level: Dictionary) -> void:
	quiz = new_quiz
	player = new_player
	count = level.get("enemies", 0)
	stars = level.get("stars", 1)
	has_boss = level.get("boss", false)


func enemy_hp() -> int:
	return 1 + stars / 2


func enemy_speed() -> float:
	return 2.0 + 0.3 * stars


func enemy_damage() -> int:
	return 4 + 2 * stars


# Fills the arena up to the level's count. Safe to call before every task.
func start() -> void:
	running = true
	var regular := enemies.filter(func(e): return not e.get_meta("boss", false)).size()
	for i in range(count - regular):
		_spawn(false)
	if has_boss and not boss_defeated and not enemies.any(func(e): return e.get_meta("boss", false)):
		_spawn(true)


# Removes all enemies (defeat, results); a later start() brings them back.
func stop() -> void:
	running = false
	respawn_token += 1
	for enemy in enemies:
		enemy.queue_free()
	enemies.clear()


func set_speed_scale(value: float) -> void:
	speed_scale = value
	for enemy in enemies:
		enemy.speed_scale = value


func _spawn(boss: bool) -> void:
	var enemy = ENEMY_SCENE.instantiate()
	enemy.position = _spawn_point()
	enemy.set_meta("boss", boss)
	if boss:
		enemy.setup(quiz, player, BOSS_HP, BOSS_SPEED, BOSS_DAMAGE, true)
	else:
		enemy.setup(quiz, player, enemy_hp(), enemy_speed(), enemy_damage())
	enemy.speed_scale = speed_scale
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemies.append(enemy)


# Enemies enter from the sides and the back, never through the answer targets in front.
func _spawn_point() -> Vector3:
	var along := randf_range(-10.0, 10.0)
	match randi() % 3:
		0:
			return Vector3(-ARENA_EDGE, 0.2, along)
		1:
			return Vector3(ARENA_EDGE, 0.2, along)
	return Vector3(along, 0.2, ARENA_EDGE)


func _on_enemy_died(enemy) -> void:
	enemies.erase(enemy)
	if enemy.get_meta("boss", false):
		boss_defeated = true
		return

	var token := respawn_token
	await get_tree().create_timer(RESPAWN_DELAY, false).timeout
	if running and token == respawn_token:
		start()
