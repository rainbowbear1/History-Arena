extends RefCounted

# Question sets for the runs that mix the campaign banks: the BOSS (three phases of levels) and
# All-in-One (every campaign task once). Tasks are never created or changed here, only picked from
# the audited banks in questions/*.json; each copy is tagged with "source_level" (its campaign level),
# which the arena shows as "Level 6 — Kazakh Khanate". Task ids are unique across the banks, so a
# task can be picked at most once per run.

const QuestionValidator := preload("res://question_validator.gd")


# {level id: [tasks]} for the given campaign levels (entries of LevelDatabase.levels).
static func load_banks(levels: Array) -> Dictionary:
	var banks := {}
	for level in levels:
		var tasks: Array = QuestionValidator.load_file(level["question_file"]).questions
		banks[int(level["id"])] = tasks.map(func(q): return _tagged(q, int(level["id"])))
	return banks


# The BOSS: for each phase {"levels": [1, 2, 3], "count": 15} `count` different tasks drawn at
# random from those levels together (mixed, not grouped by era). Phases follow each other, so the
# run moves from the early eras to the latest. Returns {"questions": [...], "problems": [...]};
# a phase whose levels hold too few tasks is reported in "problems" and gets only what exists.
static func boss_run(phases: Array, banks: Dictionary, shuffle: bool = true) -> Dictionary:
	var questions := []
	var problems := []
	var used := {}
	for i in range(phases.size()):
		var phase: Dictionary = phases[i]
		var pool := []
		for id in phase.get("levels", []):
			for task in banks.get(int(id), []):
				if not used.has(task.get("id")):
					pool.append(task)
		var count := int(phase.get("count", 0))
		if pool.size() < count:
			problems.append("BOSS phase %d (levels %s) needs %d tasks but the banks hold %d" % [
				i + 1, ", ".join(phase.get("levels", []).map(func(id): return str(int(id)))), count, pool.size()])
		if shuffle:
			pool.shuffle()
		for task in pool.slice(0, count):
			used[task.get("id")] = true
			questions.append(task)
	return {"questions": questions, "problems": problems}


# All-in-One: every task of every campaign bank exactly once, in one random order.
static func all_in_one(banks: Dictionary, shuffle: bool = true) -> Array:
	var questions := []
	var used := {}
	var ids := banks.keys()
	ids.sort()
	for id in ids:
		for task in banks[id]:
			if not used.has(task.get("id")):
				used[task.get("id")] = true
				questions.append(task)
	if shuffle:
		questions.shuffle()
	return questions


static func _tagged(task: Dictionary, level_id: int) -> Dictionary:
	var copy := task.duplicate(true)
	copy["source_level"] = level_id
	return copy
