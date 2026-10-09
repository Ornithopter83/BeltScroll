extends SceneTree

const SIZE := Vector2i(1254, 1254)
const SOURCE := "res://assets/art/player/elven_fighter_attack1_startup_v1_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack1_startup_v1_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack1_startup_safe_comparison.png"
const REVIEW_SIZE := Vector2i(2256, 760)
const MIN_MARGIN := 90

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	var safe := _load(SAFE)
	var review := _load(REVIEW)
	_check(source != null and source.get_size() == SIZE and source.get_format() == Image.FORMAT_RGBA8,
		"original candidate decodes as 1254x1254 RGBA8")
	_check(safe != null and safe.get_size() == SIZE and safe.get_format() == Image.FORMAT_RGBA8,
		"safe output decodes as 1254x1254 RGBA8")
	_check(review != null and review.get_size() == REVIEW_SIZE,
		"three-pose, 3x comparison image is present")
	if safe != null:
		var bounds := _bounds(safe)
		var margins := Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)
		_check(bounds.size.x > 0 and bounds.size.y > 0, "safe candidate retains visible alpha")
		_check(margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN,
			"nonzero-alpha inset is at least 90px L/T/R/B: %s" % str(margins))
		_check(_transparent_border(safe), "all four outer edges are fully transparent")
		_check(_transparent_rgb_is_zero(safe), "fully transparent pixels have zero RGB")
		_check(_isolated_count(safe) == 0, "isolated alpha pixels are absent")
		_check(_uniform_scale(source, safe), "source silhouette was uniformly downscaled and centered without cropping")
		_check(_red_edge_count(safe) < _red_edge_count(source), "saturated red color spill at transparent edges is reduced")
		for region in _feature_regions():
			_check(_region_alpha_count(safe, region[1]) > 0, "%s remains represented by alpha" % region[0])
		print("FOOT_ANCHORS source=%s safe=%s delta=%s" % [str(_bottom_anchors(source)), str(_bottom_anchors(safe)), str(_anchor_delta(_bottom_anchors(source), _bottom_anchors(safe)))])
	_check(not source_bytes.is_empty() and _bytes(SOURCE) == source_bytes, "source PNG bytes remain unchanged")
	if failures.is_empty():
		print("player_attack1_startup_safe_smoke: mechanical checks passed; human visual approval is pending")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack1_startup_safe_smoke: " + failure)
		quit(1)

func _feature_regions() -> Array:
	return [
		["face and ear", Rect2(0.52, 0.08, 0.27, 0.24)],
		["left glove", Rect2(0.08, 0.20, 0.27, 0.20)],
		["right glove", Rect2(0.59, 0.22, 0.27, 0.20)],
		["left boot", Rect2(0.00, 0.82, 0.35, 0.18)],
		["right boot", Rect2(0.67, 0.82, 0.33, 0.18)],
	]

func _region_alpha_count(image: Image, relative: Rect2) -> int:
	var bounds := _bounds(image)
	var x0 := bounds.position.x + floori(relative.position.x * bounds.size.x)
	var y0 := bounds.position.y + floori(relative.position.y * bounds.size.y)
	var x1 := mini(bounds.end.x, bounds.position.x + ceili(relative.end.x * bounds.size.x))
	var y1 := mini(bounds.end.y, bounds.position.y + ceili(relative.end.y * bounds.size.y))
	var count := 0
	for y in range(maxi(0, y0), y1):
		for x in range(maxi(0, x0), x1):
			if image.get_pixel(x, y).a >= 0.05:
				count += 1
	return count

func _uniform_scale(source: Image, safe: Image) -> bool:
	var before := _bounds_without_isolated(source)
	var after := _bounds(safe)
	if before.size.x <= 0 or before.size.y <= 0:
		return false
	var sx := float(after.size.x) / before.size.x
	var sy := float(after.size.y) / before.size.y
	print("UNIFORM_FIT source_bounds=%s output_bounds=%s scale_x=%.6f scale_y=%.6f" % [str(before), str(after), sx, sy])
	return sx <= 1.0 and sy <= 1.0 and absf(sx - sy) < 0.003 and after.position.x >= MIN_MARGIN and after.position.y >= MIN_MARGIN

func _bounds_without_isolated(image: Image) -> Rect2i:
	var left := SIZE.x; var top := SIZE.y; var right := -1; var bottom := -1
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox; var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < SIZE.x and ny < SIZE.y and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if neighbor:
				left = mini(left, x); top = mini(top, y); right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _bounds(image: Image, threshold: float = 0.000001) -> Rect2i:
	var left := image.get_width(); var top := image.get_height(); var right := -1; var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= threshold:
				left = mini(left, x); top = mini(top, y); right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _transparent_border(image: Image) -> bool:
	for x in range(SIZE.x):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, SIZE.y - 1).a != 0.0:
			return false
	for y in range(SIZE.y):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(SIZE.x - 1, y).a != 0.0:
			return false
	return true

func _transparent_rgb_is_zero(image: Image) -> bool:
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var p := image.get_pixel(x, y)
			if p.a <= 0.0 and (p.r != 0.0 or p.g != 0.0 or p.b != 0.0):
				return false
	return true

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var found := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox; var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < SIZE.x and ny < SIZE.y and image.get_pixel(nx, ny).a > 0.0:
						found = true
			if not found:
				count += 1
	return count

func _red_edge_count(image: Image) -> int:
	var count := 0
	for y in range(1, SIZE.y - 1):
		for x in range(1, SIZE.x - 1):
			var p := image.get_pixel(x, y)
			if p.a <= 0.0 or p.s < 0.64 or p.r - maxf(p.g, p.b) < 0.28:
				continue
			var near_clear := false
			for oy in range(-3, 4):
				for ox in range(-3, 4):
					if image.get_pixel(x + ox, y + oy).a <= 0.02:
						near_clear = true
			if near_clear:
				count += 1
	return count

func _bottom_anchors(image: Image) -> Array[Vector2i]:
	var bounds := _bounds(image, 0.05)
	var anchors: Array[Vector2i] = []
	if bounds.size.x <= 0:
		return anchors
	var y := bounds.end.y - 1
	var start := -1
	for x in range(SIZE.x + 1):
		var active := x < SIZE.x and image.get_pixel(x, y).a >= 0.05
		if active and start < 0:
			start = x
		elif not active and start >= 0:
			anchors.append(Vector2i((start + x - 1) / 2, y)); start = -1
	return anchors

func _anchor_delta(before: Array[Vector2i], after: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(mini(before.size(), after.size())):
		result.append(after[i] - before[i])
	return result

func _load(path: String) -> Image:
	var bytes := _bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes) == OK and not image.is_empty() else null

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
