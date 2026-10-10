extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FRAME := 1.0 / 60.0
const FLOOR_TOLERANCE := 0.08

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "player scene loads")
	if packed == null:
		_finish()
		return
	var player := packed.instantiate() as CharacterBody2D
	root.add_child(player)
	player.set_physics_process(false)
	(player.get_node("Camera2D") as Camera2D).queue_free()
	await process_frame

	var animator: Node = player.get_node("VisualAnimator")
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var blender := player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
	var baseline_foot := _foot_point(player)
	player.velocity = Vector2(145.0, 0.0)
	for _frame in range(14):
		animator.call("_process", FRAME)
	var first_phase := float(animator.get("_stride_phase"))
	for _frame in range(14):
		animator.call("_process", FRAME)
	var second_phase := float(animator.get("_stride_phase"))
	_check(animator.get_animation_state() == "walk", "moving resolves to walk")
	_check(not is_equal_approx(first_phase, second_phase), "walk stride advances with traveled distance")
	_check(animator.get_pose_art_status().contains("temporary procedural stride"), "unillustrated walk stride is reported as temporary")
	_check(not animator.get_state_frame_status().begins_with("approved"), "temporary stride is not labeled an approved frame")
	_check(_visible_foot_anchor_error(player, baseline_foot) <= FLOOR_TOLERANCE, "procedural alternating stride retains the alpha-foot anchor")

	player.set("attack_stage", 1)
	player.set("attack_phase", "active")
	player.set("attack_phase_remaining", 0.08)
	animator.call("_process", FRAME)
	_check(animator.get_animation_state() == "attack1_contact", "basic attack contact takes over the moving pose")
	_check(art.visible and blender.visible and float(animator.call("get_pose_blender_weight")) < 0.5, "PlayerArt and PoseBlender overlap during attack entry")
	_check(float(animator.call("get_pose_blender_weight")) > 0.0, "attack entry begins a gradual display-source blend")
	for _frame in range(12):
		animator.call("_process", FRAME)
	_check(float(animator.call("get_pose_blender_weight")) > 0.99, "approved contact becomes dominant after the blend")
	_check(_visible_foot_anchor_error(player, baseline_foot) <= FLOOR_TOLERANCE, "attack contact keeps both visible pose sources on the alpha-foot anchor")

	player.set("attack_phase", "recovery")
	player.set("attack_phase_remaining", 0.18)
	animator.call("_process", FRAME)
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	animator.call("_process", FRAME)
	_check(blender.visible and art.visible and float(animator.call("get_pose_blender_weight")) < 1.0, "attack exit crossfades back toward the live locomotion pose")
	for _frame in range(12):
		animator.call("_process", FRAME)
	_check(not blender.visible and art.visible and is_zero_approx(float(animator.call("get_pose_blender_weight"))), "attack exit finishes on PlayerArt without a lingering keypose")
	_check(_visible_foot_anchor_error(player, baseline_foot) <= FLOOR_TOLERANCE, "attack-to-walk handoff keeps both visible pose sources on the alpha-foot anchor")

	player.set("attack_stage", 2)
	player.set("attack_phase", "active")
	player.set("attack_phase_remaining", 0.08)
	player.set("facing_direction", Vector2.LEFT)
	player.get_node("VisualRoot").scale.x = -1.0
	animator.call("_process", FRAME)
	_check(animator.get_animation_state() == "attack2_contact", "combo stage two remains active after reversing facing")
	_check(is_equal_approx((player.get_node("VisualRoot") as Node2D).scale.x, -1.0), "attack reversal keeps the latest left-facing mirror")
	player.set("hitstun_remaining", 0.2)
	animator.call("_process", FRAME)
	_check(animator.get_animation_state() == "hit", "hit reaction outranks a combo contact")
	player.set("is_ko", true)
	animator.call("_process", FRAME)
	_check(animator.get_animation_state() == "ko", "KO remains the top animation priority")
	player.set("is_ko", false)
	player.set("hitstun_remaining", 0.0)
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.velocity = Vector2.ZERO
	animator.call("_process", FRAME)
	_check(animator.get_animation_state() == "idle", "idle resumes after interruptions")
	_finish()

func _foot_point(player: CharacterBody2D) -> Vector2:
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	return _sprite_foot_point(art) if art != null and art.texture != null else player.global_position

func _visible_foot_anchor_error(player: CharacterBody2D, expected: Vector2) -> float:
	# Check every rendered source during crossfades; checking PlayerArt alone can
	# pass while the approved PoseBlender silhouette visibly jumps to another foot.
	var visual_root := player.get_node("VisualRoot") as Node2D
	var error := 0.0
	for child in visual_root.find_children("*", "Sprite2D", true, false):
		var sprite := child as Sprite2D
		if sprite == null or not sprite.is_visible_in_tree() or sprite.texture == null or sprite.modulate.a <= 0.001:
			continue
		error = maxf(error, _sprite_foot_point(sprite).distance_to(expected))
	return error

func _sprite_foot_point(sprite: Sprite2D) -> Vector2:
	var bounds := sprite.texture.get_image().get_used_rect()
	var foot_x := float(bounds.position.x) + float(bounds.size.x) * 0.5
	if sprite.flip_h:
		foot_x = float(sprite.texture.get_width()) - foot_x
	var foot := Vector2(foot_x, float(bounds.end.y))
	return sprite.to_global(foot - Vector2(sprite.texture.get_size()) * 0.5)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func _finish() -> void:
	print("M6K walk-to-attack blend smoke: %d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)
