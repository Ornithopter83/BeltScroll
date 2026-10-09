extends SceneTree

const SIZE := Vector2i(1254, 1254)
const GAME_SIZE := 192
const MIN_INSET := 90
const RESAMPLE_GUARD := 12
const MAX_CONTENT := Vector2i(SIZE.x - 2 * (MIN_INSET + RESAMPLE_GUARD), SIZE.y - 2 * (MIN_INSET + RESAMPLE_GUARD))
const SOURCE := "res://assets/art/player/elven_fighter_jump_rise_v1_candidate_1254x1254.png"
const IDLE := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_jump_rise_safe_comparison.png"
const PANEL_W := 720
const GAP := 24
const DISPLAY := GAME_SIZE * 3
const IMAGE_TOP := 112
const CANVAS := Vector2i(3 * PANEL_W + 4 * GAP, 760)
const PANELS := [IDLE, SOURCE, SAFE]
const LABELS := ["V8 IDLE", "JUMP SOURCE", "JUMP SAFE"]
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
	"W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"9": ["01110", "10001", "10001", "01111", "00001", "00010", "11100"]
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	var idle := _load(IDLE)
	if source == null or source.get_size() != SIZE or source.get_format() != Image.FORMAT_RGBA8:
		_fail("jump-rise source must be a 1254x1254 RGBA8 PNG")
		return
	if idle == null or idle.get_size() != SIZE:
		_fail("v8 idle reference must be a 1254x1254 PNG")
		return
	var original_bounds := _alpha_bounds(source)
	var working := source.duplicate()
	var source_specks := _clear_isolated(working)
	var bounds := _alpha_bounds(working)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_fail("jump-rise source has no connected visible artwork")
		return
	var scale := minf(float(MAX_CONTENT.x) / bounds.size.x, float(MAX_CONTENT.y) / bounds.size.y)
	var fitted := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var resized := _resize_premultiplied(working.get_region(bounds), fitted)
	if resized == null:
		_fail("premultiplied-alpha resampling failed")
		return
	var safe := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	safe.fill(Color(0, 0, 0, 0))
	var offset := (SIZE - fitted) / 2
	safe.blit_rect(resized, Rect2i(Vector2i.ZERO, fitted), offset)
	var resample_specks := _clear_isolated(safe)
	_zero_transparent_rgb(safe)
	var output_path := ProjectSettings.globalize_path(SAFE)
	DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
	var saved := safe.save_png(output_path)
	if saved != OK:
		_fail("could not save safe candidate: %s" % error_string(saved))
		return
	if _bytes(SOURCE) != source_bytes:
		_fail("jump-rise source bytes changed during preparation")
		return
	if not _build_review():
		return
	var margins := _margins(_alpha_bounds(safe))
	var idle_metrics := _game_metrics(idle, false)
	var source_metrics := _game_metrics(source, true)
	var safe_metrics := _game_metrics(safe, true)
	print("JUMP_RISE_SAFE sha256=%s source_bounds=%s source_isolated_removed=%d fit=%s scale=%.6f offset=%s safe_bounds=%s margins_LTRB=%s resample_isolated_removed=%d" % [_sha(source_bytes), str(original_bounds), source_specks, str(fitted), scale, str(offset), str(_alpha_bounds(safe)), str(margins), resample_specks])
	print("POSE_METRICS game_canvas=%dx%d silhouette_bounds_idle=%s source=%s safe=%s silhouette_height_idle=%d source=%d safe=%d torso_window_centroid_y_idle=%.2f source=%.2f safe=%.2f lower_body_alpha_centroid_y_idle=%.2f source=%.2f safe=%.2f bottom_anchors_idle=%s source=%s safe=%s jump_centroid_delta_from_idle=(%.2f,%.2f) safe_centroid_delta_from_source=(%.2f,%.2f)" % [GAME_SIZE, GAME_SIZE, str(idle_metrics.bounds), str(source_metrics.bounds), str(safe_metrics.bounds), idle_metrics.bounds.size.y, source_metrics.bounds.size.y, safe_metrics.bounds.size.y, idle_metrics.body_y, source_metrics.body_y, safe_metrics.body_y, idle_metrics.legs_y, source_metrics.legs_y, safe_metrics.legs_y, str(idle_metrics.anchors), str(source_metrics.anchors), str(safe_metrics.anchors), source_metrics.centroid.x - idle_metrics.centroid.x, source_metrics.centroid.y - idle_metrics.centroid.y, safe_metrics.centroid.x - source_metrics.centroid.x, safe_metrics.centroid.y - source_metrics.centroid.y])
	if margins.x < MIN_INSET or margins.y < MIN_INSET or margins.z < MIN_INSET or margins.w < MIN_INSET:
		_fail("safe candidate must have at least 90px nonzero-alpha margin on every side")
		return
	if not _transparent_border(safe) or _isolated_count(safe) != 0:
		_fail("safe candidate failed transparent-border or isolated-pixel check")
		return
	quit(0)

func _build_review() -> bool:
	var canvas := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_text(canvas, "JUMP RISE SAFE REVIEW", Vector2i(24, 18), 3, Color("#f0e8d8"))
	_draw_text(canvas, "192PX GAME CANVAS / 3X PREVIEW", Vector2i(24, 50), 2, Color("#f1bd69"))
	for i in range(PANELS.size()):
		var frame := _load(PANELS[i])
		if frame == null or frame.get_size() != SIZE:
			_fail("review source missing or invalid: %s" % PANELS[i])
			return false
		var panel_x := GAP + i * (PANEL_W + GAP)
		canvas.fill_rect(Rect2i(panel_x, 80, PANEL_W, 628), Color("#252b32"))
		_draw_text(canvas, LABELS[i], Vector2i(panel_x + 18, 84), 2, Color("#f0e8d8"))
		var image_x := panel_x + (PANEL_W - DISPLAY) / 2
		var game_canvas := Image.create(GAME_SIZE, GAME_SIZE, false, Image.FORMAT_RGBA8)
		game_canvas.fill(Color(0, 0, 0, 0))
		var art := frame.duplicate()
		art.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
		game_canvas.blend_rect(art, Rect2i(Vector2i.ZERO, Vector2i(GAME_SIZE, GAME_SIZE)), Vector2i.ZERO)
		var checker := Rect2i(image_x, IMAGE_TOP, DISPLAY, DISPLAY)
		_draw_checker(canvas, checker)
		game_canvas.resize(DISPLAY, DISPLAY, Image.INTERPOLATE_NEAREST)
		canvas.blend_rect(game_canvas, Rect2i(Vector2i.ZERO, Vector2i(DISPLAY, DISPLAY)), Vector2i(image_x, IMAGE_TOP))
		var metrics := _game_metrics(frame, i > 0)
		_draw_anchor(canvas, Vector2i(image_x, IMAGE_TOP), metrics.anchors)
		print("REVIEW %s bounds_192=%s torso_center_y=%.2f lower_body_alpha_centroid_y=%.2f centroid=(%.2f,%.2f) bottom_anchors=%s" % [LABELS[i], str(metrics.bounds), metrics.body_y, metrics.legs_y, metrics.centroid.x, metrics.centroid.y, str(metrics.anchors)])
	var output := ProjectSettings.globalize_path(REVIEW)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	var error := canvas.save_png(output)
	if error != OK:
		_fail("review image could not be saved: %s" % error_string(error))
		return false
	return true

func _game_metrics(source: Image, is_jump_pose: bool) -> Dictionary:
	var image := source.duplicate()
	image.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
	var bounds := _alpha_bounds(image, 0.05)
	# Narrow pose-specific vertical slices through the torso avoid counting arms.
	var torso := Rect2i(116, 57, 8, 55) if is_jump_pose else Rect2i(108, 59, 8, 55)
	var legs := Rect2i(int(GAME_SIZE * 0.20), int(GAME_SIZE * 0.52), int(GAME_SIZE * 0.64), int(GAME_SIZE * 0.46))
	return {"bounds": bounds, "body_y": _alpha_centroid(image, torso).y, "legs_y": _alpha_centroid(image, legs).y, "centroid": _alpha_centroid(image, Rect2i(0, 0, GAME_SIZE, GAME_SIZE)), "anchors": _bottom_anchors(image, 0.05)}

func _alpha_centroid(image: Image, rect: Rect2i) -> Vector2:
	var total := 0.0
	var weighted := Vector2.ZERO
	for y in range(maxi(0, rect.position.y), mini(image.get_height(), rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(image.get_width(), rect.end.x)):
			var a := image.get_pixel(x, y).a
			if a > 0.05:
				total += a
				weighted += Vector2(x, y) * a
	return weighted / total if total > 0.0 else Vector2.ZERO

func _bottom_anchors(image: Image, threshold: float) -> Array[Vector2i]:
	var bounds := _alpha_bounds(image, threshold)
	var anchors: Array[Vector2i] = []
	if bounds.size.x <= 0:
		return anchors
	var y := bounds.end.y - 1
	var start := -1
	for x in range(image.get_width() + 1):
		var active := x < image.get_width() and image.get_pixel(x, y).a >= threshold
		if active and start < 0:
			start = x
		elif not active and start >= 0:
			anchors.append(Vector2i((start + x - 1) / 2, y))
			start = -1
	return anchors

func _draw_anchor(canvas: Image, origin: Vector2i, anchors: Array[Vector2i]) -> void:
	for p in anchors:
		var x := origin.x + p.x * 3
		var y := origin.y + p.y * 3
		canvas.fill_rect(Rect2i(x - 7, y - 2, 15, 5), Color("#fff36a"))
		canvas.fill_rect(Rect2i(x - 2, y - 7, 5, 15), Color("#fff36a"))

func _resize_premultiplied(source: Image, target: Vector2i) -> Image:
	var image := source.duplicate()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(p.r * p.a, p.g * p.a, p.b * p.a, p.a))
	image.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p: Color = image.get_pixel(x, y)
			if p.a <= 0.00001:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
			else:
				image.set_pixel(x, y, Color(clampf(p.r / p.a, 0.0, 1.0), clampf(p.g / p.a, 0.0, 1.0), clampf(p.b / p.a, 0.0, 1.0), clampf(p.a, 0.0, 1.0)))
	return image

func _clear_isolated(image: Image) -> int:
	var w := image.get_width()
	var h := image.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in range(h):
		for x in range(w):
			mask[y * w + x] = 1 if image.get_pixel(x, y).a > 0.0 else 0
	var removed := 0
	for y in range(h):
		for x in range(w):
			var index := y * w + x
			if mask[index] == 0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < w and ny < h and mask[ny * w + nx] != 0:
						neighbor = true
			if not neighbor:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				removed += 1
	return removed

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _alpha_bounds(image: Image, threshold: float = 0.000001) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= threshold:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _margins(b: Rect2i) -> Vector4i:
	return Vector4i(b.position.x, b.position.y, SIZE.x - b.end.x, SIZE.y - b.end.y)

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, image.get_height() - 1).a != 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(image.get_width() - 1, y).a != 0.0:
			return false
	return true

func _zero_transparent_rgb(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a == 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

func _draw_checker(canvas: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 24):
		for x in range(rect.position.x, rect.end.x, 24):
			var even := (int((x - rect.position.x) / 24) + int((y - rect.position.y) / 24)) % 2 == 0
			canvas.fill_rect(Rect2i(x, y, mini(24, rect.end.x - x), mini(24, rect.end.y - y)), Color("#444a50") if even else Color("#30363c"))

func _draw_text(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	var cursor := origin.x
	for c in value:
		var glyph: Array = FONT.get(c, FONT[" "])
		for y in range(glyph.size()):
			for x in range(5):
				if glyph[y].substr(x, 1) == "1":
					image.fill_rect(Rect2i(cursor + x * scale, origin.y + y * scale, scale, scale), color)
		cursor += scale * 6

func _load(path: String) -> Image:
	var data := _bytes(path)
	if data.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _sha(data: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()

func _fail(message: String) -> void:
	push_error("prepare_player_jump_rise_safe: " + message)
	quit(1)
