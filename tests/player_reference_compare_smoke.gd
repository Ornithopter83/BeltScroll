extends SceneTree

const NORMALIZER := preload("res://tools/normalize_player_art.gd")
const COMPARISON := preload("res://tools/build_player_reference_compare.gd")
const TARGET_SIZE := 1254
const MIN_MARGIN := 90
const ALIGNED_HEIGHT := 185

var failures: Array[String] = []
var cleanup_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	var temp_dir := ProjectSettings.globalize_path("res://temp/player_reference_compare_smoke")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var original := ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v4_1254x1254.png")
	var original_bytes := FileAccess.get_file_as_bytes(original)
	var temp_safe := temp_dir.path_join("v4_safe_candidate.png")
	var temp_compare := temp_dir.path_join("comparison.png")
	var cli_output := temp_dir.path_join("cli_missing_output.png")
	var output_blocker := temp_dir.path_join("not_a_directory")
	var blocked_output := output_blocker.path_join("comparison.png")
	cleanup_paths = [temp_safe, temp_compare, cli_output, output_blocker]

	_check(NORMALIZER.normalize_file(original, temp_safe) == OK, "existing player-normalize creates v4 candidate at a separate path")
	_check(FileAccess.get_file_as_bytes(original) == original_bytes, "v4 original remains byte-for-byte unchanged")
	_check(_inspect_safe(temp_safe, original), "generated v4 candidate is 1254 square RGBA PNG with alpha and at least 90px margins, preserving silhouette ratio")
	var official_safe := ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v4_safe_1254x1254.png")
	_check(_inspect_safe(official_safe, original), "v4 safe deliverable meets size, alpha, margin, and aspect-ratio requirements")
	_check(FileAccess.get_file_as_bytes(original) == original_bytes, "v4 original remains unchanged after safe-art checks")

	var v3 := _load_png(ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v3_safe_1254x1254.png"))
	var v4 := _load_png(official_safe)
	if v3 != null and v4 != null:
		var bounds3 := COMPARISON._alpha_bounds(v3)
		var bounds4 := COMPARISON._alpha_bounds(v4)
		var aligned3 := COMPARISON.aligned_silhouette(v3, bounds3, ALIGNED_HEIGHT)
		var aligned4 := COMPARISON.aligned_silhouette(v4, bounds4, ALIGNED_HEIGHT)
		_check(aligned3.get_height() == ALIGNED_HEIGHT and aligned4.get_height() == ALIGNED_HEIGHT, "comparison silhouettes are both exactly 185px tall")
		_check(COMPARISON.in_game_sprite_height() == 222, "game display preview applies the player camera zoom of 1.2 to 185px")
	else:
		_check(false, "v3 and v4 safe images can be decoded for comparison")

	var forest := ProjectSettings.globalize_path("res://assets/art/stage/forest_ruins_v1_1920x1080.png")
	_check(COMPARISON.build_comparison(
		ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v3_safe_1254x1254.png"),
		official_safe, forest, temp_compare) == OK, "comparison PNG is generated from v3/v4 safe images and forest ruins")
	_check(_inspect_comparison(temp_compare), "comparison PNG has expected canvas dimensions and opaque background composition")
	var generated_compare := _load_png(temp_compare)
	if generated_compare != null:
		var expected_baseline := Color("#f05c4f")
		_check(generated_compare.get_pixel(100, 390).is_equal_approx(expected_baseline)
			and generated_compare.get_pixel(1010, 390).is_equal_approx(expected_baseline), "both 185px silhouettes use the same rendered foot baseline")
	else:
		_check(false, "comparison baseline can be inspected")
	var delivered_compare := ProjectSettings.globalize_path("res://assets/art/review/player_v3_v4_comparison.png")
	_check(_inspect_comparison(delivered_compare), "review-only comparison deliverable exists and is valid")
	var blocker_file := FileAccess.open(output_blocker, FileAccess.WRITE)
	if blocker_file != null:
		blocker_file.store_string("file prevents output directory creation")
		blocker_file.close()
	_check(_cli_exit_code(["--headless", "--path", project_path, "--script", "res://tools/build_player_reference_compare.gd", "--", blocked_output]) == 1,
		"comparison CLI exits nonzero when output creation fails")
	_check(_cli_exit_code(["--headless", "--path", project_path, "--script", "res://tools/build_player_reference_compare.gd", "--", "one.png", "two.png"]) == 2, "comparison CLI returns usage error for invalid arguments")
	_check(FileAccess.get_file_as_bytes(original) == original_bytes, "v4 original remains byte-for-byte unchanged through comparison generation")

	for path in cleanup_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)
	if failures.is_empty():
		print("player_reference_compare_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_reference_compare_smoke: " + failure)
		quit(1)

func _inspect_safe(path: String, source_path: String) -> bool:
	var image := _load_png(path)
	var source := _load_png(source_path)
	if image == null or source == null or image.get_width() != TARGET_SIZE or image.get_height() != TARGET_SIZE:
		return false
	if image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := NORMALIZER._alpha_bounds(image)
	var source_bounds := NORMALIZER._alpha_bounds(source)
	if bounds.size.x <= 0 or bounds.size.y <= 0 or source_bounds.size.x <= 0 or source_bounds.size.y <= 0:
		return false
	var right_margin := TARGET_SIZE - bounds.end.x
	var bottom_margin := TARGET_SIZE - bounds.end.y
	if mini(mini(bounds.position.x, bounds.position.y), mini(right_margin, bottom_margin)) < MIN_MARGIN:
		return false
	if image.get_pixel(0, 0).a != 0.0 or image.get_pixel(TARGET_SIZE - 1, TARGET_SIZE - 1).a != 0.0:
		return false
	var source_ratio := float(source_bounds.size.x) / source_bounds.size.y
	var output_ratio := float(bounds.size.x) / bounds.size.y
	return absf(source_ratio - output_ratio) <= 0.003

func _inspect_comparison(path: String) -> bool:
	var image := _load_png(path)
	if image == null or image.get_width() != 1920 or image.get_height() != 2000:
		return false
	# An opaque canvas and forest panel corners confirm full-resolution composition.
	return image.get_pixel(0, 0).a == 1.0 and image.get_pixel(0, 920).a == 1.0 and image.get_pixel(1919, 1999).a == 1.0

func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return image

func _cli_exit_code(arguments: PackedStringArray) -> int:
	var output: Array[String] = []
	return OS.execute(OS.get_executable_path(), arguments, output, true)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
