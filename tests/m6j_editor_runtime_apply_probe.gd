extends SceneTree
"""Checks saved editor overrides on actual Player/Raider scene instances."""

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 3:
		_failures.append("scene path and expected Player/Raider max health values are required")
		_finish()
		return
	var scene_path := String(args[0])
	var expected_player_health := int(args[1])
	var expected_raider_health := int(args[2])
	var packed_scene := load(scene_path) as PackedScene
	if packed_scene == null:
		_failures.append("could not load target scene: " + scene_path)
		_finish()
		return
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	await process_frame
	var player := scene.get_node_or_null("YSortActors/Player") as Node
	var raider_path := "YSortActors/ForestRaider" if scene_path.contains("m6i_combat_test_arena") else "YSortActors/ForestRaider1"
	var raider := scene.get_node_or_null(raider_path) as Node
	_check(player != null, "Player instance exists in target scene")
	_check(raider != null, "ForestRaider instance exists in target scene")
	if player != null:
		_check(int(player.get("max_health")) == expected_player_health, "saved Player.max_health applied to the live instance")
		_check(int(player.get("health")) == expected_player_health, "saved Player health initialized from the live max health")
	if raider != null:
		_check(int(raider.get("max_health")) == expected_raider_health, "saved ForestRaider.max_health applied to the live instance")
		_check(int(raider.get("health")) == expected_raider_health, "saved ForestRaider health initialized from the live max health")
	scene.queue_free()
	await process_frame
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6j_editor_runtime_apply_probe: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("m6j_editor_runtime_apply_probe: " + failure)
	quit(1)
