extends SceneTree
"""Capture the isolated Num4 safe candidate beside live Player skill motion."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SAFE_CANDIDATE := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/review/player_skill1_contact_motion_strip.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const CAPTURE_SIZE := Vector2i(1920, 1080)
const FLOOR_Y := 850.0
const LANE_X := [350.0, 960.0, 1570.0]
const POSES := [
	{"phase": "startup", "progress": 0.55},
	{"phase": "active", "progress": 0.08},
	{"phase": "active", "progress": 0.55},
	{"phase": "recovery", "progress": 0.55},
]
const CAPTURE_COUNT := 10 # Four Num4 samples for each facing plus one Num5 active reference per facing.

var _frames: Array[Image] = []
var _records: Array[Dictionary] = []
var _errors: Array[String] = []
var _player_scene: PackedScene
var _candidate_image: Image
var _candidate_texture: ImageTexture
var _candidate_bounds := Rect2i()
var _stage: Node2D
var _overlay: CaptureOverlay
var _active_players: Array[CharacterBody2D] = []
var _receiver_hit := false

class CaptureReceiver:
	extends StaticBody2D
	signal hit_landed
	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group("hit_receivers")
		var shape_node := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 10.0
		shape_node.shape = shape
		add_child(shape_node)
	func receive_hit(_hit: Dictionary) -> void:
		hit_landed.emit()

class CaptureOverlay:
	extends Node2D
	var title := ""
	var phase := ""
	var facing := "right"
	var distance := 0.0
	var hitbox := false
	var clock := ""
	var num5_phase := ""
	var hit_landed := false

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(56, 66), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color("#ffe2a8"))
		draw_string(font, Vector2(115, 133), "LIVE PLAYER", HORIZONTAL_ALIGNMENT_CENTER, 470, 23, Color("#ffffff"))
		draw_string(font, Vector2(725, 133), "SAFE CANDIDATE · ISOLATED", HORIZONTAL_ALIGNMENT_CENTER, 470, 23, Color("#8de5d2"))
		draw_string(font, Vector2(1340, 133), "NUM5 ROTATIONAL SKILL", HORIZONTAL_ALIGNMENT_CENTER, 470, 23, Color("#dda9ff"))
		draw_string(font, Vector2(60, 918), clock, HORIZONTAL_ALIGNMENT_LEFT, 570, 21, Color("#ffffff"))
		draw_string(font, Vector2(60, 951), "forward travel  %.1f px  ·  hitbox %s" % [distance, "ON" if hitbox else "OFF"], HORIZONTAL_ALIGNMENT_LEFT, 570, 19, Color("#9bd4ff"))
		draw_string(font, Vector2(60, 980), "impact pop %s" % ("YES" if hit_landed else "no hit"), HORIZONTAL_ALIGNMENT_LEFT, 570, 18, Color("#ffd27a"))
		draw_string(font, Vector2(710, 918), "base alpha 192 px  ·  ground aligned  ·  %s-facing" % facing, HORIZONTAL_ALIGNMENT_LEFT, 570, 18, Color("#baf5e6"))
		draw_string(font, Vector2(1325, 918), "phase %s  ·  shared 192 px base scale" % num5_phase, HORIZONTAL_ALIGNMENT_LEFT, 570, 18, Color("#e8ccff"))

class CaptureBackdrop:
	extends Node2D
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), Color("#172128"))
		draw_rect(Rect2(Vector2(60, FLOOR_Y + 1), Vector2(1800, 3)), Color("#c98264"))

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_finish("This capture requires a visible 1920x1080 Window renderer.")
		return
	root.size = WINDOW_SIZE
	_player_scene = load(PLAYER_SCENE) as PackedScene
	_candidate_image = Image.new()
	if _player_scene == null or _candidate_image.load(ProjectSettings.globalize_path(SAFE_CANDIDATE)) != OK:
		_finish("Player scene or isolated safe candidate could not be loaded.")
		return
	_candidate_bounds = _alpha_bounds(_candidate_image, 0.05)
	if _candidate_bounds.size.y <= 0:
		_finish("Safe candidate has no visible alpha silhouette.")
		return
	_candidate_texture = ImageTexture.create_from_image(_candidate_image)
	var make_error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://assets/art/review"))
	if make_error != OK and make_error != ERR_ALREADY_EXISTS:
		_finish("Could not create review output directory (error %d)." % make_error)
		return
	for facing_right in [true, false]:
		for pose in POSES:
			await _capture_num4(facing_right, str(pose.phase), float(pose.progress))
		await _capture_num5_active(facing_right)
	if not _errors.is_empty():
		for message in _errors:
			push_error("skill1_contact_motion: " + message)
		quit(1)
		return
	var image_error := _save_contact_sheet()
	if image_error != OK:
		_finish("Could not save review strip (error %d)." % image_error)
		return
	print("player_skill1_contact_motion: captured %d actual Window frames; artifact=%s" % [_frames.size(), OUTPUT])
	quit(0)

func _capture_num4(facing_right: bool, target_phase: String, progress: float) -> void:
	await _reset_stage(facing_right, 4, target_phase, progress)
	var player := _active_players[0]
	var timeout := 0
	while timeout < 120:
		await physics_frame
		await RenderingServer.frame_post_draw
		var phase := str(player.get("skill_phase"))
		if phase == target_phase and _phase_progress(player) >= progress:
			if target_phase == "active" and not bool(player.get_node("Hitboxes/Skill1Hitbox").monitoring):
				_errors.append("Num4 active capture did not coincide with enabled Skill1Hitbox.")
			break
		if phase == "idle" and timeout > 1:
			_errors.append("Num4 returned to idle before %s %.2f could be captured." % [target_phase, progress])
			break
		timeout += 1
	if timeout >= 120:
		_errors.append("Timed out waiting for Num4 %s." % target_phase)
	await _capture_frame({"title": "NUM4 PROCEDURAL  ·  %s  ·  %s" % [target_phase.to_upper(), "RIGHT" if facing_right else "LEFT"], "phase": target_phase, "facing": "right" if facing_right else "left", "num4": true, "progress": progress, "distance": player.global_position.x - float(player.get_meta("capture_start_x")), "hitbox": bool(player.get_node("Hitboxes/Skill1Hitbox").monitoring), "clock": _clock_label(player)})
	await _cleanup_stage()

func _capture_num5_active(facing_right: bool) -> void:
	await _reset_stage(facing_right, 5, "active", 0.50)
	var player := _active_players[0]
	var timeout := 0
	while timeout < 120 and str(player.get("skill_phase")) != "active":
		await physics_frame
		timeout += 1
	if timeout >= 120:
		_errors.append("Timed out waiting for Num5 active reference.")
	else:
		await RenderingServer.frame_post_draw
		await _capture_frame({"title": "NUM5 ROTATION REFERENCE  ·  ACTIVE  ·  %s" % ("RIGHT" if facing_right else "LEFT"), "phase": "active", "facing": "right" if facing_right else "left", "num4": false, "progress": _phase_progress(player), "distance": player.global_position.x - float(player.get_meta("capture_start_x")), "hitbox": bool(player.get_node("Hitboxes/Skill2Hitbox").monitoring), "clock": _clock_label(player)})
	await _cleanup_stage()

func _reset_stage(facing_right: bool, skill_id: int, target_phase: String, target_progress: float) -> void:
	await _cleanup_stage()
	_stage = Node2D.new()
	_stage.name = "IsolatedSkillContactCapture"
	root.add_child(_stage)
	_stage.add_child(_build_backdrop())
	var candidate := Sprite2D.new()
	candidate.name = "IsolatedSafeCandidatePreview"
	candidate.texture = _candidate_texture
	var candidate_scale := 192.0 / float(_candidate_bounds.size.y)
	candidate.scale = Vector2.ONE * candidate_scale
	candidate.flip_h = not facing_right
	var candidate_foot_x := float(_candidate_bounds.position.x) + float(_candidate_bounds.size.x) * 0.5
	var candidate_foot_y := float(_candidate_bounds.end.y - 1)
	var candidate_local_foot := (Vector2(candidate_foot_x, candidate_foot_y) - Vector2(_candidate_image.get_size()) * 0.5) * candidate_scale
	if not facing_right: candidate_local_foot.x = -candidate_local_foot.x
	candidate.position = Vector2(LANE_X[1], FLOOR_Y) - candidate_local_foot
	_stage.add_child(candidate)
	var num4 := _spawn_player(1, facing_right, LANE_X[0])
	var num5 := _spawn_player(2, facing_right, LANE_X[2])
	_active_players = [num4, num5]
	_receiver_hit = false
	var receiver := CaptureReceiver.new()
	var receiver_offset := 52.0 if skill_id == 5 else 165.0
	receiver.position = Vector2(LANE_X[0] + (receiver_offset if facing_right else -receiver_offset), FLOOR_Y)
	_stage.add_child(receiver)
	receiver.hit_landed.connect(func() -> void: _receiver_hit = true)
	_overlay = CaptureOverlay.new()
	_stage.add_child(_overlay)
	await process_frame
	var start_x := num4.global_position.x
	num4.set_meta("capture_start_x", start_x)
	num5.set_meta("capture_start_x", num5.global_position.x)
	num4.call("_request_skill", 1 if skill_id == 4 else 2)
	num5.call("_request_skill", 2)

func _spawn_player(skill_id: int, facing_right: bool, x: float) -> CharacterBody2D:
	var player := _player_scene.instantiate() as CharacterBody2D
	player.name = "LiveNum%dPlayer" % (skill_id + 3)
	_set_display_size(player)
	_stage.add_child(player)
	player.global_position = Vector2(x, FLOOR_Y)
	player.set("facing_direction", Vector2.RIGHT if facing_right else Vector2.LEFT)
	player.get_node("VisualRoot").scale.x = 1.0 if facing_right else -1.0
	var camera := player.get_node("Camera2D") as Camera2D
	camera.enabled = false
	return player

func _set_display_size(player: CharacterBody2D) -> void:
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var bounds := art.texture.get_image().get_used_rect()
	var scale_value := 192.0 / float(maxi(bounds.size.y, 1))
	art.scale = Vector2.ONE * scale_value
	var blender := player.get_node("VisualRoot/PoseBlender")
	blender.set("sprite_scale", Vector2.ONE * scale_value)
	art.position = Vector2(0.0, -float(bounds.end.y - art.texture.get_height() / 2) * scale_value)

func _phase_progress(player: CharacterBody2D) -> float:
	var phase := str(player.get("skill_phase"))
	var duration := 0.16 if phase == "startup" else (0.12 if phase == "active" else 0.42)
	return clampf((duration - float(player.get("skill_phase_remaining"))) / duration, 0.0, 1.0)

func _clock_label(player: CharacterBody2D) -> String:
	var phase := str(player.get("skill_phase"))
	var total := 0.16 if phase == "startup" else (0.12 if phase == "active" else 0.42)
	return "%s  %.3f / %.3f s" % [phase, total - float(player.get("skill_phase_remaining")), total]

func _capture_frame(info: Dictionary) -> void:
	if _stage == null:
		return
	var panel := _overlay
	panel.title = str(info.title)
	panel.phase = str(info.phase)
	panel.facing = str(info.facing)
	panel.distance = float(info.distance)
	panel.hitbox = bool(info.hitbox)
	panel.clock = str(info.clock)
	panel.num5_phase = str(info.phase) if not bool(info.num4) else str(_active_players[1].get("skill_phase"))
	panel.hit_landed = _receiver_hit
	panel.queue_redraw()
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.get_size() != CAPTURE_SIZE:
		_errors.append("Post-draw image was not exactly 1920x1080.")
	else:
		_frames.append(frame.duplicate())
		_records.append(info.duplicate())

func _build_backdrop() -> Node:
	return CaptureBackdrop.new()

func _cleanup_stage() -> void:
	# Player hit-stop restores time scale from a timer owned by the Player; closing this isolated preview can cancel that timer.
	Engine.time_scale = 1.0
	if _stage != null and is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	_overlay = null
	_active_players.clear()
	await process_frame

func _save_contact_sheet() -> Error:
	if _frames.size() != CAPTURE_COUNT:
		return ERR_INVALID_DATA
	var columns := 2
	var rows := ceili(float(_frames.size()) / float(columns))
	var sheet := Image.create(CAPTURE_SIZE.x * columns, CAPTURE_SIZE.y * rows, false, Image.FORMAT_RGBA8)
	for index in _frames.size():
		var pos := Vector2i((index % columns) * CAPTURE_SIZE.x, floori(float(index) / float(columns)) * CAPTURE_SIZE.y)
		sheet.blit_rect(_frames[index], Rect2i(Vector2i.ZERO, CAPTURE_SIZE), pos)
	return sheet.save_png(ProjectSettings.globalize_path(OUTPUT))

func _alpha_bounds(image: Image, threshold: float) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= threshold:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _finish(message: String) -> void:
	push_error("player_skill1_contact_motion: " + message)
	quit(1)
