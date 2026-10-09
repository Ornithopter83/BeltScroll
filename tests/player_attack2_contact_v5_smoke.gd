extends SceneTree

const REVIEW := "res://assets/art/review/player_attack2_contact_v5_comparison.png"
const SOURCE_PATHS := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
]
const V5_CANDIDATE_PATHS := [
	"res://assets/art/player/elven_fighter_attack2_v5_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v5_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v5_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v5_identity_candidate_1254x1254.png",
]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var review := _load_image(REVIEW)
	_check(review != null, "independent comparison PNG decodes")
	if review != null:
		_check(review.get_size() == Vector2i(3744, 1000), "five-slot layout includes four existing frames and a v5 review slot")
	var candidate_path := ""
	for path in V5_CANDIDATE_PATHS:
		if FileAccess.file_exists(path):
			candidate_path = path
			break
	for path in SOURCE_PATHS:
		var source := _load_image(path)
		_check(source != null and source.get_size() == Vector2i(1254, 1254), "existing comparison source decodes at 1254 square: %s" % path.get_file())
	if candidate_path.is_empty():
		_check(review != null, "comparison remains valid when the v5 candidate has not been provided")
	else:
		var candidate := _load_raw_image(candidate_path)
		_check(candidate != null, "provided v5 candidate decodes")
		if candidate != null:
			var bounds := _alpha_bounds(candidate)
			var margins := _margins(candidate, bounds)
			_check(candidate.get_size() == Vector2i(1254, 1254), "v5 candidate uses the requested 1254x1254 canvas")
			_check(candidate.get_format() == Image.FORMAT_RGBA8, "v5 candidate is RGBA8 without conversion")
			var safe_margins := bounds.size.x > 0 and margins.x >= 90 and margins.y >= 90 and margins.z >= 90 and margins.w >= 90
			if safe_margins:
				_check(true, "v5 candidate has at least 90px margins from nonzero-alpha bounds on all sides")
			else:
				_check(review != null and review.get_size() == Vector2i(3744, 1000),
					"unsafe v5 candidate remains in the review gate and is not approved")
				print("v5 candidate rejected from approval: nonzero-alpha margins L/T/R/B=%d/%d/%d/%d" % [margins.x, margins.y, margins.z, margins.w])
	if failures.is_empty():
		print("player_attack2_contact_v5_smoke: all mechanical checks passed; visual approval remains human review")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack2_contact_v5_smoke: " + failure)
		quit(1)

func _load_image(path: String) -> Image:
	var image := _load_raw_image(path)
	if image != null and image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _load_raw_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))) != OK:
		return null
	return image

func _alpha_bounds(image: Image) -> Rect2i:
	var min_x := image.get_width()
	var min_y := image.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

func _margins(image: Image, bounds: Rect2i) -> Vector4i:
	if bounds.size.x <= 0:
		return Vector4i(-1, -1, -1, -1)
	return Vector4i(bounds.position.x, bounds.position.y, image.get_width() - bounds.end.x, image.get_height() - bounds.end.y)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
