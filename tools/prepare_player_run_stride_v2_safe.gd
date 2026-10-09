extends SceneTree

const SIZE := Vector2i(1254, 1254)
const SAFE_INSET := 90
const RESAMPLE_GUARD := 12
const MAX_CONTENT := Vector2i(SIZE.x - (SAFE_INSET + RESAMPLE_GUARD) * 2, SIZE.y - (SAFE_INSET + RESAMPLE_GUARD) * 2)
const SOURCE := "res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png"
const V8_IDLE := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_run_stride_pair_safe_comparison.png"
const PANEL_W := 720
const PANEL_GAP := 24
const DISPLAY := 576 # Three times the 192px game sprite canvas.
const IMAGE_TOP := 112
const BASELINE := IMAGE_TOP + DISPLAY
const CANVAS := Vector2i(3 * PANEL_W + 4 * PANEL_GAP, 760)
const V1_SAFE := "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png"
const PANELS := [V8_IDLE, V1_SAFE, OUTPUT]
const LABELS := ["V8 IDLE", "V1 RUN SAFE", "V2 RUN SAFE"]
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
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _read_bytes(SOURCE)
	var source := _load_image(SOURCE)
	var idle := _load_image(V8_IDLE)
	if source == null or source.get_size() != SIZE or source.get_format() != Image.FORMAT_RGBA8:
		_fail("run stride source must be a 1254x1254 RGBA8 PNG")
		return
	if idle == null or idle.get_size() != SIZE or idle.get_format() != Image.FORMAT_RGBA8:
		_fail("v8 idle reference must be a 1254x1254 RGBA8 PNG")
		return
	var source_original_bounds := _alpha_bounds(source)
	var working := source.duplicate()
	var removed_source_isolated := _clear_isolated_alpha(working)
	var source_bounds := _alpha_bounds(working)
	if source_bounds.size.x <= 0 or source_bounds.size.y <= 0:
		_fail("run stride source has no connected visible artwork")
		return
	var scale := minf(float(MAX_CONTENT.x) / source_bounds.size.x, float(MAX_CONTENT.y) / source_bounds.size.y)
	var fitted := Vector2i(maxi(1, roundi(source_bounds.size.x * scale)), maxi(1, roundi(source_bounds.size.y * scale)))
	var cropped: Image = working.get_region(source_bounds)
	var resized := _resize_premultiplied(cropped, fitted)
	if resized == null:
		_fail("premultiplied-alpha resampling failed")
		return
	var safe := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	safe.fill(Color(0, 0, 0, 0))
	var offset := (SIZE - fitted) / 2
	safe.blit_rect(resized, Rect2i(Vector2i.ZERO, fitted), offset)
	var removed_resample_isolated := _clear_isolated_alpha(safe)
	_zero_transparent_rgb(safe)
	if safe.get_format() != Image.FORMAT_RGBA8:
		safe.convert(Image.FORMAT_RGBA8)
	var output_full := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_full.get_base_dir())
	var save_error := safe.save_png(output_full)
	if save_error != OK:
		_fail("could not save safe candidate: %s" % error_string(save_error))
		return
	if _read_bytes(SOURCE) != source_bytes:
		_fail("original run stride source bytes changed during preparation")
		return
	if not _build_review():
		return
	var margins := _margins(_alpha_bounds(safe))
	var source_anchors := _bottom_anchors(source, 0.05)
	var safe_anchors := _bottom_anchors(safe, 0.05)
	var source_metrics := _metrics(source)
	var safe_metrics := _metrics(safe)
	var idle_metrics := _metrics(idle)
	print("RUN_STRIDE_SAFE source_sha256=%s source_bounds=%s isolated_source_removed=%d fitted=%s uniform_scale=%.6f offset=%s safe_bounds=%s margins_LTRB=%s isolated_resample_removed=%d source_anchors=%s safe_anchors=%s anchor_delta=%s body_aspect_v8=%.5f source=%.5f safe=%.5f height_ratio_source_vs_v8=%.5f safe_vs_v8=%.5f source_preserved=true" % [
		_hash(source_bytes), str(source_original_bounds), removed_source_isolated, str(fitted), scale, str(offset), str(_alpha_bounds(safe)), str(margins), removed_resample_isolated,
		str(source_anchors), str(safe_anchors), str(_anchor_delta(source_anchors, safe_anchors)), idle_metrics.x, source_metrics.x, safe_metrics.x, source_metrics.y / idle_metrics.y, safe_metrics.y / idle_metrics.y])
	if margins.x < SAFE_INSET or margins.y < SAFE_INSET or margins.z < SAFE_INSET or margins.w < SAFE_INSET:
		_fail("safe candidate must have at least 90px nonzero-alpha inset on all sides")
		return
	if not _transparent_border(safe) or _isolated_count(safe) != 0:
		_fail("safe candidate failed transparent border or isolated-pixel check")
		return
	quit(0)

func _build_review() -> bool:
	var canvas := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_ascii(canvas, "RUN STRIDE SAFE", Vector2i(24, 18), 3, Color("#f0e8d8"))
	_draw_ascii(canvas, "3X CANVAS - FOOT ANCHORS", Vector2i(24, 50), 2, Color("#f1bd69"))
	for index in range(PANELS.size()):
		var frame := _load_image(PANELS[index])
		if frame == null or frame.get_size() != SIZE:
			_fail("review image missing or invalid: %s" % PANELS[index])
			return false
		var panel_x := PANEL_GAP + index * (PANEL_W + PANEL_GAP)
		canvas.fill_rect(Rect2i(panel_x, 80, PANEL_W, 628), Color("#252b32"))
		_draw_checker(canvas, Rect2i(panel_x + 12, IMAGE_TOP, PANEL_W - 24, DISPLAY))
		_draw_ascii(canvas, LABELS[index], Vector2i(panel_x + 18, 84), 2, Color("#f0e8d8"))
		var sprite := frame.duplicate()
		sprite.resize(DISPLAY, DISPLAY, Image.INTERPOLATE_LANCZOS)
		var image_x := panel_x + (PANEL_W - DISPLAY) / 2
		canvas.blend_rect(sprite, Rect2i(Vector2i.ZERO, Vector2i(DISPLAY, DISPLAY)), Vector2i(image_x, IMAGE_TOP))
		var anchors := _bottom_anchors(frame, 0.05)
		_draw_anchors(canvas, anchors, image_x)
		print("RUN REVIEW %s alpha_bounds=%s bottom_foot_contacts=%s body_bounds_aspect=%.5f height_vs_v8=%.5f" % [PANELS[index], str(_alpha_bounds(frame, 0.05)), str(anchors), _metrics(frame).x, _metrics(frame).y / _metrics(_load_image(V8_IDLE)).y])
	canvas.fill_rect(Rect2i(PANEL_GAP, BASELINE, CANVAS.x - 2 * PANEL_GAP, 3), Color("#f05c4f"))
	var review_full := ProjectSettings.globalize_path(REVIEW)
	DirAccess.make_dir_recursive_absolute(review_full.get_base_dir())
	var error := canvas.save_png(review_full)
	if error != OK:
		_fail("comparison image could not be saved: %s" % error_string(error))
		return false
	return true

func _resize_premultiplied(source: Image, target: Vector2i) -> Image:
	if source.is_empty() or target.x <= 0 or target.y <= 0:
		return null
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
				image.set_pixel(x, y, Color(clampf(p.r / p.a, 0, 1), clampf(p.g / p.a, 0, 1), clampf(p.b / p.a, 0, 1), clampf(p.a, 0, 1)))
	return image

func _clear_isolated_alpha(image: Image) -> int:
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

func _zero_transparent_rgb(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a == 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

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

func _margins(bounds: Rect2i) -> Vector4i:
	return Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, image.get_height() - 1).a != 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(image.get_width() - 1, y).a != 0.0:
			return false
	return true

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a == 0.0:
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

func _anchor_delta(before: Array[Vector2i], after: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(mini(before.size(), after.size())):
		result.append(after[i] - before[i])
	return result

func _metrics(image: Image) -> Vector2:
	var bounds := _alpha_bounds(image, 0.05)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return Vector2.ZERO
	return Vector2(float(bounds.size.x) / bounds.size.y, float(bounds.size.y) / SIZE.y)

func _draw_anchors(canvas: Image, anchors: Array[Vector2i], image_x: int) -> void:
	for anchor in anchors:
		var px := image_x + roundi(float(anchor.x) * DISPLAY / SIZE.x)
		var py := IMAGE_TOP + roundi(float(anchor.y) * DISPLAY / SIZE.y)
		canvas.fill_rect(Rect2i(px - 7, py - 2, 15, 5), Color("#fff36a"))
		canvas.fill_rect(Rect2i(px - 2, py - 7, 5, 15), Color("#fff36a"))

func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 24):
		for x in range(rect.position.x, rect.end.x, 24):
			var even := (int((x - rect.position.x) / 24) + int((y - rect.position.y) / 24)) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(24, rect.end.x - x), mini(24, rect.end.y - y)), Color("#444a50") if even else Color("#30363c"))

func _draw_ascii(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	var cursor := origin.x
	for character in value:
		var glyph: Array = FONT.get(character, FONT[" "])
		for row in range(glyph.size()):
			for column in range(5):
				if glyph[row].substr(column, 1) == "1":
					image.fill_rect(Rect2i(cursor + column * scale, origin.y + row * scale, scale, scale), color)
		cursor += scale * 6

func _load_image(path: String) -> Image:
	var bytes := _read_bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _read_bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return "hash_error"
	return context.finish().hex_encode()

func _fail(message: String) -> void:
	push_error("prepare_player_run_stride_v2_safe: " + message)
	quit(1)
