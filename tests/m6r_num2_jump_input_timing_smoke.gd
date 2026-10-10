extends SceneTree

const SUCCESS_MARKER := "display_num_input_window: all checks passed"
const CAPTURE_PATH := "display_num_input_window.png"
const REPORT_PATH := "display_num_input_window.txt"
const REPEAT_COUNT := 5

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_failures_add("real Window display server is required for the synthetic keypad integration run")
		_finish()
		return
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var exit_code := OS.execute(executable, ["--path", project_path, "--script", "res://tools/capture_display_num_input.gd"], output, true)
	_check(exit_code == 0, "Num2 timing capture process exits successfully (code %d)" % exit_code)
	_check(_contains(output, SUCCESS_MARKER), "capture passes keypad mapping, attack gate, and idle jump checks")
	_check(_contains(output, "recovery") and _contains(output, "combo_hold"), "capture separately observes attack recovery and combo_hold")
	_check(_contains(output, "rise, fall, and landing"), "capture observes jump motion over physics frames")
	_check(_contains(output, "PHYSICAL_KEYBOARD: NOT_TESTED (synthetic InputEventKey only)"), "synthetic events are distinguished from physical OS keyboard input")
	var report_path := OS.get_temp_dir().path_join(REPORT_PATH)
	var report := FileAccess.open(report_path, FileAccess.READ)
	var report_text := report.get_as_text() if report != null else ""
	if report != null:
		report.close()
	_check(report_text.contains("attack_num2_probe=recovery_pressed_and_combo_hold_blocked"), "report records the blocked Num2 attack window")
	_check(report_text.contains("num2_jump_repetitions=%d" % REPEAT_COUNT), "report records five repeated idle jump cycles")
	for repetition in range(1, REPEAT_COUNT + 1):
		_check(report_text.contains("num2_run_%d=rise:true,fall:true,land:true" % repetition), "run %d records rise, fall, and landing" % repetition)
	var capture_path := OS.get_temp_dir().path_join(CAPTURE_PATH)
	var evidence_image := Image.new()
	var image_error := evidence_image.load(capture_path)
	_check(image_error == OK and not evidence_image.is_empty(), "real Window evidence PNG is readable")
	if exit_code != 0:
		for line in output:
			push_error(str(line))
	_finish()

func _failures_add(description: String) -> void:
	failures.append(description)

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
		print("m6r_num2_jump_input_timing_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("m6r_num2_jump_input_timing_smoke: " + failure)
	push_error("m6r_num2_jump_input_timing_smoke: %d check(s) failed" % failures.size())
	quit(1)
