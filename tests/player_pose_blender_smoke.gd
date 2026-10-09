extends SceneTree

const BLENDER_SCRIPT := preload("res://scripts/player/player_pose_blender.gd")
const SAFE_IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const FADE := 0.075

var failures: Array[String] = []
var blender: Node2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	blender = BLENDER_SCRIPT.new() as Node2D
	root.add_child(blender)
	await process_frame
	_check(blender.get_child_count() == 2, "standalone blender creates exactly two Sprite2D layers")
	_check(blender.get_current_pose_key() == "idle", "starts on the approved v8 clean still")
	_check(blender.get_displayed_textures().size() == 1, "safe idle is the only initially visible texture")
	_check(not blender.approve_pose_texture("attack1", "active", _fixture(Vector2i(20, 28), Rect2i(4, 5, 9, 19), Color.CORAL)), "rejects unsupported phase names")
	_check(not blender.approve_pose_texture("attack2", "contact", "res://assets/art/player/missing_pose.png"), "rejects missing texture paths")
	_check(not blender.play_pose_sequence("attack1", ["startup", "contact"], 0.05), "rejects sequences that include unapproved keyposes")

	var fixtures: Dictionary = {}
	for attack in range(1, 4):
		for phase_index in range(3):
			var phase: String = ["startup", "contact", "recovery"][phase_index]
			var margin := 2 + attack + phase_index
			var image_size := Vector2i(34 + phase_index * 3, 42 + attack * 2)
			var bounds := Rect2i(margin, 3 + phase_index, 17 + attack, 24 + phase_index)
			var fixture := _fixture(image_size, bounds, Color(0.2 * attack, 0.2 + 0.2 * phase_index, 0.8, 1.0))
			var key := "attack%d_%s" % [attack, phase]
			fixtures[key] = fixture
			_check(blender.approve_pose_texture("attack%d" % attack, phase, fixture), key + " accepts explicitly approved in-memory RGBA fixture")

	for key in ["attack1_startup", "attack1_contact", "attack1_recovery", "attack2_startup", "attack2_contact", "attack2_recovery", "attack3_startup", "attack3_contact", "attack3_recovery"]:
		var parts: PackedStringArray = key.split("_")
		blender.set_pose(parts[0], parts[1])
		_check(blender.get_current_pose_key() == key, key + " selects requested approved state")
		_check(blender.get_displayed_textures().size() <= 2, key + " uses no more than two concurrent sprites")
		blender._process(FADE)
		_check(blender.get_displayed_textures().size() == 1, key + " completes its short crossfade")
		_check(_visible_texture(blender) == fixtures[key], key + " ends on its own approved texture")
		_check(_foot_point(blender).distance_to(blender.common_foot_anchor) <= 0.01, key + " aligns alpha bounds to common foot anchor")

	# A deliberately off-center candidate proves that authored support metadata,
	# rather than the silhouette's lowest alpha pixel, owns this pose's alignment.
	var explicit_candidate := Vector2(0.35, 0.65)
	_check(blender.set_ground_candidate("attack3", "contact", explicit_candidate), "approved pose accepts an explicit support candidate")
	_check(blender.get_ground_candidate("attack3", "contact").is_equal_approx(explicit_candidate), "support candidate is stored independently from the shared combat anchor")
	blender.set_pose("attack3", "contact", 0.0)
	_check(_candidate_point(blender, explicit_candidate).distance_to(blender.common_combat_anchor) <= 0.01, "right-facing explicit support candidate aligns to the common combat anchor")
	blender.set_facing_left(true)
	_check(_candidate_point(blender, explicit_candidate).distance_to(blender.common_combat_anchor) <= 0.01, "left-facing explicit support candidate mirrors without sliding")
	blender.set_facing_left(false)

	var attack_one_sequence: Array[String] = ["startup", "contact", "recovery"]
	_check(blender.play_pose_sequence("attack1", attack_one_sequence, 0.05), "plays a timed sequence made only from explicitly approved keyposes")
	_check(blender.get_sequence_frame_count() == 3 and blender.get_sequence_frame() == 0, "sequence exposes its first frame and frame count")
	blender._process(0.051)
	_check(blender.get_sequence_frame() == 1 and blender.get_current_pose_key() == "attack1_contact", "sequence clock advances to its approved contact frame")
	blender._process(0.051)
	_check(blender.get_sequence_frame() == 2 and blender.get_current_pose_key() == "attack1_recovery", "sequence clock advances to its approved recovery frame")
	blender.set_pose("attack3", "contact")
	_check(blender.get_sequence_frame_count() == 0, "direct pose requests interrupt an active sequence")
	blender._process(FADE)
	var contact_variant := _fixture(Vector2i(46, 52), Rect2i(9, 4, 21, 32), Color.CYAN)
	_check(not blender.register_pose_frame("attack1", "inbetween", contact_variant, 0.04, "temporary transform frame"), "refuses to register temporary transform motion as completed approved art")
	_check(blender.register_pose_frame("attack1", "contact", contact_variant, 0.04, "approved inbetween drawing", "contact variant"), "registers an explicitly reviewed additional frame with its own duration")
	_check(blender.set_timed_pose("attack1", "contact", 0.11, 0.14, 0.0) and _visible_texture(blender) == contact_variant, "combat phase time selects the registered drawing whose duration contains that instant")
	var contact_first := fixtures["attack1_contact"] as Texture2D
	blender.set_pose("attack1", "startup", 0.0)
	blender.set_timed_pose("attack1", "contact", 0.0, 0.14, FADE)
	_check(blender.get_displayed_textures().size() == 1 and _visible_texture(blender) == contact_first, "contact begins on its approved pose without a crossfade hiding the hitbox frame")
	blender.set_timed_pose("attack1", "contact", 0.11, 0.14, FADE)
	_check(blender.get_displayed_textures().size() == 1 and _visible_texture(blender) == contact_variant, "same-phase registered frame changes display directly for their authored interval")
	var registered_sequence: Array[Dictionary] = [
		{"phase": "contact", "frame": 0, "duration": 0.025},
		{"phase": "contact", "frame": 1, "duration": 0.065},
	]
	_check(blender.play_pose_sequence("attack1", registered_sequence), "plays per-frame registered drawings with individual durations")
	blender._process(0.03)
	_check(blender.get_sequence_frame() == 1 and blender.get_displayed_textures().has(contact_variant), "registered sequence starts displaying its actual second texture at the frame boundary")
	_check(is_equal_approx(blender.get_current_frame_duration(), 0.065) and blender.get_current_frame_status() == "approved inbetween drawing", "frame metadata exposes its authored duration and review status")
	blender.interrupt_to_idle()
	blender._process(FADE)

	# Mirror the anchor correction with an asymmetric-alpha procedural texture.
	blender.set_pose("attack1", "contact")
	blender._process(FADE)
	blender.set_facing_left(true)
	_check(_foot_point(blender).distance_to(blender.common_foot_anchor) <= 0.01, "left-facing flip retains the same foot anchor")
	_check((_active_sprite(blender) as Sprite2D).flip_h, "left-facing state flips the active Sprite2D")
	blender.set_facing_left(false)

	# Interrupt halfway through one transition; the next request reuses the dominant
	# currently visible sprite as its source and still settles on exactly one target.
	blender.set_pose("attack2", "startup")
	blender._process(FADE * 0.4)
	_check(blender.get_displayed_textures().size() == 2, "crossfade exposes both sprites during transition")
	blender.set_pose("attack3", "contact")
	blender._process(FADE * 0.2)
	_check(blender.get_displayed_textures().size() == 2, "interrupted transition is reduced to a two-sprite handoff")
	blender._process(FADE)
	_check(_visible_texture(blender) == fixtures["attack3_contact"], "interrupted transition settles on the latest requested pose")
	blender.set_pose("attack2", "startup")
	blender._process(FADE)
	blender.set_pose("attack2", "contact", 0.10)
	blender._process(0.025)
	_check(blender.get_current_pose_key() == "attack2_contact" and is_equal_approx(blender.get_transition_progress(), 0.25), "stage two contact uses its longer timed blend from the approved v8 still")
	_check(blender.get_pose_art_status().contains("approved contact"), "contact metadata identifies the approved contact key art")
	blender._process(0.075)
	_check(blender.get_transition_progress() == 1.0 and _visible_texture(blender) == fixtures["attack2_contact"], "stage two transition completes at its configured duration")

	# A pause inherited from the SceneTree must freeze the in-flight fade.
	blender.set_pose("attack1", "recovery")
	var alphas_before_pause := _alphas(blender)
	paused = true
	await process_frame
	_check(_alphas(blender) == alphas_before_pause, "SceneTree pause freezes blend alpha")
	paused = false
	await process_frame
	_check(_alphas(blender) != alphas_before_pause, "blend resumes after unpause")
	blender._process(FADE)

	blender.set_ko(true)
	_check(blender.get_current_pose_key() == "idle" and blender.get_displayed_textures().size() == 1, "KO immediately returns to safe idle")
	blender.clear_ko()
	blender.set_pose("attack3", "recovery")
	_check(blender.get_current_pose_key() == "attack3_recovery", "explicitly cleared KO allows a later approved request")
	blender._process(FADE)
	blender.set_pose("attack4", "startup")
	_check(blender.get_current_pose_key() == "idle", "unapproved attack state falls back to v8 clean")
	blender._process(FADE)
	_check(_visible_texture(blender) == load(SAFE_IDLE_PATH), "fallback texture is the approved v8 clean asset")
	_check(blender.get_displayed_textures().size() == 1, "fallback never leaves an unapproved texture visible")

	blender.queue_free()
	await process_frame
	_finish()

func _fixture(size: Vector2i, bounds: Rect2i, color: Color) -> Texture2D:
	var image := Image.create(size.x, size.y, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _active_sprite(node: Node) -> Sprite2D:
	for child in node.get_children():
		if child is Sprite2D and child.visible and child.modulate.a > 0.99:
			return child as Sprite2D
	return null

func _visible_texture(node: Node) -> Texture2D:
	var sprite := _active_sprite(node)
	return sprite.texture if sprite != null else null

func _foot_point(node: Node) -> Vector2:
	var sprite := _active_sprite(node)
	if sprite == null:
		return Vector2(INF, INF)
	var bounds := sprite.texture.get_image().get_used_rect()
	var foot_x := float(bounds.position.x) + float(bounds.size.x) * 0.5
	if sprite.flip_h:
		foot_x = float(sprite.texture.get_width()) - foot_x
	var foot_from_center := (Vector2(foot_x, float(bounds.end.y)) - Vector2(sprite.texture.get_size()) * 0.5) * sprite.scale
	return sprite.position + foot_from_center

func _candidate_point(node: Node, candidate: Vector2) -> Vector2:
	var sprite := _active_sprite(node)
	if sprite == null:
		return Vector2(INF, INF)
	var point_x := candidate.x * float(sprite.texture.get_width())
	if sprite.flip_h:
		point_x = float(sprite.texture.get_width()) - point_x
	var point_from_center := (Vector2(point_x, candidate.y * float(sprite.texture.get_height())) - Vector2(sprite.texture.get_size()) * 0.5) * sprite.scale
	return sprite.position + point_from_center

func _alphas(node: Node) -> Array[float]:
	var result: Array[float] = []
	for child in node.get_children():
		if child is Sprite2D:
			result.append((child as Sprite2D).modulate.a)
	return result

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("player_pose_blender_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("player_pose_blender_smoke: " + failure)
	push_error("player_pose_blender_smoke: %d check(s) failed" % failures.size())
	quit(1)
