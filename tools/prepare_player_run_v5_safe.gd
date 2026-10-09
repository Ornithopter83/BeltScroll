extends SceneTree
"""Prepare an isolated v5 run candidate and a fixed-scale v1/v5 review board."""

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const RESAMPLE_GUARD := 12
const MAX_CONTENT := Vector2i(SIZE.x - 2 * (MIN_MARGIN + RESAMPLE_GUARD), SIZE.y - 2 * (MIN_MARGIN + RESAMPLE_GUARD))
const V1_SAFE := "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png"
const V5_SOURCE := "res://assets/art/player/elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png"
const V5_SAFE := "res://assets/art/player/elven_fighter_run_stride_v5_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_run_v5_antiphase_comparison.png"
const TILE := Vector2i(260, 240)
const DISPLAY := 192
const BOARD := Vector2i(520, 480)
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var v1 := _load_image(V1_SAFE)
	if v1 == null or v1.get_size() != SIZE or v1.get_format() != Image.FORMAT_RGBA8:
		_fail("v1 safe 입력은 1254x1254 RGBA8 PNG여야 합니다.")
		return
	var source_bytes := _read_bytes(V5_SOURCE)
	var v5 := _load_image(V5_SOURCE)
	if v5 == null:
		print("V5_SOURCE missing=true path=%s; safe candidate not created" % V5_SOURCE)
		if not _build_review(v1, null):
			return
		print("V5_GATE acceptance=not_granted player_or_manifest_integration=none")
		quit(0)
		return
	if v5.get_size() != SIZE or v5.get_format() != Image.FORMAT_RGBA8:
		_fail("v5 원본은 1254x1254 RGBA8 PNG여야 합니다.")
		return
	var source_hash := _sha256(source_bytes)
	var safe := _make_safe(v5)
	if safe == null:
		return
	var safe_path := ProjectSettings.globalize_path(V5_SAFE)
	if safe.save_png(safe_path) != OK:
		_fail("v5 safe 후보 저장 실패")
		return
	if _read_bytes(V5_SOURCE) != source_bytes or _sha256(_read_bytes(V5_SOURCE)) != source_hash:
		_fail("v5 원본 바이트가 변경되었습니다.")
		return
	var margins := _margins(_alpha_bounds(safe))
	var isolated := _isolated_count(safe)
	if margins.x < MIN_MARGIN or margins.y < MIN_MARGIN or margins.z < MIN_MARGIN or margins.w < MIN_MARGIN or isolated != 0:
		_fail("v5 safe 여백 또는 고립 alpha 픽셀 기준 미달: margins=%s isolated=%d" % [str(margins), isolated])
		return
	if not _build_review(v1, safe):
		return
	print("V5_SAFE source_sha256=%s source_bytes=%d source_preserved=true size=%s format=RGBA8 alpha_margins_LTRB=%s isolated_pixels=%d" % [source_hash, source_bytes.size(), str(safe.get_size()), str(margins), isolated])
	print("V5_GATE inspect_near_leg_rear_far_leg_front_pelvis_arms_boots_ponytail_foot_anchor_scale=true acceptance=not_granted player_or_manifest_integration=none")
	quit(0)

func _make_safe(source: Image) -> Image:
	var working := source.duplicate()
	_clear_isolated(working)
	var bounds := _alpha_bounds(working)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_fail("v5 원본에 alpha artwork가 없습니다.")
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

func _build_review(v1: Image, v5: Image) -> bool:
	var board := Image.create(BOARD.x, BOARD.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("#171b20"))
	var images: Array[Image] = [v1, v5 if v5 != null else v1, v1, v5 if v5 != null else v1]
	var flips := [false, false, true, true]
	var names := ["V1 RIGHT", "V5 RIGHT" if v5 != null else "V5 NOT ACQUIRED RIGHT", "V1 LEFT", "V5 LEFT" if v5 != null else "V5 NOT ACQUIRED LEFT"]
	for index in range(4):
		var cell := Rect2i(Vector2i((index % 2) * TILE.x, (index / 2) * TILE.y), TILE)
		board.fill_rect(cell, Color("#252b31"))
		_draw_text(board, names[index], cell.position + Vector2i(8, 6), 1, Color("#f0e8d8"))
		var sprite_rect := Rect2i(cell.position + Vector2i(34, 28), Vector2i(DISPLAY, DISPLAY))
		_draw_checker(board, sprite_rect)
		if v5 == null and (index == 1 or index == 3):
			_draw_text(board, "NOT ACQUIRED", cell.position + Vector2i(27, 108), 1, Color("#f1bd69"))
			board.fill_rect(Rect2i(cell.position + Vector2i(32, 140), Vector2i(196, 2)), Color("#f05c4f"))
		else:
			var sprite := images[index].duplicate()
			sprite.resize(DISPLAY, DISPLAY, Image.INTERPOLATE_LANCZOS)
			if flips[index]:
				sprite.flip_x()
			board.blend_rect(sprite, Rect2i(Vector2i.ZERO, Vector2i(DISPLAY, DISPLAY)), sprite_rect.position)
	var output := ProjectSettings.globalize_path(REVIEW)
	if DirAccess.make_dir_recursive_absolute(output.get_base_dir()) != OK or board.save_png(output) != OK:
		_fail("v5 비교 이미지 저장 실패")
		return false
	var check := Image.new()
	if check.load(output) != OK or check.get_size() != BOARD:
		_fail("v5 비교 이미지 저장 검증 실패")
		return false
	print("REVIEW_IMAGE path=%s size=%s scale=192px_per_1254px rows=right_facing,left_mirrored columns=v1_safe,v5_%s" % [REVIEW, str(BOARD), "safe" if v5 != null else "missing"])
	return true

func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 16):
		for x in range(rect.position.x, rect.end.x, 16):
			var even := (int((x - rect.position.x) / 16) + int((y - rect.position.y) / 16)) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(16, rect.end.x - x), mini(16, rect.end.y - y)), Color("#444a50") if even else Color("#30363c"))

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
	return image if image.load_png_from_buffer(bytes) == OK else null

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

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return "hash_error"
	return context.finish().hex_encode()

func _fail(message: String) -> void:
	push_error("prepare_player_run_v5_safe: " + message)
	quit(1)
