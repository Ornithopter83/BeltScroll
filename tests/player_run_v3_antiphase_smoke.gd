extends SceneTree
"""Checks the v3 not-acquired result and preserves the #70 v1/v2 rejection evidence."""

const REVIEW_SCRIPT := "res://tools/review_player_run_v3_antiphase.gd"
const REVIEW_IMAGE := "res://assets/art/review/player_run_v3_antiphase_strip.png"
const V1 := "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png"
const V2 := "res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png"
const V3_DIR := "res://assets/art/player"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.file_exists(V1) and FileAccess.file_exists(V2), "#70 v1/v2 safe inputs remain available")
	var v3_name := _find_v3()
	_check(not v3_name.is_empty(), "run_stride_v3 candidate is discovered in the player art folder")
	_check(FileAccess.file_exists(REVIEW_SCRIPT), "independent v3 acquisition gate tool exists")
	var source := FileAccess.get_file_as_string(REVIEW_SCRIPT)
	_check(source.contains("MODE_WINDOWED") and source.contains("RenderingServer.frame_post_draw"), "review requests a real Window and captures post-draw frames")
	_check(source.contains("acquired_pending_visual_review") and source.contains("duplicate_pose_risk"), "acquired v3 remains pending and #70 duplicate-pose risk is explicit")
	_check(source.contains("player_or_manifest_integration=none") and source.contains("approval=not_performed"), "review does not approve or connect any candidate")
	_check(FileAccess.file_exists(REVIEW_IMAGE), "actual Window evidence strip exists")
	if FileAccess.file_exists(REVIEW_IMAGE):
		var image := Image.new()
		var error := image.load(ProjectSettings.globalize_path(REVIEW_IMAGE))
		_check(error == OK and image.get_size() == Vector2i(1920, 1500), "Window evidence is a readable 1920×1500 PNG")
	if _failures.is_empty():
		print("player_run_v3_antiphase_smoke: v3 capture path available; #70 finding retained; no approval or integration")
		quit(0)
		return
	for failure in _failures:
		push_error("player_run_v3_antiphase_smoke: " + failure)
	quit(1)

func _find_v3() -> String:
	var dir := DirAccess.open(V3_DIR)
	if dir == null:
		return "missing-directory"
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.to_lower().ends_with(".png") and name.to_lower().contains("run_stride_v3"):
			dir.list_dir_end()
			return name
		name = dir.get_next()
	dir.list_dir_end()
	return ""

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_failures.append(message)
