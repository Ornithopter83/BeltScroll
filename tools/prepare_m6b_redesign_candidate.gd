extends SceneTree
"""Builds an isolated, foot-aligned M6B redesign candidate and review Window."""

const SOURCE := "res://assets/art/player/elven_fighter_dark_fantasy_redesign_v1_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_dark_fantasy_redesign_v1_safe_candidate_1254x1254.png"
const V8 := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const COMPARISON := "res://assets/art/review/m6b_redesign_candidate_comparison.png"
const CANVAS := Vector2i(1254, 1254)
const SAFE_MARGIN := 90
const GAME_SPRITE_SCALE := 0.4469274
const CAMERA_ZOOM := 1.2
const WINDOW_SIZE := Vector2i(1920, 1080)
const FOOTLINE_Y := 820.0

var _keep_window_open := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_keep_window_open = args.has("--window")
	root.size = WINDOW_SIZE
	root.mode = Window.MODE_WINDOWED
	root.title = "M6B Character Identity Review — Candidate Only"
	call_deferred("_build")

func _build() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_image(SOURCE)
	var v8 := _load_image(V8)
	if source == null or v8 == null:
		_fail("Could not load the original redesign source or current v8 art.")
		return
	var candidate := normalize_image(source)
	if candidate.is_empty():
		_fail("Could not normalize redesign candidate.")
		return
	var output_path := ProjectSettings.globalize_path(OUTPUT)
	var directory_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		_fail("Could not create candidate output directory: %s" % error_string(directory_error))
		return
	var save_error := candidate.save_png(output_path)
	if save_error != OK:
		_fail("Could not save normalized candidate: %s" % error_string(save_error))
		return
	if FileAccess.get_file_as_bytes(source_path) != source_bytes:
		_fail("Original redesign source changed while building candidate.")
		return
	_make_review_window(v8, candidate)
	var capture := _make_comparison_image(v8, candidate)
	var comparison_path := ProjectSettings.globalize_path(COMPARISON)
	var comparison_directory_error := DirAccess.make_dir_recursive_absolute(comparison_path.get_base_dir())
	if comparison_directory_error != OK and comparison_directory_error != ERR_ALREADY_EXISTS:
		_fail("Could not create review output directory: %s" % error_string(comparison_directory_error))
		return
	save_error = capture.save_png(comparison_path)
	if save_error != OK:
		_fail("Could not save review Window capture: %s" % error_string(save_error))
		return
	var bounds := alpha_bounds(candidate)
	print("M6B candidate=%s size=%s alpha_bounds=%s margins=%s game_scale=%.7f*%.1f footline=%.1f" % [OUTPUT, str(candidate.get_size()), str(bounds), str(_margins(candidate, bounds)), GAME_SPRITE_SCALE, CAMERA_ZOOM, FOOTLINE_Y])
	print("M6B original source alpha_bounds=%s; current v8 alpha_bounds=%s" % [str(alpha_bounds(source)), str(alpha_bounds(v8))])
	print("M6B Window review board=%s size=%s; candidate remains unapproved and game assets/manifests were not changed." % [COMPARISON, str(WINDOW_SIZE)])
	if not _keep_window_open:
		quit(0)

static func normalize_image(source: Image) -> Image:
	if source == null or source.is_empty():
		return Image.new()
	var bounds := alpha_bounds(source)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return Image.new()
	var max_content := CANVAS.x - SAFE_MARGIN * 2
	var scale := minf(1.0, minf(float(max_content) / bounds.size.x, float(max_content) / bounds.size.y))
	var content_size := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var content := source.get_region(bounds)
	if content_size != bounds.size:
		content.resize(content_size.x, content_size.y, Image.INTERPOLATE_LANCZOS)
	var output := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	output.fill(Color(0.0, 0.0, 0.0, 0.0))
	var x := (CANVAS.x - content_size.x) / 2
	var y := CANVAS.y - SAFE_MARGIN - content_size.y
	output.blit_rect(content, Rect2i(Vector2i.ZERO, content_size), Vector2i(x, y))
	return output

static func alpha_bounds(image: Image) -> Rect2i:
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

func _make_review_window(v8: Image, candidate: Image) -> Control:
	var base := Control.new()
	base.name = "M6BIdentityReview"
	base.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(base)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#11181f")
	base.add_child(bg)
	_add_text(base, "M6B  /  CHARACTER IDENTITY REVIEW", Vector2(56, 28), 36, Color("#f2dfbc"))
	_add_text(base, "WINDOW RENDER  ·  GAME SPRITE SCALE %.4f  ×  CAMERA ZOOM %.1f  ·  SHARED FOOTLINE" % [GAME_SPRITE_SCALE, CAMERA_ZOOM], Vector2(58, 80), 19, Color("#a9c0c3"))
	var images := [v8, candidate]
	var labels := ["V8 CURRENT · ACTIVE", "DARK FANTASY V1 · UNAPPROVED CANDIDATE"]
	for index in range(2):
		var center_x := 480.0 + 960.0 * index
		var panel := ColorRect.new()
		panel.position = Vector2(42.0 + 960.0 * index, 126)
		panel.size = Vector2(900, 852)
		panel.color = Color("#1b252c")
		base.add_child(panel)
		_add_text(base, labels[index], Vector2(66.0 + 960.0 * index, 145), 22, Color("#ffffff"))
		_add_checker(base, Rect2(Vector2(58.0 + 960.0 * index, 190), Vector2(868, 690)))
		var texture := ImageTexture.create_from_image(images[index])
		var sprite := Sprite2D.new()
		sprite.texture = texture
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
		sprite.scale = Vector2.ONE * GAME_SPRITE_SCALE * CAMERA_ZOOM
		var bounds := alpha_bounds(images[index])
		var foot_from_center := float(bounds.end.y) - float(images[index].get_height()) * 0.5
		sprite.position = Vector2(center_x, FOOTLINE_Y - foot_from_center * GAME_SPRITE_SCALE * CAMERA_ZOOM)
		base.add_child(sprite)
		var baseline := ColorRect.new()
		baseline.position = Vector2(58.0 + 960.0 * index, FOOTLINE_Y)
		baseline.size = Vector2(868, 2)
		baseline.color = Color("#edc878")
		base.add_child(baseline)
		_add_text(base, "alpha bounds %d×%d   ·   foot anchor y=%d/1254" % [bounds.size.x, bounds.size.y, bounds.end.y], Vector2(66.0 + 960.0 * index, 853), 16, Color("#c4d0d2"))
	_add_text(base, "FACE / COSTUME / LIMB READABILITY  ·  REVIEW AGAINST V8 AT 1:1 GAME PIXEL SCALE", Vector2(58, 907), 19, Color("#e4bd7a"))
	_add_text(base, "Review only. No PlayerArt, manifest, or allowlist promotion is performed by this tool.", Vector2(58, 946), 17, Color("#a9c0c3"))
	_add_text(base, "Run with --window to keep this Window open for interactive review; close the Window to exit.", Vector2(58, 979), 15, Color("#82959a"))
	var close_button := Button.new()
	close_button.text = "CLOSE"
	close_button.position = Vector2(1780, 28)
	close_button.size = Vector2(90, 38)
	close_button.pressed.connect(Callable(self, "quit").bind(0))
	base.add_child(close_button)
	return base

func _make_comparison_image(v8: Image, candidate: Image) -> Image:
	var board := Image.create(WINDOW_SIZE.x, WINDOW_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("#11181f"))
	_draw_bitmap_text(board, "M6B / CHARACTER IDENTITY REVIEW", Vector2i(56, 28), 4, Color("#f2dfbc"))
	_draw_bitmap_text(board, "WINDOW RENDER / GAME SCALE 0.4469 X CAMERA ZOOM 1.2 / SHARED FOOTLINE", Vector2i(58, 80), 2, Color("#a9c0c3"))
	var images := [v8, candidate]
	var labels := ["V8 CURRENT - ACTIVE", "DARK FANTASY V1 - UNAPPROVED CANDIDATE"]
	for index in range(2):
		var panel_x := 42 + 960 * index
		board.fill_rect(Rect2i(panel_x, 126, 900, 852), Color("#1b252c"))
		_draw_bitmap_text(board, labels[index], Vector2i(panel_x + 24, 145), 2, Color.WHITE)
		var checker_rect := Rect2i(panel_x + 16, 190, 868, 690)
		_draw_checker_image(board, checker_rect)
		var image: Image = images[index]
		var display_size := Vector2i(roundi(CANVAS.x * GAME_SPRITE_SCALE * CAMERA_ZOOM), roundi(CANVAS.y * GAME_SPRITE_SCALE * CAMERA_ZOOM))
		var rendered := image.duplicate()
		rendered.resize(display_size.x, display_size.y, Image.INTERPOLATE_LANCZOS)
		var bounds := alpha_bounds(image)
		var foot_from_center := float(bounds.end.y) - float(image.get_height()) * 0.5
		var center := Vector2i(480 + 960 * index, roundi(FOOTLINE_Y - foot_from_center * GAME_SPRITE_SCALE * CAMERA_ZOOM))
		board.blend_rect(rendered, Rect2i(Vector2i.ZERO, display_size), center - display_size / 2)
		board.fill_rect(Rect2i(panel_x + 16, int(FOOTLINE_Y), 868, 2), Color("#edc878"))
		_draw_bitmap_text(board, "ALPHA %d X %d / FOOT Y %d OF 1254" % [bounds.size.x, bounds.size.y, bounds.end.y], Vector2i(panel_x + 24, 853), 2, Color("#c4d0d2"))
	_draw_bitmap_text(board, "REVIEW FACE / COSTUME / LIMB READABILITY AT 1:1 GAME PIXEL SCALE", Vector2i(58, 907), 2, Color("#e4bd7a"))
	_draw_bitmap_text(board, "REVIEW ONLY / NO PLAYERART, MANIFEST OR ALLOWLIST PROMOTION", Vector2i(58, 946), 2, Color("#a9c0c3"))
	_draw_bitmap_text(board, "RUN TOOL WITH --WINDOW FOR INTERACTIVE WINDOW / CLOSE WINDOW TO EXIT", Vector2i(58, 979), 2, Color("#82959a"))
	return board

func _draw_checker_image(image: Image, rect: Rect2i) -> void:
	image.fill_rect(rect, Color("#29343a"))
	var cell := 24
	for y in range(rect.position.y, rect.end.y, cell):
		for x in range(rect.position.x, rect.end.x, cell):
			if ((x - rect.position.x) / cell + (y - rect.position.y) / cell) % 2 == 0:
				image.fill_rect(Rect2i(x, y, mini(cell, rect.end.x - x), mini(cell, rect.end.y - y)), Color("#344149"))

func _draw_bitmap_text(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
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
		"0":"01110/10001/10011/10101/11001/10001/01110", "1":"00100/01100/00100/00100/00100/00100/01110",
		"2":"01110/10001/00001/00010/00100/01000/11111", "3":"11110/00001/00001/01110/00001/00001/11110",
		"4":"00010/00110/01010/10010/11111/00010/00010", "5":"11111/10000/10000/11110/00001/00001/11110",
		"6":"01110/10000/10000/11110/10001/10001/01110", "7":"11111/00001/00010/00100/01000/01000/01000",
		"8":"01110/10001/10001/01110/10001/10001/01110", "9":"01110/10001/10001/01111/00001/00001/11110",
		"/":"00001/00010/00010/00100/01000/01000/10000", "-":"00000/00000/00000/11111/00000/00000/00000",
		".":"00000/00000/00000/00000/00000/00110/00110", ":":"00000/00110/00110/00000/00110/00110/00000",
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

func _add_checker(parent: Control, rect: Rect2) -> void:
	var panel := ColorRect.new()
	panel.position = rect.position
	panel.size = rect.size
	panel.color = Color("#29343a")
	parent.add_child(panel)
	var cell := 24
	for row in range(int(rect.size.y / cell) + 1):
		for column in range(int(rect.size.x / cell) + 1):
			if (row + column) % 2 == 0:
				var tile := ColorRect.new()
				tile.position = rect.position + Vector2(column * cell, row * cell)
				tile.size = Vector2(minf(cell, rect.size.x - column * cell), minf(cell, rect.size.y - row * cell))
				tile.color = Color("#344149")
				parent.add_child(tile)

func _add_text(parent: Control, value: String, position: Vector2, font_size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _load_image(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load(absolute) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _margins(image: Image, bounds: Rect2i) -> Vector4i:
	return Vector4i(bounds.position.x, bounds.position.y, image.get_width() - bounds.end.x, image.get_height() - bounds.end.y)

func _fail(message: String) -> void:
	push_error("m6b_redesign_candidate: " + message)
	quit(1)
