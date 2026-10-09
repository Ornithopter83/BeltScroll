extends SceneTree
"""Captures and checks Raider health indicators from a rendered Window Viewport."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://temp/raider_healthbars_window.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)
const HIT := {"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("A real Window renderer is required for Raider health bar capture.")
		return
	root.size = EXPECTED_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("Could not load the combat scene.")
		return
	var game := packed.instantiate() as Node2D
	root.add_child(game)
	await process_frame
	var player := game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	var camera := game.get_node_or_null("YSortActors/Player/Camera2D") as Camera2D
	var hud := game.get_node_or_null("CombatHUD")
	var raiders := get_nodes_in_group("forest_raiders")
	if player == null or camera == null or hud == null or raiders.size() != 3:
		game.queue_free()
		_fail("Combat scene does not contain the expected camera, HUD, and Raiders.")
		return
	player.set_physics_process(false)
	for raider in raiders:
		raider.set_physics_process(false)
		# Place each real Raider at a distinct, fully visible location.
	raiders[0].global_position = Vector2(540.0, 460.0)
	raiders[1].global_position = Vector2(960.0, 760.0)
	raiders[2].global_position = Vector2(1380.0, 460.0)
	camera.global_position = Vector2(960.0, 540.0)
	camera.zoom = Vector2.ONE
	camera.rotation = 0.0
	camera.make_current()
	hud.refresh()
	await _draw_frame()
	var initial := root.get_texture().get_image()
	if not _valid_frame(initial):
		game.queue_free()
		_fail("Initial rendered Window frame is invalid.")
		return
	var indicator_map: Dictionary = hud.get("_raider_indicators")
	var target: Node2D = raiders[1]
	var indicator: Dictionary = indicator_map[target.get_instance_id()]
	if not _indicator_tracks_head(target, indicator, camera):
		game.queue_free()
		_fail("Rendered health indicator does not track the transformed alpha head position.")
		return
	if _indicator_overlaps_player(indicator, player):
		game.queue_free()
		_fail("Rendered health indicator overlaps the Player alpha silhouette instead of sliding clear.")
		return
	var art := target.get_node("VisualRoot/RaiderArt") as Sprite2D
	var original_texture := art.texture
	var changed_image := original_texture.get_image()
	var old_bounds := changed_image.get_used_rect()
	for x in range(old_bounds.position.x, old_bounds.end.x):
		var pixel := changed_image.get_pixel(x, old_bounds.position.y)
		pixel.a = 0.0
		changed_image.set_pixel(x, old_bounds.position.y, pixel)
	art.texture = ImageTexture.create_from_image(changed_image)
	hud.refresh()
	var changed_bounds: Rect2i = indicator["alpha_bounds"]
	if changed_bounds == old_bounds or not _indicator_tracks_head(target, indicator, camera):
		game.queue_free()
		_fail("Health indicator did not recalculate after the Raider alpha silhouette changed.")
		return
	art.texture = original_texture
	hud.refresh()
	var rotation_before: Vector2 = indicator["root"].position
	camera.rotation = 0.10
	camera.zoom = Vector2(1.15, 1.15)
	target.get_node("VisualRoot").scale.x *= -1.0
	await process_frame
	hud.refresh()
	await _draw_frame()
	var transformed_head_matches := _indicator_tracks_head(target, indicator, camera)
	if indicator["root"].position.is_equal_approx(rotation_before) or not transformed_head_matches:
		game.queue_free()
		_fail("Health indicator did not follow camera zoom/rotation and Raider mirroring.")
		return
	camera.rotation = 0.0
	camera.zoom = Vector2.ONE
	target.get_node("VisualRoot").scale.x *= -1.0
	target.receive_hit(HIT)
	hud.refresh()
	await _draw_frame()
	var damage_frame := root.get_texture().get_image()
	if not _valid_frame(damage_frame) or not _has_bar_pixels(damage_frame):
		game.queue_free()
		_fail("Damage state did not render Raider health bar pixels in the Window.")
		return
	# Partial recovery must clear/shorten the red tail immediately and keep the
	# live indicator visible; the corresponding state is also checked in smoke.
	target.set("health", 2)
	hud.refresh()
	await _draw_frame()
	if not indicator["root"].visible or indicator["label"].text != "2 / 3":
		game.queue_free()
		_fail("Partial Raider recovery did not remain visible in the captured scene.")
		return
	var output_file := ProjectSettings.globalize_path(OUTPUT_PATH)
	var save_error := damage_frame.save_png(output_file)
	target.receive_hit({"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	hud.refresh()
	await _draw_frame()
	if indicator["root"].visible:
		game.queue_free()
		_fail("KO Raider indicator remained visible.")
		return
	# Move a live Raider outside the camera. It must disappear rather than stick
	# to an unrelated viewport edge.
	raiders[2].global_position = Vector2(-3000.0, -3000.0)
	hud.refresh()
	if indicator_map[raiders[2].get_instance_id()]["root"].visible:
		game.queue_free()
		_fail("Off-screen Raider health indicator was not hidden.")
		return
	game.queue_free()
	if save_error != OK:
		_fail("Could not save Window capture (Image.save_png error %d)." % save_error)
		return
	print("raider-healthbar-window-capture: saved rendered Window frame to %s" % output_file)
	print("raider-healthbar-window-capture: checked alpha bounds, transforms, damage, partial recovery, KO, and off-screen hiding")
	print("raider-healthbar-window-capture: all checks passed")
	quit(0)

func _indicator_tracks_head(raider: Node2D, indicator: Dictionary, camera: Camera2D) -> bool:
	var art := raider.get_node("VisualRoot/RaiderArt") as Sprite2D
	var bounds := art.texture.get_image().get_used_rect()
	var local_head := Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.position.y) - Vector2(art.texture.get_size()) * 0.5
	var screen_head: Vector2 = art.get_global_transform_with_canvas() * local_head
	var root_control: Control = indicator["root"]
	var expected := Vector2(screen_head.x - root_control.size.x * 0.5, screen_head.y - root_control.size.y - 12.0)
	return root_control.visible and absf(root_control.position.y - expected.y) < 1.0 and absf(root_control.position.x - expected.x) <= 168.0

func _indicator_overlaps_player(indicator: Dictionary, player: Node2D) -> bool:
	var indicator_rect := Rect2(indicator["root"].position, indicator["root"].size)
	for sprite in player.find_children("*", "Sprite2D", true, false):
		var art := sprite as Sprite2D
		if art == null or not art.is_visible_in_tree() or art.texture == null:
			continue
		var alpha := art.texture.get_image().get_used_rect()
		if alpha.size == Vector2i.ZERO:
			continue
		var half_size := Vector2(art.texture.get_size()) * 0.5
		var local := Rect2(Vector2(alpha.position) - half_size, Vector2(alpha.size))
		var transform := art.get_global_transform_with_canvas()
		var points: Array[Vector2] = [transform * local.position, transform * Vector2(local.end.x, local.position.y), transform * local.end, transform * Vector2(local.position.x, local.end.y)]
		var bounds := Rect2(points[0], Vector2.ZERO)
		for point in points.slice(1):
			bounds = bounds.expand(point)
		if indicator_rect.intersects(bounds):
			return true
	return false

func _draw_frame() -> void:
	await process_frame
	await RenderingServer.frame_post_draw

func _valid_frame(image: Image) -> bool:
	return image != null and not image.is_empty() and image.get_size() == EXPECTED_SIZE

func _has_bar_pixels(image: Image) -> bool:
	var matches := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.g > 0.32 and pixel.g > pixel.r * 1.18 and pixel.g > pixel.b * 1.05:
				matches += 1
	return matches >= 40

func _fail(message: String) -> void:
	push_error("raider-healthbar-window-capture: " + message)
	quit(1)
