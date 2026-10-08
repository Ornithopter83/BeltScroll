extends SceneTree

const REVIEWER := preload("res://tests/art_review.gd")
const VERSIONS := [
	"res://assets/art/player/elven_fighter_reference_v1_1254x1254.png",
	"res://assets/art/player/elven_fighter_reference_v2_1254x1254.png",
	"res://assets/art/player/elven_fighter_reference_v3_1254x1254.png",
]
const EXPECTED_BOUNDS := [
	Rect2i(0, 0, 1232, 1236),
	Rect2i(43, 21, 1193, 1233),
	Rect2i(0, 23, 1240, 1205),
]

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var project_path := ProjectSettings.globalize_path("res://")
	for index in range(VERSIONS.size()):
		var version: String = VERSIONS[index]
		var result: Dictionary = REVIEWER._inspect_png(ProjectSettings.globalize_path(version))
		_check(not result.passed and _contains_error(result, "최소 90px"), "%s preserves the existing 90px margin failure" % version.get_file())
		_check(result.has_alpha and result.has_transparent, "%s contains transparent alpha" % version.get_file())
		_check(result.bounds == EXPECTED_BOUNDS[index], "%s reports its expected non-transparent alpha bounds" % version.get_file())
		_check(_run_check(ProjectSettings.globalize_path(version), project_path) == 1, "%s --check exits 1 for its existing margin failure" % version.get_file())

	var temp_dir := ProjectSettings.globalize_path("res://temp/art_review_smoke")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var valid_path := temp_dir.path_join("valid.png")
	var margin_fail_path := temp_dir.path_join("margin_fail.png")
	var malformed_path := temp_dir.path_join("malformed.png")
	var missing_path := temp_dir.path_join("missing.png")
	_check(_write_synthetic(valid_path, Rect2i(90, 90, 1074, 1074)), "synthetic valid alpha PNG created")
	_check(_write_synthetic(margin_fail_path, Rect2i(89, 90, 1075, 1074)), "synthetic insufficient-margin PNG created")
	var malformed := FileAccess.open(malformed_path, FileAccess.WRITE)
	if malformed != null:
		malformed.store_buffer(PackedByteArray([1, 2, 3, 4]))
		malformed.close()
	var valid_result: Dictionary = REVIEWER._inspect_png(valid_path)
	_check(valid_result.passed, "synthetic PNG with exact 90px margins passes")
	_check(valid_result.bounds == Rect2i(90, 90, 1074, 1074), "synthetic alpha bounds are decoded exactly")
	var margin_result: Dictionary = REVIEWER._inspect_png(margin_fail_path)
	_check(not margin_result.passed and _contains_error(margin_result, "최소 90px"), "synthetic 89px left margin fails for the expected reason")
	_check(not REVIEWER._inspect_png(malformed_path).passed, "invalid PNG signature fails")
	_check(not REVIEWER._inspect_png(missing_path).passed, "missing image path fails")

	_check(_run_check(valid_path, project_path) == 0, "--check exits 0 for a passing absolute path")
	_check(_run_check(margin_fail_path, project_path) == 1, "--check exits 1 for a margin failure")
	_check(_run_check(missing_path, project_path) == 1, "--check exits 1 for a missing path")
	var relative_image := "assets/art/player/elven_fighter_reference_v1_1254x1254.png"
	_check(_run_check(relative_image, project_path) == 1, "--check resolves a project-relative path and preserves its margin failure")

	for path in [valid_path, margin_fail_path, malformed_path]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	DirAccess.remove_absolute(temp_dir)
	if failures.is_empty():
		print("art_review_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("art_review_smoke: " + failure)
		quit(1)

func _write_synthetic(path: String, opaque_rect: Rect2i) -> bool:
	var image := Image.create(1254, 1254, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	image.fill_rect(opaque_rect, Color(0.7, 0.3, 0.15, 1.0))
	return image.save_png(path) == OK

func _run_check(image_path: String, project_path: String) -> int:
	var output: Array = []
	var args := PackedStringArray([
		"--headless", "--path", project_path, "--script", "res://tests/art_review.gd",
		"--", "--check", image_path,
	])
	return OS.execute(OS.get_executable_path(), args, output, true)

func _contains_error(result: Dictionary, fragment: String) -> bool:
	for error in result.errors:
		if fragment in error:
			return true
	return false

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
