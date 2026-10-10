extends Node2D
class_name PlayerPoseBlender
"""Single-visible-Sprite pose selector. No Player scene wiring is implied."""

const SAFE_IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const APPROVED_ATTACK_POSES := {
	"attack1": "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"attack2": "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
	"attack3": "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
}
const PHASES := ["startup", "inbetween", "contact", "recovery"]
const EXTENDED_POSES := {
	"run": ["stride"], "turn": ["turn"], "jump_rise": ["rise"],
	"jump_fall": ["fall"], "hit": ["reaction"],
	"skill1": ["startup", "contact", "recovery"],
	"skill2": ["startup", "contact", "recovery"],
}

@export var sprite_scale := Vector2(0.1489758, 0.1489758)
## Shared combat-space reference; support candidates are per registered drawing.
@export var common_combat_anchor := Vector2.ZERO
## Compatibility property for existing independent blender callers.
var common_foot_anchor: Vector2:
	get: return common_combat_anchor
	set(value): common_combat_anchor = value
## Retained for scene compatibility. Full-body pose changes are now atomic.
@export_range(0.01, 0.25, 0.005) var crossfade_duration := 0.075

var _sprites: Array[Sprite2D] = []
var _bounds_cache: Dictionary = {}
var _anchor_overrides: Dictionary = {}
var _approved_textures: Dictionary = {}
var _registered_frames: Dictionary = {}
var _replacement_batch_keys: Dictionary = {}
var _current_key := "idle"
var _current_registered_frame := 0
var _current_registered_frame_elapsed := 0.0
var _current_registered_frame_effective_duration := 0.0
var _transition_from := 0
var _transition_to := 0
var _transition_elapsed := 0.0
var _active_transition_duration := 0.0
var _transitioning := false
var _facing_left := false
var _ko := false
var _sequence_action := ""
var _sequence_phases: Array[String] = []
var _sequence_indices: Array[int] = []
var _sequence_durations: Array[float] = []
var _sequence_elapsed := 0.0
var _sequence_frame := 0
var _sequence_loop := false
var _external_blend_weight := 1.0
var _base_modulate := Color.WHITE

func _ready() -> void:
	_base_modulate = modulate
	for index in range(2):
		var sprite := Sprite2D.new()
		sprite.name = "PoseSprite%d" % index
		sprite.centered = true
		sprite.scale = sprite_scale
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
	_request_texture("idle", _load_safe_idle())
	for action in APPROVED_ATTACK_POSES:
		approve_pose_texture(action, "contact", APPROVED_ATTACK_POSES[action])
	visible = false
	set_external_blend_weight(_external_blend_weight)

## Compatibility hook for callers that control the pose layer as a whole.
func set_external_blend_weight(weight: float) -> void:
	_external_blend_weight = clampf(weight, 0.0, 1.0)
	var layer_modulate := _base_modulate
	layer_modulate.a *= _external_blend_weight
	modulate = layer_modulate

func get_external_blend_weight() -> float:
	return _external_blend_weight

## Mirrors the existing PlayerArt transform and alpha-foot anchor while the
## approved contact still is displayed in its place.
func sync_from_art(art: Sprite2D) -> void:
	if art == null or art.texture == null:
		return
	var bounds := _bounds_for(art.texture)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		return
	var source_foot := Vector2(
		float(bounds.position.x) + float(bounds.size.x) * 0.5,
		float(bounds.end.y)
	)
	var centered_foot := (source_foot - Vector2(art.texture.get_size()) * 0.5) * art.scale
	position = art.position + centered_foot.rotated(art.rotation)
	rotation = art.rotation
	scale = art.scale / sprite_scale
	modulate = art.modulate

## Explicitly approves one pose image at runtime. Nothing from the art candidate folder
## is implicitly exposed; callers must make the visual approval decision themselves.
func approve_pose_texture(action: String, phase: String, texture_source: Variant) -> bool:
	var key := _pose_key(action, phase)
	if key.is_empty() or key == "idle":
		return false
	var texture: Texture2D
	if texture_source is Texture2D:
		texture = texture_source
	elif texture_source is String and ResourceLoader.exists(texture_source):
		texture = load(texture_source) as Texture2D
	else:
		return false
	if not _texture_is_usable(texture):
		return false
	_approved_textures[key] = texture
	_registered_frames[key] = [{"texture": texture, "duration": 0.1, "status": "approved keypose", "label": phase}]
	return true

## Adds a reviewed frame to a phase. This is explicit registration: files in
## candidate directories are never scanned or loaded automatically.
func register_pose_frame(action: String, phase: String, texture_source: Variant, duration: float, art_status := "approved frame", label := "", foot_anchor := Vector2(-1.0, -1.0), replace_existing := false) -> bool:
	var key := _pose_key(action, phase)
	if key.is_empty() or duration <= 0.0 or art_status.begins_with("approved") == false:
		return false
	var texture: Texture2D
	if texture_source is Texture2D:
		texture = texture_source
	elif texture_source is String and ResourceLoader.exists(texture_source):
		texture = load(texture_source) as Texture2D
	if not _texture_is_usable(texture):
		return false
	# Bank loaders mark each manifest frame as replacing the prior approved
	# registration. Consecutive frames for one phase form one replacement batch:
	# clear the previous phase once, then preserve manifest order for the rest.
	if replace_existing and not _replacement_batch_keys.has(key):
		_registered_frames[key] = []
		_replacement_batch_keys[key] = true
	elif not _registered_frames.has(key):
		_registered_frames[key] = []
	var frames: Array = _registered_frames[key]
	frames.append({"texture": texture, "duration": duration, "status": art_status, "label": label if not label.is_empty() else phase})
	_registered_frames[key] = frames
	_approved_textures[key] = texture
	if foot_anchor.x >= 0.0 and foot_anchor.y >= 0.0 and foot_anchor.x <= 1.0 and foot_anchor.y <= 1.0:
		_anchor_overrides[texture.get_instance_id()] = foot_anchor
	else:
		_anchor_overrides.erase(texture.get_instance_id())
	return true

## Assigns an explicit normalized support-foot candidate to one approved frame.
## It is distinct from the common combat anchor and never inferred from the full
## silhouette's lowest alpha pixel when a candidate is available.
func set_ground_candidate(action: String, phase: String, candidate: Vector2, frame_index := 0) -> bool:
	var key := _pose_key(action, phase)
	if key.is_empty() or not _registered_frames.has(key) or candidate.x < 0.0 or candidate.x > 1.0 or candidate.y < 0.0 or candidate.y > 1.0:
		return false
	var frames: Array = _registered_frames[key]
	if frame_index < 0 or frame_index >= frames.size():
		return false
	var texture := frames[frame_index].get("texture") as Texture2D
	if not _texture_is_usable(texture):
		return false
	_anchor_overrides[texture.get_instance_id()] = candidate
	return true

func get_ground_candidate(action: String, phase: String, frame_index := 0) -> Vector2:
	var frames: Array = _registered_frames.get(_pose_key(action, phase), [])
	if frame_index < 0 or frame_index >= frames.size():
		return Vector2(-1.0, -1.0)
	var texture := frames[frame_index].get("texture") as Texture2D
	return _anchor_overrides.get(texture.get_instance_id(), Vector2(-1.0, -1.0)) if texture != null else Vector2(-1.0, -1.0)

## action is idle, attack1, attack2, or attack3. Attack phases are startup,
## inbetween, contact, and recovery. Missing art safely resolves to the approved v8 still.
func set_pose(action: String, phase: String = "", transition_duration := -1.0) -> void:
	_clear_sequence()
	_select_pose(action, phase, transition_duration)

## Selects a registered drawing from the real combat phase clock. Unregistered
## phases remain on the safe idle fallback and are never presented as authored art.
func set_timed_pose(action: String, phase: String, phase_elapsed: float, phase_duration: float, transition_duration := -1.0, loop := false) -> bool:
	var key := _pose_key(action, phase)
	if not _registered_frames.has(key):
		set_pose(action, phase, transition_duration)
		return false
	var frames: Array = _registered_frames[key]
	var total_duration := 0.0
	for frame in frames:
		total_duration += float(frame.get("duration", 0.0))
	var time_cursor := 0.0
	var frame_index := frames.size() - 1
	var phase_time := fposmod(maxf(phase_elapsed, 0.0), total_duration) if loop and total_duration > 0.0 else clampf(phase_elapsed / maxf(phase_duration, 0.001), 0.0, 1.0) * total_duration
	var frame_start := 0.0
	for index in range(frames.size()):
		time_cursor += float(frames[index].get("duration", 0.0))
		if phase_time < time_cursor:
			frame_index = index
			frame_start = time_cursor - float(frames[index].get("duration", 0.0))
			break
	_clear_sequence()
	# Authored frame durations still decide the exact replacement boundary;
	# transition_duration remains accepted for API compatibility but never fades
	# one full-body silhouette into another.
	_select_pose(action, phase, transition_duration, frame_index)
	_current_registered_frame_elapsed = clampf(phase_time - frame_start, 0.0, get_current_registered_frame_duration())
	_current_registered_frame_effective_duration = float(frames[frame_index].get("duration", 0.0)) * (1.0 if loop else phase_duration / maxf(total_duration, 0.001))
	return true

## Pins a registered phase to its final reviewed frame. Used by combo_link hold
## so the contact drawing stays visible after the active damage window closes.
func hold_phase_end_pose(action: String, phase: String, transition_duration := 0.0) -> bool:
	var frames: Array = _registered_frames.get(_pose_key(action, phase), [])
	if frames.is_empty():
		return false
	var duration := 0.0
	for frame in frames:
		duration += float(frame.get("duration", 0.0))
	if duration <= 0.0:
		return false
	return set_timed_pose(action, phase, duration, duration, transition_duration, false)

func get_registered_frame_count(action: String, phase: String) -> int:
	var key := _pose_key(action, phase)
	if not _registered_frames.has(key):
		return 0
	var frames: Array = _registered_frames[key]
	return frames.size()

## Plays registered frames. Each item may be a phase string with a shared or
## per-item duration, or a dictionary with phase/frame/duration fields.
func play_pose_sequence(action: String, phases: Array, frame_duration: Variant = -1.0, loop := false) -> bool:
	if _ko or not _is_supported_action(action) or phases.is_empty():
		return false
	var accepted_phases: Array[String] = []
	var frame_indices: Array[int] = []
	var durations: Array[float] = []
	for phase in phases:
		var phase_name := ""
		var duration := 0.0
		var registered_index := 0
		if phase is Dictionary:
			phase_name = str(phase.get("phase", ""))
			duration = float(phase.get("duration", 0.0))
			registered_index = int(phase.get("frame", 0))
		else:
			phase_name = str(phase)
			if frame_duration is Array and accepted_phases.size() < frame_duration.size():
				duration = float(frame_duration[accepted_phases.size()])
			elif frame_duration is float or frame_duration is int:
				duration = float(frame_duration)
		var key := _pose_key(action, phase_name)
		if not PHASES.has(phase_name) or not _registered_frames.has(key) or duration <= 0.0:
			return false
		var registered: Array = _registered_frames[key]
		if registered_index < 0 or registered_index >= registered.size():
			return false
		accepted_phases.append(phase_name)
		frame_indices.append(registered_index)
		durations.append(duration)
	_sequence_action = action
	_sequence_phases = accepted_phases
	_sequence_indices = frame_indices
	_sequence_durations = durations
	_sequence_elapsed = 0.0
	_sequence_frame = 0
	_sequence_loop = loop
	_select_pose(action, _sequence_phases[0], -1.0, _sequence_indices[0])
	return true

func get_sequence_frame() -> int:
	return _sequence_frame

func get_sequence_frame_count() -> int:
	return _sequence_phases.size()

func get_sequence_elapsed() -> float:
	return _sequence_elapsed

func get_current_frame_duration() -> float:
	return _sequence_durations[_sequence_frame] if _sequence_frame < _sequence_durations.size() else 0.0

func get_current_registered_frame() -> int:
	return _current_registered_frame

func get_current_registered_frame_count() -> int:
	var frames: Array = _registered_frames.get(_current_key, [])
	return frames.size()

func get_current_registered_frame_duration() -> float:
	var frames: Array = _registered_frames.get(_current_key, [])
	if _current_registered_frame < 0 or _current_registered_frame >= frames.size():
		return 0.0
	return _current_registered_frame_effective_duration if _current_registered_frame_effective_duration > 0.0 else float(frames[_current_registered_frame].get("duration", 0.0))

func get_current_registered_frame_elapsed() -> float:
	return _current_registered_frame_elapsed

func get_current_registered_frame_label() -> String:
	var frames: Array = _registered_frames.get(_current_key, [])
	if _current_registered_frame < 0 or _current_registered_frame >= frames.size():
		return "unregistered"
	return str(frames[_current_registered_frame].get("label", "frame"))

func get_current_frame_status() -> String:
	if _current_key == "idle":
		return "temporary fallback art; approved animation frame unavailable"
	var frames: Array = _registered_frames.get(_current_key, [])
	if _current_registered_frame >= 0 and _current_registered_frame < frames.size():
		return str(frames[_current_registered_frame].get("status", "approved registered frame"))
	return "approved registered frame"

func get_current_texture_path() -> String:
	var sprite := _sprites[_transitioning_index()]
	return sprite.texture.resource_path if sprite.texture != null else ""

func _select_pose(action: String, phase: String = "", transition_duration := -1.0, registered_frame := 0) -> void:
	if _ko:
		_request_texture("idle", _load_safe_idle())
		return
	var key := "idle" if action == "idle" else _pose_key(action, phase)
	var texture: Texture2D = _load_safe_idle()
	if not key.is_empty() and key != "idle" and _registered_frames.has(key):
		var frames: Array = _registered_frames[key]
		_current_registered_frame = clampi(registered_frame, 0, frames.size() - 1)
		_current_registered_frame_elapsed = 0.0
		var frame: Dictionary = frames[_current_registered_frame]
		_current_registered_frame_effective_duration = float(frame.get("duration", 0.0))
		var candidate := frame.get("texture") as Texture2D
		if _texture_is_usable(candidate):
			texture = candidate
		else:
			_approved_textures.erase(key)
			key = "idle"
	else:
		key = "idle"
		_current_registered_frame = 0
		_current_registered_frame_elapsed = 0.0
		_current_registered_frame_effective_duration = 0.0
	_request_texture(key, texture, false, transition_duration)

func set_facing_left(facing_left: bool) -> void:
	_facing_left = facing_left
	for sprite in _sprites:
		sprite.flip_h = facing_left
		_place_sprite(sprite)

## KO is terminal until clear_ko is called; it discards any in-flight attack transition.
func set_ko(is_ko: bool) -> void:
	_ko = is_ko
	if _ko:
		_clear_sequence()
		_request_texture("idle", _load_safe_idle(), true)

func clear_ko() -> void:
	_ko = false

func interrupt_to_idle() -> void:
	_clear_sequence()
	_request_texture("idle", _load_safe_idle(), true)

func get_current_pose_key() -> String:
	return _current_key

func get_pose_art_status() -> String:
	if _current_key == "idle":
		return "approved v8 idle still; temporary transform motion; attack frame unavailable"
	var phase_name := _current_key.substr(_current_key.find("_") + 1)
	return "approved " + phase_name + " drawing; " + get_current_frame_status()

func get_transition_progress() -> float:
	return 1.0

func get_displayed_textures() -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for sprite in _sprites:
		if sprite.visible and sprite.texture != null and sprite.modulate.a > 0.0:
			result.append(sprite.texture)
	return result

func _process(delta: float) -> void:
	# A later independent bank load starts a fresh replacement batch.
	_replacement_batch_keys.clear()
	_advance_sequence(delta)

func _advance_sequence(delta: float) -> void:
	if _sequence_phases.is_empty() or _sequence_durations.is_empty():
		return
	_sequence_elapsed += maxf(delta, 0.0)
	var cursor := 0.0
	var next_frame := _sequence_phases.size() - 1
	for index in range(_sequence_durations.size()):
		cursor += _sequence_durations[index]
		if _sequence_elapsed < cursor:
			next_frame = index
			break
	if _sequence_loop:
		var total := 0.0
		for duration in _sequence_durations:
			total += duration
		if total > 0.0 and _sequence_elapsed >= total:
			_sequence_elapsed = fposmod(_sequence_elapsed, total)
			_advance_sequence(0.0)
			return
	if next_frame != _sequence_frame:
		_sequence_frame = next_frame
		_select_pose(_sequence_action, _sequence_phases[_sequence_frame], -1.0, _sequence_indices[_sequence_frame])
	var current_start := 0.0
	for index in range(_sequence_frame):
		current_start += _sequence_durations[index]
	_current_registered_frame_elapsed = clampf(_sequence_elapsed - current_start, 0.0, get_current_registered_frame_duration())
	_current_registered_frame_effective_duration = _sequence_durations[_sequence_frame]
	var total_duration := 0.0
	for duration in _sequence_durations:
		total_duration += duration
	if not _sequence_loop and _sequence_elapsed >= total_duration:
		_clear_sequence()

func _clear_sequence() -> void:
	_sequence_action = ""
	_sequence_phases.clear()
	_sequence_indices.clear()
	_sequence_durations.clear()
	_sequence_elapsed = 0.0
	_sequence_frame = 0
	_sequence_loop = false

func _request_texture(key: String, texture: Texture2D, immediate := false, transition_duration := -1.0) -> void:
	if not _texture_is_usable(texture):
		key = "idle"
		texture = _load_safe_idle()
	if texture == null:
		for sprite in _sprites:
			sprite.texture = null
			sprite.visible = false
		_transitioning = false
		_current_key = "idle"
		return
	var source := _transitioning_index()
	if _current_key == key and _sprites[source].texture == texture:
		for index in range(_sprites.size()):
			_sprites[index].visible = index == source
			_sprites[index].modulate.a = 1.0 if index == source else 0.0
		_transitioning = false
		return
	var target := 1 - source
	_sprites[target].texture = texture
	_sprites[target].modulate = Color.WHITE
	_place_sprite(_sprites[target])
	# Swap the sole visible contour synchronously on the phase/frame boundary.
	_sprites[target].visible = true
	_sprites[source].visible = false
	_sprites[source].modulate.a = 0.0
	_transition_from = target
	_transition_to = target
	_transition_elapsed = 0.0
	_active_transition_duration = 0.0
	_transitioning = false
	_current_key = key

func _pose_key(action: String, phase: String) -> String:
	if not ["attack1", "attack2", "attack3"].has(action) and not (EXTENDED_POSES.has(action) and phase in EXTENDED_POSES[action]):
		return ""
	if ["attack1", "attack2", "attack3"].has(action) and not PHASES.has(phase):
		return ""
	return action + "_" + phase

func _is_supported_action(action: String) -> bool:
	return ["attack1", "attack2", "attack3"].has(action) or EXTENDED_POSES.has(action)

func _load_safe_idle() -> Texture2D:
	if not ResourceLoader.exists(SAFE_IDLE_PATH):
		return null
	var texture := load(SAFE_IDLE_PATH) as Texture2D
	return texture if _texture_is_usable(texture) else null

func _texture_is_usable(texture: Texture2D) -> bool:
	if texture == null or texture.get_width() <= 0 or texture.get_height() <= 0:
		return false
	var cache_key := texture.get_instance_id()
	if _bounds_cache.has(cache_key):
		var cached_bounds: Rect2i = _bounds_cache[cache_key]
		return cached_bounds.size.x > 0 and cached_bounds.size.y > 0
	var image := texture.get_image()
	if image == null or image.is_empty():
		return false
	var bounds := image.get_used_rect()
	_bounds_cache[cache_key] = bounds
	return bounds.size.x > 0 and bounds.size.y > 0

func _bounds_for(texture: Texture2D) -> Rect2i:
	if texture == null:
		return Rect2i()
	var cache_key := texture.get_instance_id()
	if not _bounds_cache.has(cache_key):
		_texture_is_usable(texture)
	return _bounds_cache.get(cache_key, Rect2i())

func _place_sprite(sprite: Sprite2D) -> void:
	if sprite.texture == null:
		return
	var key := sprite.texture.get_instance_id()
	if not _bounds_cache.has(key):
		_texture_is_usable(sprite.texture)
	var bounds: Rect2i = _bounds_cache.get(key, Rect2i())
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		sprite.visible = false
		return
	var anchor: Vector2 = _anchor_overrides.get(key, Vector2(-1.0, -1.0))
	var foot := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y))
	if anchor.x >= 0.0 and anchor.y >= 0.0:
		foot = Vector2(anchor.x * sprite.texture.get_width(), anchor.y * sprite.texture.get_height())
	var foot_x := foot.x
	if _facing_left:
		foot_x = float(sprite.texture.get_width()) - foot_x
	var foot_from_center := (Vector2(foot_x, foot.y) - Vector2(sprite.texture.get_size()) * 0.5) * sprite.scale
	sprite.position = common_combat_anchor - foot_from_center

func _transitioning_index() -> int:
	return _transition_to if _transitioning else (0 if _sprites[0].visible else 1)
