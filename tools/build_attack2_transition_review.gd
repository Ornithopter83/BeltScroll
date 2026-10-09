extends SceneTree

const OUTPUT := "res://assets/art/review/player_attack2_transition_comparison.png"
const SOURCE_PATHS := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png",
]
const LABELS := ["READY / V8", "HIT 1 / CONTACT", "HIT 2 / CONTACT", "HIT 3 / CONTACT"]
const OPTIONAL_MID_PATHS := [
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_intermediate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_intermediate_v1_1254x1254.png",
]
const CANVAS_SIZE := Vector2i(3000, 1000)
const GAME_HEIGHT := 192
const DISPLAY_SCALE := 3
const DISPLAY_HEIGHT := GAME_HEIGHT * DISPLAY_SCALE
const PANEL_WIDTH := 720
const PANEL_GAP := 24
const LEFT := 24
const TOP := 116
const BASELINE := 820
const MIN_MARGIN := 90
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
}

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var images: Array[Image] = []
	var labels: Array[String] = []
	var sources: Array[String] = []
	for index in range(SOURCE_PATHS.size()):
		var image := _load_image(SOURCE_PATHS[index])
		if image == null:
			push_error("transition review source missing or invalid: %s" % SOURCE_PATHS[index])
			quit(1)
			return
		images.append(image)
		labels.append(LABELS[index])
		sources.append(SOURCE_PATHS[index])

	var mid_path := _find_intermediate()
	var intermediate_found := not mid_path.is_empty()
	var middle_valid := false
	if intermediate_found:
		var middle := _load_unconverted_image(mid_path)
		if middle == null:
			push_error("intermediate art could not be decoded: %s" % mid_path)
			quit(1)
			return
		middle_valid = _valid_canvas(middle)
		var middle_bounds := _alpha_bounds(middle)
		var format_label := "RGBA8" if middle.get_format() == Image.FORMAT_RGBA8 else "format_%d" % middle.get_format()
		var border_stats := _border_alpha_stats(middle)
		print("INTERMEDIATE QUALITY: %s | format=%s canvas=%s margins L/T/R/B=%d/%d/%d/%d border_transparent=%s border_nonzero=%d border_max_alpha=%.4f | %s | strict_rgba_safe=%s" % [
			mid_path, format_label, str(middle.get_size()), middle_bounds.position.x, middle_bounds.position.y,
			middle.get_width() - middle_bounds.end.x, middle.get_height() - middle_bounds.end.y,
			str(_transparent_border(middle)), border_stats[0], border_stats[1], _metrics_line(middle, middle_bounds), str(middle_valid)])
		if middle.get_format() != Image.FORMAT_RGBA8:
			middle.convert(Image.FORMAT_RGBA8)
		# Keep the sequence readable: ready, hit 1, hit 2 in-between, hit 2 contact, hit 3.
		images.insert(2, middle)
		labels.insert(2, "HIT 2 MID")
		sources.insert(2, mid_path)

	var width := LEFT * 2 + images.size() * PANEL_WIDTH + (images.size() - 1) * PANEL_GAP
	var canvas := Image.create(width, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_text(canvas, "ATTACK TRANSITION REVIEW", Vector2i(LEFT, 28), 4, Color("#f0e8d8"))
	var status := ("MID FOUND" if middle_valid else "MID SAFE CHECK FAIL") if intermediate_found else "MID - NOT FOUND"
	var status_color := Color("#82d4a2") if middle_valid else Color("#ef7770") if intermediate_found else Color("#f1bd69")
	_draw_text(canvas, status, Vector2i(LEFT, 68), 2,
		status_color)

	for index in range(images.size()):
		var x := LEFT + index * (PANEL_WIDTH + PANEL_GAP)
		var panel := Rect2i(x, TOP, PANEL_WIDTH, BASELINE - TOP + 18)
		canvas.fill_rect(panel, Color("#252b32"))
		_draw_checker(canvas, Rect2i(x + 8, TOP + 8, PANEL_WIDTH - 16, BASELINE - TOP - 8))
		_draw_text(canvas, labels[index], Vector2i(x + 18, TOP - 22), 3, Color("#f0e8d8"))

		var bounds := _alpha_bounds(images[index])
		var sprite := _aligned_sprite(images[index], bounds, DISPLAY_HEIGHT)
		var position := Vector2i(x + (PANEL_WIDTH - sprite.get_width()) / 2, BASELINE - DISPLAY_HEIGHT)
		canvas.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), position)
		canvas.fill_rect(Rect2i(x + 8, BASELINE, PANEL_WIDTH - 16, 3), Color("#f05c4f"))
		var metrics := _metrics_line(images[index], bounds)
		# Numeric panel details are printed by the build tool and recorded in the review log.

		print("SOURCE %s | %s" % [sources[index], metrics])
	if not intermediate_found:
		print("INTERMEDIATE: not found (searched explicit attack2_intermediate filenames)")

	var output_path := ProjectSettings.globalize_path(OUTPUT)
	var output_dir := output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(output_dir):
		var mkdir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if mkdir_error != OK:
			push_error("cannot create review output directory: %s" % error_string(mkdir_error))
			quit(1)
			return
	var save_error := canvas.save_png(output_path)
	if save_error != OK:
		push_error("cannot save transition review: %s" % error_string(save_error))
		quit(1)
		return
	print("transition review generated: %s (%dx%d, %dx game-size sprites, intermediate=%s, strict_safe=%s)" % [OUTPUT, width, CANVAS_SIZE.y, DISPLAY_SCALE, str(intermediate_found), str(middle_valid)])
	quit(0)

func _find_intermediate() -> String:
	for path in OPTIONAL_MID_PATHS:
		if FileAccess.file_exists(path):
			return path
	return ""

func _load_image(path: String) -> Image:
	var image := _load_unconverted_image(path)
	if image != null and image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _load_unconverted_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	var absolute_path := ProjectSettings.globalize_path(path)
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute_path)) != OK or image.is_empty():
		return null
	return image

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != Vector2i(1254, 1254) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return false
	return bounds.position.x >= MIN_MARGIN and bounds.position.y >= MIN_MARGIN \
		and 1254 - bounds.end.x >= MIN_MARGIN and 1254 - bounds.end.y >= MIN_MARGIN \
		and _transparent_border(image)

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, image.get_height() - 1).a != 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(image.get_width() - 1, y).a != 0.0:
			return false
	return true

func _border_alpha_stats(image: Image) -> Array:
	var count := 0
	var max_alpha := 0.0
	for x in range(image.get_width()):
		for y in [0, image.get_height() - 1]:
			var alpha := image.get_pixel(x, y).a
			if alpha > 0.0:
				count += 1
				max_alpha = maxf(max_alpha, alpha)
	for y in range(1, image.get_height() - 1):
		for x in [0, image.get_width() - 1]:
			var alpha := image.get_pixel(x, y).a
			if alpha > 0.0:
				count += 1
				max_alpha = maxf(max_alpha, alpha)
	return [count, max_alpha]

func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.05:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

func _aligned_sprite(source: Image, bounds: Rect2i, target_height: int) -> Image:
	var sprite := source.get_region(bounds)
	var target_width := maxi(1, int(round(float(bounds.size.x) * target_height / bounds.size.y)))
	sprite.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
	return sprite

func _metrics_line(image: Image, bounds: Rect2i) -> String:
	var bottom_row := bounds.end.y - 1
	var leftmost := image.get_width()
	var rightmost := -1
	for x in range(bounds.position.x, bounds.end.x):
		for y in range(maxi(bounds.position.y, bottom_row - 4), bounds.end.y):
			if image.get_pixel(x, y).a >= 0.05:
				leftmost = mini(leftmost, x)
				rightmost = maxi(rightmost, x)
				break
	return "alpha %d,%d %dx%d | bottom contact x %d-%d | 3x height %d px" % [
		bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y,
		leftmost if rightmost >= 0 else -1, rightmost, DISPLAY_HEIGHT]

func _draw_text(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	var cursor_x := origin.x
	for character in value:
		var glyph: Array = FONT.get(character, FONT[" "])
		for row in range(glyph.size()):
			for column in range(5):
				if glyph[row].substr(column, 1) == "1":
					image.fill_rect(Rect2i(cursor_x + column * scale, origin.y + row * scale, scale, scale), color)
		cursor_x += 6 * scale

func _draw_checker(image: Image, rect: Rect2i) -> void:
	var tile := 24
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var shade := Color("#444a50") if (((x - rect.position.x) / tile + (y - rect.position.y) / tile) % 2) == 0 else Color("#30363c")
			image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), shade)
