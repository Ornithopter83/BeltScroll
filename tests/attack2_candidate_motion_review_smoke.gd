extends SceneTree

const CAPTURE := "res://assets/art/review/player_attack2_candidate_motion_strip.png"
const CAPTURE_TOOL := "res://tools/capture_attack2_candidate_motion_review.gd"
const MANIFEST := "res://data/art/animation_manifest.json"
const VIEW_SIZE := Vector2i(1920, 1080)
const CELL_SIZE := Vector2i(480, 225)
const TOP := 158
const BOTTOM_ALPHA_COLOR := Color("#ffe063")
const SUPPORT_COLOR := Color("#5ff0c2")
const SOURCES := [
	"res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
]
const DURATIONS := [0.105, 0.050, 0.120, 0.140]
const SUPPORT_FOOT_X := [1073, 1064, 1100, 1000]

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var image := Image.new()
	_check(FileAccess.file_exists(CAPTURE) and image.load(ProjectSettings.globalize_path(CAPTURE)) == OK,
		"real-window motion strip decodes")
	if not image.is_empty():
		_check(image.get_size() == VIEW_SIZE, "capture is the required 1920x1080 Godot Window Viewport")
		for row in range(4):
			for column in range(4):
				_check(_marker_count(image, row, column, BOTTOM_ALPHA_COLOR, -22) >= 12,
					"row %d frame %d renders the lowest-alpha-center marker" % [row, column])
				_check(_marker_count(image, row, column, SUPPORT_COLOR, -9) >= 12,
					"row %d frame %d renders a separate support-foot candidate marker" % [row, column])
	for path in SOURCES:
		var source := Image.new()
		_check(FileAccess.file_exists(path) and source.load(ProjectSettings.globalize_path(path)) == OK,
			"sequence source decodes: %s" % path.get_file())
		if not source.is_empty():
			_check(source.get_size() == Vector2i(1254, 1254), "source keeps its 1254 square canvas: %s" % path.get_file())
	_check(DURATIONS.size() == 4 and is_equal_approx(DURATIONS[1], 0.050)
		and is_equal_approx(DURATIONS.reduce(func(sum: float, value: float) -> float: return sum + value, 0.0), 0.415),
		"50ms safe-middle target and ordered 415ms sequence are isolated from the manifest")
	_check(_capture_tool_records_rendered_exposure(), "capture tool records actual rendered and midpoint frame counts")
	_check(_manifest_keeps_review_only_candidates(), "default manifest and original approval states stay unchanged")
	var v6 := Image.new()
	var third := Image.new()
	v6.load(ProjectSettings.globalize_path(SOURCES[2]))
	third.load(ProjectSettings.globalize_path(SOURCES[3]))
	var v6_bottom := _bottom_anchor_x(v6)
	var third_bottom := _bottom_anchor_x(third)
	var derived_screen_delta := absf(float(v6_bottom - third_bottom) * (330.0 / 1254.0))
	_check(v6_bottom > 1000 and third_bottom < 500 and derived_screen_delta >= 190.0 and derived_screen_delta <= 235.0,
		"v6-to-3 lowest-alpha-center change is approximately 217 display px at the review scale")
	_check(SUPPORT_FOOT_X[2] > 900 and SUPPORT_FOOT_X[3] > 900,
		"visual support-foot candidate stays separate from the third-hit low-alpha-center heuristic")
	if _failures.is_empty():
		print("attack2_candidate_motion_review_smoke: all checks passed; visual motion judgment remains pending")
		quit(0)
	else:
		for failure in _failures:
			push_error("attack2_candidate_motion_review_smoke: " + failure)
		quit(1)

func _marker_count(image: Image, row: int, column: int, marker_color: Color, vertical_offset: int) -> int:
	var cell_top := TOP + row * CELL_SIZE.y + 22
	var baseline_y := cell_top + CELL_SIZE.y - 35 - 27
	var marker_y := baseline_y + vertical_offset
	var count := 0
	for y in range(maxi(0, marker_y), mini(image.get_height(), marker_y + 18)):
		for x in range(column * CELL_SIZE.x, mini(image.get_width(), (column + 1) * CELL_SIZE.x)):
			var pixel := image.get_pixel(x, y)
			if absf(pixel.r - marker_color.r) < 0.03 and absf(pixel.g - marker_color.g) < 0.03 \
				and absf(pixel.b - marker_color.b) < 0.03 and pixel.a > 0.95:
				count += 1
	return count

func _bottom_anchor_x(image: Image) -> int:
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a >= 0.05:
				bottom = maxi(bottom, y)
	if bottom < 0:
		return -1
	var left := image.get_width()
	var right := -1
	for x in range(image.get_width()):
		if image.get_pixel(x, bottom).a >= 0.05:
			left = mini(left, x)
			right = maxi(right, x)
	return roundi(float(left + right) * 0.5) if right >= left else -1

func _manifest_keeps_review_only_candidates() -> bool:
	var file := FileAccess.open(MANIFEST, FileAccess.READ)
	if file == null:
		return false
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or not parsed.has("clips"):
		return false
	var frames_by_clip: Dictionary = {}
	for clip in parsed["clips"]:
		if clip is Dictionary and clip.has("id"):
			frames_by_clip[clip["id"]] = clip.get("frames", [])
	var attack1_contact := _find_manifest_frame(frames_by_clip.get("attack1", []), "contact")
	var attack2_mid := _find_manifest_frame(frames_by_clip.get("attack2", []), "inbetween")
	var attack2_v6 := _find_manifest_frame(frames_by_clip.get("attack2", []), "elven_fighter_attack2_contact_v6_candidate_1254x1254.png")
	var attack3_contact := _find_manifest_frame(frames_by_clip.get("attack3", []), "contact")
	return attack1_contact.get("approval_state", "") == "approved" \
		and attack1_contact.get("texture", "").ends_with("elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png") \
		and attack2_mid.get("approval_state", "") == "unapproved" \
		and attack2_mid.get("texture", "").ends_with("elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png") \
		and is_equal_approx(float(attack2_mid.get("duration", 0.0)), 0.050) \
		and attack2_v6.get("approval_state", "") == "unapproved" \
		and attack2_v6.get("texture", "").ends_with("elven_fighter_attack2_contact_v6_candidate_1254x1254.png") \
		and attack3_contact.get("approval_state", "") == "approved" \
		and attack3_contact.get("texture", "").ends_with("elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png")

func _capture_tool_records_rendered_exposure() -> bool:
	var file := FileAccess.open(CAPTURE_TOOL, FileAccess.READ)
	if file == null:
		return false
	var source := file.get_as_text()
	return source.contains("RenderingServer.frame_post_draw") \
		and source.contains("rendered_frames") \
		and source.contains("midpoint_rendered_frames")

func _find_manifest_frame(frames: Variant, phase_or_file: String) -> Dictionary:
	if frames is Array:
		for frame in frames:
			if not frame is Dictionary:
				continue
			var texture: Variant = frame.get("texture", "")
			if frame.get("phase", "") == phase_or_file or (texture is String and texture.ends_with(phase_or_file)):
				return frame
	return {}

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
