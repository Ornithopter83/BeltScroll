extends SceneTree

const REVIEW_SCENE := "res://scenes/review/combat_art_stage_review.tscn"
const REVIEW_SCRIPT := "res://scripts/review/combat_art_stage_review.gd"
const PLAYER_PATH := "res://assets/art/player/elven_fighter_reference_v4_matte_v3_1254x1254.png"
const RAIDER_PATH := "res://assets/art/enemies/forest_raider_reference_v1_safe_1254x1254.png"
const FOREST_PATH := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const TARGET_SCREEN_HEIGHT := 192.0
const FOOT_BASELINE := 850.0

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var review_script := load(REVIEW_SCRIPT) as Script
	var packed := load(REVIEW_SCENE) as PackedScene
	_check(review_script != null, "review controller script loads")
	_check(packed != null, "standalone review scene loads")
	_check(ResourceLoader.exists(PLAYER_PATH) and ResourceLoader.exists(RAIDER_PATH) and ResourceLoader.exists(FOREST_PATH), "all three existing art assets are connected")
	if review_script != null:
		var paths := review_script.get_script_constant_map()
		_check(paths.get("PLAYER_PATH") == PLAYER_PATH and paths.get("RAIDER_PATH") == RAIDER_PATH and paths.get("FOREST_PATH") == FOREST_PATH, "review references the exact requested source assets")
	if packed == null:
		_finish()
		return
	var review := packed.instantiate() as Node2D
	_check(review != null, "review instantiates independently as Node2D")
	if review == null:
		_finish()
		return
	root.add_child(review)
	for _frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var background := review.get_node_or_null("ForestRuinsBackground") as Sprite2D
	_check(background != null and background.texture != null and background.texture.resource_path == FOREST_PATH, "Forest Ruins is the scene backdrop")
	var camera := review.get_node_or_null("Camera2D") as Camera2D
	_check(camera != null and camera.zoom.is_equal_approx(Vector2(1.2, 1.2)), "camera starts at zoom 1.2")
	var actor_group := review.get_node_or_null("ReviewActors") as Node2D
	_check(actor_group != null and actor_group.y_sort_enabled, "candidate anchors use depth sorting")
	var player_anchor := review.get_node_or_null("ReviewActors/PlayerCandidate") as Node2D
	var raider_anchor := review.get_node_or_null("ReviewActors/RaiderCandidate") as Node2D
	_check(player_anchor != null and raider_anchor != null, "both independent candidate anchors exist")
	if player_anchor != null and raider_anchor != null:
		_check(is_equal_approx(player_anchor.position.y, FOOT_BASELINE) and is_equal_approx(raider_anchor.position.y, FOOT_BASELINE), "both candidates share the same foot baseline")
		for candidate in [[player_anchor, "PlayerArt", PLAYER_PATH], [raider_anchor, "RaiderArt", RAIDER_PATH]]:
			var anchor: Node2D = candidate[0]
			var sprite := anchor.get_node_or_null(candidate[1]) as Sprite2D
			_check(sprite != null and sprite.texture != null, "%s sprite and texture are connected" % candidate[1])
			if sprite != null and sprite.texture != null:
				var rendered_height := sprite.texture.get_height() * sprite.scale.y * camera.zoom.y
				_check(absf(rendered_height - TARGET_SCREEN_HEIGHT) <= 1.0, "%s opaque crop renders about 192 screen pixels high" % candidate[1])
				_check(absf(sprite.position.y + sprite.texture.get_height() * sprite.scale.y * 0.5) <= 0.1, "%s bottom aligns to its anchor" % candidate[1])
		_check(review_script.get_script_constant_map().get("CAMERA_ZOOM") == Vector2(1.2, 1.2), "review script defines required zoom")
	var overlay := review.get_node_or_null("ReviewCanvas/ReviewOverlay") as Control
	_check(overlay != null and overlay.find_child("FootBaseline", true, false) is ColorRect, "review UI includes visible shared baseline")
	var viewport_image := root.get_texture().get_image()
	_check(viewport_image != null and not viewport_image.is_empty(), "Window Viewport produces a rendered image")
	if viewport_image != null and not viewport_image.is_empty():
		_check(viewport_image.get_size() == Vector2i(1920, 1080), "Window Viewport renders at 1920x1080")
		_check(_has_visible_variation(viewport_image), "rendered frame contains visible scene variation")
	review.queue_free()
	_finish()

func _has_visible_variation(image: Image) -> bool:
	var origin := image.get_pixel(0, 0)
	var varied := 0
	for y in range(40, image.get_height(), 80):
		for x in range(40, image.get_width(), 80):
			var color := image.get_pixel(x, y)
			var delta := color - origin
			if delta.r * delta.r + delta.g * delta.g + delta.b * delta.b > 0.0025:
				varied += 1
	return varied >= 12

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("combat_art_stage_review_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("combat_art_stage_review_smoke: " + failure)
		quit(1)
