extends Node2D
"""DEBUG-only independent candidate walk display, driven by VisualAnimator state."""

const CONTACT_PATH := "res://assets/art/player/elven_fighter_walk_opposite_stride_v1_candidate_1254x1254.png"
const PASSING_PATH := "res://assets/art/player/elven_fighter_walk_passing_v1_candidate_1254x1254.png"
const REFERENCE_SPEED := 280.0
const CONTACT_DURATION := 0.24
const PASSING_DURATION := 0.18

@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var animator: Node = player.get_node("VisualAnimator")
@onready var art: Sprite2D = player.get_node("VisualRoot/PlayerArt") as Sprite2D
@onready var visual_root: Node2D = player.get_node("VisualRoot") as Node2D

var _frames: Array[Dictionary] = []
var _sprite: Sprite2D
var _status_label: Label
var _elapsed := 0.0
var _frame_index := 0
var _active := false
var _base_art_anchor := Vector2.ZERO
var _current_phase := "missing"

func _ready() -> void:
	set_process_priority(1)
	if not OS.is_debug_build():
		set_process(false)
		return
	_sprite = Sprite2D.new()
	_sprite.name = "DebugWalkCandidateFrame"
	_sprite.centered = true
	_sprite.z_index = 2
	_sprite.visible = false
	visual_root.add_child(_sprite)
	_status_label = Label.new()
	_status_label.name = "DebugWalkPhaseStatus"
	_status_label.position = visual_root.position + Vector2(-132.0, -302.0)
	_status_label.add_theme_font_size_override("font_size", 14)
	_status_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.42))
	_status_label.add_theme_color_override("font_shadow_color", Color(0.04, 0.035, 0.025, 0.95))
	_status_label.add_theme_constant_override("shadow_offset_x", 1)
	_status_label.add_theme_constant_override("shadow_offset_y", 1)
	_status_label.visible = false
	add_child(_status_label)
	_cache_idle_anchor()
	_load_available_frames()
	_update_status()

func _process(delta: float) -> void:
	if not OS.is_debug_build() or player == null or animator == null:
		return
	var walking: bool = str(animator.call("get_animation_state")) == "walk" and player.velocity.length() > 10.0
	if not walking or _frames.is_empty():
		_set_active(false)
		return
	_set_active(true)
	var speed_ratio := maxf(player.velocity.length(), 1.0) / REFERENCE_SPEED
	var duration := float(_frames[_frame_index]["duration"]) / speed_ratio
	_elapsed += maxf(delta, 0.0)
	if _elapsed >= duration:
		_elapsed = fposmod(_elapsed, duration)
		_frame_index = (_frame_index + 1) % _frames.size()
		_apply_frame()
	_update_status()

func get_current_frame_path() -> String:
	return str(_frames[_frame_index]["path"]) if not _frames.is_empty() and _active else ""

func get_current_phase() -> String:
	return _current_phase if _active else "inactive"

func get_cycle_status() -> String:
	return "INCOMPLETE: missing right-foot contact" if not _has_phase("right_contact") else "INCOMPLETE: missing right-foot passing"

func get_available_phase_names() -> PackedStringArray:
	var phases := PackedStringArray()
	for frame in _frames:
		phases.append(str(frame["phase"]))
	return phases

func get_current_frame_duration() -> float:
	if _frames.is_empty():
		return 0.0
	return float(_frames[_frame_index]["duration"]) * REFERENCE_SPEED / maxf(player.velocity.length(), 1.0)

func get_support_anchor_local() -> Vector2:
	if _sprite == null or _sprite.texture == null or _frames.is_empty():
		return Vector2.ZERO
	var frame: Dictionary = _frames[_frame_index]
	var texture_size := Vector2(_sprite.texture.get_size())
	var anchor := Vector2(float(frame["anchor_x"]), float(frame["anchor_y"])) * texture_size
	return _sprite.position + (anchor - texture_size * 0.5) * _sprite.scale

func _set_active(active: bool) -> void:
	if _active == active:
		return
	_active = active
	_sprite.visible = active
	_status_label.visible = active
	art.visible = not active
	if active:
		_elapsed = 0.0
		_frame_index = 0
		_apply_frame()
		_update_status()

func _apply_frame() -> void:
	if _frames.is_empty():
		return
	var frame: Dictionary = _frames[_frame_index]
	_sprite.texture = frame["texture"] as Texture2D
	_sprite.scale = art.scale.abs()
	var texture_size := Vector2(_sprite.texture.get_size())
	var anchor := Vector2(float(frame["anchor_x"]), float(frame["anchor_y"])) * texture_size
	var local_anchor := _base_art_anchor
	# Keep the reviewed left-support estimate on one screen point across the
	# contact-to-passing handoff; the source PNGs remain unmodified candidates.
	_sprite.position = local_anchor - (anchor - texture_size * 0.5) * _sprite.scale
	_current_phase = str(frame["phase"])

func _cache_idle_anchor() -> void:
	if art == null or art.texture == null:
		_base_art_anchor = Vector2(0.0, 52.0)
		return
	var bounds := art.texture.get_image().get_used_rect()
	var point := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y))
	_base_art_anchor = art.position + (point - Vector2(art.texture.get_size()) * 0.5) * art.scale.abs()

func _load_available_frames() -> void:
	var contact := _load_debug_texture(CONTACT_PATH)
	if contact != null:
		_frames.append({"phase": "left_contact", "path": CONTACT_PATH, "texture": contact, "duration": CONTACT_DURATION, "anchor_x": 0.4864, "anchor_y": 0.94})
	var passing := _load_debug_texture(PASSING_PATH)
	if passing != null:
		_frames.append({"phase": "passing", "path": PASSING_PATH, "texture": passing, "duration": PASSING_DURATION, "anchor_x": 0.4944, "anchor_y": 0.94})
	var right_path := _find_optional_right_contact()
	if not right_path.is_empty():
		var right_contact := _load_debug_texture(right_path)
		if right_contact != null:
			_frames.append({"phase": "right_contact", "path": right_path, "texture": right_contact, "duration": CONTACT_DURATION, "anchor_x": 0.5136, "anchor_y": 0.94})

func _load_debug_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _find_optional_right_contact() -> String:
	var directory := DirAccess.open("res://assets/art/player")
	if directory == null:
		return ""
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		var lower := filename.to_lower()
		if not directory.current_is_dir() and lower.ends_with(".png") and lower.contains("walk") and lower.contains("right") and lower.contains("contact"):
			directory.list_dir_end()
			return "res://assets/art/player/" + filename
		filename = directory.get_next()
	directory.list_dir_end()
	return ""

func _has_phase(phase: String) -> bool:
	for frame in _frames:
		if str(frame["phase"]) == phase:
			return true
	return false

func _update_status() -> void:
	if _status_label == null:
		return
	var phase_name := "MISSING · left contact"
	if not _frames.is_empty():
		match str(_frames[_frame_index]["phase"]):
			"left_contact":
				phase_name = "LEFT CONTACT"
			"passing":
				phase_name = "PASSING"
			"right_contact":
				phase_name = "RIGHT CONTACT"
			_:
				phase_name = "MISSING · " + str(_frames[_frame_index]["phase"])
	var right_status := "RIGHT PASSING: MISSING" if _has_phase("right_contact") else "RIGHT CONTACT: MISSING"
	_status_label.text = "DEBUG · %s\n%s · CYCLE INCOMPLETE" % [phase_name, right_status]
