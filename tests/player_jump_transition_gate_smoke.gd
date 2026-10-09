extends SceneTree
"""Checks jump gate capture evidence and independent candidate availability."""

const CAPTURE_SCRIPT := "res://tools/capture_player_jump_transition_gate.gd"
const CAPTURE_PATH := "res://assets/art/review/player_jump_transition_gate.png"
const RISE_SAFE := "res://assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png"
const FALL_CANDIDATE := "res://assets/art/player/elven_fighter_jump_fall_v1_candidate_1254x1254.png"
const PLAYER_SCRIPT := "res://scripts/player/player_controller.gd"
const EXPECTED_CAPTURE_SIZE := Vector2i(1920, 2000)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	var player_source := FileAccess.get_file_as_string(PLAYER_SCRIPT)
	_check(not source.is_empty(), "전용 실제 Window 캡처 스크립트 존재")
	_check(FileAccess.file_exists(RISE_SAFE), "기존 rise safe 후보 존재 여부 독립 확인: %s" % str(FileAccess.file_exists(RISE_SAFE)))
	_check(FALL_CANDIDATE != RISE_SAFE and source.contains(FALL_CANDIDATE), "fall 후보 경로를 rise 후보와 독립적으로 지정")
	_check(source.contains("_rise_available = FileAccess.file_exists(RISE_SAFE)") and source.contains("_fall_available = FileAccess.file_exists(FALL_CANDIDATE)"), "rise/fall 후보 존재 여부를 별도 확인")
	_check(source.contains("DisplayServer.get_name() == \"headless\"") and source.contains("RenderingServer.frame_post_draw"), "headless 거부 및 실제 Window post-draw 캡처")
	_check(source.contains("_start_jump") and source.contains("_update_jump") and source.contains("jump_height_offset") and source.contains("jump_vertical_velocity"), "Player 점프 시작 및 실제 jump clock으로 연속 phase 진행")
	_check(source.contains("GAME_CANVAS := 192.0") and source.contains("ART_SCALE := GAME_CANVAS / ART_SIZE") and source.contains("_art_bounds_192"), "phase silhouette measurements use a common 192px game canvas")
	_check(source.contains("foot_anchor_y") and source.contains("shadow_alpha") and source.contains("authored_pop=") and source.contains("review_marker="), "발 anchor, shadow alpha, Player pop, 검수 표식을 phase 별 기록")
	_check(source.contains("boundary_anchor_delta") and source.contains("boundary_silhouette_delta"), "인접 phase 간 발 anchor와 silhouette 크기 차이를 기록")
	_check(source.contains("idle 실루엣 절차 대체") and source.contains("정점 원화 미확보") and source.contains("Player 착지 팝 없음"), "fall 대체, 미확보 apex, 미구현 착지 pop을 구분")
	_check(source.contains("_art.texture = fall if _fall_available else idle"), "fall 후보가 없을 때만 procedural idle proxy 사용")
	_check(player_source.contains("@export var jump_height: float = 120.0") and player_source.contains("@export var jump_velocity: float = 536.66") and player_source.contains("@export var released_jump_gravity_multiplier: float = 2.4"), "Player 점프 물리 설정이 승인된 기존 값 그대로임")
	_check(FileAccess.file_exists(CAPTURE_PATH), "실제 Window 캡처 산출물 존재")
	if FileAccess.file_exists(CAPTURE_PATH):
		var capture := Image.new()
		var loaded := capture.load(ProjectSettings.globalize_path(CAPTURE_PATH)) == OK
		_check(loaded and capture.get_size() == EXPECTED_CAPTURE_SIZE, "10개 우향/좌향 Window 프레임으로 된 1920×2000 산출물")
		if loaded:
			_check(capture.get_format() == Image.FORMAT_RGBA8, "PNG 캡처가 RGBA8로 다시 로드됨")
	print("JUMP_GATE_SMOKE candidates rise_safe=%s fall_candidate=%s fall_proxy=%s" % [str(FileAccess.file_exists(RISE_SAFE)), str(FileAccess.file_exists(FALL_CANDIDATE)), str(not FileAccess.file_exists(FALL_CANDIDATE))])
	if failures.is_empty():
		print("player_jump_transition_gate_smoke: PASS; image review approval is still pending")
		quit(0)
		return
	for failure in failures:
		push_error("player_jump_transition_gate_smoke: " + failure)
	quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
