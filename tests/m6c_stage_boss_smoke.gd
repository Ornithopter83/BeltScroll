extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const HIT := {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 3}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main stage and unique boss scene load")
	if packed == null:
		_finish()
		return
	var game := packed.instantiate()
	root.add_child(game)
	current_scene = game
	await process_frame
	var player := game.get_node("YSortActors/Player") as CharacterBody2D
	var camera := player.get_node("Camera2D") as Camera2D
	var raiders: Array = game.get("_raiders")
	var boss := game.get_node("YSortActors/RuinsWardenBoss")
	_check(raiders.size() == 3, "one Raider guards each of the three sections")
	_check(raiders[0].global_position == Vector2(1480.0, 780.0) and raiders[1].global_position == Vector2(3360.0, 780.0) and raiders[2].global_position == Vector2(5160.0, 780.0), "runtime editor overrides keep one Raider in each section")
	_check(boss.is_in_group("boss_units"), "real Ruins Warden registers in the boss HUD group")
	_check(game.get("_next_raider_wave") == 0 and raiders[0].visible and not raiders[1].visible and not raiders[2].visible, "only the first section Raider is active at start")
	_check(camera.limit_right == 5760 and camera.limit_left == 0, "camera limits span the continuous three-section world")
	var tile1 := game.get_node("StageBackground") as Sprite2D
	var tile2 := game.get_node("StageBackground2") as Sprite2D
	var tile3 := game.get_node("StageBackground3") as Sprite2D
	var tile_width := float(tile1.texture.get_width())
	_check(tile1.texture == tile2.texture and tile2.texture == tile3.texture and is_equal_approx(tile1.global_position.x + tile_width * 0.5, tile2.global_position.x - tile_width * 0.5) and is_equal_approx(tile2.global_position.x + tile_width * 0.5, tile3.global_position.x - tile_width * 0.5) and is_equal_approx(tile3.global_position.x + tile_width * 0.5, float(camera.limit_right)), "background tiles meet edge to edge across the entire camera range")
	player.global_position.x = 2100.0
	game.call("_update_raider_waves")
	_check(player.global_position.x <= 1882.0 and not raiders[1].visible, "uncleared section boundary blocks forward travel")
	raiders[0].call("receive_hit", HIT)
	game.call("_update_raider_waves")
	_check(game.get("_current_section") == 1 and raiders[1].visible, "first Raider KO unlocks section two")
	player.global_position.x = 1300.0
	game.call("_update_raider_waves")
	_check(is_equal_approx(player.global_position.x, 1300.0), "backtracking through a cleared section remains possible")
	raiders[1].call("receive_hit", HIT)
	game.call("_update_raider_waves")
	_check(game.get("_current_section") == 2 and raiders[2].visible, "second Raider KO unlocks section three")
	raiders[2].call("receive_hit", HIT)
	game.call("_update_raider_waves")
	_check(boss.get("combat_active") and boss.visible and int(boss.get("health")) == int(boss.get("max_health")), "third Raider KO releases the full-health Ruins Warden")
	_check(game.get("result_state") == 0, "clearing Raiders alone never grants victory")
	_check(boss.call("_find_player") == player, "boss AI resolves the real Player even when it has no player group membership")
	player.global_position = boss.global_position + Vector2(-200.0, 0.0)
	boss.call("_physics_process", 0.016)
	_check(boss.get("attack_kind") == "slam" and boss.get("slam_telegraph").visible, "boss autonomous AI enters a telegraphed attack against the real Player")
	boss.call("_begin_attack", "slash")
	_check(boss.get("attack_kind") == "slash" and boss.get("attack_telegraph").visible, "boss slash has a visible advance telegraph")
	player.global_position = boss.global_position + Vector2(-80.0, 0.0)
	var player_health_before_boss_hit := int(player.get("health"))
	boss.set("attack_phase", "active")
	(boss.get_node("AttackArea") as Area2D).monitoring = true
	boss.call("_check_attack_targets")
	_check(int(player.get("health")) == player_health_before_boss_hit - int(boss.get("attack_damage")), "boss slash resolves damage against the real Player without group registration")
	boss.call("_begin_attack", "slam")
	_check(boss.get("attack_kind") == "slam" and boss.get("slam_telegraph").visible, "boss ground slam has a distinct wide-area telegraph")
	var health_before := int(boss.get("health"))
	boss.call("receive_hit", {"damage": 2, "direction": Vector2.LEFT, "knockback": 120.0, "hit_stun": 0.1, "attack_stage": 2})
	_check(int(boss.get("health")) == health_before - 2 and boss.get("health_bar").value == boss.get("health"), "boss has separate health, hit reaction, and health bar")
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	game.call("_unhandled_input", escape)
	_check(paused and game.get("pause_overlay").visible, "pause freezes the expanded stage and displays its overlay")
	escape.pressed = false
	game.call("_unhandled_input", escape)
	escape.pressed = true
	game.call("_unhandled_input", escape)
	_check(not paused and not game.get("pause_overlay").visible, "resume restores gameplay")
	boss.call("receive_hit", HIT)
	await process_frame
	_check(game.get("result_state") == 2 and game.get("result_overlay").visible, "only boss KO triggers final victory")
	var old_id := game.get_instance_id()
	game.call("_restart_session")
	await process_frame
	await process_frame
	var restarted := current_scene
	_check(is_instance_valid(restarted) and restarted.get_instance_id() != old_id, "restart creates a fresh three-section run")
	if is_instance_valid(restarted):
		_check(restarted.get("_current_section") == 0 and restarted.get("_next_raider_wave") == 0, "restart returns progression to section one")
		_check(restarted.get_node("YSortActors/RuinsWardenBoss").get("health") == restarted.get_node("YSortActors/RuinsWardenBoss").get("max_health"), "restart restores boss health")
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("m6c_stage_boss_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("m6c_stage_boss_smoke: " + failure)
		quit(1)
