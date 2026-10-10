extends SceneTree
"""High-rate keyboard event stress checks for player combat and stagger."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const HIT := {
	"damage": 0,
	"direction": Vector2.ZERO,
	"knockback": 0.0,
	"hit_stun": 0.24,
	"attack_stage": 2,
}

var failures: Array[String] = []
var player: CharacterBody2D
var started_stages: Array[int] = []
var started_skills: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "실제 Player 씬을 불러옴")
	if packed == null:
		_finish()
		return
	player = packed.instantiate() as CharacterBody2D
	root.add_child(player)
	player.global_position = Vector2(900.0, 800.0)
	player.attack_started.connect(func(stage: int) -> void: started_stages.append(stage))
	player.skill_started.connect(func(skill: int) -> void: started_skills.append(skill))
	await _frames(2)

	# Repeated real key down/up events must stay inside the three-stage combo.
	for _tap in range(8):
		await _tap_action("attack")
	await _wait_attack_idle()
	_check(started_stages == [1, 2], "고속 연타는 한 번의 유효 선입력만 소비하고 단계 순서를 지킴")

	started_stages.clear()
	await _tap_action("attack")
	await _tap_action("attack")
	await _wait_attack_stage(2)
	await _tap_action("attack")
	await _wait_attack_idle()
	_check(started_stages == [1, 2, 3], "각 단계에 보낸 실제 선입력이 1→2→3타 순서로 실행됨")
	await _tap_action("attack")
	await _wait_attack_phase("active")
	_check(player.get_node("Hitboxes/Hitbox1").monitoring, "기본 공격 활성 구간에서 실제 판정이 켜짐")
	player.receive_hit(HIT)
	_check(player.get("attack_phase") == "idle" and not player.get_node("Hitboxes/Hitbox1").monitoring,
		"기본 공격 피격 취소가 잔류 hitbox를 끔")
	await _stun_and_recovery_check()

	# Num4/Num5 during a combo are dropped; cooldown input is also dropped.
	started_skills.clear()
	await _tap_action("attack")
	await _tap_action("skill_1")
	await _tap_action("skill_2")
	_check(player.get("attack_phase") != "idle" and started_skills.is_empty(),
		"공격 중 Num4/Num5가 스킬 상태를 시작하지 않음")
	await _wait_attack_idle()
	await _tap_action("skill_1")
	_check(player.get("skill_phase") == "startup" and started_skills == [1], "Num4 이벤트가 스킬 1을 시작함")
	await _tap_action("skill_1")
	await _tap_action("skill_2")
	_check(started_skills == [1] and player.get("skill_id") == 1,
		"스킬 중 Num4/Num5 재입력은 추가 발동을 만들지 않음")
	await _wait_skill_idle()
	await _tap_action("skill_1")
	_check(started_skills == [1], "쿨다운 중 Num4 재입력이 무시됨")
	player.get("skill_cooldowns")[1] = 0.0
	await _tap_action("skill_2")
	_check(started_skills == [1, 2], "Num5 입력은 다른 스킬 쿨다운과 독립적으로 실행됨")
	await _wait_skill_idle()

	# Interrupt in each skill phase and make sure the live hitbox is released.
	player.get("skill_cooldowns")[0] = 0.0
	await _tap_action("skill_1")
	_check(player.get("skill_phase") == "startup", "피격 전 스킬 선딜 상태 확인")
	player.receive_hit(HIT)
	_check(player.get("skill_phase") == "idle" and not player.get_node("Hitboxes/Skill1Hitbox").monitoring,
		"선딜 피격이 스킬을 취소하고 hitbox를 끔")
	await _stun_and_recovery_check()

	player.get("skill_cooldowns")[0] = 0.0
	await _tap_action("skill_1")
	await _wait_skill_phase("active")
	_check(player.get_node("Hitboxes/Skill1Hitbox").monitoring, "스킬 활성 단계의 실제 판정이 켜짐")
	player.receive_hit(HIT)
	_check(player.get("skill_phase") == "idle" and not player.get_node("Hitboxes/Skill1Hitbox").monitoring,
		"활성 피격 직후 잔류 스킬 hitbox가 꺼짐")
	await _stun_and_recovery_check()

	player.get("skill_cooldowns")[1] = 0.0
	await _tap_action("skill_2")
	await _wait_skill_phase("recovery")
	_check(not player.get_node("Hitboxes/Skill2Hitbox").monitoring, "스킬 후딜에는 판정 hitbox가 꺼져 있음")
	player.receive_hit(HIT)
	_check(player.get("skill_phase") == "idle" and not player.get_node("Hitboxes/Skill2Hitbox").monitoring,
		"후딜 피격이 스킬 잔류 상태를 정리함")
	await _stun_and_recovery_check()

	# A second hit extends stun, and movement/attack/skills stay locked until it ends.
	player.receive_hit(HIT)
	await _frames(4)
	var remaining_before_refresh := float(player.get("hitstun_remaining"))
	var longer_hit := HIT.duplicate()
	longer_hit["hit_stun"] = 0.42
	player.receive_hit(longer_hit)
	_check(float(player.get("hitstun_remaining")) > remaining_before_refresh,
		"연속 피격이 경직 시간을 갱신함")
	var position_during_stun := player.global_position
	await _press_action("move_right")
	await _press_action("attack")
	await _press_action("skill_1")
	await _frames(3)
	_check(player.get("attack_phase") == "idle" and player.get("skill_phase") == "idle",
		"경직 중 공격과 스킬 재발동이 차단됨")
	_check(player.global_position.distance_to(position_during_stun) < 0.01,
		"경직 중 이동 입력이 위치를 바꾸지 않음")
	await _release_action("move_right")
	await _release_action("attack")
	await _release_action("skill_1")
	await _frames(30)
	_check(player.get("hitstun_remaining") == 0.0, "갱신된 경직 시간이 정상적으로 종료됨")
	var free_position := player.global_position
	await _press_action("move_right")
	await _frames(2)
	await _release_action("move_right")
	_check(player.global_position.x > free_position.x, "경직 종료 직후 이동 조작이 복귀함")
	await _tap_action("attack")
	_check(player.get("attack_phase") == "startup", "경직 종료 직후 공격 조작이 복귀함")
	await _wait_attack_idle()

	# Guard is driven by its mapped key; then verify KO is terminal under input.
	player.set("health", 5)
	await _press_action("block")
	await _frames(1)
	_check(player.get("is_blocking"), "가드 키 이벤트가 실제 방어 상태를 만듦")
	var guarded_hit := HIT.duplicate()
	guarded_hit["damage"] = 4
	guarded_hit["hit_stun"] = 0.2
	player.receive_hit(guarded_hit)
	await _release_action("block")
	_check(player.get("health") == 4 and float(player.get("hitstun_remaining")) <= 0.11,
		"가드가 피해와 경직을 줄이고 생존 상태를 유지함")
	await _frames(15)
	player.set("health", 1)
	var ko_count := [0]
	player.player_ko.connect(func() -> void: ko_count[0] += 1)
	var lethal_hit := HIT.duplicate()
	lethal_hit["damage"] = 99
	var ko_position := player.global_position
	player.receive_hit(lethal_hit)
	await _press_action("move_right")
	await _press_action("attack")
	await _press_action("skill_2")
	await _frames(4)
	_check(player.get("is_ko") and ko_count[0] == 1 and player.get("health") == 0,
		"치명타가 KO 신호를 한 번 내고 체력을 0으로 고정함")
	_check(player.get("attack_phase") == "idle" and player.get("skill_phase") == "idle"
		and player.get("hitstun_remaining") == 0.0 and player.global_position.distance_to(ko_position) < 0.01,
		"KO 중 공격·스킬·이동 입력이 차단됨")
	await _release_action("move_right")
	await _release_action("attack")
	await _release_action("skill_2")

	# Overlapping hit-stop requests must restore the pre-hit time scale once.
	var time_scale_before := Engine.time_scale
	player.call("_trigger_hit_stop", 0.10)
	await _frames(2)
	player.call("_trigger_hit_stop", 0.12)
	await create_timer(0.06, true, false, true).timeout
	_check(player.get("_hit_stop_active") and Engine.time_scale <= 0.08,
		"겹친 hit-stop 동안 저속 상태가 유지됨")
	await create_timer(0.12, true, false, true).timeout
	_check(not player.get("_hit_stop_active") and is_equal_approx(Engine.time_scale, time_scale_before),
		"겹친 hit-stop이 완료된 뒤 원래 Engine.time_scale로 복구됨")

	_finish()

func _stun_and_recovery_check() -> void:
	_check(float(player.get("hitstun_remaining")) > 0.0, "피격이 플레이어 경직을 적용함")
	var position_before := player.global_position
	await _press_action("move_right")
	await _press_action("attack")
	await _press_action("skill_2")
	await _frames(2)
	_check(player.get("attack_phase") == "idle" and player.get("skill_phase") == "idle"
		and player.global_position.distance_to(position_before) < 0.01,
		"경직 중 이동·공격·스킬 입력이 차단됨")
	await _release_action("move_right")
	await _release_action("attack")
	await _release_action("skill_2")
	await _frames(20)
	_check(player.get("hitstun_remaining") == 0.0, "짧은 피격 경직이 종료됨")
	await _tap_action("attack")
	_check(player.get("attack_phase") == "startup", "경직 종료 직후 공격 입력이 수용됨")
	await _wait_attack_idle()

func _wait_attack_idle() -> void:
	for _frame in range(120):
		if player.get("attack_phase") == "idle":
			return
		await physics_frame
	_check(false, "기본 공격 상태가 idle로 복귀함")

func _wait_attack_stage(expected_stage: int) -> void:
	for _frame in range(120):
		if int(player.get("attack_stage")) == expected_stage and player.get("attack_phase") != "idle":
			return
		await physics_frame
	_check(false, "기본 공격이 %d단계에 진입함" % expected_stage)

func _wait_attack_phase(expected_phase: String) -> void:
	for _frame in range(120):
		if player.get("attack_phase") == expected_phase:
			return
		await physics_frame
	_check(false, "기본 공격이 %s 상태에 진입함" % expected_phase)

func _wait_skill_idle() -> void:
	for _frame in range(120):
		if player.get("skill_phase") == "idle":
			return
		await physics_frame
	_check(false, "스킬 상태가 idle로 복귀함")

func _wait_skill_phase(expected: String) -> void:
	for _frame in range(120):
		if player.get("skill_phase") == expected:
			return
		await physics_frame
	_check(false, "스킬이 %s 상태에 진입함" % expected)

func _tap_action(action: StringName) -> void:
	await _press_action(action)
	await _release_action(action)

func _press_action(action: StringName) -> void:
	var event := _key_event_for_action(action)
	if event == null:
		_check(false, "%s에 키 입력 이벤트가 매핑되어 있음" % action)
		return
	event.pressed = true
	Input.parse_input_event(event)
	await physics_frame

func _release_action(action: StringName) -> void:
	var event := _key_event_for_action(action)
	if event == null:
		return
	event.pressed = false
	Input.parse_input_event(event)
	await physics_frame

func _key_event_for_action(action: StringName) -> InputEventKey:
	for mapped_event in InputMap.action_get_events(action):
		if mapped_event is InputEventKey:
			return (mapped_event as InputEventKey).duplicate() as InputEventKey
	return null

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("m6j_combat_stagger_stress_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("m6j_combat_stagger_stress_smoke: " + failure)
		quit(1)
