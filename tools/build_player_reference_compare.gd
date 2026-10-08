extends SceneTree

const CANVAS_SIZE := Vector2i(1920, 2000)
const ALIGNED_HEIGHT := 160
const CAMERA_ZOOM := 1.2
const V3_SAFE := "res://assets/art/player/elven_fighter_reference_v3_safe_1254x1254.png"
const V4_SAFE := "res://assets/art/player/elven_fighter_reference_v4_safe_1254x1254.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const DEFAULT_OUTPUT := "res://assets/art/review/player_v3_v4_comparison.png"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if (args.size() != 0 and args.size() != 1 and args.size() != 4) or args.has("--help") or args.has("-h"):
		printerr("사용법: player-reference-compare [출력 PNG [v3 PNG v4 PNG 배경 PNG]]")
		quit(0 if args.has("--help") or args.has("-h") else 2)
		return
	var output_path := _resolve_path(args[0] if not args.is_empty() else DEFAULT_OUTPUT)
	var v3_path := _resolve_path(args[1] if args.size() == 4 else V3_SAFE)
	var v4_path := _resolve_path(args[2] if args.size() == 4 else V4_SAFE)
	var forest_path := _resolve_path(args[3] if args.size() == 4 else FOREST)
	var error := build_comparison(
		v3_path, v4_path, forest_path, output_path)
	if error != OK:
		printerr("player-reference-compare 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	print("player-reference-compare: 검수 이미지 생성 완료 (%s)" % output_path)
	quit(0)

static func build_comparison(v3_path: String, v4_path: String, forest_path: String, output_path: String) -> Error:
	var v3 := _load_png(v3_path)
	var v4 := _load_png(v4_path)
	var forest := _load_png(forest_path)
	if v3 == null or v4 == null or forest == null:
		return ERR_FILE_NOT_FOUND
	var v3_bounds := _alpha_bounds(v3)
	var v4_bounds := _alpha_bounds(v4)
	if v3_bounds.size.x <= 0 or v4_bounds.size.x <= 0:
		return ERR_INVALID_DATA

	var canvas := Image.create(CANVAS_SIZE.x, CANVAS_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	# Full silhouettes: 160 world px tall, with both foot bottoms on y=390.
	_draw_checker(canvas, Rect2i(80, 65, 840, 350))
	_draw_checker(canvas, Rect2i(1000, 65, 840, 350))
	var full3 := aligned_silhouette(v3, v3_bounds, ALIGNED_HEIGHT)
	var full4 := aligned_silhouette(v4, v4_bounds, ALIGNED_HEIGHT)
	canvas.blend_rect(full3, Rect2i(Vector2i.ZERO, full3.get_size()), Vector2i(500 - full3.get_width() / 2, 390 - ALIGNED_HEIGHT))
	canvas.blend_rect(full4, Rect2i(Vector2i.ZERO, full4.get_size()), Vector2i(1420 - full4.get_width() / 2, 390 - ALIGNED_HEIGHT))
	canvas.fill_rect(Rect2i(80, 390, 840, 3), Color("#f05c4f"))
	canvas.fill_rect(Rect2i(1000, 390, 840, 3), Color("#f05c4f"))

	# Paired close-ups use the same normalized crop on each safe image.
	var regions: Array[Rect2] = [
		Rect2(0.40, 0.00, 0.55, 0.38), # full head, face, and pointed ear
		Rect2(0.12, 0.27, 0.72, 0.27), # both hands and forearms
		Rect2(0.03, 0.53, 0.52, 0.30), # left leg and boot
		Rect2(0.46, 0.64, 0.52, 0.34), # right leg and boot
	]
	var tile_xs := [80, 535, 990, 1445]
	for index in range(regions.size()):
		var x: int = tile_xs[index]
		canvas.fill_rect(Rect2i(x, 445, 395, 8), Color("#78aeb6"))
		canvas.fill_rect(Rect2i(x, 659, 395, 8), Color("#d5a15d"))
		_draw_checker(canvas, Rect2i(x, 453, 395, 200))
		_draw_checker(canvas, Rect2i(x, 667, 395, 200))
		var crop3 := _crop_relative(v3, v3_bounds, regions[index])
		var crop4 := _crop_relative(v4, v4_bounds, regions[index])
		_fit_and_blend(canvas, crop3, Rect2i(x + 8, 461, 379, 184))
		_fit_and_blend(canvas, crop4, Rect2i(x + 8, 675, 379, 184))

	# The game's Camera2D zoom is 1.2, so a 160px world silhouette occupies
	# 192 screen pixels over the 1920x1080 stage.
	var stage := forest.duplicate()
	canvas.blit_rect(stage, Rect2i(Vector2i.ZERO, stage.get_size()), Vector2i(0, 920))
	var in_game_height := in_game_sprite_height()
	var display_sprite := _resize_image(full4, Vector2i(
		maxi(1, int(round(float(full4.get_width()) * in_game_height / ALIGNED_HEIGHT))), in_game_height))
	canvas.blend_rect(display_sprite, Rect2i(Vector2i.ZERO, display_sprite.get_size()),
		Vector2i(960 - display_sprite.get_width() / 2, 920 + 850 - in_game_height))
	canvas.fill_rect(Rect2i(0, 920, 1920, 2), Color("#f2d07d"))

	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		var dir_error := DirAccess.make_dir_recursive_absolute(output_dir)
		if dir_error != OK:
			return dir_error
	return canvas.save_png(output_path)

static func aligned_silhouette(source: Image, bounds: Rect2i, target_height: int) -> Image:
	var silhouette := source.get_region(bounds)
	var width := maxi(1, int(round(float(bounds.size.x) * target_height / bounds.size.y)))
	silhouette.resize(width, target_height, Image.INTERPOLATE_LANCZOS)
	return silhouette

static func in_game_sprite_height() -> int:
	return int(round(float(ALIGNED_HEIGHT) * CAMERA_ZOOM))

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			# Ignore sub-5% fringe pixels that disappear during downscaling.
			if image.get_pixel(x, y).a >= 0.05:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var x := bounds.position.x + int(floor(region.position.x * bounds.size.x))
	var y := bounds.position.y + int(floor(region.position.y * bounds.size.y))
	var right := bounds.position.x + int(ceil((region.position.x + region.size.x) * bounds.size.x))
	var bottom := bounds.position.y + int(ceil((region.position.y + region.size.y) * bounds.size.y))
	var rect := Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)

static func _fit_and_blend(destination: Image, source: Image, target: Rect2i) -> void:
	var scale := minf(float(target.size.x) / source.get_width(), float(target.size.y) / source.get_height())
	var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
	var fitted := _resize_image(source, size)
	var position := target.position + (target.size - size) / 2
	destination.blend_rect(fitted, Rect2i(Vector2i.ZERO, size), position)

static func _resize_image(source: Image, size: Vector2i) -> Image:
	var result := source.duplicate()
	result.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return result

static func _draw_checker(image: Image, rect: Rect2i) -> void:
	var tile := 24
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var shade := Color("#3d4247") if ((x - rect.position.x) / tile + (y - rect.position.y) / tile) % 2 == 0 else Color("#292e33")
			image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), shade)

func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)
