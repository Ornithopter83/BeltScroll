extends SceneTree
"""Normalize a newly supplied single attack1 contact and build an isolated review board."""

const INPUT_ROOT := "res://assets/art/player"
const IDLE_SOURCE := "res://assets/art/player/elven_fighter_dark_fantasy_redesign_v1_candidate_1254x1254.png"
const M6D_SHEET := "res://assets/art/player/elven_fighter_dark_fantasy_attack1_sheet_v1_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_dark_fantasy_attack1_contact_safe_candidate_1254x1254.png"
const COMPARISON := "res://assets/art/review/m6e_attack1_candidate_comparison.png"
const CANVAS := Vector2i(1254, 1254)
const SAFE_MARGIN := 90
const ALPHA_THRESHOLD := 0.05
const WINDOW_SIZE := Vector2i(1920, 1080)

var _candidate: Image
var _idle: Image
var _sheet: Image
var _cells: Array[Dictionary] = []

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	_idle = _load_image(IDLE_SOURCE)
	_sheet = _load_image(M6D_SHEET)
	var source_path := _find_single_contact()
	if not source_path.is_empty():
		var source := _load_image(source_path)
		if source == null:
			_fail("Single-contact input exists but could not be decoded: %s" % source_path)
			return
		_candidate = normalize_image(source)
		if _candidate.is_empty():
			_fail("Single-contact input has no visible alpha content: %s" % source_path)
			return
		var output_path := ProjectSettings.globalize_path(OUTPUT)
		var mkdir_error := DirAccess.make_dir_recursive_absolute(output_path.get_base_dir())
		if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
			_fail("Could not create candidate directory: %s" % error_string(mkdir_error))
			return
		var save_error := _candidate.save_png(output_path)
		if save_error != OK:
			_fail("Could not save normalized candidate: %s" % error_string(save_error))
			return
		print("M6E_INPUT status=found path=%s normalized=%s rgba=%s alpha_bounds=%s foot_anchor_y=%d" % [source_path, OUTPUT, str(_candidate.get_format()), str(alpha_bounds(_candidate)), alpha_bounds(_candidate).end.y])
	else:
		print("M6E_INPUT status=not_found searched=%s filter=dark_fantasy+attack1+contact+single_image; candidate_output_not_created" % INPUT_ROOT)
	if _sheet != null and _sheet.get_width() % 2 == 0 and _sheet.get_height() % 2 == 0:
		var cell_size := _sheet.get_size() / 2
		for index in range(4):
			var origin := Vector2i(index % 2, index / 2) * cell_size
			var cell: Image = _sheet.get_region(Rect2i(origin, cell_size))
			_cells.append({"image": cell, "origin": origin, "order": ["좌상", "우상", "좌하", "우하"][index], "bounds": alpha_bounds(cell), "edges": edge_alpha_counts(cell)})
	for index in range(_cells.size()):
		var info: Dictionary = _cells[index]
		var edges: Dictionary = info.edges
		print("M6E_M6D_CELL order=%s origin=%s size=%s alpha_bounds=%s edge_alpha_TBLR=%d/%d/%d/%d cut_or_bleed_risk=%s" % [info.order, str(info.origin), str(info.image.get_size()), str(info.bounds), edges.top, edges.bottom, edges.left, edges.right, "yes" if _edge_total(edges) > 0 else "not_detected"])
	await _capture_review(source_path)
	quit(0)

func _find_single_contact() -> String:
	var dir := DirAccess.open(INPUT_ROOT)
	if dir == null:
		return ""
	var resources: Array[String] = []
	var other_single: Array[String] = []
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if not dir.current_is_dir() and entry.get_extension().to_lower() == "png":
			var name := entry.to_lower()
			if name.contains("dark_fantasy") and name.contains("attack1") and name.contains("contact") and not name.contains("sheet"):
				if name.contains("resource"):
					resources.append(INPUT_ROOT.path_join(entry))
				else:
					other_single.append(INPUT_ROOT.path_join(entry))
		entry = dir.get_next()
	dir.list_dir_end()
	resources.sort()
	other_single.sort()
	return resources[0] if not resources.is_empty() else (other_single[0] if not other_single.is_empty() else "")

static func normalize_image(source: Image) -> Image:
	if source == null or source.is_empty():
		return Image.new()
	var rgba := source.duplicate()
	if rgba.get_format() != Image.FORMAT_RGBA8:
		rgba.convert(Image.FORMAT_RGBA8)
	var bounds := alpha_bounds(rgba)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return Image.new()
	var max_content := CANVAS.x - SAFE_MARGIN * 2
	var scale := minf(1.0, minf(float(max_content) / bounds.size.x, float(max_content) / bounds.size.y))
	var target_size := Vector2i(maxi(1, roundi(bounds.size.x * scale)), maxi(1, roundi(bounds.size.y * scale)))
	var content: Image = rgba.get_region(bounds)
	if content.get_size() != target_size:
		content.resize(target_size.x, target_size.y, Image.INTERPOLATE_LANCZOS)
	var result := Image.create(CANVAS.x, CANVAS.y, false, Image.FORMAT_RGBA8)
	result.fill(Color(0, 0, 0, 0))
	var target := Vector2i((CANVAS.x - target_size.x) / 2, CANVAS.y - SAFE_MARGIN - target_size.y)
	result.blit_rect(content, Rect2i(Vector2i.ZERO, target_size), target)
	return result

static func alpha_bounds(image: Image) -> Rect2i:
	if image == null or image.is_empty():
		return Rect2i()
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

static func edge_alpha_counts(image: Image) -> Dictionary:
	var result := {"top": 0, "bottom": 0, "left": 0, "right": 0}
	if image == null or image.is_empty():
		return result
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a >= ALPHA_THRESHOLD:
			result.top += 1
		if image.get_pixel(x, image.get_height() - 1).a >= ALPHA_THRESHOLD:
			result.bottom += 1
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a >= ALPHA_THRESHOLD:
			result.left += 1
		if image.get_pixel(image.get_width() - 1, y).a >= ALPHA_THRESHOLD:
			result.right += 1
	return result

func _capture_review(source_path: String) -> void:
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	root.title = "M6E Attack1 Contact Candidate Review"
	var board := Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(board)
	var bg := ColorRect.new()
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.color = Color("#11181f")
	board.add_child(bg)
	_add_label(board, "M6E  /  ATTACK1 SINGLE CONTACT REVIEW", Vector2(36, 22), 30, Color("#f2dfbc"))
	_add_label(board, "RGBA normalization + transparent bounds + bottom foot anchor  /  2×2 edge-alpha diagnostic", Vector2(38, 68), 17, Color("#a9c0c3"))
	var panels := [Vector2(36, 128), Vector2(670, 128), Vector2(1304, 128)]
	var titles := ["DARK FANTASY IDLE · SOURCE", "NEW CONTACT · " + ("NORMALIZED CANDIDATE" if _candidate != null else "INPUT NOT FOUND"), "M6D · EXISTING 2×2 SHEET"]
	for index in range(3):
		var panel := ColorRect.new()
		panel.position = panels[index]
		panel.size = Vector2(580, 810)
		panel.color = Color("#1b252c")
		board.add_child(panel)
		_add_label(board, titles[index], panels[index] + Vector2(18, 18), 18, Color.WHITE)
		_add_checker(board, Rect2(panels[index] + Vector2(16, 58), Vector2(548, 550)))
	if _idle != null:
		_add_image(board, _idle, Rect2(panels[0] + Vector2(40, 70), Vector2(500, 520)))
	if _candidate != null:
		_add_image(board, _candidate, Rect2(panels[1] + Vector2(40, 70), Vector2(500, 520)))
	else:
		_add_label(board, "NO NEW SINGLE-CONTACT INPUT", panels[1] + Vector2(70, 270), 20, Color("#ffbd69"))
		_add_label(board, "No safe candidate was generated.\nThe existing 2×2 sheet is not substituted.", panels[1] + Vector2(70, 310), 15, Color("#c6d2dd"))
	if _sheet != null:
		_add_image(board, _sheet, Rect2(panels[2] + Vector2(80, 115), Vector2(420, 420)))
	for index in range(_cells.size()):
		var info: Dictionary = _cells[index]
		var edges: Dictionary = info.edges
		var text := "%s cell edge α T/B/L/R %d/%d/%d/%d" % [info.order, edges.top, edges.bottom, edges.left, edges.right]
		_add_label(board, text, panels[2] + Vector2(20, 610 + index * 31), 13, Color("#ff8580") if _edge_total(edges) > 0 else Color("#a9c0c3"))
	_add_label(board, "Source: %s" % (source_path.get_file() if not source_path.is_empty() else "missing"), panels[1] + Vector2(18, 630), 12, Color("#a9c0c3"))
	_add_label(board, "Foot anchor = lowest visible alpha row after normalization; support foot needs human review.", Vector2(38, 965), 16, Color("#e4bd7a"))
	_add_label(board, "Review only · candidate approval pending · no limb reconstruction · no PlayerArt / manifest / allowlist changes", Vector2(38, 1000), 14, Color("#a9c0c3"))
	for _i in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var capture := root.get_texture().get_image()
	if capture == null or capture.get_size() != WINDOW_SIZE:
		_fail("Could not capture the comparison board at 1920×1080.")
		return
	var target := ProjectSettings.globalize_path(COMPARISON)
	var mkdir_error := DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if mkdir_error != OK and mkdir_error != ERR_ALREADY_EXISTS:
		_fail("Could not create review directory: %s" % error_string(mkdir_error))
		return
	var save_error := capture.save_png(target)
	if save_error != OK:
		_fail("Could not save review comparison: %s" % error_string(save_error))
		return
	print("M6E_REVIEW board=%s candidate=%s approval=pending manifest_allowlist_playerart=untouched" % [COMPARISON, "present" if _candidate != null else "not_created"])

func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _add_image(parent: Control, image: Image, rect: Rect2) -> void:
	var texture := TextureRect.new()
	texture.position = rect.position
	texture.size = rect.size
	texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	texture.texture = ImageTexture.create_from_image(image)
	parent.add_child(texture)

func _add_checker(parent: Control, rect: Rect2) -> void:
	var base := ColorRect.new()
	base.position = rect.position
	base.size = rect.size
	base.color = Color("#29343a")
	parent.add_child(base)
	for y in range(int(rect.size.y / 28) + 1):
		for x in range(int(rect.size.x / 28) + 1):
			if (x + y) % 2 == 0:
				var tile := ColorRect.new()
				tile.position = rect.position + Vector2(x * 28, y * 28)
				tile.size = Vector2(minf(28, rect.size.x - x * 28), minf(28, rect.size.y - y * 28))
				tile.color = Color("#344149")
				parent.add_child(tile)

func _add_label(parent: Control, value: String, position: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = position
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)

func _edge_total(edges: Dictionary) -> int:
	return edges.top + edges.bottom + edges.left + edges.right

func _fail(message: String) -> void:
	push_error("m6e_attack1_candidate: " + message)
	quit(1)
