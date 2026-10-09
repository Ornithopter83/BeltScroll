extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const GAME_SCALE := 0.4469274 * 1.2
const THREE_X_SCALE := GAME_SCALE * 3.0
const V8 := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const V9 := "res://assets/art/player/elven_fighter_reference_v9_fantasy_1254x1254.png"
const V10 := "res://assets/art/player/elven_fighter_reference_v10_fantasy_1254x1254.png"
const OUTPUT := "res://assets/art/review/player_v10_comparison.png"
const BOARD_WIDTH := 3000
const HEADER_HEIGHT := 70
const FULL_ROW_HEIGHT := 840
const DETAIL_GAP := 72
const VERSIONS := ["V8 CURRENT", "V9 UNAPPROVED", "V10 CANDIDATE"]
const COLORS := [Color("#75b8bc"), Color("#e1ad68"), Color("#83bd83")]
const ANCHORS := [
	{"name": "FACE / EARS / HAIR", "rect": Rect2(0.23, 0.0, 0.54, 0.32)},
	{"name": "GUARD / ARMS", "rect": Rect2(0.08, 0.16, 0.84, 0.36)},
	{"name": "COSTUME / BODY", "rect": Rect2(0.15, 0.20, 0.70, 0.54)},
	{"name": "FEET / GROUND ANCHOR", "rect": Rect2(0.0, 0.64, 1.0, 0.36)},
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var images: Array[Image] = []
	var metrics: Array[Dictionary] = []
	for path in [V8, V9, V10]:
		var image := _load_png(path)
		if image == null or not png_header_valid(path):
			_fail("입력 PNG를 읽지 못했거나 1254×1254 8-bit RGBA 형식이 아닙니다: " + path)
			return
		images.append(image)
		metrics.append(measure(image))
	var board := _build_board(images)
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("검수판 폴더 생성 실패: " + error_string(directory_error))
		return
	var save_error := board.save_png(output_path)
	if save_error != OK:
		_fail("검수판 저장 실패: " + error_string(save_error))
		return
	for index in range(3):
		print("%s: bounds=%s margins(LTRB)=%s alpha=%d transparent=%d safe90=%s" % [VERSIONS[index], str(metrics[index].bounds), str(metrics[index].margins), metrics[index].opaque, metrics[index].transparent, metrics[index].safe_margin])
	print("comparison canvas=%s" % str(board.get_size()))
	print("v10 comparison generated at 3x gameplay detail scale; visual approval remains human; player stays on v8; output=" + output_path)
	quit(0)

static func png_header_valid(path: String) -> bool:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return false
	var bytes := FileAccess.get_file_as_bytes(absolute)
	return bytes.size() >= 26 \
		and bytes.slice(0, 8) == PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10]) \
		and bytes.slice(12, 16).get_string_from_ascii() == "IHDR" \
		and _u32be(bytes, 16) == SIZE.x and _u32be(bytes, 20) == SIZE.y \
		and bytes[24] == 8 and bytes[25] == 6

static func _u32be(bytes: PackedByteArray, offset: int) -> int:
	return (int(bytes[offset]) << 24) | (int(bytes[offset + 1]) << 16) | (int(bytes[offset + 2]) << 8) | int(bytes[offset + 3])

static func measure(image: Image) -> Dictionary:
	if image == null or image.is_empty():
		return {"png_valid": false, "safe_margin": false, "bounds": Rect2i(), "margins": Vector4i(), "opaque": 0, "transparent": 0}
	var bounds := _alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return {"png_valid": false, "safe_margin": false, "bounds": bounds, "margins": Vector4i(), "opaque": 0, "transparent": image.get_width() * image.get_height()}
	var margins := Vector4i(bounds.position.x, bounds.position.y, image.get_width() - bounds.end.x, image.get_height() - bounds.end.y)
	var alpha_pixels := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				alpha_pixels += 1
	var total := image.get_width() * image.get_height()
	return {
		"png_valid": image.get_size() == SIZE and image.get_format() == Image.FORMAT_RGBA8 and alpha_pixels > 0 and alpha_pixels < total,
		"safe_margin": margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN,
		"bounds": bounds, "margins": margins, "opaque": alpha_pixels, "transparent": total - alpha_pixels,
		"occupancy": float(alpha_pixels) / float(total),
	}

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

func _build_board(images: Array[Image]) -> Image:
	var detail_height := 0
	for anchor in ANCHORS:
		var anchor_height := 0
		for image in images:
			var crop := _crop_relative(image, _alpha_bounds(image), anchor.rect)
			anchor_height = maxi(anchor_height, roundi(crop.get_height() * THREE_X_SCALE))
		detail_height += 54 + anchor_height * 3 + DETAIL_GAP
	var board := Image.create(BOARD_WIDTH, HEADER_HEIGHT + FULL_ROW_HEIGHT + detail_height, false, Image.FORMAT_RGBA8)
	board.fill(Color("#161c22"))
	_draw_text(board, "PLAYER ART REVIEW - 3X GAME DETAIL / SOURCE PIXELS PRESERVED", Vector2i(36, 24), 3, Color.WHITE)
	var panel_width := BOARD_WIDTH / 3
	var canvas_display_height := roundi(SIZE.y * GAME_SCALE)
	for index in range(3):
		var x := index * panel_width
		_draw_checker(board, Rect2i(x + 8, HEADER_HEIGHT, panel_width - 16, FULL_ROW_HEIGHT - 20))
		board.fill_rect(Rect2i(x + 8, HEADER_HEIGHT, panel_width - 16, 8), COLORS[index])
		_draw_text(board, VERSIONS[index] + " / GAME SCALE", Vector2i(x + 28, HEADER_HEIGHT + 24), 3, Color.WHITE)
		var image := images[index]
		# Show the complete source canvas at gameplay scale so alpha margins and
		# texture-space foot placement remain visible in the full-body row.
		var figure := _resize(image, Vector2i(canvas_display_height, canvas_display_height))
		var pos := Vector2i(x + (panel_width - figure.get_width()) / 2, HEADER_HEIGHT + 100)
		board.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), pos)
	var y := HEADER_HEIGHT + FULL_ROW_HEIGHT
	for anchor in ANCHORS:
		var crops: Array[Image] = []
		var display_height := 0
		for image in images:
			var crop := _crop_relative(image, _alpha_bounds(image), anchor.rect)
			var enlarged := _resize(crop, _scaled_size(crop.get_size(), roundi(crop.get_height() * THREE_X_SCALE)))
			crops.append(enlarged)
			display_height = maxi(display_height, enlarged.get_height())
		_draw_text(board, String(anchor.name) + " / 3X GAME SCALE / V8 - V9 - V10, TOP TO BOTTOM", Vector2i(30, y + 8), 2, Color.WHITE)
		y += 46
		for index in range(3):
			var crop: Image = crops[index]
			var row := Rect2i(12, y, BOARD_WIDTH - 24, display_height)
			_draw_checker(board, row)
			board.fill_rect(Rect2i(row.position.x, row.position.y, 8, row.size.y), COLORS[index])
			board.blend_rect(crop, Rect2i(Vector2i.ZERO, crop.get_size()), Vector2i(24, y + (display_height - crop.get_height()) / 2))
			y += display_height
		y += DETAIL_GAP
	return board

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var left := bounds.position.x + floori(region.position.x * bounds.size.x)
	var top := bounds.position.y + floori(region.position.y * bounds.size.y)
	var right := bounds.position.x + ceili((region.position.x + region.size.x) * bounds.size.x)
	var bottom := bounds.position.y + ceili((region.position.y + region.size.y) * bounds.size.y)
	var rect := Rect2i(left, top, maxi(1, right - left), maxi(1, bottom - top)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)

static func _scaled_size(size: Vector2i, height: int) -> Vector2i:
	return Vector2i(maxi(1, roundi(float(size.x) * height / size.y)), height)

static func _resize(source: Image, size: Vector2i) -> Image:
	var result := source.duplicate()
	result.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return result

static func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 24):
		for x in range(rect.position.x, rect.end.x, 24):
			var shade := Color("#3d454c") if (((x - rect.position.x) / 24 + (y - rect.position.y) / 24) % 2 == 0) else Color("#272e34")
			image.fill_rect(Rect2i(x, y, mini(24, rect.end.x - x), mini(24, rect.end.y - y)), shade)

static func _draw_text(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	var glyphs := {
		"A":"01110/10001/10001/11111/10001/10001/10001", "B":"11110/10001/10001/11110/10001/10001/11110", "C":"01111/10000/10000/10000/10000/10000/01111", "D":"11110/10001/10001/10001/10001/10001/11110", "E":"11111/10000/10000/11110/10000/10000/11111", "F":"11111/10000/10000/11110/10000/10000/10000", "G":"01111/10000/10000/10111/10001/10001/01111", "H":"10001/10001/10001/11111/10001/10001/10001", "I":"11111/00100/00100/00100/00100/00100/11111", "J":"00111/00010/00010/00010/10010/10010/01100", "K":"10001/10010/10100/11000/10100/10010/10001", "L":"10000/10000/10000/10000/10000/10000/11111", "M":"10001/11011/10101/10101/10001/10001/10001", "N":"10001/11001/10101/10011/10001/10001/10001", "O":"01110/10001/10001/10001/10001/10001/01110", "P":"11110/10001/10001/11110/10000/10000/10000", "Q":"01110/10001/10001/10001/10101/10010/01101", "R":"11110/10001/10001/11110/10100/10010/10001", "S":"01111/10000/10000/01110/00001/00001/11110", "T":"11111/00100/00100/00100/00100/00100/00100", "U":"10001/10001/10001/10001/10001/10001/01110", "V":"10001/10001/10001/10001/10001/01010/00100", "W":"10001/10001/10001/10101/10101/10101/01010", "X":"10001/10001/01010/00100/01010/10001/10001", "Y":"10001/10001/01010/00100/00100/00100/00100", "Z":"11111/00001/00010/00100/01000/10000/11111",
		"0":"01110/10001/10011/10101/11001/10001/01110", "1":"00100/01100/00100/00100/00100/00100/01110", "3":"11110/00001/00001/01110/00001/00001/11110", "8":"01110/10001/10001/01110/10001/10001/01110", "9":"01110/10001/10001/01111/00001/00001/11110", "-":"00000/00000/00000/11111/00000/00000/00000", "/":"00001/00010/00010/00100/01000/01000/10000", " ":"00000/00000/00000/00000/00000/00000/00000"
	}
	var cursor_x := origin.x
	for letter in value.to_upper():
		var rows: PackedStringArray = String(glyphs.get(letter, glyphs[" "])).split("/")
		for gy in range(rows.size()):
			for gx in range(rows[gy].length()):
				if rows[gy][gx] == "1":
					image.fill_rect(Rect2i(cursor_x + gx * scale, origin.y + gy * scale, scale, scale), color)
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
	push_error("player_v10_comparison: " + message)
	quit(1)
