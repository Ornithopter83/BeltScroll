extends SceneTree
"""Isolated real-Window review for unapproved run-stride art candidates."""

const V1_PATH := "res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png"
const REVIEW_PATH := "res://assets/art/review/player_run_cycle_review.png"
const VIEW_SIZE := Vector2i(1920, 1080)
const TILE_SIZE := Vector2i(640, 500)
const OUTPUT_SIZE := Vector2i(1920, 1500)
const DISPLAY_HEIGHT := 410.0
const PHASE_SECONDS := 0.12
const CAPTIONS := [
	"우향 · stride A / 실제 원화",
	"우향 · stride B / v2 경계 직전",
	"좌향 · stride A / v1 수평 반전",
	"좌향 · stride B / v2 수평 반전",
	"정지 유지 · 원화는 검수용 후보",
	"정지 → 달리기 · v1 후보 재생",
	"달리기 → 정지 · v1 후보 정지",
	"방향 반전 · 우향 → 좌향",
	"방향 반전 · 좌향 → 우향",
]

var _canvas: Control
var _sprite: Sprite2D
var _status: Label
var _caption: Label
var _v1: Texture2D
var _v2: Texture2D
var _source_frames: Array[Texture2D] = []
var _source_names: Array[String] = []
var _tile_images: Array[Image] = []
var _metrics: Array[Dictionary] = []
var _v1_bounds := Rect2i()
var _v2_bounds := Rect2i()
var _support_marker: ColorRect
var _edge_marker: ColorRect
var _support_marker_label: Label
var _edge_marker_label: Label
var _source_frame_count := 0
var _loop_period_seconds := -1.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Godot Window가 필요합니다. headless에서는 검수 캡처를 만들지 않습니다.")
		return
	root.mode = Window.MODE_WINDOWED
	root.size = VIEW_SIZE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(VIEW_SIZE)
	for _i in range(3):
		await process_frame
	if root.size != VIEW_SIZE or DisplayServer.window_get_size() != VIEW_SIZE:
		_fail("1920x1080 Godot Window를 설정하지 못했습니다: viewport=%s window=%s" % [str(root.size), str(DisplayServer.window_get_size())])
		return
	if not FileAccess.file_exists(V1_PATH):
		_fail("기존 v1 run stride 원화를 찾을 수 없습니다: " + V1_PATH)
		return
	_v1 = _load_texture(V1_PATH)
	if _v1 == null:
		_fail("v1 원화를 PNG Texture로 읽지 못했습니다.")
		return
	_v1_bounds = _alpha_bounds(_v1.get_image(), 0.05)
	if _v1.get_size() != Vector2(1254, 1254) or _v1_bounds.size == Vector2i.ZERO:
		_fail("v1 원화 캔버스 또는 alpha 실루엣이 예상과 다릅니다: %s %s" % [str(_v1.get_size()), str(_v1_bounds)])
		return
	_find_v2_candidate()
	_source_frames = [_v1]
	_source_names = ["v1"]
	if _v2 != null:
		_source_frames.append(_v2)
		_source_names.append("v2")
	_source_frame_count = _source_frames.size()
	_loop_period_seconds = PHASE_SECONDS * float(_source_frame_count)
	_build_window()
	for _i in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	await _measure_live_loop()
	await _capture_review_states()
	var board := Image.create(OUTPUT_SIZE.x, OUTPUT_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("#111821"))
	for i in range(_tile_images.size()):
		board.blit_rect(_tile_images[i], Rect2i(Vector2i.ZERO, TILE_SIZE), Vector2i((i % 3) * TILE_SIZE.x, (i / 3) * TILE_SIZE.y))
	var output_file := ProjectSettings.globalize_path(REVIEW_PATH)
	var dir_error := DirAccess.make_dir_recursive_absolute(output_file.get_base_dir())
	if dir_error != OK:
		_fail("리뷰 출력 폴더 생성 실패: " + error_string(dir_error))
		return
	var save_error := board.save_png(output_file)
	if save_error != OK:
		_fail("검수 보드 PNG 저장 실패: " + error_string(save_error))
		return
	var verify := Image.new()
	if verify.load(output_file) != OK or verify.get_size() != OUTPUT_SIZE:
		_fail("저장된 검수 보드를 다시 읽거나 1920x1000 크기를 확인하지 못했습니다.")
		return
	_report()
	print("player-run-cycle-review: saved actual Godot Window frame crops to %s" % REVIEW_PATH)
	quit(0)

func _find_v2_candidate() -> void:
	var dir := DirAccess.open("res://assets/art/player")
	if dir == null:
		return
	var candidates: Array[String] = []
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var lower := file_name.to_lower()
		if not dir.current_is_dir() and lower.ends_with(".png") and lower.contains("run_stride_v2"):
			candidates.append("res://assets/art/player/" + file_name)
		file_name = dir.get_next()
	dir.list_dir_end()
	candidates.sort()
	for path in candidates:
		var texture := _load_texture(path)
		if texture == null or texture.get_size() != Vector2(1254, 1254):
			continue
		var bounds := _alpha_bounds(texture.get_image(), 0.05)
		if bounds.size == Vector2i.ZERO:
			continue
		_v2 = texture
		_v2_bounds = bounds
		print("SOURCE v2=found path=%s bounds=%s approval=review-only" % [path, str(bounds)])
		return
	print("SOURCE v2=NOT_ACQUIRED searched=res://assets/art/player/*run_stride_v2*.png")

func _build_window() -> void:
	_canvas = Control.new()
	_canvas.name = "IsolatedRunCycleReview"
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_canvas)
	var background := ColorRect.new()
	background.color = Color("#111821")
	background.size = Vector2(VIEW_SIZE)
	_canvas.add_child(background)
	_label("RUN STRIDE · 격리 검수 · 승인 전 후보", Vector2(24, 14), 25, Color.WHITE)
	var v2_status := "v2: 미확보" if _v2 == null else "v2: 검수 후보 확인 · 미승인"
	_status = _label("v1/v2: 2개 보폭 후보 · %s · 본편 Player / animation manifest 미연결" % v2_status, Vector2(26, 50), 16, Color("#ffd68a"))
	_label("민트=수동 지지발 후보 · 노랑=알파 원화 경계/최하단 참고 · 원화 경계는 실제 지지발 판정이 아님", Vector2(26, 78), 13, Color("#b9e9d8"))
	_label("실측: Window 렌더 프레임 노출 수, 원화 alpha 크기, 발 기준선 · 골반/포니테일 결합과 팝은 아래 캡처에서 시각 판정", Vector2(26, 101), 13, Color("#d3dbe6"))
	_caption = _label("", Vector2(660, 285), 18, Color.WHITE)
	_caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_caption.size = Vector2(600, 32)
	var floor := ColorRect.new()
	floor.position = Vector2(695, 760)
	floor.size = Vector2(530, 3)
	floor.color = Color("#6b7788")
	_canvas.add_child(floor)
	_sprite = Sprite2D.new()
	_sprite.name = "UnapprovedRunStrideCandidate"
	_sprite.position = Vector2(960, 570)
	_sprite.scale = Vector2.ONE * DISPLAY_HEIGHT / 1254.0
	_sprite.texture = _v1
	_canvas.add_child(_sprite)
	# Candidate marker follows the visually planted right boot in v1. It is an
	# art-review annotation, not a collision or ground-contact measurement.
	_support_marker = _add_marker("SUPPORT CANDIDATE", Vector2(1111, 758), Color("#53edbd"))
	_edge_marker = _add_marker("ALPHA BOUNDS CENTER", Vector2(1120, 768), Color("#ffd75e"))
func _measure_live_loop() -> void:
	# Let the displayed candidate repeat while counting actual post-draw frames.
	# A solo key drawing has no art-derived alternating stride or stride period.
	var start_usec := Time.get_ticks_usec()
	var cycle_index := 0
	var rendered_frames := 0
	var per_source_frames: Array[int] = []
	for _i in range(_source_frame_count):
		per_source_frames.append(0)
	while Time.get_ticks_usec() - start_usec < int(_loop_period_seconds * 2000000.0):
		var elapsed := float(Time.get_ticks_usec() - start_usec) / 1000000.0
		var phase := int(floor(elapsed / PHASE_SECONDS)) % _source_frame_count
		_sprite.texture = _source_frames[phase]
		_sprite.flip_h = phase == 1 and _v2 == null
		await process_frame
		await RenderingServer.frame_post_draw
		per_source_frames[phase] += 1
		rendered_frames += 1
		cycle_index = int(floor(elapsed / _loop_period_seconds))
	var measured_seconds := float(Time.get_ticks_usec() - start_usec) / 1000000.0
	_status.text = "v1 %d장 / 실렌더 %d프레임 · 관측 %.3fs · 재생 cadence %.3fs%s · v2 %s" % [
		_source_frame_count, rendered_frames, measured_seconds, _loop_period_seconds,
		"(두 원화 주기)" if _v2 != null else "(v1 반복 미리보기; 실제 보폭 주기 미판정)",
		"미확보" if _v2 == null else "후보/미승인",
	]
	print("LIVE_LOOP source_frames=%d rendered_frames=%d per_source_rendered=%s observed_seconds=%.4f preview_period_seconds=%.4f stride_period_status=%s observed_cycles=%.2f measured_cycle_period_seconds=%.4f" % [
		_source_frame_count, rendered_frames, str(per_source_frames), measured_seconds, _loop_period_seconds,
		"measured_from_two_art_drawings" if _v2 != null else "not_derivable_from_single_drawing", measured_seconds / _loop_period_seconds, measured_seconds / maxf(1.0, floor(measured_seconds / _loop_period_seconds)),
	])

func _capture_review_states() -> void:
	for index in range(CAPTIONS.size()):
		_caption.text = CAPTIONS[index]
		_sprite.texture = _v2 if index in [1, 3] and _v2 != null else _v1
		_sprite.flip_h = index in [2, 3, 7]
		if _v2 == null:
			_sprite.flip_h = index in [2, 3, 7]
		_sprite.visible = true
		_sprite.position.x = 960.0 + (36.0 if index == 0 else (-36.0 if index == 2 else 0.0))
		var marker_support_x := 1090.0 if _sprite.texture == _v1 else 1168.0
		var marker_support_y := 1200.0 if _sprite.texture == _v1 else 1225.0
		if _sprite.flip_h:
			marker_support_x = 1254.0 - marker_support_x
		_support_marker.position = _sprite.position + (Vector2(marker_support_x, marker_support_y) - Vector2(627, 627)) * _sprite.scale.x - Vector2(5, 5)
		var marker_bounds := _v1_bounds if _sprite.texture == _v1 else _v2_bounds
		var edge_point := Vector2(marker_bounds.position.x + marker_bounds.size.x / 2, marker_bounds.end.y - 1)
		if _sprite.flip_h:
			edge_point.x = 1254.0 - edge_point.x
		_edge_marker.position = _sprite.position + (edge_point - Vector2(627, 627)) * _sprite.scale.x - Vector2(5, 5)
		var floor_marker := _label("mint dot: support candidate · yellow dot: alpha-bounds lower-center reference", Vector2(735, 310), 12, Color("#b9e9d8"))
		if index == 4:
			floor_marker.text = "mint dot: candidate support · yellow dot: alpha-bounds lower-center"
		elif index == 5:
			floor_marker.text = "mint dot: candidate support · yellow dot: alpha-bounds lower-center"
		elif index == 6:
			floor_marker.text = "mint dot: candidate support · yellow dot: alpha-bounds lower-center"
		elif index >= 7:
			floor_marker.text = "mint dot: candidate support · yellow dot: alpha-bounds lower-center"
		var frame_count := await _hold_and_count(0.18)
		var bounds_for_label := _v1_bounds if _sprite.texture == _v1 else _v2_bounds
		var meta_label := _label("Window 렌더 %d회 / 180ms · alpha 높이 %.1f%%" % [frame_count, 100.0 * float(bounds_for_label.size.y) / 1254.0], Vector2(735, 332), 12, Color("#d3dbe6"))
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image == null or image.get_size() != VIEW_SIZE:
			_fail("실제 Window 프레임 캡처를 읽지 못했습니다: state=%d" % index)
			return
		var crop := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
		crop.blit_rect(image, Rect2i(Vector2i(640, 280), TILE_SIZE), Vector2i.ZERO)
		_tile_images.append(crop)
		var bounds := _v1_bounds if _sprite.texture == _v1 else _v2_bounds
		var source_size := float(bounds.size.y) * DISPLAY_HEIGHT / 1254.0
		var support_candidate_x := 1090.0 if _sprite.texture == _v1 else 1168.0
		var support_candidate_y := 1200.0 if _sprite.texture == _v1 else 1225.0
		if _sprite.flip_h:
			support_candidate_x = 1254.0 - support_candidate_x
		var alpha_bounds_center_x := float(bounds.position.x + bounds.size.x / 2)
		if _sprite.flip_h:
			alpha_bounds_center_x = 1254.0 - alpha_bounds_center_x
		var support_center_dx := absf(alpha_bounds_center_x - support_candidate_x) * DISPLAY_HEIGHT / 1254.0
		var support_floor_delta := absf(570.0 + (support_candidate_y - 627.0) * DISPLAY_HEIGHT / 1254.0 - 760.0)
		var metric := {"state": CAPTIONS[index], "rendered_frames": frame_count, "source_alpha_bounds": bounds,
			"displayed_alpha_height_px": source_size, "support_candidate_source_x": support_candidate_x, "support_candidate_source_y": support_candidate_y,
			"alpha_bounds_center_x": alpha_bounds_center_x, "bbox_center_to_support_dx_px": support_center_dx, "support_to_floor_delta_px": support_floor_delta}
		_metrics.append(metric)
		print("CAPTURE state=%s source_frames=%d rendered_frames=%d alpha_bounds=%s alpha_height_screen_px=%.1f support_candidate_source_x=%.1f alpha_bounds_center_x=%.1f bbox_to_support_dx_px=%.1f support_floor_delta_y_px=%.1f flip_h=%s" % [
			CAPTIONS[index], _source_frame_count, frame_count, str(bounds), source_size, support_candidate_x, alpha_bounds_center_x, support_center_dx, support_floor_delta, str(_sprite.flip_h),
		])
		floor_marker.queue_free()
		meta_label.queue_free()
		await process_frame
func _hold_and_count(seconds: float) -> int:
	var deadline := Time.get_ticks_usec() + roundi(seconds * 1000000.0)
	var count := 0
	while Time.get_ticks_usec() < deadline:
		await process_frame
		await RenderingServer.frame_post_draw
		count += 1
	return count

func _add_marker(marker_text: String, point: Vector2, color: Color) -> ColorRect:
	var dot := ColorRect.new()
	dot.position = point - Vector2(5, 5)
	dot.size = Vector2(10, 10)
	dot.color = color
	_canvas.add_child(dot)
	dot.z_index = 5
	return dot

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

func _load_texture(path: String) -> Texture2D:
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _report() -> void:
	var height_ratio := float(_v1_bounds.size.y) / 1254.0
	print("ART_METRICS v1_canvas=1254x1254 alpha_bounds=%s width_screen_px=%.1f height_screen_px=%.1f; v2_alpha_bounds=%s width_screen_px=%.1f height_screen_px=%.1f" % [str(_v1_bounds), float(_v1_bounds.size.x) * DISPLAY_HEIGHT / 1254.0, height_ratio * DISPLAY_HEIGHT, str(_v2_bounds), float(_v2_bounds.size.x) * DISPLAY_HEIGHT / 1254.0, float(_v2_bounds.size.y) * DISPLAY_HEIGHT / 1254.0])
	print("CONTACT_REVIEW support candidate is a human visual annotation; transparent alpha boundary and lowest alpha row are not treated as the planted foot")
	print("QUALITATIVE_REVIEW inspect pelvis-to-torso continuity, ponytail attachment, silhouette scale consistency, and visual pop across the captured loop boundary")
	if _v2 == null:
		print("GATE v2=미확보; 보폭 주기/반대발 접지/양원화 루프 경계 통과 여부=판정 불가; v1 solo review only")
	print("GATE player_or_manifest_integration=none approval=review-only")

func _fail(message: String) -> void:
	push_error("player_run_cycle_review: " + message)
	quit(1)















