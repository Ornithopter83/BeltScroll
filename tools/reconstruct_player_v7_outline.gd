extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const EDGE_RADIUS := 8
const WARM_INK := Color("#30241f")
const INK_SOURCE := "res://assets/art/player/elven_fighter_reference_v7_ink_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_reference_v7_outline_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v7_outline_comparison.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --path . --script res://tools/reconstruct_player_v7_outline.gd")
		quit(0)
		return
	if not args.is_empty():
		printerr("예기치 않은 인수입니다.")
		quit(2)
		return
	var input_path := _resolve(INK_SOURCE)
	var input_bytes := FileAccess.get_file_as_bytes(input_path)
	var ink := _load_png(input_path)
	if ink == null or ink.get_size() != SIZE:
		_fail("v7 ink PNG를 읽을 수 없거나 규격이 1254x1254가 아닙니다.")
		return
	var processed := reconstruct(ink)
	var output: Image = processed["image"]
	var forest := _load_png(_resolve(FOREST))
	if output == null or forest == null:
		_fail("재구성 또는 Forest Ruins 입력을 읽지 못했습니다.")
		return
	var err := _save_png(output, _resolve(OUTPUT))
	if err == OK:
		err = build_review(ink, output, forest, _resolve(REVIEW))
	if err != OK:
		_fail("후보 또는 검수 이미지 저장 실패: %s" % error_string(err))
		return
	if FileAccess.get_file_as_bytes(input_path) != input_bytes:
		_fail("v7 ink 입력 바이트가 변경됐습니다.")
		return
	print("player_v7_outline: 후보·전후 검수판 생성; 복원 픽셀 %d, 자동 시각 승인 없음" % int(processed["changed"]))
	quit(0)

# Build a mask from warm edge pixels that disagree with a robust sample of the
# local foreground. Connected components keep a fringe segment coherent; the
# contour test admits both semi-transparent antialiasing and opaque edge pixels.
static func reconstruct(source: Image) -> Dictionary:
	if source == null or source.is_empty() or source.get_size() != SIZE:
		return {"image": null, "changed": 0}
	var w := source.get_width()
	var h := source.get_height()
	var eligible := PackedByteArray()
	eligible.resize(w * h)
	var queued := PackedByteArray()
	queued.resize(w * h)
	var edge_distances := _edge_distances(source, EDGE_RADIUS)
	var components: Array[Array] = []
	var bounds := _alpha_bounds(source)
	for y in range(maxi(1, bounds.position.y - EDGE_RADIUS), mini(h - 1, bounds.end.y + EDGE_RADIUS)):
		for x in range(maxi(1, bounds.position.x - EDGE_RADIUS), mini(w - 1, bounds.end.x + EDGE_RADIUS)):
			var p := source.get_pixel(x, y)
			if p.a < 0.015 or edge_distances[y * w + x] > EDGE_RADIUS:
				continue
			var foreground := _local_foreground(source, x, y)
			if not foreground["valid"] or not _is_warm_residual(source, x, y, p, foreground):
				continue
			eligible[y * w + x] = 1
	for y in range(maxi(1, bounds.position.y - EDGE_RADIUS), mini(h - 1, bounds.end.y + EDGE_RADIUS)):
		for x in range(maxi(1, bounds.position.x - EDGE_RADIUS), mini(w - 1, bounds.end.x + EDGE_RADIUS)):
			var index := y * w + x
			if eligible[index] == 0 or queued[index] != 0:
				continue
			var component: Array[Vector2i] = []
			var frontier: Array[Vector2i] = [Vector2i(x, y)]
			queued[index] = 1
			while not frontier.is_empty():
				var point: Vector2i = frontier.pop_back()
				component.append(point)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if ox == 0 and oy == 0:
							continue
						var nx := point.x + ox
						var ny := point.y + oy
						var ni := ny * w + nx
						if nx > 0 and nx < w - 1 and ny > 0 and ny < h - 1 and eligible[ni] != 0 and queued[ni] == 0:
							queued[ni] = 1
							frontier.append(Vector2i(nx, ny))
			components.append(component)
	var result := source.duplicate()
	var changed := 0
	for component in components:
		# Only connected regions tied to the alpha contour are reconstructed.
		var touches_contour := false
		for point in component:
			if edge_distances[point.y * w + point.x] <= 2:
				touches_contour = true
				break
		if not touches_contour:
			continue
		for point in component:
			var old := source.get_pixelv(point)
			var local_ink := _local_outline_color(source, point.x, point.y)
			var color: Color = local_ink["color"] if local_ink["valid"] else WARM_INK
			result.set_pixel(point.x, point.y, Color(color.r, color.g, color.b, old.a))
			changed += 1
	return {"image": result, "changed": changed}

static func _is_warm_residual(image: Image, x: int, y: int, pixel: Color, foreground: Dictionary) -> bool:
	# Warm red, orange, and yellow contamination is compared against the local
	# foreground, not a global RGB key. Similar skin and gold remain protected.
	var expected: Color = foreground["color"]
	if _has_inward_support(image, x, y, pixel, foreground["inward"]):
		return false
	var hue := pixel.h
	var warm := hue < 0.19 or hue > 0.96
	if not warm or pixel.s < 0.28 or pixel.v < 0.20:
		return false
	var hue_delta := absf(hue - expected.h)
	hue_delta = minf(hue_delta, 1.0 - hue_delta)
	var color_delta := Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(expected.r, expected.g, expected.b))
	return color_delta > 0.17 and (hue_delta > 0.045 or pixel.s - expected.s > 0.18)

static func _has_inward_support(image: Image, x: int, y: int, pixel: Color, inward: Vector2) -> bool:
	# A warm color continuing just inside the edge is a real foreground detail
	# such as gold trim or skin shading, not a background-colored fringe.
	var support := 0
	for step in range(3, 8):
		var sx := clampi(x + roundi(inward.x * step), 0, image.get_width() - 1)
		var sy := clampi(y + roundi(inward.y * step), 0, image.get_height() - 1)
		var sample := image.get_pixel(sx, sy)
		if sample.a >= 0.35 and Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(sample.r, sample.g, sample.b)) <= 0.20:
			support += 1
	return support >= 3

static func pollution_count(image: Image) -> int:
	if image == null or image.is_empty():
		return 0
	var bounds := _alpha_bounds(image)
	var edge_distances := _edge_distances(image, EDGE_RADIUS)
	var count := 0
	for y in range(maxi(1, bounds.position.y), mini(image.get_height() - 1, bounds.end.y)):
		for x in range(maxi(1, bounds.position.x), mini(image.get_width() - 1, bounds.end.x)):
			var p := image.get_pixel(x, y)
			if p.a >= 0.015 and edge_distances[y * image.get_width() + x] <= EDGE_RADIUS:
				var foreground := _local_foreground(image, x, y)
				if foreground["valid"] and _is_warm_residual(image, x, y, p, foreground):
					count += 1
	return count

static func _local_foreground(image: Image, x: int, y: int) -> Dictionary:
	# Find the nearest transparent boundary sample, then sample robustly inward.
	var nearest := Vector2i.ZERO
	var best := INF
	for ny in range(maxi(0, y - EDGE_RADIUS), mini(image.get_height(), y + EDGE_RADIUS + 1)):
		for nx in range(maxi(0, x - EDGE_RADIUS), mini(image.get_width(), x + EDGE_RADIUS + 1)):
			if image.get_pixel(nx, ny).a > 0.015:
				continue
			var d := Vector2(float(nx - x), float(ny - y)).length()
			if d < best:
				best = d
				nearest = Vector2i(nx, ny)
	if best == INF:
		return {"valid": false, "color": Color.TRANSPARENT, "inward": Vector2.ZERO}
	var inward := Vector2(float(x - nearest.x), float(y - nearest.y)).normalized()
	var samples: Array[Color] = []
	for step in range(3, 10):
		var sx := clampi(x + roundi(inward.x * step), 0, image.get_width() - 1)
		var sy := clampi(y + roundi(inward.y * step), 0, image.get_height() - 1)
		var sample := image.get_pixel(sx, sy)
		if sample.a >= 0.82:
			samples.append(sample)
	if samples.size() < 2:
		return {"valid": false, "color": Color.TRANSPARENT, "inward": inward}
	return {"valid": true, "color": _median_color(samples), "inward": inward}

static func _local_outline_color(image: Image, x: int, y: int) -> Dictionary:
	# Prefer adjacent established neutral dark-brown contour pixels and median
	# their tones so the reconstructed run joins its local outline smoothly.
	var samples: Array[Color] = []
	for radius in range(1, 7):
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				if maxi(absi(ox), absi(oy)) != radius:
					continue
				var sx := x + ox
				var sy := y + oy
				if sx < 0 or sy < 0 or sx >= image.get_width() or sy >= image.get_height():
					continue
				var p := image.get_pixel(sx, sy)
				if p.a < 0.75 or p.v > 0.43 or p.s > 0.42:
					continue
				# Reject near-black teal pixels; target the warm-neutral brown ink.
				if p.r < p.b * 0.72 or p.r > p.b * 1.9:
					continue
				samples.append(p)
		if samples.size() >= 3:
			break
	if samples.is_empty():
		return {"valid": false, "color": WARM_INK}
	var median := _median_color(samples)
	return {"valid": true, "color": median.lerp(WARM_INK, 0.28)}

static func _median_color(samples: Array[Color]) -> Color:
	var rs: Array[float] = []; var gs: Array[float] = []; var bs: Array[float] = []
	for color in samples:
		rs.append(color.r); gs.append(color.g); bs.append(color.b)
	rs.sort(); gs.sort(); bs.sort()
	var middle := samples.size() / 2
	return Color(rs[middle], gs[middle], bs[middle], 1.0)

static func build_review(before: Image, after: Image, forest: Image, path: String) -> Error:
	if before == null or after == null or forest == null or before.get_size() != SIZE or after.get_size() != SIZE:
		return ERR_INVALID_DATA
	var canvas := Image.create(1280, 3400, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var variants: Array[Image] = [before, after]
	for row in range(4):
		for col in range(2):
			var tile := Image.create(620, 620, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var variant := variants[col]
			var bounds := _alpha_bounds(variant)
			var full := _fit(variant.get_region(bounds), Vector2i(260, 420))
			tile.blend_rect(full, Rect2i(Vector2i.ZERO, full.get_size()), Vector2i((620 - full.get_width()) / 2, 5))
			var face := _crop_relative(variant, bounds, Rect2(0.42, 0.02, 0.42, 0.31))
			var pony := _crop_relative(variant, bounds, Rect2(0.00, 0.00, 0.52, 0.43))
			var face_fit := _fit(face, Vector2i(285, 180))
			var pony_fit := _fit(pony, Vector2i(285, 180))
			tile.blend_rect(face_fit, Rect2i(Vector2i.ZERO, face_fit.get_size()), Vector2i(10, 430))
			tile.blend_rect(pony_fit, Rect2i(Vector2i.ZERO, pony_fit.get_size()), Vector2i(325, 430))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, row * 640 + 5))
			canvas.fill_rect(Rect2i(col * 640 + 10, row * 640 + 5, 620, 5), Color("#db7064") if col == 0 else Color("#77c197"))
	# Exact 192px-high output comparisons on all four requested backgrounds.
	for row in range(4):
		for col in range(2):
			var tile := Image.create(620, 200, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var bounds := _alpha_bounds(variants[col])
			var figure := variants[col].get_region(bounds)
			var width := maxi(1, roundi(float(figure.get_width()) * 192.0 / figure.get_height()))
			figure.resize(width, 192, Image.INTERPOLATE_LANCZOS)
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((620 - width) / 2, 4))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, 2580 + row * 205))
	return _save_png(canvas, path)

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

static func _alpha_distance(image: Image, x: int, y: int, limit: int) -> int:
	for radius in range(1, limit + 1):
		for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
			for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
				if absi(nx - x) != radius and absi(ny - y) != radius:
					continue
				if image.get_pixel(nx, ny).a <= 0.015:
					return radius
	return limit + 1

static func _edge_distances(image: Image, limit: int) -> PackedByteArray:
	# Multi-source flood fill starts on every opaque pixel touching transparency;
	# this handles holes and the outer silhouette while covering alpha fringes.
	var w := image.get_width()
	var h := image.get_height()
	var distances := PackedByteArray()
	distances.resize(w * h)
	for index in range(distances.size()):
		distances[index] = 255
	var frontier: Array[Vector2i] = []
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			if image.get_pixel(x, y).a <= 0.015:
				continue
			var boundary := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if image.get_pixel(x + ox, y + oy).a <= 0.015:
						boundary = true
			if boundary:
				distances[y * w + x] = 1
				frontier.append(Vector2i(x, y))
	var head := 0
	while head < frontier.size():
		var p: Vector2i = frontier[head]
		head += 1
		var next_distance := int(distances[p.y * w + p.x]) + 1
		if next_distance > limit:
			continue
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				if ox == 0 and oy == 0:
					continue
				var nx := p.x + ox
				var ny := p.y + oy
				var ni := ny * w + nx
				if nx > 0 and ny > 0 and nx < w - 1 and ny < h - 1 and image.get_pixel(nx, ny).a > 0.015 and distances[ni] > next_distance:
					distances[ni] = next_distance
					frontier.append(Vector2i(nx, ny))
	return distances

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

func _fail(message: String) -> void:
	push_error("player_v7_outline: " + message)
	quit(1)
