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
var _live_pressed: Array[StringName] = []
var _sample_stage := 0
var _sample_stage_hitbox: Area2D

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
		_raiders[index].global_position = Vector2(1700.0, 100.0 + float(index) * 430.0)
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
		_check(_attack_hits[1] > 0 and _attack_hits[2] > 0 and _attack_hits[3] > 0, "all three attack_hit signals came from live active hitboxes")
		_check(_hitstop_seen[1] and _hitstop_seen[2] and _hitstop_seen[3], "hit-stop was observed during all three real hit events")
		await _capture_timeline("07 · COMBO COMPLETE", "Three live attack phases · confirmed health and hit events")
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
		var blender := _player.get_node("VisualRoot/PoseBlender")
		var expected_key := "attack%d_contact" % stage
		var expected_path := APPROVED_ATTACK1
		if stage == 2:
			expected_path = APPROVED_ATTACK2
		elif stage == 3:
			expected_path = APPROVED_ATTACK3
		var pose_ready := await _wait_for_approved_pose(blender, expected_key, expected_path)
		_check(pose_ready, "attack %d displays its approved contact keypose" % stage)
		await _capture_timeline("0%d · ATTACK %d ACTIVE" % [stage + 3, stage], "physics=%d · hitbox monitoring=%s" % [Engine.get_physics_frames(), hitbox_active])
		var hit_seen := await _wait_for_hit(stage)
		_check(hit_seen, "attack %d emits its actual hit signal" % stage)
		_check(_raider_hits[target_index + 1] > int(start_receives[target_index + 1]), "attack %d target emits raider_hit" % stage)
		_check(int(target.get("health")) < int(start_health[target_index + 1]), "attack %d reduces real Raider health" % stage)
		_check(_attack_hits[stage] > int(start_attacks[stage]), "attack %d hit signal corresponds to a live hitbox overlap" % stage)
		_check(hitbox_active and overlap_count > 0, "attack %d is recorded with its enabled live hitbox overlapping a body" % stage)
		# Once contact is observed, clear the target's concurrent retaliation so
		# the capture measures the Player's buffered combo through hit-stop/recovery.
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
			_raiders[target_index + 1].global_position = _player.global_position + _player.facing_direction * 58.0
			_reset_raider_for_live_combo(_raiders[target_index + 1])
			var recovery_seen := await _wait_for_stage_phase(stage, "recovery")
			_check(recovery_seen, "attack %d reaches recovery before its combo input buffer press" % stage)
			if not recovery_seen:
				return false
			_tap(&"attack")
			var next_started := await _wait_for_stage_phase(stage + 1, "startup")
			_check(next_started, "combo buffer advances from attack %d to attack %d" % [stage, stage + 1])
			if not next_started:
				return false
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

func _on_attack_hit(stage: int) -> void:
	_attack_hits[stage] = int(_attack_hits.get(stage, 0)) + 1
	_hit_targets[stage] = true
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

func _tap(action: StringName) -> void:
	_press(action)
	await process_frame
	if action == &"attack" and _player != null:
		_trace.append("attack tap: physics=%d phase=%s stage=%d buffer=%.3f" % [Engine.get_physics_frames(), str(_player.get("attack_phase")), int(_player.get("attack_stage")), float(_player.get("attack_buffer_remaining"))])
	_release(action)
	await process_frame

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

func _capture_timeline(title: String, subtitle: String) -> void:
	if _expired():
		_check(false, "capture completes before the overall time limit")
		return
	_player.queue_redraw()
	(_player.get_node("VisualRoot/PlayerArt") as Sprite2D).queue_redraw()
	(_player.get_node("VisualRoot/PoseBlender") as Node2D).queue_redraw()
	for raider in _raiders:
		raider.queue_redraw()
		(raider.get_node("VisualRoot/RaiderArt") as Sprite2D).queue_redraw()
	for _frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	if is_instance_valid(_player):
		var art := _player.get_node("VisualRoot/PlayerArt") as Sprite2D
		var camera := _player.get_node("Camera2D") as Camera2D
		_trace.append("render %s: player=%s canvas=%s art_visible=%s in_tree=%s scale=%s modulate=%s texture=%s camera=%s current=%s viewport=%s" % [title, _player.global_position, art.get_global_transform_with_canvas().origin, art.visible, art.is_visible_in_tree(), art.global_scale, art.modulate, art.texture.get_size() if art.texture != null else Vector2.ZERO, camera.global_position, camera.is_current(), root.get_visible_rect().size])
	var image := root.get_texture().get_image()
	_check(image != null and not image.is_empty() and image.get_size() == CAPTURE_SIZE, "'%s' is captured from the real 1920x1080 Window Viewport after frame_post_draw" % title)
	if image != null and not image.is_empty() and image.get_size() == CAPTURE_SIZE:
		_check(await _captured_characters_are_visible(image), "'%s' contains rendered Player/Raider pixels in the Window capture" % title)
		_timeline.append({"title": title, "subtitle": subtitle, "image": image})

func _captured_characters_are_visible(captured: Image) -> bool:
	# Compare the captured frame with a same-state render that hides only actor
	# art. This verifies visible sprite pixels reached the Window texture, rather
	# than trusting node visibility or texture state alone.
	var visuals: Array[CanvasItem] = [
		_player.get_node("VisualRoot/PlayerArt") as CanvasItem,
		_player.get_node("VisualRoot/PoseBlender") as CanvasItem
	]
	for raider in _raiders:
		visuals.append(raider.get_node("VisualRoot/RaiderArt") as CanvasItem)
	var prior_visibility: Array[bool] = []
	for visual in visuals:
		prior_visibility.append(visual.visible)
	var prior_process_mode := _game.process_mode
	_game.process_mode = Node.PROCESS_MODE_DISABLED
	for visual in visuals:
		visual.visible = false
	await process_frame
	await RenderingServer.frame_post_draw
	var without_actor_art := root.get_texture().get_image()
	for index in range(visuals.size()):
		visuals[index].visible = prior_visibility[index]
	_game.process_mode = prior_process_mode
	await process_frame
	await RenderingServer.frame_post_draw
	if without_actor_art == null or without_actor_art.is_empty() or without_actor_art.get_size() != captured.get_size():
		return false
	var changed_pixels := 0
	for y in range(CAPTURE_SIZE.y):
		for x in range(CAPTURE_SIZE.x):
			if captured.get_pixel(x, y) != without_actor_art.get_pixel(x, y):
				changed_pixels += 1
				if changed_pixels >= 100:
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
	var cell_w := 456.0
	var cell_h := 256.5
	var start_y := 84.0
	for index in range(_timeline.size()):
		var item: Dictionary = _timeline[index]
		var texture := ImageTexture.create_from_image(item["image"] as Image)
		var col := index % 4
		var row := index / 4
		var x := 24.0 + float(col) * 472.0
		var y := start_y + float(row) * 492.0
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
		subtitle.size = Vector2(cell_w, 24)
		subtitle.add_theme_font_size_override("font_size", 12)
		subtitle.add_theme_color_override("font_color", Color("#bdd0ce"))
		board.add_child(subtitle)
		var frame := Sprite2D.new()
		frame.texture = texture
		frame.centered = false
		frame.position = Vector2(x, y + 54)
		frame.scale = Vector2(cell_w / float(CAPTURE_SIZE.x), cell_h / float(CAPTURE_SIZE.y))
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
