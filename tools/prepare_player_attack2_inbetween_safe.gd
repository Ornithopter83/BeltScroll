extends SceneTree

const SIZE := Vector2i(1254, 1254)
const SAFE_MARGIN := 90
const SOURCE := "res://assets/art/player/elven_fighter_attack2_inbetween_v1_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png"
const EDGE_ALPHA_LIMIT := 1.0 / 255.0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := FileAccess.get_file_as_bytes(SOURCE)
	if source_bytes.is_empty():
		_fail("source PNG is missing or empty")
		return
	var source := Image.new()
	if source.load_png_from_buffer(source_bytes) != OK or source.get_size() != SIZE:
		_fail("source must decode as a 1254x1254 PNG")
		return
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var protected_snapshot := source_bytes.duplicate()
	var working := source.duplicate()
	var removed_border_pixels := _clear_contaminated_border(working)
	var removed_detached_pixels := _clear_detached_low_alpha(working)
	var bounds := _alpha_bounds(working)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_fail("no visible character pixels remain after border cleanup")
		return
	var max_content := SIZE - Vector2i(SAFE_MARGIN * 2, SAFE_MARGIN * 2)
	var scale := minf(float(max_content.x) / bounds.size.x, float(max_content.y) / bounds.size.y)
	var fitted_size := Vector2i(roundi(bounds.size.x * scale), roundi(bounds.size.y * scale))
	if fitted_size.x > max_content.x or fitted_size.y > max_content.y:
		_fail("rounded content size exceeds the 90px safe inset")
		return
	var cropped: Image = working.get_region(bounds)
	cropped = _resize_premultiplied(cropped, fitted_size)
	if cropped == null:
		_fail("premultiplied-alpha resampling failed")
		return
	var candidate := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	candidate.fill(Color.TRANSPARENT)
	var position := Vector2i((SIZE.x - fitted_size.x) / 2, (SIZE.y - fitted_size.y) / 2)
	candidate.blit_rect(cropped, Rect2i(Vector2i.ZERO, fitted_size), position)
	var output_full := ProjectSettings.globalize_path(OUTPUT)
	var dir_error := DirAccess.make_dir_recursive_absolute(output_full.get_base_dir())
	if dir_error != OK and dir_error != ERR_ALREADY_EXISTS:
		_fail("could not create output directory: %s" % error_string(dir_error))
		return
	var save_error := candidate.save_png(output_full)
	if save_error != OK:
		_fail("candidate PNG could not be saved: %s" % error_string(save_error))
		return
	var result_bounds := _alpha_bounds(candidate)
	var margins := _margins(result_bounds)
	var anchor := _foot_anchor(candidate)
	print("attack2_inbetween_safe prepared | source=%s | removed_border_pixels=%d | removed_detached_low_alpha_pixels=%d | crop=%s | scale=%.6f | content=%s | margins L/T/R/B=%d/%d/%d/%d | foot_anchor=%s | source_bytes_preserved=%s" % [
		SOURCE, removed_border_pixels, removed_detached_pixels, str(bounds), scale, str(fitted_size), margins.x, margins.y,
		margins.z, margins.w, str(anchor), str(FileAccess.get_file_as_bytes(SOURCE) == protected_snapshot)])
	quit(0)

func _clear_contaminated_border(image: Image) -> int:
	var changed := 0
	for x in range(SIZE.x):
		for y in [0, SIZE.y - 1]:
			if image.get_pixel(x, y).a > 0.0 and image.get_pixel(x, y).a <= EDGE_ALPHA_LIMIT:
				image.set_pixel(x, y, Color.TRANSPARENT)
				changed += 1
	for y in range(1, SIZE.y - 1):
		for x in [0, SIZE.x - 1]:
			if image.get_pixel(x, y).a > 0.0 and image.get_pixel(x, y).a <= EDGE_ALPHA_LIMIT:
				image.set_pixel(x, y, Color.TRANSPARENT)
				changed += 1
	return changed

func _clear_detached_low_alpha(image: Image) -> int:
	# Keep the actual antialiased contour, but remove stray alpha fragments and
	# RGB/alpha edge specks more than two pixels away from the >=5% art silhouette.
	var core := PackedByteArray()
	core.resize(SIZE.x * SIZE.y)
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a >= 0.05:
				core[y * SIZE.x + x] = 1
	var removed := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var touches_core := false
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					var nx := x + ox
					var ny := y + oy
					if nx >= 0 and ny >= 0 and nx < SIZE.x and ny < SIZE.y and core[ny * SIZE.x + nx] != 0:
						touches_core = true
						break
				if touches_core:
					break
			if not touches_core:
				image.set_pixel(x, y, Color.TRANSPARENT)
				removed += 1
	return removed

func _resize_premultiplied(source: Image, target_size: Vector2i) -> Image:
	if source == null or source.is_empty() or target_size.x <= 0 or target_size.y <= 0:
		return null
	var premultiplied := source.duplicate()
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			var p := source.get_pixel(x, y)
			premultiplied.set_pixel(x, y, Color(p.r * p.a, p.g * p.a, p.b * p.a, p.a))
	premultiplied.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	for y in range(target_size.y):
		for x in range(target_size.x):
			var p: Color = premultiplied.get_pixel(x, y)
			if p.a <= 0.00001:
				premultiplied.set_pixel(x, y, Color.TRANSPARENT)
			else:
				premultiplied.set_pixel(x, y, Color(clampf(p.r / p.a, 0.0, 1.0),
					clampf(p.g / p.a, 0.0, 1.0), clampf(p.b / p.a, 0.0, 1.0), p.a))
	return premultiplied

func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := SIZE.x
	var min_y := SIZE.y
	var max_x := -1
	var max_y := -1
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

func _margins(bounds: Rect2i) -> Vector4i:
	return Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)

func _foot_anchor(image: Image) -> Vector2i:
	var bounds := _alpha_bounds(image)
	var last_row_left := SIZE.x
	var last_row_right := -1
	for x in range(SIZE.x):
		if image.get_pixel(x, bounds.end.y - 1).a > 0.0:
			last_row_left = mini(last_row_left, x)
			last_row_right = maxi(last_row_right, x)
	return Vector2i((last_row_left + last_row_right) / 2, bounds.end.y - 1)

func _fail(message: String) -> void:
	push_error("prepare_player_attack2_inbetween_safe: " + message)
	quit(1)
