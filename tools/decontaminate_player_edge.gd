extends SceneTree

const TARGET_SIZE := Vector2i(1254, 1254)
const SOURCE := "res://assets/art/player/elven_fighter_reference_v4_matte_v2_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_reference_v4_matte_v3_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v4_matte_v3_contact.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --script res://tools/decontaminate_player_edge.gd [v2 입력 PNG v3 출력 PNG 비교 PNG]")
		quit(0)
		return
	if not args.is_empty() and args.size() != 3:
		printerr("입력 인수는 3개(입력 출력 비교)여야 합니다.")
		quit(2)
		return
	var source_path := _resolve(args[0] if args.size() == 3 else SOURCE)
	var output_path := _resolve(args[1] if args.size() == 3 else OUTPUT)
	var review_path := _resolve(args[2] if args.size() == 3 else REVIEW)
	var error := refine_file(source_path, output_path)
	if error == OK:
		error = build_comparison(source_path, output_path, review_path)
	if error != OK:
		printerr("player-edge-decontamination 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	print("player-edge-decontamination: v3 후보 및 흰색·검정·체커보드·Forest Ruins 전후, 192px 비교 생성 완료")
	quit(0)

static func refine_file(input_path: String, output_path: String) -> Error:
	if not FileAccess.file_exists(input_path):
		return ERR_FILE_NOT_FOUND
	if _canonical(input_path) == _canonical(output_path):
		return ERR_INVALID_PARAMETER
	var bytes := FileAccess.get_file_as_bytes(input_path)
	if not _png_signature(bytes):
		return ERR_FILE_UNRECOGNIZED
	var source := Image.new()
	var error := source.load_png_from_buffer(bytes)
	if error != OK or source.is_empty():
		return error if error != OK else ERR_FILE_CORRUPT
	if source.get_size() != TARGET_SIZE:
		return ERR_INVALID_DATA
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var result := refine_image(source)
	var dir := output_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		error = DirAccess.make_dir_recursive_absolute(dir)
		if error != OK:
			return error
	return (result["image"] as Image).save_png(output_path)

# Alpha and silhouette are immutable. Partially and fully opaque edge pixels are
# compared with the nearest opaque foreground support; only isolated warm outliers
# are recolored. Transparent RGB is extended from the nearest visible edge pixel
# for safe filtering at reduced sizes.
static func refine_image(source: Image) -> Dictionary:
	var output := source.duplicate()
	var changed := 0
	var bounds := _alpha_bounds(source)
	for y in range(maxi(1, bounds.position.y - 2), mini(source.get_height() - 1, bounds.end.y + 2)):
		for x in range(maxi(1, bounds.position.x - 2), mini(source.get_width() - 1, bounds.end.x + 2)):
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.0:
				var edge := _nearest_visible(source, x, y, 2)
				if bool(edge["valid"]):
					var color: Color = edge["color"]
					output.set_pixel(x, y, Color(color.r, color.g, color.b, pixel.a))
					changed += 1
				continue
			if not _near_transparency(source, x, y, 2):
				continue
			var reference := _nearest_opaque_support(source, x, y, 4)
			if not bool(reference["valid"]):
				continue
			var local: Color = reference["color"]
			var distance := _rgb_distance(pixel, local)
			if not _is_warm_outlier(pixel, local, distance):
				continue
			# Retain some source shading; stronger correction is used for lower alpha.
			var strength := clampf(0.72 + (1.0 - pixel.a) * 0.22, 0.72, 0.94)
			output.set_pixel(x, y, Color(lerpf(pixel.r, local.r, strength),
				lerpf(pixel.g, local.g, strength), lerpf(pixel.b, local.b, strength), pixel.a))
			changed += 1
	return {"image": output, "changed": changed}

static func _nearest_opaque_support(image: Image, x: int, y: int, radius: int) -> Dictionary:
	var best_distance := INF
	var best := Color.TRANSPARENT
	var count := 0
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if nx == x and ny == y:
				continue
			var sample := image.get_pixel(nx, ny)
			if sample.a < 0.90:
				continue
			var spatial := Vector2(float(nx - x), float(ny - y)).length()
			var score := spatial + (1.0 - sample.a) * 2.0
			if score < best_distance:
				best_distance = score
				best = sample
				count += 1
	return {"valid": count > 0, "color": best}

static func _nearest_visible(image: Image, x: int, y: int, radius: int) -> Dictionary:
	var best_distance := INF
	var best := Color.TRANSPARENT
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			var sample := image.get_pixel(nx, ny)
			if sample.a <= 0.0:
				continue
			var distance := Vector2(float(nx - x), float(ny - y)).length()
			if distance < best_distance:
				best_distance = distance
				best = sample
	return {"valid": best_distance < INF, "color": best}

static func _near_transparency(image: Image, x: int, y: int, radius: int) -> bool:
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if image.get_pixel(nx, ny).a < 0.02:
				return true
	return false

static func _is_warm_outlier(pixel: Color, local: Color, distance: float) -> bool:
	if pixel.s < 0.42 or distance < 0.27:
		return false
	var hue := pixel.h
	var warm := hue < 0.055 or hue > 0.96 or (hue >= 0.075 and hue <= 0.17)
	if not warm:
		return false
	# Warm skin, hair and gold edges remain when the local opaque color agrees.
	var hue_delta := absf(hue - local.h)
	hue_delta = minf(hue_delta, 1.0 - hue_delta)
	if local.s > 0.20 and hue_delta < 0.065 and distance < 0.48:
		return false
	return true

static func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

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
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func build_comparison(before_path: String, after_path: String, output_path: String) -> Error:
	var before := _load_png(before_path)
	var after := _load_png(after_path)
	var forest := _load_png(_resolve(FOREST))
	if before == null or after == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if before.get_size() != TARGET_SIZE or after.get_size() != TARGET_SIZE:
		return ERR_INVALID_DATA
	const panel_size := Vector2i(620, 420)
	const canvas_size := Vector2i(1280, 4 * 450 + 230)
	var canvas := Image.create(canvas_size.x, canvas_size.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var names := ["white", "black", "checker", "forest"]
	for row in range(4):
		for side in range(2):
			var x := 20 + side * 640
			var y := 15 + row * 450
			var base := Image.create(panel_size.x, panel_size.y, false, Image.FORMAT_RGBA8)
			match row:
				0:
					base.fill(Color.WHITE)
				1:
					base.fill(Color("#080a0c"))
				2:
					_draw_checker(base)
				3:
					var bg := forest.duplicate()
					bg.resize(panel_size.x, panel_size.y, Image.INTERPOLATE_LANCZOS)
					base.blit_rect(bg, Rect2i(Vector2i.ZERO, panel_size), Vector2i.ZERO)
			var candidate := before if side == 0 else after
			var display := candidate.duplicate()
			display.resize(panel_size.x, panel_size.y, Image.INTERPOLATE_LANCZOS)
			base.blend_rect(display, Rect2i(Vector2i.ZERO, panel_size), Vector2i.ZERO)
			canvas.blit_rect(base, Rect2i(Vector2i.ZERO, panel_size), Vector2i(x, y))
			canvas.fill_rect(Rect2i(x, y, panel_size.x, 4), Color("#e05b54") if side == 0 else Color("#69b8a2"))
			# Row colors and side order identify the panels; keep this machine-readable
			# cue in the script while preserving a clean image without font dependencies.
			if side == 0:
				canvas.fill_rect(Rect2i(8, y + 160, 6, 100), [Color.WHITE, Color("#30343a"), Color("#666b70"), Color("#788b62")][row])
	var thumb_y := 1815
	for side in range(2):
		var tile := Image.create(192, 192, false, Image.FORMAT_RGBA8)
		_draw_checker(tile)
		var small := (before if side == 0 else after).duplicate()
		small.resize(192, 192, Image.INTERPOLATE_LANCZOS)
		tile.blend_rect(small, Rect2i(Vector2i.ZERO, Vector2i(192, 192)), Vector2i.ZERO)
		canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, Vector2i(192, 192)), Vector2i(320 + side * 450, thumb_y))
	var dir := output_path.get_base_dir()
	if not dir.is_empty() and not DirAccess.dir_exists_absolute(dir):
		var error := DirAccess.make_dir_recursive_absolute(dir)
		if error != OK:
			return error
	return canvas.save_png(output_path)

static func _draw_checker(image: Image) -> void:
	var tile := 24
	for y in range(0, image.get_height(), tile):
		for x in range(0, image.get_width(), tile):
			var color := Color("#45494e") if ((x / tile) + (y / tile)) % 2 == 0 else Color("#292d32")
			image.fill_rect(Rect2i(x, y, mini(tile, image.get_width() - x), mini(tile, image.get_height() - y)), color)

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _png_signature(bytes: PackedByteArray) -> bool:
	var sig := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < sig.size(): return false
	for i in range(sig.size()):
		if bytes[i] != sig[i]: return false
	return true

static func _canonical(path: String) -> String:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else (path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path))
	return resolved.replace("\\", "/").simplify_path().to_lower()

static func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"): return ProjectSettings.globalize_path(path)
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
