extends SceneTree
"""Window-capable smoke for isolated walk candidates and combat handoff."""

const PREVIEW_SCENE := "res://scenes/review/m6o_walk_four_phase_preview.tscn"
const PLAYER_PATH := "Gameplay/YSortActors/Player"
const LEFT_CONTACT := "res://assets/art/player/elven_fighter_walk_opposite_stride_v1_candidate_1254x1254.png"
const LEFT_PASSING := "res://assets/art/player/elven_fighter_walk_passing_v1_candidate_1254x1254.png"
const RIGHT_CONTACT := "res://assets/art/player/elven_fighter_walk_right_contact_v1_candidate_1254x1254.png"
const RIGHT_PASSING_STEM := "walk_right_passing"
const STEP := 1.0 / 60.0

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1280, 720)
	_check(DisplayServer.get_name() != "headless", "preview smoke is running with a Window renderer")
	var packed := load(PREVIEW_SCENE) as PackedScene
	_check(packed != null, "isolated M6O preview scene loads")
	if packed == null:
		_finish()
		return
	var preview := packed.instantiate()
	root.add_child(preview)
	await process_frame
	var player := preview.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	_check(player != null, "preview uses the real gameplay Player")
	if player == null:
		_finish()
		return
	player.set_physics_process(false)
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.queue_free()
	await process_frame
	var animator: Node = player.get_node("VisualAnimator")
	var motion: Node2D = player.get_node("WalkMotion") as Node2D
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_check(player.get_node_or_null("VisualRoot/DebugLeftSupportAnchor") != null and player.get_node_or_null("VisualRoot/DebugRightSupportAnchor") != null, "Window preview shows separate left and right support markers")
	var has_right_passing := _has_right_passing_resource()
	_check(OS.is_debug_build() and motion.get_available_phase_names().size() == (4 if has_right_passing else 3), "available independent originals run in DEBUG with four phases when the optional drawing exists")
	_check(FileAccess.file_exists(LEFT_CONTACT) and FileAccess.file_exists(LEFT_PASSING) and FileAccess.file_exists(RIGHT_CONTACT), "left contact, passing, and right contact PNGs are present")
	_check(has_right_passing == motion.get_available_phase_names().has("right_passing"), "optional right passing resource is included only when available")
	_check(motion.get_cycle_status().contains("FOUR-PHASE") if has_right_passing else motion.get_cycle_status().contains("missing right-foot passing"), "candidate status reports the resource-backed phase count")

	player.velocity = Vector2(280.0, 0.0)
	animator.call("_process", STEP)
	motion.call("_process", STEP)
	_check(motion.get_current_phase() == "left_contact" and motion.get_current_frame_path() == LEFT_CONTACT, "left contact is displayed first from its independent PNG")
	_check(not art.visible, "DEBUG candidate display owns the walk state")
	var left_anchor: Vector2 = motion.get_support_anchor_local()
	motion.call("_process", 0.25)
	_check(motion.get_current_phase() == "passing" and motion.get_current_frame_path() == LEFT_PASSING, "left passing is an independent second original")
	_check(motion.get_support_anchor_local().distance_to(left_anchor) < 0.01, "same left support stays on its own anchor through passing")
	motion.call("_process", 0.19)
	_check(motion.get_current_phase() == "right_contact" and motion.get_current_frame_path() == RIGHT_CONTACT, "right contact is played as the third original")
	_check(motion.get_current_support_side() == "right", "support side changes from left to right at contact")
	var right_anchor: Vector2 = motion.get_support_anchor_local()
	_check(right_anchor.distance_to(left_anchor) > 10.0, "right support uses a distinct anchor instead of the left anchor")
	_check(is_equal_approx(float(motion.call("get_current_frame_duration")), 0.24), "contact timing is 0.24 seconds at reference speed")
	motion.call("_process", 0.25)
	if has_right_passing:
		var right_passing_path: String = motion.get_current_frame_path()
		_check(motion.get_current_phase() == "right_passing" and right_passing_path.get_file().to_lower().contains(RIGHT_PASSING_STEM), "right passing uses its own acquired PNG as the fourth frame")
		_check(motion.get_support_anchor_local().distance_to(right_anchor) < 0.01, "right support anchor stays stable across right contact-to-passing")
	else:
		_check(motion.get_current_phase() == "left_contact", "three-phase fallback loops to left contact without fabricating right passing")
	var duration_before_speedup := float(motion.call("get_current_frame_duration"))
	player.velocity = Vector2(560.0, 0.0)
	_check(is_equal_approx(float(motion.call("get_current_frame_duration")), duration_before_speedup * 0.5), "cadence scales with doubled travel speed")

	player.set("attack_stage", 1)
	player.set("attack_phase", "active")
	player.set("attack_phase_remaining", 0.08)
	animator.call("_process", STEP)
	motion.call("_process", STEP)
	_check(animator.get_animation_state() == "attack1_contact", "combo contact takes ownership from walking")
	_check(motion.get_current_phase() == "inactive" and art.visible, "walk overlay yields its display on attack handoff")
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.velocity = Vector2(280.0, 0.0)
	animator.call("_process", STEP)
	motion.call("_process", STEP)
	_check(animator.get_animation_state() == "walk" and motion.get_current_phase() == "left_contact", "walk resumes cleanly after combo handoff")

	await RenderingServer.frame_post_draw
	var frame_image := root.get_texture().get_image()
	_check(frame_image != null and not frame_image.is_empty(), "preview renders a readable Window frame")
	_finish()

func _has_right_passing_resource() -> bool:
	var directory := DirAccess.open("res://assets/art/player")
	if directory == null:
		return false
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		var exists := not directory.current_is_dir() and filename.to_lower().ends_with(".png") and filename.to_lower().contains(RIGHT_PASSING_STEM)
		if exists:
			directory.list_dir_end()
			return true
		filename = directory.get_next()
	directory.list_dir_end()
	return false

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
		push_error("FAIL: " + description)

func _finish() -> void:
	if _failures.is_empty():
		print("M6O_WALK_SUMMARY|fail=0|window=verified|approval=pending")
		quit(0)
		return
	for failure in _failures:
		push_error("m6o_walk_four_phase_window_smoke: " + failure)
	print("M6O_WALK_SUMMARY|fail=%d|approval=pending" % _failures.size())
	quit(1)
