extends Node

# Saves level results on this device (user:// is IndexedDB in the web build): best score and
# stars per level, which levels are unlocked, and a short history of attempts. Each Google
# account has its own file; best results saved online are merged in after sign-in (Backend).
# Levels unlock by TOTAL score: the sum of each level's best score (so replaying a level only
# counts when it beats that level's best). A level opens once the total reaches its
# "unlock_score" in data/levels.json, and stays open from then on.

const SAVE_PATH := "user://progress.json"
const BOSS_ID := 11
const ALL_IN_ONE_ID := 12
const VERSION := 1
const MAX_HISTORY := 50

var base_path: String = SAVE_PATH  # Guests; each Google account gets its own file next to it.
var path: String = SAVE_PATH
var levels := {}  # "3" -> {"best_score", "stars", "passed", "attempts"}
var history: Array = []
var demo_unlock_all: bool = false
var unlocked: Array = []  # Level ids opened so far (kept even if thresholds change later).
var just_opened: Array = []  # Levels the last recorded attempt opened (for the results screen).
var boss := {"best_score": 0, "attempts": 0, "defeated": false}  # Campaign progress: New Game clears it.
var boss_just_unlocked := false  # The last attempt passed level 10 for the first time.
# Permanent entitlements (not campaign progress): "Unlock Everything" is earned by defeating the
# BOSS once and kept in its own file, which New Game never clears; for a Google account it is also
# stored online (Backend), and administrators have it from their admin record in Firestore.
var unlock_everything_earned := false
var is_admin := false
# All-in-One personal best ({"correct", "answered", "accuracy", "playtime_sec", "score", "completed",
# "key"}, empty before the first run). Not campaign progress: kept with the entitlements.
var all_in_one_best := {}
# Highest BOSS trophy ever earned: 0 none, 1 bronze, 2 silver, 3 gold (trophy_for). Never lowered,
# kept with the entitlements (New Game keeps it); online in achievements/{uid}.
var best_trophy := 0


func _ready() -> void:
	load_data()


func load_data() -> void:
	levels = {}
	history = []
	demo_unlock_all = false
	unlocked = []
	boss = {"best_score": 0, "attempts": 0, "defeated": false}
	_load_entitlements()
	if not FileAccess.file_exists(path):
		return

	var json := JSON.new()
	var data = json.data if json.parse(FileAccess.get_file_as_string(path)) == OK else null
	if not data is Dictionary or data.get("version") != VERSION:
		push_warning("Ignoring unreadable progress file: " + path)
		return

	if data.get("levels") is Dictionary:
		# JSON numbers load as floats; keep the counters whole.
		for key in data["levels"]:
			var entry = data["levels"][key]
			if entry is Dictionary:
				levels[key] = {
					"best_score": int(entry.get("best_score", 0)),
					"stars": int(entry.get("stars", 0)),
					"passed": entry.get("passed", false) == true,
					"attempts": int(entry.get("attempts", 0)),
				}
	if data.get("history") is Array:
		history = data["history"]
	demo_unlock_all = data.get("demo_unlock_all", false) == true
	if data.get("unlocked") is Array:
		unlocked = data["unlocked"].map(func(id): return int(id))
	if data.get("boss") is Dictionary:
		boss = {"best_score": int(data["boss"].get("best_score", 0)), "attempts": int(data["boss"].get("attempts", 0)),
			"defeated": data["boss"].get("defeated", false) == true}
	# Saves from before total-score unlocking: a passed level had opened the next one.
	for key in levels:
		if levels[key]["passed"] and not unlocked.has(int(key) + 1):
			unlocked.append(int(key) + 1)
	refresh_unlocks()


func save_data() -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Cannot save progress: " + path)
		return
	file.store_string(JSON.stringify({
		"version": VERSION,
		"levels": levels,
		"history": history,
		"demo_unlock_all": demo_unlock_all,
		"unlocked": unlocked,
		"boss": boss,
	}, "  "))


# Stores one finished attempt and returns true if it set a new best score for the level.
func record_attempt(attempt: Dictionary) -> bool:
	if int(attempt["level"]) == BOSS_ID:
		return _record_boss(attempt)
	if int(attempt["level"]) == ALL_IN_ONE_ID:
		return _record_all_in_one(attempt)
	var key := str(attempt["level"])
	var boss_was_open := is_boss_unlocked()
	var best: Dictionary = levels.get(key, {"best_score": 0, "stars": 0, "passed": false, "attempts": 0})
	var new_best: bool = attempt["score"] > best["best_score"]

	best["best_score"] = maxi(best["best_score"], attempt["score"])
	best["stars"] = maxi(best["stars"], attempt["stars"])
	best["passed"] = best["passed"] or attempt["passed"]
	best["attempts"] = int(best["attempts"]) + 1
	levels[key] = best

	history.append(attempt)
	if history.size() > MAX_HISTORY:
		history = history.slice(history.size() - MAX_HISTORY)

	just_opened = refresh_unlocks()
	boss_just_unlocked = not boss_was_open and is_boss_unlocked()
	save_data()
	return new_best


# BOSS runs are kept apart from the levels, so they never change the total score.
func _record_boss(attempt: Dictionary) -> bool:
	var new_best: bool = attempt["score"] > boss["best_score"]
	boss["best_score"] = maxi(boss["best_score"], attempt["score"])
	boss["attempts"] = int(boss["attempts"]) + 1
	boss["defeated"] = boss["defeated"] or attempt["passed"]
	if attempt["passed"]:
		earn_unlock_everything()
		earn_trophy(int(attempt["stars"]))
	history.append(attempt)
	if history.size() > MAX_HISTORY:
		history = history.slice(history.size() - MAX_HISTORY)
	just_opened = []
	boss_just_unlocked = false
	save_data()
	return new_best


# All-in-One results never touch the campaign; the best run (all_in_one_key) is kept for good.
func _record_all_in_one(attempt: Dictionary) -> bool:
	var answered := int(attempt.get("answered", 0))
	var correct := int(attempt.get("correct", 0))
	var seconds := int(attempt.get("playtime_sec", 0))
	var key := all_in_one_key(correct, answered, seconds)
	var new_best: bool = all_in_one_best.is_empty() or key > int(all_in_one_best.get("key", -1))
	if new_best:
		all_in_one_best = {"correct": correct, "answered": answered, "accuracy": accuracy_permille(correct, answered),
			"playtime_sec": seconds, "score": int(attempt.get("score", 0)), "completed": attempt.get("completed", false) == true, "key": key}
		_save_entitlements()
	history.append(attempt)
	if history.size() > MAX_HISTORY:
		history = history.slice(history.size() - MAX_HISTORY)
	just_opened = []
	boss_just_unlocked = false
	save_data()
	return new_best


# All-in-One ranking, the same on the device, in the bridge and in firestore.rules: most correct
# answers first, then accuracy (correct per thousand answered), then the shorter active time.
# Character bonuses (double score) never count.
static func all_in_one_key(correct: int, answered: int, seconds: int) -> int:
	return correct * 100000000 + accuracy_permille(correct, answered) * 100000 + (99999 - clampi(seconds, 0, 99999))


static func accuracy_permille(correct: int, answered: int) -> int:
	return 0 if answered <= 0 else correct * 1000 / answered


# 75 -> "01:15", 3725 -> "1:02:05".
static func format_duration(seconds: int) -> String:
	if seconds >= 3600:
		return "%d:%02d:%02d" % [seconds / 3600, seconds / 60 % 60, seconds % 60]
	return "%02d:%02d" % [seconds / 60, seconds % 60]


# All-in-One opens with a BOSS victory (kept for good, like Unlock Everything) or for administrators.
func is_all_in_one_unlocked() -> bool:
	return can_unlock_everything() or boss["defeated"]


# The BOSS tile appears once level 10 has been passed (or with Unlock Everything on).
func is_boss_unlocked() -> bool:
	return demo_unlock_all or level_result(10)["passed"]


func can_unlock_everything() -> bool:
	return unlock_everything_earned or is_admin


# BOSS trophies are measured in correct answers, so a character's score bonus never changes them:
# bronze from 60 %, silver from 75 %, gold from 90 % of the tasks. A BOSS victory is a bronze or better.
static func trophy_for(correct: int, total: int) -> int:
	if total <= 0:
		return 0
	if correct * 100 >= 90 * total:
		return 3
	if correct * 100 >= 75 * total:
		return 2
	if correct * 100 >= 60 * total:
		return 1
	return 0


func earn_trophy(level: int) -> void:
	if level > best_trophy:
		best_trophy = mini(level, 3)
		_save_entitlements()


func earn_unlock_everything() -> void:
	if not unlock_everything_earned:
		unlock_everything_earned = true
		_save_entitlements()


func _entitlements_path() -> String:
	return path.get_basename() + "_entitlements.json"


func _load_entitlements() -> void:
	unlock_everything_earned = false
	all_in_one_best = {}
	best_trophy = 0
	if FileAccess.file_exists(_entitlements_path()):
		var data = JSON.parse_string(FileAccess.get_file_as_string(_entitlements_path()))
		if data is Dictionary:
			unlock_everything_earned = data.get("unlock_everything", false) == true
			best_trophy = clampi(int(data.get("boss_trophy", 0)), 0, 3)
			if data.get("all_in_one_best") is Dictionary and not data["all_in_one_best"].is_empty():
				var best: Dictionary = data["all_in_one_best"]
				all_in_one_best = {}
				for field in ["correct", "answered", "accuracy", "playtime_sec", "score", "key"]:
					all_in_one_best[field] = int(best.get(field, 0))
				all_in_one_best["completed"] = best.get("completed", false) == true


func _save_entitlements() -> void:
	var file := FileAccess.open(_entitlements_path(), FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"unlock_everything": unlock_everything_earned, "all_in_one_best": all_in_one_best, "boss_trophy": best_trophy}))


# Switches to the progress of one account ("" = guest) and loads it.
func use_profile(uid: String) -> void:
	var wanted := base_path if uid.is_empty() else "%s_%s.json" % [base_path.get_basename(), uid.validate_filename()]
	if wanted != path:
		path = wanted
		load_data()


# Merges best results saved online ({"1": {"score", "stars"}, ...}) into this device's progress.
func merge_remote(remote: Dictionary) -> void:
	var changed := false
	for key in remote:
		var entry = remote[key]
		if not entry is Dictionary or not str(key).is_valid_int():
			continue
		var score := int(entry.get("score", 0))
		var stars := clampi(int(entry.get("stars", 0)), 0, 3)
		if score <= 0 and stars <= 0:
			continue
		var best: Dictionary = level_result(int(key)).duplicate()
		if score > best["best_score"] or stars > best["stars"]:
			best["best_score"] = maxi(best["best_score"], score)
			best["stars"] = maxi(best["stars"], stars)
			best["passed"] = best["passed"] or stars > 0
			levels[str(int(key))] = best
			changed = true
	if changed:
		refresh_unlocks()
		save_data()


func level_result(id: int) -> Dictionary:
	return levels.get(str(id), {"best_score": 0, "stars": 0, "passed": false, "attempts": 0})


# Sum of the best score of every level: what unlocks levels (and what the online leaderboard ranks).
func total_score() -> int:
	var total := 0
	for key in levels:
		total += int(levels[key]["best_score"])
	return total


# Total score needed to open a level (0 for level 1).
func unlock_score(id: int) -> int:
	return int(_levels().get_level(id).get("unlock_score", 0)) if id > 1 else 0


func is_unlocked(id: int) -> bool:
	if id == BOSS_ID:
		return is_boss_unlocked()
	if id == ALL_IN_ONE_ID:
		return is_all_in_one_unlocked()
	return demo_unlock_all or id <= 1 or unlocked.has(id) or total_score() >= unlock_score(id)


# Characters open with the era they belong to (data/characters.json "unlock"): {"level": N} when
# level N is open, {"passed": N} once level N has been passed. A character without a rule, and
# every character in demo mode, is open.
func is_character_unlocked(character: Dictionary) -> bool:
	var rule: Dictionary = character.get("unlock", {})
	if demo_unlock_all or rule.is_empty():
		return true
	if rule.has("passed"):
		return level_result(int(rule["passed"]))["passed"]
	return is_unlocked(int(rule["level"]))


# The LevelDatabase autoload (looked up at run time, so this script also compiles on its own).
func _levels() -> Node:
	return (Engine.get_main_loop() as SceneTree).root.get_node("LevelDatabase")


# Records levels the total has reached, so they stay open. Returns the ids opened just now.
func refresh_unlocks() -> Array:
	var opened := []
	var total := total_score()
	for level in _levels().levels:
		var id: int = level["id"]
		if id > 1 and not unlocked.has(id) and total >= unlock_score(id):
			unlocked.append(id)
			opened.append(id)
	return opened


func set_demo_unlock(enabled: bool) -> void:
	demo_unlock_all = enabled
	save_data()


# New Game: clears this device's campaign progress (levels, unlocks, BOSS results, history) for the
# current profile. Permanent entitlements and everything stored online are not touched.
func reset() -> void:
	levels = {}
	history = []
	demo_unlock_all = false
	unlocked = []
	boss = {"best_score": 0, "attempts": 0, "defeated": false}
	save_data()


# 0 stars = not passed. Passing needs pass_percent of the maximum score; 2 stars need 80%;
# 3 stars need 95% without using medical help.
static func stars_for(score: int, max_score: int, pass_percent: float, revivals_used: int) -> int:
	if max_score <= 0:
		return 0
	var percent := minf(100.0, 100.0 * score / max_score)
	if percent < pass_percent:
		return 0
	if percent >= 95.0 and revivals_used == 0:
		return 3
	if percent >= 80.0:
		return 2
	return 1
