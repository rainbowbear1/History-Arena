extends SceneTree

# Renders each level's first task and saves a PNG, for checking the look without playing.
#   godot --path . --script res://tools/screenshots.gd -- [levels=1,2,...] [size=1280x720] [out=build/shots] [frames=40] [long]
# Needs a real window (not --headless). "long" swaps in a very long question to check wrapping.

var levels := range(1, 11)
var size := Vector2i(1280, 720)
var out := "build/shots"
var long_question := false
var frames := 40


func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("levels="):
			levels = Array(arg.trim_prefix("levels=").split(",")).map(func(s): return int(s))
		elif arg.begins_with("size="):
			var parts := arg.trim_prefix("size=").split("x")
			size = Vector2i(int(parts[0]), int(parts[1]))
		elif arg.begins_with("out="):
			out = arg.trim_prefix("out=")
		elif arg.begins_with("frames="):
			frames = int(arg.trim_prefix("frames="))
		elif arg == "long":
			long_question = true
	run.call_deferred()


func run() -> void:
	root.size = size
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://" + out))
	var progress := root.get_node("ProgressStore")
	progress.base_path = "user://screenshot_progress.json"
	progress.path = progress.base_path
	progress.set_demo_unlock(true)
	root.get_node("GameState").shuffle_questions = false
	for level in levels:
		root.get_node("GameState").selected_level = level
		var arena: Node = load("res://main.tscn").instantiate()
		root.add_child(arena)
		current_scene = arena
		var quiz = arena.get_node("QuizManager")
		if long_question:
			quiz.set_question("Ұзын сұрақтың үлгісі: " + "Қазақ хандығының тарихындағы маңызды оқиғаларды еске түсіріп, дұрыс жауапты таңдаңыз. ".repeat(2))
		for i in range(frames):
			await process_frame
		var image := root.get_texture().get_image()
		var path := "res://%s/level_%02d%s_%dx%d.png" % [out, level, "_long" if long_question else "", size.x, size.y]
		image.save_png(ProjectSettings.globalize_path(path))
		print("saved ", path)
		arena.queue_free()
		await process_frame
	quit()
