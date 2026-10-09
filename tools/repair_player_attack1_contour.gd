extends SceneTree

const SOURCE := "res://assets/art/player/elven_fighter_attack1_reference_v1_edge_v2_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack1_contour_gate.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const SIZE := Vector2i(1254, 1254)
const CANVAS := Vector2i(1500, 2680)
const MIN_MARGIN := 90

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty() and args.size() != 3:
		printerr("Usage: godot --headless --path . --script res://tools/repair_player_attack1_contour.gd [input.png output.png review.png]")
		quit(2)
		return
	var input_path := _resolve(args[0] if args.size() == 3 else SOURCE)
	var output_path := _resolve(args[1] if args.size() == 3 else OUTPUT)
	var review_path := _resolve(args[2] if args.size() == 3 else REVIEW)
	var err := repair_file(input_path, output_path)
	if err != OK:
		printerr("contour repair failed: %s (%d)" % [error_string(err), err])
		quit(1)
		return
	err = build_review(input_path, output_path, _resolve(FOREST), review_path)
	if err != OK:
		printerr("contour review failed: %s (%d)" % [error_string(err), err])
		quit(1)
		return
	print("attack1 contour candidate and manual review board generated")
	quit(0)

static func repair_file(input_path: String, output_path: String) -> Error:
	if not FileAccess.file_exists(input_path):
		return ERR_FILE_NOT_FOUND
	if _canonical(input_path) == _canonical(output_path):
		return ERR_INVALID_PARAMETER
	var bytes := FileAccess.get_file_as_bytes(input_path)
	if not _png_signature(bytes):
		return ERR_FILE_UNRECOGNIZED
	var source := Image.new()
	var err := source.load_png_from_buffer(bytes)
	if err != OK or source.is_empty():
		return err if err != OK else ERR_FILE_CORRUPT
	if source.get_size() != SIZE:
		return ERR_INVALID_DATA
	if source.get_format() != Image.FORMAT_RGBA8:
		source.convert(Image.FORMAT_RGBA8)
	var result := repair_image(source)
	var image: Image = result.image
	if not has_clear_margins(image):
		return ERR_INVALID_DATA
	var parent := output_path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		err = DirAccess.make_dir_recursive_absolute(parent)
		if err != OK:
			return err
	return image.save_png(output_path)

# Classify only red outliers in the 1–4 px alpha interior band. Candidate
# pixels are grouped in 8-connected components before repair so isolated
# natural warm marks never trigger a broad hue sweep.
static func repair_image(source: Image) -> Dictionary:
	if source == null or source.is_empty() or source.get_size() != SIZE:
		return {"image": Image.new(), "changed": 0, "alpha_cleared": 0, "residual_before": 0, "residual_after": 0}
	var output := source.duplicate()
	var depth := _interior_band_depth(source, 4)
	var candidates := PackedByteArray()
	candidates.resize(SIZE.x * SIZE.y)
	var residual_before := 0
	for y in range(1, SIZE.y - 1):
		for x in range(1, SIZE.x - 1):
			var index := y * SIZE.x + x
			var d := int(depth[index])
			if d < 1 or d > 4:
				continue
			var pixel := source.get_pixel(x, y)
			var evidence := _inward_color_consensus(source, depth, x, y)
			if evidence.valid and _is_contour_red_outlier(pixel, evidence.color, evidence.support):
				candidates[index] = 1
	var visited := PackedByteArray()
	visited.resize(SIZE.x * SIZE.y)
	var rgb_changed := 0
	var alpha_cleared := 0
	for y in range(1, SIZE.y - 1):
		for x in range(1, SIZE.x - 1):
			var start := y * SIZE.x + x
			if candidates[start] == 0 or visited[start] != 0:
				continue
			var component: Array[Vector2i] = []
			var queue: Array[Vector2i] = [Vector2i(x, y)]
			visited[start] = 1
			var cursor := 0
			while cursor < queue.size():
				var point := queue[cursor]
				cursor += 1
				component.append(point)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if ox == 0 and oy == 0:
							continue
						var nx := point.x + ox
						var ny := point.y + oy
						var ni := ny * SIZE.x + nx
						if candidates[ni] != 0 and visited[ni] == 0:
							visited[ni] = 1
							queue.append(Vector2i(nx, ny))
			for point in component:
				residual_before += 1
				var index := point.y * SIZE.x + point.x
				var original := source.get_pixelv(point)
				var evidence := _inward_color_consensus(source, depth, point.x, point.y)
				if evidence.valid and _external_red_edge_pixel(source, depth, point.x, point.y, original, component.size()):
					output.set_pixelv(point, Color(original.r, original.g, original.b, 0.0))
					alpha_cleared += 1
				else:
					var restored: Color = evidence.color
					output.set_pixelv(point, Color(restored.r, restored.g, restored.b, original.a))
					rgb_changed += 1
	var residual_after := count_contour_red_outliers(output)
	return {"image": output, "changed": rgb_changed + alpha_cleared, "rgb_changed": rgb_changed, "alpha_cleared": alpha_cleared, "residual_before": residual_before, "residual_after": residual_after}

static func count_contour_red_outliers(image: Image) -> int:
	if image == null or image.is_empty() or image.get_size() != SIZE:
		return -1
	var depth := _interior_band_depth(image, 4)
	var count := 0
	for y in range(1, SIZE.y - 1):
		for x in range(1, SIZE.x - 1):
			var d := int(depth[y * SIZE.x + x])
			if d < 1 or d > 4:
				continue
			var pixel := image.get_pixel(x, y)
			var evidence := _inward_color_consensus(image, depth, x, y)
			if evidence.valid and _is_contour_red_outlier(pixel, evidence.color, evidence.support):
				count += 1
	return count

static func _interior_band_depth(image: Image, limit: int) -> PackedByteArray:
	var depth := PackedByteArray()
	depth.resize(SIZE.x * SIZE.y)
	for i in range(depth.size()):
		depth[i] = limit + 1
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a < 0.02:
				depth[y * SIZE.x + x] = 0
	# Eight-neighbour dilation from transparent pixels gives exact band labels
	# through four pixels, with no RGB thresholding involved.
	for d in range(1, limit + 1):
		for y in range(1, SIZE.y - 1):
			for x in range(1, SIZE.x - 1):
				var index := y * SIZE.x + x
				if depth[index] <= d:
					continue
				var found := false
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						if depth[(y + oy) * SIZE.x + x + ox] == d - 1:
							found = true
							break
					if found:
						break
				if found:
					depth[index] = d
	return depth

static func _inward_color_consensus(image: Image, depth: PackedByteArray, x: int, y: int) -> Dictionary:
	var samples: Array[Color] = []
	var best := Color.TRANSPARENT
	var best_score := -1.0
	for ny in range(maxi(1, y - 7), mini(SIZE.y - 1, y + 8)):
		for nx in range(maxi(1, x - 7), mini(SIZE.x - 1, x + 8)):
			var distance := Vector2(float(nx - x), float(ny - y)).length()
			if distance > 7.0 or (nx == x and ny == y):
				continue
			var neighbor := image.get_pixel(nx, ny)
			if neighbor.a < 0.985 or depth[ny * SIZE.x + nx] <= 4:
				continue
			samples.append(neighbor)
	if samples.size() < 3:
		return {"valid": false, "color": Color.TRANSPARENT, "support": 0}
	var support := 0
	for candidate in samples:
		var score := 0.0
		var local_support := 0
		for other in samples:
			if _rgb_distance(candidate, other) <= 0.16:
				score += 1.0
				local_support += 1
		if score > best_score:
			best_score = score
			best = candidate
			support = local_support
	return {"valid": support >= 3, "color": best, "support": support}

static func _is_contour_red_outlier(pixel: Color, foreground: Color, support: int) -> bool:
	if pixel.a <= 0.0 or support < 3 or pixel.s < 0.62 or foreground == Color.TRANSPARENT:
		return false
	if not (pixel.h < 0.025 or pixel.h > 0.975):
		return false
	# Reject supported warm hair/skin/gold hues and require a strong RGB clash.
	if foreground.s > 0.2 and (foreground.h < 0.105 or foreground.h > 0.88):
		return false
	return _rgb_distance(pixel, foreground) >= 0.23

static func _external_red_edge_pixel(image: Image, depth: PackedByteArray, x: int, y: int, pixel: Color, component_size: int) -> bool:
	# Only a very low-opacity, one-pixel boundary fringe can be discarded.
	# Opaque/internal red components are restored from the foreground consensus.
	if pixel.a >= 0.20 or depth[y * SIZE.x + x] != 1 or component_size > 64:
		return false
	var transparent := 0
	var opaque_support := 0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var neighbor := image.get_pixel(x + ox, y + oy)
			if neighbor.a < 0.02:
				transparent += 1
			elif neighbor.a >= 0.985 and depth[(y + oy) * SIZE.x + x + ox] >= 1:
				opaque_support += 1
	return transparent >= 4 and opaque_support >= 2

static func has_clear_margins(image: Image) -> bool:
	if image == null or image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _alpha_bounds(image)
	return bounds.size.x > 0 and bounds.position.x >= MIN_MARGIN and bounds.position.y >= MIN_MARGIN \
		and SIZE.x - bounds.end.x >= MIN_MARGIN and SIZE.y - bounds.end.y >= MIN_MARGIN

static func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := SIZE.x
	var min_y := SIZE.y
	var max_x := -1
	var max_y := -1
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a >= 0.05:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func build_review(before_path: String, after_path: String, forest_path: String, output_path: String) -> Error:
	var before := _load_png(before_path)
	var after := _load_png(after_path)
	var forest := _load_png(forest_path)
	if before == null or after == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if before.get_size() != SIZE or after.get_size() != SIZE:
		return ERR_INVALID_DATA
	var canvas := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var labels := ["WHITE", "BLACK", "CHECKER", "FOREST"]
	for row in range(4):
		var y := 16 + row * 410
		for side in range(2):
			var x := 20 + side * 740
			var panel := Image.create(720, 390, false, Image.FORMAT_RGBA8)
			_fill_background(panel, row, forest)
			var target := before if side == 0 else after
			var whole := _fit(target.get_region(_alpha_bounds(target)), Vector2i(300, 370))
			panel.blend_rect(whole, Rect2i(Vector2i.ZERO, whole.get_size()), Vector2i(18, 12))
			var label := _label_strip(("BEFORE " if side == 0 else "AFTER ") + labels[row], Vector2i(200, 28))
			panel.blit_rect(label, Rect2i(Vector2i.ZERO, label.get_size()), Vector2i(380, 8))
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(x, y))
	# Enlarged crops focus on the ponytail, arm underside/armpit, and fist edge.
	var details := [Rect2(0.14, 0.03, 0.48, 0.36), Rect2(0.49, 0.18, 0.46, 0.25), Rect2(0.77, 0.17, 0.21, 0.20)]
	var names := ["PONYTAIL", "ARM UNDERSIDE + ARMPIT", "FIST CONTOUR"]
	for detail_index in range(details.size()):
		var row_y := 1665 + detail_index * 195
		var label := _label_strip(names[detail_index], Vector2i(300, 26))
		canvas.blit_rect(label, Rect2i(Vector2i.ZERO, label.get_size()), Vector2i(20, row_y))
		for side in range(2):
			var panel := Image.create(720, 164, false, Image.FORMAT_RGBA8)
			_draw_checker(panel)
			var target := before if side == 0 else after
			var crop := _crop_relative(target, _alpha_bounds(target), details[detail_index])
			var fitted := _fit(crop, Vector2i(700, 154))
			panel.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i((720 - fitted.get_width()) / 2, (164 - fitted.get_height()) / 2))
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(20 + side * 740, row_y + 28))
	# Matching 192px samples for direct silhouette and edge comparison.
	var sample_y := 2280
	var title := _label_strip("192PX BEFORE / AFTER", Vector2i(300, 26))
	canvas.blit_rect(title, Rect2i(Vector2i.ZERO, title.get_size()), Vector2i(20, sample_y))
	for side in range(2):
		var tile := Image.create(320, 192, false, Image.FORMAT_RGBA8)
		_draw_checker(tile)
		var target := before if side == 0 else after
		var figure := _fit(target.get_region(_alpha_bounds(target)), Vector2i(300, 192))
		tile.blend_rect(figure, Rect2i(Vector2i.ZERO, figure.get_size()), Vector2i((320 - figure.get_width()) / 2, 0))
		canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(400 + side * 360, sample_y))
	var parent := output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(parent):
		var err := DirAccess.make_dir_recursive_absolute(parent)
		if err != OK:
			return err
	return canvas.save_png(output_path)

static func _fill_background(image: Image, row: int, forest: Image) -> void:
	match row:
		0: image.fill(Color.WHITE)
		1: image.fill(Color("#101216"))
		2: _draw_checker(image)
		3:
			var bg := forest.duplicate()
			bg.resize(image.get_width(), image.get_height(), Image.INTERPOLATE_LANCZOS)
			image.blit_rect(bg, Rect2i(Vector2i.ZERO, bg.get_size()), Vector2i.ZERO)

static func _draw_checker(image: Image) -> void:
	for y in range(0, image.get_height(), 20):
		for x in range(0, image.get_width(), 20):
			var color := Color("#454a50") if ((x / 20 + y / 20) % 2 == 0) else Color("#272c31")
			image.fill_rect(Rect2i(x, y, mini(20, image.get_width() - x), mini(20, image.get_height() - y)), color)

static func _label_strip(label: String, size: Vector2i) -> Image:
	# Reuse the existing review tool's compact bitmap font and checker helpers.
	var helper = load("res://tools/refine_player_attack1_edge_v2.gd")
	return helper._label_strip(label, size)

static func _crop_relative(image: Image, bounds: Rect2i, region: Rect2) -> Image:
	var x := bounds.position.x + int(floor(region.position.x * bounds.size.x))
	var y := bounds.position.y + int(floor(region.position.y * bounds.size.y))
	var right := bounds.position.x + int(ceil((region.position.x + region.size.x) * bounds.size.x))
	var bottom := bounds.position.y + int(ceil((region.position.y + region.size.y) * bounds.size.y))
	var rect := Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, image.get_size()))
	return image.get_region(rect)

static func _fit(source: Image, target: Vector2i) -> Image:
	var scale := minf(float(target.x) / source.get_width(), float(target.y) / source.get_height())
	var size := Vector2i(maxi(1, int(round(source.get_width() * scale))), maxi(1, int(round(source.get_height() * scale))))
	var result := source.duplicate()
	if result.get_size() != size:
		result.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return result

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path): return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty(): return null
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	return image

static func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

static func _png_signature(bytes: PackedByteArray) -> bool:
	var sig := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < sig.size(): return false
	for i in range(sig.size()):
		if bytes[i] != sig[i]: return false
	return true

static func _canonical(path: String) -> String:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else (path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path))
	return resolved.replace("\\", "/").simplify_path().to_lower()

static func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"): return ProjectSettings.globalize_path(path)
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
