extends SceneTree
"""Verifies the M6O live-Window capture contract and its recorded result."""

const BOSS_SCRIPT := "res://scripts/enemies/ruins_warden_boss.gd"
const CAPTURE_TOOL := "res://tools/capture_m6o_boss_f10_window.gd"
const REPORT_PATH := "res://docs/review/m6o_boss_overlap_window_gate.md"

var _failures := PackedStringArray()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var boss_source := FileAccess.get_file_as_string(BOSS_SCRIPT)
	var capture_source := FileAccess.get_file_as_string(CAPTURE_TOOL)
	var report := FileAccess.get_file_as_string(REPORT_PATH)
	_check(not boss_source.is_empty(), "production Boss source exists")
	_check(not capture_source.is_empty() and load(CAPTURE_TOOL) != null, "Window capture script exists and parses")
	_check(boss_source.contains("attack_area.get_overlapping_bodies()") and boss_source.contains("attack_area.get_overlapping_areas()"), "Boss damage is driven by real Area2D overlaps")
	_check(boss_source.contains("105.0 if attack_kind == SLAM else 66.0"), "slash/slam center depth limits remain 66/105 px")
	_check(not boss_source.contains("global_position.distance_to") and not boss_source.contains("distance <="), "no Boss distance-only hit fallback is present")
	_check(capture_source.contains("get_overlapping_bodies()") and capture_source.contains("get_overlapping_areas()") and capture_source.contains("get(\"health\")"), "capture records physical overlaps and observed HP")
	_check(not capture_source.contains("receive_hit(") and not capture_source.contains("set(\"health\""), "capture does not fake hits or mutate HP")
	_check(capture_source.contains("DisplayServer.get_name() == \"headless\"") and capture_source.contains("root.get_texture().get_image()"), "capture requires rendered Window frames")
	_check(report.contains("M6O") and report.contains("PASS") and report.contains("human_window_approval=PENDING") and report.contains("사람 Window 승인: PENDING"), "report has a passing automated result and separate pending human approval")
	_check(report.contains("slash_right_inner") and report.contains("slash_left_inner") and report.contains("slash_outside_circle") and report.contains("slash_overlap_beyond_66_depth"), "report includes slash directions, radius edge, and depth gate")
	_check(report.contains("slam_inner") and report.contains("slam_overlap_beyond_105_depth") and report.contains("duplicate_body_and_area_overlap") and report.contains("boss_KO_by_Player_J"), "report includes slam, duplicate overlap, and KO evidence")
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6o_boss_overlap_window_smoke: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("m6o_boss_overlap_window_smoke: " + failure)
	quit(1)
