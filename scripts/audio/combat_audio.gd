extends Node
"""Creates and routes short procedural combat sounds without imported assets."""

const SAMPLE_RATE := 22050
const VOICE_COUNT := 12
const WAVEFORMS := {
	"attack_1": {"frequency": 310.0, "duration": 0.075, "wave": 0},
	"attack_2": {"frequency": 410.0, "duration": 0.082, "wave": 1},
	"attack_3": {"frequency": 520.0, "duration": 0.095, "wave": 2},
	"hit_1": {"frequency": 170.0, "duration": 0.105, "wave": 2},
	"hit_2": {"frequency": 205.0, "duration": 0.12, "wave": 2},
	"hit_3": {"frequency": 245.0, "duration": 0.14, "wave": 2},
	"hurt": {"frequency": 145.0, "duration": 0.12, "wave": 1},
	"ko": {"frequency": 92.0, "duration": 0.23, "wave": 3},
	"raider_windup": {"frequency": 260.0, "duration": 0.13, "wave": 1},
}

var event_counts: Dictionary = {}
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer2D] = []
var _next_voice := 0
var _player_hit_seen: Dictionary = {}
var _session: Node
var _session_audio_stopped := false

func _ready() -> void:
	for index in range(VOICE_COUNT):
		var voice := AudioStreamPlayer2D.new()
		voice.name = "CombatVoice%d" % index
		voice.max_distance = 900.0
		voice.attenuation = 1.0
		add_child(voice)
		_voices.append(voice)
	_session = get_parent()
	_connect_combat_signals()

func _process(_delta: float) -> void:
	if _session_audio_stopped or not is_instance_valid(_session):
		return
	var result_state = _session.get("result_state")
	if result_state != null and int(result_state) != 0:
		stop_all()
		_session_audio_stopped = true

func _exit_tree() -> void:
	stop_all()

func _connect_combat_signals() -> void:
	var actors := get_parent().get_node_or_null("YSortActors")
	if actors == null:
		return
	var player := actors.get_node_or_null("Player")
	if player != null:
		_connect(player, "attack_started", _on_player_attack_started)
		_connect(player, "attack_hit", _on_player_attack_hit)
		_connect(player, "player_hit", _on_player_hit)
		_connect(player, "player_ko", _on_player_ko)
	for raider in actors.get_children():
		if raider.has_signal("attack_windup_started"):
			_connect(raider, "attack_windup_started", _on_raider_windup)
			_connect(raider, "raider_hit", _on_raider_hit)
			_connect(raider, "raider_ko", _on_raider_ko)

func _connect(actor: Node, signal_name: String, callback: Callable) -> void:
	var callable := callback.bind(actor)
	if actor.has_signal(signal_name) and not actor.is_connected(signal_name, callable):
		actor.connect(signal_name, callable)

func _on_player_attack_started(stage: int, actor: Node) -> void:
	_player_hit_seen[actor.get_instance_id()] = false
	_play("attack_%d" % clampi(stage, 1, 3), actor, -15.0, 720.0)

func _on_player_attack_hit(stage: int, actor: Node) -> void:
	var actor_id := actor.get_instance_id()
	if bool(_player_hit_seen.get(actor_id, false)):
		return
	_player_hit_seen[actor_id] = true
	_play("hit_%d" % clampi(stage, 1, 3), actor, -8.0, 820.0)

func _on_player_hit(_stage: int, actor: Node) -> void:
	_play("hurt", actor, -10.0, 720.0)

func _on_player_ko(actor: Node) -> void:
	_play("ko", actor, -7.0, 760.0)

func _on_raider_windup(actor: Node) -> void:
	_play("raider_windup", actor, -13.0, 650.0)

func _on_raider_hit(_stage: int, actor: Node) -> void:
	_play("hurt", actor, -11.0, 650.0)

func _on_raider_ko(actor: Node) -> void:
	_play("ko", actor, -8.0, 700.0)

func _play(kind: String, source: Node2D, volume_db: float, max_distance: float) -> void:
	if not WAVEFORMS.has(kind):
		return
	event_counts[kind] = int(event_counts.get(kind, 0)) + 1
	if _voices.is_empty() or not is_instance_valid(source) or not source.is_inside_tree():
		return
	var voice := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % _voices.size()
	voice.stop()
	voice.stream = _stream_for(kind)
	voice.volume_db = volume_db
	voice.max_distance = max_distance
	voice.global_position = source.global_position
	voice.play()

func _stream_for(kind: String) -> AudioStreamWAV:
	if _streams.has(kind):
		return _streams[kind]
	var spec: Dictionary = WAVEFORMS[kind]
	var sample_count := int(float(spec["duration"]) * SAMPLE_RATE)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	var base_frequency: float = spec["frequency"]
	var waveform: int = spec["wave"]
	for index in range(sample_count):
		var t := float(index) / SAMPLE_RATE
		var phase := TAU * base_frequency * t * (1.0 - 0.35 * t / float(spec["duration"]))
		var tone := sin(phase)
		if waveform == 1:
			tone = sin(phase) * 0.72 + sin(phase * 1.51) * 0.28
		elif waveform == 2:
			tone = sin(phase) * 0.58 + sin(phase * 2.37) * 0.24 + sin(phase * 0.53) * 0.18
		elif waveform == 3:
			tone = sin(phase) * 0.7 + sin(phase * 0.51) * 0.3
		var envelope := pow(1.0 - float(index) / sample_count, 2.2)
		var sample := clampf(tone * envelope * 0.38, -1.0, 1.0)
		data.encode_s16(index * 2, int(sample * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.data = data
	_streams[kind] = stream
	return stream

func stop_all() -> void:
	for voice in _voices:
		if is_instance_valid(voice):
			voice.stop()
