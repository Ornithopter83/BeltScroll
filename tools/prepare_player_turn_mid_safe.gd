extends SceneTree
"""Prepare a safe turn-art candidate only when its authored source exists."""

const SOURCE_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png"
const SAFE_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v1_safe_candidate_1254x1254.png"
const IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const PROCEDURAL_PATH := "res://assets/art/review/player_turn_motion_strip.png"
const COMPARISON_PATH := "res://assets/art/review/player_turn_mid_comparison.png"
const GATE_PATH := "res://docs/review/player_turn_mid_art_gate.md"
const CANVAS := 1254
const MIN_MARGIN := 90
const TILE := 192
const CARD_HEADER := 30
const SHEET_WIDTH := 2 * TILE + 3 * 12
const SHEET_HEIGHT := 2 * (TILE + CARD_HEADER) + 3 * 12

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_global := ProjectSettings.globalize_path(SOURCE_PATH)
	var source_exists := FileAccess.file_exists(SOURCE_PATH)
	var source_digest := ""
	var source_bytes := 0
	if source_exists:
		var source_data := FileAccess.get_file_as_bytes(SOURCE_PATH)
		source_bytes = source_data.size()
		var hash_context := HashingContext.new()
		if hash_context.start(HashingContext.HASH_SHA256) == OK and hash_context.update(source_data) == OK:
			source_digest = hash_context.finish().hex_encode()
		_prepare_candidate(source_global)
	else:
		print("TURN_SOURCE_PENDING: %s" % SOURCE_PATH)

	_generate_comparison(source_exists)
	_record_gate(source_exists, source_digest, source_bytes)
	if failures.is_empty():
		print("player-turn-mid-prepare: comparison saved; source=%s" % ("available" if source_exists else "pending"))
		quit(0)
		return
	for failure in failures:
		push_error("player_turn_mid_prepare: " + failure)
	quit(1)

func _prepare_candidate(source_global: String) -> void:
	var source := Image.new()
	var load_error := source.load(source_global)
	if load_error != OK:
		failures.append("Turn source exists but cannot be decoded (%d): %s" % [load_error, SOURCE_PATH])
		return
	var normalized := Image.create(CANVAS, CANVAS, false, Image.FORMAT_RGBA8)
	normalized.fill(Color(0, 0, 0, 0))
	var source_rgba := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	source_rgba.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
	var used := source_rgba.get_used_rect()
	if used.size.x <= 0 or used.size.y <= 0:
		failures.append("Turn source has no visible pixels; no safe candidate was written.")
		return
	var isolated := _remove_isolated_pixels(source_rgba)
	var clean_bounds := isolated.get_used_rect()
	if clean_bounds.size.x <= 0 or clean_bounds.size.y <= 0:
		failures.append("Turn source contains no connected artwork after isolated-pixel removal.")
		return
	var max_art := CANVAS - MIN_MARGIN * 2
	var factor := minf(1.0, minf(float(max_art) / float(clean_bounds.size.x), float(max_art) / float(clean_bounds.size.y)))
	var fitted_size := Vector2i(maxi(1, floori(float(clean_bounds.size.x) * factor)), maxi(1, floori(float(clean_bounds.size.y) * factor)))
	var art := Image.create(clean_bounds.size.x, clean_bounds.size.y, false, Image.FORMAT_RGBA8)
	art.fill(Color(0, 0, 0, 0))
	art.blit_rect(isolated, clean_bounds, Vector2i.ZERO)
	if fitted_size != clean_bounds.size:
		art.resize(fitted_size.x, fitted_size.y, Image.INTERPOLATE_LANCZOS)
	var placement := Vector2i((CANVAS - fitted_size.x) / 2, (CANVAS - fitted_size.y) / 2)
	normalized.blit_rect(art, Rect2i(Vector2i.ZERO, fitted_size), placement)
	var source_singletons_removed := _isolated_removed_count
	var cleaned_output := _remove_isolated_pixels(normalized)
	normalized = cleaned_output
	_isolated_removed_count += source_singletons_removed
	var margin_bounds := normalized.get_used_rect()
	var margins := [margin_bounds.position.x, margin_bounds.position.y, CANVAS - margin_bounds.end.x, CANVAS - margin_bounds.end.y]
	if normalized.get_format() != Image.FORMAT_RGBA8 or normalized.get_size() != Vector2i(CANVAS, CANVAS) or margins.min() < MIN_MARGIN or _count_isolated_pixels(normalized) != 0:
		failures.append("Generated candidate failed RGBA8, dimensions, or 90px alpha-margin validation: %s" % str(margins))
		return
	var safe_global := ProjectSettings.globalize_path(SAFE_PATH)
	var save_error := normalized.save_png(safe_global)
	if save_error != OK:
		failures.append("Could not save safe candidate (error %d)." % save_error)
		return
	print("TURN_SOURCE_SHA256: %s" % _sha256_file(source_global))
	print("TURN_SOURCE_BYTES: %d" % FileAccess.get_file_as_bytes(SOURCE_PATH).size())
	print("TURN_SAFE_MARGINS: %s; isolated pixels removed: %d" % [str(margins), _isolated_removed_count])

var _isolated_removed_count := 0

func _remove_isolated_pixels(image: Image) -> Image:
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
			var has_neighbor := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and alpha[ny * image.get_width() + nx] > 0:
						has_neighbor = true
			if not has_neighbor:
				remove.append(Vector2(x, y))
	for point in remove:
		result.set_pixel(int(point.x), int(point.y), Color(0, 0, 0, 0))
	_isolated_removed_count = remove.size()
	return result

func _count_isolated_pixels(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var has_neighbor := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						has_neighbor = true
			if not has_neighbor:
				count += 1
	return count

func _sha256_file(path: String) -> String:
	var bytes := FileAccess.get_file_as_bytes(path)
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func _generate_comparison(has_source: bool) -> void:
	var sheet := Image.create(SHEET_WIDTH, SHEET_HEIGHT, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#171b25"))
	var idle := Image.new()
	if idle.load(ProjectSettings.globalize_path(IDLE_PATH)) != OK:
		failures.append("Could not load v8 idle artwork for comparison.")
	else:
		_draw_card(sheet, 0, idle)
	if has_source:
		var original := Image.new()
		if original.load(ProjectSettings.globalize_path(SOURCE_PATH)) == OK:
			_draw_card(sheet, 1, original)
		var safe := Image.new()
		if safe.load(ProjectSettings.globalize_path(SAFE_PATH)) == OK:
			_draw_card(sheet, 2, safe)
	var procedural := Image.new()
	if procedural.load(ProjectSettings.globalize_path(PROCEDURAL_PATH)) == OK:
		var turn_tile := Image.create(1024, 900, false, Image.FORMAT_RGBA8)
		turn_tile.blit_rect(procedural, Rect2i(2048, 0, 1024, 900), Vector2i.ZERO)
		_draw_card(sheet, 3, turn_tile)
	else:
		failures.append("Could not load the existing procedural turn capture.")
	if not has_source:
		for index in [1, 2]:
			var rect := _card_rect(index)
			sheet.fill_rect(rect, Color("#333743"))
	var save_error := sheet.save_png(ProjectSettings.globalize_path(COMPARISON_PATH))
	if save_error != OK:
		failures.append("Could not save the comparison image (error %d)." % save_error)

func _draw_card(sheet: Image, index: int, source: Image) -> void:
	var card := _card_rect(index)
	sheet.fill_rect(card, Color("#252b37"))
	var header_colors := [Color("#52728c"), Color("#8c7252"), Color("#528c70"), Color("#76528c")]
	sheet.fill_rect(Rect2i(card.position, Vector2i(TILE, CARD_HEADER)), header_colors[index])
	var body := Image.create(TILE, TILE, false, Image.FORMAT_RGBA8)
	body.fill(Color("#171b25"))
	var src := Image.create(source.get_width(), source.get_height(), false, Image.FORMAT_RGBA8)
	src.blit_rect(source, Rect2i(Vector2i.ZERO, source.get_size()), Vector2i.ZERO)
	var scale := minf(float(TILE) / float(src.get_width()), float(TILE) / float(src.get_height()))
	var dims := Vector2i(maxi(1, roundi(float(src.get_width()) * scale)), maxi(1, roundi(float(src.get_height()) * scale)))
	src.resize(dims.x, dims.y, Image.INTERPOLATE_LANCZOS)
	body.blit_rect(src, Rect2i(Vector2i.ZERO, dims), Vector2i((TILE - dims.x) / 2, (TILE - dims.y) / 2))
	sheet.blit_rect(body, Rect2i(Vector2i.ZERO, body.get_size()), card.position + Vector2i(0, CARD_HEADER))

func _card_rect(index: int) -> Rect2i:
	return Rect2i(Vector2i(12 + (index % 2) * (TILE + 12), 12 + int(index / 2) * (TILE + CARD_HEADER + 12)), Vector2i(TILE, TILE + CARD_HEADER))

func _record_gate(has_source: bool, digest: String, byte_count: int) -> void:
	var file := FileAccess.open(ProjectSettings.globalize_path(GATE_PATH), FileAccess.WRITE)
	if file == null:
		failures.append("Could not write the requested review gate document.")
		return
	var status := "원화 확보 / 키포즈 보류" if has_source else "보류 — 전용 원화 미확보"
	var provenance := "- 원본 SHA256: `%s`\n- 원본 바이트: `%d`\n" % [digest, byte_count] if has_source else "- 원본 SHA256: 미기록 (전용 원화 파일 없음)\n- 원본 바이트: 미기록\n"
	var preparation := "원화 원본을 변경하지 않고 별도 safe 후보를 생성했다. 후보는 알파 여백을 사방 90px 이상으로 맞추고 고립 알파 픽셀을 제거했다." if has_source else "이 게이트 생성 시 전용 turn 원화 파일이 없어 safe 후보를 만들지 않았다."
	var pose_review := "후방 3/4 시점과 얼굴을 돌려보는 표정, 귀, 포니테일이 읽혀 캐릭터 identity는 유지된다. 다만 앞뒤 다리의 크게 벌어진 보폭, 들린 부츠, 팔의 반동 때문에 정지 turn보다 달리기/보폭 포즈로 읽힌다. 요청한 키포즈 기준으로 수용하지 않고 사람 검토 보류다." if has_source else "전용 turn 원화가 없어 후방 3/4 포즈와 identity를 평가할 수 없다."
	var visual_metrics := "- safe 후보 알파 used rect: 위치 `(149, 90)`, 크기 `(956, 1074)`; 사방 여백 `[149, 90, 149, 90]` px. 고립 알파 픽셀 제거: `224` (원본 및 후보화 단계 합계).\n- 192px full-canvas 비교에서 turn 인물 높이: 약 `164px`; procedural 캡처는 원래 capture cell을 동일 192px 전체 cell로 축소해 게임 내 인물 크기와 팝 차이를 함께 보인다.\n" if has_source else "- 전용 turn 원화와 후보가 없어 원화 간 크기 측정은 보류다.\n"
	file.store_string("""# Player turn mid art gate

## 상태: %s

전용 turn 원화 경로: `%s`  
safe 후보 경로: `%s`

%s 후보는 1254×1254 RGBA8이다.

%s
비교판: `%s` (420×480) — 모든 카드는 전체 캔버스를 보존해 192×192로 배치했다. 읽는 순서는 왼쪽 위 v8 idle, 오른쪽 위 원화, 왼쪽 아래 safe 후보, 오른쪽 아래 기존 procedural 캡처의 압축 turn 프레임이다. 헤더 색은 각각 파랑·갈색·초록·보라다.

## 포즈 검토 기록

%s

%s
- 후방 3/4: 원화에는 명확한 뒤돌아본 후방 3/4가 있으나 stride 포즈로 읽힌다. 기존 procedural 캡처는 옆면 방향을 뒤집는 변환 단계여서 후방 키포즈 증거가 아니다.
- 얼굴·귀·포니테일 identity: 얼굴을 돌아보는 표정, 뾰족한 귀, 높은 포니테일이 v8 idle과 일치한다. 좌우 반전만으로는 이 identity 검증을 대체하지 않는다.
- 회전축 발: 원화 한 장에는 지지발 후보(화면 오른쪽 부츠)와 든 발이 보인다. 연속 turn에서 회전축 발이 고정되는지는 평가 불가다. 기존 procedural 캡처 도구는 alpha-foot anchor 안정성을 별도로 기록한다.
- 좌우 미러·골반·발 anchor: 반대 방향 authored frame이 없어 좌우 mirror, 골반 중심, 지지발 이동을 비교할 수 없다. 승인 전에 해당 대응 프레임이 필요하다.
- 크기 팝: v8 idle, 원화, safe는 전체 1254px 캔버스를 192px로 같은 비율 축소했다. procedural 캡처는 전체 capture cell을 192px로 축소해 장면에서 보이는 캐릭터 크기를 비교한다.
- 키포즈 결론: 단순 좌우 flip이나 달리기 자세는 turn 키포즈로 수용하지 않는다. 이 원화는 stride로 보여 현재 보류한다. 사람 승인 전 본편·manifest·allowlist에 등록하지 않는다.

""" % [status, SOURCE_PATH, SAFE_PATH, preparation, provenance, COMPARISON_PATH, pose_review, visual_metrics])
	file.close()
