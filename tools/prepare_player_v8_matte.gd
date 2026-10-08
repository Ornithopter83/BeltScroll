extends SceneTree

const SIZE := Vector2i(1254, 1254)
const CONTENT_LIMIT := 1074
const SOURCE := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_reference_v8_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v8_matte_comparison.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const CONTEXT_RADIUS := 7

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --path . --script res://tools/prepare_player_v8_matte.gd")
		quit(0)
		return
	if not args.is_empty():
		_fail("예기치 않은 인수입니다.", 2)
		return
	var source_path := _resolve(SOURCE)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	if source == null or source.get_size() != SIZE:
		_fail("v8 입력 PNG가 없거나 1254×1254 규격이 아닙니다.")
		return
	var safe := normalize(source)
	if safe == null:
		_fail("v8 안전 후보 정규화에 실패했습니다.")
		return
	var cleaned_result := clean_matte(safe)
	var clean: Image = cleaned_result["image"]
	if clean == null:
		_fail("v8 matte 정리에 실패했습니다.")
		return
	var forest := _load_png(_resolve(FOREST))
	if forest == null:
		_fail("숲 배경 검수 입력을 읽을 수 없습니다.")
		return
	var err := _save_png(safe, _resolve(SAFE))
	if err == OK:
		err = _save_png(clean, _resolve(CLEAN))
	if err == OK:
		err = build_review(source, safe, clean, forest, _resolve(REVIEW))
	if err != OK:
		_fail("후보 또는 검수 이미지 저장 실패: %s" % error_string(err))
		return
	if FileAccess.get_file_as_bytes(source_path) != source_bytes:
		_fail("v8 원본 바이트가 변경됐습니다.")
		return
	print("player_v8_matte: safe/clean/review 생성 완료; 외부 alpha 제거 %d, 내부 색 복원 %d (시각 검수 승인 없음)" % [int(cleaned_result["removed"]), int(cleaned_result["restored"])])
	quit(0)

# Crops the visible source bounds, fits them without enlargement, and centers
# the result into transparent 1254px canvas, guaranteeing at least 90px margins.
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
	var size := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var content: Image = rgba.get_region(bounds)
	if content.get_size() != size:
		content.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var result := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(content, Rect2i(Vector2i.ZERO, size), (SIZE - size) / 2)
	return result

# The mask is contextual: a candidate must be a saturated red outlier compared
# with nearby opaque pixels. Connected regions touching transparency are erased;
# enclosed regions are repaired from a robust ring of nearby normal colors.
static func clean_matte(source: Image) -> Dictionary:
	if source == null or source.is_empty() or source.get_size() != SIZE:
		return {"image": null, "removed": 0, "restored": 0}
	var w := source.get_width()
	var h := source.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var i := y * w + x
			var pixel := source.get_pixel(x, y)
			if pixel.a < 0.005 or pixel.s <= 0.60 or pixel.r - maxf(pixel.g, pixel.b) <= 0.24:
				continue
			var context := _context_color(source, x, y, CONTEXT_RADIUS)
			if _is_contextual_red_outlier(pixel, context):
				mask[i] = 1
	var components := _components(mask, w, h)
	var result := source.duplicate()
	var removed := 0
	var restored := 0
	for component in components:
		# Ignore isolated natural pixels; stains/fringes form a coherent patch.
		if component.size() < 2:
			continue
		var exterior := false
		for value in component:
			var index := int(value)
			var x: int = index % w
			var y: int = floori(float(index) / w)
			if _touches_transparency(source, x, y):
				exterior = true
				break
		for value in component:
			var index := int(value)
			var x: int = index % w
			var y: int = floori(float(index) / w)
			var old := source.get_pixel(x, y)
			if exterior:
				result.set_pixel(x, y, Color(old.r, old.g, old.b, 0.0))
				removed += 1
			else:
				var repair := _repair_color(source, mask, x, y, w, h)
				if repair.a > 0.0:
					result.set_pixel(x, y, Color(repair.r, repair.g, repair.b, old.a))
					restored += 1
	return {"image": result, "removed": removed, "restored": restored}

static func _is_contextual_red_outlier(pixel: Color, context: Color) -> bool:
	if context.a <= 0.0:
		return false
	# Hue and saturation describe a local color disagreement, while luminance
	# deviation rejects ordinary red-brown leather, skin and warm gold details.
	var hue_delta := absf(pixel.h - context.h)
	hue_delta = minf(hue_delta, 1.0 - hue_delta)
	var color_distance := Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(context.r, context.g, context.b))
	var red_direction := pixel.r - maxf(pixel.g, pixel.b)
	return pixel.s > 0.60 and context.s < pixel.s - 0.25 and hue_delta > 0.035 \
		and red_direction > 0.24 and color_distance > 0.30 \
		and (absf(pixel.v - context.v) > 0.07 or hue_delta > 0.08)

static func _context_color(image: Image, x: int, y: int, radius: int) -> Color:
	var rs: Array[float] = []
	var gs: Array[float] = []
	var bs: Array[float] = []
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if ox == 0 and oy == 0:
				continue
			var p := image.get_pixel(x + ox, y + oy)
			if p.a < 0.72:
				continue
			rs.append(p.r); gs.append(p.g); bs.append(p.b)
	if rs.size() < 4:
		return Color.TRANSPARENT
	rs.sort(); gs.sort(); bs.sort()
	var middle := rs.size() / 2
	return Color(rs[middle], gs[middle], bs[middle], 1.0)

static func _repair_color(image: Image, mask: PackedByteArray, x: int, y: int, w: int, h: int) -> Color:
	var rs: Array[float] = []; var gs: Array[float] = []; var bs: Array[float] = []
	for radius in range(1, 7):
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				if maxi(absi(ox), absi(oy)) != radius:
					continue
				var nx := x + ox; var ny := y + oy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := ny * w + nx
				var p := image.get_pixel(nx, ny)
				if mask[ni] != 0 or p.a < 0.72:
					continue
				rs.append(p.r); gs.append(p.g); bs.append(p.b)
		if rs.size() >= 5:
			break
	if rs.size() < 3:
		return Color.TRANSPARENT
	rs.sort(); gs.sort(); bs.sort()
	var mid := rs.size() / 2
	return Color(rs[mid], gs[mid], bs[mid], 1.0)

static func _components(mask: PackedByteArray, w: int, h: int) -> Array[Array]:
	var visited := PackedByteArray()
	visited.resize(w * h)
	var result: Array[Array] = []
	for start in range(mask.size()):
		if mask[start] == 0 or visited[start] != 0:
			continue
		var points: Array[int] = [start]
		visited[start] = 1
		var head := 0
		while head < points.size():
			var index: int = points[head]
			head += 1
			var x := index % w; var y := index / w
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox; var ny := y + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni := ny * w + nx
					if mask[ni] != 0 and visited[ni] == 0:
						visited[ni] = 1
						points.append(ni)
		result.append(points)
	return result

static func _touches_transparency(image: Image, x: int, y: int) -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			if image.get_pixel(x + ox, y + oy).a < 0.12:
				return true
	return false

static func build_review(original: Image, safe: Image, clean: Image, forest: Image, output_path: String) -> Error:
	if original == null or safe == null or clean == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if safe.get_size() != SIZE or clean.get_size() != SIZE or forest.is_empty():
		return ERR_INVALID_DATA
	var variants: Array[Image] = [original, safe, clean]
	var canvas := Image.create(1920, 2940, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	for row in range(4):
		for col in range(3):
			var tile := Image.create(620, 510, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var variant := variants[col]
			var bounds := _alpha_bounds(variant)
			if bounds.size.x <= 0:
				return ERR_INVALID_DATA
			var full := _fit(variant.get_region(bounds), Vector2i(330, 250))
			tile.blend_rect(full, Rect2i(Vector2i.ZERO, full.get_size()), Vector2i((620 - full.get_width()) / 2, 5))
			var face := _crop_relative(variant, bounds, Rect2(0.40, 0.03, 0.45, 0.31))
			var pony := _crop_relative(variant, bounds, Rect2(0.00, 0.00, 0.57, 0.44))
			var face_fit := _fit(face, Vector2i(285, 220))
			var pony_fit := _fit(pony, Vector2i(285, 220))
			tile.blend_rect(face_fit, Rect2i(Vector2i.ZERO, face_fit.get_size()), Vector2i(10, 276))
			tile.blend_rect(pony_fit, Rect2i(Vector2i.ZERO, pony_fit.get_size()), Vector2i(325, 276))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, row * 520 + 5))
	# Four backgrounds, each showing original/safe/clean at exactly 192px tall.
	for row in range(4):
		for col in range(3):
			var tile := Image.create(620, 200, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var bounds := _alpha_bounds(variants[col])
			var figure := variants[col].get_region(bounds)
			var width := maxi(1, roundi(float(figure.get_width()) * 192.0 / figure.get_height()))
			figure.resize(width, 192, Image.INTERPOLATE_LANCZOS)
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((620 - width) / 2, 4))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, 2100 + row * 205))
	return _save_png(canvas, output_path)

static func _fill_background(image: Image, row: int, forest: Image) -> void:
	if row == 0:
		image.fill(Color.WHITE)
	elif row == 1:
		image.fill(Color("#080a0c"))
	elif row == 2:
		for y in range(0, image.get_height(), 24):
			for x in range(0, image.get_width(), 24):
				var c := Color("#3d4247") if ((x / 24 + y / 24) % 2 == 0) else Color("#292e33")
				image.fill_rect(Rect2i(x, y, mini(24, image.get_width() - x), mini(24, image.get_height() - y)), c)
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

func _fail(message: String, code: int = 1) -> void:
	push_error("player_v8_matte: " + message)
	quit(code)
