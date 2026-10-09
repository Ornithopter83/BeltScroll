extends SceneTree
"""Captures procedural player turns from the visible fullscreen Window."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const OUTPUT_PATH := "res://assets/art/review/player_turn_motion_strip.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const TILE_SIZE := Vector2i(1024, 900)
const TILE_COUNT := 10
const CAPTIONS := [
	"Idle / right", "Idle / windup", "Idle / compress", "Idle / settle", "Idle / left",
	"Move / right", "Move / windup", "Move / compress", "Move / settle", "Rapid reverse",
]

var failures: Array[String] = []
var _capture_crop_rect := Rect2i()

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_finish("A visible Window is required for turn-motion capture.")
		return
	root.size = CAPTURE_SIZE
	root.mode = Window.MODE_FULLSCREEN
	await create_timer(0.25).timeout
	var viewport_size := Vector2(root.size)
	var scene := Node2D.new()
	scene.name = "PlayerTurnCapture"
	root.add_child(scene)
	var background := ColorRect.new()
	background.color = Color("#171b25")
	background.size = viewport_size
	background.z_index = -10
	scene.add_child(background)
	var floor_line := ColorRect.new()
	floor_line.color = Color("#67717e")
	floor_line.position = Vector2(viewport_size.x * 0.5 - 350.0, viewport_size.y * 0.5 + 200.0)
	floor_line.size = Vector2(700.0, 3.0)
	scene.add_child(floor_line)
	var caption := Label.new()
	caption.position = Vector2(viewport_size.x * 0.5 - 320.0, viewport_size.y * 0.5 - 310.0)
	caption.size = Vector2(640.0, 64.0)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size", 30)
	caption.add_theme_color_override("font_color", Color("#e8edf4"))
	scene.add_child(caption)
	var status := Label.new()
	status.position = Vector2(viewport_size.x * 0.5 - 360.0, viewport_size.y - 65.0)
	status.size = Vector2(720.0, 50.0)
	status.text = "Procedural transforms only — dedicated turn artwork unavailable"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.add_theme_font_size_override("font_size", 20)
	status.add_theme_color_override("font_color", Color("#bdc8d8"))
	scene.add_child(status)
	var camera := Camera2D.new()
	camera.position = viewport_size * 0.5
	scene.add_child(camera)
	camera.make_current()
	var player := (load(PLAYER_SCENE) as PackedScene).instantiate() as CharacterBody2D
	scene.add_child(player)
	player.position = viewport_size * 0.5 + Vector2(0.0, 200.0)
	player.set_physics_process(false)
	(player.get_node("Camera2D") as Camera2D).queue_free()
	var animator: Node = player.get_node("VisualAnimator")
	await process_frame
	animator.set_process(false)
	var samples: Array[Image] = []
	var capture_size := Vector2i(root.size)
	for index in range(TILE_COUNT):
		_prepare_sample(index, player, animator, caption)
		await RenderingServer.frame_post_draw
		var window_frame := root.get_texture().get_image()
		if window_frame == null or window_frame.is_empty():
			failures.append("Window renderer frame capture failed at sample %d." % index)
			continue
		var visual_bounds := _find_player_frame_bounds(window_frame)
		if index == 0:
			var crop_position := Vector2i(roundi(visual_bounds.get_center().x - float(TILE_SIZE.x) * 0.5), roundi(visual_bounds.get_center().y - float(TILE_SIZE.y) * 0.5))
			_capture_crop_rect = Rect2i(crop_position, TILE_SIZE)
		if window_frame.get_size() != capture_size or _capture_crop_rect.position.x < 0 or _capture_crop_rect.position.y < 0 or _capture_crop_rect.end.x > capture_size.x or _capture_crop_rect.end.y > capture_size.y:
			failures.append("Window frame or sample crop was clipped at sample %d (frame=%s, crop=%s)." % [index, str(window_frame.get_size()), str(_capture_crop_rect)])
			continue
		var tile := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, window_frame.get_format())
		tile.blit_rect(window_frame, _capture_crop_rect, Vector2i.ZERO)
		samples.append(tile)
		if not _capture_bounds_fit(visual_bounds):
			failures.append("Player alpha bounds approach the capture tile edge at sample %d (bounds=%s crop=%s)." % [index, str(visual_bounds), str(_capture_crop_rect)])
		if not _foot_anchor_stable(player):
			failures.append("Player alpha foot anchor drifted at sample %d." % index)
	if samples.size() == TILE_COUNT:
		var strip := Image.create(TILE_SIZE.x * 5, TILE_SIZE.y * 2, false, Image.FORMAT_RGBA8)
		strip.fill(Color("#171b25"))
		for index in range(TILE_COUNT):
			strip.blit_rect(samples[index], Rect2i(Vector2i.ZERO, TILE_SIZE), Vector2i((index % 5) * TILE_SIZE.x, (index / 5) * TILE_SIZE.y))
		var output := ProjectSettings.globalize_path(OUTPUT_PATH)
		var error := strip.save_png(output)
		if error != OK:
			failures.append("Could not save turn-motion strip (error %d)." % error)
	if failures.is_empty():
		print("player-turn-motion-capture: saved %s from fullscreen Window frames" % OUTPUT_PATH)
		print("player-turn-motion-capture: all samples fit and retained the alpha foot anchor")
		await create_timer(5.0).timeout
		player.queue_free()
		quit(0)
		return
	player.queue_free()
	for failure in failures:
		push_error("player_turn_motion_capture: " + failure)
	quit(1)

func _prepare_sample(index: int, player: CharacterBody2D, animator: Node, caption: Label) -> void:
	caption.text = CAPTIONS[index]
	if index >= 6:
		player.position.x -= 10.0
	var target := Vector2.RIGHT if index in [0, 5] else Vector2.LEFT
	if index == 5:
		player.velocity = Vector2(180.0, 0.0)
	elif index >= 6:
		player.velocity = Vector2(-180.0, 0.0)
	else:
		player.velocity = Vector2.ZERO
	if index in [1, 6]:
		target = Vector2.LEFT
		player.set("facing_direction", target)
		_reset_turn(player, animator, 0.025)
	elif index in [2, 7]:
		player.set("facing_direction", Vector2.LEFT)
		_reset_turn(player, animator, 0.055)
	elif index in [3, 8]:
		player.set("facing_direction", Vector2.LEFT)
		_reset_turn(player, animator, 0.090)
	elif index == 4:
		player.set("facing_direction", Vector2.LEFT)
		_reset_turn(player, animator, 0.145)
	elif index == 9:
		player.set("facing_direction", Vector2.LEFT)
		_reset_turn(player, animator, 0.030)
		player.set("facing_direction", Vector2.RIGHT)
		animator.call("_process", 0.030)
		player.set("facing_direction", Vector2.LEFT)
		animator.call("_process", 0.080)
	else:
		player.set("facing_direction", target)
		var root_node := player.get_node("VisualRoot") as Node2D
		root_node.scale.x = 1.0 if target.x > 0.0 else -1.0
		if index == 5:
			animator.set("_applied_facing_sign", 1.0)
			animator.set("_turn_target_sign", 1.0)
			animator.set("_turn_elapsed", 0.13)
		animator.call("_process", 1.0 / 60.0)
	await process_frame
	await RenderingServer.frame_post_draw

func _reset_turn(player: CharacterBody2D, animator: Node, elapsed: float) -> void:
	var root_node := player.get_node("VisualRoot") as Node2D
	animator.set("_applied_facing_sign", 1.0)
	animator.set("_turn_target_sign", 1.0)
	animator.set("_turn_elapsed", 0.13)
	animator.set("_turn_flip_applied", false)
	root_node.scale.x = 1.0
	animator.call("_process", elapsed)

func _capture_bounds_fit(bounds: Rect2) -> bool:
	return bounds.position.x >= float(_capture_crop_rect.position.x + 8) and bounds.position.y >= float(_capture_crop_rect.position.y + 8) \
		and bounds.end.x <= float(_capture_crop_rect.end.x - 8) and bounds.end.y <= float(_capture_crop_rect.end.y - 8)

func _find_player_frame_bounds(frame: Image) -> Rect2:
	var background := Color("#171b25")
	var left := frame.get_width()
	var top := frame.get_height()
	var right := 0
	var bottom := 0
	var x_min := maxi(0, int(frame.get_width() * 0.25))
	var x_max := mini(frame.get_width(), int(frame.get_width() * 0.75))
	var y_min := int(frame.get_height() * 0.16)
	var y_max := int(frame.get_height() * 0.82)
	for y in range(y_min, y_max, 2):
		for x in range(x_min, x_max, 2):
			var pixel := frame.get_pixel(x, y)
			var color_delta := absf(pixel.r - background.r) + absf(pixel.g - background.g) + absf(pixel.b - background.b)
			var saturation := maxf(pixel.r, maxf(pixel.g, pixel.b)) - minf(pixel.r, minf(pixel.g, pixel.b))
			if color_delta > 0.18 and saturation > 0.06:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2(Vector2(left, top), Vector2(right - left + 1, bottom - top + 1))

func _foot_anchor_stable(player: CharacterBody2D) -> bool:
	var sprite := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var bounds := sprite.texture.get_image().get_used_rect()
	var size := Vector2(sprite.texture.get_size())
	var local_foot := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y)) - size * 0.5
	local_foot *= sprite.scale
	var foot := sprite.position + local_foot.rotated(sprite.rotation)
	var animator: Node = player.get_node("VisualAnimator")
	var anchor: Vector2 = animator.get("_foot_anchor")
	return foot.distance_to(anchor) <= 0.08

func _finish(reason: String) -> void:
	push_error("player_turn_motion_capture: " + reason)
	quit(1)
