extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const DATA_LOADER := preload("res://scripts/game/editor_data_loader.gd")

var failures: Array[String] = []
var passed_checks: Array[String] = []
var evidence: Dictionary = {}
var artifact_dir := ""

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--artifact-dir":
			artifact_dir = args[index + 1]
	if artifact_dir.is_empty():
		artifact_dir = "user://editor_game_bridge_gate"
	DirAccess.make_dir_recursive_absolute(artifact_dir)
	call_deferred("_run")

func _run() -> void:
	var data: Dictionary = DATA_LOADER.load_data()
	var player_data := DATA_LOADER.find_record(data.get("characters", []), "Player")
	var raider_data := DATA_LOADER.find_record(data.get("enemies", []), "ForestRaider")
	var stage_data := DATA_LOADER.find_record(data.get("stages", []), "ForestRuins")
	_check(player_data.get("max_health") == 9 and player_data.get("walk_speed") == 301.0 and player_data.get("attack_damage") == 13, "saved Player record reloads with edited health/speed/damage data")
	_check(raider_data.get("max_health") == 6 and raider_data.get("walk_speed") == 131.0 and raider_data.get("attack_damage") == 4, "saved ForestRaider record reloads with edited health/speed/damage")
	_check(raider_data.get("ai", {}).get("notice_range") == 610.0 and raider_data.get("ai", {}).get("attack_depth_tolerance") == 42.0 and raider_data.get("ai", {}).get("separation_radius") == 126.0 and raider_data.get("ai", {}).get("separation_strength") == 147.0, "saved ForestRaider AI values reload")
	_check(stage_data.get("spawns", []).size() == 4, "ForestRuins placement record reloads")
	paused = true
	var main := (load(MAIN_SCENE) as PackedScene).instantiate()
	root.add_child(main)
	current_scene = main
	var player: Node2D = main.get_node("YSortActors/Player")
	var raider: Node2D = main.get_node("YSortActors/ForestRaider1")
	var raider_two: Node = main.get_node("YSortActors/ForestRaider2")
	_check(player.get("max_health") == 9 and player.get("health") == 9 and player.get("walk_speed") == 301.0 and player.get("attack_damage") == 13, "live Player receives edited health, movement speed, and attack damage after scene creation")
	_check(raider.get("max_health") == 6 and raider.get("health") == 6 and raider.get("walk_speed") == 131.0 and raider.get("attack_damage") == 4, "live ForestRaider receives edited combat and movement values")
	_check(raider.get("notice_range") == 610.0 and raider.get("attack_depth_tolerance") == 42.0 and raider.get("separation_radius") == 126.0 and raider.get("separation_strength") == 147.0, "live ForestRaider receives edited AI values")
	_check(player.global_position == Vector2(946, 792) and raider.global_position == Vector2(710, 772), "live Player and ForestRaider positions use saved ForestRuins placements")
	_check(raider_two.global_position == Vector2(1270, 900), "other stage placements remain intact")
	var damage_probe_health := 40
	raider.set("max_health", damage_probe_health)
	raider.set("health", damage_probe_health)
	var edited_basic_damage := int(player.call("_basic_attack_damage", 1))
	raider.call("receive_hit", {"damage": edited_basic_damage, "direction": Vector2.RIGHT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	var applied_player_damage := damage_probe_health - int(raider.get("health"))
	_check(edited_basic_damage == 13 and applied_player_damage == 13, "edited Player attack damage 13 reaches the real Raider damage receiver")
	var damage_probe_health_after := int(raider.get("health"))
	raider.set("max_health", 6)
	raider.set("health", 6)
	main.get_node("CombatHUD").call("refresh")
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var capture_path := artifact_dir.path_join("game-live-scene.png")
	var image := get_root().get_texture().get_image()
	var capture_error := image.save_png(capture_path)
	_check(capture_error == OK, "live combat scene screenshot saved")
	evidence = {
		"passed": failures.is_empty(),
		"scene": MAIN_SCENE,
		"reloadCount": 1,
		"player": {"max_health": player.get("max_health"), "health": player.get("health"), "walk_speed": player.get("walk_speed"), "attack_damage": player.get("attack_damage"), "attack_damage_record": player_data.get("attack_damage"), "position": _vector(player.global_position)},
		"playerAttackDamageProbe": {"configured": player.get("attack_damage"), "basicStage1Damage": edited_basic_damage, "raiderHealthBefore": damage_probe_health, "raiderHealthAfter": damage_probe_health_after, "damageApplied": applied_player_damage},
		"forestRaider": {"max_health": raider.get("max_health"), "health": raider.get("health"), "walk_speed": raider.get("walk_speed"), "attack_damage": raider.get("attack_damage"), "ai": raider_data.get("ai"), "notice_range_applied": raider.get("notice_range"), "attack_depth_tolerance_applied": raider.get("attack_depth_tolerance"), "separation_radius_applied": raider.get("separation_radius"), "separation_strength_applied": raider.get("separation_strength"), "position": _vector(raider.global_position)},
		"forestRuins": {"id": stage_data.get("id"), "spawns": stage_data.get("spawns", [])},
		"screenshot": capture_path,
		"checks": passed_checks
	}
	_write_report()
	main.queue_free()
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _vector(value: Vector2) -> Dictionary:
	return {"x": value.x, "y": value.y}

func _check(condition: bool, message: String) -> void:
	if condition:
		passed_checks.append(message)
		print("PASS: " + message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func _write_report() -> void:
	evidence["passed"] = failures.is_empty()
	evidence["failures"] = failures
	evidence["checks"] = passed_checks
	var path := artifact_dir.path_join("game-application.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(evidence, "\t") + "\n")
		file.close()
	else:
		push_error("Could not write application report: " + path)
