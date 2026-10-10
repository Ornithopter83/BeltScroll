extends SceneTree
"""Contract smoke for the isolated M6R contact review scene."""

const LAB_SCENE := preload("res://scenes/review/m6r_strike_contact_lab.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var lab := LAB_SCENE.instantiate()
	root.add_child(lab)
	current_scene = lab
	await process_frame
	if lab.get_script() == null or not lab.has_method("_apply_timeline_state"):
		_check(false, "검수장 스크립트와 타임라인 API가 로드됨; 계약 검증 중단")
		quit(1)
		return
	var player := lab.get_node_or_null("ContactLabPlayer")
	var dummy := lab.get_node_or_null("ContactLabReceiveTarget")
	_check(player != null and dummy != null, "실제 Player와 적 ReceiveArea를 독립 검수장에 생성")
	if player != null:
		_check(player.get_script() != null and player.has_method("_set_stage_hitbox"), "검수 대상 Player 스크립트가 실제로 로드됨")
		if player.get_script() == null or not player.has_method("_set_stage_hitbox"):
			quit(1)
			return
		_check(player.get_node_or_null("Hitboxes/Hitbox1/CollisionShape2D") != null and player.get_node_or_null("Hitboxes/Hitbox2/CollisionShape2D") != null and player.get_node_or_null("Hitboxes/Hitbox3/CollisionShape2D") != null, "기본 1·2·3타의 실제 Shape가 사용됨")
		_check(player.get_node_or_null("Hitboxes/Skill1Hitbox/CollisionShape2D") != null and player.get_node_or_null("Hitboxes/Skill2Hitbox/CollisionShape2D") != null, "Num4·Num5의 실제 Shape가 사용됨")
		_check(not (player.get_node("Hitboxes/Hitbox1") as Area2D).monitoring, "startup 정지 상태의 공격 영역은 비활성")
		lab.set("_phase_index", 1)
		lab.call("_apply_timeline_state")
		_check((player.get_node("Hitboxes/Hitbox1") as Area2D).monitoring, "active 단계가 실제 공격 Area를 켬")
		lab.set("_phase_index", 2)
		lab.call("_apply_timeline_state")
		_check(not (player.get_node("Hitboxes/Hitbox1") as Area2D).monitoring, "recovery 단계가 실제 공격 Area를 끔")
	_check(dummy != null and dummy.get_node_or_null("ReceiveArea/CollisionShape2D") != null, "적 ReceiveArea의 실제 CollisionShape2D를 표시 대상으로 사용")
	var script_text := FileAccess.get_file_as_string("res://scripts/review/m6r_strike_contact_lab.gd")
	_check(script_text.contains("_computed_pin_world") and script_text.contains("UNVERIFIED") and not script_text.contains("attack_flash"), "원화 좌표 provenance와 미확인 상태를 분리하고 AttackFlash 계측을 금지")
	var overlay := root.get_node_or_null("CombatCollisionOverlay")
	_check(overlay != null, "전역 F10 실제 충돌 Shape 오토로드를 그대로 사용")
	if failures.is_empty():
		print("m6r_strike_contact_lab_window_smoke: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("m6r_strike_contact_lab_window_smoke: " + failure)
	quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
