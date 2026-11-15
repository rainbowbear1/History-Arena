extends SceneTree

# Prints the question audit (question_audit.gd) for every level and the medical-help bank:
#   godot --headless --path . --script res://tools/audit_questions.gd
# The exit code is the number of problems found.

const QuestionValidator := preload("res://question_validator.gd")
const QuestionAudit := preload("res://question_audit.gd")


func _initialize() -> void:
	run.call_deferred()


func run() -> void:
	var problems := 0
	var files: Array = []
	for level in root.get_node("LevelDatabase").levels:
		files.append([level["id"], level["question_file"]])
	files.append(["medical", "res://questions/medical.json"])
	for entry in files:
		var result := QuestionValidator.load_file(entry[1])
		var issues := QuestionAudit.audit(result.questions)
		issues.append_array(result.errors)
		var counts := {1: 0, 2: 0, 3: 0}
		for q in result.questions:
			counts[int(q.get("difficulty", 0))] = counts.get(int(q.get("difficulty", 0)), 0) + 1
		print("%s  %s: %d questions, difficulty %.2f (easy %d / medium %d / hard %d), %d problems" % [
			str(entry[0]), entry[1].get_file(), result.questions.size(), QuestionAudit.average_difficulty(result.questions),
			counts[1], counts[2], counts[3], issues.size()])
		for issue in issues:
			print("    - ", issue)
		problems += issues.size()
	quit(problems)
