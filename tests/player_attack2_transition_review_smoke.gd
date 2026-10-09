extends SceneTree

const REVIEW := "res://assets/art/review/player_attack2_transition_comparison.png"
const SOURCE_PATHS := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png",
]
const MIDDLE_PATHS := [
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_intermediate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_intermediate_v1_1254x1254.png",
]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var review_path := ProjectSettings.globalize_path(REVIEW)
	var review := _load_image(review_path)
	_check(review != null, "transition comparison PNG decodes")
	var has_middle := false
	var middle_path := ""
	for path in MIDDLE_PATHS:
		if FileAccess.file_exists(path):
			has_middle = true
			middle_path = path
			break
	if review != null:
		var expected_width := 48 + (5 if has_middle else 4) * 720 + ((5 if has_middle else 4) - 1) * 24
		_check(review.get_size() == Vector2i(expected_width, 1000), "comparison has all poses and the expected 3x display layout")
	if has_middle:
		var middle := _load_unconverted_image(ProjectSettings.globalize_path(middle_path))
		_check(middle != null and middle.get_size() == Vector2i(1254, 1254) and middle.get_format() == Image.FORMAT_RGBA8,
			"provided attack2 intermediate is an unmodified RGBA8 1254 square PNG")
		if middle_path == MIDDLE_PATHS[0] and middle != null:
			_check(not _valid_middle(middle), "current candidate's top/bottom safe margins fail the 90px gate and remain review-only")
		else:
			_check(middle != null and _valid_middle(middle), "alternate intermediate satisfies the strict safe alpha margin gate")
	else:
		_check(review != null, "comparison documents existing-art-only state when no intermediate is provided")
	for path in SOURCE_PATHS:
		var image := _load_image(ProjectSettings.globalize_path(path))
		_check(image != null, "selected waiting/contact source decodes: %s" % path.get_file())
		if image != null:
			_check(image.get_size() == Vector2i(1254, 1254), "source uses 1254x1254 canvas: %s" % path.get_file())
	if failures.is_empty():
		print("player_attack2_transition_review_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack2_transition_review_smoke: " + failure)
		quit(1)

func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _load_unconverted_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return image

func _valid_middle(image: Image) -> bool:
	if image.get_size() != Vector2i(1254, 1254) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var min_x := 1254
	var min_y := 1254
	var max_x := -1
	var max_y := -1
	for y in range(1254):
		for x in range(1254):
			if image.get_pixel(x, y).a >= 0.05:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	if max_x < min_x or min_x < 90 or min_y < 90 or 1253 - max_x < 90 or 1253 - max_y < 90:
		return false
	for x in range(1254):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, 1253).a != 0.0:
			return false
	for y in range(1254):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(1253, y).a != 0.0:
			return false
	return true

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
