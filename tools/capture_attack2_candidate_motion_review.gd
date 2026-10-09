extends SceneTree
"""Capture an isolated, timed attack sequence with foot-lock and alpha-step alignment comparisons."""

const OUTPUT := "res://assets/art/review/player_attack2_candidate_motion_strip.png"
const VIEW_SIZE := Vector2i(1920, 1080)
const COLUMNS := 4
const ROWS := 4
const CELL := Vector2i(480, 225)
const TOP := 158
const DISPLAY_HEIGHT := 176.0
const FOOT_MARGIN := 35.0
const FRAME_NAMES := ["1타 접촉", "2타 중간", "2타 접촉 v6", "3타 접촉"]
const FRAME_PATHS := [
	"res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
]
const FRAME_DURATIONS := [0.105, 0.050, 0.120, 0.140]
const ALIGNMENT_NAMES := ["지지발 고정", "원화 pivot 고정·의도적 스텝"]
const ANCHOR_COLOR := Color("#ffe063")
const SUPPORT_COLOR := Color("#5ff0c2")
# Provisional visible support-foot candidates (source-canvas x). Kept separate
# from the mechanically measured lowest-alpha-row center; visual review may revise them.
const SUPPORT_FOOT_X := [1073, 1064, 1100, 1000]

var _board: Control
var _background: Texture2D
var _started_usec := 0
var _transition_log: Array[Dictionary] = []
var _metric_log: Array[Dictionary] = []
var _textures: Array[Texture2D] = []
var _bounds: Array[Rect2i] = []
var _bottom_anchors: Array[Vector2i] = []
var _exposure_labels: Array[Label] = []

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
			_fail("알파 실루엣 또는 하단 anchor를 찾을 수 없습니다: %s" % path)
			return
		_textures.append(ImageTexture.create_from_image(image))
		_bounds.append(bounds)
		_bottom_anchors.append(anchor)
	_build_isolated_combat_preview()
	for _frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	_started_usec = Time.get_ticks_usec()
	# Each row is an independently played 1 -> middle -> v6 -> 3 sequence.
	# Rows 0/1 face right, rows 2/3 face left; each direction compares both alignments.
	for row in range(ROWS):
		var facing := 1 if row < 2 else -1
		var alignment: int = row % 2
		for frame_index in range(FRAME_PATHS.size()):
			await _play_timed_pose(row, frame_index, facing, alignment)
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
	print("attack2-candidate-motion-review: real_window=%s viewport=%s target=%.3fs elapsed=%.3fs transitions=%d" % [str(DisplayServer.window_get_size()), str(root.size), 0.830, total_elapsed, _transition_log.size()])
	for event in _transition_log:
		print("EXPOSURE facing=%s alignment=%s frame=%s target_ms=%d observed_ms=%.1f rendered_frames=%d midpoint_rendered_frames=%d" % [event.facing, event.alignment, event.name, event.target_ms, event.observed_ms, event.rendered_frames, event.midpoint_rendered_frames])
	var contact_step_px := absf(float(_bottom_anchors[2].x - _bottom_anchors[3].x) * 330.0 / 1254.0)
	print("CONTACT_STEP_ANALYSIS: v6_alpha_center_x=%d attack3_alpha_center_x=%d source_delta_px=%d normalized_display_height=330px screen_delta_px=%.1f; low-alpha anchor switches boots, not proof of support-foot travel" % [_bottom_anchors[2].x, _bottom_anchors[3].x, abs(_bottom_anchors[2].x - _bottom_anchors[3].x), contact_step_px])
	for metrics in _metric_log:
		print("MOTION facing=%s alignment=%s frame=%s bounds=%s alpha_bottom_center=%s support_candidate_x=%d bottom_to_support_px=%.1f unclipped=%s flip_h=%s" % [metrics.facing, metrics.alignment, metrics.name, metrics.bounds, metrics.bottom_anchor, metrics.support_x, metrics.anchor_delta_screen, metrics.unclipped, metrics.flip_h])
	print("attack2-candidate-motion-review: saved isolated timed preview to %s" % OUTPUT)
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
	_label("2타 후보 모션 격리 검수 · 실제 Window 재생 노출 프레임 기록", Vector2(28, 10), 25, Color.WHITE)
	_label("1타 → safe 중간 50ms → v6 safe 접촉 → 기존 3타 · 우향/좌향 각 정렬 방식으로 연속 재생", Vector2(30, 43), 16, Color("#ffe2a3"))
	_label("행 비교: 지지발 후보 고정 / 원화 pivot 고정 스텝 · 노랑=움직이는 alpha anchor, 민트=지지발 후보 · 330px 기준 v6→3은 217px", Vector2(30, 67), 14, Color("#d4f5e8"))
	for row in range(ROWS):
		var facing: String = "우향" if row < 2 else "좌향 · flip_h"
		var alignment: String = ALIGNMENT_NAMES[row % 2]
		_label("%s · %s" % [facing, alignment], Vector2(20, TOP + row * CELL.y + 2), 13, Color("#ffe2a3"))
		for col in range(COLUMNS):
			var cell_position := Vector2(col * CELL.x, TOP + row * CELL.y + 22)
			var panel := ColorRect.new()
			panel.position = cell_position + Vector2(7, 4)
			panel.size = Vector2(CELL.x - 14, CELL.y - 30)
			panel.color = Color(0.025, 0.035, 0.045, 0.76)
			_board.add_child(panel)
			_label("%s · %dms" % [FRAME_NAMES[col], roundi(FRAME_DURATIONS[col] * 1000.0)], cell_position + Vector2(14, 7), 13, Color.WHITE)
			var exposure := _label("실제 노출: 측정 중", cell_position + Vector2(14, 27), 11, Color("#ffe2a3"))
			_exposure_labels.append(exposure)
			var floor_line := ColorRect.new()
			floor_line.position = cell_position + Vector2(15, CELL.y - FOOT_MARGIN - 27)
			floor_line.size = Vector2(CELL.x - 30, 2)
			floor_line.color = Color(1.0, 0.79, 0.39, 0.9)
			_board.add_child(floor_line)
			_label("시각 판정: 잘림 / 중복 / 팝 / 발 미끄럼", cell_position + Vector2(14, CELL.y - 40), 9, Color("#ffe2a3"))

func _play_timed_pose(row: int, frame_index: int, facing: int, alignment: int) -> void:
	var frame_start_usec := Time.get_ticks_usec()
	var texture := _textures[frame_index]
	var bounds := _bounds[frame_index]
	var bottom_anchor := _bottom_anchors[frame_index]
	var sprite := Sprite2D.new()
	sprite.name = "Played_%s_%s_%s" % ["right" if facing > 0 else "left", alignment, frame_index]
	sprite.texture = texture
	sprite.flip_h = facing < 0
	var scale_value := DISPLAY_HEIGHT / 1254.0
	sprite.scale = Vector2.ONE * scale_value
	var cell_position := Vector2(frame_index * CELL.x, TOP + row * CELL.y + 22)
	var baseline_y := cell_position.y + CELL.y - FOOT_MARGIN - 27
	var chosen_x: int = SUPPORT_FOOT_X[frame_index] if alignment == 0 else 627
	var anchor_offset_x := float(chosen_x) - 627.0
	var anchor_offset_y := float(bottom_anchor.y) - 627.0
	sprite.position = Vector2(cell_position.x + CELL.x * 0.5 - anchor_offset_x * scale_value * float(facing),
		baseline_y - anchor_offset_y * scale_value)
	_board.add_child(sprite)
	_add_marker(cell_position, baseline_y, bottom_anchor.x, chosen_x, facing, scale_value, ANCHOR_COLOR, "BottomAlpha", -22.0)
	_add_marker(cell_position, baseline_y, SUPPORT_FOOT_X[frame_index], chosen_x, facing, scale_value, SUPPORT_COLOR, "SupportFoot", -9.0)
	var elapsed_at_midpoint := Time.get_ticks_usec()
	var midpoint_count := 0
	var total_count := 0
	var midpoint_deadline := frame_start_usec + roundi(FRAME_DURATIONS[frame_index] * 500000.0)
	var frame_deadline := frame_start_usec + roundi(FRAME_DURATIONS[frame_index] * 1000000.0)
	midpoint_count = await _wait_until_usec(midpoint_deadline)
	elapsed_at_midpoint = Time.get_ticks_usec()
	var label_index := row * COLUMNS + frame_index
	_exposure_labels[label_index].text = "중간까지 %d회 렌더 · 50ms 전체 측정 중" % midpoint_count if frame_index == 1 else "중간까지 %d회 렌더" % midpoint_count
	var observed_until_midpoint := float(elapsed_at_midpoint - frame_start_usec) / 1000.0
	total_count += midpoint_count
	total_count += await _wait_until_usec(frame_deadline)
	var observed_ms := float(Time.get_ticks_usec() - frame_start_usec) / 1000.0
	_exposure_labels[label_index].text = "실제 노출 %d 렌더 프레임 · %.1fms" % [total_count, observed_ms]
	var bottom_to_support_px := absf(float(bottom_anchor.x - SUPPORT_FOOT_X[frame_index]) * scale_value)
	var unclipped := bounds.position.x * scale_value >= 0.0 and bounds.end.x * scale_value <= 1254.0 * scale_value \
		and bounds.position.y * scale_value >= 0.0 and bounds.end.y * scale_value <= 1254.0 * scale_value
	var event := {
		"facing": "right" if facing > 0 else "left",
		"alignment": ALIGNMENT_NAMES[alignment],
		"frame": frame_index,
		"name": FRAME_NAMES[frame_index],
		"texture": FRAME_PATHS[frame_index].get_file(),
		"target_ms": roundi(FRAME_DURATIONS[frame_index] * 1000.0),
		"observed_ms": observed_ms,
		"rendered_frames": total_count,
		"midpoint_rendered_frames": midpoint_count,
		"bounds": str(bounds),
		"bottom_anchor": str(bottom_anchor),
		"support_x": SUPPORT_FOOT_X[frame_index],
		"anchor_delta_screen": bottom_to_support_px,
		"unclipped": unclipped,
		"flip_h": facing < 0,
	}
	_transition_log.append(event)
	_metric_log.append(event)
	print("PLAY facing=%s alignment=%s frame=%s source=%s target=%dms midpoint_ms=%.1f midpoint_frames=%d observed=%.1fms rendered_frames=%d" % [event.facing, event.alignment, event.name, FRAME_PATHS[frame_index], event.target_ms, observed_until_midpoint, midpoint_count, observed_ms, total_count])

func _add_marker(cell: Vector2, baseline: float, source_x: int, alignment_x: int, facing: int, scale_value: float, color: Color, marker_name: String, vertical_offset: float) -> void:
	var marker := ColorRect.new()
	marker.name = "%s_%s" % [marker_name, str(source_x)]
	marker.position = Vector2(cell.x + CELL.x * 0.5 + float(source_x - alignment_x) * scale_value * float(facing) - 1.0, baseline + vertical_offset)
	marker.size = Vector2(2, 18)
	marker.color = color
	marker.z_index = 3
	_board.add_child(marker)

func _wait_until_usec(deadline_usec: int) -> int:
	var rendered_frames := 0
	while Time.get_ticks_usec() < deadline_usec:
		await process_frame
		await RenderingServer.frame_post_draw
		rendered_frames += 1
	return rendered_frames

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
