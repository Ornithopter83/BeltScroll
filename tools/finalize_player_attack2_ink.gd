extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const SOURCE := "res://assets/art/player/elven_fighter_attack2_reference_v4_contour_candidate_1254x1254.png"
const INK_ATTACK1 := "res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png"
const INK_ATTACK3 := "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack2_v4_ink_final_gate.png"

const CODE_USAGE := 2
const CODE_SOURCE := 3
const CODE_ATTACK1 := 4
const CODE_ATTACK3 := 5
const CODE_FOREST := 6
const CODE_OUTPUT := 7
const CODE_PROTECTED := 8

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("Usage: godot --headless --path . --script res://tools/finalize_player_attack2_ink.gd")
		quit(0)
		return
	if not args.is_empty():
		_fail("unexpected argument", CODE_USAGE)
		return
	var protected := [SOURCE, INK_ATTACK1, INK_ATTACK3]
	var protected_bytes: Array[PackedByteArray] = []
	for i in range(protected.size()):
		var full := _resolve(protected[i])
		if not FileAccess.file_exists(full):
			_fail("protected reference is missing: " + protected[i], [CODE_SOURCE, CODE_ATTACK1, CODE_ATTACK3][i])
			return
		protected_bytes.append(FileAccess.get_file_as_bytes(full))
	var source := _load_png(_resolve(SOURCE))
	var attack1 := _load_png(_resolve(INK_ATTACK1))
	var attack3 := _load_png(_resolve(INK_ATTACK3))
	var forest := _load_png(_resolve(FOREST))
	if source == null or source.get_size() != SIZE or source.get_format() != Image.FORMAT_RGBA8:
		_fail("attack2 v4 contour source is not RGBA8 1254×1254", CODE_SOURCE)
		return
	if attack1 == null or attack1.get_size() != SIZE:
		_fail("approved attack1 ink reference is invalid", CODE_ATTACK1)
		return
	if attack3 == null or attack3.get_size() != SIZE:
		_fail("approved attack3 ink reference is invalid", CODE_ATTACK3)
		return
	if forest == null or forest.is_empty():
		_fail("Forest Ruins background is invalid", CODE_FOREST)
		return
	var result := repair_ink(source, attack1, attack3)
	if result.is_empty() or int(result.changed) <= 0:
		_fail("no alpha-edge red contamination was locally restored", CODE_SOURCE)
		return
	var error := _save_png(result.image, _resolve(OUTPUT))
	if error == OK:
		error = build_review(source, result.image, forest, _resolve(REVIEW))
	if error != OK:
		_fail("candidate or comparison board could not be saved: %s" % error_string(error), CODE_OUTPUT)
		return
	for i in range(protected.size()):
		if FileAccess.get_file_as_bytes(_resolve(protected[i])) != protected_bytes[i]:
			_fail("protected source changed: " + protected[i], CODE_PROTECTED)
			return
	print("player_attack2_ink_final: %d boundary pixels neutralized (%d components; %d palette/local restorations); inputs preserved; visual approval pending" % [result.changed, result.components, result.local_restored])
	quit(0)

# Red pixels are considered only when they belong to a connected red component
# that reaches the actual alpha edge, and only within a three-pixel inward band.
# RGB is restored from nearby dark-brown contour pixels; a palette learned from
# approved attack1/3 contour edges constrains fallback colors. Alpha is exact.
static func repair_ink(source: Image, attack1: Image, attack3: Image) -> Dictionary:
	if source == null or attack1 == null or attack3 == null or source.is_empty() \
		or source.get_size() != SIZE or attack1.get_size() != SIZE or attack3.get_size() != SIZE:
		return {}
	var palette := _approved_ink_palette(attack1, attack3)
	if palette.is_empty():
		return {}
	var edge_distance := _alpha_edge_distance(source, 3)
	var red := PackedByteArray()
	red.resize(SIZE.x * SIZE.y)
	for zone_value in _zones():
		var zone: Rect2i = zone_value
		for y in range(zone.position.y, zone.end.y):
			for x in range(zone.position.x, zone.end.x):
				var index := y * SIZE.x + x
				var pixel := source.get_pixel(x, y)
				if edge_distance[index] > 0 and _red_contour(pixel) and not _protected_warm(pixel):
					red[index] = 1
	var visited := PackedByteArray()
	visited.resize(red.size())
	var output := source.duplicate()
	var changed := 0
	var local_restored := 0
	var components := 0
	for start in range(red.size()):
		if red[start] == 0 or visited[start] != 0:
			continue
		var component: Array[int] = [start]
		visited[start] = 1
		var head := 0
		var touches_alpha_edge := false
		while head < component.size():
			var index := component[head]
			head += 1
			var px := index % SIZE.x
			var py := int(index / SIZE.x)
			if edge_distance[index] > 0:
				touches_alpha_edge = true
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := px + ox
					var ny := py + oy
					if nx < 0 or ny < 0 or nx >= SIZE.x or ny >= SIZE.y:
						continue
					var ni := ny * SIZE.x + nx
					if red[ni] != 0 and visited[ni] == 0:
						visited[ni] = 1
						component.append(ni)
		if not touches_alpha_edge:
			continue
		components += 1
		for index in component:
			if edge_distance[index] <= 0 or edge_distance[index] > 3:
				continue
			var x := index % SIZE.x
			var y := int(index / SIZE.x)
			var original := source.get_pixel(x, y)
			var local := _local_ink(source, x, y)
			var restored: Color
			if local.a > 0.0:
				restored = local
				local_restored += 1
			else:
				restored = _nearest_approved_ink(palette, original, _neighbor_luminance(source, x, y))
			if restored.a <= 0.0:
				continue
			output.set_pixel(x, y, Color(restored.r, restored.g, restored.b, original.a))
			changed += 1
	return {"image": output, "changed": changed, "components": components,
		"local_restored": local_restored, "edge_distance": edge_distance}

static func _zones() -> Array[Rect2i]:
	return [
		Rect2i(215, 85, 550, 390), # ponytail strands and knot
		Rect2i(635, 190, 330, 310), # face, ear, hair and inside arm
		Rect2i(790, 300, 370, 300), # glove and backfist
		Rect2i(125, 880, 360, 315), # left boot and foot anchor
		Rect2i(900, 870, 285, 325), # right boot and foot anchor
	]

static func _red_contour(p: Color) -> bool:
	# This identifies candidate red contamination only; edge connectivity is the
	# primary gate, preventing ordinary warm skin and gold interior pixels from selection.
	return p.a >= 0.10 and p.r - p.g >= 0.12 and p.r - p.b >= 0.10 \
		and p.r > 0.16 and (p.h <= 0.055 or p.h >= 0.965)

static func _protected_warm(p: Color) -> bool:
	# Keep the bright, moderately saturated warm range used by skin and gold trim.
	return p.a >= 0.45 and p.v >= 0.36 and p.r > p.g and p.g > p.b \
		and p.r - p.b >= 0.08 and p.s <= 0.78 and p.g >= 0.16

static func _alpha_edge_distance(image: Image, max_distance: int) -> PackedByteArray:
	var distance := PackedByteArray()
	distance.resize(SIZE.x * SIZE.y)
	var queue: Array[int] = []
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var p := image.get_pixel(x, y)
			if p.a < 0.08:
				continue
			var edge := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if ox == 0 and oy == 0:
						continue
					var nx := x + ox
					var ny := y + oy
					if nx < 0 or ny < 0 or nx >= SIZE.x or ny >= SIZE.y or image.get_pixel(nx, ny).a < 0.08:
						edge = true
						break
				if edge:
					break
			if edge:
				var index := y * SIZE.x + x
				distance[index] = 1
				queue.append(index)
	var head := 0
	while head < queue.size():
		var index := queue[head]
		head += 1
		var d := int(distance[index])
		if d >= max_distance:
			continue
		var x := index % SIZE.x
		var y := int(index / SIZE.x)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				var nx := x + ox
				var ny := y + oy
				if nx < 0 or ny < 0 or nx >= SIZE.x or ny >= SIZE.y:
					continue
				var ni := ny * SIZE.x + nx
				if distance[ni] == 0 and image.get_pixel(nx, ny).a >= 0.08:
					distance[ni] = d + 1
					queue.append(ni)
	return distance

static func _approved_ink_palette(first: Image, second: Image) -> Array[Color]:
	var colors: Array[Color] = []
	for image_value in [first, second]:
		var image: Image = image_value
		var distance := _alpha_edge_distance(image, 2)
		for y in range(SIZE.y):
			for x in range(SIZE.x):
				if distance[y * SIZE.x + x] == 0:
					continue
				var p := image.get_pixel(x, y)
				if p.a >= 0.78 and _is_neutral_ink(p):
					colors.append(Color(p.r, p.g, p.b, 1.0))
	return colors

static func _is_neutral_ink(p: Color) -> bool:
	return p.a >= 0.70 and p.v <= 0.43 and p.r >= p.g and p.g >= p.b \
		and p.r - p.b <= 0.22 and p.s <= 0.58

static func _local_ink(image: Image, x: int, y: int) -> Color:
	var rs: Array[float] = []
	var gs: Array[float] = []
	var bs: Array[float] = []
	for radius in range(1, 5):
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				if maxi(absi(ox), absi(oy)) != radius:
					continue
				var nx := x + ox
				var ny := y + oy
				if nx < 0 or ny < 0 or nx >= SIZE.x or ny >= SIZE.y:
					continue
				var p := image.get_pixel(nx, ny)
				if p.a < 0.75 or _red_contour(p) or not _is_neutral_ink(p):
					continue
				rs.append(p.r)
				gs.append(p.g)
				bs.append(p.b)
		if rs.size() >= 3:
			break
	if rs.size() < 2:
		return Color.TRANSPARENT
	rs.sort()
	gs.sort()
	bs.sort()
	var middle := rs.size() / 2
	return Color(rs[middle], gs[middle], bs[middle], 1.0)

static func _neighbor_luminance(image: Image, x: int, y: int) -> float:
	var values: Array[float] = []
	for oy in range(-4, 5):
		for ox in range(-4, 5):
			if ox == 0 and oy == 0:
				continue
			var nx := x + ox
			var ny := y + oy
			if nx < 0 or ny < 0 or nx >= SIZE.x or ny >= SIZE.y:
				continue
			var p := image.get_pixel(nx, ny)
			if p.a >= 0.75 and not _red_contour(p) and _is_neutral_ink(p):
				values.append(p.v)
	if values.is_empty():
		return 0.18
	values.sort()
	return values[values.size() / 2]

static func _nearest_approved_ink(palette: Array[Color], original: Color, target_v: float) -> Color:
	var best := Color.TRANSPARENT
	var best_score := INF
	for color in palette:
		var score := absf(color.v - target_v) * 1.8 + absf(color.r - original.r) \
			+ absf(color.g - original.g) * 0.65 + absf(color.b - original.b) * 0.45
		if score < best_score:
			best_score = score
			best = color
	return best

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

static func red_boundary_count(image: Image) -> int:
	var distance := _alpha_edge_distance(image, 3)
	var total := 0
	for zone_value in _zones():
		var zone: Rect2i = zone_value
		for y in range(zone.position.y, zone.end.y):
			for x in range(zone.position.x, zone.end.x):
				var pixel := image.get_pixel(x, y)
				if distance[y * SIZE.x + x] > 0 and _red_contour(pixel) and not _protected_warm(pixel):
					total += 1
	return total

static func build_review(before: Image, after: Image, forest: Image, output_path: String) -> Error:
	if before == null or after == null or forest == null or before.get_size() != SIZE or after.get_size() != SIZE:
		return ERR_INVALID_DATA
	var canvas := Image.create(1920, 2580, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	# Four background rows, with before/after side-by-side in every row.
	for row in range(4):
		for col in range(2):
			var panel := Image.create(940, 430, false, Image.FORMAT_RGBA8)
			_fill_background(panel, row, forest)
			panel.fill_rect(Rect2i(0, 0, panel.get_width(), 22), Color("#171b20"))
			_draw_label(panel, Vector2i(8, 7), "BEFORE" if col == 0 else "AFTER")
			var image := before if col == 0 else after
			var bounds := _alpha_bounds(image)
			var figure := _fit(image.get_region(bounds), Vector2i(395, 380))
			panel.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((940 - figure.get_width()) / 2, 28))
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(col * 955 + 5, row * 440 + 5))
	# Enlarged before/after crops for ponytail, face/arm, glove and boots.
	var crops := [Rect2i(300, 190, 135, 110), Rect2i(720, 225, 135, 120),
		Rect2i(675, 345, 135, 115), Rect2i(970, 355, 140, 120),
		Rect2i(155, 1010, 135, 130), Rect2i(990, 980, 140, 130)]
	for i in range(crops.size()):
		var panel := Image.create(376, 360, false, Image.FORMAT_RGBA8)
		panel.fill(Color("#292e33"))
		panel.fill_rect(Rect2i(0, 0, panel.get_width(), 20), Color("#171b20"))
		_draw_label(panel, Vector2i(8, 7), "BEFORE")
		_draw_label(panel, Vector2i(196, 7), "AFTER")
		for col in range(2):
			var img := before if col == 0 else after
			var crop := img.get_region(crops[i])
			var fitted := _fit(crop, Vector2i(180, 325))
			panel.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i(col * 188 + (188 - fitted.get_width()) / 2, 28))
		canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(5 + i * 382, 1780))
	# Game-scale preview: four 192px high pairs on the same four backgrounds.
	for row in range(4):
		for col in range(2):
			var panel := Image.create(940, 170, false, Image.FORMAT_RGBA8)
			_fill_background(panel, row, forest)
			var img := before if col == 0 else after
			var bounds := _alpha_bounds(img)
			var figure := img.get_region(bounds)
			figure.resize(maxi(1, roundi(float(figure.get_width()) * 192.0 / figure.get_height())), 192, Image.INTERPOLATE_LANCZOS)
			panel.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((940 - figure.get_width()) / 2, 0))
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(col * 955 + 5, 2160 + row * 78))
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

static func _draw_label(image: Image, origin: Vector2i, label: String) -> void:
	var glyphs := {
		"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
		"B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
		"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
		"F": ["11111", "10000", "10000", "11110", "10000", "10000", "10000"],
		"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
		"R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
		"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"]
	}
	var x := origin.x
	for character in label:
		if glyphs.has(character):
			var rows: Array = glyphs[character]
			for y in range(rows.size()):
				for dx in range(rows[y].length()):
					if rows[y][dx] == "1":
						image.fill_rect(Rect2i(x + dx, origin.y + y, 1, 1), Color.WHITE)
		x += 6

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
		var error := DirAccess.make_dir_recursive_absolute(dir)
		if error != OK:
			return error
	return image.save_png(path)

static func _resolve(path: String) -> String:
	return ProjectSettings.globalize_path(path) if path.begins_with("res://") else path

func _fail(message: String, code: int) -> void:
	push_error("player_attack2_ink_final: " + message + " (code %d)" % code)
	quit(code)
