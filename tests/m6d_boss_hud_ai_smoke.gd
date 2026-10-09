extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const BOSS_SCENE := "res://scenes/enemies/ruins_warden_boss.tscn"
const HUD_SCENE := "res://scenes/ui/combat_hud.tscn"
const HIT := {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 3}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var player_packed := load(PLAYER_SCENE) as PackedScene
	var boss_packed := load(BOSS_SCENE) as PackedScene
	var hud_packed := load(HUD_SCENE) as PackedScene
	_check(player_packed != null and boss_packed != null and hud_packed != null, "production Player, boss, and CombatHUD scenes load")
	if player_packed == null or boss_packed == null or hud_packed == null:
		_finish()
		return
	var stage := Node2D.new()
	stage.name = "BossRuntimeSmokeStage"
	root.add_child(stage)
	current_scene = stage
	var player := player_packed.instantiate() as CharacterBody2D
	player.name = "Player"
	player.global_position = Vector2(5000.0, 780.0)
	player.set("arena_bounds", Rect2(160.0, 100.0, 5440.0, 880.0))
	stage.add_child(player)
	var boss := boss_packed.instantiate() as CharacterBody2D
	boss.global_position = Vector2(5440.0, 780.0)
	stage.add_child(boss)
	var hud := hud_packed.instantiate()
	stage.add_child(hud)
	await process_frame
	var health_bar := boss.get("health_bar") as ProgressBar
	_check(health_bar != null and boss.get_node("HealthBar") == health_bar, "legacy health_bar reference still resolves to the scene HealthBar node")
	_check(not health_bar.visible and not health_bar.is_visible_in_tree(), "boss overhead HealthBar stays hidden")
	_check(not boss.get("combat_active") and not boss.is_physics_processing() and boss.collision_layer == 0 and boss.collision_mask == 0, "inactive boss does not run AI or collide")
	_check(not (boss.get_node("ReceiveArea") as Area2D).monitorable, "inactive boss cannot receive combat hits")
	var inactive_position := boss.global_position
	player.global_position = inactive_position + Vector2(-420.0, 0.0)
	await _physics_frames(12)
	_check(boss.global_position == inactive_position, "inactive boss ignores a nearby real Player")

	boss.call("set_combat_active", true)
	_check(bool(boss.get("combat_active")) and boss.is_physics_processing(), "combat activation enables boss AI")
	hud.call("refresh")
	var boss_indicators: Dictionary = hud.get("_boss_indicators")
	_check(boss_indicators.size() == 1, "CombatHUD creates a single boss health indicator")
	if boss_indicators.size() == 1:
		var indicator: Dictionary = boss_indicators.values()[0]
		_check(indicator.root.visible and indicator.root.position == Vector2(57.0, 190.0), "boss health appears in the upper-left CombatHUD")
	_check(not health_bar.visible and health_bar.value == boss.get("health"), "hidden legacy bar remains synchronized without being displayed")

	player.global_position = boss.global_position + Vector2(-440.0, 0.0)
	var distance_before_tracking := boss.global_position.distance_to(player.global_position)
	await _physics_frames(18)
	_check(boss.call("_find_player") == player, "boss AI resolves the real, ungrouped stage Player")
	_check(boss.global_position.distance_to(player.global_position) < distance_before_tracking, "boss AI moves toward and tracks the real Player")

	player.global_position = boss.global_position + Vector2(-100.0, 0.0)
	await _physics_frames(2)
	_check(boss.get("attack_kind") == "slash" and boss.get("attack_phase") == "windup" and boss.get("attack_telegraph").visible, "AI starts slash with a visible windup telegraph at close range")
	var player_health_before_slash := int(player.get("health"))
	await _physics_frames(70)
	_check(int(player.get("health")) < player_health_before_slash, "slash active phase hits the real Player")

	player.global_position = boss.global_position + Vector2(-180.0, 0.0)
	var slam_telegraph_seen := false
	for _frame in range(140):
		await physics_frame
		if boss.get("attack_kind") == "slam" and boss.get("attack_phase") == "windup" and boss.get("slam_telegraph").visible:
			slam_telegraph_seen = true
			break
	_check(slam_telegraph_seen, "AI selects a distinct telegraphed slam at medium range")
	player.global_position = boss.global_position + Vector2(-100.0, 0.0)
	var player_health_before_slam := int(player.get("health"))
	await _physics_frames(90)
	_check(int(player.get("health")) < player_health_before_slam, "slam active phase hits the real Player")
	boss.call("receive_hit", {"damage": 2, "direction": Vector2.RIGHT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 2})
	_check(not health_bar.visible and is_equal_approx(health_bar.value, float(boss.get("health"))), "boss damage updates the preserved hidden health_bar reference")

	var boss_ko_events := [0]
	boss.boss_ko.connect(func() -> void: boss_ko_events[0] += 1)
	boss.call("receive_hit", HIT)
	await process_frame
	hud.call("refresh")
	_check(int(boss.get("health")) == 0 and not boss.get("combat_active"), "lethal hit transitions the boss to KO")
	_check(boss.collision_layer == 0 and boss.collision_mask == 0 and not (boss.get_node("ReceiveArea") as Area2D).monitorable, "KO boss disables collision and hit reception")
	_check(boss_ko_events[0] == 1, "boss KO signal emits exactly once")
	_check(not health_bar.visible and hud.get("_boss_indicators").size() == 1, "KO status remains represented by CombatHUD only")
	_finish()

func _physics_frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("m6d_boss_hud_ai_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("m6d_boss_hud_ai_smoke: " + failure)
		quit(1)
