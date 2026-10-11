extends SceneTree
"""Artifact smoke for the real-Window M6V animation review packet."""

const IMAGE_PATH := "res://assets/art/review/m6v_animation_quality_contact_sheet.png"
const REPORT_PATH := "res://docs/review/m6v_animation_visual_acceptance_matrix.md"
const TOOL_PATH := "res://tools/capture_m6v_animation_comparison_window.gd"
const GAME_SCENE := "res://scenes/game/main.tscn"
const PLAYER_PATH := "YSortActors/Player"

var _failures: Array[String] = []
var _live_player: CharacterBody2D
var _live_animator: Node
var _last_live_position := Vector2.ZERO
var _has_last_live_position := false
var _max_live_frame_step := 0.0
var _max_live_hand_error := 0.0
var _max_live_support_residual := 0.0
var _max_live_body_sources := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "smoke itself runs under a Window renderer")
	_check(FileAccess.file_exists(IMAGE_PATH), "contact sheet image exists")
	_check(FileAccess.file_exists(REPORT_PATH), "visual acceptance matrix exists")
	_check(FileAccess.file_exists(TOOL_PATH), "continuous main-scene capture tool exists")
	if FileAccess.file_exists(IMAGE_PATH):
		var image := Image.new()
		_check(image.load(ProjectSettings.globalize_path(IMAGE_PATH)) == OK and image.get_width() >= 1280 and image.get_height() >= 720, "contact sheet is a readable multi-card PNG")
	if FileAccess.file_exists(REPORT_PATH):
		var report := FileAccess.get_file_as_string(REPORT_PATH)
		for required in ["scenes/game/main.tscn", "window frame", "발 anchor", "손 anchor", "F10 박스", "UNVERIFIED", "육안", "관절 왜곡", "체형·얼굴·복장 일관성", "프레임 끊김", "주먹과 판정"]:
			_check(report.to_lower().contains(required.to_lower()), "review report records %s" % required)
		for required in ["FORCED STATE · PHYSICS OFF", "REAL INPUT · PHYSICS ON", "world_displacement_px", "support_residual_px", "hand_hitbox_error_px", "실루엣 중복", "UNVERIFIED"]:
			_check(report.to_lower().contains(required.to_lower()), "report separates forced and production-input evidence and records %s" % required)
		for phase in ["실입력·이동 중 기준", "실입력·이동 해제 후", "실입력·J1 회복 후", "실입력·Num4 회복 후", "실입력·Num5 회복 후", "실입력·피격 회복 후"]:
			_check(report.contains(phase), "production input before/after trace covers %s" % phase)
		for phase in ["실입력·상태전환·walk", "실입력·상태전환·attack1_startup", "실입력·상태전환·attack1_contact", "실입력·상태전환·attack1_recovery", "실입력·상태전환·skill1_startup", "실입력·상태전환·skill1_contact", "실입력·상태전환·skill1_recovery", "실입력·상태전환·skill2_startup", "실입력·상태전환·skill2_contact", "실입력·상태전환·skill2_recovery", "실입력·상태전환·hit"]:
			_check(report.contains(phase), "actual input trace records the production transition %s" % phase)
		for phase in ["4위상 보행", "정지·우향", "점프 상승", "점프 하강", "착지", "피격", "KO·정착", "J1 startup", "J1 active", "J1 combo_hold", "J1 recovery", "J2 startup", "J2 active", "J2 combo_hold", "J2 recovery", "J3 startup", "J3 active", "J3 recovery", "Num4 startup", "Num4 active", "Num4 recovery", "Num5 startup", "Num5 active", "Num5 recovery"]:
			_check(report.contains(phase), "review report covers %s" % phase)
	if FileAccess.file_exists(TOOL_PATH):
		var source := FileAccess.get_file_as_string(TOOL_PATH)
		_check(source.contains("res://scenes/game/main.tscn"), "capture tool targets the production game scene")
		_check(source.contains("RenderingServer.frame_post_draw"), "capture tool samples consecutive rendered Window frames")
		_check(source.contains("get_fist_contact_global") and source.contains("_f10_box"), "capture tool samples fist anchor and live hitbox geometry")
		_check(source.contains("Input.action_press") and source.contains("set_physics_process(true)"), "capture tool includes a real InputMap/Player physics path")
	await _exercise_live_input()
	_finish()

func _exercise_live_input() -> void:
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 60
	root.size = Vector2i(1280, 720)
	var packed := load(GAME_SCENE) as PackedScene
	_check(packed != null, "live-input smoke loads the production main scene")
	if packed == null:
		return
	var game := packed.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	await _ticks(2)
	var player := game.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	_check(player != null and player.is_physics_processing(), "production Player physics stays enabled during input capture")
	if player == null:
		return
	for actor in game.get_node("YSortActors").get_children():
		if actor != player and actor is CharacterBody2D:
			actor.set_physics_process(false)
			actor.set_process(false)
	var animator: Node = player.get_node("VisualAnimator")
	_live_player = player
	_live_animator = animator
	_last_live_position = player.global_position
	_has_last_live_position = true
	RenderingServer.frame_post_draw.connect(_sample_live_frame)
	var start_x := player.global_position.x
	var maximum_step := 0.0
	var fist_error := 0.0
	Input.action_press("move_right")
	await _ticks(18)
	_check(player.global_position.x > start_x + 10.0 and animator.call("get_animation_state") == "walk", "move_right action drives production physics and walk pose")
	Input.action_release("move_right")
	await _ticks(18)
	_check(not Input.is_action_pressed("move_right"), "movement release is present in the real input sequence")
	var attack_phases: Dictionary = await _track_attack(player, animator, 100)
	_check(attack_phases.has("startup") and attack_phases.has("active") and attack_phases.has("recovery"), "live J press traverses startup, active, and recovery")
	for skill_id in [1, 2]:
		var action := "skill_%d" % skill_id
		Input.action_press(action)
		await _ticks(1)
		Input.action_release(action)
		var skill_phases: Dictionary = await _track_skill(player, animator, 100)
		_check(skill_phases.has("startup") and skill_phases.has("active") and skill_phases.has("recovery"), "live Num%d action traverses every production phase" % (skill_id + 3))
	player.call("receive_hit", {"damage":1,"direction":Vector2.LEFT,"knockback":90.0,"hit_stun":0.24,"attack_stage":1})
	await _ticks(1)
	_check(float(player.get("hitstun_remaining")) > 0.0 and animator.call("get_animation_state") == "hit", "production receive_hit drives hitstun and hit pose")
	_check(_visible_body_count(player, animator) == 1, "live input transitions retain one full-body visual source")
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("attack")
	Input.action_release("skill_1")
	Input.action_release("skill_2")
	RenderingServer.frame_post_draw.disconnect(_sample_live_frame)
	# Include measurements from every production phase, not only the initial walk.
	maximum_step = _max_live_frame_step
	fist_error = _max_live_hand_error
	_check(maximum_step <= 30.0, "live movement/attack/skill/hit sequence has no >30px frame-to-frame position jump (%.3f)" % maximum_step)
	_check(fist_error <= 1.5, "active real fist hitbox stays within 1.5px of the rendered hand anchor (%.3f)" % fist_error)
	_check(_max_live_support_residual >= 0.0 and is_finite(_max_live_support_residual), "actual gait support residual is measurable and retained for review (%.3fpx; visual result remains UNVERIFIED)" % _max_live_support_residual)
	_check(_max_live_body_sources == 1, "no more than one full-body source was visible on any measured frame (max %d)" % _max_live_body_sources)
	print("M6V_LIVE_INPUT_SMOKE|position_delta=%.3f|max_frame_step=%.3f|active_fist_hitbox_error_px=%.3f|max_support_residual_px=%.3f|max_body_sources=%d" % [player.global_position.x - start_x, maximum_step, fist_error, _max_live_support_residual, _max_live_body_sources])

func _track_attack(player: CharacterBody2D, animator: Node, limit: int) -> Dictionary:
	var seen: Dictionary = {}
	var entered := false
	Input.action_press("attack")
	for index in range(limit):
		# Observe every simulation phase so the short startup is not skipped when
		# a Window draw frame contains several fixed physics ticks.
		await physics_frame
		if int(player.get("attack_stage")) == 1:
			seen[str(player.get("attack_phase"))] = true
			entered = true
		if index == 0:
			Input.action_release("attack")
		if entered and str(player.get("attack_phase")) == "idle":
			break
	return seen

func _track_skill(player: CharacterBody2D, animator: Node, limit: int) -> Dictionary:
	var seen: Dictionary = {}
	var entered := false
	for _index in range(limit):
		await _ticks(1)
		if int(player.get("skill_id")) > 0:
			seen[str(player.get("skill_phase"))] = true
			entered = true
		if entered and str(player.get("skill_phase")) == "idle":
			break
	return seen

func _sample_live_frame() -> void:
	if not is_instance_valid(_live_player) or not is_instance_valid(_live_animator):
		return
	var position := _live_player.global_position
	if _has_last_live_position:
		_max_live_frame_step = maxf(_max_live_frame_step, position.distance_to(_last_live_position))
	_last_live_position = position
	_has_last_live_position = true
	var state := str(_live_animator.call("get_animation_state"))
	if state == "walk":
		var gait: Dictionary = _live_animator.call("get_walk_motion_sample")
		_max_live_support_residual = maxf(_max_live_support_residual, float(gait.get("support_residual", 0.0)))
	_max_live_body_sources = maxi(_max_live_body_sources, _visible_body_count(_live_player, _live_animator))
	var hand: Variant = _live_animator.call("get_fist_contact_global")
	for area_name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		var area := _live_player.get_node("Hitboxes/" + area_name) as Area2D
		if area.monitoring and typeof(hand) == TYPE_VECTOR2:
			_max_live_hand_error = maxf(_max_live_hand_error, area.global_position.distance_to(hand))

func _visible_body_count(player: CharacterBody2D, animator: Node) -> int:
	var count := 0
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var pose := player.get_node("VisualRoot/PoseBlender")
	if art.visible and art.modulate.a > 0.01:
		count += 1
	if pose.visible and float(animator.call("get_pose_blender_weight")) >= 0.5:
		count += 1
	var walk := player.get_node_or_null("WalkMotion")
	if walk != null and bool(walk.call("is_candidate_active")):
		count += 1
	return count

func _ticks(count: int) -> void:
	for _index in range(count):
		await RenderingServer.frame_post_draw

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6v_animation_visual_matrix_smoke: review artifacts and state coverage are present; no visual approval is inferred")
		quit(0)
		return
	for failure in _failures:
		push_error("m6v_animation_visual_matrix_smoke: " + failure)
	quit(1)
