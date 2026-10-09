extends SceneTree

const SIZE := Vector2i(1254, 1254)
const GAME_SIZE := 192
const MIN_INSET := 90
const SOURCE := "res://assets/art/player/elven_fighter_jump_rise_v1_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png"
const IDLE := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const REVIEW := "res://assets/art/review/player_jump_rise_safe_comparison.png"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	var safe := _load(SAFE)
	var idle := _load(IDLE)
	var review := _load(REVIEW)
	_check(source != null and source.get_size() == SIZE and source.get_format() == Image.FORMAT_RGBA8, "preserved jump-rise source loads as 1254x1254 RGBA8")
	_check(idle != null and idle.get_size() == SIZE, "v8 idle comparison source loads")
	_check(safe != null and safe.get_size() == SIZE and safe.get_format() == Image.FORMAT_RGBA8, "safe candidate loads as 1254x1254 RGBA8")
	_check(review != null and review.get_size() == Vector2i(2256, 760), "v8 idle, jump source, and safe comparison board loads")
	if safe != null:
		var bounds := _alpha_bounds(safe)
		var margins := Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)
		_check(bounds.size.x > 0 and bounds.size.y > 0, "safe artwork has visible alpha")
		_check(margins.x >= MIN_INSET and margins.y >= MIN_INSET and margins.z >= MIN_INSET and margins.w >= MIN_INSET, "nonzero alpha margins are at least 90px L/T/R/B: %s" % str(margins))
		_check(_transparent_border(safe), "outermost rows and columns are fully transparent")
		_check(_transparent_rgb_zero(safe), "fully transparent pixels store zero RGB")
		_check(_isolated_count(safe) == 0, "no isolated alpha pixels remain")
	if source != null and safe != null:
		_check(_uniform_scale(source, safe), "safe is a uniform reduction with the source pose unchanged")
		_check(_features_retained(source, safe), "face, pointed ear, both gloves, both boots, and ponytail remain represented")
		var src_game := source.duplicate()
		var safe_game := safe.duplicate()
		src_game.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
		safe_game.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
		print("JUMP_RISE_SMOKE source_bounds_192=%s safe_bounds_192=%s source_bottom_anchors=%s safe_bottom_anchors=%s" % [str(_alpha_bounds(src_game, 0.05)), str(_alpha_bounds(safe_game, 0.05)), str(_bottom_anchors(src_game)), str(_bottom_anchors(safe_game))])
	_check(not source_bytes.is_empty() and _bytes(SOURCE) == source_bytes, "original jump-rise source bytes remain unchanged")
	if failures.is_empty():
		print("player_jump_rise_safe_smoke: mechanical checks passed; airborne feet and identity require human review")
		quit(0)
	else:
		for failure in failures:
			push_error("player_jump_rise_safe_smoke: " + failure)
		quit(1)

func _features_retained(source: Image, safe: Image) -> bool:
	# Regions are normalized to each artwork's own alpha bounds to ignore the
	# added transparent safe margin while checking the preserved pose.
	var regions := [
		["face", Rect2(0.69, 0.10, 0.30, 0.22)],
		["pointed ear", Rect2(0.67, 0.12, 0.25, 0.20)],
		["rear glove", Rect2(0.10, 0.35, 0.30, 0.24)],
		["raised glove", Rect2(0.79, 0.19, 0.20, 0.24)],
		["left boot", Rect2(0.00, 0.78, 0.30, 0.22)],
		["right boot", Rect2(0.69, 0.65, 0.30, 0.30)],
		["ponytail", Rect2(0.00, 0.00, 0.62, 0.34)],
	]
	var all_present := true
	for item in regions:
		var before := _region_alpha(source, item[1])
		var after := _region_alpha(safe, item[1])
		print("FEATURE %s source=%d safe=%d" % [item[0], before, after])
		all_present = all_present and before > 0 and after > 0
	return all_present

func _region_alpha(image: Image, region: Rect2) -> int:
	var b := _alpha_bounds(image)
	var x0 := b.position.x + floori(region.position.x * b.size.x)
	var y0 := b.position.y + floori(region.position.y * b.size.y)
	var x1 := mini(b.end.x, b.position.x + ceili(region.end.x * b.size.x))
	var y1 := mini(b.end.y, b.position.y + ceili(region.end.y * b.size.y))
	var count := 0
	for y in range(maxi(0, y0), y1):
		for x in range(maxi(0, x0), x1):
			if image.get_pixel(x, y).a >= 0.05:
				count += 1
	return count

func _uniform_scale(source: Image, safe: Image) -> bool:
	var before := _alpha_bounds(source, 0.05)
	var after := _alpha_bounds(safe, 0.05)
	if before.size.x <= 0 or before.size.y <= 0:
		return false
	var sx := float(after.size.x) / before.size.x
	var sy := float(after.size.y) / before.size.y
	print("UNIFORM_SCALE source=%s safe=%s x=%.6f y=%.6f" % [str(before), str(after), sx, sy])
	return sx < 1.0 and sy < 1.0 and absf(sx - sy) < 0.003

func _bottom_anchors(image: Image) -> Array[Vector2i]:
	var b := _alpha_bounds(image, 0.05)
	var result: Array[Vector2i] = []
	if b.size.x <= 0:
		return result
	var y := b.end.y - 1
	var start := -1
	for x in range(image.get_width() + 1):
		var active := x < image.get_width() and image.get_pixel(x, y).a >= 0.05
		if active and start < 0:
			start = x
		elif not active and start >= 0:
			result.append(Vector2i((start + x - 1) / 2, y))
			start = -1
	return result

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

func _transparent_border(image: Image) -> bool:
	for x in range(SIZE.x):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, SIZE.y - 1).a != 0.0:
			return false
	for y in range(SIZE.y):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(SIZE.x - 1, y).a != 0.0:
			return false
	return true

func _transparent_rgb_zero(image: Image) -> bool:
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
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < SIZE.x and ny < SIZE.y and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

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
	var absolute := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(absolute) if FileAccess.file_exists(absolute) else PackedByteArray()

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures.append(message)
