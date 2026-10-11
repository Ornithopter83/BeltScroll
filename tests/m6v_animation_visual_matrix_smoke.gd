extends SceneTree
"""Artifact smoke for the real-Window M6V animation review packet."""

const IMAGE_PATH := "res://assets/art/review/m6v_animation_quality_contact_sheet.png"
const REPORT_PATH := "res://docs/review/m6v_animation_visual_acceptance_matrix.md"
const TOOL_PATH := "res://tools/capture_m6v_animation_comparison_window.gd"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "smoke itself runs under a Window renderer")
	_check(FileAccess.file_exists(IMAGE_PATH), "contact sheet image exists")
	_check(FileAccess.file_exists(REPORT_PATH), "visual acceptance matrix exists")
	_check(FileAccess.file_exists(TOOL_PATH), "continuous main-scene capture tool exists")
	if FileAccess.file_exists(IMAGE_PATH):
		var image := Image.new()
		_check(image.load(ProjectSettings.globalize_path(IMAGE_PATH)) == OK and image.get_width() >= 1280 and image.get_height() >= 720, "contact sheet is a readable multi-card PNG")
	if FileAccess.file_exists(REPORT_PATH):
		var report := FileAccess.get_file_as_string(REPORT_PATH)
		for required in ["scenes/game/main.tscn", "window frame", "발 anchor", "손 anchor", "F10 박스", "UNVERIFIED", "육안", "관절 변형", "체형·얼굴·복장", "프레임 연결", "주먹·F10"]:
			_check(report.to_lower().contains(required.to_lower()), "review report records %s" % required)
		for phase in ["4위상 보행", "정지·우향", "점프 상승", "점프 하강", "착지", "피격", "KO·정착", "J1 startup", "J1 active", "J1 combo_hold", "J1 recovery", "J2 startup", "J2 active", "J2 combo_hold", "J2 recovery", "J3 startup", "J3 active", "J3 recovery", "Num4 startup", "Num4 active", "Num4 recovery", "Num5 startup", "Num5 active", "Num5 recovery"]:
			_check(report.contains(phase), "review report covers %s" % phase)
	if FileAccess.file_exists(TOOL_PATH):
		var source := FileAccess.get_file_as_string(TOOL_PATH)
		_check(source.contains("res://scenes/game/main.tscn"), "capture tool targets the production game scene")
		_check(source.contains("RenderingServer.frame_post_draw"), "capture tool samples consecutive rendered Window frames")
		_check(source.contains("get_fist_contact_global") and source.contains("_f10_box"), "capture tool samples fist anchor and live hitbox geometry")
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6v_animation_visual_matrix_smoke: review artifacts and state coverage are present; no visual approval is inferred")
		quit(0)
		return
	for failure in _failures:
		push_error("m6v_animation_visual_matrix_smoke: " + failure)
	quit(1)
