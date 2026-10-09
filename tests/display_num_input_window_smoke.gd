extends SceneTree

const SUCCESS_MARKER := "display_num_input_window: all checks passed"
const CAPTURE_PATH := "display_num_input_window.png"
const REPORT_PATH := "display_num_input_window.txt"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var exit_code := OS.execute(executable, ["--path", project_path, "--script", "res://tools/capture_display_num_input.gd"], output, true)
	_check(exit_code == 0, "real Window capture process exits successfully (code %d)" % exit_code)
	_check(_contains(output, SUCCESS_MARKER), "Window capture reports a successful keypad and Player state verification")
	_check(_contains(output, "fullscreen_mode="), "fullscreen mode is recorded")
	_check(_contains(output, "window_size="), "actual Window size is recorded")
	_check(_contains(output, "monitor_resolution="), "active monitor resolution is recorded")
	_check(_contains(output, "render_area="), "Window Viewport render area is recorded")
	_check(_contains(output, "PHYSICAL_KEYBOARD: NOT_TESTED"), "physical keyboard verification is explicitly marked not tested")
	_check(_contains(output, "capture_png="), "Window evidence capture path is reported")
	var capture_path := OS.get_temp_dir().path_join(CAPTURE_PATH)
	var report_path := OS.get_temp_dir().path_join(REPORT_PATH)
	var evidence_image := Image.new()
	var image_error := evidence_image.load(capture_path)
	_check(image_error == OK and not evidence_image.is_empty(), "real Window evidence PNG is present and readable")
	var report := FileAccess.open(report_path, FileAccess.READ)
	var report_text := report.get_as_text() if report != null else ""
	if report != null:
		report.close()
	_check(report_text.contains("physical_keyboard_status=NOT_TESTED"), "evidence report records that physical keyboard input was not tested")
	_check(report_text.contains("fullscreen_mode=") and report_text.contains("monitor_resolution=") and report_text.contains("window_size=") and report_text.contains("render_area="), "evidence report includes Window and render measurements")
	_check(report_text.contains("inputmap_attack_expected_key=") and report_text.contains("inputmap_skill_9_expected_key="), "evidence report records expected and configured keypad bindings")
	if exit_code != 0:
		for line in output:
			push_error(str(line))
	_finish()

func _contains(output: Array, fragment: String) -> bool:
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
		print("display_num_input_window_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("display_num_input_window_smoke: " + failure)
	push_error("display_num_input_window_smoke: %d check(s) failed" % failures.size())
	quit(1)
