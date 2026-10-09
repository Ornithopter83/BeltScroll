extends RefCounted
class_name EditorDataLoader
"""Loads and validates optional runtime tuning data without requiring an editor."""

const DATA_PATH := "res://data/editor/overrides.json"
const SCHEMA_VERSION := 1
const LIMITS := {
	"max_health": {"min": 1.0, "max": 999.0},
	"walk_speed": {"min": 1.0, "max": 2000.0},
	"attack_damage": {"min": 0.0, "max": 999.0},
	"attack_hit_stun": {"min": 0.0, "max": 10.0},
	"attack_knockback": {"min": 0.0, "max": 3000.0},
	"attack_range": {"min": 1.0, "max": 1200.0},
	"recovery_duration": {"min": 0.0, "max": 30.0},
	"skill_cooldown": {"min": 0.0, "max": 60.0},
	"windup_duration": {"min": 0.0, "max": 10.0},
	"active_duration": {"min": 0.0, "max": 10.0},
	"notice_range": {"min": 1.0, "max": 3000.0},
	"attack_depth_tolerance": {"min": 1.0, "max": 500.0},
	"separation_radius": {"min": 0.0, "max": 1000.0},
	"separation_strength": {"min": 0.0, "max": 2000.0},
}
const INTEGER_FIELDS := ["max_health", "attack_damage"]

static func load_data(path: String = DATA_PATH) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_warning("[EditorData] Can't read %s; using scene defaults." % path)
		return {"schema_version": SCHEMA_VERSION, "characters": [], "enemies": [], "stages": []}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_warning("[EditorData] Root must be a JSON object; using scene defaults.")
		return {"schema_version": SCHEMA_VERSION, "characters": [], "enemies": [], "stages": []}
	var data: Dictionary = parsed
	if data.get("schema_version") != SCHEMA_VERSION:
		push_warning("[EditorData] Unsupported schema_version; using scene defaults.")
		return {"schema_version": SCHEMA_VERSION, "characters": [], "enemies": [], "stages": []}
	for key in ["characters", "enemies", "stages"]:
		if not data.get(key) is Array:
			push_warning("[EditorData] '%s' must be an array; ignoring it." % key)
			data[key] = []
	_validate_unique_ids(data)
	return data

static func _validate_unique_ids(data: Dictionary) -> void:
	var seen := {}
	for kind in ["characters", "enemies", "stages"]:
		var valid: Array = []
		var records: Array = data.get(kind, [])
		for index in range(records.size()):
			var record: Variant = records[index]
			if not record is Dictionary or not record.get("id", "") is String:
				valid.append(record)
				continue
			var normalized_id := String(record.id).strip_edges().to_lower()
			if normalized_id.is_empty():
				valid.append(record)
				continue
			if seen.has(normalized_id):
				push_warning("[EditorData] %s[%d] duplicates ID '%s' from %s; ignoring duplicate record." % [kind, index, record.id, seen[normalized_id]])
				continue
			seen[normalized_id] = "%s[%d]" % [kind, index]
			valid.append(record)
		data[kind] = valid

static func validate_record(record: Variant, kind: String, index: int) -> Dictionary:
	var label := "%s[%d]" % [kind, index]
	if not record is Dictionary:
		push_warning("[EditorData] %s must be an object; ignoring it." % label)
		return {}
	var result: Dictionary = record.duplicate(true)
	var id: Variant = result.get("id", "")
	if not id is String or String(id).strip_edges().is_empty():
		push_warning("[EditorData] %s has no valid id; ignoring it." % label)
		return {}
	if kind == "stages":
		_validate_stage(result, label)
		return result
	for field in LIMITS:
		if not result.has(field):
			continue
		var value: Variant = result[field]
		if not (value is int or value is float) or not is_finite(float(value)):
			push_warning("[EditorData] %s.%s must be a finite number; ignoring this field." % [label, field])
			result.erase(field)
			continue
		var limits: Dictionary = LIMITS[field]
		if float(value) < float(limits.min) or float(value) > float(limits.max):
			push_warning("[EditorData] %s.%s is outside [%s, %s]; ignoring this field." % [label, field, limits.min, limits.max])
			result.erase(field)
		elif field in INTEGER_FIELDS and float(value) != floor(float(value)):
			push_warning("[EditorData] %s.%s must be an integer; ignoring this field." % [label, field])
			result.erase(field)
	if result.has("skill_cooldowns"):
		var cooldowns: Variant = result.skill_cooldowns
		var cooldowns_valid: bool = cooldowns is Array and cooldowns.size() == 2
		if cooldowns_valid:
			for cooldown in cooldowns:
				if not (cooldown is int or cooldown is float) or not is_finite(float(cooldown)) or float(cooldown) < 0.0 or float(cooldown) > 60.0:
					cooldowns_valid = false
					break
		if not cooldowns_valid:
			push_warning("[EditorData] %s.skill_cooldowns must contain two values in [0, 60]; ignoring it." % label)
			result.erase("skill_cooldowns")
	if result.has("ai") and not result.ai is Dictionary:
		push_warning("[EditorData] %s.ai must be an object; ignoring AI overrides." % label)
		result.erase("ai")
	elif result.has("ai"):
		var ai: Dictionary = result.ai
		for field in ["notice_range", "attack_depth_tolerance", "separation_radius", "separation_strength"]:
			if ai.has(field):
				var value: Variant = ai[field]
				var limits: Dictionary = LIMITS[field]
				if not (value is int or value is float) or not is_finite(float(value)) or float(value) < float(limits.min) or float(value) > float(limits.max):
					push_warning("[EditorData] %s.ai.%s invalid; ignoring this field." % [label, field])
					ai.erase(field)
	return result

static func _validate_stage(stage: Dictionary, label: String) -> void:
	_validate_bounds(stage, label)
	if stage.has("player_bounds"):
		if not stage.player_bounds is Dictionary:
			push_warning("[EditorData] %s.player_bounds must be an object; ignoring it." % label)
			stage.erase("player_bounds")
		else:
			_validate_bounds(stage.player_bounds, label + ".player_bounds")
	if stage.has("spawns"):
		if not stage.spawns is Array:
			push_warning("[EditorData] %s.spawns must be an array; ignoring it." % label)
			stage.erase("spawns")
		else:
			var valid_spawns: Array = []
			for i in range(stage.spawns.size()):
				var spawn: Variant = stage.spawns[i]
				if spawn is Dictionary and spawn.get("actor_id") is String and (spawn.get("x") is float or spawn.get("x") is int):
					if (spawn.get("y") is int or spawn.get("y") is float) and is_finite(float(spawn.y)) and is_finite(float(spawn.x)) and absf(float(spawn.x)) <= 100000.0 and absf(float(spawn.y)) <= 100000.0:
						valid_spawns.append(spawn)
						continue
				push_warning("[EditorData] %s.spawns[%d] invalid; ignoring it." % [label, i])
			stage.spawns = valid_spawns

static func _validate_bounds(bounds: Dictionary, label: String) -> void:
	for field in ["left", "top", "right", "bottom"]:
		if not bounds.has(field):
			continue
		var value: Variant = bounds[field]
		if not (value is int or value is float) or not is_finite(float(value)) or absf(float(value)) > 100000.0:
			push_warning("[EditorData] %s.%s invalid; ignoring this boundary." % [label, field])
			bounds.erase(field)
	if bounds.has_all(["left", "right"]) and float(bounds.right) <= float(bounds.left):
		push_warning("[EditorData] %s horizontal bounds are reversed; ignoring both." % label)
		bounds.erase("left")
		bounds.erase("right")
	if bounds.has_all(["top", "bottom"]) and float(bounds.bottom) <= float(bounds.top):
		push_warning("[EditorData] %s vertical bounds are reversed; ignoring both." % label)
		bounds.erase("top")
		bounds.erase("bottom")

static func find_record(records: Array, id: String) -> Dictionary:
	for index in range(records.size()):
		var record := validate_record(records[index], "record", index)
		if String(record.get("id", "")) == id:
			return record
	return {}

static func apply_properties(target: Object, values: Dictionary, fields: Array[String]) -> void:
	if target == null:
		return
	for field in fields:
		if values.has(field) and _has_property(target, field):
			target.set(field, values[field])

static func _has_property(target: Object, property_name: String) -> bool:
	for property in target.get_property_list():
		if String(property.name) == property_name:
			return true
	return false
