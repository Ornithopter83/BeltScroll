extends SceneTree

const TOOL := preload("res://tools/repair_player_attack2_v4_contour.gd")
const SOURCE := "res://assets/art/player/elven_fighter_attack2_reference_v4_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack2_reference_v4_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_attack2_reference_v4_clean_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack2_reference_v4_contour_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack2_v4_contour_gate.png"
const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var safe_bytes := _bytes(SAFE)
	var clean_bytes := _bytes(CLEAN)
	var source := _load(SOURCE)
	var safe := _load(SAFE)
	var clean := _load(CLEAN)
	var candidate := _load(OUTPUT)
	var review := _load(REVIEW)
	_check(source != null and safe != null and clean != null and candidate != null,
		"original, safe, clean and repaired PNGs decode")
	_check(review != null and review.get_size() == Vector2i(1920, 2520),
		"review board contains four backgrounds, contour enlargements and 192px comparisons")
	if source != null and safe != null and clean != null and candidate != null:
		_check(candidate.get_size() == SIZE and candidate.get_format() == Image.FORMAT_RGBA8,
			"candidate uses RGBA8 at 1254×1254")
		_check(TOOL.has_clear_margins(candidate), "candidate retains at least 90 transparent pixels on every side")
		var expected: Dictionary = TOOL.repair_contour(clean)
		_check(not expected.is_empty() and _same_pixels(candidate, expected.image), "candidate reproduces from the unchanged clean image")
		_check(_red_count(candidate) < _red_count(clean), "red residue falls across the six repair zones")
		_check(_only_zones_changed(clean, candidate), "pixels outside ponytail, face/ear, shoulder/arm/fist and boots stay exact")
		_check(_shape_is_safe(clean, candidate), "alpha removal is limited to translucent edge pixels and silhouette bounds stay fixed")
		_check(_opaque_red_was_recolored(clean, candidate), "opaque red contamination is recolored from local context")
		_check(_key_features_unchanged(clean, candidate), "face details, trousers, glove interior, gold trim and both foot anchors are preserved")
		_check(_fixture_checks(), "fixture exercises translucent fringe, opaque repair and unrelated color preservation")
	_check(source_bytes == _bytes(SOURCE) and safe_bytes == _bytes(SAFE) and clean_bytes == _bytes(CLEAN),
		"original, safe and clean files remain byte-for-byte unchanged")
	_check(TOOL.repair_contour(null).is_empty(), "null image returns a failure value")
	_check(TOOL.repair_contour(Image.create(64, 64, false, Image.FORMAT_RGBA8)).is_empty(),
		"wrong canvas size returns a failure value")
	_check(_error_codes_are_stable(), "usage, input, output and protected-file error codes are distinct")
	_check(_cli_exit_code(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/repair_player_attack2_v4_contour.gd", "--", "unexpected"]) == TOOL.CODE_USAGE,
		"unexpected CLI argument returns the documented usage code")
	if failures.is_empty():
		print("player_attack2_v4_contour_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack2_v4_contour_smoke: " + failure)
		quit(1)

func _only_zones_changed(before: Image, after: Image) -> bool:
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if not _in_zone(x, y) and not before.get_pixel(x, y).is_equal_approx(after.get_pixel(x, y)):
				return false
	return true

func _in_zone(x: int, y: int) -> bool:
	for value in TOOL._zones():
		var rect: Rect2i = value
		if rect.has_point(Vector2i(x, y)):
			return true
	return false

func _shape_is_safe(before: Image, after: Image) -> bool:
	var old_bounds := _alpha_bounds(before)
	var new_bounds := _alpha_bounds(after)
	if old_bounds != new_bounds:
		return false
	var removed := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y).a
			var b := after.get_pixel(x, y).a
			if b > a:
				return false
			if b < a:
				removed += 1
				if a >= 0.82 or b != 0.0 or not _in_zone(x, y):
					return false
	return removed > 0 and removed < 3000

func _opaque_red_was_recolored(before: Image, after: Image) -> bool:
	var repaired := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if a.a >= 0.82 and TOOL._red_stain(a) and not a.is_equal_approx(b):
				repaired += 1
				if b.a != a.a:
					return false
	return repaired > 0

func _key_features_unchanged(before: Image, after: Image) -> bool:
	# These interior patches cover eye/nose/mouth, the ear junction, glove and
	# gold fittings, trouser panels, and boot contact/anchor edges.
	var patches := [Rect2i(805, 260, 36, 44), Rect2i(685, 245, 32, 24),
		Rect2i(865, 415, 60, 55), Rect2i(280, 535, 700, 345),
		Rect2i(210, 960, 70, 80), Rect2i(1035, 1015, 80, 80)]
	for index in range(patches.size()):
		var rect: Rect2i = patches[index]
		var changed := 0
		var area := 0
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				area += 1
				if not before.get_pixel(x, y).is_equal_approx(after.get_pixel(x, y)):
					changed += 1
		var allowance := 0.14 if index == 1 else 0.05
		if float(changed) / area > allowance:
			return false
	return true

func _red_count(image: Image) -> int:
	var count := 0
	for zone_value in TOOL._zones():
		var zone: Rect2i = zone_value
		for y in range(zone.position.y, zone.end.y):
			for x in range(zone.position.x, zone.end.x):
				var pixel := image.get_pixel(x, y)
				if TOOL._red_stain(pixel):
					count += 1
	return count

func _fixture_checks() -> bool:
	var fixture := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	fixture.fill_rect(Rect2i(300, 200, 80, 70), Color("#e9b28e"))
	fixture.set_pixel(300, 220, Color(1.0, 0.05, 0.02, 0.55))
	fixture.set_pixel(301, 221, Color("#ff1712"))
	fixture.set_pixel(302, 221, Color("#ff1712"))
	fixture.fill_rect(Rect2i(220, 190, 30, 25), Color("#704a30"))
	fixture.set_pixel(230, 195, Color("#d39a31"))
	var result: Dictionary = TOOL.repair_contour(fixture)
	if result.is_empty():
		return false
	var output: Image = result.image
	return output.get_pixel(300, 220).a == 0.0 \
		and not TOOL._red_stain(output.get_pixel(301, 221)) \
		and output.get_pixel(210, 200).a == 0.0 \
		and output.get_pixel(230, 195).is_equal_approx(fixture.get_pixel(230, 195)) \
		and int(result.alpha_cleared) >= 1 and int(result.rgb_restored) >= 1

func _error_codes_are_stable() -> bool:
	var values := [TOOL.CODE_USAGE, TOOL.CODE_SOURCE, TOOL.CODE_SAFE, TOOL.CODE_CLEAN,
		TOOL.CODE_FOREST, TOOL.CODE_OUTPUT, TOOL.CODE_PROTECTED]
	var found := {}
	for code in values:
		if code <= 0 or found.has(code):
			return false
		found[code] = true
	return values.size() == 7

func _same_pixels(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true

func _alpha_bounds(image: Image) -> Rect2i:
	var left := SIZE.x
	var top := SIZE.y
	var right := -1
	var bottom := -1
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a >= 0.01:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

func _load(path: String) -> Image:
	var full := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(full):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(full)) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _cli_exit_code(arguments: PackedStringArray) -> int:
	var output: Array[String] = []
	return OS.execute(OS.get_executable_path(), arguments, output, true)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
