extends SceneTree
"""Structural smoke checks for the manually launched M6I combat arena."""

const ARENA_PATH := "res://scenes/review/m6i_combat_test_arena.tscn"
const PLAYER_PATH := "res://scenes/player/player.tscn"
const RAIDER_PATH := "res://scenes/enemies/forest_raider.tscn"
const ARENA_SCRIPT_PATH := "res://scripts/review/m6i_combat_test_arena.gd"
const DATA_LOADER := preload("res://scripts/game/editor_data_loader.gd")
const CUSTOM_OVERRIDES_PATH := "res://temp/m6i_combat_test_arena_overrides_smoke.json"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var arena_scene := load(ARENA_PATH) as PackedScene
	var player_scene := load(PLAYER_PATH) as PackedScene
	var raider_scene := load(RAIDER_PATH) as PackedScene
	_check(arena_scene != null, "F6 연습장 씬을 불러올 수 있음")
	_check(player_scene != null and raider_scene != null, "실제 Player와 ForestRaider 원본 씬 존재")
	var arena_script := load(ARENA_SCRIPT_PATH) as Script
	_check(arena_script != null and arena_script.can_instantiate(), "연습장 관측 스크립트 파싱")
	if arena_scene == null:
		_finish()
		return
	var arena := arena_scene.instantiate()
	root.add_child(arena)
	await process_frame
	var player := arena.get_node_or_null("YSortActors/Player")
	var raider := arena.get_node_or_null("YSortActors/ForestRaider")
	_check(player != null and player.scene_file_path == PLAYER_PATH, "플레이어가 기존 플레이어 씬 인스턴스임")
	_check(raider != null and raider.scene_file_path == RAIDER_PATH, "상대가 기존 ForestRaider 씬 인스턴스임")
	if player != null:
		for hitbox in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
			_check(player.has_node("Hitboxes/" + hitbox), "실제 공격 판정 %s 포함" % hitbox)
		_check(player.has_method("receive_hit") and player.is_in_group("hit_receivers"), "플레이어 피격 콜백과 수신 그룹 유지")
	if raider != null:
		_check(raider.has_node("AttackArea") and raider.has_node("ReceiveArea"), "레이더 공격 및 피격 Area 유지")
		if player != null:
			var saved_data: Dictionary = DATA_LOADER.load_data()
			var saved_player := DATA_LOADER.find_record(saved_data.characters, "Player")
			var saved_raider := DATA_LOADER.find_record(saved_data.enemies, "ForestRaider")
			_check(player.get("walk_speed") == saved_player.get("walk_speed", player.get("walk_speed")), "연습장이 저장된 Player 전투 설정을 적용")
			_check(raider.get("attack_damage") == saved_raider.get("attack_damage", raider.get("attack_damage")), "연습장이 저장된 Raider 전투 설정을 적용")
			_check_custom_saved_overrides(arena, player, raider)
	_check(arena.has_node("TestHUD/Panel/Margin/Rows/AttackStatus"), "기본 공격 단계 표시")
	_check(arena.has_node("TestHUD/Panel/Margin/Rows/SkillStatus"), "스킬 phase 표시")
	_check(arena.has_node("TestHUD/Panel/Margin/Rows/CooldownStatus"), "스킬 쿨다운 표시")
	_check(arena.has_node("TestHUD/Panel/Margin/Rows/HitstunStatus"), "피격 경직 잔여시간 표시")
	_check(arena.has_node("TestHUD/Panel/Margin/Rows/Controls"), "키보드 조작 안내 표시")
	var bindings := InputMap.action_get_events("skill_1")
	_check(bindings.any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).keycode == KEY_KP_4), "Num4가 기존 skill_1 입력에 연결")
	bindings = InputMap.action_get_events("skill_2")
	_check(bindings.any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).keycode == KEY_KP_5), "Num5가 기존 skill_2 입력에 연결")
	arena.queue_free()
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _check_custom_saved_overrides(arena: Node, player: Node, raider: Node) -> void:
	var file := FileAccess.open(CUSTOM_OVERRIDES_PATH, FileAccess.WRITE)
	if file == null:
		_check(false, "임시 override JSON 생성")
		return
	file.store_string("""{"schema_version":1,"characters":[{"id":"Player","max_health":9,"walk_speed":321.0,"attack_damage":4,"skill_cooldowns":[2.4,3.7]}],"enemies":[{"id":"ForestRaider","max_health":12,"walk_speed":155.0,"attack_damage":5,"attack_knockback":450.0,"attack_hit_stun":0.5,"attack_range":120.0,"recovery_duration":0.8,"windup_duration":0.5,"active_duration":0.2,"ai":{"notice_range":720.0,"attack_depth_tolerance":42.0,"separation_radius":120.0,"separation_strength":130.0}}],"stages":[]}""")
	file.close()
	arena.call("_apply_saved_combat_settings", CUSTOM_OVERRIDES_PATH)
	_check(int(player.get("max_health")) == 9 and int(player.get("health")) == 9, "저장된 Player 최대 체력과 초기 체력 적용")
	_check(is_equal_approx(float(player.get("walk_speed")), 321.0) and int(player.get("attack_damage")) == 4, "저장된 Player 이동 속도와 공격력 적용")
	_check(int(raider.get("max_health")) == 12 and int(raider.get("health")) == 12 and int(raider.get("attack_damage")) == 5, "저장된 Raider 체력과 공격력 적용")
	_check(is_equal_approx(float(raider.get("attack_range")), 120.0), "저장된 Raider 공격 범위 적용")
	var shape := raider.get_node("AttackArea/CollisionShape2D").shape as RectangleShape2D
	_check(is_equal_approx(shape.size.x, 98.4), "저장된 Raider 공격 범위가 실제 AttackArea 형상에 적용")
	player.set("skill_cooldowns", [0.0, 0.0])
	player.call("_request_skill", 1)
	var cooldowns: Array = player.get("skill_cooldowns")
	_check(is_equal_approx(float(cooldowns[0]), 2.4), "저장된 Num4 쿨다운이 skill_started에서 적용")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CUSTOM_OVERRIDES_PATH))
func _finish() -> void:
	if FileAccess.file_exists(CUSTOM_OVERRIDES_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(CUSTOM_OVERRIDES_PATH))
	if _failures.is_empty():
		print("m6i_combat_test_arena_smoke: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("m6i_combat_test_arena_smoke: " + failure)
	quit(1)
