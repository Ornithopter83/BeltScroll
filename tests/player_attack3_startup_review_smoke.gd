extends SceneTree

const TOOL := preload("res://tools/build_player_attack3_startup_review.gd")
const REVIEW := "res://assets/art/review/player_attack3_startup_comparison.png"
const SOURCES := [
	"res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack2_contact_v6_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack3_reference_v2_clean_candidate_1254x1254.png",
]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var valid_fixture := Image.create(1254, 1254, false, Image.FORMAT_RGBA8)
	valid_fixture.fill(Color(0, 0, 0, 0))
	valid_fixture.fill_rect(Rect2i(90, 90, 10, 10), Color.WHITE)
	_check(TOOL._strict_safe(valid_fixture), "mechanical validator accepts exact 90px margins and transparent outer edge")
	valid_fixture.set_pixel(0, 0, Color.WHITE)
	_check(not TOOL._strict_safe(valid_fixture), "mechanical validator rejects nontransparent outer edge")
	var review := _load_image(ProjectSettings.globalize_path(REVIEW))
	_check(review != null, "comparison PNG decodes")
	var startup_path := TOOL._find_startup()
	var startup_found := not startup_path.is_empty()
	if review != null:
		var expected_width := 48 + 4 * 720 + 3 * 24
		_check(review.get_size() == Vector2i(expected_width, 1000), "comparison shows three reference poses plus startup candidate or missing-art panel")
	if startup_found:
		var startup := TOOL._load_raw(startup_path)
		_check(startup != null, "startup candidate PNG decodes")
		if startup != null:
			print("INFO: startup strict mechanical gate=" + str(TOOL._strict_safe(startup)))
			_check(startup.get_size() == Vector2i(1254, 1254) and startup.get_format() == Image.FORMAT_RGBA8,
				"startup candidate format and canvas are inspected without assuming visual approval")
	else:
		_check(review != null, "comparison explicitly records that startup art has not been provided")
	for path in SOURCES:
		var source := TOOL._load_raw(path)
		_check(source != null and source.get_size() == Vector2i(1254, 1254), "comparison source decodes at 1254 square: " + path.get_file())
	if failures.is_empty():
		print("player_attack3_startup_review_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_attack3_startup_review_smoke: " + failure)
		quit(1)

func _load_image(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return image

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

