extends SceneTree
"""Isolated review of an optional 2x2 RESOURCE sheet or pending attack poses."""

const OUTPUT_PATH := "res://assets/art/review/m6d_motion_candidate_comparison.png"
const RESOURCE_ROOT := "res://assets/art/player"
const WINDOW_SIZE := Vector2i(1920, 1080)
const ALPHA_THRESHOLD := 0.05
const CANDIDATES := [
	{"attack": "ATTACK 1", "phase": "STARTUP", "path": "res://assets/art/player/elven_fighter_attack1_startup_v1_candidate_1254x1254.png", "duration_ms": 105},
	{"attack": "ATTACK 1", "phase": "CONTACT", "path": "res://assets/art/player/elven_fighter_attack1_reference_v1_1254x1254.png", "duration_ms": 120},
	{"attack": "ATTACK 2", "phase": "IN-BETWEEN", "path": "res://assets/art/player/elven_fighter_attack2_inbetween_v1_candidate_1254x1254.png", "duration_ms": 90},
	{"attack": "ATTACK 2", "phase": "CONTACT", "path": "res://assets/art/player/elven_fighter_attack2_contact_v6_candidate_1254x1254.png", "duration_ms": 120},
]
const CELL_POSITIONS := [Vector2(24, 156), Vector2(650, 156), Vector2(24, 574), Vector2(650, 574)]
const CELL_SIZE := Vector2(604, 396)
const ART_RECT_SIZE := Vector2(280, 280)
const PLAYER_RECT := Rect2(1290, 150, 605, 790)

var _frames: Array[Dictionary] = []
var _textures: Array[Texture2D] = []
var _playback: TextureRect
var _playback_label: Label

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("Visible Godot Window required for real-time exposure measurement.")
		return
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(WINDOW_SIZE)
	for _i in range(3):
		await process_frame
	if root.size != WINDOW_SIZE or DisplayServer.window_get_size() != WINDOW_SIZE:
		_fail("Could not open the review Window at 1920x1080.")
		return
	var resource_path := _find_resource_sheet()
	if resource_path.is_empty():
		if not _load_candidate_frames():
			return
		print("RESOURCE_SHEET status=not_found searched=%s; fallback=unapproved_original_attack_candidates" % RESOURCE_ROOT)
	else:
		if not _load_resource_frames(resource_path):
			return
		print("MOTION_SHEET status=found kind=%s path=%s extraction=independent_quadrants order=top_left,top_right,bottom_left,bottom_right" % [_sheet_source_label(resource_path), resource_path])
	_build_board(resource_path)
	for _i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var board := root.get_texture().get_image()
	if board == null or board.is_empty() or board.get_size() != WINDOW_SIZE:
		_fail("Could not capture the 1920x1080 comparison board.")
		return
	var output := ProjectSettings.globalize_path(OUTPUT_PATH)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output.get_base_dir())
	if mkdir_error != OK:
		_fail("Could not create output directory: %s" % error_string(mkdir_error))
		return
	var save_error := board.save_png(output)
	if save_error != OK:
		_fail("Could not save comparison PNG: %s" % error_string(save_error))
		return
	var readback := Image.new()
	if readback.load(output) != OK or readback.get_size() != WINDOW_SIZE:
		_fail("Saved comparison PNG failed read-back.")
		return
	print("M6D_REVIEW_CAPTURE path=%s size=%dx%d frame_count=%d source=%s" % [OUTPUT_PATH, WINDOW_SIZE.x, WINDOW_SIZE.y, _frames.size(), _sheet_source_label(resource_path) if not resource_path.is_empty() else "candidate_fallback"])
	await _play_sequence()
	quit(0)

func _find_resource_sheet() -> String:
	var found_resource: Array[String] = []
	var found_attack_sheet: Array[String] = []
	_scan_resource_dir(RESOURCE_ROOT, found_resource, found_attack_sheet)
	found_resource.sort()
	found_attack_sheet.sort()
	if not found_resource.is_empty():
		return found_resource[0]
	return found_attack_sheet[0] if not found_attack_sheet.is_empty() else ""

func _sheet_source_label(path: String) -> String:
	return "RESOURCE sheet" if path.get_file().to_lower().contains("resource") else "attack sheet candidate"

func _scan_resource_dir(path: String, found_resource: Array[String], found_attack_sheet: Array[String]) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if directory.current_is_dir():
			if entry != "." and entry != "..":
				_scan_resource_dir(path.path_join(entry), found_resource, found_attack_sheet)
		elif entry.get_extension().to_lower() == "png":
			var filename := entry.to_lower()
			if filename.contains("resource"):
				found_resource.append(path.path_join(entry))
			elif filename.contains("attack") and filename.contains("sheet"):
				found_attack_sheet.append(path.path_join(entry))
		entry = directory.get_next()
	directory.list_dir_end()

func _load_candidate_frames() -> bool:
	for item in CANDIDATES:
		var image := _load_image(item.path)
		if image == null or image.get_size() != Vector2i(1254, 1254):
			_fail("Missing, unreadable, or wrong-size candidate source: %s" % item.path)
			return false
		var frame: Dictionary = item.duplicate(true)
		frame.image = image
		frame.cell_order = item.attack + " / " + item.phase
		frame.origin = Vector2i.ZERO
		frame.procedural = "none; source PNG switched directly"
		_add_frame(frame)
	return true

func _load_resource_frames(path: String) -> bool:
	var sheet := _load_image(path)
	if sheet == null or sheet.get_width() % 2 != 0 or sheet.get_height() % 2 != 0:
		_fail("RESOURCE sheet must be a readable PNG with even dimensions for 2x2 extraction: %s" % path)
		return false
	var frame_size := sheet.get_size() / 2
	var names := ["TOP LEFT", "TOP RIGHT", "BOTTOM LEFT", "BOTTOM RIGHT"]
	for index in range(4):
		var origin := Vector2i(index % 2, index >> 1) * frame_size
		var crop := sheet.get_region(Rect2i(origin, frame_size))
		var frame := {"attack": _sheet_source_label(path), "phase": names[index], "path": path, "duration_ms": 120, "image": crop, "cell_order": names[index], "origin": origin, "procedural": "none; independent source quadrant"}
		_add_frame(frame)
	return true

func _add_frame(frame: Dictionary) -> void:
	var image: Image = frame.image
	var bounds := _alpha_bounds(image)
	var alpha_counts := _alpha_counts(image)
	frame.bounds = bounds
	frame.alpha_nonzero = alpha_counts[0]
	frame.alpha_partial = alpha_counts[1]
	frame.edge_alpha = _edge_alpha_counts(image)
	frame.anchor = _bottom_alpha_anchor(image, bounds)
	frame.texture = ImageTexture.create_from_image(image)
	_frames.append(frame)
	_textures.append(frame.texture)

func _build_board(resource_path: String) -> void:
	_add_rect(Vector2.ZERO, Vector2(WINDOW_SIZE), Color("#151a21"))
	_label("M6D MOTION CANDIDATE REVIEW", Vector2(28, 18), 26, Color.WHITE)
	var source_title := "%s 2×2 · independent cell extraction" % _sheet_source_label(resource_path) if not resource_path.is_empty() else "RESOURCE 2×2 not found · isolated unapproved attack originals"
	_label(source_title, Vector2(30, 54), 17, Color("#e5c98e"))
	_label("Order / alpha / identity / foot support need review · no manifest or PlayerArt changes", Vector2(30, 82), 14, Color("#c6d2dd"))
	for index in range(4):
		_draw_frame_panel(index)
	_label("ISOLATED TIMED PLAYBACK", Vector2(1310, 24), 20, Color.WHITE)
	_label("Direct frame switches · no procedural interpolation or pose deformation", Vector2(1310, 58), 13, Color("#c6d2dd"))
	_add_rect(PLAYER_RECT.position, PLAYER_RECT.size, Color("#202833"))
	_playback = TextureRect.new()
	_playback.position = PLAYER_RECT.position + Vector2(75, 76)
	_playback.size = Vector2(450, 520)
	_playback.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_playback.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_playback.texture = _textures[0]
	root.add_child(_playback)
	_playback_label = _label("READY", PLAYER_RECT.position + Vector2(20, 640), 20, Color("#ffe2a3"))
	_label("Observed wall time and rendered frames are logged per source pose.", Vector2(1310, 966), 13, Color("#c6d2dd"))
	_label("Approval: pending · runtime registration: none · procedural transform: none", Vector2(1310, 990), 12, Color("#c6d2dd"))

func _draw_frame_panel(index: int) -> void:
	var frame: Dictionary = _frames[index]
	var rect := Rect2(CELL_POSITIONS[index], CELL_SIZE)
	_add_rect(rect.position, rect.size, Color("#202833"))
	_draw_checkerboard(Rect2(rect.position + Vector2(12, 42), Vector2(270, 270)))
	var art := TextureRect.new()
	art.position = rect.position + Vector2(12, 42)
	art.size = ART_RECT_SIZE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = _textures[index]
	root.add_child(art)
	var anchor: Vector2i = frame.anchor
	_marker(rect.position + Vector2(12, 42), anchor, frame.image.get_size())
	_label("%02d · %s · %s" % [index + 1, frame.attack, frame.phase], rect.position + Vector2(12, 10), 14, Color.WHITE)
	_label("source cell: %s  ·  target %d ms" % [frame.cell_order, frame.duration_ms], rect.position + Vector2(300, 52), 11, Color("#e5c98e"))
	_label("alpha bounds: %s" % str(frame.bounds), rect.position + Vector2(300, 78), 11, Color("#ffe063"))
	_label("alpha: %d nonzero / %d partial" % [frame.alpha_nonzero, frame.alpha_partial], rect.position + Vector2(300, 102), 11, Color("#c6d2dd"))
	_label("bottom contact estimate: (%d,%d)" % [anchor.x, anchor.y], rect.position + Vector2(300, 126), 11, Color("#5ff0c2"))
	var edges: Dictionary = frame.edge_alpha
	var edge_total: int = edges.top + edges.bottom + edges.left + edges.right
	var edge_color := Color("#ff7770") if edge_total > 0 else Color("#7fe0a3")
	_label("cell-edge alpha T/B/L/R: %d/%d/%d/%d" % [edges.top, edges.bottom, edges.left, edges.right], rect.position + Vector2(300, 150), 10, edge_color)
	_label("character identity: human review", rect.position + Vector2(300, 180), 11, Color("#c6d2dd"))
	_label("support foot: human review", rect.position + Vector2(300, 204), 11, Color("#c6d2dd"))
	_label("transform: none; source pixels only", rect.position + Vector2(300, 228), 11, Color("#c6d2dd"))
	_label("actual change vs prior: logged after playback", rect.position + Vector2(300, 252), 10, Color("#c6d2dd"))
	_label("approval pending", rect.position + Vector2(300, 288), 11, Color("#ffbd69"))

func _play_sequence() -> void:
	for index in range(_frames.size()):
		var frame: Dictionary = _frames[index]
		_playback.texture = _textures[index]
		_playback_label.text = "%s · %s · %d ms" % [frame.attack, frame.phase, frame.duration_ms]
		var started := Time.get_ticks_usec()
		var deadline := started + int(frame.duration_ms) * 1000
		var rendered := 0
		while Time.get_ticks_usec() < deadline:
			await process_frame
			await RenderingServer.frame_post_draw
			rendered += 1
		var elapsed_ms := float(Time.get_ticks_usec() - started) / 1000.0
		var difference := -1 if index == 0 else _changed_pixels(_frames[index - 1].image, frame.image)
		var edges: Dictionary = frame.edge_alpha
		print("FRAME_EXPOSURE order=%d cell=%s source=%s target_ms=%d observed_ms=%.1f rendered_frames=%d changed_pixels_vs_previous=%d alpha_bounds=%s alpha_nonzero=%d bottom_contact_estimate=%s edge_alpha_TBLR=%d/%d/%d/%d procedural_transform=none" % [index + 1, frame.cell_order, frame.path.get_file(), frame.duration_ms, elapsed_ms, rendered, difference, str(frame.bounds), frame.alpha_nonzero, str(frame.anchor), edges.top, edges.bottom, edges.left, edges.right])
	print("REVIEW_GATE sequence=source_order alpha=measured identity=human_review support_foot=human_review measured_exposure=logged approval=not_performed runtime_registration=none procedural_variation=none")

func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	var raw := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))
	if raw.is_empty() or image.load_png_from_buffer(raw) != OK or image.is_empty():
		return null
	return image

func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _alpha_counts(image: Image) -> Array[int]:
	var nonzero := 0
	var partial := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var alpha := image.get_pixel(x, y).a
			if alpha > 0.0:
				nonzero += 1
				if alpha < 0.999:
					partial += 1
	return [nonzero, partial]

func _edge_alpha_counts(image: Image) -> Dictionary:
	var counts := {"top": 0, "bottom": 0, "left": 0, "right": 0}
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a >= ALPHA_THRESHOLD:
			counts.top += 1
		if image.get_pixel(x, image.get_height() - 1).a >= ALPHA_THRESHOLD:
			counts.bottom += 1
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a >= ALPHA_THRESHOLD:
			counts.left += 1
		if image.get_pixel(image.get_width() - 1, y).a >= ALPHA_THRESHOLD:
			counts.right += 1
	return counts

func _bottom_alpha_anchor(image: Image, bounds: Rect2i) -> Vector2i:
	if bounds.size == Vector2i.ZERO:
		return Vector2i(-1, -1)
	for y in range(bounds.end.y - 1, bounds.position.y - 1, -1):
		var left := image.get_width()
		var right := -1
		for x in range(bounds.position.x, bounds.end.x):
			if image.get_pixel(x, y).a >= ALPHA_THRESHOLD:
				left = mini(left, x)
				right = maxi(right, x)
		if right >= left:
			return Vector2i(roundi((left + right) * 0.5), y)
	return Vector2i(-1, -1)

func _changed_pixels(a: Image, b: Image) -> int:
	if a.get_size() != b.get_size():
		return -1
	var changed := 0
	for y in range(a.get_height()):
		for x in range(a.get_width()):
			if a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)) == false:
				changed += 1
	return changed

func _draw_checkerboard(rect: Rect2) -> void:
	for y in range(0, int(rect.size.y), 18):
		for x in range(0, int(rect.size.x), 18):
			var shade := Color("#3d454e") if ((x / 18 + y / 18) % 2) == 0 else Color("#303740")
			_add_rect(rect.position + Vector2(x, y), Vector2(mini(18, int(rect.size.x) - x), mini(18, int(rect.size.y) - y)), shade)

func _marker(origin: Vector2, point: Vector2i, source_size: Vector2i) -> void:
	if point.x < 0:
		return
	var scale := minf(ART_RECT_SIZE.x / float(source_size.x), ART_RECT_SIZE.y / float(source_size.y))
	var shown_size := Vector2(source_size) * scale
	var shown_origin := origin + (ART_RECT_SIZE - shown_size) * 0.5
	var at := shown_origin + Vector2(point) * scale
	_add_rect(at - Vector2(8, 2), Vector2(16, 4), Color("#ffe063"))
	_add_rect(at - Vector2(2, 8), Vector2(4, 16), Color("#ffe063"))

func _add_rect(position: Vector2, size: Vector2, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.position = position
	rect.size = size
	rect.color = color
	root.add_child(rect)
	return rect

func _label(value: String, position: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	root.add_child(label)
	return label

func _fail(message: String) -> void:
	push_error("m6d_motion_candidate_review: " + message)
	quit(1)
