extends SceneTree

const TOOL := preload("res://tools/finalize_forest_raider_matte.gd")
const SIZE := 1254
const MIN_MARGIN := 90
const CLEAN := "res://assets/art/enemies/forest_raider_reference_v1_clean_1254x1254.png"
const ORIGINAL := "res://assets/art/enemies/forest_raider_reference_v1_1254x1254.png"
const SAFE := "res://assets/art/enemies/forest_raider_reference_v1_safe_1254x1254.png"
const REVIEW_SIZE := Vector2i(2560, 1820)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var temp_dir := ProjectSettings.globalize_path("res://temp/forest_raider_final_matte_smoke")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var output_path := temp_dir.path_join("candidate.png")
	var review_path := temp_dir.path_join("review.png")
	var malformed_path := temp_dir.path_join("malformed.png")
	var wrong_size_path := temp_dir.path_join("wrong_size.png")
	var invalid_output_path := temp_dir.path_join("must_not_exist.png")
	var original_bytes := FileAccess.get_file_as_bytes(ORIGINAL)
	var safe_bytes := FileAccess.get_file_as_bytes(SAFE)
	var clean_bytes := FileAccess.get_file_as_bytes(CLEAN)
	var source := _load_png(CLEAN)
	_check(source != null, "clean input PNG decodes")
	_check(TOOL.finalize_file(CLEAN, output_path) == OK, "matte candidate writes to a separate PNG")
	var candidate := _load_png(output_path)
	_check(_valid_canvas(candidate), "candidate is 1254x1254 RGBA with alpha and at least 90px margins")
	_check(FileAccess.get_file_as_bytes(ORIGINAL) == original_bytes, "original reference remains byte-for-byte unchanged")
	_check(FileAccess.get_file_as_bytes(SAFE) == safe_bytes, "safe reference remains byte-for-byte unchanged")
	_check(FileAccess.get_file_as_bytes(CLEAN) == clean_bytes, "clean input remains byte-for-byte unchanged")
	if source != null and candidate != null:
		_check(_same_alpha(source, candidate), "alpha values and silhouette locations are unchanged")
		_check(_changed_pixels(source, candidate) > 0, "bright edge contamination is recolored")
		var result: Dictionary = TOOL.finalize_image(source)
		_check(float(result["fringe_after"]) < float(result["fringe_before"]), "bright fringe mismatch score decreases")
		_check(_red_fabric_preserved(source, candidate), "red headband and flying cloth pixels remain unchanged")
		print("Recolored edge pixels: %d" % int(result["changed"]))
	_check(TOOL.build_review(CLEAN, output_path, "res://assets/art/stage/forest_ruins_v1_1920x1080.png", review_path) == OK, "white, black, checkerboard, Forest Ruins, detail, and 192px review is generated")
	var review := _load_png(review_path)
	_check(review != null and review.get_size() == REVIEW_SIZE, "review sheet has the expected 4-background by 4-detail layout")

	_check(TOOL.finalize_file(temp_dir.path_join("missing.png"), invalid_output_path) == ERR_FILE_NOT_FOUND, "missing source returns file-not-found")
	_check(not FileAccess.file_exists(invalid_output_path), "invalid input does not create output")
	var malformed := FileAccess.open(malformed_path, FileAccess.WRITE)
	if malformed != null:
		malformed.store_buffer(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2]))
		malformed.close()
	_check(TOOL.finalize_file(malformed_path, invalid_output_path) != OK, "malformed PNG is rejected")
	var wrong_size := Image.create(200, 200, false, Image.FORMAT_RGBA8)
	wrong_size.fill(Color(0, 0, 0, 0))
	wrong_size.save_png(wrong_size_path)
	_check(TOOL.finalize_file(wrong_size_path, invalid_output_path) == ERR_INVALID_DATA, "wrong canvas size is rejected")
	_check(TOOL.finalize_file(CLEAN, CLEAN) == ERR_INVALID_PARAMETER, "same input and output path is rejected")
	_check(FileAccess.get_file_as_bytes(ORIGINAL) == original_bytes and FileAccess.get_file_as_bytes(SAFE) == safe_bytes and FileAccess.get_file_as_bytes(CLEAN) == clean_bytes, "all source references remain unchanged after error cases")
	for path in [output_path, review_path, malformed_path, wrong_size_path, invalid_output_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)
	if failures.is_empty():
		print("forest_raider_final_matte_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("forest_raider_final_matte_smoke: " + failure)
		quit(1)

func _valid_canvas(image: Image) -> bool:
	if image == null or image.get_size() != Vector2i(SIZE, SIZE) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return false
	var right := SIZE - bounds.end.x
	var bottom := SIZE - bounds.end.y
	return mini(mini(bounds.position.x, bounds.position.y), mini(right, bottom)) >= MIN_MARGIN and image.get_pixel(0, 0).a == 0.0

func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := SIZE
	var min_y := SIZE
	var max_x := -1
	var max_y := -1
	for y in range(SIZE):
		for x in range(SIZE):
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= 0 else Rect2i()

func _same_alpha(first: Image, second: Image) -> bool:
	for y in range(SIZE):
		for x in range(SIZE):
			if first.get_pixel(x, y).a != second.get_pixel(x, y).a:
				return false
	return true

func _changed_pixels(first: Image, second: Image) -> int:
	var count := 0
	for y in range(SIZE):
		for x in range(SIZE):
			if not first.get_pixel(x, y).is_equal_approx(second.get_pixel(x, y)):
				count += 1
	return count

func _red_fabric_preserved(first: Image, second: Image) -> bool:
	var checked := 0
	for y in range(SIZE):
		for x in range(SIZE):
			var pixel := first.get_pixel(x, y)
			if TOOL._is_protected_red(pixel):
				checked += 1
				if not pixel.is_equal_approx(second.get_pixel(x, y)):
					return false
	return checked > 100

func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
