extends SceneTree

const SIZE := Vector2i(1254, 1254)
const CONTENT_LIMIT := 1074
const MIN_MARGIN := 90
const COMPARISON_HEIGHT := 192
const COMPARISON_TOP := 45
const SOURCE := "res://assets/art/player/elven_fighter_attack3_reference_v1_1254x1254.png"
const V8_CLEAN := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack3_reference_v1_safe_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack3_identity_gate.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const CODE_USAGE := 2
const CODE_SOURCE := 3
const CODE_REFERENCE := 4
const CODE_FOREST := 5
const CODE_OUTPUT := 6
const CODE_MUTATED := 7

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("Usage: godot --headless --path . --script res://tools/prepare_player_attack3.gd")
		quit(0)
		return
	if not args.is_empty():
		_fail("unexpected argument", CODE_USAGE)
		return
	var source_path := _resolve(SOURCE)
	if not FileAccess.file_exists(source_path):
		_fail("attack3 source PNG is missing", CODE_SOURCE)
		return
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	if source == null or source.get_size() != SIZE:
		_fail("attack3 source PNG is not a valid 1254x1254 image", CODE_SOURCE)
		return
	var reference := _load_png(_resolve(V8_CLEAN))
	if reference == null or reference.get_size() != SIZE:
		_fail("approved v8 clean reference is missing or invalid", CODE_REFERENCE)
		return
	var forest := _load_png(_resolve(FOREST))
	if forest == null:
		_fail("Forest Ruins review image is missing or invalid", CODE_FOREST)
		return
	var safe := normalize(source)
	if safe == null or not has_clear_margins(safe):
		_fail("safe candidate normalization failed", CODE_SOURCE)
		return
	var err := _save_png(safe, _resolve(SAFE))
	if err == OK:
		err = build_review(source, safe, reference, forest, _resolve(REVIEW))
	if err != OK:
		_fail("safe or review image could not be saved: %s" % error_string(err), CODE_OUTPUT)
		return
	if FileAccess.get_file_as_bytes(source_path) != source_bytes:
		_fail("attack3 source bytes changed during preparation", CODE_MUTATED)
		return
	print("player_attack3: safe normalization and identity review generated; source preserved (visual approval pending)")
	quit(0)

# Keeps the complete source alpha silhouette. It only resizes when needed to fit
# a centered 1074px box; it does not paint, reconstruct, or clean any pixels.
static func normalize(source: Image) -> Image:
	if source == null or source.is_empty():
		return null
	var rgba := source.duplicate()
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba.convert(Image.FORMAT_RGBA8)
	var bounds := _alpha_bounds(rgba)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var scale := minf(1.0, minf(float(CONTENT_LIMIT) / bounds.size.x, float(CONTENT_LIMIT) / bounds.size.y))
	var content_size := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var content: Image = rgba.get_region(bounds)
	if content.get_size() != content_size:
		content.resize(content_size.x, content_size.y, Image.INTERPOLATE_LANCZOS)
	var result := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(content, Rect2i(Vector2i.ZERO, content_size), (SIZE - content_size) / 2)
	return result

static func has_clear_margins(image: Image) -> bool:
	if image == null or image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _alpha_bounds(image)
	return bounds.size.x > 0 and bounds.position.x >= MIN_MARGIN and bounds.position.y >= MIN_MARGIN \
		and SIZE.x - bounds.end.x >= MIN_MARGIN and SIZE.y - bounds.end.y >= MIN_MARGIN

static func build_review(original: Image, safe: Image, reference: Image, forest: Image, output_path: String) -> Error:
	if original == null or safe == null or reference == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if original.get_size() != SIZE or safe.get_size() != SIZE or reference.get_size() != SIZE or forest.is_empty():
		return ERR_INVALID_DATA
	var variants: Array[Image] = [original, safe, reference]
	var canvas := Image.create(1920, 2280, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	# Four background rows, each showing original, safe normalization and v8 clean.
	for row in range(4):
		for col in range(3):
			var tile := Image.create(620, 480, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var image := variants[col]
			var bounds := _alpha_bounds(image)
			if bounds.size.x <= 0:
				return ERR_INVALID_DATA
			var figure := _fit(image.get_region(bounds), Vector2i(270, 360))
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i(8, 8))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, row * 490 + 5))
	# The bottom comparison uses the same 192px silhouette height and foot baseline.
	var comparisons: Array[Image] = [safe, reference]
	for col in range(comparisons.size()):
		var tile := Image.create(940, 290, false, Image.FORMAT_RGBA8)
		_fill_background(tile, 2, forest)
		var figure := comparison_figure(comparisons[col])
		if figure == null:
			return ERR_INVALID_DATA
		# Both figures have a 192px alpha silhouette and the same lower-foot baseline.
		var y := comparison_y(figure)
		tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((940 - figure.get_width()) / 2, y))
		canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 960 + 10, 1970))
	return _save_png(canvas, output_path)

static func comparison_figure(image: Image) -> Image:
	if image == null or image.is_empty():
		return null
	var bounds := _alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var figure := image.get_region(bounds)
	var width := maxi(1, roundi(float(figure.get_width()) * float(COMPARISON_HEIGHT) / figure.get_height()))
	figure.resize(width, COMPARISON_HEIGHT, Image.INTERPOLATE_LANCZOS)
	return figure

static func comparison_y(figure: Image) -> int:
	if figure == null or figure.get_height() != COMPARISON_HEIGHT:
		return -1
	var bounds := _alpha_bounds(figure)
	if bounds.size.x <= 0:
		return -1
	return COMPARISON_TOP + COMPARISON_HEIGHT - 1 - bounds.end.y

static func _fill_background(image: Image, row: int, forest: Image) -> void:
	if row == 0:
		image.fill(Color.WHITE)
	elif row == 1:
		image.fill(Color("#080a0c"))
	elif row == 2:
		for y in range(0, image.get_height(), 24):
			for x in range(0, image.get_width(), 24):
				var color := Color("#3d4247") if ((x / 24 + y / 24) % 2 == 0) else Color("#292e33")
				image.fill_rect(Rect2i(x, y, mini(24, image.get_width() - x), mini(24, image.get_height() - y)), color)
	else:
		var resized := forest.duplicate()
		resized.resize(image.get_width(), image.get_height(), Image.INTERPOLATE_LANCZOS)
		image.blit_rect(resized, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)

static func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width(); var top := image.get_height(); var right := -1; var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x); top = mini(top, y); right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

static func _fit(source: Image, limit: Vector2i) -> Image:
	var scale := minf(float(limit.x) / source.get_width(), float(limit.y) / source.get_height())
	var result := source.duplicate()
	result.resize(maxi(1, roundi(source.get_width() * scale)), maxi(1, roundi(source.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return result

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _save_png(image: Image, path: String) -> Error:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return err
	return image.save_png(path)

static func _resolve(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path

func _fail(message: String, code: int) -> void:
	push_error("player_attack3: " + message + " (code %d)" % code)
	quit(code)
