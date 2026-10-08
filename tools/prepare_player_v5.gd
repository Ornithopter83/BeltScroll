extends SceneTree

const TARGET := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const CONTENT_LIMIT := 1074
const SOURCE := "res://assets/art/player/elven_fighter_reference_v5_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_reference_v5_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_reference_v5_clean_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v5_clean_comparison.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const PANEL := Vector2i(620, 340)
const EDGE_RADIUS := 7

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --script res://tools/prepare_player_v5.gd")
		quit(0)
		return
	if not args.is_empty():
		printerr("인수 없이 실행하세요.")
		quit(2)
		return
	var src := _resolve(SOURCE)
	var safe := _resolve(SAFE)
	var clean := _resolve(CLEAN)
	var review := _resolve(REVIEW)
	var source_bytes := FileAccess.get_file_as_bytes(src)
	var source := _load_png(src)
	if source == null:
		_fail("v5 원본 PNG를 읽을 수 없습니다.")
		return
	var normalized := normalize_image(source)
	if normalized == null:
		_fail("v5 원본 정규화에 실패했습니다.")
		return
	var safe_error := _save_png(normalized, safe)
	if safe_error != OK:
		_fail("safe 후보 저장 실패: %s" % error_string(safe_error))
		return
	var cleaned := clean_image(normalized)
	var clean_error := _save_png(cleaned["image"], clean)
	if clean_error != OK:
		_fail("clean 후보 저장 실패: %s" % error_string(clean_error))
		return
	var review_error := build_comparison(source, normalized, cleaned["image"], _load_png(_resolve(FOREST)), review)
	if review_error != OK:
		_fail("비교 이미지 생성 실패: %s" % error_string(review_error))
		return
	if FileAccess.get_file_as_bytes(src) != source_bytes:
		_fail("원본 바이트가 변경됐습니다.")
		return
	print("player_v5_prepare: safe/clean 후보 및 4배경 비교 이미지 생성 완료; 변경 픽셀 %d" % int(cleaned["changed"]))
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

# The clean pass only inspects a narrow alpha-boundary band. A component is
# recolored only when its pixels are vivid red outliers against the inward color
# and form a connected fringe. Warm/gold/skin/hair edges with matching local hue
# remain untouched. Alpha and all pixel positions stay fixed.
static func clean_image(source: Image) -> Dictionary:
	var output := source.duplicate()
	var candidates := {}
	var bounds := _alpha_bounds(source)
	for y in range(maxi(1, bounds.position.y - EDGE_RADIUS), mini(source.get_height() - 1, bounds.end.y + EDGE_RADIUS)):
		for x in range(maxi(1, bounds.position.x - EDGE_RADIUS), mini(source.get_width() - 1, bounds.end.x + EDGE_RADIUS)):
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.01 or _alpha_distance(source, x, y, EDGE_RADIUS) > EDGE_RADIUS:
				continue
			var reference := _inward_color(source, x, y, EDGE_RADIUS)
			if not bool(reference["valid"]):
				continue
			var local: Color = reference["color"]
			if _is_red_outlier(pixel, local):
				candidates[Vector2i(x, y)] = true
	var visited := {}
	var changed := 0
	for key in candidates:
		if visited.has(key):
			continue
		var component: Array[Vector2i] = []
		var queue: Array[Vector2i] = [key]
		visited[key] = true
		while not queue.is_empty():
			var point: Vector2i = queue.pop_back()
			component.append(point)
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var neighbor := point + Vector2i(dx, dy)
					if candidates.has(neighbor) and not visited.has(neighbor):
						visited[neighbor] = true
						queue.append(neighbor)
		# A strong isolated red pixel is still a fringe artifact. Larger connected
		# patches use the same inward support test; diffuse warm detail never enters.
		if component.size() < 2:
			var only: Vector2i = component[0]
			var sample := source.get_pixelv(only)
			var inward := _inward_color(source, only.x, only.y, EDGE_RADIUS)
			if not bool(inward["valid"]) or _rgb_distance(sample, inward["color"]) < 0.34:
				continue
		for point in component:
			var pixel := source.get_pixelv(point)
			var inward := _inward_color(source, point.x, point.y, EDGE_RADIUS)
			if not bool(inward["valid"]):
				continue
			var local: Color = inward["color"]
			# The classification already requires a strong red outlier against inward
			# support, so fully replace RGB to avoid leaving a residual red rim.
			output.set_pixelv(point, Color(local.r, local.g, local.b, pixel.a))
			changed += 1
	return {"image": output, "changed": changed}

static func _is_red_outlier(pixel: Color, local: Color) -> bool:
	if pixel.s < 0.62 or pixel.v < 0.34 or _rgb_distance(pixel, local) < 0.22:
		return false
	var hue := pixel.h
	if not (hue < 0.045 or hue > 0.955):
		return false
	# Keep naturally red/brown detail where the inward edge supports its hue.
	var hue_delta := absf(hue - local.h)
	hue_delta = minf(hue_delta, 1.0 - hue_delta)
	if local.s > 0.18 and hue_delta < 0.075 and _rgb_distance(pixel, local) < 0.48:
		return false
	return pixel.r > local.r + 0.10 or pixel.g < local.g - 0.10

static func pollution_count(image: Image) -> int:
	var count := 0
	var bounds := _alpha_bounds(image)
	for y in range(maxi(1, bounds.position.y), mini(image.get_height() - 1, bounds.end.y)):
		for x in range(maxi(1, bounds.position.x), mini(image.get_width() - 1, bounds.end.x)):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.01 or _alpha_distance(image, x, y, EDGE_RADIUS) > EDGE_RADIUS:
				continue
			var inward := _inward_color(image, x, y, EDGE_RADIUS)
			if bool(inward["valid"]) and _is_red_outlier(pixel, inward["color"]):
				count += 1
	return count

static func build_comparison(original: Image, safe: Image, clean: Image, forest: Image, output_path: String) -> Error:
	if original == null or safe == null or clean == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if safe.get_size() != TARGET or clean.get_size() != TARGET:
		return ERR_INVALID_DATA
	var canvas := Image.create(1920, 2840, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var variants: Array[Image] = [original, safe, clean]
	var backgrounds: Array[Color] = [Color.WHITE, Color("#080a0c"), Color("#363b40"), Color("#171b20")]
	for row in range(4):
		for col in range(3):
			var x := 10 + col * 635
			var y := 10 + row * 490
			var tile := Image.create(PANEL.x, 480, false, Image.FORMAT_RGBA8)
			if row == 3:
				var bg := forest.duplicate()
				bg.resize(tile.get_width(), tile.get_height(), Image.INTERPOLATE_LANCZOS)
				tile.blit_rect(bg, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i.ZERO)
			elif row == 2:
				_draw_checker(tile)
			else:
				tile.fill(backgrounds[row])
			var crop := _alpha_bounds(variants[col])
			var art: Image = variants[col].get_region(crop)
			art = _fit(art, Vector2i(580, 280))
			tile.blend_rect(art, Rect2i(Vector2i.ZERO, art.get_size()), Vector2i((PANEL.x - art.get_width()) / 2, 8 + (280 - art.get_height()) / 2))
			var head_rect := Rect2i(crop.position.x + int(crop.size.x * 0.08), crop.position.y + int(crop.size.y * 0.01), int(crop.size.x * 0.72), int(crop.size.y * 0.39))
			var head := _fit(variants[col].get_region(head_rect.intersection(Rect2i(Vector2i.ZERO, TARGET))), Vector2i(580, 172))
			tile.blend_rect(head, Rect2i(Vector2i.ZERO, head.get_size()), Vector2i((PANEL.x - head.get_width()) / 2, 298 + (172 - head.get_height()) / 2))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(x, y))
			var header := Color("#db7064") if col == 0 else (Color("#68aeca") if col == 1 else Color("#77c197"))
			canvas.fill_rect(Rect2i(x, y, PANEL.x, 6), header)
			var label: String = ["ORIGINAL", "SAFE", "CLEAN"][col]
			canvas.fill_rect(Rect2i(x + 14, y + 14, label.length() * 12 + 10, 24), Color("#171b20"))
			_draw_label(canvas, label, Vector2i(x + 20, y + 18), header)
	# Bottom rows compare all three at exact 192px silhouette height on every backdrop.
	var bottom_y := 1970
	for bg_index in range(4):
		for col in range(3):
			var x := 10 + col * 635
			var y := bottom_y + bg_index * 215
			var tile := Image.create(PANEL.x, 205, false, Image.FORMAT_RGBA8)
			if bg_index == 0:
				tile.fill(Color.WHITE)
			elif bg_index == 1:
				tile.fill(Color("#080a0c"))
			elif bg_index == 2:
				_draw_checker(tile)
			else:
				var bg := forest.duplicate()
				bg.resize(tile.get_width(), tile.get_height(), Image.INTERPOLATE_LANCZOS)
				tile.blit_rect(bg, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i.ZERO)
			var bounds := _alpha_bounds(variants[col])
			var figure := variants[col].get_region(bounds)
			var width := maxi(1, roundi(float(figure.get_width()) * 192.0 / figure.get_height()))
			figure.resize(width, 192, Image.INTERPOLATE_LANCZOS)
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((tile.get_width() - width) / 2, 6))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(x, y))
			canvas.fill_rect(Rect2i(x, y, PANEL.x, 6), Color("#8f7fcb") if bg_index == 0 else Color("#d4ae64"))
			var label: String = ["ORIGINAL", "SAFE", "CLEAN"][col]
			canvas.fill_rect(Rect2i(x + 14, y + 14, label.length() * 12 + 10, 24), Color("#171b20"))
			_draw_label(canvas, label, Vector2i(x + 20, y + 18), Color("#e8e6f2"))
	return _save_png(canvas, output_path)

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

static func _draw_label(image: Image, text: String, position: Vector2i, color: Color) -> void:
	var glyphs := {
		"A": [14, 17, 17, 31, 17, 17, 17], "C": [14, 17, 16, 16, 16, 17, 14],
		"E": [31, 16, 16, 30, 16, 16, 31], "F": [31, 16, 16, 30, 16, 16, 16],
		"G": [14, 17, 16, 23, 17, 17, 15], "I": [31, 4, 4, 4, 4, 4, 31],
		"L": [16, 16, 16, 16, 16, 16, 31], "N": [17, 25, 25, 21, 19, 19, 17],
		"O": [14, 17, 17, 17, 17, 17, 14], "R": [30, 17, 17, 30, 20, 18, 17],
		"S": [15, 16, 16, 14, 1, 1, 30]
	}
	var cursor := position.x
	for character in text:
		var rows: Array = glyphs.get(character, [])
		for row in range(rows.size()):
			for col in range(5):
				if (int(rows[row]) & (1 << (4 - col))) != 0:
					image.fill_rect(Rect2i(cursor + col * 2, position.y + row * 2, 2, 2), color)
		cursor += 12

static func _alpha_distance(image: Image, x: int, y: int, limit: int) -> int:
	for radius in range(1, limit + 1):
		for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
			for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
				if absi(nx - x) != radius and absi(ny - y) != radius:
					continue
				if image.get_pixel(nx, ny).a <= 0.01:
					return radius
	return limit + 1

static func _inward_color(image: Image, x: int, y: int, radius: int) -> Dictionary:
	var nearest := Vector2i.ZERO
	var best := INF
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if image.get_pixel(nx, ny).a > 0.01:
				continue
			var distance := Vector2(float(nx - x), float(ny - y)).length()
			if distance < best:
				best = distance
				nearest = Vector2i(nx, ny)
	if best == INF:
		return {"valid": false, "color": Color.TRANSPARENT}
	var direction := Vector2(float(x - nearest.x), float(y - nearest.y)).normalized()
	for step in range(1, radius + 1):
		var point := Vector2i(clampi(x + roundi(direction.x * step), 0, image.get_width() - 1), clampi(y + roundi(direction.y * step), 0, image.get_height() - 1))
		var sample := image.get_pixelv(point)
		if sample.a >= 0.82 and not _is_red(sample):
			return {"valid": true, "color": sample}
	return {"valid": false, "color": Color.TRANSPARENT}

static func _is_red(color: Color) -> bool:
	return color.s >= 0.62 and color.v >= 0.34 and (color.h < 0.045 or color.h > 0.955)

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
	push_error("player_v5_prepare: " + message)
	quit(1)
