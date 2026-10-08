extends SceneTree

const TOOL := preload("res://tools/prepare_player_attack3.gd")
const SOURCE := "res://assets/art/player/elven_fighter_attack3_reference_v1_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack3_reference_v1_safe_1254x1254.png"
const V8_CLEAN := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack3_identity_gate.png"
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
	var reference := _load(ProjectSettings.globalize_path(V8_CLEAN))
	var review := _load(ProjectSettings.globalize_path(REVIEW))
	_check(source != null, "attack3 original PNG decodes")
	_check(safe != null, "safe candidate PNG decodes")
	_check(review != null, "four-background identity board and 192px v8 comparison decode")
	if review != null:
		_check(review.get_size() == Vector2i(1920, 2280), "review board has four backdrop rows and shared-foot-baseline comparison strip")
	if source != null and safe != null:
		_check(_valid_canvas(safe), "safe is RGBA 1254 square with 90px transparent minimum margins")
		_check(_same_pixels(safe, TOOL.normalize(source)), "safe image is only nondestructively normalized from original alpha/RGB pixels")
		_check(_alpha_is_preserved(source, safe), "normalization retains the full silhouette and source alpha coverage")
	if safe != null and reference != null:
		_check(_shared_foot_scale_and_baseline(safe, reference), "attack3 and v8 comparison figures use the same 192px foot scale and baseline")
	_check(source != null and FileAccess.get_file_as_bytes(source_path) == source_bytes,
		"attack3 source PNG remains byte-for-byte unchanged")
	_check(TOOL.normalize(null) == null, "null image returns the documented normalization failure value")
	_check(_failure_codes_are_stable(), "usage/source/reference/forest/output/mutation failure codes are distinct")
	_check(_cli_exit_code(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/prepare_player_attack3.gd", "--", "unexpected"]) == TOOL.CODE_USAGE,
		"unexpected command-line arguments return usage failure code")
	if failures.is_empty():
		print("player_attack3_art_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack3_art_smoke: " + failure)
		quit(1)

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != Vector2i(SIZE, SIZE) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := TOOL._alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.position.x < MIN_MARGIN or bounds.position.y < MIN_MARGIN:
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

func _alpha_is_preserved(source: Image, safe: Image) -> bool:
	var source_bounds := TOOL._alpha_bounds(source)
	var safe_bounds := TOOL._alpha_bounds(safe)
	if source_bounds.size.x <= 0 or safe_bounds.size.x <= 0:
		return false
	var source_has_partial_alpha := false
	var safe_has_partial_alpha := false
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var alpha := source.get_pixel(x, y).a
			if alpha > 0.0 and alpha < 1.0:
				source_has_partial_alpha = true
	for y in range(safe.get_height()):
		for x in range(safe.get_width()):
			var alpha := safe.get_pixel(x, y).a
			if alpha > 0.0 and alpha < 1.0:
				safe_has_partial_alpha = true
	# Exact pixel equality to normalize(source) is checked separately. These checks
	# ensure alpha exists and antialiased edge transparency survives resampling.
	return source_has_partial_alpha and safe_has_partial_alpha and safe_bounds.size.x <= TOOL.CONTENT_LIMIT and safe_bounds.size.y <= TOOL.CONTENT_LIMIT

func _failure_codes_are_stable() -> bool:
	var codes := [TOOL.CODE_USAGE, TOOL.CODE_SOURCE, TOOL.CODE_REFERENCE, TOOL.CODE_FOREST, TOOL.CODE_OUTPUT, TOOL.CODE_MUTATED]
	var unique := {}
	for code in codes:
		if code <= 0 or unique.has(code):
			return false
		unique[code] = true
	return codes.size() == 6

func _shared_foot_scale_and_baseline(attack3: Image, v8: Image) -> bool:
	var attack_figure := TOOL.comparison_figure(attack3)
	var v8_figure := TOOL.comparison_figure(v8)
	if attack_figure == null or v8_figure == null:
		return false
	if attack_figure.get_height() != TOOL.COMPARISON_HEIGHT or v8_figure.get_height() != TOOL.COMPARISON_HEIGHT:
		return false
	var attack_bottom := TOOL.comparison_y(attack_figure) + TOOL._alpha_bounds(attack_figure).end.y
	var v8_bottom := TOOL.comparison_y(v8_figure) + TOOL._alpha_bounds(v8_figure).end.y
	return attack_bottom == v8_bottom and attack_bottom == TOOL.COMPARISON_TOP + TOOL.COMPARISON_HEIGHT - 1

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
