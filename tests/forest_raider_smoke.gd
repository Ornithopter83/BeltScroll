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

	# Two raiders at the same point must move apart while pursuing.
	var second := packed.instantiate() as CharacterBody2D
	raider.global_position = Vector2(700.0, 400.0)
	second.global_position = raider.global_position + Vector2(10.0, 0.0)
	player.global_position = Vector2(1000.0, 400.0)
	root.add_child(second)
	await _frames(12)
	_check(raider.global_position.distance_to(second.global_position) > EPSILON, "nearby raiders apply separation while pursuing")
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
