extends SceneTree
"""Smoke checks the isolated run-stride review gate and its Window evidence."""

const CAPTURE_SCRIPT := "res://tools/capture_player_run_cycle_review.gd"
const CAPTURE_PATH := "res://assets/art/review/player_run_cycle_review.png"
const V1_PATH := "res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png"
const V2_GLOB := "run_stride_v2"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.file_exists(V1_PATH), "existing v1 run-stride drawing is present")
	_check(FileAccess.file_exists(CAPTURE_SCRIPT), "isolated real-Window capture script is present")
	var script_text := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	_check(script_text.contains("MODE_WINDOWED") and script_text.contains("RenderingServer.frame_post_draw"), "review counts actual rendered Window frames")
	_check(script_text.contains("NOT_ACQUIRED") and script_text.contains(V2_GLOB), "missing v2 is explicitly recorded and searched by filename")
	_check(script_text.contains("SUPPORT CANDIDATE") and script_text.contains("ALPHA BOUNDS CENTER"), "support-foot annotation is distinguished from alpha bounds")
	_check(script_text.contains("not_derivable_from_single_drawing"), "single-frame source does not claim a measured stride period")
	_check(script_text.contains("player_or_manifest_integration=none"), "review-only candidate is kept out of Player and manifest")
	_check(FileAccess.file_exists(CAPTURE_PATH), "review board PNG evidence exists")
	if FileAccess.file_exists(CAPTURE_PATH):
		var image := Image.new()
		var error := image.load(ProjectSettings.globalize_path(CAPTURE_PATH))
		_check(error == OK and image.get_size() == Vector2i(1920, 1500), "review board is a readable 1920x1500 PNG")
	if failures.is_empty():
		print("player_run_cycle_review_smoke: isolated v1/v2 gate and Window evidence are present")
		quit(0)
		return
	for failure in failures:
		push_error("player_run_cycle_review_smoke: " + failure)
	quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)




