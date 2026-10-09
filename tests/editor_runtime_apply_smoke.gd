extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DATA_LOADER := preload("res://scripts/game/editor_data_loader.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	# Reading twice models a fresh process after the JSON has been saved.
	var first_read: Dictionary = DATA_LOADER.load_data()
	var second_read: Dictionary = DATA_LOADER.load_data()
	_check(first_read.schema_version == 1 and second_read.schema_version == 1, "schema v1 data reloads from disk on each run")
	var player_values := _find(second_read.characters, "Player", "characters")
	var enemy_values := _find(second_read.enemies, "ForestRaider", "enemies")
	var stage_values := _find(second_read.stages, "ForestRuins", "stages")
	_check(player_values.get("walk_speed") == 280.0 and player_values.get("max_health") == 5 and player_values.get("skill_cooldowns") == [1.35, 1.8], "Player ID resolves with its authored baseline values")
	_check(enemy_values.get("attack_damage") == 1 and enemy_values.get("attack_range") == 96.0 and enemy_values.get("recovery_duration") == 0.62, "ForestRaider ID resolves with original attack and cooldown values")
	_check(stage_values.get("left") == 160.0 and stage_values.get("right") == 1760.0 and stage_values.get("spawns", []).size() == 4, "stage boundaries and actor placements parse")

	var invalid_enemy: Dictionary = DATA_LOADER.validate_record({"id": "bad", "attack_range": 0.0, "attack_damage": 1.5, "attack_knockback": 200.0}, "enemies", 0)
	_check(not invalid_enemy.has("attack_range") and not invalid_enemy.has("attack_damage") and invalid_enemy.get("attack_knockback") == 200.0, "invalid fields are diagnosed and dropped individually")
	var invalid_player: Dictionary = DATA_LOADER.validate_record({"id": "bad_player", "skill_cooldowns": [ -1.0, 61.0 ]}, "characters", 0)
	_check(not invalid_player.has("skill_cooldowns"), "out-of-range Player cooldowns are ignored")
	var invalid_stage: Dictionary = DATA_LOADER.validate_record({"id": "bad_stage", "left": 500, "right": 100, "top": 0, "bottom": 100, "spawns": [{"actor_id": "Player", "x": 1, "y": "bad"}]}, "stages", 0)
	_check(not invalid_stage.has("left") and not invalid_stage.has("right") and invalid_stage.spawns.is_empty(), "reversed bounds and malformed placements are rejected")
	var duplicate_data := {"characters": [{"id": "Player"}], "enemies": [{"id": " player "}, {"id": "ForestRaider"}], "stages": [{"id": "ForestRuins"}]}
	DATA_LOADER._validate_unique_ids(duplicate_data)
	_check(duplicate_data.characters.size() == 1 and duplicate_data.enemies.size() == 1, "duplicate IDs are ignored across arrays, case-insensitively")

	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	await process_frame
	var player: Node = main.get_node("YSortActors/Player")
	var raider: Node = main.get_node("YSortActors/ForestRaider1")
	_check(player.get("max_health") == 5 and player.get("health") == 5 and player.get("walk_speed") == 280.0, "runtime applies Player data by ID")
	player.call("_request_skill", 1)
	_check(is_equal_approx(float(player.get("skill_cooldowns")[0]), 1.35), "Player skill cooldown is applied when the skill starts")
	player.call("_cancel_skill")
	player.call("_request_skill", 2)
	_check(is_equal_approx(float(player.get("skill_cooldowns")[1]), 1.8), "second Player skill cooldown is applied independently")
	_check(raider.get("max_health") == 3 and raider.get("health") == 3 and raider.get("attack_damage") == 1, "runtime applies ForestRaider data by ID")
	_check(player.get("arena_bounds") == Rect2(Vector2(237, 722), Vector2(1446, 258)), "stage player boundary preserves the original HUD-safe movement bounds")
	_check(raider.get("arena_bounds") == Rect2(Vector2(160, 100), Vector2(1600, 880)), "stage boundary overrides apply to ForestRaider")
	_check(player.position == Vector2(960, 780) and raider.position == Vector2(690, 762), "stage placements override scene positions")

	# Original player attack payload and hitbox sizing remain the combat regression baseline.
	var player_scene := (load(PLAYER_SCENE) as PackedScene).instantiate()
	_check(player_scene.get("max_health") == 5 and player_scene.get("walk_speed") == 280.0, "Player scene retains its original combat health and speed defaults")
	_check((player_scene.get_node("Hitboxes/Hitbox1/CollisionShape2D").shape as RectangleShape2D).size == Vector2(60, 40), "original stage-one melee range geometry remains unchanged")
	_check((player_scene.get_node("Hitboxes/Hitbox2/CollisionShape2D").shape as RectangleShape2D).size == Vector2(78, 52), "original stage-two melee range geometry remains unchanged")
	_check((player_scene.get_node("Hitboxes/Hitbox3/CollisionShape2D").shape as RectangleShape2D).size == Vector2(100, 66), "original stage-three melee range geometry remains unchanged")
	player_scene.free()
	main.queue_free()
	await process_frame
	_finish()

func _find(records: Array, id: String, kind: String) -> Dictionary:
	for index in range(records.size()):
		var value: Dictionary = DATA_LOADER.validate_record(records[index], kind, index)
		if String(value.get("id", "")) == id:
			return value
	return {}

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("editor_runtime_apply_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("editor_runtime_apply_smoke: " + failure)
		quit(1)
