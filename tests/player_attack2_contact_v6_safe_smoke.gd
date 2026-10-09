extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const CANDIDATE := "res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png"
const SOURCE := "res://assets/art/player/elven_fighter_attack2_contact_v6_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack2_contact_v6_safe_comparison.png"
const EXPECTED_REVIEW_SIZE := Vector2i(3000, 760)
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	var candidate := _load(CANDIDATE)
	var review := _load(REVIEW)
	_check(source != null and source.get_size() == SIZE, "untouched v6 source remains available")
	_check(candidate != null and candidate.get_size() == SIZE and candidate.get_format() == Image.FORMAT_RGBA8,
		"safe candidate decodes as 1254x1254 RGBA8")
	_check(review != null and review.get_size() == EXPECTED_REVIEW_SIZE,
		"separate four-panel 3x comparison image is present")
	if candidate == null:
		_finish()
		return
	var bounds := _bounds(candidate, 0.000001)
	var margins := Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)
	_check(bounds.size.x > 0 and bounds.size.y > 0, "candidate retains visible full-body alpha")
	_check(margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN,
		"nonzero alpha inset is at least 90px on every side: L/T/R/B=%d/%d/%d/%d" % [margins.x, margins.y, margins.z, margins.w])
	_check(_transparent_edges(candidate), "all outer canvas edges are fully transparent")
	print("ALPHA DIAGNOSTICS transparent_rgb_nonzero=%d isolated_nonzero_alpha=%d" % [_transparent_rgb_nonzero_count(candidate), _isolated_alpha_count(candidate)])
	_check(_transparent_rgb_is_zero(candidate), "transparent pixels have zero RGB after premultiplied-alpha filtering")
	var isolated := _isolated_alpha_count(candidate)
	_check(isolated == 0, "no alpha pixel is disconnected from its 8-neighbor contour (count=%d)" % isolated)
	var source_anchor := _bottom_anchors(source, 0.05)
	var candidate_anchor := _bottom_anchors(candidate, 0.05)
	print("FOOT ANCHORS (alpha>=5%%, source asset pixels -> safe asset pixels; game-space delta=asset delta/6.53125): source=%s; safe=%s; deltas=%s" % [
		str(source_anchor), str(candidate_anchor), str(_anchor_deltas(source_anchor, candidate_anchor))])
	_check(not source_bytes.is_empty() and _bytes(SOURCE) == source_bytes, "original source PNG bytes remain unchanged")
	_finish()

func _load(path: String) -> Image:
	var data := _bytes(path)
	if data.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK or image.is_empty():
		return null
	return image

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _bounds(image: Image, threshold: float) -> Rect2i:
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
			var p := image.get_pixel(x, y)
			if p.a <= 0.0 and (p.r != 0.0 or p.g != 0.0 or p.b != 0.0):
				return false
	return true

func _transparent_rgb_nonzero_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p := image.get_pixel(x, y)
			if p.a <= 0.0 and (p.r != 0.0 or p.g != 0.0 or p.b != 0.0):
				count += 1
	return count

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

func _bottom_anchors(image: Image, threshold: float) -> Array[Vector2i]:
	var bounds := _bounds(image, threshold)
	var anchors: Array[Vector2i] = []
	if bounds.size.x <= 0:
		return anchors
	var y := bounds.end.y - 1
	var start := -1
	for x in range(image.get_width() + 1):
		var active := x < image.get_width() and image.get_pixel(x, y).a >= threshold
		if active and start < 0:
			start = x
		elif not active and start >= 0:
			anchors.append(Vector2i((start + x - 1) / 2, y))
			start = -1
	return anchors

func _anchor_deltas(source: Array[Vector2i], candidate: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(mini(source.size(), candidate.size())):
		result.append(candidate[i] - source[i])
	return result

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("player_attack2_contact_v6_safe_smoke: mechanical checks passed; visual approval remains pending")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack2_contact_v6_safe_smoke: " + failure)
		quit(1)
