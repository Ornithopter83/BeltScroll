extends SceneTree
"""Window smoke comparing sequential full-body gameplay motion samples."""

const PREVIEW_SCENE := "res://scenes/review/m6o_walk_four_phase_preview.tscn"
const PLAYER_PATH := "Gameplay/YSortActors/Player"
const CONTACT_PATHS := {
	1: "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	2: "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
	3: "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
}
const STEP := 1.0 / 60.0

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_check(DisplayServer.get_name() != "headless", "gameplay motion smoke uses a rendered Window")
	var packed := load(PREVIEW_SCENE) as PackedScene
	_check(packed != null, "real gameplay preview scene loads")
	if packed == null:
		_finish()
		return
	var preview := packed.instantiate()
	root.add_child(preview)
	await process_frame
	var player := preview.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	_check(player != null, "motion samples use the gameplay Player")
	if player == null:
		_finish()
		return
	player.set_physics_process(false)
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.queue_free()
	var animator: Node = player.get_node("VisualAnimator")
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var blender: Node = player.get_node("VisualRoot/PoseBlender")
	var walk_motion: Node = player.get_node("WalkMotion")
	# Manual sampling must not also advance with variable Window render deltas.
	animator.set_process(false)
	walk_motion.set_process(false)
	blender.set_process(false)
	var walk_sprite := walk_motion.call("get_candidate_sprite") as Sprite2D
	player.velocity = Vector2(280.0, 0.0)
	player.set("skill_phase", "idle")
	player.set("attack_phase", "idle")
	await _render_animator_frame(animator)
	walk_motion.call("_process", STEP)
	var left_support: Vector2 = walk_motion.call("get_support_anchor_local")
	var contact_scale: Vector2 = walk_sprite.scale
	walk_motion.call("_process", 0.25)
	await _render_animator_frame(animator)
	var passing_support: Vector2 = walk_motion.call("get_support_anchor_local")
	_check(walk_motion.call("get_current_phase") == "passing", "four-phase gait advances from left contact into left passing")
	_check(passing_support.distance_to(left_support) < 0.01, "left foot stays fixed at its own contact anchor during passing")
	_check(float(walk_motion.call("get_current_pelvis_lift")) > 0.0 and walk_sprite.scale.y > contact_scale.y, "passing phase raises the pelvis while retaining its support anchor")
	walk_motion.call("_process", 0.19)
	await _render_animator_frame(animator)
	var right_support: Vector2 = walk_motion.call("get_support_anchor_local")
	_check(walk_motion.call("get_current_phase") == "right_contact" and right_support.distance_to(left_support) > 10.0, "contact alternates to the separate right support anchor")
	var duration_at_reference := float(walk_motion.call("get_current_frame_duration"))
	player.velocity = Vector2(560.0, 0.0)
	_check(is_equal_approx(float(walk_motion.call("get_current_frame_duration")), duration_at_reference * 0.5), "gait cadence follows doubled travel speed")
	player.velocity = Vector2(280.0, 0.0)
	walk_motion.set_process(false)
	walk_motion.call("_set_active", false)
	await _render_animator_frame(animator)
	_check(_visible(art), "main gameplay stride renders PlayerArt when the DEBUG candidate is inactive")
	var planted_foot_before := _alpha_foot_global(art)
	var main_walk_samples: Array[Dictionary] = []
	for frame_index in range(8):
		await _render_animator_frame(animator)
		main_walk_samples.append(_body_sample(animator, art, blender))
	_check(_has_sequential_motion(main_walk_samples, 1.0), "main four-phase stride changes the visible body over consecutive Window frames")
	_check(_alpha_foot_global(art).distance_to(planted_foot_before) < 0.1, "main stride pelvis lift keeps the alpha-foot anchor planted")
	player.set("attack_stage", 1)
	player.set("attack_phase", "startup")
	player.set("attack_phase_remaining", 0.075)
	await _render_animator_frame(animator)
	_check(animator.get_animation_state() == "attack1_startup", "attack startup takes state ownership from walk")
	_check(not _visible(walk_sprite), "debug walk source is hidden during attack startup")
	_check(str(blender.call("get_current_pose_key")) == "attack1_contact", "stage 1 keeps its own approved contact original during preparation")
	_check_single_body(player, "attack1 startup")
	var attack_motion: Array[Dictionary] = []
	for sample in [
		{"phase": "startup", "remaining": 0.065},
		{"phase": "startup", "remaining": 0.035},
		{"phase": "startup", "remaining": 0.005},
		{"phase": "active", "remaining": 0.09},
		{"phase": "active", "remaining": 0.045},
		{"phase": "active", "remaining": 0.005},
		{"phase": "combo_hold", "remaining": 0.12},
		{"phase": "combo_hold", "remaining": 0.06},
		{"phase": "recovery", "remaining": 0.18},
		{"phase": "recovery", "remaining": 0.09},
		{"phase": "recovery", "remaining": 0.01},
	]:
		player.set("attack_phase", sample["phase"])
		player.set("attack_phase_remaining", sample["remaining"])
		await _render_animator_frame(animator)
		var expected_state := "attack1_startup" if sample["phase"] == "startup" else ("attack1_recovery" if sample["phase"] == "recovery" else "attack1_contact")
		_check(animator.get_animation_state() == expected_state, "animation state follows the previous-to-next %s transition" % sample["phase"])
		_check(str(blender.call("get_current_pose_key")) == "attack1_contact", "attack phases never fall back to the idle still")
		_check_single_body(player, "attack1 " + str(sample["phase"]))
		attack_motion.append(_body_sample(animator, art, blender))
	_check(_has_sequential_motion(attack_motion, 3.0), "attack startup, contact, hold, and recovery change the visible body across consecutive Window frames")

	var stage_paths := {}
	for stage in [1, 2, 3]:
		player.set("attack_stage", stage)
		player.set("attack_phase", "combo_hold")
		player.set("attack_phase_remaining", 0.10)
		await _render_animator_frame(animator)
		var key := str(blender.call("get_current_pose_key"))
		_check(key == "attack%d_contact" % stage, "combo_hold retains stage %d contact drawing" % stage)
		_check(not key.begins_with("idle"), "combo_hold never selects the full-body idle still")
		_check_single_body(player, "stage %d combo_hold" % stage)
		stage_paths[stage] = str(animator.call("get_displayed_texture_path"))
		_check(stage_paths[stage] == CONTACT_PATHS[stage], "stage %d uses its existing approved contact image" % stage)
	_check(stage_paths.size() == 3 and stage_paths[1] != stage_paths[2] and stage_paths[2] != stage_paths[3] and stage_paths[1] != stage_paths[3], "basic combo uses three different existing approved contact originals")
	var linked_motion: Array[Dictionary] = []
	for stage in [2, 3]:
		player.set("attack_stage", stage)
		for sample in [
			{"phase": "startup", "remaining": 0.08 if stage == 2 else 0.095},
			{"phase": "startup", "remaining": 0.02},
			{"phase": "active", "remaining": 0.11 if stage == 2 else 0.13},
			{"phase": "active", "remaining": 0.01},
			{"phase": "recovery", "remaining": 0.18 if stage == 2 else 0.25},
			{"phase": "recovery", "remaining": 0.01},
		]:
			player.set("attack_phase", sample["phase"])
			player.set("attack_phase_remaining", sample["remaining"])
			await _render_animator_frame(animator)
			_check(str(blender.call("get_current_pose_key")) == "attack%d_contact" % stage, "stage %d linked motion stays on its own contact original" % stage)
			_check_single_body(player, "stage %d %s" % [stage, sample["phase"]])
			linked_motion.append(_body_sample(animator, art, blender))
	_check(_has_sequential_motion(linked_motion, 3.0), "stage 2 and 3 linking includes preparation, impact, and return body motion")

	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	var skill_samples := {}
	for skill in [1, 2]:
		player.set("skill_id", skill)
		player.set("skill_phase", "startup")
		player.set("skill_phase_remaining", 0.16 if skill == 1 else 0.22)
		await _render_animator_frame(animator)
		var sequence: Array[Dictionary] = []
		for sample in [
			{"phase": "startup", "remaining": 0.03 if skill == 1 else 0.04},
			{"phase": "active", "remaining": 0.10 if skill == 1 else 0.16},
			{"phase": "active", "remaining": 0.02},
			{"phase": "recovery", "remaining": 0.28 if skill == 1 else 0.36},
			{"phase": "recovery", "remaining": 0.04},
		]:
			player.set("skill_phase", sample["phase"])
			player.set("skill_phase_remaining", sample["remaining"])
			await _render_animator_frame(animator)
			var expected_state := "skill%d_%s" % [skill, "contact" if sample["phase"] == "active" else sample["phase"]]
			_check(animator.get_animation_state() == expected_state, "skill %d state follows %s" % [skill, sample["phase"]])
			_check_single_body(player, "skill %d %s" % [skill, sample["phase"]])
			sequence.append(_body_sample(animator, art, blender))
		_check(_has_sequential_motion(sequence, 5.0), "skill %d has sequential body translation and pose motion" % skill)
		skill_samples[skill] = sequence[2]
	_check(_samples_differ(skill_samples[1], skill_samples[2], 8.0), "Num4 rush and Num5 backfist body motion differ beyond their effects")

	player.set("skill_phase", "idle")
	player.velocity = Vector2.ZERO
	await _render_animator_frame(animator)
	_check(animator.get_animation_state() == "idle", "gameplay returns to idle after combat motion")
	await RenderingServer.frame_post_draw
	var frame_image := root.get_texture().get_image()
	_check(frame_image != null and not frame_image.is_empty(), "Window produced a rendered gameplay frame")
	_finish()

func _render_animator_frame(animator: Node) -> void:
	animator.call("_process", STEP)
	await process_frame
	await RenderingServer.frame_post_draw

func _body_sample(animator: Node, art: Sprite2D, blender: Node) -> Dictionary:
	var sprite := animator.call("_get_visible_combat_sprite") as Sprite2D
	if sprite == null:
		sprite = art
	return {
		"path": str(animator.call("get_displayed_texture_path")),
		"position": sprite.global_position,
		"rotation": sprite.global_rotation,
		"scale": sprite.global_scale,
		"art_position": art.global_position,
		"key": str(blender.call("get_current_pose_key")),
	}

func _alpha_foot_global(art: Sprite2D) -> Vector2:
	if art == null or art.texture == null:
		return Vector2.ZERO
	var bounds := art.texture.get_image().get_used_rect()
	var foot := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y))
	return art.to_global(foot - Vector2(art.texture.get_size()) * 0.5)

func _has_sequential_motion(samples: Array[Dictionary], minimum_shift: float) -> bool:
	var changed := 0
	for index in range(1, samples.size()):
		if _samples_differ(samples[index - 1], samples[index], minimum_shift):
			changed += 1
	return changed >= 3

func _samples_differ(first: Dictionary, second: Dictionary, minimum_shift: float) -> bool:
	var first_position: Vector2 = first["position"]
	var second_position: Vector2 = second["position"]
	var first_art_position: Vector2 = first["art_position"]
	var second_art_position: Vector2 = second["art_position"]
	var first_scale: Vector2 = first["scale"]
	var second_scale: Vector2 = second["scale"]
	return (
		first_position.distance_to(second_position) >= minimum_shift
		or first_art_position.distance_to(second_art_position) >= minimum_shift
		or absf(float(first["rotation"]) - float(second["rotation"])) >= 0.035
		or first_scale.distance_to(second_scale) >= 0.02
		or str(first["path"]) != str(second["path"])
	)

func _single_body_count(player: CharacterBody2D) -> int:
	var count := 0
	var sources: Array[Sprite2D] = [player.get_node("VisualRoot/PlayerArt") as Sprite2D]
	var walk_sprite := player.get_node("WalkMotion").call("get_candidate_sprite") as Sprite2D
	sources.append(walk_sprite)
	for node in player.get_node("VisualRoot/PoseBlender").find_children("PoseSprite*", "Sprite2D", false, false):
		sources.append(node as Sprite2D)
	for sprite in sources:
		if _visible(sprite):
			count += 1
	return count

func _check_single_body(player: CharacterBody2D, label: String) -> void:
	_check(_single_body_count(player) == 1, "%s shows one full-body source" % label)

func _visible(sprite: Sprite2D) -> bool:
	if sprite == null or sprite.texture == null:
		return false
	var mesh := sprite.get_node_or_null("ArticulatedBody") as Polygon2D
	var source: CanvasItem = mesh if mesh != null and mesh.visible else sprite
	var alpha := source.self_modulate.a
	var cursor: Node = source
	while cursor is CanvasItem:
		var item := cursor as CanvasItem
		if not item.visible:
			return false
		alpha *= item.modulate.a
		cursor = item.get_parent()
	return alpha > 0.001

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
		push_error("FAIL: " + description)

func _finish() -> void:
	if _failures.is_empty():
		print("M6S_GAMEPLAY_MOTION_SUMMARY|fail=0|window=rendered|motion=sequentially-compared|approval=pending")
		quit(0)
		return
	for failure in _failures:
		push_error("m6s_gameplay_motion_window_smoke: " + failure)
	print("M6S_GAMEPLAY_MOTION_SUMMARY|fail=%d|approval=pending" % _failures.size())
	quit(1)
