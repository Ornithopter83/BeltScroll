extends SceneTree

const TARGET_SIZE := Vector2i(1254, 1254)
const SOURCE := "res://assets/art/player/elven_fighter_reference_v4_matte_v3_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_reference_v4_matte_v4_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v4_matte_v4_contact.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const PANEL := Vector2i(620, 410)
const REVIEW_SIZE := Vector2i(1280, 4 * 430 + 20)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --script res://tools/repair_player_color_halo.gd [입력 PNG 출력 PNG 비교 PNG]")
		quit(0)
		return
	if not args.is_empty() and args.size() != 3:
		printerr("입력 인수는 3개(입력 출력 비교)여야 합니다.")
		quit(2)
		return
	var input_path := _resolve(args[0] if args.size() == 3 else SOURCE)
	var output_path := _resolve(args[1] if args.size() == 3 else OUTPUT)
	var review_path := _resolve(args[2] if args.size() == 3 else REVIEW)
	var error := repair_file(input_path, output_path)
	if error == OK:
		error = build_comparison(input_path, output_path, review_path)
	if error != OK:
		printerr("player-color-halo 복구 실패: %s (%d)" % [error_string(error), error])
		quit(1)
		return
	print("player-color-halo: v4 후보 및 흰색·검정·체커보드·숲 배경 확대 비교본 생성 완료")
	quit(0)

static func repair_file(input_path: String, output_path: String) -> Error:
	if not FileAccess.file_exists(input_path):
		return ERR_FILE_NOT_FOUND
	if _canonical(input_path) == _canonical(output_path):
		return ERR_INVALID_PARAMETER
	var bytes := FileAccess.get_file_as_bytes(input_path)
	if not _has_png_signature(bytes):
		return ERR_FILE_UNRECOGNIZED
	var source := Image.new()
	var error := source.load_png_from_buffer(bytes)
	if error != OK or source.is_empty():
		return error if error != OK else ERR_FILE_CORRUPT
	if source.get_size() != TARGET_SIZE:
		return ERR_INVALID_DATA
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var processed := repair_image(source)
	var output: Image = processed["image"]
	var output_dir := output_path.get_base_dir()
	if not output_dir.is_empty() and not DirAccess.dir_exists_absolute(output_dir):
		error = DirAccess.make_dir_recursive_absolute(output_dir)
		if error != OK:
			return error
	return output.save_png(output_path)

# Retains alpha and geometry. Warm fringe pixels next to transparency are
# reconstructed from the closest supported opaque foreground color. This
# includes fully opaque fringe pixels left by earlier matte passes.
static func repair_image(source: Image) -> Dictionary:
	var output := source.duplicate()
	var changed := 0
	var bounds := _alpha_bounds(source)
	for y in range(maxi(1, bounds.position.y - 1), mini(source.get_height() - 1, bounds.end.y + 1)):
		for x in range(maxi(1, bounds.position.x - 1), mini(source.get_width() - 1, bounds.end.x + 1)):
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.0 or not _near_transparency(source, x, y, 6):
				continue
			var reference := _edge_inward_color(source, x, y, 6)
			if not bool(reference["valid"]):
				reference = _local_foreground_color(source, x, y, 5)
			if not bool(reference["valid"]):
				continue
			var clean: Color = reference["color"]
			var distance := _rgb_distance(pixel, clean)
			if not _is_warm_outlier(pixel, clean, distance):
				continue
			# Preserve texture while removing a strong spill; opaque fringe receives
			# a firm correction, and partial-alpha pixels a slightly stronger one.
			var strength := clampf(0.84 + (1.0 - pixel.a) * 0.12, 0.84, 0.96)
			output.set_pixel(x, y, Color(lerpf(pixel.r, clean.r, strength),
				lerpf(pixel.g, clean.g, strength), lerpf(pixel.b, clean.b, strength), pixel.a))
			changed += 1
	return {"image": output, "changed": changed}

static func _local_foreground_color(image: Image, x: int, y: int, radius: int) -> Dictionary:
	# Select a nearby color supported by a compact local cluster instead of a
	# broad average, which would blend across hair/skin/garment boundaries.
	var samples: Array[Dictionary] = []
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if nx == x and ny == y:
				continue
			var color := image.get_pixel(nx, ny)
			if color.a < 0.88:
				continue
			samples.append({"color": color, "distance": Vector2(float(nx - x), float(ny - y)).length()})
	if samples.size() < 2:
		return {"valid": false, "color": Color.TRANSPARENT}
	samples.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["distance"]) < float(b["distance"]))
	var nearest: Color = samples[0]["color"]
	var supported := 0
	var total_weight := 0.0
	var sum := Vector3.ZERO
	for sample in samples:
		var color: Color = sample["color"]
		var distance := float(sample["distance"])
		if _rgb_distance(color, nearest) <= 0.30:
			var weight := 1.0 / maxf(1.0, distance * distance)
			sum += Vector3(color.r, color.g, color.b) * weight
			total_weight += weight
			supported += 1
	if supported < 2 or total_weight <= 0.0 or float(supported) / float(samples.size()) < 0.18:
		return {"valid": false, "color": Color.TRANSPARENT}
	var rgb := sum / total_weight
	return {"valid": true, "color": Color(rgb.x, rgb.y, rgb.z, 1.0)}

static func _edge_inward_color(image: Image, x: int, y: int, radius: int) -> Dictionary:
	# Follow the nearest transparent-to-foreground direction. This avoids using a
	# multi-pixel red fringe as its own color reference at opaque silhouette edges.
	var nearest_distance := INF
	var transparent := Vector2i.ZERO
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if image.get_pixel(nx, ny).a >= 0.025:
				continue
			var distance := Vector2(float(nx - x), float(ny - y)).length()
			if distance < nearest_distance:
				nearest_distance = distance
				transparent = Vector2i(nx, ny)
	if nearest_distance == INF or nearest_distance <= 0.0:
		return {"valid": false, "color": Color.TRANSPARENT}
	var inward := Vector2(float(x - transparent.x), float(y - transparent.y)).normalized()
	for step in range(1, radius + 1):
		var nx := clampi(x + roundi(inward.x * step), 0, image.get_width() - 1)
		var ny := clampi(y + roundi(inward.y * step), 0, image.get_height() - 1)
		var sample := image.get_pixel(nx, ny)
		if sample.a >= 0.88 and not _is_extreme_warm(sample):
			return {"valid": true, "color": sample}
	return {"valid": false, "color": Color.TRANSPARENT}

static func _is_extreme_warm(color: Color) -> bool:
	var hue := color.h
	return color.s >= 0.72 and color.v >= 0.40 and (hue < 0.055 or hue > 0.965)

static func _is_warm_outlier(pixel: Color, local: Color, distance: float) -> bool:
	if pixel.s < 0.50 or pixel.v < 0.40 or distance < 0.22:
		return false
	var hue := pixel.h
	var red := hue < 0.055 or hue > 0.965
	var yellow := hue >= 0.075 and hue <= 0.17
	if not (red or yellow):
		return false
	# Strong red/yellow spill can form a compact cluster at an opaque edge. Do not
	# let that cluster vote itself clean: compare its channel intensity against
	# the neighboring foreground support before applying the normal hue guard.
	var strong_spill := red and pixel.s >= 0.72 and pixel.r >= local.r + 0.16
	strong_spill = strong_spill or (yellow and pixel.s >= 0.78
		and pixel.r >= local.r + 0.14 and pixel.g >= local.g + 0.10)
	if strong_spill:
		return true
	var hue_delta := absf(hue - local.h)
	hue_delta = minf(hue_delta, 1.0 - hue_delta)
	# Matching local warm support protects gold trim, lips, skin, and warm hair.
	if local.s > 0.22 and hue_delta < 0.065 and distance < 0.50:
		return false
	# Bright warm detail in an otherwise warm neighborhood remains protected if
	# the immediate color difference is modest (hair strand/skin highlight).
	if distance < 0.34 and local.s > 0.30:
		return false
	return true

static func is_warm_outlier(pixel: Color, local: Color) -> bool:
	return _is_warm_outlier(pixel, local, _rgb_distance(pixel, local))

static func _near_transparency(image: Image, x: int, y: int, radius: int) -> bool:
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if image.get_pixel(nx, ny).a < 0.025:
				return true
	return false

static func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

static func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.05:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func pollution_count(image: Image) -> int:
	var count := 0
	var bounds := _alpha_bounds(image)
	for y in range(maxi(1, bounds.position.y), mini(image.get_height() - 1, bounds.end.y)):
		for x in range(maxi(1, bounds.position.x), mini(image.get_width() - 1, bounds.end.x)):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0 or not _near_transparency(image, x, y, 6):
				continue
			var reference := _edge_inward_color(image, x, y, 6)
			if not bool(reference["valid"]):
				reference = _local_foreground_color(image, x, y, 5)
			if bool(reference["valid"]) and is_warm_outlier(pixel, reference["color"]):
				count += 1
	return count

static func build_comparison(before_path: String, after_path: String, output_path: String) -> Error:
	var before := _load_png(before_path)
	var after := _load_png(after_path)
	var forest := _load_png(_resolve(FOREST))
	if before == null or after == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if before.get_size() != TARGET_SIZE or after.get_size() != TARGET_SIZE:
		return ERR_INVALID_DATA
	var canvas := Image.create(REVIEW_SIZE.x, REVIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	for row in range(4):
		for side in range(2):
			var x := 20 + side * 640
			var y := 10 + row * 430
			var base := Image.create(PANEL.x, PANEL.y, false, Image.FORMAT_RGBA8)
			match row:
				0:
					base.fill(Color.WHITE)
				1:
					base.fill(Color("#080a0c"))
				2:
					_draw_checker(base)
				3:
					var bg := forest.duplicate()
					bg.resize(PANEL.x, PANEL.y, Image.INTERPOLATE_LANCZOS)
					base.blit_rect(bg, Rect2i(Vector2i.ZERO, PANEL), Vector2i.ZERO)
			var art: Image = before if side == 0 else after
			var crop := _head_and_shoulder_crop(art)
			var fitted := _fit(crop, PANEL - Vector2i(28, 28))
			base.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()),
				Vector2i((PANEL.x - fitted.get_width()) / 2, (PANEL.y - fitted.get_height()) / 2))
			canvas.blit_rect(base, Rect2i(Vector2i.ZERO, PANEL), Vector2i(x, y))
			canvas.fill_rect(Rect2i(x, y, PANEL.x, 5), Color("#e05b54") if side == 0 else Color("#69b8a2"))
	var directory := output_path.get_base_dir()
	if not directory.is_empty() and not DirAccess.dir_exists_absolute(directory):
		var error := DirAccess.make_dir_recursive_absolute(directory)
		if error != OK:
			return error
	return canvas.save_png(output_path)

static func _head_and_shoulder_crop(image: Image) -> Image:
	var bounds := _alpha_bounds(image)
	# The original character is centered with generous canvas padding. This
	# normalized crop isolates ponytail, ear, face, and both shoulder edges.
	var rect := Rect2i(bounds.position.x + int(bounds.size.x * 0.05), bounds.position.y,
		int(bounds.size.x * 0.88), int(bounds.size.y * 0.43))
	return image.get_region(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())))

static func _fit(source: Image, target: Vector2i) -> Image:
	var scale := minf(float(target.x) / source.get_width(), float(target.y) / source.get_height())
	var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
	var result := source.duplicate()
	if result.get_size() != size:
		result.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return result

static func _draw_checker(image: Image) -> void:
	for y in range(0, image.get_height(), 24):
		for x in range(0, image.get_width(), 24):
			var color := Color("#3d4247") if ((x / 24) + (y / 24)) % 2 == 0 else Color("#292e33")
			image.fill_rect(Rect2i(x, y, mini(24, image.get_width() - x), mini(24, image.get_height() - y)), color)

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _has_png_signature(bytes: PackedByteArray) -> bool:
	var signature := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < signature.size():
		return false
	for index in range(signature.size()):
		if bytes[index] != signature[index]:
			return false
	return true

static func _canonical(path: String) -> String:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else (path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path))
	return resolved.replace("\\", "/").simplify_path().to_lower()

static func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
