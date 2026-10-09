extends SceneTree

const CAPTURE_SCRIPT := "res://tools/capture_player_skill_interruption_window.gd"
const EVIDENCE_PATH := "res://assets/art/review/player_skill_interruption_window.png"
const REPORT_PATH := "res://docs/review/player_skill_interruption_gate.md"
const SUCCESS_MARKER := "player_skill_interruption_window: all checks passed"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_check(false, "실제 Window post-draw를 수집하는 캡처 게이트 실행 환경")
		_finish()
		return
	var output: Array = []
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var exit_code := OS.execute(executable, ["--path", project_path, "--script", CAPTURE_SCRIPT], output, true)
	_check(exit_code == 0, "Window 통합 캡처 게이트 성공 (code %d)" % exit_code)
	_check(_contains(output, SUCCESS_MARKER), "Window 캡처 게이트가 전체 검수 통과를 보고")
	var report_file := FileAccess.open(REPORT_PATH, FileAccess.READ)
	var report := report_file.get_as_text() if report_file != null else ""
	if report_file != null: report_file.close()
	_check(report.contains("12개") and report.contains("frame_post_draw"), "보고서에 12개 단계·방향 시나리오와 post-draw 근거 기록")
	_check(report.contains("AttackArea") and report.contains("receive_hit") and report.contains("player_hit"), "상대 실제 공격 경로와 피격 이벤트·프레임 시각 기록")
	_check(report.contains("가드") and report.contains("KO") and report.contains("hit-stop") and report.contains("재시작"), "전투 회귀 항목 기록")
	var evidence := Image.new()
	var image_error := evidence.load(EVIDENCE_PATH)
	_check(image_error == OK and evidence.get_size() == Vector2i(1920, 1080), "우향·좌향 실제 Window post-draw PNG 저장")
	if exit_code != 0:
		for line in output: push_error(str(line))
	_finish()

func _contains(lines: Array, fragment: String) -> bool:
	for line in lines:
		if str(line).contains(fragment): return true
	return false

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("player_skill_interruption_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures: push_error("player_skill_interruption_smoke: " + failure)
		quit(1)
