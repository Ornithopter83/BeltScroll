extends SceneTree
"""Captures consecutive, live Window Viewport frames for Num4 and Num5."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CAPTURE_SIZE := Vector2i(1280, 720)
const OUTPUT_DIRECTORY := "res://temp/player_skill_motion_capture"
const FRAME_LIMIT_PER_SKILL := 180

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_finish("A visible Window renderer is required for consecutive motion capture.")
		return
	root.size = CAPTURE_SIZE
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		_finish("Player scene could not be loaded.")
		return
	var player := packed.instantiate() as CharacterBody2D
	root.add_child(player)
	player.global_position = CAPTURE_SIZE * 0.5 + Vector2(0.0, 150.0)
	player.set("facing_direction", Vector2.RIGHT)
	player.get_node("VisualRoot").scale.x = 1.0
	var camera := player.get_node("Camera2D") as Camera2D
	camera.position = Vector2(0.0, -150.0)
	camera.zoom = Vector2.ONE
	camera.make_current()
	await process_frame
	var output_path := ProjectSettings.globalize_path(OUTPUT_DIRECTORY)
	var dir_error := DirAccess.make_dir_recursive_absolute(output_path)
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		_finish("Could not create capture directory: %s" % output_path)
		return
	var phase_samples: Dictionary = {}
	var active_representatives: Dictionary = {}
	var total_frames := 0
	for skill_id in [1, 2]:
		player.set("skill_cooldowns", [0.0, 0.0])
		player.call("_request_skill", skill_id)
		var frame_index := 0
		var prior_phase := ""
		while str(player.get("skill_phase")) != "idle" and frame_index < FRAME_LIMIT_PER_SKILL:
			await process_frame
			await RenderingServer.frame_post_draw
			var phase := str(player.get("skill_phase"))
			if phase != prior_phase:
				phase_samples["%d_%s" % [skill_id, phase]] = true
				prior_phase = phase
			var image := root.get_texture().get_image()
			if image == null or image.is_empty() or image.get_size() != CAPTURE_SIZE:
				failures.append("Num%d frame %d was not a valid Window Viewport image." % [skill_id + 3, frame_index])
				break
			if phase == "active" and not active_representatives.has(skill_id):
				active_representatives[skill_id] = image.duplicate()
			var image_path := "%s/num%d_%03d_%s.png" % [output_path, skill_id + 3, frame_index, phase]
			var save_error := image.save_png(image_path)
			if save_error != OK:
				failures.append("Could not save %s (error %d)." % [image_path, save_error])
			frame_index += 1
			total_frames += 1
		if frame_index >= FRAME_LIMIT_PER_SKILL:
			failures.append("Num%d skill did not finish within the capture frame limit." % (skill_id + 3))
		if player.get("skill_phase") != "idle":
			failures.append("Num%d remained active when its capture ended." % (skill_id + 3))
	for skill_id in [1, 2]:
		for phase in ["startup", "active", "recovery"]:
			if not phase_samples.has("%d_%s" % [skill_id, phase]):
				failures.append("Num%d consecutive capture missed its %s phase." % [skill_id + 3, phase])
	var silhouettes_differ := false
	if active_representatives.has(1) and active_representatives.has(2):
		silhouettes_differ = _images_differ(active_representatives[1], active_representatives[2])
	_check(silhouettes_differ, "Num4 dash and Num5 spin active silhouettes differ in captured Window frames.")
	if total_frames < 20:
		failures.append("Consecutive capture produced too few rendered frames (%d)." % total_frames)
	if failures.is_empty():
		print("player-skill-motion-capture: captured %d consecutive Window frames to %s" % [total_frames, output_path])
		print("player-skill-motion-capture: Num4 and Num5 active silhouettes differ")
		print("player-skill-motion-capture: all checks passed")
		player.queue_free()
		quit(0)
		return
	player.queue_free()
	for failure in failures:
		push_error("player_skill_motion_capture: " + failure)
	quit(1)

func _images_differ(first: Image, second: Image) -> bool:
	if first.get_size() != second.get_size():
		return false
	var changed_pixels := 0
	for y in range(first.get_height()):
		for x in range(first.get_width()):
			var first_pixel := first.get_pixel(x, y)
			var second_pixel := second.get_pixel(x, y)
			var color_delta := absf(first_pixel.r - second_pixel.r) + absf(first_pixel.g - second_pixel.g) + absf(first_pixel.b - second_pixel.b)
			if color_delta > 0.12:
				changed_pixels += 1
	return changed_pixels > 120

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _finish(reason: String) -> void:
	push_error("player_skill_motion_capture: " + reason)
	quit(1)
