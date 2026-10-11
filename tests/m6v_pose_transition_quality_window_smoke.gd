extends SceneTree
"""Checks full-body source ownership and transform continuity at live pose gates."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FRAME := 1.0 / 60.0
const TRANSFORM_BOUND := 0.16

var _failures: Array[String] = []
var _player: CharacterBody2D
var _animator: Node
var _art: Sprite2D
var _blender: PlayerPoseBlender

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "test runs with a rendered Window")
	if DisplayServer.get_name() == "headless":
		_finish()
		return
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "Player scene loads")
	if packed == null:
		_finish()
		return
	_player = packed.instantiate() as CharacterBody2D
	root.add_child(_player)
	_player.set_physics_process(false)
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.queue_free()
	_animator = _player.get_node("VisualAnimator")
	_art = _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_blender = _player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
	await process_frame
	_animator.set_process(false)
	_check(_art != null and _blender != null, "PlayerArt and PoseBlender are present")
	if _art == null or _blender == null:
		_finish()
		return

	_player.velocity = Vector2.ZERO
	await _step(3)
	_check(_animator.get_animation_state() == "idle", "neutral state starts from idle")
	_player.velocity = Vector2(145.0, 0.0)
	await _step(2)
	_check(_animator.get_animation_state() == "walk", "movement enters walk without an idle frame")
	_player.velocity = Vector2.ZERO
	await _step(2)
	_check(_animator.get_animation_state() == "idle", "stopping returns directly to idle")
	_player.set("facing_direction", Vector2.LEFT)
	_player.velocity = Vector2(-145.0, 0.0)
	await _step(10)
	_check(not bool(_animator.call("is_turning")) and (_player.get_node("VisualRoot") as Node2D).scale.x < 0.0, "walking turn completes on the requested mirror")
	_player.velocity = Vector2.ZERO

	_player.set("is_jumping", true)
	_player.set("jump_vertical_velocity", -220.0)
	await _step(2)
	_check(_animator.get_animation_state() == "jump_rise", "jump ascent is resolved")
	_player.set("jump_vertical_velocity", 160.0)
	await _step(2)
	_check(_animator.get_animation_state() == "jump_fall", "jump descent is resolved")
	_player.set("is_jumping", false)
	await _step(1)
	_check(_animator.get_animation_state() == "landing", "jump release enters landing pose")
	_player.velocity = Vector2(145.0, 0.0)
	await _step(10)
	_check(_animator.get_animation_state() == "walk", "landing settles before the combo transition scenario")
	_player.velocity = Vector2.ZERO

	# Each attack phase starts from the exact transform reached by its prior phase.
	_player.set("attack_stage", 1)
	_player.set("attack_phase", "startup")
	_player.set("attack_phase_remaining", 0.0)
	await _step(1)
	var attack_start := _attack_transform()
	_player.set("attack_phase", "active")
	_player.set("attack_phase_remaining", 0.105)
	await _step(1)
	_check(_animator.get_animation_state() == "attack1_contact", "first strike takes over landing directly")
	_check(_transform_distance(attack_start, _attack_transform()) <= TRANSFORM_BOUND, "J1 startup to contact transform is continuous")
	_player.set("attack_phase_remaining", 0.0)
	await _step(1)
	var attack_active_end := _attack_transform()
	_player.set("attack_phase", "recovery")
	_player.set("attack_phase_remaining", 0.20)
	await _step(1)
	_check(_transform_distance(attack_active_end, _attack_transform()) <= TRANSFORM_BOUND, "J1 contact to recovery transform is continuous")
	_player.set("attack_phase_remaining", 0.0)
	await _step(1)
	var attack_contact := _attack_transform()
	_player.set("attack_phase", "combo_hold")
	_player.set("attack_phase_remaining", 0.4)
	await _step(5)
	_check(_animator.get_animation_state() == "attack1_contact" and _blender.get_current_pose_key() == "attack1_contact", "combo hold pins the final J1 contact drawing")
	_check(is_equal_approx(float(attack_contact.get("rotation")), float(_animator.get("_attack_rotation"))), "combo hold does not reset the preceding strike pose")
	_check(_exclusive_body_source_count() == 1, "combo hold renders exactly one full-body silhouette")
	_player.set("attack_stage", 2)
	_player.set("attack_phase", "startup")
	_player.set("attack_phase_remaining", 0.085)
	await _step(1)
	_check(_animator.get_animation_state() == "attack2_startup" and _exclusive_body_source_count() == 1, "2nd strike replaces J1 without an idle frame or silhouette overlap")
	_player.set("attack_phase_remaining", 0.0)
	await _step(1)
	var j2_start := _attack_transform()
	_player.set("attack_phase", "active")
	_player.set("attack_phase_remaining", 0.12)
	await _step(1)
	_check(_animator.get_animation_state() == "attack2_contact", "J2 contact follows its startup")
	_check(_transform_distance(j2_start, _attack_transform()) <= TRANSFORM_BOUND, "J2 startup to contact transform is continuous")
	_player.set("attack_phase_remaining", 0.0)
	await _step(1)
	var j2_active_end := _attack_transform()
	_player.set("attack_phase", "recovery")
	_player.set("attack_phase_remaining", 0.22)
	await _step(1)
	_check(_transform_distance(j2_active_end, _attack_transform()) <= TRANSFORM_BOUND, "J2 contact to recovery transform is continuous")
	_player.set("attack_phase_remaining", 0.0)
	await _step(1)
	_player.set("attack_phase", "combo_hold")
	_player.set("attack_phase_remaining", 0.4)
	await _step(3)
	_check(_blender.get_current_pose_key() == "attack2_contact", "2nd combo hold pins its contact pose")
	_player.set("attack_stage", 3)
	_player.set("attack_phase", "startup")
	_player.set("attack_phase_remaining", 0.10)
	await _step(1)
	_check(_animator.get_animation_state() == "attack3_startup", "J2 advances directly to J3")
	_player.set("attack_phase_remaining", 0.0)
	await _step(1)
	var j3_start := _attack_transform()
	_player.set("attack_phase", "active")
	_player.set("attack_phase_remaining", 0.14)
	await _step(1)
	_check(_animator.get_animation_state() == "attack3_contact", "J3 contact is resolved")
	_check(_transform_distance(j3_start, _attack_transform()) <= TRANSFORM_BOUND, "J3 startup to contact transform is continuous")
	_player.set("attack_phase_remaining", 0.0)
	await _step(1)
	var j3_active_end := _attack_transform()
	_player.set("attack_phase", "recovery")
	_player.set("attack_phase_remaining", 0.28)
	await _step(1)
	_check(_transform_distance(j3_active_end, _attack_transform()) <= TRANSFORM_BOUND, "J3 contact to recovery transform is continuous")
	_player.set("attack_phase_remaining", 0.0)
	await _step(1)
	_player.set("attack_phase", "idle")
	_player.set("attack_stage", 0)
	_player.velocity = Vector2(145.0, 0.0)
	await _step(1)
	_check(_animator.get_animation_state() == "walk" and _exclusive_body_source_count() == 1, "J3 returns to walk without a blank or doubled frame")

	# Num4 and Num5 pose endpoints share their phase boundary keys while keeping
	# distinct rotation and displacement signatures, independent of their VFX.
	var dash_start := await _run_skill_boundary(1, 0.12)
	var spin_start := await _run_skill_boundary(2, 0.18)
	_check(_transform_distance(dash_start, spin_start) > 0.15, "Num4 dash brace and Num5 spin windup have distinct body signatures")
	_player.set("hit_flash_remaining", 0.12)
	_player.set("hitstun_remaining", 0.20)
	_player.velocity = Vector2(-95.0, 0.0)
	await _step(2)
	_check(_animator.get_animation_state() == "hit", "hit reaction interrupts the active pose")
	_player.set("is_ko", true)
	await _step(2)
	_check(_animator.get_animation_state() == "ko", "KO has highest pose priority")

	var animator_source := FileAccess.get_file_as_string("res://scripts/player/player_visual_animator.gd")
	var controller_source := FileAccess.get_file_as_string("res://scripts/player/player_controller.gd")
	_check(animator_source.contains("get_fist_contact_global") and animator_source.contains("get_articulated_point_global"), "world-space hand contact interfaces remain available")
	_check(controller_source.contains("const ACTIVE := [0.105, 0.12, 0.14]"), "physical attack active windows remain controller-owned")
	_check(controller_source.contains("const SKILL_ACTIVE := [0.12, 0.18]"), "physical skill active windows remain controller-owned")
	_finish()

func _run_skill_boundary(skill_id: int, active_duration: float) -> Dictionary:
	_player.set("attack_phase", "idle")
	_player.set("attack_stage", 0)
	_player.set("skill_id", skill_id)
	_player.set("skill_phase", "startup")
	_player.set("skill_phase_remaining", 0.0)
	await _step(1)
	var startup_end := _skill_transform()
	_player.set("skill_phase", "active")
	_player.set("skill_phase_remaining", active_duration)
	await _step(1)
	var active_start := _skill_transform()
	_check(_transform_distance(startup_end, active_start) <= TRANSFORM_BOUND, "Num%d startup to contact transform is continuous" % (skill_id + 3))
	_player.set("skill_phase_remaining", 0.0)
	await _step(1)
	var active_end := _skill_transform()
	_player.set("skill_phase", "recovery")
	_player.set("skill_phase_remaining", 0.42 if skill_id == 1 else 0.55)
	await _step(1)
	_check(_transform_distance(active_end, _skill_transform()) <= TRANSFORM_BOUND, "Num%d contact to recovery transform is continuous" % (skill_id + 3))
	var signature := active_end
	_player.set("skill_phase", "idle")
	_player.set("skill_id", 0)
	await _step(2)
	return signature

func _attack_transform() -> Dictionary:
	return {"rotation": float(_animator.get("_attack_rotation")), "scale": _animator.get("_attack_scale"), "translation": _animator.get("_pose_translation")}

func _skill_transform() -> Dictionary:
	return {"rotation": float(_animator.get("_skill_rotation")), "scale": _animator.get("_skill_scale"), "translation": _animator.get("_pose_translation")}

func _transform_distance(left: Dictionary, right: Dictionary) -> float:
	var left_scale: Vector2 = left.get("scale", Vector2.ONE)
	var right_scale: Vector2 = right.get("scale", Vector2.ONE)
	var left_translation: Vector2 = left.get("translation", Vector2.ZERO)
	var right_translation: Vector2 = right.get("translation", Vector2.ZERO)
	return absf(float(left.get("rotation", 0.0)) - float(right.get("rotation", 0.0))) + left_scale.distance_to(right_scale) * 2.0 + left_translation.distance_to(right_translation) / 100.0

func _exclusive_body_source_count() -> int:
	var count := 1 if _art.visible and _art.texture != null else 0
	for node in _blender.find_children("PoseSprite*", "Sprite2D", false, false):
		var sprite := node as Sprite2D
		if sprite.is_visible_in_tree() and sprite.texture != null and sprite.modulate.a > 0.001:
			count += 1
	var walk_candidate := _player.get_node_or_null("WalkMotion")
	if walk_candidate != null and walk_candidate.has_method("get_candidate_sprite"):
		var sprite := walk_candidate.call("get_candidate_sprite") as Sprite2D
		if sprite != null and sprite.is_visible_in_tree() and sprite.texture != null:
			count += 1
	return count

func _step(count: int) -> void:
	for _frame in range(count):
		_animator.call("_process", FRAME)
		await process_frame
		await RenderingServer.frame_post_draw
		_check(_exclusive_body_source_count() == 1, "sample retains one visible full-body source")

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
		push_error("FAIL: " + description)

func _finish() -> void:
	print("m6v_pose_transition_quality_window_smoke: %d failure(s)" % _failures.size())
	quit(1 if not _failures.is_empty() else 0)
