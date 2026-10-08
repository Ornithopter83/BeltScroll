extends SceneTree

const TOOL := preload("res://tools/decontaminate_player_edge.gd")
const SIZE := 1254
const MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var temp := ProjectSettings.globalize_path("res://temp/player_edge_decontamination_smoke")
	DirAccess.make_dir_recursive_absolute(temp)
	var source_path := ProjectSettings.globalize_path("res://assets/art/player/elven_fighter_reference_v4_matte_v2_1254x1254.png")
	var out_path := temp.path_join("candidate.png")
	var review_path := temp.path_join("review.png")
	var bad_path := temp.path_join("bad.png")
	var absent_path := temp.path_join("absent.png")
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load(source_path)
	_check(source != null, "v4_matte_v2 input decodes")
	_check(TOOL.refine_file(source_path, out_path) == OK, "v3 is written to a separate candidate")
	var candidate := _load(out_path)
	_check(_valid(candidate), "candidate preserves 1254 canvas and at least 90px transparent margins")
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "v2 remains byte-for-byte unchanged")
	if source != null and candidate != null:
		_check(_same_alpha(source, candidate), "all alpha values and silhouette positions are unchanged")
		_check(_opaque_interior_unchanged(source, candidate), "interior RGB is byte-equivalent at opaque interior pixels")
		_check(int(TOOL.refine_image(source)["changed"]) > 0, "edge RGB or transparent fringe pixels are analyzed and corrected")
		print("v3 changed edge and transparent RGB pixels: %d" % int(TOOL.refine_image(source)["changed"]))
	_check(TOOL.build_comparison(source_path, out_path, review_path) == OK, "comparison sheet is generated")
	var review := _load(review_path)
	_check(review != null and review.get_width() == 1280 and review.get_height() == 2030, "comparison sheet includes four backgrounds and 192px before/after samples")

	var sample := _synthetic()
	var processed: Dictionary = TOOL.refine_image(sample)
	var refined: Image = processed["image"]
	_check(refined.get_pixel(49, 50).r < sample.get_pixel(49, 50).r, "partial-alpha saturated red edge is corrected")
	_check(refined.get_pixel(80, 50).r < sample.get_pixel(80, 50).r, "opaque boundary warm color outlier is corrected")
	_check(refined.get_pixel(60, 50).is_equal_approx(sample.get_pixel(60, 50)), "normal opaque gold ornament is protected")
	_check(refined.get_pixel(99, 50).is_equal_approx(sample.get_pixel(99, 50)), "normal partial-alpha gold edge is protected")
	_check(refined.get_pixel(119, 50).is_equal_approx(sample.get_pixel(119, 50)), "normal partial-alpha skin edge is protected")
	_check(refined.get_pixel(149, 50).is_equal_approx(sample.get_pixel(149, 50)), "normal partial-alpha hair edge is protected")
	_check(refined.get_pixel(49, 50).a == sample.get_pixel(49, 50).a, "edge correction preserves alpha")
	var extended := refined.get_pixel(48, 50)
	var edge := sample.get_pixel(49, 50)
	_check(extended.a == 0.0 and is_equal_approx(extended.r, edge.r) and is_equal_approx(extended.g, edge.g) and is_equal_approx(extended.b, edge.b), "transparent exterior receives edge RGB while remaining transparent")

	_check(TOOL.refine_file(temp.path_join("missing.png"), absent_path) == ERR_FILE_NOT_FOUND, "missing source reports file-not-found")
	_check(not FileAccess.file_exists(absent_path), "missing source does not create output")
	var malformed := FileAccess.open(bad_path, FileAccess.WRITE)
	if malformed != null:
		malformed.store_buffer(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2]))
		malformed.close()
	_check(TOOL.refine_file(bad_path, absent_path) != OK, "malformed PNG reports an error")
	_check(TOOL.refine_file(source_path, source_path) == ERR_INVALID_PARAMETER, "same input/output path is rejected")
	var wrong := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	var wrong_path := temp.path_join("wrong.png")
	wrong.save_png(wrong_path)
	_check(TOOL.refine_file(wrong_path, absent_path) == ERR_INVALID_DATA, "wrong canvas size reports invalid-data")
	var blocker := temp.path_join("blocker")
	var blocker_file := FileAccess.open(blocker, FileAccess.WRITE)
	if blocker_file != null:
		blocker_file.store_string("file")
		blocker_file.close()
	_check(TOOL.refine_file(source_path, blocker.path_join("child.png")) != OK, "unwritable output path reports an error")
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "all error cases retain source bytes")
	if failures.is_empty():
		print("player_edge_decontamination_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures: push_error("player_edge_decontamination_smoke: " + failure)
		quit(1)

func _synthetic() -> Image:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(50, 20, 25, 80), Color(0.12, 0.34, 0.38, 1.0))
	image.set_pixel(49, 50, Color(1.0, 0.01, 0.01, 0.62))
	image.fill_rect(Rect2i(81, 20, 25, 80), Color(0.12, 0.34, 0.38, 1.0))
	image.set_pixel(80, 50, Color(1.0, 0.01, 0.01, 1.0))
	image.fill_rect(Rect2i(90, 20, 25, 80), Color(0.83, 0.57, 0.15, 1.0))
	image.set_pixel(89, 50, Color(0.83, 0.57, 0.15, 0.62))
	image.set_pixel(99, 50, Color(0.98, 0.72, 0.12, 1.0))
	image.fill_rect(Rect2i(120, 20, 25, 80), Color(0.83, 0.57, 0.15, 1.0))
	image.set_pixel(119, 50, Color(0.91, 0.57, 0.39, 0.62))
	image.fill_rect(Rect2i(150, 20, 25, 80), Color(0.73, 0.49, 0.22, 1.0))
	image.set_pixel(149, 50, Color(0.73, 0.49, 0.22, 0.62))
	return image

func _valid(image: Image) -> bool:
	if image == null or image.get_size() != Vector2i(SIZE, SIZE) or image.get_format() != Image.FORMAT_RGBA8: return false
	var bounds := _bounds(image)
	return bounds.size.x > 0 and mini(mini(bounds.position.x, bounds.position.y), mini(SIZE - bounds.end.x, SIZE - bounds.end.y)) >= MARGIN

func _bounds(image: Image) -> Rect2i:
	var min_x := SIZE
	var min_y := SIZE
	var max_x := -1
	var max_y := -1
	for y in range(SIZE):
		for x in range(SIZE):
			if image.get_pixel(x, y).a >= 0.05:
				min_x = mini(min_x, x); min_y = mini(min_y, y)
				max_x = maxi(max_x, x); max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= 0 else Rect2i()

func _same_alpha(a: Image, b: Image) -> bool:
	for y in range(SIZE):
		for x in range(SIZE):
			if a.get_pixel(x, y).a != b.get_pixel(x, y).a: return false
	return true

func _opaque_interior_unchanged(a: Image, b: Image) -> bool:
	for y in range(2, SIZE - 2):
		for x in range(2, SIZE - 2):
			var p := a.get_pixel(x, y)
			if p.a >= 0.985 and not TOOL._near_transparency(a, x, y, 2) and not p.is_equal_approx(b.get_pixel(x, y)): return false
	return true

func _load(path: String) -> Image:
	if not FileAccess.file_exists(path): return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK: return null
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	return image

func _check(ok: bool, message: String) -> void:
	if ok: print("PASS: " + message)
	else: failures.append(message)
