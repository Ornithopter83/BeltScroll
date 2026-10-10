extends SceneTree
"""Contact-window contract for sprite-authored basic and skill fist attacks."""

class HitReceiver extends CharacterBody2D:
	var hits: Array[Dictionary] = []

	func receive_hit(hit: Dictionary) -> void:
		hits.append(hit)

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
var _failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var arena := Node2D.new()
	root.add_child(arena)
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.set("arena_bounds", Rect2(0, 0, 2400, 2400))
	player.set_physics_process(false)
	arena.add_child(player)
	await process_frame
	player.set_physics_process(false)
	if not _player_script_is_live(player):
		_failures.append("Player script loaded with required hitbox methods; aborting before contract assertions")
		quit(1)
		return
	var visual_animator := player.get_node("VisualAnimator") as Node
	visual_animator.set_process(false)
	var pose_blender := player.get_node_or_null("VisualRoot/PoseBlender") as Node
	if pose_blender != null:
		pose_blender.set_process(false)
	await _check_basic_fists(arena, player)
	await _check_skill_fists(arena, player)
	_check_missing_sprite_disables_contact(player, visual_animator, pose_blender)
	if _failures.is_empty():
		print("m6r_player_fist_skill_contact_window_smoke: PASS")
		quit(0)
	else:
		for failure in _failures:
			push_error("m6r_player_fist_skill_contact_window_smoke: " + failure)
		quit(1)

func _player_script_is_live(player: CharacterBody2D) -> bool:
	if player.get_script() == null:
		push_error("Player scene has no live script; contact smoke cannot continue")
		return false
	for method_name in ["_set_stage_hitbox", "_set_skill_hitbox_transform", "_set_skill_hitboxes", "_check_stage_hitbox", "_check_skill_hitbox"]:
		if not player.has_method(method_name):
			push_error("Player script is missing required contact method: " + method_name)
			return false
	return true

func _check_basic_fists(arena: Node2D, player: CharacterBody2D) -> void:
	var animator: Node = player.get_node("VisualAnimator")
	var active_durations := [0.105, 0.12, 0.14]
	for stage in range(1, 4):
		player.set("attack_stage", stage)
		player.set("attack_phase", "active")
		player.set("attack_phase_remaining", active_durations[stage - 1] * 0.9)
		animator.call("_process", 0.0)
		var hitbox := player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
		player.call("_set_stage_hitbox", stage, true)
		var early_contact_value: Variant = animator.call("get_fist_contact_global")
		_check(typeof(early_contact_value) == TYPE_VECTOR2, "Stage %d displayed sprite exposes a real hand contact point" % stage)
		if typeof(early_contact_value) != TYPE_VECTOR2:
			continue
		var early_contact: Vector2 = early_contact_value
		player.set("attack_phase_remaining", active_durations[stage - 1] * 0.1)
		animator.call("_process", 0.0)
		player.call("_set_stage_hitbox", stage, true)
		var late_contact_value: Variant = animator.call("get_fist_contact_global")
		_check(typeof(late_contact_value) == TYPE_VECTOR2, "Stage %d displayed sprite retains its hand point while animating" % stage)
		if typeof(late_contact_value) != TYPE_VECTOR2:
			continue
		var late_contact: Vector2 = late_contact_value
		_check(hitbox.global_position.distance_to(late_contact) < 0.1, "Stage %d live Shape2D follows the displayed fist as its active phase advances" % stage)
		_check(early_contact.distance_to(late_contact) > 0.5, "Stage %d authored hand path moves during the active phase" % stage)
		player.set("attack_phase_remaining", active_durations[stage - 1] * 0.5)
		animator.call("_process", 0.0)
		player.call("_set_stage_hitbox", stage, true)
		var contact_value: Variant = animator.call("get_fist_contact_global")
		_check(typeof(contact_value) == TYPE_VECTOR2, "Stage %d has a measurable sprite contact point" % stage)
		if typeof(contact_value) != TYPE_VECTOR2:
			continue
		var contact: Vector2 = contact_value
		_check(hitbox.global_position.distance_to(contact) < 0.1, "Stage %d area follows the currently displayed fist transform" % stage)
		_check((hitbox.get_node("CollisionShape2D").shape as CircleShape2D).radius <= 15.0, "Stage %d contact shape stays fist-sized" % stage)
		var target := _receiver(arena, player.global_position, hitbox.global_position)
		await physics_frame
		player.call("_check_stage_hitbox", stage)
		_check(target.hits.size() == 1, "Stage %d contact damages one receiver from the fist contact" % stage)
		player.call("_check_stage_hitbox", stage)
		_check(target.hits.size() == 1, "Stage %d body and ReceiveArea do not duplicate damage" % stage)
		player.call("_set_stage_hitbox", stage, false)
		arena.remove_child(target)
		target.free()
		player.get("_hit_targets").clear()
		if stage == 1:
			var deep := _receiver(arena, player.global_position + Vector2(0, 80), contact)
			await physics_frame
			player.call("_check_stage_hitbox", stage)
			_check(deep.hits.is_empty(), "Basic fist rejects a physically overlapping receiver beyond belt depth")
			arena.remove_child(deep)
			deep.free()

	player.set("facing_direction", Vector2.LEFT)
	player.get_node("VisualRoot").scale.x = -1.0
	player.set("attack_stage", 1)
	animator.call("_process", 0.0)
	var left_hitbox := player.get_node("Hitboxes/Hitbox1") as Area2D
	var left_contact_value: Variant = animator.call("get_fist_contact_global")
	player.call("_set_stage_hitbox", 1, true)
	left_contact_value = animator.call("get_fist_contact_global")
	_check(typeof(left_contact_value) == TYPE_VECTOR2, "Left-facing sprite exposes a hand contact point")
	if typeof(left_contact_value) == TYPE_VECTOR2:
		var left_contact: Vector2 = left_contact_value
		_check(left_hitbox.global_position.distance_to(left_contact) < 0.1, "Left-facing hitbox uses the mirrored displayed fist point")
	player.call("_set_stage_hitbox", 1, false)
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.set("facing_direction", Vector2.RIGHT)
	player.get_node("VisualRoot").scale.x = 1.0

func _check_skill_fists(arena: Node2D, player: CharacterBody2D) -> void:
	var animator: Node = player.get_node("VisualAnimator")
	for skill_id in [1, 2]:
		player.set("skill_id", skill_id)
		player.set("skill_phase", "active")
		var active_duration := 0.12 if skill_id == 1 else 0.18
		player.set("skill_phase_remaining", active_duration * 0.9)
		animator.call("_process", 0.0)
		var area_name := "Skill1Hitbox" if skill_id == 1 else "Skill2Hitbox"
		var hitbox := player.get_node("Hitboxes/" + area_name) as Area2D
		player.call("_set_skill_hitbox_transform")
		var early_contact_value: Variant = animator.call("get_fist_contact_global")
		_check(typeof(early_contact_value) == TYPE_VECTOR2, "Num%d sprite exposes a real hand contact point" % (skill_id + 3))
		if typeof(early_contact_value) != TYPE_VECTOR2:
			continue
		var early_contact: Vector2 = early_contact_value
		player.set("skill_phase_remaining", active_duration * 0.1)
		animator.call("_process", 0.0)
		player.call("_set_skill_hitbox_transform")
		var late_contact_value: Variant = animator.call("get_fist_contact_global")
		_check(typeof(late_contact_value) == TYPE_VECTOR2, "Num%d displayed sprite retains its hand point while animating" % (skill_id + 3))
		if typeof(late_contact_value) != TYPE_VECTOR2:
			continue
		var late_contact: Vector2 = late_contact_value
		_check(hitbox.global_position.distance_to(late_contact) < 0.1, "Num%d live Shape2D follows the displayed fist as its active phase advances" % (skill_id + 3))
		_check(early_contact.distance_to(late_contact) > 0.5, "Num%d authored fist path changes across the active phase" % (skill_id + 3))
		player.set("skill_phase_remaining", active_duration * 0.5)
		animator.call("_process", 0.0)
		player.call("_set_skill_hitbox_transform")
		var contact_value: Variant = animator.call("get_fist_contact_global")
		_check(typeof(contact_value) == TYPE_VECTOR2, "Num%d has a measurable sprite contact point" % (skill_id + 3))
		if typeof(contact_value) != TYPE_VECTOR2:
			continue
		var contact: Vector2 = contact_value
		_check(hitbox.global_position.distance_to(contact) < 0.1, "Num%d hitbox follows the active fist path" % (skill_id + 3))
		_check((hitbox.get_node("CollisionShape2D").shape as CircleShape2D).radius <= 16.0, "Num%d contact shape stays fist-sized" % (skill_id + 3))
		player.call("_set_skill_hitboxes", true)
		var target := _receiver(arena, player.global_position, hitbox.global_position)
		await physics_frame
		player.call("_check_skill_hitbox")
		_check(target.hits.size() == 1, "Num%d fist contact damages one receiver" % (skill_id + 3))
		player.get("_skill_hit_targets").clear()
		var deep := _receiver(arena, player.global_position + Vector2(0, 80), contact)
		await physics_frame
		player.call("_check_skill_hitbox")
		_check(deep.hits.is_empty(), "Num%d fist rejects a physically overlapping receiver beyond belt depth" % (skill_id + 3))
		arena.remove_child(deep)
		deep.free()
		player.call("_set_skill_hitboxes", false)
		arena.remove_child(target)
		target.free()
		player.get("_skill_hit_targets").clear()
	player.set("skill_phase", "idle")
	player.set("skill_id", 0)

func _check_missing_sprite_disables_contact(player: CharacterBody2D, animator: Node, pose_blender: Node) -> void:
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	art.visible = false
	if pose_blender != null:
		pose_blender.visible = false
	var contact: Variant = animator.call("get_fist_contact_global")
	_check(contact == null, "Missing visible sprite has no substitute hand point")
	player.set("attack_stage", 1)
	player.set("attack_phase", "active")
	player.call("_set_stage_hitbox", 1, true)
	_check(not (player.get_node("Hitboxes/Hitbox1") as Area2D).monitoring, "Basic attack contact disables when no visible hand point exists")
	player.set("skill_id", 1)
	player.set("skill_phase", "active")
	player.call("_set_skill_hitboxes", true)
	_check(not (player.get_node("Hitboxes/Skill1Hitbox") as Area2D).monitoring, "Skill contact disables when no visible hand point exists")

func _receiver(parent: Node, root_position: Vector2, contact_global: Vector2) -> HitReceiver:
	var receiver := HitReceiver.new()
	receiver.name = "HitReceiver"
	receiver.position = root_position
	receiver.collision_layer = 2
	receiver.collision_mask = 0
	var contact_local := contact_global - root_position
	var body_shape := CollisionShape2D.new()
	var body_circle := CircleShape2D.new()
	body_circle.radius = 12.0
	body_shape.position = contact_local
	body_shape.shape = body_circle
	receiver.add_child(body_shape)
	var receive_area := Area2D.new()
	receive_area.name = "ReceiveArea"
	receive_area.position = contact_local
	receive_area.collision_layer = 2
	receive_area.collision_mask = 0
	receiver.add_child(receive_area)
	var receive_shape := CollisionShape2D.new()
	var receive_circle := CircleShape2D.new()
	receive_circle.radius = 12.0
	receive_shape.shape = receive_circle
	receive_area.add_child(receive_shape)
	receiver.add_to_group("hit_receivers")
	parent.add_child(receiver)
	return receiver

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)
		push_error("FAIL: " + description)
