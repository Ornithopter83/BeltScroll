extends SceneTree

const NORMALIZER := preload("res://tools/normalize_stage_art.gd")
const REVIEWER := preload("res://tests/stage_art_review.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var input_path := ProjectSettings.globalize_path("res://temp/stage_tools_smoke_input.png")
	var output_path := ProjectSettings.globalize_path("res://temp/stage_tools_smoke_output.png")
	var image := Image.create(1600, 1000, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.2, 0.8, 0.3, 1.0))
	image.fill_rect(Rect2i(0, 0, 1600, 50), Color.RED)
	image.fill_rect(Rect2i(0, 950, 1600, 50), Color.BLUE)
	var save_error := image.save_png(input_path)
	_check(save_error == OK, "synthetic source PNG can be created")
	var normalize_error: Error = NORMALIZER.normalize_file(input_path, output_path)
	_check(normalize_error == OK, "PNG decoder, crop, Lanczos resize, and PNG save succeed")
	var result: Dictionary = REVIEWER.inspect_png(output_path)
	_check(result.passed, "normalized synthetic PNG passes exact 1920x1080 review")
	_check(result.width == 1920 and result.height == 1080, "normalized output dimensions are 1920x1080")
	var output_image: Image = result.image
	var crop_sample := output_image.get_pixel(960, 24)
	_check(Vector3(crop_sample.r, crop_sample.g, crop_sample.b).distance_to(Vector3(0.2, 0.8, 0.3)) < 0.01, "central crop excludes both outer 50px bands")
	var wrong_size: Dictionary = REVIEWER.inspect_png(input_path)
	_check(not wrong_size.passed, "review rejects a valid PNG with the wrong dimensions")
	DirAccess.remove_absolute(input_path)
	DirAccess.remove_absolute(output_path)
	if failures.is_empty():
		print("stage_tools_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("stage_tools_smoke: " + failure)
		quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
