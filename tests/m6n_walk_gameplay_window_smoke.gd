extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CONTACT_PATH := "res://assets/art/player/elven_fighter_walk_opposite_stride_v1_candidate_1254x1254.png"
const PASSING_PATH := "res://assets/art/player/elven_fighter_walk_passing_v1_candidate_1254x1254.png"
const RIGHT_CONTACT_PATH := "res://assets/art/player/elven_fighter_walk_right_contact_v1_candidate_1254x1254.png"
const FRAME := 1.0 / 60.0

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "Player scene loads")
	if packed == null:
		_finish()
		return
	var player := packed.instantiate() as CharacterBody2D
	root.add_child(player)
	player.set_physics_process(false)
	(player.get_node("Camera2D") as Camera2D).queue_free()
	await process_frame
	await process_frame

	var animator: Node = player.get_node("VisualAnimator")
	var walk_motion: Node2D = player.get_node("WalkMotion") as Node2D
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var visual_root := player.get_node("VisualRoot") as Node2D
	_check(OS.is_debug_build(), "candidate overlay runs only in DEBUG test execution")
	_check(FileAccess.file_exists(CONTACT_PATH) and FileAccess.file_exists(PASSING_PATH), "left contact and passing source drawings exist")
	_check(FileAccess.file_exists(RIGHT_CONTACT_PATH), "available right-contact candidate resource is present")
	_check(walk_motion.get_cycle_status().contains("missing right-foot passing"), "missing next phase blocks normal two-step cycle PASS")
	_check(walk_motion.get_available_phase_names().has("right_contact"), "existing right-contact candidate is included only in the DEBUG sequence")

	player.velocity = Vector2(280.0, 0.0)
	animator.call("_process", FRAME)
	walk_motion.call("_process", 0.001)
	_check(animator.get_animation_state() == "walk", "existing VisualAnimator walk state drives candidate display")
	_check(walk_motion.get_current_phase() == "left_contact", "left contact starts the independent display sequence")
	_check(walk_motion.get_current_frame_path() == CONTACT_PATH, "left contact uses its own complete source drawing")
	_check(not art.visible, "DEBUG contact frame takes display ownership during walk")
	var anchor_before: Vector2 = walk_motion.call("get_support_anchor_local")
	var frame_duration := float(walk_motion.call("get_current_frame_duration"))
	_check(is_equal_approx(frame_duration, 0.24), "contact cadence uses reference-speed duration")
	walk_motion.call("_process", 0.25)
	_check(walk_motion.get_current_phase() == "passing", "passing is an independent displayed frame")
	_check(walk_motion.get_current_frame_path() == PASSING_PATH, "passing frame is loaded from its own candidate texture")
	var anchor_local: Vector2 = walk_motion.call("get_support_anchor_local")
	_check(anchor_local.distance_to(anchor_before) <= 0.001, "left-support anchor remains stable across contact-to-passing frame swap")

	player.velocity = Vector2(560.0, 0.0)
	_check(is_equal_approx(float(walk_motion.call("get_current_frame_duration")), 0.09), "frame cadence scales with movement speed")
	walk_motion.call("_process", 0.10)
	_check(walk_motion.get_current_phase() == "right_contact", "existing right-contact resource plays as its own frame")
	_check(walk_motion.get_current_frame_path() == RIGHT_CONTACT_PATH, "right contact uses the optional candidate texture")
	_check((walk_motion.get_node("DebugWalkPhaseStatus") as Label).text.contains("RIGHT CONTACT"), "on-character phase marker names the displayed right contact")
	_check(walk_motion.get_cycle_status().contains("missing right-foot passing"), "right contact does not fill the missing opposite passing phase")
	player.set("facing_direction", Vector2.LEFT)
	for _frame in range(10):
		animator.call("_process", FRAME)
		walk_motion.call("_process", FRAME)
	_check(visual_root.scale.x < 0.0, "direction reversal is retained by existing Player visual root")
	_check(walk_motion.call("get_support_anchor_local").distance_to(anchor_local) <= 0.05, "support anchor remains stable through direction reversal")

	player.set("attack_stage", 1)
	player.set("attack_phase", "active")
	player.set("attack_phase_remaining", 0.08)
	animator.call("_process", FRAME)
	walk_motion.call("_process", FRAME)
	_check(animator.get_animation_state() == "attack1_contact", "basic attack takes over walk state")
	_check(walk_motion.get_current_phase() == "inactive" and art.visible, "walk display yields immediately to attack art")
	_check((player.get_node("VisualRoot/PoseBlender") as Node2D).visible, "existing attack pose display remains active after handoff")

	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.set("facing_direction", Vector2.RIGHT)
	player.velocity = Vector2(280.0, 0.0)
	animator.call("_process", FRAME)
	walk_motion.call("_process", FRAME)
	_check(animator.get_animation_state() == "walk" and walk_motion.get_current_phase() == "left_contact", "walking display resumes after attack")
	_check(not art.visible, "walk candidate frame receives display ownership again")
	_check(walk_motion.get_cycle_status().contains("INCOMPLETE"), "cycle remains explicitly incomplete after return")
	_finish()

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
		push_error("FAIL: " + message)

func _finish() -> void:
	print("M6N walk gameplay window smoke: %d failure(s)" % failures.size())
	quit(1 if not failures.is_empty() else 0)
