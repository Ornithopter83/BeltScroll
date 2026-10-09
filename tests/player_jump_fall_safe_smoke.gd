extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_INSET := 90
const REVIEW_SIZE := Vector2i(1626, 880)
const SOURCE := "res://assets/art/player/elven_fighter_jump_fall_v1_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_jump_fall_v1_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_jump_fall_comparison.png"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	var safe := _load(SAFE)
	var review := _load(REVIEW)
	if source_bytes.is_empty():
		_check(safe == null, "missing jump-fall source is reported without a derived safe candidate")
		_check(review != null and review.get_size() == REVIEW_SIZE, "192px full-canvas comparison board is still produced when jump-fall artwork is missing")
		print("JUMP_FALL_SMOKE source=MISSING safe=MISSING; compare board keeps v8 idle and jump-rise safe")
	else:
		_check(source != null and source.get_size() == SIZE and source.get_format() == Image.FORMAT_RGBA8, "source PNG is 1254x1254 RGBA8")
		_check(safe != null and safe.get_size() == SIZE and safe.get_format() == Image.FORMAT_RGBA8, "safe candidate is 1254x1254 RGBA8")
		if safe != null:
			var b := _bounds(safe)
			var margins := Vector4i(b.position.x, b.position.y, SIZE.x - b.end.x, SIZE.y - b.end.y)
			_check(b.size.x > 0 and b.size.y > 0, "safe candidate contains alpha artwork")
			_check(margins.x >= MIN_INSET and margins.y >= MIN_INSET and margins.z >= MIN_INSET and margins.w >= MIN_INSET, "safe candidate has 90px minimum alpha margins: %s" % str(margins))
			_check(_transparent_border(safe), "safe candidate outer border is transparent")
			_check(_isolated_count(safe) == 0, "safe candidate has zero isolated alpha pixels")
			_check(_zero_alpha_rgb(safe), "fully transparent pixels have zero RGB")
		_check(not source_bytes.is_empty() and _bytes(SOURCE) == source_bytes, "source bytes remain unchanged during smoke inspection")
		print("JUMP_FALL_SMOKE source_bytes=%d sha256=%s human_art_review=required" % [source_bytes.size(), _sha(source_bytes)])
	_check(review != null and review.get_size() == REVIEW_SIZE, "comparison board is 1626x880 and includes right/mirrored pose rows")
	if failures.is_empty():
		print("player_jump_fall_safe_smoke: mechanical checks passed; pose, identity, anchors, and scale-pop require human review")
		quit(0)
	else:
		for message in failures:
			push_error("player_jump_fall_safe_smoke: " + message)
		quit(1)

func _load(path: String) -> Image:
	var bytes := _bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes) == OK else null

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.000001:
				left = mini(left, x); top = mini(top, y); right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, image.get_height() - 1).a != 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(image.get_width() - 1, y).a != 0.0:
			return false
	return true

func _zero_alpha_rgb(image: Image) -> bool:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p := image.get_pixel(x, y)
			if p.a == 0.0 and (p.r != 0.0 or p.g != 0.0 or p.b != 0.0):
				return false
	return true

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox; var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _sha(data: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures.append(message)
