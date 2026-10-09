extends SceneTree

const CAPTURE_PATH := "res://assets/art/review/player_turn_candidate_window.png"
const TURN_SCRIPT_PATH := "res://scripts/player/player_visual_animator.gd"
const TURN_ART_CANDIDATE_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	var failures: Array[String] = []
	var script_text := FileAccess.get_file_as_string(TURN_SCRIPT_PATH)
	_check("const TURN_DURATION := 0.13" in script_text, "uses the production 0.13 second turn clock", failures)
	_check("await RenderingServer.frame_post_draw" in FileAccess.get_file_as_string("res://tools/capture_player_turn_candidate_window.gd"), "waits for frame_post_draw before each sample", failures)
	_check(FileAccess.file_exists(TURN_ART_CANDIDATE_PATH), "turn art candidate source is actually present", failures)
	_check(not FileAccess.get_file_as_string("res://tools/capture_player_turn_candidate_window.gd").contains("turn_rear_mid_v1_safe_candidate"), "does not depend on the safe-derived turn image", failures)
	_print_art_bounds("elven_fighter_reference_v8_clean_candidate_1254x1254.png")
	_print_art_bounds("elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png")
	_check(FileAccess.file_exists(CAPTURE_PATH), "turn candidate review PNG exists", failures)
	if FileAccess.file_exists(CAPTURE_PATH):
		var image := Image.new()
		var error := image.load(ProjectSettings.globalize_path(CAPTURE_PATH))
		_check(error == OK, "PNG loads", failures)
		if error == OK:
			_check(image.get_size() == EXPECTED_SIZE, "montage is 1920x1080", failures)
			_check(_has_rendered_content(image), "montage contains rendered scene variation", failures)
	if failures.is_empty():
		print("player_turn_candidate_window_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("player_turn_candidate_window_smoke: " + failure)
	quit(1)

func _has_rendered_content(image: Image) -> bool:
	var baseline := image.get_pixel(0, 0)
	var different := 0
	for y in range(35, image.get_height(), 45):
		for x in range(35, image.get_width(), 45):
			if image.get_pixel(x, y).is_equal_approx(baseline) == false:
				different += 1
	return different > 80

func _print_art_bounds(file_name: String) -> void:
	var image := Image.new()
	var path := ProjectSettings.globalize_path("res://assets/art/player/" + file_name)
	if image.load(path) == OK:
		print("ART_BOUNDS: %s size=%s alpha_bounds=%s" % [file_name, str(image.get_size()), str(image.get_used_rect())])

func _check(condition: bool, description: String, failures: Array[String]) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
