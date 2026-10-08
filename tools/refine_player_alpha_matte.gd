extends SceneTree

const TARGET_SIZE := 1254
const MIN_MARGIN := 90
const DEFAULT_SOURCE := "res://assets/art/player/elven_fighter_reference_v4_retouch_1254x1254.png"
const DEFAULT_OUTPUT := "res://assets/art/player/elven_fighter_reference_v4_matte_v2_1254x1254.png"
const DEFAULT_REVIEW := "res://assets/art/review/player_v4_matte_v2_contact.png"
const REVIEW_SIZE := Vector2i(1600, 1540)
const PANEL_SIZE := Vector2i(760, 470)

func _initialize() -> void:
	call_deferred("_run_cli")

func _run_cli() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --script res://tools/refine_player_alpha_matte.gd [입력 PNG 출력 PNG 비교 PNG]")
		quit(0)
		return
	if args.size() != 0 and args.size() != 3:
		printerr("사용법: godot --headless --script res://tools/refine_player_alpha_matte.gd [입력 PNG 출력 PNG 비교 PNG]")
		quit(2)
		return
	var input_path := _resolve_path(args[0] if args.size() == 3 else DEFAULT_SOURCE)
	var output_path := _resolve_path(args[1] if args.size() == 3 else DEFAULT_OUTPUT)
	var review_path := _resolve_path(args[2] if args.size() == 3 else DEFAULT_REVIEW)
	var error := refine_file(input_path, output_path)
	if error == OK:
		error = build_comparison(input_path, output_path, review_path)
	if error != OK:
		printerr("player-alpha-matte 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	print("player-alpha-matte: 후보 및 체커보드·어두운 배경·Forest Ruins 비교 이미지 생성 완료")
	quit(0)

static func refine_file(input_path: String, output_path: String) -> Error:
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
	if source.get_size() != Vector2i(TARGET_SIZE, TARGET_SIZE):
		return ERR_INVALID_DATA
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var result := refine_image(source)
	var output: Image = result["image"]
	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_error != OK:
			return dir_error
	return output.save_png(output_path)

# Non-destructive matte cleanup: alpha, pixel positions, and opaque interior RGB
# remain untouched. Only contaminated partial-alpha edge RGB is reconstructed.
static func refine_image(source: Image) -> Dictionary:
	var output := source.duplicate()
	var changed := 0
	var bounds := _alpha_bounds(source)
	for y in range(maxi(1, bounds.position.y - 1), mini(source.get_height() - 1, bounds.end.y + 1)):
		for x in range(maxi(1, bounds.position.x - 1), mini(source.get_width() - 1, bounds.end.x + 1)):
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.0:
				continue
			if not _touches_transparency(source, x, y, 3):
				continue
			var reference := _local_foreground_color(source, x, y, 5)
			if not bool(reference["valid"]):
				continue
			var clean_color: Color = reference["color"]
			var distance := Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(clean_color.r, clean_color.g, clean_color.b))
			# Keep real skin, hair highlights, and gold trim when their local
			# opaque neighbors support the same color family.
			if not _is_red_or_yellow_contaminant(pixel, clean_color, distance):
				continue
			var correction := clampf(0.68 + (1.0 - pixel.a) * 0.24, 0.68, 0.91)
			output.set_pixel(x, y, Color(
				lerpf(pixel.r, clean_color.r, correction),
				lerpf(pixel.g, clean_color.g, correction),
				lerpf(pixel.b, clean_color.b, correction), pixel.a))
			changed += 1
	return {"image": output, "changed": changed}

static func _local_foreground_color(source: Image, x: int, y: int, radius: int) -> Dictionary:
	var sum := Vector3.ZERO
	var weight_sum := 0.0
	var samples := 0
	var colors: Array[Vector3] = []
	for ny in range(maxi(0, y - radius), mini(source.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(source.get_width(), x + radius + 1)):
			if nx == x and ny == y:
				continue
			var neighbor := source.get_pixel(nx, ny)
			if neighbor.a < 0.88:
				continue
			var distance := Vector2(float(nx - x), float(ny - y)).length()
			var weight := 1.0 / maxf(1.0, distance * distance)
			var rgb := Vector3(neighbor.r, neighbor.g, neighbor.b)
			sum += rgb * weight
			weight_sum += weight
			samples += 1
			colors.append(rgb)
	if samples < 2 or weight_sum <= 0.0:
		return {"valid": false, "color": Color.TRANSPARENT}
	var mean := sum / weight_sum
	# Reject mixed boundaries (e.g. hair beside skin) where a mean could invent
	# a color belonging to neither region. Nearby samples must support the mean.
	var inliers := 0
	for rgb in colors:
		if rgb.distance_to(mean) <= 0.34:
			inliers += 1
	if float(inliers) / float(samples) < 0.55:
		return {"valid": false, "color": Color.TRANSPARENT}
	return {"valid": true, "color": Color(mean.x, mean.y, mean.z, 1.0)}

static func _is_red_or_yellow_contaminant(pixel: Color, local_color: Color, distance: float) -> bool:
	if pixel.s < 0.48 or distance < 0.24:
		return false
	var hue := pixel.h
	var warm_hue := hue < 0.045 or hue > 0.965 or (hue >= 0.085 and hue <= 0.155)
	if not warm_hue:
		return false
	# Protect clean gold, skin, and warm hair edges when the opaque local color
	# remains in that family; an actual matte spill is a sharp hue/color outlier.
	if local_color.s > 0.24 and absf(pixel.h - local_color.h) < 0.055 and distance < 0.46:
		return false
	return true

static func _touches_transparency(image: Image, x: int, y: int, radius: int) -> bool:
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if image.get_pixel(nx, ny).a < 0.035:
				return true
	return false

static func build_comparison(before_path: String, after_path: String, output_path: String) -> Error:
	var before := _load_png(before_path)
	var after := _load_png(after_path)
	var forest := _load_png(_resolve_path("res://assets/art/stage/forest_ruins_v1_1920x1080.png"))
	if before == null or after == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if before.get_size() != Vector2i(TARGET_SIZE, TARGET_SIZE) or after.get_size() != Vector2i(TARGET_SIZE, TARGET_SIZE):
		return ERR_INVALID_DATA
	var canvas := Image.create(REVIEW_SIZE.x, REVIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var rows := ["체커보드", "어두운 배경", "Forest Ruins"]
	var crops := [Rect2(0.30, 0.00, 0.58, 0.40), Rect2(0.17, 0.23, 0.70, 0.40), Rect2(0.05, 0.48, 0.91, 0.49)]
	for row in range(3):
		var panel_y := 70 + row * 490
		for side in range(2):
			var panel_x := 35 + side * 765
			var panel := Rect2i(panel_x, panel_y, PANEL_SIZE.x, PANEL_SIZE.y)
			var base := Image.create(PANEL_SIZE.x, PANEL_SIZE.y, false, Image.FORMAT_RGBA8)
			if row == 0:
				_draw_checker(base, Rect2i(Vector2i.ZERO, PANEL_SIZE))
			elif row == 1:
				base.fill(Color("#11151a"))
			else:
				var bg := forest.get_region(Rect2i(0, 0, forest.get_width(), forest.get_height()))
				bg.resize(PANEL_SIZE.x, PANEL_SIZE.y, Image.INTERPOLATE_LANCZOS)
				base.blit_rect(bg, Rect2i(Vector2i.ZERO, bg.get_size()), Vector2i.ZERO)
			var image := before if side == 0 else after
			var bounds := _alpha_bounds(image)
			var crop := _crop_relative(image, bounds, crops[row])
			var fitted := _fit(crop, Vector2i(PANEL_SIZE.x - 28, PANEL_SIZE.y - 28))
			base.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()),
				Vector2i((PANEL_SIZE.x - fitted.get_width()) / 2, (PANEL_SIZE.y - fitted.get_height()) / 2))
			canvas.blit_rect(base, Rect2i(Vector2i.ZERO, base.get_size()), panel.position)
			canvas.fill_rect(Rect2i(panel_x, panel_y - 7, PANEL_SIZE.x, 5), Color("#e05b54") if side == 0 else Color("#69b8a2"))
	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_error != OK:
			return dir_error
	return canvas.save_png(output_path)

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var x := bounds.position.x + int(floor(region.position.x * bounds.size.x))
	var y := bounds.position.y + int(floor(region.position.y * bounds.size.y))
	var right := bounds.position.x + int(ceil((region.position.x + region.size.x) * bounds.size.x))
	var bottom := bounds.position.y + int(ceil((region.position.y + region.size.y) * bounds.size.y))
	return image.get_region(Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size())))

static func _fit(source: Image, target: Vector2i) -> Image:
	var scale := minf(float(target.x) / source.get_width(), float(target.y) / source.get_height())
	var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
	var result := source.duplicate()
	if result.get_size() != size:
		result.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return result

static func _draw_checker(image: Image, rect: Rect2i) -> void:
	var tile := 24
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var color := Color("#3d4247") if ((x / tile) + (y / tile)) % 2 == 0 else Color("#292e33")
			image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), color)

static func _alpha_bounds(image: Image) -> Rect2i:
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

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _has_png_signature(bytes: PackedByteArray) -> bool:
	var signature := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < signature.size():
		return false
	for index in range(signature.size()):
		if bytes[index] != signature[index]:
			return false
	return true

static func _canonical_path(path: String) -> String:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else (path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path))
	return resolved.replace("\\", "/").simplify_path().to_lower()

static func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
