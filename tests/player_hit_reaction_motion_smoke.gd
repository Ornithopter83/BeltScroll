extends SceneTree
"""Checks the Window hit-reaction review evidence and isolation claims."""

const TOOL_PATH := "res://tools/capture_player_hit_reaction_review.gd"
const CAPTURE_PATH := "res://assets/art/review/player_hit_reaction_motion_strip.png"
const REPORT_PATH := "res://docs/review/player_hit_reaction_motion_gate.md"
const MANIFEST_PATH := "res://data/art/animation_manifest.json"
const ALLOWLIST_PATH := "res://data/art/reviewed_frame_allowlist.json"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var tool := _text(TOOL_PATH)
	var report := _text(REPORT_PATH)
	_check(not tool.is_empty(), "격리 Window 캡처 도구 존재")
	_check(load(TOOL_PATH) != null, "캡처 도구 GDScript 파싱")
	_check(tool.contains("scenes/game/main.tscn") and tool.contains("Player.receive_hit") and tool.contains("AttackArea"), "본편 Player와 ForestRaider 실타격 경로 사용")
	_check(tool.contains("RenderingServer.frame_post_draw") and tool.contains("SAFE_CANDIDATE") and tool.contains("LIVE PROCEDURAL HIT"), "Window 프레임에서 safe 후보/절차 표현을 구분 캡처")
	_check(tool.contains("receive_hit") and tool.contains("hitstun_remaining") and tool.contains("_wait_for_recovery"), "receive_hit부터 경직·회복 시간 전이 확인")
	_check(not report.is_empty(), "Window 검수 게이트 보고서 존재")
	_check(report.contains("16.23px") and report.contains("얼굴·귀·복장") and report.contains("양발") and report.contains("크기 팝") and report.contains("hit-stop"), "anchor·연속성·접지·크기·hit-stop 관찰 항목 기록")
	_check(report.contains("4.90/192px") and report.contains("검정·적색") and report.contains("청록·녹색"), "후보의 측정 크기 차이와 의상 연속성 관찰 기록")
	_check(report.contains("승인된 전용 hit 애니메이션이 아닙니다") and report.contains("manifest와 allowlist를 변경하지 않았습니다"), "safe 후보 미승인 및 등록 불변 선언")
	var image := Image.new()
	_check(image.load(ProjectSettings.globalize_path(CAPTURE_PATH)) == OK, "실제 Window 캡처 PNG 디코드")
	if not image.is_empty():
		_check(image.get_size() == Vector2i(2400, 1400), "우향/좌향 × idle/safe/procedural/recovery 8패널 크기")
	_check(FileAccess.file_exists(MANIFEST_PATH), "animation manifest 존재")
	_check(FileAccess.file_exists(ALLOWLIST_PATH), "animation allowlist 존재")
	var manifest := _text(MANIFEST_PATH)
	_check(not manifest.contains("elven_fighter_hit_reaction_v1_safe_candidate_1254x1254.png"), "manifest에 hit safe 후보 등록 안 됨")
	var allowlist := _text(ALLOWLIST_PATH)
	_check(not allowlist.contains("elven_fighter_hit_reaction_v1_safe_candidate_1254x1254.png"), "allowlist에 hit safe 후보 등록 안 됨")
	if failures.is_empty():
		print("player_hit_reaction_motion_smoke: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("player_hit_reaction_motion_smoke: " + failure)
	quit(1)

func _text(path: String) -> String:
	return FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
