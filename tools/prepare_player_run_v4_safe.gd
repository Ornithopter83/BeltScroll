extends SceneTree
"""Prepare v4 safe only when its source exists; otherwise preserve and compare v1-v3."""

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const RESAMPLE_GUARD := 12
const MAX_CONTENT := Vector2i(SIZE.x - 2 * (MIN_MARGIN + RESAMPLE_GUARD), SIZE.y - 2 * (MIN_MARGIN + RESAMPLE_GUARD))
const V1_SAFE := "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png"
const V2_SAFE := "res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png"
const V3_CANDIDATE := "res://assets/art/player/elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png"
const V4_SOURCE := "res://assets/art/player/elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png"
const V4_SAFE := "res://assets/art/player/elven_fighter_run_stride_v4_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_run_v4_opposition_comparison.png"
const TILE := 560
const DISPLAY := 410
const BOARD := Vector2i(TILE * 3, 1100)
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var v1 := _load_image(V1_SAFE)
	var v2 := _load_image(V2_SAFE)
	var v3 := _load_image(V3_CANDIDATE)
	if v1 == null or v2 == null or v3 == null:
		_fail("v1 safe, v2 safe, v3 candidate 입력 중 하나가 없습니다.")
		return
	var source_bytes := _read_bytes(V4_SOURCE)
	var v4 := _load_image(V4_SOURCE)
	if v4 == null:
		print("V4_SOURCE missing=true path=%s; v4 safe was not created" % V4_SOURCE)
		if not _build_review([v1, v2, v3], ["V1 SAFE", "V2 SAFE", "V3 CANDIDATE"], false):
			return
		print("EXISTING_POSES v1=v2=v3 same_stride_finding_preserved=true acceptance=not_granted integration=none")
		quit(0)
		return
	if v4.get_size() != SIZE or v4.get_format() != Image.FORMAT_RGBA8:
		_fail("v4 원본은 1254x1254 RGBA8 PNG여야 합니다.")
		return
	var v4_original_hash := _hash(source_bytes)
	var safe := _make_safe(v4)
	if safe == null:
		return
	var safe_path := ProjectSettings.globalize_path(V4_SAFE)
	var save_error := safe.save_png(safe_path)
	if save_error != OK:
		_fail("v4 safe 저장 실패: " + error_string(save_error))
		return
	if _read_bytes(V4_SOURCE) != source_bytes or _hash(_read_bytes(V4_SOURCE)) != v4_original_hash:
		_fail("v4 원본 바이트가 변경되었습니다.")
		return
	var margins := _margins(_alpha_bounds(safe))
	var isolated := _isolated_count(safe)
	if margins.x < MIN_MARGIN or margins.y < MIN_MARGIN or margins.z < MIN_MARGIN or margins.w < MIN_MARGIN or isolated != 0:
		_fail("v4 safe alpha 여백 또는 고립 픽셀 기준 미달: margins=%s isolated=%d" % [str(margins), isolated])
		return
	if not _build_review([v1, safe, v3], ["V1 SAFE", "V4 SAFE", "V3 CANDIDATE"], true):
		return
	print("V4_SAFE source_sha256=%s source_preserved=true size=%s format=RGBA8 alpha_margins_LTRB=%s isolated_pixels=%d" % [v4_original_hash, str(safe.get_size()), str(margins), isolated])
	print("OPPOSITION_GATE inspect_person_relative_lead_leg_rear_leg_arm_cross_support_foot=true compare_equal_game_scale=true compare_left_mirror=true pelvis_and_ponytail_connection=visual_review_required acceptance=not_granted integration=none")
	quit(0)

func _make_safe(source: Image) -> Image:
	var working := source.duplicate()
	_clear_isolated(working)
	var bounds := _alpha_bounds(working)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_fail("v4 원본에 연결된 alpha artwork가 없습니다.")
		return null
	var scale := minf(float(MAX_CONTENT.x) / bounds.size.x, float(MAX_CONTENT.y) / bounds.size.y)
	var fitted := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var crop: Image = working.get_region(bounds)
	for y in range(crop.get_height()):
		for x in range(crop.get_width()):
			var px: Color = crop.get_pixel(x, y)
			crop.set_pixel(x, y, Color(px.r * px.a, px.g * px.a, px.b * px.a, px.a))
	crop.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
	for y in range(crop.get_height()):
		for x in range(crop.get_width()):
			var px: Color = crop.get_pixel(x, y)
			if px.a > 0.0:
				crop.set_pixel(x, y, Color(clampf(px.r / px.a, 0.0, 1.0), clampf(px.g / px.a, 0.0, 1.0), clampf(px.b / px.a, 0.0, 1.0), px.a))
	var safe := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	safe.fill(Color(0, 0, 0, 0))
	safe.blit_rect(crop, Rect2i(Vector2i.ZERO, fitted), (SIZE - fitted) / 2)
	_clear_isolated(safe)
	_zero_transparent_rgb(safe)
	return safe

func _build_review(images: Array[Image], labels: Array[String], v4_acquired: bool) -> bool:
	var board := Image.create(BOARD.x, BOARD.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("#171b20"))
	_draw_text(board, "RUN V4 OPPOSITION REVIEW", Vector2i(28, 18), 3, Color("#f0e8d8"))
	_draw_text(board, "SAME GAME SCALE - LEFT MIRROR BELOW - NO APPROVAL", Vector2i(28, 54), 2, Color("#f1bd69"))
	for i in range(3):
		var x := i * TILE
		_draw_text(board, labels[i], Vector2i(x + 22, 92), 2, Color("#f0e8d8"))
		_draw_pose(board, images[i], x, 126, false)
		_draw_pose(board, images[i], x, 608, true)
	_draw_text(board, "RIGHT FACING", Vector2i(24, 574), 2, Color("#93d8c3"))
	_draw_text(board, "LEFT FACING MIRROR", Vector2i(24, 1050), 2, Color("#93d8c3"))
	var output := ProjectSettings.globalize_path(REVIEW)
	var error := DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if error != OK:
		_fail("비교 이미지 폴더 생성 실패: " + error_string(error))
		return false
	if board.save_png(output) != OK:
		_fail("비교 이미지 저장 실패")
		return false
	var check := Image.new()
	if check.load(output) != OK or check.get_size() != BOARD:
		_fail("비교 이미지 저장 검증 실패")
		return false
	print("REVIEW_IMAGE path=%s size=%s v4_acquired=%s columns=%s" % [REVIEW, str(BOARD), str(v4_acquired), str(labels)])
	return true

func _draw_pose(board: Image, source: Image, tile_x: int, top: int, flip: bool) -> void:
	var box := Rect2i(tile_x + (TILE - DISPLAY) / 2, top, DISPLAY, DISPLAY)
	_draw_checker(board, box)
	var sprite := source.duplicate()
	sprite.resize(DISPLAY, DISPLAY, Image.INTERPOLATE_LANCZOS)
	if flip:
		sprite.flip_x()
	board.blend_rect(sprite, Rect2i(Vector2i.ZERO, Vector2i(DISPLAY, DISPLAY)), box.position)
	var floor_y := top + DISPLAY - 1
	board.fill_rect(Rect2i(tile_x + 16, floor_y, TILE - 32, 2), Color("#f05c4f"))

func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 20):
		for x in range(rect.position.x, rect.end.x, 20):
			var even := (int((x - rect.position.x) / 20) + int((y - rect.position.y) / 20)) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(20, rect.end.x - x), mini(20, rect.end.y - y)), Color("#444a50") if even else Color("#30363c"))

func _draw_text(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	var cursor := origin.x
	for character in value:
		var glyph: Array = FONT.get(character, FONT[" "])
		for row in range(glyph.size()):
			for column in range(5):
				if glyph[row].substr(column, 1) == "1":
					image.fill_rect(Rect2i(cursor + column * scale, origin.y + row * scale, scale, scale), color)
		cursor += 6 * scale

func _load_image(path: String) -> Image:
	var bytes := _read_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.is_empty():
		return null
	return image

func _read_bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _margins(bounds: Rect2i) -> Vector4i:
	return Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)

func _clear_isolated(image: Image) -> void:
	var remove: Array[Vector2i] = []
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if not neighbor:
				remove.append(Vector2i(x, y))
	for point in remove:
		image.set_pixel(point.x, point.y, Color(0, 0, 0, 0))

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _zero_transparent_rgb(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return "hash_error"
	return context.finish().hex_encode()

func _fail(message: String) -> void:
	push_error("prepare_player_run_v4_safe: " + message)
	quit(1)
