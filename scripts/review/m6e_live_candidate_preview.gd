extends Window
"""Approval-only M6E preview. This scene never registers art with gameplay."""

const WINDOW_SIZE := Vector2i(1920, 1080)
const STAGE_PATH := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const V8_PATH := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const DARK_SHEET_PATH := "res://assets/art/player/elven_fighter_dark_fantasy_attack1_sheet_v1_candidate_1254x1254.png"
const OUTPUT_PATH := "res://assets/art/review/m6e_live_candidate_preview.png"
const ALPHA_THRESHOLD := 0.05
const TARGET_ART_HEIGHT := 192.0
const FLOOR_Y := 850.0
const FRAME_DURATION := 0.12
const FRAME_NAMES := ["좌상 · 가드", "우상 · 준비", "좌하 · 펀치", "우하 · 가드"]

var _frames: Array[Dictionary] = []
var _frame_index := 0
var _elapsed := 0.0
var _playing := true
var _looping := true
var _stage: TextureRect
var _v8_sprite: Sprite2D
var _candidate_sprite: Sprite2D
var _ground_marker: ColorRect
var _ground_vertical: ColorRect
var _cell_edges: Array[ColorRect] = []
var _frame_label: Label
var _defect_label: Label
var _play_button: Button
var _loop_button: Button
var _capture_mode := false

func _ready() -> void:
	mode = Window.MODE_WINDOWED
	size = WINDOW_SIZE
	min_size = Vector2i(1280, 720)
	_build_frames()
	_build_review()
	_update_candidate()
	_update_labels()
	_capture_mode = OS.get_cmdline_user_args().has("--m6e-review-capture")
	if _capture_mode:
		_playing = false
		_update_labels()
		_capture_board.call_deferred()

func _process(delta: float) -> void:
	if not _playing or _frames.size() != 4:
		return
	_elapsed += delta
	if _elapsed >= FRAME_DURATION:
		_elapsed = fmod(_elapsed, FRAME_DURATION)
		_step_frame(1)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			toggle_playback()
		KEY_LEFT:
			_step_frame(-1)
		KEY_RIGHT:
			_step_frame(1)
		KEY_R:
			_looping = not _looping
			_update_labels()
		KEY_HOME:
			_frame_index = 0
			_elapsed = 0.0
			_update_candidate()
			_update_labels()
		_:
			return
	get_viewport().set_input_as_handled()

func toggle_playback() -> void:
	_playing = not _playing
	_elapsed = 0.0
	_update_labels()

func _step_frame(direction: int) -> void:
	if _frames.size() != 4:
		return
	var next := _frame_index + direction
	if _looping:
		next = posmod(next, _frames.size())
	else:
		next = clampi(next, 0, _frames.size() - 1)
	_frame_index = next
	_elapsed = 0.0
	_update_candidate()
	_update_labels()

func _build_frames() -> void:
	var sheet := _load_png(DARK_SHEET_PATH)
	if sheet == null or sheet.get_size() != Vector2i(1254, 1254):
		push_error("M6E 후보 시트를 읽을 수 없거나 크기가 예상과 다릅니다: " + DARK_SHEET_PATH)
		return
	var cell_size := Vector2i(sheet.get_width() / 2, sheet.get_height() / 2)
	var previous_image: Image = null
	for index in range(4):
		var origin := Vector2i(index % 2, index / 2) * cell_size
		var image := sheet.get_region(Rect2i(origin, cell_size))
		var bounds := _alpha_bounds(image)
		_frames.append({
			"image": image,
			"texture": ImageTexture.create_from_image(image),
			"bounds": bounds,
			"anchor": _bottom_alpha_anchor(image, bounds),
			"edge": _edge_alpha_counts(image),
			"changed": _changed_pixels(previous_image, image) if previous_image != null else -1,
			"order": FRAME_NAMES[index],
			"origin": origin
		})
		previous_image = image

func _build_review() -> void:
	var stage_texture := load(STAGE_PATH) as Texture2D
	if stage_texture == null:
		push_error("Forest Ruins 실제 배경을 읽지 못했습니다: " + STAGE_PATH)
		return
	var root_layer := Control.new()
	root_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root_layer)
	_stage = TextureRect.new()
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage.texture = stage_texture
	_stage.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_stage.stretch_mode = TextureRect.STRETCH_SCALE
	_stage.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	root_layer.add_child(_stage)
	var veil := ColorRect.new()
	veil.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	veil.color = Color(0.015, 0.025, 0.035, 0.45)
	root_layer.add_child(veil)
	var header := _panel(root_layer, Rect2(20, 18, 1880, 150), Color("#101820", 0.94), Color("#b39761"))
	_label(header, "M6E  /  전투 후보 실시간 검수", Vector2(26, 14), 31, Color("#f1dfb4"))
	_label(header, "실제 Forest Ruins 스테이지 · 게임 표시 높이 192px · 발 기준선 y=850 · 격리 씬 · 승인 미수행", Vector2(28, 58), 17, Color("#d7dfdd"))
	_label(header, "← / → 프레임별 확인     Space 재생·일시정지     R 반복 전환     Home 첫 프레임", Vector2(28, 91), 17, Color("#bce4d8"))
	_label(header, "좌측: 현행 v8 원화 고정     우측: M6D 다크 판타지 후보 4셀을 원본 순서로 120ms씩 재생", Vector2(28, 119), 15, Color("#e3c98d"))
	_panel(root_layer, Rect2(20, 180, 930, 865), Color("#18242c", 0.32), Color("#c3a66c"))
	_panel(root_layer, Rect2(970, 180, 930, 865), Color("#18242c", 0.32), Color("#65c9b0"))
	_label(root_layer, "현행 v8 · 비교 기준", Vector2(48, 194), 23, Color("#f5e4bd"))
	_label(root_layer, "elven_fighter_reference_v8_1254x1254.png", Vector2(48, 226), 14, Color("#e1e5df"))
	_label(root_layer, "다크 판타지 리디자인 · M6D 미승인 2×2", Vector2(998, 194), 23, Color("#d1f0e5"))
	_label(root_layer, "attack1_sheet_v1_candidate · 좌상 → 우상 → 좌하 → 우하", Vector2(998, 226), 14, Color("#e1e5df"))
	var floor := ColorRect.new()
	floor.position = Vector2(58, FLOOR_Y)
	floor.size = Vector2(1804, 3)
	floor.color = Color("#ff7167")
	root_layer.add_child(floor)
	_label(root_layer, "공통 발 기준선", Vector2(60, FLOOR_Y + 8), 13, Color("#ffd0bd"))
	_label(root_layer, "공통 발 기준선", Vector2(1795, FLOOR_Y + 8), 13, Color("#ffd0bd"))
	_v8_sprite = Sprite2D.new()
	_v8_sprite.name = "ApprovalReferenceV8"
	_v8_sprite.centered = true
	_v8_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root_layer.add_child(_v8_sprite)
	var v8_image := _load_png(V8_PATH)
	if v8_image != null:
		var v8_bounds := _alpha_bounds(v8_image)
		_v8_sprite.texture = ImageTexture.create_from_image(v8_image)
		_v8_sprite.scale = Vector2.ONE * TARGET_ART_HEIGHT / float(maxi(v8_bounds.size.y, 1))
		_v8_sprite.position = _sprite_origin_for(v8_bounds, _v8_sprite.scale.x, Vector2(485, FLOOR_Y))
	else:
		push_error("현행 v8 비교 원화를 읽지 못했습니다: " + V8_PATH)
	_candidate_sprite = Sprite2D.new()
	_candidate_sprite.name = "UnapprovedDarkFantasyCandidateFrame"
	_candidate_sprite.centered = true
	_candidate_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	root_layer.add_child(_candidate_sprite)
	_ground_marker = ColorRect.new()
	_ground_marker.color = Color("#51f0c0")
	root_layer.add_child(_ground_marker)
	_ground_vertical = ColorRect.new()
	_ground_vertical.color = Color("#51f0c0")
	_ground_marker.add_child(_ground_vertical)
	for _i in range(4):
		var edge_mark := ColorRect.new()
		edge_mark.color = Color("#ff5e54")
		root_layer.add_child(edge_mark)
		_cell_edges.append(edge_mark)
	var edge_note := _label(root_layer, "빨강: 셀 경계 alpha 결함   민트: 하단 alpha 추정 (실제 지지발은 사람 확인)", Vector2(995, 875), 14, Color("#ffd68b"))
	edge_note.size = Vector2(870, 24)
	_frame_label = _label(root_layer, "", Vector2(995, 910), 18, Color("#ffffff"))
	_frame_label.size = Vector2(870, 26)
	_defect_label = _label(root_layer, "", Vector2(995, 941), 16, Color("#ffb6a5"))
	_defect_label.size = Vector2(870, 46)
	var controls := HBoxContainer.new()
	controls.position = Vector2(995, 1000)
	controls.add_theme_constant_override("separation", 12)
	root_layer.add_child(controls)
	var previous := Button.new()
	previous.text = "◀ 이전 프레임"
	previous.pressed.connect(_step_frame.bind(-1))
	controls.add_child(previous)
	_play_button = Button.new()
	_play_button.pressed.connect(toggle_playback)
	controls.add_child(_play_button)
	var next := Button.new()
	next.text = "다음 프레임 ▶"
	next.pressed.connect(_step_frame.bind(1))
	controls.add_child(next)
	_loop_button = Button.new()
	_loop_button.pressed.connect(func() -> void:
		_looping = not _looping
		_update_labels()
	)
	controls.add_child(_loop_button)
	_label(root_layer, "검수 전용 · 게임 등록 없음 · PlayerArt / manifest / allowlist / 전투 판정 미변경", Vector2(48, 1010), 15, Color("#f0dfbd"))

func _update_candidate() -> void:
	if _frames.is_empty() or _candidate_sprite == null:
		return
	var frame: Dictionary = _frames[_frame_index]
	var bounds: Rect2i = frame.bounds
	var scale := TARGET_ART_HEIGHT / float(maxi(bounds.size.y, 1))
	_candidate_sprite.texture = frame.texture
	_candidate_sprite.scale = Vector2.ONE * scale
	_candidate_sprite.position = _sprite_origin_for(bounds, scale, Vector2(1445, FLOOR_Y))
	var anchor: Vector2i = frame.anchor
	var anchor_at := _candidate_sprite.position + (Vector2(anchor) - Vector2(313.5, 313.5)) * scale
	_ground_marker.position = anchor_at - Vector2(13, 2)
	_ground_marker.size = Vector2(26, 4)
	_ground_vertical.position = Vector2(11, -11)
	_ground_vertical.size = Vector2(4, 26)
	var cell_top_left := _candidate_sprite.position - Vector2(313.5, 313.5) * scale
	var cell_extent := 627.0 * scale
	var border_width := 3.0
	var edge_rects := [
		Rect2(cell_top_left, Vector2(cell_extent, border_width)),
		Rect2(cell_top_left + Vector2(0, cell_extent - border_width), Vector2(cell_extent, border_width)),
		Rect2(cell_top_left, Vector2(border_width, cell_extent)),
		Rect2(cell_top_left + Vector2(cell_extent - border_width, 0), Vector2(border_width, cell_extent))
	]
	var edge: Dictionary = frame.edge
	var edge_keys := ["top", "bottom", "left", "right"]
	for i in range(4):
		var marker := _cell_edges[i]
		var rect: Rect2 = edge_rects[i]
		marker.position = rect.position
		marker.size = rect.size
		marker.visible = int(edge[edge_keys[i]]) > 0

func _update_labels() -> void:
	if _frame_label == null or _frames.is_empty():
		return
	var frame: Dictionary = _frames[_frame_index]
	var edge: Dictionary = frame.edge
	var edge_total := int(edge.top) + int(edge.bottom) + int(edge.left) + int(edge.right)
	_frame_label.text = "프레임 %d / 4 · %s · %s · 반복 %s" % [_frame_index + 1, frame.order, "재생 중" if _playing else "일시정지", "켜짐" if _looping else "꺼짐"]
	_defect_label.text = "프레임 변경: 직전 셀 대비 %s 픽셀 · alpha 경계 T/B/L/R %d/%d/%d/%d · %s\n접지 추정: 셀 좌표 %s · 민트 십자 = 하단 alpha · 빨강 선 = alpha 셀 경계" % ["기준" if int(frame.changed) < 0 else str(frame.changed), edge.top, edge.bottom, edge.left, edge.right, "경계 alpha 감지" if edge_total > 0 else "경계 alpha 없음", str(frame.anchor)]
	_defect_label.add_theme_color_override("font_color", Color("#ff897c") if edge_total > 0 else Color("#9fe2c9"))
	_play_button.text = "일시정지" if _playing else "재생"
	_loop_button.text = "반복: 켜짐" if _looping else "반복: 꺼짐"

func _sprite_origin_for(bounds: Rect2i, scale: float, ground: Vector2) -> Vector2:
	var image_center := Vector2(313.5, 313.5)
	var bottom_center := Vector2(bounds.position.x + bounds.size.x * 0.5, bounds.end.y - 1)
	return ground - (bottom_center - image_center) * scale

func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		return null
	return image

func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _bottom_alpha_anchor(image: Image, bounds: Rect2i) -> Vector2i:
	if bounds.size == Vector2i.ZERO:
		return Vector2i(-1, -1)
	for y in range(bounds.end.y - 1, bounds.position.y - 1, -1):
		var left := image.get_width()
		var right := -1
		for x in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				left = mini(left, x)
				right = maxi(right, x)
		if right >= left:
			return Vector2i(roundi((left + right) * 0.5), y)
	return Vector2i(-1, -1)

func _edge_alpha_counts(image: Image) -> Dictionary:
	var result := {"top": 0, "bottom": 0, "left": 0, "right": 0}
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a >= ALPHA_THRESHOLD:
			result.top += 1
		if image.get_pixel(x, image.get_height() - 1).a >= ALPHA_THRESHOLD:
			result.bottom += 1
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a >= ALPHA_THRESHOLD:
			result.left += 1
		if image.get_pixel(image.get_width() - 1, y).a >= ALPHA_THRESHOLD:
			result.right += 1
	return result

func _changed_pixels(previous: Image, current: Image) -> int:
	if previous.get_size() != current.get_size():
		return -1
	var changed := 0
	for y in range(current.get_height()):
		for x in range(current.get_width()):
			if not previous.get_pixel(x, y).is_equal_approx(current.get_pixel(x, y)):
				changed += 1
	return changed

func _panel(parent: Control, rect: Rect2, fill: Color, border: Color) -> Panel:
	var panel := Panel.new()
	panel.position = rect.position
	panel.size = rect.size
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	return panel

func _label(parent: Control, text: String, at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _capture_board() -> void:
	for _i in range(3):
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
	var image := get_texture().get_image()
	if image == null or image.is_empty():
		push_error("M6E 미리보기 보드 캡처 실패")
		get_tree().quit(1)
		return
	var path := ProjectSettings.globalize_path(OUTPUT_PATH)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if mkdir_error != OK:
		push_error("M6E 캡처 폴더 생성 실패: " + error_string(mkdir_error))
		get_tree().quit(1)
		return
	var save_error := image.save_png(path)
	if save_error != OK:
		push_error("M6E 캡처 저장 실패: " + error_string(save_error))
		get_tree().quit(1)
		return
	print("M6E_PREVIEW_CAPTURE path=%s size=%s isolated=true approval=not_performed" % [OUTPUT_PATH, str(image.get_size())])
	get_tree().quit(0)
