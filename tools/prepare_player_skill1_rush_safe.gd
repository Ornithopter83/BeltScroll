extends SceneTree

const SIZE := Vector2i(1254, 1254)
const GAME_SIZE := 192
const MIN_MARGIN := 90
const GUARD := 12
const MAX_CONTENT := Vector2i(SIZE.x - 2 * (MIN_MARGIN + GUARD), SIZE.y - 2 * (MIN_MARGIN + GUARD))
const SOURCE := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png"
const IDLE := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const ATTACK := "res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_skill1_rush_safe_comparison.png"
const PANEL_W := 500
const GAP := 20
const DISPLAY := 384
const CANVAS := Vector2i(4 * PANEL_W + 5 * GAP, 640)
const LABELS := ["V8 IDLE", "ATTACK 1", "NUM4 SOURCE", "NUM4 SAFE"]
const PATHS := [IDLE, ATTACK, SOURCE, SAFE]
const FONT := {
	" ": ["00000","00000","00000","00000","00000","00000","00000"],
	"-": ["00000","00000","00000","11111","00000","00000","00000"],
	"0": ["01110","10001","10011","10101","11001","10001","01110"],
	"1": ["00100","01100","00100","00100","00100","00100","01110"],
	"4": ["00010","00110","01010","10010","11111","00010","00010"],
	"8": ["01110","10001","10001","01110","10001","10001","01110"],
	"9": ["01110","10001","10001","01111","00001","00010","11100"],
	"2": ["01110","10001","00001","00010","00100","01000","11111"],
	"A": ["01110","10001","10001","11111","10001","10001","10001"],
	"C": ["01111","10000","10000","10000","10000","10000","01111"],
	"D": ["11110","10001","10001","10001","10001","10001","11110"],
	"E": ["11111","10000","10000","11110","10000","10000","11111"],
	"F": ["11111","10000","10000","11110","10000","10000","10000"],
	"H": ["10001","10001","10001","11111","10001","10001","10001"],
	"I": ["11111","00100","00100","00100","00100","00100","11111"],
	"K": ["10001","10010","10100","11000","10100","10010","10001"],
	"L": ["10000","10000","10000","10000","10000","10000","11111"],
	"M": ["10001","11011","10101","10101","10001","10001","10001"],
	"N": ["10001","11001","11001","10101","10011","10011","10001"],
	"O": ["01110","10001","10001","10001","10001","10001","01110"],
	"P": ["11110","10001","10001","11110","10000","10000","10000"],
	"R": ["11110","10001","10001","11110","10100","10010","10001"],
	"S": ["01111","10000","10000","01110","00001","00001","11110"],
	"T": ["11111","00100","00100","00100","00100","00100","00100"],
	"U": ["10001","10001","10001","10001","10001","10001","01110"],
	"V": ["10001","10001","10001","10001","10001","01010","00100"],
	"W": ["10001","10001","10001","10101","10101","10101","01010"],
	"X": ["10001","10001","01010","00100","01010","10001","10001"]
}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	var idle := _load(IDLE)
	var attack := _load(ATTACK)
	if source == null or source.get_size() != SIZE or source.get_format() != Image.FORMAT_RGBA8:
		_fail("Num4 source must be a 1254x1254 RGBA8 PNG")
		return
	if idle == null or attack == null:
		_fail("v8 idle or existing attack contact reference is missing")
		return
	var original_bounds := _alpha_bounds(source)
	var working := source.duplicate()
	var removed := _clear_isolated(working)
	var bounds := _alpha_bounds(working)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		_fail("Num4 source has no visible artwork")
		return
	var scale := minf(float(MAX_CONTENT.x) / bounds.size.x, float(MAX_CONTENT.y) / bounds.size.y)
	var fitted := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var resized := _resize_premultiplied(working.get_region(bounds), fitted)
	if resized == null:
		_fail("premultiplied-alpha uniform resampling failed")
		return
	var safe := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	safe.fill(Color(0, 0, 0, 0))
	var offset := (SIZE - fitted) / 2
	safe.blit_rect(resized, Rect2i(Vector2i.ZERO, fitted), offset)
	var resample_removed := _clear_isolated(safe)
	_zero_transparent_rgb(safe)
	var output := ProjectSettings.globalize_path(SAFE)
	DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if safe.save_png(output) != OK:
		_fail("could not save separate safe candidate")
		return
	if _bytes(SOURCE) != source_bytes:
		_fail("Num4 source bytes changed during preparation")
		return
	if not _build_review():
		return
	var source_game := _game_metrics(source)
	var safe_game := _game_metrics(safe)
	var idle_game := _game_metrics(idle)
	var attack_game := _game_metrics(attack)
	var margins := _margins(_alpha_bounds(safe))
	var anchor_delta: Vector2i = safe_game.bottom[0] - source_game.bottom[0] if not safe_game.bottom.is_empty() and not source_game.bottom.is_empty() else Vector2i.ZERO
	print("RUSH_SAFE sha256=%s source_bounds=%s source_isolated_removed=%d fit=%s scale=%.6f offset=%s safe_bounds=%s margins_LTRB=%s resample_isolated_removed=%d isolated_after=%d outer_border=%s" % [_sha(source_bytes), str(original_bounds), removed, str(fitted), scale, str(offset), str(_alpha_bounds(safe)), str(margins), resample_removed, _isolated_count(safe), str(_transparent_border(safe))])
	print("RUSH_POSE game=192 source_bounds=%s safe_bounds=%s idle_bounds=%s attack_bounds=%s source_centroid=%s safe_centroid=%s idle_centroid=%s attack_centroid=%s source_bottom=%s safe_bottom=%s idle_bottom=%s attack_bottom=%s source_fist_proxy=%s safe_fist_proxy=%s attack_fist_proxy=%s source_height=%d safe_height=%d idle_height=%d attack_height=%d safe_anchor_delta_from_source=%s" % [str(source_game.bounds), str(safe_game.bounds), str(idle_game.bounds), str(attack_game.bounds), str(source_game.centroid), str(safe_game.centroid), str(idle_game.centroid), str(attack_game.centroid), str(source_game.bottom), str(safe_game.bottom), str(idle_game.bottom), str(attack_game.bottom), str(source_game.fist), str(safe_game.fist), str(attack_game.fist), source_game.bounds.size.y, safe_game.bounds.size.y, idle_game.bounds.size.y, attack_game.bounds.size.y, str(anchor_delta)])
	if margins.x < MIN_MARGIN or margins.y < MIN_MARGIN or margins.z < MIN_MARGIN or margins.w < MIN_MARGIN:
		_fail("safe must have at least 90px alpha margin on all sides")
		return
	if not _transparent_border(safe) or _isolated_count(safe) != 0:
		_fail("safe failed transparent-border or isolated-pixel check")
		return
	quit(0)

func _build_review() -> bool:
	var canvas := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	_draw_text(canvas, "RUSH SAFE REVIEW / 192PX GAME CANVAS / 2X", Vector2i(20, 16), 2, Color("#f0e8d8"))
	for i in range(PATHS.size()):
		var frame := _load(PATHS[i])
		if frame == null or frame.get_size() != SIZE:
			_fail("review reference missing or not 1254x1254: " + PATHS[i])
			return false
		var px := GAP + i * (PANEL_W + GAP)
		canvas.fill_rect(Rect2i(px, 64, PANEL_W, 510), Color("#252b32"))
		_draw_text(canvas, LABELS[i], Vector2i(px + 16, 72), 2, Color("#f0e8d8"))
		var ix := px + (PANEL_W - DISPLAY) / 2
		var game := Image.create(GAME_SIZE, GAME_SIZE, false, Image.FORMAT_RGBA8)
		game.fill(Color(0, 0, 0, 0))
		var art := frame.duplicate()
		art.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
		game.blend_rect(art, Rect2i(Vector2i.ZERO, Vector2i(GAME_SIZE, GAME_SIZE)), Vector2i.ZERO)
		_draw_checker(canvas, Rect2i(ix, 112, DISPLAY, DISPLAY))
		game.resize(DISPLAY, DISPLAY, Image.INTERPOLATE_NEAREST)
		canvas.blend_rect(game, Rect2i(Vector2i.ZERO, Vector2i(DISPLAY, DISPLAY)), Vector2i(ix, 112))
		var metrics := _game_metrics(frame)
		_draw_anchor(canvas, Vector2i(ix, 112), metrics.bottom)
		print("REVIEW %s bounds=%s height=%d centroid=%s bottom_anchors=%s fist_proxy=%s" % [LABELS[i], str(metrics.bounds), metrics.bounds.size.y, str(metrics.centroid), str(metrics.bottom), str(metrics.fist)])
	var path := ProjectSettings.globalize_path(REVIEW)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if canvas.save_png(path) != OK:
		_fail("could not save comparison board")
		return false
	return true

func _game_metrics(source: Image) -> Dictionary:
	var image := source.duplicate()
	image.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
	var bounds := _alpha_bounds(image, 0.05)
	return {"bounds": bounds, "centroid": _centroid(image), "bottom": _bottom_anchors(image), "fist": _rightmost_in(image, Rect2i(0, 25, GAME_SIZE, 90))}

func _centroid(image: Image) -> Vector2:
	var total := 0.0
	var sum := Vector2.ZERO
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var a := image.get_pixel(x, y).a
			if a >= 0.05:
				total += a
				sum += Vector2(x, y) * a
	return sum / total if total > 0.0 else Vector2.ZERO

func _rightmost_in(image: Image, rect: Rect2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if image.get_pixel(x, y).a >= 0.05 and x > best.x:
				best = Vector2i(x, y)
	return best

func _bottom_anchors(image: Image) -> Array[Vector2i]:
	var b := _alpha_bounds(image, 0.05)
	var result: Array[Vector2i] = []
	if b.size.x <= 0: return result
	var y := b.end.y - 1
	var start := -1
	for x in range(image.get_width() + 1):
		var active := x < image.get_width() and image.get_pixel(x, y).a >= 0.05
		if active and start < 0: start = x
		elif not active and start >= 0:
			result.append(Vector2i((start + x - 1) / 2, y))
			start = -1
	return result

func _draw_anchor(image: Image, origin: Vector2i, anchors: Array[Vector2i]) -> void:
	for p in anchors:
		var at := origin + p * 2
		image.fill_rect(Rect2i(at.x - 5, at.y - 2, 11, 5), Color("#fff36a"))
		image.fill_rect(Rect2i(at.x - 2, at.y - 5, 5, 11), Color("#fff36a"))

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
			if p.a <= 0.00001: image.set_pixel(x, y, Color(0, 0, 0, 0))
			else: image.set_pixel(x, y, Color(clampf(p.r / p.a, 0.0, 1.0), clampf(p.g / p.a, 0.0, 1.0), clampf(p.b / p.a, 0.0, 1.0), clampf(p.a, 0.0, 1.0)))
	return image

func _clear_isolated(image: Image) -> int:
	var w := image.get_width()
	var h := image.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in range(h):
		for x in range(w): mask[y * w + x] = 1 if image.get_pixel(x, y).a > 0.0 else 0
	var removed := 0
	for y in range(h):
		for x in range(w):
			var i := y * w + x
			if mask[i] == 0: continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < w and ny < h and mask[ny * w + nx] != 0: neighbor = true
			if not neighbor:
				image.set_pixel(x, y, Color(0, 0, 0, 0))
				removed += 1
	return removed

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0: continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0: neighbor = true
			if not neighbor: count += 1
	return count

func _alpha_bounds(image: Image, threshold: float = 0.000001) -> Rect2i:
	var l := image.get_width(); var t := image.get_height(); var r := -1; var b := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= threshold:
				l = mini(l, x); t = mini(t, y); r = maxi(r, x); b = maxi(b, y)
	return Rect2i(l, t, r - l + 1, b - t + 1) if r >= l else Rect2i()

func _margins(b: Rect2i) -> Vector4i:
	return Vector4i(b.position.x, b.position.y, SIZE.x - b.end.x, SIZE.y - b.end.y)

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, image.get_height() - 1).a != 0.0: return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(image.get_width() - 1, y).a != 0.0: return false
	return true

func _zero_transparent_rgb(image: Image) -> void:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a == 0.0: image.set_pixel(x, y, Color(0, 0, 0, 0))

func _draw_checker(image: Image, rect: Rect2i) -> void:
	for y in range(rect.position.y, rect.end.y, 24):
		for x in range(rect.position.x, rect.end.x, 24):
			var even := ((x - rect.position.x) / 24 + (y - rect.position.y) / 24) % 2 == 0
			image.fill_rect(Rect2i(x, y, mini(24, rect.end.x - x), mini(24, rect.end.y - y)), Color("#444a50") if even else Color("#30363c"))

func _draw_text(image: Image, value: String, origin: Vector2i, scale: int, color: Color) -> void:
	var cursor := origin.x
	for c in value:
		var glyph: Array = FONT.get(c, FONT[" "])
		for y in range(glyph.size()):
			for x in range(5):
				if glyph[y].substr(x, 1) == "1": image.fill_rect(Rect2i(cursor + x * scale, origin.y + y * scale, scale, scale), color)
		cursor += scale * 6

func _load(path: String) -> Image:
	var data := _bytes(path)
	if data.is_empty(): return null
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK: return null
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
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
	push_error("prepare_player_skill1_rush_safe: " + message)
	quit(1)
