extends RefCounted
class_name PlayerAnimationBank
"""Loads schema_version 1 editor manifests through explicit art approval gates."""

const MANIFEST_PATH := "res://data/art/animation_manifest.json"
const SAFE_IDLE_TEXTURE := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const APPROVED_CONTACT_TEXTURES := {
	"attack1": "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"attack2": "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
	"attack3": "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
}
const VALID_PHASES := ["startup", "inbetween", "contact", "recovery"]
const VALID_APPROVALS := ["approved", "review", "unapproved", "temporary"]

var last_errors: Array[String] = []
var last_registered: Array[String] = []
var _phase_durations: Dictionary = {}

func load_and_register(pose_blender: PlayerPoseBlender, manifest_path := MANIFEST_PATH) -> bool:
	last_errors.clear()
	last_registered.clear()
	_phase_durations.clear()
	if pose_blender == null:
		last_errors.append("PoseBlender is missing")
		return false
	if not FileAccess.file_exists(manifest_path):
		last_errors.append("Animation manifest not found: " + manifest_path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary or int(parsed.get("schema_version", 0)) != 1:
		last_errors.append("Animation manifest must use schema_version 1")
		return false
	var clips: Variant = parsed.get("clips", null)
	if not clips is Array:
		last_errors.append("Animation manifest clips must be an array")
		return false
	var all_valid := true
	for clip_value in clips:
		if not clip_value is Dictionary:
			last_errors.append("Clip entry must be an object")
			all_valid = false
			continue
		var clip: Dictionary = clip_value
		# Editor schema uses id; accept action as a backwards-compatible alias for the built-in manifest.
		var action := str(clip.get("id", clip.get("action", "")))
		var frames: Variant = clip.get("frames", null)
		if (action != "idle" and not APPROVED_CONTACT_TEXTURES.has(action)) or not frames is Array:
			last_errors.append("Invalid clip id or frames list in clip: " + action)
			all_valid = false
			continue
		for frame_value in frames:
			if not frame_value is Dictionary:
				last_errors.append("Frame entry must be an object in clip: " + action)
				all_valid = false
				continue
			var frame: Dictionary = frame_value
			var phase := str(frame.get("phase", ""))
			var duration := float(frame.get("duration", 0.0))
			var approval := str(frame.get("approval_state", ""))
			var anchor: Variant = frame.get("foot_anchor", null)
			if not _validate_frame(action, frame):
				all_valid = false
				continue
			# Preserve the built-in temporary phase clock; review-only editor frames cannot
			# alter gameplay timing or become registered artwork.
			if approval in ["temporary", "approved"]:
				_phase_durations[action + "_" + phase] = duration
			if approval != "approved" or action == "idle":
				continue
			if phase != "contact" or not APPROVED_CONTACT_TEXTURES.has(action):
				last_errors.append("Approved registration is only allowed for existing contact keyposes: " + action + "/" + phase)
				all_valid = false
				continue
			var texture_source: Variant = _approved_texture_source(manifest_path, frame.get("texture"), action)
			if texture_source == null:
				last_errors.append("Approved frame is not pixel-identical to the allowlisted keypose: " + str(frame.get("texture")))
				all_valid = false
				continue
			var anchor_point := Vector2(-1.0, -1.0)
			if anchor is Dictionary:
				anchor_point = Vector2(float(anchor["x"]), float(anchor["y"]))
			if pose_blender.register_pose_frame(action, phase, texture_source, duration, "approved manifest frame", str(frame.get("label", phase)), anchor_point, true):
				last_registered.append(action + "_" + phase)
			else:
				last_errors.append("PoseBlender rejected approved frame: " + str(frame.get("texture")))
				all_valid = false
	return all_valid

func get_phase_duration(action: String, phase: String, fallback := 0.0) -> float:
	return float(_phase_durations.get(action + "_" + phase, fallback))

func _validate_frame(action: String, frame: Dictionary) -> bool:
	var phase := str(frame.get("phase", ""))
	var texture_value: Variant = frame.get("texture", null)
	var duration := float(frame.get("duration", 0.0))
	var anchor: Variant = frame.get("foot_anchor", null)
	var approval := str(frame.get("approval_state", ""))
	var legacy_anchor: bool = anchor is String and anchor == "alpha_bottom_center"
	var editor_anchor: bool = anchor is Dictionary and anchor.has("x") and anchor.has("y")
	if editor_anchor:
		var x := float(anchor["x"])
		var y := float(anchor["y"])
		editor_anchor = is_finite(x) and is_finite(y) and x >= 0.0 and x <= 1.0 and y >= 0.0 and y <= 1.0
	if action == "idle":
		if phase != "idle" or texture_value != SAFE_IDLE_TEXTURE or approval != "approved":
			last_errors.append("Idle entry must be the approved v8 still")
			return false
	else:
		if not VALID_PHASES.has(phase):
			last_errors.append("Invalid animation phase: " + phase)
			return false
		if approval == "approved" and (not texture_value is String or str(texture_value).is_empty()):
			last_errors.append("Approved frame needs a texture path")
			return false
		if texture_value != null and not texture_value is String:
			last_errors.append("Candidate texture must be a path or null")
	if not is_finite(duration) or duration <= 0.0 or not (legacy_anchor or editor_anchor):
		last_errors.append("Frame needs positive duration and a valid string or normalized object foot_anchor")
		return false
	if not VALID_APPROVALS.has(approval):
		last_errors.append("Unknown approval_state: " + approval)
		return false
	return true

func _approved_texture_source(manifest_path: String, texture_value: Variant, action: String) -> Texture2D:
	if not texture_value is String:
		return null
	var canonical_path: String = APPROVED_CONTACT_TEXTURES[action]
	var candidate_path := _resolve_texture_path(manifest_path, str(texture_value))
	var canonical_file := ProjectSettings.globalize_path(canonical_path) if canonical_path.begins_with("res://") else canonical_path
	var candidate_file := ProjectSettings.globalize_path(candidate_path) if candidate_path.begins_with("res://") else candidate_path
	if not FileAccess.file_exists(candidate_file):
		last_errors.append("Candidate file missing at resolved path: " + candidate_file)
		return null
	if FileAccess.get_file_as_bytes(candidate_file) != FileAccess.get_file_as_bytes(canonical_file):
		return null
	if candidate_path.begins_with("res://"):
		if not ResourceLoader.exists(candidate_path):
			return null
		return load(candidate_path) as Texture2D
	var candidate_image := Image.new()
	if candidate_image.load(candidate_path) != OK:
		return null
	return ImageTexture.create_from_image(candidate_image)

func _resolve_texture_path(manifest_path: String, texture_path: String) -> String:
	if texture_path.begins_with("res://") or texture_path.begins_with("user://") or texture_path.is_absolute_path():
		return texture_path
	var base := manifest_path.get_base_dir()
	if base.begins_with("res://") or base.begins_with("user://"):
		return base.path_join(texture_path).simplify_path()
	if base.is_absolute_path():
		return base.path_join(texture_path).simplify_path()
	return ProjectSettings.globalize_path("res://").path_join(base).path_join(texture_path).simplify_path()
