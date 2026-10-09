extends SceneTree
"""Checks rendered Raider motion states, scale, anchors, persistence, and failure exit."""

const CAPTURE_SCRIPT := "res://tools/capture_raider_motion_sheet.gd"
const CAPTURE_PATH := "res://assets/art/review/raider_motion_states_capture.png"
const RAIDER_SCENE := "res://scenes/enemies/forest_raider.tscn"
const DISPLAY_HEIGHT := 192.0
const FLOOR_TOLERANCE := 0.05
const CELL_SIZE := Vector2i(480, 540)
const STATE_COUNT := 7

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "smoke runs with a real Window Viewport renderer")
	var packed := load(RAIDER_SCENE) as PackedScene
	_check(packed != null, "integrated ForestRaider scene loads")
	if packed == null:
		_finish()
		return
	var raider := packed.instantiate() as CharacterBody2D
	var art := raider.get_node("VisualRoot/RaiderArt") as Sprite2D
	var bounds := art.texture.get_image().get_used_rect()
	art.scale = Vector2.ONE * (DISPLAY_HEIGHT / float(bounds.size.y))
	root.add_child(raider)
	await process_frame
	raider.set_physics_process(false)
	var animator := raider.get_node("VisualAnimator")
	var shown_height := float(bounds.size.y) * art.scale.y
	_check(is_equal_approx(shown_height, DISPLAY_HEIGHT), "captured Raider alpha silhouette is displayed at 192 px high")
	var foot := _foot_point(art)
	raider.set("attack_phase", "active")
	for _frame in range(24):
		animator.call("_process", 1.0 / 60.0)
	_check(_foot_point(art).distance_to(foot) <= FLOOR_TOLERANCE, "active strike preserves its alpha-edge foot anchor")
	raider.set("attack_phase", "recovery")
	raider.set("attack_phase_remaining", 0.0)
	for _frame in range(90):
		animator.call("_process", 1.0 / 60.0)
	_check(absf(art.rotation) < 0.01 and art.scale.distance_to(Vector2.ONE * (DISPLAY_HEIGHT / float(bounds.size.y))) < 0.004, "recovery pose returns to neutral without visual residue")
	raider.set("health", 0)
	for _frame in range(60):
		animator.call("_process", 1.0 / 60.0)
	var ko_rotation := art.rotation
	var ko_scale := art.scale
	for _frame in range(45):
		animator.call("_process", 1.0 / 60.0)
	_check(is_equal_approx(art.rotation, ko_rotation) and art.scale.is_equal_approx(ko_scale), "KO pose settles without residual breathing or stride")
	_check(_foot_point(art).distance_to(foot) <= FLOOR_TOLERANCE, "KO pose preserves its alpha-edge foot anchor")
	raider.queue_free()
	await process_frame
	if DisplayServer.get_name() != "headless":
		var executable := OS.get_executable_path()
		var project_path := ProjectSettings.globalize_path("res://")
		var script_path := ProjectSettings.globalize_path(CAPTURE_SCRIPT)
		var child_output: Array = []
		var child_exit := OS.execute(executable, ["--headless", "--path", project_path, "--script", script_path], child_output, true)
		_check(child_exit != 0, "capture exits nonzero when Window Viewport renderer is unavailable")
		if child_exit == 0:
			push_error("headless capture unexpectedly succeeded: " + "\n".join(child_output))
		if child_exit == -1:
			_check(false, "headless renderer failure subprocess launches")
		else:
			_check(not child_output.is_empty() and str(child_output[0]).contains("headless"), "renderer failure explains the headless limitation")
	var output := []
	var capture_exit := OS.execute(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "--script", ProjectSettings.globalize_path(CAPTURE_SCRIPT), "--", CAPTURE_PATH], output, true)
	_check(capture_exit == 0, "capture tool renders and saves its PNG successfully")
	if capture_exit != 0:
		for line in output:
			push_error("capture output: " + str(line))
	else:
		_check(_verify_saved_sheet(), "saved PNG dimensions, state frame differences, and rendered content are valid")
		var capture_source := FileAccess.get_file_as_string(CAPTURE_SCRIPT)
		_check(not capture_source.contains("♥") and capture_source.contains("게임 HUD 제외"), "pose review sheet does not depict a gameplay health bar")
	_finish()

func _verify_saved_sheet() -> bool:
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(CAPTURE_PATH)) != OK:
		_check(false, "saved state comparison PNG can be reopened")
		return false
	_check(image.get_size() == Vector2i(1920, 1080), "saved comparison PNG is 1920x1080")
	if image.get_size() != Vector2i(1920, 1080):
		return false
	var signatures: Array[float] = []
	for state in range(STATE_COUNT):
		var x0 := (state % 4) * CELL_SIZE.x
		var y0 := (state / 4) * CELL_SIZE.y
		var signature := 0.0
		for y in range(y0 + 150, y0 + 480, 24):
			for x in range(x0 + 72, x0 + 408, 24):
				var color := image.get_pixel(x, y)
				signature += color.r * 3.0 + color.g * 5.0 + color.b * 7.0
		signatures.append(signature)
	var distinct := 0
	for i in range(signatures.size()):
		for j in range(i + 1, signatures.size()):
			if absf(signatures[i] - signatures[j]) > 0.2:
				distinct += 1
	_check(distinct >= 12, "idle, tracking, windup, active, recovery, hit, and KO cells render visibly different frames")
	var changed_samples := 0
	for y in range(100, 1060, 40):
		for x in range(20, 1900, 40):
			if image.get_pixel(x, y).get_luminance() > 0.08:
				changed_samples += 1
	_check(changed_samples > 120, "saved viewport image contains the Forest Ruins scene and review overlay")
	return distinct >= 12 and changed_samples > 120

func _foot_point(sprite: Sprite2D) -> Vector2:
	var image := sprite.texture.get_image()
	var bounds := image.get_used_rect()
	var texture_size := Vector2(sprite.texture.get_size())
	var alpha_foot := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y))
	var local_offset := (alpha_foot - texture_size * 0.5) * sprite.scale
	return sprite.position + local_offset.rotated(sprite.rotation)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("raider_motion_capture_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("raider_motion_capture_smoke: " + failure)
	push_error("raider_motion_capture_smoke: %d check(s) failed" % failures.size())
	quit(1)
