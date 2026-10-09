extends SceneTree

const SOURCE := "res://assets/art/player/elven_fighter_hit_reaction_v1_candidate_1254x1254.png"
const CANDIDATE := "res://assets/art/player/elven_fighter_hit_reaction_v1_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_hit_reaction_comparison.png"
const IDLE := "res://assets/art/player/elven_fighter_reference_v8_safe_1254x1254.png"
const ATTACK := "res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png"
const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	var candidate := _load(CANDIDATE)
	var review := _load(REVIEW)
	_check(_load(IDLE) != null and _load(ATTACK) != null, "v8 idle and attack contact references are available")
	if source_bytes.is_empty():
		_check(source == null and candidate == null, "missing new hit original remains pending; no source or safe candidate was fabricated")
		_check(review != null and review.get_size() == Vector2i(2400, 1200), "review board compares idle, contact, and procedural hit at one shared 192px canvas scale in both mirror directions")
	else:
		_check(source != null and source.get_size() == SIZE and source.get_format() == Image.FORMAT_RGBA8, "provided original is 1254x1254 RGBA8")
		_check(candidate != null and candidate.get_size() == SIZE and candidate.get_format() == Image.FORMAT_RGBA8, "separate safe candidate is 1254x1254 RGBA8")
		_check(review != null and review.get_size() == Vector2i(2400, 1200), "review board includes original and safe panels")
		if candidate != null:
			var bounds := _bounds(candidate)
			var margins := Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)
			_check(mini(mini(margins.x, margins.y), mini(margins.z, margins.w)) >= MIN_MARGIN, "candidate has at least 90px transparent margin on all sides")
			_check(_isolated_count(candidate) == 0, "candidate has zero isolated alpha pixels")
		_check(_bytes(SOURCE) == source_bytes, "original source PNG bytes remain unchanged")
	if failures.is_empty():
		print("player_hit_reaction_safe_smoke: mechanical gates passed; human pose/identity distinction review remains pending")
		quit(0)
	else:
		for failure in failures:
			push_error("player_hit_reaction_safe_smoke: " + failure)
		quit(1)

func _load(path: String) -> Image:
	var bytes := _bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return null
	return image

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
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if (ox != 0 or oy != 0) and x + ox >= 0 and y + oy >= 0 and x + ox < image.get_width() and y + oy < image.get_height() and image.get_pixel(x + ox, y + oy).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)


