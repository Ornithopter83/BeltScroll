extends SceneTree
"""Captures paired real Window pixels for the read-only F10 shape overlay."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/m6o_f10_overlay_alignment_sheet.png"
const CELL_SIZE := Vector2i(960, 540)
const BASIC_AREAS := ["Hitbox1", "Hitbox2", "Hitbox3"]

var _failures: Array[String] = []
var _pairs: Array[Dictionary] = []
var _game: Node2D
var _player: CharacterBody2D
var _raider: CharacterBody2D
var _boss: CharacterBody2D
var _overlay: Node

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server"), "non-headless Godot Window renderer is active")
	_check(DisplayServer.window_get_size().x > 0 and root.size.x > 0, "Window and render viewport have nonzero dimensions")
	_overlay = root.get_node_or_null("CombatCollisionOverlay")
	_check(_overlay != null, "global collision overlay autoload exists")
	if _overlay == null or DisplayServer.get_name() == "headless":
		_finish()
		return
	_check(not bool(_overlay.get("enabled")), "overlay starts hidden")
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "live gameplay scene loads")
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
	_check(_player != null and _raider != null and _boss != null, "live Player, Raider, and Boss instances exist")
	if _player == null or _raider == null or _boss == null:
		_finish()
		return
	# Stabilize the live actors and put every tested collider in the camera view.
	_player.global_position = Vector2(960, 780)
	_player.set_physics_process(false)
	_player.set_process(false)
	_raider.global_position = Vector2(1175, 780)
	_raider.set_physics_process(false)
	_raider.set_process(false)
	_boss.global_position = Vector2(820, 780)
	_boss.set_combat_active(true)
	_boss.set_physics_process(false)
	_boss.visible = true
	_check(_boss.visible and _boss.get_node("VisualRoot").visible, "Boss combat actor and visual root are visible in the review scene")
	var camera := _player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.make_current()
	await _settle()

	for index in range(3):
		var area := _player.get_node("Hitboxes/" + BASIC_AREAS[index]) as Area2D
		area.monitoring = true
		await _capture_pair("Player 기본 %d타 · 실제 monitoring=on" % (index + 1))
		area.monitoring = false
		_check(not area.monitoring, "기본 %d타 monitoring can return OFF unchanged" % (index + 1))
	var skill1 := _player.get_node("Hitboxes/Skill1Hitbox") as Area2D
	var skill2 := _player.get_node("Hitboxes/Skill2Hitbox") as Area2D
	_player.set("skill_id", 1)
	_player.call("_set_skill_hitboxes", true)
	skill1.monitoring = true
	await _capture_pair("Player Num4 · 실제 monitoring=on")
	skill1.monitoring = false
	_player.set("skill_id", 2)
	_player.call("_set_skill_hitboxes", true)
	skill2.monitoring = true
	await _capture_pair("Player Num5 · 실제 monitoring=on")
	skill2.monitoring = false
	_player.call("_set_skill_hitboxes", false)
	_check(not skill1.monitoring and not skill2.monitoring, "Num4 and Num5 monitoring can return OFF unchanged")

	var raider_attack := _raider.get_node("AttackArea") as Area2D
	var raider_receive := _raider.get_node("ReceiveArea") as Area2D
	raider_attack.monitoring = true
	await _capture_pair("Raider 몸체·피격·공격")
	raider_attack.monitoring = false

	var boss_attack := _boss.get_node("AttackArea") as Area2D
	var boss_receive := _boss.get_node("ReceiveArea") as Area2D
	_boss.call("_begin_attack", "slash")
	boss_attack.monitoring = true
	await _capture_pair("Boss slash 원 · 실제 Shape2D 및 monitoring")
	_boss.call("_begin_attack", "slam")
	await _capture_pair("Boss slam 원 교체 · 실제 Shape2D 및 monitoring")
	boss_attack.monitoring = false
	_boss.call("_begin_attack", "slash")

	# Camera scroll/zoom and facing reversal are rendered in a separate pair.
	_player.set("facing_direction", Vector2.LEFT)
	_player.get_node("VisualRoot").scale.x = -1.0
	_player.global_position = Vector2(1210, 780)
	for stage in range(1, 4):
		_player.call("_set_stage_hitbox", stage, false)
	_player.call("_set_skill_hitbox_transform")
	camera.zoom = Vector2(1.55, 1.55)
	await _settle()
	await _capture_pair("카메라 줌·스크롤 및 Player 방향 전환")
	camera.zoom = Vector2(1.2, 1.2)
	_player.global_position = Vector2(960, 780)
	_player.set("facing_direction", Vector2.RIGHT)

	# KO shapes remain discoverable but report their real inactive monitoring.
	_raider.call("receive_hit", _fatal_hit())
	_boss.call("receive_hit", _fatal_hit())
	await _settle()
	await _capture_pair("Raider·Boss KO · 몸체/피격 shape와 inactive 상태")
	_check(int(_raider.get("health")) == 0 and int(_boss.get("health")) == 0, "KO snapshot uses real enemy KO state")

	# Synthetic key event toggles the overlay; it is not evidence of a physical key press.
	_set_overlay(false)
	_check(not bool(_overlay.get("enabled")), "F10 off state restored before scene restart")
	var restart_error := reload_current_scene()
	_check(restart_error == OK, "live main scene reload starts")
	await process_frame
	_check(not bool(_overlay.get("enabled")), "scene restart returns overlay to OFF")
	_print_metadata()
	await _write_alignment_sheet()
	_finish()

func _capture_pair(title: String) -> void:
	_set_overlay(false)
	await _settle()
	var off_image := await _window_image()
	var projected := _reference_projection()
	_check(not _projected_edge_visible(off_image, projected), "%s: OFF pixels do not contain the Player body outline at its projected location" % title)
	var collision_state := _collision_signature()
	var health_state := [_player.get("health"), _raider.get("health"), _boss.get("health")]
	_set_overlay(true)
	await _settle()
	var on_image := await _window_image()
	_check(_images_equal(off_image, on_image), "%s: ON Window pixels differ from OFF" % title)
	_check(_contains_overlay_color(on_image), "%s: ON Window pixels include rendered diagnostic colors" % title)
	_check(_projected_edge_visible(on_image, projected), "%s: drawn outline is within 3 px of the runtime transformed reference point %s" % [title, projected.round()])
	_check(_actor_body_edges_projected(on_image), "%s: Player/Raider/Boss body edges match their canvas-to-Window projection" % title)
	_check(collision_state == _collision_signature(), "%s: F10 display toggle preserves live collision layers, masks, and monitoring" % title)
	_check(health_state == [_player.get("health"), _raider.get("health"), _boss.get("health")], "%s: F10 display toggle does not change Player/Raider/Boss health" % title)
	_check(bool(_game.get_node("CombatHUD").visible), "%s: ordinary combat HUD remains visible" % title)
	_pairs.append({"title": title, "off": off_image, "on": on_image})
	_set_overlay(false)

func _reference_projection() -> Vector2:
	var body := _player.get_node("CollisionShape2D") as CollisionShape2D
	var viewport_point := body.get_global_transform_with_canvas() * Vector2(16, 0)
	return root.get_final_transform() * viewport_point

func _actor_body_edges_projected(image: Image) -> bool:
	for actor in [_player, _raider, _boss]:
		for node in _descendants(actor):
			if not node is CollisionShape2D or not node.get_parent() is CharacterBody2D:
				continue
			var collider := node as CollisionShape2D
			if collider.shape == null or collider.disabled:
				continue
			var point_local := Vector2.ZERO
			var color_name := "red"
			color_name = "cyan"
			if collider.shape is RectangleShape2D:
				point_local.x = (collider.shape as RectangleShape2D).size.x * 0.5
			elif collider.shape is CircleShape2D:
				point_local.x = (collider.shape as CircleShape2D).radius
			elif collider.shape is CapsuleShape2D:
				point_local.x = (collider.shape as CapsuleShape2D).radius
			else:
				continue
			var viewport_point := collider.get_global_transform_with_canvas() * point_local
			var window_point := root.get_final_transform() * viewport_point
			if not _has_outline_color_near(image, window_point, color_name):
				print("F10_OVERLAY_ALIGNMENT_MISS: %s %s expected=%s point=%s" % [actor.name, actor.get_path_to(collider), color_name, window_point.round()])
				return false
	return true

func _has_outline_color_near(image: Image, point: Vector2, color_name: String) -> bool:
	var scale_x := float(image.get_width()) / maxf(1.0, float(root.size.x))
	var scale_y := float(image.get_height()) / maxf(1.0, float(root.size.y))
	var center := Vector2(point.x * scale_x, point.y * scale_y)
	for y in range(maxi(0, int(center.y) - 4), mini(image.get_height(), int(center.y) + 5)):
		for x in range(maxi(0, int(center.x) - 4), mini(image.get_width(), int(center.x) + 5)):
			var c := image.get_pixel(x, y)
			match color_name:
				"cyan":
					if c.b > 0.7 and c.g > 0.52 and c.r < 0.58:
						return true
				"green":
					if c.g > 0.72 and c.r < 0.58 and c.b < 0.62:
						return true
				_:
					if c.r > 0.72 and c.g < 0.58 and c.b < 0.58:
						return true
	return false

func _projected_edge_visible(image: Image, point: Vector2) -> bool:
	# Runtime projection returns viewport pixels. Find cyan body-outline pixels near
	# the capsule's rightmost point; a bad canvas transform moves them outside this box.
	var scale_x := float(image.get_width()) / maxf(1.0, float(root.size.x))
	var scale_y := float(image.get_height()) / maxf(1.0, float(root.size.y))
	var center := Vector2(point.x * scale_x, point.y * scale_y)
	for y in range(maxi(0, int(center.y) - 4), mini(image.get_height(), int(center.y) + 5)):
		for x in range(maxi(0, int(center.x) - 4), mini(image.get_width(), int(center.x) + 5)):
			var c := image.get_pixel(x, y)
			if c.b > 0.75 and c.g > 0.55 and c.r < 0.5:
				return true
	return false

func _contains_overlay_color(image: Image) -> bool:
	var found := 0
	for y in range(0, image.get_height(), 3):
		for x in range(0, image.get_width(), 3):
			var c := image.get_pixel(x, y)
			if (c.r > 0.75 and c.g < 0.55 and c.b < 0.5) or (c.b > 0.75 and c.g > 0.55 and c.r < 0.5) or (c.g > 0.75 and c.r < 0.55 and c.b < 0.5):
				found += 1
				if found > 20:
					return true
	return false

func _images_equal(left: Image, right: Image) -> bool:
	if left.get_size() != right.get_size():
		return false
	var changed := 0
	for y in range(0, left.get_height(), 4):
		for x in range(0, left.get_width(), 4):
			if not left.get_pixel(x, y).is_equal_approx(right.get_pixel(x, y)):
				changed += 1
				if changed > 20:
					return true
	return false

func _window_image() -> Image:
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()

func _settle() -> void:
	await process_frame
	await process_frame

func _set_overlay(value: bool) -> void:
	var enabled := bool(_overlay.get("enabled"))
	if enabled == value:
		return
	var event := InputEventKey.new()
	event.keycode = KEY_F10
	event.physical_keycode = KEY_F10
	event.pressed = true
	_overlay.call("_input", event)

func _collision_signature() -> Array[Dictionary]:
	var signature: Array[Dictionary] = []
	for actor in [_player, _raider, _boss]:
		for node in _descendants(actor):
			if node is CollisionObject2D:
				var collision := node as CollisionObject2D
				var area := collision as Area2D
				signature.append({
					"path": str(actor.get_path_to(collision)),
					"layer": collision.collision_layer,
					"mask": collision.collision_mask,
					"monitoring": area.monitoring if area != null else false,
					"monitorable": area.monitorable if area != null else false,
				})
	return signature

func _descendants(node: Node) -> Array[Node]:
	var result: Array[Node] = [node]
	for child in node.get_children():
		result.append_array(_descendants(child))
	return result

func _write_alignment_sheet() -> void:
	var sheet := Image.create(CELL_SIZE.x * 2, CELL_SIZE.y * _pairs.size(), false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.035, 0.045, 0.06, 1.0))
	for index in range(_pairs.size()):
		var pair: Dictionary = _pairs[index]
		var off_image: Image = pair.off
		var on_image: Image = pair.on
		off_image.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_LANCZOS)
		on_image.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(off_image, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i(0, CELL_SIZE.y * index))
		sheet.blit_rect(on_image, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i(CELL_SIZE.x, CELL_SIZE.y * index))
	var error := sheet.save_png(OUTPUT_PATH)
	_check(error == OK, "OFF/ON real Window pixel comparison sheet is saved to %s" % OUTPUT_PATH)
	print("F10_OVERLAY_CAPTURE: %s" % ProjectSettings.globalize_path(OUTPUT_PATH))

func _print_metadata() -> void:
	print("F10_OVERLAY_CAPTURE: display_server=%s window_size=%s viewport_size=%s" % [DisplayServer.get_name(), DisplayServer.window_get_size(), root.size])
	print("F10_OVERLAY_CAPTURE: PHYSICAL_F10=NOT_TESTED; HUMAN_APPROVAL=NOT_RECORDED; synthetic InputEventKey delivered directly to the overlay callback")
	print("F10_OVERLAY_CAPTURE: pair_rows=%d; actual monitoring properties were read from live Area2D nodes" % _pairs.size())

func _fatal_hit() -> Dictionary:
	return {"damage": 999, "direction": Vector2.LEFT, "knockback": 1.0, "hit_stun": 0.0, "attack_stage": 3}

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6o_f10_overlay_window_smoke: all checks passed")
		quit(0)
		return
	for failure in _failures:
		push_error("m6o_f10_overlay_window_smoke: " + failure)
	quit(1)
