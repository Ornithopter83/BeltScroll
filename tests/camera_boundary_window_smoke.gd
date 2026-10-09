extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const CAPTURE_TOOL := "res://tools/capture_camera_boundary.gd"
const CAPTURE_PATH := "res://assets/art/review/camera_boundary_capture.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)
const SUCCESS_MARKER := "camera-boundary-capture: all checks passed"

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "smoke runs with a Window Viewport renderer")
	var game := (load(MAIN_SCENE) as PackedScene).instantiate() as Node2D
	root.size = EXPECTED_SIZE
	root.add_child(game)
	await process_frame
	var player := game.get_node("YSortActors/Player") as CharacterBody2D
	var camera := player.get_node("Camera2D") as Camera2D
	var stage := game.get_node("StageBackground") as Sprite2D
	for raider in get_nodes_in_group("forest_raiders"):
		raider.set_physics_process(false)
		raider.velocity = Vector2.ZERO
		raider.get_node("AttackArea").monitoring = false
	_check(camera.zoom.is_equal_approx(Vector2(1.2, 1.2)), "camera zoom is preserved at 1.2")
	_check(camera.position.is_equal_approx(Vector2(0.0, -360.0)), "camera framing offset keeps the full-size actors below the HUD")
	_check(camera.position_smoothing_enabled, "camera position smoothing stays enabled")
	_check(stage.texture.get_size() == Vector2(EXPECTED_SIZE), "camera boundary is checked against the 1920x1080 stage texture")
	_check(camera.limit_left == 0 and camera.limit_top == 0 and camera.limit_right == 1920 and camera.limit_bottom == 1080, "camera limits cover the stage background exactly")
	_check(player.get("arena_bounds") == Rect2(Vector2(237, 722), Vector2(1446, 258)), "player combat arena stays inside the HUD-safe visible band")
	player.global_position = Vector2(250.0, 760.0)
	await _wait_frames(120)
	var requested := Vector2(100.0, -100.0)
	var bounded: Vector2 = player.call("_clamp_camera_offset_to_background", requested)
	_check(bounded.length() < requested.length(), "camera trauma offset is constrained by visible background limits (requested=%s bounded=%s)" % [requested, bounded])
	player.call("_add_camera_trauma", 0.34)
	player.call("_add_camera_trauma", 0.22)
	player.call("_add_camera_trauma", 0.12)
	player.call("_update_camera_trauma", 0.0)
	_check(player.camera_trauma > 0.0 and player.camera.offset != Vector2.ZERO, "three-hit trauma produces a bounded shake")
	for _frame in range(100):
		await physics_frame
		await process_frame
	_check(is_zero_approx(player.camera_trauma) and camera.offset == Vector2.ZERO, "camera trauma decays and its offset returns to zero")
	await _check_player_silhouette_at_arena_edges(player)

	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var capture_output: Array[String] = []
	var capture_status := OS.execute(executable, ["--path", project_path, "--script", CAPTURE_TOOL], capture_output, true)
	_check(capture_status == 0, "real Window Viewport boundary capture exits successfully")
	_check(_output_contains(capture_output, SUCCESS_MARKER), "capture tool reports all boundary checks passed")
	_check(_output_contains(capture_output, "shows no backdrop gaps at viewport edge pixels"), "all nine rendered positions check for background gaps")
	_check(_output_contains(capture_output, "boundary samples match actual Forest Ruins pixels"), "edge checks compare rendered pixels to the stage source pixels")
	if capture_status != 0:
		for line in capture_output:
			push_error(str(line))
	var capture := Image.new()
	var capture_error := capture.load(CAPTURE_PATH)
	_check(capture_error == OK, "comparison capture PNG is created")
	if capture_error == OK:
		_check(capture.get_size() == EXPECTED_SIZE, "comparison capture is exactly 1920x1080")
		_check(_has_visible_variation(capture), "comparison capture contains rendered Forest Ruins pixels")

	var headless_output: Array[String] = []
	var headless_status := OS.execute(executable, ["--headless", "--path", project_path, "--script", CAPTURE_TOOL], headless_output, true)
	_check(headless_status != 0, "capture tool exits nonzero without a window renderer")
	_check(_output_contains(headless_output, "active display server is headless"), "windowless capture failure explains the unavailable renderer")
	game.queue_free()
	_finish()

func _check_player_silhouette_at_arena_edges(player: CharacterBody2D) -> void:
	var visual_root := player.get_node("VisualRoot") as Node2D
	var player_art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var alpha_rect: Rect2i = player_art.texture.get_image().get_used_rect()
	var texture_center := player_art.texture.get_size() * 0.5
	var alpha_left_local := (Vector2(alpha_rect.position.x, alpha_rect.position.y + alpha_rect.size.y * 0.5) - texture_center) * player_art.scale
	var alpha_right_local := (Vector2(alpha_rect.end.x, alpha_rect.position.y + alpha_rect.size.y * 0.5) - texture_center) * player_art.scale
	var alpha_top_local := (Vector2(alpha_rect.position.x + alpha_rect.size.x * 0.5, alpha_rect.position.y) - texture_center) * player_art.scale
	var alpha_bottom_local := (Vector2(alpha_rect.position.x + alpha_rect.size.x * 0.5, alpha_rect.end.y) - texture_center) * player_art.scale
	var arena: Rect2 = player.get("arena_bounds")
	player.global_position = Vector2(960.0, arena.position.y + 38.0)
	player.set("is_jumping", false)
	player.set("jump_height_offset", 0.0)
	visual_root.position.y = -18.0
	player.set("camera_trauma", 0.0)
	await _wait_frames(120)
	player.set("is_jumping", true)
	player.set("jump_height_offset", float(player.get("jump_height")))
	player.set("jump_vertical_velocity", 0.0)
	visual_root.position.y = -18.0 - float(player.get("jump_height"))
	var top_screen: Vector2 = player_art.get_global_transform_with_canvas() * alpha_top_local
	var bottom_screen: Vector2 = player_art.get_global_transform_with_canvas() * alpha_bottom_local
	var top_screen_y := top_screen.y
	var bottom_screen_y := bottom_screen.y
	_check(top_screen_y >= 256.0, "real player alpha head at the upper jump boundary clears the full HUD safe area")
	_check(bottom_screen_y <= EXPECTED_SIZE.y, "real player alpha feet remain visible at the upper jump boundary")
	await _check_attack_pose_silhouette(player)
	player.global_position.x = 250.0
	await _wait_frames(120)
	var left_screen_x: float = (player_art.get_global_transform_with_canvas() * alpha_left_local).x
	_check(left_screen_x >= 0.0, "full player alpha silhouette remains inside the left camera edge")
	player.global_position.x = 1670.0
	await _wait_frames(120)
	var right_screen_x: float = (player_art.get_global_transform_with_canvas() * alpha_right_local).x
	_check(right_screen_x <= EXPECTED_SIZE.x, "full player alpha silhouette remains inside the right camera edge")
	player.global_position = Vector2(960.0, 978.0)
	player.set("is_jumping", false)
	player.set("jump_height_offset", 0.0)
	visual_root.position.y = -18.0
	await _wait_frames(120)
	bottom_screen = player_art.get_global_transform_with_canvas() * alpha_bottom_local
	bottom_screen_y = bottom_screen.y
	_check(bottom_screen_y <= EXPECTED_SIZE.y, "real player alpha feet remain visible at the lower arena boundary")

func _check_attack_pose_silhouette(player: CharacterBody2D) -> void:
	player.call("_begin_attack", 3)
	for _frame in range(20):
		if str(player.get("attack_phase")) == "active":
			break
		await process_frame
	await process_frame
	await process_frame
	var pose_blender := player.get_node("VisualRoot/PoseBlender") as Node2D
	var checked_pose := false
	var camera := player.get_node("Camera2D") as Camera2D
	for child in pose_blender.get_children():
		var art := child as Sprite2D
		if art == null or not art.visible or art.texture == null:
			continue
		var alpha_rect: Rect2i = art.texture.get_image().get_used_rect()
		var texture_center := art.texture.get_size() * 0.5
		var top_local := (Vector2(alpha_rect.position.x + alpha_rect.size.x * 0.5, alpha_rect.position.y) - texture_center) * art.scale
		var bottom_local := (Vector2(alpha_rect.position.x + alpha_rect.size.x * 0.5, alpha_rect.end.y) - texture_center) * art.scale
		var top_screen_y: float = (art.get_global_transform_with_canvas() * top_local).y
		var bottom_screen_y: float = (art.get_global_transform_with_canvas() * bottom_local).y
		_check(top_screen_y >= 256.0, "real contact pose alpha head clears the HUD during a combo attack")
		_check(bottom_screen_y <= EXPECTED_SIZE.y, "real contact pose alpha feet stay visible during a combo attack")
		checked_pose = true
	_check(checked_pose, "combo attack displays an alpha-bounded pose for the framing regression")
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.velocity = Vector2.ZERO
	for index in range(1, 4):
		player.call("_set_stage_hitbox", index, false)
	await process_frame

func _wait_frames(count: int) -> void:
	for _frame in range(count):
		await process_frame

func _has_visible_variation(image: Image) -> bool:
	var first_color := image.get_pixel(0, 0)
	var varied := 0
	for y in range(20, image.get_height(), 80):
		for x in range(20, image.get_width(), 80):
			var difference := image.get_pixel(x, y) - first_color
			if difference.r * difference.r + difference.g * difference.g + difference.b * difference.b > 0.0025:
				varied += 1
	return varied >= 12

func _output_contains(output: Array, fragment: String) -> bool:
	for line in output:
		if str(line).contains(fragment):
			return true
	return false

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("camera_boundary_window_smoke: all checks passed")
		quit(0)
		return
	for failure in _failures:
		push_error("camera_boundary_window_smoke: " + failure)
	push_error("camera_boundary_window_smoke: %d check(s) failed" % _failures.size())
	quit(1)
