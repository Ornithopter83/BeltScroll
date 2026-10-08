extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const INPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_edge_v2_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack1_edge_v2_gate.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const CANVAS := Vector2i(1500, 2650)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("Usage: godot --headless --path . --script res://tools/refine_player_attack1_edge_v2.gd [input.png output.png review.png]")
		quit(0)
		return
	if not args.is_empty() and args.size() != 3:
		printerr("Usage: godot --headless --path . --script res://tools/refine_player_attack1_edge_v2.gd [input.png output.png review.png]")
		quit(2)
		return
	var input_path := _resolve(args[0] if args.size() == 3 else INPUT)
	var output_path := _resolve(args[1] if args.size() == 3 else OUTPUT)
	var review_path := _resolve(args[2] if args.size() == 3 else REVIEW)
	var err := refine_file(input_path, output_path)
	if err != OK:
		printerr("attack1 edge v2 candidate failed: %s (%d)" % [error_string(err), err])
		quit(1)
		return
	err = build_review(input_path, output_path, _resolve(FOREST), review_path)
	if err != OK:
		printerr("attack1 edge v2 review failed: %s (%d)" % [error_string(err), err])
		quit(1)
		return
	print("attack1 edge v2 candidate and review generated; manual gate required")
	quit(0)

static func refine_file(input_path: String, output_path: String) -> Error:
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
	var result := refine_image(source)
	var image: Image = result.image
	if image.get_size() != SIZE or not has_clear_margins(image):
		return ERR_INVALID_DATA
	var parent := output_path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		err = DirAccess.make_dir_recursive_absolute(parent)
		if err != OK:
			return err
	return image.save_png(output_path)

# Re-synthesizes contaminated edge RGB from the local opaque foreground
# medoid. The alpha silhouette is retained except for tiny, low-alpha red
# components that are clearly outside the supported foreground contour.
static func refine_image(source: Image) -> Dictionary:
	if source == null or source.is_empty() or source.get_size() != SIZE:
		return {"image": Image.new(), "changed": 0, "rgb_changed": 0, "alpha_cleared": 0, "residual_before": 0, "residual_after": 0}
	var output := source.duplicate()
	var bounds := _alpha_bounds(source)
	var rgb_changed := 0
	var alpha_cleared := 0
	var residual_before := 0
	for y in range(maxi(1, bounds.position.y - 2), mini(source.get_height() - 1, bounds.end.y + 2)):
		for x in range(maxi(1, bounds.position.x - 2), mini(source.get_width() - 1, bounds.end.x + 2)):
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.0 or not _near_alpha_edge(source, x, y, 3):
				continue
			var evidence := _foreground_medoid(source, x, y, 6)
			if not evidence.valid:
				continue
			var foreground: Color = evidence.color
			var distance := _rgb_distance(pixel, foreground)
			if _is_red_outlier(pixel, foreground, distance, int(evidence.support)):
				residual_before += 1
				if pixel.a < 0.24 and _external_low_alpha_island(source, x, y, foreground):
					output.set_pixel(x, y, Color(pixel.r, pixel.g, pixel.b, 0.0))
					alpha_cleared += 1
				else:
					# Straight-alpha edge RGB is set to the locally supported foreground.
					output.set_pixel(x, y, Color(foreground.r, foreground.g, foreground.b, pixel.a))
					rgb_changed += 1
	var residual_after := count_red_edge_outliers(output)
	return {"image": output, "changed": rgb_changed + alpha_cleared, "rgb_changed": rgb_changed, "alpha_cleared": alpha_cleared, "residual_before": residual_before, "residual_after": residual_after}

static func count_red_edge_outliers(image: Image) -> int:
	if image == null or image.is_empty() or image.get_size() != SIZE:
		return -1
	var bounds := _alpha_bounds(image)
	var count := 0
	for y in range(maxi(1, bounds.position.y - 2), mini(image.get_height() - 1, bounds.end.y + 2)):
		for x in range(maxi(1, bounds.position.x - 2), mini(image.get_width() - 1, bounds.end.x + 2)):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0 or not _near_alpha_edge(image, x, y, 3):
				continue
			var evidence := _foreground_medoid(image, x, y, 6)
			if evidence.valid and _is_red_outlier(pixel, evidence.color, _rgb_distance(pixel, evidence.color), int(evidence.support)):
				count += 1
	return count

static func _foreground_medoid(image: Image, x: int, y: int, radius: int) -> Dictionary:
	var samples: Array[Color] = []
	var weights: Array[float] = []
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if nx == x and ny == y:
				continue
			var candidate := image.get_pixel(nx, ny)
			if candidate.a < 0.985:
				continue
			var d := Vector2(float(nx - x), float(ny - y)).length()
			if d > float(radius):
				continue
			samples.append(candidate)
			weights.append(1.0 / maxf(1.0, d * d))
	if samples.size() < 3:
		return {"valid": false, "color": Color.TRANSPARENT, "support": 0}
	var best := -1
	var best_score := -1.0
	var best_support := 0
	for i in range(samples.size()):
		var score := 0.0
		var support := 0
		for j in range(samples.size()):
			if _rgb_distance(samples[i], samples[j]) <= 0.15:
				score += weights[j]
				support += 1
		if score > best_score:
			best = i
			best_score = score
			best_support = support
	return {"valid": best >= 0 and best_support >= 3, "color": samples[best] if best >= 0 else Color.TRANSPARENT, "support": best_support}

static func _is_red_outlier(pixel: Color, foreground: Color, distance: float, support: int) -> bool:
	if support < 3 or pixel.s < 0.58 or distance < 0.26:
		return false
	if not (pixel.h < 0.035 or pixel.h > 0.965):
		return false
	# Natural hair, skin, and gold are preserved when neighboring opaque contour
	# colors support that warm hue or when their RGB distance is modest.
	var warm_foreground := foreground.s > 0.20 and (foreground.h < 0.10 or foreground.h > 0.89)
	if warm_foreground and distance < 0.47:
		return false
	return true

static func _external_low_alpha_island(image: Image, x: int, y: int, foreground: Color) -> bool:
	var transparent_neighbors := 0
	var opaque_neighbors := 0
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			if ox == 0 and oy == 0:
				continue
			var neighbor := image.get_pixel(x + ox, y + oy)
			if neighbor.a < 0.02:
				transparent_neighbors += 1
			elif neighbor.a >= 0.985 and _rgb_distance(neighbor, foreground) < 0.18:
				opaque_neighbors += 1
	return transparent_neighbors >= 6 and opaque_neighbors >= 2

static func _near_alpha_edge(image: Image, x: int, y: int, radius: int) -> bool:
	for ny in range(maxi(0, y - radius), mini(image.get_height(), y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(image.get_width(), x + radius + 1)):
			if nx == x and ny == y:
				continue
			if image.get_pixel(nx, ny).a < 0.02:
				return true
	return false

static func has_clear_margins(image: Image) -> bool:
	if image == null or image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var b := _alpha_bounds(image)
	return b.size.x > 0 and b.position.x >= MIN_MARGIN and b.position.y >= MIN_MARGIN \
		and SIZE.x - b.end.x >= MIN_MARGIN and SIZE.y - b.end.y >= MIN_MARGIN

static func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width(); var min_y := image.get_height()
	var max_x := -1; var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.05:
				min_x = mini(min_x, x); min_y = mini(min_y, y)
				max_x = maxi(max_x, x); max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func build_review(before_path: String, after_path: String, forest_path: String, output_path: String) -> Error:
	var before := _load_png(before_path)
	var after := _load_png(after_path)
	var forest := _load_png(forest_path)
	if before == null or after == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if before.get_size() != SIZE or after.get_size() != SIZE or forest.is_empty():
		return ERR_INVALID_DATA
	var canvas := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var labels := ["WHITE", "BLACK", "CHECKER", "FOREST"]
	for row in range(4):
		var panel_y := 18 + row * 438
		for side in range(2):
			var panel_x := 20 + side * 740
			var panel := Image.create(720, 430, false, Image.FORMAT_RGBA8)
			_fill_background(panel, row, forest)
			var target := before if side == 0 else after
			var crop := target.get_region(_alpha_bounds(target))
			var fitted := _fit(crop, Vector2i(310, 400))
			panel.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i(10, 18))
			var detail_rects := [Rect2(0.48, 0.05, 0.28, 0.29), Rect2(0.12, 0.05, 0.42, 0.34), Rect2(0.55, 0.18, 0.43, 0.25)]
			for d in range(detail_rects.size()):
				var detail := _crop_relative(target, _alpha_bounds(target), detail_rects[d])
				var detail_fit := _fit(detail, Vector2i(150, 125))
				panel.blend_rect(detail_fit, Rect2i(Vector2i.ZERO, detail_fit.get_size()), Vector2i(400 + (d % 2) * 155, 18 + (d / 2) * 145))
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(panel_x, panel_y))
			var label := _label_strip(("BEFORE " if side == 0 else "V2 AFTER ") + labels[row], Vector2i(200, 26))
			canvas.blit_rect(label, Rect2i(Vector2i.ZERO, label.get_size()), Vector2i(panel_x + 8, panel_y + 4))
	# Compare at matching 192px figure height.
	var compare_label := _label_strip("192PX BEFORE / V2 AFTER", Vector2i(360, 28))
	canvas.blit_rect(compare_label, Rect2i(Vector2i.ZERO, compare_label.get_size()), Vector2i(20, 1785))
	for i in range(2):
		var target := before if i == 0 else after
		var figure := target.get_region(_alpha_bounds(target))
		var resized := _fit(figure, Vector2i(250, 192))
		var tile := Image.create(280, 220, false, Image.FORMAT_RGBA8)
		_draw_checker(tile)
		tile.blend_rect(resized, Rect2i(Vector2i.ZERO, resized.get_size()), Vector2i((280 - resized.get_width()) / 2, 14))
		canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(400 + i * 330, 1785))
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
	var tile := 22
	for y in range(0, image.get_height(), tile):
		for x in range(0, image.get_width(), tile):
			var color := Color("#454a50") if ((x / tile + y / tile) % 2 == 0) else Color("#272c31")
			image.fill_rect(Rect2i(x, y, mini(tile, image.get_width() - x), mini(tile, image.get_height() - y)), color)

static func _label_strip(label: String, size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("#252d35"))
	var font := {"A":[14,17,17,31,17,17,17],"B":[30,17,17,30,17,17,30],"C":[14,17,16,16,16,17,14],"D":[30,17,17,17,17,17,30],"E":[31,16,16,30,16,16,31],"F":[31,16,16,30,16,16,16],"G":[14,17,16,23,17,17,15],"H":[17,17,17,31,17,17,17],"I":[14,4,4,4,4,4,14],"J":[7,2,2,2,18,18,12],"K":[17,18,20,24,20,18,17],"L":[16,16,16,16,16,16,31],"M":[17,27,21,21,17,17,17],"N":[17,25,25,21,19,19,17],"O":[14,17,17,17,17,17,14],"P":[30,17,17,30,16,16,16],"R":[30,17,17,30,20,18,17],"S":[15,16,16,14,1,1,30],"T":[31,4,4,4,4,4,4],"U":[17,17,17,17,17,17,14],"V":[17,17,17,17,17,10,4],"W":[17,17,17,21,21,21,10],"X":[17,17,10,4,10,17,17],"Y":[17,17,10,4,4,4,4],"0":[14,17,19,21,25,17,14],"1":[4,12,4,4,4,4,14],"2":[14,17,1,2,4,8,31],"9":[14,17,17,15,1,1,14],"/ ":[0,0,0,0,0,0,0],"/":[1,2,2,4,8,8,16]," ":[0,0,0,0,0,0,0]}
	for i in range(label.length()):
		var glyph: Array = font.get(label.substr(i, 1).to_upper(), font[" "])
		for gy in range(7):
			for gx in range(5):
				if 8 + i * 8 + gx < size.x and (int(glyph[gy]) & (1 << (4 - gx))) != 0:
					image.set_pixel(8 + i * 8 + gx, 5 + gy, Color("#e7ecef"))
	return image

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
	var image := source.duplicate()
	if image.get_size() != size:
		image.resize(size.x, size.y, Image.INTERPOLATE_LANCZOS)
	return image

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

static func _png_signature(bytes: PackedByteArray) -> bool:
	var sig := [137,80,78,71,13,10,26,10]
	if bytes.size() < sig.size(): return false
	for i in range(sig.size()):
		if bytes[i] != sig[i]: return false
	return true

static func _canonical(path: String) -> String:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else (path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path))
	return resolved.replace("\\", "/").simplify_path().to_lower()

static func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
