extends SceneTree

const CAPTURE_TOOL := "res://tools/capture_combat_live_session.gd"
const CAPTURE_PATH := "res://assets/art/review/combat_live_session_window.png"
const SUCCESS_MARKER := "combat_live_session_window_smoke: all checks passed"
const EXPECTED_SIZE := Vector2i(1920, 1080)

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "smoke requires a Window Viewport")
	var executable := OS.get_executable_path()
	var project_path := ProjectSettings.globalize_path("res://")
	var output: Array[String] = []
	var status := OS.execute(executable, ["--path", project_path, "--script", CAPTURE_TOOL], output, true)
	_check(status == 0, "live combat capture process exits successfully")
	_check(_contains(output, SUCCESS_MARKER), "capture reports all real combat checks passed")
	_check(_contains(output, "synthetic right action advances live physics"), "capture records real rightward movement")
	_check(_contains(output, "synthetic left action reverses live movement"), "capture records direction reversal")
	_check(_contains(output, "all three attack_hit signals came from live active hitboxes"), "capture confirms real hit signals")
	_check(_contains(output, "hit-stop was observed during all three real hit events"), "capture observes hit-stop")
	_check(_contains(output, "combat phase physics="), "capture records attack phases by physics frame")
	_check(_contains(output, "attack buffer physics="), "capture records buffered input by physics frame")
	for stage in range(1, 4):
		_check(_contains(output, "attack %d emits its actual hit signal" % stage), "attack %d emits its real hit signal" % stage)
		_check(_contains(output, "attack %d reduces real Raider health" % stage), "attack %d applies real damage" % stage)
	_check(_count_matches(output, "contains a rendered scene and visible combat actors") == 9, "all nine chronological frames, including combo completion, capture the live combat scene")
	if status != 0:
		for line in output:
			push_error(str(line))
	var image := Image.new()
	var image_error := image.load(CAPTURE_PATH)
	_check(image_error == OK, "live session timeline PNG is created")
	if image_error == OK:
		_check(image.get_size() == EXPECTED_SIZE, "live session timeline PNG is 1920x1080")
		_check(_image_contains_visible_pixels(image), "timeline comparison board shows the final combo-complete frame")
	if _failures.is_empty():
		print(SUCCESS_MARKER)
		quit(0)
		return
	for failure in _failures:
		push_error("combat_live_session_window_smoke: " + failure)
	push_error("combat_live_session_window_smoke: %d check(s) failed" % _failures.size())
	quit(1)

func _contains(output: Array, fragment: String) -> bool:
	for line in output:
		if str(line).contains(fragment):
			return true
	return false

func _count_matches(output: Array, fragment: String) -> int:
	var combined := "\n".join(output)
	return combined.split(fragment, false).size() - 1

func _image_contains_visible_pixels(image: Image) -> bool:
	# The ninth frame is centered in the third row of the 3x3 board. Sample its
	# center area so the capture cannot pass with a truncated 8-frame layout.
	var rect := Rect2i(1330, 790, 465, 255)
	if not Rect2i(Vector2i.ZERO, image.get_size()).encloses(rect):
		return false
	var varied_pixels := 0
	var first := image.get_pixel(rect.position.x, rect.position.y)
	for y in range(rect.position.y, rect.end.y, 4):
		for x in range(rect.position.x, rect.end.x, 4):
			var pixel := image.get_pixel(x, y)
			var color_delta := absf(pixel.r - first.r) + absf(pixel.g - first.g) + absf(pixel.b - first.b)
			if color_delta > 0.12:
				varied_pixels += 1
	return varied_pixels > 100

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
