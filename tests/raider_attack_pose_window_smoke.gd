extends SceneTree
"""Checks the procedural Raider attack key poses and authored combat timing."""

const RAIDER_SCENE := "res://scenes/enemies/forest_raider.tscn"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(RAIDER_SCENE) as PackedScene
	_check(packed != null, "ForestRaider scene loads with the attack pose rig")
	if packed == null:
		_finish()
		return
	var raider := packed.instantiate() as CharacterBody2D
	root.add_child(raider)
	await process_frame
	raider.set_physics_process(false)
	var animator := raider.get_node("VisualAnimator")
	var rig := raider.get_node("VisualRoot/AttackPoseRig")
	var arm := rig.get_node("PunchArmPivot") as Node2D
	var home := arm.position
	var art := raider.get_node("VisualRoot/RaiderArt") as Sprite2D
	var baseline_foot := _foot_point(art)
	_check(rig.get_child_count() == 1 and rig.get_node_or_null("PunchArmPivot/Forearm") != null and rig.get_node_or_null("PunchArmPivot/Fist") != null, "separate forearm and fist overlays are attached to the source artwork")
	_check(is_equal_approx(float(raider.get("windup_duration")), 0.42), "windup keeps the authored 0.42 second telegraph")
	_check(is_equal_approx(float(raider.get("active_duration")), 0.16), "hitbox active window duration remains unchanged")
	raider.call("_begin_attack")
	_check(raider.get("attack_phase") == "windup" and not (raider.get_node("AttackArea") as Area2D).monitoring, "hitbox remains disabled throughout windup")
	_check(is_equal_approx(float(raider.get("attack_phase_remaining")), 0.42), "attack begins with the full 0.42 second windup")

	raider.set("attack_phase", "windup")
	raider.set("attack_phase_remaining", 0.0)
	_pose(animator, 18)
	var windup := arm.position
	raider.set("attack_phase", "active")
	raider.set("attack_phase_remaining", 0.08)
	_pose(animator, 18)
	var contact := arm.position
	raider.set("attack_phase", "recovery")
	raider.set("attack_phase_remaining", 0.25)
	_pose(animator, 18)
	var recovery := arm.position
	_check(windup.x > home.x + 20.0, "windup pulls the striking arm behind its guard")
	_check(contact.x < windup.x - 80.0, "contact pose drives the fist decisively forward")
	_check(recovery.x > contact.x + 25.0 and recovery.x < home.x, "recovery visibly draws the fist back toward neutral")
	_check(_foot_point(art).distance_to(baseline_foot) < 0.5, "keyframed body motion preserves the art foot anchor")
	raider.set("hit_flash_remaining", 0.12)
	raider.set("hitstun_remaining", 0.2)
	_pose(animator, 1)
	_check(arm.position.is_equal_approx(home), "hit flash interrupts the attack overlay immediately")
	raider.queue_free()
	await process_frame
	_finish()

func _pose(animator: Node, frames: int) -> void:
	for _frame in range(frames):
		animator.call("_process", 1.0 / 60.0)

func _foot_point(sprite: Sprite2D) -> Vector2:
	var bounds := sprite.texture.get_image().get_used_rect()
	var size := Vector2(sprite.texture.get_size())
	var alpha_foot := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y))
	return sprite.position + ((alpha_foot - size * 0.5) * sprite.scale).rotated(sprite.rotation)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("raider_attack_pose_window_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("raider_attack_pose_window_smoke: " + failure)
	push_error("raider_attack_pose_window_smoke: %d check(s) failed" % failures.size())
	quit(1)
