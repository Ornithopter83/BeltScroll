extends SceneTree
"""Captures the skill HUD from the live 1920×1080 Window Viewport."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/combat_skill_hud_window.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("combat-skill-hud-capture: an actual Window renderer is required")
		quit(1)
		return
	root.size = CAPTURE_SIZE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		push_error("combat-skill-hud-capture: could not load the main combat scene")
		quit(1)
		return
	var game := packed.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	await process_frame
	var player := game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	var hud := game.get_node_or_null("CombatHUD")
	if player == null or hud == null:
		push_error("combat-skill-hud-capture: live Player or combat HUD is missing")
		quit(1)
		return
	# Use live Player skill fields to compose an illustrative active/cooldown frame.
	# No combat timing constants or runtime gameplay paths are changed.
	player.set_physics_process(false)
	player.set("skill_id", 1)
	player.set("skill_phase", "active")
	player.set("skill_phase_remaining", 0.08)
	var cooldowns: Array = player.get("skill_cooldowns")
	cooldowns[0] = 1.0
	cooldowns[1] = 0.72
	player.set("skill_cooldowns", cooldowns)
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.zoom = Vector2(1.04, 1.04)
		camera.global_position += Vector2(24.0, -8.0)
	hud.call("refresh")
	await process_frame
	await RenderingServer.frame_post_draw
	var window_image := root.get_texture().get_image()
	if window_image == null or window_image.is_empty():
		push_error("combat-skill-hud-capture: Window Viewport frame was empty or not 1920×1080")
		quit(1)
		return
	if window_image.get_size() != CAPTURE_SIZE:
		var source_size := window_image.get_size()
		if not is_equal_approx(float(source_size.x) / float(source_size.y), float(CAPTURE_SIZE.x) / float(CAPTURE_SIZE.y)):
			push_error("combat-skill-hud-capture: fullscreen Window aspect ratio is %s, expected 16:9" % source_size)
			quit(1)
			return
		window_image.resize(CAPTURE_SIZE.x, CAPTURE_SIZE.y, Image.INTERPOLATE_LANCZOS)
		print("combat-skill-hud-capture: normalized fullscreen Window frame %s to 1920×1080" % source_size)
	var path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var error := window_image.save_png(path)
	if error != OK:
		push_error("combat-skill-hud-capture: could not save Window capture (error %d)" % error)
		quit(1)
		return
	print("combat-skill-hud-capture: saved actual 1920×1080 Window Viewport to %s" % path)
	quit(0)
