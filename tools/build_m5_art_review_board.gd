extends SceneTree

## Builds an evidence board for human M5B art approval. The board does not
## mutate the animation manifest and never upgrades a candidate's approval.

const OUTPUT := "res://assets/art/review/m5_art_approval_board.png"
const PLAYER_DIR := "res://assets/art/player"
const LEFT := 24
const TOP := 164
const PANEL_W := 720
const PANEL_H := 680
const GAP := 24
const DISPLAY := 576 # 3x the 192px in-game character canvas.
const MARKER_ALPHA := Color("#ffe063")
const MARKER_SUPPORT := Color("#5ff0c2")
const MARKER_PATH := Color("#ff796b")
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
	".": ["00000", "00000", "00000", "00000", "00000", "00110", "00110"],
	":": ["00000", "00110", "00110", "00000", "00110", "00110", "00000"],
	"(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"],
	")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
	"5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
	"6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
	"7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
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
	"Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
}

const BASE_ITEMS := [
	{"key":"idle_v8", "title":"IDLE / V8 APPROVED", "path":"elven_fighter_reference_v8_clean_candidate_1254x1254.png", "kind":"APPROVED", "motion":"HOLD / IDLE", "support_x":-1, "safe":true},
	{"key":"attack1_contact", "title":"ATTACK 1 / CONTACT", "path":"elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png", "kind":"APPROVED", "motion":"FIST: STRAIGHT OUT", "support_x":1073, "safe":true},
	{"key":"attack2_contact", "title":"ATTACK 2 / CONTACT", "path":"elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png", "kind":"APPROVED", "motion":"FIST: BACKFIST SWEEP", "support_x":-1, "safe":true},
	{"key":"attack3_contact", "title":"ATTACK 3 / CONTACT", "path":"elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png", "kind":"APPROVED", "motion":"FIST: UPWARD", "support_x":1000, "safe":true},
	{"key":"attack1_startup", "title":"ATTACK 1 / STARTUP", "path":"elven_fighter_attack1_startup_v1_candidate_1254x1254.png", "kind":"UNAPPROVED", "motion":"FIST PATH: REVIEW", "support_x":-1, "safe":false},
	{"key":"attack2_middle_safe", "title":"ATTACK 2 / SAFE MIDDLE", "path":"elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png", "kind":"UNAPPROVED", "motion":"50 MS / TRANSITION", "support_x":1064, "safe":true},
	{"key":"attack2_v6_safe", "title":"ATTACK 2 / V6 SAFE CONTACT", "path":"elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png", "kind":"UNAPPROVED", "motion":"V6 / FIST PATH REVIEW", "support_x":1100, "safe":true},
	{"key":"attack3_startup_safe", "title":"ATTACK 3 / STARTUP SAFE", "path":"elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png", "kind":"UNAPPROVED", "motion":"TO UPWARD CONTACT", "support_x":-1, "safe":true},
]

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var items: Array[Dictionary] = []
	for item in BASE_ITEMS:
		if not FileAccess.file_exists(PLAYER_DIR.path_join(item.path)):
			push_error("required M5B review source missing: " + item.path)
			quit(1)
			return
		items.append(item.duplicate())
	var run_paths := _existing_run_candidates()
	if run_paths.is_empty():
		items.append({"key":"run_missing", "title":"RUN / NOT PROVIDED", "path":"", "kind":"MISSING", "motion":"NO RUN CANDIDATE FILE", "support_x":-1, "safe":false})
	else:
		for run_path in run_paths:
			items.append({"key":"run_candidate", "title":"RUN / CANDIDATE", "path":run_path, "kind":"UNAPPROVED", "motion":"RUN / HUMAN REVIEW", "support_x":-1, "safe":false})
	var columns := 4
	var rows := ceili(float(items.size()) / columns)
	var width := LEFT * 2 + columns * PANEL_W + (columns - 1) * GAP
	var height := TOP + rows * (PANEL_H + GAP) + 24
	var board := Image.create(width, height, false, Image.FORMAT_RGBA8)
	board.fill(Color("#151a20"))
	_draw_text(board, "M5B ART APPROVAL REVIEW", Vector2i(LEFT, 22), 4, Color("#f0e8d8"))
	_draw_text(board, "3X CANVAS 576PX  |  RIGHT VIEW  |  LEFT = FLIP_H ONCE  |  HUMAN APPROVAL REQUIRED", Vector2i(LEFT, 74), 2, Color("#8fd8c1"))
	_draw_text(board, "YELLOW = LOWEST ALPHA ANCHOR  |  MINT = SUPPORT FOOT CANDIDATE  |  RED TEXT = MOTION NOTE", Vector2i(LEFT, 110), 2, Color("#c8ced5"))
	for index in range(items.size()):
		_draw_panel(board, items[index], index % columns, index / columns)
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	var make_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if make_error != OK:
		push_error("could not create review output directory: " + error_string(make_error))
		quit(1)
		return
	var save_error := board.save_png(output_path)
	if save_error != OK:
		push_error("could not save M5B art approval board: " + error_string(save_error))
		quit(1)
		return
	print("M5B review board: %s (%dx%d; panels=%d; run_files=%d; approval unchanged)" % [OUTPUT, width, height, items.size(), run_paths.size()])
	quit(0)

func _existing_run_candidates() -> Array[String]:
	var found: Array[String] = []
	var directory := DirAccess.open(PLAYER_DIR)
	if directory == null:
		return found
	for file_name in directory.get_files():
		var lower := file_name.to_lower()
		if lower.contains("run") and lower.ends_with(".png") and lower.contains("candidate"):
			found.append(file_name)
	found.sort()
	return found

func _draw_panel(board: Image, item: Dictionary, column: int, row: int) -> void:
	var x := LEFT + column * (PANEL_W + GAP)
	var y := TOP + row * (PANEL_H + GAP)
	board.fill_rect(Rect2i(x, y, PANEL_W, PANEL_H), Color("#252b32"))
	_draw_checker(board, Rect2i(x + 8, y + 58, PANEL_W - 16, DISPLAY + 4))
	var status_color := Color("#80d6a4") if item.kind == "APPROVED" else (Color("#f0bd70") if item.kind == "UNAPPROVED" else Color("#e98c74"))
	_draw_text(board, item.title, Vector2i(x + 18, y + 14), 2, Color("#f0e8d8"))
	_draw_text(board, item.kind, Vector2i(x + PANEL_W - 170, y + 14), 2, status_color)
	var source: Image = null
	if item.path.is_empty():
		_draw_text(board, "NOT PROVIDED", Vector2i(x + 220, y + 300), 4, Color("#f0bd70"))
		_draw_text(board, "RUN ART NOT FOUND", Vector2i(x + 218, y + 356), 2, Color("#c8ced5"))
	else:
		source = _load_image(PLAYER_DIR.path_join(item.path))
		if source == null:
			push_error("M5B review source cannot be decoded: " + item.path)
			quit(1)
			return
		var full_canvas := Image.create(DISPLAY, DISPLAY, false, Image.FORMAT_RGBA8)
		full_canvas.fill(Color(0, 0, 0, 0))
		var scaled := source.duplicate()
		scaled.convert(Image.FORMAT_RGBA8)
		scaled.resize(DISPLAY, DISPLAY, Image.INTERPOLATE_LANCZOS)
		full_canvas.blit_rect(scaled, Rect2i(Vector2i.ZERO, scaled.get_size()), Vector2i.ZERO)
		var position := Vector2i(x + (PANEL_W - DISPLAY) / 2, y + 60)
		board.blend_rect(full_canvas, Rect2i(Vector2i.ZERO, full_canvas.get_size()), position)
		var alpha_anchor := _bottom_anchor(source)
		_draw_cross(board, position + Vector2i(roundi(float(alpha_anchor.x) * DISPLAY / source.get_width()), roundi(float(alpha_anchor.y) * DISPLAY / source.get_height())), MARKER_ALPHA, 13)
		if int(item.support_x) >= 0:
			var support_y := _foot_y_near_x(source, int(item.support_x))
			var support_point := position + Vector2i(roundi(float(item.support_x) * DISPLAY / source.get_width()), roundi(float(support_y) * DISPLAY / source.get_height()))
			_draw_diamond(board, support_point, MARKER_SUPPORT, 9)
		var gate := _mechanical_status(source, bool(item.safe))
		_draw_text(board, "MACHINE: " + gate, Vector2i(x + 18, y + 642), 1, Color("#c8ced5"))
		var bounds := _alpha_bounds(source, 0.0)
		var margins := Vector4i(bounds.position.x, bounds.position.y, source.get_width() - bounds.end.x, source.get_height() - bounds.end.y)
		print("ASSET key=%s path=%s size=%s format=%s alpha_margins_ltrb=%d/%d/%d/%d alpha05_anchor=%s support_candidate_x=%d machine=%s human=%s" % [
			item.key, item.path, str(source.get_size()), "RGBA8" if source.get_format() == Image.FORMAT_RGBA8 else "format_%d" % source.get_format(),
			margins.x, margins.y, margins.z, margins.w, str(alpha_anchor), int(item.support_x), gate,
			"approved" if item.kind == "APPROVED" else "pending"])
	_draw_text(board, "MOTION: " + item.motion, Vector2i(x + 18, y + 612), 1, Color("#ffab9d"))
	if item.path.is_empty():
		_draw_text(board, "MACHINE: NO SOURCE", Vector2i(x + 18, y + 642), 1, Color("#c8ced5"))
	_draw_text(board, "HUMAN: " + ("APPROVED" if item.kind == "APPROVED" else "PENDING"), Vector2i(x + 18, y + 660), 1, status_color)
	if int(item.support_x) < 0:
		_draw_text(board, "FOOT CANDIDATE: NOT SET", Vector2i(x + 410, y + 660), 1, Color("#8fd8c1"))

func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		return null
	return image

func _mechanical_status(image: Image, require_safe: bool) -> String:
	if image.get_size() != Vector2i(1254, 1254) or image.get_format() != Image.FORMAT_RGBA8:
		return "FAIL SIZE/FORMAT"
	if not require_safe:
		return "FAIL SAFE ALPHA MARGIN"
	var bounds := _alpha_bounds(image, 0.0)
	if bounds.size.x <= 0:
		return "FAIL EMPTY ALPHA"
	var margins := Vector4i(bounds.position.x, bounds.position.y, image.get_width() - bounds.end.x, image.get_height() - bounds.end.y)
	if mini(mini(margins.x, margins.y), mini(margins.z, margins.w)) < 90 or not _transparent_border(image):
		return "FAIL SAFE ALPHA MARGIN"
	return "PASS RGBA8 1254 SAFE"

func _alpha_bounds(image: Image, threshold: float) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > threshold:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

func _bottom_anchor(image: Image) -> Vector2i:
	var bottom := -1
	var left := image.get_width()
	var right := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.05:
				if y > bottom:
					bottom = y
					left = x
					right = x
				elif y == bottom:
					left = mini(left, x)
					right = maxi(right, x)
	return Vector2i((left + right) / 2, bottom)

func _foot_y_near_x(image: Image, x: int) -> int:
	var clamped_x := clampi(x, 0, image.get_width() - 1)
	for y in range(image.get_height() - 1, -1, -1):
		for candidate_x in range(maxi(0, clamped_x - 36), mini(image.get_width(), clamped_x + 37)):
			if image.get_pixel(candidate_x, y).a >= 0.05:
				return y
	return image.get_height() - 1

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a > 0.0 or image.get_pixel(x, image.get_height() - 1).a > 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a > 0.0 or image.get_pixel(image.get_width() - 1, y).a > 0.0:
			return false
	return true

func _draw_cross(image: Image, point: Vector2i, color: Color, radius: int) -> void:
	image.fill_rect(Rect2i(point.x - radius, point.y - 2, radius * 2 + 1, 5), color)
	image.fill_rect(Rect2i(point.x - 2, point.y - radius, 5, radius * 2 + 1), color)

func _draw_diamond(image: Image, point: Vector2i, color: Color, radius: int) -> void:
	for dy in range(-radius, radius + 1):
		var half_width := radius - absi(dy)
		image.fill_rect(Rect2i(point.x - half_width, point.y + dy, half_width * 2 + 1, 1), color)

func _draw_checker(image: Image, rect: Rect2i) -> void:
	var tile := 24
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var even := int((x - rect.position.x) / tile + (y - rect.position.y) / tile) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), Color("#454b52") if even else Color("#30363c"))

func _draw_text(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	var cursor_x := origin.x
	for character in value.to_upper():
		var glyph: Array = FONT.get(character, FONT[" "])
		for row in range(glyph.size()):
			for column in range(5):
				if glyph[row].substr(column, 1) == "1":
					image.fill_rect(Rect2i(cursor_x + column * scale, origin.y + row * scale, scale, scale), color)
		cursor_x += 6 * scale
