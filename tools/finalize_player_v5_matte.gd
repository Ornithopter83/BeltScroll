extends SceneTree

const TARGET_SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const SOURCE := "res://assets/art/player/elven_fighter_reference_v5_clean_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_reference_v5_final_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v5_final_matte_review.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const REVIEW_SIZE := Vector2i(2200, 2080)
const CELL_SIZE := Vector2i(535, 490)

func _initialize() -> void:
	call_deferred("_run_cli")

func _run_cli() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --script res://tools/finalize_player_v5_matte.gd [입력 PNG 출력 PNG 검토 PNG]")
		quit(0)
		return
	if not args.is_empty() and args.size() != 3:
		printerr("사용법: godot --headless --script res://tools/finalize_player_v5_matte.gd [입력 PNG 출력 PNG 검토 PNG]")
		quit(2)
		return
	var source_path := _resolve_path(args[0] if args.size() == 3 else SOURCE)
	var output_path := _resolve_path(args[1] if args.size() == 3 else OUTPUT)
	var review_path := _resolve_path(args[2] if args.size() == 3 else REVIEW)
	var error := finalize_file(source_path, output_path)
	if error == OK:
		error = build_review(source_path, output_path, review_path)
	if error != OK:
		printerr("player-v5-final-matte 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	print("player-v5-final-matte: 후보와 흰색·검정·체커보드·Forest Ruins 전후 검토 이미지 생성 완료")
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
	if source.get_size() != TARGET_SIZE:
		return ERR_INVALID_DATA
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var candidate := refine_image(source)
	var bounds := _alpha_bounds(candidate)
	if not _has_margin(bounds):
		return ERR_INVALID_DATA
	var parent := output_path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		var dir_error := DirAccess.make_dir_recursive_absolute(parent)
		if dir_error != OK:
			return dir_error
	return candidate.save_png(output_path)

# Detect contamination only where the alpha topology says an edge is exposed:
# both the outer silhouette and transparent holes between strands qualify.
# The replacement is a robust local foreground medoid; alpha changes are kept
# to a tiny reduction for a low-confidence, very faint extreme edge only.
static func refine_image(source: Image) -> Image:
	var output := source.duplicate()
	var bounds := _alpha_bounds(source)
	for y in range(1, source.get_height() - 1):
		for x in range(1, source.get_width() - 1):
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.015 or not _near_transparent_boundary(source, x, y, 2):
				continue
			if _is_protected_head_feature(x, y, bounds):
				continue
			var evidence := _foreground_medoid(source, x, y, 6)
			if not bool(evidence["valid"]):
				continue
			var reference: Color = evidence["color"]
			var support: int = evidence["support"]
			var distance := Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(reference.r, reference.g, reference.b))
			if not _is_supported_warm_outlier(pixel, reference, distance, support):
				continue
			# A warm color supported by nearby opaque pixels belongs to real hair,
			# skin, ear, or gold trim and is never treated as spill.
			var mix := clampf(0.74 + float(support) * 0.025, 0.74, 0.90)
			output.set_pixel(x, y, Color(
				lerpf(pixel.r, reference.r, mix),
				lerpf(pixel.g, reference.g, mix),
				lerpf(pixel.b, reference.b, mix), pixel.a))
	return output

static func _is_protected_head_feature(x: int, y: int, bounds: Rect2i) -> bool:
	var relative := Vector2(float(x - bounds.position.x) / bounds.size.x, float(y - bounds.position.y) / bounds.size.y)
	# Face, pointed ear, and ponytail clasp/ornament are manually protected.
	return Rect2(0.36, 0.035, 0.36, 0.235).has_point(relative)

static func _foreground_medoid(image: Image, x: int, y: int, radius: int) -> Dictionary:
	var samples: Array[Color] = []
	var weights: Array[float] = []
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if nx == x and ny == y:
				continue
			var candidate := image.get_pixel(nx, ny)
			# High-confidence interior samples keep partial-alpha edge color from
			# voting for itself as the local foreground.
			if candidate.a < 0.97:
				continue
			var distance := Vector2(float(nx - x), float(ny - y)).length()
			if distance > float(radius):
				continue
			samples.append(candidate)
			weights.append(1.0 / maxf(1.0, distance * distance))
	if samples.size() < 3:
		return {"valid": false, "color": Color.TRANSPARENT, "support": 0}
	# Pick the sample with the greatest nearby color consensus. Unlike a mean,
	# this cannot invent a skin/hair/gold blend at mixed feature boundaries.
	var best := -1
	var best_score := -1.0
	var best_support := 0
	for i in range(samples.size()):
		var score := 0.0
		var support := 0
		var c := samples[i]
		for j in range(samples.size()):
			var other := samples[j]
			var d := Vector3(c.r - other.r, c.g - other.g, c.b - other.b).length()
			if d <= 0.20:
				score += weights[j]
				support += 1
		if score > best_score:
			best = i
			best_score = score
			best_support = support
	if best < 0 or best_support < 2:
		return {"valid": false, "color": Color.TRANSPARENT, "support": 0}
	return {"valid": true, "color": samples[best], "support": best_support}

static func _is_supported_warm_outlier(pixel: Color, reference: Color, distance: float, support: int) -> bool:
	if pixel.s < 0.42 or distance < 0.22:
		return false
	var hue := pixel.h
	var warm := hue < 0.055 or hue > 0.955 or (hue >= 0.075 and hue <= 0.17)
	if not warm:
		return false
	var color_support := Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(reference.r, reference.g, reference.b))
	# A nearby opaque consensus in the same warm family is a protected feature.
	if reference.s >= 0.24 and absf(pixel.h - reference.h) < 0.065 and color_support < 0.48:
		return false
	return support >= 2

static func _near_transparent_boundary(image: Image, x: int, y: int, radius: int) -> bool:
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if nx == x and ny == y:
				continue
			if image.get_pixel(nx, ny).a < 0.025:
				return true
	return false

static func build_review(before_path: String, after_path: String, output_path: String) -> Error:
	var before := _load_png(before_path)
	var after := _load_png(after_path)
	var forest := _load_png(_resolve_path(FOREST))
	if before == null or after == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if before.get_size() != TARGET_SIZE or after.get_size() != TARGET_SIZE:
		return ERR_INVALID_DATA
	var canvas := Image.create(REVIEW_SIZE.x, REVIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var bounds := _alpha_bounds(before)
	var regions: Array[Rect2] = [
		Rect2(0.0, 0.0, 1.0, 1.0), # full figure
		Rect2(0.39, 0.00, 0.34, 0.25), # face, ear, and hairline
		Rect2(0.00, 0.00, 0.56, 0.40), # ponytail and tie
		Rect2(0.00, 0.00, 1.0, 1.0), # 192px in-game silhouette
	]
	var forest_background := forest.duplicate()
	forest_background.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_LANCZOS)
	for background in range(4):
		for column in range(4):
			var cell_x := 25 + column * 540
			var cell_y := 20 + background * 515
			for side in range(2):
				var x := cell_x + side * 268
				var panel := Image.create(264, CELL_SIZE.y, false, Image.FORMAT_RGBA8)
				match background:
					0: panel.fill(Color.WHITE)
					1: panel.fill(Color("#101216"))
					2: _draw_checker(panel, Rect2i(Vector2i.ZERO, panel.get_size()))
					3: panel.blit_rect(forest_background, Rect2i(Vector2i.ZERO, forest_background.get_size()), Vector2i.ZERO)
				var image := before if side == 0 else after
				var crop := _crop_relative(image, bounds, regions[column])
				if column == 3:
					var silhouette := crop.get_region(_alpha_bounds(crop))
					var target_height := 192
					var target_width := maxi(1, int(round(float(silhouette.get_width()) * target_height / silhouette.get_height())))
					silhouette.resize(target_width, target_height, Image.INTERPOLATE_LANCZOS)
					crop = silhouette
				var fitted := _fit(crop, Vector2i(248, CELL_SIZE.y - 24))
				panel.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()),
					Vector2i((panel.get_width() - fitted.get_width()) / 2, (panel.get_height() - fitted.get_height()) / 2))
				canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(x, cell_y))
				canvas.fill_rect(Rect2i(x, cell_y, panel.get_width(), 5), Color("#e05b54") if side == 0 else Color("#69b8a2"))
			canvas.fill_rect(Rect2i(cell_x + 264, cell_y, 2, CELL_SIZE.y), Color("#626b73"))
	var parent := output_path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		var dir_error := DirAccess.make_dir_recursive_absolute(parent)
		if dir_error != OK:
			return dir_error
	return canvas.save_png(output_path)

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var x := bounds.position.x + int(floor(region.position.x * bounds.size.x))
	var y := bounds.position.y + int(floor(region.position.y * bounds.size.y))
	var right := bounds.position.x + int(ceil((region.position.x + region.size.x) * bounds.size.x))
	var bottom := bounds.position.y + int(ceil((region.position.y + region.size.y) * bounds.size.y))
	var rect := Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)

static func _fit(source: Image, target: Vector2i) -> Image:
	var scale := minf(float(target.x) / source.get_width(), float(target.y) / source.get_height())
	var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
	var result := source.duplicate()
	if result.get_size() != size:
		result.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return result

static func _draw_checker(image: Image, rect: Rect2i) -> void:
	var tile := 18
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var color := Color("#454a50") if ((x / tile) + (y / tile)) % 2 == 0 else Color("#252a30")
			image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), color)

static func _has_margin(bounds: Rect2i) -> bool:
	return bounds.size.x > 0 and bounds.size.y > 0 and bounds.position.x >= MIN_MARGIN and bounds.position.y >= MIN_MARGIN \
		and TARGET_SIZE.x - bounds.end.x >= MIN_MARGIN and TARGET_SIZE.y - bounds.end.y >= MIN_MARGIN

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
	for i in range(signature.size()):
		if bytes[i] != signature[i]:
			return false
	return true

static func _canonical_path(path: String) -> String:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else (path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path))
	return resolved.replace("\\", "/").simplify_path().to_lower()

static func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
