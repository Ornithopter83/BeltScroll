extends SceneTree

const NORMALIZER := preload("res://tools/normalize_player_art.gd")
const TARGET_SIZE := 1254
const MIN_MARGIN := 90

var failures: Array[String] = []
var temp_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var temp_dir := ProjectSettings.globalize_path("res://temp")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var synthetic_input := temp_dir.path_join("player_normalize_smoke_input.png")
	var synthetic_output := temp_dir.path_join("player_normalize_smoke_output.png")
	var bad_input := temp_dir.path_join("player_normalize_smoke_bad.png")
	var cli_output := temp_dir.path_join("player_normalize_smoke_cli.png")
	temp_paths = [synthetic_input, synthetic_output, bad_input, cli_output]

	var synthetic := Image.create(1000, 1300, false, Image.FORMAT_RGBA8)
	synthetic.fill(Color(0, 0, 0, 0))
	synthetic.fill_rect(Rect2i(50, 40, 900, 1200), Color(0.25, 0.7, 0.4, 1.0))
	var save_error := synthetic.save_png(synthetic_input)
	_check(save_error == OK, "synthetic source PNG can be created")
	var source_bytes := FileAccess.get_file_as_bytes(synthetic_input)
	_check(NORMALIZER.normalize_file(synthetic_input, synthetic_output) == OK, "PNG direct decode, alpha bounds, aspect fit, and PNG save succeed")
	_check(FileAccess.get_file_as_bytes(synthetic_input) == source_bytes, "source PNG remains byte-for-byte unchanged")
	_check(_inspect_output(synthetic_output, 0.75), "synthetic output has expected dimensions, transparency margins, and aspect ratio")

	var original_path := ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v3_1254x1254.png")
	var original_bytes := FileAccess.get_file_as_bytes(original_path)
	var actual_candidate := temp_dir.path_join("player_normalize_smoke_v3_candidate.png")
	temp_paths.append(actual_candidate)
	_check(NORMALIZER.normalize_file(original_path, actual_candidate) == OK, "existing v3 source can be normalized to a separate candidate")
	_check(FileAccess.get_file_as_bytes(original_path) == original_bytes, "existing v3 source remains byte-for-byte unchanged")
	_check(_inspect_output(actual_candidate, -1.0), "v3 candidate has 1254 square dimensions and at least 90px transparent margins")
	var safe_art_path := ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v3_safe_1254x1254.png")
	_check(_inspect_output(safe_art_path, -1.0), "designated safe PNG has 1254 square dimensions and at least 90px transparent margins")

	_check(NORMALIZER.normalize_file(temp_dir.path_join("does_not_exist.png"), cli_output) == ERR_FILE_NOT_FOUND, "missing input returns a failure error")
	_check(not FileAccess.file_exists(cli_output), "missing input does not create an output")
	var invalid_file := FileAccess.open(bad_input, FileAccess.WRITE)
	invalid_file.store_buffer(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2]))
	invalid_file.close()
	_check(NORMALIZER.normalize_file(bad_input, cli_output) != OK, "malformed PNG is rejected")
	_check(not FileAccess.file_exists(cli_output), "malformed input does not create an output")
	_check(_cli_exit_code(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/normalize_player_art.gd", "--", temp_dir.path_join("missing_cli_input.png"), cli_output]) == 1, "CLI returns nonzero when normalization fails")
	_check(_cli_exit_code(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/normalize_player_art.gd"]) == 2, "CLI returns usage error code for invalid arguments")

	for path in temp_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if failures.is_empty():
		print("player_art_normalize_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_art_normalize_smoke: " + failure)
		quit(1)

func _inspect_output(path: String, expected_ratio: float) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var bytes := FileAccess.get_file_as_bytes(path)
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK:
		return false
	if image.get_width() != TARGET_SIZE or image.get_height() != TARGET_SIZE:
		return false
	var bounds := NORMALIZER._alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return false
	var left := bounds.position.x
	var top := bounds.position.y
	var right := TARGET_SIZE - bounds.position.x - bounds.size.x
	var bottom := TARGET_SIZE - bounds.position.y - bounds.size.y
	if mini(mini(left, right), mini(top, bottom)) < MIN_MARGIN:
		return false
	if image.get_pixel(0, 0).a != 0.0 or image.get_pixel(TARGET_SIZE - 1, TARGET_SIZE - 1).a != 0.0:
		return false
	if expected_ratio >= 0.0 and absf(float(bounds.size.x) / bounds.size.y - expected_ratio) > 0.002:
		return false
	return true

func _cli_exit_code(arguments: PackedStringArray) -> int:
	var output: Array[String] = []
	return OS.execute(OS.get_executable_path(), arguments, output, true)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
