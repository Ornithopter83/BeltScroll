extends Control
"""Static, isolated comparison of M6K walk-stride drawing candidates."""

const DISPLAY_HEIGHT := 192.0
const RESOURCE_SCAN_DIR := "res://assets/art/player"
const LEGACY_CANDIDATES := [
	{"label": "run_stride v1", "path": "res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png"},
	{"label": "run_stride v2 opposite", "path": "res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png"},
	{"label": "run_stride v3 left lead", "path": "res://assets/art/player/elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png"},
	{"label": "run_stride v4 opposite contact", "path": "res://assets/art/player/elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png"},
	{"label": "run_stride v5 far leg forward", "path": "res://assets/art/player/elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png"},
]

const BG := Color("#101720")
const PANEL := Color("#18232e")
const TEXT := Color("#edf2f5")
const MUTED := Color("#a8bac8")
const ACCENT := Color("#f3c969")
const FLOOR := Color("#5d7180")

var _candidates: Array[Dictionary] = []
var _selected := 0
var _font: Font

func _ready() -> void:
	custom_minimum_size = Vector2(1280, 720)
	_font = ThemeDB.fallback_font
	_load_candidates()
	queue_redraw()

func _load_candidates() -> void:
	for entry in LEGACY_CANDIDATES:
		_add_candidate(entry.label, entry.path, "기존 후보")
	var additional_paths := _find_additional_stride_candidates()
	var has_resource_candidate := false
	for path in additional_paths:
		var is_resource := path.get_file().to_lower().contains("resource")
		if is_resource:
			has_resource_candidate = true
			_add_candidate(_display_candidate_name(path), path, "신규 RESOURCE")
		else:
			_add_candidate(_display_candidate_name(path), path, "추가 후보 · 미승인")
	if not has_resource_candidate:
		_candidates.append({"label": "RESOURCE 보폭 후보", "path": "", "kind": "RESOURCE", "missing": true})

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
		if not dir.current_is_dir() and lower.ends_with(".png") and (lower.contains("walk") or lower.contains("run")) and lower.contains("stride") and not _is_legacy_candidate(path):
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

func _add_candidate(label: String, path: String, kind: String) -> void:
	var texture: Texture2D = load(path) as Texture2D if ResourceLoader.exists(path) else null
	# Editor-imported assets load through ResourceLoader; a newly dropped review
	# PNG may not have an .import sidecar yet, so read it directly for this isolated board.
	if texture == null and FileAccess.file_exists(path):
		var image := Image.new()
		if image.load(ProjectSettings.globalize_path(path)) == OK and not image.is_empty():
			texture = ImageTexture.create_from_image(image)
	if texture == null:
		_candidates.append({"label": label, "path": path, "kind": kind, "missing": true})
		return
	var image := texture.get_image()
	var bounds := _alpha_bounds(image, 0.05)
	_candidates.append({"label": label, "path": path, "kind": kind, "texture": texture, "bounds": bounds, "missing": bounds.size == Vector2i.ZERO})

func _draw() -> void:
	var size := get_rect().size
	draw_rect(Rect2(Vector2.ZERO, size), BG, true)
	_draw_header(size.x)
	var count := _candidates.size()
	if count == 0:
		return
	var margin := 24.0
	var gap := 10.0
	var card_top := 146.0
	var card_bottom := size.y - 80.0
	var card_w := (size.x - margin * 2.0 - gap * float(count - 1)) / float(count)
	for i in range(count):
		var rect := Rect2(Vector2(margin + float(i) * (card_w + gap), card_top), Vector2(card_w, card_bottom - card_top))
		_draw_card(i, rect)
	_draw_footer(size.x, size.y)

func _draw_header(width: float) -> void:
	_draw_text("M6K · 보폭 후보 격리 검토", Vector2(28, 38), 27, TEXT)
	_draw_text("F6 정적 비교 · 게임 크기 기준 캐릭터 높이 192px · 좌우 키로 카드 선택", Vector2(30, 69), 16, MUTED)
	_draw_text("접지 교대 / 지지발 고정 / 팔 반대 흔들림 / 골반 높이를 후보 원화에서 판정하세요", Vector2(30, 95), 16, Color("#b9e9d8"))
	_draw_text("정지 원화 비교만 수행 · 자동 루프/프레임 보간 없음 · 미리보기와 후보는 미승인 격리 상태", Vector2(30, 119), 14, ACCENT)
	draw_line(Vector2(24, 132), Vector2(width - 24, 132), FLOOR, 1.0)

func _draw_card(index: int, rect: Rect2) -> void:
	var candidate: Dictionary = _candidates[index]
	var selected := index == _selected
	draw_rect(rect, Color("#243442") if selected else PANEL, true)
	draw_rect(rect, ACCENT if selected else Color("#30414f"), false, 2.0 if selected else 1.0)
	_draw_text(str(candidate.label), rect.position + Vector2(12, 27), 12, TEXT)
	_draw_text(str(candidate.kind), rect.position + Vector2(12, 49), 12, MUTED)
	var floor_y := rect.position.y + 306.0
	draw_line(Vector2(rect.position.x + 12, floor_y), Vector2(rect.end.x - 12, floor_y), FLOOR, 1.0)
	if bool(candidate.missing):
		var msg := "RESOURCE 미도착" if str(candidate.kind) == "RESOURCE" else "후보 파일 없음"
		_draw_text(msg, rect.position + Vector2(12, 115), 16, ACCENT if str(candidate.kind) == "RESOURCE" else Color("#ff9e8c"))
		_draw_text("파일이 추가되면 자동 탐색", rect.position + Vector2(12, 140), 12, MUTED)
		return
	var bounds: Rect2i = candidate.bounds
	var draw_h := DISPLAY_HEIGHT
	var draw_w := draw_h * float(bounds.size.x) / float(bounds.size.y)
	var center_x := rect.position.x + rect.size.x * 0.5
	var image_rect := Rect2(Vector2(center_x - draw_w * 0.5, floor_y - draw_h), Vector2(draw_w, draw_h))
	draw_texture_rect_region(candidate.texture, image_rect, Rect2(bounds), Color.WHITE, false, true)
	draw_circle(Vector2(center_x, floor_y), 3.0, ACCENT)
	var foot_center_x := center_x
	_draw_text("알파 경계 %d×%d px → 높이 192 px" % [bounds.size.x, bounds.size.y], rect.position + Vector2(12, 337), 12, MUTED)
	_draw_text("하단 중심 참고 x=%.1f · y=%.1f" % [float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y - 1)], rect.position + Vector2(12, 357), 12, MUTED)
	_draw_text("발 접지와 좌우 지지 확인", rect.position + Vector2(12, 391), 12, Color("#b9e9d8"))
	_draw_text("팔·골반 높이 실루엣 확인", rect.position + Vector2(12, 411), 12, Color("#b9e9d8"))
	if selected:
		_draw_text("선택됨", Vector2(foot_center_x - 21, floor_y + 22), 11, ACCENT)

func _draw_footer(width: float, height: float) -> void:
	draw_line(Vector2(24, height - 62), Vector2(width - 24, height - 62), FLOOR, 1.0)
	_draw_text("비교 원화는 한 장씩 정지 표시합니다. 서로 다른 보폭이 실제로 좌우 접지 교대를 이루는지 시각 확인 후 승인하세요.", Vector2(28, height - 37), 14, TEXT)
	_draw_text("본편 manifest · reviewed allowlist · Player 씬 자동 반영 없음", Vector2(28, height - 15), 12, ACCENT)

func _draw_text(value: String, position: Vector2, font_size: int, color: Color) -> void:
	if _font != null:
		draw_string(_font, position, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, color)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_RIGHT:
			_selected = (_selected + 1) % maxi(1, _candidates.size())
			queue_redraw()
		elif event.keycode == KEY_LEFT:
			_selected = posmod(_selected - 1, maxi(1, _candidates.size()))
			queue_redraw()

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
