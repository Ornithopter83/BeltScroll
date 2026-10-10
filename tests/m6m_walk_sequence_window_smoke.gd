extends SceneTree
"""Smoke contract for the isolated M6M walk sequence review scene."""

const SCENE_PATH := "res://scenes/review/m6m_walk_sequence_lab.tscn"
const SCRIPT_PATH := "res://scripts/review/m6m_walk_sequence_lab.gd"
const GATE_PATH := "res://docs/review/m6m_walk_sequence_gate.md"
const SOURCES := [
	"res://assets/art/player/elven_fighter_walk_opposite_stride_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_walk_passing_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png",
]

func _initialize() -> void:
	var failures: Array[String] = []
	_check(FileAccess.file_exists(SCENE_PATH), "F6 scene exists", failures)
	_check(FileAccess.file_exists(SCRIPT_PATH), "dedicated sequence lab script exists", failures)
	_check(FileAccess.file_exists(GATE_PATH), "human review gate exists", failures)
	for source in SOURCES:
		_check(FileAccess.file_exists(source), "acquired source exists: " + source.get_file(), failures)
	if FileAccess.file_exists(SCENE_PATH):
		var scene := FileAccess.get_file_as_string(SCENE_PATH)
		_check(scene.contains("m6m_walk_sequence_lab.gd"), "scene attaches only the dedicated review script", failures)
	if FileAccess.file_exists(SCRIPT_PATH):
		var source := FileAccess.get_file_as_string(SCRIPT_PATH)
		_check(source.contains("FRAME_CANVAS_PX := 192.0") and source.contains("duration"), "frames use a 192 px canvas and declare individual durations", failures)
		_check(source.contains("walk_opposite_stride") and source.contains("walk_passing") and source.contains("run_stride_v1"), "three acquired images are explicit independent frames", failures)
		_check(source.contains("support") and source.contains("lifted") and source.contains("pelvis") and source.contains("arms"), "each frame records foot and body phase annotations", failures)
		_check(source.contains("MISSING · 양발 공중") and source.contains("오른발 접지 보폭"), "unsupported contact phases remain visibly MISSING", failures)
		_check(source.contains("_contact_delta_px") and source.contains("_silhouette_jump_px") and source.contains("ROOT_SPEED"), "loop and translation lanes report foot slip and silhouette jump", failures)
		_check(source.contains("KEY_SPACE") and source.contains("KEY_LEFT") and source.contains("KEY_RIGHT"), "F6 preview supports playback pause and frame stepping", failures)
		_check(source.contains("미러·반복 삽입 없음") and source.contains("Player/manifest/allowlist 연결 없음"), "candidate art remains isolated and is never mirrored or duplicated", failures)
	if failures.is_empty():
		print("m6m_walk_sequence_window_smoke: isolated frames, MISSING phases, and locomotion measurements are present")
		quit(0)
		return
	for failure in failures:
		push_error("m6m_walk_sequence_window_smoke: " + failure)
	quit(1)

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
