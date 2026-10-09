extends Node2D

const FRAME_SIZE := 192.0
const DISPLAY_SCALE := 3.0
const WINDOW_SIZE := Vector2i(1920, 1080)
const ALPHA_THRESHOLD := 0.05
const CAPTURE_PATH := "res://assets/art/review/player_candidate_motion_strip.png"
const NUM4_CANDIDATES := [
	"res://assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_num4_dash_contact_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_dash_contact_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack4_contact_v1_candidate_1254x1254.png",
]
const CLIPS := [
	{"name": "대기 · 승인", "category": "idle", "path": "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png", "duration": 0.8, "duration_source": "manifest idle", "approval": "승인 idle 원화", "foot": Vector2(0.5, 0.92822966507177), "support": null, "interpolation": "없음 · 원화 고정 표시"},
	{"name": "달리기 · v1 후보", "category": "run", "path": "res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png", "duration": 0.12, "duration_source": "검수 루프 배정 · 2장 합계 0.24초", "approval": "미승인 후보", "foot": null, "support": Vector2(1090.0 / 1254.0, 1200.0 / 1254.0), "interpolation": "없음 · 원화 고정 표시"},
	{"name": "달리기 · v2 반대 보폭 후보", "category": "run", "path": "res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png", "duration": 0.12, "duration_source": "검수 루프 배정 · 2장 합계 0.24초", "approval": "미승인 후보", "foot": null, "support": Vector2(1168.0 / 1254.0, 1225.0 / 1254.0), "interpolation": "없음 · 원화 고정 표시"},
	{"name": "점프 상승 safe 후보", "category": "jump", "path": "res://assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png", "duration": 0.3, "duration_source": "검수 표시 시간 · 실제 동작 시간은 격리 Window 캡처 도구에서 Player 물리로 측정", "approval": "safe 파생 · 미승인 후보", "foot": null, "support": null, "interpolation": "없음 · 상승 원화 고정 표시; 정점/하강/착지는 미구현 및 절차 표시"},
	{"name": "1타 startup 후보", "category": "startup", "path": "res://assets/art/player/elven_fighter_attack1_startup_v1_candidate_1254x1254.png", "duration": 0.075, "duration_source": "manifest 임시 startup 시간 · 후보 검수용", "approval": "미승인 후보", "foot": Vector2(0.5, 0.927432216905901), "support": null, "interpolation": "없음 · 원화 고정 표시"},
	{"name": "3타 startup 후보", "category": "startup", "path": "res://assets/art/player/elven_fighter_attack3_startup_v1_candidate_1254x1254.png", "duration": 0.1, "duration_source": "manifest 임시 startup 시간 · 후보 검수용", "approval": "미승인 후보", "foot": Vector2(0.5, 0.92822966507177), "support": null, "interpolation": "없음 · 원화 고정 표시"},
	{"name": "1타 접촉 · 승인", "category": "contact", "path": "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png", "duration": 0.105, "duration_source": "manifest 승인 contact", "approval": "승인 contact 원화", "foot": Vector2(0.5, 0.927432216905901), "support": null, "interpolation": "없음 · 원화 고정 표시"},
	{"name": "2타 접촉 · 승인", "category": "contact", "path": "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png", "duration": 0.12, "duration_source": "manifest 승인 contact", "approval": "승인 contact 원화", "foot": Vector2(0.499601275917065, 0.92822966507177), "support": null, "interpolation": "없음 · 원화 고정 표시"},
	{"name": "3타 접촉 · 승인", "category": "contact", "path": "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png", "duration": 0.14, "duration_source": "manifest 승인 contact", "approval": "승인 contact 원화", "foot": Vector2(0.5, 0.92822966507177), "support": null, "interpolation": "없음 · 원화 고정 표시"},
]

@onready var _sprite: Sprite2D = $CandidateSprite
var _group_names: Array[String] = ["대기", "달리기", "점프", "공격 startup", "공격 접촉"]
var _groups: Array[Array] = [[], [], [], [], []]
var _clips: Array = []
var _group_index := 0
var _clip_index := 0
var _elapsed := 0.0
var _playing := true
var _facing_right := true
var _missing_file := false
var _loaded_image: Image
var _alpha_bounds := Rect2i()
var _status_label: Label
var _metadata_label: Label
var _name_label: Label
var _capture_mode := false
var _capture_frames: Array[Image] = []
var _capture_group_queue: Array[int] = [1, 2, 4]
var _capture_requested := false

func _ready() -> void:
	get_window().size = WINDOW_SIZE
	_clips = CLIPS.duplicate(true)
	for candidate in NUM4_CANDIDATES:
		if FileAccess.file_exists(candidate):
			_add_dash_candidate(candidate)
			break
	_build_groups()
	_build_ui()
	_select_group(0)
	_capture_mode = OS.get_cmdline_user_args().has("--review-capture")
	if _capture_mode:
		_playing = false
		_capture_next_group.call_deferred()

func _build_groups() -> void:
	for clip_index in _clips.size():
		var group_index := _category_index(_clips[clip_index].category)
		_groups[group_index].append(clip_index)

func _category_index(category: String) -> int:
	match category:
		"idle": return 0
		"run": return 1
		"jump": return 2
		"startup": return 3
		"contact": return 4
		"dash": return 5
	return 0

func _add_dash_candidate(path: String) -> void:
	_group_names.append("Num4 돌진 접촉")
	_groups.append([CLIPS.size()])
	var clip := {"name": "Num4 돌진 접촉 후보", "category": "dash", "path": path, "duration": 0.12, "duration_source": "후보 원화 검수 표시 시간", "approval": "미승인 후보", "foot": null, "support": null, "interpolation": "없음 · 원화 고정 표시"}
	_clips.append(clip)

func _build_ui() -> void:
	var overlay := CanvasLayer.new()
	overlay.name = "ReviewOverlay"
	add_child(overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(32, 26)
	panel.size = Vector2(670, 1028)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.025, 0.045, 0.06, 0.94)
	panel_style.border_color = Color("#5f8b8a")
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(panel)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 9)
	panel.add_child(layout)
	_add_label(layout, "Player 원화 동작 검수", 30, Color("#f4dfb2"))
	_add_label(layout, "독립 검수 장면 · Player / manifest 변경 및 승인 없음", 16, Color("#b8d0cf"))
	var tabs := GridContainer.new()
	tabs.columns = 3
	tabs.add_theme_constant_override("h_separation", 6)
	tabs.add_theme_constant_override("v_separation", 6)
	layout.add_child(tabs)
	for i in mini(_group_names.size(), 5):
		var tab := Button.new()
		tab.text = "%d · %s" % [i + 1, _group_names[i]]
		tab.custom_minimum_size = Vector2(204, 38)
		tab.pressed.connect(_select_group.bind(i))
		tabs.add_child(tab)
	var unavailable := Button.new()
	unavailable.text = "Num4 · 돌진 접촉 [원화 미확보]"
	unavailable.disabled = true
	unavailable.custom_minimum_size = Vector2(624, 38)
	if _group_names.has("Num4 돌진 접촉"):
		unavailable.text = "Num4 · 돌진 접촉 후보"
		unavailable.disabled = false
		unavailable.pressed.connect(_select_group.bind(_group_names.find("Num4 돌진 접촉")))
	layout.add_child(unavailable)
	var controls := HBoxContainer.new()
	layout.add_child(controls)
	var play_button := Button.new()
	play_button.text = "재생 / 일시정지"
	play_button.pressed.connect(toggle_playback)
	controls.add_child(play_button)
	var left_button := Button.new()
	left_button.text = "좌향 전환"
	left_button.pressed.connect(_toggle_facing)
	controls.add_child(left_button)
	var next_button := Button.new()
	next_button.text = "다음 원화"
	next_button.pressed.connect(_step_clip.bind(1))
	controls.add_child(next_button)
	_name_label = _add_label(layout, "", 22, Color.WHITE)
	_status_label = _add_label(layout, "", 17, Color("#ffd17a"))
	_metadata_label = _add_label(layout, "", 16, Color("#d0dfdf"))
	_add_label(layout, "표시 기준: 192×192 게임 캔버스 · 3배 확대 (576px 실루엣)", 16, Color("#a9d6c8"))
	_add_label(layout, "좌/우: 방향   ↑/↓: 상태   ←/→: 원화   Space: 재생/중단", 16, Color("#a9d6c8"))
	_add_label(layout, "노랑: alpha 5% 기준점   민트: 사람 지정 지지발 후보", 15, Color("#c8e0d8"))

func _add_label(parent: Control, text: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(label)
	return label

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE: toggle_playback()
		KEY_LEFT: _step_clip(-1)
		KEY_RIGHT: _step_clip(1)
		KEY_UP: _select_group(posmod(_group_index - 1, _groups.size()))
		KEY_DOWN: _select_group(posmod(_group_index + 1, _groups.size()))
		KEY_A: _set_facing(false)
		KEY_D: _set_facing(true)
		KEY_1, KEY_2, KEY_3, KEY_4, KEY_5, KEY_6, KEY_7, KEY_8, KEY_9:
			var requested := int(event.keycode) - int(KEY_1)
			if requested < _groups.size(): _select_group(requested)
		KEY_KP_4:
			if _group_names.has("Num4 돌진 접촉"): _select_group(_group_names.find("Num4 돌진 접촉"))
		_:
			return
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not _playing or _groups[_group_index].is_empty():
		return
	_elapsed += delta
	var duration: float = float(_current_clip().duration)
	if _elapsed >= duration:
		_elapsed = fposmod(_elapsed, duration)
		_step_clip(1, false)

func _draw() -> void:
	var floor_y := 800.0
	draw_line(Vector2(735, floor_y), Vector2(1850, floor_y), Color("#c85d51"), 3.0)
	draw_string(ThemeDB.fallback_font, Vector2(742, floor_y + 28), "발 기준선 · 화면 기준", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#ffd0bb"))
	if _loaded_image == null or _alpha_bounds.size.y == 0:
		return
	var marker := _alpha_reference_point()
	draw_circle(marker, 8.0, Color("#ffd43b"))
	draw_line(marker - Vector2(15, 0), marker + Vector2(15, 0), Color("#ffd43b"), 2.0)
	draw_line(marker - Vector2(0, 15), marker + Vector2(0, 15), Color("#ffd43b"), 2.0)
	var support: Variant = _current_clip().support
	if support is Vector2:
		var point := _source_to_screen(support)
		draw_circle(point, 9.0, Color("#51f0c0"))
		draw_string(ThemeDB.fallback_font, point + Vector2(16, -8), "지지발 후보", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("#8effd8"))

func _select_group(index: int) -> void:
	if _groups.is_empty(): return
	_group_index = clampi(index, 0, _groups.size() - 1)
	_clip_index = 0
	_elapsed = 0.0
	_load_current_clip()

func select_group(index: int) -> void:
	_select_group(index)

func _step_clip(amount: int, reset_clock := true) -> void:
	var clips: Array = _groups[_group_index]
	if clips.is_empty(): return
	_clip_index = posmod(_clip_index + amount, clips.size())
	if reset_clock: _elapsed = 0.0
	_load_current_clip()

func toggle_playback() -> void:
	_playing = not _playing
	_elapsed = 0.0
	_refresh_labels()

func stop_playback() -> void:
	_playing = false
	_elapsed = 0.0
	_refresh_labels()

func get_review_state() -> Dictionary:
	return {"group": _group_index, "clip": _clip_index, "playing": _playing, "facing_right": _facing_right, "available": not _missing_file, "name": _current_clip().name}

func _toggle_facing() -> void:
	_set_facing(not _facing_right)

func _set_facing(right: bool) -> void:
	_facing_right = right
	_sprite.flip_h = not right
	queue_redraw()
	_refresh_labels()

func _current_clip() -> Dictionary:
	var clip_index: int = _groups[_group_index][_clip_index]
	return _clips[clip_index]

func _load_current_clip() -> void:
	var clip := _current_clip()
	var path: String = clip.path
	if not FileAccess.file_exists(path):
		_missing_file = true
		_sprite.texture = null
		_loaded_image = null
		_alpha_bounds = Rect2i()
		_status_label.text = "파일 누락 · " + path
		_name_label.text = clip.name
		_metadata_label.text = "원화 파일을 찾지 못해 재생할 수 없습니다.\n" + path
		queue_redraw()
		return
	_loaded_image = Image.new()
	var image_error := _loaded_image.load(ProjectSettings.globalize_path(path))
	if image_error != OK or _loaded_image.is_empty():
		_missing_file = true
		_status_label.text = "불러오기 실패 · %s (오류 %d)" % [path, image_error]
		_metadata_label.text = "원화 파일을 읽지 못했습니다. 오류 %d\n%s" % [image_error, path]
		_sprite.texture = null
		return
	_missing_file = false
	_alpha_bounds = _find_alpha_bounds(_loaded_image)
	_sprite.texture = ImageTexture.create_from_image(_loaded_image)
	var display_scale := FRAME_SIZE * DISPLAY_SCALE / float(maxi(1, _alpha_bounds.size.y))
	_sprite.scale = Vector2.ONE * display_scale
	_sprite.position = _alpha_reference_point_for(_current_clip(), _alpha_bounds, display_scale, _facing_right)
	_status_label.text = "%s  ·  %s" % [clip.approval, "우향" if _facing_right else "좌향"]
	_refresh_labels()
	queue_redraw()

func _refresh_labels() -> void:
	if _groups.is_empty() or _groups[_group_index].is_empty(): return
	var clip := _current_clip()
	_name_label.text = "%s  ·  %s" % [clip.name, "우향" if _facing_right else "좌향"]
	_status_label.text = "%s  ·  %s" % [clip.approval, "재생 중" if _playing else "중단"]
	_metadata_label.text = "duration %.3f s (%s)   |   보간: %s\n%s\nalpha 기준: α≥5%% 하단 연속구간 중앙 · 크기: alpha 높이 %dpx / 게임 192px 캔버스의 3배 표시" % [float(clip.duration), clip.duration_source, clip.interpolation, clip.path.get_file(), roundi(float(_alpha_bounds.size.y) * FRAME_SIZE / 1254.0)]

func _find_alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in image.get_height():
		for x in image.get_width():
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

func _alpha_reference_point() -> Vector2:
	return _source_to_screen(Vector2((_alpha_bounds.position.x + _alpha_bounds.size.x * 0.5) / 1254.0, (_alpha_bounds.position.y + _alpha_bounds.size.y - 1) / 1254.0))

func _source_to_screen(normalized_point: Vector2) -> Vector2:
	var local := (normalized_point * 1254.0 - Vector2(627.0, 627.0)) * _sprite.scale.x
	if not _facing_right: local.x = -local.x
	return _sprite.position + local

func _alpha_reference_point_for(_clip: Dictionary, bounds: Rect2i, display_scale: float, right: bool) -> Vector2:
	var alpha_bottom := Vector2((bounds.position.x + bounds.size.x * 0.5) / 1254.0, (bounds.position.y + bounds.size.y - 1) / 1254.0)
	var local := (alpha_bottom * 1254.0 - Vector2(627.0, 627.0)) * display_scale
	if not right: local.x = -local.x
	return Vector2(1280.0, 800.0) - local

func _capture_next_group() -> void:
	if _capture_group_queue.is_empty():
		var error := _save_capture_strip()
		if error != OK: push_error("Window 캡처 저장 실패: %s" % error)
		get_tree().quit(0 if error == OK else 1)
		return
	_select_group(_capture_group_queue.pop_front())
	_set_facing(true)
	await RenderingServer.frame_post_draw
	_capture_frames.append(get_viewport().get_texture().get_image())
	_set_facing(false)
	await RenderingServer.frame_post_draw
	_capture_frames.append(get_viewport().get_texture().get_image())
	_capture_next_group.call_deferred()

func _save_capture_strip() -> Error:
	if _capture_frames.size() < 2: return ERR_INVALID_DATA
	var tile_width := _capture_frames[0].get_width()
	var tile_height := _capture_frames[0].get_height()
	var strip := Image.create(tile_width * 2, tile_height * _capture_frames.size() / 2, false, Image.FORMAT_RGBA8)
	for i in _capture_frames.size():
		var tile := _capture_frames[i]
		var dst := Rect2i((i % 2) * tile_width, (i / 2) * tile_height, tile_width, tile_height)
		strip.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), dst.position)
	var path := ProjectSettings.globalize_path(CAPTURE_PATH)
	return strip.save_png(path)


