extends SceneTree

const REVIEW := "res://assets/art/review/player_attack2_contact_v6_comparison.png"
const SOURCE_PATHS := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_inbetween_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
]
const V6_CANDIDATE_PATHS := [
	"res://assets/art/player/elven_fighter_attack2_v6_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_reference_v6_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_identity_candidate_1254x1254.png",
]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var review := _load_raw_image(REVIEW)
	_check(review != null, "separate comparison PNG decodes")
	if review != null:
		_check(review.get_size() == Vector2i(3768, 1000), "five-panel comparison includes the v6 candidate slot")
	for path in SOURCE_PATHS:
		var source := _load_raw_image(path)
		_check(source != null and source.get_size() == Vector2i(1254, 1254), "comparison source decodes at 1254 square: %s" % path.get_file())

	var candidate_path := ""
	for path in V6_CANDIDATE_PATHS:
		if FileAccess.file_exists(path):
			candidate_path = path
			break
	if candidate_path.is_empty():
		_check(review != null, "missing v6 art is represented by a review-only placeholder")
		print("v6 contact candidate: NOT PROVIDED; v5 edge-defect recurrence cannot be visually assessed.")
	else:
		var candidate := _load_raw_image(candidate_path)
		_check(candidate != null, "provided v6 candidate PNG decodes")
		if candidate != null:
			_check(candidate.get_size() == Vector2i(1254, 1254), "v6 candidate canvas is 1254x1254")
			_check(candidate.get_format() == Image.FORMAT_RGBA8, "v6 candidate is RGBA8 without conversion")
			var bounds := _alpha_bounds(candidate)
			var margins := _margins(candidate, bounds)
			var safe := bounds.size.x > 0 and margins.x >= 90 and margins.y >= 90 and margins.z >= 90 and margins.w >= 90
			var transparent_border := _transparent_border(candidate)
			var gate_pass := candidate.get_size() == Vector2i(1254, 1254) and candidate.get_format() == Image.FORMAT_RGBA8 and safe and transparent_border
			_check(review != null, "v6 candidate is retained in the separate review board regardless of gate outcome")
			print("V6 CHECK: nonzero-alpha margins L/T/R/B=%d/%d/%d/%d; transparent_border=%s; mechanical_gate=%s. Human review still required for identity, anatomy, motion and edge artifacts." % [margins.x, margins.y, margins.z, margins.w, str(transparent_border), str(gate_pass)])
	if failures.is_empty():
		print("player_attack2_contact_v6_smoke: mechanical checks passed; no image approval is implied")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack2_contact_v6_smoke: " + failure)
		quit(1)

func _load_raw_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path))) != OK or image.is_empty():
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

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a > 0.0 or image.get_pixel(x, image.get_height() - 1).a > 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a > 0.0 or image.get_pixel(image.get_width() - 1, y).a > 0.0:
			return false
	return true

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
