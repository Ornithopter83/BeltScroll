extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"

class SkillReceiver:
	extends StaticBody2D
	var received_hits: Array[Dictionary] = []

	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group("hit_receivers")
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 7.0
		shape.shape = circle
		add_child(shape)

	func receive_hit(hit: Dictionary) -> void:
		received_hits.append(hit.duplicate())

var failures: Array[String] = []
var player: CharacterBody2D
var targets: Array[SkillReceiver] = []
var skill_recoil_observations: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	player = (load(PLAYER_SCENE) as PackedScene).instantiate() as CharacterBody2D
	root.add_child(player)
	player.skill_hit.connect(_on_player_skill_hit)
	player.global_position = Vector2(400.0, 800.0)
	player.set("facing_direction", Vector2.RIGHT)
	player.get_node("VisualRoot").scale.x = 1.0
	var dash_target := _add_target(Vector2(535.0, 800.0))
	var dash_decoy := _add_target(Vector2(535.0, 850.0))
	var dash_far_decoy := _add_target(Vector2(705.0, 800.0))
	var spin_target := _add_target(Vector2(610.0, 800.0))
	var spin_edge := _add_target(Vector2(647.0, 800.0))
	var spin_decoy := _add_target(Vector2(650.0, 880.0))
	var spin_far_decoy := _add_target(Vector2(680.0, 800.0))
	await _frames(3)

	Input.action_press("skill_1")
	await physics_frame
	await physics_frame
	Input.action_release("skill_1")
	_check(player.get("skill_id") == 1 and ["startup", "active"].has(player.get("skill_phase")), "Num4 action starts skill 1")
	await _wait_for_skill_phase("active", 1)
	await _wait_for_skill_phase("recovery", 1)
	_check(dash_target.received_hits.size() == 1, "forward dash area hits its target exactly once")
	_check(skill_recoil_observations.get(1, false), "skill 1 hit briefly recoils the attacker opposite its lunge")
	_check(dash_decoy.received_hits.is_empty(), "forward dash lane rejects targets outside its depth")
	_check(dash_far_decoy.received_hits.is_empty(), "forward dash rejects targets beyond its reach")
	if not dash_target.received_hits.is_empty():
		var hit: Dictionary = dash_target.received_hits[0]
		_check(hit.get("skill_id") == 1 and hit.get("damage") == 3, "skill 1 has independent heavy damage metadata")
		_check(hit.get("knockback", 0.0) == 520.0 and hit.get("hit_stun", 0.0) == 0.42, "skill 1 carries its own knockback and hit stun")
	_check(player.get("skill_cooldowns")[0] > 0.0, "skill 1 starts its own cooldown")
	_check(player.get_node("Hitboxes/Skill1Hitbox").monitoring == false, "skill 1 hitbox turns off after active phase")
	await _wait_for_idle()

	# Skill 2 remains available while skill 1 is cooling down.
	spin_target.received_hits.clear()
	spin_edge.received_hits.clear()
	player.global_position = Vector2(600.0, 800.0)
	Input.action_press("skill_2")
	await physics_frame
	await physics_frame
	Input.action_release("skill_2")
	_check(player.get("skill_id") == 2 and ["startup", "active"].has(player.get("skill_phase")), "Num5 action starts skill 2 independently of skill 1 cooldown")
	await _wait_for_skill_phase("active", 2)
	await _wait_for_skill_phase("recovery", 2)
	_check(spin_target.received_hits.size() == 1 and spin_edge.received_hits.size() == 1, "spin area reaches targets inside its radius")
	_check(skill_recoil_observations.get(2, false), "skill 2 hit briefly recoils the attacker")
	_check(spin_decoy.received_hits.is_empty(), "spin area rejects targets outside its radius")
	_check(spin_far_decoy.received_hits.is_empty(), "spin area rejects targets beyond its radius")
	if not spin_target.received_hits.is_empty():
		var hit: Dictionary = spin_target.received_hits[0]
		_check(hit.get("skill_id") == 2 and hit.get("damage") == 2, "skill 2 has separate damage metadata")
		_check(hit.get("knockback", 0.0) == 360.0 and hit.get("hit_stun", 0.0) == 0.32, "skill 2 carries its own knockback and hit stun")
	_check(player.get("skill_cooldowns")[1] > 0.0, "skill 2 starts its own cooldown")
	_check(player.get_node("Hitboxes/Skill2Hitbox").monitoring == false, "skill 2 hitbox turns off after active phase")

	# Cooldown rejects recasting even after recovery ends.
	await _wait_for_idle()
	Input.action_press("skill_2")
	await physics_frame
	Input.action_release("skill_2")
	_check(player.get("skill_phase") == "idle", "skill 2 cannot recast during its cooldown")

	# Incoming hit interrupts all skill phases and restores movement after hit stun.
	player.set("skill_cooldowns", [0.0, 0.0])
	player.call("_request_skill", 1)
	await _wait_for_skill_phase("active", 1)
	player.set("attack_recoil_remaining", 0.06)
	player.set("attack_recoil_velocity", Vector2.LEFT * 100.0)
	player.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 180.0, "hit_stun": 0.08, "attack_stage": 1})
	_check(player.get("skill_phase") == "idle" and not player.get_node("Hitboxes/Skill1Hitbox").monitoring, "incoming hit interrupts skill and disables its area")
	_check(is_zero_approx(float(player.get("attack_recoil_remaining"))) and player.get("attack_recoil_velocity") == Vector2.ZERO, "incoming hit stun cancels any pending attack recoil")
	_check(player.get("hitstun_remaining") > 0.0, "interruption follows the existing receive_hit hit stun contract")
	await _frames(12)
	var x_before_move: float = player.global_position.x
	Input.action_press("move_right")
	await _frames(5)
	Input.action_release("move_right")
	_check(player.global_position.x > x_before_move, "normal movement returns after interrupted skill hit stun")

	# Jumping and blocking prevent skill start; blocking can interrupt an active skill.
	player.set("skill_cooldowns", [0.0, 0.0])
	player.set("is_jumping", true)
	player.call("_request_skill", 1)
	_check(player.get("skill_phase") == "idle", "skills cannot start during a jump")
	player.set("is_jumping", false)
	player.set("is_blocking", true)
	player.call("_request_skill", 2)
	_check(player.get("skill_phase") == "idle", "blocking prevents skill activation")
	player.set("is_blocking", false)
	Input.action_press("block")
	await physics_frame
	player.call("_request_skill", 2)
	_check(player.get("skill_phase") == "idle", "held block input prevents skill activation")
	Input.action_release("block")
	await _frames(2)
	player.call("_request_skill", 2)
	player.set("skill_phase", "active")
	player.call("_set_skill_hitboxes", true)
	Input.action_press("block")
	await physics_frame
	_check(player.get("skill_phase") == "idle" and not player.get_node("Hitboxes/Skill2Hitbox").monitoring, "block input interrupts an active skill")
	Input.action_release("block")

	if failures.is_empty():
		print("player_skill_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_skill_smoke: " + failure)
		push_error("player_skill_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _add_target(position: Vector2) -> SkillReceiver:
	var target := SkillReceiver.new()
	root.add_child(target)
	target.global_position = position
	targets.append(target)
	return target

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _wait_for_skill_phase(expected_phase: String, expected_skill: int) -> void:
	for _frame in range(1200):
		if player.get("skill_id") == expected_skill and player.get("skill_phase") == expected_phase:
			return
		await physics_frame
	_check(false, "skill %d reaches %s" % [expected_skill, expected_phase])

func _wait_for_idle() -> void:
	for _frame in range(1200):
		if player.get("skill_phase") == "idle":
			return
		await physics_frame
	_check(false, "skill recovery returns control")

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _on_player_skill_hit(skill: int) -> void:
	var recoil_velocity: Vector2 = player.get("attack_recoil_velocity")
	skill_recoil_observations[skill] = float(player.get("attack_recoil_remaining")) > 0.0 and recoil_velocity.length() > 0.0
