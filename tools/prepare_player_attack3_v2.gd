extends SceneTree

const HALO_REPAIR := preload("res://tools/repair_player_color_halo.gd")

const SIZE := Vector2i(1254, 1254)
const CONTENT_LIMIT := 1074
const MIN_MARGIN := 90
const COMPARISON_HEIGHT := 192
const SOURCE := "res://assets/art/player/elven_fighter_attack3_reference_v2_1254x1254.png"
const V8_CLEAN := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack3_reference_v2_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack3_v2_gate.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
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
		print("Usage: godot --headless --path . --script res://tools/prepare_player_attack3_v2.gd")
		quit(0)
		return
	if not args.is_empty():
		_fail("unexpected argument", CODE_USAGE)
		return
	var source_path := _resolve(SOURCE)
	if not FileAccess.file_exists(source_path):
		_fail("attack3 v2 source PNG is missing", CODE_SOURCE)
		return
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	if source == null or source.get_size() != SIZE:
		_fail("attack3 v2 source PNG is not a valid 1254x1254 image", CODE_SOURCE)
		return
	var reference := _load_png(_resolve(V8_CLEAN))
	if reference == null or reference.get_size() != SIZE:
		_fail("approved v8 clean reference is missing or invalid", CODE_REFERENCE)
		return
	var forest := _load_png(_resolve(FOREST))
	if forest == null:
		_fail("Forest Ruins review image is missing or invalid", CODE_FOREST)
		return
	var safe := normalize(source)
	if safe == null or not has_clear_margins(safe):
		_fail("safe candidate normalization failed", CODE_SOURCE)
		return
	var cleanup := clean_fringes(safe)
	if cleanup.is_empty():
		_fail("localized fringe cleanup failed", CODE_SOURCE)
		return
	var clean: Image = cleanup["image"]
	var err := _save_png(safe, _resolve(SAFE))
	if err == OK:
		err = _save_png(clean, _resolve(CLEAN))
	if err == OK:
		err = build_review(source, safe, clean, reference, forest, _resolve(REVIEW))
	if err != OK:
		_fail("candidate or review image could not be saved: %s" % error_string(err), CODE_OUTPUT)
		return
	if FileAccess.get_file_as_bytes(source_path) != source_bytes:
		_fail("attack3 v2 source bytes changed during preparation", CODE_MUTATED)
		return
	print("player_attack3_v2: safe/clean/review generated; %d localized pixels changed, source preserved (visual approval pending)" % int(cleanup["changed"]))
	quit(0)

# Fits the full alpha silhouette, without enlargement, inside a centered 1074px box.
# All content pixels originate in the source; only resampling is used when it must shrink.
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
	var content_size := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var content: Image = rgba.get_region(bounds)
	if content.get_size() != content_size:
		content.resize(content_size.x, content_size.y, Image.INTERPOLATE_LANCZOS)
	var result := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(content, Rect2i(Vector2i.ZERO, content_size), (SIZE - content_size) / 2)
	return result

# Exterior red/yellow contamination is removed only when the candidate region
# connects to transparency. Enclosed anomalies are repaired from nearby normal
# opaque colors, keeping their original alpha. Restrictive hue tests spare gold trim.
static func clean_fringes(source: Image) -> Dictionary:
	if source == null or source.is_empty() or source.get_size() != SIZE:
		return {}
	var w := source.get_width()
	var h := source.get_height()
	var mask := PackedByteArray()
	mask.resize(w * h)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			var p := source.get_pixel(x, y)
			if p.a < 0.08 or not _stain_candidate(p):
				continue
			mask[y * w + x] = 1
	var result := source.duplicate()
	var changed := 0
	for component in _components(mask, w, h):
		if component.size() < 2:
			continue
		var exterior := false
		for value in component:
			var index := int(value)
			if _touches_transparency(source, index % w, int(index / w)):
				exterior = true
				break
		for value in component:
			var index := int(value)
			var x := index % w
			var y := int(index / w)
			var old := source.get_pixel(x, y)
			if exterior:
				result.set_pixel(x, y, Color(old.r, old.g, old.b, 0.0))
				changed += 1
			else:
				var repair := _repair_color(source, mask, x, y, w, h)
				if repair.a > 0.0:
					result.set_pixel(x, y, Color(repair.r, repair.g, repair.b, old.a))
					changed += 1
	# The color-component pass handles obvious external marks and enclosed spots.
	# A second edge-aware pass catches saturated warm spill that is attached to
	# the silhouette and therefore cannot be classified by connectivity alone.
	var edge_cleanup: Dictionary = HALO_REPAIR.repair_image(result)
	var edge_image: Image = edge_cleanup["image"]
	changed += int(edge_cleanup["changed"])
	return {"image": edge_image, "changed": changed}

static func has_clear_margins(image: Image) -> bool:
	if image == null or image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _alpha_bounds(image)
	return bounds.size.x > 0 and bounds.position.x >= MIN_MARGIN and bounds.position.y >= MIN_MARGIN \
		and SIZE.x - bounds.end.x >= MIN_MARGIN and SIZE.y - bounds.end.y >= MIN_MARGIN

static func _stain_candidate(p: Color) -> bool:
	if p.s < 0.55 or p.v < 0.24:
		return false
	var red := p.r - p.g >= 0.17 and p.r - p.b >= 0.13 and (p.h <= 0.045 or p.h >= 0.965)
	# Very bright lemon pixels are unlike the source's muted amber/gold ornaments.
	var yellow := p.r >= 0.92 and p.g >= 0.72 and p.b <= 0.12 and p.r - p.g <= 0.27
	return red or yellow

static func _repair_color(image: Image, mask: PackedByteArray, x: int, y: int, w: int, h: int) -> Color:
	var rs: Array[float] = []; var gs: Array[float] = []; var bs: Array[float] = []
	for radius in range(1, 7):
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
			var x := index % w; var y := int(index / w)
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

static func build_review(original: Image, safe: Image, clean: Image, reference: Image, forest: Image, output_path: String) -> Error:
	if original == null or safe == null or clean == null or reference == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if original.get_size() != SIZE or safe.get_size() != SIZE or clean.get_size() != SIZE or reference.get_size() != SIZE or forest.is_empty():
		return ERR_INVALID_DATA
	var variants: Array[Image] = [original, reference, safe, clean]
	var canvas := Image.create(2560, 3180, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	# Four columns (original, v8, safe, clean) over white, black, checker and forest.
	for row in range(4):
		for col in range(4):
			var tile := Image.create(620, 455, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			tile.fill_rect(Rect2i(0, 0, 620, 30), Color("#171b20"))
			var labels := ["ORIG", "V8", "SAFE", "CLEAN"]
			_draw_label(tile, Vector2i(12, 8), labels[col])
			var variant := variants[col]
			var bounds := _alpha_bounds(variant)
			if bounds.size.x <= 0:
				return ERR_INVALID_DATA
			var figure := _fit(variant.get_region(bounds), Vector2i(270, 390))
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((620 - figure.get_width()) / 2, 8))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, row * 465 + 5))
	# Game-scale strip: each candidate has a 192px silhouette and shared foot baseline.
	for row in range(4):
		for col in range(4):
			var tile := Image.create(620, 290, false, Image.FORMAT_RGBA8)
			_fill_background(tile, row, forest)
			var figure := comparison_figure(variants[col])
			if figure == null:
				return ERR_INVALID_DATA
			var bounds := _alpha_bounds(figure)
			tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((620 - figure.get_width()) / 2, 265 - bounds.end.y))
			canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(col * 640 + 10, 1880 + row * 300))
	return _save_png(canvas, output_path)

static func _draw_label(image: Image, origin: Vector2i, label: String) -> void:
	var glyphs := {
		"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
		"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
		"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
		"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
		"G": ["01111", "10000", "10000", "10111", "10001", "10001", "01111"],
		"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
		"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
		"N": ["10001", "11001", "11001", "10101", "10011", "10011", "10001"],
		"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
		"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
		"S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
		"V": ["10001", "10001", "10001", "10001", "01010", "01010", "00100"],
		"8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"]
	}
	var cursor_x := origin.x
	for character in label:
		var rows: Array = glyphs.get(character, [])
		for y in range(rows.size()):
			for x in range(rows[y].length()):
				if rows[y][x] == "1":
					image.fill_rect(Rect2i(cursor_x + x * 2, origin.y + y * 2, 2, 2), Color.WHITE)
		cursor_x += 12

static func comparison_figure(image: Image) -> Image:
	if image == null or image.is_empty():
		return null
	var bounds := _alpha_bounds(image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var figure := image.get_region(bounds)
	var width := maxi(1, roundi(float(figure.get_width()) * COMPARISON_HEIGHT / figure.get_height()))
	figure.resize(width, COMPARISON_HEIGHT, Image.INTERPOLATE_LANCZOS)
	return figure

static func _fill_background(image: Image, row: int, forest: Image) -> void:
	if row == 0:
		image.fill(Color.WHITE)
	elif row == 1:
		image.fill(Color("#080a0c"))
	elif row == 2:
		for y in range(0, image.get_height(), 24):
			for x in range(0, image.get_width(), 24):
				var color := Color("#3d4247") if ((x / 24 + y / 24) % 2 == 0) else Color("#292e33")
				image.fill_rect(Rect2i(x, y, mini(24, image.get_width() - x), mini(24, image.get_height() - y)), color)
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
	push_error("player_attack3_v2: " + message + " (code %d)" % code)
	quit(code)
