extends Node3D

# Active enemies: the soldiers that actually threaten the player. (Background soldiers are scenery,
# see environment_builder.gd; answer targets are answer_target.gd.)
# - At most `enemies` (from levels.json, never more than MAX_ACTIVE) are active at once.
# - Each task starts with a wave: missing enemies march in from the edge of the arena to free posts,
#   never to the post they held in the previous wave.
# - During a task a killed enemy is replaced at most REINFORCEMENTS_PER_TASK times, after
#   REINFORCE_DELAY seconds, so the line can actually be cleared.
# - Toughness is counted in hits of the player's own weapon, so a bow, a musket and a machine gun
#   all need about the same time to bring an enemy down (see hits_to_kill).
# - One shared volley clock picks a single enemy to aim and fire.

const ENEMY_SCENE := preload("res://enemy.tscn")
const Projectile := preload("res://projectile.gd")
const MAX_ACTIVE := 3
const REINFORCE_DELAY := 8.0
const REINFORCEMENTS_PER_TASK := 1
# Seconds of continuous fire an enemy should take to bring down, by stars (index = stars).
const TIME_TO_KILL := [0.0, 0.0, 0.0, 0.5, 1.0, 1.0]
# Posts on both flanks, at different depths, clear of the answer rows (|x| <= 7.5).
const POSTS := [
	Vector3(-9.0, 0.2, -4.0), Vector3(9.0, 0.2, -4.0), Vector3(-10.5, 0.2, -6.5), Vector3(10.5, 0.2, -6.5),
	Vector3(-12.0, 0.2, -3.0), Vector3(12.0, 0.2, -3.0), Vector3(-9.5, 0.2, -9.0), Vector3(9.5, 0.2, -9.0),
	Vector3(-12.5, 0.2, -8.0), Vector3(12.5, 0.2, -8.0),
]
const ENTRY_X := 14.5

var quiz
var player: Node3D
var count: int = 0
var stars: int = 1
var look: Dictionary = {}
var enemies: Array = []
var running: bool = false
var speed_scale: float = 1.0
var task_token: int = 0
var reinforcements_left: int = 0
var volley_left: float = 0.0
var last_posts: Array = []
var background_shooters: Array = []  # Distant soldiers used for the wrong-answer reaction.


func configure(new_quiz, new_player: Node3D, level: Dictionary, theme: Dictionary = {}) -> void:
	quiz = new_quiz
	player = new_player
	look = theme.get("enemy_look", {})
	# Enemies are soldiers; an era without an enemy look (the shooting range) has none.
	count = mini(level.get("enemies", 0), MAX_ACTIVE) if not look.is_empty() or theme.is_empty() else 0
	stars = level.get("stars", 1)
	volley_left = volley_interval()


# Hits of the player's weapon an enemy takes: one on easy levels, more on hard ones, scaled by the
# weapon's cooldown so fast weapons need more hits and slow ones fewer.
func hits_to_kill() -> int:
	var cooldown: float = player.weapon.get("cooldown", 0.3) if player and "weapon" in player else 0.3
	return 1 + roundi(TIME_TO_KILL[clampi(stars, 0, 5)] / cooldown)


func weapon_damage() -> int:
	return player.weapon.get("damage", 1) if player and "weapon" in player else 1


func enemy_damage() -> int:
	return 3 + stars


# Seconds between shots from the enemy line: 10.5 s at one star down to 4.5 s at five.
func volley_interval() -> float:
	return maxf(3.5, 12.0 - stars * 1.5)


# A new task: a fresh wave fills the free posts and the task gets its reinforcement allowance.
func start() -> void:
	running = true
	task_token += 1
	reinforcements_left = REINFORCEMENTS_PER_TASK
	var posts := _free_posts(true)
	posts.shuffle()
	for i in range(mini(count - enemies.size(), posts.size())):
		_spawn(posts[i])
	last_posts = enemies.map(func(e): return e.post)


# Removes all enemies (defeat, results); a later start() brings a new wave.
func stop() -> void:
	running = false
	task_token += 1
	for enemy in enemies:
		enemy.queue_free()
	enemies.clear()


func set_speed_scale(value: float) -> void:
	speed_scale = value
	for enemy in enemies:
		enemy.speed_scale = value


func _process(delta: float) -> void:
	# No volleys while the map is open: the player aims on the map and cannot dodge.
	if not running or quiz == null or not quiz.accepting_answers or quiz.map_aiming():
		return
	var shooters := enemies.filter(func(e): return is_instance_valid(e) and e.ready_to_aim())
	if shooters.is_empty():
		return
	volley_left -= delta * speed_scale
	if volley_left <= 0.0:
		volley_left = volley_interval() + randf_range(0.0, 2.0)
		shooters.pick_random().begin_aim()


# A wrong answer: an enemy (or a distant soldier) visibly lands a shot. The HP loss itself is
# applied by the quiz; this only shows where it came from.
func reaction_shot() -> void:
	if player == null:
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


func _spawn(post: Vector3) -> void:
	var enemy = ENEMY_SCENE.instantiate()
	var hits := hits_to_kill()
	enemy.setup(quiz, player, hits * weapon_damage(), enemy_damage(), look, weapon_damage())
	enemy.speed_scale = speed_scale
	# Marches in from the edge of the arena on its side.
	enemy.position = Vector3(signf(post.x) * ENTRY_X, post.y, post.z)
	enemy.post = post
	enemy.died.connect(_on_enemy_died)
	add_child(enemy)
	enemy.build_look(look)
	enemies.append(enemy)


# Posts nobody holds; at the start of a wave also avoids the posts used in the last wave.
func _free_posts(new_wave: bool) -> Array:
	var taken := enemies.map(func(e): return e.post)
	var free := POSTS.filter(func(p): return not taken.has(p))
	var fresh := free.filter(func(p): return not last_posts.has(p))
	return fresh if new_wave and fresh.size() >= count else free


func _on_enemy_died(enemy) -> void:
	enemies.erase(enemy)
	if reinforcements_left <= 0:
		return
	reinforcements_left -= 1
	var fallen_post: Vector3 = enemy.post
	var token := task_token
	await get_tree().create_timer(REINFORCE_DELAY, false).timeout
	if not running or token != task_token or enemies.size() >= count:
		return
	var posts := _free_posts(false).filter(func(p): return p != fallen_post)
	if not posts.is_empty():
		_spawn(posts.pick_random())
