extends SceneTree

const TOOL := preload("res://tools/prepare_player_attack1.gd")
const SOURCE := "res://assets/art/player/elven_fighter_attack1_reference_v1_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack1_reference_v1_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_attack1_reference_v1_clean_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack1_v8_contact.png"
const SIZE := 1254
const MIN_MARGIN := 90

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load(source_path)
	var safe := _load(ProjectSettings.globalize_path(SAFE))
	var clean := _load(ProjectSettings.globalize_path(CLEAN))
	var review := _load(ProjectSettings.globalize_path(REVIEW))
	_check(source != null, "single attack1 original PNG decodes")
	_check(safe != null, "safe candidate PNG decodes")
	_check(clean != null, "clean candidate PNG decodes")
	_check(review != null, "white/dark/checker/Forest Ruins review and v8 comparison decode")
	if source != null and safe != null:
		_check(_valid_canvas(safe), "safe is RGBA 1254 square with at least 90 fully transparent pixels on every side")
		_check(_same_pixels(safe, TOOL.normalize(source)), "safe candidate is nondestructively normalized from the original")
	if safe != null and clean != null:
		_check(_valid_canvas(clean), "clean candidate retains size, alpha and safe margins")
		_check(_localized_changes(safe, clean), "fringe cleanup is localized and preserves opaque silhouette/foot anchor")
		_check(_punch_and_gold_preserved(safe, clean), "extended punch fist, clothing and gold ornament remain intact")
		_check(_fixture_checks(), "fringe pixels are cleaned while natural warm colors and transparent margins are protected")
	_check(source != null and FileAccess.get_file_as_bytes(source_path) == source_bytes,
		"source PNG remains byte-for-byte unchanged")
	_check(TOOL.clean_fringes(null).is_empty(), "null cleanup input returns a failure result")
	var wrong_size := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	_check(TOOL.clean_fringes(wrong_size).is_empty(), "wrong-sized cleanup input returns a failure result")
	_check(_failure_codes_are_stable(), "documented source/reference/forest/output/mutation failure codes are distinct")
	_check(_cli_exit_code(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/prepare_player_attack1.gd", "--", "unexpected"]) == TOOL.CODE_USAGE,
		"unexpected command-line arguments return usage failure code")
	if failures.is_empty():
		print("player_attack1_art_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack1_art_smoke: " + failure)
		quit(1)

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != Vector2i(SIZE, SIZE) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := TOOL._alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return false
	if bounds.position.x < MIN_MARGIN or bounds.position.y < MIN_MARGIN:
		return false
	if SIZE - bounds.end.x < MIN_MARGIN or SIZE - bounds.end.y < MIN_MARGIN:
		return false
	for x in range(SIZE):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, SIZE - 1).a != 0.0:
			return false
	for y in range(SIZE):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(SIZE - 1, y).a != 0.0:
			return false
	return true

func _localized_changes(before: Image, after: Image) -> bool:
	var changed := 0
	var lost_alpha := 0
	var gained_alpha := 0
	for y in range(SIZE):
		for x in range(SIZE):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if not a.is_equal_approx(b):
				changed += 1
				if a.a >= 0.5 and b.a < 0.5:
					lost_alpha += 1
				elif a.a < 0.5 and b.a >= 0.5:
					gained_alpha += 1
				if changed > 10000:
					return false
	# The bottom-most opaque row is the foot anchor. Cleanup may clear a few fringe
	# alpha pixels, but cannot move the anchor or alter any of the fist's solid core.
	var before_bounds := TOOL._alpha_bounds(before)
	var after_bounds := TOOL._alpha_bounds(after)
	return lost_alpha <= 1000 and gained_alpha == 0 and before_bounds.end.y == after_bounds.end.y

func _punch_and_gold_preserved(before: Image, after: Image) -> bool:
	var b := TOOL._alpha_bounds(before)
	var fist_left := b.position.x + int(float(b.size.x) * 0.91)
	var fist_right := b.end.x - 4
	var fist_top := b.position.y + int(float(b.size.y) * 0.23)
	var fist_bottom := b.position.y + int(float(b.size.y) * 0.32)
	var fist_pixels := 0
	for y in range(fist_top, fist_bottom):
		for x in range(fist_left, fist_right):
			var a := before.get_pixel(x, y)
			if a.a > 0.95:
				fist_pixels += 1
				if not a.is_equal_approx(after.get_pixel(x, y)):
					return false
	# Stable samples in the tunic and the gold waist ornament are untouched.
	var garment := before.get_pixel(b.position.x + int(b.size.x * 0.56), b.position.y + int(b.size.y * 0.58))
	var ornament := before.get_pixel(b.position.x + int(b.size.x * 0.61), b.position.y + int(b.size.y * 0.64))
	var garment_after := after.get_pixel(b.position.x + int(b.size.x * 0.56), b.position.y + int(b.size.y * 0.58))
	var ornament_after := after.get_pixel(b.position.x + int(b.size.x * 0.61), b.position.y + int(b.size.y * 0.64))
	return fist_pixels > 20 and garment.a > 0.9 and ornament.a > 0.9 \
		and garment.is_equal_approx(garment_after) and ornament.is_equal_approx(ornament_after)

func _fixture_checks() -> bool:
	var fixture := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	var skin := Color("#e9b28e")
	fixture.fill_rect(Rect2i(100, 100, 80, 70), skin)
	# Internal connected red blemish should be repaired without removing its alpha.
	for y in range(120, 124):
		for x in range(130, 135):
			fixture.set_pixel(x, y, Color("#ff1712"))
	# A second red patch touches transparent space and should be cleared.
	for y in range(140, 144):
		for x in range(96, 102):
			fixture.set_pixel(x, y, Color("#ff2018"))
	fixture.fill_rect(Rect2i(220, 100, 44, 50), Color("#72502e"))
	fixture.fill_rect(Rect2i(223, 106, 7, 37), Color("#d39a31"))
	var fixed_result := TOOL.clean_fringes(fixture)
	if fixed_result.is_empty():
		return false
	var fixed: Image = fixed_result["image"]
	var repaired := fixed.get_pixel(132, 121)
	return fixed.get_pixel(97, 141).a == 0.0 and repaired.a > 0.9 and repaired.r < 0.95 \
		and fixed.get_pixel(110, 110).is_equal_approx(skin) \
		and fixed.get_pixel(225, 120).is_equal_approx(Color("#d39a31"))

func _failure_codes_are_stable() -> bool:
	var codes := [TOOL.CODE_USAGE, TOOL.CODE_SOURCE, TOOL.CODE_REFERENCE, TOOL.CODE_FOREST, TOOL.CODE_OUTPUT, TOOL.CODE_MUTATED]
	var unique := {}
	for code in codes:
		if code <= 0 or unique.has(code):
			return false
		unique[code] = true
	return codes.size() == 6

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

func _cli_exit_code(arguments: PackedStringArray) -> int:
	var output: Array[String] = []
	return OS.execute(OS.get_executable_path(), arguments, output, true)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
