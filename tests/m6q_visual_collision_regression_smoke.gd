extends SceneTree
"""Runs the M6Q continuous actual-Window capture; approval remains human-owned."""

const CAPTURE_SCRIPT := "res://tools/capture_m6q_visual_collision_regression.gd"
const REPORT_PATH := "res://docs/review/m6q_user_video_regression_gate.md"
const SHEET_PATH := "res://assets/art/review/m6q_visual_collision_regression_sheet.png"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var capture_script := load(CAPTURE_SCRIPT)
	if capture_script == null:
		push_error("M6Q: capture script could not be loaded")
		quit(1)
		return
	var result: Dictionary = await capture_script.capture(self)
	if not bool(result.get("ok", false)):
		push_error("M6Q: actual Window capture failed: %s" % str(result.get("error", "unknown error")))
		quit(1)
		return
	if not bool(result.get("body_sources_exclusive", false)):
		push_error("M6Q: at least one captured frame did not have exactly one visible full-body sprite")
		quit(1)
		return
	if str(result.get("video_sha256", "")) != "391F5EA5CFB20245D90C44BDB3B8D565E708254A20EBEF2C828324F7411577D1":
		push_error("M6Q: input video hash did not match the requested SHA256")
		quit(1)
		return
	if int(result.get("rows", 0)) < 60:
		push_error("M6Q: capture produced fewer than 60 per-frame records")
		quit(1)
		return
	if not FileAccess.file_exists(REPORT_PATH) or not FileAccess.file_exists(SHEET_PATH):
		push_error("M6Q: report or visual sheet is missing")
		quit(1)
		return
	var report := FileAccess.open(REPORT_PATH, FileAccess.READ)
	var contents := report.get_as_text()
	_check(contents.contains("**UNVERIFIED**"), "reference MP4 timing uncertainty remains UNVERIFIED")
	_check(contents.contains("걷기 캐릭터 중복") and contents.contains("1타 다중 실루엣") and contents.contains("지면의 공격 판정"), "three reported defects are recorded independently")
	_check(contents.contains("육안 승인은 **PENDING**"), "visual approval is separate and pending")
	_check(contents.contains("Hitbox1_2_3_center_size_monitoring") and contents.contains("PoseSprite1.effective_alpha"), "frame telemetry includes shape and pose-layer values")
	_check(contents.contains("F10 ON 관측 `true`; F10 OFF 관측 `true`"), "F10 overlay was captured ON and returned OFF")
	_check(contents.contains("attack1_active_f10_on") and contents.contains("combo_hold_2") and contents.contains("attack2_active") and contents.contains("attack3_active") and contents.contains("walk_f10_off"), "walk and all three consecutive attacks were captured")
	_check(contents.contains("WalkMotionCandidate.effective_alpha") and contents.contains("full_body_source_count") and contents.contains("전신 소스 수 검사: `PASS`"), "actual walk candidate alpha and per-frame single-body count are recorded")
	if _failures.is_empty():
		print("M6Q_VISUAL_COLLISION_SUMMARY|frames=%d|hash=match|single_body=pass|comparison=UNVERIFIED|visual_approval=pending" % int(result.get("rows", 0)))
		quit(0)
		return
	for failure in _failures:
		push_error("m6q_visual_collision_regression_smoke: " + failure)
	quit(1)

var _failures := PackedStringArray()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
