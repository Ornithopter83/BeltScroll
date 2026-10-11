extends SceneTree
"""Continuously records production animation states from the main Window scene."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_IMAGE := "res://assets/art/review/m6v_animation_quality_contact_sheet.png"
const OUTPUT_REPORT := "res://docs/review/m6v_animation_visual_acceptance_matrix.md"
const PLAYER_PATH := "YSortActors/Player"
const STEP := 1.0 / 60.0
const COLUMNS := 4
const TILE := Vector2i(320, 360)
const CROP := Rect2i(680, 250, 560, 600)
const ACTOR_NAMES := ["TrainingDummy", "ForestRaider1", "ForestRaider2", "ForestRaider3", "RuinsWardenBoss"]

var _game: Node2D
var _player: CharacterBody2D
var _animator: Node
var _overlay: Node
var _samples: Array[Dictionary] = []
var _timeline_rows := PackedStringArray()
var _capture_sequence := 0
var _visual_seconds := 0.0
var _capture_error := ""
var _segment_elapsed := 0.0
var _segment_walk_phase := -1
var _capture_mode := "강제상태·physics_off"
var _actual_previous_state := ""
var _actual_previous_walk_phase := ""
var _actual_previous_position := Vector2.ZERO
var _actual_has_previous_position := false
var _actual_max_frame_displacement := 0.0
var _actual_max_support_residual := 0.0
var _actual_max_hand_hitbox_error := 0.0
var _actual_max_visible_sources := 0
var _actual_frames := 0
var _raw_frames: Array[Dictionary] = []
var _run_dir := "res://assets/art/review/m6v_high_after_final"
var _output_image := OUTPUT_IMAGE
var _output_report := OUTPUT_REPORT
var _stimulus := "InputMap"
var _saved_size := Vector2i.ZERO

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Godot Window 렌더러가 필요합니다. headless 캡처는 증거가 아닙니다.")
		return
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 60
	root.mode = Window.MODE_WINDOWED
	if OS.get_cmdline_user_args().has("--baseline"):
		_run_dir = "res://assets/art/review/m6v_high_baseline_replay"
		_output_image = _run_dir + "/contact_sheet.png"
		_output_report = _run_dir + "/matrix.md"
	# A viewport-sized render target is independent of desktop/fullscreen limits.
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	root.content_scale_size = Vector2i(1920, 1080)
	root.size = Vector2i(1920, 1080)
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("본편 scenes/game/main.tscn을 불러오지 못했습니다.")
		return
	_game = packed.instantiate() as Node2D
	_game.name = "Main"
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_player = _game.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	_overlay = root.get_node_or_null("CombatCollisionOverlay")
	if _player == null or _overlay == null:
		_fail("본편 Player 또는 F10 충돌 오버레이를 찾지 못했습니다.")
		return
	_animator = _player.get_node("VisualAnimator")
	_player.set_physics_process(false)
	_player.set_process(false)
	for name in ACTOR_NAMES:
		var actor := _game.get_node_or_null("YSortActors/" + name)
		if actor != null:
			actor.set_physics_process(false)
			actor.set_process(false)
	_player.global_position = Vector2(960, 780)
	var camera := _player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE
	camera.make_current()
	var f10_event := InputEventKey.new()
	f10_event.keycode = KEY_F10
	f10_event.pressed = true
	_overlay.call("_input", f10_event)
	if not bool(_overlay.get("enabled")):
		_fail("실제 F10 입력 경로로 충돌 오버레이를 켜지 못했습니다.")
		return
	await _settle(3)
	_timeline_rows.append("sequence,wall_timestamp,monotonic_usec,visual_seconds,window_frame,physics_frame,segment,state,pose_frame,pose_frame_count,pose_frame_label,body_source,body_source_count,facing,foot_anchor_world,hand_anchor_world,f10_box_screen,f10_monitoring,capture_mode,world_displacement_px,gait_phase,support_residual_px,hand_hitbox_error_px")
	await _capture_baselines()
	print("M6V_PROGRESS|forced_baselines")
	await _capture_walk()
	await _capture_jump_and_reactions()
	for stage in [1, 2, 3]:
		for phase in ["startup", "active", "combo_hold", "recovery"]:
			if phase == "combo_hold" and stage == 3:
				await _capture_unavailable("J3 combo_hold", "실제 컨트롤러는 3타에서 combo_hold를 열지 않음")
				continue
			var duration := _attack_duration(stage, phase)
			await _capture_phase("J%d %s" % [stage, phase], "attack", stage, phase, duration, phase == "active")
	for skill_id in [1, 2]:
		for phase in ["startup", "active", "recovery"]:
			await _capture_phase("Num%d %s" % [skill_id + 3, phase], "skill", skill_id, phase, _skill_duration(skill_id, phase), phase == "active")
	await _capture_real_input_sequence()
	print("M6V_PROGRESS|compose_sheet")
	await _capture_sheet_and_report()
	if not _capture_error.is_empty():
		_fail(_capture_error)
		return
	print("M6V_CAPTURE_COMPLETE|samples=%d|frames=%d|image=%s|report=%s" % [_samples.size(), _capture_sequence, ProjectSettings.globalize_path(_output_image), ProjectSettings.globalize_path(_output_report)])
	quit(0)

func _capture_baselines() -> void:
	_reset_actor()
	await _segment("정지·우향", "idle", 0.10, 3)
	_reset_actor()
	_set_facing(-1.0)
	await _segment("정지·좌향 반전", "mirror_left", 0.10, 3)
	_reset_actor()
	_set_facing(1.0)
	await _segment("정지·우향 반전 복귀", "mirror_right", 0.10, 3)

func _capture_walk() -> void:
	_reset_actor()
	_player.velocity = Vector2(280, 0)
	for index in range(4):
		var phases := ["left_contact", "left_passing", "right_contact", "right_passing"]
		_segment_walk_phase = index
		_animator.set("_stride_phase", (float(index) + 0.5) * PI * 0.5)
		await _segment("4위상 보행·" + phases[index], "walk", 0.08, 3)
	_segment_walk_phase = -1

func _capture_jump_and_reactions() -> void:
	_reset_actor()
	_player.set("is_jumping", true)
	_player.set("jump_vertical_velocity", -536.66)
	_player.set("jump_height_offset", 74.0)
	_player.get_node("VisualRoot").position.y = -18.0 - 74.0
	await _segment("점프 상승", "jump_rise", 0.14, 3)
	_player.set("jump_vertical_velocity", 180.0)
	await _segment("점프 하강", "jump_fall", 0.14, 3)
	# A real transition edge starts the landing pose timer in VisualAnimator.
	_player.set("is_jumping", false)
	_player.set("jump_height_offset", 0.0)
	_player.get_node("VisualRoot").position.y = -18.0
	_animator.set("_was_jumping", true)
	await _segment("착지", "landing", 0.08, 3)
	_reset_actor()
	_player.velocity = Vector2(-80, 0)
	_player.set("hitstun_remaining", 0.20)
	_player.set("hit_flash_remaining", 0.12)
	await _segment("피격", "hit", 0.12, 3)
	_reset_actor()
	_player.set("is_ko", true)
	for row in [{"label":"KO·비틀림", "duration":0.16}, {"label":"KO·붕괴", "duration":0.40}, {"label":"KO·정착", "duration":0.50}]:
		await _segment(str(row.label), "ko", float(row.duration), 3)

func _capture_phase(label: String, family: String, index: int, phase: String, duration: float, active: bool) -> void:
	_reset_actor()
	if family == "attack":
		_player.set("attack_stage", index)
		_player.set("attack_phase", phase)
		_player.set("attack_phase_remaining", duration)
		_player.set("attack_progress", 0.5 if phase == "active" else 0.0)
		if phase == "combo_hold":
			_player.set("combo_link_remaining", duration)
			_player.set("attack_progress", 1.0)
		var area := _player.get_node("Hitboxes/Hitbox%d" % index) as Area2D
		if active:
			_animator.call("_process", 0.0)
			_player.call("_update_fist_hitbox", area)
			area.monitoring = true
	else:
		_player.set("skill_id", index)
		_player.set("skill_phase", phase)
		_player.set("skill_phase_remaining", duration)
		var area := _player.get_node("Hitboxes/Skill%dHitbox" % index) as Area2D
		if active:
			_animator.call("_process", 0.0)
			_player.call("_update_fist_hitbox", area)
			area.monitoring = true
	var flash := _player.get_node("VisualRoot/AttackFlash") as Polygon2D
	flash.visible = active
	await _segment(label, "%s%d_%s" % [family, index, "contact" if phase == "active" else phase], duration, 3)

func _segment(label: String, forced_state: String, duration: float, sample_limit: int) -> void:
	var total_frames := maxi(1, int(ceil(duration / STEP)))
	_segment_elapsed = 0.0
	var capture_indices: Array[int] = []
	for requested in [0, int(total_frames / 2), total_frames - 1]:
		if not capture_indices.has(requested):
			capture_indices.append(requested)
	for frame_index in range(total_frames):
		if _segment_walk_phase >= 0:
			var walk_rate := TAU * 280.0 / 235.2
			_animator.set("_stride_phase", (float(_segment_walk_phase) + 0.5) * PI * 0.5 - walk_rate * _segment_elapsed)
		if str(_player.get("attack_phase")) != "idle":
			_player.set("attack_phase_remaining", maxf(0.0, float(_player.get("attack_phase_remaining")) - STEP))
		elif str(_player.get("skill_phase")) != "idle":
			_player.set("skill_phase_remaining", maxf(0.0, float(_player.get("skill_phase_remaining")) - STEP))
		_visual_seconds += STEP
		_animator.call("_process", STEP)
		for hitbox_name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
			var area := _player.get_node("Hitboxes/" + hitbox_name) as Area2D
			if area.monitoring:
				_player.call("_update_fist_hitbox", area)
		await RenderingServer.frame_post_draw
		_capture_sequence += 1
		if capture_indices.has(frame_index) and _samples.size() < 128:
			var state := forced_state
			if forced_state == "landing":
				state = str(_animator.call("get_animation_state"))
			_record(label, state)
		_record_timeline(label, forced_state)
		await process_frame
		_segment_elapsed += STEP
		if _capture_error.is_empty() == false:
			return

func _capture_real_input_sequence() -> void:
	_capture_mode = "실제입력·physics_on"
	# Start the live-input comparison from a fresh production scene. This prevents
	# the preceding forced KO pose (and its animator interpolation) from bleeding
	# into the physics-on measurements.
	_game.queue_free()
	await process_frame
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_capture_error = "실제 입력 비교용 본편 main scene을 다시 불러오지 못했습니다."
		return
	_game = packed.instantiate() as Node2D
	_game.name = "Main"
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_player = _game.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	if _player == null:
		_capture_error = "새 본편 scene에서 실제 입력 Player를 찾지 못했습니다."
		return
	_animator = _player.get_node("VisualAnimator")
	for name in ACTOR_NAMES:
		var actor := _game.get_node_or_null("YSortActors/" + name)
		if actor != null:
			actor.set_physics_process(false)
			actor.set_process(false)
			actor.process_mode = Node.PROCESS_MODE_DISABLED
			actor.position.x += 10000.0
	var camera := _player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE
	camera.make_current()
	# Scene replacement can reset the debug overlay; toggle it via its normal F10
	# input hook so the real-input evidence still contains the live boxes.
	_overlay = root.get_node_or_null("CombatCollisionOverlay")
	if _overlay != null and not bool(_overlay.get("enabled")):
		var f10_event := InputEventKey.new()
		f10_event.keycode = KEY_F10
		f10_event.pressed = true
		_overlay.call("_input", f10_event)
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "skill_1", "skill_2"]:
		Input.action_release(action)
	_reset_actor()
	_player.set_physics_process(true)
	_player.set_process(true)
	_player.global_position = Vector2(960, 780)
	await _actual_ticks(12) # Let the fresh idle pose and support point settle before motion.
	_actual_previous_position = _player.global_position
	_actual_has_previous_position = true
	_actual_previous_state = str(_animator.call("get_animation_state"))
	_actual_previous_walk_phase = ""
	_record("실입력·정지 기준", _actual_previous_state)
	# Exercise configured InputMap actions while production physics/animation stay live.
	Input.action_press("move_right")
	await _actual_ticks(60)
	_record("실입력·이동 중 기준", str(_animator.call("get_animation_state")))
	Input.action_release("move_right")
	await _actual_ticks(18)
	_record("실입력·이동 해제 후", str(_animator.call("get_animation_state")))
	Input.action_press("move_left")
	await _actual_ticks(24)
	Input.action_release("move_left")
	await _actual_ticks(12)
	Input.action_press("move_right")
	await _actual_ticks(12)
	Input.action_release("move_right")
	await _actual_ticks(12)
	Input.action_press("jump")
	await _actual_ticks(18)
	Input.action_release("jump")
	await _actual_ticks(48)
	_record("실입력·착지 후", str(_animator.call("get_animation_state")))
	# J press/release is consumed by Player._physics_process, then phases advance on its timer.
	Input.action_press("attack")
	await _actual_ticks(1)
	Input.action_release("attack")
	await _actual_until_attack_idle(100)
	_record("실입력·J1 회복 후", str(_animator.call("get_animation_state")))
	for stage in [1, 2, 3]:
		Input.action_press("attack")
		await _actual_ticks(1)
		Input.action_release("attack")
		for _tick in range(120):
			await _actual_ticks(1)
			if int(_player.get("attack_stage")) == stage and str(_player.get("attack_phase")) == "recovery":
				break
			if _tick == 119:
				_capture_error = "실입력 J%d recovery 미도달" % stage
	await _actual_until_attack_idle(100)
	_record("실입력·J3 회복 후", str(_animator.call("get_animation_state")))
	for skill_id in [1, 2]:
		var action := "skill_%d" % skill_id
		Input.action_press(action)
		await _actual_ticks(1)
		Input.action_release(action)
		await _actual_until_skill_idle(100)
		_record("실입력·Num%d 회복 후" % (skill_id + 3), str(_animator.call("get_animation_state")))
	# Use the production damage receiver so hitstun, flash, and recovery are not forced pose fields.
	_stimulus = "receive_hit fixture (not enemy attack)"
	_player.call("receive_hit", {"damage": 1, "direction": Vector2.LEFT, "knockback": 90.0, "hit_stun": 0.24, "attack_stage": 1})
	await _actual_ticks(24)
	_record("실입력·피격 회복 후", str(_animator.call("get_animation_state")))
	_player.call("receive_hit", {"damage": 99, "direction": Vector2.LEFT, "knockback": 90.0, "hit_stun": 0.24, "attack_stage": 3})
	await _actual_ticks(48)
	_record("실입력·KO 정착", str(_animator.call("get_animation_state")))
	for action in ["move_left", "move_right", "move_up", "move_down", "attack", "skill_1", "skill_2"]:
		Input.action_release(action)
	_player.set_physics_process(false)
	_player.set_process(false)
	_capture_mode = "강제상태·physics_off"
	print("M6V_INPUT_TRACE|frames=%d|max_displacement=%.3f|max_support_residual=%.3f|max_hand_hitbox_error=%.3f|max_visible_sources=%d" % [_actual_frames, _actual_max_frame_displacement, _actual_max_support_residual, _actual_max_hand_hitbox_error, _actual_max_visible_sources])

func _actual_ticks(count: int) -> void:
	for _index in range(count):
		# One sample per completed Window render. Waiting for a separate physics
		# tick first can skip intermediate rendered frames and inflate movement or
		# support residuals under load.
		await RenderingServer.frame_post_draw
		_capture_sequence += 1
		_visual_seconds += STEP
		_actual_frames += 1
		var position := _player.global_position
		var displacement := position.distance_to(_actual_previous_position) if _actual_has_previous_position else 0.0
		_actual_max_frame_displacement = maxf(_actual_max_frame_displacement, displacement)
		_actual_previous_position = position
		_actual_has_previous_position = true
		var state := str(_animator.call("get_animation_state"))
		var capture_state := state
		var capture_label := "실입력 연속"
		var walk_phase := ""
		if state == "walk":
			var gait: Dictionary = _animator.call("get_walk_motion_sample")
			walk_phase = str(gait.get("phase", ""))
			_actual_max_support_residual = maxf(_actual_max_support_residual, float(gait.get("support_residual", 0.0)))
			if walk_phase != _actual_previous_walk_phase:
				capture_label = "실입력·보행위상·" + walk_phase
				_actual_previous_walk_phase = walk_phase
		var sources := _visible_body_count()
		_actual_max_visible_sources = maxi(_actual_max_visible_sources, sources)
		var hand_error := _active_hand_hitbox_error()
		_actual_max_hand_hitbox_error = maxf(_actual_max_hand_hitbox_error, hand_error)
		if state != _actual_previous_state:
			capture_label = "실입력·상태전환·" + state
			_record(capture_label, state)
			_actual_previous_state = state
		_record_timeline(capture_label, state, displacement, walk_phase, hand_error)
		var frame := root.get_texture().get_image()
		if frame.get_size() != Vector2i(1920, 1080):
			_capture_error = "원본 viewport 크기 불일치: %s" % frame.get_size()
		_raw_frames.append({"image": frame.get_region(CROP), "sequence": _capture_sequence, "window_frame": Engine.get_frames_drawn(), "state": state, "stimulus": _stimulus, "facing": _player.get_node("VisualRoot").scale.x, "hp": _player.get("health"), "support_residual": float((_animator.call("get_walk_motion_sample") as Dictionary).get("support_residual", -1.0)) if state == "walk" else -1.0})

func _actual_until_attack_idle(limit: int) -> void:
	var entered_attack := false
	for _index in range(limit):
		if str(_player.get("attack_phase")) != "idle":
			entered_attack = true
		await _actual_ticks(1)
		if entered_attack and str(_player.get("attack_phase")) == "idle":
			return
	_capture_error = "실제 attack action이 production startup/active/recovery를 완료하지 못했습니다."

func _actual_until_skill_idle(limit: int) -> void:
	var entered_skill := false
	for _index in range(limit):
		if str(_player.get("skill_phase")) != "idle":
			entered_skill = true
		await _actual_ticks(1)
		if entered_skill and str(_player.get("skill_phase")) == "idle":
			return
	_capture_error = "실제 skill action이 production startup/active/recovery를 완료하지 못했습니다."

func _active_hand_hitbox_error() -> float:
	var hand: Variant = _animator.call("get_fist_contact_global")
	if typeof(hand) != TYPE_VECTOR2:
		return 0.0
	for name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		var area := _player.get_node("Hitboxes/" + name) as Area2D
		if area.monitoring:
			return area.global_position.distance_to(hand)
	return 0.0

func _record(label: String, forced_state: String) -> void:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_capture_error = "Window 프레임 이미지를 읽을 수 없습니다 (%s)." % label
		return
	var crop := image.get_region(CROP)
	crop.resize(TILE.x - 20, TILE.y - 58, Image.INTERPOLATE_LANCZOS)
	_samples.append({"label":label, "state":forced_state, "mode":_capture_mode, "image":crop, "sequence":_capture_sequence, "visual_seconds":_visual_seconds, "wall":Time.get_datetime_string_from_system(false, true), "window_frame":Engine.get_frames_drawn(), "physics_frame":Engine.get_physics_frames(), "pose_frame":int(_animator.call("get_state_frame")), "pose_count":int(_animator.call("get_state_frame_count")), "pose_label":str(_animator.call("get_state_frame_label")), "source":str(_animator.call("get_displayed_texture_path")), "foot":_foot_anchor(), "hand":_hand_anchor(), "box":_f10_box(), "monitoring":_active_f10_monitoring(), "source_count":_visible_body_count(), "facing":"좌향" if _player.get_node("VisualRoot").scale.x < 0.0 else "우향"})

func _record_timeline(label: String, forced_state: String, displacement := 0.0, support_phase := "", hand_error := 0.0) -> void:
	var measured_state := str(_animator.call("get_animation_state")) if forced_state == "landing" else forced_state
	var values := _sample_values(label, measured_state)
	var support_residual := -1.0
	if measured_state == "walk":
		var gait: Dictionary = _animator.call("get_walk_motion_sample")
		support_residual = float(gait.get("support_residual", -1.0))
	var columns := PackedStringArray([
		str(_capture_sequence), Time.get_datetime_string_from_system(false, true), str(Time.get_ticks_usec()), "%.4f" % _visual_seconds,
		str(Engine.get_frames_drawn()), str(Engine.get_physics_frames()), label, measured_state,
		str(_animator.call("get_state_frame")), str(_animator.call("get_state_frame_count")),
		str(_animator.call("get_state_frame_label")), str(_animator.call("get_displayed_texture_path")),
		str(_visible_body_count()), "left" if _player.get_node("VisualRoot").scale.x < 0.0 else "right",
		values.foot, values.hand, values.box, _active_f10_monitoring(), _capture_mode,
		"%.4f" % displacement, support_phase, "%.4f" % support_residual, "%.4f" % hand_error,
	])
	for index in range(columns.size()):
		columns[index] = _csv_quote(columns[index])
	_timeline_rows.append(",".join(columns))

func _csv_quote(value: String) -> String:
	return "\"" + value.replace("\"", "\"\"") + "\""

func _sample_values(_label: String, _state: String) -> Dictionary:
	return {"foot":_foot_anchor(), "hand":_hand_anchor(), "box":_f10_box()}

func _reset_actor() -> void:
	_player.velocity = Vector2.ZERO
	_player.set("is_ko", false)
	_player.set("is_jumping", false)
	_player.set("jump_vertical_velocity", 0.0)
	_player.set("jump_height_offset", 0.0)
	_player.set("attack_stage", 0)
	_player.set("attack_phase", "idle")
	_player.set("attack_phase_remaining", 0.0)
	_player.set("attack_progress", 0.0)
	_player.set("combo_link_remaining", 0.0)
	_player.set("skill_id", 0)
	_player.set("skill_phase", "idle")
	_player.set("skill_phase_remaining", 0.0)
	_player.set("hitstun_remaining", 0.0)
	_player.set("hit_flash_remaining", 0.0)
	_player.get_node("VisualRoot/AttackFlash").visible = false
	for name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		(_player.get_node("Hitboxes/" + name) as Area2D).monitoring = false
	_player.get_node("VisualRoot").scale.x = 1.0
	_player.set("facing_direction", Vector2.RIGHT)
	_player.global_position = Vector2(960, 780)
	_animator.call("_process", 0.0)

func _foot_anchor() -> String:
	var sprite := _visible_sprite()
	if sprite == null or sprite.texture == null:
		return "미확인"
	var bounds := sprite.texture.get_image().get_used_rect()
	var local := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y)) - Vector2(sprite.texture.get_size()) * 0.5
	var point := sprite.to_global(local)
	return "%.1f,%.1f" % [point.x, point.y]

func _hand_anchor() -> String:
	var point: Variant = _animator.call("get_fist_contact_global")
	return "미확인" if typeof(point) != TYPE_VECTOR2 else "%.1f,%.1f" % [point.x, point.y]

func _f10_box() -> String:
	var boxes: Array[String] = []
	for name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		var area := _player.get_node("Hitboxes/" + name) as Area2D
		var shape_node := area.get_node("CollisionShape2D") as CollisionShape2D
		var center := shape_node.get_global_transform_with_canvas().origin
		if shape_node.shape is CircleShape2D:
			var radius := (shape_node.shape as CircleShape2D).radius * shape_node.global_scale.x
			boxes.append("%s[%s %.1f,%.1f %.1fx%.1f]" % [name, "on" if area.monitoring else "off", center.x - radius, center.y - radius, radius * 2.0, radius * 2.0])
	return "; ".join(boxes)

func _set_facing(sign: float) -> void:
	_player.set("facing_direction", Vector2(sign, 0.0))
	_player.get_node("VisualRoot").scale.x = sign
	_animator.set("_applied_facing_sign", sign)
	_animator.set("_turn_target_sign", sign)
	_animator.set("_turn_elapsed", 0.13)
	_animator.set("_turn_flip_applied", true)
	_animator.call("_process", 0.0)

func _active_f10_monitoring() -> String:
	var enabled: Array[String] = []
	for name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		if (_player.get_node("Hitboxes/" + name) as Area2D).monitoring:
			enabled.append(name)
	return ",".join(enabled) if not enabled.is_empty() else "none"

func _visible_sprite() -> Sprite2D:
	var pose := _player.get_node("VisualRoot/PoseBlender")
	if pose.visible and float(_animator.call("get_pose_blender_weight")) >= 0.5:
		return pose.call("get_current_sprite") as Sprite2D
	return _player.get_node("VisualRoot/PlayerArt") as Sprite2D

func _visible_body_count() -> int:
	var count := 0
	var art := _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var pose := _player.get_node("VisualRoot/PoseBlender")
	if art.visible and art.modulate.a > 0.01:
		count += 1
	if pose.visible and float(_animator.call("get_pose_blender_weight")) >= 0.5:
		count += 1
	var walk := _player.get_node_or_null("WalkMotion")
	if walk != null and walk.call("is_candidate_active"):
		count += 1
	return count

func _capture_unavailable(label: String, reason: String) -> void:
	_samples.append({"label":label, "state":"UNAVAILABLE", "mode":_capture_mode, "image":Image.create(TILE.x - 20, TILE.y - 58, false, Image.FORMAT_RGBA8), "sequence":_capture_sequence, "visual_seconds":_visual_seconds, "wall":Time.get_datetime_string_from_system(false, true), "window_frame":Engine.get_frames_drawn(), "physics_frame":Engine.get_physics_frames(), "pose_frame":0, "pose_count":0, "pose_label":reason, "source":"N/A", "foot":"N/A", "hand":"N/A", "box":"N/A", "monitoring":"none", "source_count":0, "facing":"N/A"})

func _capture_sheet_and_report() -> void:
	_overlay.set("enabled", false)
	_overlay.get_node("CollisionShapes").visible = false
	_game.queue_free()
	await process_frame
	var columns := COLUMNS
	var rows := int(ceil(float(_samples.size()) / columns))
	var viewport := SubViewport.new()
	viewport.size = Vector2i(columns * TILE.x, TILE.y * 2)
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var sheet := Control.new()
	sheet.name = "M6VContactSheet"
	viewport.add_child(sheet)
	for index in range(_samples.size()):
		var sample: Dictionary = _samples[index]
		var x := (index % columns) * TILE.x
		var y := (index / columns) * TILE.y
		var bg := ColorRect.new()
		bg.position = Vector2(x, y)
		bg.size = Vector2(TILE)
		bg.color = Color("#172226") if index % 2 == 0 else Color("#202d31")
		sheet.add_child(bg)
		var texture := ImageTexture.create_from_image(sample.image as Image)
		var rect := TextureRect.new()
		rect.position = Vector2(x + 10, y + 48)
		rect.size = Vector2(TILE.x - 20, TILE.y - 58)
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		sheet.add_child(rect)
		var mode_tag := "REAL INPUT · PHYSICS ON" if str(sample.mode) == "실제입력·physics_on" else "FORCED STATE · PHYSICS OFF"
		_add_label(sheet, mode_tag, Vector2(x + 8, y + 3), 10, Color("#71e0bb") if str(sample.mode) == "실제입력·physics_on" else Color("#e6d797"))
		_add_label(sheet, "#%03d %s" % [index + 1, str(sample.label).substr(0, 29)], Vector2(x + 8, y + 23), 11, Color.WHITE)
		_add_label(sheet, "%s  frame %d  t=%.3fs" % [sample.wall, sample.window_frame, sample.visual_seconds], Vector2(x + 8, y + 39), 9, Color("#c8d4cc"))
	# Compose bounded pages on the CPU; never resize the desktop Window to a
	# 10,000px sheet and assume the OS honored that request.
	var output := Image.create(columns * TILE.x, rows * TILE.y, false, Image.FORMAT_RGBA8)
	for first_row in range(0, rows, 2):
		sheet.position.y = -first_row * TILE.y
		await process_frame
		await RenderingServer.frame_post_draw
		var page := viewport.get_texture().get_image()
		output.blit_rect(page, Rect2i(0, 0, page.get_width(), mini(page.get_height(), (rows - first_row) * TILE.y)), Vector2i(0, first_row * TILE.y))
	# Preserve the captured pixels exactly; GPU texture filtering/color roundtrips
	# and label overlap must not modify evidence thumbnails.
	for index in range(_samples.size()):
		var captured: Image = (_samples[index].image as Image).duplicate()
		captured.convert(Image.FORMAT_RGBA8)
		output.blit_rect(captured, Rect2i(Vector2i.ZERO, captured.get_size()), Vector2i((index % columns) * TILE.x + 10, (index / columns) * TILE.y + 48))
	var absolute_image := ProjectSettings.globalize_path(_output_image)
	DirAccess.make_dir_recursive_absolute(absolute_image.get_base_dir())
	if output.save_png(absolute_image) != OK:
		_capture_error = "접촉 시트 PNG 저장에 실패했습니다."
		return
	var saved := Image.load_from_file(absolute_image)
	_saved_size = saved.get_size()
	if _saved_size != Vector2i(columns * TILE.x, rows * TILE.y):
		_capture_error = "저장된 접촉 시트 치수 불일치"
		return
	var manifest := {"width": saved.get_width(), "height": saved.get_height(), "columns": columns, "rows": rows, "card_count": _samples.size(), "cards": [], "raw_frames": [], "human_approval": "UNVERIFIED", "fixed_fps": 60 if OS.get_cmdline_args().has("--fixed-fps") else 0, "body_mesh_sha256": FileAccess.get_sha256("res://scripts/player/player_body_mesh.gd")}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_run_dir))
	for index in range(_samples.size()):
		var crop := saved.get_region(Rect2i((index % columns) * TILE.x + 10, (index / columns) * TILE.y + 48, TILE.x - 20, TILE.y - 58))
		var expected: Image = (_samples[index].image as Image).duplicate()
		expected.convert(crop.get_format())
		# Blank N/A cards blend with the card background; all rendered cards must
		# survive page composition byte-for-byte.
		if str(_samples[index].state) != "UNAVAILABLE" and crop.get_data() != expected.get_data():
			_capture_error = "시트 카드 픽셀 불일치 #%d" % (index + 1)
		manifest.cards.append({"index": index, "sequence": _samples[index].sequence, "state": _samples[index].state, "mode": _samples[index].mode, "sha256": _image_hash(crop)})
	for frame in _raw_frames:
		var path := _run_dir + "/frame_%04d.png" % frame.sequence
		if (frame.image as Image).save_png(ProjectSettings.globalize_path(path)) != OK:
			_capture_error = "연속 프레임 저장 실패: " + path
		var metadata: Dictionary = frame.duplicate()
		metadata.erase("image")
		metadata["path"] = path
		metadata["sha256"] = FileAccess.get_sha256(path)
		metadata["human_review"] = "UNVERIFIED"
		manifest.raw_frames.append(metadata)
	var manifest_file := FileAccess.open(_output_image + ".json", FileAccess.WRITE)
	manifest_file.store_string(JSON.stringify(manifest, "\t"))
	manifest_file.close()
	_write_report(columns, rows)
	viewport.queue_free()

func _image_hash(image: Image) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(image.get_data())
	return hash.finish().hex_encode()

func _add_label(parent: Control, text: String, position: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = Vector2(TILE.x - 16, 22)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)

func _write_report(columns: int, rows: int) -> void:
	var lines := PackedStringArray()
	lines.append("# M6V 애니메이션 시각 검수 매트릭스")
	lines.append("")
	lines.append("- 수집 시각: %s (Godot 시스템 로컬 시각, Asia/Seoul 환경)" % Time.get_datetime_string_from_system(false, true))
	lines.append("- 대상: `scenes/game/main.tscn`의 production Player, 실제 Godot Window Viewport 캡처")
	lines.append("- 접촉 시트: `%s` (%d×%d px 실측, %d열 × %d행, %d카드; 카메라 줌 1.0, 560×600 원본 crop → 300×302 시트 썸네일). PNG 재로딩 후 카드별 픽셀과 manifest hash를 검증한다." % [_output_image, _saved_size.x, _saved_size.y, columns, rows, _samples.size()])
	lines.append("- 원본 연속 PNG 및 프레임별 manifest: `%s`, `%s.json`. 모든 실입력 rendered frame을 560×600 동일 배율로 보존한다. receive_hit fixture는 적 공격 입력과 구분되며 피격/KO는 damage API 행사 증거다. 적 AI는 중지된 격리 장면이다." % [_run_dir, _output_image])
	var forced_count := 0
	var input_count := 0
	for sample in _samples:
		if str(sample.mode) == "실제입력·physics_on":
			input_count += 1
		else:
			forced_count += 1
	lines.append("- 연속 수집: %d Window draw ticks, 표본 누적 t 간격 1/60초, 모션 시퀀스 %.3f초. 원본 체크포인트 PNG/보고서는 docs/review/m6v_high_checkpoint에 바이트 그대로 보존했다. 이 시트는 같은 강제상태 매트릭스 %d카드를 재수집하고 실제 입력 비교 %d카드를 추가한 새 증거다. 상태 telemetry는 모든 sample frame을 기록한다." % [_capture_sequence, _visual_seconds, forced_count, input_count])
	lines.append("- HIGH의 전후 검토·잔여 결함·실제 피해 결과: [m6v_high_review.md](m6v_high_review.md). 시트 썸네일은 비등방 리사이즈되므로 관절/외형 판정은 동일 560×600 원본과 종횡비를 유지한 전후 비교 보드를 사용한다.")
	lines.append("- 측정: 발 anchor는 표시 전신 텍스처 alpha 하단 중심의 world point, 손 anchor는 animator의 실제 주먹 접촉 point, F10 박스는 실제 CollisionShape2D canvas bounds와 monitoring을 기록한다. F10 오버레이는 녹화 중 켜져 있었다.")
	lines.append("- 프레임 번호는 Godot `Engine.get_frames_drawn()` Window draw counter다. visual t는 시퀀스 시작 이후 60Hz 샘플 누적 시간이고 monotonic_usec은 표본 시점의 단조 시계 마이크로초 값이다. 표본은 초 단위 wall-clock ISO 시각과 함께 저장한다.")
	lines.append("- 캡처 모드 구분: `FORCED STATE · PHYSICS OFF` 카드는 Player physics/process를 중지한 뒤 상태 필드를 직접 설정해 기존 매트릭스를 보존한 것이다. `REAL INPUT · PHYSICS ON` 카드는 본편 Player physics/process를 켜고 InputMap action을 입력해 수집한 별도 실제 전환이다. 후자에서 이동·J·Num4/5·receive_hit 경로를 연속 기록했다.")
	lines.append("- 두 모드는 같은 main scene, 카메라 zoom 1.0, 화면 crop, 표시 크기를 사용하므로 전후 비교 배율이 같다.")
	lines.append("- 실제 입력 연속 구간은 %d rendered frame이다. 프레임별 최대 이동량 %.3f px, gait support residual %.3f px, fist↔활성 hitbox 중심 오차 %.3f px, 최대 표시 전신 source 수 %d를 계측했다. support residual이 1.5px를 넘은 표본은 발 미끄러짐 후보로 표시해 육안 확인이 필요하며, 어느 수치도 시각 승인으로 해석하지 않는다." % [_actual_frames, _actual_max_frame_displacement, _actual_max_support_residual, _actual_max_hand_hitbox_error, _actual_max_visible_sources])
	lines.append("")
	lines.append("## 연속 상태 기록")
	lines.append("")
	lines.append("강제 상태와 실제 입력 연속 구간을 `capture_mode`로 구분했다. 실제 입력 쪽은 매 rendered frame마다 전신 source 수, 이동량, gait/support residual, 손과 활성 판정 중심 오차를 기록한다. 접촉 시트의 추가 실입력 카드는 전환 전/후 비교이며 모든 카드가 같은 배율이다.")
	lines.append("")
	lines.append("| seq | mode | wall timestamp | visual t | window frame | 상태 / 구간 | pose frame | 발 anchor world | 손 anchor world | F10 box screen / monitoring | 전신 source |")
	lines.append("|---:|---|---|---:|---:|---|---:|---|---|---|---|")
	for sample in _samples:
		lines.append("| %d | %s | %s | %.3fs | %d | %s / %s | %d/%d %s | %s | %s | %s / %s | `%s` (%d) |" % [sample.sequence, sample.mode, sample.wall, sample.visual_seconds, sample.window_frame, sample.label, sample.state, sample.pose_frame, sample.pose_count, sample.pose_label, sample.foot, sample.hand, sample.box, sample.monitoring, sample.source, sample.source_count])
	lines.append("")
	lines.append("## 시각 검수 판정")
	lines.append("")
	lines.append("PASS는 이 접촉 시트에서 사람이 육안으로 확인한 항목만 의미한다. 현재 자동 캡처/anchor 데이터는 형태 평가를 대체하지 않으므로 관절·얼굴·복장·연속성·주먹과 판정 정합성은 육안 승인 전까지 UNVERIFIED로 둔다. 자동 픽셀 측정으로 PASS를 만들지 않았다.")
	lines.append("")
	lines.append("| 상태 / 캡처 모드 | 관절 왜곡 | 발 미끄러짐 | 손/판정 불일치 | 실루엣 중복 | 전환 순간 점프 | 프레임 끊김 | 체형·얼굴·복장 일관성 | 전체 결과 / 검토 메모 |")
	lines.append("|---|---|---|---|---|---|---|---|---|")
	for label in _unique_labels():
		var disposition := "UNVERIFIED"
		var note := "육안 확인 대기; 같은 배율의 카드와 실제 F10 표시를 함께 볼 것"
		if label == "J3 combo_hold":
			disposition = "UNVERIFIED"
			note = "본편 규칙상 J3 다음 combo_hold가 없어 재현 불가"
		lines.append("| %s | %s | %s | %s | %s | %s | %s | %s | %s: %s |" % [label, disposition, disposition, disposition, disposition, disposition, disposition, disposition, disposition, note])
	lines.append("")
	lines.append("## 해석 범위와 한계")
	lines.append("")
	lines.append("- 본편 걷기 4위상은 procedural mesh gait의 `left_contact`, `left_passing`, `right_contact`, `right_passing` phase clock에서 채집했다. 임시 보행은 승인된 4장의 연속 애니메이션 원화가 아니다.")
	lines.append("- J1/J2는 실제 `combo_hold` link window를 포함한다. 컨트롤러는 J3에서 combo_hold를 제공하지 않으므로 해당 칸은 UNVERIFIED/N/A로 기록했다.")
	lines.append("- Num4/Num5의 production phase는 startup/active/recovery다. 별도 combo_hold 상태는 없다.")
	lines.append("- 강제상태 카드의 수치/포즈는 production input을 재현하지 않는 참고용이며 실제 입력 카드와 섞어 해석하지 않는다.")
	lines.append("- 실제 입력 연속 CSV는 프레임별 측정으로 화면 점프/발 미끄럼 후보/주먹 판정점 차이를 찾도록 돕지만, 관절 왜곡과 외형 일관성 및 최종 시각 판정은 사람이 확인하기 전까지 UNVERIFIED다.")
	lines.append("- 한 장의 검수 시트와 수치 telemetry는 육안 승인, 원화 일관성 보증, 실제 상대에게 접촉했을 때의 적중 보증을 대신하지 않는다.")
	lines.append("")
	lines.append("## 원본 연속 telemetry")
	lines.append("")
	lines.append("```csv")
	lines.append("\n".join(_timeline_rows))
	lines.append("```")
	var absolute_report := ProjectSettings.globalize_path(_output_report)
	DirAccess.make_dir_recursive_absolute(absolute_report.get_base_dir())
	var file := FileAccess.open(absolute_report, FileAccess.WRITE)
	if file == null:
		_capture_error = "검수 매트릭스 문서를 열지 못했습니다."
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()

func _unique_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for sample in _samples:
		var label := str(sample.label)
		if not labels.has(label):
			labels.append(label)
	return labels

func _attack_duration(stage: int, phase: String) -> float:
	var index := stage - 1
	var durations := {"startup":[0.075, 0.085, 0.10], "active":[0.105, 0.12, 0.14], "recovery":[0.20, 0.22, 0.28], "combo_hold":[0.45, 0.45, 0.0]}
	return float(durations[phase][index])

func _skill_duration(skill_id: int, phase: String) -> float:
	var index := skill_id - 1
	var durations := {"startup":[0.16, 0.22], "active":[0.12, 0.18], "recovery":[0.42, 0.55]}
	return float(durations[phase][index])

func _settle(frames: int) -> void:
	for _index in range(frames):
		await process_frame
		await RenderingServer.frame_post_draw

func _fail(message: String) -> void:
	push_error("m6v_animation_comparison: " + message)
	quit(1)
