extends Node2D
"""Isolated F6 locomotion review: three acquired PNGs, never a sprite sheet."""

const FRAME_CANVAS_PX := 192.0
const FRAME_DATA: Array[Dictionary] = [
	{
		"id": "walk_opposite_stride",
		"path": "res://assets/art/player/elven_fighter_walk_opposite_stride_v1_candidate_1254x1254.png",
		"duration": 0.24,
		"support": "LEFT",
		"contact_x": -17.0,
		"lifted": "RIGHT · 전진 스윙",
		"pelvis": "중립 · 보행 높이",
		"arms": "왼팔 뒤 / 오른팔 앞",
		"pose": "왼발 지지 보폭 · 오른발 전진",
	},
	{
		"id": "walk_passing",
		"path": "res://assets/art/player/elven_fighter_walk_passing_v1_candidate_1254x1254.png",
		"duration": 0.18,
		"support": "LEFT",
		"contact_x": -10.0,
		"lifted": "RIGHT · 발끝 들림",
		"pelvis": "중립 · 통과 높이",
		"arms": "왼팔 뒤 / 오른팔 앞",
		"pose": "왼발 지지 통과 · 오른발 전진",
	},
	{
		"id": "run_stride_v1",
		"path": "res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png",
		"duration": 0.20,
		"support": "MISSING · 양발 공중",
		"contact_x": 0.0,
		"lifted": "양발 · 비행 자세",
		"pelvis": "높음 · 도약",
		"arms": "왼팔 뒤 / 오른팔 앞",
		"pose": "달리기형 공중 보폭 · 보행 접지로 불인정",
	},
]

const BG := Color("#111a20")
const PANEL := Color("#19272e")
const PANEL_MOVE := Color("#20242d")
const TEXT := Color("#e5edf0")
const MUTED := Color("#a9bbc1")
const CYAN := Color("#72e8ee")
const PINK := Color("#ff82bf")
const GOLD := Color("#ffd68a")
const FLOOR_Y := 728.0
const BASE_X := [480.0, 1440.0]
const LANE_WIDTH := 920.0
const ROOT_SPEED := 48.0

var _sprites: Array[Sprite2D] = []
var _candidate_textures: Array[Texture2D] = []
var _candidate_bounds: Array[Rect2i] = []
var _frame_index := 0
var _frame_elapsed := 0.0
var _world_elapsed := 0.0
var _playing := true
var _hud: CanvasLayer
var _frame_label: Label
var _phase_label: Label
var _measure_label: Label
var _status_label: Label

func _ready() -> void:
	get_viewport().size = Vector2i(1920, 1080)
	_load_candidates()
	_build_stage()
	_apply_frame()
	_refresh_hud()
	print("M6M preview ready · candidates=%d/3 · stand_slip=%.2fpx · translate_slip=%.2fpx · silhouette_jump=%.2fpx" % [_candidate_textures.size() - _candidate_textures.count(null), _contact_delta_px(0, 1), ROOT_SPEED * float(FRAME_DATA[1]["duration"]) + _contact_delta_px(0, 1), _silhouette_jump_px(0, 1)])

func _load_candidates() -> void:
	for data in FRAME_DATA:
		var path: String = data["path"]
		var texture := load(path) as Texture2D if ResourceLoader.exists(path) else null
		_candidate_textures.append(texture)
		_candidate_bounds.append(texture.get_image().get_used_rect() if texture != null else Rect2i())

func _build_stage() -> void:
	for lane in range(2):
		var sprite := Sprite2D.new()
		sprite.name = "CandidateFrame_Loop" if lane == 0 else "CandidateFrame_Translate"
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.z_index = 3
		add_child(sprite)
		_sprites.append(sprite)
	_build_hud()
	queue_redraw()

func _build_hud() -> void:
	_hud = CanvasLayer.new()
	_hud.layer = 10
	add_child(_hud)
	_add_label(Vector2(36, 20), Vector2(1848, 42), "M6M · 보행 연속성 실험실 — 격리 후보 원화", 28, Color.WHITE)
	_add_label(Vector2(38, 67), Vector2(1844, 34), "F6 현재 장면 실행 · Space 재생/정지 · ←/→ 한 장씩 · 1/2/3 프레임 선택 · R 초기화", 18, MUTED)
	_add_label(Vector2(38, 119), Vector2(900, 36), "A · 제자리 반복", 23, CYAN)
	_add_label(Vector2(998, 119), Vector2(900, 36), "B · 실제 이동 비교 · +48 px/s", 23, PINK)
	_frame_label = _add_label(Vector2(38, 171), Vector2(1844, 48), "", 18, TEXT)
	_phase_label = _add_label(Vector2(38, 784), Vector2(1844, 94), "", 17, TEXT)
	_measure_label = _add_label(Vector2(38, 882), Vector2(1844, 66), "", 17, GOLD)
	_status_label = _add_label(Vector2(38, 960), Vector2(1844, 78), "", 16, Color("#ffc7a3"))

func _add_label(at: Vector2, size: Vector2, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = size
	label.text = value
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	_hud.add_child(label)
	return label

func _process(delta: float) -> void:
	if not _playing:
		return
	_world_elapsed += delta
	_frame_elapsed += delta
	var duration: float = float(FRAME_DATA[_frame_index]["duration"])
	if _frame_elapsed >= duration:
		_frame_elapsed = fmod(_frame_elapsed, duration)
		_frame_index = posmod(_frame_index + 1, FRAME_DATA.size())
		_apply_frame()
		_refresh_hud()
	_sprites[1].position.x = BASE_X[1] + fmod(_world_elapsed * ROOT_SPEED, 320.0)

func _apply_frame() -> void:
	for lane in range(2):
		var sprite := _sprites[lane]
		var texture := _candidate_textures[_frame_index]
		var bounds := _candidate_bounds[_frame_index]
		sprite.texture = texture
		sprite.visible = texture != null
		if texture == null or bounds.size.y <= 0:
			continue
		# All three source canvases use the same native pixel scale. Align only
		# their measured alpha feet to the common floor; never flip or duplicate.
		var scale_factor := FRAME_CANVAS_PX / float(texture.get_height())
		sprite.scale = Vector2.ONE * scale_factor
		var used_center := Vector2(bounds.position) + Vector2(bounds.size) * 0.5
		sprite.offset = Vector2(
			-(used_center.x - float(texture.get_width()) * 0.5) * scale_factor,
			-(float(bounds.end.y) - float(texture.get_height()) * 0.5) * scale_factor
		)
		sprite.position = Vector2(BASE_X[lane] + (fmod(_world_elapsed * ROOT_SPEED, 320.0) if lane == 1 else 0.0), FLOOR_Y)
	queue_redraw()

func _refresh_hud() -> void:
	var data: Dictionary = FRAME_DATA[_frame_index]
	var source_name: String = String(data["path"]).get_file()
	_frame_label.text = "프레임 %d / %d · %s · %.2f s · 192 px 원본 캔버스 · %s" % [
		_frame_index + 1, FRAME_DATA.size(), source_name, float(data["duration"]),
		"재생 중" if _playing else "일시 정지",
	]
	_phase_label.text = "현재 포즈  %s\n지지발 %s  |  들린 발 %s  |  골반 %s  |  팔 위상 %s" % [
		data["pose"], data["support"], data["lifted"], data["pelvis"], data["arms"],
	]
	var stationary_slip := _contact_delta_px(0, 1)
	var travel_per_frame := ROOT_SPEED * float(FRAME_DATA[1]["duration"])
	var translated_slip := travel_per_frame + stationary_slip
	var height_jump := _silhouette_jump_px(0, 1)
	_measure_label.text = "접지 위치 잔차 · 반대 보폭 → 통과 보폭 (같은 LEFT 접지 표기):  제자리 %.1f px/frame  |  이동 %.1f px/frame  |  알파 실루엣 상단 점프 %.1f px" % [stationary_slip, translated_slip, height_jump]
	_status_label.text = "MISSING · 오른발 접지 보폭 / 좌우 교대 / 이중 지지 / 실제 보행 접지로 확인된 공중 구간. 세 이미지는 각 1회만 재생하며 미러·반복 삽입 없음. 위치 랩은 시야 유지용이며 접지 연속성 아님. 원화 미승인 격리 상태 · 본편 Player/manifest/allowlist 연결 없음."

func _contact_delta_px(from_index: int, to_index: int) -> float:
	var from_data: Dictionary = FRAME_DATA[from_index]
	var to_data: Dictionary = FRAME_DATA[to_index]
	if String(from_data["support"]) != String(to_data["support"]) or String(from_data["support"]) == "MISSING · 양발 공중":
		return 0.0
	return (float(to_data["contact_x"]) - float(from_data["contact_x"])) * FRAME_CANVAS_PX / 1254.0

func _silhouette_jump_px(from_index: int, to_index: int) -> float:
	var from_bounds := _candidate_bounds[from_index]
	var to_bounds := _candidate_bounds[to_index]
	if from_bounds.size.y <= 0 or to_bounds.size.y <= 0:
		return 0.0
	return absf(float(to_bounds.position.y - from_bounds.position.y)) * FRAME_CANVAS_PX / 1254.0

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_SPACE:
			_playing = not _playing
			_refresh_hud()
		KEY_RIGHT:
			_step_frame(1)
		KEY_LEFT:
			_step_frame(-1)
		KEY_1:
			_select_frame(0)
		KEY_2:
			_select_frame(1)
		KEY_3:
			_select_frame(2)
		KEY_R:
			_frame_index = 0
			_frame_elapsed = 0.0
			_world_elapsed = 0.0
			_apply_frame()
			_refresh_hud()
		_:
			return
	get_viewport().set_input_as_handled()

func _step_frame(step: int) -> void:
	_playing = false
	_select_frame(posmod(_frame_index + step, FRAME_DATA.size()))

func _select_frame(index: int) -> void:
	_playing = false
	_frame_index = clampi(index, 0, FRAME_DATA.size() - 1)
	_frame_elapsed = 0.0
	_apply_frame()
	_refresh_hud()

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), BG)
	draw_rect(Rect2(Vector2(20, 108), Vector2(LANE_WIDTH, 650)), PANEL)
	draw_rect(Rect2(Vector2(980, 108), Vector2(LANE_WIDTH, 650)), PANEL_MOVE)
	draw_line(Vector2(960, 108), Vector2(960, 758), Color("#60717a"), 2.0, true)
	draw_rect(Rect2(Vector2(40, FLOOR_Y), Vector2(880, 3)), Color("#bd967b"))
	draw_rect(Rect2(Vector2(1000, FLOOR_Y), Vector2(880, 3)), Color("#bd967b"))
	for x in range(60, 930, 40):
		draw_line(Vector2(x, FLOOR_Y + 12), Vector2(x, FLOOR_Y + 22), Color("#72e8ee", 0.42), 1.0, true)
	for x in range(1020, 1890, 40):
		draw_line(Vector2(x, FLOOR_Y + 12), Vector2(x, FLOOR_Y + 22), Color("#ff82bf", 0.42), 1.0, true)
	draw_line(Vector2(BASE_X[0], FLOOR_Y + 5), Vector2(BASE_X[0], FLOOR_Y + 34), Color(CYAN, 0.9), 2.0, true)
	draw_line(Vector2(BASE_X[1], FLOOR_Y + 5), Vector2(BASE_X[1], FLOOR_Y + 34), Color(PINK, 0.9), 2.0, true)
	var support: String = FRAME_DATA[_frame_index]["support"]
	if support == "LEFT":
		var foot_x: float = float(FRAME_DATA[_frame_index]["contact_x"]) * FRAME_CANVAS_PX / 1254.0
		draw_circle(Vector2(BASE_X[0] + foot_x, FLOOR_Y + 2.0), 5.0, CYAN)
		draw_circle(Vector2(_sprites[1].position.x + foot_x, FLOOR_Y + 2.0), 5.0, PINK)




