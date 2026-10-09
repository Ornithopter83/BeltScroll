extends SceneTree

const SIZE := Vector2i(1254, 1254)
const SOURCE := "res://assets/art/player/elven_fighter_attack1_startup_v1_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack1_startup_v1_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack1_startup_safe_comparison.png"
const READY := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const CONTACT := "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png"
const MARGIN := 90
const FIT_LIMIT := 1074
const PANEL_W := 720
const GAP := 24
const DISPLAY := 576 # Three times the 192px game sprite height.
const TOP := 112
const BASELINE := TOP + DISPLAY
const CANVAS := Vector2i(3 * PANEL_W + 4 * GAP, 760)
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
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
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
	"Y": ["10001", "10001", "01010", "00100", "00100", "00100", "00100"],
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var original_bytes := _bytes(SOURCE)
	var original := _load(SOURCE)
	if original == null or original.get_size() != SIZE or original.get_format() != Image.FORMAT_RGBA8:
		_fail("startup source must be a valid 1254x1254 RGBA8 PNG")
		return
	var fit_source := original.duplicate()
	var isolated_before := _remove_isolated(fit_source)
	var original_bounds := _bounds(fit_source)
	if original_bounds.size.x <= 0 or original_bounds.size.y <= 0:
		_fail("startup source has no nonzero-alpha pixels")
		return
	var scale := minf(1.0, minf(float(FIT_LIMIT) / original_bounds.size.x, float(FIT_LIMIT) / original_bounds.size.y))
	var fitted := Vector2i(maxi(1, roundi(original_bounds.size.x * scale)), maxi(1, roundi(original_bounds.size.y * scale)))
	var crop: Image = fit_source.get_region(original_bounds)
	var normalized := _resize_premultiplied(crop, fitted)
	var safe := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	safe.fill(Color(0, 0, 0, 0))
	var offset := (SIZE - fitted) / 2
	safe.blit_rect(normalized, Rect2i(Vector2i.ZERO, fitted), offset)
	var bleed_removed := _clean_red_bleed(safe)
	var isolated_after := _remove_isolated(safe)
	if safe.get_format() != Image.FORMAT_RGBA8:
		safe.convert(Image.FORMAT_RGBA8)
	var save_path := ProjectSettings.globalize_path(SAFE)
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var error := safe.save_png(save_path)
	if error != OK:
		_fail("safe candidate could not be saved: %s" % error_string(error))
		return
	if _bytes(SOURCE) != original_bytes:
		_fail("source PNG bytes changed during preparation")
		return
	if not _build_review():
		return
	var bounds := _bounds(safe)
	var margins := _margins(bounds)
	var foot_before := _bottom_anchors(original, 0.05)
	var foot_after := _bottom_anchors(safe, 0.05)
	print("STARTUP_SAFE source_sha256=%s original_canvas=%s original_alpha_bounds=%s fitted=%s scale=%.6f offset=%s result_alpha_bounds=%s margins_LTRB=%s isolated_before=%d isolated_removed=%d red_bleed_pixels=%d foot_source=%s foot_safe=%s foot_delta=%s source_preserved=true" % [
		_hash(original_bytes), str(original.get_size()), str(original_bounds), str(fitted), scale, str(offset), str(bounds), str(margins), isolated_before, isolated_after, bleed_removed,
		str(foot_before), str(foot_after), str(_anchor_delta(foot_before, foot_after))])
	if margins.x < MARGIN or margins.y < MARGIN or margins.z < MARGIN or margins.w < MARGIN:
		_fail("safe candidate does not retain at least 90px nonzero-alpha inset on every side")
		return
	quit(0)

func _build_review() -> bool:
	var paths := [READY, SAFE, CONTACT]
	var labels := ["V8 READY", "HIT 1 STARTUP SAFE", "HIT 1 CONTACT APPROVED"]
	var canvas := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	for index in range(paths.size()):
		var frame := _load(paths[index])
		if frame == null or frame.get_size() != SIZE:
			_fail("review input missing or invalid: %s" % paths[index])
			return false
		var x := GAP + index * (PANEL_W + GAP)
		canvas.fill_rect(Rect2i(x, 88, PANEL_W, 624), Color("#252b32"))
		_draw_ascii(canvas, labels[index], Vector2i(x + 18, 92), 2, Color("#f0e8d8"))
		_draw_checker(canvas, Rect2i(x + 12, TOP, PANEL_W - 24, DISPLAY))
		var sprite := frame.duplicate()
		sprite.resize(DISPLAY, DISPLAY, Image.INTERPOLATE_LANCZOS)
		var image_x := x + (PANEL_W - DISPLAY) / 2
		canvas.blend_rect(sprite, Rect2i(Vector2i.ZERO, sprite.get_size()), Vector2i(image_x, TOP))
		var anchors := _bottom_anchors(frame, 0.05)
		_draw_anchors(canvas, anchors, image_x)
		print("REVIEW %s size=%s alpha_bounds=%s feet_alpha>=5%%=%s" % [paths[index], str(frame.get_size()), str(_bounds(frame, 0.05)), str(anchors)])
	canvas.fill_rect(Rect2i(GAP, BASELINE, CANVAS.x - 2 * GAP, 3), Color("#f05c4f"))
	var path := ProjectSettings.globalize_path(REVIEW)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var error := canvas.save_png(path)
	if error != OK:
		_fail("comparison image could not be saved: %s" % error_string(error))
		return false
	return true

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

# Remove only strongly saturated red pixels at the silhouette edge. Pixels
# connected to transparency lose alpha; enclosed specks receive local RGB.
func _clean_red_bleed(image: Image) -> int:
	var w := image.get_width()
	var h := image.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in range(2, h - 2):
		for x in range(2, w - 2):
			var p := image.get_pixel(x, y)
			if p.a < 0.08 or p.s < 0.64 or p.r - maxf(p.g, p.b) < 0.28:
				continue
			if _near_transparent(image, x, y, 3):
				mask[y * w + x] = 1
	var visited := PackedByteArray()
	visited.resize(w * h)
	var changed := 0
	for start in range(mask.size()):
		if mask[start] == 0 or visited[start] != 0:
			continue
		var points: Array[int] = [start]
		visited[start] = 1
		var head := 0
		while head < points.size():
			var index := points[head]
			head += 1
			var x := index % w
			var y := int(index / w)
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni := ny * w + nx
					if mask[ni] != 0 and visited[ni] == 0:
						visited[ni] = 1
						points.append(ni)
		for value in points:
			var px := value % w
			var py := int(value / w)
			var old := image.get_pixel(px, py)
			var neighbor := _nearby_supported_color(image, px, py, 4)
			if neighbor.a > 0.0:
				image.set_pixel(px, py, Color(neighbor.r, neighbor.g, neighbor.b, old.a))
				changed += 1
	return changed

func _nearby_supported_color(image: Image, x: int, y: int, radius: int) -> Color:
	var samples: Array[Color] = []
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if ox == 0 and oy == 0:
				continue
			var nx := x + ox
			var ny := y + oy
			if nx < 0 or ny < 0 or nx >= image.get_width() or ny >= image.get_height():
				continue
			var p := image.get_pixel(nx, ny)
			if p.a >= 0.65 and not (p.s > 0.64 and p.r - maxf(p.g, p.b) > 0.28):
				samples.append(p)
	if samples.size() < 3:
		return Color.TRANSPARENT
	samples.sort_custom(func(a: Color, b: Color) -> bool: return a.get_luminance() < b.get_luminance())
	return samples[samples.size() / 2]

func _near_transparent(image: Image, x: int, y: int, radius: int) -> bool:
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			var nx := x + ox
			var ny := y + oy
			if nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a <= 0.02:
				return true
	return false

func _remove_isolated(image: Image) -> int:
	var mask := PackedByteArray()
	mask.resize(image.get_width() * image.get_height())
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			mask[y * image.get_width() + x] = 1 if image.get_pixel(x, y).a > 0.0 else 0
	var removed := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var index := y * image.get_width() + x
			if mask[index] == 0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and mask[ny * image.get_width() + nx] != 0:
						neighbor = true
			if not neighbor:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				removed += 1
	return removed

func _bounds(image: Image, threshold: float = 0.000001) -> Rect2i:
	var left := image.get_width(); var top := image.get_height(); var right := -1; var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= threshold:
				left = mini(left, x); top = mini(top, y); right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _margins(bounds: Rect2i) -> Vector4i:
	return Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)

func _bottom_anchors(image: Image, threshold: float) -> Array[Vector2i]:
	var bounds := _bounds(image, threshold)
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

func _draw_anchors(canvas: Image, anchors: Array[Vector2i], image_x: int) -> void:
	for anchor in anchors:
		var px := image_x + roundi(float(anchor.x) * DISPLAY / SIZE.x)
		var py := TOP + roundi(float(anchor.y) * DISPLAY / SIZE.y)
		canvas.fill_rect(Rect2i(px - 7, py - 2, 15, 5), Color("#fff36a"))
		canvas.fill_rect(Rect2i(px - 2, py - 7, 5, 15), Color("#fff36a"))

func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 24):
		for x in range(rect.position.x, rect.end.x, 24):
			var even := (int((x - rect.position.x) / 24) + int((y - rect.position.y) / 24)) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(24, rect.end.x - x), mini(24, rect.end.y - y)), Color("#444a50") if even else Color("#30363c"))

func _draw_ascii(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	# Compact readable numbered panel labels; typography is intentionally ASCII-only.
	var cursor := origin.x
	for character in value:
		var glyph: Array = FONT.get(character, FONT[" "])
		for row in range(glyph.size()):
			for column in range(5):
				if glyph[row].substr(column, 1) == "1":
					image.fill_rect(Rect2i(cursor + column * scale, origin.y + row * scale, scale, scale), color)
		cursor += scale * 6

func _load(path: String) -> Image:
	var bytes := _bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes) == OK and not image.is_empty() else null

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0 or _has_alpha_neighbor(image, x, y):
				continue
			count += 1
	return count

func _has_alpha_neighbor(image: Image, x: int, y: int) -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var nx := x + ox; var ny := y + oy
			if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
				return true
	return false

func _hash(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return "hash_error"
	return context.finish().hex_encode()

func _fail(message: String) -> void:
	push_error("prepare_player_attack1_startup_safe: " + message)
	quit(1)
