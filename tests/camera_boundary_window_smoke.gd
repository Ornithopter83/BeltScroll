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
	_check(camera.zoom.is_equal_approx(Vector2(1.2, 1.2)), "camera zoom is preserved at 1.2")
	_check(camera.position_smoothing_enabled, "camera position smoothing stays enabled")
	_check(stage.texture.get_size() == Vector2(EXPECTED_SIZE), "camera boundary is checked against the 1920x1080 stage texture")
	_check(camera.limit_left == 0 and camera.limit_top == 0 and camera.limit_right == 1920 and camera.limit_bottom == 1080, "camera limits cover the stage background exactly")
	var requested := Vector2(100.0, -100.0)
	var bounded: Vector2 = player.call("_clamp_camera_offset_to_background", requested)
	_check(bounded.length() < requested.length(), "camera trauma offset is constrained by visible background limits")
	player.call("_add_camera_trauma", 0.34)
	player.call("_add_camera_trauma", 0.22)
	player.call("_add_camera_trauma", 0.12)
	player.call("_update_camera_trauma", 0.0)
	_check(player.camera_trauma > 0.0 and player.camera.offset != Vector2.ZERO, "three-hit trauma produces a bounded shake")
	for _frame in range(100):
		await process_frame
	_check(is_zero_approx(player.camera_trauma) and camera.offset == Vector2.ZERO, "camera trauma decays and its offset returns to zero")

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
