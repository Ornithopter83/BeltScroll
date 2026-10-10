extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const ART_SCALE := Vector2(0.4469274, 0.4469274)
const POSE_CELL := Vector2(640.0, 380.0)
const FLOOR_TOLERANCE := 0.08
const POSE_NAMES := ["idle", "walk", "idle baseline", "jump rise", "jump fall", "landing", "1 startup", "1 active", "2 active", "3 startup", "3 active", "3 recovery", "hit", "KO"]
const POSE_COUNT := 14

var failures: Array[String] = []
var players: Array[CharacterBody2D] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("player_visual_animator_smoke requires a Window Viewport")
		quit(1)
		return
	root.size = CAPTURE_SIZE
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "Player scene loads with the independent VisualAnimator")
	if packed == null:
		_finish()
		return
	var canvas := Node2D.new()
	canvas.name = "MotionStateCapture"
	root.add_child(canvas)
	var capture_camera := Camera2D.new()
	capture_camera.position = CAPTURE_SIZE * 0.5
	capture_camera.enabled = true
	canvas.add_child(capture_camera)
	capture_camera.make_current()
	var captions := CanvasLayer.new()
	root.add_child(captions)
	for index in range(POSE_COUNT):
		var label := Label.new()
		label.text = POSE_NAMES[index]
		label.position = Vector2(220.0 + float(index % 3) * POSE_CELL.x, 188.0 + float(index / 3) * POSE_CELL.y)
		label.size = Vector2(180.0, 32.0)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 22)
		label.add_theme_color_override("font_color", Color(0.9, 0.92, 0.96, 1.0))
		captions.add_child(label)

	var poses: Array[CharacterBody2D] = []
	var animator_nodes: Array[Node] = []
	for index in range(POSE_COUNT):
		var player := packed.instantiate() as CharacterBody2D
		canvas.add_child(player)
		player.set_physics_process(false)
		player.position = Vector2(320.0 + float(index % 3) * POSE_CELL.x, 260.0 + float(index / 3) * POSE_CELL.y)
		(player.get_node("Camera2D") as Camera2D).queue_free()
		(player.get_node("GroundShadow") as Polygon2D).visible = false
		(player.get_node("VisualRoot/AttackFlash") as Polygon2D).visible = false
		var player_art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
		var pose_blender := player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
		_check(player_art.scale.is_equal_approx(ART_SCALE) and pose_blender.sprite_scale.is_equal_approx(ART_SCALE), "player and PoseBlender use the approved art at approximately three times scale")
		var body_capsule := (player.get_node("CollisionShape2D") as CollisionShape2D).shape as CapsuleShape2D
		_check(body_capsule != null and is_equal_approx(body_capsule.radius, 16.0) and is_equal_approx(body_capsule.height, 40.0), "player collision body widens while retaining its ground edge")
		var expected_hit_radii := [13.0, 14.0, 15.0]
		for stage in range(1, 4):
			var hitbox_shape := (player.get_node("Hitboxes/Hitbox%d/CollisionShape2D" % stage) as CollisionShape2D).shape as CircleShape2D
			_check(hitbox_shape != null and is_equal_approx(hitbox_shape.radius, expected_hit_radii[stage - 1]) and hitbox_shape.radius <= 15.0, "player stage %d attack judgment area stays fist-sized" % stage)
		poses.append(player)
		animator_nodes.append(player.get_node("VisualAnimator"))
		players.append(player)
	await process_frame
	for index in range(POSE_COUNT):
		_configure_pose(poses[index], index)
		var animator := animator_nodes[index]
		if index == 5:
			animator.set("_was_jumping", true)
		var pose_frames := 3 if index == 5 else 36
		for _frame in range(pose_frames):
			animator.call("_process", 1.0 / 60.0)
		_check(poses[index].position.y == 260.0 + float(index / 3) * POSE_CELL.y, POSE_NAMES[index] + " leaves Player root position unchanged")
		_check(_foot_point(poses[index]).distance_to(_baseline_foot(poses[index])) <= FLOOR_TOLERANCE, POSE_NAMES[index] + " keeps the alpha foot anchor stable")
		var pose_blender := poses[index].get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
		if pose_blender.visible:
			_check(_blender_keeps_common_foot(pose_blender), POSE_NAMES[index] + " keeps PoseBlender crossfade sprites on the common foot anchor")
		if index > 0 and index != 2:
			var pose_art := poses[index].get_node("VisualRoot/PlayerArt") as Sprite2D
			var pose_is_distinct := absf(pose_art.rotation) > 0.008 or pose_art.scale.distance_to(ART_SCALE) > 0.0015
			_check(pose_is_distinct, POSE_NAMES[index] + " differs visibly from the neutral still pose")
			_check(_alpha_bounds_fit_cell(pose_art), POSE_NAMES[index] + " enlarged art remains inside its capture cell")
		_check(animator.get_animation_state() == _expected_state(index), POSE_NAMES[index] + " resolves to a timed animation state")
		_check(animator.get_state_frame_count() >= 1 and animator.get_state_frame() >= 0, POSE_NAMES[index] + " exposes its current frame in the state sequence")
		if index == 13:
			_check(animator.get_state_frame_count() == 3, "KO exposes three timed temporary final-down beats")
		_check(animator.is_current_pose_temporary() == (index not in [7, 8, 10]), POSE_NAMES[index] + " identifies temporary poses separately from approved attack contact art")
		_check(animator.get_state_frame_duration() > 0.0 and not animator.get_displayed_texture_path().is_empty(), POSE_NAMES[index] + " exposes frame timing and the texture actually selected for display")
		if index in [6, 9, 11]:
			_check(animator.get_state_frame_status().contains("temporary"), POSE_NAMES[index] + " labels missing pose drawings as temporary transforms")

	# Compare the 2 -> 3 contact handoff in both facings. The visual reference
	# and sprite anchors may animate, while the Player root and live hitbox stay fixed.
	var right_chain := packed.instantiate() as CharacterBody2D
	var left_chain := packed.instantiate() as CharacterBody2D
	canvas.add_child(right_chain)
	canvas.add_child(left_chain)
	right_chain.set_physics_process(false)
	left_chain.set_physics_process(false)
	(right_chain.get_node("Camera2D") as Camera2D).queue_free()
	(left_chain.get_node("Camera2D") as Camera2D).queue_free()
	await process_frame
	var right_chain_animator: Node = right_chain.get_node("VisualAnimator")
	var left_chain_animator: Node = left_chain.get_node("VisualAnimator")
	var chain_samples: Array[float] = []
	for chain_case in [
		{"player": right_chain, "animator": right_chain_animator, "sign": 1.0},
		{"player": left_chain, "animator": left_chain_animator, "sign": -1.0},
	]:
		var chain_player: CharacterBody2D = chain_case["player"]
		var chain_animator: Node = chain_case["animator"]
		var facing_sign: float = chain_case["sign"]
		var chain_root := chain_player.get_node("VisualRoot") as Node2D
		var chain_art := chain_player.get_node("VisualRoot/PlayerArt") as Sprite2D
		var chain_blender := chain_player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
		var root_position := chain_player.global_position
		var hitbox := chain_player.get_node("Hitboxes/Hitbox3") as Area2D
		var hitbox_position := hitbox.global_position
		chain_player.set("facing_direction", Vector2(facing_sign, 0.0))
		chain_root.scale.x = facing_sign
		_set_attack(chain_player, 2, "active", 0.03)
		chain_animator.call("_process", 1.0 / 60.0)
		var rotation_before := chain_art.rotation
		_set_attack(chain_player, 3, "active", 0.12)
		for _frame in range(7):
			chain_animator.call("_process", 1.0 / 60.0)
			chain_root.scale.x = facing_sign
			_check(_blender_keeps_common_foot(chain_blender), ("right" if facing_sign > 0.0 else "left") + " 2-to-3 crossfade keeps both registered support candidates aligned")
		_check(chain_player.global_position.is_equal_approx(root_position), ("right" if facing_sign > 0.0 else "left") + " 2-to-3 handoff leaves the physical Player position unchanged")
		_check(hitbox.global_position.is_equal_approx(hitbox_position), ("right" if facing_sign > 0.0 else "left") + " 2-to-3 handoff leaves the real hitbox position unchanged")
		_check(_foot_point(chain_player).distance_to(_baseline_foot(chain_player)) <= FLOOR_TOLERANCE, ("right" if facing_sign > 0.0 else "left") + " 2-to-3 handoff has no grounded-foot slide")
		chain_samples.append(chain_art.rotation - rotation_before)
	_check(chain_samples.size() == 2 and chain_samples[0] * chain_samples[1] < 0.0, "2-to-3 torso rotation is mirrored across right-facing and left-facing playback")

	var idle := poses[0]
	var idle_art := idle.get_node("VisualRoot/PlayerArt") as Sprite2D
	var idle_transform := idle_art.transform
	var idle_foot := _foot_point(idle)
	var idle_animator := animator_nodes[0]
	idle.set("attack_phase", "idle")
	idle.set("is_ko", false)
	idle.set("hitstun_remaining", 0.0)
	idle.set("hit_flash_remaining", 0.0)
	idle.velocity = Vector2.ZERO
	for _frame in range(90):
		idle_animator.call("_process", 1.0 / 60.0)
	_check(idle_art.transform.origin.distance_to(idle_transform.origin) < 1.5 and absf(idle_art.rotation) < 0.01 and idle_art.scale.distance_to(ART_SCALE) < 0.002, "idle transform remains neutral and restrained")
	_check(_foot_point(idle).distance_to(idle_foot) <= FLOOR_TOLERANCE, "idle return retains the same foot anchor")
	_check(idle_animator.get_state_elapsed() > 0.0, "idle state clock advances while its pose loops")

	var turn_player := packed.instantiate() as CharacterBody2D
	canvas.add_child(turn_player)
	turn_player.set_physics_process(false)
	(turn_player.get_node("Camera2D") as Camera2D).queue_free()
	var turn_animator: Node = turn_player.get_node("VisualAnimator")
	await process_frame
	var turn_root := turn_player.get_node("VisualRoot") as Node2D
	var turn_art := turn_player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var turn_foot := _foot_point(turn_player)
	turn_player.set("facing_direction", Vector2.LEFT)
	for _frame in range(3):
		turn_root.scale.x = 1.0 # Mirror the controller's requested facing write each physics tick.
		turn_animator.call("_process", 1.0 / 60.0)
	_check(turn_animator.call("is_turning") and is_equal_approx(turn_root.scale.x, 1.0), "standing turn holds the original facing during its anticipation")
	_check(turn_art.scale.y > ART_SCALE.y * 1.01 and turn_art.scale.x < ART_SCALE.x * 0.995, "standing turn shows a procedural windup and body compression")
	for _frame in range(2):
		turn_root.scale.x = 1.0
		turn_animator.call("_process", 1.0 / 60.0)
	_check(is_equal_approx(turn_root.scale.x, -1.0), "standing turn applies VisualRoot mirroring once after the compression")
	turn_player.velocity = Vector2(180.0, 0.0)
	turn_player.set("facing_direction", Vector2.RIGHT)
	for _frame in range(10):
		turn_root.scale.x = -1.0
		turn_animator.call("_process", 1.0 / 60.0)
	_check(not turn_animator.call("is_turning") and is_equal_approx(turn_root.scale.x, 1.0), "moving turn settles to the latest direction without changing velocity")
	_check(_foot_point(turn_player).distance_to(turn_foot) <= FLOOR_TOLERANCE, "standing and moving turn keep the alpha foot anchor fixed")
	turn_player.set("facing_direction", Vector2.LEFT)
	for _frame in range(8):
		turn_root.scale.x = 1.0
		turn_animator.call("_process", 1.0 / 60.0)
	turn_player.set("facing_direction", Vector2.RIGHT)
	for _frame in range(2):
		turn_root.scale.x = -1.0
		turn_animator.call("_process", 1.0 / 60.0)
	turn_player.set("facing_direction", Vector2.LEFT)
	for _frame in range(10):
		turn_root.scale.x = 1.0
		turn_animator.call("_process", 1.0 / 60.0)
	_check(not turn_animator.call("is_turning") and is_equal_approx(turn_root.scale.x, -1.0), "rapid reverse input restarts the turn and settles on the latest facing")
	turn_player.velocity = Vector2.ZERO
	turn_player.set("facing_direction", Vector2.RIGHT)
	turn_animator.call("_process", 1.0 / 60.0)
	turn_player.set("hitstun_remaining", 0.2)
	turn_animator.call("_process", 1.0 / 60.0)
	_check(turn_animator.get_animation_state() == "hit" and not turn_animator.call("is_turning"), "hitstun interrupts the procedural turn")
	turn_player.set("hitstun_remaining", 0.0)
	turn_player.set("facing_direction", Vector2.LEFT)
	turn_animator.call("_process", 1.0 / 60.0)
	turn_player.set("attack_stage", 1)
	turn_player.set("attack_phase", "startup")
	turn_player.set("attack_phase_remaining", 0.075)
	turn_animator.call("_process", 1.0 / 60.0)
	_check(turn_animator.get_animation_state() == "attack1_startup" and not turn_animator.call("is_turning"), "attack startup interrupts the procedural turn")
	turn_player.set("attack_phase", "idle")
	turn_player.set("attack_stage", 0)
	turn_player.set("facing_direction", Vector2.RIGHT)
	turn_animator.call("_process", 1.0 / 60.0)
	turn_player.set("skill_id", 1)
	turn_player.set("skill_phase", "startup")
	turn_player.set("skill_phase_remaining", 0.16)
	turn_animator.call("_process", 1.0 / 60.0)
	_check(turn_animator.get_animation_state() == "skill1_startup" and not turn_animator.call("is_turning"), "skill startup interrupts the procedural turn")
	turn_player.set("skill_phase", "idle")
	turn_player.set("skill_id", 0)
	turn_player.set("is_jumping", true)
	turn_player.set("jump_vertical_velocity", -100.0)
	turn_player.set("facing_direction", Vector2.LEFT)
	turn_animator.call("_process", 1.0 / 60.0)
	_check(turn_animator.get_animation_state() == "jump_rise" and not turn_animator.call("is_turning"), "jump rise interrupts the procedural turn")
	turn_player.set("is_ko", true)
	turn_animator.call("_process", 1.0 / 60.0)
	_check(turn_animator.get_animation_state() == "ko" and not turn_animator.call("is_turning"), "KO interrupts the procedural turn")
	var down_foot := _baseline_foot(turn_player)
	var down_art := turn_player.get_node("VisualRoot/PlayerArt") as Sprite2D
	for _frame in range(8):
		turn_animator.call("_process", 1.0 / 60.0)
	var stagger_rotation := down_art.rotation
	for _frame in range(20):
		turn_animator.call("_process", 1.0 / 60.0)
	var collapse_rotation := down_art.rotation
	for _frame in range(40):
		turn_animator.call("_process", 1.0 / 60.0)
	var final_down_rotation := down_art.rotation
	_check(absf(collapse_rotation) > absf(stagger_rotation) + 0.30 and absf(final_down_rotation) > absf(collapse_rotation) + 0.04, "KO progresses from stagger through collapse into final-down")
	_check(absf(final_down_rotation) > 1.0 and _foot_point(turn_player).distance_to(down_foot) <= FLOOR_TOLERANCE, "final-down settles sideways while preserving the alpha-foot anchor")

	var third_start := poses[9].get_node("VisualRoot/PlayerArt") as Sprite2D
	var third_active := poses[10].get_node("VisualRoot/PlayerArt") as Sprite2D
	var second_active := poses[8].get_node("VisualRoot/PlayerArt") as Sprite2D
	var stage_one_active := poses[7].get_node("VisualRoot/PlayerArt") as Sprite2D
	var authored_scale := ART_SCALE
	_check(absf(third_active.rotation) > absf(second_active.rotation) + 0.08 and absf(third_active.scale.y / authored_scale.y - 1.0) < 0.04, "third combo contact has a stronger torso turn with restrained scale change")
	_check(absf(second_active.rotation) > absf(stage_one_active.rotation) + 0.04, "second combo strike reads stronger than the first")
	_check(third_start.scale.y > third_active.scale.y and absf(third_active.rotation) > absf(third_start.rotation), "third combo startup and active poses are distinct")
	_check(animator_nodes[8].get_state_frame_count() == 5 and animator_nodes[8].get_pose_art_status().contains("approved contact"), "stage two contact exposes timed temporary transform motion while retaining approved art status")
	_check(absf(stage_one_active.rotation) < absf(second_active.rotation) and absf(second_active.rotation) < absf(third_active.rotation), "all three approved contact poses have distinct increasing turn emphasis")
	var stage_two := poses[8]
	var stage_two_animator := animator_nodes[8]
	_set_attack(stage_two, 2, "active", 0.12)
	stage_two_animator.call("_process", 1.0 / 60.0)
	_check(stage_two_animator.get_state_frame_label() == "inbetween" and stage_two_animator.get_state_frame_status().contains("temporary inbetween"), "stage two labels its gradual turn as a temporary inbetween while keeping contact art provenance clear")
	_set_attack(stage_two, 2, "active", 0.12)
	stage_two_animator.call("_process", 1.0 / 60.0)
	var early_turn := (stage_two.get_node("VisualRoot/PlayerArt") as Sprite2D).rotation
	_set_attack(stage_two, 2, "active", 0.06)
	for _frame in range(3):
		stage_two_animator.call("_process", 1.0 / 60.0)
	var late_turn := (stage_two.get_node("VisualRoot/PlayerArt") as Sprite2D).rotation
	_check(absf(early_turn - late_turn) > 0.025, "stage two turns progressively from the v8-ready alignment toward the approved contact")
	_check(_foot_point(stage_two).distance_to(_baseline_foot(stage_two)) <= FLOOR_TOLERANCE, "stage two turn keeps its alpha-foot anchor fixed")
	_check(stage_two_animator.get_state_elapsed() > 0.05 and stage_two_animator.get_state_elapsed() < 0.07, "stage two phase clock follows real attack_phase_remaining")
	var skill_dash := packed.instantiate() as CharacterBody2D
	canvas.add_child(skill_dash)
	skill_dash.set_physics_process(false)
	(skill_dash.get_node("Camera2D") as Camera2D).queue_free()
	var dash_animator := skill_dash.get_node("VisualAnimator")
	await process_frame
	skill_dash.set("skill_id", 1)
	skill_dash.set("skill_phase", "startup")
	skill_dash.set("skill_phase_remaining", 0.08)
	dash_animator.call("_process", 1.0 / 60.0)
	var dash_art := skill_dash.get_node("VisualRoot/PlayerArt") as Sprite2D
	_check(dash_art.rotation > 0.0, "Num4 preparation leans toward the right-facing dash direction")
	skill_dash.set("skill_phase", "active")
	skill_dash.set("skill_phase_remaining", 0.06)
	for _frame in range(8):
		dash_animator.call("_process", 1.0 / 60.0)
	_check(dash_animator.get_animation_state() == "skill1_contact" and is_equal_approx(dash_animator.get_state_elapsed(), 0.06), "Num4 contact clock follows the actual skill_phase_remaining")
	_check(dash_animator.get_state_frame_count() == 6 and dash_animator.get_pose_art_status().contains("temporary procedural"), "Num4 exposes six explicitly temporary procedural motion frames")
	_check(dash_art.rotation > 0.0, "Num4 acceleration continues to lean toward its facing direction")
	var dash_contact_rotation := dash_art.rotation
	skill_dash.set("facing_direction", Vector2.LEFT)
	(skill_dash.get_node("VisualRoot") as Node2D).scale.x = -1.0
	for _frame in range(8):
		dash_animator.call("_process", 1.0 / 60.0)
	_check(dash_art.rotation < 0.0, "Num4 forward lean mirrors when facing left")
	skill_dash.set("facing_direction", Vector2.RIGHT)
	(skill_dash.get_node("VisualRoot") as Node2D).scale.x = 1.0
	skill_dash.set("skill_phase", "recovery")
	skill_dash.set("skill_phase_remaining", 0.21)
	for _frame in range(10):
		dash_animator.call("_process", 1.0 / 60.0)
	_check(dash_animator.get_animation_state() == "skill1_recovery" and dash_animator.get_state_elapsed() > 0.20 and absf(dash_art.rotation - dash_contact_rotation) > 0.04, "Num4 recoil and return pose follow its recovery clock")
	_check(_foot_point(skill_dash).distance_to(_baseline_foot(skill_dash)) <= FLOOR_TOLERANCE, "Num4 procedural lean keeps the alpha foot anchor fixed")
	skill_dash.set("skill_phase", "active")
	skill_dash.set("skill_phase_remaining", 0.06)
	skill_dash.set("attack_recoil_remaining", 0.08)
	for _frame in range(8):
		dash_animator.call("_process", 1.0 / 60.0)
	_check(dash_art.rotation < dash_contact_rotation - 0.10, "Num4 impact recoil counters its forward acceleration pose")
	_check(_foot_point(skill_dash).distance_to(_baseline_foot(skill_dash)) <= FLOOR_TOLERANCE, "Num4 impact recoil preserves the alpha foot anchor")
	skill_dash.set("skill_phase", "idle")
	skill_dash.set("skill_id", 0)
	skill_dash.set("attack_recoil_remaining", 0.0)
	dash_animator.call("_process", 1.0 / 60.0)
	_check(not (skill_dash.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender).visible, "skill exit hides attack keypose art and returns to procedural base art")
	var skill_spin := packed.instantiate() as CharacterBody2D
	canvas.add_child(skill_spin)
	skill_spin.set_physics_process(false)
	(skill_spin.get_node("Camera2D") as Camera2D).queue_free()
	var spin_animator := skill_spin.get_node("VisualAnimator")
	await process_frame
	skill_spin.set("skill_id", 2)
	skill_spin.set("skill_phase", "active")
	skill_spin.set("skill_phase_remaining", 0.09)
	spin_animator.call("_process", 1.0 / 60.0)
	var spin_art := skill_spin.get_node("VisualRoot/PlayerArt") as Sprite2D
	var spin_start_rotation := spin_art.rotation
	skill_spin.set("skill_phase_remaining", 0.03)
	for _frame in range(8):
		spin_animator.call("_process", 1.0 / 60.0)
	_check(spin_animator.get_animation_state() == "skill2_contact" and absf(spin_art.rotation - spin_start_rotation) > 0.20, "Num5 circular contact visibly rotates through a distinct pose")
	_check(spin_animator.get_state_elapsed() > 0.14 and spin_animator.get_state_elapsed() < 0.16, "Num5 contact frame time follows the real active timer")
	_check(_foot_point(skill_spin).distance_to(_baseline_foot(skill_spin)) <= FLOOR_TOLERANCE, "Num5 procedural rotation keeps the alpha foot anchor fixed")
	skill_spin.set("skill_phase", "recovery")
	skill_spin.set("skill_phase_remaining", 0.275)
	spin_animator.call("_process", 1.0 / 60.0)
	_check(spin_animator.get_animation_state() == "skill2_recovery" and is_equal_approx(spin_animator.get_state_elapsed(), 0.275), "Num5 unwind clock follows its actual recovery timer")
	_check(spin_animator.get_pose_art_status().contains("temporary procedural"), "Num5 recovery is explicitly marked as temporary animation")
	skill_spin.set("is_ko", true)
	spin_animator.call("_process", 1.0 / 60.0)
	_check(spin_animator.get_animation_state() == "ko", "KO interrupts the Num5 spin pose")
	skill_spin.set("is_ko", false)
	skill_spin.set("skill_phase", "idle")
	skill_spin.set("skill_id", 0)
	for _frame in range(90):
		spin_animator.call("_process", 1.0 / 60.0)
	_check(absf(spin_art.rotation) < 0.01 and spin_art.scale.distance_to(authored_scale) < 0.002, "Num5 KO exit returns to the neutral sprite transform")
	_check(_foot_point(skill_spin).distance_to(_baseline_foot(skill_spin)) <= FLOOR_TOLERANCE, "Num5 KO return retains its alpha foot anchor")
	var left_player := poses[10]
	var left_animator := animator_nodes[10]
	var right_player := packed.instantiate() as CharacterBody2D
	canvas.add_child(right_player)
	right_player.set_physics_process(false)
	(right_player.get_node("Camera2D") as Camera2D).queue_free()
	var right_animator := right_player.get_node("VisualAnimator")
	await process_frame
	left_player.get_node("VisualRoot").scale.x = -1.0
	right_player.get_node("VisualRoot").scale.x = 1.0
	left_player.set("facing_direction", Vector2.LEFT)
	right_player.set("facing_direction", Vector2.RIGHT)
	left_player.set("attack_stage", 3)
	left_player.set("attack_phase", "active")
	right_player.set("attack_stage", 3)
	right_player.set("attack_phase", "active")
	for _frame in range(36):
		left_animator.call("_process", 1.0 / 60.0)
		right_animator.call("_process", 1.0 / 60.0)
	var left_rotation := (left_player.get_node("VisualRoot/PlayerArt") as Sprite2D).rotation
	var right_rotation := (right_player.get_node("VisualRoot/PlayerArt") as Sprite2D).rotation
	_check(left_rotation * right_rotation < 0.0 and absf(absf(left_rotation) - absf(right_rotation)) < 0.01, "left and right facing mirror the stage three strike")
	_check(_foot_point(left_player).distance_to(_baseline_foot(left_player)) <= FLOOR_TOLERANCE and _foot_point(right_player).distance_to(_baseline_foot(right_player)) <= FLOOR_TOLERANCE, "both mirrored poses keep the foot anchor stable")
	_check(_alpha_bounds_fit_cell(left_player.get_node("VisualRoot/PlayerArt") as Sprite2D) and _alpha_bounds_fit_cell(right_player.get_node("VisualRoot/PlayerArt") as Sprite2D), "mirrored enlarged art remains within capture bounds")
	left_player.get_node("VisualRoot").scale.x = 1.0
	left_player.set("facing_direction", Vector2.RIGHT)
	left_player.set("attack_phase", "idle")
	left_player.set("attack_stage", 0)
	left_player.velocity = Vector2.ZERO
	var recovery_foot := _foot_point(left_player)
	for _frame in range(90):
		left_animator.call("_process", 1.0 / 60.0)
	var recovered_art := left_player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_check(absf(recovered_art.rotation) < 0.01 and recovered_art.scale.distance_to(authored_scale) < 0.002, "stage three recovery transitions smoothly back to neutral")
	_check(_foot_point(left_player).distance_to(recovery_foot) <= FLOOR_TOLERANCE, "recovery return keeps its original foot anchor")
	left_player.set("is_ko", true)
	left_player.set("attack_phase", "startup")
	left_player.set("attack_stage", 1)
	left_player.set("attack_phase_remaining", 0.075)
	left_animator.call("_process", 1.0 / 60.0)
	_check(left_animator.get_animation_state() == "ko", "KO preempts an in-flight attack state")
	left_player.set("is_ko", false)
	left_player.set("attack_phase", "startup")
	left_player.set("attack_phase_remaining", 0.075)
	left_animator.call("_process", 1.0 / 60.0)
	_check(left_animator.get_animation_state() == "attack1_startup" and left_animator.get_state_elapsed() == 0.0, "rapid state changes reset the active state clock")

	# Synthetic approved frames prove the live animator follows movement, attack,
	# and skill clocks without relying on any unreviewed project artwork.
	var playback_player := packed.instantiate() as CharacterBody2D
	canvas.add_child(playback_player)
	playback_player.set_physics_process(false)
	(playback_player.get_node("Camera2D") as Camera2D).queue_free()
	var playback_animator: Node = playback_player.get_node("VisualAnimator")
	var playback_blender: PlayerPoseBlender = playback_player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
	await process_frame
	var synthetic_frame_a := _synthetic_frame(Color(0.95, 0.2, 0.2, 1.0))
	var synthetic_frame_b := _synthetic_frame(Color(0.2, 0.9, 0.3, 1.0))
	_check(playback_blender.register_pose_frame("attack1", "contact", synthetic_frame_a, 0.0525, "approved synthetic test frame", "contact A", Vector2(0.5, 0.9375), true), "synthetic attack frame A registers explicitly")
	_check(playback_blender.register_pose_frame("attack1", "contact", synthetic_frame_b, 0.0525, "approved synthetic test frame", "contact B", Vector2(0.5, 0.9375)), "synthetic attack frame B registers explicitly")
	playback_player.set("attack_stage", 1)
	playback_player.set("attack_phase", "active")
	playback_player.set("attack_phase_remaining", 0.105)
	playback_animator.call("_process", 0.0)
	_check(playback_blender.get_registered_frame_count("attack1", "contact") == 2, "synthetic attack contact frames register as an ordered pair")
	_check(playback_blender.visible and playback_blender.get_current_registered_frame_label() == "contact A" and playback_blender.get_displayed_textures().size() == 1, "attack hitbox start immediately displays the first contact drawing")
	playback_player.set("attack_phase_remaining", 0.0525)
	# Advance the real visual handoff clock while the controller clock is at the
	# authored frame boundary; a zero-delta call cannot make PoseBlender dominant.
	playback_animator.call("_process", 0.06)
	_check(playback_animator.get_art_frame_label() == "contact B" and playback_blender.get_displayed_textures().size() == 1, "attack contact advances to its second synthetic drawing at the controller clock boundary")
	_check(_blender_keeps_common_foot(playback_blender), "both synthetic attack frames retain their planted-foot anchor")
	playback_player.set("attack_phase", "idle")
	playback_player.set("attack_stage", 0)
	playback_player.velocity = Vector2(280.0, 0.0)
	playback_blender.register_pose_frame("run", "stride", synthetic_frame_a, 0.05, "approved synthetic test frame", "stride A", Vector2(0.5, 0.9375), true)
	playback_blender.register_pose_frame("run", "stride", synthetic_frame_b, 0.05, "approved synthetic test frame", "stride B", Vector2(0.5, 0.9375))
	playback_animator.call("_process", 0.0)
	playback_animator.call("_process", 0.06)
	_check(playback_animator.get_animation_state() == "walk" and playback_animator.get_art_frame_label() == "stride B", "registered movement frames advance in order on the live stride clock")
	playback_player.velocity = Vector2.ZERO
	playback_animator.call("_process", 0.0)
	playback_player.set("skill_id", 1)
	playback_player.set("skill_phase", "active")
	playback_player.set("skill_phase_remaining", 0.12)
	playback_blender.register_pose_frame("skill1", "contact", synthetic_frame_a, 0.06, "approved synthetic test frame", "skill A", Vector2(0.5, 0.9375), true)
	playback_blender.register_pose_frame("skill1", "contact", synthetic_frame_b, 0.06, "approved synthetic test frame", "skill B", Vector2(0.5, 0.9375))
	playback_animator.call("_process", 0.0)
	playback_player.set("skill_phase_remaining", 0.06)
	playback_animator.call("_process", 0.0)
	_check(playback_animator.get_animation_state() == "skill1_contact" and playback_animator.get_art_frame_label() == "skill B", "skill contact advances on the skill controller's active timer")
	playback_player.set("skill_phase", "idle")
	playback_player.set("skill_id", 0)
	for _frame in range(8):
		playback_animator.call("_process", 0.015)
	var restored_art := playback_player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_check(not playback_blender.visible and restored_art.visible and absf(playback_blender.get_external_blend_weight() - 1.0) < 0.001 and restored_art.modulate.a > 0.999, "skill interruption atomically discards the registered full-body pose and restores procedural art")

	await process_frame
	await RenderingServer.frame_post_draw
	var rendered := root.get_texture().get_image()
	_check(rendered != null and not rendered.is_empty() and rendered.get_size() == CAPTURE_SIZE, "Window Viewport renders the enlarged pose comparison at the configured size")
	if rendered != null and not rendered.is_empty() and rendered.get_size() == CAPTURE_SIZE:
		print("player-motion-capture: Window Viewport rendered the enlarged state comparison")
	_check(not FileAccess.get_file_as_string(PLAYER_SCENE).contains("SpriteFrames"), "approved still artwork is not represented as completed frame animation")
	canvas.queue_free()
	captions.queue_free()
	await process_frame
	_finish()

func _configure_pose(player: CharacterBody2D, index: int) -> void:
	player.velocity = Vector2.ZERO
	player.set("is_ko", false)
	player.set("is_jumping", false)
	player.set("jump_vertical_velocity", 0.0)
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.set("attack_phase_remaining", 0.0)
	player.set("hitstun_remaining", 0.0)
	player.set("hit_flash_remaining", 0.0)
	var visual_root := player.get_node("VisualRoot") as Node2D
	visual_root.scale = Vector2.ONE
	match index:
		1:
			player.velocity = Vector2(280.0, 0.0)
		2:
			pass
		3:
			player.set("is_jumping", true)
			player.set("jump_vertical_velocity", -220.0)
		4:
			player.set("is_jumping", true)
			player.set("jump_vertical_velocity", 160.0)
		5:
			pass
		6:
			_set_attack(player, 1, "startup", 0.02)
		7:
			_set_attack(player, 1, "active", 0.05)
		8:
			_set_attack(player, 2, "active", 0.06)
		9:
			_set_attack(player, 3, "startup", 0.025)
		10:
			_set_attack(player, 3, "active", 0.07)
		11:
			_set_attack(player, 3, "recovery", 0.14)
		12:
			player.velocity = Vector2(-80.0, 0.0)
			player.set("hitstun_remaining", 0.2)
			player.set("hit_flash_remaining", 0.08)
		13:
			player.set("is_ko", true)

func _set_attack(player: CharacterBody2D, stage: int, phase: String, remaining: float) -> void:
	player.set("attack_stage", stage)
	player.set("attack_phase", phase)
	player.set("attack_phase_remaining", remaining)

func _expected_state(index: int) -> String:
	match index:
		0, 2:
			return "idle"
		1:
			return "walk"
		3:
			return "jump_rise"
		4:
			return "jump_fall"
		5:
			return "landing"
		6:
			return "attack1_startup"
		7:
			return "attack1_contact"
		8:
			return "attack2_contact"
		9:
			return "attack3_startup"
		10:
			return "attack3_contact"
		11:
			return "attack3_recovery"
		12:
			return "hit"
		13:
			return "ko"
	return "idle"

func _baseline_foot(player: CharacterBody2D) -> Vector2:
	var sprite := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var bounds := sprite.texture.get_image().get_used_rect()
	var size := Vector2(sprite.texture.get_size())
	var centered_foot := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y)) - size * 0.5
	return Vector2(0.0, -62.0) + centered_foot * Vector2(0.1489758, 0.1489758)

func _synthetic_frame(color: Color) -> Texture2D:
	var image := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	image.fill(Color(0.0, 0.0, 0.0, 0.0))
	for y in range(5, 45):
		for x in range(7, 25):
			image.set_pixel(x, y, color)
	return ImageTexture.create_from_image(image)

func _alpha_bounds_fit_cell(sprite: Sprite2D) -> bool:
	var bounds := sprite.texture.get_image().get_used_rect()
	var scaled_size := Vector2(bounds.size) * sprite.scale.abs()
	return bounds.position.x >= 0 and bounds.position.y >= 0 \
		and bounds.end.x <= sprite.texture.get_width() and bounds.end.y <= sprite.texture.get_height() \
		and scaled_size.x < float(CAPTURE_SIZE.x - 64) and scaled_size.y < float(CAPTURE_SIZE.y - 64)

func _blender_keeps_common_foot(blender: PlayerPoseBlender) -> bool:
	for child in blender.get_children():
		var sprite := child as Sprite2D
		if sprite == null or not sprite.visible or sprite.texture == null:
			continue
		var candidate := Vector2(-1.0, -1.0)
		match sprite.texture.resource_path.get_file():
			"elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png":
				candidate = Vector2(0.85, 0.91)
			"elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png":
				candidate = Vector2(0.86, 0.91)
			"elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png":
				candidate = Vector2(0.80, 0.91)
		var foot_from_center: Vector2
		if candidate.x >= 0.0:
			var candidate_x := candidate.x * float(sprite.texture.get_width())
			if sprite.flip_h:
				candidate_x = float(sprite.texture.get_width()) - candidate_x
			foot_from_center = (Vector2(candidate_x, candidate.y * float(sprite.texture.get_height())) - Vector2(sprite.texture.get_size()) * 0.5) * sprite.scale
		else:
			var bounds := sprite.texture.get_image().get_used_rect()
			var foot_x := float(bounds.position.x) + float(bounds.size.x) * 0.5
			if sprite.flip_h:
				foot_x = float(sprite.texture.get_width()) - foot_x
			foot_from_center = (Vector2(foot_x, float(bounds.end.y)) - Vector2(sprite.texture.get_size()) * 0.5) * sprite.scale
		if (sprite.position + foot_from_center - blender.common_combat_anchor).length() > FLOOR_TOLERANCE:
			return false
	return true

func _foot_point(player: CharacterBody2D) -> Vector2:
	var sprite := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var bounds := sprite.texture.get_image().get_used_rect()
	var size := Vector2(sprite.texture.get_size())
	var local_foot := (Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y)) - size * 0.5) * sprite.scale
	return sprite.position + local_foot.rotated(sprite.rotation)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("player_visual_animator_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("player_visual_animator_smoke: " + failure)
	push_error("player_visual_animator_smoke: %d check(s) failed" % failures.size())
	quit(1)
