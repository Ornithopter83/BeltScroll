extends SceneTree

class HitReceiver extends CharacterBody2D:
	var hits: Array[Dictionary] = []

	func receive_hit(hit: Dictionary) -> void:
		hits.append(hit)

const RAIDER_SCENE := preload("res://scenes/enemies/forest_raider.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/ruins_warden_boss.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	await process_frame
	await _test_raider_rectangle(arena)
	await _test_boss_slash_circle(arena)
	await _test_boss_slam_circle_and_depth(arena)
	_test_disabled_state(arena)
	if _failures.is_empty():
		print("m6n_enemy_collision_alignment_smoke: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("m6n_enemy_collision_alignment_smoke: " + failure)
		push_error("m6n_enemy_collision_alignment_smoke: %d check(s) failed" % _failures.size())
		quit(1)

func _test_raider_rectangle(arena: Node2D) -> void:
	var raider := RAIDER_SCENE.instantiate()
	arena.add_child(raider)
	raider.set_physics_process(false)
	raider.global_position = Vector2(600, 500)
	raider.facing_direction = Vector2.RIGHT
	raider.call("_begin_attack")
	var attack_area := raider.get_node("AttackArea") as Area2D
	var rect := (attack_area.get_node("CollisionShape2D") as CollisionShape2D).shape as RectangleShape2D
	_check(rect != null and rect.size == Vector2(78, 48), "Raider live AttackArea uses the authored 78×48 rectangle")
	_check(attack_area.position.is_equal_approx(Vector2(54.72, -30.0)), "Raider rectangle center follows the right-facing windup/contact placement")
	var target := _receiver(arena, raider.global_position + Vector2(55, -30))
	attack_area.monitoring = true
	await _physics_frames(2)
	_check(attack_area.get_overlapping_bodies().has(target), "Raider rectangle overlaps a receiver inside its actual shape")
	raider.call("_check_attack_targets")
	_check(target.hits.size() == 1, "Raider actual Area2D overlap calls the existing receive_hit contract once")
	attack_area.monitoring = false
	await _physics_frames(2)
	_check(not attack_area.monitoring, "Raider disabled AttackArea cannot retain an active hit window")
	attack_area.monitoring = true
	target.global_position = raider.global_position + Vector2(130, -30)
	await _physics_frames(2)
	_check(not attack_area.get_overlapping_bodies().has(target), "Raider rectangle does not hit beyond its forward edge")
	arena.remove_child(raider)
	arena.remove_child(target)
	raider.free()
	target.free()

func _test_boss_slash_circle(arena: Node2D) -> void:
	var boss := BOSS_SCENE.instantiate()
	arena.add_child(boss)
	boss.set_physics_process(false)
	boss.facing_direction = Vector2.RIGHT
	boss.call("_begin_attack", "slash")
	var attack_area := boss.get_node("AttackArea") as Area2D
	var slash := (attack_area.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	_check(slash != null and is_equal_approx(slash.radius, 67.0), "Boss slash uses its live 67px circular shape")
	_check(attack_area.position.is_equal_approx(Vector2(86, -47)), "Boss slash circle center faces forward at the telegraphed offset")
	var target := _receiver(arena, Vector2(140, 0))
	target.add_to_group("player")
	attack_area.monitoring = true
	await _physics_frames(2)
	_check(attack_area.get_overlapping_bodies().has(target), "Boss slash circle overlaps its forward contact target")
	boss.call("_check_attack_targets")
	_check(target.hits.size() == 1, "Boss slash applies damage only after live Area2D overlap")
	attack_area.monitoring = false
	await _physics_frames(2)
	target.global_position = Vector2(180, 0)
	attack_area.monitoring = true
	await _physics_frames(2)
	_check(not attack_area.get_overlapping_bodies().has(target), "Boss slash target outside its actual 67px Area2D circle does not overlap")
	boss.get("_hit_targets").clear()
	boss.call("_check_attack_targets")
	_check(target.hits.size() == 1, "Boss slash does not hit a player outside the actual 67px Area2D circle")
	attack_area.monitoring = false
	boss.facing_direction = Vector2.LEFT
	boss.call("_begin_attack", "slash")
	_check(attack_area.position.is_equal_approx(Vector2(-86, -47)), "Boss slash circle moves behind the boss when facing left")
	target.global_position = Vector2(-140, 0)
	attack_area.monitoring = true
	await _physics_frames(2)
	_check(attack_area.get_overlapping_bodies().has(target), "Left-facing Boss slash overlaps its actual forward contact target")
	boss.call("_check_attack_targets")
	_check(target.hits.size() == 2, "Left-facing Boss slash applies damage through the live Area2D overlap")
	arena.remove_child(boss)
	arena.remove_child(target)
	boss.free()
	target.free()

func _test_boss_slam_circle_and_depth(arena: Node2D) -> void:
	var boss := BOSS_SCENE.instantiate()
	arena.add_child(boss)
	boss.set_physics_process(false)
	boss.call("_begin_attack", "slam")
	var attack_area := boss.get_node("AttackArea") as Area2D
	var slam := (attack_area.get_node("CollisionShape2D") as CollisionShape2D).shape as CircleShape2D
	_check(slam != null and is_equal_approx(slam.radius, 125.0), "Boss slam switches to its live 125px circular shape")
	_check(attack_area.position.is_equal_approx(Vector2(0, -18)), "Boss slam circle stays centered on the telegraphed ground lane")
	var target := _receiver(arena, Vector2(80, 100))
	attack_area.monitoring = true
	await _physics_frames(2)
	_check(attack_area.get_overlapping_bodies().has(target), "Boss slam shape reaches the 100px depth lane")
	boss.call("_check_attack_targets")
	_check(target.hits.size() == 1, "Boss slam accepts the intended depth lane through actual overlap")
	attack_area.monitoring = false
	await _physics_frames(2)
	arena.remove_child(target)
	target.free()
	target = _receiver(arena, Vector2(0, 120))
	attack_area.monitoring = true
	await _physics_frames(2)
	_check(attack_area.get_overlapping_bodies().has(target), "Boss deep-lane fixture physically overlaps the slam circle")
	boss.call("_check_attack_targets")
	_check(target.hits.is_empty(), "Boss slam depth lane rejects a root beyond 105px even when its body overlaps the circle")
	target.global_position = Vector2(0, 105)
	await _physics_frames(2)
	_check(attack_area.get_overlapping_bodies().has(target), "Boss slam circle overlaps a target at the 105px depth limit")
	boss.call("_check_attack_targets")
	_check(target.hits.size() == 1, "Boss slam accepts actual overlap at the 105px depth limit")
	attack_area.monitoring = false
	await _physics_frames(2)
	target.global_position = Vector2(180, 0)
	attack_area.monitoring = true
	await _physics_frames(2)
	_check(not attack_area.get_overlapping_bodies().has(target), "Boss slam does not overlap a target beyond its circular radius")
	boss.call("_check_attack_targets")
	_check(target.hits.size() == 1, "Boss slam cannot damage a target beyond its live Area2D circle")
	arena.remove_child(boss)
	arena.remove_child(target)
	boss.free()
	target.free()

func _test_disabled_state(arena: Node2D) -> void:
	var raider := RAIDER_SCENE.instantiate()
	arena.add_child(raider)
	raider.set_physics_process(false)
	raider.call("receive_hit", {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	_check(not (raider.get_node("AttackArea") as Area2D).monitoring, "Raider KO leaves AttackArea disabled")
	_check(not (raider.get_node("ReceiveArea") as Area2D).monitorable, "Raider KO removes ReceiveArea from hit detection")
	var boss := BOSS_SCENE.instantiate()
	arena.add_child(boss)
	boss.set_physics_process(false)
	boss.call("set_combat_active", true)
	boss.call("receive_hit", {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1})
	_check(not (boss.get_node("AttackArea") as Area2D).monitoring, "Boss KO leaves AttackArea disabled")
	_check(not (boss.get_node("ReceiveArea") as Area2D).monitorable, "Boss KO removes ReceiveArea from hit detection")
	arena.remove_child(raider)
	arena.remove_child(boss)
	raider.free()
	boss.free()

func _receiver(parent: Node, position: Vector2) -> HitReceiver:
	var target := HitReceiver.new()
	target.name = "HitReceiver"
	target.position = position
	target.collision_layer = 1
	target.collision_mask = 0
	var shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 16.0
	capsule.height = 40.0
	shape.position = Vector2(0, -19)
	shape.shape = capsule
	target.add_child(shape)
	target.add_to_group("hit_receivers")
	parent.add_child(target)
	return target

func _physics_frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		push_error("FAIL: " + description)
