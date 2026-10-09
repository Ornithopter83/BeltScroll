extends SceneTree

const CAPTURE_SCRIPT := "res://tools/capture_raider_healthbars.gd"
const CAPTURE_PATH := "res://temp/raider_healthbars_window.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var capture_absolute := ProjectSettings.globalize_path(CAPTURE_PATH)
	if FileAccess.file_exists(capture_absolute):
		DirAccess.remove_absolute(capture_absolute)
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var output: Array = []
	var status := OS.execute(executable, ["--path", project_path, "--script", CAPTURE_SCRIPT], output, true)
	_check(status == 0, "actual Window capture process exits successfully (code %d)" % status)
	_check(_contains(output, "raider-healthbar-window-capture: all checks passed"), "capture process validates the rendered Raider states")
	if status != 0:
		for line in output:
			push_error(str(line))
	var image: Image
	if FileAccess.file_exists(capture_absolute):
		image = Image.load_from_file(capture_absolute)
	_check(image != null and not image.is_empty(), "actual Window capture PNG loads as a nonempty image")
	var capture_valid := false
	if image != null and not image.is_empty():
		var dimensions_valid := image.get_size() == EXPECTED_SIZE
		var bar_rect := _capture_bar_rect(output)
		var bars_rendered := dimensions_valid and bar_rect.size == Vector2i(84, 9) and Rect2i(Vector2i.ZERO, image.get_size()).encloses(bar_rect) and _has_rendered_color(image, bar_rect)
		_check(dimensions_valid, "Window capture is exactly 1920x1080")
		_check(bar_rect.size == Vector2i(84, 9), "capture reports the transformed Raider health bar pixel location")
		_check(bars_rendered, "captured healed Raider bar contains green fill and no red damage pixels at its reported location")
		capture_valid = dimensions_valid and bars_rendered
	if FileAccess.file_exists(capture_absolute):
		DirAccess.remove_absolute(capture_absolute)
	if DisplayServer.get_name() == "headless":
		_check(_contains(output, "saved rendered Window frame"), "headless smoke runner launches a separate Window renderer")
	if status == 0 and image != null and not image.is_empty() and capture_valid:
		print("raider_healthbar_window_smoke: all checks passed")
		quit(0)
	else:
		push_error("raider_healthbar_window_smoke: validation failed")
		quit(1)

func _has_rendered_color(image: Image, rect: Rect2i) -> bool:
	var green := 0
	var red := 0
	var sample_rect := rect.grow(3)
	for y in range(sample_rect.position.y, sample_rect.end.y):
		for x in range(sample_rect.position.x, sample_rect.end.x):
			var pixel := image.get_pixel(x, y)
			if pixel.g > pixel.r * 1.02 and pixel.g > pixel.b * 1.3:
				green += 1
			if pixel.r > pixel.g * 1.35 and pixel.r > pixel.b * 1.35:
				red += 1
	return green >= 8 and red < 8

func _capture_bar_rect(lines: Array) -> Rect2i:
	const PREFIX := "raider-healthbar-window-capture: healed-bar-rect="
	for line in lines:
		for value in str(line).split("\n"):
			var marker := value.find(PREFIX)
			if marker < 0:
				continue
			var fields := value.substr(marker + PREFIX.length()).strip_edges().split(",")
			if fields.size() != 4:
				return Rect2i()
			return Rect2i(Vector2i(int(fields[0]), int(fields[1])), Vector2i(int(fields[2]), int(fields[3])))
	return Rect2i()

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
