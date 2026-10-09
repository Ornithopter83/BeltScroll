extends SceneTree

const SOURCE_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v2_candidate_1254x1254.png"
const ALTERNATE_SOURCE_PATH := "res://assets/art/player/elven_fighter_turn_pivot_v2_candidate_1254x1254.png"
const SAFE_PATH := "res://assets/art/player/elven_fighter_turn_pivot_v2_safe_candidate_1254x1254.png"
const COMPARISON_PATH := "res://assets/art/review/player_turn_pivot_v2_comparison.png"
const GATE_PATH := "res://docs/review/player_turn_pivot_v2_gate.md"
const CANVAS := Vector2i(1254, 1254)
const MIN_MARGIN := 90

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var has_source := FileAccess.file_exists(SOURCE_PATH) or FileAccess.file_exists(ALTERNATE_SOURCE_PATH)
	var has_candidate := FileAccess.file_exists(SAFE_PATH)
	_check(not has_candidate or has_source, "No safe candidate is left when its v2 source is unavailable")
	if has_source and has_candidate:
		var safe := Image.new()
		_check(safe.load(ProjectSettings.globalize_path(SAFE_PATH)) == OK, "Safe candidate PNG decodes")
		if not safe.is_empty():
			_check(safe.get_size() == CANVAS, "Safe candidate is 1254x1254")
			_check(safe.get_format() == Image.FORMAT_RGBA8, "Safe candidate is RGBA8")
			var bounds := safe.get_used_rect()
			var margins := [bounds.position.x, bounds.position.y, CANVAS.x - bounds.end.x, CANVAS.y - bounds.end.y]
			_check(bounds.size.x > 0 and margins.min() >= MIN_MARGIN, "Safe candidate has at least 90 transparent pixels on every side")
			_check(_isolated_alpha_count(safe) == 0, "Safe candidate has no isolated alpha pixels")
	else:
		_check(not has_candidate, "Unavailable v2 source leaves candidate pending")
	var comparison := Image.new()
	_check(comparison.load(ProjectSettings.globalize_path(COMPARISON_PATH)) == OK, "Comparison PNG decodes")
	if not comparison.is_empty():
		_check(comparison.get_size() == Vector2i(624, 480), "Comparison contains six equal full-canvas 192px cards")
	_check(FileAccess.file_exists(GATE_PATH), "Human review gate exists")
	if failures.is_empty():
		print("player_turn_pivot_v2_safe_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("player_turn_pivot_v2_safe_smoke: " + failure)
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
					var nx := x + dx
					var ny := y + dy
					if (dx != 0 or dy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
