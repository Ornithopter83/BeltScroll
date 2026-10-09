extends SceneTree
"""Isolated review of original run candidates on the live Player motion clock."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const V1_PATH := "res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png"
const PLAYER_IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const OUTPUT_PATH := "res://assets/art/review/player_run_v5_motion_strip.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const TILE_SIZE := Vector2i(640, 450)
const DISPLAY_ALPHA_HEIGHT := 192.0
const FIT_MARGIN := 90
const FIT_SIZE := 1254
const PHASE_COUNT := 4
const PHASE_SECONDS := 0.12
const CAPTURE_RECT := Rect2i(640, 580, 640, 450)

var _canvas: Control
var _player: CharacterBody2D
var _art: Sprite2D
var _visual_root: Node2D
var _camera: Camera2D
var _caption: Label
var _status: Label
var _pelvis_marker: ColorRect
var _foot_marker: ColorRect
var _floor: ColorRect
var _procedural: Texture2D
var _v1: Texture2D
var _v5: Texture2D
var _v5_path := ""
var _textures: Array[Texture2D] = []
var _mode_names: Array[String] = []
var _mode_sources: Array[String] = []
var _bounds: Array[Rect2i] = []
var _support_points: Array[Vector2] = []
var _captures: Array[Image] = []
var _previous_foot_y := -1.0
var _previous_height := -1.0
var _max_foot_step := 0.0
var _max_height_step := 0.0
var _min_height := INF
var _max_height := 0.0
var _cycle_foot_x: Array[float] = []
var _cycle_support_names: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Godot Window가 필요합니다. headless 검수는 수행하지 않습니다.")
		return
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(WINDOW_SIZE)
	for _i in range(3):
		await process_frame
	if root.size != WINDOW_SIZE or DisplayServer.window_get_size() != WINDOW_SIZE:
		_fail("1920×1080 Godot Window 설정 실패: viewport=%s window=%s" % [str(root.size), str(DisplayServer.window_get_size())])
		return
	if not FileAccess.file_exists(V1_PATH) or not FileAccess.file_exists(PLAYER_IDLE_PATH):
		_fail("원본 v1 run 또는 본편 Player idle 원화를 찾을 수 없습니다.")
		return
	_v1 = _load_and_fit_original(V1_PATH)
	_procedural = _load_and_fit_original(PLAYER_IDLE_PATH)
	if _v1 == null or _procedural == null:
		_fail("원본 PNG를 메모리에서 읽거나 90px 여백으로 임시 맞춤하지 못했습니다.")
		return
	_v5_path = _find_v5_source()
	if not _v5_path.is_empty():
		_v5 = _load_and_fit_original(_v5_path)
		if _v5 == null:
			_v5_path = ""
	_load_player()
	if _player == null:
		_fail("본편 Player scene을 준비하지 못했습니다.")
		return
	_build_review_overlay()
	for _i in range(3):
		await process_frame
	await RenderingServer.frame_post_draw
	for phase in range(PHASE_COUNT):
		var move_right := phase < 2
		_set_motion_input(move_right)
		if phase > 0:
			await create_timer(PHASE_SECONDS).timeout
		else:
			await create_timer(0.22).timeout
		for mode_index in range(_textures.size()):
			_art.visible = _textures[mode_index] != null
			if _textures[mode_index] != null:
				_art.texture = _textures[mode_index]
				_art.flip_h = false
				_art.offset = Vector2.ZERO
			_caption.text = "%s · %s · %s" % ["오른쪽 이동" if move_right else "왼쪽 이동/방향 전환", _mode_names[mode_index], "접지/교차 위상 %d/%d" % [phase + 1, PHASE_COUNT]]
			_status.text = "본편 Player clock · 실제 속도 %.0f · 표시 높이 목표 192px · 발 점은 시각 후보" % _player.velocity.length()
			await process_frame
			await RenderingServer.frame_post_draw
			_update_anchor_markers(_bounds[mode_index], mode_index)
			await process_frame
			await RenderingServer.frame_post_draw
			var frame := root.get_texture().get_image()
			if frame == null or frame.get_size() != WINDOW_SIZE:
				_fail("실제 Window post-draw 캡처 실패: phase=%d mode=%s" % [phase, _mode_names[mode_index]])
				return
			var tile := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
			tile.blit_rect(frame, CAPTURE_RECT, Vector2i.ZERO)
			_captures.append(tile)
			_measure_current(_bounds[mode_index], mode_index, phase)
			if mode_index + 1 < _textures.size():
				await process_frame
	var columns := _textures.size()
	var rows := PHASE_COUNT
	var sheet := Image.create(TILE_SIZE.x * columns, TILE_SIZE.y * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#111821"))
	for index in range(_captures.size()):
		var tile_position := Vector2i((index % columns) * TILE_SIZE.x, (index / columns) * TILE_SIZE.y)
		sheet.blit_rect(_captures[index], Rect2i(Vector2i.ZERO, TILE_SIZE), tile_position)
	var output_file := ProjectSettings.globalize_path(OUTPUT_PATH)
	var save_error := sheet.save_png(output_file)
	if save_error != OK:
		_fail("모션 스트립 PNG 저장 실패: " + error_string(save_error))
		return
	var verify := Image.new()
	if verify.load(output_file) != OK or verify.get_size() != Vector2i(TILE_SIZE.x * columns, TILE_SIZE.y * rows):
		_fail("저장된 모션 스트립 PNG 확인 실패")
		return
	_report()
	quit(0)

func _load_player() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		return
	_player = packed.instantiate() as CharacterBody2D
	if _player == null:
		return
	_art = _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_visual_root = _player.get_node("VisualRoot") as Node2D
	if _art == null:
		_player.free()
		_player = null
		return
	var camera_in_player := _player.get_node_or_null("Camera2D") as Camera2D
	if camera_in_player != null:
		camera_in_player.enabled = false
	_art.texture = _procedural
	_art.scale = Vector2.ONE * (DISPLAY_ALPHA_HEIGHT / (FIT_SIZE - FIT_MARGIN * 2)) / 1.2
	_art.position = Vector2(0.0, -62.0)
	_art.centered = true
	_player.position = Vector2(960.0, 790.0)
	_player.set_physics_process(true)
	root.add_child(_player)
	_camera = Camera2D.new()
	_camera.name = "ReviewCamera"
	_camera.position = Vector2(960.0, 540.0)
	_camera.zoom = Vector2.ONE * 1.2
	root.add_child(_camera)
	_camera.make_current()
	_textures = [_procedural, _v1]
	_mode_names = ["본편 절차적 run", "원본 v1 후보"]
	_mode_sources = [PLAYER_IDLE_PATH, V1_PATH]
	_bounds = [_alpha_bounds(_procedural.get_image()), _alpha_bounds(_v1.get_image())]
	if _v5 != null:
		_textures.append(_v5)
		_mode_names.append("원본 v5 후보 · 미승인")
		_mode_sources.append(_v5_path)
		_bounds.append(_alpha_bounds(_v5.get_image()))
		_support_points.append(_map_original_point(_v1_path(), Vector2(1090.0, 1200.0)))
		_support_points.append(_map_original_point(_v5_path, Vector2(1145.0, 1205.0)))
	else:
		_mode_names.append("v5 미확보 · 비교 생략")
		_mode_sources.append("")
		_bounds.append(Rect2i())
		_textures.append(null)
		_support_points.append(Vector2.ZERO)
	_support_points.push_front(Vector2(float(_bounds[0].position.x) + float(_bounds[0].size.x) * 0.5, float(_bounds[0].end.y - 1)))

func _build_review_overlay() -> void:
	var layer := CanvasLayer.new()
	layer.name = "ReviewAnnotations"
	root.add_child(layer)
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_canvas)
	var floor_line := ColorRect.new()
	floor_line.position = Vector2(730, 790)
	floor_line.size = Vector2(460, 2)
	floor_line.color = Color("#728092")
	_canvas.add_child(floor_line)
	_floor = floor_line
	_label("PLAYER RUN · 실제 이동 시계 · 검수 전 원화", Vector2(24, 12), 24, Color.WHITE)
	_label("좌/우 입력은 본편 Player controller에 전달 · 점선 높이 기준 192px · 주황=골반 기준 · 민트=발 접지 후보", Vector2(24, 44), 14, Color("#c9d5e3"))
	_status = _label("", Vector2(24, 70), 14, Color("#ffd68a"))
	_caption = _label("", Vector2(710, 588), 18, Color.WHITE)
	_caption.size = Vector2(500, 36)
	_pelvis_marker = _marker(Color("#ffab5e"))
	_foot_marker = _marker(Color("#53edbd"))
	var height_rule := ColorRect.new()
	height_rule.position = Vector2(948, 572)
	height_rule.size = Vector2(24, 1)
	height_rule.color = Color("#e9d268")
	_canvas.add_child(height_rule)
	_label("192 px", Vector2(975, 570), 12, Color("#e9d268"))

func _load_and_fit_original(path: String) -> Texture2D:
	var raw := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))
	var source := Image.new()
	if raw.is_empty() or source.load_png_from_buffer(raw) != OK:
		return null
	var bounds := _alpha_bounds(source)
	if bounds.size == Vector2i.ZERO:
		return null
	var source_crop := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	source_crop.blit_rect(source, bounds, Vector2i.ZERO)
	var inner := FIT_SIZE - FIT_MARGIN * 2
	var fit_scale := minf(float(inner) / float(bounds.size.x), float(inner) / float(bounds.size.y))
	var target_size := Vector2i(maxi(1, floori(bounds.size.x * fit_scale)), maxi(1, floori(bounds.size.y * fit_scale)))
	source_crop.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	var fitted := Image.create(FIT_SIZE, FIT_SIZE, false, Image.FORMAT_RGBA8)
	fitted.fill(Color.TRANSPARENT)
	fitted.blit_rect(source_crop, Rect2i(Vector2i.ZERO, target_size), Vector2i((FIT_SIZE - target_size.x) / 2, (FIT_SIZE - target_size.y) / 2))
	return ImageTexture.create_from_image(fitted)

func _find_v5_source() -> String:
	var folder := "res://assets/art/player"
	var dir := DirAccess.open(folder)
	if dir == null:
		return ""
	var candidates: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var lower := file_name.to_lower()
		if not dir.current_is_dir() and lower.ends_with(".png") and lower.contains("run_stride_v5") and not lower.contains("safe"):
			candidates.append(folder + "/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	candidates.sort()
	return candidates[0] if not candidates.is_empty() else ""

func _set_motion_input(right: bool) -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_press("move_right" if right else "move_left")

func _update_anchor_markers(bounds: Rect2i, mode_index: int) -> void:
	if bounds.size == Vector2i.ZERO:
		_pelvis_marker.visible = false
		_foot_marker.visible = false
		return
	var pelvis_local := Vector2(627.0, float(bounds.position.y) + float(bounds.size.y) * 0.67) - Vector2(627.0, 627.0)
	var foot_local := _support_points[mode_index] - Vector2(627.0, 627.0)
	var transform := _art.get_global_transform_with_canvas()
	_place_marker(_pelvis_marker, transform * pelvis_local)
	var foot_screen := transform * foot_local
	_place_marker(_foot_marker, foot_screen)
	_floor.position.y = foot_screen.y + 8.0

func _measure_current(bounds: Rect2i, mode_index: int, phase: int) -> void:
	if bounds.size == Vector2i.ZERO:
		print("SAMPLE phase=%d mode=v5_missing movement_speed=%.1f" % [phase, _player.velocity.length()])
		return
	var screen_transform := _art.get_global_transform_with_canvas()
	var pelvis := screen_transform * (Vector2(627.0, float(bounds.position.y) + float(bounds.size.y) * 0.67) - Vector2(627.0, 627.0))
	var foot := screen_transform * (_support_points[mode_index] - Vector2(627.0, 627.0))
	var height := absf(float(bounds.size.y) * screen_transform.y.length())
	_min_height = minf(_min_height, height)
	_max_height = maxf(_max_height, height)
	_cycle_foot_x.append(foot.x)
	_cycle_support_names.append("right" if _player.facing_direction.x > 0.0 else "left")
	if _previous_foot_y >= 0.0:
		_max_foot_step = maxf(_max_foot_step, absf(foot.y - _previous_foot_y))
		_max_height_step = maxf(_max_height_step, absf(height - _previous_height))
	_previous_foot_y = foot.y
	_previous_height = height
	print("SAMPLE phase=%d mode=%s direction=%s speed=%.1f alpha_height_screen_px=%.2f pelvis_screen=(%.1f,%.1f) foot_candidate_screen=(%.1f,%.1f) candidate_flip_h=%s player_visual_root_scale_x=%.1f" % [phase, _mode_names[mode_index], "right" if _player.facing_direction.x > 0.0 else "left", _player.velocity.length(), height, pelvis.x, pelvis.y, foot.x, foot.y, str(_art.flip_h), _visual_root.scale.x])

func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.05:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _map_original_point(path: String, original_point: Vector2) -> Vector2:
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return Vector2(627.0, 1163.0)
	var bounds := _alpha_bounds(image)
	var inner := FIT_SIZE - FIT_MARGIN * 2
	var fit_scale := minf(float(inner) / float(bounds.size.x), float(inner) / float(bounds.size.y))
	var target_size := Vector2(float(bounds.size.x), float(bounds.size.y)) * fit_scale
	var offset := (Vector2(FIT_SIZE, FIT_SIZE) - target_size) * 0.5
	return offset + (original_point - Vector2(bounds.position)) * fit_scale

func _v1_path() -> String:
	return V1_PATH

func _place_marker(marker: ColorRect, point: Vector2) -> void:
	marker.position = point - marker.size * 0.5
	marker.visible = true

func _marker(color: Color) -> ColorRect:
	var marker := ColorRect.new()
	marker.size = Vector2(10, 10)
	marker.color = color
	marker.z_index = 10
	_canvas.add_child(marker)
	return marker

func _label(value: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	_canvas.add_child(label)
	return label

func _report() -> void:
	print("WINDOW size=%s display=windowed renderer=actual_post_draw player_scene=%s" % [str(WINDOW_SIZE), PLAYER_SCENE])
	print("SOURCE v1=%s raw_original=loaded_from_bytes fit=in_memory margin=%dpx integration=none" % [V1_PATH, FIT_MARGIN])
	if _v5 == null:
		print("SOURCE v5=NOT_ACQUIRED searched=run_stride_v5*.png excluding_safe=true")
	else:
		print("SOURCE v5=found path=%s raw_original=loaded_from_bytes fit=in_memory margin=%dpx approval=review-only" % [_v5_path, FIT_MARGIN])
	print("METRIC target_silhouette_height=192px measured_range=%.2f..%.2f max_adjacent_height_delta=%.2fpx max_adjacent_foot_anchor_delta=%.2fpx" % [_min_height, _max_height, _max_height_step, _max_foot_step])
	print("CYCLE facing_samples=%s; visual_contact_pose_same_stride=true foot_crossing=not_demonstrated procedural_run_clock=PlayerVisualAnimator._stride_phase direction_turn=PlayerController.facing_direction" % str(_cycle_support_names))
	print("MIRROR candidate_flip_h=false; left/right facing uses Player.VisualRoot scale; same-source mirrored pose is duplicate_pose_risk")
	var acquisition := "not_acquired" if _v5 == null else "acquired_pending_visual_review"
	print("GATE v5=%s; same_stride_is_not_accepted=true approval=not_performed integration=none runtime_registration=none" % acquisition)
	print("CAPTURE path=%s size=%dx%d states=%d source_mode_count=%d" % [OUTPUT_PATH, TILE_SIZE.x * _textures.size(), TILE_SIZE.y * PHASE_COUNT, _captures.size(), _textures.size()])

func _fail(message: String) -> void:
	push_error("player_run_v5_motion_review: " + message)
	quit(1)
