extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DUMMY_SCENE := "res://scenes/combat/training_dummy.tscn"

class HitReceiver:
	extends StaticBody2D
	var received_hits: Array[Dictionary] = []

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

var failures: Array[String] = []
var player: CharacterBody2D
var receivers: Array[HitReceiver] = []
var depth_decoys: Array[HitReceiver] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed: PackedScene = load(PLAYER_SCENE) as PackedScene
	player = packed.instantiate() as CharacterBody2D
	root.add_child(player)
	player.global_position = Vector2(400.0, 300.0)
	for target_y in [360.0, 432.0, 620.0]:
		var receiver := HitReceiver.new()
		receiver.position = Vector2(400.0, target_y)
		root.add_child(receiver)
		receivers.append(receiver)
	for decoy_position in [Vector2(440.0, 360.0), Vector2(400.0, 250.0)]:
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
	_check(hits_per_receiver <= 3, "each receiver is hit at most once per combo stage")
	_check(damage_by_stage[1] < damage_by_stage[2] and damage_by_stage[2] < damage_by_stage[3], "combo damage scales upward")
	_check(knockback_by_stage[1] < knockback_by_stage[2] and knockback_by_stage[2] < knockback_by_stage[3], "combo knockback scales upward")
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
	await _frames(15)
	_check(player.get("hitstun_remaining") == 0.0, "hit stun expires and controls return")
	player.global_position = Vector2(1747.0, 500.0)
	player.receive_hit({"damage": 0, "direction": Vector2.RIGHT, "knockback": 800.0, "hit_stun": 0.12, "attack_stage": 1})
	await _frames(3)
	_check(player.global_position.x <= 1747.0, "incoming knockback remains clamped at the player arena edge")
	await _frames(20)
	Input.action_press("jump")
	await _frames(3)
	var jump_height_before_stop: float = player.get("jump_height_offset")
	player.call("_trigger_hit_stop", 0.08)
	await _frames(2)
	_check(player.get("is_jumping") == true and player.get("jump_height_offset") >= jump_height_before_stop, "jump state remains valid while hit-stop is active")
	Input.action_release("jump")
	await _frames(40)
	_check(player.get("is_jumping") == false, "jump completes after hit-stop restores gameplay time")
	await _check_player_hits_training_dummy()

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
	player.global_position = Vector2(900.0, 500.0)
	player.set("facing_direction", Vector2.DOWN)
	var dummy_scene := load(DUMMY_SCENE) as PackedScene
	var dummy := dummy_scene.instantiate() as CharacterBody2D
	dummy.global_position = Vector2(900.0, 560.0)
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
