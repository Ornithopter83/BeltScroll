extends SceneTree

const TARGET_SIZE := 1254
const DEFAULT_SOURCE := "res://assets/art/enemies/forest_raider_reference_v1_clean_1254x1254.png"
const DEFAULT_OUTPUT := "res://assets/art/enemies/forest_raider_reference_v1_final_candidate_1254x1254.png"
const DEFAULT_REVIEW := "res://assets/art/review/forest_raider_final_matte_review.png"
const FOREST_BACKGROUND := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const PANEL_SIZE := Vector2i(620, 430)
const ROWS := 4
const HEAD_REGION := Rect2(0.10, 0.015, 0.48, 0.25)
const CAPE_REGION := Rect2(0.77, 0.34, 0.23, 0.38)
const DISPLAY_HEIGHT := 192

func _initialize() -> void:
	call_deferred("_run_cli")

func _run_cli() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --script res://tools/finalize_forest_raider_matte.gd [입력 PNG 후보 PNG 검수 PNG]")
		quit(0)
		return
	if not args.is_empty() and args.size() != 3:
		printerr("사용법: godot --headless --script res://tools/finalize_forest_raider_matte.gd [입력 PNG 후보 PNG 검수 PNG]")
		quit(2)
		return
	var source_path := _resolve_path(args[0] if args.size() == 3 else DEFAULT_SOURCE)
	var output_path := _resolve_path(args[1] if args.size() == 3 else DEFAULT_OUTPUT)
	var review_path := _resolve_path(args[2] if args.size() == 3 else DEFAULT_REVIEW)
	var error := finalize_file(source_path, output_path)
	if error != OK:
		printerr("forest-raider-finalize 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	error = build_review(source_path, output_path, FOREST_BACKGROUND, review_path)
	if error != OK:
		printerr("forest-raider-finalize 검수 이미지 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	print("forest-raider-finalize: 독립 후보와 전후 검수 이미지 생성 완료")
	quit(0)

static func finalize_file(input_path: String, output_path: String) -> Error:
	if not FileAccess.file_exists(input_path):
		return ERR_FILE_NOT_FOUND
	if _canonical_path(input_path) == _canonical_path(output_path):
		return ERR_INVALID_PARAMETER
	var bytes := FileAccess.get_file_as_bytes(input_path)
	if not _has_png_signature(bytes):
		return ERR_FILE_UNRECOGNIZED
	var source := Image.new()
	var decode_error := source.load_png_from_buffer(bytes)
	if decode_error != OK or source.is_empty():
		return decode_error if decode_error != OK else ERR_FILE_CORRUPT
	if source.get_width() != TARGET_SIZE or source.get_height() != TARGET_SIZE:
		return ERR_INVALID_DATA
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var result := finalize_image(source)
	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_error != OK:
			return dir_error
	return (result["image"] as Image).save_png(output_path)

# Recolors only partially transparent pixels touching exterior transparency.
# Alpha is never modified, and saturated red fabric is protected wherever it
# appears, including the long flying tails outside the headband bounds.
static func finalize_image(source: Image) -> Dictionary:
	var output := source.duplicate()
	var changed := 0
	var fringe_before := 0.0
	var fringe_after := 0.0
	for y in range(2, source.get_height() - 2):
		for x in range(2, source.get_width() - 2):
			var pixel := source.get_pixel(x, y)
			if pixel.a < 0.10 or pixel.a >= 0.90 or _is_protected_red(pixel):
				continue
			if not _touches_transparency(source, x, y):
				continue
			var local := _local_opaque_color(source, x, y)
			if not bool(local["valid"]):
				continue
			var average: Vector3 = local["color"]
			var color := Vector3(pixel.r, pixel.g, pixel.b)
			var mismatch := color.distance_to(average)
			var luminance_excess := _luminance(color) - _luminance(average)
			# Limit changes to clear local color outliers, especially pale/bright
			# contamination. This avoids smoothing normal textured edge colors.
			if mismatch < 0.24 or luminance_excess < 0.09:
				continue
			var corrected := Color(average.x, average.y, average.z, pixel.a)
			fringe_before += mismatch
			fringe_after += Vector3(corrected.r, corrected.g, corrected.b).distance_to(average)
			output.set_pixel(x, y, corrected)
			changed += 1
	return {"image": output, "changed": changed, "fringe_before": fringe_before, "fringe_after": fringe_after}

static func _luminance(color: Vector3) -> float:
	return color.x * 0.2126 + color.y * 0.7152 + color.z * 0.0722

static func _is_protected_red(color: Color) -> bool:
	return color.a > 0.05 and color.s > 0.30 and (color.h < 0.055 or color.h > 0.94)

static func _touches_transparency(image: Image, x: int, y: int) -> bool:
	for ny in range(y - 2, y + 3):
		for nx in range(x - 2, x + 3):
			if nx == x and ny == y:
				continue
			if image.get_pixel(nx, ny).a < 0.03:
				return true
	return false

static func _local_opaque_color(image: Image, x: int, y: int) -> Dictionary:
	var sum := Vector3.ZERO
	var weight_sum := 0.0
	for ny in range(maxi(0, y - 4), mini(image.get_height(), y + 5)):
		for nx in range(maxi(0, x - 4), mini(image.get_width(), x + 5)):
			if nx == x and ny == y:
				continue
			var neighbor := image.get_pixel(nx, ny)
			if neighbor.a < 0.92:
				continue
			var distance := Vector2(float(nx - x), float(ny - y)).length()
			var weight := 1.0 / (distance * distance)
			sum += Vector3(neighbor.r, neighbor.g, neighbor.b) * weight
			weight_sum += weight
	if weight_sum < 0.12:
		return {"valid": false, "color": Vector3.ZERO}
	return {"valid": true, "color": sum / weight_sum}

static func build_review(before_path: String, after_path: String, forest_path: String, output_path: String) -> Error:
	if _canonical_path(before_path) == _canonical_path(after_path) or _canonical_path(before_path) == _canonical_path(output_path):
		return ERR_INVALID_PARAMETER
	var before := _load_png(before_path)
	var after := _load_png(after_path)
	var forest := _load_png(forest_path)
	if before == null or after == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if before.get_size() != Vector2i(TARGET_SIZE, TARGET_SIZE) or after.get_size() != Vector2i(TARGET_SIZE, TARGET_SIZE):
		return ERR_INVALID_DATA
	if forest.get_size() != Vector2i(1920, 1080):
		return ERR_INVALID_DATA
	var row_height := PANEL_SIZE.y + 18
	var canvas := Image.create(2560, 28 + ROWS * row_height, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	for column in range(4):
		var x := column * 640 + 10
		for row in range(ROWS):
			var y := 14 + row * row_height
			var panel := Rect2i(x, y, 620, PANEL_SIZE.y)
			_draw_background(canvas, panel, column, forest)
			var crop_before := _review_crop(before, row)
			var crop_after := _review_crop(after, row)
			if row == 3:
				crop_before = _resize_to_height(crop_before, DISPLAY_HEIGHT)
				crop_after = _resize_to_height(crop_after, DISPLAY_HEIGHT)
				var before_pos := Vector2i(x + 155 - crop_before.get_width() / 2, y + 18 + (394 - DISPLAY_HEIGHT) / 2)
				var after_pos := Vector2i(x + 465 - crop_after.get_width() / 2, y + 18 + (394 - DISPLAY_HEIGHT) / 2)
				canvas.blend_rect(crop_before, Rect2i(Vector2i.ZERO, crop_before.get_size()), before_pos)
				canvas.blend_rect(crop_after, Rect2i(Vector2i.ZERO, crop_after.get_size()), after_pos)
			else:
				_fit_and_blend(canvas, crop_before, Rect2i(x + 8, y + 18, 294, 394))
				_fit_and_blend(canvas, crop_after, Rect2i(x + 318, y + 18, 294, 394))
			canvas.fill_rect(Rect2i(x + 8, y + 5, 294, 5), Color("#e05b54"))
			canvas.fill_rect(Rect2i(x + 318, y + 5, 294, 5), Color("#69b8a2"))
	return _save_png(canvas, output_path)

static func _review_crop(image: Image, row: int) -> Image:
	var bounds := _alpha_bounds(image)
	if row == 0:
		return image.get_region(bounds)
	if row == 1:
		return _crop_relative(image, bounds, HEAD_REGION)
	if row == 2:
		return _crop_relative(image, bounds, CAPE_REGION)
	return image.get_region(_visible_bounds(image))

static func _draw_background(canvas: Image, rect: Rect2i, kind: int, forest: Image) -> void:
	if kind == 0:
		canvas.fill_rect(rect, Color.WHITE)
	elif kind == 1:
		canvas.fill_rect(rect, Color.BLACK)
	elif kind == 2:
		_draw_checker(canvas, rect)
	else:
		var background := forest.duplicate()
		background.resize(rect.size.x, rect.size.y, Image.INTERPOLATE_LANCZOS)
		canvas.blit_rect(background, Rect2i(Vector2i.ZERO, rect.size), rect.position)

static func _fit_and_blend(destination: Image, source: Image, target: Rect2i) -> void:
	var scale := minf(float(target.size.x) / source.get_width(), float(target.size.y) / source.get_height())
	var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
	var fitted := source.duplicate()
	if fitted.get_size() != size:
		fitted.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	destination.blend_rect(fitted, Rect2i(Vector2i.ZERO, size), target.position + (target.size - size) / 2)

static func _resize_to_height(source: Image, height: int) -> Image:
	var result := source.duplicate()
	var width := maxi(1, int(round(float(source.get_width()) * height / source.get_height())))
	result.resize(width, height, Image.INTERPOLATE_LANCZOS)
	return result

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var x := bounds.position.x + int(floor(region.position.x * bounds.size.x))
	var y := bounds.position.y + int(floor(region.position.y * bounds.size.y))
	var right := bounds.position.x + int(ceil((region.position.x + region.size.x) * bounds.size.x))
	var bottom := bounds.position.y + int(ceil((region.position.y + region.size.y) * bounds.size.y))
	var rect := Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)

static func _draw_checker(image: Image, rect: Rect2i) -> void:
	var tile := 22
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var shade := Color("#d7d7d7") if ((x - rect.position.x) / tile + (y - rect.position.y) / tile) % 2 == 0 else Color("#a7a7a7")
			image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), shade)

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _save_png(image: Image, output_path: String) -> Error:
	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_error != OK:
			return dir_error
	return image.save_png(output_path)

static func _alpha_bounds(image: Image) -> Rect2i:
	return _bounds_at_threshold(image, 0.0)

static func _visible_bounds(image: Image) -> Rect2i:
	return _bounds_at_threshold(image, 0.05)

static func _bounds_at_threshold(image: Image, threshold: float) -> Rect2i:
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

static func _has_png_signature(bytes: PackedByteArray) -> bool:
	var signature := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < signature.size():
		return false
	for index in range(signature.size()):
		if bytes[index] != signature[index]:
			return false
	return true

static func _canonical_path(path: String) -> String:
	var resolved := path
	if path.begins_with("res://") or path.begins_with("user://"):
		resolved = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		resolved = ProjectSettings.globalize_path("res://" + path)
	return resolved.replace("\\", "/").simplify_path().to_lower()

func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)
