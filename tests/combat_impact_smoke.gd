extends SceneTree

const IMPACT_SCENE := "res://scenes/vfx/combat_impact.tscn"

class ImpactHost:
	extends Node2D
	var health := 1
	var is_ko := false

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var user_arguments := OS.get_cmdline_user_args()
	if user_arguments.size() == 2 and user_arguments[0] == "--window-compare":
		await _capture_window_comparison(user_arguments[1])
		return
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
		impact.configure(stage, directions[stage], 0, 0.14 + float(stage) * 0.055)
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
	_check(effects[0].get("impact_color") != effects[1].get("impact_color") and effects[1].get("impact_color") != effects[2].get("impact_color"), "combo stages use distinct impact colors")
	_check(effects[0].get("shard_count") < effects[1].get("shard_count") and effects[1].get("shard_count") < effects[2].get("shard_count"), "combo finishers emit progressively more directional shards")
	_check(float(effects[0].get("lifetime")) <= 0.105 and float(effects[2].get("lifetime")) <= 0.19, "ordinary hit stays brief while the finisher concentrates inside early hit-stun")
	var skill_impacts: Array[Node2D] = []
	for selected_skill in [1, 2]:
		var skill_impact := packed.instantiate() as Node2D
		root.add_child(skill_impact)
		skill_impact.configure(3 if selected_skill == 1 else 2, Vector2.RIGHT, selected_skill, 0.42 if selected_skill == 1 else 0.32)
		skill_impacts.append(skill_impact)
	_check(skill_impacts[0].get("impact_color") != skill_impacts[1].get("impact_color"), "Num4 and Num5 skills have distinct colors")
	_check(skill_impacts[0].get("arc_width") != skill_impacts[1].get("arc_width") and skill_impacts[0].get("shard_count") != skill_impacts[1].get("shard_count"), "Num4 and Num5 skills differ in arc weight and shard motion")
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
	var host := ImpactHost.new()
	root.add_child(host)
	var ko_impact := packed.instantiate() as Node2D
	host.add_child(ko_impact)
	ko_impact.configure(3, Vector2.LEFT)
	ko_impact.set("lifetime", 5.0)
	host.health = 0
	ko_impact.call("_process", 0.016)
	_check(ko_impact.is_queued_for_deletion(), "impact queues for removal as soon as its hit receiver is KO")
	await process_frame
	_check(not is_instance_valid(ko_impact), "KO impact is freed on the next frame")
	_finish()

func _capture_window_comparison(output_path: String) -> void:
	if DisplayServer.get_name() == "headless":
		push_error("combat_impact_smoke: window comparison requires a windowed renderer")
		quit(1)
		return
	root.size = Vector2i(1920, 1080)
	var game := (load("res://scenes/game/main.tscn") as PackedScene).instantiate() as Node2D
	root.add_child(game)
	await process_frame
	var player := game.get_node("YSortActors/Player") as Node2D
	var first_target := game.get_node("YSortActors/ForestRaider1") as Node2D
	var finisher_target := game.get_node("YSortActors/ForestRaider3") as Node2D
	var impact_scene := load(IMPACT_SCENE) as PackedScene
	var first_hit := impact_scene.instantiate() as Node2D
	first_target.add_child(first_hit)
	first_hit.global_position = player.call("_combat_impact_position", first_target)
	first_hit.configure(1, Vector2.RIGHT, 0, 0.195)
	var finisher := impact_scene.instantiate() as Node2D
	finisher_target.add_child(finisher)
	finisher.global_position = player.call("_combat_impact_position", finisher_target)
	finisher.configure(3, Vector2.RIGHT, 0, 0.305)
	first_hit.set("lifetime", 5.0)
	finisher.set("lifetime", 5.0)
	for _frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.is_empty() or frame.get_size() != Vector2i(1920, 1080):
		push_error("combat_impact_smoke: window comparison did not render a 1920x1080 Window frame")
		quit(1)
		return
	var absolute_path := output_path if output_path.is_absolute_path() else ProjectSettings.globalize_path(output_path)
	var save_error := frame.save_png(absolute_path)
	if save_error != OK:
		push_error("combat_impact_smoke: could not save Window comparison (error %d)" % save_error)
		quit(1)
		return
	print("combat_impact_smoke: saved actual Window comparison with ordinary hit and finisher to %s" % absolute_path)
	quit(0)

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
