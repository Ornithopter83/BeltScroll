extends SceneTree

const IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const NUM4_PATH := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png"
const NUM5_V1_PATH := "res://assets/art/player/elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png"
const NUM5_V2_PATH := "res://assets/art/player/elven_fighter_skill2_spin_contact_v2_candidate_1254x1254.png"
const OUTPUT_PATH := "res://assets/art/review/player_skill2_spin_art_comparison.png"
const SOURCE_SIZE := Vector2i(1254, 1254)
const GAME_SIZE := 192
const SCALE := 2
const PANEL_WIDTH := 430
const PANEL_HEIGHT := 520
const GUTTER := 12

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var paths := [IDLE_PATH, NUM4_PATH, NUM5_V1_PATH]
	var labels := ["V8 IDLE", "NUM4 SAFE RUSH", "NUM5 V1 CONTACT"]
	var images: Array[Image] = []
	for path in paths:
		var image := _load_png(path)
		if image == null:
			push_error("required review source missing or invalid: " + path)
			quit(1)
			return
		if image.get_size() != SOURCE_SIZE:
			push_error("review source must be 1254x1254: %s is %s" % [path, str(image.get_size())])
			quit(1)
			return
		images.append(image)

	var v2_available := FileAccess.file_exists(NUM5_V2_PATH)
	if v2_available:
		var v2 := _load_png(NUM5_V2_PATH)
		if v2 == null:
			push_error("Num5 v2 exists but is not a readable PNG: " + NUM5_V2_PATH)
			quit(1)
			return
		if v2.get_size() != SOURCE_SIZE:
			push_error("Num5 v2 must be 1254x1254: %s" % str(v2.get_size()))
			quit(1)
			return
		images.append(v2)
		paths.append(NUM5_V2_PATH)
		labels.append("NUM5 V2 CONTACT")
	else:
		images.append(null)
		paths.append(NUM5_V2_PATH)
		labels.append("NUM5 V2 NOT PROVIDED")

	var canvas := Image.create(PANEL_WIDTH * 4 + GUTTER * 5, PANEL_HEIGHT, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	for index in range(4):
		var x := GUTTER + index * (PANEL_WIDTH + GUTTER)
		canvas.fill_rect(Rect2i(x, 12, PANEL_WIDTH, PANEL_HEIGHT - 24), Color("#252b32"))
		_draw_text(canvas, labels[index], Vector2i(x + 20, 28), 3, Color("#f0e8d8"))
		_draw_text(canvas, "RIGHT", Vector2i(x + 74, 78), 2, Color("#c7ccd0"))
		_draw_text(canvas, "MIRROR", Vector2i(x + 265, 78), 2, Color("#c7ccd0"))
		if images[index] == null:
			canvas.fill_rect(Rect2i(x + 22, 98, PANEL_WIDTH - 44, 384), Color("#303841"))
			_draw_text(canvas, "V2 FILE MISSING", Vector2i(x + 67, 260), 3, Color("#f1bd69"))
			_draw_text(canvas, "NO REVIEW - NO ACCEPTANCE", Vector2i(x + 38, 300), 1, Color("#c7ccd0"))
			continue
		var game_image := images[index].duplicate()
		game_image.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
		var mirrored := game_image.duplicate()
		mirrored.flip_x()
		_draw_checker(canvas, Rect2i(x + 18, 98, GAME_SIZE * SCALE, GAME_SIZE * SCALE))
		_draw_checker(canvas, Rect2i(x + 216, 98, GAME_SIZE * SCALE, GAME_SIZE * SCALE))
		var display := game_image.duplicate()
		display.resize(GAME_SIZE * SCALE, GAME_SIZE * SCALE, Image.INTERPOLATE_NEAREST)
		var display_mirror := mirrored.duplicate()
		display_mirror.resize(GAME_SIZE * SCALE, GAME_SIZE * SCALE, Image.INTERPOLATE_NEAREST)
		canvas.blend_rect(display, Rect2i(Vector2i.ZERO, display.get_size()), Vector2i(x + 18, 98))
		canvas.blend_rect(display_mirror, Rect2i(Vector2i.ZERO, display_mirror.get_size()), Vector2i(x + 216, 98))
		var bounds := _alpha_bounds(images[index])
		var margins := Vector4i(bounds.position.x, bounds.position.y, SOURCE_SIZE.x - bounds.end.x, SOURCE_SIZE.y - bounds.end.y)
		var isolated := _isolated_count(images[index])
		var dimensions_delta := images[index].get_size() - SOURCE_SIZE
		var visible_192 := _alpha_bounds(game_image, 0.05)
		print("REVIEW %s exists=true canvas=%s format=%s alpha_bounds=%s alpha_size=%s margins_ltrb=%s isolated_alpha_pixels=%d source_size_delta=%s game_192_alpha_bounds=%s mirrored=true" % [
			paths[index], str(images[index].get_size()), _format_name(images[index]), str(bounds), str(bounds.size), str(margins), isolated, str(dimensions_delta), str(visible_192)])
	_draw_text(canvas, "1254X1254 TO 192X192 GAME CANVAS - LANCZOS - RIGHT AND HORIZONTAL MIRROR", Vector2i(22, 500), 2, Color("#a9c8c2"))
	var absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := canvas.save_png(absolute)
	if error != OK:
		push_error("could not save comparison board: " + error_string(error))
		quit(1)
		return
	print("comparison generated: %s (%dx%d; v2_available=%s)" % [OUTPUT_PATH, canvas.get_width(), canvas.get_height(), str(v2_available)])
	quit(0)

func _load_png(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute)) != OK or image.is_empty():
		return null
	return image

func _format_name(image: Image) -> String:
	match image.get_format():
		Image.FORMAT_RGBA8: return "RGBA8"
		Image.FORMAT_RGB8: return "RGB8"
		_: return "format_%d" % image.get_format()

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

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var has_neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := x + ox
					var ny := y + oy
					if nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						has_neighbor = true
			if not has_neighbor:
				count += 1
	return count

func _draw_checker(canvas: Image, rect: Rect2i) -> void:
	var tile := 16
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var parity := ((x - rect.position.x) / tile + (y - rect.position.y) / tile) % 2
			canvas.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), Color("#343c45") if parity == 0 else Color("#2b323a"))

func _draw_text(canvas: Image, value: String, position: Vector2i, scale: int, color: Color) -> void:
	var glyphs := {
		" ": ["000", "000", "000", "000", "000"], "-": ["000", "000", "111", "000", "000"], ">": ["100", "010", "001", "010", "100"],
		"0": ["111", "101", "101", "101", "111"], "1": ["010", "110", "010", "010", "111"], "2": ["110", "001", "111", "100", "111"],
		"4": ["101", "101", "111", "001", "001"], "5": ["111", "100", "110", "001", "110"], "8": ["111", "101", "111", "101", "111"],
		"A": ["010", "101", "111", "101", "101"], "B": ["110", "101", "110", "101", "110"], "C": ["011", "100", "100", "100", "011"],
		"D": ["110", "101", "101", "101", "110"], "E": ["111", "100", "110", "100", "111"], "F": ["111", "100", "110", "100", "100"],
		"G": ["011", "100", "101", "101", "011"], "H": ["101", "101", "111", "101", "101"], "I": ["111", "010", "010", "010", "111"],
		"L": ["100", "100", "100", "100", "111"], "M": ["101", "111", "111", "101", "101"], "N": ["101", "111", "111", "111", "101"],
		"O": ["111", "101", "101", "101", "111"], "P": ["110", "101", "110", "100", "100"], "R": ["110", "101", "110", "101", "101"],
		"S": ["011", "100", "010", "001", "110"], "T": ["111", "010", "010", "010", "010"], "U": ["101", "101", "101", "101", "111"],
		"V": ["101", "101", "101", "101", "010"], "X": ["101", "101", "010", "101", "101"], "Y": ["101", "101", "010", "010", "010"],
		"Z": ["111", "001", "010", "100", "111"]
	}
	var cursor_x := position.x
	for character in value:
		var rows: Array = glyphs.get(character, glyphs[" "])
		for row_index in range(rows.size()):
			for column in range(3):
				if rows[row_index].substr(column, 1) == "1":
					canvas.fill_rect(Rect2i(cursor_x + column * scale, position.y + row_index * scale, scale, scale), color)
		cursor_x += 4 * scale
