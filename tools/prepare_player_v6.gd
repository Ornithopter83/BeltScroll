extends SceneTree

const TARGET := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const CONTENT_LIMIT := 1074
const SOURCE := "res://assets/art/player/elven_fighter_reference_v6_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_reference_v6_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_reference_v6_clean_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v6_comparison.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const EDGE_RADIUS := 8

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --script res://tools/prepare_player_v6.gd")
		quit(0)
		return
	if not args.is_empty():
		printerr("인수 없이 실행하세요.")
		quit(2)
		return
	var source_path := _resolve(SOURCE)
	var original_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	if source == null:
		_fail("v6 원본 PNG를 읽을 수 없습니다.")
		return
	var safe := normalize_image(source)
	if safe == null:
		_fail("v6 원본 정규화에 실패했습니다.")
		return
	var cleaned := clean_image(safe)
	var error := _save_png(safe, _resolve(SAFE))
	if error == OK:
		error = _save_png(cleaned["image"], _resolve(CLEAN))
	if error == OK:
		error = build_comparison(source, safe, cleaned["image"], _load_png(_resolve(FOREST)), _resolve(REVIEW))
	if error != OK:
		_fail("후보 또는 비교 이미지 저장 실패: %s" % error_string(error))
		return
	if FileAccess.get_file_as_bytes(source_path) != original_bytes:
		_fail("원본 바이트가 변경됐습니다.")
		return
	print("player_v6_prepare: safe/clean 후보 및 흰색·검정·체커보드·Forest Ruins 비교본 생성 완료; 변경 픽셀 %d" % int(cleaned["changed"]))
	quit(0)

static func normalize_image(source: Image) -> Image:
	if source == null or source.is_empty():
		return null
	var rgba := source.duplicate()
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba.convert(Image.FORMAT_RGBA8)
	var bounds := _alpha_bounds(rgba)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var scale := minf(1.0, minf(float(CONTENT_LIMIT) / bounds.size.x, float(CONTENT_LIMIT) / bounds.size.y))
	var size := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var content: Image = rgba.get_region(bounds)
	if content.get_size() != size:
		content.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var result := Image.create(TARGET.x, TARGET.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(content, Rect2i(Vector2i.ZERO, size), (TARGET - size) / 2)
	return result

# Only boundary pixels with alpha support are considered. Replacement RGB is
# drawn from nearby opaque foreground pixels along the local inward direction;
# alpha, pixel locations, and the original image remain untouched.
static func clean_image(source: Image) -> Dictionary:
	if source == null or source.is_empty():
		return {"image": null, "changed": 0}
	var output := source.duplicate()
	var bounds := _alpha_bounds(source)
	var replacements: Dictionary = {}
	for y in range(maxi(1, bounds.position.y - EDGE_RADIUS), mini(source.get_height() - 1, bounds.end.y + EDGE_RADIUS)):
		for x in range(maxi(1, bounds.position.x - EDGE_RADIUS), mini(source.get_width() - 1, bounds.end.x + EDGE_RADIUS)):
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.02 or _alpha_distance(source, x, y, EDGE_RADIUS) > EDGE_RADIUS:
				continue
			var reference := _inward_color(source, x, y, EDGE_RADIUS)
			if not bool(reference["valid"]):
				reference = _local_foreground_color(source, x, y, EDGE_RADIUS)
			if not bool(reference["valid"]):
				continue
			var local: Color = reference["color"]
			if _is_warm_fringe(pixel, local):
				replacements[Vector2i(x, y)] = local
	var changed := 0
	for point in replacements:
		var pixel := source.get_pixelv(point)
		var local: Color = replacements[point]
		output.set_pixelv(point, Color(local.r, local.g, local.b, pixel.a))
		changed += 1
	return {"image": output, "changed": changed}

static func _is_warm_fringe(pixel: Color, local: Color) -> bool:
	if pixel.s < 0.48 or pixel.v < 0.32:
		return false
	var hue := pixel.h
	var red := hue < 0.055 or hue > 0.965
	var yellow := hue >= 0.075 and hue <= 0.17
	if not red and not yellow:
		return false
	var distance := _rgb_distance(pixel, local)
	if distance < 0.20:
		return false
	var hue_delta := absf(hue - local.h)
	hue_delta = minf(hue_delta, 1.0 - hue_delta)
	# Preserve skin, gold trim, and warm hair supported by a similar neighboring hue.
	if local.s >= 0.18 and hue_delta <= 0.07 and distance < 0.52:
		return false
	# A hot red/yellow edge is treated as spill only when adjacent foreground
	# supports a distinctly different color. This avoids global color replacement.
	if red:
		return pixel.r >= local.r + 0.10 or pixel.g <= local.g - 0.09
	return pixel.s >= 0.68 and pixel.r >= local.r + 0.12 and pixel.g >= local.g + 0.06

static func pollution_count(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var count := 0
	var bounds := _alpha_bounds(image)
	for y in range(maxi(1, bounds.position.y), mini(image.get_height() - 1, bounds.end.y)):
		for x in range(maxi(1, bounds.position.x), mini(image.get_width() - 1, bounds.end.x)):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.02 or _alpha_distance(image, x, y, EDGE_RADIUS) > EDGE_RADIUS:
				continue
			var reference := _inward_color(image, x, y, EDGE_RADIUS)
			if not bool(reference["valid"]):
				reference = _local_foreground_color(image, x, y, EDGE_RADIUS)
			if bool(reference["valid"]) and _is_warm_fringe(pixel, reference["color"]):
				count += 1
	return count

static func build_comparison(original: Image, safe: Image, clean: Image, forest: Image, output_path: String) -> Error:
	if original == null or safe == null or clean == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if safe.get_size() != TARGET or clean.get_size() != TARGET or forest.is_empty():
		return ERR_INVALID_DATA
	var variants: Array[Image] = [original, safe, clean]
	var canvas := Image.create(1920, 2900, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var backgrounds := [Color.WHITE, Color("#080a0c"), Color("#292e33"), Color("#171b20")]
	for row in range(4):
		for col in range(3):
			var x := col * 640
			var y := row * 520
			var tile := Image.create(620, 510, false, Image.FORMAT_RGBA8)
			if row == 3:
				var forest_tile := forest.duplicate()
				forest_tile.resize(tile.get_width(), tile.get_height(), Image.INTERPOLATE_LANCZOS)
				tile.blit_rect(forest_tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i.ZERO)
			elif row == 2:
				_draw_checker(tile)
			else:
				tile.fill(backgrounds[row])
			var bounds := _alpha_bounds(variants[col])
			var figure := _fit(variants[col].get_region(bounds), Vector2i(350, 250))
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((620 - figure.get_width()) / 2, 8))
			var face := _crop_relative(variants[col], bounds, Rect2(0.43, 0.04, 0.42, 0.30))
			var ponytail := _crop_relative(variants[col], bounds, Rect2(0.02, 0.00, 0.52, 0.48))
			var face_fit := _fit(face, Vector2i(285, 220))
			var pony_fit := _fit(ponytail, Vector2i(285, 220))
			tile.blend_rect(face_fit, Rect2i(Vector2i.ZERO, face_fit.get_size()), Vector2i(12, 276))
			tile.blend_rect(pony_fit, Rect2i(Vector2i.ZERO, pony_fit.get_size()), Vector2i(323, 276))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(x + 10, y + 5))
			canvas.fill_rect(Rect2i(x + 10, y + 5, 620, 5), [Color("#db7064"), Color("#68aeca"), Color("#77c197")][col])
	# Last four rows show each candidate at a 192px figure height over all backgrounds.
	for row in range(4):
		for col in range(3):
			var x := col * 640
			var y := 2080 + row * 205
			var tile := Image.create(620, 200, false, Image.FORMAT_RGBA8)
			if row == 0:
				tile.fill(Color.WHITE)
			elif row == 1:
				tile.fill(Color("#080a0c"))
			elif row == 2:
				_draw_checker(tile)
			else:
				var bg := forest.duplicate()
				bg.resize(tile.get_width(), tile.get_height(), Image.INTERPOLATE_LANCZOS)
				tile.blit_rect(bg, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i.ZERO)
			var bounds := _alpha_bounds(variants[col])
			var figure := variants[col].get_region(bounds)
			var width := maxi(1, roundi(float(figure.get_width()) * 192.0 / figure.get_height()))
			figure.resize(width, 192, Image.INTERPOLATE_LANCZOS)
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((620 - width) / 2, 4))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(x + 10, y))
	return _save_png(canvas, output_path)

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var x := bounds.position.x + int(floor(region.position.x * bounds.size.x))
	var y := bounds.position.y + int(floor(region.position.y * bounds.size.y))
	var right := bounds.position.x + int(ceil((region.position.x + region.size.x) * bounds.size.x))
	var bottom := bounds.position.y + int(ceil((region.position.y + region.size.y) * bounds.size.y))
	return image.get_region(Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size())))

static func _fit(source: Image, limit: Vector2i) -> Image:
	var scale := minf(float(limit.x) / source.get_width(), float(limit.y) / source.get_height())
	var result := source.duplicate()
	result.resize(maxi(1, roundi(source.get_width() * scale)), maxi(1, roundi(source.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return result

static func _draw_checker(image: Image) -> void:
	for y in range(0, image.get_height(), 24):
		for x in range(0, image.get_width(), 24):
			var color := Color("#3d4247") if ((x / 24 + y / 24) % 2 == 0) else Color("#292e33")
			image.fill_rect(Rect2i(x, y, mini(24, image.get_width() - x), mini(24, image.get_height() - y)), color)

static func _alpha_distance(image: Image, x: int, y: int, limit: int) -> int:
	for radius in range(1, limit + 1):
		for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
			for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
				if absi(nx - x) != radius and absi(ny - y) != radius:
					continue
				if image.get_pixel(nx, ny).a <= 0.02:
					return radius
	return limit + 1

static func _inward_color(image: Image, x: int, y: int, radius: int) -> Dictionary:
	var nearest := Vector2i.ZERO
	var best := INF
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if image.get_pixel(nx, ny).a > 0.02:
				continue
			var distance := Vector2(float(nx - x), float(ny - y)).length()
			if distance < best:
				best = distance
				nearest = Vector2i(nx, ny)
	if best == INF:
		return {"valid": false, "color": Color.TRANSPARENT}
	var direction := Vector2(float(x - nearest.x), float(y - nearest.y)).normalized()
	var nearest_supported := Color.TRANSPARENT
	for step in range(1, radius + 1):
		var point := Vector2i(clampi(x + roundi(direction.x * step), 0, image.get_width() - 1), clampi(y + roundi(direction.y * step), 0, image.get_height() - 1))
		var sample := image.get_pixelv(point)
		if sample.a >= 0.82:
			nearest_supported = sample
	# A few pixels deeper avoids sampling a multi-pixel spill as its own support.
	# Stop early enough to avoid crossing narrow strands or limbs.
			if step >= mini(4, radius):
				return {"valid": true, "color": sample}
	return {"valid": nearest_supported.a > 0.0, "color": nearest_supported}

static func _local_foreground_color(image: Image, x: int, y: int, radius: int) -> Dictionary:
	var best := INF
	var chosen := Color.TRANSPARENT
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			var sample := image.get_pixel(nx, ny)
			if sample.a < 0.88:
				continue
			var distance := Vector2(float(nx - x), float(ny - y)).length()
			if distance > 0.0 and distance < best:
				best = distance
				chosen = sample
	return {"valid": best < INF, "color": chosen}

static func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

static func _alpha_bounds(image: Image) -> Rect2i:
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
	var directory := path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var error := DirAccess.make_dir_recursive_absolute(directory)
		if error != OK:
			return error
	return image.save_png(path)

static func _resolve(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path

func _fail(message: String) -> void:
	push_error("player_v6_prepare: " + message)
	quit(1)
