extends SceneTree

const SOURCE_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png"
const SAFE_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v1_safe_candidate_1254x1254.png"
const COMPARISON_PATH := "res://assets/art/review/player_turn_mid_comparison.png"
const CANVAS := Vector2i(1254, 1254)
const MIN_MARGIN := 90

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_exists := FileAccess.file_exists(SOURCE_PATH)
	var safe_exists := FileAccess.file_exists(SAFE_PATH)
	_check(not safe_exists or source_exists, "A safe candidate cannot exist without an authored turn source")
	if source_exists and safe_exists:
		var safe := Image.new()
		_check(safe.load(ProjectSettings.globalize_path(SAFE_PATH)) == OK, "Safe candidate PNG decodes")
		if not safe.is_empty():
			_check(safe.get_size() == CANVAS, "Safe candidate is 1254x1254")
			_check(safe.get_format() == Image.FORMAT_RGBA8, "Safe candidate is RGBA8")
			var bounds := safe.get_used_rect()
			var margins := [bounds.position.x, bounds.position.y, safe.get_width() - bounds.end.x, safe.get_height() - bounds.end.y]
			_check(bounds.size.x > 0 and margins.min() >= MIN_MARGIN, "Safe candidate has at least 90 transparent pixels on all sides")
			_check(_isolated_alpha_count(safe) == 0, "Safe candidate has no isolated alpha pixels")
	else:
		_check(not safe_exists, "Unacquired turn source leaves safe candidate pending")

	var comparison := Image.new()
	_check(comparison.load(ProjectSettings.globalize_path(COMPARISON_PATH)) == OK, "192px comparison image decodes")
	if not comparison.is_empty():
		_check(comparison.get_size() == Vector2i(420, 480), "Comparison uses four equal 192x192 full-canvas cards")
	_check(FileAccess.file_exists("res://docs/review/player_turn_mid_art_gate.md"), "Human review gate records the pending or candidate state")
	if failures.is_empty():
		print("player_turn_mid_safe_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("player_turn_mid_safe_smoke: " + failure)
	quit(1)

func _isolated_alpha_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if dx == 0 and dy == 0:
						continue
					var nx := x + dx
					var ny := y + dy
					if nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
