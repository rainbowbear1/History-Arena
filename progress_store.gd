extends Node

# Saves level results on this device (user:// is IndexedDB in the web build): best score and
# stars per level, which levels are unlocked, and a short history of attempts. Each Google
# account has its own file; best results saved online are merged in after sign-in (Backend).

const SAVE_PATH := "user://progress.json"
const VERSION := 1
const MAX_HISTORY := 50

var base_path: String = SAVE_PATH  # Guests; each Google account gets its own file next to it.
var path: String = SAVE_PATH
var levels := {}  # "3" -> {"best_score", "stars", "passed", "attempts"}
var history: Array = []
var demo_unlock_all: bool = false


func _ready() -> void:
	load_data()


func load_data() -> void:
	levels = {}
	history = []
	demo_unlock_all = false
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
	}, "  "))


# Stores one finished attempt and returns true if it set a new best score for the level.
func record_attempt(attempt: Dictionary) -> bool:
	var key := str(attempt["level"])
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

	save_data()
	return new_best


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
		save_data()


func level_result(id: int) -> Dictionary:
	return levels.get(str(id), {"best_score": 0, "stars": 0, "passed": false, "attempts": 0})


# Level 1 is always open; each later level opens when the one before it is passed.
func is_unlocked(id: int) -> bool:
	return demo_unlock_all or id <= 1 or level_result(id - 1)["passed"]


func set_demo_unlock(enabled: bool) -> void:
	demo_unlock_all = enabled
	save_data()


func reset() -> void:
	levels = {}
	history = []
	demo_unlock_all = false
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
