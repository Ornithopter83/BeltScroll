extends SceneTree

const REVIEW_SCENE := "res://scenes/review/combat_art_stage_review.tscn"
const REVIEW_SCRIPT := "res://scripts/review/combat_art_stage_review.gd"
const CAPTURE_PATH := "res://assets/art/review/combat_art_v5_clean_capture.png"
const PLAYER_PATH := "res://assets/art/player/elven_fighter_reference_v5_clean_1254x1254.png"
const RAIDER_PATH := "res://assets/art/enemies/forest_raider_reference_v1_clean_1254x1254.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)
const TARGET_SCREEN_HEIGHT := 192.0

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("combat_art_candidate_capture_smoke requires a window renderer")
		quit(1)
		return
	root.size = EXPECTED_SIZE
	var review_script := load(REVIEW_SCRIPT) as Script
	var packed := load(REVIEW_SCENE) as PackedScene
	_check(review_script != null and packed != null, "review script and scene load")
	_check(ResourceLoader.exists(PLAYER_PATH) and ResourceLoader.exists(RAIDER_PATH), "v5_clean and Raider clean source art exist")
	if review_script != null:
		var source_paths := review_script.get_script_constant_map()
		_check(source_paths.get("CANDIDATE_PLAYER_PATH") == PLAYER_PATH and source_paths.get("CANDIDATE_RAIDER_PATH") == RAIDER_PATH, "candidate mode connects the exact clean sources")
	if packed == null:
		_finish()
		return
	var review := packed.instantiate() as Node2D
	_check(review != null, "standalone review instantiates")
	if review == null:
		_finish()
		return
	review.set("candidate_review_mode", true)
	root.add_child(review)
	for _frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var actors := review.get_node_or_null("ReviewActors") as Node2D
	var camera := review.get_node_or_null("Camera2D") as Camera2D
	_check(actors != null and actors.y_sort_enabled, "candidate anchors use YSort depth sorting")
	_check(camera != null and camera.zoom.is_equal_approx(Vector2(1.2, 1.2)), "candidate camera keeps zoom 1.2")
	var player := review.get_node_or_null("ReviewActors/PlayerCandidate") as Node2D
	var raider := review.get_node_or_null("ReviewActors/RaiderCandidate") as Node2D
	_check(player != null and raider != null, "both candidate anchors exist")
	if player != null and raider != null:
		_check(player.position.is_equal_approx(Vector2(650, 850)) and raider.position.is_equal_approx(Vector2(1270, 850)), "default candidate staging shares the foot baseline")
		_check(_check_sprite(player, "PlayerArt", PLAYER_PATH, camera), "PLAYER v5_clean sprite uses the connected texture and 192 px scale")
		_check(_check_sprite(raider, "RaiderArt", RAIDER_PATH, camera), "RAIDER clean sprite uses the connected texture and 192 px scale")
		player.position = Vector2(960, 850)
		raider.position = Vector2(960, 890)
		_check(player.position.y < raider.position.y, "Raider draws in front when its Y anchor is lower")
		player.position.y = 890
		raider.position.y = 850
		_check(player.position.y > raider.position.y, "PLAYER draws in front when its Y anchor is lower")
	var overlay := review.get_node_or_null("ReviewCanvas/ReviewOverlay") as Control
	_check(overlay != null and overlay.find_child("AssetNames", true, false) is Label and overlay.find_child("Controls", true, false) is Label, "candidate names, approval state, and per-art direction controls are shown")
	var switch_event := InputEventKey.new()
	switch_event.pressed = true
	switch_event.keycode = KEY_C
	review.call("_unhandled_key_input", switch_event)
	_check(not review.get("candidate_review_mode"), "C returns to the preserved v4 and Raider safe review mode")
	review.call("_unhandled_key_input", switch_event)
	_check(review.get("candidate_review_mode"), "C selects the v5_clean and Raider clean candidate mode")
	switch_event.keycode = KEY_P
	review.call("_unhandled_key_input", switch_event)
	_check(player.get_node("PlayerArt").flip_h and not raider.get_node("RaiderArt").flip_h, "P changes only the PLAYER artwork direction")
	switch_event.keycode = KEY_R
	review.call("_unhandled_key_input", switch_event)
	_check(player.get_node("PlayerArt").flip_h and raider.get_node("RaiderArt").flip_h, "R changes the RAIDER artwork direction independently")
	switch_event.keycode = KEY_O
	review.call("_unhandled_key_input", switch_event)
	_check(review.get("candidate_overlap_mode") and player.position.y < raider.position.y, "O enables the candidate YSort overlap arrangement")
	review.call("_unhandled_key_input", switch_event)
	_check(not review.get("candidate_overlap_mode") and player.position.y == raider.position.y, "O restores the default candidate staging")
	var viewport_image := root.get_texture().get_image()
	_check(viewport_image != null and not viewport_image.is_empty(), "Window Viewport renders a frame")
	if viewport_image != null and not viewport_image.is_empty():
		_check(viewport_image.get_size() == EXPECTED_SIZE, "Window Viewport frame is 1920x1080")
		_check(_has_visible_variation(viewport_image), "Window Viewport frame contains rendered scene pixels")
	var capture := Image.new()
	var capture_error := capture.load(CAPTURE_PATH)
	_check(capture_error == OK, "real candidate capture PNG exists")
	if capture_error == OK:
		_check(capture.get_size() == EXPECTED_SIZE, "candidate capture PNG is 1920x1080")
		_check(_has_visible_variation(capture), "candidate capture contains visible rendered pixels")
	review.queue_free()
	await process_frame
	_validate_capture_failure_exit()
	_finish()

func _check_sprite(anchor: Node2D, sprite_name: String, expected_path: String, camera: Camera2D) -> bool:
	var sprite := anchor.get_node_or_null(sprite_name) as Sprite2D
	var valid := sprite != null and sprite.texture != null
	_check(valid, "%s sprite and texture load" % sprite_name)
	if not valid:
		return false
	var source := load(expected_path) as Texture2D
	_check(source != null, "%s source resource loads" % sprite_name)
	if source == null:
		return false
	var opaque_height := sprite.texture.get_height() * sprite.scale.y * camera.zoom.y
	_check(absf(opaque_height - TARGET_SCREEN_HEIGHT) <= 1.0, "%s opaque bounds render at 192 px" % sprite_name)
	_check(absf(sprite.position.y + sprite.texture.get_height() * sprite.scale.y * 0.5) <= 0.1, "%s bottom aligns to its foot anchor" % sprite_name)
	return sprite.texture.get_width() > 0

func _validate_capture_failure_exit() -> void:
	var subprocess_output: Array[String] = []
	var project_path := ProjectSettings.globalize_path("res://")
	var exit_code := OS.execute(OS.get_executable_path(), ["--headless", "--path", project_path, "--script", "res://tools/capture_combat_art_review.gd"], subprocess_output, true)
	_check(exit_code != 0, "capture tool exits with failure status when a real Window Viewport is unavailable")

func _has_visible_variation(image: Image) -> bool:
	var origin := image.get_pixel(0, 0)
	var varied := 0
	for y in range(40, image.get_height(), 80):
		for x in range(40, image.get_width(), 80):
			var difference := image.get_pixel(x, y) - origin
			if difference.r * difference.r + difference.g * difference.g + difference.b * difference.b > 0.0025:
				varied += 1
	return varied >= 12

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("combat_art_candidate_capture_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("combat_art_candidate_capture_smoke: " + failure)
	push_error("combat_art_candidate_capture_smoke: %d check(s) failed" % failures.size())
	quit(1)
