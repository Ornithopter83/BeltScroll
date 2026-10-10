extends "res://tests/m6p_f10_attack_shape_pixel_smoke.gd"
"""Independent real-Window regression check for the six-point Boss capsule outline."""

func _run() -> void:
	_check(DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server"), "real Window renderer is available")
	_overlay = root.get_node_or_null("CombatCollisionOverlay")
	_check(_overlay != null, "collision overlay autoload exists")
	if _overlay == null or DisplayServer.get_name() == "headless":
		_finish()
		return
	_set_overlay(false)
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "production main scene loads")
	if packed == null:
		_finish()
		return
	_game = packed.instantiate() as Node2D
	root.add_child(_game)
	current_scene = _game
	await _settle()
	_player = _game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	_raider = _game.get_node_or_null("YSortActors/ForestRaider1") as CharacterBody2D
	_boss = _game.get_node_or_null("YSortActors/RuinsWardenBoss") as CharacterBody2D
	_check(_player != null and _raider != null and _boss != null, "production Player, Raider, and Boss are present")
	if _player == null or _raider == null or _boss == null:
		_finish()
		return

	_player.set_physics_process(false)
	_player.set_process(false)
	_raider.set_physics_process(false)
	_raider.set_process(false)
	_boss.set_combat_active(true)
	_boss.set_physics_process(false)
	_camera = _player.get_node("Camera2D") as Camera2D
	_camera.position_smoothing_enabled = false
	_camera.make_current()
	_player.global_position = Vector2(1000, 760)
	_raider.global_position = Vector2(1260, 760)
	_boss.global_position = Vector2(720, 760)
	await _settle()

	var boss_receive := _area_shape(_boss, "ReceiveArea")
	var capsule := boss_receive.shape as CapsuleShape2D if boss_receive != null else null
	_check(capsule != null and is_equal_approx(capsule.radius, 45.0) and is_equal_approx(capsule.height, 160.0), "Boss ReceiveArea uses its production 45×160 CapsuleShape2D")
	var boss_receive_area := _boss.get_node("ReceiveArea") as Area2D
	_check(boss_receive_area.position.is_equal_approx(Vector2(0, -320)), "Boss receive lane retains the latest production offset")
	for kind in ["slash", "slam"]:
		_boss.call("_begin_attack", kind)
		_check(boss_receive_area.monitoring, "Boss %s keeps the live receiver monitoring" % kind)
		var before := boss_receive.global_transform
		var health_before := _health_signature()
		await _capture_shape_pair("Boss %s ReceiveArea six-point outline" % kind, boss_receive, true)
		_check(before.is_equal_approx(boss_receive.global_transform), "Boss %s receive transform is stable through F10 OFF/ON capture" % kind)
		_check(health_before == _health_signature(), "Boss %s receive pixel inspection leaves HP unchanged" % kind)

	# Exercise a different camera transform; all six projected capsule landmarks
	# must continue to land on the actual cyan pixels in the Window image.
	_camera.zoom = Vector2(1.35, 1.35)
	_player.global_position = Vector2(1160, 820)
	_boss.global_position = Vector2(820, 790)
	await _settle()
	var zoom_transform := boss_receive.global_transform
	var zoom_health := _health_signature()
	await _capture_shape_pair("Boss ReceiveArea camera zoom and scroll six-point outline", boss_receive, true)
	_check(zoom_transform.is_equal_approx(boss_receive.global_transform), "camera zoom and scroll do not mutate the Boss Shape2D transform")
	_check(zoom_health == _health_signature(), "zoomed F10 pixel inspection leaves Player/Raider/Boss HP unchanged")

	var before_collapse: Transform2D = (_boss.get_node("VisualRoot") as Node2D).transform
	_boss.call("receive_hit", _fatal_hit())
	# receive_hit enables production KO physics. Let the visual collapse advance
	# while checking that the root-owned capsule does not inherit that transform.
	await _settle()
	_check(_boss.is_physics_processing() and not (_boss.get_node("VisualRoot") as Node2D).transform.is_equal_approx(before_collapse), "production Boss KO collapse advances during the Window inspection")
	_check(int(_boss.get("health")) == 0 and not boss_receive_area.monitoring and not boss_receive_area.monitorable, "Boss KO preserves the shape but disables receiver monitoring and monitorable state")
	var ko_transform := boss_receive.global_transform
	var ko_health := _health_signature()
	await _capture_shape_pair("Boss KO ReceiveArea six-point outline", boss_receive, false)
	_check(ko_transform.is_equal_approx(boss_receive.global_transform), "KO visual motion does not transform the root-owned ReceiveArea shape")
	_check(ko_health == _health_signature(), "KO F10 inspection leaves all HP values unchanged")

	_player.call("_begin_attack", 2)
	_player.call("_set_stage_hitbox", 2, true)
	var player_hitbox := _area_shape(_player, "Hitbox2")
	await _capture_shape_pair("Player J2 attack area", player_hitbox, true)
	_player.call("_set_stage_hitbox", 2, false)
	await _capture_shape_pair("Player J2 inactive attack area", player_hitbox, false)
	await _capture_shape_pair("Raider ReceiveArea", _area_shape(_raider, "ReceiveArea"), false)
	_check(not bool(_overlay.get("enabled")), "test leaves F10 overlay OFF")
	if _failures.is_empty():
		print("m6u_f10_boss_receive_independent_window_smoke: PASS (%d pixel landmarks)" % _point_count)
	else:
		for failure in _failures:
			push_error("m6u_f10_boss_receive_independent_window_smoke: " + failure)
	quit(1 if not _failures.is_empty() else 0)
