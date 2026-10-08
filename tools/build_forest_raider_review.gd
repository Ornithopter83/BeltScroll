extends SceneTree

const NORMALIZER := preload("res://tools/normalize_player_art.gd")
const TARGET_SIZE := 1254
const MIN_MARGIN := 90
const SOURCE := "res://assets/art/enemies/forest_raider_reference_v1_1254x1254.png"
const SAFE := "res://assets/art/enemies/forest_raider_reference_v1_safe_1254x1254.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const REVIEW := "res://assets/art/review/forest_raider_reference_v1_contact.png"
const CANVAS_SIZE := Vector2i(1920, 2200)
const DETAILS_Y := 25
const DETAILS_TILE_SIZE := Vector2i(340, 505)
const DETAILS_POSITIONS := [
	Vector2i(825, 25), Vector2i(1180, 25), Vector2i(1535, 25),
	Vector2i(825, 565), Vector2i(1180, 565), Vector2i(1535, 565),
]
const DETAIL_REGIONS := [
	Rect2(0.12, 0.01, 0.30, 0.22), # Face and headband
	Rect2(0.00, 0.16, 0.19, 0.17), # Forward fist
	Rect2(0.00, 0.78, 0.31, 0.22), # Left boot
	Rect2(0.58, 0.68, 0.42, 0.32), # Right boot
	Rect2(0.78, 0.42, 0.22, 0.36), # Torn cape edge
	Rect2(0.84, 0.36, 0.16, 0.26), # Cape alpha edge close-up
]
const DISPLAY_HEIGHT := 192

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if (not args.is_empty() and args.size() != 4) or args.has("--help") or args.has("-h"):
		printerr("사용법: forest-raider-review [원본 PNG safe PNG 배경 PNG 검수 PNG]")
		quit(0 if args.has("--help") or args.has("-h") else 2)
		return
	var source_path := _resolve_path(args[0] if args.size() == 4 else SOURCE)
	var safe_path := _resolve_path(args[1] if args.size() == 4 else SAFE)
	var forest_path := _resolve_path(args[2] if args.size() == 4 else FOREST)
	var review_path := _resolve_path(args[3] if args.size() == 4 else REVIEW)
	var error := build_review(source_path, safe_path, forest_path, review_path)
	if error != OK:
		printerr("forest-raider-review 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	print("forest-raider-review: safe 후보 및 독립 검수 PNG 생성 완료")
	quit(0)

static func build_review(source_path: String, safe_path: String, forest_path: String, review_path: String) -> Error:
	if _canonical_path(source_path) == _canonical_path(safe_path) or _canonical_path(source_path) == _canonical_path(review_path):
		return ERR_INVALID_PARAMETER
	if not FileAccess.file_exists(source_path) or not FileAccess.file_exists(forest_path):
		return ERR_FILE_NOT_FOUND
	var source := _load_png(source_path)
	var forest := _load_png(forest_path)
	if source == null or forest == null:
		return ERR_FILE_UNRECOGNIZED
	if forest.get_width() != 1920 or forest.get_height() != 1080:
		return ERR_INVALID_DATA
	var normalize_error := NORMALIZER.normalize_file(source_path, safe_path)
	if normalize_error != OK:
		return normalize_error
	var safe := _load_png(safe_path)
	if safe == null or safe.get_width() != TARGET_SIZE or safe.get_height() != TARGET_SIZE:
		return ERR_INVALID_DATA
	var bounds := _alpha_bounds(safe)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return ERR_INVALID_DATA
	var review_bounds := _visible_bounds(safe)
	if review_bounds.size.x <= 0 or review_bounds.size.y <= 0:
		return ERR_INVALID_DATA

	var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_checker(canvas, Rect2i(0, 0, CANVAS_SIZE.x, 1120))
	var full := safe.get_region(review_bounds)
	var full_height := 1020
	var full_width := maxi(1, int(round(float(full.get_width()) * full_height / full.get_height())))
	full.resize(full_width, full_height, Image.INTERPOLATE_LANCZOS)
	canvas.blend_rect(full, Rect2i(Vector2i.ZERO, full.get_size()), Vector2i((800 - full_width) / 2, 30))
	for index in range(DETAIL_REGIONS.size()):
		var position: Vector2i = DETAILS_POSITIONS[index]
		var tile := Rect2i(position, DETAILS_TILE_SIZE)
		_draw_checker(canvas, tile)
		var crop := _crop_relative(safe, review_bounds, DETAIL_REGIONS[index])
		_fit_and_blend(canvas, crop, tile.grow(-8))
		# Distinct top edge makes each crop's alpha boundary visible over the checker.
		canvas.fill_rect(Rect2i(position.x, position.y, DETAILS_TILE_SIZE.x, 3), Color("#78aeb6"))

	# The lower section is native 1920x1080 Forest Ruins; at zoom 1.2,
	# a 160px world silhouette is shown at exactly 192 screen pixels.
	canvas.blit_rect(forest, Rect2i(Vector2i.ZERO, forest.get_size()), Vector2i(0, 1120))
	# Resize from the safe source once so the stage check preserves its full 192px alpha extent.
	var visible_bounds := _visible_bounds(safe)
	var display_width := maxi(1, int(round(float(visible_bounds.size.x) * DISPLAY_HEIGHT / visible_bounds.size.y)))
	var display := _resize_image(safe.get_region(visible_bounds), Vector2i(display_width, DISPLAY_HEIGHT))
	canvas.blend_rect(display, Rect2i(Vector2i.ZERO, display.get_size()),
		Vector2i(960 - display.get_width() / 2, 1120 + 850 - DISPLAY_HEIGHT))
	canvas.fill_rect(Rect2i(0, 1120, 1920, 2), Color("#f2d07d"))
	var output_dir := review_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_error != OK:
			return dir_error
	return canvas.save_png(review_path)

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
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

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var x := bounds.position.x + int(floor(region.position.x * bounds.size.x))
	var y := bounds.position.y + int(floor(region.position.y * bounds.size.y))
	var right := bounds.position.x + int(ceil((region.position.x + region.size.x) * bounds.size.x))
	var bottom := bounds.position.y + int(ceil((region.position.y + region.size.y) * bounds.size.y))
	var rect := Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)

static func _fit_and_blend(destination: Image, source: Image, target: Rect2i) -> void:
	var scale := minf(float(target.size.x) / source.get_width(), float(target.size.y) / source.get_height())
	var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
	var fitted := _resize_image(source, size)
	destination.blend_rect(fitted, Rect2i(Vector2i.ZERO, size), target.position + (target.size - size) / 2)

static func _resize_image(source: Image, size: Vector2i) -> Image:
	var result := source.duplicate()
	result.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return result

static func _draw_checker(image: Image, rect: Rect2i) -> void:
	var tile := 24
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var shade := Color("#3d4247") if ((x - rect.position.x) / tile + (y - rect.position.y) / tile) % 2 == 0 else Color("#292e33")
			image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), shade)

func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)

static func _canonical_path(path: String) -> String:
	return path.replace("\\", "/").simplify_path().to_lower()
