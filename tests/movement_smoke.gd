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
	await _check_crouch()
	await _check_arena_clamp()
	await _check_camera_bounds()
	await _check_visual_jump_and_landing()
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
	var viewport_size := get_root().get_visible_rect().size
	var visible_world_size := viewport_size / camera.zoom
	_check(camera.zoom == Vector2(1.2, 1.2), "camera uses the configured zoom for the arena framing")
	_check(viewport_size == Vector2(1920, 1080), "headless test uses the logical 1920 by 1080 viewport")
	_check(camera.limit_left == 0 and camera.limit_top == 0, "camera starts at backdrop origin")
	_check(camera.limit_right == 1920 and camera.limit_bottom == 1080, "camera limits match backdrop bounds")
	_check(camera.offset == Vector2.ZERO, "camera offset does not shift the visible bounds")
	_check(visible_world_size.x <= camera.limit_right - camera.limit_left and visible_world_size.y <= camera.limit_bottom - camera.limit_top, "zoomed camera view fits inside backdrop at limits")
	_check(camera.position_smoothing_enabled, "camera position smoothing remains enabled")

func _check_cardinal_movement() -> void:
	await _reset_player(Vector2(960, 540))
	Input.action_press("move_right")
	await _frames(12)
	var right_delta: Vector2 = player.global_position - Vector2(960, 540)
	_check(right_delta.x > 40.0 and absf(right_delta.y) < EPSILON, "right input moves on x only")
	_release("move_right")
	await _frames(1)
	await _reset_player(Vector2(960, 540))
	Input.action_press("move_down")
	await _frames(12)
	var down_delta: Vector2 = player.global_position - Vector2(960, 540)
	_check(down_delta.y > 40.0 and absf(down_delta.x) < EPSILON, "down input moves on y only")
	_release("move_down")
	await _frames(1)

func _check_diagonal_movement() -> void:
	await _reset_player(Vector2(960, 540))
	Input.action_press("move_right")
	Input.action_press("move_down")
	await _frames(12)
	var delta_position: Vector2 = player.global_position - Vector2(960, 540)
	_check(delta_position.x > 25.0 and delta_position.y > 25.0, "diagonal input moves on both axes")
	_check(absf(delta_position.x - delta_position.y) < 1.0, "diagonal movement is normalized")
	_release("move_right")
	_release("move_down")
	await _frames(1)

func _check_facing() -> void:
	Input.action_press("move_left")
	await _frames(1)
	_check(player.facing_direction.x < -0.9 and visual_root.scale.x < 0.0, "left input updates facing and visual flip")
	_release("move_left")
	await _frames(1)
	Input.action_press("move_up")
	await _frames(1)
	_check(player.facing_direction.y < -0.9, "up input updates facing direction")
	_release("move_up")
	await _frames(1)

func _check_crouch() -> void:
	await _reset_player(Vector2(960, 540))
	Input.action_press("move_right")
	await _frames(10)
	var normal_distance := player.global_position.x - 960.0
	_release("move_right")
	await _frames(1)
	await _reset_player(Vector2(960, 540))
	Input.action_press("move_right")
	Input.action_press("sit")
	await _frames(10)
	var crouch_distance := player.global_position.x - 960.0
	var crouch_foot_anchor := visual_root.position.y + 15.0 * visual_root.scale.y
	_check(player.get("is_sitting") == true and is_equal_approx(visual_root.scale.y, 0.78), "sit input applies crouch visual state")
	_check(absf(crouch_distance / normal_distance - 0.45) < 0.03, "crouch applies configured movement multiplier")
	_check(absf(crouch_foot_anchor - (-3.0)) < EPSILON, "crouch keeps the visual foot anchor fixed")
	_check(visual_root.scale.x > 0.0 and player.facing_direction.x > 0.9, "crouch preserves horizontal facing")
	_release("move_right")
	_release("sit")
	await _frames(1)
	_check(player.get("is_sitting") == false and is_equal_approx(visual_root.scale.y, 1.0), "releasing sit restores standing state")

func _check_arena_clamp() -> void:
	await _reset_player(Vector2(180, 540))
	Input.action_press("move_left")
	await _frames(2)
	_check(absf(player.global_position.x - 173.0) < EPSILON, "arena clamps left edge")
	_release("move_left")
	await _reset_player(Vector2(960, 145))
	Input.action_press("move_up")
	await _frames(2)
	_check(absf(player.global_position.y - 138.0) < EPSILON, "arena clamps top edge")
	_release("move_up")
	await _reset_player(Vector2(1740, 540))
	Input.action_press("move_right")
	await _frames(2)
	_check(absf(player.global_position.x - 1747.0) < EPSILON, "arena clamps right edge")
	_release("move_right")
	await _reset_player(Vector2(960, 970))
	Input.action_press("move_down")
	await _frames(2)
	_check(absf(player.global_position.y - 978.0) < EPSILON, "arena clamps bottom edge")
	_release("move_down")
	await _frames(1)

func _check_camera_bounds() -> void:
	await _reset_player(Vector2(1747.0, 978.0))
	await _frames(90)
	player.set("camera_trauma", 1.0)
	await _frames(2)
	var camera := player.get_node("Camera2D") as Camera2D
	var center := camera.get_screen_center_position()
	var half_view := get_root().get_visible_rect().size / camera.zoom * 0.5
	_check(center.x - half_view.x >= camera.limit_left - 1.0 and center.x + half_view.x <= camera.limit_right + 1.0, "camera trauma stays inside horizontal arena bounds")
	_check(center.y - half_view.y >= camera.limit_top - 1.0 and center.y + half_view.y <= camera.limit_bottom + 1.0, "camera trauma stays inside vertical arena bounds")

func _check_visual_jump_and_landing() -> void:
	await _reset_player(Vector2(960, 540))
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
	await _reset_player(Vector2(960, 540))
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

func _check_variable_jump() -> void:
	var short_jump_height := await _measure_jump_height(2)
	var full_jump_height := await _measure_jump_height(18)
	_check(full_jump_height > short_jump_height + 5.0, "holding jump produces a higher arc than early release")

func _measure_jump_height(hold_frames: int) -> float:
	await _reset_player(Vector2(960, 540))
	Input.action_press("jump")
	await _frames(hold_frames)
	_release("jump")
	var max_height := 0.0
	for _frame in range(28):
		await physics_frame
		max_height = maxf(max_height, -18.0 - visual_root.position.y)
	return max_height

func _check_coyote_grace() -> void:
	await _reset_player(Vector2(960, 540))
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
	await _reset_player(Vector2(960, 540))
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
	for action in ["move_left", "move_right", "move_up", "move_down", "sit", "jump", "attack"]:
		Input.action_release(action)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
