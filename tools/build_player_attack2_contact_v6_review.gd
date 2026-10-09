extends SceneTree

const OUTPUT := "res://assets/art/review/player_attack2_contact_v6_comparison.png"
const SOURCE_PATHS := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
]
const SOURCE_LABELS := ["READY V8 APPROVED", "HIT 1 CONTACT", "HIT 2 MID SAFE", "HIT 2 CONTACT OLD"]
const V6_CANDIDATE_PATHS := [
	"res://assets/art/player/elven_fighter_attack2_v6_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v6_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_identity_candidate_1254x1254.png",
]
const CANVAS_SIZE := Vector2i(3768, 1000)
const PANEL_WIDTH := 720
const PANEL_GAP := 24
const LEFT := 24
const TOP := 116
const BASELINE := 820
const DISPLAY_HEIGHT := 576 # 3x the 192px gameplay sprite height.
const MIN_MARGIN := 90
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
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
	"W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
}

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var images: Array[Image] = []
	for path in SOURCE_PATHS:
		var image := _load_raw_image(path)
		if image == null:
			push_error("required review source missing or invalid: %s" % path)
			quit(1)
			return
		images.append(image)

	var candidate_path := _find_v6_candidate()
	var candidate: Image = null
	var candidate_valid := false
	if not candidate_path.is_empty():
		candidate = _load_raw_image(candidate_path)
		if candidate == null:
			push_error("v6 candidate exists but could not be decoded: %s" % candidate_path)
			quit(1)
			return
		var alpha_bounds := _alpha_bounds(candidate)
		var margins := _margins(candidate, alpha_bounds)
		candidate_valid = candidate.get_size() == Vector2i(1254, 1254) and candidate.get_format() == Image.FORMAT_RGBA8 \
			and alpha_bounds.size.x > 0 and margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN \
			and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN and _transparent_border(candidate)
		print("V6 CANDIDATE: %s | format=%s | canvas=%s | nonzero-alpha margins L/T/R/B=%d/%d/%d/%d | transparent_border=%s | mechanical_gate=%s" % [
			candidate_path, _format_name(candidate), str(candidate.get_size()), margins.x, margins.y,
			margins.z, margins.w, str(_transparent_border(candidate)), str(candidate_valid)])
		if candidate.get_format() != Image.FORMAT_RGBA8:
			candidate.convert(Image.FORMAT_RGBA8)
	else:
		print("V6 CANDIDATE: NOT PROVIDED; review panel records missing source.")

	var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_text(canvas, "ATTACK 2 CONTACT V6 REVIEW", Vector2i(LEFT, 28), 4, Color("#f0e8d8"))
	var status := "V6 CANDIDATE NOT PROVIDED" if candidate == null else ("V6 FOUND - MECHANICAL GATE PASS - HUMAN REVIEW REQUIRED" if candidate_valid else "V6 FOUND - MECHANICAL GATE FAIL - HUMAN REVIEW REQUIRED")
	_draw_text(canvas, status, Vector2i(LEFT, 68), 2, Color("#f1bd69") if candidate == null or not candidate_valid else Color("#82d4a2"))

	for index in range(5):
		var x := LEFT + index * (PANEL_WIDTH + PANEL_GAP)
		var panel := Rect2i(x, TOP, PANEL_WIDTH, BASELINE - TOP + 18)
		canvas.fill_rect(panel, Color("#252b32"))
		_draw_checker(canvas, Rect2i(x + 8, TOP + 8, PANEL_WIDTH - 16, BASELINE - TOP - 8))
		var label: String = SOURCE_LABELS[index] if index < SOURCE_LABELS.size() else "HIT 2 CONTACT V6"
		_draw_text(canvas, label, Vector2i(x + 18, TOP - 22), 2 if label.length() > 16 else 3, Color("#f0e8d8"))
		if index == 4 and candidate == null:
			_draw_text(canvas, "NOT PROVIDED", Vector2i(x + 228, 410), 4, Color("#f1bd69"))
			_draw_text(canvas, "AWAITING V6 FILE", Vector2i(x + 210, 460), 2, Color("#c7ccd0"))
			continue
		var source: Image = candidate if index == 4 else images[index]
		var bounds := _visible_bounds(source)
		if bounds.size.x <= 0:
			push_error("source has no visible-alpha pixels")
			quit(1)
			return
		var sprite := _aligned_sprite(source, bounds, DISPLAY_HEIGHT)
		var position := Vector2i(x + (PANEL_WIDTH - sprite.get_width()) / 2, BASELINE - DISPLAY_HEIGHT)
		canvas.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), position)
		var margins := _margins(source, _alpha_bounds(source))
		print("SOURCE %s | size=%s | format=%s | nonzero-alpha margins L/T/R/B=%d/%d/%d/%d | display_height=%d" % [
			candidate_path if index == 4 else SOURCE_PATHS[index], str(source.get_size()), _format_name(source),
			margins.x, margins.y, margins.z, margins.w, DISPLAY_HEIGHT])
	canvas.fill_rect(Rect2i(LEFT, BASELINE, CANVAS_SIZE.x - LEFT * 2, 3), Color("#f05c4f"))
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var error := canvas.save_png(output_path)
	if error != OK:
		push_error("could not save comparison: %s" % error_string(error))
		quit(1)
		return
	print("comparison generated: %s (%dx%d; all visible silhouettes shown at 3x gameplay height; v6_found=%s; v6_mechanical_gate=%s)" % [
		OUTPUT, CANVAS_SIZE.x, CANVAS_SIZE.y, str(candidate != null), str(candidate_valid)])
	quit(0)

func _find_v6_candidate() -> String:
	for path in V6_CANDIDATE_PATHS:
		if FileAccess.file_exists(path):
			return path
	return ""

func _load_raw_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))) != OK or image.is_empty():
		return null
	return image

func _alpha_bounds(image: Image) -> Rect2i:
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

func _visible_bounds(image: Image) -> Rect2i:
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

func _margins(image: Image, bounds: Rect2i) -> Vector4i:
	if bounds.size.x <= 0:
		return Vector4i(-1, -1, -1, -1)
	return Vector4i(bounds.position.x, bounds.position.y, image.get_width() - bounds.end.x, image.get_height() - bounds.end.y)

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a > 0.0 or image.get_pixel(x, image.get_height() - 1).a > 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a > 0.0 or image.get_pixel(image.get_width() - 1, y).a > 0.0:
			return false
	return true

func _aligned_sprite(source: Image, bounds: Rect2i, target_height: int) -> Image:
	var sprite := source.get_region(bounds)
	var target_width := maxi(1, int(round(float(bounds.size.x) * target_height / bounds.size.y)))
	sprite.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
	return sprite

func _format_name(image: Image) -> String:
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
