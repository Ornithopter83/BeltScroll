extends SceneTree
"""Runs the real Window timing capture and checks its evidence artifacts."""

const TOOL_PATH := "res://tools/capture_m6i_combat_timing_window.gd"
const REPORT_PATH := "res://docs/review/m6i_combat_timing_window_gate.md"
const IMAGE_PATH := "res://assets/art/review/m6i_combat_timing_matrix.png"
const EXPECTED_WIDTH := 1920

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var tool := FileAccess.get_file_as_string(TOOL_PATH)
	_check(not tool.is_empty(), "timing capture tool exists")
	_check(load(TOOL_PATH) != null, "timing capture tool parses")
	_check(tool.contains("Input.parse_input_event") and tool.contains("physical_keyboard") and tool.contains("auto_input_event"), "physical and generated keyboard events are distinguished")
	_check(tool.contains("attack_phase") and tool.contains("skill_phase") and tool.contains("hitstun_remaining") and tool.contains("attack_hit"), "live attack, skill and player reaction states are observed")
	_check(not tool.contains("set(\"health\"") and not tool.contains("_begin_attack") and not tool.contains("receive_hit("), "no direct health mutation or internal combat invocation")
	_check(DisplayServer.get_name() != "headless", "Godot Window renderer is available")
	if DisplayServer.get_name() != "headless":
		var output: Array = []
		var status := OS.execute(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "--script", TOOL_PATH], output, true)
		var log := "\n".join(PackedStringArray(output))
		_check(status == 0, "live Window capture exits without FAIL records")
		_check(not log.contains("M6I|FAIL|"), "capture trace has no FAIL measurements")
		_check(log.contains("source=auto_input_event"), "generated keyboard input is labeled in the trace")
		_check(log.contains("basic_1") and log.contains("Num4") and log.contains("Num5"), "basic attacks and both keypad skills are represented")
		_check(log.contains("M6I_SUMMARY|fail=0") and log.contains("captures=20"), "capture emits a zero-failure summary and 20 Window frames")
		var report := FileAccess.get_file_as_string(REPORT_PATH)
		_check(report.contains("UNVERIFIED") and report.contains("physical_keyboard"), "report preserves unobserved items and input provenance")
		var image := Image.new()
		var load_error := image.load(ProjectSettings.globalize_path(IMAGE_PATH))
		_check(load_error == OK, "real Window timing matrix PNG decodes")
		if load_error == OK:
			_check(image.get_width() == EXPECTED_WIDTH and image.get_height() >= 360, "contact sheet uses 640x360 cells in three columns")
	_finish()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)

func _finish() -> void:
	if _failures.is_empty():
		print("m6i_combat_timing_window_smoke: PASS")
		quit(0)
		return
	for message in _failures:
		push_error("m6i_combat_timing_window_smoke: " + message)
	quit(1)
