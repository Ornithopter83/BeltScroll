extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const ART_PATH := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const CAPTURE_PATH := "res://assets/art/review/player_v8_ingame_capture.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const CAMERA_ZOOM := Vector2(1.2, 1.2)
const TARGET_SCREEN_HEIGHT := 192.0
const HIT_COLOR := Color(1.0, 0.42, 0.36, 1.0)
const KO_COLOR := Color(0.62, 0.62, 0.62, 0.78)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("player_art_integration_smoke requires a Window Viewport")
		quit(1)
		return
	root.size = CAPTURE_SIZE
	var packed_player := load(PLAYER_SCENE) as PackedScene
	var packed_game := load(MAIN_SCENE) as PackedScene
	_check(packed_player != null and packed_game != null, "Player and real gameplay scenes load")
	_check(ResourceLoader.exists(ART_PATH), "visually approved v8 clean candidate is available")
	if packed_player == null or packed_game == null:
		_finish()
		return

	var player_scene := packed_player.instantiate() as CharacterBody2D
	var sprite := player_scene.get_node_or_null("VisualRoot/PlayerArt") as Sprite2D
	_check(sprite != null and sprite.texture != null and sprite.texture.resource_path == ART_PATH, "PlayerArt Sprite2D uses the approved still image")
	_check(player_scene.get_node_or_null("VisualRoot/BodyStage1") == null and player_scene.get_node_or_null("VisualRoot/BodyStage2") == null and player_scene.get_node_or_null("VisualRoot/BodyStage3") == null and player_scene.get_node_or_null("VisualRoot/Face") == null, "temporary BodyStage1–3 and Face polygons are removed")
	_check(player_scene.get_node_or_null("GroundShadow") is Polygon2D and player_scene.get_node_or_null("VisualRoot/AttackFlash") is Polygon2D, "ground shadow and attack flash remain")
	_check(player_scene.get_node_or_null("CollisionShape2D") is CollisionShape2D and player_scene.get_node_or_null("Hitboxes/Hitbox1/CollisionShape2D") is CollisionShape2D and player_scene.get_node_or_null("Hitboxes/Hitbox2/CollisionShape2D") is CollisionShape2D and player_scene.get_node_or_null("Hitboxes/Hitbox3/CollisionShape2D") is CollisionShape2D, "body physics and all three combo hitboxes remain")
	_check(player_scene.get_node_or_null("Camera2D") is Camera2D and (player_scene.get_node("Camera2D") as Camera2D).zoom.is_equal_approx(CAMERA_ZOOM), "Player camera keeps zoom 1.2")
	var alpha_bounds := _alpha_bounds(sprite.texture) if sprite != null and sprite.texture != null else Rect2i()
	_check(alpha_bounds == Rect2i(110, 90, 1034, 1074), "integrated image keeps the approved 1254-square alpha bounds")
	if sprite != null and sprite.texture != null:
		var displayed_height := float(alpha_bounds.size.y) * sprite.scale.y * CAMERA_ZOOM.y
		_check(absf(displayed_height - TARGET_SCREEN_HEIGHT) <= 0.1, "alpha silhouette displays approximately 192 screen pixels at zoom 1.2")
		var alpha_bottom_local := sprite.position.y + (float(alpha_bounds.end.y) - float(sprite.texture.get_height()) * 0.5) * sprite.scale.y
		var floor_y: float = (player_scene.get_node("VisualRoot") as Node2D).position.y + alpha_bottom_local
		_check(absf(floor_y) <= 0.1, "sprite alpha foot bottom aligns to the Player physics floor")
		_check(absf(sprite.scale.x - sprite.scale.y) < 0.00001 and absf(sprite.scale.y - 160.0 / 1074.0) < 0.00001, "sprite scale preserves aspect ratio and targets 160 world pixels")
	_check(not FileAccess.get_file_as_string(PLAYER_SCENE).contains("SpriteFrames"), "integrated artwork is represented as a still image, not completed frame animation")
	player_scene.free()

	var game := packed_game.instantiate() as Node2D
	_check(game != null, "real gameplay scene instantiates for the Window Viewport capture")
	if game == null:
		_finish()
		return
	root.add_child(game)
	for _frame_index in range(3):
		await process_frame
	var player := game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	var actors := game.get_node_or_null("YSortActors") as Node2D
	var camera := game.get_node_or_null("YSortActors/Player/Camera2D") as Camera2D
	_check(player != null and actors != null and actors.y_sort_enabled and camera != null and camera.is_current(), "real gameplay Player uses YSort and its active camera")
	if player == null or camera == null:
		game.queue_free()
		_finish()
		return
	player.global_position = Vector2(960.0, 540.0)
	player.velocity = Vector2.ZERO
	await _physics_frames(2)
	Input.action_press("move_left")
	await _physics_frames(2)
	var player_root := player.get_node("VisualRoot") as Node2D
	_check(player_root.scale.x < 0.0, "leftward movement flips the Sprite2D with the existing visual root")
	Input.action_release("move_left")
	Input.action_press("move_right")
	await _physics_frames(2)
	_check(player_root.scale.x > 0.0, "rightward movement restores the Sprite2D facing direction")
	Input.action_release("move_right")
	player.velocity = Vector2.ZERO

	for _frame_index in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var viewport_image := root.get_texture().get_image()
	_check(viewport_image != null and not viewport_image.is_empty() and viewport_image.get_size() == CAPTURE_SIZE, "Window Viewport returns a real 1920x1080 gameplay frame")
	if viewport_image != null and not viewport_image.is_empty() and viewport_image.get_size() == CAPTURE_SIZE:
		_check(_has_visible_variation(viewport_image), "rendered gameplay capture contains visible scene content")
		var save_error := viewport_image.save_png(ProjectSettings.globalize_path(CAPTURE_PATH))
		_check(save_error == OK, "actual Window Viewport capture is saved")
		if save_error == OK:
			print("player-art-capture: saved real 1920x1080 Window Viewport frame to %s" % CAPTURE_PATH)

	Input.action_press("sit")
	await _physics_frames(2)
	var visual_root := player.get_node("VisualRoot") as Node2D
	sprite = player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var sit_floor_y: float = visual_root.position.y + sprite.position.y * visual_root.scale.y + (float(alpha_bounds.end.y) - float(sprite.texture.get_height()) * 0.5) * sprite.scale.y * visual_root.scale.y
	var sit_height: float = float(alpha_bounds.size.y) * sprite.scale.y * visual_root.scale.y * CAMERA_ZOOM.y
	_check(player.is_sitting and is_equal_approx(visual_root.scale.y, 0.78), "sit input keeps the existing crouch pose on the Sprite2D")
	_check(absf(sit_floor_y) <= 1.0 and sit_height >= TARGET_SCREEN_HEIGHT * 0.70 and sit_height <= TARGET_SCREEN_HEIGHT * 0.80, "sitting artwork stays floor-anchored and remains legible through the crouch pose")
	Input.action_release("sit")
	await _physics_frames(1)
	var shadow_floor_y := (player.get_node("GroundShadow") as Polygon2D).global_position.y
	player._start_jump()
	await _physics_frames(2)
	_check(player.is_jumping and player.jump_height_offset > 0.0, "jump state moves the integrated still artwork through the existing jump path")
	_check(absf(player.jump_height_offset) > 1.0 and sprite.visible and is_equal_approx((player.get_node("GroundShadow") as Polygon2D).global_position.y, shadow_floor_y), "jumped PlayerArt stays visible while its ground shadow remains on the floor")
	player.is_jumping = false
	player.jump_height_offset = 0.0
	player.jump_vertical_velocity = 0.0
	visual_root.position.y = -18.0
	player._begin_attack(1)
	var stage_one_flash := player.get_node("VisualRoot/AttackFlash") as Polygon2D
	var stage_one_scale := stage_one_flash.scale
	_check(player.attack_stage == 1 and stage_one_flash.visible and sprite.visible, "first combo stage keeps the still artwork visible with its attack cue")
	player._begin_attack(2)
	var stage_two_scale := stage_one_flash.scale
	player._begin_attack(3)
	_check(player.attack_stage == 3 and stage_one_flash.visible and stage_two_scale.x > stage_one_scale.x and stage_one_flash.scale.x > stage_two_scale.x, "second and third combo stages remain distinguishable through the existing expanding cue")
	player._set_attack_stage_visual(0)

	player.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.1, "attack_stage": 1})
	var player_sprite := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	await physics_frame
	_check(player_sprite.modulate.is_equal_approx(HIT_COLOR), "nonlethal hit flashes the integrated Sprite2D through modulate")
	for _frame_index in range(12):
		await physics_frame
	_check(player_sprite.modulate.is_equal_approx(Color.WHITE), "Player sprite returns to normal after hit flash")
	player.receive_hit({"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	_check(player.is_ko, "lethal hit enters KO")
	for _frame_index in range(12):
		await physics_frame
	_check(player_sprite.modulate.is_equal_approx(KO_COLOR), "KO feedback tint remains on the integrated Sprite2D")
	game.queue_free()
	await process_frame
	_validate_capture()
	_finish()

func _alpha_bounds(texture: Texture2D) -> Rect2i:
	var image := texture.get_image()
	return image.get_used_rect()

func _physics_frames(count: int) -> void:
	for _frame_index in range(count):
		await physics_frame

func _has_visible_variation(image: Image) -> bool:
	var first_color := image.get_pixel(0, 0)
	var varied := 0
	for y in range(40, image.get_height(), 80):
		for x in range(40, image.get_width(), 80):
			var difference := image.get_pixel(x, y) - first_color
			if difference.r * difference.r + difference.g * difference.g + difference.b * difference.b > 0.0025:
				varied += 1
	return varied >= 12

func _validate_capture() -> void:
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(CAPTURE_PATH))
	_check(error == OK, "saved Player in-game capture PNG loads")
	if error == OK:
		_check(image.get_size() == CAPTURE_SIZE, "saved Player capture is 1920x1080")
		_check(_has_visible_variation(image), "saved Player capture contains rendered gameplay pixels")

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("player_art_integration_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("player_art_integration_smoke: " + failure)
	push_error("player_art_integration_smoke: %d check(s) failed" % failures.size())
	quit(1)
