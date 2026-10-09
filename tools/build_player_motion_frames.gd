extends SceneTree
"""Extracts unapproved, normalized frames from operator-attested original PNG art."""

const METADATA_SCHEMA_VERSION := 1
const ALPHA_THRESHOLD := 0.0
const ANCHOR_ALPHA_RADIUS := 2
const MIN_DURATION := 0.001
const MAX_DURATION := 10.0
const METADATA_FILENAME := "motion_candidate.json"

func _initialize() -> void:
	call_deferred("_run_cli")

func _run_cli() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		_print_usage()
		quit(0)
		return
	if args.size() < 2:
		_print_usage()
		quit(2)
		return

	var result: Dictionary = {}
	if args[0] == "--sheet" and args.size() == 9 and args[8] == "--source-kind=original_art":
		var columns := int(args[3])
		var rows := int(args[4])
		var duration := float(args[5])
		var anchor := Vector2(float(args[6]), float(args[7]))
		result = extract_sheet(_resolve_path(args[1]), _resolve_path(args[2]), columns, rows, duration, anchor, true)
	elif args[0] == "--sequence" and args.size() == 7 and args[6] == "--source-kind=original_art":
		var duration := float(args[3])
		var anchor := Vector2(float(args[4]), float(args[5]))
		result = extract_sequence(_resolve_path(args[1]), _resolve_path(args[2]), duration, anchor, true)
	else:
		_print_usage()
		quit(2)
		return

	if not bool(result.get("ok", false)):
		printerr("player-motion-frames: %s" % str(result.get("error", "unknown failure")))
		quit(1)
		return
	print("player-motion-frames: wrote %d unapproved frames to %s" % [int(result["frame_count"]), str(result["output_dir"])])
	quit(0)

static func extract_sheet(input_path: String, output_dir: String, columns: int, rows: int, duration: float, support_anchor: Vector2, source_attested_original_art: bool) -> Dictionary:
	if columns <= 0 or rows <= 0:
		return _failure("sheet columns and rows must be positive integers")
	var loaded := _load_rgba_png(input_path)
	if not bool(loaded.get("ok", false)):
		return loaded
	var sheet: Image = loaded["image"]
	if sheet.get_width() % columns != 0 or sheet.get_height() % rows != 0:
		return _failure("sheet dimensions must divide evenly by the requested grid")
	var frame_size := Vector2i(sheet.get_width() / columns, sheet.get_height() / rows)
	if frame_size.x <= 0 or frame_size.y <= 0:
		return _failure("sheet cells must have non-zero dimensions")
	var images: Array[Image] = []
	var labels: Array[String] = []
	for row in range(rows):
		for column in range(columns):
			var frame := sheet.get_region(Rect2i(column * frame_size.x, row * frame_size.y, frame_size.x, frame_size.y))
			images.append(frame)
			labels.append("row_%02d_column_%02d" % [row + 1, column + 1])
	return build_candidate(images, labels, output_dir, duration, support_anchor, "transparent_png_sheet", source_attested_original_art)

static func extract_sequence(input_dir: String, output_dir: String, duration: float, support_anchor: Vector2, source_attested_original_art: bool) -> Dictionary:
	var files := _ordered_png_files(input_dir)
	if not bool(files.get("ok", false)):
		return files
	var images: Array[Image] = []
	var labels: Array[String] = []
	for filename in files["files"]:
		var loaded := _load_rgba_png(input_dir.path_join(str(filename)))
		if not bool(loaded.get("ok", false)):
			return loaded
		images.append(loaded["image"])
		labels.append(str(filename))
	return build_candidate(images, labels, output_dir, duration, support_anchor, "ordered_png_sequence", source_attested_original_art)

static func build_candidate(images: Array[Image], labels: Array[String], output_dir: String, duration: float, support_anchor: Vector2, source_format: String, source_attested_original_art: bool) -> Dictionary:
	if not source_attested_original_art:
		return _failure("operator must attest that inputs are original art, not a recording or screen capture")
	if images.is_empty() or images.size() != labels.size():
		return _failure("at least one image and a matching ordered label are required")
	if not is_finite(duration) or duration < MIN_DURATION or duration > MAX_DURATION:
		return _failure("duration must be finite and in range [0.001, 10] seconds")
	if not _valid_anchor(support_anchor):
		return _failure("support-foot anchor must be normalized to [0, 1] on both axes")
	var canonical_output := _canonical_path(output_dir)
	if canonical_output.is_empty() or _path_is_root(canonical_output):
		return _failure("output directory must be a non-root path")
	if DirAccess.dir_exists_absolute(canonical_output):
		var existing := DirAccess.get_files_at(canonical_output)
		var existing_dirs := DirAccess.get_directories_at(canonical_output)
		if not existing.is_empty() or not existing_dirs.is_empty():
			return _failure("output directory must be new or empty; existing candidate files are never overwritten")

	var canvas := Vector2i.ZERO
	var frame_records: Array[Dictionary] = []
	for index in range(images.size()):
		var image := images[index]
		if image == null or image.is_empty() or image.get_format() != Image.FORMAT_RGBA8:
			return _failure("frame %d is empty or is not decoded as 8-bit RGBA" % index)
		var bounds := alpha_bounds(image)
		if bounds.size.x <= 0 or bounds.size.y <= 0:
			return _failure("frame %d has no non-transparent alpha bounds" % index)
		var anchor_pixel := Vector2i(roundi(support_anchor.x * float(image.get_width() - 1)), roundi(support_anchor.y * float(image.get_height() - 1)))
		if not _anchor_hits_alpha(image, anchor_pixel):
			return _failure("frame %d support-foot anchor does not touch alpha within %d px" % [index, ANCHOR_ALPHA_RADIUS])
		canvas.x = maxi(canvas.x, image.get_width())
		canvas.y = maxi(canvas.y, image.get_height())
		frame_records.append({"source_size": Vector2i(image.get_width(), image.get_height()), "alpha_bounds": bounds, "source_anchor": anchor_pixel})
	if canvas.x <= 0 or canvas.y <= 0:
		return _failure("normalized canvas has invalid dimensions")

	var normalized: Array[Image] = []
	var target_anchor := Vector2i(roundi(support_anchor.x * float(canvas.x - 1)), roundi(support_anchor.y * float(canvas.y - 1)))
	for index in range(images.size()):
		var source := images[index]
		var record: Dictionary = frame_records[index]
		var source_anchor: Vector2i = record["source_anchor"]
		var offset := target_anchor - source_anchor
		var bounds: Rect2i = record["alpha_bounds"]
		var placed_bounds := Rect2i(bounds.position + offset, bounds.size)
		if placed_bounds.position.x < 0 or placed_bounds.position.y < 0 or placed_bounds.end.x > canvas.x or placed_bounds.end.y > canvas.y:
			return _failure("frame %d would clip its alpha bounds while aligning support-foot anchors" % index)
		var output := Image.create(canvas.x, canvas.y, false, Image.FORMAT_RGBA8)
		output.fill(Color(0, 0, 0, 0))
		output.blit_rect(source, Rect2i(Vector2i.ZERO, Vector2i(source.get_width(), source.get_height())), offset)
		normalized.append(output)
		record["normalized_alpha_bounds"] = placed_bounds
		record["normalization_offset"] = offset
		frame_records[index] = record

	var make_dir_error := DirAccess.make_dir_recursive_absolute(canonical_output)
	if make_dir_error != OK and not DirAccess.dir_exists_absolute(canonical_output):
		return _failure("could not create output directory: %s" % error_string(make_dir_error))
	var metadata_frames: Array[Dictionary] = []
	for index in range(normalized.size()):
		var filename := "frame_%04d.png" % index
		var save_error := normalized[index].save_png(canonical_output.path_join(filename))
		if save_error != OK:
			return _failure("could not save %s: %s" % [filename, error_string(save_error)])
		var record: Dictionary = frame_records[index]
		var bounds: Rect2i = record["alpha_bounds"]
		var normalized_bounds: Rect2i = record["normalized_alpha_bounds"]
		var source_size: Vector2i = record["source_size"]
		var source_anchor: Vector2i = record["source_anchor"]
		var offset: Vector2i = record["normalization_offset"]
		metadata_frames.append({
			"index": index,
			"source_label": labels[index],
			"output": filename,
			"duration_seconds": duration,
			"source_size": {"width": source_size.x, "height": source_size.y},
			"source_alpha_bounds": _rect_to_dict(bounds),
			"source_support_foot_anchor_px": {"x": source_anchor.x, "y": source_anchor.y},
			"normalization_offset_px": {"x": offset.x, "y": offset.y},
			"normalized_alpha_bounds": _rect_to_dict(normalized_bounds),
			"support_foot_anchor": {"x": support_anchor.x, "y": support_anchor.y}
		})
	var metadata := {
		"schema_version": METADATA_SCHEMA_VERSION,
		"artifact_type": "player_motion_frame_candidate",
		"approval_state": "unapproved",
		"source_format": source_format,
		"source_kind_attestation": "operator_attested_original_art",
		"frame_order": "row_major" if source_format == "transparent_png_sheet" else "ascending_contiguous_numeric_suffix",
		"canvas_size": {"width": canvas.x, "height": canvas.y},
		"support_foot_anchor": {"x": support_anchor.x, "y": support_anchor.y},
		"frames": metadata_frames,
		"promotion": {"manifest_modified": false, "reviewed_frame_allowlist_modified": false, "human_review_required": true}
	}
	var metadata_path := canonical_output.path_join(METADATA_FILENAME)
	var file := FileAccess.open(metadata_path, FileAccess.WRITE)
	if file == null:
		return _failure("could not create unapproved metadata: %s" % error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(metadata, "\t") + "\n")
	file.close()
	return {"ok": true, "output_dir": canonical_output, "frame_count": normalized.size(), "metadata_path": metadata_path, "metadata": metadata}

static func alpha_bounds(image: Image) -> Rect2i:
	if image == null or image.is_empty():
		return Rect2i()
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > ALPHA_THRESHOLD:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

static func _ordered_png_files(input_dir: String) -> Dictionary:
	if not DirAccess.dir_exists_absolute(input_dir):
		return _failure("sequence input directory does not exist: " + input_dir)
	var pngs: Array[String] = []
	for filename in DirAccess.get_files_at(input_dir):
		if filename.get_extension().to_lower() == "png":
			pngs.append(filename)
	if pngs.is_empty():
		return _failure("sequence input directory contains no PNG frames")
	var indexed: Array[Dictionary] = []
	for filename in pngs:
		var stem := filename.get_basename()
		var suffix := _trailing_number(stem)
		if suffix < 0:
			return _failure("each sequence PNG needs a numeric suffix: " + filename)
		indexed.append({"name": filename, "number": suffix})
	indexed.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["number"]) == int(b["number"]):
			return str(a["name"]) < str(b["name"])
		return int(a["number"]) < int(b["number"])
	)
	var previous := -1
	var ordered: Array[String] = []
	for item in indexed:
		var number := int(item["number"])
		if number == previous:
			return _failure("sequence PNG numeric suffixes must be unique")
		if previous >= 0 and number != previous + 1:
			return _failure("sequence PNG numeric suffixes must be contiguous; gap before %s" % str(item["name"]))
		previous = number
		ordered.append(str(item["name"]))
	return {"ok": true, "files": ordered}

static func _trailing_number(value: String) -> int:
	var index := value.length() - 1
	while index >= 0 and value.substr(index, 1).is_valid_int():
		index -= 1
	if index == value.length() - 1:
		return -1
	return value.substr(index + 1).to_int()

static func _load_rgba_png(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _failure("PNG not found: " + path)
	var bytes := FileAccess.get_file_as_bytes(path)
	if not _has_png_signature(bytes):
		return _failure("input is not a PNG file: " + path)
	var image := Image.new()
	var decode_error := image.load_png_from_buffer(bytes)
	if decode_error != OK or image.is_empty():
		return _failure("PNG decode failed for %s: %s" % [path, error_string(decode_error)])
	if image.get_format() != Image.FORMAT_RGBA8:
		return _failure("PNG must decode as RGBA8 with an alpha channel: " + path)
	return {"ok": true, "image": image}

static func _anchor_hits_alpha(image: Image, anchor: Vector2i) -> bool:
	for y in range(maxi(0, anchor.y - ANCHOR_ALPHA_RADIUS), mini(image.get_height(), anchor.y + ANCHOR_ALPHA_RADIUS + 1)):
		for x in range(maxi(0, anchor.x - ANCHOR_ALPHA_RADIUS), mini(image.get_width(), anchor.x + ANCHOR_ALPHA_RADIUS + 1)):
			if image.get_pixel(x, y).a > ALPHA_THRESHOLD:
				return true
	return false

static func _valid_anchor(anchor: Vector2) -> bool:
	return is_finite(anchor.x) and is_finite(anchor.y) and anchor.x >= 0.0 and anchor.x <= 1.0 and anchor.y >= 0.0 and anchor.y <= 1.0

static func _rect_to_dict(rect: Rect2i) -> Dictionary:
	return {"x": rect.position.x, "y": rect.position.y, "width": rect.size.x, "height": rect.size.y}

static func _has_png_signature(bytes: PackedByteArray) -> bool:
	var signature := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < signature.size():
		return false
	for index in range(signature.size()):
		if bytes[index] != signature[index]:
			return false
	return true

static func _canonical_path(path: String) -> String:
	var resolved := path
	if path.begins_with("res://") or path.begins_with("user://"):
		resolved = ProjectSettings.globalize_path(path)
	elif not path.is_absolute_path():
		resolved = ProjectSettings.globalize_path("res://" + path)
	return resolved.replace("\\", "/").simplify_path()

static func _path_is_root(path: String) -> bool:
	return path == "/" or path == "//" or path == "" or path.ends_with(":") or path.ends_with(":/")

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}

func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)

func _print_usage() -> void:
	print("사용법:")
	print("  godot --headless --path . --script res://tools/build_player_motion_frames.gd -- --sheet <input.png> <output_dir> <columns> <rows> <duration_sec> <support_x> <support_y> --source-kind=original_art")
	print("  godot --headless --path . --script res://tools/build_player_motion_frames.gd -- --sequence <input_dir> <output_dir> <duration_sec> <support_x> <support_y> --source-kind=original_art")
