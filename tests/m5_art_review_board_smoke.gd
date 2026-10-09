extends SceneTree

const BOARD_PATH := "res://assets/art/review/m5_art_approval_board.png"
const BUILDER_PATH := "res://tools/build_m5_art_review_board.gd"
const PLAYER_DIR := "res://assets/art/player"
const LEFT := 24
const TOP := 164
const PANEL_W := 720
const PANEL_H := 680
const GAP := 24
const DISPLAY := 576
const COLUMNS := 4
const YELLOW := Color("#ffe063")
const MINT := Color("#5ff0c2")
const REQUIRED := [
	{"name":"v8 idle", "file":"elven_fighter_reference_v8_clean_candidate_1254x1254.png", "support_x":-1},
	{"name":"attack1 contact", "file":"elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png", "support_x":1073},
	{"name":"attack2 contact", "file":"elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png", "support_x":-1},
	{"name":"attack3 contact", "file":"elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png", "support_x":1000},
	{"name":"attack1 startup", "file":"elven_fighter_attack1_startup_v1_candidate_1254x1254.png", "support_x":-1},
	{"name":"attack2 safe middle", "file":"elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png", "support_x":1064},
	{"name":"attack2 v6 safe contact", "file":"elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png", "support_x":1100},
	{"name":"attack3 startup safe", "file":"elven_fighter_attack3_startup_v1_safe_candidate_1254x1254.png", "support_x":-1},
]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var builder_source := FileAccess.get_file_as_string(BUILDER_PATH)
	_check(not builder_source.is_empty(), "board builder source is readable")
	_check(builder_source.contains("func _existing_run_candidates") and builder_source.contains("lower.contains(\"run\")")
		and builder_source.contains("lower.contains(\"candidate\")") and builder_source.contains("lower.ends_with(\".png\")"),
		"run art is included only when an existing candidate PNG is found")
	_check(not builder_source.contains("animation_manifest.json") and not builder_source.contains("approval_state\" = \"approved\""),
		"board builder does not edit or promote the animation manifest")
	var builder_output: Array = []
	var project_root := ProjectSettings.globalize_path("res://")
	var builder_exit := OS.execute(OS.get_executable_path(), ["--headless", "--path", project_root, "--script", BUILDER_PATH], builder_output, true)
	_check(builder_exit == 0, "integrated board is freshly rebuilt from every existing review candidate")
	var items: Array[Dictionary] = []
	for item in REQUIRED:
		items.append(item)
		var source := _load_image(PLAYER_DIR.path_join(item.file))
		_check(source != null, "required source decodes: " + item.name)
		if source != null:
			_check(source.get_size() == Vector2i(1254, 1254), "source retains original canvas: " + item.name)
	var run_files := _run_candidate_files()
	if run_files.is_empty():
		items.append({"name":"run missing", "file":"", "support_x":-1})
	else:
		for run_file in run_files:
			items.append({"name":"run candidate", "file":run_file, "support_x":-1})
	var known_run_files := [
		"elven_fighter_run_stride_v1_candidate_1254x1254.png",
		"elven_fighter_run_stride_v1_safe_candidate_1254x1254.png",
		"elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png",
		"elven_fighter_run_stride_v2_safe_candidate_1254x1254.png",
		"elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png",
		"elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png",
		"elven_fighter_run_stride_v4_safe_candidate_1254x1254.png",
	]
	var expected_run_files: Array[String] = []
	for candidate_file in known_run_files:
		if FileAccess.file_exists(PLAYER_DIR.path_join(candidate_file)):
			expected_run_files.append(candidate_file)
	_check(run_files == expected_run_files,
		"all existing run candidates, including optional v4 files, are discovered in stable order")
	var board := _load_image(BOARD_PATH)
	_check(board != null, "integrated board PNG decodes")
	if board != null:
		var expected_rows := ceili(float(items.size()) / COLUMNS)
		var expected_size := Vector2i(LEFT * 2 + COLUMNS * PANEL_W + (COLUMNS - 1) * GAP, TOP + expected_rows * (PANEL_H + GAP) + 24)
		_check(board.get_size() == expected_size, "board dimensions match all supplied or explicitly missing panels")
		for index in range(items.size()):
			var item: Dictionary = items[index]
			var panel_rect := Rect2i(LEFT + (index % COLUMNS) * (PANEL_W + GAP), TOP + int(index / COLUMNS) * (PANEL_H + GAP), PANEL_W, PANEL_H)
			if item.file.is_empty():
				continue
			var source := _load_image(PLAYER_DIR.path_join(item.file))
			if source == null:
				continue
			if item.name == "run candidate":
				_check(source.get_size() == Vector2i(1254, 1254), "run review candidate keeps its source canvas: " + item.file)
				_check(not _builder_marks_run_approved(builder_source), "run candidates remain pending human approval: " + item.file)
			var alpha := _bottom_anchor(source)
			var marker := panel_rect.position + Vector2i((PANEL_W - DISPLAY) / 2, 60) + Vector2i(roundi(float(alpha.x) * DISPLAY / 1254.0), roundi(float(alpha.y) * DISPLAY / 1254.0))
			_check(_contains_color_near(board, marker, YELLOW, 8), "alpha anchor is rendered separately: " + item.name)
			if int(item.support_x) >= 0:
				var support_y := _foot_y_near_x(source, int(item.support_x))
				var support := panel_rect.position + Vector2i((PANEL_W - DISPLAY) / 2, 60) + Vector2i(roundi(float(item.support_x) * DISPLAY / 1254.0), roundi(float(support_y) * DISPLAY / 1254.0))
				_check(_contains_color_near(board, support, MINT, 8), "support foot candidate has its own marker: " + item.name)
			else:
				var image_rect := Rect2i(panel_rect.position + Vector2i((PANEL_W - DISPLAY) / 2, 60), Vector2i(DISPLAY, DISPLAY))
				_check(not _contains_color(board, image_rect, MINT), "unset support foot has no image marker: " + item.name)
	if failures.is_empty():
		print("m5_art_review_board_smoke: all checks passed; human art approval remains independent")
		quit(0)
	else:
		for failure in failures:
			push_error("m5_art_review_board_smoke: " + failure)
		quit(1)

func _run_candidate_files() -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(PLAYER_DIR)
	if directory == null:
		return result
	for file_name in directory.get_files():
		var lower := file_name.to_lower()
		if lower.contains("run") and lower.contains("candidate") and lower.ends_with(".png"):
			result.append(file_name)
	result.sort()
	return result

func _builder_marks_run_approved(source: String) -> bool:
	return source.contains('"RUN / CANDIDATE", "path":run_path, "kind":"APPROVED"')

func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		return null
	return image

func _bottom_anchor(image: Image) -> Vector2i:
	var bottom := -1
	var left := image.get_width()
	var right := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.05:
				if y > bottom:
					bottom = y
					left = x
					right = x
				elif y == bottom:
					left = mini(left, x)
					right = maxi(right, x)
	return Vector2i((left + right) / 2, bottom)

func _foot_y_near_x(image: Image, x: int) -> int:
	for y in range(image.get_height() - 1, -1, -1):
		for candidate_x in range(maxi(0, x - 36), mini(image.get_width(), x + 37)):
			if image.get_pixel(candidate_x, y).a >= 0.05:
				return y
	return image.get_height() - 1

func _contains_color_near(image: Image, point: Vector2i, color: Color, radius: int) -> bool:
	for y in range(maxi(0, point.y - radius), mini(image.get_height(), point.y + radius + 1)):
		for x in range(maxi(0, point.x - radius), mini(image.get_width(), point.x + radius + 1)):
			if _same_color(image.get_pixel(x, y), color):
				return true
	return false

func _contains_color(image: Image, rect: Rect2i, color: Color) -> bool:
	for y in range(maxi(0, rect.position.y), mini(image.get_height(), rect.end.y)):
		for x in range(maxi(0, rect.position.x), mini(image.get_width(), rect.end.x)):
			if _same_color(image.get_pixel(x, y), color):
				return true
	return false

func _same_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.01 and absf(a.g - b.g) < 0.01 and absf(a.b - b.b) < 0.01 and a.a > 0.95

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
