extends SceneTree

const TARGET_SIZE := 1254
const MIN_MARGIN := 90
const MAX_CONTENT_SIZE := TARGET_SIZE - MIN_MARGIN * 2

func _initialize() -> void:
	call_deferred("_run_cli")

func _run_cli() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 2 or args.has("--help") or args.has("-h"):
		printerr("사용법: player-normalize <입력 PNG> <출력 PNG>")
		quit(2 if not args.has("--help") and not args.has("-h") else 0)
		return
	var input_path := _resolve_path(args[0])
	var output_path := _resolve_path(args[1])
	var error := normalize_file(input_path, output_path)
	if error != OK:
		printerr("player-normalize 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	print("player-normalize: %s -> %s (%dx%d, 투명 여백 %dpx 이상)" % [input_path, output_path, TARGET_SIZE, TARGET_SIZE, MIN_MARGIN])
	quit(0)

static func normalize_file(input_path: String, output_path: String) -> Error:
	if not FileAccess.file_exists(input_path):
		return ERR_FILE_NOT_FOUND
	if _canonical_path(input_path) == _canonical_path(output_path):
		return ERR_INVALID_PARAMETER
	var bytes := FileAccess.get_file_as_bytes(input_path)
	if not _has_png_signature(bytes):
		return ERR_FILE_UNRECOGNIZED
	var image := Image.new()
	var decode_error := image.load_png_from_buffer(bytes)
	if decode_error != OK or image.is_empty():
		return decode_error if decode_error != OK else ERR_FILE_CORRUPT
	var bounds := _alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return ERR_INVALID_DATA

	var scale := minf(1.0, minf(float(MAX_CONTENT_SIZE) / bounds.size.x, float(MAX_CONTENT_SIZE) / bounds.size.y))
	var content_width := maxi(1, mini(MAX_CONTENT_SIZE, int(round(bounds.size.x * scale))))
	var content_height := maxi(1, mini(MAX_CONTENT_SIZE, int(round(bounds.size.y * scale))))
	var content := image.get_region(bounds)
	if content_width != bounds.size.x or content_height != bounds.size.y:
		content.resize(content_width, content_height, Image.INTERPOLATE_LANCZOS)

	var output := Image.create(TARGET_SIZE, TARGET_SIZE, false, Image.FORMAT_RGBA8)
	output.fill(Color(0, 0, 0, 0))
	var placement := Vector2i((TARGET_SIZE - content_width) / 2, (TARGET_SIZE - content_height) / 2)
	output.blit_rect(content, Rect2i(Vector2i.ZERO, Vector2i(content_width, content_height)), placement)
	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_error != OK:
			return dir_error
	return output.save_png(output_path)

static func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or max_y < min_y:
		return Rect2i()
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1)

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
	return resolved.replace("\\", "/").simplify_path().to_lower()

func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)
