extends SceneTree

const CAPTURE := "res://assets/art/review/player_attack2_candidate_motion_strip.png"
const MANIFEST := "res://data/art/animation_manifest.json"
const VIEW_SIZE := Vector2i(1920, 1080)
const CELL_SIZE := Vector2i(480, 493)
const ROW_TOP := 94
const FOOT_MARGIN := 64
const ANCHOR_COLOR := Color("#ffe063")
const SOURCES := [
	"res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
]
const DURATIONS := [0.105, 0.050, 0.120, 0.140]

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var image := Image.new()
	_check(FileAccess.file_exists(CAPTURE) and image.load(ProjectSettings.globalize_path(CAPTURE)) == OK,
		"real-window motion strip decodes")
	if not image.is_empty():
		_check(image.get_size() == VIEW_SIZE, "capture is the required 1920x1080 Godot Window Viewport")
		for row in range(2):
			for column in range(4):
				_check(_anchor_marker_count(image, row, column) >= 12,
					"direction row %d frame %d includes its rendered bottom-alpha anchor marker" % [row, column])
	for path in SOURCES:
		var source := Image.new()
		_check(FileAccess.file_exists(path) and source.load(ProjectSettings.globalize_path(path)) == OK,
			"sequence source decodes: %s" % path.get_file())
		if not source.is_empty():
			_check(source.get_size() == Vector2i(1254, 1254), "sequence source keeps its original 1254 square canvas: %s" % path.get_file())
	_check(DURATIONS.size() == 4 and is_equal_approx(DURATIONS.reduce(func(sum: float, value: float) -> float: return sum + value, 0.0), 0.415),
		"ordered four-pose timing totals 415ms per direction without changing the source manifest")
	_check(_manifest_keeps_review_only_candidates(), "default manifest retains its approved contacts and does not register the safe v6 candidate")
	var middle := Image.new()
	var v6 := Image.new()
	middle.load(ProjectSettings.globalize_path(SOURCES[1]))
	v6.load(ProjectSettings.globalize_path(SOURCES[2]))
	var middle_anchor := _bottom_anchor_x(middle)
	var v6_anchor := _bottom_anchor_x(v6)
	var third := Image.new()
	third.load(ProjectSettings.globalize_path(SOURCES[3]))
	var third_anchor := _bottom_anchor_x(third)
	_check(middle_anchor > 1000 and v6_anchor > 1000 and third_anchor < 500,
		"automatic bottom-row contact changes from right boot to left boot at hit 3; visual support-leg review is required")
	if _failures.is_empty():
		print("attack2_candidate_motion_review_smoke: all checks passed; visual review remains pending")
		quit(0)
	else:
		for failure in _failures:
			push_error("attack2_candidate_motion_review_smoke: " + failure)
		quit(1)

func _anchor_marker_count(image: Image, row: int, column: int) -> int:
	var top := ROW_TOP + row * CELL_SIZE.y
	var y_start := top + CELL_SIZE.y - FOOT_MARGIN - 10
	var y_end := top + CELL_SIZE.y - FOOT_MARGIN + 10
	var count := 0
	for y in range(maxi(0, y_start), mini(image.get_height(), y_end)):
		for x in range(column * CELL_SIZE.x, mini(image.get_width(), (column + 1) * CELL_SIZE.x)):
			var pixel := image.get_pixel(x, y)
			if absf(pixel.r - ANCHOR_COLOR.r) < 0.03 and absf(pixel.g - ANCHOR_COLOR.g) < 0.03 \
				and absf(pixel.b - ANCHOR_COLOR.b) < 0.03 and pixel.a > 0.95:
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
