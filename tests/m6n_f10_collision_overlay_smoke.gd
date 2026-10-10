extends SceneTree
"""Smoke checks for the global F10 collision overlay and live collider inventory."""

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RAIDER_SCENE := preload("res://scenes/enemies/forest_raider.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/ruins_warden_boss.tscn")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var overlay := root.get_node_or_null("CombatCollisionOverlay")
	_check(overlay != null, "전역 F10 오버레이 오토로드가 존재함")
	if overlay == null:
		_finish()
		return
	_check(not bool(overlay.get("enabled")), "실행 직후 오버레이가 OFF")
	var holder := Node2D.new()
	root.add_child(holder)
	current_scene = holder
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	var raider := RAIDER_SCENE.instantiate() as CharacterBody2D
	var boss := BOSS_SCENE.instantiate() as CharacterBody2D
	player.position = Vector2(300, 320)
	raider.position = Vector2(520, 320)
	boss.position = Vector2(740, 320)
	holder.add_child(player)
	holder.add_child(raider)
	holder.add_child(boss)
	await process_frame
	_check(_count_shapes(player) == 6, "Player 몸체·기본 1~3타·Num4/5 실제 CollisionShape2D 6개를 찾음")
	_check(_count_shapes(raider) == 3, "ForestRaider 몸체·공격·피격 영역 3개를 찾음")
	_check(_count_shapes(boss) == 3, "RuinsWardenBoss 몸체·공격·피격 영역 3개를 찾음")
	_check(_has_shape_type(player, "CapsuleShape2D") and _has_shape_type(player, "RectangleShape2D") and _has_shape_type(player, "CircleShape2D"), "캡슐·사각형·원 실제 shape 종류를 모두 식별")
	_check(raider.get_node_or_null("AttackArea") != null and boss.get_node_or_null("AttackArea") != null, "연습용 트리에 Raider와 보스 생성 완료")
	for name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		var area := player.get_node("Hitboxes/" + name) as Area2D
		_check(not area.monitoring, "%s 초기 비활성 monitoring 상태" % name)
		_check(int(area.collision_mask) == 2 and int(area.collision_layer) == 0, "%s 실제 충돌 레이어·마스크를 유지" % name)
	var first := player.get_node("Hitboxes/Hitbox1") as Area2D
	first.monitoring = true
	_check(first.monitoring, "기본 공격 활성화 상태를 실제 monitoring에서 읽음")
	first.monitoring = false
	player.set("facing_direction", Vector2.RIGHT)
	player.call("_set_stage_hitbox", 1, true)
	var right_facing_hitbox_x := first.position.x
	player.set("facing_direction", Vector2.LEFT)
	player.call("_set_stage_hitbox", 1, true)
	_check(right_facing_hitbox_x > 0.0 and first.position.x < 0.0, "캐릭터 방향 전환에 따라 실제 기본 공격 영역 transform이 반전")
	player.call("_set_stage_hitbox", 1, false)
	var attack := raider.get_node("AttackArea") as Area2D
	attack.monitoring = true
	_check(attack.monitoring and int(attack.collision_mask) == 1, "Raider 공격 활성 상태와 실제 mask를 읽음")
	attack.monitoring = false
	var boss_attack := boss.get_node("AttackArea") as Area2D
	boss.call("_begin_attack", "slash")
	var slash_radius := ((boss.get_node("AttackArea/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius
	boss.call("_begin_attack", "slam")
	var slam_radius := ((boss.get_node("AttackArea/CollisionShape2D") as CollisionShape2D).shape as CircleShape2D).radius
	_check(slash_radius == 67.0 and slam_radius == 125.0 and boss_attack.position == Vector2(0, -18), "보스 slash/slam 실제 공격 shape와 위치 변경을 추적")
	var fatal_hit := {"damage": 999, "direction": Vector2.LEFT, "knockback": 1.0, "hit_stun": 0.0, "attack_stage": 3}
	raider.receive_hit(fatal_hit)
	boss.set_combat_active(true)
	boss.receive_hit(fatal_hit)
	_check(int(raider.get("health")) == 0 and int(raider.collision_layer) == 0, "ForestRaider 실제 KO 상태 확인")
	_check(int(boss.get("health")) == 0 and int(boss.collision_layer) == 0, "RuinsWardenBoss 실제 KO 상태 확인")
	var camera := player.get_node("Camera2D") as Camera2D
	camera.make_current()
	await process_frame
	var body_shape := player.get_node("CollisionShape2D") as CollisionShape2D
	var before_zoom := body_shape.get_global_transform_with_canvas().origin
	camera.zoom = Vector2(1.6, 1.6)
	await process_frame
	var after_zoom := body_shape.get_global_transform_with_canvas().origin
	_check(before_zoom.distance_to(after_zoom) > 0.1, "실제 카메라 줌 변화가 화면 투영 좌표에 반영")
	var key := InputEventKey.new()
	key.keycode = KEY_F10
	key.pressed = true
	overlay.call("_input", key)
	_check(bool(overlay.get("enabled")), "F10 입력으로 ON")
	await process_frame
	key.pressed = false
	overlay.call("_input", key)
	key.pressed = true
	overlay.call("_input", key)
	_check(not bool(overlay.get("enabled")), "F10 반복 전환으로 OFF")
	key.echo = false
	overlay.call("_input", key)
	_check(bool(overlay.get("enabled")), "두 번째 F10 입력으로 다시 ON")
	_check(bool(overlay.get("enabled")), "적 생성·KO 상태와 무관하게 전역 표시 상태를 유지")
	var player_packed := PLAYER_SCENE
	var change_error := change_scene_to_packed(player_packed)
	_check(change_error == OK, "씬 재시작 경로에서 Player 씬 교체를 시작")
	await process_frame
	_check(not bool(overlay.get("enabled")), "씬 재시작/교체 후 오버레이가 OFF로 초기화")
	_finish()

func _count_shapes(root_node: Node) -> int:
	var count := 0
	for node in _descendants(root_node):
		if node is CollisionShape2D and node.shape != null:
			count += 1
	return count

func _has_shape_type(root_node: Node, expected_type: String) -> bool:
	for node in _descendants(root_node):
		if node is CollisionShape2D and node.shape != null and node.shape.get_class() == expected_type:
			return true
	return false

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_descendants(child))
	return result

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("m6n_f10_collision_overlay_smoke: 전역 F10 충돌 오버레이 확인 완료")
		quit(0)
		return
	for failure in failures:
		push_error("m6n_f10_collision_overlay_smoke: " + failure)
	quit(1)
