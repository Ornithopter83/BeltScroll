extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(_has_event("move_left", 0, -1.0), "left stick is mapped to horizontal movement")
	_check(_has_event("move_up", 1, -1.0), "left stick is mapped to vertical movement")
	_check(_has_button("move_left", JOY_BUTTON_DPAD_LEFT) and _has_button("move_right", JOY_BUTTON_DPAD_RIGHT) and _has_button("move_up", JOY_BUTTON_DPAD_UP) and _has_button("move_down", JOY_BUTTON_DPAD_DOWN), "D-pad buttons are mapped to movement")
	_check(_has_button("jump", JOY_BUTTON_A), "south button is mapped to jump")
	_check(_has_button("attack", JOY_BUTTON_X), "west button is mapped to attack")
	_check(_has_button("sit", JOY_BUTTON_B), "east button is mapped to sit")
	_check(_has_button("pause", JOY_BUTTON_START) and _has_button("help", JOY_BUTTON_BACK), "Start and Select are mapped to session actions")
	_check(_has_button("restart", JOY_BUTTON_Y), "north button is mapped to result restart")
	_check(_has_key("pause", KEY_ESCAPE) and _has_key("help", KEY_H) and _has_key("restart", KEY_R), "Escape, H and R remain on the shared actions")
	_check(_has_button("ui_accept", JOY_BUTTON_A) and _has_button("ui_cancel", JOY_BUTTON_B), "menu confirm and cancel are mapped to the south and east buttons")
	_check(is_equal_approx(InputMap.action_get_deadzone("move_right"), 0.2), "movement deadzone is 0.2")

	var motion := InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.19
	Input.parse_input_event(motion)
	await process_frame
	_check(not Input.is_action_pressed("move_right"), "stick movement below deadzone is ignored")
	motion = InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.8
	Input.parse_input_event(motion)
	await process_frame
	_check(Input.is_action_pressed("move_right"), "synthetic stick motion activates movement")
	motion = InputEventJoypadMotion.new()
	motion.axis = JOY_AXIS_LEFT_X
	motion.axis_value = 0.0
	Input.parse_input_event(motion)
	await process_frame
	_check(not Input.is_action_pressed("move_right"), "releasing the stick stops movement")

	var button := InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = true
	Input.parse_input_event(button)
	await process_frame
	_check(Input.is_action_pressed("jump"), "synthetic south button activates jump")
	button = InputEventJoypadButton.new()
	button.button_index = JOY_BUTTON_A
	button.pressed = false
	Input.parse_input_event(button)
	await process_frame
	_check(not Input.is_action_pressed("jump"), "releasing the south button clears jump")

	var menu_scene := load("res://scenes/ui/title_menu.tscn") as PackedScene
	if menu_scene != null:
		var menu := menu_scene.instantiate()
		root.add_child(menu)
		current_scene = menu
		await process_frame
		_send_joy_button(JOY_BUTTON_DPAD_DOWN, true)
		await process_frame
		_check(menu.get_node("MenuCenter/MenuContent/ControlsButton").has_focus(), "D-pad navigation moves title menu focus")
		_send_joy_button(JOY_BUTTON_DPAD_DOWN, false)
		await process_frame
		_send_joy_button(JOY_BUTTON_A, true)
		await process_frame
		_send_joy_button(JOY_BUTTON_A, false)
		await process_frame
		_check(menu.get_node("ControlsOverlay").visible, "south button confirms the focused menu item")
		_send_joy_button(JOY_BUTTON_B, true)
		await process_frame
		_check(not menu.get_node("ControlsOverlay").visible and menu.get_node("MenuCenter/MenuContent/ControlsButton").has_focus(), "east button closes controls and restores focus")
		_send_joy_button(JOY_BUTTON_B, false)
	else:
		_check(false, "title menu scene loads for gamepad focus check")

	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main scene loads for restart check")
	if packed != null:
		var session := packed.instantiate()
		root.add_child(session)
		current_scene = session
		await process_frame
		session.set("result_state", 1)
		button = InputEventJoypadButton.new()
		button.button_index = JOY_BUTTON_Y
		button.pressed = true
		session.call("_unhandled_input", button)
		await process_frame
		_check(current_scene != session and current_scene != null and current_scene.scene_file_path == MAIN_SCENE, "north button restarts the result scene")

	_finish()

func _has_button(action: StringName, button_index: JoyButton) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadButton and (event as InputEventJoypadButton).button_index == button_index:
			return true
	return false

func _has_key(action: StringName, physical_keycode: Key) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventKey and (event as InputEventKey).physical_keycode == physical_keycode:
			return true
	return false

func _send_joy_button(button_index: JoyButton, pressed: bool) -> void:
	var event := InputEventJoypadButton.new()
	event.button_index = button_index
	event.pressed = pressed
	Input.parse_input_event(event)

func _has_event(action: StringName, axis: int, value: float) -> bool:
	for event in InputMap.action_get_events(action):
		if event is InputEventJoypadMotion:
			var motion := event as InputEventJoypadMotion
			if motion.axis == axis and is_equal_approx(motion.axis_value, value):
				return true
	return false

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("gamepad_input_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("gamepad_input_smoke: " + failure)
		push_error("gamepad_input_smoke: %d check(s) failed" % failures.size())
		quit(1)
