extends SceneTree
"""Guards stable editor spawn identity independently from wave ordering."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const DATA_LOADER := preload("res://scripts/game/editor_data_loader.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var saved := DATA_LOADER.load_data()
	var stage_values: Dictionary = DATA_LOADER.find_record(saved.get("stages", []), "ForestRuins")
	var spawn_data: Array = stage_values.get("spawns", [])
	_check(_spawn_position(spawn_data, "ForestRaider") == Vector2(1480, 780), "saved ForestRaider spawn remains the first-section baseline")
	_check(_spawn_position(spawn_data, "ForestRaider2") == Vector2(3360, 780), "saved ForestRaider2 spawn remains the second-section baseline")
	_check(_spawn_position(spawn_data, "ForestRaider3") == Vector2(5160, 780), "saved ForestRaider3 spawn remains the third-section baseline")

	for run_index in range(2):
		var game := (load(MAIN_SCENE) as PackedScene).instantiate()
		root.add_child(game)
		current_scene = game
		await process_frame
		var raider1 := game.get_node("YSortActors/ForestRaider1") as Node2D
		var raider2 := game.get_node("YSortActors/ForestRaider2") as Node2D
		var raider3 := game.get_node("YSortActors/ForestRaider3") as Node2D
		# Reverse discovery order to reproduce a group-order mismatch.
		game.set("_raiders", [raider3, raider2, raider1])
		game.call("_apply_spawns", stage_values)
		_check(raider1.global_position == Vector2(1480, 780) and raider2.global_position == Vector2(3360, 780) and raider3.global_position == Vector2(5160, 780), "run %d: shuffled Raider array still applies IDs by actual scene node name" % (run_index + 1))
		game.call("_initialize_raider_waves")
		var waves: Array = game.get("_wave_order")
		_check(waves == [raider1, raider2, raider3], "run %d: wave order is sorted separately by applied section position" % (run_index + 1))
		_check(raider1.visible and bool(raider1.get("combat_active")) and not raider2.visible and not raider3.visible, "run %d: only section one activates initially" % (run_index + 1))
		var placed_raider1 := raider1.global_position
		await physics_frame
		await physics_frame
		var first_raider_physics_delta := raider1.global_position - placed_raider1
		_check(first_raider_physics_delta.x < -0.1 and absf(first_raider_physics_delta.x) < 8.0 and absf(first_raider_physics_delta.y) < 0.1, "run %d: the active Raider moves only after spawn application, via its normal physics step (delta=%s)" % [run_index + 1, first_raider_physics_delta])
		_check(raider2.global_position == Vector2(3360, 780) and raider3.global_position == Vector2(5160, 780), "run %d: inactive section spawns stay fixed while section one AI advances" % (run_index + 1))
		raider1.set("health", 0)
		game.call("_update_raider_waves")
		_check(raider2.visible and bool(raider2.get("combat_active")) and not raider3.visible, "run %d: clearing section one activates section two" % (run_index + 1))
		raider2.set("health", 0)
		game.call("_update_raider_waves")
		_check(raider3.visible and bool(raider3.get("combat_active")), "run %d: clearing section two activates section three" % (run_index + 1))
		game.queue_free()
		await process_frame

	if failures.is_empty():
		print("m6o_editor_spawn_order_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("m6o_editor_spawn_order_smoke: " + failure)
		quit(1)

func _spawn_position(spawns: Array, actor_id: String) -> Vector2:
	for spawn in spawns:
		if String(spawn.get("actor_id", "")) == actor_id:
			return Vector2(float(spawn.get("x", 0.0)), float(spawn.get("y", 0.0)))
	return Vector2.INF

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
