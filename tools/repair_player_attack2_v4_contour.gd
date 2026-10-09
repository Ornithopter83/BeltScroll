extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const SOURCE := "res://assets/art/player/elven_fighter_attack2_reference_v4_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack2_reference_v4_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_attack2_reference_v4_clean_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack2_reference_v4_contour_candidate_1254x1254.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const REVIEW := "res://assets/art/review/player_attack2_v4_contour_gate.png"

const CODE_USAGE := 2
const CODE_SOURCE := 3
const CODE_SAFE := 4
const CODE_CLEAN := 5
const CODE_FOREST := 6
const CODE_OUTPUT := 7
const CODE_PROTECTED := 8

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("Usage: godot --headless --path . --script res://tools/repair_player_attack2_v4_contour.gd")
		quit(0)
		return
	if not args.is_empty():
		_fail("unexpected argument", CODE_USAGE)
		return
	var protected := [SOURCE, SAFE, CLEAN]
	var protected_bytes: Array[PackedByteArray] = []
	for i in range(protected.size()):
		var full := _resolve(protected[i])
		if not FileAccess.file_exists(full):
			_fail("protected input is missing: " + protected[i], [CODE_SOURCE, CODE_SAFE, CODE_CLEAN][i])
			return
		protected_bytes.append(FileAccess.get_file_as_bytes(full))
	var source := _load_png(_resolve(SOURCE))
	var safe := _load_png(_resolve(SAFE))
	var clean := _load_png(_resolve(CLEAN))
	var forest := _load_png(_resolve(FOREST))
	if source == null or source.get_size() != SIZE:
		_fail("attack2 v4 original is invalid", CODE_SOURCE)
		return
	if safe == null or safe.get_size() != SIZE:
		_fail("attack2 v4 safe image is invalid", CODE_SAFE)
		return
	if clean == null or clean.get_size() != SIZE:
		_fail("attack2 v4 clean candidate is invalid", CODE_CLEAN)
		return
	if forest == null or forest.is_empty():
		_fail("Forest Ruins image is invalid", CODE_FOREST)
		return
	var result := repair_contour(clean)
	if result.is_empty() or int(result.changed) <= 0:
		_fail("no contour stain was repaired", CODE_CLEAN)
		return
	var error := _save_png(result.image, _resolve(OUTPUT))
	if error == OK:
		error = build_review(clean, result.image, forest, _resolve(REVIEW))
	if error != OK:
		_fail("candidate or review could not be saved: %s" % error_string(error), CODE_OUTPUT)
		return
	for i in range(protected.size()):
		if FileAccess.get_file_as_bytes(_resolve(protected[i])) != protected_bytes[i]:
			_fail("protected input changed: " + protected[i], CODE_PROTECTED)
			return
	print("player_attack2_v4_contour: %d pixels repaired (%d alpha cleared, %d colors restored); inputs preserved; visual approval pending" % [result.changed, result.alpha_cleared, result.rgb_restored])
	quit(0)

# Repair is limited to the ponytail, ear/face, shoulder/attacking arm/fist and
# both boot contours. Translucent red fringe is removed; opaque red pixels are
# recolored from nearby non-red opaque pixels. Everything else stays exact.
static func repair_contour(source: Image) -> Dictionary:
	if source == null or source.is_empty() or source.get_size() != SIZE:
		return {}
	var output := source.duplicate()
	var alpha_cleared := 0
	var rgb_restored := 0
	for zone in _zones():
		var rect: Rect2i = zone
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				var p := source.get_pixel(x, y)
				if not _red_stain(p):
					continue
				if p.a < 0.82:
					output.set_pixel(x, y, Color(0, 0, 0, 0))
					alpha_cleared += 1
				elif _opaque_context(source, x, y):
					var replacement := _local_median(source, x, y)
					if replacement.a > 0.0:
						output.set_pixel(x, y, Color(replacement.r, replacement.g, replacement.b, p.a))
						rgb_restored += 1
	return {"image": output, "changed": alpha_cleared + rgb_restored,
		"alpha_cleared": alpha_cleared, "rgb_restored": rgb_restored}

static func _zones() -> Array[Rect2i]:
	return [
		Rect2i(225, 90, 525, 365), # full ponytail, knot, rear hair edge
		Rect2i(640, 205, 300, 200), # ear, face, front hair
		Rect2i(610, 305, 290, 245), # shoulder and exposed upper arm
		Rect2i(795, 330, 340, 240), # extended arm, glove and fist
		Rect2i(135, 900, 335, 280), # left boot
		Rect2i(920, 890, 255, 285), # right boot
	]

static func _red_stain(p: Color) -> bool:
	return p.a >= 0.12 and p.s >= 0.52 and p.v >= 0.18 \
		and p.r - p.g >= 0.16 and p.r - p.b >= 0.12 \
		and (p.h <= 0.045 or p.h >= 0.965)

static func _opaque_context(image: Image, x: int, y: int) -> bool:
	var found := 0
	for oy in range(-5, 6):
		for ox in range(-5, 6):
			if ox == 0 and oy == 0:
				continue
			var p := image.get_pixel(x + ox, y + oy)
			if p.a >= 0.82 and not _red_stain(p):
				found += 1
	return found >= 3

static func _local_median(image: Image, x: int, y: int) -> Color:
	var rs: Array[float] = []
	var gs: Array[float] = []
	var bs: Array[float] = []
	for radius in range(1, 7):
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				if maxi(absi(ox), absi(oy)) != radius:
					continue
				var p := image.get_pixel(x + ox, y + oy)
				if p.a < 0.82 or _red_stain(p):
					continue
				rs.append(p.r)
				gs.append(p.g)
				bs.append(p.b)
		if rs.size() >= 5:
			break
	if rs.size() < 3:
		return Color.TRANSPARENT
	rs.sort()
	gs.sort()
	bs.sort()
	var mid := rs.size() / 2
	return Color(rs[mid], gs[mid], bs[mid], 1.0)

static func has_clear_margins(image: Image) -> bool:
	if image == null or image.is_empty() or image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _alpha_bounds(image)
	return bounds.size.x > 0 and bounds.position.x >= MIN_MARGIN and bounds.position.y >= MIN_MARGIN \
		and SIZE.x - bounds.end.x >= MIN_MARGIN and SIZE.y - bounds.end.y >= MIN_MARGIN

static func _alpha_bounds(image: Image) -> Rect2i:
	var left := SIZE.x
	var top := SIZE.y
	var right := -1
	var bottom := -1
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a >= 0.01:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

# Board layout: two rows of four background comparisons (before/after), a row
# of six enlarged contour details (before/after pairs), then four 192px rows.
static func build_review(before: Image, after: Image, forest: Image, output_path: String) -> Error:
	if before == null or after == null or forest == null or before.get_size() != SIZE or after.get_size() != SIZE:
		return ERR_INVALID_DATA
	var canvas := Image.create(1920, 2520, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	for row in range(4):
		for col in range(2):
			var panel := Image.create(940, 430, false, Image.FORMAT_RGBA8)
			_fill_background(panel, row, forest)
			var image := before if col == 0 else after
			var bounds := _alpha_bounds(image)
			var figure := _fit(image.get_region(bounds), Vector2i(395, 410))
			panel.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((940 - figure.get_width()) / 2, 10))
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(col * 955 + 5, row * 440 + 5))
	# Six details selected over all requested contour zones.
	var crops := [Rect2i(230, 95, 520, 360), Rect2i(645, 205, 285, 195),
		Rect2i(615, 305, 270, 230), Rect2i(800, 335, 325, 225),
		Rect2i(135, 900, 335, 275), Rect2i(920, 890, 255, 280)]
	for i in range(crops.size()):
		var panel := Image.create(310, 360, false, Image.FORMAT_RGBA8)
		panel.fill(Color("#292e33"))
		for col in range(2):
			var image := before if col == 0 else after
			var crop := image.get_region(crops[i])
			var fitted := _fit(crop, Vector2i(145, 345))
			panel.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i(col * 155 + (155 - fitted.get_width()) / 2, 8))
		canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(5 + i * 318, 1770))
	# Game-scale silhouette preview, same 192px height on each background.
	for row in range(4):
		for col in range(2):
			var panel := Image.create(940, 170, false, Image.FORMAT_RGBA8)
			_fill_background(panel, row, forest)
			var image := before if col == 0 else after
			var bounds := _alpha_bounds(image)
			var figure := image.get_region(bounds)
			figure.resize(maxi(1, roundi(float(figure.get_width()) * 192.0 / figure.get_height())), 192, Image.INTERPOLATE_LANCZOS)
			panel.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((940 - figure.get_width()) / 2, 0))
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(col * 955 + 5, 2140 + row * 95))
	return _save_png(canvas, output_path)

static func _fill_background(image: Image, row: int, forest: Image) -> void:
	if row == 0:
		image.fill(Color.WHITE)
	elif row == 1:
		image.fill(Color("#080a0c"))
	elif row == 2:
		for y in range(0, image.get_height(), 24):
			for x in range(0, image.get_width(), 24):
				image.fill_rect(Rect2i(x, y, mini(24, image.get_width() - x), mini(24, image.get_height() - y)), Color("#3d4247") if ((x / 24 + y / 24) % 2 == 0) else Color("#292e33"))
	else:
		var resized := forest.duplicate()
		resized.resize(image.get_width(), image.get_height(), Image.INTERPOLATE_LANCZOS)
		image.blit_rect(resized, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)

static func _fit(source: Image, limit: Vector2i) -> Image:
	var scale := minf(float(limit.x) / source.get_width(), float(limit.y) / source.get_height())
	var result := source.duplicate()
	result.resize(maxi(1, roundi(source.get_width() * scale)), maxi(1, roundi(source.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return result

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _save_png(image: Image, path: String) -> Error:
	var dir := path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
		if err != OK:
			return err
	return image.save_png(path)

static func _resolve(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path

func _fail(message: String, code: int) -> void:
	push_error("player_attack2_v4_contour: " + message + " (code %d)" % code)
	quit(code)
