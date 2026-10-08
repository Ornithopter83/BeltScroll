extends SceneTree

const REVIEW_SCENE := "res://scenes/review/combat_art_stage_review.tscn"
const REVIEW_SCRIPT := "res://scripts/review/combat_art_stage_review.gd"
const CAPTURE_PATH := "res://assets/art/review/combat_art_overlap_capture.png"
const PLAYER_PATH := "res://assets/art/player/elven_fighter_reference_v4_matte_v4_1254x1254.png"
const RAIDER_PATH := "res://assets/art/enemies/forest_raider_reference_v1_safe_1254x1254.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)
const TARGET_SCREEN_HEIGHT := 192.0

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("combat_art_overlap_smoke requires a window renderer; headless mode cannot validate a Window Viewport capture")
		quit(1)
		return
	root.size = EXPECTED_SIZE
	var review_script := load(REVIEW_SCRIPT) as Script
	var packed := load(REVIEW_SCENE) as PackedScene
	_check(review_script != null and packed != null, "review script and scene load")
	_check(ResourceLoader.exists(PLAYER_PATH) and ResourceLoader.exists(RAIDER_PATH), "v4 matte and Raider safe source assets exist")
	if review_script != null:
		var source_paths := review_script.get_script_constant_map()
		_check(source_paths.get("PLAYER_PATH") == PLAYER_PATH and source_paths.get("RAIDER_PATH") == RAIDER_PATH, "review mode is configured for the exact source artwork")
	if packed == null:
		_finish()
		return
	var review := packed.instantiate() as Node2D
	_check(review != null, "overlap review scene instantiates")
	if review == null:
		_finish()
		return
	review.set("overlap_review_mode", true)
	root.add_child(review)
	for _frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var actors := review.get_node_or_null("ReviewActors") as Node2D
	var camera := review.get_node_or_null("Camera2D") as Camera2D
	_check(actors != null and actors.y_sort_enabled, "overlap candidates use YSort")
	_check(camera != null and camera.zoom.is_equal_approx(Vector2(1.2, 1.2)), "overlap camera uses zoom 1.2")
	if actors != null:
		_check_pair(actors, "PlayerCandidate", "RaiderCandidate", PLAYER_PATH, RAIDER_PATH, "Raider is in front")
		_check_pair(actors, "PlayerFrontCandidate", "RaiderFrontCandidate", PLAYER_PATH, RAIDER_PATH, "Player is in front")
	var overlay := review.get_node_or_null("ReviewCanvas/ReviewOverlay") as Control
	_check(overlay != null and overlay.find_child("FootBaseline", true, false) == null and overlay.find_children("FootBaseline_*", "ColorRect", true, false).size() == 4, "four feet baselines identify both reversed depth pairs")
	var viewport_image := root.get_texture().get_image()
	_check(viewport_image != null and not viewport_image.is_empty(), "Window Viewport overlap frame renders")
	if viewport_image != null and not viewport_image.is_empty():
		_check(viewport_image.get_size() == EXPECTED_SIZE, "Window Viewport is 1920x1080")
		_check(_has_visible_variation(viewport_image), "overlap frame contains visible rendered scene pixels")
	var capture := Image.new()
	var capture_error := capture.load(CAPTURE_PATH)
	_check(capture_error == OK, "separate overlap capture PNG loads")
	if capture_error == OK:
		_check(capture.get_size() == EXPECTED_SIZE, "overlap capture PNG is exactly 1920x1080")
		_check(_has_visible_variation(capture), "saved overlap capture is not blank")
	review.queue_free()
	_finish()

func _check_pair(actors: Node2D, player_name: String, raider_name: String, player_path: String, raider_path: String, description: String) -> void:
	var player := actors.get_node_or_null(player_name) as Node2D
	var raider := actors.get_node_or_null(raider_name) as Node2D
	_check(player != null and raider != null, "%s anchors exist" % description)
	if player == null or raider == null:
		return
	_check(is_equal_approx(player.position.x, raider.position.x), "%s pair shares X" % description)
	_check(is_equal_approx(absf(player.position.y - raider.position.y), 40.0), "%s pair differs only by its Y depth" % description)
	_check(player.position.y < raider.position.y if "Raider" in description else player.position.y > raider.position.y, description)
	for candidate in [[player, "PlayerArt", player_path], [raider, "RaiderArt", raider_path]]:
		var anchor: Node2D = candidate[0]
		var sprite := anchor.get_node_or_null(candidate[1]) as Sprite2D
		_check(sprite != null and sprite.texture != null, "%s has a rendered sprite" % anchor.name)
		if sprite != null and sprite.texture != null:
			_check(absf(sprite.texture.get_height() * sprite.scale.y * 1.2 - TARGET_SCREEN_HEIGHT) <= 1.0, "%s renders about 192 screen pixels tall" % anchor.name)

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
		print("combat_art_overlap_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("combat_art_overlap_smoke: " + failure)
	push_error("combat_art_overlap_smoke: %d check(s) failed" % failures.size())
	quit(1)
