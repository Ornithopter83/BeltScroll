extends SceneTree

const MENU_SCENE := "res://scenes/ui/title_menu.tscn"
const MAIN_SCENE := "res://scenes/game/main.tscn"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(1920, 1080)
	var packed := load(MENU_SCENE) as PackedScene
	_check(packed != null, "title menu scene loads")
	if packed == null:
		_finish()
		return

	var menu := packed.instantiate()
	root.add_child(menu)
	current_scene = menu
	await process_frame
	var start_button := menu.get_node_or_null("MenuCenter/MenuContent/StartButton") as Button
	var controls_button := menu.get_node_or_null("MenuCenter/MenuContent/ControlsButton") as Button
	var quit_button := menu.get_node_or_null("MenuCenter/MenuContent/QuitButton") as Button
	_check(menu.get_node_or_null("Background") is TextureRect, "Forest Ruins backdrop is present")
	_check(start_button != null and controls_button != null and quit_button != null, "start, controls and quit buttons are built")
	if start_button == null or controls_button == null or quit_button == null:
		_finish()
		return

	_check(start_button.has_focus(), "keyboard focus starts on the start button")
	_check(start_button.focus_mode == Control.FOCUS_ALL and start_button.mouse_filter == Control.MOUSE_FILTER_STOP, "buttons support keyboard focus and mouse input")
	_check(start_button.get_theme_stylebox("focus") != null, "focused buttons have a visible focus style")

	_send_key(KEY_TAB)
	await process_frame
	_check(controls_button.has_focus(), "Tab moves keyboard focus to the controls button")
	_send_key(KEY_ENTER)
	await process_frame
	_check(menu.get_node("ControlsOverlay").visible, "controls button opens the controls panel")
	_send_key(KEY_ESCAPE)
	await process_frame
	_check(not menu.get_node("ControlsOverlay").visible, "Escape closes the controls panel")
	controls_button.pressed.emit()
	await process_frame
	await _send_mouse_click(menu.get("_controls_close_button") as Button)
	await process_frame
	_check(not menu.get_node("ControlsOverlay").visible, "back button closes the controls panel")
	_check(controls_button.has_focus(), "closing the panel returns focus to controls")

	await _send_mouse_click(start_button)
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == MAIN_SCENE, "start button transitions to the existing main scene")
	if current_scene != null and current_scene.scene_file_path == MAIN_SCENE:
		_check(current_scene.get_node_or_null("CombatHUD") != null, "main combat scene remains intact after the transition")

	if not failures.is_empty():
		_finish()
		return

	var quit_menu := packed.instantiate()
	root.add_child(quit_menu)
	await process_frame
	var quit_action := quit_menu.get_node_or_null("MenuCenter/MenuContent/QuitButton") as Button
	_check(quit_action != null and quit_menu.quit_requested.is_connected(Callable(quit_menu, "_quit_tree")), "quit button is wired to the application quit handler")
	if quit_action == null or not quit_menu.quit_requested.is_connected(Callable(quit_menu, "_quit_tree")):
		_finish()
		return

	print("PASS: quit button exits the application")
	print("title_menu_smoke: all checks passed")
	create_timer(2.0).timeout.connect(_quit_timeout)
	quit_action.grab_focus()
	_send_key(KEY_ENTER)

func _quit_timeout() -> void:
	push_error("title_menu_smoke: quit button did not close the application")
	quit(1)

func _finish() -> void:
	if failures.is_empty():
		print("title_menu_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("title_menu_smoke: " + failure)
		push_error("title_menu_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _send_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate() as InputEventKey
	event.pressed = false
	Input.parse_input_event(event)

func _send_mouse_click(button: Button) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	Input.parse_input_event(event)
	await process_frame
	event = event.duplicate() as InputEventMouseButton
	event.pressed = false
	event.button_mask = 0
	Input.parse_input_event(event)


