extends SceneTree
"""Prepare an isolated safe candidate and mirrored review sheet for turn v2."""

const SOURCE_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v2_candidate_1254x1254.png"
const ALTERNATE_SOURCE_PATH := "res://assets/art/player/elven_fighter_turn_pivot_v2_candidate_1254x1254.png"
const SAFE_PATH := "res://assets/art/player/elven_fighter_turn_pivot_v2_safe_candidate_1254x1254.png"
const IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const V1_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png"
const COMPARISON_PATH := "res://assets/art/review/player_turn_pivot_v2_comparison.png"
const GATE_PATH := "res://docs/review/player_turn_pivot_v2_gate.md"
const CANVAS := 1254
const MIN_MARGIN := 90
const TILE := 192
const HEADER := 26
const PAD_X := 12
const GAP_X := 12
const PAD_Y := 12
const GAP_Y := 20
const SHEET_WIDTH := 2 * PAD_X + 3 * TILE + 2 * GAP_X
const SHEET_HEIGHT := 2 * PAD_Y + 2 * (TILE + HEADER) + GAP_Y

var failures: Array[String] = []
var isolated_removed := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := _find_source_path()
	var has_source := not source_path.is_empty()
	var source_hash := ""
	var source_bytes := 0
	var candidate_metrics := "원본 미확보로 후보를 생성하지 않았다."
	if has_source:
		var source_data := FileAccess.get_file_as_bytes(source_path)
		source_bytes = source_data.size()
		var hash_context := HashingContext.new()
		if hash_context.start(HashingContext.HASH_SHA256) == OK and hash_context.update(source_data) == OK:
			source_hash = hash_context.finish().hex_encode()
		else:
			failures.append("Could not hash the v2 source bytes.")
		candidate_metrics = _prepare_candidate(source_path)
	else:
		var stale_candidate := ProjectSettings.globalize_path(SAFE_PATH)
		if FileAccess.file_exists(SAFE_PATH):
			DirAccess.remove_absolute(stale_candidate)
	_generate_comparison(source_path)
	_record_gate(has_source, source_path, source_hash, source_bytes, candidate_metrics)
	if failures.is_empty():
		print("player_turn_pivot_v2_prepare: source=%s" % ("available" if has_source else "pending"))
		quit(0)
		return
	for failure in failures:
		push_error("player_turn_pivot_v2_prepare: " + failure)
	quit(1)

func _find_source_path() -> String:
	if FileAccess.file_exists(SOURCE_PATH):
		return SOURCE_PATH
	if FileAccess.file_exists(ALTERNATE_SOURCE_PATH):
		return ALTERNATE_SOURCE_PATH
	return ""

func _prepare_candidate(source_path: String) -> String:
	var source := Image.new()
	var load_error := source.load(ProjectSettings.globalize_path(source_path))
	if load_error != OK:
		failures.append("v2 source exists but cannot be decoded (%d)." % load_error)
		return "원본 디코딩 실패로 후보를 생성하지 않았다."
	var rgba := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	rgba.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
	var cleaned := _remove_isolated(rgba)
	var bounds := cleaned.get_used_rect()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		failures.append("v2 source has no connected visible artwork.")
		return "유효한 연결 알파가 없어 후보를 생성하지 않았다."
	var max_art := CANVAS - 2 * MIN_MARGIN
	var scale := minf(1.0, minf(float(max_art) / bounds.size.x, float(max_art) / bounds.size.y))
	var fitted := Vector2i(maxi(1, floori(bounds.size.x * scale)), maxi(1, floori(bounds.size.y * scale)))
	var art := Image.create(bounds.size.x, bounds.size.y, false, Image.FORMAT_RGBA8)
	art.fill(Color(0, 0, 0, 0))
	art.blit_rect(cleaned, bounds, Vector2i.ZERO)
	if fitted != bounds.size:
		art.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
	var output := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	output.fill(Color(0, 0, 0, 0))
	var placement := Vector2i((CANVAS - fitted.x) / 2, (CANVAS - fitted.y) / 2)
	output.blit_rect(art, Rect2i(Vector2i.ZERO, fitted), placement)
	output = _remove_isolated(output)
	var final_bounds := output.get_used_rect()
	var margins := [final_bounds.position.x, final_bounds.position.y, CANVAS - final_bounds.end.x, CANVAS - final_bounds.end.y]
	if output.get_size() != Vector2i(CANVAS, CANVAS) or output.get_format() != Image.FORMAT_RGBA8 or margins.min() < MIN_MARGIN or _count_isolated(output) != 0:
		failures.append("Generated safe candidate failed size, RGBA8, margin, or isolated-alpha validation.")
		return "후보 검증 실패."
	var save_error := output.save_png(ProjectSettings.globalize_path(SAFE_PATH))
	if save_error != OK:
		failures.append("Could not write v2 safe candidate (%d)." % save_error)
		return "후보 저장 실패."
	return "1254×1254 RGBA8; 알파 bounds %s; 여백 %s px; 고립 alpha 제거 %d개; 결과 고립 alpha 0개." % [str(final_bounds), str(margins), isolated_removed]

func _remove_isolated(image: Image) -> Image:
	var result := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	result.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
	var alpha := PackedByteArray()
	alpha.resize(image.get_width() * image.get_height())
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			alpha[y * image.get_width() + x] = 1 if image.get_pixel(x, y).a > 0.0 else 0
	var remove := PackedVector2Array()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if alpha[y * image.get_width() + x] == 0:
				continue
			var neighbor := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if (dx != 0 or dy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and alpha[ny * image.get_width() + nx] > 0:
						neighbor = true
			if not neighbor:
				remove.append(Vector2(x, y))
	for point in remove:
		result.set_pixel(int(point.x), int(point.y), Color(0, 0, 0, 0))
	isolated_removed += remove.size()
	return result

func _count_isolated(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					var nx := x + dx
					var ny := y + dy
					if (dx != 0 or dy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _generate_comparison(source_path: String) -> void:
	var sheet := Image.create(SHEET_WIDTH, SHEET_HEIGHT, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#171b25"))
	var paths := [IDLE_PATH, V1_PATH, source_path]
	var colors := [Color("#52728c"), Color("#8c7252"), Color("#528c70")]
	for column in range(3):
		var image := Image.new()
		var available := FileAccess.file_exists(paths[column]) and image.load(ProjectSettings.globalize_path(paths[column])) == OK
		for row in range(2):
			var rect := Rect2i(Vector2i(PAD_X + column * (TILE + GAP_X), PAD_Y + row * (TILE + HEADER + GAP_Y)), Vector2i(TILE, TILE + HEADER))
			sheet.fill_rect(rect, Color("#252b37"))
			sheet.fill_rect(Rect2i(rect.position, Vector2i(TILE, HEADER)), colors[column].darkened(0.1) if row == 0 else colors[column].lightened(0.15))
			var body := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
			body.fill(Color("#171b25"))
			if available:
				var full_canvas := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
				full_canvas.blit_rect(image, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)
				full_canvas.resize(TILE, TILE, Image.INTERPOLATE_LANCZOS)
				if row == 1:
					full_canvas.flip_x()
				body.blit_rect(full_canvas, Rect2i(Vector2i.ZERO, Vector2i(TILE, TILE)), Vector2i.ZERO)
			else:
				body.fill(Color("#343944"))
			sheet.blit_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), rect.position + Vector2i(0, HEADER))
			_draw_label(sheet, rect.position + Vector2i(8, 8), ["IDLE", "V1", "V2"][column], Color.WHITE)
			if row == 1:
				_draw_label(sheet, rect.position + Vector2i(TILE - 49, 8), "MIRROR", Color.WHITE)
	var save_error := sheet.save_png(ProjectSettings.globalize_path(COMPARISON_PATH))
	if save_error != OK:
		failures.append("Could not save 192px full-canvas comparison (%d)." % save_error)

func _draw_label(image: Image, origin: Vector2i, label: String, color: Color) -> void:
	var glyphs := {
		"I": [7, 2, 2, 2, 7], "D": [6, 5, 5, 5, 6], "L": [4, 4, 4, 4, 7],
		"E": [7, 4, 6, 4, 7], "V": [5, 5, 5, 5, 2], "1": [2, 6, 2, 2, 7],
		"2": [6, 1, 2, 4, 7], "M": [5, 7, 7, 5, 5], "R": [6, 5, 6, 5, 5],
		"O": [2, 5, 5, 5, 2], "": [0, 0, 0, 0, 0]
	}
	var cursor := origin.x
	for character in label:
		var rows: Array = glyphs.get(character, glyphs[""])
		for y in range(rows.size()):
			for x in range(3):
				if rows[y] & (1 << (2 - x)) != 0:
					image.set_pixel(cursor + x, origin.y + y, color)
		cursor += 4

func _record_gate(has_source: bool, source_path: String, digest: String, byte_count: int, candidate_metrics: String) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(GATE_PATH), FileAccess.WRITE)
	if file == null:
		failures.append("Could not write v2 review gate.")
		return
	var availability := "확보" if has_source else "미확보 — 작업 보류"
	var provenance := "SHA256 `%s`, 원본 %d bytes. 원본 파일 바이트는 수정하지 않았다." % [digest, byte_count] if has_source else "검색 경로에 원본이 없다. SHA256·바이트는 기록하지 않았으며 원본 및 safe 후보를 생성하지 않았다."
	var comparison_note := "원본 v2" if has_source else "v2 원본 미확보 자리표시자"
	var v2_column_note := "v2 원본이 없으므로 해당 열은 빈 자리표시자다." if not has_source else "v2 열은 확보된 원본 바이트를 직접 읽어 표시했다."
	var v2_visual_note := "미검토 — 원본 미확보." if not has_source else "Window 캡처에서 두 부츠 landmark는 약 61 px 떨어져 골반 아래 가까이 모여 보인다. anchor 정렬은 오른쪽 부츠 landmark (770,1135)를 지지발로 가정해 맞춘 결과이므로 실제 뒤꿈치 접촉은 사람 확인이 필요하다. v8 idle 대비 원본 alpha bounds 폭은 약 18.9 percent 좁고 높이는 약 11.0 percent 커서 크기 팝 우려가 있다. 머리카락·뾰족 귀·의상 색과 형태는 같은 캐릭터로 읽히지만, 회전축의 자연스러움과 뒤꿈치 접촉은 미승인 상태다."
	file.store_string("""# Player turn pivot v2 review gate

## 상태: %s

v2 원본: `%s` (%s)  
safe 후보: `%s`  
비교 이미지: `%s` (624×480)

### 원본 provenance와 후보

%s

후보 처리: %s

### 비교 배치

3열×2행의 각 카드는 전체 원본 캔버스를 같은 192×192 픽셀로 축소했다. 열 순서는 v8 idle, 기존 rear-mid v1, %s이며, 위 행은 원래 방향, 아래 행은 좌우 반전이다. 반전은 각 전체 캔버스 이미지에 한 번만 적용했다. %s

### 시각 검토 기록

- v1 rear-mid는 idle보다 alpha bounds 폭이 14.4%%, 높이가 13.5%% 크다. 큰 보폭과 들린 부츠가 달리기로 읽히는 미수용 후보 상태를 유지한다. v1은 이번 작업에서 수정하거나 수용 처리하지 않았다.
- v2 시각 메모: %s
- 회전축과 뒤꿈치 접촉, 반대 방향 mirror 대응: %s
- 얼굴·귀·의상 identity 및 idle 대비 크기: %s
- foot anchor와 지지발 이동: %s
- 사람 검토 전 본편, manifest, allowlist에 등록하지 않는다.

""" % [availability, source_path if has_source else ALTERNATE_SOURCE_PATH, "있음" if has_source else "없음", SAFE_PATH, COMPARISON_PATH, provenance, candidate_metrics, comparison_note, v2_column_note,
		v2_visual_note,
		"원본 미확보로 평가 불가" if not has_source else "미승인 — 반대 방향 mirror 접점은 Window 캡처와 비교판에서 확인 가능하나 사람 검토 필요",
		"원본 미확보로 평가 불가" if not has_source else "identity는 같은 캐릭터로 보임; alpha bounds가 idle보다 좁고 높아 크기 팝 우려, 사람 수용 보류",
		"원본 미확보로 평가 불가" if not has_source else "anchor 좌표는 (960,790) 고정; 지지발 landmark를 수동 가정해 정렬했으므로 실제 뒤꿈치 접촉·이동은 사람 검토 필요"])
	file.close()
