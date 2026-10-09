extends SceneTree

const CAPTURE_SCRIPT := "res://tools/capture_raider_healthbars.gd"
const CAPTURE_PATH := "res://temp/raider_healthbars_window.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var status := OS.execute(executable, ["--path", project_path, "--script", CAPTURE_SCRIPT], output, true)
	_check(status == 0, "actual Window capture process exits successfully (code %d)" % status)
	_check(_contains(output, "raider-healthbar-window-capture: all checks passed"), "capture process validates the rendered Raider states")
	if status != 0:
		for line in output:
			push_error(str(line))
	var image := Image.new()
	var load_error := image.load(ProjectSettings.globalize_path(CAPTURE_PATH))
	_check(load_error == OK, "actual Window capture PNG loads")
	var capture_valid := false
	if load_error == OK:
		var dimensions_valid := image.get_size() == EXPECTED_SIZE
		var bars_rendered := dimensions_valid and _has_rendered_color(image)
		_check(dimensions_valid, "Window capture is exactly 1920x1080")
		_check(bars_rendered, "captured Raider health bars contain rendered fill pixels")
		capture_valid = dimensions_valid and bars_rendered
	var capture_absolute := ProjectSettings.globalize_path(CAPTURE_PATH)
	if FileAccess.file_exists(capture_absolute):
		DirAccess.remove_absolute(capture_absolute)
	if DisplayServer.get_name() == "headless":
		_check(_contains(output, "saved rendered Window frame"), "headless smoke runner launches a separate Window renderer")
	if status == 0 and load_error == OK and capture_valid:
		print("raider_healthbar_window_smoke: all checks passed")
		quit(0)
	else:
		push_error("raider_healthbar_window_smoke: validation failed")
		quit(1)

func _has_rendered_color(image: Image) -> bool:
	var colored := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.g > 0.32 and pixel.g > pixel.r * 1.18 and pixel.g > pixel.b * 1.05:
				colored += 1
	return colored >= 40

func _contains(lines: Array, fragment: String) -> bool:
	for line in lines:
		if str(line).contains(fragment):
			return true
	return false

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		push_error("raider_healthbar_window_smoke: " + description)
