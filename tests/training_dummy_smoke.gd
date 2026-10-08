extends SceneTree

const DUMMY_SCENE := "res://scenes/combat/training_dummy.tscn"
const EPSILON := 0.1

var failures: Array[String] = []
var dummy: CharacterBody2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed_dummy := load(DUMMY_SCENE) as PackedScene
	dummy = packed_dummy.instantiate() as CharacterBody2D
	dummy.position = Vector2(1220, 540)
	root.add_child(dummy)
	await physics_frame
	var home := dummy.global_position
	_check(dummy.is_in_group("hit_receivers"), "dummy registers in hit_receivers")
	_check(dummy.collision_layer == 2, "dummy is visible to the player's forward attack hitbox layer")

	var hit := {
		"damage": 37.0,
		"direction": Vector2.RIGHT,
		"knockback": 480.0,
		"hit_stun": 0.12,
		"attack_stage": 2,
	}
	dummy.receive_hit(hit)
	_check(is_equal_approx(dummy.get("health"), 963.0), "receive_hit applies damage")
	_check(int(dummy.get("last_attack_stage")) == 2, "receive_hit records attack stage")
	_check(dummy.velocity.x > 0.0, "receive_hit applies directional knockback")
	_check((dummy.get_node("VisualRoot/Body") as Polygon2D).color == Color(1.0, 0.88, 0.72, 1.0), "hit immediately flashes the dummy")
	await _frames(8)
	_check(dummy.global_position.x > home.x + 20.0, "knockback moves the dummy away from home")
	_check(dummy.global_position.x <= 1742.0 + EPSILON, "dummy remains inside the arena after knockback")
	await _frames(150)
	_check(dummy.global_position.distance_to(home) < 2.0, "dummy returns to its home position after the delay")
	_check((dummy.get_node("VisualRoot/Body") as Polygon2D).color == Color(0.72, 0.57, 0.29, 1.0), "hit flash clears after its duration")

	if failures.is_empty():
		print("training_dummy_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("training_dummy_smoke: " + failure)
		push_error("training_dummy_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
