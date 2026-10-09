extends RefCounted
class_name PlayerAnimationBank
"""Strict schema v1 loader with a byte-level approval gate for gameplay contact art."""

const MANIFEST_PATH := "res://data/art/animation_manifest.json"
const REVIEWED_FRAME_ALLOWLIST_PATH := "res://data/art/reviewed_frame_allowlist.json"
const SAFE_IDLE_TEXTURE := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const APPROVED_CONTACT_TEXTURES := {
	"attack1": "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"attack2": "res://assets/art/player/elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
	"attack3": "res://assets/art/player/elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
}
const APPROVED_CONTACT_DURATIONS := {"attack1": 0.105, "attack2": 0.12, "attack3": 0.14}
const VALID_PHASES := ["startup", "inbetween", "contact", "recovery"]
const VALID_APPROVALS := ["approved", "review", "unapproved", "temporary"]

var last_errors: Array[String] = []
var last_registered: Array[String] = []
var _phase_durations: Dictionary = {}
var _promotion_entries: Dictionary = {}
var _used_promotion_entries: Dictionary = {}

func load_and_register(pose_blender: PlayerPoseBlender, manifest_path := MANIFEST_PATH, registry_path := REVIEWED_FRAME_ALLOWLIST_PATH) -> bool:
	last_errors.clear()
	last_registered.clear()
	_phase_durations.clear()
	_promotion_entries.clear()
	_used_promotion_entries.clear()
	if pose_blender == null:
		return _fail("PoseBlender is missing")
	if not FileAccess.file_exists(manifest_path):
		return _fail("Animation manifest not found: " + manifest_path)
	if not _load_promotion_registry(registry_path):
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(manifest_path))
	if not parsed is Dictionary or typeof(parsed.get("schema_version")) not in [TYPE_INT, TYPE_FLOAT] or float(parsed["schema_version"]) != 1.0:
		return _fail("Animation manifest must use schema_version 1")
	var clips: Variant = parsed.get("clips")
	if not clips is Array or clips.is_empty():
		return _fail("Animation manifest clips must be a non-empty array")

	# Validate the whole document before registering anything, so a bad later frame
	# cannot leave a partially applied manifest in the runtime bank.
	var clip_ids := {}
	for clip_value in clips:
		if not clip_value is Dictionary:
			return _fail("Clip entry must be an object")
		var clip: Dictionary = clip_value
		if typeof(clip.get("id")) != TYPE_STRING or str(clip["id"]).strip_edges().is_empty():
			return _fail("Each clip must have a non-empty string id")
		var action: String = str(clip["id"])
		if clip_ids.has(action):
			return _fail("Duplicate clip id: " + action)
		clip_ids[action] = true
		var frames: Variant = clip.get("frames")
		if not frames is Array or frames.is_empty():
			return _fail("Clip frames must be a non-empty array: " + action)
		for frame_value in frames:
			if not frame_value is Dictionary:
				return _fail("Frame entry must be an object in clip: " + action)
			if not _validate_frame(action, frame_value, manifest_path):
				return false
	if _used_promotion_entries.size() != _promotion_entries.size():
		return _fail("Reviewed-frame registry contains an entry not present as an approved manifest frame")

	for clip_value in clips:
		var clip: Dictionary = clip_value
		var action: String = str(clip["id"])
		for frame_value in clip["frames"]:
			var frame: Dictionary = frame_value
			var phase: String = str(frame["phase"])
			var approval: String = str(frame["approval_state"])
			var duration: float = float(frame["duration"])
			if approval in ["temporary", "approved"]:
				_phase_durations[action + "_" + phase] = duration
			if approval != "approved" or action == "idle":
				continue
			var texture_source: Texture2D
			if _is_legacy_contact(action, phase):
				texture_source = _approved_texture_source(manifest_path, frame["texture"], action)
			else:
				texture_source = _load_approved_texture(manifest_path, frame["texture"])
			if texture_source == null:
				return false
			var anchor: Dictionary = frame["foot_anchor"]
			var anchor_point := Vector2(float(anchor["x"]), float(anchor["y"]))
			if pose_blender.register_pose_frame(action, phase, texture_source, duration, "approved manifest frame", str(frame.get("label", phase)), anchor_point, true):
				last_registered.append(action + "_" + phase)
			else:
				return _fail("PoseBlender rejected approved frame: " + str(frame["texture"]))
	return true

func _load_promotion_registry(registry_path: String) -> bool:
	if registry_path != REVIEWED_FRAME_ALLOWLIST_PATH or ProjectSettings.globalize_path(registry_path) != ProjectSettings.globalize_path(REVIEWED_FRAME_ALLOWLIST_PATH):
		return _fail("Reviewed-frame allowlist must come from the checked-in project registry")
	if not FileAccess.file_exists(registry_path):
		return _fail("Reviewed-frame allowlist not found: " + registry_path)
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(registry_path))
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("entries") is Array:
		return _fail("Reviewed-frame allowlist must use schema_version 1 and an entries array")
	for value in parsed["entries"]:
		if not value is Dictionary:
			return _fail("Reviewed-frame registry entry must be an object")
		var entry: Dictionary = value
		for key in ["clip", "phase", "texture", "sha256", "duration", "foot_anchor", "review_record", "manifest_sha256"]:
			if not entry.has(key):
				return _fail("Reviewed-frame registry entry is missing required field: " + key)
		if typeof(entry["clip"]) != TYPE_STRING or typeof(entry["phase"]) != TYPE_STRING or typeof(entry["texture"]) != TYPE_STRING or typeof(entry["review_record"]) != TYPE_STRING:
			return _fail("Reviewed-frame registry identity, texture, and review_record fields must be strings")
		var clip: String = entry["clip"]
		var phase: String = entry["phase"]
		var key := clip + "_" + phase
		if not ["attack1", "attack2", "attack3"].has(clip) or not VALID_PHASES.has(phase) or phase == "contact" or _promotion_entries.has(key):
			return _fail("Reviewed-frame registry has an invalid or duplicate clip/phase: " + key)
		if not _is_sha256(entry["sha256"]) or not _is_sha256(entry["manifest_sha256"]):
			return _fail("Reviewed-frame registry hashes must be 64 lowercase hexadecimal characters")
		if typeof(entry["duration"]) not in [TYPE_INT, TYPE_FLOAT] or not is_finite(float(entry["duration"])) or float(entry["duration"]) <= 0.0 or float(entry["duration"]) > 10.0:
			return _fail("Reviewed-frame registry duration must be finite and in the range (0, 10]")
		var anchor: Variant = entry["foot_anchor"]
		if not _valid_anchor(anchor):
			return _fail("Reviewed-frame registry foot_anchor must contain normalized x and y numbers")
		if not _is_reviewed_png_path(entry["texture"]):
			return _fail("Reviewed-frame registry texture must be a project PNG under assets/art/player")
		if not _review_record_exists(entry["review_record"]):
			return _fail("Reviewed-frame registry needs an existing manual review record under docs/review/records")
		_promotion_entries[key] = entry
	return true

func _promotion_frame_matches(manifest_path: String, action: String, phase: String, frame: Dictionary) -> bool:
	var key := action + "_" + phase
	if not _promotion_entries.has(key):
		return _fail("New approved frame is not present in the reviewed-frame registry: " + key)
	if manifest_path != MANIFEST_PATH or ProjectSettings.globalize_path(manifest_path) != ProjectSettings.globalize_path(MANIFEST_PATH):
		return _fail("Reviewed-frame promotion is accepted only from the checked-in animation manifest")
	var entry: Dictionary = _promotion_entries[key]
	if str(frame["texture"]) != str(entry["texture"]):
		return _fail("Approved frame texture does not match the reviewed-frame registry: " + key)
	var anchor: Dictionary = frame["foot_anchor"]
	var expected_anchor: Dictionary = entry["foot_anchor"]
	if float(frame["duration"]) != float(entry["duration"]) or float(anchor["x"]) != float(expected_anchor["x"]) or float(anchor["y"]) != float(expected_anchor["y"]):
		return _fail("Approved frame duration or normalized foot_anchor does not match its reviewed record: " + key)
	var manifest_file: String = ProjectSettings.globalize_path(MANIFEST_PATH)
	if _sha256_file(manifest_file) != str(entry["manifest_sha256"]):
		return _fail("Animation manifest SHA-256 does not match the reviewed-frame registry")
	var texture_file: String = ProjectSettings.globalize_path(str(frame["texture"]))
	if not _sha256_matches_file(texture_file, str(entry["sha256"])):
		return _fail("PNG SHA-256 does not match the reviewed-frame registry: " + key)
	_used_promotion_entries[key] = true
	return true

func _load_approved_texture(manifest_path: String, texture_value: Variant) -> Texture2D:
	var path := _resolve_texture_path(manifest_path, str(texture_value))
	if path.begins_with("res://"):
		if not ResourceLoader.exists(path):
			return null
		return load(path) as Texture2D
	var image := Image.new()
	if image.load(path) != OK:
		last_errors.append("Approved image could not be loaded: " + path)
		return null
	return ImageTexture.create_from_image(image)

func _is_legacy_contact(action: String, phase: String) -> bool:
	return phase == "contact" and APPROVED_CONTACT_TEXTURES.has(action)

func _is_sha256(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING or str(value).length() != 64:
		return false
	for character in str(value):
		if not "0123456789abcdef".contains(character):
			return false
	return true

func _valid_anchor(value: Variant) -> bool:
	if not value is Dictionary or not value.has("x") or not value.has("y"):
		return false
	if typeof(value["x"]) not in [TYPE_INT, TYPE_FLOAT] or typeof(value["y"]) not in [TYPE_INT, TYPE_FLOAT]:
		return false
	var x := float(value["x"])
	var y := float(value["y"])
	return is_finite(x) and is_finite(y) and x >= 0.0 and x <= 1.0 and y >= 0.0 and y <= 1.0

func _review_record_exists(reference: String) -> bool:
	if not _is_review_record_path(reference):
		return false
	var record_path: String = ProjectSettings.globalize_path(reference)
	return FileAccess.file_exists(record_path) and not FileAccess.get_file_as_string(record_path).strip_edges().is_empty()

func _is_reviewed_png_path(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var path: String = value
	var prefix := "res://assets/art/player/"
	if not path.begins_with(prefix) or not path.ends_with(".png") or not _is_safe_texture_path(path, MANIFEST_PATH):
		return false
	var filename := path.trim_prefix(prefix)
	if filename.is_empty() or filename.contains("/") or filename.length() <= 4:
		return false
	for character in filename:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-".contains(character):
			return false
	return true

func _is_review_record_path(value: Variant) -> bool:
	if typeof(value) != TYPE_STRING:
		return false
	var path: String = value
	var prefix := "res://docs/review/records/"
	if not path.begins_with(prefix) or not _is_safe_texture_path(path, MANIFEST_PATH):
		return false
	var filename := path.trim_prefix(prefix)
	if filename.is_empty() or filename.contains("/"):
		return false
	for character in filename:
		if not "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_.-".contains(character):
			return false
	return true

func _sha256_file(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	while file.get_position() < file.get_length():
		context.update(file.get_buffer(65536))
	file.close()
	return context.finish().hex_encode()

func _sha256_matches_file(path: String, expected_hash: String) -> bool:
	return _is_sha256(expected_hash) and FileAccess.file_exists(path) and _sha256_file(path) == expected_hash

func get_phase_duration(action: String, phase: String, fallback := 0.0) -> float:
	return float(_phase_durations.get(action + "_" + phase, fallback))

func _validate_frame(action: String, frame: Dictionary, manifest_path: String) -> bool:
	for key in ["phase", "duration", "texture", "foot_anchor", "approval_state"]:
		if not frame.has(key):
			return _fail("Frame is missing required schema v1 field: " + key)
	if typeof(frame["phase"]) != TYPE_STRING or typeof(frame["approval_state"]) != TYPE_STRING:
		return _fail("phase and approval_state must be strings")
	var phase: String = frame["phase"]
	var approval: String = frame["approval_state"]
	var valid_phase := phase == "idle" if action == "idle" else VALID_PHASES.has(phase)
	if not valid_phase:
		return _fail("Invalid animation phase: " + phase)
	if not VALID_APPROVALS.has(approval):
		return _fail("Unknown approval_state: " + approval)
	if typeof(frame["duration"]) not in [TYPE_INT, TYPE_FLOAT]:
		return _fail("duration must be a number")
	var duration := float(frame["duration"])
	if not is_finite(duration) or duration <= 0.0 or duration > 10.0:
		return _fail("duration must be finite and in the range (0, 10]")
	var texture: Variant = frame["texture"]
	if texture != null and (typeof(texture) != TYPE_STRING or str(texture).strip_edges().is_empty()):
		return _fail("texture must be a non-empty path or null")
	if approval == "approved" and typeof(texture) != TYPE_STRING:
		return _fail("Approved frame needs a texture path")
	if typeof(texture) == TYPE_STRING and not _is_safe_texture_path(str(texture), manifest_path):
		return _fail("Texture path must be relative and stay inside its manifest folder or project: " + str(texture))
	if typeof(texture) == TYPE_STRING:
		var resolved_texture := _resolve_texture_path(manifest_path, str(texture))
		var resolved_file: String = ProjectSettings.globalize_path(resolved_texture) if resolved_texture.begins_with("res://") else resolved_texture
		if not FileAccess.file_exists(resolved_file):
			return _fail("Referenced texture file does not exist: " + str(texture))
	var anchor: Variant = frame["foot_anchor"]
	if not anchor is Dictionary or not anchor.has("x") or not anchor.has("y"):
		return _fail("foot_anchor must be an object with normalized x and y numbers")
	if typeof(anchor["x"]) not in [TYPE_INT, TYPE_FLOAT] or typeof(anchor["y"]) not in [TYPE_INT, TYPE_FLOAT]:
		return _fail("foot_anchor x and y must be numbers")
	var x := float(anchor["x"])
	var y := float(anchor["y"])
	if not is_finite(x) or not is_finite(y) or x < 0.0 or x > 1.0 or y < 0.0 or y > 1.0:
		return _fail("foot_anchor x and y must be normalized to 0..1")
	if action == "idle":
		if phase != "idle" or approval != "approved" or texture != SAFE_IDLE_TEXTURE:
			return _fail("Idle entry must be the approved v8 still")
	elif approval == "approved":
		if _is_legacy_contact(action, phase):
			if not is_equal_approx(duration, float(APPROVED_CONTACT_DURATIONS[action])):
				return _fail("Approved contact duration does not match the live hitbox window: " + action)
			if not _approved_texture_matches(manifest_path, str(texture), action):
				return _fail("Approved frame is not byte-identical to the allowlisted keypose: " + str(texture))
		elif not _promotion_frame_matches(manifest_path, action, phase, frame):
			return false
	return true

func _is_safe_texture_path(texture_path: String, manifest_path: String) -> bool:
	# Resource paths in the checked-in manifest are supported, but URI, absolute,
	# drive, and traversal paths from external editor exports are not.
	if texture_path.begins_with("res://"):
		var resource_tail := texture_path.trim_prefix("res://")
		return not resource_tail.is_empty() and not _has_parent_segment(resource_tail) and not resource_tail.contains("\\")
	if texture_path.contains(":") or texture_path.begins_with("/") or texture_path.begins_with("\\") or texture_path.is_absolute_path():
		return false
	if texture_path.contains("\\") or _has_parent_segment(texture_path):
		return false
	var base := manifest_path.get_base_dir()
	if base.begins_with("res://"):
		return not (base.path_join(texture_path).simplify_path().trim_prefix("res://").begins_with("../"))
	if base.begins_with("user://"):
		return not (base.path_join(texture_path).simplify_path().trim_prefix("user://").begins_with("../"))
	return true

func _has_parent_segment(path: String) -> bool:
	for segment in path.split("/"):
		if segment == "..":
			return true
	return false

func _approved_texture_source(manifest_path: String, texture_value: Variant, action: String) -> Texture2D:
	var candidate_path := _resolve_texture_path(manifest_path, str(texture_value))
	var canonical_path: String = APPROVED_CONTACT_TEXTURES[action]
	var canonical_file: String = ProjectSettings.globalize_path(canonical_path)
	var candidate_file: String = ProjectSettings.globalize_path(candidate_path) if candidate_path.begins_with("res://") else candidate_path
	if not FileAccess.file_exists(candidate_file):
		last_errors.append("Approved candidate file is missing: " + candidate_file)
		return null
	if FileAccess.get_file_as_bytes(candidate_file) != FileAccess.get_file_as_bytes(canonical_file):
		last_errors.append("Approved frame is not byte-identical to the allowlisted keypose: " + str(texture_value))
		return null
	if candidate_path.begins_with("res://"):
		if not ResourceLoader.exists(candidate_path):
			return null
		return load(candidate_path) as Texture2D
	var candidate_image := Image.new()
	if candidate_image.load(candidate_path) != OK:
		last_errors.append("Approved image could not be loaded: " + candidate_path)
		return null
	return ImageTexture.create_from_image(candidate_image)

func _approved_texture_matches(manifest_path: String, texture_path: String, action: String) -> bool:
	var candidate_path := _resolve_texture_path(manifest_path, texture_path)
	var candidate_file: String = ProjectSettings.globalize_path(candidate_path) if candidate_path.begins_with("res://") else candidate_path
	var canonical_file: String = ProjectSettings.globalize_path(APPROVED_CONTACT_TEXTURES[action])
	return FileAccess.file_exists(candidate_file) and FileAccess.get_file_as_bytes(candidate_file) == FileAccess.get_file_as_bytes(canonical_file)

func _resolve_texture_path(manifest_path: String, texture_path: String) -> String:
	if texture_path.begins_with("res://"):
		return texture_path
	var base := manifest_path.get_base_dir()
	if base.begins_with("res://") or base.begins_with("user://"):
		return base.path_join(texture_path).simplify_path()
	return base.path_join(texture_path).simplify_path()

func _fail(message: String) -> bool:
	last_errors.append(message)
	return false
