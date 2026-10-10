extends SceneTree
"""Exercise the M6K Window capture and validate its review evidence."""

const TOOL_PATH := "res://tools/capture_m6k_motion_window.gd"
const VIDEO_PATH := "res://temp/ProjectHub/attachments/30319a1f00274afb8876fbb88d14dd9ahq/BeltScroll (DEBUG) 2026-10-10 12-23-33.mp4"
const CONTACT_SHEET_PATH := "res://assets/art/review/m6k_motion_contact_sheet.png"
const REPORT_PATH := "res://docs/review/m6k_motion_video_gate.md"
const CONTACT_SHEET_SIZE := Vector2i(2560, 1440)

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var tool := FileAccess.get_file_as_string(TOOL_PATH)
	_check(not tool.is_empty() and load(TOOL_PATH) != null, "실제 Window 캡처 도구가 존재하고 파싱됨")
	for marker in ["Input.parse_input_event", "KEY_KP_4", "KEY_KP_5", "KEY_KP_3", "RenderingServer.frame_post_draw", "root.get_texture()"]:
		_check(tool.contains(marker), "캡처 도구에 %s 사용" % marker)
	_check(tool.contains("physics_frame=%d") and tool.contains("visual_signoff=pending"), "프레임 타이밍을 기록하고 자동 캡처와 시각 승인을 구분")
	_check(FileAccess.file_exists(VIDEO_PATH), "26.52초 기준 MP4 첨부가 존재")
	var video := FileAccess.open(VIDEO_PATH, FileAccess.READ)
	_check(video != null and video.get_length() > 1000000, "기준 MP4 파일 크기를 확인")
	var report := FileAccess.get_file_as_string(REPORT_PATH)
	_check(report.contains("UNVERIFIED") and report.contains("사람의 시각 승인"), "기준 비교 한계와 사람의 시각 승인 대기 상태를 명시")
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var status := OS.execute(executable, ["--path", project_path, "--script", TOOL_PATH], output, true)
	var log := "\n".join(PackedStringArray(output))
	_check(status == 0, "실제 Window에서 모션 프레임 캡처 실행(종료 코드 %d)" % status)
	_check(log.contains("M6K_SUMMARY|fail=0|frames=16|visual_signoff=pending"), "모든 16개 동작 상태 캡처와 자동 승인 제외를 기록")
	_check(log.contains("physics_frame=") and log.contains("num4_interrupt_return") and log.contains("num5_interrupt_return"), "물리 프레임과 Num4/Num5 중단 후 복귀 상태를 기록")
	var image := Image.new()
	var image_error := image.load(CONTACT_SHEET_PATH)
	_check(image_error == OK, "실제 Window 프레임 contact sheet를 불러옴")
	if image_error == OK:
		_check(image.get_size() == CONTACT_SHEET_SIZE, "16개 1280x720 캡처를 동일 640x360 셀로 배열")
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6k_motion_window_smoke: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("m6k_motion_window_smoke: " + failure)
	print("m6k_motion_window_smoke: FAIL count=%d" % _failures.size())
	quit(1)
