extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const RAIDER_SCENE := "res://scenes/enemies/forest_raider.tscn"
const ART_PATH := "res://assets/art/enemies/forest_raider_reference_v1_final_candidate_1254x1254.png"
const CAPTURE_PATH := "res://assets/art/review/forest_raider_in_game_capture.png"
const FEEDBACK_CAPTURE_PATH := "res://assets/art/review/forest_raider_feedback_capture.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const CAMERA_ZOOM := Vector2(1.2, 1.2)
const TARGET_SCREEN_HEIGHT := 192.0
const HIT_COLOR := Color(1.0, 0.78, 0.58, 1.0)
const KNOCKED_OUT_COLOR := Color(0.62, 0.62, 0.62, 0.78)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("forest_raider_art_integration_smoke requires a Window Viewport")
		quit(1)
		return
	root.size = CAPTURE_SIZE
	var raider_packed := load(RAIDER_SCENE) as PackedScene
	var main_packed := load(MAIN_SCENE) as PackedScene
	_check(raider_packed != null and main_packed != null, "Raider and real gameplay scenes load")
	_check(ResourceLoader.exists(ART_PATH), "visually approved Raider candidate is available")
	if raider_packed == null or main_packed == null:
		_finish()
		return

	var scene := raider_packed.instantiate() as CharacterBody2D
	var sprite := scene.get_node_or_null("VisualRoot/RaiderArt") as Sprite2D
	_check(sprite != null and sprite.texture != null and sprite.texture.resource_path == ART_PATH, "RaiderArt uses the approved candidate Sprite2D")
	_check(scene.get_node_or_null("VisualRoot/Body") == null and scene.get_node_or_null("VisualRoot/Cloak") == null and scene.get_node_or_null("VisualRoot/Face") == null and scene.get_node_or_null("VisualRoot/Bandana") == null, "temporary Body, Cloak, Face, and Bandana polygons are removed")
	_check(scene.get_node_or_null("GroundShadow") is Polygon2D and scene.get_node_or_null("VisualRoot/AttackFlash") is Polygon2D, "ground shadow and attack flash are preserved")
	_check(scene.get_node_or_null("CollisionShape2D") is CollisionShape2D and scene.get_node_or_null("AttackArea/CollisionShape2D") is CollisionShape2D and scene.get_node_or_null("ReceiveArea/CollisionShape2D") is CollisionShape2D, "body, attack, and receive physics shapes are preserved")
	var art_image := sprite.texture.get_image() if sprite != null and sprite.texture != null else null
	var alpha_bounds := art_image.get_used_rect() if art_image != null else Rect2i()
	_check(alpha_bounds == Rect2i(99, 90, 1055, 1074), "Sprite2D texture keeps the approved alpha silhouette bounds")
	var camera := Camera2D.new()
	camera.zoom = CAMERA_ZOOM
	if sprite != null and sprite.texture != null:
		var displayed_height := float(alpha_bounds.size.y) * sprite.scale.y * camera.zoom.y
		_check(absf(displayed_height - TARGET_SCREEN_HEIGHT) <= 0.1, "alpha silhouette displays 192 screen pixels at camera zoom 1.2")
		var alpha_bottom_local := sprite.position.y + (float(alpha_bounds.end.y) - float(sprite.texture.get_height()) * 0.5) * sprite.scale.y
		var floor_y: float = (scene.get_node("VisualRoot") as Node2D).position.y + alpha_bottom_local
		_check(absf(floor_y) <= 0.05, "alpha silhouette foot bottom aligns to the Raider physics floor")
		_check(is_equal_approx(sprite.scale.x, sprite.scale.y) and absf(sprite.scale.y - 160.0 / 1074.0) < 0.00001, "art scale preserves aspect ratio and uses the alpha silhouette target")
	var raider_scene_text := FileAccess.get_file_as_string(RAIDER_SCENE)
	_check(not raider_scene_text.contains("elven_fighter_reference_v5_final_candidate"), "unapproved Player candidate is not connected to the Raider scene")
	scene.free()
	camera.free()

	var game := main_packed.instantiate() as Node2D
	_check(game != null, "actual gameplay scene instantiates for the in-game capture")
	if game == null:
		_finish()
		return
	root.add_child(game)
	for _frame in range(3):
		await process_frame
	var player := game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	var raider := game.get_node_or_null("YSortActors/ForestRaider1") as CharacterBody2D
	var raider_two := game.get_node_or_null("YSortActors/ForestRaider2") as CharacterBody2D
	var raider_three := game.get_node_or_null("YSortActors/ForestRaider3") as CharacterBody2D
	var actor_layer := game.get_node_or_null("YSortActors") as Node2D
	var active_camera := game.get_node_or_null("YSortActors/Player/Camera2D") as Camera2D
	_check(player != null and raider != null and raider_two != null and raider_three != null and actor_layer != null and actor_layer.y_sort_enabled, "real Player and all three Raiders participate in YSort combat")
	_check(get_nodes_in_group("forest_raiders").size() == 3, "actual combat scene contains exactly three Raiders for the visual review")
	_check(active_camera != null and active_camera.zoom.is_equal_approx(CAMERA_ZOOM) and active_camera.is_current(), "real gameplay camera uses zoom 1.2")
	if player == null or raider == null or raider_two == null or raider_three == null or active_camera == null:
		game.queue_free()
		_finish()
		return

	player.global_position = Vector2(940.0, 540.0)
	raider.global_position = Vector2(1010.0, 540.0)
	player.velocity = Vector2.ZERO
	raider.velocity = Vector2.ZERO
	await _physics_frames(3)
	_check(float(raider.get_node("VisualRoot").scale.x) > 0.0, "Raider artwork faces left when pursuing a player to its left (scale x=%s)" % raider.get_node("VisualRoot").scale.x)
	player.global_position.x = 1080.0
	await _physics_frames(3)
	_check(float(raider.get_node("VisualRoot").scale.x) < 0.0, "Raider artwork flips to face right when pursuing a player to its right")
	player.global_position.x = 940.0
	await _physics_frames(3)
	raider.global_position = Vector2(1010.0, 540.0)
	raider.velocity = Vector2.ZERO
	raider.call("_begin_attack")
	_check(raider.get_node("VisualRoot/AttackFlash").visible, "preserved attack flash remains visible with the sprite art")
	var impact_packed := load("res://scenes/vfx/combat_impact.tscn") as PackedScene
	if impact_packed != null:
		var impact := impact_packed.instantiate() as Node2D
		raider.add_child(impact)
		impact.global_position = raider.global_position + Vector2(0.0, -24.0)
		impact.configure(3, Vector2.LEFT)
		impact.lifetime = 5.0
		impact.set("_start_ticks_usec", Time.get_ticks_usec())
	else:
		_check(false, "combat impact VFX scene loads for the capture")

	for _frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var viewport_image := root.get_texture().get_image()
	_check(viewport_image != null and not viewport_image.is_empty() and viewport_image.get_size() == CAPTURE_SIZE, "real Window Viewport returns the expected 1920x1080 combat frame")
	if viewport_image != null and not viewport_image.is_empty() and viewport_image.get_size() == CAPTURE_SIZE:
		_check(_has_visible_variation(viewport_image), "in-game combat frame contains rendered gameplay and Raider art")
		var absolute_capture_path := ProjectSettings.globalize_path(CAPTURE_PATH)
		var save_error := viewport_image.save_png(absolute_capture_path)
		_check(save_error == OK, "in-game Window Viewport capture is saved")
		if save_error == OK:
			print("forest-raider-art-capture: saved real 1920x1080 Window Viewport frame to %s" % CAPTURE_PATH)

	raider.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	var raider_sprite := raider.get_node("VisualRoot/RaiderArt") as Sprite2D
	_check(raider_sprite.modulate.is_equal_approx(HIT_COLOR), "hit flash modulates the integrated Sprite2D")
	for _frame in range(12):
		await physics_frame
	_check(raider_sprite.modulate.is_equal_approx(Color.WHITE), "live Raider sprite returns to its normal color after hit flash")
	raider.receive_hit({"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	_check(raider_sprite.modulate.is_equal_approx(HIT_COLOR), "lethal hit flash is applied to the integrated Sprite2D")
	for _frame in range(12):
		await physics_frame
	_check(raider_sprite.modulate.is_equal_approx(KNOCKED_OUT_COLOR), "defeated Raider sprite keeps its KO feedback tint")
	var second_sprite := raider_two.get_node("VisualRoot/RaiderArt") as Sprite2D
	var third_sprite := raider_three.get_node("VisualRoot/RaiderArt") as Sprite2D
	raider_two.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.2, "attack_stage": 1})
	_check(second_sprite.modulate.is_equal_approx(HIT_COLOR), "second Raider shows live hit feedback for the review capture")
	_check(raider.health <= 0 and raider_sprite.modulate.is_equal_approx(KNOCKED_OUT_COLOR), "first Raider shows KO feedback for the review capture")
	_check(raider_three.health > 0 and third_sprite.modulate.is_equal_approx(Color.WHITE), "third Raider remains available as the normal-state comparison")
	for _frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var feedback_image := root.get_texture().get_image()
	_check(feedback_image != null and not feedback_image.is_empty() and feedback_image.get_size() == CAPTURE_SIZE, "hit and KO review uses a real Window Viewport frame")
	if feedback_image != null and not feedback_image.is_empty() and feedback_image.get_size() == CAPTURE_SIZE:
		var feedback_save_error := feedback_image.save_png(ProjectSettings.globalize_path(FEEDBACK_CAPTURE_PATH))
		_check(feedback_save_error == OK, "hit and KO Window Viewport capture is saved")
		if feedback_save_error == OK:
			print("forest-raider-art-capture: saved real hit and KO Window Viewport frame to %s" % FEEDBACK_CAPTURE_PATH)
	game.queue_free()
	await process_frame
	_validate_saved_capture()
	_validate_saved_feedback_capture()
	_finish()

func _validate_saved_capture() -> void:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(CAPTURE_PATH))
	_check(error == OK, "saved Raider in-game capture PNG loads")
	if error == OK:
		_check(image.get_size() == CAPTURE_SIZE, "saved Raider in-game capture is 1920x1080")
		_check(_has_visible_variation(image), "saved Raider in-game capture contains visible rendered pixels")

func _validate_saved_feedback_capture() -> void:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(FEEDBACK_CAPTURE_PATH))
	_check(error == OK, "saved Raider hit and KO capture PNG loads")
	if error == OK:
		_check(image.get_size() == CAPTURE_SIZE, "saved Raider hit and KO capture is 1920x1080")
		_check(_has_visible_variation(image), "saved Raider hit and KO capture contains visible rendered pixels")

func _physics_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

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
		print("forest_raider_art_integration_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("forest_raider_art_integration_smoke: " + failure)
	push_error("forest_raider_art_integration_smoke: %d check(s) failed" % failures.size())
	quit(1)
