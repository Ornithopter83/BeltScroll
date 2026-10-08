extends SceneTree

const IMPACT_SCENE := "res://scenes/vfx/combat_impact.tscn"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(IMPACT_SCENE) as PackedScene
	_check(packed != null, "impact scene loads independently")
	if packed == null:
		_finish()
		return
	var effects: Array[Node2D] = []
	var directions := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var direction_rotation_ok := true
	for stage in range(1, 4):
		var impact := packed.instantiate() as Node2D
		root.add_child(impact)
		impact.configure(stage, directions[stage])
		var local_streak: Vector2 = impact.call("streak_direction_local")
		var local_perpendicular: Vector2 = impact.call("streak_perpendicular_local")
		direction_rotation_ok = direction_rotation_ok and absf(local_streak.dot(local_perpendicular)) < 0.001
		direction_rotation_ok = direction_rotation_ok and local_streak.rotated(impact.rotation).distance_to(directions[stage]) < 0.001
		effects.append(impact)
	_check(direction_rotation_ok, "streak axes stay perpendicular and rotate to the configured attack direction")
	_check(effects[0].get("attack_stage") == 1 and effects[1].get("attack_stage") == 2 and effects[2].get("attack_stage") == 3, "each combo stage configures a distinct impact")
	_check(effects[0].get("arc_radius") < effects[1].get("arc_radius") and effects[1].get("arc_radius") < effects[2].get("arc_radius"), "later stages use wider arcs")
	_check(effects[0].get("lifetime") < effects[1].get("lifetime") and effects[1].get("lifetime") < effects[2].get("lifetime"), "later stages have distinct longer lifetimes")
	_check(effects[2].get("streak_length") > effects[0].get("streak_length"), "finisher streak is stronger than the first hit")
	var within_size_cap := true
	for effect in effects:
		within_size_cap = within_size_cap and float(effect.get("arc_radius")) <= 40.0
	_check(within_size_cap, "impact size stays within the screen space cap")
	var saved_scale := Engine.time_scale
	Engine.time_scale = 0.08
	await create_timer(0.30, true, false, true).timeout
	var all_cleaned := true
	for effect in effects:
		all_cleaned = all_cleaned and not is_instance_valid(effect)
	_check(all_cleaned, "effects expire on real time while hit-stop scales gameplay time")
	_check(Engine.time_scale <= 0.08, "real-time impact cleanup does not end or bypass the active hit-stop")
	Engine.time_scale = saved_scale
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("combat_impact_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("combat_impact_smoke: " + failure)
		push_error("combat_impact_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
