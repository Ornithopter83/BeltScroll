extends Node2D
class_name PlayerPoseBlender
"""Independent two-Sprite2D pose crossfader. No Player scene wiring is implied."""

const SAFE_IDLE_PATH := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const PHASES := ["startup", "contact", "recovery"]

@export var sprite_scale := Vector2(0.1489758, 0.1489758)
@export var common_foot_anchor := Vector2.ZERO
@export_range(0.01, 0.25, 0.005) var crossfade_duration := 0.075

var _sprites: Array[Sprite2D] = []
var _bounds_cache: Dictionary = {}
var _approved_textures: Dictionary = {}
var _current_key := "idle"
var _transition_from := 0
var _transition_to := 0
var _transition_elapsed := 0.0
var _transitioning := false
var _facing_left := false
var _ko := false

func _ready() -> void:
	for index in range(2):
		var sprite := Sprite2D.new()
		sprite.name = "PoseSprite%d" % index
		sprite.centered = true
		sprite.scale = sprite_scale
		sprite.visible = false
		add_child(sprite)
		_sprites.append(sprite)
	_request_texture("idle", _load_safe_idle())

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
	return true

## action is idle, attack1, attack2, or attack3. Attack phases are startup, contact,
## and recovery. Unknown/unapproved/missing poses safely resolve to the approved v8 still.
func set_pose(action: String, phase: String = "") -> void:
	if _ko:
		_request_texture("idle", _load_safe_idle())
		return
	var key := "idle" if action == "idle" else _pose_key(action, phase)
	var texture: Texture2D = _load_safe_idle()
	if not key.is_empty() and key != "idle" and _approved_textures.has(key):
		var candidate := _approved_textures[key] as Texture2D
		if _texture_is_usable(candidate):
			texture = candidate
		else:
			_approved_textures.erase(key)
			key = "idle"
	else:
		key = "idle"
	_request_texture(key, texture)

func set_facing_left(facing_left: bool) -> void:
	_facing_left = facing_left
	for sprite in _sprites:
		sprite.flip_h = facing_left
		_place_sprite(sprite)

## KO is terminal until clear_ko is called; it discards any in-flight attack transition.
func set_ko(is_ko: bool) -> void:
	_ko = is_ko
	if _ko:
		_request_texture("idle", _load_safe_idle(), true)

func clear_ko() -> void:
	_ko = false

func interrupt_to_idle() -> void:
	_request_texture("idle", _load_safe_idle(), true)

func get_current_pose_key() -> String:
	return _current_key

func get_displayed_textures() -> Array[Texture2D]:
	var result: Array[Texture2D] = []
	for sprite in _sprites:
		if sprite.visible and sprite.texture != null and sprite.modulate.a > 0.0:
			result.append(sprite.texture)
	return result

func _process(delta: float) -> void:
	if not _transitioning:
		return
	_transition_elapsed = minf(_transition_elapsed + maxf(delta, 0.0), crossfade_duration)
	var blend := 1.0 if crossfade_duration <= 0.0 else clampf(_transition_elapsed / crossfade_duration, 0.0, 1.0)
	_sprites[_transition_from].modulate.a = 1.0 - blend
	_sprites[_transition_to].modulate.a = blend
	if blend >= 1.0:
		_sprites[_transition_from].visible = false
		_sprites[_transition_from].modulate.a = 0.0
		_sprites[_transitioning_index()].modulate.a = 1.0
		_transitioning = false

func _request_texture(key: String, texture: Texture2D, immediate := false) -> void:
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
	if _current_key == key and _sprites[_transitioning_index()].texture == texture and not immediate:
		return
	var source := _transition_to if _transitioning and _sprites[_transition_to].modulate.a >= _sprites[_transition_from].modulate.a else _transition_from
	if not _transitioning:
		source = 0 if _sprites[0].visible else 1
	var target := 1 - source
	if _sprites[source].texture == texture and not immediate:
		_current_key = key
		return
	_sprites[target].texture = texture
	_sprites[target].modulate = Color(1.0, 1.0, 1.0, 0.0)
	_sprites[target].visible = true
	_place_sprite(_sprites[target])
	if _sprites[source].visible:
		_sprites[source].modulate.a = 1.0
	_transition_from = source
	_transition_to = target
	_transition_elapsed = 0.0
	_current_key = key
	if immediate or not _sprites[source].visible or crossfade_duration <= 0.0:
		_sprites[source].visible = false
		_sprites[source].modulate.a = 0.0
		_sprites[target].modulate.a = 1.0
		_transitioning = false
	else:
		_transitioning = true

func _pose_key(action: String, phase: String) -> String:
	if not ["attack1", "attack2", "attack3"].has(action) or not PHASES.has(phase):
		return ""
	return action + "_" + phase

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
	var foot_x := float(bounds.position.x) + float(bounds.size.x) * 0.5
	if _facing_left:
		foot_x = float(sprite.texture.get_width()) - foot_x
	var foot_from_center := (Vector2(foot_x, float(bounds.end.y)) - Vector2(sprite.texture.get_size()) * 0.5) * sprite.scale
	sprite.position = common_foot_anchor - foot_from_center

func _transitioning_index() -> int:
	return _transition_to if _transitioning else (0 if _sprites[0].visible else 1)
