extends SceneTree
"""Independent real-Window comparison of the two isolated run-stride safe drawings."""

const V1_PATH := "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png"
const V2_PATH := "res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png"
const IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const OUTPUT_PATH := "res://assets/art/review/player_run_stride_opposition_strip.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const TILE_SIZE := Vector2i(640, 500)
const OUTPUT_SIZE := Vector2i(1920, 1500)
const DISPLAY_SCALE := 0.327
const CAPTIONS := [
	"RIGHT · A / v1 safe",
	"RIGHT · B / v2 safe",
	"RIGHT · A / loop return",
	"LEFT · A / mirrored v1",
	"LEFT · B / mirrored v2",
	"LEFT · A / loop return",
	"RUN A → STOP / v8 idle",
	"STOP → RUN A",
	"RUN B → RUN A / loop boundary",
]

var _canvas: Control
var _sprite: Sprite2D
var _caption: Label
var _support_marker: ColorRect
var _bounds_marker: ColorRect
var _v1: Texture2D
var _v2: Texture2D
var _idle: Texture2D
var _tiles: Array[Image] = []
var _render_counts: Array[int] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Godot Window 캡처가 필요합니다. headless 실행은 통과로 처리하지 않습니다.")
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
	_idle = _load_texture(IDLE_PATH)
	if _v1 == null or _v2 == null or _idle == null:
		_fail("v1/v2 safe 또는 v8 idle 입력 원화를 읽을 수 없습니다.")
		return
	if _v1.get_size() != Vector2(1254, 1254) or _v2.get_size() != Vector2(1254, 1254):
		_fail("두 run safe 원화의 캔버스가 1254×1254가 아닙니다.")
		return
	_build_window()
	for _frame in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	var states := [
		{"texture": _v1, "flip": false}, {"texture": _v2, "flip": false}, {"texture": _v1, "flip": false},
		{"texture": _v1, "flip": true}, {"texture": _v2, "flip": true}, {"texture": _v1, "flip": true},
		{"texture": _v1, "flip": false}, {"texture": _idle, "flip": false}, {"texture": _v1, "flip": false},
		{"texture": _idle, "flip": false}, {"texture": _v1, "flip": false},
		{"texture": _v2, "flip": false}, {"texture": _v1, "flip": false},
	]
	var state_captures := [0, 1, 2, 3, 4, 5, 6, 7, 11]
	for i in range(states.size()):
		var state: Dictionary = states[i]
		_sprite.texture = state.texture
		_sprite.flip_h = state.flip
		_update_markers(state.texture == _v2, state.flip)
		_caption.text = CAPTIONS[state_captures.find(i)] if state_captures.has(i) else "TRANSITION SAMPLE · %s" % ("IDLE" if state.texture == _idle else "RUN A")
		_caption.position = Vector2(650, 294)
		_caption.add_theme_font_size_override("font_size", 19)
		var frame_count := await _hold_and_count(0.14 if i < 6 else 0.18)
		if state_captures.has(i):
			_render_counts.append(frame_count)
			var frame := root.get_texture().get_image()
			if frame == null or frame.get_size() != WINDOW_SIZE:
				_fail("실제 Window의 post-draw 프레임 읽기 실패: state=%d" % i)
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
	print("RUN_WINDOW_CAPTURE size=%s states=%d render_frames_per_tile=%s output=%s" % [str(DisplayServer.window_get_size()), _tiles.size(), str(_render_counts), OUTPUT_PATH])
	print("RUN_OPPOSITION_GATE result=duplicate_pose_risk both_support_right_boot=true player_or_manifest_integration=none approval=not_performed")
	quit(0)

func _build_window() -> void:
	_canvas = Control.new()
	_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_canvas)
	var background := ColorRect.new()
	background.color = Color("#111821")
	background.size = Vector2(WINDOW_SIZE)
	_canvas.add_child(background)
	_caption = _label("", Vector2(24, 16), 24, Color.WHITE)
	_caption.size = Vector2(1870, 34)
	_label("독립 보폭 판정 · 민트=같은 오른쪽 부츠 지지 후보 · 노랑=alpha 하단 중심 참고 · 바닥선은 시각 가이드", Vector2(26, 54), 14, Color("#b9e9d8"))
	_label("실제 Window post-draw 캡처 · 표시 배율 고정 · 본편 미연결 · 후보 미승인", Vector2(26, 78), 14, Color("#ffd68a"))
	var floor_line := ColorRect.new()
	floor_line.position = Vector2(690, 742)
	floor_line.size = Vector2(540, 3)
	floor_line.color = Color("#7b8795")
	_canvas.add_child(floor_line)
	_sprite = Sprite2D.new()
	_sprite.position = Vector2(960, 550)
	_sprite.scale = Vector2.ONE * DISPLAY_SCALE
	_canvas.add_child(_sprite)
	_support_marker = _marker("SUPPORT?", Color("#53edbd"))
	_bounds_marker = _marker("BOUNDS", Color("#ffd75e"))

func _marker(text: String, color: Color) -> ColorRect:
	var mark := ColorRect.new()
	mark.name = text
	mark.color = color
	mark.size = Vector2(10, 10)
	mark.z_index = 20
	_canvas.add_child(mark)
	var tag := _label(text, Vector2.ZERO, 10, color)
	tag.z_index = 21
	mark.set_meta("tag", tag)
	return mark

func _update_markers(is_v2: bool, flip: bool) -> void:
	var support := Vector2(1168, 1225) if is_v2 else Vector2(1090, 1200)
	var bounds_center := Vector2(627, 627)
	var bounds_image := _v2.get_image() if is_v2 else _v1.get_image()
	var bounds := _alpha_bounds(bounds_image, 0.05)
	var edge := Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.end.y - 1)
	if flip:
		support.x = 1254.0 - support.x
		edge.x = 1254.0 - edge.x
	_support_marker.position = _sprite.position + (support - bounds_center) * DISPLAY_SCALE - _support_marker.size * 0.5
	_bounds_marker.position = _sprite.position + (edge - bounds_center) * DISPLAY_SCALE - _bounds_marker.size * 0.5
	_support_marker.get_meta("tag").position = _support_marker.position + Vector2(-30, -20)
	_bounds_marker.get_meta("tag").position = _bounds_marker.position + Vector2(-30, -20)

func _label(value: String, position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_canvas.add_child(label)
	return label

func _hold_and_count(seconds: float) -> int:
	var start := Time.get_ticks_usec()
	var count := 0
	while Time.get_ticks_usec() - start < int(seconds * 1000000.0):
		await process_frame
		await RenderingServer.frame_post_draw
		count += 1
	return count

func _print_metrics() -> void:
	var image_a := _v1.get_image()
	var image_b := _v2.get_image()
	var a := _alpha_bounds(image_a, 0.05)
	var b := _alpha_bounds(image_b, 0.05)
	var a_height := float(a.size.y) * DISPLAY_SCALE
	var b_height := float(b.size.y) * DISPLAY_SCALE
	var support_y_a := (1200.0 - 627.0) * DISPLAY_SCALE
	var support_y_b := (1225.0 - 627.0) * DISPLAY_SCALE
	var support_x_a := (1090.0 - 627.0) * DISPLAY_SCALE
	var support_x_b := (1168.0 - 627.0) * DISPLAY_SCALE
	print("SOURCE v1_safe path=%s alpha_bounds=%s display_alpha=%.1fx%.1f support_candidate=right_boot(1090,1200)" % [V1_PATH, str(a), float(a.size.x) * DISPLAY_SCALE, a_height])
	print("SOURCE v2_safe path=%s alpha_bounds=%s display_alpha=%.1fx%.1f support_candidate=right_boot(1168,1225)" % [V2_PATH, str(b), float(b.size.x) * DISPLAY_SCALE, b_height])
	print("POSE_COMPARE legs=both_right_boot_forward_left_boot_rear_kicked pelvis=both_forward_lean_same_rotation arm_cross=both_left_arm_reaches_forward_right_arm_drives_back support=both_right_boot_candidate conclusion=duplicate_pose_risk")
	print("MOTION_METRICS fixed_display_scale=%.3f alpha_height_delta=%.2fpx candidate_support_delta=(%.2f,%.2f)px stop_pose=v8_idle height_delta_vs_A=%.2fpx rendered_frames_per_capture=%s" % [DISPLAY_SCALE, absf(a_height - b_height), support_x_b - support_x_a, support_y_b - support_y_a, absf(1115.0 * DISPLAY_SCALE - a_height), str(_render_counts)])

func _load_texture(path: String) -> Texture2D:
	if not ResourceLoader.exists(path):
		return null
	var texture := load(path) as Texture2D
	return texture

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

func _fail(message: String) -> void:
	push_error("player_run_stride_opposition: " + message)
	quit(1)
