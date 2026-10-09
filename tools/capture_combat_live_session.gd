extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/combat_live_session_window.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const MAX_DURATION_MSEC := 30000
const APPROVED_ATTACK1 := "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png"
const APPROVED_ATTACK2 := "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png"
const APPROVED_ATTACK3 := "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png"

var _started_msec := 0
var _player: CharacterBody2D
var _raiders: Array[CharacterBody2D] = []
var _game: Node2D
var _saved_scale := 1.0
var _failures: Array[String] = []
var _timeline: Array[Dictionary] = []
var _trace: Array[String] = []
var _attack_hits := {1: 0, 2: 0, 3: 0}
var _raider_hits := {1: 0, 2: 0, 3: 0}
var _hitstop_seen := {1: false, 2: false, 3: false}
var _hit_targets: Dictionary = {}
var _hitstun_at_contact: Dictionary = {}
var _live_pressed: Array[StringName] = []
var _sample_stage := 0
var _sample_stage_hitbox: Area2D
var _combat_monitor_active := false
var _last_observed_phase := ""
var _last_observed_hitstop := false
var _phase_frame_counts: Dictionary = {}
var _phase_hitbox_mismatches: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_started_msec = Time.get_ticks_msec()
	_saved_scale = Engine.time_scale
	_check(DisplayServer.get_name() != "headless" and not OS.has_feature("dedicated_server"), "Window renderer is available")
	if not _failures.is_empty():
		_finish()
		return
	root.size = CAPTURE_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main.tscn loads as the live combat scene")
	if packed == null:
		_finish()
		return
	_game = packed.instantiate() as Node2D
	root.add_child(_game)
	await process_frame
	_player = _game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	_check(_player != null, "main scene provides the real Player")
	_check(_game.get_node_or_null("CombatHUD") != null, "main scene provides the real combat HUD")
	_check(_game.get_node_or_null("CombatAudio") != null, "main scene provides CombatAudio")
	_check(_game.get_node_or_null("YSortActors/Player/Camera2D") != null, "main scene provides the Player camera")
	for index in range(1, 4):
		var raider := _game.get_node_or_null("YSortActors/ForestRaider%d" % index) as CharacterBody2D
		_check(raider != null, "main scene provides Raider %d" % index)
		if raider != null:
			_raiders.append(raider)
	if _player == null or _raiders.size() != 3 or not _failures.is_empty():
		_finish()
		return
	_player.attack_hit.connect(_on_attack_hit)
	_player.player_hit.connect(_on_player_hit)
	for index in range(3):
		_raiders[index].raider_hit.connect(_on_raider_hit.bind(index + 1))
		_raiders[index].attack_windup_started.connect(_on_raider_windup_started.bind(index + 1))
		# Preserve the real Raider receiver and collision path, while keeping its
		# autonomous retaliation out of this controlled Player-combo capture.
		_raiders[index].set("notice_range", 0.0)
		_raiders[index].global_position = Vector2(1700.0, 100.0 + float(index) * 430.0)
	_combat_monitor_active = true
	call_deferred("_monitor_combat_physics")
	_sample_stage = 0
	await _physics_frames(2)
	await _capture_timeline("01 · LIVE START", "Main scene running before synthetic input")

	# Move and turn using the same actions consumed by Player._physics_process.
	_press(&"move_right")
	await _physics_frames(18)
	_release(&"move_right")
	var moved_right: bool = _player.global_position.x > 960.0 and _player.facing_direction.x > 0.8
	_trace.append("movement right: x=%.1f facing=%s physics=%d" % [_player.global_position.x, _player.facing_direction, Engine.get_physics_frames()])
	_check(moved_right, "synthetic right action advances live physics and turns Player right")
	await _capture_timeline("02 · MOVE RIGHT", "Synthetic Input action · live physics movement")
	_press(&"move_left")
	await _physics_frames(14)
	_release(&"move_left")
	var reversed: bool = _player.global_position.x < 1010.0 and _player.facing_direction.x < -0.8
	_trace.append("movement reversal: x=%.1f facing=%s physics=%d" % [_player.global_position.x, _player.facing_direction, Engine.get_physics_frames()])
	_check(reversed, "synthetic left action reverses live movement and facing")
	await _capture_timeline("03 · TURN", "Synthetic Input action · direction reversed")

	# Set encounter spacing only; all attacks, hitboxes, damage, signals and stun
	# effects below are produced by the unmodified game's normal physics path.
	await _physics_frames(2)
	var combat_ok := await _run_live_combo()
	if combat_ok:
		for stage in range(1, 4):
			_check(int(_phase_frame_counts.get("%d:active" % stage, 0)) > 0, "attack %d active phase is sampled across real physics frames" % stage)
			_check(int(_phase_hitbox_mismatches.get(stage, 0)) == 0, "attack %d hitbox is enabled exactly while its active phase is sampled" % stage)
		_check(_attack_hits[1] > 0 and _attack_hits[2] > 0 and _attack_hits[3] > 0, "all three attack_hit signals came from live active hitboxes")
		_check(_hitstop_seen[1] and _hitstop_seen[2] and _hitstop_seen[3], "hit-stop was observed during all three real hit events")
		await _capture_timeline("09 · COMBO COMPLETE", "Three live attack phases · confirmed health and hit events")
	if _trace.size() > 0:
		print("combat-live-session trace:\n" + "\n".join(_trace))
	if _failures.is_empty():
		await _build_comparison_board()
	_finish()

func _run_live_combo() -> bool:
	if _expired():
		_check(false, "overall live-session time limit was not exceeded")
		return false
	var start_health: Dictionary = {}
	var start_receives: Dictionary = {}
	var start_attacks: Dictionary = {}
	for index in range(3):
		var raider := _raiders[index]
		_reset_raider_for_live_combo(raider)
		# Stage 3 deals enough real damage to KO a default Raider. Give that
		# receiver extra health so its production hit-stun can also be observed.
		if index == 2:
			raider.set("max_health", 6)
			raider.set("health", 6)
		raider.global_position = Vector2(1700.0, 100.0 + float(index) * 430.0)
		start_health[index + 1] = int(raider.get("health"))
		start_receives[index + 1] = int(_raider_hits[index + 1])
		start_attacks[index + 1] = int(_attack_hits[index + 1])
	_raiders[0].global_position = _player.global_position + _player.facing_direction * 58.0
	await _physics_frames(2)
	_trace.append("combo start: physics=%d player=%s target1=%s" % [Engine.get_physics_frames(), _player.global_position, _raiders[0].global_position])
	_tap(&"attack")
	for stage in range(1, 4):
		var target_index := stage - 1
		var target := _raiders[target_index]
		if stage > 1:
			_sample_stage = stage
		var active_seen := await _wait_for_stage_phase(stage, "active")
		_check(active_seen, "attack %d reached active through its real combo input and physics state" % stage)
		if not active_seen:
			return false
		_sample_stage = stage
		_sample_stage_hitbox = _player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
		var hitbox_active := _sample_stage_hitbox.monitoring
		var overlap_count := _sample_stage_hitbox.get_overlapping_bodies().size()
		_trace.append("stage %d active: physics=%d phase=%s hitbox=%s overlaps=%d health=%d time_scale=%.3f" % [stage, Engine.get_physics_frames(), _player.attack_phase, hitbox_active, overlap_count, int(target.get("health")), Engine.time_scale])
		_check(hitbox_active, "attack %d active phase enables its actual Area2D hitbox" % stage)
		# Read the live Window immediately on the first observed active physics
		# frame. Waiting for a pose-blend update first can outlast this short phase.
		await _capture_timeline("0%d · ATTACK %d ACTIVE" % [stage * 2 + 2, stage], "physics=%d · hitbox monitoring=%s" % [Engine.get_physics_frames(), hitbox_active], 0)
		var blender := _player.get_node("VisualRoot/PoseBlender")
		var expected_key := "attack%d_contact" % stage
		var expected_path := APPROVED_ATTACK1
		if stage == 2:
			expected_path = APPROVED_ATTACK2
		elif stage == 3:
			expected_path = APPROVED_ATTACK3
		var pose_ready := await _wait_for_approved_pose(blender, expected_key, expected_path)
		_check(pose_ready, "attack %d displays its approved contact keypose" % stage)
		# Capture runs independently; its render/readback waits must not delay the
		# physical-frame event observer or the next recovery input.
		var hit_seen := await _wait_for_hit(stage)
		_check(hit_seen, "attack %d emits its actual hit signal" % stage)
		_check(_raider_hits[target_index + 1] > int(start_receives[target_index + 1]), "attack %d target emits raider_hit" % stage)
		_check(int(target.get("health")) < int(start_health[target_index + 1]), "attack %d reduces real Raider health" % stage)
		_check(float(_hitstun_at_contact.get(stage, 0.0)) > 0.0, "attack %d applies real Raider hit-stun at its contact event" % stage)
		_check(_attack_hits[stage] > int(start_attacks[stage]), "attack %d hit signal corresponds to a live hitbox overlap" % stage)
		_check(hitbox_active and overlap_count > 0, "attack %d is recorded with its enabled live hitbox overlapping a body" % stage)
		# Move the completed receiver away to make each strike's health and signal
		# evidence unambiguous. Its production hit handling remains enabled.
		target.global_position = Vector2(1700.0, 100.0 + float(target_index) * 430.0)
		_reset_raider_for_live_combo(target)
		var hitstop_deadline := Time.get_ticks_msec() + 700
		while not _hitstop_seen[stage] and Time.get_ticks_msec() < hitstop_deadline and not _expired():
			await process_frame
		_check(_hitstop_seen[stage], "attack %d real hit enters hit-stop" % stage)
		_trace.append("stage %d contact: raider=%d hp=%d->%d raider_hit=%d attack_hit=%d hitstop=%s" % [stage, target_index + 1, int(start_health[target_index + 1]), int(target.get("health")), _raider_hits[target_index + 1], _attack_hits[stage], _hitstop_seen[stage]])
		_sample_stage = 0
		if stage < 3:
			_raiders[target_index].global_position = Vector2(1700.0, 100.0 + float(target_index) * 430.0)
			_reset_raider_for_live_combo(_raiders[target_index])
			var recovery_seen := await _wait_for_stage_phase(stage, "recovery")
			_check(recovery_seen, "attack %d reaches recovery before its combo input buffer press" % stage)
			if not recovery_seen:
				return false
			if stage == 2:
				await _capture_timeline("07 · ATTACK 2 RECOVERY", "stage 2 return motion · temporary transforms · physics=%d" % Engine.get_physics_frames(), 0)
			var next_target_distance := 58.0 if stage == 1 else 100.0
			_raiders[target_index + 1].global_position = _player.global_position + _player.facing_direction * next_target_distance
			_reset_raider_for_live_combo(_raiders[target_index + 1])
			var input_buffered := await _tap(&"attack")
			_check(input_buffered, "attack %d input is buffered on a physical frame" % stage)
			var next_started := await _wait_for_stage_phase(stage + 1, "startup")
			_check(next_started, "combo buffer advances from attack %d to attack %d" % [stage, stage + 1])
			if not next_started:
				return false
			if stage + 1 == 2:
				await _capture_timeline("05 · ATTACK 2 STARTUP", "stage 2 v8 alignment · temporary turn motion · physics=%d" % Engine.get_physics_frames(), 0)
	var final_recovery_seen := await _wait_for_stage_phase(3, "recovery")
	_check(final_recovery_seen, "attack 3 reaches its real recovery phase after contact and hit-stop")
	if not final_recovery_seen:
		return false
	var combo_idle := await _wait_for_combo_idle()
	_check(combo_idle and float(_player.get("attack_buffer_remaining")) <= 0.0, "final recovery clears the combo and returns Player to idle")
	if not combo_idle:
		return false
	var idle_position := _player.global_position
	_press(&"move_right")
	await _physics_frames(6)
	_release(&"move_right")
	_check(_player.global_position.x > idle_position.x + 1.0 and str(_player.get("attack_phase")) == "idle", "normal Player movement resumes after the three-hit combo")
	return true

func _reset_raider_for_live_combo(raider: Node) -> void:
	# Leave normal Raider physics/AI active, but clear any attack that began while
	# the player was moving into the test encounter. The next target can still
	# wind up, receive the live combo hit, and react through the production code.
	raider.set("attack_phase", "idle")
	raider.set("attack_phase_remaining", 0.0)
	raider.set("hitstun_remaining", 0.0)
	raider.set("velocity", Vector2.ZERO)
	var attack_area := raider.get_node_or_null("AttackArea") as Area2D
	if attack_area != null:
		attack_area.monitoring = false
	var attack_flash := raider.get_node_or_null("VisualRoot/AttackFlash") as Polygon2D
	if attack_flash != null:
		attack_flash.visible = false

func _wait_for_stage_phase(stage: int, phase: String) -> bool:
	var deadline := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline and not _expired():
		await physics_frame
		_sample_physics()
		if int(_player.get("attack_stage")) == stage and str(_player.get("attack_phase")) == phase:
			return true
	return false

func _wait_for_hit(stage: int) -> bool:
	var deadline := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline and not _expired():
		await physics_frame
		_sample_physics()
		if _attack_hits[stage] > 0:
			return true
	return false

func _wait_for_combo_idle() -> bool:
	var deadline := Time.get_ticks_msec() + 2500
	while Time.get_ticks_msec() < deadline and not _expired():
		if int(_player.get("attack_stage")) == 0 and str(_player.get("attack_phase")) == "idle":
			return true
		await physics_frame
	return int(_player.get("attack_stage")) == 0 and str(_player.get("attack_phase")) == "idle"

func _wait_for_approved_pose(blender: Node, expected_key: String, expected_path: String) -> bool:
	var deadline := Time.get_ticks_msec() + 700
	while Time.get_ticks_msec() < deadline and not _expired():
		if bool(blender.visible) and blender.get_current_pose_key() == expected_key and _blender_has_texture(blender, expected_path):
			return true
		await process_frame
	return false

func _sample_physics() -> void:
	if _sample_stage <= 0 or _player == null or _sample_stage_hitbox == null:
		return
	var overlap_count := _sample_stage_hitbox.get_overlapping_bodies().size() if _sample_stage_hitbox.monitoring else 0
	if str(_player.get("attack_phase")) != "idle":
		_trace.append("physics=%d stage=%d phase=%s hitbox=%s overlaps=%d player_hp=%d raider_hp=%d hitstun=%.3f hitstop=%s" % [Engine.get_physics_frames(), _sample_stage, str(_player.get("attack_phase")), _sample_stage_hitbox.monitoring, overlap_count, int(_player.get("health")), int(_raiders[_sample_stage - 1].get("health")), float(_raiders[_sample_stage - 1].get("hitstun_remaining")), Engine.time_scale < 0.99])
	if Engine.time_scale < 0.99:
		_hitstop_seen[_sample_stage] = true

func _monitor_combat_physics() -> void:
	while _combat_monitor_active and not _expired():
		await physics_frame
		if _player == null or not is_instance_valid(_player):
			continue
		var physics_frame_number := Engine.get_physics_frames()
		var stage := int(_player.get("attack_stage"))
		var phase := str(_player.get("attack_phase"))
		var phase_key := "%d:%s" % [stage, phase]
		if stage >= 1 and stage <= 3 and phase in ["startup", "active", "recovery"]:
			_phase_frame_counts[phase_key] = int(_phase_frame_counts.get(phase_key, 0)) + 1
			var active_expected := phase == "active"
			var stage_hitbox := _player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
			if stage_hitbox.monitoring != active_expected:
				_phase_hitbox_mismatches[stage] = int(_phase_hitbox_mismatches.get(stage, 0)) + 1
		if phase_key != _last_observed_phase:
			_trace.append("combat phase physics=%d stage=%d phase=%s remaining=%.4f hitbox_active_frames=%d mismatches=%d buffer=%.4f" % [physics_frame_number, stage, phase, float(_player.get("attack_phase_remaining")), int(_phase_frame_counts.get(phase_key, 0)), int(_phase_hitbox_mismatches.get(stage, 0)), float(_player.get("attack_buffer_remaining"))])
			_last_observed_phase = phase_key
		var hitstop_active := Engine.time_scale < 0.99
		if hitstop_active:
			if stage >= 1 and stage <= 3:
				_hitstop_seen[stage] = true
			if not _last_observed_hitstop:
				_trace.append("hit-stop physics=%d stage=%d scale=%.3f" % [physics_frame_number, stage, Engine.time_scale])
		elif _last_observed_hitstop:
			_trace.append("hit-stop ended physics=%d stage=%d scale=%.3f" % [physics_frame_number, stage, Engine.time_scale])
		_last_observed_hitstop = hitstop_active
		if float(_player.get("attack_buffer_remaining")) > 0.0:
			_trace.append("attack buffer physics=%d stage=%d phase=%s remaining=%.4f" % [physics_frame_number, stage, phase, float(_player.get("attack_buffer_remaining"))])

func _on_attack_hit(stage: int) -> void:
	_attack_hits[stage] = int(_attack_hits.get(stage, 0)) + 1
	_hit_targets[stage] = true
	if stage >= 1 and stage <= _raiders.size():
		_hitstun_at_contact[stage] = float(_raiders[stage - 1].get("hitstun_remaining"))
	call_deferred("_observe_hitstop", stage)
	call_deferred("_retain_latest_real_impact")

func _retain_latest_real_impact() -> void:
	var impacts := get_nodes_in_group("combat_impacts")
	if impacts.is_empty():
		return
	var impact := impacts.back() as Node2D
	if impact != null and is_instance_valid(impact):
		impact.set("lifetime", 5.0)
		impact.set("_start_ticks_usec", Time.get_ticks_usec())
		impact.queue_redraw()

func _observe_hitstop(stage: int) -> void:
	if Engine.time_scale < 0.99:
		_hitstop_seen[stage] = true
		_trace.append("stage %d hit-stop entered at physics=%d scale=%.3f" % [stage, Engine.get_physics_frames(), Engine.time_scale])

func _on_raider_hit(stage: int, target_index: int) -> void:
	_raider_hits[target_index] = int(_raider_hits.get(target_index, 0)) + 1
	_trace.append("raider %d received attack stage %d at physics=%d health=%d" % [target_index, stage, Engine.get_physics_frames(), int(_raiders[target_index - 1].get("health"))])

func _on_player_hit(stage: int) -> void:
	_trace.append("player received attack stage %d at physics=%d health=%d position=%s" % [stage, Engine.get_physics_frames(), int(_player.get("health")), _player.global_position])

func _on_raider_windup_started(target_index: int) -> void:
	_trace.append("raider %d begins windup at physics=%d position=%s" % [target_index, Engine.get_physics_frames(), _raiders[target_index - 1].global_position])

func _tap(action: StringName) -> bool:
	_press(action)
	await physics_frame
	# Input.action_press is observed by the Player on the following physics
	# tick in a Window run. Keep it down until that tick before sampling buffer.
	await physics_frame
	var input_buffered := false
	if action == &"attack" and _player != null:
		_trace.append("attack input physics=%d phase=%s stage=%d buffer=%.4f" % [Engine.get_physics_frames(), str(_player.get("attack_phase")), int(_player.get("attack_stage")), float(_player.get("attack_buffer_remaining"))])
		input_buffered = float(_player.get("attack_buffer_remaining")) > 0.0 or (str(_player.get("attack_phase")) == "startup" and int(_player.get("attack_stage")) > 1)
	_release(action)
	await physics_frame
	return input_buffered

func _press(action: StringName) -> void:
	Input.action_press(action)
	if not _live_pressed.has(action):
		_live_pressed.append(action)

func _release(action: StringName) -> void:
	Input.action_release(action)
	_live_pressed.erase(action)

func _release_all() -> void:
	for action in _live_pressed:
		Input.action_release(action)
	_live_pressed.clear()
	for action in [&"move_left", &"move_right", &"move_up", &"move_down", &"attack"]:
		Input.action_release(action)

func _physics_frames(count: int) -> void:
	for _frame in range(count):
		if _expired():
			break
		await physics_frame
		_sample_physics()

func _capture_timeline(title: String, subtitle: String, warmup_frames := 2) -> void:
	if _expired():
		_check(false, "capture completes before the overall time limit")
		return
	if title.contains("ATTACK 2 STARTUP"):
		_check(int(_player.get("attack_stage")) == 2 and str(_player.get("attack_phase")) == "startup", "stage two startup Window frame is captured inside the real startup phase")
	if title.contains("ATTACK 1 ACTIVE") or title.contains("ATTACK 2 ACTIVE") or title.contains("ATTACK 3 ACTIVE"):
		var expected_stage := 1 if title.contains("ATTACK 1 ACTIVE") else (2 if title.contains("ATTACK 2 ACTIVE") else 3)
		_check(int(_player.get("attack_stage")) == expected_stage and str(_player.get("attack_phase")) == "active", "stage %d active Window frame is captured inside the real active phase" % expected_stage)
	elif title.contains("ATTACK 2 RECOVERY"):
		_check(int(_player.get("attack_stage")) == 2 and str(_player.get("attack_phase")) == "recovery", "stage two recovery Window frame is captured inside the real recovery phase")
	_player.queue_redraw()
	(_player.get_node("VisualRoot/PlayerArt") as Sprite2D).queue_redraw()
	(_player.get_node("VisualRoot/PoseBlender") as Node2D).queue_redraw()
	for raider in _raiders:
		raider.queue_redraw()
		(raider.get_node("VisualRoot/RaiderArt") as Sprite2D).queue_redraw()
	var image: Image
	var animator_state := "unavailable"
	var frame_index := -1
	var frame_count := 0
	var frame_label := "unavailable"
	var frame_elapsed := 0.0
	var frame_duration := 0.0
	var frame_status := "unavailable"
	var texture_path := ""
	var art_frame := -1
	var art_frame_count := 0
	var art_frame_duration := 0.0
	var art_frame_elapsed := 0.0
	var art_frame_label := "unavailable"
	if warmup_frames <= 0:
		# Phase-specific keyposes must be sampled without waiting for more physics
		# ticks; active windows are shorter than a slow Window readback cycle.
		image = root.get_texture().get_image()
	else:
		for _frame in range(warmup_frames):
			await process_frame
			await RenderingServer.frame_post_draw
		image = root.get_texture().get_image()
	if is_instance_valid(_player):
		var art := _player.get_node("VisualRoot/PlayerArt") as Sprite2D
		var animator := _player.get_node("VisualAnimator")
		var pose_blender := _player.get_node("VisualRoot/PoseBlender")
		var camera := _player.get_node("Camera2D") as Camera2D
		animator_state = str(animator.get_animation_state())
		frame_index = int(animator.get_state_frame())
		frame_count = int(animator.get_state_frame_count())
		frame_label = str(animator.get_state_frame_label())
		frame_elapsed = float(animator.get_state_frame_elapsed())
		frame_duration = float(animator.get_state_frame_duration())
		frame_status = str(animator.get_state_frame_status())
		texture_path = str(animator.get_displayed_texture_path())
		art_frame = int(animator.get_art_frame_index())
		art_frame_count = int(animator.get_art_frame_count())
		art_frame_duration = float(animator.get_art_frame_duration())
		art_frame_elapsed = float(animator.get_art_frame_elapsed())
		art_frame_label = str(animator.get_art_frame_label())
		_trace.append("render %s: physics=%d stage=%d combat_phase=%s remaining=%.4f visual_state=%s frame=%d/%d label=%s time=%.4f/%.4f art_frame=%d/%d art_label=%s art_time=%.4f/%.4f art_status=%s texture=%s player=%s canvas=%s art_visible=%s in_tree=%s scale=%s modulate=%s camera=%s current=%s viewport=%s" % [title, Engine.get_physics_frames(), int(_player.get("attack_stage")), str(_player.get("attack_phase")), float(_player.get("attack_phase_remaining")), animator_state, frame_index + 1, frame_count, frame_label, frame_elapsed, frame_duration, art_frame + 1, art_frame_count, art_frame_label, art_frame_elapsed, art_frame_duration, frame_status, texture_path.get_file(), _player.global_position, art.get_global_transform_with_canvas().origin, art.visible, art.is_visible_in_tree(), art.global_scale, art.modulate, camera.global_position, camera.is_current(), root.get_visible_rect().size])
		subtitle += "\npose %d/%d %s %.3f/%.3fs · art %d/%d %s %.3f/%.3fs · %s · tex %s" % [frame_index + 1, frame_count, frame_label, frame_elapsed, frame_duration, art_frame + 1, art_frame_count, art_frame_label, art_frame_elapsed, art_frame_duration, frame_status, texture_path.get_file()]
	_check(image != null and not image.is_empty() and image.get_size() == CAPTURE_SIZE, "'%s' is captured from the real 1920x1080 Window Viewport readback" % title)
	if image != null and not image.is_empty() and image.get_size() == CAPTURE_SIZE:
		_check(await _captured_characters_are_visible(image), "'%s' contains a rendered scene and visible combat actors in the Window capture" % title)
		_timeline.append({"title": title, "subtitle": subtitle, "image": image, "texture": texture_path, "visual_state": animator_state, "frame": frame_index, "frame_count": frame_count, "frame_label": frame_label, "elapsed": frame_elapsed, "duration": frame_duration, "art_frame": art_frame, "art_frame_count": art_frame_count, "art_frame_label": art_frame_label, "art_elapsed": art_frame_elapsed, "art_frame_duration": art_frame_duration, "art_status": frame_status})

func _captured_characters_are_visible(captured: Image) -> bool:
	# Validate the real Window readback without hiding actors or pausing the live
	# scene. The independent physics observer owns all event and timing evidence.
	if captured == null or captured.is_empty() or captured.get_size() != CAPTURE_SIZE:
		return false
	var player_art := _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var pose_blender := _player.get_node("VisualRoot/PoseBlender") as Node2D
	if not player_art.is_visible_in_tree() and not pose_blender.is_visible_in_tree():
		return false
	var distinct_samples: Dictionary = {}
	for y in range(0, CAPTURE_SIZE.y, 16):
		for x in range(0, CAPTURE_SIZE.x, 16):
			distinct_samples[captured.get_pixel(x, y).to_rgba32()] = true
			if distinct_samples.size() >= 32:
				return true
	return false

func _build_comparison_board() -> void:
	_check(_timeline.size() >= 6, "timeline contains movement, reversal and every live combo stage")
	if _timeline.size() < 6:
		return
	if is_instance_valid(_game):
		_game.queue_free()
	await process_frame
	var board := Control.new()
	board.name = "CombatLiveSessionComparisonBoard"
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(board)
	var background := ColorRect.new()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.color = Color("#111b20")
	board.add_child(background)
	var header := Label.new()
	header.text = "LIVE COMBAT SESSION  ·  REAL PHYSICS / HITBOX / DAMAGE / HIT-STOP"
	header.position = Vector2(32, 18)
	header.size = Vector2(1850, 48)
	header.add_theme_font_size_override("font_size", 27)
	header.add_theme_color_override("font_color", Color("#f1e8cd"))
	board.add_child(header)
	# Nine chronological frames fit in a 3x3 board, including the final combo
	# completion frame. The previous 4-column layout clipped row three below the
	# 1080px viewport and hid that final result.
	var cell_w := 480.0
	var cell_h := 270.0
	var start_y := 76.0
	for index in range(_timeline.size()):
		var item: Dictionary = _timeline[index]
		var texture := ImageTexture.create_from_image(item["image"] as Image)
		var col := index % 3
		var row := index / 3
		var x := 112.0 + float(col) * 608.0
		var y := start_y + float(row) * 328.0
		var title := Label.new()
		title.text = str(item["title"])
		title.position = Vector2(x, y)
		title.size = Vector2(cell_w, 28)
		title.add_theme_font_size_override("font_size", 18)
		title.add_theme_color_override("font_color", Color("#eacb78"))
		board.add_child(title)
		var subtitle := Label.new()
		subtitle.text = str(item["subtitle"])
		subtitle.position = Vector2(x, y + 27)
		subtitle.size = Vector2(cell_w, 38)
		subtitle.add_theme_font_size_override("font_size", 10)
		subtitle.add_theme_color_override("font_color", Color("#bdd0ce"))
		board.add_child(subtitle)
		var frame := Sprite2D.new()
		frame.texture = texture
		frame.centered = false
		frame.position = Vector2(x, y + 68)
		frame.scale = Vector2(cell_w / float(CAPTURE_SIZE.x), (cell_h - 14.0) / float(CAPTURE_SIZE.y))
		board.add_child(frame)
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty() and image.get_size() == CAPTURE_SIZE, "timeline comparison board renders at 1920x1080 after frame_post_draw")
	if image != null and not image.is_empty() and image.get_size() == CAPTURE_SIZE:
		var save_error := image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		_check(save_error == OK, "real gameplay timeline comparison PNG is saved")
		if save_error == OK:
			print("combat-live-session-capture: saved %s" % OUTPUT_PATH)

func _blender_has_texture(blender: Node, path: String) -> bool:
	for child in blender.get_children():
		if child is Sprite2D and (child as Sprite2D).visible and (child as Sprite2D).texture != null:
			if (child as Sprite2D).texture.resource_path == path:
				return true
	return false

func _expired() -> bool:
	return Time.get_ticks_msec() - _started_msec > MAX_DURATION_MSEC

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	_release_all()
	if is_instance_valid(_player) and _player.has_method("get"):
		if bool(_player.get("_hit_stop_active")):
			_player.set("_hit_stop_token", int(_player.get("_hit_stop_token")) + 1)
			_player.set("_hit_stop_active", false)
			_player.set("_saved_time_scale", 1.0)
	Engine.time_scale = _saved_scale
	if _failures.is_empty():
		print("combat_live_session_window_smoke: all checks passed")
		quit(0)
		return
	for failure in _failures:
		push_error("combat_live_session_window_smoke: " + failure)
	push_error("combat_live_session_window_smoke: %d check(s) failed" % _failures.size())
	quit(1)
