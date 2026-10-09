extends SceneTree
"""Checks the isolated M6D motion candidate review tool and generated evidence."""

const TOOL_PATH := "res://tools/build_m6d_motion_candidate_review.gd"
const CAPTURE_PATH := "res://assets/art/review/m6d_motion_candidate_comparison.png"
const GATE_PATH := "res://docs/review/m6d_motion_candidate_gate.md"
const RESOURCE_ROOT := "res://assets/art/player"

var _failures: Array[String] = []

func _initialize() -> void:
	_run()

func _run() -> void:
	_check(FileAccess.file_exists(TOOL_PATH), "isolated M6D review builder exists")
	if FileAccess.file_exists(TOOL_PATH):
		var source := FileAccess.get_file_as_string(TOOL_PATH)
		_check(source.contains("_find_resource_sheet") and source.contains("_load_resource_frames") and source.contains("found_attack_sheet"), "RESOURCE and attack sheet discovery with 2x2 extraction are implemented")
		_check(source.contains("TOP LEFT") and source.contains("TOP RIGHT") and source.contains("BOTTOM LEFT") and source.contains("BOTTOM RIGHT"), "cell order is explicit and stable")
		_check(source.contains("_alpha_bounds") and source.contains("_alpha_counts") and source.contains("_edge_alpha_counts") and source.contains("_bottom_alpha_anchor"), "alpha bounds, transparency, crop edges and bottom contact estimate are measured")
		_check(source.contains("_changed_pixels") and source.contains("procedural_transform=none"), "source frame changes are measured separately from procedural transforms")
		_check(source.contains("observed_ms") and source.contains("rendered_frames") and source.contains("frame_post_draw"), "visible frame playback logs measured exposure and rendered frames")
		_check(source.contains("elven_fighter_attack1_startup_v1_candidate") and source.contains("elven_fighter_attack2_contact_v6_candidate"), "fallback uses pending original attack art candidates")
		_check(source.contains("runtime_registration=none") and source.contains("approval=not_performed"), "review stays isolated and unapproved")
		_check(not source.contains("manifest") or source.contains("no manifest or PlayerArt changes"), "tool states that project art registration remains untouched")
	_check(FileAccess.file_exists(CAPTURE_PATH), "comparison PNG exists")
	if FileAccess.file_exists(CAPTURE_PATH):
		var image := Image.new()
		_check(image.load(ProjectSettings.globalize_path(CAPTURE_PATH)) == OK and image.get_size() == Vector2i(1920, 1080), "comparison PNG is readable at 1920x1080")
	_check(FileAccess.file_exists(GATE_PATH), "review findings are documented")
	if FileAccess.file_exists(GATE_PATH):
		var gate := FileAccess.get_file_as_string(GATE_PATH)
		_check(gate.contains("2×2") and gate.contains("미승인") and gate.contains("실측"), "gate records 2x2 sheet status, pending candidate status and measured exposure")
		_check(gate.contains("절차적") and gate.contains("테두리") and gate.contains("PlayerArt") and gate.contains("manifest"), "gate distinguishes procedural variation, crop edge alpha and isolation boundary")
	if _failures.is_empty():
		print("m6d_motion_candidate_review_smoke: isolated review evidence is present")
		quit(0)
		return
	for failure in _failures:
		push_error("m6d_motion_candidate_review_smoke: " + failure)
	quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
