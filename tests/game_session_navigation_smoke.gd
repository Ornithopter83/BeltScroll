extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const TITLE_SCENE := "res://scenes/ui/title_menu.tscn"
const DEFEAT_RESULT_DELAY := 1.3

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main scene loads for navigation smoke")
	if packed == null:
		_finish()
		return

	var session := await _new_session(packed)
	var pause := session.get("pause_overlay") as CanvasLayer
	session.call("_set_paused", true)
	_check(paused and pause.visible, "pause menu is active and visible")
	var resume_button := session.get("_pause_resume_button") as Button
	_check(resume_button != null and resume_button.focus_mode == Control.FOCUS_ALL, "pause menu provides keyboard and gamepad focusable buttons")
	resume_button.emit_signal("pressed")
	_check(not paused and not pause.visible, "continue button resumes the paused tree")

	session.call("_set_paused", true)
	var pause_restart := session.get("_pause_restart_button") as Button
	var old_id := session.get_instance_id()
	var player := session.get_node("YSortActors/Player")
	player.call("_trigger_hit_stop", 0.5)
	var combat_audio := session.get_node("CombatAudio")
	var voice := combat_audio.get_child(0) as AudioStreamPlayer2D
	voice.stream = combat_audio.call("_stream_for", "attack_1")
	voice.play()
	pause_restart.emit_signal("pressed")
	pause_restart.emit_signal("pressed")
	_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "pause restart clears pause and hit-stop time scale")
	_check(not bool(player.get("_hit_stop_active")) and not voice.playing, "pause restart cancels hit-stop and stops combat audio")
	await process_frame
	await process_frame
	session = current_scene
	_check(is_instance_valid(session) and session.get_instance_id() != old_id, "pause restart loads a fresh scene once")
	_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "fresh scene starts with restored global state")

	session = await _new_session(packed)
	session.call("_set_paused", true)
	combat_audio = session.get_node("CombatAudio")
	voice = combat_audio.get_child(0) as AudioStreamPlayer2D
	voice.stream = combat_audio.call("_stream_for", "attack_1")
	voice.play()
	var pause_title := session.get("_pause_title_button") as Button
	pause_title.emit_signal("pressed")
	_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "title request clears pause and time scale before transition")
	_check(not voice.playing, "title request stops active combat audio before transition")
	await process_frame
	await process_frame
	_check(current_scene != null and current_scene.scene_file_path == TITLE_SCENE, "pause title button returns to title scene")
	_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "title return clears pause and time scale")

	var result_states := [1, 2]
	for state in result_states:
		session = await _new_session(packed)
		session.call("_finish_session", state)
		if state == 1:
			await create_timer(DEFEAT_RESULT_DELAY).timeout
		var result_overlay := session.get("result_overlay") as CanvasLayer
		_check(result_overlay.visible, "DEFEAT and VICTORY retain result overlay contract")
		_check((session.get("_result_restart_button") as Button).focus_mode == Control.FOCUS_ALL, "result actions support keyboard and gamepad focus")
		var retry := session.get("_result_restart_button") as Button
		old_id = session.get_instance_id()
		retry.emit_signal("pressed")
		retry.emit_signal("pressed")
		await process_frame
		await process_frame
		session = current_scene
		_check(is_instance_valid(session) and session.get_instance_id() != old_id, "result retry reloads a fresh scene once")
		_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "result retry restores global state")

	for state in result_states:
		session = await _new_session(packed)
		session.call("_finish_session", state)
		if state == 1:
			await create_timer(DEFEAT_RESULT_DELAY).timeout
		var result_title := session.get("_result_title_button") as Button
		result_title.emit_signal("pressed")
		await process_frame
		await process_frame
		_check(current_scene != null and current_scene.scene_file_path == TITLE_SCENE, "DEFEAT and VICTORY title buttons return to title")
		_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "result title return restores global state")

	_finish()

func _new_session(packed: PackedScene) -> Node:
	paused = false
	Engine.time_scale = 1.0
	var session := packed.instantiate()
	root.add_child(session)
	current_scene = session
	await process_frame
	return session

func _finish() -> void:
	paused = false
	Engine.time_scale = 1.0
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	current_scene = null
	if failures.is_empty():
		print("game_session_navigation_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("game_session_navigation_smoke: " + failure)
		push_error("game_session_navigation_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
