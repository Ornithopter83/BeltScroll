extends SceneTree
"""Structural smoke for the M6J arena HUD and same-session retry records."""

const ARENA_PATH := "res://scenes/review/m6i_combat_test_arena.tscn"
const PLAYER_PATH := "res://scenes/player/player.tscn"
const RAIDER_PATH := "res://scenes/enemies/forest_raider.tscn"
const RECORD_META := "m6j_arena_repeatability_records"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena_scene := load(ARENA_PATH) as PackedScene
	_check(arena_scene != null, "연습장 씬 로드")
	if arena_scene == null:
		_finish()
		return
	var arena := arena_scene.instantiate()
	root.add_child(arena)
	await process_frame
	var player := arena.get_node_or_null("YSortActors/Player")
	var raider := arena.get_node_or_null("YSortActors/ForestRaider")
	_check(player != null and player.scene_file_path == PLAYER_PATH, "원본 Player 씬 인스턴스 사용")
	_check(raider != null and raider.scene_file_path == RAIDER_PATH, "원본 ForestRaider 씬 인스턴스 사용")
	for node_name in ["Controls", "PositionStatus", "AttackStatus", "SkillStatus", "CooldownStatus", "HitstunStatus", "HealthStatus", "RaiderStatus", "RecordStatus", "EventStatus", "ResetHint"]:
		_check(arena.has_node("TestHUD/Panel/Margin/Rows/" + node_name), "HUD에 %s 표시" % node_name)
	if player != null and raider != null:
		_check(player.has_signal("attack_started") and player.has_signal("attack_hit"), "기본 공격 실제 전투 신호 관측")
		_check(player.has_signal("skill_started") and player.has_signal("skill_hit"), "스킬 실제 전투 신호 관측")
		_check(raider.has_signal("raider_hit") and raider.has_signal("raider_ko"), "상대 피격과 KO 신호 관측")
		_check(absf(player.global_position.x - raider.global_position.x) >= 400.0, "시작 시 방향과 수평 거리 확인을 위한 간격 확보")
	_check(arena.has_method("_unhandled_key_input"), "R 키 재시작 처리")
	var cooldown_text := String(arena.get_node("TestHUD/Panel/Margin/Rows/CooldownStatus").text)
	_check(cooldown_text.contains("Num4") and cooldown_text.contains("Num5"), "Num4와 Num5 쿨다운 구별")
	if player != null:
		var skill_1 := InputMap.action_get_events("skill_1")
		var skill_2 := InputMap.action_get_events("skill_2")
		_check(skill_1.any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).keycode == KEY_KP_4), "Num4 입력 바인딩 확인")
		_check(skill_2.any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).keycode == KEY_KP_5), "Num5 입력 바인딩 확인")
		# Emit outcome signals to exercise the read-only session recorder without
		# forcing actor health, cooldown, or hitstun values in the smoke.
		player.emit_signal("player_ko")
		player.emit_signal("player_ko")
		await process_frame
		var first_record: Dictionary = get_meta_record()
		_check(int(first_record.get("failures", 0)) == 1 and int(first_record.get("rounds", 0)) == 1, "실패 결과가 한 번만 세션 기록에 저장")
		arena.queue_free()
		await process_frame
		arena = arena_scene.instantiate()
		root.add_child(arena)
		await process_frame
		var repeated_record: Dictionary = get_meta_record()
		_check(int(repeated_record.get("failures", 0)) == 1 and int(repeated_record.get("rounds", 0)) >= 1, "장면 재생성 뒤에도 세션 결과 유지")
		var raider_again := arena.get_node("YSortActors/ForestRaider")
		raider_again.emit_signal("raider_ko")
		raider_again.emit_signal("raider_ko")
		await process_frame
		var success_record: Dictionary = get_meta_record()
		_check(int(success_record.get("successes", 0)) == 1 and int(success_record.get("rounds", 0)) == 2, "새 씬의 성공 결과는 한 번 기록되고 이전 세션 합계 유지")
		arena.queue_free()
	_finish()

func get_meta_record() -> Dictionary:
	if has_meta(RECORD_META):
		return get_meta(RECORD_META)
	return {}

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6j_arena_repeatability_smoke: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("m6j_arena_repeatability_smoke: " + failure)
	quit(1)
