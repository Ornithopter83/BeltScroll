extends SceneTree

const TARGET_WIDTH := 1920
const TARGET_HEIGHT := 1080

func _initialize() -> void:
	call_deferred("_run_cli")

func _run_cli() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args.has("--help") or args.has("-h"):
		printerr("사용법: stage-normalize <입력 PNG> <출력 PNG>")
		quit(2 if not args.has("--help") and not args.has("-h") else 0)
		return
	var input_path := _resolve_path(args[0])
	var output_path := _resolve_path(args[1])
	var error := normalize_file(input_path, output_path)
	if error != OK:
		printerr("stage-normalize 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	print("stage-normalize: %s -> %s (%dx%d, Lanczos)" % [input_path, output_path, TARGET_WIDTH, TARGET_HEIGHT])
	quit(0)

static func normalize_file(input_path: String, output_path: String) -> Error:
	if not FileAccess.file_exists(input_path):
		return ERR_FILE_NOT_FOUND
	var bytes := FileAccess.get_file_as_bytes(input_path)
	if not _has_png_signature(bytes):
		return ERR_FILE_UNRECOGNIZED
	var image := Image.new()
	var decode_error := image.load_png_from_buffer(bytes)
	if decode_error != OK or image.is_empty():
		return decode_error if decode_error != OK else ERR_FILE_CORRUPT
	var source_width := image.get_width()
	var source_height := image.get_height()
	if source_width <= 0 or source_height <= 0:
		return ERR_INVALID_DATA
	var crop_width := source_width
	var crop_height := source_height
	if source_width * TARGET_HEIGHT > source_height * TARGET_WIDTH:
		crop_width = maxi(1, int(floor(float(source_height * TARGET_WIDTH) / TARGET_HEIGHT)))
	else:
		crop_height = maxi(1, int(floor(float(source_width * TARGET_HEIGHT) / TARGET_WIDTH)))
	var crop_x := int((source_width - crop_width) / 2)
	var crop_y := int((source_height - crop_height) / 2)
	if crop_x != 0 or crop_y != 0 or crop_width != source_width or crop_height != source_height:
		image = image.get_region(Rect2i(crop_x, crop_y, crop_width, crop_height))
	image.resize(TARGET_WIDTH, TARGET_HEIGHT, Image.INTERPOLATE_LANCZOS)
	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_error != OK:
			return dir_error
	return image.save_png(output_path)

static func _has_png_signature(bytes: PackedByteArray) -> bool:
	var signature := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < signature.size():
		return false
	for index in range(signature.size()):
		if bytes[index] != signature[index]:
			return false
	return true

func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)
