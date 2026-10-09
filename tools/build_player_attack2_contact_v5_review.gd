extends SceneTree

const OUTPUT := "res://assets/art/review/player_attack2_contact_v5_comparison.png"
const SOURCE_PATHS := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
]
const SOURCE_LABELS := ["READY V8", "HIT 1 CONTACT", "HIT 2 MID", "HIT 2 CONTACT OLD"]
const V5_CANDIDATE_PATHS := [
	"res://assets/art/player/elven_fighter_attack2_v5_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v5_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v5_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v5_identity_candidate_1254x1254.png",
]
const V5_LABEL := "HIT 2 CONTACT V5"
const CANVAS_SIZE := Vector2i(3744, 1000)
const PANEL_WIDTH := 720
const PANEL_GAP := 24
const LEFT := 24
const TOP := 116
const BASELINE := 820
const DISPLAY_HEIGHT := 576 # 192px game sprite, displayed at 3x.
const MIN_MARGIN := 90
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
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
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
}

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var sources: Array[String] = []
	var labels := SOURCE_LABELS.duplicate()
	for path in SOURCE_PATHS:
		var image := _load_image(path)
		if image == null:
			push_error("required review source missing or invalid: %s" % path)
			quit(1)
			return
		sources.append(path)

	var candidate_path := _find_v5_candidate()
	var candidate_found := not candidate_path.is_empty()
	var candidate_valid := false
	if candidate_found:
		var candidate := _load_raw_image(candidate_path)
		if candidate == null:
			push_error("v5 candidate exists but could not be decoded: %s" % candidate_path)
			quit(1)
			return
		var bounds := _alpha_bounds(candidate)
		var margins := _margins(candidate, bounds)
		candidate_valid = candidate.get_size() == Vector2i(1254, 1254) \
			and candidate.get_format() == Image.FORMAT_RGBA8 \
			and bounds.size.x > 0 and margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN \
			and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN
		print("V5 CANDIDATE: %s | format=%s | canvas=%s | nonzero-alpha margins L/T/R/B=%d/%d/%d/%d | mechanical_gate=%s" % [
			candidate_path, _format_name(candidate), str(candidate.get_size()), margins.x, margins.y,
			margins.z, margins.w, str(candidate_valid)])
		if candidate.get_format() != Image.FORMAT_RGBA8:
			candidate.convert(Image.FORMAT_RGBA8)
		sources.append(candidate_path)
		labels.append(V5_LABEL)
	else:
		sources.append("")
		labels.append(V5_LABEL)
		print("V5 CANDIDATE: NOT PROVIDED; comparison continues with four existing frames.")

	var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_text(canvas, "ATTACK 2 CONTACT V5 REVIEW", Vector2i(LEFT, 28), 4, Color("#f0e8d8"))
	var status := ("V5 CANDIDATE FOUND - HUMAN REVIEW REQUIRED" if candidate_valid else "V5 CANDIDATE FOUND - MECHANICAL FAIL - HUMAN REVIEW REQUIRED") if candidate_found else "V5 CANDIDATE NOT PROVIDED - EXISTING ART COMPARISON"
	_draw_text(canvas, status, Vector2i(LEFT, 68), 2, Color("#f1bd69") if not candidate_found or not candidate_valid else Color("#82d4a2"))
	for index in range(5):
		var x := LEFT + index * (PANEL_WIDTH + PANEL_GAP)
		canvas.fill_rect(Rect2i(x, TOP, PANEL_WIDTH, BASELINE - TOP + 18), Color("#252b32"))
		_draw_checker(canvas, Rect2i(x + 8, TOP + 8, PANEL_WIDTH - 16, BASELINE - TOP - 8))
		_draw_text(canvas, labels[index], Vector2i(x + 18, TOP - 22), 3, Color("#f0e8d8"))
		if sources[index].is_empty():
			_draw_text(canvas, "NOT PROVIDED", Vector2i(x + 214, 410), 4, Color("#f1bd69"))
			_draw_text(canvas, "AWAITING V5 FILE", Vector2i(x + 210, 460), 2, Color("#c7ccd0"))
			continue
		var source := _load_image(sources[index])
		var bounds := _visible_bounds(source)
		if bounds.size.x <= 0:
			push_error("source has no nonzero alpha pixels: %s" % sources[index])
			quit(1)
			return
		var sprite := _aligned_sprite(source, bounds, DISPLAY_HEIGHT)
		var position := Vector2i(x + (PANEL_WIDTH - sprite.get_width()) / 2, BASELINE - DISPLAY_HEIGHT)
		canvas.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), position)
		var metrics := _margins(source, bounds)
		print("SOURCE %s | size=%s | format=%s | visible-alpha(>=0.05) margins L/T/R/B=%d/%d/%d/%d | display_height=%d" % [
			sources[index], str(source.get_size()), _format_name(source), metrics.x, metrics.y, metrics.z, metrics.w, DISPLAY_HEIGHT])
	canvas.fill_rect(Rect2i(LEFT, BASELINE, CANVAS_SIZE.x - LEFT * 2, 3), Color("#f05c4f"))
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var error := canvas.save_png(output_path)
	if error != OK:
		push_error("could not save comparison: %s" % error_string(error))
		quit(1)
		return
	print("comparison generated: %s (%dx%d, each sprite shown at 3x game height; v5_found=%s; v5_mechanical_gate=%s)" % [OUTPUT, CANVAS_SIZE.x, CANVAS_SIZE.y, str(candidate_found), str(candidate_valid)])
	quit(0)

func _find_v5_candidate() -> String:
	for path in V5_CANDIDATE_PATHS:
		if FileAccess.file_exists(path):
			return path
	return ""

func _load_image(path: String) -> Image:
	var image := _load_raw_image(path)
	if image != null and image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _load_raw_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	var absolute_path := ProjectSettings.globalize_path(path)
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute_path)) != OK or image.is_empty():
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
