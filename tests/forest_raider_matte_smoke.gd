extends SceneTree

const CLEANER := preload("res://tools/clean_forest_raider_matte.gd")
const TARGET_SIZE := 1254
const MIN_MARGIN := 90
const SOURCE := "res://assets/art/enemies/forest_raider_reference_v1_safe_1254x1254.png"
const OUTPUT := "res://assets/art/enemies/forest_raider_reference_v1_clean_1254x1254.png"
const REVIEW := "res://assets/art/review/forest_raider_clean_comparison.png"

var failures: Array[String] = []
var cleanup_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var temp_dir := ProjectSettings.globalize_path("res://temp/forest_raider_matte_smoke")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var output_path := temp_dir.path_join("clean.png")
	var malformed_path := temp_dir.path_join("malformed.png")
	var wrong_size_path := temp_dir.path_join("wrong_size.png")
	var no_output_path := temp_dir.path_join("must_not_exist.png")
	cleanup_paths = [output_path, malformed_path, wrong_size_path, no_output_path]
	var original_bytes := FileAccess.get_file_as_bytes(SOURCE)
	var original := _load_png(SOURCE)
	_check(original != null, "v1_safe input PNG decodes")
	_check(CLEANER.clean_file(SOURCE, output_path) == OK, "clean candidate writes to a separate PNG")
	_check(FileAccess.get_file_as_bytes(SOURCE) == original_bytes, "v1_safe source remains byte-for-byte unchanged")
	var candidate := _load_png(output_path)
	_check(_valid_canvas(candidate), "candidate is 1254x1254 RGBA with alpha and at least 90px margins")
	if original != null and candidate != null:
		_check(_same_alpha(original, candidate), "every alpha value is unchanged so no silhouette erosion occurs")
		var changed := _changed_pixel_count(original, candidate)
		_check(changed > 0, "edge color cleanup changes targeted pixels")
		var score: Dictionary = CLEANER.clean_image(original)
		_check(float(score["edge_after"]) < float(score["edge_before"]), "color fringe mismatch score decreases")
		_check(_red_headband_preserved(original, candidate), "red headband and its cloth ends remain pixel-identical")
		print("Cleaned edge pixel count: " + str(changed))

	var synthetic := _synthetic_edge_sample()
	var synthetic_result: Dictionary = CLEANER.clean_image(synthetic)
	var synthetic_image: Image = synthetic_result["image"]
	_check(int(synthetic_result["changed"]) > 0, "synthetic edge contamination is detected")
	_check(synthetic_image.get_pixel(99, 150).a == synthetic.get_pixel(99, 150).a, "correction keeps fringe alpha unchanged")
	_check(synthetic_image.get_pixel(110, 150).is_equal_approx(synthetic.get_pixel(110, 150)), "opaque interior color is preserved")
	_check(synthetic_image.get_pixel(120, 99).is_equal_approx(synthetic.get_pixel(120, 99)), "red cloth edge is protected")

	_check(CLEANER.clean_file(temp_dir.path_join("missing.png"), no_output_path) == ERR_FILE_NOT_FOUND, "missing source returns file-not-found")
	_check(not FileAccess.file_exists(no_output_path), "invalid source does not create output")
	var malformed := FileAccess.open(malformed_path, FileAccess.WRITE)
	if malformed != null:
		malformed.store_buffer(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2]))
		malformed.close()
	_check(CLEANER.clean_file(malformed_path, no_output_path) != OK, "malformed PNG is rejected")
	var wrong_size := Image.create(200, 200, false, Image.FORMAT_RGBA8)
	wrong_size.fill(Color(0, 0, 0, 0))
	wrong_size.save_png(wrong_size_path)
	_check(CLEANER.clean_file(wrong_size_path, no_output_path) == ERR_INVALID_DATA, "wrong-sized input is rejected")
	_check(CLEANER.clean_file(SOURCE, SOURCE) == ERR_INVALID_PARAMETER, "same input/output path is rejected")
	_check(FileAccess.get_file_as_bytes(SOURCE) == original_bytes, "source stays byte-identical after invalid input cases")

	for path in cleanup_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)
	if failures.is_empty():
		print("forest_raider_matte_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("forest_raider_matte_smoke: " + failure)
		quit(1)

func _valid_canvas(image: Image) -> bool:
	if image == null or image.get_width() != TARGET_SIZE or image.get_height() != TARGET_SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := CLEANER._alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return false
	var right := TARGET_SIZE - bounds.end.x
	var bottom := TARGET_SIZE - bounds.end.y
	return mini(mini(bounds.position.x, bounds.position.y), mini(right, bottom)) >= MIN_MARGIN and image.get_pixel(0, 0).a == 0.0

func _same_alpha(first: Image, second: Image) -> bool:
	for y in range(TARGET_SIZE):
		for x in range(TARGET_SIZE):
			if first.get_pixel(x, y).a != second.get_pixel(x, y).a:
				return false
	return true

func _changed_pixel_count(first: Image, second: Image) -> int:
	var count := 0
	for y in range(TARGET_SIZE):
		for x in range(TARGET_SIZE):
			if not first.get_pixel(x, y).is_equal_approx(second.get_pixel(x, y)):
				count += 1
	return count

func _red_headband_preserved(first: Image, second: Image) -> bool:
	var checked := 0
	for y in range(175, 295):
		for x in range(430, 820):
			var source_pixel := first.get_pixel(x, y)
			if CLEANER._is_headband_red(source_pixel) and source_pixel.a > 0.12:
				checked += 1
				if not source_pixel.is_equal_approx(second.get_pixel(x, y)):
					return false
	return checked > 100

func _synthetic_edge_sample() -> Image:
	var image := Image.create(TARGET_SIZE, TARGET_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(100, 100, 100, 100), Color(0.16, 0.25, 0.14, 1.0))
	image.set_pixel(99, 150, Color(0.95, 0.95, 0.05, 0.62))
	image.set_pixel(110, 150, Color(0.25, 0.34, 0.16, 1.0))
	image.fill_rect(Rect2i(120, 100, 20, 25), Color(0.72, 0.06, 0.04, 1.0))
	image.set_pixel(120, 99, Color(0.72, 0.06, 0.04, 0.62))
	return image

func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
