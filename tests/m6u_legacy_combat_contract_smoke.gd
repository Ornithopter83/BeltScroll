extends "res://tests/m6s_real_combat_damage_window_smoke.gd"
"""Separates sprite-hand/Shape alignment from production-distance HP damage."""

func _run() -> void:
	await _check_hand_shape_contract()
	await super._run()

func _check_hand_shape_contract() -> void:
	var player_scene := load("res://scenes/player/player.tscn") as PackedScene
	_check(player_scene != null, "production Player scene loads for hand alignment contract")
	if player_scene == null:
		failures.append("hand alignment fixture unavailable")
		return
	var player := player_scene.instantiate() as CharacterBody2D
	root.add_child(player)
	await process_frame
	player.set_physics_process(false)
	player.set_process(false)
	var animator := player.get_node("VisualAnimator") as Node
	animator.set_process(false)
	for stage in range(1, 4):
		player.set("attack_stage", stage)
		player.set("attack_phase", "active")
		player.set("attack_phase_remaining", [0.105, 0.12, 0.14][stage - 1] * 0.5)
		animator.call("_process", 0.0)
		player.call("_set_stage_hitbox", stage, true)
		var contact: Variant = animator.call("get_fist_contact_global")
		var shape_node := player.get_node("Hitboxes/Hitbox%d/CollisionShape2D" % stage) as CollisionShape2D
		_check(typeof(contact) == TYPE_VECTOR2, "J%d has a visible authored fist contact point" % stage)
		if typeof(contact) == TYPE_VECTOR2:
			_check(shape_node.global_position.distance_to(contact as Vector2) < 0.1, "J%d CollisionShape2D origin matches the displayed fist point" % stage)
		_check((shape_node.shape as CircleShape2D).radius <= 15.0, "J%d contact shape remains fist-sized" % stage)
		player.call("_set_stage_hitbox", stage, false)

	player.set("facing_direction", Vector2.LEFT)
	player.get_node("VisualRoot").scale.x = -1.0
	player.set("attack_stage", 1)
	player.set("attack_phase", "active")
	animator.call("_process", 0.0)
	player.call("_set_stage_hitbox", 1, true)
	var left_contact: Variant = animator.call("get_fist_contact_global")
	var left_shape := player.get_node("Hitboxes/Hitbox1/CollisionShape2D") as CollisionShape2D
	_check(typeof(left_contact) == TYPE_VECTOR2 and left_shape.global_position.distance_to(left_contact as Vector2) < 0.1, "left-facing J1 Shape origin follows the mirrored fist point")
	player.call("_set_stage_hitbox", 1, false)

	for skill_id in [1, 2]:
		player.set("skill_id", skill_id)
		player.set("skill_phase", "active")
		player.set("skill_phase_remaining", (0.12 if skill_id == 1 else 0.18) * 0.5)
		animator.call("_process", 0.0)
		player.call("_set_skill_hitbox_transform")
		var contact: Variant = animator.call("get_fist_contact_global")
		var area_name := "Skill%dHitbox" % skill_id
		var shape_node := player.get_node("Hitboxes/%s/CollisionShape2D" % area_name) as CollisionShape2D
		_check(typeof(contact) == TYPE_VECTOR2, "Num%d has a visible authored fist contact point" % (skill_id + 3))
		if typeof(contact) == TYPE_VECTOR2:
			_check(shape_node.global_position.distance_to(contact as Vector2) < 0.1, "Num%d CollisionShape2D origin matches the displayed fist point" % (skill_id + 3))
		_check((shape_node.shape as CircleShape2D).radius <= 16.0, "Num%d contact shape remains fist-sized" % (skill_id + 3))
	player.set("attack_phase", "idle")
	player.set("skill_phase", "idle")
	root.remove_child(player)
	player.free()
	print("m6u legacy contract A: hand/Shape origin alignment checked independently")
	print("m6u legacy contract B: inherited live Window test checks actual HP damage at 120px")
