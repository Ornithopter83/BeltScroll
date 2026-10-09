extends SceneTree
"""Builds a review board and plays only acquired attack pose originals."""
# 실제 후보 원화만 순서대로 재생하고 승인 상태는 프레임 메타데이터와 분리한다.

const OUTPUT_PATH := "res://assets/art/review/m6b_attack_motion_strip.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const FRAMES := [
	{"attack": "ATTACK 1", "phase": "STARTUP", "path": "res://assets/art/player/elven_fighter_attack1_startup_v1_safe_candidate_1254x1254.png", "duration_ms": 105, "support_x": 326, "support_y": 1057, "status": "visual approval pending"},
	{"attack": "ATTACK 1", "phase": "CONTACT", "path": "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png", "duration_ms": 120, "support_x": 1073, "support_y": 1102, "status": "contour gate only; motion/identity approval pending"},
	{"attack": "ATTACK 2", "phase": "IN-BETWEEN", "path": "res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png", "duration_ms": 90, "support_x": 1063, "support_y": 1141, "status": "visual approval pending"},
	{"attack": "ATTACK 2", "phase": "CONTACT", "path": "res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png", "duration_ms": 120, "support_x": 1099, "support_y": 1123, "status": "visual approval pending"},
	{"attack": "ATTACK 3", "phase": "STARTUP", "path": "res://assets/art/player/elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png", "duration_ms": 105, "support_x": 458, "support_y": 1102, "status": "visual approval pending"},
	{"attack": "ATTACK 3", "phase": "CONTACT", "path": "res://assets/art/player/elven_fighter_attack3_reference_v2_safe_1254x1254.png", "duration_ms": 140, "support_x": 273, "support_y": 1125, "status": "visual approval pending"},
]
const LEFT_WIDTH := 1270.0
const CELL_SIZE := Vector2(610.0, 300.0)
const CELL_ORIGIN := Vector2(24.0, 140.0)
const PLAYBACK_RECT := Rect2(1310.0, 150.0, 580.0, 790.0)
const DISPLAY_SIZE := Vector2(470.0, 470.0)
const ALPHA_THRESHOLD := 0.05

var _images: Array[Image] = []
var _textures: Array[Texture2D] = []
var _bounds: Array[Rect2i] = []
var _bottom_anchors: Array[Vector2i] = []
var _support_markers: Array[Vector2i] = []
var _playback_sprite: TextureRect
var _playback_status: Label
var _time_log: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_build_and_play")

func _build_and_play() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("This review needs a visible Godot Window to capture and time the playback.")
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
	if not _load_sources():
		return
	_build_board()
	for _i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var strip := root.get_texture().get_image()
	if strip == null or strip.is_empty() or strip.get_size() != WINDOW_SIZE:
		_fail("Could not capture the 1920x1080 review board.")
		return
	var output_absolute := ProjectSettings.globalize_path(OUTPUT_PATH)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(output_absolute.get_base_dir())
	if mkdir_error != OK:
		_fail("Could not create the review image folder: %s" % error_string(mkdir_error))
		return
	var save_error := strip.save_png(output_absolute)
	if save_error != OK:
		_fail("Could not save the review strip: %s" % error_string(save_error))
		return
	var check := Image.new()
	if check.load(output_absolute) != OK or check.get_size() != WINDOW_SIZE:
		_fail("Saved review strip failed its PNG read-back check.")
		return
	print("M6B_REVIEW_CAPTURE path=%s size=%dx%d source_count=%d integration=none" % [OUTPUT_PATH, WINDOW_SIZE.x, WINDOW_SIZE.y, FRAMES.size()])
	await _play_sequence()
	_print_motion_checks()
	quit(0)

func _load_sources() -> bool:
	var byte_fingerprints: Dictionary = {}
	for item in FRAMES:
		var source_path: String = item.path
		var raw := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(source_path)) if FileAccess.file_exists(source_path) else PackedByteArray()
		var image := Image.new()
		if raw.is_empty() or image.load_png_from_buffer(raw) != OK or image.get_size() != Vector2i(1254, 1254):
			_fail("Missing, unreadable, or wrong-size original: %s" % source_path)
			return false
		var digest := _sha256_bytes(raw)
		if byte_fingerprints.has(digest):
			_fail("Duplicate source image cannot count as a new pose: %s duplicates %s" % [source_path, byte_fingerprints[digest]])
			return false
		byte_fingerprints[digest] = source_path
		var bounds := _alpha_bounds(image)
		var bottom := _bottom_anchor(image, bounds)
		if bounds.size == Vector2i.ZERO or bottom.x < 0:
			_fail("No usable alpha silhouette or bottom anchor: %s" % source_path)
			return false
		_images.append(image)
		_textures.append(ImageTexture.create_from_image(image))
		_bounds.append(bounds)
		_bottom_anchors.append(bottom)
		_support_markers.append(Vector2i(item.support_x, item.support_y))
	return true

func _sha256_bytes(bytes: PackedByteArray) -> String:
	var hashing := HashingContext.new()
	var error := hashing.start(HashingContext.HASH_SHA256)
	if error != OK:
		_fail("Could not initialize SHA-256 for source image validation.")
		return ""
	error = hashing.update(bytes)
	if error != OK:
		_fail("Could not hash source image bytes.")
		return ""
	return hashing.finish().hex_encode()

func _build_board() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#151a21")
	root.add_child(bg)
	_label("M6B ATTACK MOTION REVIEW · acquired candidate art only", Vector2(28, 18), 26, Color.WHITE)
	_label("Ordered source poses · original 1254 × 1254 canvas · target hold times · approval status remains separate", Vector2(30, 56), 15, Color("#e5c98e"))
	_label("Hands / arms: compare each real pose · Identity and planted foot require human review · no interpolated or duplicated frames", Vector2(30, 83), 14, Color("#c6d2dd"))
	for row in range(3):
		for col in range(2):
			var frame_index := row * 2 + col
			var item: Dictionary = FRAMES[frame_index]
			var cell := Rect2(CELL_ORIGIN + Vector2(float(col) * (CELL_SIZE.x + 18.0), float(row) * 302.0), CELL_SIZE)
			_add_panel(cell, item, frame_index)
	_label("Attack 2 startup source unavailable; playback begins at IN-BETWEEN.", Vector2(30, 108), 13, Color("#e5c98e"))
	_label("LIVE TIMED PLAYBACK", Vector2(1325, 18), 19, Color.WHITE)
	_label("Actual pose switches · no tween · one source per unique pose", Vector2(1325, 50), 13, Color("#c6d2dd"))
	var playback_panel := ColorRect.new()
	playback_panel.position = PLAYBACK_RECT.position
	playback_panel.size = PLAYBACK_RECT.size
	playback_panel.color = Color("#202833")
	root.add_child(playback_panel)
	_playback_sprite = TextureRect.new()
	_playback_sprite.position = PLAYBACK_RECT.position + Vector2(55, 68)
	_playback_sprite.size = DISPLAY_SIZE
	_playback_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_playback_sprite.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_playback_sprite.texture = _textures[0]
	root.add_child(_playback_sprite)
	_playback_status = _label("ATTACK 1 · STARTUP · 105 ms", Vector2(PLAYBACK_RECT.position.x + 20, PLAYBACK_RECT.end.y - 102), 19, Color("#ffe2a3"))
	_label("Target hold is stated per pose; measured wall time and rendered-frame count appear in the run log.", Vector2(1320, 962), 12, Color("#c6d2dd"))
	_label("No RESOURCE sheet, Player scene, or runtime manifest is read or changed.", Vector2(1320, 985), 12, Color("#c6d2dd"))

func _add_panel(cell: Rect2, item: Dictionary, index: int) -> void:
	var panel := ColorRect.new()
	panel.position = cell.position
	panel.size = cell.size
	panel.color = Color("#202833")
	root.add_child(panel)
	var art := TextureRect.new()
	art.position = cell.position + Vector2(17, 42)
	art.size = Vector2(245, 245)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.texture = _textures[index]
	root.add_child(art)
	var label := "%s · %s · %d ms" % [item.attack, item.phase, item.duration_ms]
	_label(label, cell.position + Vector2(12, 11), 14, Color.WHITE)
	var anchor := _bottom_anchors[index]
	_add_anchor_marker(cell.position, anchor, 245.0, Color("#ffe063"), false)
	_add_anchor_marker(cell.position, Vector2i(item.support_x, item.support_y), 245.0, Color("#5ff0c2"), true)
	_label("alpha bounds %s · bottom-alpha (%d,%d)" % [str(_bounds[index]), anchor.x, anchor.y], cell.position + Vector2(275, 58), 11, Color("#ffe063"))
	_label("support candidate (%d,%d)" % [item.support_x, item.support_y], cell.position + Vector2(275, 83), 11, Color("#5ff0c2"))
	_label("state: %s" % item.status, cell.position + Vector2(275, 120), 10, Color("#c6d2dd"))
	_label("Visual check: fist / forearm / shoulder", cell.position + Vector2(275, 150), 10, Color("#c6d2dd"))
	_label("Identity + foot lock: human decision", cell.position + Vector2(275, 172), 10, Color("#c6d2dd"))

func _play_sequence() -> void:
	for index in range(FRAMES.size()):
		var item: Dictionary = FRAMES[index]
		_playback_sprite.texture = _textures[index]
		_playback_status.text = "%s · %s · %d ms" % [item.attack, item.phase, item.duration_ms]
		var start := Time.get_ticks_usec()
		var deadline := start + int(item.duration_ms) * 1000
		var rendered := 0
		while Time.get_ticks_usec() < deadline:
			await process_frame
			await RenderingServer.frame_post_draw
			rendered += 1
		var elapsed_ms := float(Time.get_ticks_usec() - start) / 1000.0
		var event := {"index": index, "attack": item.attack, "phase": item.phase, "target_ms": item.duration_ms, "observed_ms": elapsed_ms, "rendered_frames": rendered, "source": item.path}
		_time_log.append(event)
		print("POSE_EXPOSURE attack=%s phase=%s source=%s target_ms=%d observed_ms=%.1f rendered_frames=%d" % [item.attack, item.phase, item.path.get_file(), item.duration_ms, elapsed_ms, rendered])

func _print_motion_checks() -> void:
	for attack_number in range(3):
		var first := attack_number * 2
		var second := first + 1
		var diff := _silhouette_difference(_images[first], _images[second])
		var bottom_a := _bottom_anchors[first]
		var bottom_b := _bottom_anchors[second]
		var support_a: Vector2i = _support_markers[first]
		var support_b: Vector2i = _support_markers[second]
		var raw_bottom_delta := bottom_b - bottom_a
		var support_delta := support_b - support_a
		print("POSE_DELTA attack=%d silhouette_pixels_changed=%d bottom_alpha_delta=%s support_candidate_delta=%s; candidates are not proof of planted-foot travel" % [attack_number + 1, diff, str(raw_bottom_delta), str(support_delta)])
	print("REVIEW_GATE hand_arm=human_review identity=human_review foot_slip=human_review contact_timing=target_ms_plus_logged_exposure approval=not_performed runtime_registration=none interpolated_frames=none duplicate_frames=none")

func _silhouette_difference(a: Image, b: Image) -> int:
	var changed := 0
	for y in range(0, 1254, 3):
		for x in range(0, 1254, 3):
			var a_inside := a.get_pixel(x, y).a >= ALPHA_THRESHOLD
			var b_inside := b.get_pixel(x, y).a >= ALPHA_THRESHOLD
			if a_inside != b_inside:
				changed += 1
	return changed * 9

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

func _bottom_anchor(image: Image, bounds: Rect2i) -> Vector2i:
	var row := bounds.end.y - 1
	var left := image.get_width()
	var right := -1
	for x in range(bounds.position.x, bounds.end.x):
		if image.get_pixel(x, row).a >= ALPHA_THRESHOLD:
			left = mini(left, x)
			right = maxi(right, x)
	return Vector2i(roundi((float(left) + float(right)) * 0.5), row) if right >= left else Vector2i(-1, -1)

func _add_anchor_marker(cell_position: Vector2, source_point: Vector2i, display_size: float, color: Color, circle: bool) -> void:
	var point := cell_position + Vector2(17.0, 42.0) + Vector2(source_point) * (display_size / 1254.0)
	if circle:
		var mark := ColorRect.new()
		mark.position = point - Vector2(5.0, 5.0)
		mark.size = Vector2(10.0, 10.0)
		mark.color = color
		root.add_child(mark)
		return
	var vertical := ColorRect.new()
	vertical.position = point - Vector2(1.5, 9.0)
	vertical.size = Vector2(3.0, 18.0)
	vertical.color = color
	root.add_child(vertical)
	var horizontal := ColorRect.new()
	horizontal.position = point - Vector2(9.0, 1.5)
	horizontal.size = Vector2(18.0, 3.0)
	horizontal.color = color
	root.add_child(horizontal)

func _label(text_value: String, at: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.position = at
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	root.add_child(label)
	return label

func _fail(message: String) -> void:
	push_error("m6b_attack_motion_review: " + message)
	quit(1)
