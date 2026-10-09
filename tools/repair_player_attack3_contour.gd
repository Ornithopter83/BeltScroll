extends SceneTree

const SIZE := Vector2i(1254, 1254)
const SOURCE := "res://assets/art/player/elven_fighter_attack3_reference_v2_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack3_reference_v2_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const REVIEW := "res://assets/art/review/player_attack3_contour_gate.png"
const CODE_USAGE := 2
const CODE_SOURCE := 3
const CODE_SAFE := 4
const CODE_CLEAN := 5
const CODE_FOREST := 6
const CODE_OUTPUT := 7
const CODE_MUTATED := 8

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("Usage: godot --headless --path . --script res://tools/repair_player_attack3_contour.gd")
		quit(0)
		return
	if not args.is_empty():
		_fail("unexpected argument", CODE_USAGE)
		return
	var protected_paths := [SOURCE, SAFE, CLEAN]
	var protected_bytes: Array[PackedByteArray] = []
	for path in protected_paths:
		var full := _resolve(path)
		if not FileAccess.file_exists(full):
			_fail("protected input is missing: " + path, CODE_SOURCE if path == SOURCE else (CODE_SAFE if path == SAFE else CODE_CLEAN))
			return
		protected_bytes.append(FileAccess.get_file_as_bytes(full))
	var source := _load_png(_resolve(SOURCE))
	var safe := _load_png(_resolve(SAFE))
	var clean := _load_png(_resolve(CLEAN))
	var forest := _load_png(_resolve(FOREST))
	if source == null or source.get_size() != SIZE:
		_fail("attack3 v2 original is invalid", CODE_SOURCE)
		return
	if safe == null or safe.get_size() != SIZE:
		_fail("attack3 v2 safe image is invalid", CODE_SAFE)
		return
	if clean == null or clean.get_size() != SIZE:
		_fail("attack3 v2 clean candidate is invalid", CODE_CLEAN)
		return
	if forest == null:
		_fail("Forest Ruins image is invalid", CODE_FOREST)
		return
	var repaired := repair_contour(clean, safe)
	if repaired.is_empty():
		_fail("localized contour repair failed", CODE_CLEAN)
		return
	var error := _save_png(repaired.image, _resolve(OUTPUT))
	if error == OK:
		error = build_review(clean, repaired.image, forest, _resolve(REVIEW))
	if error != OK:
		_fail("candidate or review could not be saved: %s" % error_string(error), CODE_OUTPUT)
		return
	for i in range(protected_paths.size()):
		if FileAccess.get_file_as_bytes(_resolve(protected_paths[i])) != protected_bytes[i]:
			_fail("protected input changed: " + protected_paths[i], CODE_MUTATED)
			return
	print("player_attack3_contour: %d pixels adjusted; originals/safe/clean preserved; visual approval pending" % repaired.changed)
	quit(0)

# Only four contour zones are eligible: face/neck, bare raised arm, and fist.
# Opaque red islands are repaired from the local median; translucent pixels
# touching transparency are cleared to alpha zero. All other source pixels stay exact.
static func repair_contour(source: Image, donor: Image = null) -> Dictionary:
	if source == null or source.is_empty() or source.get_size() != SIZE:
		return {}
	if donor != null and (donor.is_empty() or donor.get_size() != SIZE):
		return {}
	var result := source.duplicate()
	var changed := 0
	var removed := 0
	var restored := 0
	var red_mask := PackedByteArray()
	red_mask.resize(SIZE.x * SIZE.y)
	var exterior_mask := PackedByteArray()
	exterior_mask.resize(SIZE.x * SIZE.y)
	# Earlier cleanup punched small holes through the mouth. Restore only missing
	# pixels in this tiny interior patch from the unchanged safe version.
	if donor != null:
		for y in range(315, 353):
			for x in range(698, 745):
				if source.get_pixel(x, y).a < 0.08 and donor.get_pixel(x, y).a >= 0.92:
					result.set_pixel(x, y, donor.get_pixel(x, y))
					changed += 1
					restored += 1
	for y in range(84, 492):
		for x in range(545, 990):
			var p := source.get_pixel(x, y)
			if _in_target_zone(x, y) and not _mouth_guard(x, y) and p.a >= 0.12 and _red_outlier(p):
				red_mask[y * SIZE.x + x] = 1
	var visited := PackedByteArray()
	visited.resize(red_mask.size())
	for start in range(red_mask.size()):
		if red_mask[start] == 0 or visited[start] != 0:
			continue
		var component: Array[int] = [start]
		visited[start] = 1
		var head := 0
		var exterior := false
		while head < component.size():
			var index := component[head]
			head += 1
			var px := index % SIZE.x
			var py := int(index / SIZE.x)
			if _touches_transparency(source, px, py, 2):
				exterior = true
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := px + ox
					var ny := py + oy
					if nx < 0 or ny < 0 or nx >= SIZE.x or ny >= SIZE.y:
						continue
					var ni := ny * SIZE.x + nx
					if red_mask[ni] != 0 and visited[ni] == 0:
						visited[ni] = 1
						component.append(ni)
		if exterior:
			for index in component:
				exterior_mask[index] = 1
	for y in range(84, 492):
		for x in range(545, 990):
			if not _in_target_zone(x, y) or _mouth_guard(x, y):
				continue
			var pixel := source.get_pixel(x, y)
			if pixel.a < 0.12 or not _red_outlier(pixel):
				continue
			var external := exterior_mask[y * SIZE.x + x] != 0
			if external:
				result.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
				changed += 1
				removed += 1
			elif pixel.a >= 0.82 and _skin_context(source, x, y):
				var local := _local_median(source, x, y)
				if local.a > 0.0:
					result.set_pixel(x, y, Color(local.r, local.g, local.b, pixel.a))
					changed += 1
					restored += 1
	return {"image": result, "changed": changed, "removed": removed, "restored": restored}

static func _in_target_zone(x: int, y: int) -> bool:
	# Canvas-space ROIs based on the preserved 1254px v2 composition.
	var face_neck := x >= 548 and x <= 790 and y >= 250 and y <= 440
	var raised_arm := x >= 690 and x <= 955 and y >= 190 and y <= 490
	var raised_fist := x >= 895 and x <= 988 and y >= 84 and y <= 205
	return face_neck or raised_arm or raised_fist

static func _mouth_guard(x: int, y: int) -> bool:
	# Protect lips and adjacent facial linework from red-pixel heuristics.
	return x >= 700 and x <= 742 and y >= 316 and y <= 346

static func _red_outlier(p: Color) -> bool:
	return p.s >= 0.50 and p.v >= 0.22 and p.r - p.g >= 0.15 and p.r - p.b >= 0.12 \
		and (p.h <= 0.045 or p.h >= 0.965)

static func _touches_transparency(image: Image, x: int, y: int, radius: int) -> bool:
	for oy in range(-radius, radius + 1):
		for ox in range(-radius, radius + 1):
			if ox == 0 and oy == 0:
				continue
			var nx := x + ox
			var ny := y + oy
			if nx >= 0 and ny >= 0 and nx < SIZE.x and ny < SIZE.y and image.get_pixel(nx, ny).a < 0.12:
				return true
	return false

static func _skin_context(image: Image, x: int, y: int) -> bool:
	var count := 0
	for oy in range(-3, 4):
		for ox in range(-3, 4):
			if ox == 0 and oy == 0:
				continue
			var p := image.get_pixel(x + ox, y + oy)
			if p.a >= 0.82 and p.r > p.g and p.g > p.b * 0.72 and p.r - p.b > 0.10 and not _red_outlier(p):
				count += 1
	return count >= 5

static func _local_median(image: Image, x: int, y: int) -> Color:
	var rs: Array[float] = []
	var gs: Array[float] = []
	var bs: Array[float] = []
	for radius in range(1, 5):
		for oy in range(-radius, radius + 1):
			for ox in range(-radius, radius + 1):
				if maxi(absi(ox), absi(oy)) != radius:
					continue
				var p := image.get_pixel(x + ox, y + oy)
				if p.a < 0.82 or _red_outlier(p) or p.r <= p.g or p.g <= p.b * 0.72:
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

static func _alpha_bounds(image: Image, threshold := 0.01) -> Rect2i:
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

static func build_review(before: Image, after: Image, forest: Image, output_path: String) -> Error:
	if before == null or after == null or forest == null or before.get_size() != SIZE or after.get_size() != SIZE:
		return ERR_INVALID_DATA
	var canvas := Image.create(1920, 2740, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var labels := ["BEFORE", "CONTOUR", "FACE / NECK", "RAISED ARM / FIST"]
	for row in range(4):
		for col in range(4):
			var panel := Image.create(470, 410, false, Image.FORMAT_RGBA8)
			_fill_background(panel, row, forest)
			panel.fill_rect(Rect2i(0, 0, 470, 24), Color("#171b20"))
			var label: String = labels[col]
			if col < 2:
				var img := before if col == 0 else after
				var bounds := _alpha_bounds(img)
				var fit := _fit(img.get_region(bounds), Vector2i(250, 370))
				panel.blend_rect(fit, Rect2i(Vector2i.ZERO, fit.get_size()), Vector2i((470 - fit.get_width()) / 2, 30))
			else:
				var crop := img_crop(after, Rect2i(545, 245, 255, 205) if col == 2 else Rect2i(685, 82, 310, 410))
				var before_crop := img_crop(before, Rect2i(545, 245, 255, 205) if col == 2 else Rect2i(685, 82, 310, 410))
				var before_fit := _fit(before_crop, Vector2i(218, 370))
				var after_fit := _fit(crop, Vector2i(218, 370))
				panel.blend_rect(before_fit, Rect2i(Vector2i.ZERO, before_fit.get_size()), Vector2i(8 + (218 - before_fit.get_width()) / 2, 30))
				panel.blend_rect(after_fit, Rect2i(Vector2i.ZERO, after_fit.get_size()), Vector2i(244 + (218 - after_fit.get_width()) / 2, 30))
				_draw_label(panel, Vector2i(8, 16), "BEFORE")
				_draw_label(panel, Vector2i(244, 16), "AFTER")
			_draw_label(panel, Vector2i(8, 5), label)
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(5 + col * 477, 5 + row * 415))
	# Four background rows compare both source and repaired sprite at exactly 192px height.
	for row in range(4):
		for col in range(2):
			var panel := Image.create(940, 230, false, Image.FORMAT_RGBA8)
			_fill_background(panel, row, forest)
			var img := before if col == 0 else after
			var bounds := _alpha_bounds(img)
			var figure := img.get_region(bounds)
			figure.resize(maxi(1, roundi(float(figure.get_width()) * 192.0 / figure.get_height())), 192, Image.INTERPOLATE_LANCZOS)
			panel.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((940 - figure.get_width()) / 2, 24))
			_draw_label(panel, Vector2i(8, 5), "192 BEFORE" if col == 0 else "192 CONTOUR")
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(5 + col * 955, 1670 + row * 255))
	return _save_png(canvas, output_path)

static func img_crop(image: Image, rect: Rect2i) -> Image:
	return image.get_region(rect.intersection(Rect2i(Vector2i.ZERO, image.get_size())))

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

static func _fit(source: Image, limit: Vector2i) -> Image:
	var scale := minf(float(limit.x) / source.get_width(), float(limit.y) / source.get_height())
	var result := source.duplicate()
	result.resize(maxi(1, roundi(source.get_width() * scale)), maxi(1, roundi(source.get_height() * scale)), Image.INTERPOLATE_LANCZOS)
	return result

static func _draw_label(image: Image, origin: Vector2i, label: String) -> void:
	var glyphs := {"A":["01110","10001","10001","11111","10001","10001","10001"],"B":["11110","10001","10001","11110","10001","10001","11110"],"C":["01111","10000","10000","10000","10000","10000","01111"],"D":["11110","10001","10001","10001","10001","10001","11110"],"E":["11111","10000","10000","11110","10000","10000","11111"],"F":["11111","10000","10000","11110","10000","10000","10000"],"G":["01111","10000","10000","10111","10001","10001","01111"],"I":["11111","00100","00100","00100","00100","00100","11111"],"K":["10001","10010","10100","11000","10100","10010","10001"],"M":["10001","11011","10101","10101","10001","10001","10001"],"N":["10001","11001","11001","10101","10011","10011","10001"],"O":["01110","10001","10001","10001","10001","10001","01110"],"R":["11110","10001","10001","11110","10100","10010","10001"],"S":["01111","10000","10000","01110","00001","00001","11110"],"T":["11111","00100","00100","00100","00100","00100","00100"],"U":["10001","10001","10001","10001","10001","10001","01110"],"/": ["00001","00010","00100","01000","10000","00000","00000"],"1":["00100","01100","00100","00100","00100","00100","01110"],"2":["01110","10001","00001","00010","00100","01000","11111"],"9":["01110","10001","10001","01111","00001","00001","01110"]}
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
	push_error("player_attack3_contour: " + message + " (code %d)" % code)
	quit(code)
