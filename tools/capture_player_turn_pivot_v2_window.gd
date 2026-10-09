extends SceneTree
"""Post-draw review capture for the production Player turn clock."""

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const OUTPUT_PATH := "res://assets/art/review/player_turn_pivot_v2_window.png"
const V1_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png"
const V2_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v2_candidate_1254x1254.png"
const V2_ALTERNATE_PATH := "res://assets/art/player/elven_fighter_turn_pivot_v2_candidate_1254x1254.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const TILE_SIZE := Vector2i(480, 540)
const TILE_COUNT := 8
const ALPHA_THRESHOLD := 0.05

var _stage: Node2D
var _player: CharacterBody2D
var _animator: Node
var _art: Sprite2D
var _idle_texture: Texture2D
var _idle_art_position := Vector2.ZERO
var _v1_texture: Texture2D
var _v2_texture: Texture2D
var _caption: Label
var _detail: Label
var _frames: Array[Image] = []
var _capture_size := Vector2i.ZERO
var _measurements: Array[Dictionary] = []
var _v2_available := false
var _landmark_layer: Node2D
var _landmarks: Dictionary = {}

func _initialize() -> void:
	root.size = WINDOW_SIZE
	root.mode = Window.MODE_WINDOWED
	root.title = "Player turn pivot review · 1920×1080"
	DisplayServer.window_set_size(WINDOW_SIZE)
	call_deferred("_run")

func _run() -> void:
	await process_frame
	root.size = WINDOW_SIZE
	DisplayServer.window_set_size(WINDOW_SIZE)
	await process_frame
	var os_window_size := DisplayServer.window_get_size()
	var dpi_ratio := Vector2(float(os_window_size.x) / float(WINDOW_SIZE.x), float(os_window_size.y) / float(WINDOW_SIZE.y))
	if dpi_ratio.x > 1.01 or dpi_ratio.y > 1.01:
		DisplayServer.window_set_size(Vector2i(roundi(float(WINDOW_SIZE.x) / dpi_ratio.x), roundi(float(WINDOW_SIZE.y) / dpi_ratio.y)))
		root.size = WINDOW_SIZE
		await process_frame
	_stage = Node2D.new()
	_stage.name = "TurnPivotReview"
	root.add_child(_stage)
	_stage.add_child(_make_background())
	_player = PLAYER_SCENE.instantiate() as CharacterBody2D
	_player.name = "ReviewPlayer"
	_player.position = Vector2(960.0, 790.0)
	(_player.get_node("Camera2D") as Camera2D).enabled = false
	_player.set_physics_process(false)
	_stage.add_child(_player)
	_animator = _player.get_node("VisualAnimator")
	_animator.set_process(false)
	_art = _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_idle_texture = _art.texture
	_idle_art_position = _art.position
	_v1_texture = _load_texture(V1_PATH)
	_v2_texture = _load_texture(V2_PATH)
	if _v2_texture == null:
		_v2_texture = _load_texture(V2_ALTERNATE_PATH)
	_v2_available = _v2_texture != null
	_add_overlay()
	await process_frame
	await RenderingServer.frame_post_draw

	_set_facing(1.0)
	await _capture("IDLE · 우향", "본편 Player · turn 0.13 s · idle")
	_start_turn(-1.0)
	await _advance_clock(0.020)
	await _capture("ANTICIPATION · 우→좌", "0.020 s · windup / compression 전")
	await _advance_clock(0.035)
	_art.texture = _v1_texture if _v1_texture != null else _idle_texture
	if _v1_texture != null:
		_set_v1_review_pose()
	await _capture("MID · V1 원본 임시 표시", "0.055 s · v1 candidate 원본 · safe 산출물 미사용")
	_art.texture = _idle_texture
	_art.position = _idle_art_position
	_set_landmarks({})
	if _v2_available:
		_art.texture = _v2_texture
		_set_v2_review_pose()
		await _capture("MID · V2 원본 임시 표시", "0.055 s · v2 candidate 원본")
		_art.texture = _idle_texture
		_art.position = _idle_art_position
		_set_landmarks({})
	else:
		await _advance_clock(0.010)
		await _capture("FLIP · 우→좌", "0.065 s · 본편 flip 경계 0.040 + 0.025 s")
		await _advance_clock(0.065)
		await _capture("SETTLE · 좌향", "0.130 s · 본편 turn 시계 완료")

	if _v2_available:
		await _advance_clock(0.010)
		await _capture("FLIP · 우→좌", "0.065 s · 본편 flip 경계 0.040 + 0.025 s")
		await _advance_clock(0.065)
		await _capture("SETTLE · 좌향", "0.130 s · 본편 turn 시계 완료")

	_set_facing(-1.0)
	_start_turn(1.0)
	await _advance_clock(0.075)
	await _capture("방향 전환 · 좌→우", "반대 방향 turn · flip 이후")
	_set_facing(-1.0)
	_start_turn(1.0)
	await _advance_clock(0.035)
	_player.set("facing_direction", Vector2.LEFT)
	await _advance_clock(0.035)
	await _capture("역입력 · 좌→우→좌", "0.070 s · 진행 중 목표 방향 재지정")
	_set_facing(1.0)
	_start_turn(-1.0)
	await _advance_clock(0.025)
	_player.call("receive_hit", {"damage": 0, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.12, "attack_stage": 1})
	await _advance_clock(1.0 / 60.0)
	await _capture("피격 취소", "0.042 s · 본편 receive_hit → hitstun / turn 취소")

	var expected_count := TILE_COUNT + (1 if _v2_available else 0)
	if _frames.size() != expected_count:
		_fail("Expected %d captures, got %d." % [expected_count, _frames.size()])
		return
	var montage := _compose_montage()
	var save_error := montage.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if save_error != OK:
		_fail("Could not save capture: %s" % error_string(save_error))
		return
	print("turn-pivot-window: renderer=%s OS_window=%s render_framebuffer=%s output=%s" % [DisplayServer.get_name(), str(DisplayServer.window_get_size()), str(_capture_size), OUTPUT_PATH])
	print("turn-pivot-window: v2_raw_available=%s; v1_raw_available=%s" % [str(_v2_available), str(_v1_texture != null)])
	for measurement in _measurements:
		print("turn-pivot-measure: %s" % JSON.stringify(measurement))
	quit(0)

func _make_background() -> Node2D:
	var background := Node2D.new()
	background.draw.connect(func() -> void:
		background.draw_rect(Rect2(Vector2.ZERO, WINDOW_SIZE), Color("#111923"), true)
		background.draw_line(Vector2(720.0, 792.0), Vector2(1200.0, 792.0), Color("#677d82"), 2.0)
		background.draw_line(Vector2(960.0, 745.0), Vector2(960.0, 815.0), Color("#ffcd57"), 2.0)
		background.draw_circle(Vector2(960.0, 792.0), 5.0, Color("#ffcd57")))
	return background

func _add_overlay() -> void:
	var layer := CanvasLayer.new()
	_stage.add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(530.0, 28.0)
	panel.size = Vector2(860.0, 120.0)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.06, 0.95)
	style.border_color = Color("#6d9794")
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	layer.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 4)
	panel.add_child(stack)
	_caption = _label("", 30, Color("#f4dfb2"))
	_detail = _label("", 19, Color("#c8dcda"))
	stack.add_child(_caption)
	stack.add_child(_detail)
	_landmark_layer = Node2D.new()
	_landmark_layer.draw.connect(_draw_landmarks)
	_stage.add_child(_landmark_layer)

func _label(value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)

func _set_v1_review_pose() -> void:
	# Authored raw-source landmarks, in 1254×1254 source pixels. The right sole
	# is the candidate's inferred support foot and is aligned to the production
	# combat anchor for a direct planted-foot check.
	var pelvis_source := Vector2(640.0, 700.0)
	var near_boot_source := Vector2(535.0, 1138.0)
	var support_boot_source := Vector2(887.0, 1199.0)
	var image_size := Vector2(_art.texture.get_size())
	var support_local := (support_boot_source - image_size * 0.5) * _art.scale
	_art.position = _animator.get("_combat_anchor") - support_local.rotated(_art.rotation)
	_set_landmarks({
		"pelvis": _art.to_global(pelvis_source - image_size * 0.5),
		"boot_a": _art.to_global(near_boot_source - image_size * 0.5),
		"boot_b": _art.to_global(support_boot_source - image_size * 0.5),
		"anchor": (_player.get_node("VisualRoot") as Node2D).to_global(_animator.get("_combat_anchor")),
	})

func _set_v2_review_pose() -> void:
	# Independent landmarks authored for the alternate v2 source in its own
	# 1254x1254 coordinates; do not reuse the v1 support-foot location.
	var pelvis_source := Vector2(650.0, 700.0)
	var left_boot_source := Vector2(625.0, 1135.0)
	var support_boot_source := Vector2(770.0, 1135.0)
	var image_size := Vector2(_art.texture.get_size())
	var support_local := (support_boot_source - image_size * 0.5) * _art.scale
	_art.position = _animator.get("_combat_anchor") - support_local.rotated(_art.rotation)
	_set_landmarks({
		"pelvis": _art.to_global(pelvis_source - image_size * 0.5),
		"boot_a": _art.to_global(left_boot_source - image_size * 0.5),
		"boot_b": _art.to_global(support_boot_source - image_size * 0.5),
		"anchor": (_player.get_node("VisualRoot") as Node2D).to_global(_animator.get("_combat_anchor")),
	})

func _set_landmarks(points: Dictionary) -> void:
	_landmarks = points
	if _landmark_layer != null:
		_landmark_layer.queue_redraw()

func _draw_landmarks() -> void:
	for key in _landmarks:
		var point: Vector2 = _landmarks[key]
		var color := Color("#ffcd57") if key == "anchor" else (Color("#55efd0") if key == "pelvis" else Color("#ff806d"))
		_landmark_layer.draw_circle(point, 9.0, color)
		_landmark_layer.draw_line(point - Vector2(13.0, 0.0), point + Vector2(13.0, 0.0), color, 2.0)
		_landmark_layer.draw_line(point - Vector2(0.0, 13.0), point + Vector2(0.0, 13.0), color, 2.0)

func _set_facing(sign: float) -> void:
	_player.set("facing_direction", Vector2(sign, 0.0))
	_player.set("hitstun_remaining", 0.0)
	_player.set("hit_flash_remaining", 0.0)
	_player.set("is_ko", false)
	_art.modulate = Color.WHITE
	_animator.set("_applied_facing_sign", sign)
	_animator.set("_turn_target_sign", sign)
	_animator.set("_turn_elapsed", 0.13)
	_animator.set("_turn_flip_applied", false)
	(_player.get_node("VisualRoot") as Node2D).scale.x = sign

func _start_turn(sign: float) -> void:
	_player.set("facing_direction", Vector2(sign, 0.0))
	_animator.call("_process", 0.0)

func _advance_clock(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 60.0)
		_animator.call("_process", step)
		remaining -= step
		await process_frame

func _capture(title: String, detail: String) -> void:
	_caption.text = title
	_detail.text = detail
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.is_empty() or frame.get_size() != WINDOW_SIZE:
		_fail("Window framebuffer is not 1920×1080: %s" % (str(frame.get_size()) if frame != null else "null"))
		return
	_capture_size = frame.get_size()
	_frames.append(frame)
	var image := _art.texture.get_image()
	var bounds := _alpha_bounds(image)
	var visual_root := _player.get_node("VisualRoot") as Node2D
	var foot_anchor: Vector2 = _animator.get("_combat_anchor")
	var root_anchor := visual_root.to_global(foot_anchor)
	var effective_flip := visual_root.scale.x < 0.0
	var landmark_positions := {}
	for key in _landmarks:
		var point: Vector2 = _landmarks[key]
		landmark_positions[key] = [snappedf(point.x, 0.1), snappedf(point.y, 0.1)]
	_measurements.append({
		"sample": title,
		"turn_progress": snappedf(float(_animator.call("get_turn_progress")), 0.001),
		"turning": bool(_animator.call("is_turning")),
		"applied_facing": "left" if effective_flip else "right",
		"sprite_flip_h": _art.flip_h,
		"rotation_rad": snappedf(_art.rotation, 0.0001),
		"scale": [snappedf(_art.scale.x, 0.0001), snappedf(_art.scale.y, 0.0001)],
		"alpha_bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"alpha_ratio_xy": [snappedf(float(bounds.size.x) / float(image.get_width()), 0.0001), snappedf(float(bounds.size.y) / float(image.get_height()), 0.0001)],
		"pivot_world": [snappedf(_art.global_position.x, 0.1), snappedf(_art.global_position.y, 0.1)],
		"combat_foot_anchor_world": [snappedf(root_anchor.x, 0.1), snappedf(root_anchor.y, 0.1)],
		"manual_landmarks_screen_px": landmark_positions,
		"texture": V1_PATH.get_file() if _art.texture == _v1_texture else (V2_ALTERNATE_PATH.get_file() if _v2_texture != null and _art.texture == _v2_texture else _art.texture.resource_path.get_file())
	})

func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _compose_montage() -> Image:
	var montage := Image.create(WINDOW_SIZE.x, WINDOW_SIZE.y, false, Image.FORMAT_RGBA8)
	montage.fill(Color("#091016"))
	var columns := 5 if _v2_available else 4
	var tile_size := Vector2i(WINDOW_SIZE.x / columns, WINDOW_SIZE.y / 2)
	for index in _frames.size():
		var tile := _frames[index]
		tile.resize(tile_size.x, tile_size.y, Image.INTERPOLATE_LANCZOS)
		montage.blit_rect(tile, Rect2i(Vector2i.ZERO, tile_size), Vector2i((index % columns) * tile_size.x, (index / columns) * tile_size.y))
	for column in range(1, columns):
		montage.fill_rect(Rect2i(column * tile_size.x - 1, 0, 2, WINDOW_SIZE.y), Color("#6d9794"))
	montage.fill_rect(Rect2i(0, tile_size.y - 1, WINDOW_SIZE.x, 2), Color("#6d9794"))
	return montage

func _fail(message: String) -> void:
	push_error("player_turn_pivot_v2_window: " + message)
	quit(1)
