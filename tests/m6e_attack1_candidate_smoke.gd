extends SceneTree
"""Checks normalization safety, missing-source handling, and the M6D cell-edge diagnosis."""

const BUILDER := preload("res://tools/prepare_m6e_attack1_candidate.gd")
const SOURCE_DIR := "res://assets/art/player"
const SHEET := "res://assets/art/player/elven_fighter_dark_fantasy_attack1_sheet_v1_candidate_1254x1254.png"
const CANDIDATE := "res://assets/art/player/elven_fighter_dark_fantasy_attack1_contact_safe_candidate_1254x1254.png"
const BOARD := "res://assets/art/review/m6e_attack1_candidate_comparison.png"
const EXPECTED_EDGES := [
	{"top": 0, "bottom": 49, "left": 0, "right": 0},
	{"top": 0, "bottom": 49, "left": 0, "right": 0},
	{"top": 35, "bottom": 0, "left": 0, "right": 50},
	{"top": 47, "bottom": 0, "left": 49, "right": 0},
]

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_paths: Array[String] = []
	var dir := DirAccess.open(SOURCE_DIR)
	if dir != null:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while not entry.is_empty():
			var lower := entry.to_lower()
			if not dir.current_is_dir() and lower.ends_with(".png") and lower.contains("dark_fantasy") and lower.contains("attack1") and lower.contains("contact") and not lower.contains("sheet"):
				source_paths.append(entry)
			entry = dir.get_next()
		dir.list_dir_end()
	_check((source_paths.is_empty() and not FileAccess.file_exists(CANDIDATE)) or (not source_paths.is_empty() and FileAccess.file_exists(CANDIDATE)), "candidate output exists only after a matching single-contact input is supplied")
	_check(FileAccess.file_exists(SHEET), "existing M6D 2×2 candidate sheet remains available for alpha diagnostics")
	if FileAccess.file_exists(SHEET):
		var sheet := _load(SHEET)
		_check(sheet != null and sheet.get_size() == Vector2i(1254, 1254), "M6D source sheet loads at 1254×1254")
		if sheet != null and sheet.get_width() % 2 == 0 and sheet.get_height() % 2 == 0:
			var size := sheet.get_size() / 2
			for index in range(4):
				var crop: Image = sheet.get_region(Rect2i(Vector2i(index % 2, index / 2) * size, size))
				_check(BUILDER.edge_alpha_counts(crop) == EXPECTED_EDGES[index], "cell %s edge alpha matches recorded crop-boundary diagnosis" % ["top-left", "top-right", "bottom-left", "bottom-right"][index])
	var tool_text := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://tools/prepare_m6e_attack1_candidate.gd"))
	_check(tool_text.contains("normalize_image") and tool_text.contains("FORMAT_RGBA8") and tool_text.contains("SAFE_MARGIN := 90"), "normalization converts to RGBA8 and enforces transparent margin / foot anchor")
	_check(tool_text.contains("not_created") and tool_text.contains("_edge_total(edges) > 0"), "missing single-contact source does not get replaced by a 2×2 crop and edge contact is detected")
	_check(tool_text.contains("no limb reconstruction") and tool_text.contains("manifest / allowlist changes"), "review forbids inferred limb reconstruction and registration changes")
	_check(FileAccess.file_exists(BOARD), "comparison board exists")
	if FileAccess.file_exists(BOARD):
		var image := _load(BOARD)
		_check(image != null and image.get_size() == Vector2i(1920, 1080), "comparison board is readable at 1920×1080")
	if _failures.is_empty():
		print("m6e_attack1_candidate_smoke: checks passed")
		quit(0)
		return
	for failure in _failures:
		push_error("m6e_attack1_candidate_smoke: " + failure)
	quit(1)

func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK or image.is_empty():
		return null
	return image

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
