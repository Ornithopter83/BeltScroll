extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DUMMY_SCENE := "res://scenes/combat/training_dummy.tscn"

class HitReceiver:
	extends StaticBody2D
	var received_hits: Array[Dictionary] = []
	var impact_stage_observations: Array[int] = []
	var duplicate_impact_observation := false
	var impact_position_mismatch := false

	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group("hit_receivers")
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 8.0
		shape.shape = circle
		add_child(shape)

	func receive_hit(hit: Dictionary) -> void:
		received_hits.append(hit.duplicate())
		call_deferred("_observe_combat_impacts", int(hit["attack_stage"]))

	func _observe_combat_impacts(stage: int) -> void:
		var effect_count := 0
		for child in get_children():
			if child.name == "CombatImpact":
				effect_count += 1
				if int(child.get("attack_stage")) == stage:
					impact_stage_observations.append(stage)
					impact_position_mismatch = impact_position_mismatch or child.global_position.distance_to(global_position + Vector2(0.0, -20.0)) > 0.1
		duplicate_impact_observation = duplicate_impact_observation or effect_count > 1

var failures: Array[String] = []
var player: CharacterBody2D
var receivers: Array[HitReceiver] = []
var depth_decoys: Array[HitReceiver] = []
var recoil_by_stage: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(PLAYER_SCENE) as PackedScene
	player = packed.instantiate() as CharacterBody2D
	root.add_child(player)
	player.attack_hit.connect(_on_player_attack_hit)
	player.global_position = Vector2(400.0, 800.0)
	player.set("facing_direction", Vector2.RIGHT)
	player.get_node("VisualRoot").scale.x = 1.0
	for target_x in [460.0, 532.0, 620.0]:
		var receiver := HitReceiver.new()
		receiver.position = Vector2(target_x, 800.0)
		root.add_child(receiver)
		receivers.append(receiver)
	for decoy_position in [Vector2(460.0, 840.0), Vector2(350.0, 800.0)]:
		var decoy := HitReceiver.new()
		decoy.position = decoy_position
		root.add_child(decoy)
		depth_decoys.append(decoy)
	await _frames(2)

	Input.action_press("attack")
	await _frames(1)
	Input.action_release("attack")
	# Queue the first continuation near recovery, then queue the third strike
	# near the next recovery. Each stage gets fresh target IDs.
	await _wait_for_phase("recovery", 1)
	await _tap_attack()
	await _wait_for_phase("recovery", 2)
	await _tap_attack()
	await _wait_for_phase("recovery", 3)
	await _tap_attack()
	await _wait_for_idle()

	var stages: Array[int] = []
	var damage_by_stage := {1: 0.0, 2: 0.0, 3: 0.0}
	var knockback_by_stage := {1: 0.0, 2: 0.0, 3: 0.0}
	var hits_per_receiver := 0
	for receiver in receivers:
		hits_per_receiver = maxi(hits_per_receiver, receiver.received_hits.size())
		for hit in receiver.received_hits:
			_check(hit.has_all(["damage", "direction", "knockback", "hit_stun", "attack_stage"]), "hit payload follows the Dictionary contract")
			var stage := int(hit["attack_stage"])
			if not stages.has(stage):
				stages.append(stage)
			damage_by_stage[stage] = hit["damage"]
			knockback_by_stage[stage] = hit["knockback"]
	_check(stages.has(1) and stages.has(2) and stages.has(3), "buffered combo stages all reach receivers")
	_check(depth_decoys.all(func(decoy: HitReceiver) -> bool: return decoy.received_hits.is_empty()), "forward hitbox rejects targets outside its depth lane and behind the player")
	_check(depth_decoys.all(func(decoy: HitReceiver) -> bool:
		for child in decoy.get_children():
			if child.name == "CombatImpact":
				return false
		return true
	), "missed depth and rear attacks do not spawn impact effects")
	_check(hits_per_receiver <= 3, "each receiver is hit at most once per combo stage")
	var observed_stages: Array[int] = []
	var duplicate_impacts := false
	for receiver in receivers:
		for stage in receiver.impact_stage_observations:
			if not observed_stages.has(stage):
				observed_stages.append(stage)
		duplicate_impacts = duplicate_impacts or receiver.duplicate_impact_observation
	_check(observed_stages.has(1) and observed_stages.has(2) and observed_stages.has(3), "actual stage hits spawn their matching impact effect")
	_check(not duplicate_impacts, "a receiver never gets duplicate impacts from one hit callback")
	_check(receivers.all(func(receiver: HitReceiver) -> bool: return not receiver.impact_position_mismatch), "impact effects align to the receiver depth and torso position")
	_check(damage_by_stage[1] < damage_by_stage[2] and damage_by_stage[2] < damage_by_stage[3], "combo damage scales upward")
	_check(damage_by_stage[1] == 1.0 and damage_by_stage[2] == 2.0 and damage_by_stage[3] == 3.0, "default Player attack damage preserves the authored 1/2/3 combo values")
	player.set("attack_damage", 5)
	_check(player.call("_basic_attack_damage", 1) == 5 and player.call("_basic_attack_damage", 2) == 6 and player.call("_basic_attack_damage", 3) == 7, "edited Player attack damage feeds all combo stages while preserving stage scaling")
	_check(player.call("_skill_damage", 1) == 7 and player.call("_skill_damage", 2) == 6, "edited Player attack damage feeds skill damage while preserving skill differences")
	player.set("attack_damage", 1)
	_check(knockback_by_stage[1] < knockback_by_stage[2] and knockback_by_stage[2] < knockback_by_stage[3], "combo knockback scales upward")
	_check(recoil_by_stage.size() == 3, "all three combo hits trigger attacker recoil")
	_check(recoil_by_stage.get(1, false) and recoil_by_stage.get(2, false) and recoil_by_stage.get(3, false), "combo recoil pushes opposite the hit direction and briefly interrupts the attack")
	_check(player.get("attack_phase") == "idle", "combo returns control after recovery")
	_check(player.get("attack_progress") == 0.0, "attack progress resets after combo completion")

	var incoming := {
		"damage": 1,
		"direction": Vector2.LEFT,
		"knockback": 260.0,
		"hit_stun": 0.16,
		"attack_stage": 2,
	}
	player.receive_hit(incoming)
	_check(player.get("hitstun_remaining") > 0.0, "receive_hit enters hit stun")
	_check(player.velocity.x < 0.0, "receive_hit applies directional knockback")
	_check(player.get("camera_trauma") > 0.0, "incoming hit adds camera trauma")
	await _frames(15)
	_check(player.get("hitstun_remaining") == 0.0, "hit stun expires and controls return")
	var position_after_stun := player.global_position
	Input.action_press("move_right")
	await _frames(4)
	Input.action_release("move_right")
	_check(player.global_position.x > position_after_stun.x, "movement input works again after hit stun")
	_check(player.get("camera_trauma") < 0.22, "camera trauma decays after an incoming hit")
	player.global_position = Vector2(1747.0, 800.0)
	player.receive_hit({"damage": 0, "direction": Vector2.RIGHT, "knockback": 800.0, "hit_stun": 0.12, "attack_stage": 1})
	await _frames(3)
	_check(player.global_position.x <= 1747.0, "incoming knockback remains clamped at the player arena edge")
	await _frames(20)
	Input.action_press("jump")
	await _frames(3)
	var jump_height_before_stop: float = player.get("jump_height_offset")
	var time_scale_before_stop := Engine.time_scale
	player.call("_trigger_hit_stop", 0.08)
	_check(Engine.time_scale <= 0.08, "hit stop reduces gameplay time scale")
	await _frames(2)
	_check(player.get("is_jumping") == true and player.get("jump_height_offset") >= jump_height_before_stop, "jump state remains valid while hit-stop is active")
	Input.action_release("jump")
	await _frames(40)
	_check(player.get("is_jumping") == false, "jump completes after hit-stop restores gameplay time")
	_check(is_equal_approx(Engine.time_scale, time_scale_before_stop), "hit stop restores the previous gameplay time scale")
	await _check_player_hits_training_dummy()
	await _wait_for_idle()
	var skill1_keys := InputMap.action_get_events("skill_1")
	var skill2_keys := InputMap.action_get_events("skill_2")
	_check(skill1_keys.any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).keycode == KEY_KP_4), "Num4 keypad key is bound to skill 1")
	_check(skill2_keys.any(func(event: InputEvent) -> bool: return event is InputEventKey and (event as InputEventKey).keycode == KEY_KP_5), "Num5 keypad key is bound to skill 2")
	player.call("_request_skill", 1)
	_check(player.get("skill_phase") == "startup", "skill action can begin after ordinary combat")
	player.call("_request_attack")
	_check(player.get("skill_phase") == "startup" and player.get("attack_phase") == "idle", "basic combo input cannot overlap a skill")
	player.call("_cancel_skill")
	player.set("hitstun_remaining", 0.0)

	# KO interrupts an active combo and all player input while preserving floor placement.
	player.global_position = Vector2(900.0, 800.0)
	player.call("_request_skill", 2)
	player.set("skill_phase", "active")
	player.call("_set_skill_hitboxes", true)
	var floor_position := player.global_position
	player.receive_hit({"damage": 99, "direction": Vector2.LEFT, "knockback": 500.0, "hit_stun": 0.2, "attack_stage": 3})
	_check(player.get("health") == 0 and player.get("is_ko"), "lethal damage enters the terminal KO state")
	_check(player.get("attack_phase") == "idle" and player.get("attack_stage") == 0 and player.get("skill_phase") == "idle", "KO cancels combo and skill states")
	var hitboxes_off := true
	for index in range(1, 4):
		hitboxes_off = hitboxes_off and not player.get_node("Hitboxes/Hitbox%d" % index).monitoring
	hitboxes_off = hitboxes_off and not player.get_node("Hitboxes/Skill1Hitbox").monitoring and not player.get_node("Hitboxes/Skill2Hitbox").monitoring
	_check(hitboxes_off, "KO disables every combo and skill hitbox")
	Input.action_press("move_right")
	Input.action_press("jump")
	Input.action_press("attack")
	await _frames(8)
	Input.action_release("move_right")
	Input.action_release("jump")
	Input.action_release("attack")
	_check(player.global_position.distance_to(floor_position) < 0.01, "KO blocks movement and preserves the player's floor position")
	_check(not player.get("is_jumping") and player.get("jump_height_offset") == 0.0, "KO blocks jump input and grounds the visual")
	_check(player.get("attack_phase") == "idle", "KO blocks new attack input")
	player.receive_hit({"damage": 99, "direction": Vector2.RIGHT, "knockback": 800.0, "hit_stun": 0.5, "attack_stage": 1})
	_check(player.get("health") == 0 and player.get("hitstun_remaining") == 0.0, "repeated hits cannot underflow health or re-enter hit stun")

	if failures.is_empty():
		print("player_combat_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_combat_smoke: " + failure)
		push_error("player_combat_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _tap_attack() -> void:
	Input.action_press("attack")
	await physics_frame
	Input.action_release("attack")

func _wait_for_phase(expected_phase: String, expected_stage: int) -> void:
	for _frame in range(1200):
		if player.get("attack_phase") == expected_phase and player.get("attack_stage") == expected_stage:
			return
		await physics_frame
	_check(false, "stage %d reaches %s" % [expected_stage, expected_phase])

func _wait_for_idle() -> void:
	for _frame in range(1200):
		if player.get("attack_phase") == "idle":
			return
		await physics_frame
	_check(false, "combo returns to idle")

func _check_player_hits_training_dummy() -> void:
	player.global_position = Vector2(900.0, 800.0)
	player.set("facing_direction", Vector2.DOWN)
	var dummy_scene := load(DUMMY_SCENE) as PackedScene
	var dummy := dummy_scene.instantiate() as CharacterBody2D
	dummy.global_position = Vector2(900.0, 860.0)
	root.add_child(dummy)
	await physics_frame
	Input.action_press("attack")
	await physics_frame
	Input.action_release("attack")
	for _frame in range(1200):
		if dummy.get("last_attack_stage") == 1:
			break
		await physics_frame
	_check(dummy.get("last_attack_stage") == 1 and dummy.get("health") < 1000.0, "player's forward hitbox reaches the scene TrainingDummy via its receiver group")
	dummy.queue_free()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _on_player_attack_hit(stage: int) -> void:
	var recoil_velocity: Vector2 = player.get("attack_recoil_velocity")
	recoil_by_stage[stage] = float(player.get("attack_recoil_remaining")) > 0.0 and recoil_velocity.x < 0.0
