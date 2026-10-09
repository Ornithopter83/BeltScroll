extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const HIT := {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main scene with session controller loads")
	if packed == null:
		_finish()
		return

	var victory_session := packed.instantiate()
	var victory_player: Node2D = victory_session.get_node("YSortActors/Player") as Node2D
	var victory_dummy: Node2D = victory_session.get_node("YSortActors/TrainingDummy") as Node2D
	var raider1: Node2D = victory_session.get_node("YSortActors/ForestRaider1") as Node2D
	var raider2: Node2D = victory_session.get_node("YSortActors/ForestRaider2") as Node2D
	var raider3: Node2D = victory_session.get_node("YSortActors/ForestRaider3") as Node2D
	_check(victory_player.position == Vector2(960.0, 780.0) and victory_dummy.position == Vector2(1220.0, 780.0), "player and training dummy preserve their 260-unit combat spacing in the HUD-safe lane")
	_check(victory_player.get("arena_bounds") == Rect2(Vector2(237, 722), Vector2(1446, 258)), "player combat bounds use the HUD-safe visible band")
	_check(raider1.position == Vector2(690.0, 762.0) and raider2.position == Vector2(1270.0, 900.0) and raider3.position == Vector2(1450.0, 820.0), "raiders start in visible Y-sort lanes inside the combat arena")
	root.add_child(victory_session)
	current_scene = victory_session
	await process_frame
	var escape := InputEventKey.new()
	escape.physical_keycode = KEY_ESCAPE
	escape.pressed = true
	victory_session.call("_unhandled_input", escape)
	_check(paused and victory_session.get("pause_overlay").visible, "ESC pauses the tree and shows the pause overlay")
	escape.pressed = false
	victory_session.call("_unhandled_input", escape)
	_check(paused, "key release does not resume the session")
	escape.pressed = true
	victory_session.call("_unhandled_input", escape)
	_check(not paused and not victory_session.get("pause_overlay").visible, "ESC resumes the session")
	var help_key := InputEventKey.new()
	help_key.physical_keycode = KEY_H
	help_key.pressed = true
	victory_session.call("_unhandled_input", help_key)
	_check(victory_session.get("help_panel").visible, "H shows the compact controls help")
	var help_panel := victory_session.get("help_panel") as PanelContainer
	var help_label := help_panel.get_child(0) as Label if help_panel != null and help_panel.get_child_count() > 0 else null
	_check(help_label != null and help_label.text.contains("WASD") and help_label.text.contains("Num1~Num9") and help_label.text.contains("예약") and not help_label.text.contains("앉"), "in-game help matches WASD and reserved Num1~Num9 controls without a stale sitting entry")
	victory_session.call("_unhandled_input", help_key)
	_check(not victory_session.get("help_panel").visible, "H hides the controls help")
	var raiders: Array = victory_session.get("_raiders")
	_check(raiders.size() == 3, "session tracks all three ForestRaiders")
	var victory_impact: Node2D = (load("res://scenes/vfx/combat_impact.tscn") as PackedScene).instantiate()
	victory_session.get_node("YSortActors/ForestRaider1").add_child(victory_impact)
	var victory_hitbox := victory_player.get_node("Hitboxes/Hitbox2") as Area2D
	victory_player.call("_begin_attack", 2)
	victory_hitbox.monitoring = true
	Engine.time_scale = 0.5
	victory_player.call("_trigger_hit_stop", 0.1)
	var victory_raider_area := raiders[0].get_node("AttackArea") as Area2D
	victory_raider_area.monitoring = true
	for raider in raiders:
		raider.set("health", 0)
	await process_frame
	_check(victory_session.get("result_state") == 2, "all three defeated raiders produce VICTORY")
	_check(victory_session.get("result_label").text == "VICTORY" and victory_session.get("result_overlay").visible, "victory is shown on its own CanvasLayer")
	_check(not victory_hitbox.monitoring and not (raiders[0].get_node("AttackArea") as Area2D).monitoring, "victory cancels lingering Player and Raider hitboxes")
	_check(is_equal_approx(Engine.time_scale, 1.0), "victory restores normal engine time scale immediately")
	_check(not is_instance_valid(victory_impact), "session end immediately clears active combat impact effects")
	await create_timer(0.15).timeout
	_check(is_equal_approx(Engine.time_scale, 1.0), "pending hit-stop timer cannot restore a stale time scale")
	victory_session.call("_finish_session", 1)
	_check(victory_session.get("result_state") == 2 and victory_session.get("result_label").text == "VICTORY", "duplicate end checks do not replace the first result")
	_check(victory_session.get_node_or_null("CombatHUD") != null, "session result remains separate from CombatHUD")
	victory_session.queue_free()
	await process_frame

	var defeat_session := packed.instantiate()
	root.add_child(defeat_session)
	current_scene = defeat_session
	await process_frame
	var player: Node = defeat_session.get_node("YSortActors/Player")
	player.receive_hit(HIT)
	await process_frame
	_check(defeat_session.get("result_state") == 1, "Player KO produces DEFEAT")
	_check(defeat_session.get("result_label").text == "DEFEAT" and defeat_session.get("result_overlay").visible, "defeat result is displayed")
	_check(not (defeat_session.get_node("YSortActors/ForestRaider1/AttackArea") as Area2D).monitoring, "defeat cancels lingering Raider attack hitboxes")
	defeat_session.queue_free()
	await process_frame

	var restart_session := packed.instantiate()
	root.add_child(restart_session)
	current_scene = restart_session
	await process_frame
	player = restart_session.get_node("YSortActors/Player")
	raiders = restart_session.get("_raiders")
	player.receive_hit({"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	player.call("_begin_attack", 2)
	player.get_node("Camera2D").offset = Vector2(12.0, -8.0)
	raiders[0].set("attack_phase", "windup")
	raiders[0].set("hitstun_remaining", 0.25)
	restart_session.call("_finish_session", 1)
	Engine.time_scale = 0.08
	var previous_id := restart_session.get_instance_id()
	var restart_key := InputEventKey.new()
	restart_key.physical_keycode = KEY_R
	restart_key.pressed = true
	restart_session.call("_unhandled_input", restart_key)
	await process_frame
	await process_frame
	var reloaded := current_scene
	_check(is_instance_valid(reloaded) and reloaded.get_instance_id() != previous_id, "R restart reloads a fresh main scene")
	if is_instance_valid(reloaded):
		player = reloaded.get_node("YSortActors/Player")
		raiders = reloaded.get("_raiders")
		_check(player.get("health") == player.get("max_health"), "restart restores Player health")
		_check(player.get("attack_phase") == "idle" and player.get("attack_stage") == 0, "restart clears combo state")
		_check(player.get_node("Camera2D").offset == Vector2.ZERO, "restart resets camera offset")
		_check(is_equal_approx(Engine.time_scale, 1.0), "restart restores normal engine time scale")
		_check(raiders.size() == 3 and raiders[0].get("health") == raiders[0].get("max_health"), "restart restores raider health")
	_check(raiders[0].get("attack_phase") == "idle" and is_zero_approx(float(raiders[0].get("hitstun_remaining"))), "restart restores raider AI state")
	_check(reloaded.get_node("CombatHUD") != null and reloaded.get_node("CombatHUD").visible, "restart restores the CombatHUD")
	_check(reloaded.get("result_state") == 0 and not reloaded.get("result_overlay").visible, "restart hides the result overlay")
	_finish()

func _finish() -> void:
	if failures.is_empty():
		print("game_session_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("game_session_smoke: " + failure)
		push_error("game_session_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
