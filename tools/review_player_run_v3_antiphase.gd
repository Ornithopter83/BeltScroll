extends SceneTree
"""Reviews requested run v3 acquisition against the retained v1/v2 duplicate-pose gate."""

const V1_PATH := "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png"
const V2_PATH := "res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png"
const PLAYER_DIR := "res://assets/art/player"
const OUTPUT_PATH := "res://assets/art/review/player_run_v3_antiphase_strip.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const TILE_SIZE := Vector2i(640, 500)
const OUTPUT_SIZE := Vector2i(1920, 1500)
const DISPLAY_SCALE := 0.4469274 # Match PlayerArt scale in scenes/player/player.tscn.

var _canvas: Control
var _sprite: Sprite2D
var _caption: Label
var _status: Label
var _missing_label: Label
var _support_marker: ColorRect
var _bounds_marker: ColorRect
var _v1: Texture2D
var _v2: Texture2D
var _v3: Texture2D
var _v3_path := ""
var _tiles: Array[Image] = []
var _render_counts: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Godot Window 캡처가 필요합니다. headless 결과는 증거로 처리하지 않습니다.")
		return
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(WINDOW_SIZE)
	for _frame in range(3):
		await process_frame
	if root.size != WINDOW_SIZE or DisplayServer.window_get_size() != WINDOW_SIZE:
		_fail("1920×1080 Godot Window 설정 실패: viewport=%s window=%s" % [str(root.size), str(DisplayServer.window_get_size())])
		return
	_v1 = _load_texture(V1_PATH)
	_v2 = _load_texture(V2_PATH)
	_v3_path = _find_v3()
	_v3 = _load_texture(_v3_path) if not _v3_path.is_empty() else null
	if _v1 == null or _v2 == null:
		_fail("기존 #70 v1/v2 safe 원화를 모두 읽어야 중복 판정을 보존할 수 있습니다.")
		return
	if _v1.get_size() != Vector2(1254, 1254) or _v2.get_size() != Vector2(1254, 1254):
		_fail("#70 v1/v2 safe 원화가 1254×1254가 아닙니다.")
		return
	if _v3 != null and _v3.get_size() != Vector2(1254, 1254):
		_fail("v3 후보 캔버스가 1254×1254가 아닙니다: " + _v3_path)
		return
	_build_window()
	for _frame in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	var v3_caption := "v3 candidate · pending visual review" if _v3 != null else "v3 NOT ACQUIRED"
	var states := [
		{"texture": _v1, "flip": false, "missing": false, "support": true, "caption":"RIGHT · v1 safe before"},
		{"texture": _v3, "flip": false, "missing": _v3 == null, "support": false, "caption":"RIGHT · " + v3_caption},
		{"texture": _v1, "flip": false, "missing": false, "support": true, "caption":"RIGHT · v1 safe return"},
		{"texture": _v1, "flip": true, "missing": false, "support": true, "caption":"LEFT · v1 safe before"},
		{"texture": _v3, "flip": true, "missing": _v3 == null, "support": false, "caption":"LEFT · " + v3_caption},
		{"texture": _v1, "flip": true, "missing": false, "support": true, "caption":"LEFT · v1 safe return"},
		{"texture": _v1, "flip": false, "missing": false, "support": true, "caption":"#70 retained · v1 safe"},
		{"texture": _v2, "flip": false, "missing": false, "support": true, "caption":"#70 retained · v2 safe"},
		{"texture": _v1, "flip": false, "missing": false, "support": true, "caption":"#70 retained · v1 safe return"},
	]
	for i in range(states.size()):
		var state: Dictionary = states[i]
		var missing: bool = state.missing
		_sprite.visible = not missing
		_support_marker.visible = not missing and bool(state.support)
		_bounds_marker.visible = not missing
		_support_marker.get_meta("tag").visible = not missing
		_bounds_marker.get_meta("tag").visible = not missing
		_missing_label.visible = missing
		if not missing:
			_sprite.texture = state.texture
			_sprite.flip_h = state.flip
			_update_markers(state.texture, state.flip, bool(state.support))
		_caption.text = state.caption
		_status.text = ("v3 후보 미승인 · #70: v1/v2 같은 오른쪽 앞 부츠 지지 후보 · 본편 미연결" if _v3 != null else "v3 미확보 · #70: v1/v2 같은 오른쪽 앞 부츠 지지 후보 · 본편 미연결 · 승인 안 함")
		var frame_count := await _hold_and_count(0.16)
		_render_counts.append(frame_count)
		var frame := root.get_texture().get_image()
		if frame == null or frame.get_size() != WINDOW_SIZE:
			_fail("실제 Window post-draw 프레임 읽기 실패: state=%d" % i)
			return
		var crop := Image.create(TILE_SIZE.x, TILE_SIZE.y, false, Image.FORMAT_RGBA8)
		crop.blit_rect(frame, Rect2i(Vector2i(640, 290), TILE_SIZE), Vector2i.ZERO)
		_tiles.append(crop)
	var board := Image.create(OUTPUT_SIZE.x, OUTPUT_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("#111821"))
	for i in range(_tiles.size()):
		board.blit_rect(_tiles[i], Rect2i(Vector2i.ZERO, TILE_SIZE), Vector2i((i % 3) * TILE_SIZE.x, (i / 3) * TILE_SIZE.y))
	var output_file := ProjectSettings.globalize_path(OUTPUT_PATH)
	var dir_error := DirAccess.make_dir_recursive_absolute(output_file.get_base_dir())
	if dir_error != OK:
		_fail("출력 폴더 생성 실패: " + error_string(dir_error))
		return
	var save_error := board.save_png(output_file)
	if save_error != OK:
		_fail("검수 스트립 PNG 저장 실패: " + error_string(save_error))
		return
	var check := Image.new()
	if check.load(output_file) != OK or check.get_size() != OUTPUT_SIZE:
		_fail("저장한 실제 Window 캡처 스트립 검증 실패")
		return
	_print_metrics()
	print("RUN_V3_GATE v3=%s candidate=%s retained_v1_v2=duplicate_pose_risk player_or_manifest_integration=none approval=not_performed" % ["acquired_pending_visual_review" if _v3 != null else "not_acquired", _v3_path if _v3 != null else "none"])
	print("RUN_WINDOW_CAPTURE size=%s states=%d render_frames_per_tile=%s output=%s" % [str(DisplayServer.window_get_size()), _tiles.size(), str(_render_counts), OUTPUT_PATH])
	quit(0)

func _find_v3() -> String:
	var dir := DirAccess.open(PLAYER_DIR)
	if dir == null:
		return ""
	dir.list_dir_begin()
	var name := dir.get_next()
	while not name.is_empty():
		if not dir.current_is_dir() and name.to_lower().ends_with(".png") and name.to_lower().contains("run_stride_v3"):
			dir.list_dir_end()
			return PLAYER_DIR + "/" + name
		name = dir.get_next()
	dir.list_dir_end()
	return ""

func _build_window() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_canvas)
	var background := ColorRect.new()
	background.color = Color("#111821")
	background.size = Vector2(WINDOW_SIZE)
	_canvas.add_child(background)
	_label("RUN v3 ANTIPHASE · 격리 검수 · v3 원화 미확보", Vector2(24, 12), 24, Color.WHITE)
	_status = _label("", Vector2(26, 47), 16, Color("#ffd68a"))
	_label("민트=사람이 지정한 지지발 후보 · 노랑=alpha 하단 중심 참고 · 원화 부재는 검정 카드로 표시", Vector2(26, 72), 13, Color("#b9e9d8"))
	_label("1920×1080 실제 Window post-draw · PlayerArt scale 0.4469274 · 160ms 보유 후 캡처", Vector2(26, 93), 13, Color("#d3dbe6"))
	_caption = _label("", Vector2(650, 294), 19, Color.WHITE)
	_caption.size = Vector2(620, 32)
	_missing_label = _label("v3 원화가 없습니다\n반대 보폭 확인 불가", Vector2(735, 475), 28, Color("#ffd68a"))
	_missing_label.size = Vector2(450, 100)
	_missing_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_missing_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_missing_label.visible = false
	var floor_line := ColorRect.new()
	floor_line.position = Vector2(690, 772)
	floor_line.size = Vector2(540, 3)
	floor_line.color = Color("#7b8795")
	_canvas.add_child(floor_line)
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(960, 550)
	_sprite.scale = Vector2.ONE * DISPLAY_SCALE
	_canvas.add_child(_sprite)
	_support_marker = _marker("SUPPORT?", Color("#53edbd"))
	_bounds_marker = _marker("ALPHA", Color("#ffd75e"))

func _marker(value: String, color: Color) -> ColorRect:
	var mark := ColorRect.new()
	mark.color = color
	mark.size = Vector2(10, 10)
	mark.z_index = 20
	_canvas.add_child(mark)
	var tag := _label(value, Vector2.ZERO, 10, color)
	tag.z_index = 21
	mark.set_meta("tag", tag)
	return mark

func _update_markers(texture: Texture2D, flip: bool, support_known: bool) -> void:
	var is_v2 := texture == _v2
	var source_image := texture.get_image()
	var support_x := 1168 if is_v2 else 1090
	var support := Vector2(support_x, _foot_y_near_x(source_image, support_x))
	var bounds := _alpha_bounds(source_image, 0.05)
	var edge := Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.end.y - 1)
	if flip:
		support.x = 1254.0 - support.x
		edge.x = 1254.0 - edge.x
	_support_marker.visible = support_known
	_support_marker.position = _sprite.position + (support - Vector2(627, 627)) * DISPLAY_SCALE - _support_marker.size * 0.5
	_bounds_marker.position = _sprite.position + (edge - Vector2(627, 627)) * DISPLAY_SCALE - _bounds_marker.size * 0.5
	_support_marker.get_meta("tag").visible = support_known
	_support_marker.get_meta("tag").position = _support_marker.position + Vector2(-34, -20)
	_bounds_marker.get_meta("tag").position = _bounds_marker.position + Vector2(-20, -20)

func _hold_and_count(seconds: float) -> int:
	var end := Time.get_ticks_usec() + roundi(seconds * 1000000.0)
	var count := 0
	while Time.get_ticks_usec() < end:
		await process_frame
		await RenderingServer.frame_post_draw
		count += 1
	return count

func _print_metrics() -> void:
	var a := _alpha_bounds(_v1.get_image(), 0.05)
	var b := _alpha_bounds(_v2.get_image(), 0.05)
	print("SOURCE v1_safe alpha_bounds=%s display_alpha=%.1fx%.1f right_support_candidate=(1090,1200)" % [str(a), float(a.size.x) * DISPLAY_SCALE, float(a.size.y) * DISPLAY_SCALE])
	print("SOURCE v2_safe alpha_bounds=%s display_alpha=%.1fx%.1f right_support_candidate=(1168,1225)" % [str(b), float(b.size.x) * DISPLAY_SCALE, float(b.size.y) * DISPLAY_SCALE])
	if _v3 != null:
		var c := _alpha_bounds(_v3.get_image(), 0.05)
		var v1_anchor := Vector2(a.position.x + a.size.x * 0.5, a.end.y - 1)
		var v3_anchor := Vector2(c.position.x + c.size.x * 0.5, c.end.y - 1)
		var anchor_delta := v3_anchor - v1_anchor
		print("SOURCE v3_candidate path=%s alpha_bounds=%s display_alpha=%.1fx%.1f support_candidate=unmarked approval=pending" % [_v3_path, str(c), float(c.size.x) * DISPLAY_SCALE, float(c.size.y) * DISPLAY_SCALE])
		print("ANCHOR_COMPARE alpha_bottom_center v1=%s v3=%s delta_source=%s delta_display=%s" % [str(v1_anchor), str(v3_anchor), str(anchor_delta), str(anchor_delta * DISPLAY_SCALE)])
	print("POSE_COMPARE #70 legs=right_forward_left_rear_kicked arms=left_forward_right_back pelvis=forward_lean same_support=right_boot candidate conclusion=duplicate_pose_risk")

func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D

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

func _foot_y_near_x(image: Image, x: int) -> int:
	for y in range(image.get_height() - 1, -1, -1):
		for candidate_x in range(maxi(0, x - 36), mini(image.get_width(), x + 37)):
			if image.get_pixel(candidate_x, y).a >= 0.05:
				return y
	return image.get_height() - 1

func _label(value: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	_canvas.add_child(label)
	return label

func _fail(message: String) -> void:
	push_error("player_run_v3_antiphase: " + message)
	quit(1)
