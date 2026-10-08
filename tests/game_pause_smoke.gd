extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const HIT := {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1}

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main scene loads for pause smoke")
	if packed == null:
		_finish()
		return
	var session := packed.instantiate()
	root.add_child(session)
	current_scene = session
	await process_frame
	var player: Node = session.get_node("YSortActors/Player")
	var combat_audio: Node = session.get_node("CombatAudio")
	var voice: AudioStreamPlayer2D = combat_audio.get_child(0) as AudioStreamPlayer2D
	var raider: Node = session.get_node("YSortActors/ForestRaider1")
	var raiders: Array = session.get("_raiders")
	raider.set("hitstun_remaining", 0.3)
	var hitstun_at_pause := float(raider.get("hitstun_remaining"))
	var start_position: Vector2 = player.global_position
	voice.stream = combat_audio.call("_stream_for", "attack_1")
	voice.play()
	player.call("_trigger_hit_stop", 0.5)
	_check(bool(player.get("_hit_stop_active")), "test starts during hit-stop")
	_send_key(session, KEY_ESCAPE)
	_check(paused and session.get("pause_overlay").visible, "ESC enters pause and displays its overlay")
	_check(not bool(player.get("_hit_stop_active")) and is_equal_approx(Engine.time_scale, 1.0), "pausing cancels hit-stop and restores the time scale")
	_check(not combat_audio.can_process() and not voice.can_process(), "CombatAudio and active voices inherit the paused world state")
	player.global_position += Vector2(24.0, 0.0)
	for tracked_raider in raiders:
		tracked_raider.set("health", 0)
	await create_timer(0.15, true).timeout
	_check(session.get("result_state") == 0 and session.get("result_overlay").visible == false, "session result checks stay frozen while paused")
	_check(is_equal_approx(float(raider.get("hitstun_remaining")), hitstun_at_pause), "Raider AI timers stay frozen while paused")
	_check(is_equal_approx(Engine.time_scale, 1.0), "stale hit-stop timer cannot alter the paused time scale")
	_check(player.global_position != start_position, "test can observe manually changed paused world state")
	_send_key(session, KEY_ESCAPE)
	_check(not paused and not session.get("pause_overlay").visible, "ESC resumes the session")
	_check(combat_audio.can_process() and voice.can_process(), "CombatAudio resumes with the session")
	await process_frame
	await process_frame
	_check(session.get("result_state") == 2 and session.get("result_overlay").visible, "victory is evaluated after resuming")
	_send_key(session, KEY_R)
	await process_frame
	await process_frame
	_check(is_instance_valid(current_scene) and current_scene != session, "R restarts from the result screen")
	_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "restart clears pause and hit-stop state")
	var defeat_session := current_scene
	var defeated_player: Node = defeat_session.get_node("YSortActors/Player")
	defeated_player.call("receive_hit", HIT)
	_send_key(defeat_session, KEY_ESCAPE)
	_check(paused and defeat_session.get("result_state") == 0, "a KO can enter pause before DEFEAT is evaluated")
	await create_timer(0.1, true).timeout
	_check(defeat_session.get("result_state") == 0, "DEFEAT remains pending while the KO session is paused")
	_send_key(defeat_session, KEY_ESCAPE)
	await process_frame
	await process_frame
	_check(not paused and defeat_session.get("result_state") == 1 and defeat_session.get("result_overlay").visible, "DEFEAT is evaluated after resuming a paused KO")
	_send_key(defeat_session, KEY_R)
	await process_frame
	await process_frame
	_check(is_instance_valid(current_scene) and current_scene != defeat_session, "R restarts from the resumed DEFEAT screen")
	if is_instance_valid(current_scene):
		current_scene.queue_free()
	current_scene = null
	_finish()

func _send_key(session: Node, code: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.pressed = true
	session.call("_unhandled_input", event)

func _finish() -> void:
	paused = false
	Engine.time_scale = 1.0
	if failures.is_empty():
		print("game_pause_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("game_pause_smoke: " + failure)
		push_error("game_pause_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
