extends SceneTree

const OUTPUT := "res://assets/art/review/player_attack3_startup_comparison.png"
const SOURCE_PATHS := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png",
]
const SOURCE_LABELS := ["V8 READY", "HIT 2 SAFE", "HIT 3 CONTACT OLD"]
const STARTUP_PATHS := [
	"res://assets/art/player/elven_fighter_attack3_startup_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_startup_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_inbetween_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_intermediate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_intermediate_v1_1254x1254.png",
]
const CANVAS_HEIGHT := 1000
const PANEL_WIDTH := 720
const PANEL_GAP := 24
const LEFT := 24
const TOP := 116
const BASELINE := 820
const MIN_MARGIN := 90
const DISPLAY_HEIGHT := 576 # 3x a 192px game sprite.
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
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
	"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
}

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var images: Array = []
	var labels: Array[String] = []
	var paths: Array[String] = []
	for index in range(SOURCE_PATHS.size()):
		var image := _load_raw(SOURCE_PATHS[index])
		if image == null:
			push_error("required startup review source missing or invalid: %s" % SOURCE_PATHS[index])
			quit(1)
			return
		images.append(image)
		labels.append(SOURCE_LABELS[index])
		paths.append(SOURCE_PATHS[index])

	var startup_path := _find_startup()
	var startup: Image = null
	var startup_valid := false
	if not startup_path.is_empty():
		startup = _load_raw(startup_path)
		if startup == null:
			push_error("startup candidate exists but cannot be decoded: %s" % startup_path)
			quit(1)
			return
		startup_valid = _strict_safe(startup)
		var bounds := _alpha_bounds(startup)
		var margins := _margins(startup, bounds)
		print("STARTUP QUALITY: %s | format=%s | canvas=%s | nonzero-alpha margins L/T/R/B=%d/%d/%d/%d | transparent_border=%s | strict_gate=%s" % [
			startup_path, _format_name(startup), str(startup.get_size()), margins.x, margins.y, margins.z, margins.w,
			str(_transparent_border(startup)), str(startup_valid)])
		if startup.get_format() != Image.FORMAT_RGBA8:
			startup.convert(Image.FORMAT_RGBA8)
		images.insert(2, startup)
		labels.insert(2, "HIT 3 STARTUP")
		paths.insert(2, startup_path)
	else:
		print("STARTUP QUALITY: NOT PROVIDED; existing poses only.")
		images.insert(2, null)
		labels.insert(2, "HIT 3 STARTUP")
		paths.insert(2, "")

	var canvas_width := LEFT * 2 + images.size() * PANEL_WIDTH + (images.size() - 1) * PANEL_GAP
	var canvas := Image.create(canvas_width, CANVAS_HEIGHT, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_text(canvas, "ATTACK 2 TO 3 STARTUP GATE", Vector2i(LEFT, 28), 4, Color("#f0e8d8"))
	var status := "STARTUP NOT PROVIDED" if startup == null else ("MECHANICAL PASS - HUMAN REVIEW REQUIRED" if startup_valid else "MECHANICAL FAIL - HUMAN REVIEW REQUIRED")
	var status_color := Color("#f1bd69") if startup == null or not startup_valid else Color("#82d4a2")
	_draw_text(canvas, status, Vector2i(LEFT, 68), 2, status_color)

	for index in range(images.size()):
		var x := LEFT + index * (PANEL_WIDTH + PANEL_GAP)
		canvas.fill_rect(Rect2i(x, TOP, PANEL_WIDTH, BASELINE - TOP + 18), Color("#252b32"))
		_draw_checker(canvas, Rect2i(x + 8, TOP + 8, PANEL_WIDTH - 16, BASELINE - TOP - 8))
		var label := labels[index] if index < labels.size() else "HIT 3 STARTUP"
		_draw_text(canvas, label, Vector2i(x + 18, TOP - 22), 3, Color("#f0e8d8"))
		if images[index] == null:
			_draw_text(canvas, "NOT PROVIDED", Vector2i(x + 228, 400), 4, Color("#f1bd69"))
			_draw_text(canvas, "WAITING FOR ART", Vector2i(x + 210, 452), 2, Color("#c7ccd0"))
			continue
		var source: Image = images[index]
		var bounds := _visible_bounds(source)
		if bounds.size.x <= 0:
			push_error("source has no visible alpha pixels: %s" % paths[index])
			quit(1)
			return
		var sprite := _scaled_sprite(source, bounds, DISPLAY_HEIGHT)
		var position := Vector2i(x + (PANEL_WIDTH - sprite.get_width()) / 2, BASELINE - DISPLAY_HEIGHT)
		canvas.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), position)
		var alpha_bounds := _alpha_bounds(source)
		var margins := _margins(source, alpha_bounds)
		print("SOURCE %s | size=%s | format=%s | nonzero-alpha margins L/T/R/B=%d/%d/%d/%d | display_height=%d" % [
			paths[index], str(source.get_size()), _format_name(source), margins.x, margins.y, margins.z, margins.w, DISPLAY_HEIGHT])
	canvas.fill_rect(Rect2i(LEFT, BASELINE, canvas_width - LEFT * 2, 3), Color("#f05c4f"))
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var error := canvas.save_png(output_path)
	if error != OK:
		push_error("could not save startup review comparison: %s" % error_string(error))
		quit(1)
		return
	print("comparison generated: %s (%dx%d; 3x display; startup_found=%s; startup_mechanical_gate=%s)" % [
		OUTPUT, canvas_width, CANVAS_HEIGHT, str(startup != null), str(startup_valid)])
	quit(0)

static func _find_startup() -> String:
	for path in STARTUP_PATHS:
		if FileAccess.file_exists(path):
			return path
	return ""

static func _load_raw(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))) != OK or image.is_empty():
		return null
	return image

static func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func _visible_bounds(image: Image) -> Rect2i:
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

static func _margins(image: Image, bounds: Rect2i) -> Vector4i:
	if bounds.size.x <= 0:
		return Vector4i(-1, -1, -1, -1)
	return Vector4i(bounds.position.x, bounds.position.y, image.get_width() - bounds.end.x, image.get_height() - bounds.end.y)

static func _strict_safe(image: Image) -> bool:
	if image.get_size() != Vector2i(1254, 1254) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _alpha_bounds(image)
	var margins := _margins(image, bounds)
	return bounds.size.x > 0 and margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN \
		and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN and _transparent_border(image)

static func _transparent_border(image: Image) -> bool:
	if image.is_empty():
		return false
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a > 0.0 or image.get_pixel(x, image.get_height() - 1).a > 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a > 0.0 or image.get_pixel(image.get_width() - 1, y).a > 0.0:
			return false
	return true

static func _scaled_sprite(source: Image, bounds: Rect2i, target_height: int) -> Image:
	var sprite := source.get_region(bounds)
	var width := maxi(1, int(round(float(bounds.size.x) * target_height / bounds.size.y)))
	sprite.resize(width, target_height, Image.INTERPOLATE_LANCZOS)
	return sprite

static func _format_name(image: Image) -> String:
	return "RGBA8" if image.get_format() == Image.FORMAT_RGBA8 else "format_%d" % image.get_format()

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







