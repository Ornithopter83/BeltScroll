extends SceneTree

const CAPTURE_SCRIPT := "res://tools/capture_player_skill1_contact_motion.gd"
const CAPTURE_IMAGE := "res://assets/art/review/player_skill1_contact_motion_strip.png"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SAFE_CANDIDATE := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png"
const MANIFEST := "res://data/art/animation_manifest.json"
const EXPECTED_STRIP_SIZE := Vector2i(3840, 5400)

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
	var player_scene_source := FileAccess.get_file_as_string(PLAYER_SCENE)
	_check(not source.is_empty(), "독립 Num4 접촉 동작 캡처 스크립트가 존재")
	_check(source.contains("res://scenes/player/player.tscn") and player_scene_source.contains("res://scripts/player/player_controller.gd"), "실제 Player 장면과 본편 Player controller를 사용")
	_check(source.contains("physics_frame") and source.contains("RenderingServer.frame_post_draw"), "Player 물리 시계와 실제 Window post-draw를 캡처 시점에 사용")
	_check(source.contains("skill_phase_remaining") and source.contains("Skill1Hitbox") and source.contains("global_position.x"), "phase 시계·Num4 hitbox·전진 거리를 기록")
	_check(source.contains("0.16") and source.contains("0.12") and source.contains("0.42"), "Num4 startup/active/recovery 기준을 캡처에 표시")
	_check(source.contains("SAFE_CANDIDATE") and source.contains("IsolatedSafeCandidatePreview"), "safe 원화는 독립 미리보기 노드에서만 사용")
	_check(source.contains("192.0 / float(_candidate_bounds.size.y)") and source.contains("1920, 1080"), "192px 표시 높이와 1920x1080 Window 캡처를 설정")
	_check(source.contains("CaptureReceiver") and source.contains("hit_landed") and source.contains("impact pop"), "실제 hit receiver 접촉과 impact pop 확인 정보를 기록")
	_check(source.contains("num5.call(\"_request_skill\", 2)") and source.contains("NUM5 ROTATION REFERENCE"), "Num5 회전 동작을 같은 배율로 별도 기록")
	_check(source.contains("for facing_right in [true, false]") and source.contains("POSES"), "우향과 좌향의 연속 phase 캡처를 각각 수행")
	_check(FileAccess.file_exists(PLAYER_SCENE) and FileAccess.file_exists(SAFE_CANDIDATE), "Player 장면과 기존 safe 후보 원화를 읽을 수 있음")
	_check(FileAccess.file_exists(MANIFEST) and not source.contains("animation_manifest.json"), "manifest 파일을 캡처 스크립트에서 쓰지 않고 그대로 둠")
	var image := Image.new()
	var load_error := image.load(ProjectSettings.globalize_path(CAPTURE_IMAGE))
	_check(load_error == OK and image.get_size() == EXPECTED_STRIP_SIZE, "10개 1920x1080 Window 프레임 스트립이 3840x5400 크기로 존재")
	if _failures.is_empty():
		print("player_skill1_contact_motion_smoke: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("player_skill1_contact_motion_smoke: " + failure)
	quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
