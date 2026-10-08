extends SceneTree

const RAIDER_SCENE := "res://scenes/enemies/forest_raider.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const EPSILON := 0.2

class TestReceiver:
	extends CharacterBody2D
	var hits: Array[Dictionary] = []

	func _init() -> void:
		collision_layer = 1
		collision_mask = 0
		add_to_group("hit_receivers")
		var shape := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 10.0
		shape.shape = circle
		add_child(shape)

	func receive_hit(hit: Dictionary) -> void:
		hits.append(hit.duplicate(true))

var failures: Array[String] = []
var raider: CharacterBody2D
var player: TestReceiver

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(RAIDER_SCENE) as PackedScene
	raider = packed.instantiate() as CharacterBody2D
	player = TestReceiver.new()
	player.name = "Player"
	raider.position = Vector2(500.0, 500.0)
	player.position = Vector2(760.0, 500.0)
	root.add_child(player)
	root.add_child(raider)
	await _frames(35)
	_check(raider.global_position.x > 500.0, "raider pursues the player on the x axis")
	_check(raider.collision_layer == 2 and raider.get_node("AttackArea").collision_mask == 1, "enemy body and attack mask match player combat layers")
	_check(raider.is_in_group("hit_receivers"), "raider registers in hit_receivers")
	var player_scene := (load(PLAYER_SCENE) as PackedScene).instantiate()
	_check(player_scene.get_node("Hitboxes/Hitbox1").collision_mask == 2, "player attack hitbox targets enemy layer 2")
	player_scene.free()

	# A nearby player on another depth lane must not trigger an attack.
	raider.global_position = Vector2(900.0, 450.0)
	player.global_position = Vector2(930.0, 620.0)
	await _frames(3)
	_check(raider.get("attack_phase") == "idle", "depth-separated player is rejected as an attack target")

	# Test the complete attack timeline with a receiver that records the payload.
	raider.global_position = Vector2(1000.0, 500.0)
	player.global_position = Vector2(1050.0, 500.0)
	raider.set("windup_duration", 0.12)
	raider.set("active_duration", 0.28)
	raider.set("recovery_duration", 0.32)
	await _frames(1)
	_check(raider.get("attack_phase") == "windup", "raider enters windup at close matching depth")
	await _wait_for_phase("active")
	_check(raider.get("attack_phase") == "active", "windup advances into active")
	_check(player.hits.size() == 1, "active attack delivers one Dictionary hit")
	if not player.hits.is_empty():
		var hit: Dictionary = player.hits[0]
		_check(hit.has_all(["damage", "direction", "knockback", "hit_stun", "attack_stage"]), "raider hit follows the shared Dictionary contract")
	await _frames(5)
	_check(player.hits.size() == 1, "one active swing cannot hit the same receiver twice")
	await _wait_for_phase("recovery")
	_check(raider.get("attack_phase") == "recovery", "active advances into recovery")

	# Windup cancellation is independent of hit delivery.
	await _wait_for_phase("idle")
	player.hits.clear()
	raider.global_position = Vector2(1200.0, 500.0)
	player.global_position = Vector2(1245.0, 500.0)
	await _frames(1)
	_check(raider.get("attack_phase") == "windup", "second attack starts before depth cancellation check")
	player.global_position.y = 580.0
	await _frames(1)
	_check(raider.get("attack_phase") == "idle" and not raider.get_node("AttackArea").monitoring, "depth exit cancels windup and disables the attack area")
	_check(player.hits.is_empty(), "canceled attack does not deliver a hit")

	# Raiders starting at the exact same point separate, keep room, then continue pursuit.
	var second := packed.instantiate() as CharacterBody2D
	raider.global_position = Vector2(700.0, 400.0)
	second.global_position = raider.global_position
	player.global_position = Vector2(1000.0, 400.0)
	root.add_child(second)
	await _frames(12)
	var initial_separation := raider.global_position.distance_to(second.global_position)
	_check(initial_separation > EPSILON, "coincident raiders deterministically separate while pursuing")
	await _frames(24)
	var maintained_separation := raider.global_position.distance_to(second.global_position)
	_check(maintained_separation > EPSILON, "separated raiders do not return to the same position")
	_check(raider.global_position.x < 1745.0 and second.global_position.x < 1745.0, "separation keeps both raiders inside the arena")
	var pair_x_before_pursuit := (raider.global_position.x + second.global_position.x) * 0.5
	player.global_position.x = 1250.0
	await _frames(10)
	var pair_x_after_pursuit := (raider.global_position.x + second.global_position.x) * 0.5
	_check(pair_x_after_pursuit > pair_x_before_pursuit, "separated raiders resume tracking the player")
	# A point-blank player must not let coincident raiders enter repeated attacks before they make room.
	raider.global_position = Vector2(700.0, 400.0)
	second.global_position = raider.global_position
	player.global_position = Vector2(770.0, 400.0)
	await _frames(1)
	_check(raider.get("attack_phase") == "idle" and second.get("attack_phase") == "idle", "coincident raiders prioritize separation over point-blank attacks")
	await _frames(40)
	var close_pair_gap := raider.global_position.distance_to(second.global_position)
	_check(close_pair_gap > 35.0, "point-blank raiders establish room before attacking")
	var min_gap := close_pair_gap
	var max_gap := close_pair_gap
	for _frame in range(30):
		await physics_frame
		var current_gap := raider.global_position.distance_to(second.global_position)
		min_gap = minf(min_gap, current_gap)
		max_gap = maxf(max_gap, current_gap)
	_check(min_gap > 35.0, "point-blank combat does not collapse back into Raider overlap")
	_check(max_gap - min_gap < 12.0, "Raider spacing stays stable without visible oscillation")
	_check(raider.get("attack_phase") != "idle" or second.get("attack_phase") != "idle", "Raider attacks resume after they have made room")
	second.queue_free()

	# Incoming hit cancels attacks, applies knockback, expires stun, and resumes pursuit.
	raider.global_position = Vector2(800.0, 500.0)
	player.global_position = Vector2(1100.0, 500.0)
	raider.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 360.0, "hit_stun": 0.14, "attack_stage": 2})
	_check(raider.get("hitstun_remaining") > 0.0 and raider.velocity.x < 0.0, "receive_hit applies stun and directional knockback")
	await _frames(12)
	_check(raider.get("hitstun_remaining") == 0.0, "hit stun expires")
	var position_after_hit := raider.global_position.x
	await _frames(8)
	_check(raider.global_position.x > position_after_hit, "raider resumes pursuit after hit stun")

	raider.global_position = Vector2(1750.0, 500.0)
	raider.receive_hit({"damage": 0, "direction": Vector2.RIGHT, "knockback": 900.0, "hit_stun": 0.16, "attack_stage": 1})
	await _frames(5)
	_check(raider.global_position.x <= 1745.0 + EPSILON, "knockback remains clamped inside the arena")

	if failures.is_empty():
		print("forest_raider_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("forest_raider_smoke: " + failure)
		push_error("forest_raider_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _wait_for_phase(expected: String) -> void:
	for _frame in range(240):
		if raider.get("attack_phase") == expected:
			return
		await physics_frame
	_check(false, "raider reaches %s" % expected)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
