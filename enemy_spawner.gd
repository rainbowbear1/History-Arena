extends Node3D

# Keeps the level's number of enemies at posts on the flanks (plus a boss on boss levels).
# One shared volley clock picks a single enemy to aim and fire, so harder levels shoot more often
# without a hail of arrows. Killed enemies return to their post after a delay.
# In the shooting gallery (enemy_mode "gallery") enemies are sliding panels that never shoot.

const ENEMY_SCENE := preload("res://enemy.tscn")
const RESPAWN_DELAY := 6.0
const BOSS_HP := 12
const BOSS_DAMAGE := 12
# Gallery panels slide across the line of fire; more than this would hide the answers.
const MAX_PANELS := 3
const Projectile := preload("res://projectile.gd")

var quiz
var player: Node3D
var count: int = 0
var stars: int = 1
var has_boss: bool = false
var boss_defeated: bool = false
var mode: String = "soldier"
var look: Dictionary = {}
var enemies: Array = []
var running: bool = false
var speed_scale: float = 1.0
var respawn_token: int = 0
var volley_left: float = 0.0
var background_shooters: Array = []  # Distant soldiers used for the wrong-answer reaction.


func configure(new_quiz, new_player: Node3D, level: Dictionary, theme: Dictionary = {}) -> void:
	quiz = new_quiz
	player = new_player
	count = level.get("enemies", 0)
	stars = level.get("stars", 1)
	has_boss = level.get("boss", false)
	look = theme.get("enemy_look", {})
	mode = "panel" if theme.get("enemy_mode", "") == "gallery" else "soldier"
	volley_left = volley_interval()


func enemy_hp() -> int:
	return 1 + stars / 2


func enemy_damage() -> int:
	return 3 + stars


# Seconds between shots from the enemy line: 10.5 s at one star down to 4.5 s at five.
func volley_interval() -> float:
	return maxf(3.5, 12.0 - stars * 1.5)


# Fills the posts up to the level's count. Safe to call before every task.
func start() -> void:
	running = true
	var regular := enemies.filter(func(e): return not e.get_meta("boss", false)).size()
	var wanted := count if mode != "panel" else mini(count, MAX_PANELS)
	for i in range(wanted - regular):
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


func _process(delta: float) -> void:
	if not running or mode == "panel" or quiz == null or not quiz.accepting_answers:
		return
	var shooters := enemies.filter(func(e): return is_instance_valid(e) and e.aim_left < 0.0)
	if shooters.is_empty():
		return
	volley_left -= delta * speed_scale
	if volley_left <= 0.0:
		volley_left = volley_interval() + randf_range(0.0, 2.0)
		shooters.pick_random().begin_aim()


# A wrong answer: an enemy (or a distant soldier) visibly lands a shot. The HP loss itself is
# applied by the quiz; this only shows where it came from.
func reaction_shot() -> void:
	if mode == "panel" or player == null:
		return
	var shooters := enemies.filter(func(e): return is_instance_valid(e))
	if not shooters.is_empty():
		shooters.pick_random().fire(false)
		return
	var distant := background_shooters.filter(func(s): return is_instance_valid(s))
	if distant.is_empty():
		return
	var from: Vector3 = distant.pick_random().global_position + Vector3(0, 1.4, 0)
	var projectile := Projectile.new()
	get_tree().current_scene.add_child(projectile)
	projectile.launch(from, player.global_position + Vector3(0, 0.4, 0), 30.0, "arrow", func(_p): pass)


func _spawn(boss: bool) -> void:
	var enemy = ENEMY_SCENE.instantiate()
	var index := enemies.size()
	enemy.position = _post(index, boss)
	enemy.set_meta("boss", boss)
	enemy.floating = boss and mode == "soldier"
	if boss:
		enemy.setup(quiz, player, BOSS_HP, BOSS_DAMAGE, look, true, mode)
	else:
		enemy.setup(quiz, player, enemy_hp(), enemy_damage(), look, false, mode)
	enemy.speed_scale = speed_scale
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemy.build_look(look)
	enemies.append(enemy)


# Posts on both flanks, staggered back toward the rampart. Gallery panels slide in front of the targets.
func _post(index: int, boss: bool) -> Vector3:
	if mode == "panel":
		return Vector3(0, 1.4, -5.0 - (index % 3) * 0.7) if not boss else Vector3(0, 3.4, -9.4)
	if boss:
		# On the flank of the rampart, above the answer rows (the rampart has no collision).
		return Vector3(10.0, 3.1, -10.6)
	var side := -1.0 if index % 2 == 0 else 1.0
	var rank := index / 2
	return Vector3(side * (8.5 + (rank % 3) * 1.6), 0.2, -4.5 - rank * 1.8)


func _on_enemy_died(enemy) -> void:
	enemies.erase(enemy)
	if enemy.get_meta("boss", false):
		boss_defeated = true
		return

	var token := respawn_token
	await get_tree().create_timer(RESPAWN_DELAY, false).timeout
	if running and token == respawn_token:
		start()
