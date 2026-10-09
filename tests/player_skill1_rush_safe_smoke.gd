extends SceneTree

const SIZE := Vector2i(1254, 1254)
const GAME_SIZE := 192
const MIN_MARGIN := 90
const SOURCE := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png"
const IDLE := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const ATTACK := "res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_skill1_rush_safe_comparison.png"
const SOURCE_SHA256 := "cf9fdabd1db74d298bbd2f102ab4a40302da152d4990698b763d7ebcde4fcfc1"
const NUM5_CAPTURE := "res://temp/player_skill_motion_capture/num5_004_active.png"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	var source := _load(SOURCE)
	var safe := _load(SAFE)
	var idle := _load(IDLE)
	var attack := _load(ATTACK)
	_check(not source_bytes.is_empty() and _sha(source_bytes) == SOURCE_SHA256, "original Num4 rush artwork retains its recorded SHA-256")
	_check(source != null and source.get_size() == SIZE and source.get_format() == Image.FORMAT_RGBA8, "Num4 original is a 1254x1254 RGBA8 PNG")
	_check(safe != null and safe.get_size() == SIZE and safe.get_format() == Image.FORMAT_RGBA8, "safe candidate is a 1254x1254 RGBA8 PNG")
	_check(idle != null and idle.get_size() == SIZE and attack != null and attack.get_size() == SIZE, "v8 idle and existing attack-contact comparison art are available")
	var review := _load(REVIEW)
	_check(review != null and review.get_size().x > review.get_size().y, "four-pose same-game-size comparison board exists")
	if source != null and safe != null:
		var bounds := _alpha_bounds(safe)
		var margins := Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)
		_check(margins.x >= MIN_MARGIN and margins.y >= MIN_MARGIN and margins.z >= MIN_MARGIN and margins.w >= MIN_MARGIN, "safe alpha artwork has at least 90px inset on every side: " + str(margins))
		_check(_transparent_border(safe), "outermost pixel rows and columns are fully transparent")
		_check(_transparent_rgb_zero(safe), "fully transparent pixels store zero RGB")
		_check(_isolated_count(safe) == 0, "safe candidate has zero isolated alpha pixels")
		_check(_uniform_scale(source, safe), "safe uses equal horizontal and vertical scale factors")
		_check(_features_retained(source, safe), "face, pointed ear, teal-gold costume, extended fist, and rear drive boot remain present")
		var source_game := source.duplicate()
		var safe_game := safe.duplicate()
		source_game.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
		safe_game.resize(GAME_SIZE, GAME_SIZE, Image.INTERPOLATE_LANCZOS)
		var before := _bottom_anchors(source_game)
		var after := _bottom_anchors(safe_game)
		print("RUSH_SMOKE source_bounds_192=%s safe_bounds_192=%s source_bottom=%s safe_bottom=%s bottom_anchor_delta=%s" % [str(_alpha_bounds(source_game, 0.05)), str(_alpha_bounds(safe_game, 0.05)), str(before), str(after), str(after[0] - before[0]) if not before.is_empty() and not after.is_empty() else "unavailable"])
		_check(not before.is_empty() and not after.is_empty(), "source and safe retain a measurable ground-contact anchor")
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(NUM5_CAPTURE)), "existing Num5 rotation active capture is available for human distinction review")
	_check(_bytes(SOURCE) == source_bytes, "original Num4 rush source bytes are unchanged")
	if failures.is_empty():
		print("player_skill1_rush_safe_smoke: mechanical checks passed; face/clothing identity, drive-leg readability, and Num5 rotational distinction remain human review gates")
		quit(0)
	else:
		for failure in failures:
			push_error("player_skill1_rush_safe_smoke: " + failure)
		quit(1)

func _features_retained(source: Image, safe: Image) -> bool:
	var regions := [
		["face", Rect2(0.65, 0.17, 0.22, 0.16)],
		["pointed ear", Rect2(0.57, 0.15, 0.16, 0.16)],
		["costume", Rect2(0.42, 0.34, 0.27, 0.32)],
		["extended fist", Rect2(0.91, 0.26, 0.09, 0.13)],
		["rear drive boot", Rect2(0.00, 0.87, 0.20, 0.13)]
	]
	var all_present := true
	for item in regions:
		var before := _region_alpha(source, item[1])
		var after := _region_alpha(safe, item[1])
		print("FEATURE %s source=%d safe=%d" % [item[0], before, after])
		all_present = all_present and before > 0 and after > 0
	return all_present

func _region_alpha(image: Image, region: Rect2) -> int:
	var b := _alpha_bounds(image)
	var x0 := b.position.x + floori(region.position.x * b.size.x)
	var y0 := b.position.y + floori(region.position.y * b.size.y)
	var x1 := mini(b.end.x, b.position.x + ceili(region.end.x * b.size.x))
	var y1 := mini(b.end.y, b.position.y + ceili(region.end.y * b.size.y))
	var count := 0
	for y in range(maxi(0, y0), y1):
		for x in range(maxi(0, x0), x1):
			if image.get_pixel(x, y).a >= 0.05: count += 1
	return count

func _uniform_scale(source: Image, safe: Image) -> bool:
	var before := _alpha_bounds(source, 0.05)
	var after := _alpha_bounds(safe, 0.05)
	if before.size.x <= 0 or before.size.y <= 0: return false
	var sx := float(after.size.x) / before.size.x
	var sy := float(after.size.y) / before.size.y
	print("UNIFORM_SCALE source=%s safe=%s x=%.6f y=%.6f" % [str(before), str(after), sx, sy])
	return sx < 1.0 and sy < 1.0 and absf(sx - sy) < 0.01

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

func _alpha_bounds(image: Image, threshold: float = 0.000001) -> Rect2i:
	var l := image.get_width(); var t := image.get_height(); var r := -1; var b := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= threshold:
				l = mini(l, x); t = mini(t, y); r = maxi(r, x); b = maxi(b, y)
	return Rect2i(l, t, r - l + 1, b - t + 1) if r >= l else Rect2i()

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, image.get_height() - 1).a != 0.0: return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(image.get_width() - 1, y).a != 0.0: return false
	return true

func _transparent_rgb_zero(image: Image) -> bool:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var p: Color = image.get_pixel(x, y)
			if p.a <= 0.0 and (p.r != 0.0 or p.g != 0.0 or p.b != 0.0): return false
	return true

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0: continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox; var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0: neighbor = true
			if not neighbor: count += 1
	return count

func _load(path: String) -> Image:
	var data := _bytes(path)
	if data.is_empty(): return null
	var image := Image.new()
	if image.load_png_from_buffer(data) != OK: return null
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	return image

func _bytes(path: String) -> PackedByteArray:
	var absolute := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(absolute) if FileAccess.file_exists(absolute) else PackedByteArray()

func _sha(data: PackedByteArray) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(data)
	return hash.finish().hex_encode()

func _check(condition: bool, description: String) -> void:
	if condition: print("PASS: " + description)
	else: failures.append(description)
