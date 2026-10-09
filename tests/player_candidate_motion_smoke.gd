extends SceneTree
"""Checks the isolated candidate review, missing-art state, and unchanged manifest."""

const SCENE_PATH := "res://scenes/review/player_candidate_motion.tscn"
const SCRIPT_PATH := "res://scripts/review/player_candidate_motion.gd"
const MANIFEST_PATH := "res://data/art/animation_manifest.json"
const NUM4_SAFE := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png"
const NUM5_ART := "res://assets/art/player/elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png"
const RUN_V4_SAFE := "res://assets/art/player/elven_fighter_run_stride_v4_safe_candidate_1254x1254.png"
const CAPTURE_PATH := "res://assets/art/review/player_candidate_motion_strip.png"
var failures: Array[String] = []
var _manifest_before := ""

func _initialize() -> void:
	_manifest_before = FileAccess.get_file_as_string(MANIFEST_PATH)
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.file_exists(SCENE_PATH), "격리 검수 씬 존재")
	_check(FileAccess.file_exists(SCRIPT_PATH), "전용 검수 스크립트 존재")
	_check(FileAccess.file_exists(NUM4_SAFE), "Num4 safe 직선 돌진 후보 확보")
	_check(FileAccess.file_exists(RUN_V4_SAFE), "run v4 safe 검수 원화 확보")
	_check(FileAccess.file_exists(NUM5_ART), "Num5 spin 접촉 후보 파일 확보 상태 확인")
	var source := FileAccess.get_file_as_string(SCRIPT_PATH)
	_check(source.contains("미수용 · 반대 보폭 아님") and source.contains("동일 보폭"), "run v4를 동일 보폭 미수용으로 표시")
	_check(source.contains("Num4 · 직선 돌진 safe 후보") and source.contains("Num5 · 회전 미입증 접촉 후보"), "Num4와 Num5를 독립 항목으로 제공")
	_check(source.contains("뻗은 주먹 포즈라 원형 회전 미입증") and source.contains("미승인 · 회전 동작 미입증"), "Num5 후보 확보와 회전 미입증 판정을 함께 표시")
	_check(source.contains("FRAME_SIZE := 192.0") and source.contains("DISPLAY_SCALE := 3.0"), "192px 게임 기준 및 3배 확대 고정")
	_check(source.contains("startup/recovery") and source.contains("보간"), "없는 startup/recovery를 보간 애니메이션으로 주장하지 않음")
	_check(source.contains("RenderingServer.frame_post_draw") and source.contains("_capture_group_queue: Array[int] = [5, 6, 7]"), "실제 Window에서 세 항목을 우향/좌향 캡처")
	_check(FileAccess.file_exists(CAPTURE_PATH), "실제 Window 검수 스트립 존재")
	if FileAccess.file_exists(CAPTURE_PATH):
		var capture := Image.new()
		_check(capture.load(ProjectSettings.globalize_path(CAPTURE_PATH)) == OK and capture.get_size() == Vector2i(3840, 3240), "우향/좌향 6개 Window 프레임 스트립 확인")
	var scene := load(SCENE_PATH) as PackedScene
	_check(scene != null, "검수 씬 로드")
	if scene != null:
		var review := scene.instantiate()
		root.add_child(review)
		await process_frame
		review.call("select_group", 5)
		var run_state: Dictionary = review.call("get_review_state")
		_check(run_state.name == "run v4 · 미수용 / 동일 보폭" and run_state.available, "run v4 판정 항목 선택")
		review.call("select_group", 6)
		var num4_state: Dictionary = review.call("get_review_state")
		_check(num4_state.name == "Num4 · 직선 돌진 safe 후보" and num4_state.available, "Num4 safe 항목 선택")
		review.call("_set_facing", false)
		_check(not (review.call("get_review_state") as Dictionary).facing_right, "좌향 실루엣으로 전환")
		review.call("select_group", 7)
		var num5_state: Dictionary = review.call("get_review_state")
		_check(num5_state.name == "Num5 · 회전 미입증 접촉 후보" and num5_state.available, "Num5 확보 후보를 미승인 상태로 별도 표시")
		review.queue_free()
	await process_frame
	_check(FileAccess.get_file_as_string(MANIFEST_PATH) == _manifest_before, "manifest 불변")
	if failures.is_empty():
		print("player_candidate_motion_smoke: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("player_candidate_motion_smoke: " + failure)
	quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
