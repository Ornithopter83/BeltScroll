extends SceneTree
"""Play the approved-hit -> attack2 candidate sequence in a real Godot Window and capture its timed poses."""

const OUTPUT := "res://assets/art/review/player_attack2_candidate_motion_strip.png"
const VIEW_SIZE := Vector2i(1920, 1080)
const COLUMNS := 4
const ROWS := 2
const CELL := Vector2i(480, 493)
const DISPLAY_HEIGHT := 330.0
const FOOT_MARGIN := 64.0
const FRAME_NAMES := ["1타 접촉", "2타 중간", "2타 접촉 v6", "3타 접촉"]
const FRAME_PATHS := [
	"res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
]
const FRAME_DURATIONS := [0.105, 0.050, 0.120, 0.140]

var _board: Control
var _background: Texture2D
var _started_usec := 0
var _transition_log: Array[Dictionary] = []
var _metric_log: Array[Dictionary] = []
var _textures: Array[Texture2D] = []
var _bounds: Array[Rect2i] = []
var _anchors: Array[Vector2i] = []

func _initialize() -> void:
	call_deferred("_play_and_capture")

func _play_and_capture() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Godot Window 캡처에는 headless가 아닌 실행이 필요합니다.")
		return
	if not OS.get_cmdline_user_args().is_empty():
		_fail("이 캡처 도구는 사용자 인자를 받지 않습니다.")
		return
	root.mode = Window.MODE_WINDOWED
	root.size = VIEW_SIZE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(VIEW_SIZE)
	for _frame in range(3):
		await process_frame
	if DisplayServer.window_get_size() != VIEW_SIZE or root.size != VIEW_SIZE:
		_fail("Godot Window가 1920x1080으로 설정되지 않았습니다: window=%s viewport=%s" % [str(DisplayServer.window_get_size()), str(root.size)])
		return
	_background = load("res://assets/art/stage/forest_ruins_v1_1920x1080.png") as Texture2D
	if _background == null:
		_fail("격리 미리보기의 Forest Ruins 배경을 열 수 없습니다.")
		return
	for path in FRAME_PATHS:
		var image := Image.new()
		if not FileAccess.file_exists(path) or image.load(ProjectSettings.globalize_path(path)) != OK or image.get_size() != Vector2i(1254, 1254):
			_fail("연속 재생 원화를 열 수 없거나 캔버스가 1254x1254가 아닙니다: %s" % path)
			return
		var bounds := _alpha_bounds(image, 0.05)
		var anchor := _bottom_anchor(image, bounds, 0.05)
		if bounds.size.x <= 0 or anchor.x < 0:
			_fail("알파 실루엣 또는 발 anchor를 찾을 수 없습니다: %s" % path)
			return
		_textures.append(ImageTexture.create_from_image(image))
		_bounds.append(bounds)
		_anchors.append(anchor)
	_build_isolated_combat_preview()
	for _frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	_started_usec = Time.get_ticks_usec()
	for direction_row in range(ROWS):
		var facing := 1 if direction_row == 0 else -1
		for frame_index in range(FRAME_PATHS.size()):
			await _play_timed_pose(direction_row, frame_index, facing)
	await process_frame
	await RenderingServer.frame_post_draw
	var total_elapsed := float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	var screenshot := root.get_texture().get_image()
	if screenshot == null or screenshot.is_empty() or screenshot.get_size() != VIEW_SIZE:
		_fail("Godot Window Viewport에서 1920x1080 캡처를 얻지 못했습니다.")
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK:
		_fail("리뷰 이미지 출력 폴더를 만들 수 없습니다: %s" % error_string(directory_error))
		return
	var save_error := screenshot.save_png(output_path)
	if save_error != OK:
		_fail("Window 모션 캡처 저장 실패: %s" % error_string(save_error))
		return
	var verify := Image.new()
	if verify.load(output_path) != OK or verify.get_size() != VIEW_SIZE:
		_fail("저장한 실제 Window 캡처를 다시 열지 못했거나 크기가 다릅니다.")
		return
	print("attack2-candidate-motion-review: real_window=%s viewport=%s timeline_target=%.3fs timeline_elapsed=%.3fs transitions=%d" % [str(DisplayServer.window_get_size()), str(root.size), FRAME_DURATIONS.reduce(func(sum: float, value: float) -> float: return sum + value, 0.0) * ROWS, total_elapsed, _transition_log.size()])
	for event in _transition_log:
		print("TRANSITION facing=%s frame=%d texture=%s duration_target=%.3fs elapsed_to_sample=%.3fs" % [event.facing, event.frame, event.texture, event.duration, event.elapsed])
	for metrics in _metric_log:
		print("MOTION facing=%s frame=%d alpha_bounds=%s bottom_anchor_px=%s display_scale=%.5f support_feet=visual_review" % [metrics.facing, metrics.frame, metrics.bounds, metrics.anchor, metrics.scale])
	print("attack2-candidate-motion-review: saved timed combat preview to %s" % OUTPUT)
	quit(0)

func _build_isolated_combat_preview() -> void:
	var backdrop := Sprite2D.new()
	backdrop.name = "IsolatedForestCombatBackdrop"
	backdrop.texture = _background
	backdrop.position = Vector2(VIEW_SIZE) * 0.5
	backdrop.z_index = -10
	root.add_child(backdrop)
	_board = Control.new()
	_board.name = "Attack2CandidateMotionReview"
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_board)
	_label("격리 전투 미리보기 · 실시간 전환 캡처", Vector2(28, 10), 25, Color.WHITE)
	_label("타임라인: 승인 1타 접촉 → 2타 safe 중간 후보 → v6 safe 접촉 후보 → 승인 3타 접촉 · 각 행 실제 재생", Vector2(30, 43), 16, Color("#ffe2a3"))
	for row in range(ROWS):
		for col in range(COLUMNS):
			var index := row * COLUMNS + col
			var cell_position := Vector2(col * CELL.x, 94 + row * CELL.y)
			var panel := ColorRect.new()
			panel.position = cell_position + Vector2(8, 8)
			panel.size = Vector2(CELL.x - 16, CELL.y - 16)
			panel.color = Color(0.025, 0.035, 0.045, 0.73)
			_board.add_child(panel)
			_label("%s · %dms" % [FRAME_NAMES[col], roundi(FRAME_DURATIONS[col] * 1000.0)], cell_position + Vector2(20, 16), 16, Color.WHITE)
			_label("우향" if row == 0 else "좌향 · flip_h", cell_position + Vector2(20, 40), 13, Color("#e2d2ae"))
			var floor_line := ColorRect.new()
			floor_line.position = cell_position + Vector2(18, CELL.y - FOOT_MARGIN - 1)
			floor_line.size = Vector2(CELL.x - 36, 2)
			floor_line.color = Color(1.0, 0.79, 0.39, 0.9)
			_board.add_child(floor_line)
			_label("alpha 5% 하단 anchor · 지지발은 시각 판정", cell_position + Vector2(17, CELL.y - 49), 11, Color("#ffe2a3"))

func _play_timed_pose(row: int, frame_index: int, facing: int) -> void:
	var frame_start_usec := Time.get_ticks_usec()
	var texture := _textures[frame_index]
	var bounds := _bounds[frame_index]
	var anchor := _anchors[frame_index]
	var sprite := Sprite2D.new()
	sprite.name = "Played_%s_%s" % ["right" if facing > 0 else "left", frame_index]
	sprite.texture = texture
	sprite.region_enabled = true
	sprite.region_rect = Rect2(bounds)
	sprite.flip_h = facing < 0
	var scale_value := DISPLAY_HEIGHT / float(bounds.size.y)
	sprite.scale = Vector2.ONE * scale_value
	var col := frame_index
	var cell_position := Vector2(col * CELL.x, 94 + row * CELL.y)
	var baseline_y := cell_position.y + CELL.y - FOOT_MARGIN
	var anchor_offset_x := float(anchor.x - bounds.position.x) - float(bounds.size.x) * 0.5
	var anchor_offset_y := float(anchor.y - bounds.position.y) - float(bounds.size.y) * 0.5
	sprite.position = Vector2(cell_position.x + CELL.x * 0.5,
		baseline_y - anchor_offset_y * scale_value)
	_board.add_child(sprite)
	var anchor_marker := ColorRect.new()
	anchor_marker.name = "BottomAlphaAnchor_%s_%s" % [row, frame_index]
	anchor_marker.position = Vector2(cell_position.x + CELL.x * 0.5 + anchor_offset_x * scale_value * (-1.0 if facing < 0 else 1.0) - 1.0, baseline_y - 9.0)
	anchor_marker.size = Vector2(2, 18)
	anchor_marker.color = Color("#ffe063")
	anchor_marker.z_index = 2
	_board.add_child(anchor_marker)
	var midpoint: float = FRAME_DURATIONS[frame_index] * 0.5
	var midpoint_deadline := frame_start_usec + roundi(midpoint * 1000000.0)
	var frame_deadline := frame_start_usec + roundi(FRAME_DURATIONS[frame_index] * 1000000.0)
	await _wait_until_usec(midpoint_deadline)
	var sample_elapsed := float(Time.get_ticks_usec() - _started_usec) / 1000000.0
	_transition_log.append({
		"facing": "right" if facing > 0 else "left",
		"frame": frame_index,
		"texture": FRAME_PATHS[frame_index].get_file(),
		"duration": FRAME_DURATIONS[frame_index],
		"elapsed": sample_elapsed,
	})
	_metric_log.append({
		"facing": "right" if facing > 0 else "left",
		"frame": frame_index,
		"bounds": str(bounds),
		"anchor": str(anchor),
		"scale": scale_value,
	})
	await _wait_until_usec(frame_deadline)
	print("PLAY facing=%s frame=%s source=%s target_duration=%.3fs observed=%.3fs" % ["right" if facing > 0 else "left", FRAME_NAMES[frame_index], FRAME_PATHS[frame_index], FRAME_DURATIONS[frame_index], float(Time.get_ticks_usec() - frame_start_usec) / 1000000.0])

func _wait_until_usec(deadline_usec: int) -> void:
	while Time.get_ticks_usec() < deadline_usec:
		await process_frame

func _alpha_bounds(image: Image, threshold: float) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= threshold:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _bottom_anchor(image: Image, bounds: Rect2i, threshold: float) -> Vector2i:
	var bottom_y := bounds.end.y - 1
	var left := image.get_width()
	var right := -1
	for x in range(bounds.position.x, bounds.end.x):
		if image.get_pixel(x, bottom_y).a >= threshold:
			left = mini(left, x)
			right = maxi(right, x)
	return Vector2i(roundi(float(left + right) * 0.5), bottom_y) if right >= left else Vector2i(-1, -1)

func _label(value: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	_board.add_child(label)
	return label

func _fail(message: String) -> void:
	push_error("attack2-candidate-motion-review: " + message)
	quit(1)
