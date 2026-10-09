extends SceneTree

const SCENE_PATH := "res://scenes/review/player_candidate_motion.tscn"
const SCRIPT_PATH := "res://scripts/review/player_candidate_motion.gd"
const MANIFEST_PATH := "res://data/art/animation_manifest.json"
const REQUIRED_ART := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_jump_rise_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_startup_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_startup_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
]
var failures: Array[String] = []
var _manifest_before := ""

func _initialize() -> void:
	_manifest_before = FileAccess.get_file_as_string(MANIFEST_PATH)
	call_deferred("_run")

func _run() -> void:
	_check(FileAccess.file_exists(SCENE_PATH), "독립 검수 씬이 존재")
	_check(FileAccess.file_exists(SCRIPT_PATH), "검수 동작 스크립트가 존재")
	for path in REQUIRED_ART:
		_check(FileAccess.file_exists(path), "필수 원화 확인: " + path.get_file())
	var source := FileAccess.get_file_as_string(SCRIPT_PATH)
	var capture_source := FileAccess.get_file_as_string("res://tools/capture_player_jump_motion_review.gd")
	_check(source.contains("--review-capture") and source.contains("RenderingServer.frame_post_draw"), "실제 Window post-draw 캡처 경로 포함")
	_check(source.contains("[원화 미확보]") and source.contains("NUM4_CANDIDATES"), "Num4 후보 미확보 상태를 표시")
	_check(source.contains("duration_source") and source.contains("interpolation") and source.contains("ALPHA_THRESHOLD"), "duration 출처, 보간 설정, alpha 기준 구현")
	_check(source.contains("elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png") and source.contains("미구현"), "safe 상승 원화와 미구현 정점/하강 구간을 구분")
	_check(capture_source.contains("_update_jump") and capture_source.contains("physics_frame") and capture_source.contains("frame_post_draw"), "격리 캡처가 실제 Player 점프 함수·물리 틱·Window post-draw를 동기화")
	_check(capture_source.contains("APEX / PROCEDURAL") and capture_source.contains("FALL / PROCEDURAL") and capture_source.contains("SINGLE MIRROR"), "정점/하강 절차 표시와 좌향 단일 미러 캡처")
	_check(source.contains("FRAME_SIZE := 192.0") and source.contains("DISPLAY_SCALE := 3.0"), "192px 게임 크기와 3배 표시 상수")
	_check(source.contains("func stop_playback") and source.contains("func select_group") and source.contains("_step_clip"), "전환·재생 중단 제어 구현")
	_check(source.contains("KEY_KP_4") and source.contains("Num4 돌진 접촉"), "Num4 keypad 입력과 돌진 후보 상태 처리")
	var capture_path := "res://assets/art/review/player_candidate_motion_strip.png"
	_check(FileAccess.file_exists(capture_path), "실제 Window 캡처 산출물이 존재")
	if FileAccess.file_exists(capture_path):
		var capture := Image.new()
		_check(capture.load(ProjectSettings.globalize_path(capture_path)) == OK and capture.get_size() == Vector2i(3840, 3240), "6개 Window 프레임으로 구성한 읽기 가능한 캡처 스트립")
	var jump_capture_path := "res://assets/art/review/player_jump_motion_strip.png"
	_check(FileAccess.file_exists(jump_capture_path), "Player 물리 시계와 동기화한 jump Window 스트립이 존재")
	if FileAccess.file_exists(jump_capture_path):
		var jump_capture := Image.new()
		_check(jump_capture.load(ProjectSettings.globalize_path(jump_capture_path)) == OK and jump_capture.get_size() == Vector2i(1920, 2000), "도약 직전부터 착지까지 10개 post-draw 프레임 캡처")
	var dash_art := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png"
	_check(FileAccess.file_exists(dash_art), "Num4 전방 돌진 접촉 후보 원화 확보")
	var scene := load(SCENE_PATH) as PackedScene
	_check(scene != null, "검수 씬 리소스를 불러옴")
	if scene != null:
		var review := scene.instantiate()
		root.add_child(review)
		await process_frame
		var initial: Dictionary = review.call("get_review_state")
		_check(initial.name == "대기 · 승인" and initial.playing, "idle에서 장면이 시작")
		review.call("select_group", 1)
		var run_state: Dictionary = review.call("get_review_state")
		_check(run_state.name == "달리기 · v1 후보", "상태 전환 시 해당 후보로 변경")
		review.call("_step_clip", 1)
		var second_stride: Dictionary = review.call("get_review_state")
		_check(second_stride.name == "달리기 · v2 반대 보폭 후보", "상태 내 원화 순환")
		review.call("_set_facing", false)
		_check(not (review.call("get_review_state") as Dictionary).facing_right, "좌향 전환")
		review.call("stop_playback")
		var stopped: Dictionary = review.call("get_review_state")
		await create_timer(0.2).timeout
		var still_stopped: Dictionary = review.call("get_review_state")
		_check(not stopped.playing and still_stopped.name == stopped.name, "중단 후 프레임이 유지")
		review.call("select_group", 3)
		_check((review.call("get_review_state") as Dictionary).name == "1타 startup 후보", "startup 후보 상태 선택")
		review.call("select_group", 5)
		_check((review.call("get_review_state") as Dictionary).name == "Num4 돌진 접촉 후보", "확보된 원화가 있을 때 Num4 상태 선택")
		var clips: Array = review.get("_clips")
		var saved_dash_path: String = clips[9].path
		clips[9]["path"] = "res://assets/art/player/definitely_missing_candidate.png"
		review.call("select_group", 5)
		_check(not (review.call("get_review_state") as Dictionary).available, "선택한 원화가 누락되면 재생을 막고 누락 상태를 기록")
		clips[9]["path"] = saved_dash_path
		review.call("select_group", 5)
		_check((review.call("get_review_state") as Dictionary).available, "원화 복구 후 후보 미리보기를 다시 불러옴")
		review.queue_free()
	await process_frame
	_check(FileAccess.get_file_as_string(MANIFEST_PATH) == _manifest_before, "검수 장면이 animation manifest를 변경하지 않음")
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

