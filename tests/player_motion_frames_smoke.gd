extends SceneTree

const BUILDER := preload("res://tools/build_player_motion_frames.gd")
const SUPPORT_ANCHOR := Vector2(0.5, 0.75)

var failures: Array[String] = []
var temp_paths: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var temp_dir := ProjectSettings.globalize_path("res://temp/player_motion_frames_smoke")
	if DirAccess.dir_exists_absolute(temp_dir):
		_remove_tree_contents(temp_dir)
		DirAccess.remove_absolute(temp_dir)
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var sheet_path := temp_dir.path_join("source_sheet.png")
	var sheet_output := temp_dir.path_join("sheet_candidate")
	var sequence_dir := temp_dir.path_join("source_sequence")
	var sequence_output := temp_dir.path_join("sequence_candidate")
	var gap_dir := temp_dir.path_join("gap_sequence")
	var duplicate_dir := temp_dir.path_join("duplicate_sequence")
	var invalid_output := temp_dir.path_join("should_not_exist")
	var empty_output := temp_dir.path_join("empty_alpha_candidate")
	temp_paths = [sheet_path]

	var sheet := Image.create(16, 8, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0, 0, 0, 0))
	sheet.fill_rect(Rect2i(2, 2, 4, 4), Color(0.2, 0.5, 0.8, 1.0))
	sheet.fill_rect(Rect2i(10, 2, 4, 4), Color(0.8, 0.4, 0.2, 1.0))
	_check(sheet.save_png(sheet_path) == OK, "synthetic transparent RGBA sheet is written")
	var source_bytes := FileAccess.get_file_as_bytes(sheet_path)
	var sheet_result := BUILDER.extract_sheet(sheet_path, sheet_output, 2, 1, 0.08, SUPPORT_ANCHOR, true)
	_check(bool(sheet_result.get("ok", false)), "sheet is split row-major into a candidate sequence")
	_check(_inspect_candidate(sheet_output, 0.08, Vector2i(8, 8),
		["row_01_column_01", "row_01_column_02"],
		[Vector2i(8, 8), Vector2i(8, 8)],
		[Rect2i(2, 2, 4, 4), Rect2i(2, 2, 4, 4)],
		[Rect2i(2, 2, 4, 4), Rect2i(2, 2, 4, 4)]), "sheet frames preserve row-major order, RGBA, alpha bounds, size, anchor, and duration")
	var sheet_frame_0 := Image.load_from_file(sheet_output.path_join("frame_0000.png"))
	var sheet_frame_1 := Image.load_from_file(sheet_output.path_join("frame_0001.png"))
	_check(_pixel_matches(sheet_frame_0, Vector2i(2, 2), Color(0.2, 0.5, 0.8, 1.0)) and _pixel_matches(sheet_frame_1, Vector2i(2, 2), Color(0.8, 0.4, 0.2, 1.0)), "sheet output pixels retain their row-major source order")
	_check(FileAccess.get_file_as_bytes(sheet_path) == source_bytes, "source sheet remains byte-for-byte unchanged")
	_check(not bool(BUILDER.extract_sheet(sheet_path, invalid_output, 3, 1, 0.08, SUPPORT_ANCHOR, true).get("ok", false)), "non-divisible sheet dimensions are rejected")
	_check(not bool(BUILDER.extract_sheet(sheet_path, invalid_output, 2, 1, 0.08, SUPPORT_ANCHOR, false).get("ok", false)), "missing operator source attestation is rejected")

	DirAccess.make_dir_recursive_absolute(sequence_dir)
	DirAccess.make_dir_recursive_absolute(gap_dir)
	DirAccess.make_dir_recursive_absolute(duplicate_dir)
	var first := _synthetic_frame(Color(0.2, 0.5, 0.8, 1.0))
	var second := Image.create(10, 8, false, Image.FORMAT_RGBA8)
	second.fill(Color(0.0, 0.0, 0.0, 0.0))
	second.fill_rect(Rect2i(4, 3, 3, 3), Color(0.8, 0.4, 0.2, 1.0))
	_check(first.save_png(sequence_dir.path_join("walk_0001.png")) == OK, "first ordered PNG fixture is written")
	_check(second.save_png(sequence_dir.path_join("walk_0002.png")) == OK, "second ordered PNG fixture is written")
	_check(first.save_png(duplicate_dir.path_join("walk_0001.png")) == OK, "duplicate suffix fixture one is written")
	_check(second.save_png(duplicate_dir.path_join("run_0001.png")) == OK, "duplicate suffix fixture two is written")
	_check(first.save_png(gap_dir.path_join("walk_0001.png")) == OK, "gap sequence first fixture is written")
	_check(second.save_png(gap_dir.path_join("walk_0003.png")) == OK, "gap sequence second fixture is written")
	var sequence_result := BUILDER.extract_sequence(sequence_dir, sequence_output, 0.1, SUPPORT_ANCHOR, true)
	_check(bool(sequence_result.get("ok", false)), "numbered PNG sequence is loaded and normalized")
	_check(_inspect_candidate(sequence_output, 0.1, Vector2i(10, 8),
		["walk_0001.png", "walk_0002.png"],
		[Vector2i(8, 8), Vector2i(10, 8)],
		[Rect2i(3, 3, 3, 3), Rect2i(4, 3, 3, 3)],
		[Rect2i(4, 3, 3, 3), Rect2i(4, 3, 3, 3)]), "sequence metadata verifies numeric order, RGBA, alpha bounds, shared size, aligned anchor, and duration")
	var sequence_frame_0 := Image.load_from_file(sequence_output.path_join("frame_0000.png"))
	var sequence_frame_1 := Image.load_from_file(sequence_output.path_join("frame_0001.png"))
	_check(_pixel_matches(sequence_frame_0, Vector2i(4, 3), Color(0.2, 0.5, 0.8, 1.0)) and _pixel_matches(sequence_frame_1, Vector2i(4, 3), Color(0.8, 0.4, 0.2, 1.0)), "sequence output pixels retain ascending numeric frame order")
	_check(not bool(BUILDER.extract_sequence(gap_dir, invalid_output, 0.1, SUPPORT_ANCHOR, true).get("ok", false)), "numeric sequence gaps are rejected")
	_check(not bool(BUILDER.extract_sequence(duplicate_dir, invalid_output, 0.1, SUPPORT_ANCHOR, true).get("ok", false)), "duplicate numeric suffixes are rejected")
	_check(not bool(BUILDER.extract_sequence(sequence_dir, invalid_output, 0.0, SUPPORT_ANCHOR, true).get("ok", false)), "invalid frame duration is rejected")
	_check(not bool(BUILDER.extract_sequence(sequence_dir, invalid_output, 0.1, Vector2(0.0, 0.0), true).get("ok", false)), "support anchor without nearby alpha is rejected")
	_check(not bool(BUILDER.extract_sequence(sequence_dir, sheet_output, 0.1, SUPPORT_ANCHOR, true).get("ok", false)), "non-empty output directories are never overwritten")
	var blank := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	blank.fill(Color(0.0, 0.0, 0.0, 0.0))
	_check(not bool(BUILDER.build_candidate([blank], ["blank"], empty_output, 0.1, SUPPORT_ANCHOR, "ordered_png_sequence", true).get("ok", false)), "fully transparent frames without alpha bounds are rejected")

	_remove_tree_contents(temp_dir)
	if failures.is_empty():
		print("player_motion_frames_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_motion_frames_smoke: " + failure)
		quit(1)

func _synthetic_frame(color: Color) -> Image:
	var image := Image.create(8, 8, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(Rect2i(3, 3, 3, 3), color)
	return image

func _inspect_candidate(output_dir: String, expected_duration: float, expected_canvas: Vector2i,
		expected_labels: Array, expected_source_sizes: Array, expected_source_bounds: Array, expected_output_bounds: Array) -> bool:
	var metadata_path := output_dir.path_join("motion_candidate.json")
	if not FileAccess.file_exists(metadata_path):
		return false
	var metadata: Variant = JSON.parse_string(FileAccess.get_file_as_string(metadata_path))
	if not metadata is Dictionary or metadata.get("approval_state") != "unapproved" or not metadata.get("promotion", {}).get("human_review_required", false):
		return false
	if metadata.get("promotion", {}).get("manifest_modified", true) or metadata.get("promotion", {}).get("reviewed_frame_allowlist_modified", true):
		return false
	if not metadata.get("frames") is Array or metadata["frames"].size() != expected_labels.size():
		return false
	var expected_size: Vector2i = Vector2i(metadata["canvas_size"]["width"], metadata["canvas_size"]["height"])
	if expected_size != expected_canvas:
		return false
	var anchor_pixel := Vector2i(roundi(SUPPORT_ANCHOR.x * float(expected_canvas.x - 1)), roundi(SUPPORT_ANCHOR.y * float(expected_canvas.y - 1)))
	for index in range(expected_labels.size()):
		var frame: Dictionary = metadata["frames"][index]
		if int(frame.get("index", -1)) != index or str(frame.get("source_label", "")) != str(expected_labels[index]) or absf(float(frame.get("duration_seconds", -1.0)) - expected_duration) > 0.00001:
			return false
		var source_size := Vector2i(int(frame["source_size"]["width"]), int(frame["source_size"]["height"]))
		if source_size != expected_source_sizes[index] or _metadata_rect(frame["source_alpha_bounds"]) != expected_source_bounds[index] or _metadata_rect(frame["normalized_alpha_bounds"]) != expected_output_bounds[index]:
			return false
		var source_anchor := Vector2i(int(frame["source_support_foot_anchor_px"]["x"]), int(frame["source_support_foot_anchor_px"]["y"]))
		var normalization_offset := Vector2i(int(frame["normalization_offset_px"]["x"]), int(frame["normalization_offset_px"]["y"]))
		if source_anchor + normalization_offset != anchor_pixel:
			return false
		var frame_path := output_dir.path_join(str(frame["output"]))
		var image := Image.new()
		if image.load(frame_path) != OK or image.get_format() != Image.FORMAT_RGBA8 or Vector2i(image.get_width(), image.get_height()) != expected_size:
			return false
		if BUILDER.alpha_bounds(image) != expected_output_bounds[index] or not BUILDER._anchor_hits_alpha(image, anchor_pixel):
			return false
		if absf(float(frame["support_foot_anchor"]["x"]) - SUPPORT_ANCHOR.x) > 0.00001 or absf(float(frame["support_foot_anchor"]["y"]) - SUPPORT_ANCHOR.y) > 0.00001:
			return false
	return true

func _metadata_rect(value: Dictionary) -> Rect2i:
	return Rect2i(int(value["x"]), int(value["y"]), int(value["width"]), int(value["height"]))

func _pixel_matches(image: Image, position: Vector2i, expected: Color) -> bool:
	if image == null or image.is_empty():
		return false
	var actual := image.get_pixel(position.x, position.y)
	return absf(actual.r - expected.r) < 0.005 and absf(actual.g - expected.g) < 0.005 and absf(actual.b - expected.b) < 0.005 and absf(actual.a - expected.a) < 0.005

func _remove_tree_contents(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for filename in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(filename))
	for dirname in DirAccess.get_directories_at(path):
		_remove_tree_contents(path.path_join(dirname))
		DirAccess.remove_absolute(path.path_join(dirname))

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
