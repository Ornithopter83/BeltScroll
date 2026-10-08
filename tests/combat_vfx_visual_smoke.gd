extends SceneTree

const IMPACT_SCRIPT := preload("res://scripts/vfx/combat_impact.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var directions := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT, Vector2(1.0, -1.0).normalized()]
	var direction_checks_pass := true
	for direction in directions:
		var impact := IMPACT_SCRIPT.new() as Node2D
		impact.configure(1, direction)
		var streak: Vector2 = impact.streak_direction_local()
		var perpendicular: Vector2 = impact.streak_perpendicular_local()
		direction_checks_pass = direction_checks_pass and absf(streak.length() - 1.0) < 0.001
		direction_checks_pass = direction_checks_pass and absf(perpendicular.length() - 1.0) < 0.001
		direction_checks_pass = direction_checks_pass and absf(streak.dot(perpendicular)) < 0.001
		direction_checks_pass = direction_checks_pass and streak.rotated(impact.rotation).distance_to(direction) < 0.001
		impact.free()
	_check(direction_checks_pass, "all attack directions rotate a unit streak and its true perpendicular")

	var stages: Array[Node2D] = []
	for stage in range(1, 4):
		var impact := IMPACT_SCRIPT.new() as Node2D
		impact.configure(stage, Vector2.RIGHT)
		stages.append(impact)
	var silhouettes_distinct := true
	for index in range(1, stages.size()):
		silhouettes_distinct = silhouettes_distinct and stages[index].get("arc_radius") > stages[index - 1].get("arc_radius")
		silhouettes_distinct = silhouettes_distinct and stages[index].get("arc_width") > stages[index - 1].get("arc_width")
		silhouettes_distinct = silhouettes_distinct and stages[index].get("streak_length") > stages[index - 1].get("streak_length")
	_check(silhouettes_distinct, "stages 1 to 3 have progressively larger arc and streak silhouettes")

	var size_capped := true
	var opacity_fades := true
	var lifetime_increases := true
	for impact in stages:
		var lifetime := float(impact.get("lifetime"))
		var early: Dictionary = impact.visual_state_at(0.0)
		var middle: Dictionary = impact.visual_state_at(0.5)
		var end_state: Dictionary = impact.visual_state_at(1.0)
		size_capped = size_capped and float(early["radius"]) <= 40.0 and float(middle["radius"]) <= 40.0 and float(end_state["radius"]) <= 40.0
		opacity_fades = opacity_fades and float(early["arc_alpha"]) > float(middle["arc_alpha"]) and float(middle["arc_alpha"]) > float(end_state["arc_alpha"])
		lifetime_increases = lifetime_increases and lifetime > 0.0
	_check(size_capped, "animated arc radius remains under the 40px cap")
	_check(opacity_fades, "arc opacity fades monotonically to zero over its lifetime")
	_check(lifetime_increases, "each stage has a positive real-time lifetime")
	_check(float(stages[0].get("lifetime")) < float(stages[1].get("lifetime")) and float(stages[1].get("lifetime")) < float(stages[2].get("lifetime")), "later stages remain visible for progressively longer durations")
	for impact in stages:
		impact.free()

	if failures.is_empty():
		print("combat_vfx_visual_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("combat_vfx_visual_smoke: " + failure)
		push_error("combat_vfx_visual_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
