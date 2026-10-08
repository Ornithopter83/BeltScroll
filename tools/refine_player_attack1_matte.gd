extends SceneTree

const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
const INPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_clean_candidate_1254x1254.png"
const V8_REFERENCE := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack1_final_gate.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const CANVAS := Vector2i(1500, 2650)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.has("--help") or args.has("-h"):
		print("사용법: godot --headless --path . --script res://tools/refine_player_attack1_matte.gd [입력 PNG 출력 PNG 검토 PNG]")
		quit(0)
		return
	if not args.is_empty() and args.size() != 3:
		printerr("사용법: godot --headless --path . --script res://tools/refine_player_attack1_matte.gd [입력 PNG 출력 PNG 검토 PNG]")
		quit(2)
		return
	var input_path := _resolve(args[0] if args.size() == 3 else INPUT)
	var output_path := _resolve(args[1] if args.size() == 3 else OUTPUT)
	var review_path := _resolve(args[2] if args.size() == 3 else REVIEW)
	var result := refine_file(input_path, output_path)
	if result != OK:
		printerr("attack1 matte 처리 실패: %s (%d)" % [error_string(result), result])
		quit(1)
		return
	result = build_review(input_path, output_path, _resolve(V8_REFERENCE), _resolve(FOREST), review_path)
	if result != OK:
		printerr("attack1 matte 검토판 실패: %s (%d)" % [error_string(result), result])
		quit(1)
		return
	print("attack1 matte 후보와 검토판 생성 완료")
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
	var refined := refine_image(source)
	if refined.get_size() != SIZE or not _same_alpha(source, refined):
		return ERR_INVALID_DATA
	var bounds := _alpha_bounds(refined)
	if not _has_margin(bounds):
		return ERR_INVALID_DATA
	var parent := output_path.get_base_dir()
	if not parent.is_empty() and not DirAccess.dir_exists_absolute(parent):
		err = DirAccess.make_dir_recursive_absolute(parent)
		if err != OK:
			return err
	return refined.save_png(output_path)

# The alpha mask is immutable. Partial-alpha edge RGB and fully opaque red
# edge outliers take separate repair paths, both using nearby opaque color.
static func refine_image(source: Image) -> Image:
	var output := source.duplicate()
	var bounds := _alpha_bounds(source)
	for y in range(maxi(1, bounds.position.y - 1), mini(source.get_height() - 1, bounds.end.y + 1)):
		for x in range(maxi(1, bounds.position.x - 1), mini(source.get_width() - 1, bounds.end.x + 1)):
			var pixel := source.get_pixel(x, y)
			if pixel.a <= 0.0 or not _near_alpha_edge(source, x, y):
				continue
			var evidence := _local_foreground_medoid(source, x, y, 6)
			if not evidence.valid:
				continue
			var reference: Color = evidence.color
			var distance := _rgb_distance(pixel, reference)
			if pixel.a < 0.995:
				# Straight-alpha edge colors should carry the foreground RGB even
				# at low alpha; only a red fringe that conflicts with local opaque
				# consensus is repaired, protecting natural warm edge detail.
				if _is_partial_red_spill(pixel, reference, distance) and evidence.support >= 2:
					output.set_pixel(x, y, Color(reference.r, reference.g, reference.b, pixel.a))
			elif _is_opaque_red_spill(pixel, reference, distance) and evidence.support >= 3:
				# Keep real warm details whenever the opaque neighborhood agrees.
				output.set_pixel(x, y, Color(reference.r, reference.g, reference.b, pixel.a))
	return output

static func _local_foreground_medoid(image: Image, x: int, y: int, radius: int) -> Dictionary:
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
			if _rgb_distance(samples[i], samples[j]) <= 0.17:
				score += weights[j]
				support += 1
		if score > best_score:
			best = i
			best_score = score
			best_support = support
	return {"valid": best >= 0 and best_support >= 2, "color": samples[best] if best >= 0 else Color.TRANSPARENT, "support": best_support}

static func _is_opaque_red_spill(pixel: Color, reference: Color, distance: float) -> bool:
	if pixel.s < 0.62 or distance < 0.29:
		return false
	var hue := pixel.h
	if not (hue < 0.035 or hue > 0.965):
		return false
	# Red/brown hair, skin, and gold remain intact if supported by the local
	# opaque edge consensus. Strong outliers against non-red surroundings are spill.
	if reference.s > 0.22 and (reference.h < 0.07 or reference.h > 0.91) and distance < 0.48:
		return false
	return true

static func _is_partial_red_spill(pixel: Color, reference: Color, distance: float) -> bool:
	if pixel.s < 0.34 or distance < 0.19:
		return false
	if not (pixel.h < 0.055 or pixel.h > 0.945):
		return false
	# A warm edge remains valid when nearby foreground supports its hue family.
	if reference.s > 0.22 and (reference.h < 0.085 or reference.h > 0.90) and absf(pixel.h - reference.h) < 0.075 and distance < 0.48:
		return false
	return true

static func _near_alpha_edge(image: Image, x: int, y: int) -> bool:
	for ny in range(maxi(0, y - 2), mini(image.get_height(), y + 3)):
		for nx in range(maxi(0, x - 2), mini(image.get_width(), x + 3)):
			if nx == x and ny == y:
				continue
			if image.get_pixel(nx, ny).a < 0.02:
				return true
	return false

static func build_review(before_path: String, after_path: String, v8_path: String, forest_path: String, output_path: String) -> Error:
	var before := _load_png(before_path)
	var after := _load_png(after_path)
	var v8 := _load_png(v8_path)
	var forest := _load_png(forest_path)
	if before == null or after == null or v8 == null or forest == null:
		return ERR_FILE_NOT_FOUND
	if before.get_size() != SIZE or after.get_size() != SIZE or v8.get_size() != SIZE:
		return ERR_INVALID_DATA
	var canvas := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	canvas.fill(Color("#171b20"))
	var bounds := _alpha_bounds(before)
	var labels := ["WHITE", "BLACK", "CHECKER", "FOREST"]
	var panel_size := Vector2i(580, 430)
	for row in range(4):
		var panel_y := 18 + row * 438
		canvas.fill_rect(Rect2i(20, 18 + row * 438, 220, 30), Color("#303840"))
		var label_image := _label_strip(labels[row], Vector2i(220, 30))
		canvas.blit_rect(label_image, Rect2i(Vector2i.ZERO, label_image.get_size()), Vector2i(20, 18 + row * 438))
		for side in range(2):
			var panel_x := 250 + side * 600
			var panel := Image.create(panel_size.x, panel_size.y, false, Image.FORMAT_RGBA8)
			_fill_background(panel, row, forest)
			var target := before if side == 0 else after
			var crop := _crop_relative(target, _alpha_bounds(target), Rect2(0, 0, 1, 1))
			var fitted := _fit(crop, Vector2i(panel_size.x - 32, panel_size.y - 28))
			panel.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i((panel_size.x - fitted.get_width()) / 2, (panel_size.y - fitted.get_height()) / 2))
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel_size), Vector2i(panel_x, panel_y))
			canvas.fill_rect(Rect2i(panel_x, panel_y + panel_size.y - 5, panel_size.x, 5), Color("#e05b54") if side == 0 else Color("#69b8a2"))
		# Side labels
		for side in range(2):
			var tag := _label_strip("BEFORE" if side == 0 else "AFTER", Vector2i(110, 26))
			canvas.blit_rect(tag, Rect2i(Vector2i.ZERO, tag.get_size()), Vector2i(255 + side * 600, panel_y + 4))
	# Detail strip: face/ear, ponytail, and extended punching arm/fist on checker.
	var details := [Rect2(0.49, 0.12, 0.24, 0.24), Rect2(0.15, 0.05, 0.43, 0.39), Rect2(0.53, 0.22, 0.47, 0.22)]
	var detail_names := ["FACE", "PONYTAIL", "FIST + ARM"]
	for i in range(3):
		var y := 1780 + i * 205
		var caption := _label_strip(detail_names[i], Vector2i(200, 28))
		canvas.blit_rect(caption, Rect2i(Vector2i.ZERO, caption.get_size()), Vector2i(20, y))
		for side in range(2):
			var x := 250 + side * 600
			var panel := Image.create(580, 190, false, Image.FORMAT_RGBA8)
			_draw_checker(panel)
			var image := before if side == 0 else after
			var crop := _crop_relative(image, _alpha_bounds(image), details[i])
			var fitted := _fit(crop, Vector2i(560, 180))
			panel.blend_rect(fitted, Rect2i(Vector2i.ZERO, fitted.get_size()), Vector2i((580 - fitted.get_width()) / 2, (190 - fitted.get_height()) / 2))
			canvas.blit_rect(panel, Rect2i(Vector2i.ZERO, panel.get_size()), Vector2i(x, y))
	# 192px in-game pair, plus v8 clean as a silhouette/edge reference.
	var sample_y := 2440
	var sample_label := _label_strip("192px: BEFORE / AFTER / V8 CLEAN", Vector2i(500, 26))
	canvas.blit_rect(sample_label, Rect2i(Vector2i.ZERO, sample_label.get_size()), Vector2i(20, sample_y))
	for i in range(3):
		var image := before if i == 0 else (after if i == 1 else v8)
		var silhouette := image.get_region(_alpha_bounds(image))
		var ratio := 192.0 / float(silhouette.get_height())
		silhouette.resize(maxi(1, int(round(silhouette.get_width() * ratio))), 192, Image.INTERPOLATE_LANCZOS)
		var x := 520 + i * 250
		var tile := Image.create(220, 192, false, Image.FORMAT_RGBA8)
		tile.fill(Color("#303840"))
		_draw_checker(tile)
		tile.blend_rect(silhouette, Rect2i(Vector2i.ZERO, silhouette.get_size()), Vector2i((220 - silhouette.get_width()) / 2, 0))
		canvas.blit_rect(tile, Rect2i(Vector2i.ZERO, tile.get_size()), Vector2i(x, sample_y))
	var dir := output_path.get_base_dir()
	if not DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.make_dir_recursive_absolute(dir)
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
			image.fill_rect(Rect2i(x, y, mini(tile, image.get_width() - x), mini(tile, image.get_height() - y)), Color("#454a50") if ((x / tile + y / tile) % 2 == 0) else Color("#272c31"))

static func _label_strip(label: String, size: Vector2i) -> Image:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color("#252d35"))
	var font := {
		"A": [14,17,17,31,17,17,17], "B": [30,17,17,30,17,17,30], "C": [14,17,16,16,16,17,14],
		"D": [30,17,17,17,17,17,30], "E": [31,16,16,30,16,16,31], "F": [31,16,16,30,16,16,16],
		"G": [14,17,16,23,17,17,15], "H": [17,17,17,31,17,17,17], "I": [14,4,4,4,4,4,14],
		"J": [7,2,2,2,18,18,12], "K": [17,18,20,24,20,18,17], "L": [16,16,16,16,16,16,31],
		"M": [17,27,21,21,17,17,17], "N": [17,25,25,21,19,19,17], "O": [14,17,17,17,17,17,14],
		"P": [30,17,17,30,16,16,16], "Q": [14,17,17,17,21,18,13], "R": [30,17,17,30,20,18,17],
		"S": [15,16,16,14,1,1,30], "T": [31,4,4,4,4,4,4], "U": [17,17,17,17,17,17,14],
		"V": [17,17,17,17,17,10,4], "W": [17,17,17,21,21,21,10], "X": [17,17,10,4,10,17,17],
		"Y": [17,17,10,4,4,4,4], "Z": [31,1,2,4,8,16,31], "+": [0,4,4,31,4,4,0],
		"0": [14,17,19,21,25,17,14], "1": [4,12,4,4,4,4,14], "2": [14,17,1,2,4,8,31],
		"3": [30,1,1,14,1,1,30], "4": [2,6,10,18,31,2,2], "5": [31,16,16,30,1,1,30],
		"6": [14,16,16,30,17,17,14], "7": [31,1,2,4,8,8,8], "8": [14,17,17,14,17,17,14],
		"9": [14,17,17,15,1,1,14], ":": [0,4,4,0,4,4,0], "/": [1,2,2,4,8,8,16],
		" ": [0,0,0,0,0,0,0]
	}
	for i in range(label.length()):
		var glyph: Array = font.get(label.substr(i, 1).to_upper(), font[" "])
		for gy in range(7):
			for gx in range(5):
				if (int(glyph[gy]) & (1 << (4 - gx))) != 0:
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

static func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.05:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

static func _has_margin(bounds: Rect2i) -> bool:
	return bounds.size.x > 0 and bounds.size.y > 0 and bounds.position.x >= MIN_MARGIN and bounds.position.y >= MIN_MARGIN and SIZE.x - bounds.end.x >= MIN_MARGIN and SIZE.y - bounds.end.y >= MIN_MARGIN

static func _same_alpha(a: Image, b: Image) -> bool:
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x, y).a != b.get_pixel(x, y).a:
				return false
	return true

static func _rgb_distance(a: Color, b: Color) -> float:
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()

static func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

static func _png_signature(bytes: PackedByteArray) -> bool:
	var sig := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < sig.size():
		return false
	for i in range(sig.size()):
		if bytes[i] != sig[i]:
			return false
	return true

static func _canonical(path: String) -> String:
	var resolved := ProjectSettings.globalize_path(path) if path.begins_with("res://") or path.begins_with("user://") else (path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path))
	return resolved.replace("\\", "/").simplify_path().to_lower()

static func _resolve(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	return path if path.is_absolute_path() else ProjectSettings.globalize_path("res://" + path)
