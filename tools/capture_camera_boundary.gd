extends SceneTree
"""Renders a nine-position Forest Ruins camera boundary comparison sheet."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/camera_boundary_capture.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const TILE_SIZE := Vector2i(640, 360)
const POSITIONS := [
	Vector2(173, 138), Vector2(960, 138), Vector2(1747, 138),
	Vector2(173, 558), Vector2(960, 558), Vector2(1747, 558),
	Vector2(173, 978), Vector2(960, 978), Vector2(1747, 978),
]
const POSITION_NAMES := ["top-left", "top-edge", "top-right", "left-edge", "center", "right-edge", "bottom-left", "bottom-edge", "bottom-right"]

var _failures: Array[String] = []
var _check_count := 0
var _started_usec := 0

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	_started_usec = Time.get_ticks_usec()
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("A windowed renderer is required; the active display server is headless.")
		return
	root.size = CAPTURE_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("Could not load the real gameplay scene: %s" % MAIN_SCENE)
		return
	var game := packed.instantiate() as Node2D
	if game == null:
		_fail("The gameplay scene did not instantiate as Node2D.")
		return
	root.add_child(game)
	await process_frame
	var player := game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	var camera := game.get_node_or_null("YSortActors/Player/Camera2D") as Camera2D
	var stage := game.get_node_or_null("StageBackground") as Sprite2D
	if player == null or camera == null or stage == null or stage.texture == null:
		_fail("Gameplay scene is missing its player camera or Forest Ruins background.")
		return
	_check(camera.zoom.is_equal_approx(Vector2(1.2, 1.2)), "Camera2D zoom remains 1.2")
	_check(camera.position_smoothing_enabled, "Camera2D position smoothing remains enabled")
	var source := stage.texture.get_image()
	for raider in get_nodes_in_group("forest_raiders"):
		raider.set_physics_process(false)
		raider.velocity = Vector2.ZERO
		raider.get_node("AttackArea").monitoring = false
	_check(source != null and source.get_size() == CAPTURE_SIZE, "Forest Ruins source pixels are 1920x1080")
	_check(camera.limit_left == 0 and camera.limit_top == 0 and camera.limit_right == CAPTURE_SIZE.x and camera.limit_bottom == CAPTURE_SIZE.y, "camera limits match the actual stage texture bounds")
	if source == null or source.get_size() != CAPTURE_SIZE:
		_finish()
		return
	# This sheet compares the stage texture at the viewport boundary. Hide the
	# enlarged actors and HUD so their foreground pixels do not invalidate those
	# background-only samples; actor framing is checked by gameplay window tests.
	var hud := game.get_node_or_null("CombatHUD") as CanvasLayer
	if hud != null:
		hud.visible = false
	for actor in game.get_node("YSortActors").get_children():
		var art := actor.get_node_or_null("VisualRoot/PlayerArt") as Sprite2D
		if art == null:
			art = actor.get_node_or_null("VisualRoot/RaiderArt") as Sprite2D
		if art != null:
			art.visible = false

	var comparison := Image.create(CAPTURE_SIZE.x, CAPTURE_SIZE.y, false, Image.FORMAT_RGBA8)
	comparison.fill(Color.BLACK)
	for position_index in range(POSITIONS.size()):
		var position: Vector2 = POSITIONS[position_index]
		player.global_position = position
		player.velocity = Vector2.ZERO
		player.set("camera_trauma", 0.0)
		player.camera.offset = Vector2.ZERO
		# Keep the real camera smoothing enabled and wait only until it settles.
		var previous_center := camera.get_screen_center_position()
		var settled_frames := 0
		for _frame in range(120):
			await process_frame
			await RenderingServer.frame_post_draw
			var current_center := camera.get_screen_center_position()
			if current_center.distance_to(previous_center) <= 0.5:
				settled_frames += 1
				if settled_frames >= 3:
					break
			else:
				settled_frames = 0
			previous_center = current_center
		_check(settled_frames >= 3, "%s camera smoothing settles before capture" % POSITION_NAMES[position_index])
		player.call("_add_camera_trauma", 0.34)
		player.call("_add_camera_trauma", 0.22)
		player.call("_add_camera_trauma", 0.12)
		player.call("_update_camera_trauma", 0.0)
		for _frame in range(2):
			await process_frame
			await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		_check(frame != null and frame.get_size() == CAPTURE_SIZE, "%s frame is rendered at 1920x1080" % POSITION_NAMES[position_index])
		if frame == null or frame.get_size() != CAPTURE_SIZE:
			continue
		_check_boundary_pixels(frame, source, camera, POSITION_NAMES[position_index])
		# Pixel checks are complete, so resize this one captured image in place.
		frame.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_LANCZOS)
		var tile_origin := Vector2i((position_index % 3) * TILE_SIZE.x, (position_index / 3) * TILE_SIZE.y)
		comparison.blit_rect(frame, Rect2i(Vector2i.ZERO, TILE_SIZE), tile_origin)

	# Wait for accumulated three-hit trauma to decay completely and ensure offset restores.
	for _frame in range(100):
		await physics_frame
		await process_frame
		await RenderingServer.frame_post_draw
	_check(is_zero_approx(float(player.get("camera_trauma"))), "camera trauma decays back to zero")
	_check(player.camera.offset == Vector2.ZERO, "camera offset returns to zero after shake")
	var absolute_output := ProjectSettings.globalize_path(OUTPUT_PATH)
	var save_error := comparison.save_png(absolute_output)
	_check(save_error == OK, "nine-frame comparison PNG saves")
	if save_error == OK:
		print("camera-boundary-capture: saved nine rendered 1920x1080 Window Viewport frames to %s" % absolute_output)
	_finish()

func _check_boundary_pixels(frame: Image, source: Image, camera: Camera2D, position_name: String) -> void:
	var edge_points := [
		Vector2i(10, 10), Vector2i(960, 10), Vector2i(1909, 10),
		Vector2i(10, 540), Vector2i(1909, 540),
		Vector2i(10, 1069), Vector2i(960, 1069), Vector2i(1909, 1069),
	]
	var matched_background_pixels := 0
	var samples_inside_stage := 0
	var center := camera.get_screen_center_position()
	for screen_pixel in edge_points:
		var world_pixel := center + (Vector2(screen_pixel) - Vector2(CAPTURE_SIZE) * 0.5) / camera.zoom
		if world_pixel.x < 0.0 or world_pixel.y < 0.0 or world_pixel.x >= source.get_width() or world_pixel.y >= source.get_height():
			continue
		samples_inside_stage += 1
		var expected := source.get_pixelv(Vector2i(roundi(world_pixel.x), roundi(world_pixel.y)))
		var actual := frame.get_pixelv(screen_pixel)
		if _color_distance_squared(actual, expected) < 0.018:
			matched_background_pixels += 1
	_check(samples_inside_stage == edge_points.size(), "%s shows no backdrop gaps at viewport edge pixels" % position_name)
	_check(matched_background_pixels >= 6, "%s boundary samples match actual Forest Ruins pixels" % position_name)

func _color_distance_squared(left: Color, right: Color) -> float:
	var difference := left - right
	return difference.r * difference.r + difference.g * difference.g + difference.b * difference.b

func _check(condition: bool, description: String) -> void:
	_check_count += 1
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	var elapsed_seconds := float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	print("camera-boundary-capture: checks=%d elapsed_seconds=%.3f" % [_check_count, elapsed_seconds])
	if _failures.is_empty():
		print("camera-boundary-capture: all checks passed")
		quit(0)
		return
	for failure in _failures:
		push_error("camera-boundary-capture: " + failure)
	push_error("camera-boundary-capture: %d check(s) failed" % _failures.size())
	quit(1)

func _fail(message: String) -> void:
	push_error("camera-boundary-capture: " + message)
	quit(1)
