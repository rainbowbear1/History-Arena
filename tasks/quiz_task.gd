extends RefCounted

# Base for one question played on the arena. The quiz manager creates the task,
# calls start(), then forwards every target hit to on_target_hit() and reacts to
# the returned Outcome (scoring, HP, feedback, moving on).

enum Outcome {
	NONE,      # Nothing to score (e.g. selecting the first half of a pair).
	PROGRESS,  # A correct step; the task continues.
	MISTAKE,   # A wrong step; costs HP, the task continues.
	SOLVED,    # Task finished correctly.
	FAILED,    # Task finished incorrectly.
}

const Target := preload("res://answer_target.gd")

var question: Dictionary
var quiz  # The quiz manager, used for spawning targets and boards.

# Optional text for the feedback label after the last hit; cleared by the quiz manager.
var message: String = ""


func start(new_question: Dictionary, quiz_manager) -> void:
	question = new_question
	quiz = quiz_manager
	_build()


# Short instruction shown under the question.
func hint() -> String:
	return ""


func on_target_hit(_target) -> Outcome:
	return Outcome.NONE


func _build() -> void:
	pass
