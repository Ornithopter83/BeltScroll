extends SceneTree

const SIZE := Vector2i(1254, 1254)
const SOURCE := "res://assets/art/player/elven_fighter_attack3_startup_v1_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack3_startup_safe_comparison.png"
const PRIOR := "res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png"
const CONTACT := "res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png"
const SAFE_MARGIN := 90
const RESAMPLE_GUARD := 12
const CONTENT_LIMIT := 1254 - 2 * (SAFE_MARGIN + RESAMPLE_GUARD)
const PANEL_W := 720
const PANEL_GAP := 24
const IMAGE_SIZE := 576 # 3x the 192px game sprite height.
const IMAGE_TOP := 112
const BASELINE := IMAGE_TOP + IMAGE_SIZE
const CANVAS := Vector2i(3 * PANEL_W + 4 * PANEL_GAP, 760)
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
	"W": ["10001", "10001", "10101", "10101", "10101", "10101", "01010"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	if source == null or source.get_size() != SIZE or source.get_format() != Image.FORMAT_RGBA8:
		_fail("startup source must be a valid 1254x1254 RGBA8 PNG")
		return
	var source_isolated_removed := _clear_isolated(source)
	var bounds := _alpha_bounds(source)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_fail("source contains no connected nonzero-alpha art")
		return
	var scale := minf(float(CONTENT_LIMIT) / bounds.size.x, float(CONTENT_LIMIT) / bounds.size.y)
	var fitted := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var filtered := _resize_premultiplied(source.get_region(bounds), fitted)
	if filtered == null:
		_fail("premultiplied-alpha resize failed")
		return
	var candidate := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	candidate.fill(Color(0, 0, 0, 0))
	var placement := Vector2i((SIZE.x - fitted.x) / 2, (SIZE.y - fitted.y) / 2)
	candidate.blit_rect(filtered, Rect2i(Vector2i.ZERO, fitted), placement)
	var resample_isolated_removed := _clear_isolated(candidate)
	if candidate.get_format() != Image.FORMAT_RGBA8:
		candidate.convert(Image.FORMAT_RGBA8)
	var output_full := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_full.get_base_dir())
	var save_error := candidate.save_png(output_full)
	if save_error != OK:
		_fail("safe candidate could not be saved: %s" % error_string(save_error))
		return
	if _bytes(SOURCE) != source_bytes:
		_fail("source PNG bytes changed during preparation")
		return
	if not _build_comparison():
		return
	var margins := _margins(candidate, _alpha_bounds(candidate))
	var src_anchors := _bottom_anchors(_load(SOURCE), 0.05)
	var safe_anchors := _bottom_anchors(candidate, 0.05)
	print("STARTUP SAFE | source_sha256=%s | uniform_scale=%.6f | fitted=%s | content_offset=%s | margins_LTRB=%s | isolated_pixels_removed_source=%d | isolated_pixels_removed_resample=%d | source_foot_anchors=%s | safe_foot_anchors=%s | anchor_delta_px=%s | source_bytes_preserved=true" % [
		_bytes_hash(source_bytes), scale, str(fitted), str(placement), str(margins), source_isolated_removed, resample_isolated_removed,
		str(src_anchors), str(safe_anchors), str(_anchor_deltas(src_anchors, safe_anchors))])
	if margins.x < SAFE_MARGIN or margins.y < SAFE_MARGIN or margins.z < SAFE_MARGIN or margins.w < SAFE_MARGIN:
		_fail("candidate does not have at least 90px nonzero-alpha inset on all sides")
		return
	quit(0)

func _build_comparison() -> bool:
	var paths := [PRIOR, OUTPUT, CONTACT]
	var labels := ["HIT 2 V6 SAFE", "HIT 3 STARTUP SAFE", "HIT 3 CONTACT"]
	var canvas := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_text(canvas, "ATTACK 2 TO 3 STARTUP SAFE REVIEW", Vector2i(24, 20), 3, Color("#f0e8d8"))
	_draw_text(canvas, "3X GAME DISPLAY - FOOT CONTACT ANCHORS MARKED", Vector2i(24, 58), 2, Color("#f1bd69"))
	for index in range(paths.size()):
		var frame := _load(paths[index])
		if frame == null or frame.get_size() != SIZE:
			_fail("comparison input missing or invalid: %s" % paths[index])
			return false
		var x := PANEL_GAP + index * (PANEL_W + PANEL_GAP)
		canvas.fill_rect(Rect2i(x, 88, PANEL_W, 624), Color("#252b32"))
		_draw_text(canvas, labels[index], Vector2i(x + 18, 92), 2, Color("#f0e8d8"))
		_draw_checker(canvas, Rect2i(x + 12, IMAGE_TOP, PANEL_W - 24, IMAGE_SIZE))
		var sprite := frame.duplicate()
		sprite.resize(IMAGE_SIZE, IMAGE_SIZE, Image.INTERPOLATE_LANCZOS)
		var image_x := x + (PANEL_W - IMAGE_SIZE) / 2
		canvas.blend_rect(sprite, Rect2i(Vector2i.ZERO, Vector2i(IMAGE_SIZE, IMAGE_SIZE)), Vector2i(image_x, IMAGE_TOP))
		var anchors := _bottom_anchors(frame, 0.05)
		_draw_contact_marks(canvas, anchors, image_x)
		print("REVIEW_FRAME %s | alpha>=5%% bounds=%s | bottom_anchors=%s" % [paths[index], str(_alpha_bounds(frame, 0.05)), str(anchors)])
	canvas.fill_rect(Rect2i(PANEL_GAP, BASELINE, CANVAS.x - 2 * PANEL_GAP, 3), Color("#f05c4f"))
	var target := ProjectSettings.globalize_path(REVIEW)
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	var error := canvas.save_png(target)
	if error != OK:
		_fail("comparison could not be saved: %s" % error_string(error))
		return false
	return true

func _draw_contact_marks(canvas: Image, anchors: Array[Vector2i], image_x: int) -> void:
	for anchor in anchors:
		var px := image_x + roundi(float(anchor.x) * IMAGE_SIZE / SIZE.x)
		var py := IMAGE_TOP + roundi(float(anchor.y) * IMAGE_SIZE / SIZE.y)
		canvas.fill_rect(Rect2i(px - 7, py - 2, 15, 5), Color("#fff36a"))
		canvas.fill_rect(Rect2i(px - 2, py - 7, 5, 15), Color("#fff36a"))

func _resize_premultiplied(source: Image, target_size: Vector2i) -> Image:
	var image := source.duplicate()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(p.r * p.a, p.g * p.a, p.b * p.a, p.a))
	image.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
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
			if image.get_pixel(x, y).a > 0.0:
				mask[y * w + x] = 1
	var removed := 0
	for y in range(h):
		for x in range(w):
			var index := y * w + x
			if mask[index] == 0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := x + ox
					var ny := y + oy
					if nx >= 0 and ny >= 0 and nx < w and ny < h and mask[ny * w + nx] != 0:
						neighbor = true
						break
				if neighbor:
					break
			if not neighbor:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				removed += 1
	return removed

func _load(path: String) -> Image:
	var bytes := _bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes) == OK and not image.is_empty() else null

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

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

func _margins(image: Image, bounds: Rect2i) -> Vector4i:
	return Vector4i(bounds.position.x, bounds.position.y, image.get_width() - bounds.end.x, image.get_height() - bounds.end.y)

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

func _anchor_deltas(before: Array[Vector2i], after: Array[Vector2i]) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for i in range(mini(before.size(), after.size())):
		result.append(after[i] - before[i])
	return result

func _bytes_hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return "hash_error"
	return context.finish().hex_encode()

func _draw_text(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	var cursor := origin.x
	for character in value:
		var glyph: Array = FONT.get(character, FONT[" "])
		for row in range(glyph.size()):
			for column in range(5):
				if glyph[row].substr(column, 1) == "1":
					image.fill_rect(Rect2i(cursor + column * scale, origin.y + row * scale, scale, scale), color)
		cursor += 6 * scale

func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 24):
		for x in range(rect.position.x, rect.end.x, 24):
			var even := (int((x - rect.position.x) / 24) + int((y - rect.position.y) / 24)) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(24, rect.end.x - x), mini(24, rect.end.y - y)), Color("#444a50") if even else Color("#30363c"))

func _fail(message: String) -> void:
	push_error("prepare_player_attack3_startup_safe: " + message)
	quit(1)
