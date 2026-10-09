extends SceneTree

const SIZE := Vector2i(1254, 1254)
const GAME_SIZE := 192
const MIN_INSET := 90
const SAFE_PATH := "res://assets/art/player/elven_fighter_jump_fall_v1_safe_candidate_1254x1254.png"
const SOURCE_PATH := "res://assets/art/player/elven_fighter_jump_fall_v1_candidate_1254x1254.png"
const IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const RISE_PATH := "res://assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png"
const REVIEW_PATH := "res://assets/art/review/player_jump_fall_comparison.png"
const TILE := 384
const GAP := 18
const BOARD := Vector2i(4 * TILE + 5 * GAP, 2 * TILE + 3 * GAP + 58)
const FONT := {
	" ": ["00000", "00000", "00000", "00000", "00000", "00000", "00000"], "-": ["00000", "00000", "00000", "11111", "00000", "00000", "00000"],
	"0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"], "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"], "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
	"3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"], "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"], "5": ["11111", "10000", "10000", "11110", "00001", "00001", "11110"],
	"6": ["01110", "10000", "10000", "11110", "10001", "10001", "01110"], "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"], "9": ["01110", "10001", "10001", "01111", "00001", "00010", "11100"],
	"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"], "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"], "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
	"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"], "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"], "F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
	"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"], "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"], "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
	"J": ["00111", "00010", "00010", "00010", "10010", "10010", "01100"], "K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"], "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
	"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"], "N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"], "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
	"P": ["11110", "10001", "10001", "11110", "10000", "10000", "10000"], "Q": ["01110", "10001", "10001", "10001", "10101", "10010", "01101"], "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"], "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
	"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"], "U": ["10001", "10001", "10001", "10001", "10001", "10001", "01110"], "V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"], "W": ["10001", "10001", "10001", "10101", "10101", "10101", "01010"], "X": ["10001", "10001", "01010", "00100", "01010", "10001", "10001"]
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE_PATH)
	var source := _load(SOURCE_PATH)
	var safe: Image = null
	if source == null:
		print("JUMP_FALL_SOURCE_MISSING path=%s; safe candidate not created; existing review continues" % SOURCE_PATH)
	else:
		if source.get_size() != SIZE or source.get_format() != Image.FORMAT_RGBA8:
			_fail("jump-fall source must be a 1254x1254 RGBA8 PNG")
			return
		safe = _make_safe(source)
		if safe == null:
			_fail("could not make jump-fall safe candidate")
			return
		var out_path := ProjectSettings.globalize_path(SAFE_PATH)
		DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
		if safe.save_png(out_path) != OK:
			_fail("could not save safe candidate")
			return
		var margins := _margins(_bounds(safe))
		print("JUMP_FALL_SAFE source_sha256=%s source_bytes=%d source_bounds=%s isolated_removed=%d scale=%.6f safe_bounds=%s margins_LTRB=%s safe_isolated=%d" % [_sha(source_bytes), source_bytes.size(), str(_bounds(source)), _source_removed, _fit_scale, str(_bounds(safe)), str(margins), _isolated_count(safe)])
		if _bytes(SOURCE_PATH) != source_bytes:
			_fail("jump-fall source bytes changed during preparation")
			return
		if margins.x < MIN_INSET or margins.y < MIN_INSET or margins.z < MIN_INSET or margins.w < MIN_INSET or _isolated_count(safe) != 0:
			_fail("safe candidate failed margin or isolated-alpha gate")
			return
	if not _build_review():
		return
	print("JUMP_FALL_REVIEW board=%s canvas=%dx%d scale=192/1254 horizontal_mirror=one_flip" % [REVIEW_PATH, GAME_SIZE, GAME_SIZE])
	quit(0)

var _source_removed := 0
var _fit_scale := 0.0

func _make_safe(source: Image) -> Image:
	var clean := source.duplicate()
	_source_removed = _clear_isolated(clean)
	var bounds := _bounds(clean)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var available := Vector2i(SIZE.x - 2 * MIN_INSET, SIZE.y - 2 * MIN_INSET)
	_fit_scale = minf(float(available.x) / bounds.size.x, float(available.y) / bounds.size.y)
	var target := Vector2i(maxi(1, roundi(bounds.size.x * _fit_scale)), maxi(1, roundi(bounds.size.y * _fit_scale)))
	var resized := _resize_premultiplied(clean.get_region(bounds), target)
	var output := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	output.fill(Color(0, 0, 0, 0))
	output.blit_rect(resized, Rect2i(Vector2i.ZERO, target), (SIZE - target) / 2)
	_clear_isolated(output)
	_zero_transparent_rgb(output)
	return output

func _build_review() -> bool:
	var idle := _load(IDLE_PATH)
	var rise := _load(RISE_PATH)
	var fall := _load(SOURCE_PATH)
	var safe := _load(SAFE_PATH)
	if idle == null or rise == null:
		_fail("v8 idle or existing jump-rise safe is missing")
		return false
	var board := Image.create(BOARD.x, BOARD.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("#171b20"))
	_draw_text(board, "JUMP FALL POSE COMPARISON 192PX FULL CANVAS", Vector2i(20, 14), 2, Color("#f0e8d8"))
	var poses: Array = [idle, rise, fall, safe, idle, rise, fall, safe]
	var labels := ["V8 IDLE RIGHT", "JUMP RISE SAFE RIGHT", "JUMP FALL SOURCE RIGHT", "JUMP FALL SAFE RIGHT", "V8 IDLE MIRROR", "JUMP RISE SAFE MIRROR", "JUMP FALL SOURCE MIRROR", "JUMP FALL SAFE MIRROR"]
	for i in range(poses.size()):
		var col := i % 4
		var row := int(i / 4)
		var x := GAP + col * (TILE + GAP)
		var y := 48 + GAP + row * (TILE + GAP)
		board.fill_rect(Rect2i(x, y, TILE, TILE), Color("#252b32"))
		_draw_text(board, labels[i], Vector2i(x + 10, y + 10), 1, Color("#f1bd69"))
		var game := Image.create(GAME_SIZE, GAME_SIZE, false, Image.FORMAT_RGBA8)
		game.fill(Color(0, 0, 0, 0))
		if poses[i] == null:
			_draw_checker(board, Rect2i(x + 96, y + 46, 192, 192))
			_draw_text(board, "MISSING SOURCE", Vector2i(x + 112, y + 136), 2, Color("#ff8585"))
			continue
		var pose: Image = poses[i].duplicate()
		if i >= 4:
			pose.flip_x()
		pose.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
		game.blend_rect(pose, Rect2i(Vector2i.ZERO, Vector2i(GAME_SIZE, GAME_SIZE)), Vector2i.ZERO)
		var target := Rect2i(x + 96, y + 46, 192, 192)
		_draw_checker(board, target)
		board.blend_rect(game, Rect2i(Vector2i.ZERO, Vector2i(GAME_SIZE, GAME_SIZE)), target.position)
		var kind := 0 if i == 0 or i == 4 else (1 if i == 1 or i == 5 else 2)
		var m := _metrics(poses[i], i >= 4, kind)
		_draw_anchor(board, target.position, m.anchors)
		print("POSE_METRICS %s bounds_192=%s silhouette_h=%d torso_y=%.2f lower_body_y=%.2f centroid=(%.2f,%.2f) boot_roi_centers=%s bottom_anchors=%s" % [labels[i], str(m.bounds), m.bounds.size.y, m.torso_y, m.lower_y, m.centroid.x, m.centroid.y, str(m.boot_centers), str(m.anchors)])
	if fall == null:
		_draw_text(board, "JUMP FALL SOURCE MISSING / NO SAFE CANDIDATE", Vector2i(20, BOARD.y - 18), 1, Color("#ff8585"))
	else:
		_draw_text(board, "FALL SAFE / RISE-TO-FALL HEIGHT DELTA REQUIRES HUMAN REVIEW", Vector2i(20, BOARD.y - 18), 1, Color("#f0e8d8"))
	var out := ProjectSettings.globalize_path(REVIEW_PATH)
	DirAccess.make_dir_recursive_absolute(out.get_base_dir())
	return board.save_png(out) == OK

func _metrics(source: Image, mirrored: bool, kind: int) -> Dictionary:
	var image := source.duplicate()
	if mirrored:
		image.flip_x()
	image.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
	var torso := Rect2i(90, 40, 34, 80)
	var lower := Rect2i(0, 90, GAME_SIZE, 100)
	var boots: Array[Rect2i]
	if kind == 0:
		boots = [Rect2i(45, 158, 30, 30), Rect2i(135, 158, 30, 30)]
	elif kind == 1:
		boots = [Rect2i(47, 151, 27, 28), Rect2i(112, 123, 28, 26)]
	else:
		boots = [Rect2i(93, 163, 27, 29), Rect2i(94, 127, 30, 29)]
	var boot_centers: Array[Vector2] = []
	for region in boots:
		var measured_region := Rect2i(GAME_SIZE - region.end.x, region.position.y, region.size.x, region.size.y) if mirrored else region
		boot_centers.append(_centroid(image, measured_region))
	return {"bounds": _bounds(image, 0.05), "torso_y": _centroid(image, torso).y, "lower_y": _centroid(image, lower).y, "centroid": _centroid(image, Rect2i(0, 0, GAME_SIZE, GAME_SIZE)), "boot_centers": boot_centers, "anchors": _bottom_anchors(image)}

func _centroid(image: Image, rect: Rect2i) -> Vector2:
	var sum := 0.0
	var weighted := Vector2.ZERO
	for y in range(maxi(0, rect.position.y), mini(image.get_height(), rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(image.get_width(), rect.end.x)):
			var a := image.get_pixel(x, y).a
			if a >= 0.05:
				sum += a
				weighted += Vector2(x, y) * a
	return weighted / sum if sum > 0.0 else Vector2.ZERO

func _bottom_anchors(image: Image) -> Array[Vector2i]:
	var b := _bounds(image, 0.05)
	var result: Array[Vector2i] = []
	if b.size.x == 0:
		return result
	var y := b.end.y - 1
	var start := -1
	for x in range(image.get_width() + 1):
		var on := x < image.get_width() and image.get_pixel(x, y).a >= 0.05
		if on and start < 0:
			start = x
		elif not on and start >= 0:
			result.append(Vector2i((start + x - 1) / 2, y))
			start = -1
	return result

func _draw_anchor(image: Image, origin: Vector2i, anchors: Array[Vector2i]) -> void:
	for p in anchors:
		image.fill_rect(Rect2i(origin.x + p.x - 5, origin.y + p.y - 1, 11, 3), Color("#fff36a"))
		image.fill_rect(Rect2i(origin.x + p.x - 1, origin.y + p.y - 5, 3, 11), Color("#fff36a"))

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
	var mask := PackedByteArray()
	mask.resize(image.get_width() * image.get_height())
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			mask[y * image.get_width() + x] = 1 if image.get_pixel(x, y).a > 0.0 else 0
	var removed := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var idx := y * image.get_width() + x
			if mask[idx] == 0:
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

func _isolated_count(image: Image) -> int:
	var copy := image.duplicate()
	return _clear_isolated(copy)

func _bounds(image: Image, threshold: float = 0.000001) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= threshold:
				left = mini(left, x); top = mini(top, y); right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _margins(b: Rect2i) -> Vector4i:
	return Vector4i(b.position.x, b.position.y, SIZE.x - b.end.x, SIZE.y - b.end.y)

func _zero_transparent_rgb(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a == 0.0:
				image.set_pixel(x, y, Color(0, 0, 0, 0))

func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 24):
		for x in range(rect.position.x, rect.end.x, 24):
			var light := (int((x - rect.position.x) / 24) + int((y - rect.position.y) / 24)) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(24, rect.end.x - x), mini(24, rect.end.y - y)), Color("#444a50") if light else Color("#30363c"))

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
	push_error("prepare_player_jump_fall_safe: " + message)
	quit(1)
