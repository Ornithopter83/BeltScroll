extends SceneTree
"""Checks the independent run-stride opposition judgment and its real-Window evidence."""

const REVIEW_SCRIPT := "res://tools/review_player_run_stride_opposition.gd"
const REVIEW_IMAGE := "res://assets/art/review/player_run_stride_opposition_strip.png"
const V1 := "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png"
const V2 := "res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.file_exists(V1) and FileAccess.file_exists(V2), "both pre-existing safe run drawings are present")
	_check(FileAccess.file_exists(REVIEW_SCRIPT), "independent review capture tool is present")
	var source := FileAccess.get_file_as_string(REVIEW_SCRIPT)
	_check(source.contains("MODE_WINDOWED") and source.contains("RenderingServer.frame_post_draw"), "capture requires the actual Godot Window and post-draw frames")
	_check(source.contains("RIGHT · A / v1 safe") and source.contains("LEFT · B / mirrored v2"), "right-facing and left-facing A-B-A cases are included")
	_check(source.contains("RUN A → STOP / v8 idle") and source.contains("STOP → RUN A"), "run-to-stop and stop-to-run captures are included")
	_check(source.contains("duplicate_pose_risk") and source.contains("both_support_right_boot=true"), "same-support result is classified as duplicate-pose risk")
	_check(source.contains("player_or_manifest_integration=none") and source.contains("approval=not_performed"), "review does not approve or connect candidates")
	_check(FileAccess.file_exists(REVIEW_IMAGE), "actual Window evidence strip exists")
	if FileAccess.file_exists(REVIEW_IMAGE):
		var image := Image.new()
		var error := image.load(ProjectSettings.globalize_path(REVIEW_IMAGE))
		_check(error == OK and image.get_size() == Vector2i(1920, 1500), "Window capture strip is a readable 1920×1500 PNG")
	if _failures.is_empty():
		print("player_run_stride_opposition_smoke: evidence and duplicate-pose gate are present; no approval or integration performed")
		quit(0)
		return
	for failure in _failures:
		push_error("player_run_stride_opposition_smoke: " + failure)
	quit(1)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
