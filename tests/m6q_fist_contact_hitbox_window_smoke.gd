extends SceneTree
"""Regression coverage for basic punch contact, belt depth, and enemy contracts."""

class HitReceiver extends CharacterBody2D:
	var hits: Array[Dictionary] = []

	func receive_hit(hit: Dictionary) -> void:
		hits.append(hit)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RAIDER_SCENE := preload("res://scenes/enemies/forest_raider.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/ruins_warden_boss.tscn")

var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.set("arena_bounds", Rect2(0, 0, 2000, 2000))
	player.set_physics_process(false)
	arena.add_child(player)
	await process_frame
	await _test_contact_and_misses(arena, player)
	await _test_enemy_contracts(arena, player)
	if _failures.is_empty():
		print("m6q_fist_contact_hitbox_window_smoke: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("m6q_fist_contact_hitbox_window_smoke: " + failure)
		quit(1)

func _test_contact_and_misses(arena: Node2D, player: CharacterBody2D) -> void:
	player.global_position = Vector2(300, 500)
	player.set("facing_direction", Vector2.RIGHT)
	for stage in range(1, 4):
		player.call("_set_stage_hitbox", stage, true)
		var hitbox := player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
		_check(hitbox.rotation == 0.0 and hitbox.position.y < -35.0, "Stage %d hitbox is horizontal and elevated to fist height" % stage)
		var target := _receiver(arena, player.global_position + Vector2(50, 0))
		await _physics_frames(2)
		_check(hitbox.get_overlapping_areas().size() > 0, "Stage %d actual hitbox overlaps the receiver at the fist contact lane" % stage)
		player.call("_check_stage_hitbox", stage)
		_check(target.hits.size() == 1, "Stage %d overlap applies one hit despite body and ReceiveArea overlap" % stage)
		player.call("_check_stage_hitbox", stage)
		_check(target.hits.size() == 1, "Stage %d target can only be hit once per combo" % stage)
		player.get("_hit_targets").clear()
		player.call("_set_stage_hitbox", stage, false)
		arena.remove_child(target)
		target.free()
	var first := player.get_node("Hitboxes/Hitbox1") as Area2D
	player.call("_set_stage_hitbox", 1, true)
	var outside := _receiver(arena, player.global_position + Vector2(145, 0))
	await _physics_frames(2)
	_check(first.get_overlapping_areas().is_empty(), "Target outside the fist strike does not physically overlap basic attack")
	player.call("_check_stage_hitbox", 1)
	_check(outside.hits.is_empty(), "Target outside the fist strike takes no damage")
	var deep := _receiver(arena, player.global_position + Vector2(40, 50), 130.0)
	await _physics_frames(2)
	_check(first.get_overlapping_bodies().has(deep), "Deep-lane fixture overlaps the real attack area geometry")
	player.call("_check_stage_hitbox", 1)
	_check(deep.hits.is_empty(), "Root depth beyond tolerance is rejected despite shape overlap")
	player.call("_set_stage_hitbox", 1, false)
	player.set("facing_direction", Vector2.LEFT)
	player.call("_set_stage_hitbox", 1, true)
	_check(first.position.x < 0.0 and first.position.y < -35.0, "Left-facing punch mirrors forward while staying at fist height")
	var left_target := _receiver(arena, player.global_position + Vector2(-50, 0))
	await _physics_frames(2)
	_check(first.get_overlapping_areas().has(left_target.get_node("ReceiveArea")), "Left-facing actual hitbox overlaps its forward target")
	player.call("_check_stage_hitbox", 1)
	_check(left_target.hits.size() == 1, "Left-facing punch applies damage")
	player.call("_set_stage_hitbox", 1, false)
	for target in [outside, deep, left_target]:
		arena.remove_child(target)
		target.free()
	player.get("_hit_targets").clear()

func _test_enemy_contracts(arena: Node2D, player: CharacterBody2D) -> void:
	player.global_position = Vector2(300, 500)
	player.set("facing_direction", Vector2.RIGHT)
	player.call("_set_stage_hitbox", 1, true)
	var raider := RAIDER_SCENE.instantiate()
	raider.set_physics_process(false)
	arena.add_child(raider)
	raider.set_physics_process(false)
	raider.global_position = player.global_position + Vector2(50, 0)
	await _physics_frames(2)
	player.call("_check_stage_hitbox", 1)
	_check(int(raider.get("health")) == int(raider.get("max_health")) - 1, "Basic punch preserves the ForestRaider receive_hit damage contract")
	player.get("_hit_targets").clear()
	arena.remove_child(raider)
	raider.free()
	var boss := BOSS_SCENE.instantiate()
	boss.set_physics_process(false)
	boss.global_position = player.global_position + Vector2(50, 0)
	arena.add_child(boss)
	boss.call("set_combat_active", true)
	boss.set_physics_process(false)
	await _physics_frames(2)
	player.call("_check_stage_hitbox", 1)
	_check(int(boss.get("health")) == int(boss.get("max_health")) - 1, "Basic punch preserves the active RuinsWardenBoss receive_hit damage contract")
	player.call("_set_stage_hitbox", 1, false)
	arena.remove_child(boss)
	boss.free()

func _receiver(parent: Node, position: Vector2, body_height: float = 40.0) -> HitReceiver:
	var target := HitReceiver.new()
	target.name = "HitReceiver"
	target.position = position
	target.collision_layer = 2
	target.collision_mask = 0
	var body_shape := CollisionShape2D.new()
	var capsule := CapsuleShape2D.new()
	capsule.radius = 16.0
	capsule.height = body_height
	body_shape.position = Vector2(0, -19)
	body_shape.shape = capsule
	target.add_child(body_shape)
	var receive_area := Area2D.new()
	receive_area.name = "ReceiveArea"
	receive_area.position = Vector2(0, -19)
	receive_area.collision_layer = 2
	receive_area.collision_mask = 0
	receive_area.monitorable = true
	target.add_child(receive_area)
	var receive_shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 30.0
	receive_shape.shape = circle
	receive_area.add_child(receive_shape)
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
