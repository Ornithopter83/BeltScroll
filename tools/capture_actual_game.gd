extends SceneTree
"""Captures a rendered frame of the real gameplay scene for visual review."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const DEFAULT_OUTPUT := "res://assets/art/review/actual_gameplay_capture.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const COMBAT_IMPACT_SCENE := preload("res://scenes/vfx/combat_impact.tscn")

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("A windowed renderer is required; the active display server is headless.")
		return

	var arguments := OS.get_cmdline_user_args()
	if arguments.size() > 1:
		_fail("Usage: actual-game-capture [output.png]")
		return
	var output_path := DEFAULT_OUTPUT
	if not arguments.is_empty():
		output_path = arguments[0]
		if output_path.begins_with("-"):
			_fail("Usage: actual-game-capture [output.png]; output paths cannot be command-line options.")
			return

	root.size = CAPTURE_SIZE
	var packed_scene := load(MAIN_SCENE) as PackedScene
	if packed_scene == null:
		_fail("Could not load the real gameplay scene: %s" % MAIN_SCENE)
		return
	var game := packed_scene.instantiate() as Node2D
	if game == null:
		_fail("The gameplay scene did not instantiate as Node2D.")
		return
	root.add_child(game)
	await process_frame

	var player := game.get_node_or_null("YSortActors/Player") as Node2D
	var raider := game.get_node_or_null("YSortActors/ForestRaider1") as Node2D
	var actors := game.get_node_or_null("YSortActors") as Node2D
	var stage := game.get_node_or_null("StageBackground") as Sprite2D
	var camera := game.get_node_or_null("YSortActors/Player/Camera2D") as Camera2D
	var hud := game.get_node_or_null("CombatHUD")
	if player == null or raider == null or actors == null or stage == null or camera == null or hud == null:
		_fail("Gameplay scene is missing its Forest Ruins background, YSort actors, player, raider, camera, or HUD.")
		return
	if not actors.y_sort_enabled or stage.texture == null or not camera.enabled or not camera.is_current():
		_fail("Gameplay scene background, YSort, or active Player camera is not ready for capture.")
		return
	# Render the state immediately after the first progress trigger. The remaining
	# Raiders stay hidden until their own later triggers, matching the real wave flow.
	player.global_position.x = maxf(player.global_position.x, 1040.0)
	game.call("_update_raider_waves")
	hud.call("refresh")

	# Add a real world-space impact node so the capture reliably includes combat VFX.
	var impact := COMBAT_IMPACT_SCENE.instantiate() as Node2D
	if impact == null:
		_fail("Could not instantiate the combat impact scene.")
		return
	raider.add_child(impact)
	impact.global_position = raider.global_position + Vector2(0.0, -20.0)
	impact.configure(3, Vector2.RIGHT)
	# Keep the real animated impact alive long enough for a deterministic review frame.
	impact.lifetime = 5.0
	impact._start_ticks_usec = Time.get_ticks_usec()

	# Wait for several completed draw frames before reading the Window Viewport texture.
	for _frame_index in range(4):
		await process_frame
		await RenderingServer.frame_post_draw

	var viewport_image := root.get_texture().get_image()
	if viewport_image == null or viewport_image.is_empty():
		_fail("The Window Viewport returned an empty image; no rendered frame is available.")
		return
	if viewport_image.get_size() != CAPTURE_SIZE:
		_fail("Rendered viewport size is %s; expected %s." % [viewport_image.get_size(), CAPTURE_SIZE])
		return
	if not _has_rendered_content(viewport_image):
		_fail("The rendered frame is blank or has no visible scene variation.")
		return

	var absolute_output := ProjectSettings.globalize_path(output_path)
	var save_error := viewport_image.save_png(absolute_output)
	if save_error != OK:
		_fail("Could not save rendered capture to '%s' (error %d)." % [absolute_output, save_error])
		return
	print("actual-game-capture: saved real %dx%d Window Viewport frame to %s" % [CAPTURE_SIZE.x, CAPTURE_SIZE.y, absolute_output])
	quit(0)

func _has_rendered_content(image: Image) -> bool:
	var first_color := image.get_pixel(0, 0)
	var varied_samples := 0
	for y in range(40, CAPTURE_SIZE.y, 80):
		for x in range(40, CAPTURE_SIZE.x, 80):
			if _color_distance_squared(image.get_pixel(x, y), first_color) > 0.0025:
				varied_samples += 1
	return varied_samples >= 12

func _color_distance_squared(left: Color, right: Color) -> float:
	var difference := left - right
	return difference.r * difference.r + difference.g * difference.g + difference.b * difference.b

func _fail(message: String) -> void:
	push_error("actual-game-capture: " + message)
	quit(1)
