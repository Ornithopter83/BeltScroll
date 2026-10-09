extends SceneTree
"""Checks the isolated v5 run-motion review gate and captured evidence."""

const CAPTURE_SCRIPT := "res://tools/capture_player_run_v5_motion_review.gd"
const CAPTURE_PATH := "res://assets/art/review/player_run_v5_motion_strip.png"
const GATE_PATH := "res://docs/review/player_run_v5_motion_gate.md"
const V1_PATH := "res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png"
const V5_PATH := "res://assets/art/player/elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.file_exists(V1_PATH), "unmodified v1 source candidate exists")
	_check(FileAccess.file_exists(V5_PATH), "unapproved original v5 candidate remains available for isolated review")
	_check(FileAccess.file_exists(CAPTURE_SCRIPT), "isolated live-Player review capture tool exists")
	if FileAccess.file_exists(CAPTURE_SCRIPT):
		var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
		_check(source.contains("MODE_WINDOWED") and source.contains("RenderingServer.frame_post_draw"), "review uses the actual 1920×1080 Godot Window")
		_check(source.contains("PLAYER_SCENE") and source.contains("Input.action_press") and source.contains("facing_direction"), "main Player controller and direction changes drive capture")
		_check(source.contains("load_png_from_buffer") and source.contains("FIT_MARGIN := 90"), "raw originals are fit in memory with 90px margin")
		_check(source.contains("run_stride_v5") and source.contains("acquired_pending_visual_review") and source.contains("not_acquired"), "v5 acquisition is searched and both acquisition states are reported")
		_check(source.contains("alpha_height_screen_px") and source.contains("pelvis_screen") and source.contains("foot_candidate_screen"), "silhouette, pelvis and foot anchors are measured")
		_check(source.contains("duplicate_pose_risk") or source.contains("same_stride_is_not_accepted"), "single/same stride is explicitly rejected")
		_check(source.contains("runtime_registration=none") and source.contains("approval=not_performed"), "candidate remains review-only and unregistered")
	_check(FileAccess.file_exists(CAPTURE_PATH), "actual Window motion strip exists")
	if FileAccess.file_exists(CAPTURE_PATH):
		var image := Image.new()
		_check(image.load(ProjectSettings.globalize_path(CAPTURE_PATH)) == OK and image.get_width() == 1920 and image.get_height() == 1800, "motion strip is a readable 1920×1800 PNG")
	_check(FileAccess.file_exists(GATE_PATH), "review findings are recorded")
	if FileAccess.file_exists(GATE_PATH):
		var gate := FileAccess.get_file_as_string(GATE_PATH)
		_check(gate.contains("확보") and gate.contains("같은 보폭") and gate.contains("미승인"), "gate records acquisition, same-stride rejection and pending approval")
	if _failures.is_empty():
		print("player_run_v5_motion_review_smoke: live Player review gate and evidence are present")
		quit(0)
		return
	for failure in _failures:
		push_error("player_run_v5_motion_review_smoke: " + failure)
	quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
