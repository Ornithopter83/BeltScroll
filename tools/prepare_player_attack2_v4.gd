extends SceneTree

const SIZE := Vector2i(1254, 1254)
const CONTENT_LIMIT := 1074
const MIN_MARGIN := 90
const SOURCE := "res://assets/art/player/elven_fighter_attack2_reference_v4_1254x1254.png"
const ATTACK1_CLEAN := "res://assets/art/player/elven_fighter_attack1_reference_v1_clean_candidate_1254x1254.png"
const ATTACK3_CLEAN := "res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png"
const V8_CLEAN := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack2_reference_v4_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_attack2_reference_v4_clean_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack2_v4_gate.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const CONTEXT_RADIUS := 6
const CODE_USAGE := 2
const CODE_SOURCE := 3
const CODE_REFERENCE := 4
const CODE_FOREST := 5
const CODE_OUTPUT := 6
const CODE_MUTATED := 7

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("Usage: godot --headless --path . --script res://tools/prepare_player_attack2_v4.gd")
		quit(0)
		return
	if not args.is_empty():
		_fail("unexpected argument", CODE_USAGE)
		return
	var source_path := _resolve(SOURCE)
	if not FileAccess.file_exists(source_path):
		_fail("attack2 v4 source PNG is missing", CODE_SOURCE)
		return
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	if source == null or source.get_size() != SIZE:
		_fail("attack2 v4 source PNG is not a valid 1254x1254 image", CODE_SOURCE)
		return
	var reference := _load_png(_resolve(V8_CLEAN))
	if reference == null or reference.get_size() != SIZE:
		_fail("approved v8 clean reference is missing or invalid", CODE_REFERENCE)
		return
	var attack1 := _load_png(_resolve(ATTACK1_CLEAN))
	if attack1 == null or attack1.get_size() != SIZE:
		_fail("attack1 clean comparison reference is missing or invalid", CODE_REFERENCE)
		return
	var attack3 := _load_png(_resolve(ATTACK3_CLEAN))
	if attack3 == null or attack3.get_size() != SIZE:
		_fail("attack3 clean comparison reference is missing or invalid", CODE_REFERENCE)
		return
	var forest := _load_png(_resolve(FOREST))
	if forest == null:
		_fail("Forest Ruins review image is missing or invalid", CODE_FOREST)
		return
	var safe := normalize(source)
	if safe == null or not has_clear_margins(safe):
		_fail("safe candidate normalization failed", CODE_SOURCE)
		return
	var cleaned := clean_fringes(safe)
	if cleaned.is_empty():
		_fail("localized fringe cleanup failed", CODE_SOURCE)
		return
	var err := _save_png(safe, _resolve(SAFE))
	if err == OK:
		err = _save_png(cleaned["image"], _resolve(CLEAN))
	if err == OK:
		err = build_review(source, safe, cleaned["image"], reference, attack1, attack3, forest, _resolve(REVIEW))
	if err != OK:
		_fail("candidate or review image could not be saved: %s" % error_string(err), CODE_OUTPUT)
		return
	if FileAccess.get_file_as_bytes(source_path) != source_bytes:
		_fail("attack2 source bytes changed during preparation", CODE_MUTATED)
		return
	print("player_attack2_v4: safe/clean/review generated; %d fringe pixels changed, source preserved (visual approval pending)" % int(cleaned["changed"]))
	quit(0)

# Fits the full alpha silhouette without enlargement into a centered 1074px box.
# The 1254px RGBA canvas then has at least 90 transparent pixels on each side.
static func normalize(source: Image) -> Image:
	if source == null or source.is_empty():
		return null
	var rgba := source.duplicate()
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba.convert(Image.FORMAT_RGBA8)
	var bounds := _alpha_bounds(rgba)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var scale := minf(1.0, minf(float(CONTENT_LIMIT) / bounds.size.x, float(CONTENT_LIMIT) / bounds.size.y))
	var size := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var content: Image = rgba.get_region(bounds)
	if content.get_size() != size:
		content.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	var result := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(content, Rect2i(Vector2i.ZERO, size), (SIZE - size) / 2)
	return result

# Erases only coherent, locally anomalous saturated-red pixels. Stains connected
# to transparency are cleared; enclosed red specks inherit a nearby median color.
static func clean_fringes(source: Image) -> Dictionary:
	if source == null or source.is_empty() or source.get_size() != SIZE:
		return {}
	var w := source.get_width()
	var h := source.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in range(CONTEXT_RADIUS, h - CONTEXT_RADIUS):
		for x in range(CONTEXT_RADIUS, w - CONTEXT_RADIUS):
			var p := source.get_pixel(x, y)
			# Keep RGB contamination from fully transparent pixels out of the
			# subsequent Lanczos normalization too; these pixels can bleed inward.
			if p.s < 0.48 or not _red_stain_candidate(p):
				continue
			mask[y * w + x] = 1
	var components := _components(mask, w, h)
	var result := source.duplicate()
	var changed := 0
	for component in components:
		var boundary_contamination := false
		for value in component:
			var index := int(value)
			var px := index % w
			var py := floori(float(index) / w)
			if source.get_pixel(px, py).a < 0.99 or _touches_transparency(source, px, py):
				boundary_contamination = true
				break
		for value in component:
			var index := int(value)
			var x := index % w
			var y := floori(float(index) / w)
			var old := source.get_pixel(x, y)
			# Clear a connected stain as one edge component when any pixel reaches
			# transparent/partial-alpha space. Enclosed opaque specks are recolored.
			if boundary_contamination:
				result.set_pixel(x, y, Color(old.r, old.g, old.b, 0.0))
				changed += 1
			else:
				var repair := _repair_color(source, mask, x, y, w, h)
				if repair.a > 0.0:
					result.set_pixel(x, y, Color(repair.r, repair.g, repair.b, old.a))
					changed += 1
	return {"image": result, "changed": changed}

static func has_clear_margins(image: Image) -> bool:
	if image == null or image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var b := _alpha_bounds(image)
	return b.size.x > 0 and b.position.x >= MIN_MARGIN and b.position.y >= MIN_MARGIN \
		and SIZE.x - b.end.x >= MIN_MARGIN and SIZE.y - b.end.y >= MIN_MARGIN

static func _red_outlier(p: Color, context: Color) -> bool:
	if context.a <= 0.0:
		return false
	var hue_delta := absf(p.h - context.h)
	hue_delta = minf(hue_delta, 1.0 - hue_delta)
	var distance := Vector3(p.r, p.g, p.b).distance_to(Vector3(context.r, context.g, context.b))
	return p.s > 0.58 and context.s < p.s - 0.18 and hue_delta > 0.035 \
		and _warm_fringe_candidate(p) and distance > 0.25 \
		and (absf(p.v - context.v) > 0.06 or hue_delta > 0.075)

static func _red_stain_candidate(p: Color) -> bool:
	# Scarlet/magenta contamination is distinct from skin, leather and gold hues.
	return p.s >= 0.48 and p.v >= 0.22 and p.r - p.g >= 0.16 and p.r - p.b >= 0.12 \
		and (p.h <= 0.035 or p.h >= 0.965)

static func _warm_fringe_candidate(p: Color) -> bool:
	# Red fringe or unnaturally bright yellow; neighborhood tests protect gold trim.
	return p.r - maxf(p.g, p.b) > 0.20 or (p.r > 0.82 and p.g > 0.58 and p.b < 0.30)

static func _context_color(image: Image, x: int, y: int, radius: int) -> Color:
	var rs: Array[float] = []; var gs: Array[float] = []; var bs: Array[float] = []
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if ox == 0 and oy == 0:
				continue
			var p := image.get_pixel(x + ox, y + oy)
			if p.a < 0.65:
				continue
			rs.append(p.r); gs.append(p.g); bs.append(p.b)
	if rs.size() < 4:
		return Color.TRANSPARENT
	rs.sort(); gs.sort(); bs.sort()
	var middle := rs.size() / 2
	return Color(rs[middle], gs[middle], bs[middle], 1.0)

static func _repair_color(image: Image, mask: PackedByteArray, x: int, y: int, w: int, h: int) -> Color:
	var rs: Array[float] = []; var gs: Array[float] = []; var bs: Array[float] = []
	for radius in range(1, 6):
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				if maxi(absi(ox), absi(oy)) != radius:
					continue
				var nx := x + ox; var ny := y + oy
				if nx < 0 or ny < 0 or nx >= w or ny >= h:
					continue
				var ni := ny * w + nx
				var p := image.get_pixel(nx, ny)
				if mask[ni] != 0 or p.a < 0.65:
					continue
				rs.append(p.r); gs.append(p.g); bs.append(p.b)
		if rs.size() >= 5:
			break
	if rs.size() < 3:
		return Color.TRANSPARENT
	rs.sort(); gs.sort(); bs.sort()
	var mid := rs.size() / 2
	return Color(rs[mid], gs[mid], bs[mid], 1.0)

static func _components(mask: PackedByteArray, w: int, h: int) -> Array[Array]:
	var visited := PackedByteArray(); visited.resize(w * h)
	var result: Array[Array] = []
	for start in range(mask.size()):
		if mask[start] == 0 or visited[start] != 0:
			continue
		var points: Array[int] = [start]
		visited[start] = 1
		var head := 0
		while head < points.size():
			var index: int = points[head]; head += 1
			var x := index % w; var y := index / w
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox; var ny := y + oy
					if nx < 0 or ny < 0 or nx >= w or ny >= h:
						continue
					var ni := ny * w + nx
					if mask[ni] != 0 and visited[ni] == 0:
						visited[ni] = 1; points.append(ni)
		result.append(points)
	return result

static func _touches_transparency(image: Image, x: int, y: int) -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			if image.get_pixel(x + ox, y + oy).a < 0.12:
				return true
	return false

static func build_review(original: Image, safe: Image, clean: Image, reference: Image, attack1: Image, attack3: Image, forest: Image, output_path: String) -> Error:
	if original == null or safe == null or clean == null or reference == null or attack1 == null or attack3 == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if safe.get_size() != SIZE or clean.get_size() != SIZE or reference.get_size() != SIZE or attack1.get_size() != SIZE or attack3.get_size() != SIZE or forest.is_empty():
		return ERR_INVALID_DATA
	var variants: Array[Image] = [original, safe, clean]
	var canvas := Image.create(2560, 3230, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	# Each background row presents original, normalized safe, and cleaned attack2.
	for row in range(4):
		for col in range(3):
			var tile := Image.create(620, 480, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var variant := variants[col]
			var bounds := _alpha_bounds(variant)
			if bounds.size.x <= 0:
				return ERR_INVALID_DATA
			var figure := _fit(variant.get_region(bounds), Vector2i(270, 360))
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i(8, 8))
			# Four enlarged identity/pose details: ponytail, ear/face, elbow, and glove.
			var details := [Rect2(0.02, 0.04, 0.58, 0.34), Rect2(0.60, 0.07, 0.24, 0.20),
				Rect2(0.48, 0.24, 0.34, 0.30), Rect2(0.82, 0.20, 0.18, 0.24)]
			for detail_index in range(details.size()):
				var detail := _fit(_crop_relative(variant, bounds, details[detail_index]), Vector2i(80, 132))
				tile.blend_rect(detail, Rect2i(Vector2i.ZERO, detail.get_size()), Vector2i(292 + detail_index * 82, 16))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, row * 490 + 5))
	# Compare attack2 against attack1 and v8 at exactly 192px silhouette height
	# over all four backgrounds, so color fringes remain visible at game scale.
	var comparisons: Array[Image] = [clean, attack1, attack3, reference]
	for row in range(4):
		for col in range(4):
			var tile := Image.create(620, 300, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var image := comparisons[col]
			var bounds := _alpha_bounds(image)
			if bounds.size.x <= 0:
				return ERR_INVALID_DATA
			var figure := image.get_region(bounds)
			var width := maxi(1, roundi(float(figure.get_width()) * 192.0 / figure.get_height()))
			figure.resize(width, 192, Image.INTERPOLATE_LANCZOS)
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((620 - width) / 2, 45))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, 1970 + row * 310))
	return _save_png(canvas, output_path)

static func _fill_background(image: Image, row: int, forest: Image) -> void:
	if row == 0:
		image.fill(Color.WHITE)
	elif row == 1:
		image.fill(Color("#080a0c"))
	elif row == 2:
		for y in range(0, image.get_height(), 24):
			for x in range(0, image.get_width(), 24):
				var c := Color("#3d4247") if ((x / 24 + y / 24) % 2 == 0) else Color("#292e33")
				image.fill_rect(Rect2i(x, y, mini(24, image.get_width() - x), mini(24, image.get_height() - y)), c)
	else:
		var resized := forest.duplicate()
		resized.resize(image.get_width(), image.get_height(), Image.INTERPOLATE_LANCZOS)
		image.blit_rect(resized, Rect2i(Vector2i.ZERO, image.get_size()), Vector2i.ZERO)

static func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width(); var top := image.get_height(); var right := -1; var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x); top = mini(top, y); right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var x := bounds.position.x + floori(region.position.x * bounds.size.x)
	var y := bounds.position.y + floori(region.position.y * bounds.size.y)
	var right := bounds.position.x + ceili((region.position.x + region.size.x) * bounds.size.x)
	var bottom := bounds.position.y + ceili((region.position.y + region.size.y) * bounds.size.y)
	var rect := Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)

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
	push_error("player_attack2_v4: " + message + " (code %d)" % code)
	quit(code)

