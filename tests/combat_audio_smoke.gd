extends SceneTree

const MAIN_SCENE := preload("res://scenes/game/main.tscn")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var main := MAIN_SCENE.instantiate()
	root.add_child(main)
	await process_frame
	var audio := main.get_node("CombatAudio")
	var player := main.get_node("YSortActors/Player")
	var raider := main.get_node("YSortActors/ForestRaider1")

	# A started swing is audible, while a miss produces no hit event.
	for stage in range(1, 4):
		player._begin_attack(stage)
		_check(int(audio.event_counts.get("attack_%d" % stage, 0)) == 1, "each combo stage has its own attack cue")
		_check(audio._stream_for("attack_%d" % stage) is AudioStreamWAV, "combo cue is generated as AudioStreamWAV")
		_check(audio._stream_for("hit_%d" % stage) is AudioStreamWAV, "hit cue is generated as AudioStreamWAV")
	for stage in range(1, 3):
		_check(audio._stream_for("attack_%d" % stage).data != audio._stream_for("attack_%d" % (stage + 1)).data, "adjacent combo cues have different samples")
		_check(audio._stream_for("hit_%d" % stage).data != audio._stream_for("hit_%d" % (stage + 1)).data, "adjacent hit cues have different samples")
	_check(int(audio.event_counts.get("hit_1", 0)) == 0, "a whiff does not play a hit cue")

	# Repeated hit notifications within one player swing are reduced to one cue.
	player._begin_attack(1)
	player.attack_hit.emit(1)
	player.attack_hit.emit(1)
	_check(int(audio.event_counts.get("hit_1", 0)) == 1, "duplicate hit cue is suppressed per swing")
	player._begin_attack(2)
	player.attack_hit.emit(2)
	_check(int(audio.event_counts.get("hit_2", 0)) == 1, "second combo hit uses a distinct cue")
	player._begin_attack(3)
	player.attack_hit.emit(3)
	_check(int(audio.event_counts.get("hit_3", 0)) == 1, "third combo hit uses a distinct cue")

	raider._begin_attack()
	_check(int(audio.event_counts.get("raider_windup", 0)) == 1, "Raider windup cue is connected")
	var hit := {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1}
	raider.receive_hit(hit)
	_check(int(audio.event_counts.get("ko", 0)) == 1, "Raider KO cue is emitted")
	_check(int(audio.event_counts.get("hurt", 0)) == 1, "Raider hit cue is emitted")

	player.receive_hit(hit)
	_check(int(audio.event_counts.get("ko", 0)) == 2, "player KO cue is emitted")
	_check(int(audio.event_counts.get("hurt", 0)) >= 2, "player hit cue is emitted")

	main.set("result_state", 1)
	await process_frame
	for voice in audio.get_children():
		if voice is AudioStreamPlayer2D:
			_check(not voice.playing, "session end stops all combat voices")
	main.queue_free()
	await process_frame
	print("combat_audio_smoke: all checks passed")
	quit(0)

func _check(condition: bool, message: String) -> void:
	if not condition:
		push_error("combat_audio_smoke: " + message)
		quit(1)
