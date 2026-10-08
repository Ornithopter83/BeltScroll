extends SceneTree

const CAPTURE_PATH := "res://assets/art/review/actual_gameplay_capture.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)
const SUCCESS_MARKER := "actual-game-capture: saved real 1920x1080 Window Viewport frame"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var godot_executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var success_output: Array = []
	var success_status := OS.execute(godot_executable, ["--path", project_path, "--script", "res://tools/capture_actual_game.gd"], success_output, true)
	_check(success_status == 0, "windowed capture process exits successfully (code %d)" % success_status)
	_check(_output_contains(success_output, SUCCESS_MARKER), "capture process reports the rendered PNG success marker")
	if success_status != 0:
		for line in success_output:
			push_error(str(line))

	var image := Image.new()
	var load_error := image.load(CAPTURE_PATH)
	_check(load_error == OK, "actual game capture PNG loads")
	if load_error == OK:
		_check(image.get_size() == EXPECTED_SIZE, "capture is exactly 1920x1080")
		_check(_has_rendered_content(image), "capture contains varied rendered scene pixels, not a blank image")

	var headless_output: Array = []
	var headless_status := OS.execute(godot_executable, ["--headless", "--path", project_path, "--script", "res://tools/capture_actual_game.gd"], headless_output, true)
	_check(headless_status != 0, "renderer-unavailable capture exits nonzero (code %d)" % headless_status)
	_check(_output_contains(headless_output, "active display server is headless"), "renderer-unavailable failure explains the missing windowed renderer")
	var option_output: Array = []
	var option_status := OS.execute(godot_executable, ["--path", project_path, "--script", "res://tools/capture_actual_game.gd", "--", "--headless"], option_output, true)
	_check(option_status != 0, "option-like output path is rejected as a usage error (code %d)" % option_status)
	_check(_output_contains(option_output, "output paths cannot be command-line options"), "option-like output path does not get treated as a PNG filename")
	_finish()

func _has_rendered_content(image: Image) -> bool:
	var first_color := image.get_pixel(0, 0)
	var varied_samples := 0
	for y in range(40, EXPECTED_SIZE.y, 80):
		for x in range(40, EXPECTED_SIZE.x, 80):
			if _color_distance_squared(image.get_pixel(x, y), first_color) > 0.0025:
				varied_samples += 1
	return varied_samples >= 12

func _color_distance_squared(left: Color, right: Color) -> float:
	var difference := left - right
	return difference.r * difference.r + difference.g * difference.g + difference.b * difference.b

func _output_contains(output: Array, fragment: String) -> bool:
	for line in output:
		if str(line).contains(fragment):
			return true
	return false

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("actual_game_capture_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("actual_game_capture_smoke: " + failure)
	push_error("actual_game_capture_smoke: %d check(s) failed" % failures.size())
	quit(1)
