extends SceneTree

const MATTE := preload("res://tools/refine_player_alpha_matte.gd")
const TARGET_SIZE := 1254
const MIN_MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v4_retouch_1254x1254.png")
	var temp_dir := ProjectSettings.globalize_path("res://temp/player_matte_smoke")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var output_path := temp_dir.path_join("candidate.png")
	var bad_path := temp_dir.path_join("bad.png")
	var missing_output := temp_dir.path_join("missing-output.png")
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	_check(source != null, "v4_retouch PNG decodes")
	_check(MATTE.refine_file(source_path, output_path) == OK, "matte candidate writes to a separate PNG")
	var candidate := _load_png(output_path)
	_check(_valid_canvas(candidate), "candidate is 1254x1254 RGBA, retains alpha, and has at least 90px margins")
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "v4_retouch source remains byte-for-byte unchanged")
	if source != null and candidate != null:
		_check(_same_alpha(source, candidate), "all alpha values and silhouette positions are unchanged")
		_check(_opaque_interior_pixels_unchanged(source, candidate), "opaque interior RGB remains unchanged")
		var source_pollution := _pollution_count(source)
		var candidate_pollution := _pollution_count(candidate)
		_check(source_pollution > candidate_pollution and candidate_pollution <= 10, "red/yellow alpha-edge pollution count falls to at most 10 (%d to %d)" % [source_pollution, candidate_pollution])
		print("Matte corrected pixels: %d; detected edge contaminants: %d -> %d" % [MATTE.refine_image(source)["changed"], source_pollution, candidate_pollution])

	var synthetic := _synthetic_edge()
	var processed: Dictionary = MATTE.refine_image(synthetic)
	var refined: Image = processed["image"]
	_check(int(processed["changed"]) > 0, "synthetic contaminated partial-alpha red edge is corrected")
	_check(_warm_outlier_score(refined, 99, 150) < _warm_outlier_score(synthetic, 99, 150), "synthetic edge color moves toward its local foreground reference")
	_check(is_equal_approx(refined.get_pixel(99, 150).a, synthetic.get_pixel(99, 150).a), "matte correction preserves edge alpha")
	_check(refined.get_pixel(110, 150).is_equal_approx(synthetic.get_pixel(110, 150)), "opaque gold ornament and interior color are preserved")
	_check(refined.get_pixel(101, 150).is_equal_approx(synthetic.get_pixel(101, 150)), "normal fully opaque edge neighbor is preserved")
	_check(refined.get_pixel(199, 150).is_equal_approx(synthetic.get_pixel(199, 150)), "normal partial-alpha gold trim is preserved")
	_check(refined.get_pixel(299, 150).is_equal_approx(synthetic.get_pixel(299, 150)), "normal partial-alpha hair highlight is preserved")
	_check(refined.get_pixel(399, 150).is_equal_approx(synthetic.get_pixel(399, 150)), "normal partial-alpha skin edge is preserved")

	_check(MATTE.refine_file(temp_dir.path_join("not-found.png"), missing_output) == ERR_FILE_NOT_FOUND, "missing input returns file-not-found")
	_check(not FileAccess.file_exists(missing_output), "missing input does not create output")
	var malformed := FileAccess.open(bad_path, FileAccess.WRITE)
	if malformed != null:
		malformed.store_buffer(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2]))
		malformed.close()
	_check(MATTE.refine_file(bad_path, missing_output) != OK, "malformed PNG returns an error")
	_check(MATTE.refine_file(source_path, source_path) == ERR_INVALID_PARAMETER, "same input and output path is rejected")
	var wrong_size := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var wrong_size_path := temp_dir.path_join("wrong-size.png")
	wrong_size.save_png(wrong_size_path)
	_check(MATTE.refine_file(wrong_size_path, missing_output) == ERR_INVALID_DATA, "incorrect canvas size returns invalid-data")
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "source remains byte-identical after invalid inputs")
	for path in [output_path, bad_path, wrong_size_path, missing_output]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)
	if failures.is_empty():
		print("player_matte_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_matte_smoke: " + failure)
		quit(1)

func _valid_canvas(image: Image) -> bool:
	if image == null or image.get_size() != Vector2i(TARGET_SIZE, TARGET_SIZE) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := MATTE._alpha_bounds(image)
	var right := TARGET_SIZE - bounds.end.x
	var bottom := TARGET_SIZE - bounds.end.y
	return bounds.size.x > 0 and bounds.size.y > 0 and mini(mini(bounds.position.x, bounds.position.y), mini(right, bottom)) >= MIN_MARGIN and image.get_pixel(0, 0).a == 0.0

func _same_alpha(first: Image, second: Image) -> bool:
	for y in range(TARGET_SIZE):
		for x in range(TARGET_SIZE):
			if first.get_pixel(x, y).a != second.get_pixel(x, y).a:
				return false
	return true

func _opaque_interior_pixels_unchanged(first: Image, second: Image) -> bool:
	for y in range(TARGET_SIZE):
		for x in range(TARGET_SIZE):
			var pixel := first.get_pixel(x, y)
			if pixel.a >= 0.985 and not MATTE._touches_transparency(first, x, y, 3) and not pixel.is_equal_approx(second.get_pixel(x, y)):
				return false
	return true

func _pollution_count(image: Image) -> int:
	var count := 0
	var bounds := MATTE._alpha_bounds(image)
	for y in range(maxi(1, bounds.position.y), mini(image.get_height() - 1, bounds.end.y)):
		for x in range(maxi(1, bounds.position.x), mini(image.get_width() - 1, bounds.end.x)):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0 or not MATTE._touches_transparency(image, x, y, 3):
				continue
			var reference := MATTE._local_foreground_color(image, x, y, 5)
			if bool(reference["valid"]) and MATTE._is_red_or_yellow_contaminant(pixel, reference["color"], Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(reference["color"].r, reference["color"].g, reference["color"].b))):
				count += 1
	return count

func _warm_outlier_score(image: Image, x: int, y: int) -> float:
	var pixel := image.get_pixel(x, y)
	var reference := MATTE._local_foreground_color(image, x, y, 5)
	return Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(reference["color"].r, reference["color"].g, reference["color"].b))

func _synthetic_edge() -> Image:
	var image := Image.create(TARGET_SIZE, TARGET_SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(100, 100, 40, 100), Color(0.12, 0.34, 0.38, 1.0))
	image.set_pixel(99, 150, Color(1.0, 0.01, 0.01, 0.62))
	image.set_pixel(110, 150, Color(0.98, 0.72, 0.12, 1.0))
	image.fill_rect(Rect2i(200, 100, 40, 100), Color(0.83, 0.57, 0.15, 1.0))
	image.set_pixel(199, 150, Color(0.83, 0.57, 0.15, 0.62))
	image.fill_rect(Rect2i(300, 100, 40, 100), Color(0.73, 0.49, 0.22, 1.0))
	image.set_pixel(299, 150, Color(0.73, 0.49, 0.22, 0.62))
	image.fill_rect(Rect2i(400, 100, 40, 100), Color(0.91, 0.57, 0.39, 1.0))
	image.set_pixel(399, 150, Color(0.91, 0.57, 0.39, 0.62))
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
