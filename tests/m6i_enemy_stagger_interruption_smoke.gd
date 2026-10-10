extends SceneTree

const RAIDER_SCENE := "res://scenes/enemies/forest_raider.tscn"
const BOSS_SCENE := "res://scenes/enemies/ruins_warden_boss.tscn"
const HIT := {"damage": 1, "direction": Vector2.LEFT, "knockback": 360.0, "hit_stun": 0.24, "attack_stage": 2}

class TestPlayer:
	extends CharacterBody2D

	func _init() -> void:
		collision_layer = 1
		collision_mask = 0

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var raider_scene := load(RAIDER_SCENE) as PackedScene
	var boss_scene := load(BOSS_SCENE) as PackedScene
	_check(raider_scene != null and boss_scene != null, "production Raider and Ruins Warden scenes load")
	if raider_scene == null or boss_scene == null:
		_finish()
		return
	var stage := Node2D.new()
	stage.name = "M6iStaggerSmokeStage"
	root.add_child(stage)
	current_scene = stage
	var player := TestPlayer.new()
	player.name = "Player"
	player.global_position = Vector2(1100.0, 650.0)
	stage.add_child(player)
	var raider := raider_scene.instantiate() as CharacterBody2D
	raider.global_position = Vector2(700.0, 650.0)
	stage.add_child(raider)
	var boss := boss_scene.instantiate() as CharacterBody2D
	boss.global_position = Vector2(900.0, 650.0)
	stage.add_child(boss)
	await process_frame
	boss.call("set_combat_active", true)
	var raider_attack: Area2D = raider.get_node("AttackArea")
	var raider_flash: Polygon2D = raider.get_node("VisualRoot/AttackFlash")
	var boss_attack: Area2D = boss.get_node("AttackArea")
	var boss_slash: Polygon2D = boss.get_node("AttackTelegraph")
	var boss_slam: Polygon2D = boss.get_node("SlamTelegraph")

	for phase in ["windup", "active", "recovery"]:
		raider.set("attack_phase", phase)
		raider.set("attack_phase_remaining", 0.5)
		raider_attack.monitoring = phase == "active"
		raider_flash.visible = phase != "recovery"
		raider.call("receive_hit", {"damage": 0, "direction": HIT.direction, "knockback": HIT.knockback, "hit_stun": HIT.hit_stun, "attack_stage": HIT.attack_stage})
		_check(raider.get("attack_phase") == "idle" and float(raider.get("attack_phase_remaining")) == 0.0,
			"Raider hit interrupts %s immediately" % phase)
		_check(not raider_attack.monitoring and not raider_flash.visible,
			"Raider hit disables attack detection and tell from %s" % phase)
		_check(float(raider.get("hitstun_remaining")) > 0.0 and raider.velocity.x < 0.0,
			"Raider hit applies directional knockback and stagger from %s" % phase)
		# Reset stagger between phase cases while preserving the Raider's health.
		raider.set("hitstun_remaining", 0.0)

	# Repeated contact refreshes the lockout and replaces the impact direction.
	raider.call("receive_hit", HIT)
	await _physics_frames(4)
	var raider_stun_before_refresh := float(raider.get("hitstun_remaining"))
	raider.call("receive_hit", {"damage": 0, "direction": Vector2.RIGHT, "knockback": 500.0, "hit_stun": 0.4, "attack_stage": 3})
	_check(float(raider.get("hitstun_remaining")) > raider_stun_before_refresh and raider.velocity.x > 0.0,
		"Raider consecutive hit refreshes stagger and impact direction")
	player.global_position = Vector2(400.0, 650.0)
	var raider_locked_position := raider.global_position
	await _physics_frames(3)
	_check(raider.get("attack_phase") == "idle" and not raider_attack.monitoring,
		"Raider cannot restart an attack during stagger")
	_check(raider.global_position.distance_to(raider_locked_position) < 64.0
		and raider.global_position.x > raider_locked_position.x,
		"Raider stagger movement follows decaying knockback, not player tracking")
	await _physics_frames(30)
	_check(float(raider.get("hitstun_remaining")) == 0.0,
		"Raider stagger expires after the refreshed duration")
	player.global_position = Vector2(1100.0, 650.0)
	var raider_resume_position := raider.global_position
	await _physics_frames(8)
	_check(raider.global_position.x > raider_resume_position.x,
		"Raider resumes pursuit after stagger expires")

	player.global_position = Vector2(1500.0, 650.0)
	for phase in ["windup", "active", "recovery"]:
		boss.set("attack_phase", phase)
		boss.set("attack_phase_remaining", 0.5)
		boss_attack.monitoring = phase == "active"
		boss_slash.visible = phase == "windup"
		boss_slam.visible = phase == "windup"
		boss.call("receive_hit", HIT)
		_check(boss.get("attack_phase") == "idle" and float(boss.get("attack_phase_remaining")) == 0.0,
			"Warden hit interrupts %s immediately" % phase)
		_check(not boss_attack.monitoring and not boss_slash.visible and not boss_slam.visible,
			"Warden hit disables attack detection and both tells from %s" % phase)
		_check(float(boss.get("hitstun_remaining")) > 0.0 and boss.velocity.x < 0.0,
			"Warden hit applies directional knockback and stagger from %s" % phase)
		boss.set("hitstun_remaining", 0.0)

	boss.call("receive_hit", HIT)
	await _physics_frames(4)
	var boss_stun_before_refresh := float(boss.get("hitstun_remaining"))
	boss.call("receive_hit", {"damage": 0, "direction": Vector2.RIGHT, "knockback": 500.0, "hit_stun": 0.4, "attack_stage": 3})
	_check(float(boss.get("hitstun_remaining")) > boss_stun_before_refresh and boss.velocity.x > 0.0,
		"Warden consecutive hit refreshes stagger and impact direction")
	player.global_position = Vector2(500.0, 650.0)
	var boss_locked_position := boss.global_position
	await _physics_frames(3)
	_check(boss.get("attack_phase") == "idle" and not boss_attack.monitoring,
		"Warden cannot restart an attack during stagger")
	_check(boss.global_position.distance_to(boss_locked_position) < 64.0
		and boss.global_position.x > boss_locked_position.x,
		"Warden stagger movement follows decaying knockback, not player tracking")
	await _physics_frames(30)
	_check(float(boss.get("hitstun_remaining")) == 0.0,
		"Warden stagger expires after the refreshed duration")
	player.global_position = Vector2(1500.0, 650.0)
	var boss_resume_position := boss.global_position
	await _physics_frames(8)
	_check(boss.global_position.x > boss_resume_position.x,
		"Warden resumes pursuit after stagger expires")

	var boss_health_bar := boss.get_node("HealthBar") as ProgressBar
	boss.call("receive_hit", {"damage": 2, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.1, "attack_stage": 1})
	_check(int(boss.get("health")) == 20 - 4 * HIT.damage - 2,
		"Warden consecutive damage is reflected in health")
	_check(is_equal_approx(boss_health_bar.value, float(boss.get("health"))),
		"Warden health bar stays synchronized after hits")

	var raider_ko_events := [0]
	raider.raider_ko.connect(func() -> void: raider_ko_events[0] += 1)
	raider.call("receive_hit", {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.2, "attack_stage": 3})
	raider.call("receive_hit", HIT)
	_check(raider_ko_events[0] == 1, "Raider KO signal emits exactly once")
	_check(raider.collision_layer == 0 and raider.collision_mask == 0
		and not (raider.get_node("ReceiveArea") as Area2D).monitoring
		and not (raider.get_node("ReceiveArea") as Area2D).monitorable,
		"Raider KO releases body and receive-area collision")

	var boss_ko_events := [0]
	boss.boss_ko.connect(func() -> void: boss_ko_events[0] += 1)
	boss.call("receive_hit", {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.2, "attack_stage": 3})
	boss.call("receive_hit", HIT)
	_check(boss_ko_events[0] == 1, "Warden KO signal emits exactly once")
	_check(boss.collision_layer == 0 and boss.collision_mask == 0
		and not (boss.get_node("ReceiveArea") as Area2D).monitoring
		and not (boss.get_node("ReceiveArea") as Area2D).monitorable,
		"Warden KO releases body and receive-area collision")
	_check(is_equal_approx(boss_health_bar.value, 0.0),
		"Warden KO synchronizes the health bar to zero")
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
		print("m6i_enemy_stagger_interruption_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("m6i_enemy_stagger_interruption_smoke: " + failure)
		quit(1)
