extends SceneTree
"""Executes live keypad skill cases and validates the generated target trace."""

const TOOL_PATH := "res://tools/capture_m6i_combat_timing_window.gd"
const REPORT_PATH := "res://docs/review/m6j_skill_target_trace_gate.md"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var tool := FileAccess.get_file_as_string(TOOL_PATH)
	_check(not tool.is_empty() and load(TOOL_PATH) != null, "capture tool exists and parses")
	_check(tool.contains("Input.parse_input_event") and tool.contains("KEY_KP_4") and tool.contains("KEY_KP_5"), "Num4 and Num5 are driven through keypad input events")
	_check(tool.contains("get_instance_id()") and tool.contains("hp_before") and tool.contains("physics_frame") and tool.contains("skill_id"), "per-target ID, health, frame, and skill evidence is recorded")
	_check(not tool.contains("target.receive_hit(") and not tool.contains("call(\"_check_skill_hitbox") and not tool.contains("set(\"health\""), "the harness does not invoke damage or hit functions or overwrite health")
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", TOOL_PATH], output, true)
	var log := "\n".join(PackedStringArray(output))
	_check(status == 0, "live skill target trace exits without FAIL")
	_check(log.contains("M6J_SUMMARY|fail=0"), "capture summary reports zero failures")
	for skill_name in ["Num4/single", "Num4/same_area_pair", "Num4/out_of_range", "Num4/persistent_overlap", "Num5/single", "Num5/same_area_pair", "Num5/out_of_range", "Num5/persistent_overlap"]:
		_check(log.contains(skill_name), skill_name + " scenario was executed")
	var report := FileAccess.get_file_as_string(REPORT_PATH)
	_check(report.contains("인스턴스 ID") and report.contains("HP 전→후") and report.contains("같은 프레임 신호 수"), "review gate contains per-target hit evidence columns")
	_check(report.contains("이전 Num4 중복 신호 원인") and report.contains("same_area_pair"), "review gate explains the prior same-frame signal and multi-target distinction")
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6j_skill_target_trace_window_smoke: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("m6j_skill_target_trace_window_smoke: " + failure)
	quit(1)
