extends SceneTree
"""Static contract checks for the isolated M6K walk candidate preview."""

const SCENE_PATH := "res://scenes/review/m6k_walk_cycle_preview.tscn"
const SCRIPT_PATH := "res://tools/prepare_m6k_walk_candidate_preview.gd"
const GATE_PATH := "res://docs/review/m6k_walk_candidate_gate.md"
const EXTRA_CANDIDATE_PATH := "res://assets/art/player/elven_fighter_walk_opposite_stride_v1_candidate_1254x1254.png"
const LEGACY_FILES := [
	"res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v5_far_leg_forward_candidate_1254x1254.png",
]

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var failures: Array[String] = []
	_check(FileAccess.file_exists(SCENE_PATH), "F6 review scene exists", failures)
	_check(FileAccess.file_exists(SCRIPT_PATH), "isolated preview script exists", failures)
	_check(FileAccess.file_exists(GATE_PATH), "human review gate exists", failures)
	for path in LEGACY_FILES:
		_check(FileAccess.file_exists(path), "legacy candidate exists: " + path.get_file(), failures)
	if FileAccess.file_exists(SCENE_PATH):
		var scene := FileAccess.get_file_as_string(SCENE_PATH)
		_check(scene.contains("prepare_m6k_walk_candidate_preview.gd"), "scene attaches the dedicated review script", failures)
	if FileAccess.file_exists(SCRIPT_PATH):
		var source := FileAccess.get_file_as_string(SCRIPT_PATH)
		_check(source.contains("DISPLAY_HEIGHT := 192.0") and source.contains("_alpha_bounds"), "art is normalized to 192px alpha height", failures)
		_check(source.contains("lower.contains(\"stride\")") and source.contains("get_file().to_lower().contains(\"resource\")") and source.contains("RESOURCE 보폭 후보") and source.contains("has_resource_candidate"), "RESOURCE candidates are labeled separately and missing RESOURCE status remains visible", failures)
		_check(source.contains("_find_additional_stride_candidates") and source.contains("not _is_legacy_candidate(path)"), "other unregistered walk/run stride candidates are shown in the isolated comparison", failures)
		_check(source.contains("_unhandled_key_input") and source.contains("KEY_LEFT") and source.contains("KEY_RIGHT"), "candidate selection is keyboard navigable", failures)
		_check(not source.contains("FRAME_DURATION") and not source.contains("Timer.new"), "single-pose images are never looped as a fake cycle", failures)
		_check(source.contains("manifest") and source.contains("allowlist") and source.contains("Player 씬"), "preview declares its integration boundary", failures)
	if FileAccess.file_exists(EXTRA_CANDIDATE_PATH) and load(SCRIPT_PATH) != null:
		var preview := Control.new()
		preview.set_script(load(SCRIPT_PATH))
		root.add_child(preview)
		await process_frame
		var candidates: Array = preview.get("_candidates")
		var extra_candidate_loaded := false
		for candidate in candidates:
			if str(candidate.get("path", "")) == EXTRA_CANDIDATE_PATH:
				extra_candidate_loaded = not bool(candidate.get("missing", true))
		_check(extra_candidate_loaded, "new unregistered opposite-stride PNG is loaded into the isolated review board", failures)
		preview.queue_free()
	if failures.is_empty():
		print("m6k_walk_candidate_preview_smoke: isolated static candidate comparison contract is present")
		quit(0)
		return
	for failure in failures:
		push_error("m6k_walk_candidate_preview_smoke: " + failure)
	quit(1)

func _check(condition: bool, message: String, failures: Array[String]) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
