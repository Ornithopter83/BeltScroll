extends SceneTree
"""Checks the review capture artifact without touching production resources."""

const CAPTURE_PATH := "res://assets/art/review/player_turn_pivot_v2_window.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if not FileAccess.file_exists(CAPTURE_PATH):
		_fail("Capture artifact is missing: %s" % CAPTURE_PATH)
		return
	var image := Image.new()
	var error := image.load(ProjectSettings.globalize_path(CAPTURE_PATH))
	if error != OK:
		_fail("Capture PNG could not be decoded: %s" % error_string(error))
		return
	if image.get_size() != EXPECTED_SIZE:
		_fail("Capture size mismatch: expected %s, got %s" % [str(EXPECTED_SIZE), str(image.get_size())])
		return
	var unique_colors := {}
	for y in range(0, image.get_height(), 12):
		for x in range(0, image.get_width(), 12):
			unique_colors[image.get_pixel(x, y).to_html()] = true
	if unique_colors.size() < 24:
		_fail("Capture appears blank or lacks rendered review content (%d sampled colors)." % unique_colors.size())
		return
	print("player-turn-pivot-window-smoke: PASS · %s · %s · sampled_colors=%d" % [CAPTURE_PATH, str(image.get_size()), unique_colors.size()])
	quit(0)

func _fail(message: String) -> void:
	push_error("player_turn_pivot_v2_window_smoke: " + message)
	quit(1)
