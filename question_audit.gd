extends RefCounted

# Content checks that go beyond the format (question_validator.gd): a run asks every task of a
# level, so within one level no question may repeat another, test the same fact twice or give
# away another task's answer. Kazakh words are compared by their first letters ("stems"), so case
# endings do not hide a repeat. Run `tools/audit_questions.gd` for a readable report.

const STEM_LENGTH := 5
const MIN_WORD := 4  # Shorter words ("хан", "кім", "жыл") say nothing about the answer.
const NEAR_DUPLICATE := 0.6
# Tasks with one right answer. (A map task names its place on purpose; only the pin is the answer.)
const CHOICE_TYPES := ["single_choice", "fill_blank", "image"]


# Returns a list of readable problems (empty when the level is clean).
static func audit(questions: Array) -> Array[String]:
	var issues: Array[String] = []
	for i in range(questions.size()):
		var a: Dictionary = questions[i]
		var leak := _self_leak(a)
		if not leak.is_empty():
			issues.append("%s: the question text gives away its answer (%s)" % [_name(a), leak])
		for j in range(questions.size()):
			if i == j:
				continue
			var b: Dictionary = questions[j]
			if j > i:
				var similarity := jaccard(stems(a["question"]), stems(b["question"]))
				if similarity >= NEAR_DUPLICATE:
					issues.append("%s and %s are near duplicates (%d%% shared words)" % [_name(a), _name(b), roundi(similarity * 100)])
				if CHOICE_TYPES.has(_type(a)) and CHOICE_TYPES.has(_type(b)) and correct(a) == correct(b):
					issues.append("%s and %s have the same answer \"%s\"" % [_name(a), _name(b), correct(a)])
			if CHOICE_TYPES.has(_type(a)) and reveals(statements(b), correct(a)):
				issues.append("%s gives away the answer of %s (\"%s\")" % [_name(b), _name(a), correct(a)])
	return issues


# Average difficulty (1–3) of the questions that have one.
static func average_difficulty(questions: Array) -> float:
	var total := 0.0
	var counted := 0
	for question in questions:
		if question.has("difficulty"):
			total += question["difficulty"]
			counted += 1
	return total / counted if counted > 0 else 0.0


static func correct(question: Dictionary) -> String:
	return question.get("correct", "")


# Text a task presents as true: its prompt, its pairs and its events. (Wrong options are not
# statements, so a name that only appears as a distractor elsewhere is no leak.)
static func statements(question: Dictionary) -> String:
	var parts := [question["question"]]
	for pair in question.get("pairs", []):
		parts.append(pair["left"])
		parts.append(pair["right"])
	parts.append_array(question.get("items", []))
	return " ".join(parts)


# True when `text` contains the answer: its year, or every significant word of it.
static func reveals(text: String, answer: String) -> bool:
	var years := numbers(answer)
	if not years.is_empty():
		var found := numbers(text)
		return years.all(func(y): return found.has(y))
	var wanted := stems(answer)
	if wanted.is_empty():
		return false
	var present := stems(text)
	return wanted.all(func(s): return present.has(s))


# The correct answer appears in the prompt while none of the wrong options shares those words.
static func _self_leak(question: Dictionary) -> String:
	if not CHOICE_TYPES.has(_type(question)):
		return ""
	var answer := correct(question)
	if not reveals(question["question"], answer):
		return ""
	for option in question["answers"]:
		if option != answer and reveals(question["question"], option):
			return ""
	return answer


static func stems(text: String) -> Array:
	var result := []
	for word in words(text):
		if word.length() >= MIN_WORD and not (word[0] >= "0" and word[0] <= "9"):
			var stem: String = word.substr(0, STEM_LENGTH)
			if not result.has(stem):
				result.append(stem)
	return result


# Every number in the text ("16 желтоқсан 1991" → 16, 1991), so a full date only counts as revealed
# when its day and year both appear.
static func numbers(text: String) -> Array:
	var result := []
	for word in words(text):
		var digits := ""
		for c in word:
			if c >= "0" and c <= "9":
				digits += c
		if not digits.is_empty() and not result.has(digits):
			result.append(digits)
	return result


static func words(text: String) -> Array:
	var result := []
	var current := ""
	for c in text.to_lower():
		if (c >= "0" and c <= "9") or c.to_upper() != c.to_lower():
			current += c
		elif not current.is_empty():
			result.append(current)
			current = ""
	if not current.is_empty():
		result.append(current)
	return result


static func jaccard(a: Array, b: Array) -> float:
	if a.is_empty() or b.is_empty():
		return 0.0
	var shared := a.filter(func(s): return b.has(s)).size()
	return float(shared) / (a.size() + b.size() - shared)


static func _type(question: Dictionary) -> String:
	return question.get("type", "single_choice")


static func _name(question: Dictionary) -> String:
	return question.get("id", question["question"].left(30))
