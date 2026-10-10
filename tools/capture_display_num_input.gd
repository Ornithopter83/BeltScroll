extends SceneTree
"""Verifies keypad input against the live Player in a real Window run."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const CAPTURE_PATH := "display_num_input_window.png"
const REPORT_PATH := "display_num_input_window.txt"
const KEYPAD_CODES := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]
const ACTIONS := ["attack", "jump", "block", "skill_1", "skill_2", "skill_6", "skill_7", "skill_8", "skill_9"]
const REPEAT_COUNT := 5

var _failures: Array[String] = []
var _metadata: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("A real Window display server is required; physical keyboard input is not tested by this automated run.")
		return

	var screen := DisplayServer.window_get_current_screen()
	var window_mode := DisplayServer.window_get_mode()
	var monitor_size := DisplayServer.screen_get_size(screen)
	var window_size := DisplayServer.window_get_size()
	var viewport_size := root.size
	var render_rect := root.get_visible_rect()
	_metadata = [
		"display_server=%s" % DisplayServer.get_name(),
		"fullscreen_mode=%s (%d)" % [_mode_name(window_mode), window_mode],
		"screen_index=%d" % screen,
		"monitor_resolution=%s" % monitor_size,
		"window_size=%s" % window_size,
		"root_viewport_size=%s" % viewport_size,
		"render_area=%s" % render_rect,
		"physical_keyboard=NOT_TESTED (synthetic InputEventKey only)",
	]
	for line in _metadata:
		print("DISPLAY_NUM_INPUT: " + line)
	print("PHYSICAL_KEYBOARD: NOT_TESTED (synthetic InputEventKey only)")
	_check(screen >= 0 and monitor_size.x > 0 and monitor_size.y > 0, "active monitor and resolution are available")
	_check(window_size.x > 0 and window_size.y > 0, "real Window has a nonzero size")
	_check(viewport_size.x > 0 and viewport_size.y > 0 and render_rect.size.x > 0.0 and render_rect.size.y > 0.0, "Window Viewport render area is nonzero")

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_failures.append("main gameplay scene loads")
		_finish()
		return
	var game := packed.instantiate() as Node2D
	if game == null:
		_failures.append("main gameplay scene instantiates")
		_finish()
		return
	root.add_child(game)
	current_scene = game
	await process_frame
	var player := game.get_node_or_null("YSortActors/Player")
	if player == null:
		_failures.append("main gameplay scene contains its Player")
		_finish()
		return
	if not _has_property(player, "is_jumping") or not _has_property(player, "attack_phase"):
		_failures.append("live Player script exposes jump and attack state; inspect Player script parse/runtime errors")
		_finish()
		return

	for index in range(KEYPAD_CODES.size()):
		var action: StringName = ACTIONS[index]
		var code: Key = KEYPAD_CODES[index]
		_check(_has_key(action, code), "Num%d keypad physical key is mapped to %s" % [index + 1, action])
		_metadata.append("inputmap_%s_expected_key=%s (%d); configured=%s" % [action, OS.get_keycode_string(code), code, _mapped_keys(action)])
		var keypad_event := _key_event(code, true)
		_check(InputMap.event_is_action(keypad_event, action, false), "Num%d keypad event matches %s" % [index + 1, action])
		var top_row_event := _key_event(KEY_0 + index + 1, true)
		_check(not InputMap.event_is_action(top_row_event, action, false), "Num%d top-row key remains distinct from %s" % [index + 1, action])

		if index == 0:
			Input.parse_input_event(keypad_event)
			await process_frame
			await physics_frame
			_check(Input.is_action_pressed(action), "Num1 synthetic keypad event reaches InputMap action attack")
			_check(str(player.get("attack_phase")) == "startup" or str(player.get("attack_phase")) == "active", "Num1 starts the real Player attack state")
			Input.parse_input_event(_key_event(code, false))
			await process_frame
			await physics_frame
			_check(not Input.is_action_pressed(action), "Num1 release clears attack")
			await _verify_jump_is_blocked_during_attack(player)
		elif index == 1:
			for repetition in range(REPEAT_COUNT):
				await _wait_for_attack_idle(player, 180)
				_check(str(player.get("attack_phase")) == "idle", "Num2 repetition %d begins at complete attack idle" % (repetition + 1))
				_check(await _verify_jump_cycle(player, repetition + 1), "Num2 repetition %d observes rise, fall, and landing on physics frames" % (repetition + 1))
		else:
			Input.parse_input_event(keypad_event)
			await process_frame
			await physics_frame
			_check(Input.is_action_pressed(action), "Num%d synthetic keypad event reaches InputMap action %s" % [index + 1, action])
			if index == 2:
				_check(await _wait_for_player_flag(player, "is_blocking", true, 6), "Num3 changes the real Player block state")
			elif index == 3 or index == 4:
				var expected_skill := index - 2
				_check(await _wait_for_skill_start(player, expected_skill, 6), "Num%d starts the real Player skill %d state" % [index + 1, expected_skill])
				await _wait_for_skill_idle(player, 240)
			else:
				_check(int(player.get("skill_id")) == 0 and str(player.get("skill_phase")) == "idle", "Num%d remains reserved without starting a Player skill" % (index + 1))
			Input.parse_input_event(_key_event(code, false))
			await process_frame
			await physics_frame
			_check(not Input.is_action_pressed(action), "Num%d release clears %s" % [index + 1, action])

	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and not frame.is_empty(), "actual Window Viewport produced a rendered image")
	var capture_absolute := OS.get_temp_dir().path_join(CAPTURE_PATH)
	var report_absolute := OS.get_temp_dir().path_join(REPORT_PATH)
	if frame != null and not frame.is_empty():
		_check(frame.save_png(capture_absolute) == OK, "actual Window Viewport evidence PNG is saved")
	else:
		_failures.append("actual Window Viewport evidence PNG is saved")
	_metadata.append("capture_png=%s" % capture_absolute)
	_metadata.append("report_file=%s" % report_absolute)
	_metadata.append("synthetic_keypad_actions=attack,jump,block,skill_1,skill_2,skill_6,skill_7,skill_8,skill_9")
	_metadata.append("implemented_skills=Num4:skill_1,Num5:skill_2; reserved_skills=Num6-Num9")
	_metadata.append("num2_jump_repetitions=%d" % REPEAT_COUNT)
	_metadata.append("num2_attack_gate=recovery_and_combo_hold_blocked_then_idle_jump_allowed")
	_metadata.append("physical_keyboard_status=NOT_TESTED")
	print("DISPLAY_NUM_INPUT: num2_jump_repetitions=%d" % REPEAT_COUNT)
	print("DISPLAY_NUM_INPUT: num2_attack_gate=recovery_and_combo_hold_blocked_then_idle_jump_allowed")
	print("DISPLAY_NUM_INPUT: capture_png=%s" % capture_absolute)
	print("DISPLAY_NUM_INPUT: report_file=%s" % report_absolute)
	_finish()

func _verify_jump_is_blocked_during_attack(player: Node) -> void:
	_check(await _wait_for_attack_phase(player, "recovery", 30), "Num1 reaches recovery before the blocked Num2 probe")
	Input.parse_input_event(_key_event(KEY_KP_2, true))
	await process_frame
	await physics_frame
	_check(Input.is_action_pressed("jump"), "Num2 is received by InputMap during attack recovery")
	_check(not bool(player.get("is_jumping")), "Num2 does not jump during attack recovery")
	_check(await _wait_for_attack_phase(player, "combo_hold", 30), "Num1 proceeds from recovery to combo_hold")
	_check(not bool(player.get("is_jumping")), "Num2 remains blocked during combo_hold")
	Input.parse_input_event(_key_event(KEY_KP_2, false))
	await process_frame
	await physics_frame
	_check(not Input.is_action_pressed("jump"), "Num2 release clears the buffered attack probe")
	await _wait_for_attack_idle(player, 120)
	_check(str(player.get("attack_phase")) == "idle", "attack recovery and combo_hold fully finish before idle jump probe")
	_metadata.append("attack_num2_probe=recovery_pressed_and_combo_hold_blocked")

func _verify_jump_cycle(player: Node, repetition: int) -> bool:
	var start_height := float(player.get("jump_height_offset"))
	Input.parse_input_event(_key_event(KEY_KP_2, true))
	await process_frame
	var saw_rise := false
	var saw_fall := false
	var saw_landing := false
	var peak_height := start_height
	var max_frames := 100
	for physics_index in range(max_frames):
		await physics_frame
		# SceneTree.physics_frame is emitted before nodes receive their
		# _physics_process callbacks. Wait for the frame's process callbacks
		# before sampling Player state so this is a post-physics observation.
		await process_frame
		var height := float(player.get("jump_height_offset"))
		var velocity := float(player.get("jump_vertical_velocity"))
		var jumping := bool(player.get("is_jumping"))
		peak_height = maxf(peak_height, height)
		if jumping and height > start_height + 0.01 and velocity < 0.0:
			saw_rise = true
		if saw_rise and jumping and velocity >= 0.0:
			saw_fall = true
		if saw_rise and not jumping and height <= 0.0:
			saw_landing = true
			break
		if physics_index == 0:
			_check(jumping, "Num2 starts a Player jump on the first eligible physics frame (run %d)" % repetition)
	Input.parse_input_event(_key_event(KEY_KP_2, false))
	await process_frame
	await physics_frame
	_check(Input.is_action_pressed("jump") == false, "Num2 release clears after jump run %d" % repetition)
	_metadata.append("num2_run_%d=rise:%s,fall:%s,land:%s,peak_height:%.3f" % [repetition, saw_rise, saw_fall, saw_landing, peak_height])
	return saw_rise and saw_fall and saw_landing and peak_height > 0.0

func _wait_for_attack_phase(player: Node, phase: String, max_physics_frames: int) -> bool:
	for _frame in range(max_physics_frames):
		if str(player.get("attack_phase")) == phase:
			return true
		await physics_frame
	return str(player.get("attack_phase")) == phase

func _wait_for_attack_idle(player: Node, max_physics_frames: int) -> void:
	for _frame in range(max_physics_frames):
		if str(player.get("attack_phase")) == "idle" and float(player.get("hitstun_remaining")) <= 0.0 and not bool(player.get("is_blocking")):
			return
		await physics_frame
	_check(str(player.get("attack_phase")) == "idle" and float(player.get("hitstun_remaining")) <= 0.0 and not bool(player.get("is_blocking")), "Player is free before idle jump verification")

func _wait_for_player_flag(player: Node, property: StringName, expected: bool, max_physics_frames: int) -> bool:
	for _frame in range(max_physics_frames):
		if bool(player.get(property)) == expected:
			return true
		await physics_frame
	return bool(player.get(property)) == expected

func _wait_for_skill_idle(player: Node, max_physics_frames: int) -> void:
	for _frame in range(max_physics_frames):
		if str(player.get("skill_phase")) == "idle":
			return
		await physics_frame
	_check(str(player.get("skill_phase")) == "idle", "skill input returns Player control after recovery")

func _wait_for_skill_start(player: Node, skill_id: int, max_physics_frames: int) -> bool:
	for _frame in range(max_physics_frames):
		if int(player.get("skill_id")) == skill_id and str(player.get("skill_phase")) != "idle":
			return true
		await physics_frame
	return int(player.get("skill_id")) == skill_id and str(player.get("skill_phase")) != "idle"

func _key_event(code: Key, is_pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = 16
	event.keycode = code
	event.physical_keycode = code
	event.pressed = is_pressed
	return event

func _has_key(action: StringName, code: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
			return true
	return false

func _has_property(object: Object, property_name: StringName) -> bool:
	for property in object.get_property_list():
		if StringName(property.get("name", "")) == property_name:
			return true
	return false

func _mapped_keys(action: StringName) -> String:
	var keys: Array[String] = []
	if not InputMap.has_action(action):
		return "<missing action>"
	for event in InputMap.action_get_events(action):
		if event is InputEventKey:
			var key := event as InputEventKey
			keys.append("%s (%d)" % [OS.get_keycode_string(key.physical_keycode), key.physical_keycode])
	return ", ".join(keys)

func _mode_name(mode: int) -> String:
	match mode:
		DisplayServer.WINDOW_MODE_WINDOWED:
			return "windowed"
		DisplayServer.WINDOW_MODE_MINIMIZED:
			return "minimized"
		DisplayServer.WINDOW_MODE_MAXIMIZED:
			return "maximized"
		DisplayServer.WINDOW_MODE_FULLSCREEN:
			return "fullscreen"
		DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN:
			return "exclusive_fullscreen"
		_:
			return "unknown"

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _fail(message: String) -> void:
	_failures.append(message)
	_finish()

func _finish() -> void:
	var report_path := OS.get_temp_dir().path_join(REPORT_PATH)
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	if report != null:
		for line in _metadata:
			report.store_line(str(line))
		if not _failures.is_empty():
			report.store_line("check_failures=%s" % "; ".join(_failures))
		report.close()
	else:
		_failures.append("metadata report is written to %s" % report_path)
	if _failures.is_empty():
		print("display_num_input_window: all checks passed")
		quit(0)
		return
	for failure in _failures:
		push_error("display_num_input_window: " + failure)
	push_error("display_num_input_window: %d check(s) failed" % _failures.size())
	quit(1)
