extends SceneTree
"""Verifies keypad input against the live Player in a real Window run."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const CAPTURE_PATH := "display_num_input_window.png"
const REPORT_PATH := "display_num_input_window.txt"
const KEYPAD_CODES := [KEY_KP_1, KEY_KP_2, KEY_KP_3, KEY_KP_4, KEY_KP_5, KEY_KP_6, KEY_KP_7, KEY_KP_8, KEY_KP_9]
const ACTIONS := ["attack", "jump", "block", "skill_4", "skill_5", "skill_6", "skill_7", "skill_8", "skill_9"]

var _failures: Array[String] = []

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
	var metadata := [
		"display_server=%s" % DisplayServer.get_name(),
		"fullscreen_mode=%s (%d)" % [_mode_name(window_mode), window_mode],
		"screen_index=%d" % screen,
		"monitor_resolution=%s" % monitor_size,
		"window_size=%s" % window_size,
		"root_viewport_size=%s" % viewport_size,
		"render_area=%s" % render_rect,
		"physical_keyboard=NOT_TESTED (synthetic InputEventKey only)",
	]
	for line in metadata:
		print("DISPLAY_NUM_INPUT: " + line)
	print("PHYSICAL_KEYBOARD: NOT_TESTED (synthetic InputEventKey only)")
	_check(screen >= 0 and monitor_size.x > 0 and monitor_size.y > 0, "active monitor and resolution are available")
	_check(window_size.x > 0 and window_size.y > 0, "real Window has a nonzero size")
	_check(viewport_size.x > 0 and viewport_size.y > 0 and render_rect.size.x > 0.0 and render_rect.size.y > 0.0, "Window Viewport render area is nonzero")

	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_failures.append("main gameplay scene loads")
		_finish(metadata)
		return
	var game := packed.instantiate() as Node2D
	if game == null:
		_failures.append("main gameplay scene instantiates")
		_finish(metadata)
		return
	root.add_child(game)
	current_scene = game
	await process_frame
	var player := game.get_node_or_null("YSortActors/Player")
	if player == null:
		_failures.append("main gameplay scene contains its Player")
		_finish(metadata)
		return

	for index in range(KEYPAD_CODES.size()):
		var action: StringName = ACTIONS[index]
		var code: Key = KEYPAD_CODES[index]
		_check(_has_key(action, code), "Num%d keypad physical key is mapped to %s" % [index + 1, action])
		metadata.append("inputmap_%s_expected_key=%s (%d); configured=%s" % [action, OS.get_keycode_string(code), code, _mapped_keys(action)])
		var keypad_event := _key_event(code, true)
		_check(InputMap.event_is_action(keypad_event, action, false), "Num%d keypad event matches %s" % [index + 1, action])
		var top_row_event := _key_event(KEY_0 + index + 1, true)
		_check(not InputMap.event_is_action(top_row_event, action, false), "Num%d top-row key remains distinct from %s" % [index + 1, action])

		Input.parse_input_event(keypad_event)
		await process_frame
		await physics_frame
		_check(Input.is_action_pressed(action), "Num%d synthetic keypad event reaches InputMap action %s" % [index + 1, action])
		if index == 0:
			_check(str(player.get("attack_phase")) != "idle" and int(player.get("attack_stage")) == 1, "Num1 starts the real Player attack state")
		elif index == 1:
			_check(await _wait_for_player_flag(player, "is_jumping", true, 6), "Num2 changes the real Player jump state")
		elif index == 2:
			_check(await _wait_for_player_flag(player, "is_blocking", true, 6), "Num3 changes the real Player block state")
		else:
			_check(not bool(player.get("is_jumping")) and not bool(player.get("is_blocking")) and str(player.get("attack_phase")) == "idle", "Num%d remains a reserved skill action without an implemented Player move" % (index + 1))
		Input.parse_input_event(_key_event(code, false))
		await process_frame
		await physics_frame
		_check(not Input.is_action_pressed(action), "Num%d release clears %s" % [index + 1, action])
		if index == 1:
			_check(await _wait_for_player_flag(player, "is_jumping", false, 120), "Num2 jump completes and Player returns to ground")

	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and not frame.is_empty(), "actual Window Viewport produced a rendered image")
	var capture_absolute := OS.get_temp_dir().path_join(CAPTURE_PATH)
	var report_absolute := OS.get_temp_dir().path_join(REPORT_PATH)
	if frame != null and not frame.is_empty():
		_check(frame.save_png(capture_absolute) == OK, "actual Window Viewport evidence PNG is saved")
	else:
		_failures.append("actual Window Viewport evidence PNG is saved")
	metadata.append("capture_png=%s" % capture_absolute)
	metadata.append("report_file=%s" % report_absolute)
	print("DISPLAY_NUM_INPUT: capture_png=%s" % capture_absolute)
	print("DISPLAY_NUM_INPUT: report_file=%s" % report_absolute)
	metadata.append("synthetic_keypad_actions=attack,jump,block,skill_4,skill_5,skill_6,skill_7,skill_8,skill_9")
	metadata.append("reserved_skills=Num4-Num9 mapped in InputMap; no Player move implementation asserted")
	metadata.append("physical_keyboard_status=NOT_TESTED")
	_finish(metadata)

func _key_event(code: Key, is_pressed: bool) -> InputEventKey:
	var event := InputEventKey.new()
	event.device = 16
	# Carry the keypad code in both fields so the synthetic event reaches both
	# InputMap matching and runtime Input state while remaining distinct from
	# the top-row key tested separately above.
	event.keycode = code
	event.physical_keycode = code
	event.pressed = is_pressed
	return event

func _wait_for_player_flag(player: Node, property: StringName, expected: bool, max_physics_frames: int) -> bool:
	for _frame in range(max_physics_frames):
		if bool(player.get(property)) == expected:
			return true
		await physics_frame
	return bool(player.get(property)) == expected

func _has_key(action: StringName, code: Key) -> bool:
	if not InputMap.has_action(action):
		return false
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == code:
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
	_finish([])

func _finish(metadata: Array) -> void:
	var report_path := OS.get_temp_dir().path_join(REPORT_PATH)
	var report := FileAccess.open(report_path, FileAccess.WRITE)
	if report != null:
		for line in metadata:
			report.store_line(str(line))
		report.close()
	else:
		_failures.append("metadata report is written to %s" % report_path)
	if _failures.is_empty():
		print("display_num_input_window: all checks passed")
		quit(0)
		return
	if report != null and metadata.size() > 0:
		var failure_report := FileAccess.open(report_path, FileAccess.WRITE)
		if failure_report != null:
			for line in metadata:
				failure_report.store_line(str(line))
			failure_report.store_line("check_failures=%s" % "; ".join(_failures))
			failure_report.close()
	for failure in _failures:
		push_error("display_num_input_window: " + failure)
	push_error("display_num_input_window: %d check(s) failed" % _failures.size())
	quit(1)
