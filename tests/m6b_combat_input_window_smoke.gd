extends SceneTree
"""Runs the Window capture and guards combat input, reaction, KO, and measurements."""

const TOOL_PATH := "res://tools/capture_m6b_combat_input_window.gd"
const REPORT_PATH := "res://docs/review/m6b_combat_input_gate.md"
const IMAGE_PATH := "res://assets/art/review/m6b_combat_input_window.png"
const EXPECTED_SIZE := Vector2i(1920, 2520)

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var tool_text := FileAccess.get_file_as_string(TOOL_PATH)
	var report_text := FileAccess.get_file_as_string(REPORT_PATH)
	_check(not tool_text.is_empty(), "Window 캡처 도구 존재")
	_check(load(TOOL_PATH) != null, "캡처 도구 GDScript 파싱")
	_check(report_text.contains("시각 인수 미완료") and report_text.contains("절차 변형"), "임시 절차 동작의 아트 승인 미완료 표기")
	_check(tool_text.contains("attack_phase") and tool_text.contains("skill_phase") and tool_text.contains("hitstun_remaining") and tool_text.contains("is_final_down_settled"), "기본 입력·스킬·피격·KO 회귀 상태 검사")
	_check(tool_text.contains("hand_proxy_px") and tool_text.contains("upper_rotation_deg") and tool_text.contains("silhouette_scale") and tool_text.contains("vertical_from_floor"), "주먹 대용점·상체 회전·실루엣 스케일·수직 이동량 측정")
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_failures.append("활성 디스플레이 서버가 headless라서 Window 동작 검증을 실행할 수 없습니다.")
	else:
		var output: Array = []
		var executable := OS.get_executable_path()
		var project_path := ProjectSettings.globalize_path("res://")
		var status := OS.execute(executable, ["--path", project_path, "--script", TOOL_PATH], output, true)
		_check(status == 0, "실제 Window 회귀/캡처 프로세스 종료 코드 0 (code %d)" % status)
		var log := "\n".join(PackedStringArray(output))
		for expected in ["attack_1", "attack_2", "attack_3", "num4_rush", "num5_backfist", "hitstun", "final_down"]:
			_check(log.contains(expected), "%s 계측 로그" % expected)
		var metric_count := log.split("M6B_METRIC|").size() - 1
		_check(metric_count >= 21, "전체 21 프레임 계측행 (%d/21)" % metric_count)
		_check(log.contains("hand_proxy_px=") and log.contains("upper_rotation_deg=") and log.contains("vertical_from_floor="), "Window 캡처의 수치 계측 로그")
		_check(log.contains("21 real Window frames saved"), "21개 실제 Window 프레임 완료 표식")
		if status != 0:
			for line in output:
				push_error(str(line))
		var image := Image.new()
		_check(image.load(ProjectSettings.globalize_path(IMAGE_PATH)) == OK, "실제 Window contact sheet PNG 디코드")
		if not image.is_empty():
			_check(image.get_size() == EXPECTED_SIZE, "7동작×시작/접촉/종료 1920x2520 contact sheet 크기")
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6b_combat_input_window_smoke: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("m6b_combat_input_window_smoke: " + failure)
	quit(1)
