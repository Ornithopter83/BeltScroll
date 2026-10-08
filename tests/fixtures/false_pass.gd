extends SceneTree

func _initialize() -> void:
	print("false_pass: all checks passed")
	push_error("false_pass: intentional runtime failure after the success marker")
	quit(0)
