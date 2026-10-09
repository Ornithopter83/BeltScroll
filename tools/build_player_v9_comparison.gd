extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const GAME_SPRITE_SCALE := 0.4469274
const CAMERA_ZOOM := 1.2
const GAME_DISPLAY_HEIGHT := 576
const REVIEW_SCALE := 3
const DISPLAY_HEIGHT := GAME_DISPLAY_HEIGHT * REVIEW_SCALE
const V8 := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const V9 := "res://assets/art/player/elven_fighter_reference_v9_fantasy_1254x1254.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const OUTPUT := "res://assets/art/review/player_v9_comparison.png"
const CANVAS_SIZE := Vector2i(1920, 2280)

# Normalized to each image's alpha bounds. Keep this list synchronized with the
# review legend and smoke checks: face/ear, gloves, costume, and both feet.
const ANCHORS := [
	{"name": "FACE_EAR", "rect": Rect2(0.39, 0.00, 0.47, 0.30)},
	{"name": "GLOVES", "rect": Rect2(0.23, 0.24, 0.66, 0.29)},
	{"name": "COSTUME", "rect": Rect2(0.25, 0.34, 0.56, 0.46)},
	{"name": "FEET", "rect": Rect2(0.02, 0.70, 0.96, 0.30)},
]
const COLORS := [Color("#75b8bc"), Color("#e1ad68")]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var v8 := _load_png(V8)
	var v9 := _load_png(V9)
	var forest := _load_png(FOREST)
	if v8 == null or v9 == null or forest == null:
		_fail("v8/v9 원화 또는 Forest Ruins 배경을 읽지 못했습니다.")
		return
	var m8 := _measure(v8)
	var m9 := _measure(v9)
	if not png_header_valid(V8) or not png_header_valid(V9) or v8.get_size() != SIZE or v9.get_size() != SIZE or not m8.png_valid or not m9.png_valid:
		printerr("v8 size=%s format=%s metrics=%s; v9 size=%s format=%s metrics=%s" % [str(v8.get_size()), str(v8.get_format()), str(m8), str(v9.get_size()), str(v9.get_format()), str(m9)])
		_fail("입력 PNG의 규격 또는 유효한 알파 실루엣 검사가 실패했습니다.")
		return
	var board := _build_board(v8, v9, forest)
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("검수 이미지 폴더 생성 실패: %s" % error_string(directory_error))
		return
	var save_error := await _save_labeled_board(board, output_path)
	if save_error != OK:
		_fail("검수 이미지 저장 실패: %s" % error_string(save_error))
		return
	print("v9 review: v8 bounds=%s margins=%s safe=%s; v9 bounds=%s margins=%s safe=%s; 3x display=%d px; output=%s" % [
		str(m8.bounds), str(m8.margins), str(m8.safe_margin), str(m9.bounds), str(m9.margins), str(m9.safe_margin), DISPLAY_HEIGHT, output_path
	])
	print("v9 identity/style review remains a human visual decision; no game art was changed.")
	quit(0)

static func measure(image: Image) -> Dictionary:
	return _measure(image)

static func png_header_valid(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return false
	var bytes := FileAccess.get_file_as_bytes(absolute)
	if bytes.size() < 26 or bytes.slice(0, 8) != PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]):
		return false
	return bytes.slice(12, 16).get_string_from_ascii() == "IHDR" \
		and _u32be(bytes, 16) == SIZE.x and _u32be(bytes, 20) == SIZE.y \
		and bytes[24] == 8 and bytes[25] == 6

static func _u32be(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])

static func _measure(image: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {"valid": false, "png_valid": false, "safe_margin": false, "bounds": Rect2i(), "margins": Vector4i(), "opaque": 0, "transparent": 0}
	var bounds := _alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return {"valid": false, "png_valid": false, "safe_margin": false, "bounds": bounds, "margins": Vector4i(), "opaque": 0, "transparent": image.get_width() * image.get_height()}
	var margins := Vector4i(bounds.position.x, bounds.position.y, image.get_width() - bounds.end.x, image.get_height() - bounds.end.y)
	var alpha_pixels := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				alpha_pixels += 1
	var total := image.get_width() * image.get_height()
	var has_alpha := alpha_pixels < total
	var safe := margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN
	var png_valid := image.get_size() == SIZE and image.get_format() == Image.FORMAT_RGBA8 and has_alpha
	return {
		"valid": png_valid,
		"png_valid": png_valid,
		"safe_margin": safe,
		"bounds": bounds,
		"margins": margins,
		"opaque": alpha_pixels,
		"transparent": total - alpha_pixels,
		"occupancy": float(alpha_pixels) / float(total),
	}

static func _build_board(v8: Image, v9: Image, forest: Image) -> Image:
	var board := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("#161c22"))
	var variants := [v8, v9]
	var max_display_height := 0
	for image in variants:
		max_display_height = maxi(max_display_height, roundi(float(_alpha_bounds(image).size.y) * GAME_SPRITE_SCALE * CAMERA_ZOOM))
	# Full silhouettes use the current player's exact texture and camera scale.
	for index in range(2):
		var x := 38 + index * 922
		_draw_checker(board, Rect2i(x, 44, 906, 690))
		var image: Image = variants[index]
		var bounds := _alpha_bounds(image)
		var figure_height := roundi(float(bounds.size.y) * GAME_SPRITE_SCALE * CAMERA_ZOOM)
		var figure := _resize(image.get_region(bounds), _scaled_size(bounds.size, figure_height))
		var pos := Vector2i(x + (906 - figure.get_width()) / 2, 60 + max_display_height - figure.get_height())
		board.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), pos)
		board.fill_rect(Rect2i(x, 60 + max_display_height, 906, 3), Color("#f2d07d"))
		# Small color bars identify columns in the raster itself; file labels are
		# repeated in the accompanying UTF-8 gate document.
		board.fill_rect(Rect2i(x, 34, 906, 7), COLORS[index])
	_draw_text(board, "V8 CURRENT - GAME SCALE", Vector2i(48, 42), 3, Color.WHITE)
	_draw_text(board, "V9 FANTASY - SAME SCALE", Vector2i(970, 42), 3, Color.WHITE)
	# Actual Forest Ruins viewport comparison keeps the same source-pixel scale
	# for both assets, so v9's larger alpha silhouette remains visible.
	var screen_y := 740
	board.blit_rect(forest, Rect2i(Vector2i.ZERO, forest.get_size()), Vector2i(0, screen_y))
	for index in range(2):
		var image: Image = variants[index]
		var bounds := _alpha_bounds(image)
		var figure_height := roundi(float(bounds.size.y) * GAME_SPRITE_SCALE * CAMERA_ZOOM)
		var figure := _resize(image.get_region(bounds), _scaled_size(bounds.size, figure_height))
		board.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i(480 + index * 960 - figure.get_width() / 2, screen_y + 850 - figure.get_height()))
	board.fill_rect(Rect2i(0, screen_y + 850, 1920, 3), Color("#f2d07d"))
	# Four anchor pairs. Each crop is sampled at the same three-times source
	# scale as the silhouette above, preserving the game's pixel-to-screen ratio.
	var cell_width := 468
	var gap := 12
	var start_x := 12
	var start_y := 1860
	var row_height := 180
	for anchor_index in range(ANCHORS.size()):
		var anchor: Dictionary = ANCHORS[anchor_index]
		var cell_x := start_x + anchor_index * (cell_width + gap)
		board.fill_rect(Rect2i(cell_x, start_y - 9, cell_width, 5), Color("#78aeb6"))
		board.fill_rect(Rect2i(cell_x, start_y + row_height + 3, cell_width, 5), Color("#d5a15d"))
		for version in range(2):
			var image: Image = variants[version]
			var bounds := _alpha_bounds(image)
			var crop := _crop_relative(image, bounds, anchor.rect)
			var magnified_height := roundi(float(crop.get_height()) * GAME_SPRITE_SCALE * CAMERA_ZOOM * REVIEW_SCALE)
			var enlarged := _resize(crop, _scaled_size(crop.get_size(), magnified_height))
			var target := Rect2i(cell_x + 4, start_y + version * row_height, cell_width - 8, row_height - 4)
			_draw_checker(board, target)
			var fit := _fit(enlarged, Vector2i(target.size.x - 8, target.size.y - 8))
			board.blend_rect(fit, Rect2i(Vector2i.ZERO, fit.get_size()), target.position + (target.size - fit.get_size()) / 2)
		_draw_text(board, String(anchor.name).replace("_", " / ") + " - 3X", Vector2i(cell_x + 8, start_y - 35), 2, Color.WHITE)
	# Legend keys at the very bottom: version colors map to v8/current and v9.
	board.fill_rect(Rect2i(48, 2225, 24, 12), COLORS[0])
	board.fill_rect(Rect2i(300, 2225, 24, 12), COLORS[1])
	_draw_text(board, "CYAN = V8 CURRENT     GOLD = V9 FANTASY", Vector2i(48, 2242), 2, Color.WHITE)
	return board

static func _scaled_size(size: Vector2i, height: int) -> Vector2i:
	return Vector2i(maxi(1, roundi(float(size.x) * height / size.y)), height)

static func _alpha_bounds(image: Image) -> Rect2i:
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
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var left := bounds.position.x + floori(region.position.x * bounds.size.x)
	var top := bounds.position.y + floori(region.position.y * bounds.size.y)
	var right := bounds.position.x + ceili((region.position.x + region.size.x) * bounds.size.x)
	var bottom := bounds.position.y + ceili((region.position.y + region.size.y) * bounds.size.y)
	var rect := Rect2i(left, top, maxi(1, right - left), maxi(1, bottom - top)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)

static func _resize(source: Image, size: Vector2i) -> Image:
	var result := source.duplicate()
	result.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return result

static func _fit(source: Image, limit: Vector2i) -> Image:
	var scale := minf(float(limit.x) / source.get_width(), float(limit.y) / source.get_height())
	return _resize(source, Vector2i(maxi(1, roundi(source.get_width() * scale)), maxi(1, roundi(source.get_height() * scale))))

static func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 24):
		for x in range(rect.position.x, rect.end.x, 24):
			var shade := Color("#3d454c") if (((x - rect.position.x) / 24 + (y - rect.position.y) / 24) % 2 == 0) else Color("#272e34")
			image.fill_rect(Rect2i(x, y, mini(24, rect.end.x - x), mini(24, rect.end.y - y)), shade)

func _save_labeled_board(board: Image, output_path: String) -> Error:
	return board.save_png(output_path)

static func _draw_text(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	var glyphs := {
		"A":"01110/10001/10001/11111/10001/10001/10001", "B":"11110/10001/10001/11110/10001/10001/11110",
		"C":"01111/10000/10000/10000/10000/10000/01111", "D":"11110/10001/10001/10001/10001/10001/11110",
		"E":"11111/10000/10000/11110/10000/10000/11111", "F":"11111/10000/10000/11110/10000/10000/10000",
		"G":"01111/10000/10000/10111/10001/10001/01111", "H":"10001/10001/10001/11111/10001/10001/10001",
		"I":"11111/00100/00100/00100/00100/00100/11111", "J":"00111/00010/00010/00010/10010/10010/01100",
		"K":"10001/10010/10100/11000/10100/10010/10001", "L":"10000/10000/10000/10000/10000/10000/11111",
		"M":"10001/11011/10101/10101/10001/10001/10001", "N":"10001/11001/10101/10011/10001/10001/10001",
		"O":"01110/10001/10001/10001/10001/10001/01110", "P":"11110/10001/10001/11110/10000/10000/10000",
		"Q":"01110/10001/10001/10001/10101/10010/01101", "R":"11110/10001/10001/11110/10100/10010/10001",
		"S":"01111/10000/10000/01110/00001/00001/11110", "T":"11111/00100/00100/00100/00100/00100/00100",
		"U":"10001/10001/10001/10001/10001/10001/01110", "V":"10001/10001/10001/10001/10001/01010/00100",
		"W":"10001/10001/10001/10101/10101/10101/01010", "X":"10001/10001/01010/00100/01010/10001/10001",
		"Y":"10001/10001/01010/00100/00100/00100/00100", "Z":"11111/00001/00010/00100/01000/10000/11111",
		"3":"11110/00001/00001/01110/00001/00001/11110", "8":"01110/10001/10001/01110/10001/10001/01110",
		"9":"01110/10001/10001/01111/00001/00001/11110", "=":"00000/11111/00000/11111/00000/00000/00000",
		"-":"00000/00000/00000/11111/00000/00000/00000", "/":"00001/00010/00010/00100/01000/01000/10000",
		" ":"00000/00000/00000/00000/00000/00000/00000",
	}
	var cursor_x := origin.x
	for letter in value.to_upper():
		var rows: PackedStringArray = String(glyphs.get(letter, glyphs[" "])).split("/")
		for y in range(rows.size()):
			for x in range(rows[y].length()):
				if rows[y][x] == "1":
					image.fill_rect(Rect2i(cursor_x + x * scale, origin.y + y * scale, scale, scale), color)
		cursor_x += 6 * scale

static func _load_png(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _fail(message: String) -> void:
	push_error("player_v9_comparison: " + message)
	quit(1)
