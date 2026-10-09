extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_INSET := 90
const SOURCE := "res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png"
const V8_IDLE := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const REVIEW := "res://assets/art/review/player_run_stride_pair_safe_comparison.png"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	var safe := _load(SAFE)
	var idle := _load(V8_IDLE)
	var review := _load(REVIEW)
	_check(source != null and source.get_size() == SIZE and source.get_format() == Image.FORMAT_RGBA8, "v2 opposite-stride source is present as 1254x1254 RGBA8")
	_check(idle != null and idle.get_size() == SIZE and idle.get_format() == Image.FORMAT_RGBA8, "v8 idle comparison source is present")
	_check(safe != null and safe.get_size() == SIZE and safe.get_format() == Image.FORMAT_RGBA8, "safe candidate is present as 1254x1254 RGBA8")
	_check(review != null and review.get_size() == Vector2i(3 * 720 + 4 * 24, 760), "three-pose review canvas is present")
	if safe != null:
		var bounds := _alpha_bounds(safe)
		var margins := Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)
		_check(bounds.size.x > 0 and bounds.size.y > 0, "safe artwork retains visible alpha")
		_check(margins.x >= MIN_INSET and margins.y >= MIN_INSET and margins.z >= MIN_INSET and margins.w >= MIN_INSET, "nonzero-alpha margins are at least 90px L/T/R/B: %s" % str(margins))
		_check(_transparent_border(safe), "outermost pixel rows and columns are fully transparent")
		_check(_transparent_rgb_is_zero(safe), "fully transparent pixels have zero RGB values")
		_check(_isolated_count(safe) == 0, "no isolated alpha pixels remain")
		if source != null:
			_check(_uniform_scale(source, safe), "safe candidate is a centered uniform downscale of the v2 silhouette")
			_check(_features_retained(source, safe), "face, ear, both gloves, both boots, and cloth tails remain represented")
			var source_anchors := _bottom_anchors(source, 0.05)
			var safe_anchors := _bottom_anchors(safe, 0.05)
			print("RUN_STRIDE_SMOKE anchors_source=%s anchors_safe=%s anchor_delta=%s" % [str(source_anchors), str(safe_anchors), str(_anchor_delta(source_anchors, safe_anchors))])
	if not source_bytes.is_empty():
		_check(_bytes(SOURCE) == source_bytes, "v2 opposite-stride original source bytes are unchanged")
	if failures.is_empty():
		print("player_run_stride_v2_safe_smoke: mechanical checks passed; human visual approval remains required and main-game registration is prohibited")
		quit(0)
	else:
		for failure in failures:
			push_error("player_run_stride_v2_safe_smoke: " + failure)
		quit(1)

func _features_retained(source: Image, safe: Image) -> bool:
	# ROIs are measured relative to each silhouette's own bounds so the safe
	# fit can shrink and recenter without changing the feature checks.
	var regions := [
		["face and ear", Rect2(0.58, 0.08, 0.36, 0.28)],
		["rear glove", Rect2(0.13, 0.28, 0.27, 0.22)],
		["forward glove", Rect2(0.78, 0.31, 0.21, 0.23)],
		["rear boot", Rect2(0.03, 0.79, 0.30, 0.21)],
		["forward boot", Rect2(0.79, 0.82, 0.21, 0.18)],
		["cloth tails", Rect2(0.08, 0.43, 0.52, 0.40)],
	]
	var all_present := true
	for region in regions:
		var before := _region_alpha_count(source, region[1])
		var after := _region_alpha_count(safe, region[1])
		print("FEATURE %s source_alpha=%d safe_alpha=%d" % [region[0], before, after])
		all_present = all_present and before > 0 and after > 0
	return all_present

func _region_alpha_count(image: Image, relative: Rect2) -> int:
	var bounds := _alpha_bounds(image)
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
	# Use the same visible-alpha cutoff on both images; the resize can discard
	# tiny ringing alpha values on isolated wisps without changing scale.
	var before := _alpha_bounds(source, 0.05)
	var after := _alpha_bounds(safe, 0.05)
	if before.size.x <= 0 or before.size.y <= 0:
		return false
	var sx := float(after.size.x) / before.size.x
	var sy := float(after.size.y) / before.size.y
	print("UNIFORM_FIT source_bounds=%s safe_bounds=%s scale_x=%.6f scale_y=%.6f" % [str(before), str(after), sx, sy])
	return sx < 1.0 and sy < 1.0 and absf(sx - sy) < 0.003 and after.position.x >= MIN_INSET and after.position.y >= MIN_INSET

func _alpha_bounds(image: Image, threshold: float = 0.000001) -> Rect2i:
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

func _has_alpha_neighbor(image: Image, x: int, y: int) -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var nx := x + ox
			var ny := y + oy
			if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
				return true
	return false

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
			if image.get_pixel(x, y).a > 0.0 and not _has_alpha_neighbor(image, x, y):
				count += 1
	return count

func _bottom_anchors(image: Image, threshold: float) -> Array[Vector2i]:
	var bounds := _alpha_bounds(image, threshold)
	var anchors: Array[Vector2i] = []
	if bounds.size.x <= 0:
		return anchors
	var y := bounds.end.y - 1
	var start := -1
	for x in range(SIZE.x + 1):
		var active := x < SIZE.x and image.get_pixel(x, y).a >= threshold
		if active and start < 0:
			start = x
		elif not active and start >= 0:
			anchors.append(Vector2i((start + x - 1) / 2, y))
			start = -1
	return anchors

func _anchor_delta(before: Array[Vector2i], after: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(mini(before.size(), after.size())):
		result.append(after[i] - before[i])
	return result

func _load(path: String) -> Image:
	var data := _bytes(path)
	if data.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
