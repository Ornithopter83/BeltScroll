extends SceneTree

const NORMALIZER := preload("res://tools/normalize_player_art.gd")
const REVIEW_BUILDER := preload("res://tools/build_forest_raider_review.gd")
const SOURCE := "res://assets/art/enemies/forest_raider_reference_v1_1254x1254.png"
const SAFE := "res://assets/art/enemies/forest_raider_reference_v1_safe_1254x1254.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const DELIVERED_REVIEW := "res://assets/art/review/forest_raider_reference_v1_contact.png"
const TARGET_SIZE := 1254
const MIN_MARGIN := 90
const DISPLAY_HEIGHT := 192

var failures: Array[String] = []
var cleanup_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var temp_dir := ProjectSettings.globalize_path("res://temp/forest_raider_art_smoke")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var safe_path := ProjectSettings.globalize_path(SAFE)
	var safe_bytes := FileAccess.get_file_as_bytes(safe_path)
	var candidate := temp_dir.path_join("raider_candidate.png")
	var compare := temp_dir.path_join("raider_compare.png")
	var missing_output := temp_dir.path_join("missing_output.png")
	var malformed := temp_dir.path_join("malformed.png")
	cleanup_paths = [candidate, compare, missing_output, malformed]

	_check(NORMALIZER.normalize_file(source_path, candidate) == OK, "existing Raider source normalizes into a separate 1254px safe candidate")
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "source original remains byte-for-byte unchanged during normalization")
	_check(_inspect_safe(candidate, source_path), "candidate preserves aspect ratio, has transparent alpha margins, and keeps whole silhouette inside bounds")
	_check(FileAccess.get_file_as_bytes(safe_path) == safe_bytes and _inspect_safe(safe_path, source_path), "delivered safe PNG is valid and source remains unchanged")

	var forest_path := ProjectSettings.globalize_path(FOREST)
	_check(REVIEW_BUILDER.build_review(source_path, candidate, forest_path, compare) == OK, "review builder creates safe image and inspection comparison")
	_check(_inspect_review(compare), "inspection PNG contains transparent detail area and 192px-high Forest Ruins comparison")
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "review generation leaves the source original byte-for-byte unchanged")

	_check(NORMALIZER.normalize_file(temp_dir.path_join("absent.png"), missing_output) == ERR_FILE_NOT_FOUND, "missing source is rejected")
	_check(not FileAccess.file_exists(missing_output), "missing source does not create output")
	var bad_file := FileAccess.open(malformed, FileAccess.WRITE)
	if bad_file != null:
		bad_file.store_buffer(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2]))
		bad_file.close()
	_check(NORMALIZER.normalize_file(malformed, missing_output) != OK, "malformed PNG input is rejected")
	_check(not FileAccess.file_exists(missing_output), "malformed PNG does not create output")
	_check(REVIEW_BUILDER.build_review(source_path, source_path, forest_path, compare) == ERR_INVALID_PARAMETER, "source cannot be selected as its own safe output")
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "invalid inputs do not modify the source original")

	for path in cleanup_paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)
	if failures.is_empty():
		print("forest_raider_art_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("forest_raider_art_smoke: " + failure)
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
	var margins := [bounds.position.x, bounds.position.y, TARGET_SIZE - bounds.end.x, TARGET_SIZE - bounds.end.y]
	for margin in margins:
		if margin < MIN_MARGIN:
			return false
	if image.get_pixel(0, 0).a != 0.0 or image.get_pixel(TARGET_SIZE - 1, TARGET_SIZE - 1).a != 0.0:
		return false
	var source_ratio := float(source_bounds.size.x) / source_bounds.size.y
	var safe_ratio := float(bounds.size.x) / bounds.size.y
	return absf(source_ratio - safe_ratio) <= 0.003

func _inspect_review(path: String) -> bool:
	var image := _load_png(path)
	if image == null or image.get_width() != 1920 or image.get_height() != 2200:
		return false
	if image.get_format() != Image.FORMAT_RGBA8 or image.get_pixel(0, 0).a != 1.0:
		return false
	var forest := _load_png(ProjectSettings.globalize_path(FOREST))
	if forest == null:
		return false
	var stage_y := 1120
	var stage_point := Vector2i(10, 10)
	if not image.get_pixel(stage_point.x, stage_y + stage_point.y).is_equal_approx(forest.get_pixel(stage_point.x, stage_point.y)):
		return false
	if REVIEW_BUILDER.DISPLAY_HEIGHT != DISPLAY_HEIGHT:
		return false
	var first_changed_row := -1
	var last_changed_row := -1
	for y in range(500, 900):
		var row_changed := false
		for x in range(700, 1220):
			if not image.get_pixel(x, stage_y + y).is_equal_approx(forest.get_pixel(x, y)):
				row_changed = true
				break
		if row_changed:
			if first_changed_row < 0:
				first_changed_row = y
			last_changed_row = y
	return first_changed_row >= 650 and first_changed_row <= 670 and last_changed_row >= 840 and last_changed_row <= 860

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
