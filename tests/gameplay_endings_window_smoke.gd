extends SceneTree

const CAPTURE_TOOL := "res://tools/capture_gameplay_endings.gd"
const CAPTURE_PATH := "res://assets/art/review/gameplay_endings_window.png"
const SUCCESS_MARKER := "gameplay_endings_window_smoke: all checks passed"
const EXPECTED_SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("gameplay_endings_window_smoke: Window renderer is required")
		quit(1)
		return
	var script := load(CAPTURE_TOOL)
	if script == null:
		push_error("gameplay_endings_window_smoke: could not load ending capture gate")
		quit(1)
		return
	var gate = script.new()
	var result: Dictionary = await gate.capture(self)
	if not bool(result.get("ok", false)):
		push_error("gameplay_endings_window_smoke: gate failed with %s: %s" % [result.get("code", "GEW-000"), result.get("message", "unknown error")])
		for failure in result.get("failures", []):
			push_error("gameplay_endings_window_smoke: " + str(failure))
		quit(1)
		return
	var image := Image.new()
	var image_error := image.load(CAPTURE_PATH)
	if image_error != OK or image.get_size() != EXPECTED_SIZE:
		push_error("gameplay_endings_window_smoke: final comparison PNG missing or not 1920x1080")
		quit(1)
		return
	if paused or not is_equal_approx(Engine.time_scale, 1.0):
		push_error("gameplay_endings_window_smoke: capture left global pause or time scale dirty")
		quit(1)
		return
	print("PASS: actual Window frames captured after frame_post_draw at 1920x1080")
	print("PASS: VICTORY and DEFEAT are evaluated after existing receive_hit calls")
	print("PASS: result panel stays below the HUD and actor art in the lower safe band with under 2% actor-bounds overlap")
	print("PASS: retry restores pause, time scale, and prior CombatAudio")
	print("PASS: keyboard and synthetic gamepad focus reach result/pause actions")
	print("PASS: result controls and actor art fit; pause controls render over the live actor scene")
	print("PASS: PAUSE returns through the title scene and restores global state")
	print(SUCCESS_MARKER)
	quit(0)
