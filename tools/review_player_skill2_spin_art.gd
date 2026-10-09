extends SceneTree

const IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const NUM4_PATH := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png"
const NUM5_V1_PATH := "res://assets/art/player/elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png"
const NUM5_V2_SOURCE_PATH := "res://assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png"
const NUM5_V2_SAFE_PATH := "res://assets/art/player/elven_fighter_skill2_spin_backfist_v2_safe_candidate_1254x1254.png"
const OUTPUT_PATH := "res://assets/art/review/player_skill2_spin_art_comparison.png"
const SOURCE_SIZE := Vector2i(1254, 1254)
const SAFE_INSET := 90
const RESAMPLE_GUARD := 12
const MAX_CONTENT := Vector2i(SOURCE_SIZE.x - (SAFE_INSET + RESAMPLE_GUARD) * 2, SOURCE_SIZE.y - (SAFE_INSET + RESAMPLE_GUARD) * 2)
const GAME_SIZE := 192
const PANEL_WIDTH := 430
const PANEL_HEIGHT := 520
const GUTTER := 12

const FONT := {
	" ": ["000", "000", "000", "000", "000"], "-": ["000", "000", "111", "000", "000"],
	"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"],
	"2": ["110", "001", "111", "100", "111"], "4": ["101", "101", "111", "001", "001"],
	"5": ["111", "100", "110", "001", "110"], "8": ["111", "101", "111", "101", "111"],
	"A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"],
	"C": ["011", "100", "100", "100", "011"], "D": ["110", "101", "101", "101", "110"],
	"E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
	"G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"],
	"I": ["111", "010", "010", "010", "111"], "L": ["100", "100", "100", "100", "111"],
	"M": ["101", "111", "111", "101", "101"], "N": ["101", "111", "111", "111", "101"],
	"O": ["111", "101", "101", "101", "111"], "P": ["110", "101", "110", "100", "100"],
	"R": ["110", "101", "110", "101", "101"], "S": ["011", "100", "010", "001", "110"],
	"T": ["111", "010", "010", "010", "010"], "U": ["101", "101", "101", "101", "111"],
	"V": ["101", "101", "101", "101", "010"], "X": ["101", "101", "010", "101", "101"],
	"Y": ["101", "101", "010", "010", "010"], "Z": ["111", "001", "010", "100", "111"]
}

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var source_bytes := _read_bytes(NUM5_V2_SOURCE_PATH)
	var source := _load_png(NUM5_V2_SOURCE_PATH)
	if source == null or source.get_size() != SOURCE_SIZE or source.get_format() != Image.FORMAT_RGBA8:
		_fail("v2 source must be the actual backfist candidate in 1254x1254 RGBA8")
		return
	var safe := _make_safe_candidate(source)
	if safe == null:
		_fail("could not prepare a safe v2 derivative")
		return
	var safe_absolute := ProjectSettings.globalize_path(NUM5_V2_SAFE_PATH)
	DirAccess.make_dir_recursive_absolute(safe_absolute.get_base_dir())
	if safe.save_png(safe_absolute) != OK:
		_fail("could not save safe v2 derivative")
		return
	if _read_bytes(NUM5_V2_SOURCE_PATH) != source_bytes:
		_fail("original backfist candidate bytes changed unexpectedly")
		return

	var paths := [IDLE_PATH, NUM4_PATH, NUM5_V1_PATH, NUM5_V2_SAFE_PATH]
	var labels := ["V8 IDLE", "NUM4 SAFE RUSH", "NUM5 V1 CONTACT", "NUM5 V2 SAFE"]
	var images: Array[Image] = []
	for path in paths:
		var image := _load_png(path)
		if image == null:
			_fail("required comparison source missing or invalid: " + path)
			return
		if image.get_size() != SOURCE_SIZE or image.get_format() != Image.FORMAT_RGBA8:
			_fail("review source must be 1254x1254 RGBA8: " + path)
			return
		images.append(image)

	var canvas := Image.create(PANEL_WIDTH * 4 + GUTTER * 5, PANEL_HEIGHT, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	for index in range(4):
		var x := GUTTER + index * (PANEL_WIDTH + GUTTER)
		canvas.fill_rect(Rect2i(x, 12, PANEL_WIDTH, PANEL_HEIGHT - 24), Color("#252b32"))
		_draw_text(canvas, labels[index], Vector2i(x + 20, 28), 3, Color("#f0e8d8"))
		_draw_text(canvas, "RIGHT", Vector2i(x + 64, 78), 2, Color("#c7ccd0"))
		_draw_text(canvas, "MIRROR", Vector2i(x + 267, 78), 2, Color("#c7ccd0"))
		var game_image := images[index].duplicate()
		game_image.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
		var mirrored := game_image.duplicate()
		mirrored.flip_x()
		var display := game_image
		var display_mirror := mirrored
		_draw_checker(canvas, Rect2i(x + 12, 98, GAME_SIZE, GAME_SIZE))
		_draw_checker(canvas, Rect2i(x + 226, 98, GAME_SIZE, GAME_SIZE))
		canvas.blend_rect(display, Rect2i(Vector2i.ZERO, display.get_size()), Vector2i(x + 12, 98))
		canvas.blend_rect(display_mirror, Rect2i(Vector2i.ZERO, display_mirror.get_size()), Vector2i(x + 226, 98))
		_print_metrics(paths[index], images[index], game_image)
	_draw_text(canvas, "STRAIGHT PUNCH READ NOT ACCEPTED - HUMAN REVIEW", Vector2i(22, 488), 2, Color("#f1bd69"))
	_draw_text(canvas, "1254X1254 TO 192X192 - SAME CANVAS - RIGHT AND HORIZONTAL MIRROR", Vector2i(22, 504), 1, Color("#a9c8c2"))
	var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	if canvas.save_png(absolute) != OK:
		_fail("could not save comparison board")
		return
	print("comparison generated: %s (%dx%d; source_bytes_preserved=true)" % [OUTPUT_PATH, canvas.get_width(), canvas.get_height()])
	quit(0)

func _make_safe_candidate(original: Image) -> Image:
	var image := original.duplicate()
	image.convert(Image.FORMAT_RGBA8)
	var source_isolated := _clear_isolated(image)
	var bounds := _alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var scale := minf(float(MAX_CONTENT.x) / float(bounds.size.x), float(MAX_CONTENT.y) / float(bounds.size.y))
	var fitted := Vector2i(roundi(float(bounds.size.x) * scale), roundi(float(bounds.size.y) * scale))
	var cropped: Image = image.get_region(bounds)
	var scaled := _resize_premultiplied(cropped, fitted)
	if scaled == null:
		return null
	var result := Image.create(SOURCE_SIZE.x, SOURCE_SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	var offset := Vector2i((SOURCE_SIZE.x - fitted.x) / 2, (SOURCE_SIZE.y - fitted.y) / 2)
	result.blit_rect(scaled, Rect2i(Vector2i.ZERO, fitted), offset)
	_clear_isolated(result)
	_zero_transparent_rgb(result)
	var margins := _margins(_alpha_bounds(result))
	print("SAFE_SOURCE %s | size=%s format=RGBA8 | source_bounds=%s | source_margins=%s | isolated_removed=%d | source_sha256=%s" % [NUM5_V2_SOURCE_PATH, str(original.get_size()), str(_alpha_bounds(original)), str(_margins(_alpha_bounds(original))), source_isolated, _sha(_read_bytes(NUM5_V2_SOURCE_PATH))])
	print("SAFE_DERIVATIVE %s | fitted=%s | scale=%.6f | alpha_margins_LTRB=%s | isolated_after=%d | transparent_border=%s" % [NUM5_V2_SAFE_PATH, str(fitted), scale, str(margins), _isolated_count(result), str(_transparent_border(result))])
	if margins.x < SAFE_INSET or margins.y < SAFE_INSET or margins.z < SAFE_INSET or margins.w < SAFE_INSET or _isolated_count(result) != 0 or not _transparent_border(result):
		return null
	return result

func _print_metrics(path: String, image: Image, game_image: Image) -> void:
	var bounds := _alpha_bounds(image)
	var margins := _margins(bounds)
	var game_bounds := _alpha_bounds(game_image, 0.05)
	print("REVIEW %s exists=true canvas=%s format=RGBA8 alpha_bounds=%s alpha_size=%s margins_LTRB=%s isolated_alpha_pixels=%d game_192_alpha_bounds=%s mirrored=true" % [path, str(image.get_size()), str(bounds), str(bounds.size), str(margins), _isolated_count(image), str(game_bounds)])

func _load_png(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _read_bytes(path: String) -> PackedByteArray:
	var absolute := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(absolute) if FileAccess.file_exists(absolute) else PackedByteArray()

func _sha(data: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()

func _alpha_bounds(image: Image, threshold: float = 0.0) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > threshold:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

func _margins(bounds: Rect2i) -> Vector4i:
	return Vector4i(bounds.position.x, bounds.position.y, SOURCE_SIZE.x - bounds.end.x, SOURCE_SIZE.y - bounds.end.y)

func _clear_isolated(image: Image) -> int:
	var width := image.get_width()
	var height := image.get_height()
	var mask := PackedByteArray()
	mask.resize(width * height)
	for y in range(height):
		for x in range(width):
			mask[y * width + x] = 1 if image.get_pixel(x, y).a > 0.0 else 0
	var removed := 0
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			if mask[index] == 0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < width and ny < height and mask[ny * width + nx] != 0:
						neighbor = true
				if neighbor:
					break
			if not neighbor:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				removed += 1
	return removed

func _isolated_count(image: Image) -> int:
	var duplicate := image.duplicate()
	return _isolated_count_by_mask(duplicate)

func _isolated_count_by_mask(image: Image) -> int:
	var width := image.get_width()
	var height := image.get_height()
	var mask := PackedByteArray()
	mask.resize(width * height)
	for y in range(height):
		for x in range(width):
			mask[y * width + x] = 1 if image.get_pixel(x, y).a > 0.0 else 0
	var count := 0
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			if mask[index] == 0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < width and ny < height and mask[ny * width + nx] != 0:
						neighbor = true
				if neighbor:
					break
			if not neighbor:
				count += 1
	return count

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, image.get_height() - 1).a != 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(image.get_width() - 1, y).a != 0.0:
			return false
	return true

func _zero_transparent_rgb(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a == 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

func _resize_premultiplied(source: Image, target_size: Vector2i) -> Image:
	var image := source.duplicate()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(pixel.r * pixel.a, pixel.g * pixel.a, pixel.b * pixel.a, pixel.a))
	image.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel: Color = image.get_pixel(x, y)
			if pixel.a <= 0.00001:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, Color(clampf(pixel.r / pixel.a, 0.0, 1.0), clampf(pixel.g / pixel.a, 0.0, 1.0), clampf(pixel.b / pixel.a, 0.0, 1.0), clampf(pixel.a, 0.0, 1.0)))
	return image

func _draw_checker(canvas: Image, rect: Rect2i) -> void:
	var tile := 16
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var parity := ((x - rect.position.x) / tile + (y - rect.position.y) / tile) % 2
			canvas.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), Color("#343c45") if parity == 0 else Color("#2b323a"))

func _draw_text(canvas: Image, value: String, position: Vector2i, scale: int, color: Color) -> void:
	var cursor_x := position.x
	for character in value:
		var rows: Array = FONT.get(character, FONT[" "])
		for row_index in range(rows.size()):
			for column in range(3):
				if rows[row_index].substr(column, 1) == "1":
					canvas.fill_rect(Rect2i(cursor_x + column * scale, position.y + row_index * scale, scale, scale), color)
		cursor_x += 4 * scale

func _fail(message: String) -> void:
	push_error("review_player_skill2_spin_art: " + message)
	quit(1)
