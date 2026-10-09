extends SceneTree

const SIZE := Vector2i(1254, 1254)
const SOURCE := "res://assets/art/player/elven_fighter_attack3_startup_v1_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack3_startup_safe_comparison.png"
const EXPECTED_REVIEW := Vector2i(3 * 720 + 4 * 24, 760)
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
		"original startup remains a decodable 1254x1254 RGBA8 PNG")
	_check(safe != null and safe.get_size() == SIZE and safe.get_format() == Image.FORMAT_RGBA8,
		"safe candidate is 1254x1254 RGBA8")
	_check(review != null and review.get_size() == EXPECTED_REVIEW,
		"three-pose comparison is present at 3x review size")
	if safe != null:
		var bounds := _bounds(safe, 0.000001)
		var margins := Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)
		_check(bounds.size.x > 0 and bounds.size.y > 0, "candidate retains a nonempty alpha silhouette")
		_check(margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN,
			"nonzero-alpha inset is at least 90px L/T/R/B: %s" % str(margins))
		_check(_transparent_edges(safe), "all four outer edges are fully transparent")
		_check(_transparent_rgb_is_zero(safe), "fully transparent pixels contain zero RGB")
		_check(_isolated_alpha_count(safe) == 0, "isolated nonzero-alpha pixels are absent")
		_check(_uniform_fit_preserved(source, safe), "source art fits with one uniform downscale and no crop")
		for item in _feature_regions():
			var source_count := _region_alpha_count(source, item[1], 0.05)
			var candidate_count := _region_alpha_count(safe, item[1], 0.05)
			_check(source_count > 0 and candidate_count > 0, "%s alpha region survives resampling (source=%d, candidate=%d)" % [item[0], source_count, candidate_count])
		print("FOOT ANCHORS alpha>=5%% source=%s safe=%s delta=%s" % [str(_bottom_anchors(source)), str(_bottom_anchors(safe)), str(_anchor_deltas(_bottom_anchors(source), _bottom_anchors(safe)))])
	_check(not source_bytes.is_empty() and _bytes(SOURCE) == source_bytes, "source bytes are unchanged by the preparation output")
	if failures.is_empty():
		print("player_attack3_startup_safe_smoke: mechanical checks passed; human visual approval remains pending")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack3_startup_safe_smoke: " + failure)
		quit(1)

func _feature_regions() -> Array:
	return [
		["face", Rect2(0.48, 0.015, 0.36, 0.31)],
		["guard fist and forearm", Rect2(0.34, 0.18, 0.34, 0.32)],
		["forward fist and forearm", Rect2(0.69, 0.20, 0.30, 0.37)],
		["left leg and boot", Rect2(0.12, 0.57, 0.48, 0.43)],
		["right leg and boot", Rect2(0.45, 0.51, 0.53, 0.48)],
	]

func _region_alpha_count(image: Image, rect: Rect2, threshold: float) -> int:
	var bounds := _bounds(image, threshold)
	var x0 := bounds.position.x + floori(rect.position.x * bounds.size.x)
	var y0 := bounds.position.y + floori(rect.position.y * bounds.size.y)
	var x1 := mini(bounds.end.x, bounds.position.x + ceili(rect.end.x * bounds.size.x))
	var y1 := mini(bounds.end.y, bounds.position.y + ceili(rect.end.y * bounds.size.y))
	var count := 0
	for y in range(maxi(0, y0), y1):
		for x in range(maxi(0, x0), x1):
			if image.get_pixel(x, y).a >= threshold:
				count += 1
	return count

func _uniform_fit_preserved(source: Image, candidate: Image) -> bool:
	if source == null or candidate == null:
		return false
	var original := _bounds_without_isolated(source)
	var result := _bounds(candidate, 0.000001)
	if original.size.x <= 0 or original.size.y <= 0:
		return false
	var scale_x := float(result.size.x) / original.size.x
	var scale_y := float(result.size.y) / original.size.y
	print("UNIFORM FIT source_bounds_without_isolated=%s result_bounds=%s scale_x=%.6f scale_y=%.6f" % [str(original), str(result), scale_x, scale_y])
	return scale_x < 1.0 and scale_y < 1.0 and absf(scale_x - scale_y) < 0.003 and result.position.x >= MIN_MARGIN and result.position.y >= MIN_MARGIN

func _bounds_without_isolated(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0 or not _has_alpha_neighbor(image, x, y):
				continue
			left = mini(left, x)
			top = mini(top, y)
			right = maxi(right, x)
			bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _load(path: String) -> Image:
	var bytes := _bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes) == OK and not image.is_empty() else null

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _bounds(image: Image, threshold: float) -> Rect2i:
	if image == null:
		return Rect2i()
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= threshold:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _transparent_edges(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a > 0.0 or image.get_pixel(x, image.get_height() - 1).a > 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a > 0.0 or image.get_pixel(image.get_width() - 1, y).a > 0.0:
			return false
	return true

func _transparent_rgb_is_zero(image: Image) -> bool:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0 and (pixel.r != 0.0 or pixel.g != 0.0 or pixel.b != 0.0):
				return false
	return true

func _isolated_alpha_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0 or _has_alpha_neighbor(image, x, y):
				continue
			count += 1
	return count

func _has_alpha_neighbor(image: Image, x: int, y: int) -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var nx := x + ox
			var ny := y + oy
			if nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
				return true
	return false

func _bottom_anchors(image: Image) -> Array[Vector2i]:
	var bounds := _bounds(image, 0.05)
	var anchors: Array[Vector2i] = []
	if bounds.size.x <= 0:
		return anchors
	var y := bounds.end.y - 1
	var start := -1
	for x in range(image.get_width() + 1):
		var active := x < image.get_width() and image.get_pixel(x, y).a >= 0.05
		if active and start < 0:
			start = x
		elif not active and start >= 0:
			anchors.append(Vector2i((start + x - 1) / 2, y))
			start = -1
	return anchors

func _anchor_deltas(source: Array[Vector2i], candidate: Array[Vector2i]) -> Array[Vector2i]:
	var values: Array[Vector2i] = []
	for index in range(mini(source.size(), candidate.size())):
		values.append(candidate[index] - source[index])
	return values

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
