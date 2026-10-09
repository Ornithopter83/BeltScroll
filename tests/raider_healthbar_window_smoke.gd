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
	var output: Array = []
	var status := OS.execute(OS.get_executable_path(), ["--path", ProjectSettings.globalize_path("res://"), "--script", CAPTURE_SCRIPT], output, true)
	_check(status == 0, "actual Window capture process exits successfully (code %d)" % status)
	_check(_contains(output, "raider-healthbar-window-capture: all checks passed"), "capture process validates actual fixed Player and Raider renders")
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
		var player_rect := _capture_rect(output, "player-bar-rect=")
		var raider_rect := _capture_rect(output, "raider-bar-rect=")
		var player_pixels := _is_expected_rect(player_rect, image) and _has_yellow_fill(image, player_rect)
		var raider_pixels := _is_expected_rect(raider_rect, image) and _has_yellow_fill(image, raider_rect)
		_check(dimensions_valid, "Window capture is exactly 1920x1080")
		_check(player_rect.size.x > 0 and Rect2i(Vector2i.ZERO, image.get_size()).encloses(player_rect), "capture reports the fixed Player bar pixel location")
		_check(raider_rect.size.x == 300 and raider_rect.size.y >= 9 and raider_rect.size.y <= 32 and Rect2i(Vector2i.ZERO, image.get_size()).encloses(raider_rect), "capture reports the fixed Raider bar pixel location and rendered height")
		_check(player_pixels and raider_pixels, "healed Player and Raider capture rows contain rendered yellow fill without red damage pixels")
		capture_valid = dimensions_valid and player_pixels and raider_pixels
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

func _is_expected_rect(rect: Rect2i, image: Image) -> bool:
	return rect.size.x == 300 and rect.size.y >= 9 and rect.size.y <= 32 and Rect2i(Vector2i.ZERO, image.get_size()).encloses(rect)

func _has_yellow_fill(image: Image, rect: Rect2i) -> bool:
	var yellow := 0
	var red := 0
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var pixel := image.get_pixel(x, y)
			if pixel.r > 0.72 and pixel.g > 0.60 and pixel.b < 0.34:
				yellow += 1
			if pixel.r > pixel.g * 1.6 and pixel.r > pixel.b * 1.6:
				red += 1
	return yellow >= 8 and red < 8

func _capture_rect(lines: Array, suffix: String) -> Rect2i:
	var prefix := "raider-healthbar-window-capture: " + suffix
	for line in lines:
		for value in str(line).split("\n"):
			var marker := value.find(prefix)
			if marker < 0:
				continue
			var fields := value.substr(marker + prefix.length()).strip_edges().split(",")
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
