extends SceneTree

const TOOL := preload("res://tools/prepare_player_attack2_inbetween_safe.gd")
const SOURCE := "res://assets/art/player/elven_fighter_attack2_inbetween_v1_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png"
const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const GAME_SCALE := 3.0
const GAME_CANVAS := 192.0 * GAME_SCALE

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var candidate_bytes := _bytes(OUTPUT)
	var source := _load(SOURCE)
	var candidate := _load(OUTPUT)
	_check(not source_bytes.is_empty() and source != null, "original candidate PNG remains present and decodes")
	_check(candidate != null and candidate.get_size() == SIZE and candidate.get_format() == Image.FORMAT_RGBA8,
		"safe candidate decodes as RGBA8 at 1254x1254")
	if source == null or candidate == null:
		_finish()
		return
	var candidate_edge_pixels := _canvas_edge_nonzero_count(candidate)
	var source_bounds := _bounds(source)
	var candidate_bounds := _bounds(candidate)
	var source_visible_bounds := _bounds(source, 0.05)
	var candidate_visible_bounds := _bounds(candidate, 0.05)
	var margins := Vector4i(candidate_bounds.position.x, candidate_bounds.position.y,
		SIZE.x - candidate_bounds.end.x, SIZE.y - candidate_bounds.end.y)
	_check(source_bounds.position.x < MIN_MARGIN or source_bounds.position.y < MIN_MARGIN \
		or SIZE.x - source_bounds.end.x < MIN_MARGIN or SIZE.y - source_bounds.end.y < MIN_MARGIN,
		"source fails the nonzero-alpha safe inset, so the candidate addresses a real margin defect")
	_check(candidate_edge_pixels == 0, "all four outer canvas edges are fully transparent")
	_check(margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN,
		"all-side nonzero-alpha inset is at least 90px (L/T/R/B=%d/%d/%d/%d)" % [margins.x, margins.y, margins.z, margins.w])
	_check(candidate_bounds.size.x > 0 and candidate_bounds.size.y > 0, "candidate retains a nonempty full-body silhouette")
	var source_anchor := _foot_anchor(source, source_visible_bounds, 0.05)
	var candidate_anchor := _foot_anchor(candidate, candidate_visible_bounds, 0.05)
	var source_anchor_ratio := float(source_anchor.x - source_visible_bounds.position.x) / maxf(1.0, source_visible_bounds.size.x - 1)
	var candidate_anchor_ratio := float(candidate_anchor.x - candidate_visible_bounds.position.x) / maxf(1.0, candidate_visible_bounds.size.x - 1)
	_check(absf(source_anchor_ratio - candidate_anchor_ratio) <= 0.02,
		"bottom-row foot anchor stays within 0.02 of its relative horizontal position")
	var uniform_scale := float(candidate_visible_bounds.size.y) / source_visible_bounds.size.y
	var width_scale := float(candidate_visible_bounds.size.x) / source_visible_bounds.size.x
	_check(absf(uniform_scale - width_scale) <= 0.003,
		"silhouette is uniformly scaled without aspect-ratio distortion")
	var source_game := Vector2(source_visible_bounds.size) * (GAME_CANVAS / SIZE.x)
	var candidate_game := Vector2(candidate_visible_bounds.size) * (GAME_CANVAS / SIZE.x)
	var source_3x := source.duplicate()
	var candidate_3x := candidate.duplicate()
	source_3x.resize(roundi(GAME_CANVAS), roundi(GAME_CANVAS), Image.INTERPOLATE_LANCZOS)
	candidate_3x.resize(roundi(GAME_CANVAS), roundi(GAME_CANVAS), Image.INTERPOLATE_LANCZOS)
	var source_3x_bounds := _bounds_arbitrary(source_3x, 0.05)
	var candidate_3x_bounds := _bounds_arbitrary(candidate_3x, 0.05)
	print("GAME SCALE 3X (192px canvas rendered at 576px, alpha>=5%%): source visible bounds=%s -> %.1fx%.1fpx; safe=%s -> %.1fx%.1fpx; uniform scale=%.5f; relative foot anchor x=%.4f/%.4f; source nonzero bounds=%s; candidate outer-edge alpha=%d" % [
		str(source_visible_bounds.size), source_game.x, source_game.y, str(candidate_visible_bounds.size),
		candidate_game.x, candidate_game.y, uniform_scale, source_anchor_ratio, candidate_anchor_ratio,
		str(source_bounds), candidate_edge_pixels])
	print("RENDERED 3X CANVAS (576x576, Lanczos resample, alpha>=5%%): source=%s; safe=%s" % [str(source_3x_bounds.size), str(candidate_3x_bounds.size)])
	_check(source_bytes == _bytes(SOURCE), "original image bytes were not changed during candidate generation")
	_finish()

func _load(path: String) -> Image:
	var data := _bytes(path)
	if data.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _bounds(image: Image, threshold: float = 0.0) -> Rect2i:
	var left := SIZE.x
	var top := SIZE.y
	var right := -1
	var bottom := -1
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a >= maxf(0.000001, threshold):
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _bounds_arbitrary(image: Image, threshold: float) -> Rect2i:
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

func _foot_anchor(image: Image, bounds: Rect2i, threshold: float) -> Vector2i:
	var left := SIZE.x
	var right := -1
	for x in range(SIZE.x):
		if image.get_pixel(x, bounds.end.y - 1).a >= threshold:
			left = mini(left, x)
			right = maxi(right, x)
	return Vector2i((left + right) / 2, bounds.end.y - 1)

func _canvas_edge_nonzero_count(image: Image) -> int:
	var count := 0
	for x in range(SIZE.x):
		if image.get_pixel(x, 0).a > 0.0:
			count += 1
		if image.get_pixel(x, SIZE.y - 1).a > 0.0:
			count += 1
	for y in range(1, SIZE.y - 1):
		if image.get_pixel(0, y).a > 0.0:
			count += 1
		if image.get_pixel(SIZE.x - 1, y).a > 0.0:
			count += 1
	return count

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)

func _finish() -> void:
	if failures.is_empty():
		print("player_attack2_inbetween_safe_smoke: all checks passed; visual approval pending")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack2_inbetween_safe_smoke: " + failure)
		quit(1)
