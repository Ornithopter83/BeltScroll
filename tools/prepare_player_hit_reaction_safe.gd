extends SceneTree

const SIZE := Vector2i(1254, 1254)
const GAME_CANVAS := 192
const MIN_MARGIN := 90
const SOURCE := "res://assets/art/player/elven_fighter_hit_reaction_v1_candidate_1254x1254.png"
const IDLE := "res://assets/art/player/elven_fighter_reference_v8_safe_1254x1254.png"
const ATTACK := "res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_hit_reaction_v1_safe_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_hit_reaction_comparison.png"
const PANEL := 600
const BOARD_H := 1200

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_bytes := _bytes(SOURCE)
	if source_bytes.is_empty():
		print("STATUS: PENDING — no new hit reaction original found at %s; no candidate created and no source was fabricated." % SOURCE)
		if not _build_comparison(null):
			quit(1)
			return
		quit(0)
		return
	var source := _load(SOURCE)
	if source == null or source.get_size() != SIZE or source.get_format() != Image.FORMAT_RGBA8:
		_fail("provided hit original must decode as 1254x1254 RGBA8; original bytes were left untouched")
		return
	var candidate := _make_safe(source)
	if candidate == null:
		_fail("could not normalize provided hit original while preserving its source bytes")
		return
	var out_path := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(out_path.get_base_dir())
	if candidate.save_png(out_path) != OK:
		_fail("could not save separate safe candidate")
		return
	if _bytes(SOURCE) != source_bytes:
		_fail("source bytes changed unexpectedly")
		return
	var bounds := _bounds(candidate)
	var margins := Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)
	if mini(mini(margins.x, margins.y), mini(margins.z, margins.w)) < MIN_MARGIN or _isolated_count(candidate) != 0:
		_fail("candidate failed 90px margin or isolated alpha pixel gate")
		return
	print("STATUS: CANDIDATE CREATED | source_bytes_preserved=true | size=1254x1254 RGBA8 | margins L/T/R/B=%s | isolated_alpha=%d" % [str(margins), _isolated_count(candidate)])
	if not _build_comparison(candidate):
		quit(1)
		return
	quit(0)

func _make_safe(source: Image) -> Image:
	var bounds := _bounds(source)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return null
	var max_extent := SIZE.x - MIN_MARGIN * 2 - 12
	var factor := minf(float(max_extent) / bounds.size.x, float(max_extent) / bounds.size.y)
	var target := Vector2i(roundi(bounds.size.x * factor), roundi(bounds.size.y * factor))
	var crop := source.get_region(bounds)
	var scaled := crop.duplicate()
	# Premultiply before filtering so transparent fringe colors cannot bleed into the silhouette.
	for y in range(scaled.get_height()):
		for x in range(scaled.get_width()):
			var p: Color = scaled.get_pixel(x, y)
			scaled.set_pixel(x, y, Color(p.r * p.a, p.g * p.a, p.b * p.a, p.a))
	scaled.resize(target.x, target.y, Image.INTERPOLATE_LANCZOS)
	for y in range(scaled.get_height()):
		for x in range(scaled.get_width()):
			var p: Color = scaled.get_pixel(x, y)
			if p.a <= 0.00001:
				scaled.set_pixel(x, y, Color.TRANSPARENT)
			else:
				scaled.set_pixel(x, y, Color(clampf(p.r / p.a, 0.0, 1.0), clampf(p.g / p.a, 0.0, 1.0), clampf(p.b / p.a, 0.0, 1.0), p.a))
	var result := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	result.blit_rect(scaled, Rect2i(Vector2i.ZERO, target), Vector2i((SIZE.x - target.x) / 2, (SIZE.y - target.y) / 2))
	_clear_isolated(result)
	return result

func _build_comparison(candidate: Image) -> bool:
	var idle := _load(IDLE)
	var attack := _load(ATTACK)
	if idle == null or attack == null:
		push_error("comparison input missing: v8 idle safe or attack2 contact safe")
		return false
	var panel_images: Array[Image] = [idle, attack]
	var titles := ["1 IDLE", "2 CONTACT"]
	if candidate == null:
		panel_images.append(idle)
		titles.append("3 PROCEDURAL HIT")
	else:
		var original := _load(SOURCE)
		if original == null:
			return false
		panel_images.append(original)
		panel_images.append(candidate)
		titles.append("3 HIT ORIGINAL")
		titles.append("4 SAFE CANDIDATE")
	var board := Image.create(PANEL * panel_images.size(), BOARD_H, false, Image.FORMAT_RGBA8)
	board.fill(Color("#171b20"))
	for i in range(panel_images.size()):
		var x0 := i * PANEL
		board.fill_rect(Rect2i(x0, 0, PANEL, BOARD_H), Color("#252b32"))
		# All panels use the identical 192x192 game canvas and 3x nearest-neighbor display scale.
		_draw_marker(board, x0 + 18, 18, i + 1)
		var game_canvas := _to_game_canvas(panel_images[i], i == 2 and candidate == null)
		game_canvas.resize(GAME_CANVAS * 3, GAME_CANVAS * 3, Image.INTERPOLATE_NEAREST)
		board.blend_rect(game_canvas, Rect2i(Vector2i.ZERO, game_canvas.get_size()), Vector2i(x0 + (PANEL - GAME_CANVAS * 3) / 2, 72))
		var mirrored := game_canvas.duplicate()
		mirrored.flip_x()
		board.blend_rect(mirrored, Rect2i(Vector2i.ZERO, mirrored.get_size()), Vector2i(x0 + (PANEL - GAME_CANVAS * 3) / 2, 672))
		board.fill_rect(Rect2i(x0 + 18, 648, PANEL - 36, 3), Color("#f05c4f"))
		print("COMPARE %s | alpha_bounds_1254=%s | scaled_canvas=192x192 | facing=right" % [titles[i], str(_bounds(panel_images[i]))])
	var full := ProjectSettings.globalize_path(REVIEW)
	DirAccess.make_dir_recursive_absolute(full.get_base_dir())
	return board.save_png(full) == OK

func _to_game_canvas(source: Image, recoil: bool) -> Image:
	var result := Image.create(GAME_CANVAS, GAME_CANVAS, false, Image.FORMAT_RGBA8)
	result.fill(Color.TRANSPARENT)
	var bounds := _bounds(source)
	if bounds.size.x <= 0:
		return result
	# Common scale is 192/1254 for every source; foot baseline is shared at row 191.
	var resized := source.duplicate()
	resized.resize(GAME_CANVAS, GAME_CANVAS, Image.INTERPOLATE_LANCZOS)
	var foot_y := mini(GAME_CANVAS - 1, roundi(float(bounds.end.y) * GAME_CANVAS / SIZE.y) - 1)
	var offset_y := GAME_CANVAS - 1 - foot_y
	if not recoil:
		result.blit_rect(resized, Rect2i(Vector2i.ZERO, resized.get_size()), Vector2i(0, offset_y))
		return result
	# Faithful peak transform approximation from player_visual_animator.gd: +0.18 rad,
	# scale 1.05 x 0.91 around the sprite foot anchor. Flash color is documented in the gate.
	for y in range(GAME_CANVAS):
		for x in range(GAME_CANVAS):
			var dx := float(x) - GAME_CANVAS * 0.5
			var dy := float(y - (GAME_CANVAS - 1))
			var angle := -0.18
			var sx := dx * cos(angle) - dy * sin(angle)
			var sy := dx * sin(angle) + dy * cos(angle)
			sx = sx / 1.05 + GAME_CANVAS * 0.5
			var sample_y := roundi(sy / 0.91 + foot_y)
			if sx >= 0.0 and sx < GAME_CANVAS and sample_y >= 0 and sample_y < GAME_CANVAS:
				var pixel: Color = resized.get_pixel(roundi(sx), sample_y)
				result.set_pixel(x, y, Color(pixel.r, pixel.g * 0.42, pixel.b * 0.36, pixel.a))
	return result

func _clear_isolated(image: Image) -> void:
	var mask := PackedByteArray()
	mask.resize(SIZE.x * SIZE.y)
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if image.get_pixel(x, y).a > 0.0:
				mask[y * SIZE.x + x] = 1
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if mask[y * SIZE.x + x] == 0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if (ox != 0 or oy != 0) and x + ox >= 0 and y + oy >= 0 and x + ox < SIZE.x and y + oy < SIZE.y and mask[(y + oy) * SIZE.x + x + ox] != 0:
						neighbor = true
			if not neighbor:
				image.set_pixel(x, y, Color.TRANSPARENT)

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					if (ox != 0 or oy != 0) and x + ox >= 0 and y + oy >= 0 and x + ox < image.get_width() and y + oy < image.get_height() and image.get_pixel(x + ox, y + oy).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _load(path: String) -> Image:
	var bytes := _bytes(path)
	if bytes.is_empty():
		return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _bytes(path: String) -> PackedByteArray:
	var full := ProjectSettings.globalize_path(path)
	return FileAccess.get_file_as_bytes(full) if FileAccess.file_exists(full) else PackedByteArray()

func _draw_marker(image: Image, x: int, y: int, number: int) -> void:
	# Numbered panel marker; the Korean legend and exact panel names live in the review gate.
	var c := Color("#f1bd69")
	image.fill_rect(Rect2i(x, y, 36, 5), c)
	image.fill_rect(Rect2i(x, y, 5, 40), c)
	image.fill_rect(Rect2i(x + 31, y, 5, 40), c)
	image.fill_rect(Rect2i(x, y + 35, 36, 5), c)
	if number == 1 or number == 3:
		image.fill_rect(Rect2i(x + 15, y + 5, 5, 30), c)
	else:
		image.fill_rect(Rect2i(x + 6, y + 13, 24, 5), c)
		image.fill_rect(Rect2i(x + 6, y + 22, 24, 5), c)

func _fail(message: String) -> void:
	push_error("prepare_player_hit_reaction_safe: " + message)
	quit(1)













