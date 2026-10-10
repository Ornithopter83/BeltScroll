extends Control
"""Isolated animated review of available walk and run stride drawings."""

const DISPLAY_HEIGHT := 192.0
const RESOURCE_SCAN_DIR := "res://assets/art/player"
const FRAME_SECONDS := 0.18
const ALPHA_THRESHOLD := 13
const LEGACY_CANDIDATES := [
	{"label": "run_stride v1", "path": "res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png", "stride_phase": "same_run_lead"},
	{"label": "run_stride v2 opposite", "path": "res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png", "stride_phase": "same_run_lead"},
	{"label": "run_stride v3 left lead", "path": "res://assets/art/player/elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png", "stride_phase": "same_run_lead"},
	{"label": "run_stride v4 opposite contact", "path": "res://assets/art/player/elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png", "stride_phase": "same_run_lead"},
	{"label": "run_stride v5 far leg forward", "path": "res://assets/art/player/elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png", "stride_phase": "same_run_lead"},
]

const BG := Color("#101720")
const PANEL := Color("#18232e")
const TEXT := Color("#edf2f5")
const MUTED := Color("#a8bac8")
const ACCENT := Color("#f3c969")
const FLOOR := Color("#5d7180")
const PASS := Color("#b9e9d8")
const FAIL := Color("#ff8c7a")

var _candidates: Array[Dictionary] = []
var _frame_index := 0
var _frame_elapsed := 0.0
var _playing := true
var _font: Font
var _duplicate_pairs: Array[String] = []
var _stride_phase_failures: Array[String] = []

func _ready() -> void:
	custom_minimum_size = Vector2(1280, 720)
	_font = ThemeDB.fallback_font
	_load_candidates()
	queue_redraw()

func _process(delta: float) -> void:
	if not _playing or _candidates.is_empty():
		return
	_frame_elapsed += delta
	if _frame_elapsed >= FRAME_SECONDS:
		_frame_elapsed = fmod(_frame_elapsed, FRAME_SECONDS)
		_frame_index = (_frame_index + 1) % _candidates.size()
		queue_redraw()

func _load_candidates() -> void:
	for entry in LEGACY_CANDIDATES:
		_add_candidate(str(entry.label), str(entry.path), "기존 run_stride · 미승인", str(entry.stride_phase))
	var additional_paths := _find_additional_stride_candidates()
	for path in additional_paths:
		var label := _display_candidate_name(path)
		var lower_name := path.get_file().to_lower()
		var kind := ""
		if lower_name.contains("passing"):
			kind = "신규 passing 후보 · 독립 검토 · 미승인"
		elif lower_name.contains("opposite"):
			kind = "신규 반대 보폭 후보 · 미승인"
		else:
			kind = "추가 보폭 · 미승인"
		_add_candidate(label, path, kind)
	_detect_duplicate_drawings()

func _find_additional_stride_candidates() -> PackedStringArray:
	var found := PackedStringArray()
	var dir := DirAccess.open(RESOURCE_SCAN_DIR)
	if dir == null:
		return found
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while not file_name.is_empty():
		var lower := file_name.to_lower()
		var path := RESOURCE_SCAN_DIR.path_join(file_name)
		var locomotion_candidate := lower.contains("walk") or lower.contains("run")
		var stride_or_passing_pose := lower.contains("stride") or lower.contains("passing")
		var is_review_drawing := not lower.contains("_safe")
		if not dir.current_is_dir() and lower.ends_with(".png") and locomotion_candidate and stride_or_passing_pose and is_review_drawing and not _is_legacy_candidate(path):
			found.append(path)
		file_name = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found

func _is_legacy_candidate(path: String) -> bool:
	for entry in LEGACY_CANDIDATES:
		if str(entry.path) == path:
			return true
	return false

func _display_candidate_name(path: String) -> String:
	var name := path.get_file().get_basename().trim_suffix("_1254x1254").trim_suffix("_candidate").trim_prefix("elven_fighter_")
	return name.replace("_", " ")

func _add_candidate(label: String, path: String, kind: String, stride_phase: String = "") -> void:
	var image := Image.new()
	var texture: Texture2D
	if image.load(ProjectSettings.globalize_path(path)) == OK and not image.is_empty():
		# PNG decoders may return different channel layouts. A single RGBA8
		# conversion lets the bounds scan read alpha bytes directly, avoiding
		# millions of Image.get_pixel calls while the F6 review scene starts.
		image.convert(Image.FORMAT_RGBA8)
		texture = ImageTexture.create_from_image(image)
	if texture == null:
		_candidates.append({"label": label, "path": path, "kind": kind, "missing": true})
		return
	var rgba := image.get_data()
	var bounds := _alpha_bounds(rgba, image.get_width(), image.get_height())
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(image.get_data())
	_candidates.append({"label": label, "path": path, "kind": kind, "texture": texture, "bounds": bounds,
		"missing": bounds.size == Vector2i.ZERO, "signature": context.finish().hex_encode(),
		"bottom_center_x": _bottom_alpha_center_x(rgba, image.get_width(), bounds), "stride_phase": stride_phase})

func _detect_duplicate_drawings() -> void:
	var seen: Dictionary = {}
	var phases: Dictionary = {}
	for index in range(_candidates.size()):
		var candidate: Dictionary = _candidates[index]
		if bool(candidate.get("missing", true)):
			continue
		var signature := str(candidate.signature)
		if seen.has(signature):
			var first_index: int = seen[signature]
			var pair := "%s ↔ %s" % [str(_candidates[first_index].label), str(candidate.label)]
			_duplicate_pairs.append(pair)
			_candidates[index].duplicate_of = first_index
			_candidates[first_index].duplicate_of = index
		else:
			seen[signature] = index
		var phase := str(candidate.get("stride_phase", ""))
		if not phase.is_empty():
			if not phases.has(phase):
				phases[phase] = []
			phases[phase].append(index)
	for phase in phases:
		var indices: Array = phases[phase]
		if indices.size() < 2:
			continue
		var labels := PackedStringArray()
		for index in indices:
			_candidates[index].phase_duplicate = true
			labels.append(str(_candidates[index].label))
		_stride_phase_failures.append("%s: 같은 전진 보폭 phase 반복" % ", ".join(labels))

func _draw() -> void:
	var size := get_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), BG, true)
	_draw_header(size.x)
	_draw_current_frame(size)
	_draw_timeline(size)
	_draw_footer(size)

func _draw_header(width: float) -> void:
	_draw_text("M6L · 보행 보폭 연속 검토", Vector2(28, 38), 27, TEXT)
	_draw_text("F6 미리보기 · 실제 원화 알파 높이 192px · Space 재생/일시정지 · ←/→ 프레임 진행", Vector2(30, 69), 16, MUTED)
	_draw_text("관찰: 좌우 교대 접지 · 들린 발 · 팔 반대 흔들림 · 지지발 고정 · 골반 높이 · 좌우 이동", Vector2(30, 96), 16, PASS)
	_draw_text("모든 후보 미승인 · 동일 보폭 중복은 FAIL · 재생 순서는 관찰용이며 본편 애니메이션 등록이 아님", Vector2(30, 122), 14, ACCENT)
	draw_line(Vector2(24, 137), Vector2(width - 24, 137), FLOOR, 1.0)

func _draw_current_frame(size: Vector2) -> void:
	if _candidates.is_empty():
		_draw_text("검토할 보폭 원화가 없습니다.", Vector2(48, 220), 20, FAIL)
		return
	var candidate: Dictionary = _candidates[_frame_index]
	var stage := Rect2(Vector2(24, 150), Vector2(size.x - 48, size.y - 275))
	draw_rect(stage, PANEL, true)
	_draw_text("프레임 %d / %d  ·  %s" % [_frame_index + 1, _candidates.size(), str(candidate.label)], stage.position + Vector2(20, 30), 18, TEXT)
	_draw_text(str(candidate.kind), stage.position + Vector2(20, 54), 14, MUTED)
	var ground_y := stage.end.y - 40.0
	draw_line(Vector2(stage.position.x + 24, ground_y), Vector2(stage.end.x - 24, ground_y), FLOOR, 2.0)
	if bool(candidate.missing):
		_draw_text("파일을 읽을 수 없음", stage.position + Vector2(24, 105), 18, FAIL)
		return
	var bounds: Rect2i = candidate.bounds
	var image_width := DISPLAY_HEIGHT * float(bounds.size.x) / float(bounds.size.y)
	var texture_size: Vector2 = (candidate.texture as Texture2D).get_size()
	var source_center_x := float(bounds.position.x) + float(bounds.size.x) * 0.5
	var lateral_offset := (source_center_x - float(texture_size.x) * 0.5) * DISPLAY_HEIGHT / float(bounds.size.y)
	var center := Vector2(stage.size.x * 0.5 + lateral_offset, ground_y - DISPLAY_HEIGHT * 0.5) + stage.position
	var image_rect := Rect2(center.x - image_width * 0.5, ground_y - DISPLAY_HEIGHT, image_width, DISPLAY_HEIGHT)
	draw_texture_rect_region(candidate.texture, image_rect, Rect2(bounds), Color.WHITE, false, true)
	_draw_text("알파 실루엣 %d×%d → 높이 192px" % [bounds.size.x, bounds.size.y], stage.position + Vector2(20, stage.size.y - 14), 13, MUTED)
	var previous_index := posmod(_frame_index - 1, _candidates.size())
	var previous: Dictionary = _candidates[previous_index]
	var lateral_delta := (float(candidate.bottom_center_x) - float(previous.get("bottom_center_x", candidate.bottom_center_x))) * DISPLAY_HEIGHT / float(bounds.size.y)
	_draw_text("하단 중심 x=%.1f원화 px · 프레임 Δx=%.1f표시 px · y=%d" % [float(candidate.bottom_center_x), lateral_delta, bounds.end.y - 1], stage.position + Vector2(310, stage.size.y - 14), 13, PASS)
	if candidate.has("duplicate_of"):
		var other: Dictionary = _candidates[int(candidate.duplicate_of)]
		_draw_text("FAIL · 동일 원화 중복: " + str(other.label), stage.position + Vector2(20, 84), 16, FAIL)
	elif bool(candidate.get("phase_duplicate", false)):
		_draw_text("FAIL · 같은 전진 보폭 phase 반복 · 반대 접지 교대 없음", stage.position + Vector2(20, 84), 16, FAIL)
	elif str(candidate.label).contains("walk opposite"):
		_draw_text("판정 보류 · 단독 선 자세로 반대 접지/팔 반대 흔들림을 입증할 짝 원화 없음", stage.position + Vector2(20, 84), 14, ACCENT)
	elif str(candidate.label).contains("walk passing"):
		_draw_text("독립 검토 프레임 · passing 동작/지지발 고정/골반 높이 판정 필요", stage.position + Vector2(20, 84), 14, ACCENT)
	else:
		_draw_text("접지/들린 발/지지발/골반/좌우 이동: 시각 검토 필요", stage.position + Vector2(20, 84), 15, PASS)
	_draw_text("후보 상태: 미승인 · 검토 프레임에만 표시", Vector2(stage.end.x - 290, stage.position.y + 30), 13, ACCENT)

func _draw_timeline(size: Vector2) -> void:
	var y := size.y - 111.0
	draw_line(Vector2(24, y), Vector2(size.x - 24, y), FLOOR, 1.0)
	var summary := "재생 중" if _playing else "일시정지"
	_draw_text("%s  ·  간격 %.2fs" % [summary, FRAME_SECONDS], Vector2(28, y + 26), 14, ACCENT)
	var x := 225.0
	var available := size.x - x - 28.0
	var cell := available / float(maxi(1, _candidates.size()))
	for index in range(_candidates.size()):
		var color := ACCENT if index == _frame_index else Color("#3b4c59")
		draw_rect(Rect2(Vector2(x + cell * index, y + 11), Vector2(maxf(3.0, cell - 3.0), 12)), color, true)

func _draw_footer(size: Vector2) -> void:
	var y := size.y - 68.0
	var failures := PackedStringArray(_stride_phase_failures)
	for pair in _duplicate_pairs:
		failures.append("동일 원화 %s" % pair)
	var fail_summary := "FAIL · " + "; ".join(failures) if not failures.is_empty() else "중복 보폭 자동 확인: 없음"
	_draw_text(fail_summary, Vector2(28, y + 15), 13, FAIL if not failures.is_empty() else MUTED)
	_draw_text("본편 manifest · allowlist · Player 연결 없음", Vector2(28, size.y - 12), 12, ACCENT)

func _draw_text(value: String, position: Vector2, font_size: int, color: Color) -> void:
	if _font != null:
		draw_string(_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_SPACE:
		_playing = not _playing
		_frame_elapsed = 0.0
		queue_redraw()
	elif event.keycode == KEY_RIGHT:
		_step_frame(1)
	elif event.keycode == KEY_LEFT:
		_step_frame(-1)

func _step_frame(direction: int) -> void:
	if _candidates.is_empty():
		return
	_playing = false
	_frame_elapsed = 0.0
	_frame_index = posmod(_frame_index + direction, _candidates.size())
	queue_redraw()

func _alpha_bounds(rgba: PackedByteArray, width: int, height: int) -> Rect2i:
	var left := width
	var top := height
	var right := -1
	var bottom := -1
	for y in range(height):
		var row_offset := y * width * 4
		for x in range(width):
			if rgba[row_offset + x * 4 + 3] >= ALPHA_THRESHOLD:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _bottom_alpha_center_x(rgba: PackedByteArray, width: int, bounds: Rect2i) -> float:
	if bounds.size == Vector2i.ZERO:
		return 0.0
	var y := bounds.end.y - 1
	var row_offset := y * width * 4
	var total := 0.0
	var count := 0
	for x in range(bounds.position.x, bounds.end.x):
		if rgba[row_offset + x * 4 + 3] >= ALPHA_THRESHOLD:
			total += float(x)
			count += 1
	return total / float(count) if count > 0 else float(bounds.position.x + bounds.size.x / 2)
