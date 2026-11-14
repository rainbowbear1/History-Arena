extends RefCounted

# Character special abilities, used with the E key in the arena. Each one returns
# the feedback text when it took effect, or "" when it cannot be used right now
# (the use is then not spent).

const INFO := {
	"fifty_fifty": {"name": "Даналық", "description": "Екі қате жауапты алып тастайды"},
	"slow_time": {"name": "Дала желі", "description": "Нысаналар мен жаулар 8 секунд баяулайды"},
	"extra_time": {"name": "Қосымша уақыт", "description": "Тапсырмаға +10 секунд қосады"},
	"shield": {"name": "Қалқан", "description": "Келесі зақымды толық бөгейді"},
	"heal": {"name": "Емдеу", "description": "+25 HP қалпына келтіреді"},
	"double_score": {"name": "Ерлік", "description": "Келесі шешілген тапсырма екі есе ұпай береді"},
}

const SLOW_FACTOR := 0.4
const SLOW_SECONDS := 8.0
const EXTRA_SECONDS := 10.0
const HEAL_AMOUNT := 25


static func apply(id: String, quiz) -> String:
	match id:
		"fifty_fifty":
			if quiz.current_task.has_method("remove_wrong") and quiz.current_task.remove_wrong(2):
				return "Екі қате жауап алынып тасталды"
		"slow_time":
			if not quiz.slow_active:
				quiz.set_slow(true)
				return "Уақыт баяулады!"
		"extra_time":
			if quiz.timer_running():
				quiz.time_left += EXTRA_SECONDS
				return "+%d секунд" % EXTRA_SECONDS
		"shield":
			if not quiz.shield_active:
				quiz.shield_active = true
				return "Қалқан белсенді"
		"heal":
			if quiz.health < quiz.max_health:
				quiz.health = mini(quiz.health + HEAL_AMOUNT, quiz.max_health)
				quiz.update_hud()
				return "+%d HP" % HEAL_AMOUNT
		"double_score":
			if not quiz.double_score_active:
				quiz.double_score_active = true
				return "Келесі жауап ×2 ұпай"
	return ""
