extends SceneTree
"""M6P F10 real-Window pixel gate for each attack and receive shape."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const REPORT_PATH := "res://docs/review/m6p_f10_attack_shape_gate.md"
const TOLERANCE_PX := 4.0
const BASIC_HITBOXES := ["Hitbox1", "Hitbox2", "Hitbox3"]
const CONTROLLED_AREAS := ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]

var _failures := PackedStringArray()
var _rows := PackedStringArray()
var _game: Node2D
var _player: CharacterBody2D
var _raider: CharacterBody2D
var _boss: CharacterBody2D
var _overlay: Node
var _camera: Camera2D
var _pair_count := 0
var _point_count := 0
var _direct_callback_toggles := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server"), "real Godot Window renderer is active")
	_check(root.size.x > 0 and root.size.y > 0, "render Window has nonzero dimensions")
	_overlay = root.get_node_or_null("CombatCollisionOverlay")
	_check(_overlay != null, "CombatCollisionOverlay autoload exists")
	if _overlay == null or DisplayServer.get_name() == "headless":
		_finish()
		return
	_set_overlay(false)
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "live main scene loads")
	if packed == null:
		_finish()
		return
	_game = packed.instantiate() as Node2D
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_player = _game.get_node("YSortActors/Player") as CharacterBody2D
	_raider = _game.get_node("YSortActors/ForestRaider1") as CharacterBody2D
	_boss = _game.get_node("YSortActors/RuinsWardenBoss") as CharacterBody2D
	_check(_player != null and _raider != null and _boss != null, "live Player, Raider, and Boss exist")
	if _player == null or _raider == null or _boss == null:
		_finish()
		return

	# Freeze simulation movement while retaining the production scenes, transforms,
	# shape resources, overlay renderer, and live Window/camera canvas chain.
	_player.global_position = Vector2(960, 780)
	_player.set_physics_process(false)
	_player.set_process(false)
	_raider.global_position = Vector2(1180, 780)
	_raider.set_physics_process(false)
	_raider.set_process(false)
	_boss.global_position = Vector2(770, 780)
	_boss.set_physics_process(false)
	_boss.set_combat_active(true)
	_camera = _player.get_node("Camera2D") as Camera2D
	_camera.position_smoothing_enabled = false
	_camera.make_current()
	await _settle()

	for index in range(BASIC_HITBOXES.size()):
		var stage := index + 1
		_player.call("_begin_attack", stage)
		_player.call("_set_stage_hitbox", stage, true)
		var target := _area_shape(_player, BASIC_HITBOXES[index])
		await _capture_shape_pair("Player 기본 %d타 활성" % stage, target, true)
		_player.call("_set_stage_hitbox", stage, false)
		await _capture_shape_pair("Player 기본 %d타 비활성" % stage, target, false)

	var skill1 := _player.get_node("Hitboxes/Skill1Hitbox") as Area2D
	var skill2 := _player.get_node("Hitboxes/Skill2Hitbox") as Area2D
	_player.set("skill_id", 1)
	_player.call("_set_skill_hitbox_transform")
	_player.call("_set_skill_hitboxes", true)
	await _capture_shape_pair("Player Num4 활성", _area_shape(_player, "Skill1Hitbox"), true)
	_player.call("_set_skill_hitboxes", false)
	await _capture_shape_pair("Player Num4 비활성", _area_shape(_player, "Skill1Hitbox"), false)
	_player.set("skill_id", 2)
	_player.call("_set_skill_hitbox_transform")
	_player.call("_set_skill_hitboxes", true)
	await _capture_shape_pair("Player Num5 활성", _area_shape(_player, "Skill2Hitbox"), true)
	_player.call("_set_skill_hitboxes", false)
	await _capture_shape_pair("Player Num5 비활성", _area_shape(_player, "Skill2Hitbox"), false)
	_check(not skill1.monitoring and not skill2.monitoring, "Num4 and Num5 return to monitoring OFF")

	var raider_attack := _area_shape(_raider, "AttackArea")
	var raider_receive := _area_shape(_raider, "ReceiveArea")
	var raider_attack_area := _raider.get_node("AttackArea") as Area2D
	raider_attack_area.monitoring = true
	await _capture_shape_pair("Raider AttackArea 활성", raider_attack, true)
	raider_attack_area.monitoring = false
	await _capture_shape_pair("Raider AttackArea 비활성", raider_attack, false)
	await _capture_shape_pair("Raider ReceiveArea", raider_receive, false)

	var boss_attack_area := _boss.get_node("AttackArea") as Area2D
	var boss_receive := _area_shape(_boss, "ReceiveArea")
	var boss_attack := _area_shape(_boss, "AttackArea")
	for kind in ["slash", "slam"]:
		_boss.call("_begin_attack", kind)
		boss_attack_area.monitoring = true
		await _capture_shape_pair("Boss %s AttackArea 활성" % kind, boss_attack, true)
		boss_attack_area.monitoring = false
		await _capture_shape_pair("Boss %s AttackArea 비활성" % kind, boss_attack, false)
		await _capture_shape_pair("Boss %s ReceiveArea" % kind, boss_receive, true)
	boss_attack_area.monitoring = false
	_boss.call("_begin_attack", "slash")

	# Mirror facing through production transforms and exercise camera scroll and zoom.
	_player.set("facing_direction", Vector2.LEFT)
	_player.get_node("VisualRoot").scale.x = -1.0
	_player.global_position = Vector2(1210, 780)
	_player.call("_set_stage_hitbox", 2, true)
	_camera.zoom = Vector2(1.35, 1.35)
	await _settle()
	await _capture_shape_pair("Player 2타 좌우 반전 + 카메라 줌/스크롤", _area_shape(_player, "Hitbox2"), true)
	_player.call("_set_stage_hitbox", 2, false)
	_camera.zoom = Vector2(1.2, 1.2)
	_player.global_position = Vector2(960, 780)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	await _settle()

	# KO via production hit handling leaves receive shapes present but inactive.
	_raider.call("receive_hit", _fatal_hit())
	_boss.call("receive_hit", _fatal_hit())
	await _settle()
	await _capture_shape_pair("Raider KO ReceiveArea", raider_receive, false)
	await _capture_shape_pair("Boss KO ReceiveArea", boss_receive, false)
	_check(int(_raider.get("health")) == 0 and int(_boss.get("health")) == 0, "KO snapshots use the real enemy KO state")
	_check(not (_raider.get_node("AttackArea") as Area2D).monitoring and not boss_attack_area.monitoring, "KO leaves enemy attacks inactive")

	# OFF/ON control uses a direct call to the overlay callback. It deliberately does
	# not claim that a physical F10 press or the application's input routing was tested.
	_set_overlay(false)
	var restart_error := reload_current_scene()
	_check(restart_error == OK, "scene restart succeeds")
	await process_frame
	_check(not bool(_overlay.get("enabled")), "scene restart resets F10 overlay to OFF")
	_write_report()
	_finish()

func _capture_shape_pair(title: String, shape_node: CollisionShape2D, expected_active: bool) -> void:
	if shape_node == null or not is_instance_valid(shape_node):
		_check(false, title + ": CollisionShape2D exists")
		return
	_set_overlay(false)
	await _settle()
	_check(not bool(_overlay.get("enabled")), "%s: OFF callback state is active before reference capture" % title)
	var off_image := await _window_image()
	var collision_state := _shape_collision_signature(shape_node)
	var health_state := _health_signature()
	_set_overlay(true)
	await _settle()
	_check(bool(_overlay.get("enabled")), "%s: ON callback state is active before outline capture" % title)
	var on_image := await _window_image()
	var area := shape_node.get_parent() as Area2D
	var actually_active := area != null and area.monitoring
	_check(actually_active == expected_active, "%s: live monitoring=%s matches requested state" % [title, str(expected_active)])
	var color_name := _expected_color(shape_node)
	var points := _outline_points(shape_node)
	var matched := 0
	for local_point in points:
		var screen_point := _shape_point_to_window(shape_node, local_point)
		if _has_color_near(on_image, screen_point, color_name):
			matched += 1
		else:
			print("M6P_F10_PIXEL_MISS: title=%s path=%s color=%s projected=%s tolerance=%.1f" % [title, shape_node.get_path(), color_name, screen_point, TOLERANCE_PX])
	_point_count += points.size()
	_pair_count += 1
	var points_ok := matched == points.size() and not points.is_empty()
	_check(points_ok, "%s: %d/%d %s outline points match within %.0f Window pixels" % [title, matched, points.size(), color_name, TOLERANCE_PX])
	_check(_images_differ(off_image, on_image), "%s: actual Window pixels change between F10 OFF and ON" % title)
	var collision_after := _shape_collision_signature(shape_node)
	_check(collision_state == collision_after, "%s: F10 callback preserves layers, masks, monitoring, and monitorable state" % title)
	_check(health_state == _health_signature(), "%s: F10 callback preserves Player/Raider/Boss HP" % title)
	_check(_game.get_node("CombatHUD").visible, "%s: combat HUD remains visible" % title)
	_rows.append("| %s | %s | %s | %d/%d | %s |" % [title, shape_node.get_path(), color_name, matched, points.size(), "PASS" if points_ok else "FAIL"])
	_set_overlay(false)

func _expected_color(shape_node: CollisionShape2D) -> String:
	var collider := shape_node.get_parent() as CollisionObject2D
	if collider is CharacterBody2D or collider.name == "ReceiveArea":
		return "cyan"
	var area := collider as Area2D
	return "green" if area != null and area.monitoring else "red"

func _outline_points(shape_node: CollisionShape2D) -> PackedVector2Array:
	var result := PackedVector2Array()
	if shape_node.shape is RectangleShape2D:
		var half := (shape_node.shape as RectangleShape2D).size * 0.5
		result = PackedVector2Array([Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)])
	elif shape_node.shape is CircleShape2D:
		var radius := (shape_node.shape as CircleShape2D).radius
		result = PackedVector2Array([Vector2.RIGHT * radius, Vector2.DOWN * radius, Vector2.LEFT * radius, Vector2.UP * radius])
	elif shape_node.shape is CapsuleShape2D:
		var capsule := shape_node.shape as CapsuleShape2D
		var half_segment := maxf(0.0, capsule.height * 0.5 - capsule.radius)
		result = PackedVector2Array([Vector2(0, -capsule.height * 0.5), Vector2(capsule.radius, -half_segment), Vector2(capsule.radius, half_segment), Vector2(0, capsule.height * 0.5), Vector2(-capsule.radius, half_segment), Vector2(-capsule.radius, -half_segment)])
	return result

func _shape_point_to_window(shape_node: CollisionShape2D, point: Vector2) -> Vector2:
	# CollisionShape2D's global canvas transform contains world, camera zoom/scroll,
	# actor and shape transforms. root final transform maps viewport pixels to Window pixels.
	return root.get_final_transform() * (shape_node.get_global_transform_with_canvas() * point)

func _has_color_near(image: Image, window_point: Vector2, color_name: String) -> bool:
	var center := window_point * Vector2(float(image.get_width()) / maxf(1.0, root.size.x), float(image.get_height()) / maxf(1.0, root.size.y))
	var radius := int(ceil(TOLERANCE_PX))
	for y in range(maxi(0, int(center.y) - radius), mini(image.get_height(), int(center.y) + radius + 1)):
		for x in range(maxi(0, int(center.x) - radius), mini(image.get_width(), int(center.x) + radius + 1)):
			if Vector2(float(x), float(y)).distance_to(center) > TOLERANCE_PX:
				continue
			var pixel := image.get_pixel(x, y)
			match color_name:
				"cyan":
					if pixel.b > 0.62 and pixel.g > 0.42 and pixel.r < 0.66:
						return true
				"green":
					if pixel.g > 0.62 and pixel.r < 0.65 and pixel.b < 0.68:
						return true
				_:
					if pixel.r > 0.62 and pixel.g < 0.66 and pixel.b < 0.66:
						return true
	return false

func _area_shape(actor: Node, area_name: String) -> CollisionShape2D:
	return actor.get_node_or_null(area_name + "/CollisionShape2D") as CollisionShape2D if area_name in ["AttackArea", "ReceiveArea"] else actor.get_node_or_null("Hitboxes/" + area_name + "/CollisionShape2D") as CollisionShape2D

func _set_overlay(value: bool) -> void:
	if _overlay == null or bool(_overlay.get("enabled")) == value:
		return
	var event := InputEventKey.new()
	event.keycode = KEY_F10
	event.physical_keycode = KEY_F10
	event.pressed = true
	# This is a direct callback invocation, not Input.parse_input_event and not a
	# physical keyboard route through the application/window.
	_overlay.call("_input", event)
	_direct_callback_toggles += 1

func _window_image() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _settle() -> void:
	await process_frame
	await process_frame

func _shape_collision_signature(shape_node: CollisionShape2D) -> Array[Dictionary]:
	var collider := shape_node.get_parent() as CollisionObject2D
	var area := collider as Area2D
	return [{"layer": collider.collision_layer, "mask": collider.collision_mask, "monitoring": area.monitoring if area != null else false, "monitorable": area.monitorable if area != null else false}]

func _images_differ(left: Image, right: Image) -> bool:
	if left.get_size() != right.get_size():
		return true
	var changed := 0
	for y in range(0, left.get_height(), 2):
		for x in range(0, left.get_width(), 2):
			if not left.get_pixel(x, y).is_equal_approx(right.get_pixel(x, y)):
				changed += 1
				if changed >= 12:
					return true
	return false

func _health_signature() -> Array[int]:
	return [int(_player.get("health")), int(_raider.get("health")), int(_boss.get("health"))]

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_descendants(child))
	return result

func _fatal_hit() -> Dictionary:
	return {"damage": 999, "direction": Vector2.LEFT, "knockback": 1.0, "hit_stun": 0.0, "attack_stage": 3}

func _write_report() -> void:
	var lines := PackedStringArray([
		"# M6P F10 공격·피격 shape 픽셀 게이트",
		"",
		"- 결과: %s" % ("PASS" if _failures.is_empty() else "FAIL"),
		"- 실제 Window: `%s`, 크기 `%s`, 뷰포트 `%s`" % [DisplayServer.get_name(), DisplayServer.window_get_size(), root.size],
		"- 검증: 개별 Player 기본 1·2·3타, Num4·Num5, Raider/Boss AttackArea·ReceiveArea 외곽 기준점. Shape2D 로컬 외곽점을 CollisionShape2D 전역 canvas transform 및 Window final transform으로 투영하고 해당 색상 픽셀을 원형 반경 %.0f px 안에서 찾음." % TOLERANCE_PX,
		"- 상태 범위: monitoring 활성·비활성, 좌우 반전, 카메라 줌 1.35·스크롤, Raider·Boss KO, F10 OFF/ON 및 scene restart 뒤 OFF.",
		"- 구동 방식: Player 단계/스킬과 Boss 공격 단계는 스크립트 상태 설정으로 준비했다. 이 픽셀 게이트는 실제 전투 입력·피해 라우팅을 검증하지 않음.",
		"- F10 입력 한계: OFF/ON은 `%d`회 overlay `_input` callback 직접 호출로 확인. 물리 키 입력이나 `Input.parse_input_event`를 통한 앱 입력 라우팅은 검증하지 않음." % _direct_callback_toggles,
		"- 비교: %d OFF/ON shape 상태, %d 외곽 기준점." % [_pair_count, _point_count],
		"",
		"| 상태 | CollisionShape2D | 색 | 기준점 일치 | 결과 |",
		"|---|---|---|---:|---|"
	])
	lines.append_array(_rows)
	lines.append_array(["", "## 실패", ""])
	if _failures.is_empty():
		lines.append("없음")
	else:
		for failure in _failures:
			lines.append("- " + failure)
	lines.append_array(["", "## 오버레이 변경 판단", "", "외곽점 투영 실패가 재현된 경우에만 `scripts/debug/combat_collision_overlay.gd`의 투영 경로를 수정한다. 이 게이트는 렌더링/표시만 확인하며 게임 충돌 판정과 피해 수치를 변경하지 않는다."])
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		_check(false, "review report can be opened for writing")
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6p_f10_attack_shape_pixel_smoke: all checks passed")
		quit(0)
		return
	for failure in _failures:
		push_error("M6P_F10|FAIL|" + failure)
	quit(1)
