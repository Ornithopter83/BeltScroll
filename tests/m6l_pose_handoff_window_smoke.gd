extends SceneTree
"""Capture every rendered frame across the M6L pose source handoffs."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const FRAME_FALLBACK := 1.0 / 60.0
const SOURCE_BLEND_SECONDS := 0.105
const FOOT_TOLERANCE := 0.08

var _player: CharacterBody2D
var _animator: Node
var _art: Sprite2D
var _blender: PlayerPoseBlender
var _frame_index := 0
var _trace_rows := 0
var _max_alpha_step := 0.0
var _max_foot_error := 0.0
var _max_rotation_step := 0.0
var _max_scale_step := 0.0
var _max_composite_alpha_error := 0.0
var _elapsed_seconds := 0.0
var _blend_start_seconds := -1.0
var _blend_direction := 0
var _blend_durations: Array[float] = []
var _last_art_alpha := -1.0
var _last_blender_alpha := -1.0
var _last_rotation := NAN
var _last_scale := Vector2(NAN, NAN)
var _failures: Array[String] = []
var _state_frames: Dictionary = {}
var _saw_both_layers := false
var _attack_keys: Dictionary = {}
var _saw_hit_key := false
var _saw_walk_return := false
var _saw_direction_flip := false
var _expected_foot := Vector2.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "Godot is rendering an actual Window")
	var animator_source := FileAccess.get_file_as_string("res://scripts/player/player_visual_animator.gd")
	var controller_source := FileAccess.get_file_as_string("res://scripts/player/player_controller.gd")
	_check(animator_source.contains("const POSE_SOURCE_BLEND_DURATION := 0.105"), "pose source handoff keeps the 105 ms duration")
	_check(controller_source.contains("const ACTIVE := [0.105, 0.12, 0.14]"), "gameplay hitbox active windows keep their existing durations")
	_check(animator_source.find('if player.get("is_ko") == true') < animator_source.find('if float(player.get("hit_flash_remaining")) > 0.0') and animator_source.find('if float(player.get("hit_flash_remaining")) > 0.0') < animator_source.find('if skill_phase in ["startup", "active", "recovery"]'), "KO, hit and skill priority order remains intact")
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "player scene loads")
	if packed == null:
		_finish()
		return
	_player = packed.instantiate() as CharacterBody2D
	_player.position = Vector2(640.0, 520.0)
	root.add_child(_player)
	_player.set_physics_process(false)
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.queue_free()
	_animator = _player.get_node("VisualAnimator")
	_art = _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_blender = _player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
	await process_frame
	await RenderingServer.frame_post_draw
	if _art == null or _blender == null:
		_check(false, "both pose source layers are present")
		_finish()
		return
	_expected_foot = _foot_point(_art)
	print("M6L_TRACE|columns=frame,scenario,delta_ms,state,pose_key,art_alpha,blender_alpha,pose_sprite_alphas,pose_effective_alphas,foot_art_x,foot_art_y,foot_pose_x,foot_pose_y,rotation_rad,scale_x,scale_y,state_frame")
	_player.velocity = Vector2(145.0, 0.0)
	await _capture_for("walk_in", 0.18)
	for stage in range(1, 4):
		await _play_attack(stage)
		if stage < 3:
			_set_attack(stage + 1, "startup", 0.035)
			await _capture_for("combo_%d_to_%d" % [stage, stage + 1], 0.035)
	_player.set("attack_stage", 0)
	_player.set("attack_phase", "idle")
	_player.set("attack_phase_remaining", 0.0)
	await _capture_for("combo_walk_return", 0.19)
	_saw_walk_return = _animator.get_animation_state() == "walk"

	# Reverse while moving so the turn and mirror are sampled over consecutive frames.
	_player.set("facing_direction", Vector2.LEFT)
	_player.velocity = Vector2(-145.0, 0.0)
	await _capture_for("direction_reverse", 0.18)
	_saw_direction_flip = (_player.get_node("VisualRoot") as Node2D).scale.x < 0.0
	_check(_saw_direction_flip, "direction reversal reaches the left-facing mirror")

	# Cancel an in-progress attack, then run the real hit-priority and recovery state path.
	_set_attack(2, "active", 0.12)
	await _capture_for("attack_abort", 0.045)
	_player.set("attack_stage", 0)
	_player.set("attack_phase", "idle")
	_player.set("attack_phase_remaining", 0.0)
	await _capture_for("abort_walk_return", 0.14)
	_player.set("hit_flash_remaining", 0.12)
	_player.set("hitstun_remaining", 0.20)
	_player.velocity = Vector2(-95.0, 0.0)
	await _capture_for("hit_stagger", 0.14)
	_player.set("hit_flash_remaining", 0.0)
	_player.set("hitstun_remaining", 0.0)
	await _capture_for("stagger_walk_return", 0.17)

	_check(_saw_both_layers, "the 105 ms handoff renders both source layers during its transition")
	_check(_attack_keys.has("attack1_contact") and _attack_keys.has("attack2_contact") and _attack_keys.has("attack3_contact"), "rendered trace includes all three attack contact pose keys")
	_check(_saw_hit_key, "hit reaction outranks attack and is represented in the trace")
	_check(_saw_walk_return, "walking resumes after the three-hit chain")
	_check(_max_foot_error <= FOOT_TOLERANCE, "every visible source stays on the M6K alpha-foot anchor")
	_check(_max_rotation_step < 0.30, "no one-frame rotation jump exceeds 0.30 radians")
	_check(_max_scale_step < 0.18, "no one-frame scale jump exceeds 0.18")
	_check(_max_alpha_step < 0.60, "no one-frame source opacity cut exceeds 0.60")
	_check(_max_composite_alpha_error < 0.01, "combined visible-layer alpha stays normalized without opacity doubling")
	_check(not _blend_durations.is_empty(), "one or more complete source handoffs were timed")
	var min_blend: float = _blend_durations.min() if not _blend_durations.is_empty() else 0.0
	var max_blend: float = _blend_durations.max() if not _blend_durations.is_empty() else 0.0
	_check(min_blend >= SOURCE_BLEND_SECONDS * 0.65 and max_blend <= SOURCE_BLEND_SECONDS + 0.09, "rendered handoff completion stays within 105 ms plus frame quantization")
	print("M6L_SUMMARY|fail=%d|rendered_frames=%d|blend_count=%d|blend_min_ms=%.2f|blend_max_ms=%.2f|max_alpha_step=%.5f|max_composite_alpha_error=%.5f|max_foot_error_px=%.5f|max_rotation_step_rad=%.5f|max_scale_step=%.5f|visual_signoff=pending" % [_failures.size(), _trace_rows, _blend_durations.size(), min_blend * 1000.0, max_blend * 1000.0, _max_alpha_step, _max_composite_alpha_error, _max_foot_error, _max_rotation_step, _max_scale_step])
	_finish()

func _play_attack(stage: int) -> void:
	var startup: float = [0.075, 0.085, 0.10][stage - 1]
	var active: float = [0.105, 0.12, 0.14][stage - 1]
	var recovery: float = [0.20, 0.22, 0.28][stage - 1]
	_set_attack(stage, "startup", startup)
	await _capture_for("attack%d_startup" % stage, startup)
	_set_attack(stage, "active", active)
	await _capture_for("attack%d_contact" % stage, active)
	_set_attack(stage, "recovery", recovery)
	await _capture_for("attack%d_recovery" % stage, recovery)

func _set_attack(stage: int, phase: String, duration: float) -> void:
	_player.set("attack_stage", stage)
	_player.set("attack_phase", phase)
	_player.set("attack_phase_remaining", duration)

func _capture_for(scenario: String, duration: float) -> void:
	var elapsed := 0.0
	while elapsed < duration:
		await process_frame
		await RenderingServer.frame_post_draw
		var delta := maxf(_player.get_process_delta_time(), FRAME_FALLBACK)
		elapsed += delta
		_record_frame(scenario, delta)
		if _frame_index > 600:
			_check(false, "capture is bounded to 600 actual Window frames")
			return

func _record_frame(scenario: String, delta: float) -> void:
	_frame_index += 1
	_elapsed_seconds += delta
	var state := _animator.get_animation_state() as String
	var pose_key := _blender.get_current_pose_key() as String
	var art_alpha := _art.modulate.a if _art.visible else 0.0
	var blender_alpha := _blender.modulate.a if _blender.visible else 0.0
	var pose_sprites := _blender.find_children("PoseSprite*", "Sprite2D", false, false)
	var pose_alphas := PackedStringArray()
	var pose_effective_alphas := PackedStringArray()
	var foot_art := _foot_point(_art)
	var foot_pose := Vector2.ZERO
	var pose_foot_found := false
	var foot_error := 0.0
	if art_alpha > 0.001:
		foot_error = maxf(foot_error, foot_art.distance_to(_expected_foot))
	for node in pose_sprites:
		var sprite := node as Sprite2D
		if sprite == null:
			continue
		var alpha := sprite.modulate.a if sprite.visible and sprite.is_visible_in_tree() else 0.0
		pose_alphas.append("%.4f" % alpha)
		pose_effective_alphas.append("%.4f" % (alpha * blender_alpha))
		if alpha > 0.001:
			foot_pose = _pose_foot_point(sprite, pose_key)
			pose_foot_found = true
			foot_error = maxf(foot_error, foot_pose.distance_to(_expected_foot))
	if not pose_foot_found:
		foot_pose = foot_art
	_max_foot_error = maxf(_max_foot_error, foot_error)
	var rotation := _art.rotation
	var art_scale := _art.scale
	if is_finite(_last_rotation):
		_max_rotation_step = maxf(_max_rotation_step, absf(rotation - _last_rotation))
		_max_scale_step = maxf(_max_scale_step, art_scale.distance_to(_last_scale))
		_max_alpha_step = maxf(_max_alpha_step, maxf(absf(art_alpha - _last_art_alpha), absf(blender_alpha - _last_blender_alpha)))
	if art_alpha > 0.001 and blender_alpha > 0.001:
		_saw_both_layers = true
	var composite_alpha := art_alpha
	for effective_alpha in pose_effective_alphas:
		composite_alpha += float(effective_alpha)
	_max_composite_alpha_error = maxf(_max_composite_alpha_error, absf(composite_alpha - 1.0))
	var previous_weight := 1.0 - _last_art_alpha if _last_art_alpha >= 0.0 else blender_alpha
	var current_weight := blender_alpha
	var direction := 1 if current_weight > previous_weight + 0.0001 else (-1 if current_weight < previous_weight - 0.0001 else 0)
	if direction != 0 and direction != _blend_direction:
		_blend_direction = direction
		_blend_start_seconds = _elapsed_seconds - delta
	if _blend_direction != 0 and ((current_weight >= 0.999 and _blend_direction > 0) or (current_weight <= 0.001 and _blend_direction < 0)):
		if _blend_start_seconds >= 0.0:
			_blend_durations.append(_elapsed_seconds - _blend_start_seconds)
		_blend_start_seconds = -1.0
		_blend_direction = 0
	_saw_hit_key = _saw_hit_key or state == "hit"
	if pose_key in ["attack1_contact", "attack2_contact", "attack3_contact"]:
		_attack_keys[pose_key] = true
	_state_frames[state] = int(_state_frames.get(state, 0)) + 1
	print("M6L_FRAME|%d|%s|%.3f|%s|%s|%.4f|%.4f|%s|%s|%.3f|%.3f|%.3f|%.3f|%.5f|%.5f|%.5f|%d" % [
		_frame_index, scenario, delta * 1000.0, state, pose_key, art_alpha, blender_alpha,
		";".join(pose_alphas), ";".join(pose_effective_alphas), foot_art.x, foot_art.y, foot_pose.x, foot_pose.y,
		rotation, art_scale.x, art_scale.y, int(_animator.get_state_frame())
	])
	_trace_rows += 1
	_last_art_alpha = art_alpha
	_last_blender_alpha = blender_alpha
	_last_rotation = rotation
	_last_scale = art_scale

func _foot_point(sprite: Sprite2D) -> Vector2:
	if sprite.texture == null:
		return sprite.global_position
	var bounds := sprite.texture.get_image().get_used_rect()
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return sprite.global_position
	var foot_x := float(bounds.position.x) + float(bounds.size.x) * 0.5
	if sprite.flip_h:
		foot_x = float(sprite.texture.get_width()) - foot_x
	var local_foot := Vector2(foot_x, float(bounds.end.y)) - Vector2(sprite.texture.get_size()) * 0.5
	return sprite.to_global(local_foot)

func _pose_foot_point(sprite: Sprite2D, pose_key: String) -> Vector2:
	# Keep the registered support point tied to its own texture while the
	# blender's internal two-sprite fade displays outgoing and incoming poses.
	if sprite.texture != null:
		for action in PlayerPoseBlender.APPROVED_ATTACK_POSES:
			if sprite.texture.resource_path != str(PlayerPoseBlender.APPROVED_ATTACK_POSES[action]):
				continue
			var candidate := _blender.get_ground_candidate(action, "contact")
			if candidate.x >= 0.0 and candidate.y >= 0.0:
				# Sprite2D.to_global applies the sprite scale; keep this point in raw
				# texture pixels so the normalized candidate is transformed only once.
				var candidate_local := candidate * Vector2(sprite.texture.get_size()) - Vector2(sprite.texture.get_size()) * 0.5
				if sprite.flip_h:
					candidate_local.x = -candidate_local.x
				return sprite.to_global(candidate_local)
	return _foot_point(sprite)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
		push_error("FAIL: " + description)

func _finish() -> void:
	if _failures.is_empty():
		quit(0)
	else:
		print("M6L_FAILURES|" + " ; ".join(PackedStringArray(_failures)))
		quit(1)
