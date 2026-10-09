extends SceneTree
"""Builds a fixed-scale, human-review comparison of run v1-v4 sources and available safes."""

const SIZE := Vector2i(1254, 1254)
const SAFE_INSET := 90
const RESAMPLE_GUARD := 12
const DISPLAY := 340
const PANEL_W := 800
const PANEL_H := 1450
const BOARD := Vector2i(PANEL_W * 4, PANEL_H + 112)
const OUTPUT := "res://assets/art/review/player_run_antiphase_decision_sheet.png"
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"], "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"], ".": ["00000", "00000", "00000", "00000", "00000", "00110", "00110"],
	"(": ["00010", "00100", "01000", "01000", "01000", "00100", "00010"], ")": ["01000", "00100", "00010", "00010", "00010", "00100", "01000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"], "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
	"6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"], "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"], "9": ["01110", "10001", "10001", "01111", "00001", "00001", "01110"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"], "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"], "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"], "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"], "J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"], "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"], "N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"], "P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"], "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"], "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"], "V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"], "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"], "Z": ["11111", "00001", "00010", "00100", "01000", "10000", "11111"],
}
const RUNS := [
	{"id": "V1", "source": "res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png", "safe": "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png", "finding": "RETAINED: SAME LEAD AS V1/V2 GATE"},
	{"id": "V2", "source": "res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png", "safe": "res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png", "finding": "RETAINED: SAME LEAD AS V1/V2 GATE"},
	{"id": "V3", "source": "res://assets/art/player/elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png", "safe": "", "finding": "SAME LEAD AS V1; NO SAVED SAFE"},
	{"id": "V4", "source": "res://assets/art/player/elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png", "safe": "res://assets/art/player/elven_fighter_run_stride_v4_safe_candidate_1254x1254.png", "finding": "NOT ACCEPTED: LEAD NOT REVERSED"},
]

func _initialize() -> void:
	_build()

func _build() -> void:
	var board := Image.create(BOARD.x, BOARD.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("#111820"))
	_text(board, "RUN V1-V4 ANTIPHASE DECISION SHEET", Vector2i(28, 16), 4, Color("#f0e8d8"))
	_text(board, "FIXED 1254 CANVAS SCALE | RIGHT + LEFT VIEW | SOURCE AND SAFE KEPT SEPARATE | REVIEW ONLY", Vector2i(28, 52), 2, Color("#f1bd69"))
	_text(board, "GREEN FOOT LINE = VISUAL BASELINE ONLY; NO AUTOMATIC SUPPORT-FOOT DECISION", Vector2i(28, 78), 2, Color("#93d8c3"))
	for i in range(RUNS.size()):
		var run: Dictionary = RUNS[i]
		var x := i * PANEL_W
		var y := 112
		board.fill_rect(Rect2i(x + 8, y, PANEL_W - 16, PANEL_H - 8), Color("#202832"))
		_text(board, str(run.id) + "  SOURCE DRAWING", Vector2i(x + 24, y + 12), 3, Color("#f0e8d8"))
		var source := _load(str(run.source))
		if source == null:
			_fail("Missing or invalid source drawing: " + str(run.source))
			return
		if source.get_size() != SIZE:
			_fail("Source canvas is not 1254x1254: " + str(run.source))
			return
		_draw_pair(board, source, x, y + 48)
		var safe_title := str(run.id) + ("  SAFE FIT PREVIEW (DERIVED IN MEMORY; NOT SAVED)" if str(run.safe).is_empty() else "  SAFE DRAWING")
		_text(board, safe_title, Vector2i(x + 24, y + 430), 2 if str(run.safe).is_empty() else 3, Color("#f0e8d8"))
		if str(run.safe).is_empty():
			_draw_pair(board, _make_safe_preview(source), x, y + 466)
		else:
			var safe := _load(str(run.safe))
			if safe == null or safe.get_size() != SIZE:
				_fail("Missing, invalid, or wrong-size safe: " + str(run.safe))
				return
			_draw_pair(board, safe, x, y + 466)
		_text(board, str(run.finding), Vector2i(x + 24, y + 956), 2, Color("#ffd07c"))
	_text(board, "NO CANDIDATE APPROVED | DO NOT REGISTER IN THE MAIN RUN CLIP | SEE AUTHORING GATE FOR LIMB NOTES", Vector2i(28, BOARD.y - 34), 2, Color("#ff9e91"))
	var output := ProjectSettings.globalize_path(OUTPUT)
	var dir_error := DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if dir_error != OK:
		_fail("Cannot create review output directory: " + error_string(dir_error))
		return
	if board.save_png(output) != OK:
		_fail("Could not save decision sheet PNG")
		return
	var check := Image.new()
	if check.load(output) != OK or check.get_size() != BOARD:
		_fail("Saved PNG did not pass its readback check")
		return
	print("RUN_ANTIPHASE_SHEET path=%s size=%s fixed_canvas_scale=true source_and_safe_separate=true orientations=right,left approval=none integration=none" % [OUTPUT, str(BOARD)])
	quit(0)

func _draw_pair(board: Image, source: Image, panel_x: int, top: int) -> void:
	_text(board, "RIGHT FACING", Vector2i(panel_x + 116, top), 2, Color("#a9d8c5"))
	_text(board, "LEFT FACING (MIRROR VIEW)", Vector2i(panel_x + 470, top), 2, Color("#a9d8c5"))
	var sprite := source.duplicate()
	sprite.resize(DISPLAY, DISPLAY, Image.INTERPOLATE_LANCZOS)
	var left := sprite.duplicate()
	left.flip_x()
	for pair in [[sprite, panel_x + 30], [left, panel_x + 420]]:
		var tile_x: int = pair[1]
		var tile_y := top + 26
		_draw_checker(board, Rect2i(tile_x, tile_y, DISPLAY, DISPLAY))
		board.blend_rect(pair[0], Rect2i(Vector2i.ZERO, Vector2i(DISPLAY, DISPLAY)), Vector2i(tile_x, tile_y))
		board.fill_rect(Rect2i(tile_x - 8, tile_y + DISPLAY - 1, DISPLAY + 16, 2), Color("#6c818d"))

func _make_safe_preview(source: Image) -> Image:
	var bounds := _alpha_bounds(source)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return source.duplicate()
	var content := SIZE - Vector2i.ONE * (2 * (SAFE_INSET + RESAMPLE_GUARD))
	var fit_scale := minf(float(content.x) / bounds.size.x, float(content.y) / bounds.size.y)
	var fitted := Vector2i(maxi(1, roundi(bounds.size.x * fit_scale)), maxi(1, roundi(bounds.size.y * fit_scale)))
	var crop := source.get_region(bounds)
	crop.resize(fitted.x, fitted.y, Image.INTERPOLATE_LANCZOS)
	var safe := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	safe.fill(Color(0, 0, 0, 0))
	safe.blit_rect(crop, Rect2i(Vector2i.ZERO, fitted), (SIZE - fitted) / 2)
	return safe

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

func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 20):
		for x in range(rect.position.x, rect.end.x, 20):
			var even := ((x - rect.position.x) / 20 + (y - rect.position.y) / 20) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(20, rect.end.x - x), mini(20, rect.end.y - y)), Color("#444a50") if even else Color("#30363c"))

func _text(image: Image, value: String, position: Vector2i, scale: int, color: Color) -> void:
	var cursor := position.x
	for character in value:
		var glyph: Array = FONT.get(character, FONT[" "])
		for row in range(glyph.size()):
			for column in range(5):
				if glyph[row].substr(column, 1) == "1":
					image.fill_rect(Rect2i(cursor + column * scale, position.y + row * scale, scale, scale), color)
		cursor += 6 * scale

func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	return image if image.load(ProjectSettings.globalize_path(path)) == OK and not image.is_empty() else null

func _fail(message: String) -> void:
	push_error("build_player_run_antiphase_decision_sheet: " + message)
	quit(1)
