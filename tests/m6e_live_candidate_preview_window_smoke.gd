extends SceneTree
"""Static smoke checks for the isolated M6E live candidate preview."""

const SCENE_PATH := "res://scenes/review/m6e_live_candidate_preview.tscn"
const SCRIPT_PATH := "res://scripts/review/m6e_live_candidate_preview.gd"
const CAPTURE_PATH := "res://assets/art/review/m6e_live_candidate_preview.png"
const GATE_PATH := "res://docs/review/m6e_live_candidate_preview_gate.md"

func _initialize() -> void:
	var failures: Array[String] = []
	_check(FileAccess.file_exists(SCENE_PATH), "independent Window scene exists", failures)
	_check(FileAccess.file_exists(SCRIPT_PATH), "preview script exists", failures)
	_check(FileAccess.file_exists(CAPTURE_PATH), "preview evidence PNG exists", failures)
	_check(FileAccess.file_exists(GATE_PATH), "review gate exists", failures)
	if FileAccess.file_exists(SCENE_PATH):
		var scene := FileAccess.get_file_as_string(SCENE_PATH)
		_check(scene.contains("type=\"Window\"") and scene.contains("m6e_live_candidate_preview.gd"), "scene root is a dedicated Window", failures)
	if FileAccess.file_exists(SCRIPT_PATH):
		var source := FileAccess.get_file_as_string(SCRIPT_PATH)
		_check(source.contains("forest_ruins_v1_1920x1080.png") and source.contains("elven_fighter_reference_v8_1254x1254.png"), "actual stage and current v8 sources are used", failures)
		_check(source.contains("elven_fighter_dark_fantasy_attack1_sheet_v1_candidate") and source.contains("get_region") and source.contains("FRAME_NAMES"), "M6D 2x2 source cells are extracted in fixed order", failures)
		_check(source.contains("FRAME_DURATION := 0.12") and source.contains("KEY_SPACE") and source.contains("KEY_LEFT") and source.contains("KEY_RIGHT") and source.contains("_looping"), "timed playback, pause, looping and manual stepping are implemented", failures)
		_check(source.contains("_changed_pixels") and source.contains("프레임 변경:") and source.contains("_edge_alpha_counts") and source.contains("_bottom_alpha_anchor") and source.contains("발 기준선") and source.contains("edge_total"), "frame changes, cell edges and grounding defect cues are shown", failures)
		_check(source.contains("approval=not_performed") and source.contains("PlayerArt / manifest / allowlist / 전투 판정 미변경"), "preview states the review isolation boundary", failures)
	_check(not FileAccess.file_exists("res://assets/art/player/m6e_live_candidate_preview.png"), "new art remains under review-only assets", failures)
	if failures.is_empty():
		print("m6e_live_candidate_preview_window_smoke: isolated preview files are present")
		quit(0)
		return
	for failure in failures:
		push_error("m6e_live_candidate_preview_window_smoke: " + failure)
	quit(1)

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
