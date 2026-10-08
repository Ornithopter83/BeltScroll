extends SceneTree

const TOOL := preload("res://tools/prepare_player_attack3_v2.gd")
const SOURCE := "res://assets/art/player/elven_fighter_attack3_reference_v2_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack3_reference_v2_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png"
const V8 := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack3_v2_gate.png"
const SIZE := 1254
const MIN_MARGIN := 90

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load(SOURCE)
	var safe := _load(SAFE)
	var clean := _load(CLEAN)
	var reference := _load(V8)
	var review := _load(REVIEW)
	_check(source != null, "attack3 v2 original PNG decodes")
	_check(safe != null, "safe candidate PNG decodes")
	_check(clean != null, "clean candidate PNG decodes")
	_check(reference != null, "v8 clean comparison reference decodes")
	_check(review != null, "four candidates render over white, black, checker and forest backgrounds")
	if review != null:
		_check(review.get_size() == Vector2i(2560, 3180), "review sheet includes a 192px comparison row for each background")
	if source != null and safe != null:
		_check(_valid_canvas(safe), "safe uses RGBA 1254 square with at least 90 transparent pixels on every side")
		_check(_same_pixels(safe, TOOL.normalize(source)), "safe candidate is normalized from the original without paint or cleanup")
	if safe != null and clean != null:
		_check(_valid_canvas(clean), "clean retains the safe dimensions and margin")
		_check(_localized_changes(safe, clean), "clean changes remain localized and preserve the foot anchor")
		_check(_body_preserved(safe, clean), "face, hair, raised arm, tunic, trousers and boots remain intact")
		_check(_stain_count(clean) < _stain_count(safe), "red/yellow contamination count is reduced")
		var edge_spill_before: int = TOOL.HALO_REPAIR.pollution_count(safe)
		var edge_spill_after: int = TOOL.HALO_REPAIR.pollution_count(clean)
		_check(edge_spill_before > edge_spill_after,
			"edge-aware warm spill score decreases (%d -> %d)" % [edge_spill_before, edge_spill_after])
		_check(_fixture_checks(), "external stains lose alpha, internal stains get local color repair, and gold is preserved")
	_check(source != null and FileAccess.get_file_as_bytes(source_path) == source_bytes,
		"attack3 v2 original remains byte-for-byte unchanged")
	_check(TOOL.normalize(null) == null and TOOL.clean_fringes(null).is_empty(), "null inputs return failure values")
	_check(TOOL.normalize(Image.create(64, 64, false, Image.FORMAT_RGBA8)) == null,
		"fully transparent source cannot produce a safe candidate")
	_check(TOOL.clean_fringes(Image.create(64, 64, false, Image.FORMAT_RGBA8)).is_empty(),
		"wrong-sized cleanup input returns a failure value")
	_check(_failure_codes_are_stable(), "documented usage/source/reference/forest/output/mutation codes are distinct")
	_check(_cli_exit_code(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script",
		"res://tools/prepare_player_attack3_v2.gd", "--", "unexpected"]) == TOOL.CODE_USAGE,
		"unexpected command-line argument returns usage error code")
	if failures.is_empty():
		print("player_attack3_v2_art_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack3_v2_art_smoke: " + failure)
		quit(1)

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != Vector2i(SIZE, SIZE) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var b := TOOL._alpha_bounds(image)
	if b.size.x <= 0 or b.position.x < MIN_MARGIN or b.position.y < MIN_MARGIN:
		return false
	if SIZE - b.end.x < MIN_MARGIN or SIZE - b.end.y < MIN_MARGIN:
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
	for y in range(SIZE):
		for x in range(SIZE):
			if not before.get_pixel(x, y).is_equal_approx(after.get_pixel(x, y)):
				changed += 1
				if changed > 12000:
					return false
	var before_bounds := TOOL._alpha_bounds(before)
	var after_bounds := TOOL._alpha_bounds(after)
	return changed > 0 and before_bounds.end.y == after_bounds.end.y

func _body_preserved(before: Image, after: Image) -> bool:
	var b := TOOL._alpha_bounds(before)
	# Relative boxes cover ponytail, face/ear, raised fist and arm, torso and both boots.
	var windows := [Rect2(0.06, 0.13, 0.34, 0.27), Rect2(0.43, 0.10, 0.20, 0.17),
		Rect2(0.78, 0.00, 0.18, 0.26), Rect2(0.62, 0.18, 0.24, 0.28),
		Rect2(0.42, 0.38, 0.30, 0.30), Rect2(0.02, 0.87, 0.23, 0.13),
		Rect2(0.79, 0.81, 0.21, 0.18)]
	for window in windows:
		var region := Rect2i(b.position.x + int(b.size.x * window.position.x), b.position.y + int(b.size.y * window.position.y),
			maxi(1, int(b.size.x * window.size.x)), maxi(1, int(b.size.y * window.size.y)))
		var solid := 0
		var unchanged := 0
		for y in range(region.position.y, mini(region.end.y, SIZE)):
			for x in range(region.position.x, mini(region.end.x, SIZE)):
				var p := before.get_pixel(x, y)
				if p.a > 0.95:
					solid += 1
					if p.is_equal_approx(after.get_pixel(x, y)):
						unchanged += 1
		if solid < 8 or float(unchanged) / solid < 0.97:
			return false
	return true

func _stain_count(image: Image) -> int:
	var count := 0
	for y in range(SIZE):
		for x in range(SIZE):
			var p := image.get_pixel(x, y)
			if p.a > 0.02 and TOOL._stain_candidate(p):
				count += 1
	return count

func _fixture_checks() -> bool:
	var fixture := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	var body := Color("#376879")
	fixture.fill_rect(Rect2i(100, 100, 90, 90), body)
	# Enclosed red anomaly is replaced with a local normal color, preserving alpha.
	fixture.fill_rect(Rect2i(135, 135, 5, 5), Color("#ff1712"))
	# Red and bright yellow patches outside the silhouette connect to transparency.
	fixture.fill_rect(Rect2i(96, 155, 5, 5), Color("#ff2018"))
	fixture.fill_rect(Rect2i(188, 170, 5, 5), Color("#fff000"))
	var gold := Color("#d39a31")
	fixture.fill_rect(Rect2i(220, 100, 34, 40), Color("#72502e"))
	fixture.fill_rect(Rect2i(224, 105, 6, 30), gold)
	var result := TOOL.clean_fringes(fixture)
	if result.is_empty():
		return false
	var fixed: Image = result["image"]
	var repaired := fixed.get_pixel(137, 137)
	return fixed.get_pixel(97, 157).a == 0.0 and fixed.get_pixel(189, 171).a == 0.0 \
		and repaired.a == 1.0 and Vector3(repaired.r, repaired.g, repaired.b).distance_to(Vector3(body.r, body.g, body.b)) < 0.25 \
		and fixed.get_pixel(110, 110).is_equal_approx(body) and fixed.get_pixel(226, 120).is_equal_approx(gold)

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
	var full := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(full):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(full)) != OK:
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
