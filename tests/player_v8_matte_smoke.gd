extends SceneTree

const TOOL := preload("res://tools/prepare_player_v8_matte.gd")
const SOURCE := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_reference_v8_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v8_matte_comparison.png"
const SIZE := 1254
const MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var original_bytes := FileAccess.get_file_as_bytes(source_path)
	var original := _load(source_path)
	var safe := _load(ProjectSettings.globalize_path(SAFE))
	var clean := _load(ProjectSettings.globalize_path(CLEAN))
	var review := _load(ProjectSettings.globalize_path(REVIEW))
	_check(original != null, "v8 source PNG loads")
	_check(safe != null, "safe candidate PNG loads")
	_check(clean != null, "clean candidate PNG loads")
	_check(review != null, "4-background enlarged and 192px comparison PNG loads")
	if safe != null:
		_check(_valid_canvas(safe), "safe candidate is 1254×1254 with at least 90px clear margins")
		var regenerated := TOOL.normalize(original)
		_check(_same_pixels(safe, regenerated), "safe candidate matches nondestructive source normalization")
	if clean != null and safe != null:
		_check(_valid_canvas(clean), "clean candidate keeps dimensions and safe margins")
		_check(_localized_changes(safe, clean), "cleanup leaves all unrelated artwork unchanged")
		_check(TOOL.clean_matte(null)["image"] == null, "null input returns a structured error result")
		var wrong_size := Image.create(64, 64, false, Image.FORMAT_RGBA8)
		_check(TOOL.clean_matte(wrong_size)["image"] == null, "invalid dimensions are rejected")
		_check(_fixture_checks(), "connected external/interior stain cleanup and skin/gold/hair protection")
	_check(FileAccess.get_file_as_bytes(source_path) == original_bytes, "v8 original remains byte-for-byte unchanged")
	if failures.is_empty():
		print("player_v8_matte_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_v8_matte_smoke: " + failure)
		quit(1)

func _fixture_checks() -> bool:
	var fixture := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	var skin := Color("#e9b28e")
	fixture.fill_rect(Rect2i(100, 100, 80, 70), skin)
	# One connected internal red patch, fully enclosed by opaque skin.
	for y in range(120, 124):
		for x in range(130, 135):
			fixture.set_pixel(x, y, Color("#ff1712"))
	# A second patch straddles the silhouette boundary and should be erased.
	for y in range(140, 144):
		for x in range(96, 102):
			fixture.set_pixel(x, y, Color("#ff2018"))
	# Normal color boundaries model protected gold trim and a tapered hair tip.
	fixture.fill_rect(Rect2i(220, 100, 44, 50), Color("#72502e"))
	fixture.fill_rect(Rect2i(223, 106, 7, 37), Color("#d39a31"))
	fixture.fill_rect(Rect2i(300, 100, 32, 30), Color("#50392e"))
	for i in range(20):
		fixture.set_pixel(332 + i, 100 - i / 2, Color(0.30 + i * 0.006, 0.20 + i * 0.003, 0.14, 1.0))
	var processed := TOOL.clean_matte(fixture)
	var fixed: Image = processed["image"]
	if fixed == null:
		return false
	var repaired := fixed.get_pixel(132, 121)
	var external_removed := fixed.get_pixel(97, 141).a == 0.0 and fixed.get_pixel(98, 142).a == 0.0
	var skin_protected := fixed.get_pixel(110, 110).is_equal_approx(skin)
	var gold_protected := fixed.get_pixel(225, 120).is_equal_approx(Color("#d39a31"))
	var hair_tip_protected := fixed.get_pixel(347, 92).is_equal_approx(fixture.get_pixel(347, 92))
	var stain_fixed := repaired.a > 0.9 and repaired.r < 0.95
	return external_removed and stain_fixed and skin_protected and gold_protected and hair_tip_protected

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != Vector2i(SIZE, SIZE) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := TOOL._alpha_bounds(image)
	return bounds.size.x > 0 and bounds.position.x >= MARGIN and bounds.position.y >= MARGIN \
		and SIZE - bounds.end.x >= MARGIN and SIZE - bounds.end.y >= MARGIN

func _localized_changes(before: Image, after: Image) -> bool:
	var changed := 0
	for y in range(SIZE):
		for x in range(SIZE):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if not a.is_equal_approx(b):
				changed += 1
				if changed > 3000:
					return false
	return true

func _same_pixels(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	for y in range(SIZE):
		for x in range(SIZE):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true

func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
