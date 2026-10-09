extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const EPSILON := 0.1

var failures: Array[String] = []
var player: CharacterBody2D
var visual_root: Node2D
var ground_shadow: Polygon2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_main: PackedScene = load(MAIN_SCENE) as PackedScene
	var main: Node = packed_main.instantiate()
	_disable_test_enemies(main)
	root.add_child(main)
	await physics_frame
	player = main.get_node("YSortActors/Player") as CharacterBody2D
	visual_root = player.get_node("VisualRoot") as Node2D
	ground_shadow = player.get_node("GroundShadow") as Polygon2D

	_check_scene_configuration(main)
	await _check_cardinal_movement()
	await _check_diagonal_movement()
	await _check_facing()
	await _check_blocking()
	await _check_arena_clamp()
	await _check_camera_bounds()
	await _check_visual_jump_and_landing()
	await _check_jump_height_and_airtime()
	await _check_jump_buffer()
	await _check_variable_jump()
	await _check_coyote_grace()
	await _check_attack_input()
	_release_all_actions()

	if failures.is_empty():
		print("movement_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("movement_smoke: " + failure)
		push_error("movement_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _disable_test_enemies(main: Node) -> void:
	# Keep movement input checks independent from the live combat AI in main.tscn.
	var actors := main.get_node("YSortActors")
	for raider_name in ["ForestRaider1", "ForestRaider2", "ForestRaider3"]:
		actors.get_node(raider_name).free()

func _check_scene_configuration(main: Node) -> void:
	_check(main.get_node("YSortActors").y_sort_enabled, "YSortActors enables y sorting")
	var camera := player.get_node("Camera2D") as Camera2D
	_check(player.global_position == Vector2(960.0, 780.0), "player starts in the lower HUD-safe combat lane")
	_check(player.get("arena_bounds") == Rect2(Vector2(237, 722), Vector2(1446, 258)), "arena bounds account for zoomed alpha silhouette limits")
	var viewport_size := get_root().get_visible_rect().size
	var visible_world_size := viewport_size / camera.zoom
	_check(camera.zoom == Vector2(1.2, 1.2), "camera uses the configured zoom for the arena framing")
	_check(camera.position == Vector2(0.0, -360.0), "camera frames the full-size actor silhouette below the HUD")
	_check(viewport_size == Vector2(1920, 1080), "headless test uses the logical 1920 by 1080 viewport")
	_check(camera.limit_left == 0 and camera.limit_top == 0, "camera starts at backdrop origin")
	_check(camera.limit_right == 1920 and camera.limit_bottom == 1080, "camera limits match backdrop bounds")
	_check(camera.offset == Vector2.ZERO, "camera offset does not shift the visible bounds")
	_check(visible_world_size.x <= camera.limit_right - camera.limit_left and visible_world_size.y <= camera.limit_bottom - camera.limit_top, "zoomed camera view fits inside backdrop at limits")
	_check(camera.position_smoothing_enabled, "camera position smoothing remains enabled")

func _check_cardinal_movement() -> void:
	await _reset_player(Vector2(960, 800))
	Input.action_press("move_right")
	await _frames(12)
	var right_delta: Vector2 = player.global_position - Vector2(960, 800)
	_check(right_delta.x > 40.0 and absf(right_delta.y) < EPSILON, "right input moves on x only (delta=%s)" % right_delta)
	_release("move_right")
	await _frames(1)
	await _reset_player(Vector2(960, 800))
	Input.action_press("move_down")
	await _frames(12)
	var down_delta: Vector2 = player.global_position - Vector2(960, 800)
	_check(down_delta.y > 40.0 and absf(down_delta.x) < EPSILON, "down input moves on y only")
	_release("move_down")
	await _frames(1)

func _check_diagonal_movement() -> void:
	await _reset_player(Vector2(960, 800))
	Input.action_press("move_right")
	Input.action_press("move_down")
	await _frames(12)
	var delta_position: Vector2 = player.global_position - Vector2(960, 800)
	_check(delta_position.x > 25.0 and delta_position.y > 25.0, "diagonal input moves on both axes")
	_check(absf(delta_position.x - delta_position.y) < 1.0, "diagonal movement is normalized")
	_release("move_right")
	_release("move_down")
	await _frames(1)

func _check_facing() -> void:
	Input.action_press("move_left")
	await _frames(1)
	_check(player.facing_direction.x < -0.9, "left input updates facing immediately")
	await _frames(5)
	_check(visual_root.scale.x < 0.0, "left-facing turn applies its single visual flip after the procedural windup")
	_release("move_left")
	await _frames(1)
	Input.action_press("move_up")
	await _frames(1)
	_check(player.facing_direction.y < -0.9, "up input updates facing direction")
	_release("move_up")
	await _frames(1)

func _check_blocking() -> void:
	await _reset_player(Vector2(960, 800))
	Input.action_press("block")
	Input.action_press("move_right")
	await _frames(10)
	_check(player.get("is_blocking") == true, "block input enters guarding state")
	_check(absf(player.global_position.x - 960.0) < EPSILON, "blocking prevents movement")
	Input.action_press("attack")
	await _frames(1)
	_check(player.get("attack_phase") == "idle", "blocking prevents starting an attack")
	_release("attack")
	_release("move_right")
	_release("block")
	await _frames(1)
	await _reset_player(Vector2(960, 800))
	player.set("is_blocking", true)
	var health_before: int = player.get("health")
	player.call("receive_hit", {"damage": 2, "direction": Vector2.LEFT, "knockback": 200.0, "hit_stun": 0.4, "attack_stage": 2})
	_check(player.get("health") == health_before - 1, "blocking reduces incoming damage")
	_check(absf(float(player.get("hitstun_remaining")) - 0.2) < EPSILON, "blocking reduces hit stun")
	_check(absf(player.velocity.length() - 70.0) < EPSILON, "blocking reduces knockback")
	await _frames(1)

func _check_arena_clamp() -> void:
	await _reset_player(Vector2(200, 800))
	Input.action_press("move_left")
	await _frames(2)
	_check(absf(player.global_position.x - 250.0) < EPSILON, "arena clamps left edge with the full alpha silhouette inside camera bounds (x=%.2f)" % player.global_position.x)
	_release("move_left")
	await _reset_player(Vector2(960, 700))
	Input.action_press("move_up")
	await _frames(2)
	_check(absf(player.global_position.y - 760.0) < EPSILON, "HUD-safe arena clamps the top edge after accounting for the jump silhouette")
	_release("move_up")
	await _reset_player(Vector2(1800, 800))
	Input.action_press("move_right")
	await _frames(2)
	_check(absf(player.global_position.x - 1670.0) < EPSILON, "arena clamps right edge with the full alpha silhouette inside camera bounds (x=%.2f)" % player.global_position.x)
	_release("move_right")
	await _reset_player(Vector2(960, 970))
	Input.action_press("move_down")
	await _frames(2)
	_check(absf(player.global_position.y - 978.0) < EPSILON, "arena clamps bottom edge")
	_release("move_down")
	await _frames(1)

func _check_camera_bounds() -> void:
	await _reset_player(Vector2(1670.0, 978.0))
	await _frames(90)
	player.set("camera_trauma", 1.0)
	await _frames(2)
	var camera := player.get_node("Camera2D") as Camera2D
	var center := camera.get_screen_center_position()
	var half_view := get_root().get_visible_rect().size / camera.zoom * 0.5
	_check(center.x - half_view.x >= camera.limit_left - 1.0 and center.x + half_view.x <= camera.limit_right + 1.0, "camera trauma stays inside horizontal arena bounds")
	_check(center.y - half_view.y >= camera.limit_top - 1.0 and center.y + half_view.y <= camera.limit_bottom + 1.0, "camera trauma stays inside vertical arena bounds")

func _check_visual_jump_and_landing() -> void:
	await _reset_player(Vector2(960, 800))
	var floor_position := player.global_position
	var floor_visual_y := visual_root.position.y
	var floor_shadow_alpha := ground_shadow.modulate.a
	Input.action_press("jump")
	await _frames(3)
	_check(player.global_position == floor_position, "visual jump leaves the player floor position unchanged")
	_check(visual_root.position.y < floor_visual_y, "jump raises the visual root")
	_check(ground_shadow.modulate.a < floor_shadow_alpha, "jump changes ground shadow alpha")
	_release("jump")
	await _frames(30)
	_check(is_equal_approx(visual_root.position.y, floor_visual_y), "visual returns to floor offset after jump")
	_check(is_equal_approx(ground_shadow.modulate.a, floor_shadow_alpha), "shadow alpha returns after landing")

func _check_jump_buffer() -> void:
	await _reset_player(Vector2(960, 800))
	# Place the airborne visual just above its landing point. The real action
	# press then has to survive until the next physics tick lands and relaunches.
	player.set("is_jumping", true)
	player.set("jump_height_offset", 2.5)
	player.set("jump_vertical_velocity", 100.0)
	player.set("coyote_remaining", 0.0)
	Input.action_press("jump")
	await _frames(3)
	_check(player.get("is_jumping") == true and player.get("jump_vertical_velocity") < 0.0, "jump pressed just before landing is buffered into a new takeoff")
	_check(player.get("jump_buffer_remaining") == 0.0, "buffer is consumed by the landing takeoff")
	_release("jump")
	await _frames(30)

func _check_jump_height_and_airtime() -> void:
	await _reset_player(Vector2(960, 800))
	Input.action_press("jump")
	await _frames(2)
	var floor_position := player.global_position
	var peak_height := 0.0
	var airborne_frames := 0
	for _frame in range(90):
		await physics_frame
		peak_height = maxf(peak_height, float(player.get("jump_height_offset")))
		if player.get("is_jumping"):
			airborne_frames += 1
		else:
			break
	_release("jump")
	_check(peak_height >= 110.0 and peak_height <= 130.0, "held jump reaches the intended 110 to 130 world pixel arc (peak=%.1f)" % peak_height)
	_check(airborne_frames >= 45 and airborne_frames <= 65, "held jump keeps a readable, bounded airtime (frames=%d)" % airborne_frames)
	_check(player.global_position == floor_position, "larger jump still keeps the actor's floor coordinate grounded")
	_check(not player.get("is_jumping") and is_zero_approx(float(player.get("jump_height_offset"))), "larger jump lands and resets its visual offset")
	await _reset_player(Vector2(960, 800))
	Input.action_press("jump")
	await _frames(1)
	_release("jump")
	await _frames(2)
	var height_before_repeat := float(player.get("jump_height_offset"))
	Input.action_press("jump")
	await _frames(2)
	_check(player.get("is_jumping") and float(player.get("jump_height_offset")) > height_before_repeat, "repeated jump input while airborne does not reset the current jump")
	_release("jump")
	await _frames(70)

func _check_variable_jump() -> void:
	var short_jump_height := await _measure_jump_height(2)
	var full_jump_height := await _measure_jump_height(18)
	_check(full_jump_height > short_jump_height + 5.0, "holding jump produces a higher arc than early release")

func _measure_jump_height(hold_frames: int) -> float:
	await _reset_player(Vector2(960, 800))
	Input.action_press("jump")
	await _frames(hold_frames)
	_release("jump")
	var max_height := 0.0
	for _frame in range(28):
		await physics_frame
		max_height = maxf(max_height, -18.0 - visual_root.position.y)
	return max_height

func _check_coyote_grace() -> void:
	await _reset_player(Vector2(960, 800))
	# This arena has no ledges, so seed the controller's airborne grace state to
	# model the instant after walking off a platform in the same movement code.
	player.set("is_jumping", true)
	player.set("jump_height_offset", 8.0)
	player.set("jump_vertical_velocity", 100.0)
	player.set("coyote_remaining", 0.08)
	Input.action_press("jump")
	await _frames(3)
	_check(player.get("jump_vertical_velocity") < 0.0, "jump press during coyote grace starts a jump")
	_check(is_equal_approx(player.get("coyote_remaining"), 0.0), "using coyote grace consumes its timer")
	_release("jump")
	await _frames(35)
	await _reset_player(Vector2(960, 800))
	player.set("is_jumping", true)
	player.set("jump_height_offset", 70.0)
	player.set("jump_vertical_velocity", 100.0)
	player.set("coyote_remaining", 0.001)
	Input.action_press("jump")
	await _frames(12)
	_check(player.get("is_jumping") == true and player.get("jump_vertical_velocity") > 0.0, "jump after coyote grace expires does not relaunch")
	_check(player.get("jump_buffer_remaining") == 0.0, "expired coyote input buffer also expires before landing")
	_release("jump")
	await _frames(30)

func _check_attack_input() -> void:
	_release_all_actions()
	Input.action_press("attack")
	await _frames(2)
	_check(player.get_node("VisualRoot/AttackFlash").visible, "temporary attack input still activates the attack flash")
	_release("attack")
	await _frames(10)

func _reset_player(position: Vector2) -> void:
	_release_all_actions()
	player.global_position = position
	player.velocity = Vector2.ZERO
	player.set("jump_vertical_velocity", 0.0)
	player.set("jump_height_offset", 0.0)
	player.set("jump_buffer_remaining", 0.0)
	player.set("coyote_remaining", 0.0)
	player.set("is_jumping", false)
	player.set("attack_recoil_remaining", 0.0)
	player.set("attack_recoil_velocity", Vector2.ZERO)
	player.set("is_blocking", false)
	player.set("hitstun_remaining", 0.0)
	visual_root.position = Vector2(0, -18)
	visual_root.scale = Vector2.ONE
	ground_shadow.modulate.a = 0.42
	await physics_frame

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _release(action: String) -> void:
	Input.action_release(action)

func _release_all_actions() -> void:
	for action in ["move_left", "move_right", "move_up", "move_down", "block", "jump", "attack"]:
		Input.action_release(action)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
