extends SceneTree

const TARGET := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const CONTENT_LIMIT := 1074
const EDGE_BAND := 4
const INK := Color("#30241f")
const SOURCE := "res://assets/art/player/elven_fighter_reference_v7_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_reference_v7_safe_1254x1254.png"
const INK_CANDIDATE := "res://assets/art/player/elven_fighter_reference_v7_ink_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v7_ink_review.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --path . --script res://tools/prepare_player_v7_ink.gd")
		quit(0)
		return
	if not args.is_empty():
		printerr("예기치 않은 인수입니다.")
		quit(2)
		return
	var source_path := _resolve(SOURCE)
	var original_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	if source == null:
		_fail("v7 원본 PNG를 읽을 수 없습니다.")
		return
	var safe := normalize_image(source)
	if safe == null:
		_fail("v7 원본 정규화에 실패했습니다.")
		return
	var processed := ink_image(safe)
	var err := _save_png(safe, _resolve(SAFE))
	if err == OK:
		err = _save_png(processed["image"], _resolve(INK_CANDIDATE))
	var forest := _load_png(_resolve(FOREST))
	if err == OK:
		err = build_review(source, safe, processed["image"], forest, _resolve(REVIEW))
	if err != OK:
		_fail("후보 또는 검수 이미지 저장 실패: %s" % error_string(err))
		return
	if FileAccess.get_file_as_bytes(source_path) != original_bytes:
		_fail("원본 바이트가 변경됐습니다.")
		return
	print("player_v7_ink_prepare: safe/ink/review 생성 완료; 재구성 픽셀 %d (자동 승인 없음)" % int(processed["changed"]))
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

# Alpha topology selects the only pixels eligible for reconstruction. A local
# inward sample supplies the expected foreground color, so skin, hair, and gold
# remain intact whenever their edge agrees with nearby opaque interior pixels.
static func ink_image(source: Image) -> Dictionary:
	if source == null or source.is_empty():
		return {"image": null, "changed": 0}
	var result := source.duplicate()
	var bounds := _alpha_bounds(source)
	var replacement: Dictionary = {}
	for y in range(maxi(1, bounds.position.y - EDGE_BAND), mini(source.get_height() - 1, bounds.end.y + EDGE_BAND)):
		for x in range(maxi(1, bounds.position.x - EDGE_BAND), mini(source.get_width() - 1, bounds.end.x + EDGE_BAND)):
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.02:
				continue
			var edge_distance := _alpha_distance(source, x, y, EDGE_BAND)
			if edge_distance < 1 or edge_distance > EDGE_BAND:
				continue
			var reference := _local_inward_color(source, x, y, EDGE_BAND)
			if not bool(reference["valid"]):
				continue
			var expected: Color = reference["color"]
			if _is_local_contamination(pixel, expected):
				replacement[Vector2i(x, y)] = INK
	var changed := 0
	for point in replacement:
		var old := source.get_pixelv(point)
		result.set_pixelv(point, Color(INK.r, INK.g, INK.b, old.a))
		changed += 1
	return {"image": result, "changed": changed}

static func _is_local_contamination(pixel: Color, expected: Color) -> bool:
	# A stain must disagree materially with the local color AND be chromatic.
	# The comparison is local; there are no global red/yellow RGB cutoffs.
	var distance := _rgb_distance(pixel, expected)
	if distance < 0.20 or pixel.s < 0.42 or pixel.v < 0.28:
		return false
	var hue_delta := absf(pixel.h - expected.h)
	hue_delta = minf(hue_delta, 1.0 - hue_delta)
	return hue_delta > 0.075 and distance > 0.28

static func pollution_count(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var bounds := _alpha_bounds(image)
	var count := 0
	for y in range(maxi(1, bounds.position.y), mini(image.get_height() - 1, bounds.end.y)):
		for x in range(maxi(1, bounds.position.x), mini(image.get_width() - 1, bounds.end.x)):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.02:
				continue
			var distance := _alpha_distance(image, x, y, EDGE_BAND)
			if distance < 1 or distance > EDGE_BAND:
				continue
			var reference := _local_inward_color(image, x, y, EDGE_BAND)
			if bool(reference["valid"]) and _is_local_contamination(pixel, reference["color"]):
				count += 1
	return count

static func build_review(original: Image, safe: Image, ink: Image, forest: Image, output_path: String) -> Error:
	if original == null or safe == null or ink == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if safe.get_size() != TARGET or ink.get_size() != TARGET or forest.is_empty():
		return ERR_INVALID_DATA
	var variants: Array[Image] = [original, safe, ink]
	var canvas := Image.create(1920, 2900, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var bg_names := ["#FFFFFF", "#080a0c", "checker", "Forest Ruins"]
	for row in range(4):
		for col in range(3):
			var tile := Image.create(620, 510, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var variant := variants[col]
			var bounds := _alpha_bounds(variant)
			var full := _fit(variant.get_region(bounds), Vector2i(330, 250))
			tile.blend_rect(full, Rect2i(Vector2i.ZERO, full.get_size()), Vector2i((620 - full.get_width()) / 2, 6))
			# Side-by-side face and ponytail detail crops in each background panel.
			var face := _crop_relative(variant, bounds, Rect2(0.43, 0.02, 0.39, 0.31))
			var pony := _crop_relative(variant, bounds, Rect2(0.00, 0.00, 0.54, 0.48))
			var face_fit := _fit(face, Vector2i(285, 220))
			var pony_fit := _fit(pony, Vector2i(285, 220))
			tile.blend_rect(face_fit, Rect2i(Vector2i.ZERO, face_fit.get_size()), Vector2i(10, 276))
			tile.blend_rect(pony_fit, Rect2i(Vector2i.ZERO, pony_fit.get_size()), Vector2i(325, 276))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, row * 520 + 5))
			canvas.fill_rect(Rect2i(col * 640 + 10, row * 520 + 5, 620, 5), [Color("#db7064"), Color("#68aeca"), Color("#77c197")][col])
	# Bottom band: exact 192px-high display samples over every requested backdrop.
	for row in range(4):
		for col in range(3):
			var tile := Image.create(620, 200, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var bounds := _alpha_bounds(variants[col])
			var figure := variants[col].get_region(bounds)
			var width := maxi(1, roundi(float(figure.get_width()) * 192.0 / figure.get_height()))
			figure.resize(width, 192, Image.INTERPOLATE_LANCZOS)
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((620 - width) / 2, 4))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, 2080 + row * 205))
	return _save_png(canvas, output_path)

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

static func _local_inward_color(image: Image, x: int, y: int, radius: int) -> Dictionary:
	var nearest := Vector2i.ZERO
	var best := INF
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if image.get_pixel(nx, ny).a > 0.02:
				continue
			var d := Vector2(float(nx - x), float(ny - y)).length()
			if d < best:
				best = d
				nearest = Vector2i(nx, ny)
	if best == INF:
		return {"valid": false, "color": Color.TRANSPARENT}
	var inward := Vector2(float(x - nearest.x), float(y - nearest.y)).normalized()
	var samples: Array[Color] = []
	# Skip the contaminated rim itself, then take a robust local sample farther
	# inward. This also handles 1–4px colored bands without sampling the stain.
	for step in range(radius, radius + 6):
		var p := Vector2i(clampi(x + roundi(inward.x * step), 0, image.get_width() - 1), clampi(y + roundi(inward.y * step), 0, image.get_height() - 1))
		var sample := image.get_pixelv(p)
		if sample.a >= 0.92:
			samples.append(sample)
	if samples.is_empty():
		return {"valid": false, "color": Color.TRANSPARENT}
	return {"valid": true, "color": _median_color(samples)}

static func _median_color(samples: Array[Color]) -> Color:
	var rs: Array[float] = []
	var gs: Array[float] = []
	var bs: Array[float] = []
	for color in samples:
		rs.append(color.r); gs.append(color.g); bs.append(color.b)
	rs.sort(); gs.sort(); bs.sort()
	var middle := samples.size() / 2
	return Color(rs[middle], gs[middle], bs[middle], 1.0)

static func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

static func _alpha_distance(image: Image, x: int, y: int, limit: int) -> int:
	for radius in range(1, limit + 1):
		for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
			for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
				if absi(nx - x) != radius and absi(ny - y) != radius:
					continue
				if image.get_pixel(nx, ny).a <= 0.02:
					return radius
	return limit + 1

static func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width(); var top := image.get_height()
	var right := -1; var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x); top = mini(top, y)
				right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var x := bounds.position.x + floori(region.position.x * bounds.size.x)
	var y := bounds.position.y + floori(region.position.y * bounds.size.y)
	var right := bounds.position.x + ceili((region.position.x + region.size.x) * bounds.size.x)
	var bottom := bounds.position.y + ceili((region.position.y + region.size.y) * bounds.size.y)
	var rect := Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)

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

func _fail(message: String) -> void:
	push_error("player_v7_ink_prepare: " + message)
	quit(1)
