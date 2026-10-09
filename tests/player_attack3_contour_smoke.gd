extends SceneTree

const TOOL := preload("res://tools/repair_player_attack3_contour.gd")
const SOURCE := "res://assets/art/player/elven_fighter_attack3_reference_v2_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack3_reference_v2_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack3_contour_gate.png"
const SIZE := 1254
const MARGIN := 90

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
		"source/safe/clean and contour candidate PNGs decode")
	_check(review != null and review.get_size() == Vector2i(1920, 2740),
		"review sheet includes four backgrounds, detail enlargements and 192px comparison rows")
	if source != null and safe != null and clean != null and candidate != null:
		_check(_valid_canvas(candidate), "RGBA 1254 square retains at least 90px transparent margins")
		var expected: Image = TOOL.repair_contour(clean, safe).image
		if not _same_pixels(candidate, expected):
			var mismatches := 0
			for y in range(SIZE):
				for x in range(SIZE):
					if not candidate.get_pixel(x, y).is_equal_approx(expected.get_pixel(x, y)):
						mismatches += 1
			print("candidate debug: mismatches=%d" % mismatches)
		_check(_same_pixels(candidate, expected), "candidate is reproducible from clean and safe inputs")
		_check(_mouth_repaired(clean, safe, candidate), "interior mouth alpha loss is restored from the unchanged safe image")
		_check(_outside_roi_unchanged(clean, candidate), "all pixels outside face/neck/raised-arm/fist ROIs remain exact")
		_check(_features_preserved(clean, candidate), "face/hair, uppercut connection, trousers, boots, gold and foot anchor remain intact")
		_check(_red_count(candidate) < _red_count(clean), "red contour residual count falls in the repair zones")
		_check(_alpha_rules(clean, safe, candidate), "repair clears external alpha and restores only the known interior mouth loss")
		_check(_fixture_checks(), "fixture separately tests external translucency, opaque skin repair and protected pixels")
	_check(source_bytes == _bytes(SOURCE) and safe_bytes == _bytes(SAFE) and clean_bytes == _bytes(CLEAN),
		"v2 original, safe and clean files remain byte-for-byte unchanged")
	_check(TOOL.repair_contour(null).is_empty(), "null image returns a failure value")
	_check(TOOL.repair_contour(Image.create(64, 64, false, Image.FORMAT_RGBA8)).is_empty(),
		"wrong-sized image returns a failure value")
	_check(_failure_codes_are_stable(), "usage/source/safe/clean/forest/output/mutation codes are distinct")
	_check(_cli_exit_code(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/repair_player_attack3_contour.gd", "--", "unexpected"]) == TOOL.CODE_USAGE,
		"unexpected command-line argument returns usage code")
	if failures.is_empty():
		print("player_attack3_contour_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack3_contour_smoke: " + failure)
		quit(1)

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != Vector2i(SIZE, SIZE) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.position.x < MARGIN or bounds.position.y < MARGIN:
		return false
	if SIZE - bounds.end.x < MARGIN or SIZE - bounds.end.y < MARGIN:
		return false
	for x in range(SIZE):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, SIZE - 1).a != 0.0:
			return false
	for y in range(SIZE):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(SIZE - 1, y).a != 0.0:
			return false
	return true

func _outside_roi_unchanged(before: Image, after: Image) -> bool:
	for y in range(SIZE):
		for x in range(SIZE):
			if not _in_roi(x, y) and not before.get_pixel(x, y).is_equal_approx(after.get_pixel(x, y)):
				return false
	return true

func _in_roi(x: int, y: int) -> bool:
	return ((x >= 548 and x <= 790 and y >= 250 and y <= 440) \
		or (x >= 690 and x <= 955 and y >= 190 and y <= 490) \
		or (x >= 895 and x <= 988 and y >= 84 and y <= 205))

func _features_preserved(before: Image, after: Image) -> bool:
	var bounds := _alpha_bounds(before)
	var windows := [Rect2(0.06, 0.13, 0.34, 0.27), Rect2(0.43, 0.10, 0.20, 0.17),
		Rect2(0.78, 0.00, 0.18, 0.26), Rect2(0.62, 0.18, 0.24, 0.28),
		Rect2(0.42, 0.38, 0.30, 0.30), Rect2(0.02, 0.87, 0.23, 0.13),
		Rect2(0.79, 0.81, 0.21, 0.18)]
	for window in windows:
		var rect := Rect2i(bounds.position.x + int(bounds.size.x * window.position.x),
			bounds.position.y + int(bounds.size.y * window.position.y),
			maxi(1, int(bounds.size.x * window.size.x)), maxi(1, int(bounds.size.y * window.size.y)))
		var solid := 0
		var unchanged := 0
		for y in range(rect.position.y, mini(rect.end.y, SIZE)):
			for x in range(rect.position.x, mini(rect.end.x, SIZE)):
				var p := before.get_pixel(x, y)
				if p.a > 0.95:
					solid += 1
					if p.is_equal_approx(after.get_pixel(x, y)):
						unchanged += 1
		if solid < 8 or float(unchanged) / solid < 0.97:
			return false
	return _alpha_bounds(before).end.y == _alpha_bounds(after).end.y

func _red_count(image: Image) -> int:
	var count := 0
	for y in range(84, 492):
		for x in range(545, 990):
			if _in_roi(x, y):
				var p := image.get_pixel(x, y)
				if p.a > 0.02 and TOOL._red_outlier(p):
					count += 1
	return count

func _alpha_rules(before: Image, donor: Image, after: Image) -> bool:
	var removed := 0
	for y in range(SIZE):
		for x in range(SIZE):
			var a := before.get_pixel(x, y).a
			var b := after.get_pixel(x, y).a
			if b > a and not (x >= 698 and x < 745 and y >= 315 and y < 353 \
				and before.get_pixel(x, y).a < 0.08 and after.get_pixel(x, y).is_equal_approx(donor.get_pixel(x, y))):
				return false
			if a >= 0.82 and b < 0.82:
				removed += 1
	return removed <= 3000

func _fixture_checks() -> bool:
	var fixture := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	var skin := Color("#e9b28e")
	fixture.fill_rect(Rect2i(580, 280, 100, 90), skin)
	fixture.fill_rect(Rect2i(615, 315, 5, 5), Color("#ff1712"))
	fixture.fill_rect(Rect2i(895, 150, 5, 5), Color("#ff2018"))
	fixture.set_pixel(895, 152, Color("#ff2018", 0.55))
	var result := TOOL.repair_contour(fixture)
	if result.is_empty():
		return false
	var fixed: Image = result.image
	var repaired := fixed.get_pixel(617, 317)
	var ok := fixed.get_pixel(896, 152).a == 0.0 and repaired.a == 1.0 \
		and Vector3(repaired.r, repaired.g, repaired.b).distance_to(Vector3(skin.r, skin.g, skin.b)) < 0.12 \
		and fixed.get_pixel(600, 300).is_equal_approx(skin) and fixed.get_pixel(500, 300).a == 0.0 \
		and int(result.removed) > 0 and int(result.restored) > 0
	return ok

func _failure_codes_are_stable() -> bool:
	var codes := [TOOL.CODE_USAGE, TOOL.CODE_SOURCE, TOOL.CODE_SAFE, TOOL.CODE_CLEAN,
		TOOL.CODE_FOREST, TOOL.CODE_OUTPUT, TOOL.CODE_MUTATED]
	var found := {}
	for code in codes:
		if code <= 0 or found.has(code):
			return false
		found[code] = true
	return codes.size() == 7

func _same_pixels(a: Image, b: Image) -> bool:
	if a == null or b == null or a.get_size() != b.get_size():
		return false
	for y in range(SIZE):
		for x in range(SIZE):
			var pa := a.get_pixel(x, y)
			var pb := b.get_pixel(x, y)
			if pa.a < 0.001 and pb.a < 0.001:
				continue
			if not pa.is_equal_approx(pb):
				return false
	return true

func _mouth_repaired(clean: Image, safe: Image, candidate: Image) -> bool:
	var restored := 0
	for y in range(315, 353):
		for x in range(698, 745):
			if clean.get_pixel(x, y).a < 0.08 and safe.get_pixel(x, y).a >= 0.92:
				restored += 1
				if not candidate.get_pixel(x, y).is_equal_approx(safe.get_pixel(x, y)):
					return false
	return restored > 0

func _alpha_bounds(image: Image) -> Rect2i:
	var left := SIZE
	var top := SIZE
	var right := -1
	var bottom := -1
	for y in range(SIZE):
		for x in range(SIZE):
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
