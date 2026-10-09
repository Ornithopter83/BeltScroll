extends SceneTree

const SIZE := Vector2i(1254, 1254)
const SAFE_INSET := 90
const RESAMPLE_GUARD := 12
const MAX_CONTENT := Vector2i(SIZE.x - (SAFE_INSET + RESAMPLE_GUARD) * 2, SIZE.y - (SAFE_INSET + RESAMPLE_GUARD) * 2)
const SOURCE := "res://assets/art/player/elven_fighter_attack2_contact_v6_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack2_contact_v6_safe_comparison.png"
const COMPARE_PATHS := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png",
	SOURCE,
	OUTPUT,
]
const COMPARE_LABELS := ["V8 APPROVED", "HIT 2 MID SAFE", "V6 SOURCE", "V6 SAFE CANDIDATE"]
const PANEL_W := 720
const PANEL_GAP := 24
const CANVAS := Vector2i(4 * PANEL_W + 5 * PANEL_GAP, 760)
const IMAGE_SIZE := 576 # 3x the 192px game canvas.
const IMAGE_TOP := 92
const BASELINE := IMAGE_TOP + IMAGE_SIZE
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"],
	"-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
	"1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
	"2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"],
	"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
	"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
	"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
	"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
	"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
	"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
	"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"],
	"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
	"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
	"V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
	"U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"],
	"W": ["10001", "10001", "10101", "10101", "10101", "10101", "01010"],
	"X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"],
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _read_bytes(SOURCE)
	var source := _load_image(SOURCE)
	if source == null or source.get_size() != SIZE or source.get_format() != Image.FORMAT_RGBA8:
		_fail("source must remain a decodable 1254x1254 RGBA8 PNG")
		return
	var source_bounds := _alpha_bounds(source)
	if source_bounds.size.x <= 0 or source_bounds.size.y <= 0:
		_fail("source has no nonzero-alpha pixels")
		return
	var removed_source_isolated := _clear_isolated_alpha(source)
	var bounds := _alpha_bounds(source)
	var scale := minf(float(MAX_CONTENT.x) / bounds.size.x, float(MAX_CONTENT.y) / bounds.size.y)
	var fitted := Vector2i(roundi(bounds.size.x * scale), roundi(bounds.size.y * scale))
	if fitted.x > MAX_CONTENT.x or fitted.y > MAX_CONTENT.y:
		_fail("uniformly fitted image exceeds the guarded safe area")
		return
	var cropped := source.get_region(bounds)
	var scaled := _resize_premultiplied(cropped, fitted)
	if scaled == null:
		_fail("premultiplied-alpha resampling failed")
		return
	var candidate := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	candidate.fill(Color(0.0, 0.0, 0.0, 0.0))
	var position := Vector2i((SIZE.x - fitted.x) / 2, (SIZE.y - fitted.y) / 2)
	candidate.blit_rect(scaled, Rect2i(Vector2i.ZERO, fitted), position)
	var removed_resample_isolated := _clear_isolated_alpha(candidate)
	var output_full := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(output_full.get_base_dir())
	var save_error := candidate.save_png(output_full)
	if save_error != OK:
		_fail("could not save safe candidate: %s" % error_string(save_error))
		return
	if _read_bytes(SOURCE) != source_bytes:
		_fail("original v6 source bytes changed unexpectedly")
		return
	var margins := _margins(candidate, _alpha_bounds(candidate))
	var source_anchors := _bottom_contact_anchors(_load_image(SOURCE), 0.05)
	var safe_anchors := _bottom_contact_anchors(candidate, 0.05)
	print("v6 safe candidate prepared | uniform_scale=%.6f | fitted=%s | nonzero-alpha margins L/T/R/B=%d/%d/%d/%d | removed_isolated_alpha_pixels=%d | source_bottom_contacts=%s | safe_bottom_contacts=%s | source_bytes_preserved=true" % [
		scale, str(fitted), margins.x, margins.y, margins.z, margins.w, removed_source_isolated + removed_resample_isolated,
		str(source_anchors), str(safe_anchors)])
	if margins.x < SAFE_INSET or margins.y < SAFE_INSET or margins.z < SAFE_INSET or margins.w < SAFE_INSET:
		_fail("generated candidate does not meet the 90px all-side inset")
		return
	if not _build_comparison():
		return
	quit(0)

func _build_comparison() -> bool:
	var images: Array[Image] = []
	for path in COMPARE_PATHS:
		var image := _load_image(path)
		if image == null or image.get_size() != SIZE:
			_fail("comparison input missing or not 1254x1254: %s" % path)
			return false
		images.append(image)
	var canvas := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_text(canvas, "ATTACK 2 CONTACT V6 SAFE REVIEW", Vector2i(24, 18), 3, Color("#f0e8d8"))
	_draw_text(canvas, "3X GAME CANVAS - FOOT CONTACT ANCHORS SHOWN", Vector2i(24, 50), 2, Color("#f1bd69"))
	for i in range(images.size()):
		var x := PANEL_GAP + i * (PANEL_W + PANEL_GAP)
		canvas.fill_rect(Rect2i(x, 80, PANEL_W, 628), Color("#252b32"))
		_draw_checker(canvas, Rect2i(x + 12, IMAGE_TOP, PANEL_W - 24, IMAGE_SIZE))
		_draw_text(canvas, COMPARE_LABELS[i], Vector2i(x + 18, 84), 2, Color("#f0e8d8"))
		var sprite := images[i].duplicate()
		sprite.resize(IMAGE_SIZE, IMAGE_SIZE, Image.INTERPOLATE_LANCZOS)
		var image_x := x + (PANEL_W - IMAGE_SIZE) / 2
		canvas.blend_rect(sprite, Rect2i(Vector2i.ZERO, Vector2i(IMAGE_SIZE, IMAGE_SIZE)), Vector2i(image_x, IMAGE_TOP))
		var anchors := _bottom_contact_anchors(images[i], 0.05)
		_draw_contact_marks(canvas, anchors, image_x)
		var bounds := _alpha_bounds_at_threshold(images[i], 0.05)
		print("3X COMPARE %s | 576x576 canvas | visible alpha>=5%%=%s | bottom contacts=%s" % [COMPARE_PATHS[i], str(bounds), str(anchors)])
	canvas.fill_rect(Rect2i(PANEL_GAP, BASELINE, CANVAS.x - PANEL_GAP * 2, 3), Color("#f05c4f"))
	var review_full := ProjectSettings.globalize_path(REVIEW)
	DirAccess.make_dir_recursive_absolute(review_full.get_base_dir())
	var err := canvas.save_png(review_full)
	if err != OK:
		_fail("could not save comparison image: %s" % error_string(err))
		return false
	return true

func _draw_contact_marks(canvas: Image, anchors: Array[Vector2i], image_x: int) -> void:
	for anchor in anchors:
		var px := image_x + roundi(float(anchor.x) * IMAGE_SIZE / SIZE.x)
		var py := IMAGE_TOP + roundi(float(anchor.y) * IMAGE_SIZE / SIZE.y)
		canvas.fill_rect(Rect2i(px - 7, py - 2, 15, 5), Color("#fff36a"))
		canvas.fill_rect(Rect2i(px - 2, py - 7, 5, 15), Color("#fff36a"))

func _resize_premultiplied(source: Image, target_size: Vector2i) -> Image:
	if source.is_empty() or target_size.x <= 0 or target_size.y <= 0:
		return null
	var image: Image = source.duplicate()
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p: Color = image.get_pixel(x, y)
			image.set_pixel(x, y, Color(p.r * p.a, p.g * p.a, p.b * p.a, p.a))
	image.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	for y in range(target_size.y):
		for x in range(target_size.x):
			var p: Color = image.get_pixel(x, y)
			if p.a <= 0.00001:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
			else:
				image.set_pixel(x, y, Color(clampf(p.r / p.a, 0.0, 1.0), clampf(p.g / p.a, 0.0, 1.0), clampf(p.b / p.a, 0.0, 1.0), clampf(p.a, 0.0, 1.0)))
	return image

func _clear_isolated_alpha(image: Image) -> int:
	var mask := PackedByteArray()
	mask.resize(SIZE.x * SIZE.y)
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a > 0.0:
				mask[y * SIZE.x + x] = 1
	var removed := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if mask[y * SIZE.x + x] == 0:
				continue
			var has_neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := x + ox
					var ny := y + oy
					if nx >= 0 and ny >= 0 and nx < SIZE.x and ny < SIZE.y and mask[ny * SIZE.x + nx] != 0:
						has_neighbor = true
						break
				if has_neighbor:
					break
			if not has_neighbor:
				image.set_pixel(x, y, Color(0.0, 0.0, 0.0, 0.0))
				removed += 1
	return removed

func _alpha_bounds(image: Image) -> Rect2i:
	return _alpha_bounds_at_threshold(image, 0.000001)

func _alpha_bounds_at_threshold(image: Image, threshold: float) -> Rect2i:
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

func _bottom_contact_anchors(image: Image, threshold: float) -> Array[Vector2i]:
	var bounds := _alpha_bounds_at_threshold(image, threshold)
	var anchors: Array[Vector2i] = []
	if bounds.size.x <= 0:
		return anchors
	var bottom := bounds.end.y - 1
	var run_start := -1
	for x in range(image.get_width() + 1):
		var active := x < image.get_width() and image.get_pixel(x, bottom).a >= threshold
		if active and run_start < 0:
			run_start = x
		elif not active and run_start >= 0:
			anchors.append(Vector2i((run_start + x - 1) / 2, bottom))
			run_start = -1
	return anchors

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
	var tile := 24
	for y in range(rect.position.y, rect.end.y, tile):
		for x in range(rect.position.x, rect.end.x, tile):
			var even := (int((x - rect.position.x) / tile) + int((y - rect.position.y) / tile)) % 2 == 0
			var color := Color("#444a50") if even else Color("#30363c")
			image.fill_rect(Rect2i(x, y, mini(tile, rect.end.x - x), mini(tile, rect.end.y - y)), color)

func _fail(message: String) -> void:
	push_error("prepare_player_attack2_contact_v6_safe: " + message)
	quit(1)
