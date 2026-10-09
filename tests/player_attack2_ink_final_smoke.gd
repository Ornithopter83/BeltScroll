extends SceneTree

const TOOL := preload("res://tools/finalize_player_attack2_ink.gd")
const SOURCE := "res://assets/art/player/elven_fighter_attack2_reference_v4_contour_candidate_1254x1254.png"
const ORIGINAL := "res://assets/art/player/elven_fighter_attack2_reference_v4_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack2_reference_v4_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_attack2_reference_v4_clean_candidate_1254x1254.png"
const ATTACK1 := "res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png"
const ATTACK3 := "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack2_v4_ink_final_gate.png"
const SIZE := Vector2i(1254, 1254)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var protected_paths := [ORIGINAL, SAFE, CLEAN, SOURCE, ATTACK1, ATTACK3]
	var snapshots: Array[PackedByteArray] = []
	for path in protected_paths:
		snapshots.append(_bytes(path))
	var source := _load(SOURCE)
	var output := _load(OUTPUT)
	var board := _load(REVIEW)
	var attack1 := _load(ATTACK1)
	var attack3 := _load(ATTACK3)
	_check(source != null and output != null and attack1 != null and attack3 != null,
		"contour source, candidate and approved ink references decode")
	_check(board != null and board.get_size() == Vector2i(1920, 2580),
		"review board contains four backgrounds, enlarged details and 192px comparisons")
	if source != null and output != null and attack1 != null and attack3 != null:
		_check(source.get_size() == SIZE and source.get_format() == Image.FORMAT_RGBA8 \
			and output.get_size() == SIZE and output.get_format() == Image.FORMAT_RGBA8,
			"source and candidate are RGBA8 at 1254×1254")
		_check(TOOL.has_clear_margins(output), "candidate keeps at least 90 transparent pixels on all sides")
		_check(_same_alpha(source, output), "alpha and silhouette are unchanged pixel-for-pixel")
		_check(TOOL.red_boundary_count(output) < TOOL.red_boundary_count(source),
			"connected red contamination in the 1–3px alpha-edge band is reduced")
		_check(_only_selected_boundary_rgb_changed(source, output),
			"RGB edits stay inside connected red alpha-edge components and declared zones")
		_check(_normal_warm_colors_unchanged(source, output), "normal skin and gold colors remain exact")
		var expected: Dictionary = TOOL.repair_ink(source, attack1, attack3)
		_check(not expected.is_empty() and _same_pixels(output, expected.image),
			"candidate reproduces from unchanged contour and approved ink references")
	_check(_fixture_checks(attack1, attack3), "fixture confirms boundary repair, alpha preservation and warm-color protection")
	_check(TOOL.repair_ink(null, attack1, attack3).is_empty(), "null input returns a failure value")
	_check(TOOL.repair_ink(Image.create(64, 64, false, Image.FORMAT_RGBA8), attack1, attack3).is_empty(),
		"wrong canvas size returns a failure value")
	_check(_error_codes_are_stable(), "usage, source, reference, output and protected-input codes are distinct")
	_check(_cli_exit_code(["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--script", "res://tools/finalize_player_attack2_ink.gd", "--", "unexpected"]) == TOOL.CODE_USAGE,
		"unexpected CLI argument returns the documented usage code")
	var unchanged := true
	for i in range(protected_paths.size()):
		if snapshots[i] != _bytes(protected_paths[i]):
			unchanged = false
	_check(unchanged, "attack2 original, safe, clean, contour and approved references remain byte-for-byte unchanged")
	if failures.is_empty():
		print("player_attack2_ink_final_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack2_ink_final_smoke: " + failure)
		quit(1)

func _only_selected_boundary_rgb_changed(before: Image, after: Image) -> bool:
	var boundary: PackedByteArray = TOOL._alpha_edge_distance(before, 3)
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if a.is_equal_approx(b):
				continue
			var index := y * SIZE.x + x
			if boundary[index] == 0 or not TOOL._red_contour(a) or not _in_zone(x, y):
				return false
	return true

func _in_zone(x: int, y: int) -> bool:
	for zone_value in TOOL._zones():
		var zone: Rect2i = zone_value
		if zone.has_point(Vector2i(x, y)):
			return true
	return false

func _same_alpha(a: Image, b: Image) -> bool:
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if a.get_pixel(x, y).a != b.get_pixel(x, y).a:
				return false
	return true

func _normal_warm_colors_unchanged(before: Image, after: Image) -> bool:
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y)
			if _is_normal_warm(a) and not a.is_equal_approx(after.get_pixel(x, y)):
				return false
	return true

func _is_normal_warm(p: Color) -> bool:
	return TOOL._protected_warm(p)

func _fixture_checks(first: Image, second: Image) -> bool:
	var fixture := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	fixture.fill_rect(Rect2i(300, 200, 80, 70), Color("#553b2e"))
	fixture.set_pixel(300, 220, Color("#f51b16"))
	fixture.set_pixel(301, 220, Color("#f51b16"))
	fixture.fill_rect(Rect2i(410, 200, 25, 20), Color("#d6a53c"))
	fixture.set_pixel(410, 205, Color("#d6a53c"))
	fixture.fill_rect(Rect2i(460, 200, 24, 22), Color("#e9b28e"))
	var result: Dictionary = TOOL.repair_ink(fixture, first, second)
	if result.is_empty():
		return false
	var repaired: Image = result.image
	var before_red := TOOL.red_boundary_count(fixture)
	var after_red := TOOL.red_boundary_count(repaired)
	return before_red >= 2 and after_red < before_red \
		and repaired.get_pixel(300, 220).a == fixture.get_pixel(300, 220).a \
		and not TOOL._red_contour(repaired.get_pixel(300, 220)) \
		and repaired.get_pixel(410, 205).is_equal_approx(fixture.get_pixel(410, 205)) \
		and repaired.get_pixel(460, 205).is_equal_approx(fixture.get_pixel(460, 205))

func _error_codes_are_stable() -> bool:
	var values := [TOOL.CODE_USAGE, TOOL.CODE_SOURCE, TOOL.CODE_ATTACK1, TOOL.CODE_ATTACK3,
		TOOL.CODE_FOREST, TOOL.CODE_OUTPUT, TOOL.CODE_PROTECTED]
	var found := {}
	for code in values:
		if code <= 0 or found.has(code):
			return false
		found[code] = true
	return values.size() == 7

func _same_pixels(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	for y in range(SIZE.y):
		for x in range(SIZE.x):
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

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _cli_exit_code(arguments: PackedStringArray) -> int:
	var output_text: Array[String] = []
	return OS.execute(OS.get_executable_path(), arguments, output_text, true)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
