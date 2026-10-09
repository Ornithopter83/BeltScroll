extends SceneTree

## Observational wrapper for the normal project scene. It never synthesizes input
## and never writes game state; it records what Godot delivers to this process.
class AuditObserver extends Node:
	var output: FileAccess
	var started_usec: int = 0
	var held: Dictionary = {}
	var action_names: Array[String] = [
		"move_up", "move_down", "move_left", "move_right", "jump", "attack", "block", "pause",
		"skill_1", "skill_2", "skill_3", "skill_4", "skill_5", "skill_6", "skill_7", "skill_8", "skill_9"
	]

	func open_log(path: String) -> bool:
		output = FileAccess.open(path, FileAccess.WRITE)
		if output == null:
			push_error("수동 입력 감사 로그를 열 수 없습니다: %s" % path)
			return false
		started_usec = Time.get_ticks_usec()
		_write({
			"record_type": "session_start",
			"timestamp_utc": Time.get_datetime_string_from_system(true, true),
			"monotonic_usec": 0,
			"project": ProjectSettings.get_setting("application/config/name", "BeltScroll"),
			"main_scene": ProjectSettings.get_setting("application/run/main_scene", ""),
			"requested_window_size": {"width": 1920, "height": 1080},
			"source_claim": "unverified; Godot input logs do not prove physical device origin",
			"synthetic_input_detection": "Godot does not expose a reliable physical-versus-injected origin flag; suspicious markers are recorded separately"
		})
		return true

	func _input(event: InputEvent) -> void:
		var target := _describe_target(event)
		if target.is_empty():
			return
		var key := str(target.get("control", ""))
		var pressed := false
		var has_state := false
		if event is InputEventKey:
			pressed = (event as InputEventKey).pressed
			has_state = true
		elif event is InputEventMouseButton:
			pressed = (event as InputEventMouseButton).pressed
			has_state = true
		var previous := bool(held.get(key, false))
		var transition := "none"
		if has_state and not event.is_echo():
			if pressed and not previous:
				transition = "pressed"
				held[key] = true
			elif not pressed and previous:
				transition = "released"
				held.erase(key)
		var matching_actions: Array[String] = []
		for action in action_names:
			if InputMap.has_action(action) and event.is_action(action, false):
				matching_actions.append(action)
		_write({
			"record_type": "input_event",
			"timestamp_utc": Time.get_datetime_string_from_system(true, true),
			"monotonic_usec": Time.get_ticks_usec() - started_usec,
			"control": key,
			"event_class": event.get_class(),
			"event": target,
			"state_transition": transition,
			"pressed_state_after_event": bool(held.get(key, false)),
			"matching_actions": matching_actions,
			"device_id": event.device,
			"window_id": event.window_id,
			"echo": event.is_echo(),
			"canceled": event is InputEventMouseButton and (event as InputEventMouseButton).canceled,
			"synthetic_suspicion_markers": _synthetic_markers(event),
			"input_origin_classification": "suspected_synthetic_or_nonstandard" if not _synthetic_markers(event).is_empty() else "unverified_standard_event",
			"physical_device_origin": "unverified"
		})

	func record_focus(focused: bool) -> void:
		var held_controls := held.keys()
		_write({
			"record_type": "window_focus",
			"timestamp_utc": Time.get_datetime_string_from_system(true, true),
			"monotonic_usec": Time.get_ticks_usec() - started_usec,
			"state": "focused" if focused else "focus_lost",
			"held_controls_at_transition": held_controls,
			"note": "Focus events are not input events. Held-state cache is cleared on focus loss without inventing release input."
		})
		if not focused:
			held.clear()

	func _describe_target(event: InputEvent) -> Dictionary:
		if event is InputEventKey:
			var key_event := event as InputEventKey
			var code := key_event.physical_keycode if key_event.physical_keycode != 0 else key_event.keycode
			var name := ""
			if code >= KEY_1 and code <= KEY_9:
				name = "Num%d" % (code - KEY_0)
			elif code >= KEY_KP_1 and code <= KEY_KP_9:
				name = "Num%d" % (code - KEY_KP_0)
			else:
				match code:
					KEY_W: name = "W"
					KEY_A: name = "A"
					KEY_S: name = "S"
					KEY_D: name = "D"
					KEY_SPACE: name = "Space"
					KEY_SHIFT: name = "Shift"
					KEY_J: name = "J"
					KEY_ESCAPE: name = "Esc"
			if name.is_empty():
				return {}
			return {"control": name, "physical_keycode": key_event.physical_keycode, "keycode": key_event.keycode, "pressed": key_event.pressed}
		if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mouse_event := event as InputEventMouseButton
			return {"control": "MouseLeft", "button_index": mouse_event.button_index, "pressed": mouse_event.pressed, "position": [mouse_event.position.x, mouse_event.position.y]}
		return {}

	func _synthetic_markers(event: InputEvent) -> Array[String]:
		var markers: Array[String] = []
		if event.is_echo():
			markers.append("key_echo")
		if event.device < 0:
			markers.append("negative_device_id")
		if event is InputEventMouseButton and (event as InputEventMouseButton).canceled:
			markers.append("mouse_event_canceled")
		return markers

	func _write(record: Dictionary) -> void:
		if output != null:
			output.store_line(JSON.stringify(record))
			output.flush()

	func close_log() -> void:
		if output != null:
			_write({
				"record_type": "session_end",
				"timestamp_utc": Time.get_datetime_string_from_system(true, true),
				"monotonic_usec": Time.get_ticks_usec() - started_usec,
				"physical_device_origin": "unverified",
				"manual_review_required": true
			})
			output.close()
			output = null

var observer: AuditObserver

func _initialize() -> void:
	var log_path := "user://manual_input_audit.jsonl"
	var args := OS.get_cmdline_user_args()
	for index in range(args.size() - 1):
		if args[index] == "--audit-output":
			log_path = args[index + 1]
	var main_scene_path := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	var packed_scene := load(main_scene_path) as PackedScene
	if packed_scene == null:
		push_error("본편 메인 씬을 불러올 수 없습니다: %s" % main_scene_path)
		quit(2)
		return
	root.size = Vector2i(1920, 1080)
	DisplayServer.window_set_size(Vector2i(1920, 1080))
	var scene := packed_scene.instantiate()
	root.add_child(scene)
	observer = AuditObserver.new()
	root.add_child(observer)
	if not observer.open_log(log_path):
		quit(3)
		return
	root.focus_entered.connect(observer.record_focus.bind(true))
	root.focus_exited.connect(observer.record_focus.bind(false))
	observer.record_focus(root.has_focus())
	print("수동 입력 감사 기록 중: ", log_path)
	print("본편 창에서 요청된 키와 마우스를 직접 확인하세요. 이벤트 로그는 물리 장치 출처를 증명하지 않습니다.")

func _finalize() -> void:
	if observer != null:
		observer.close_log()
