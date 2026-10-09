extends SceneTree
"""Verifies the source/safe inventory and non-approval review artifact contract."""

const BOARD := "res://assets/art/review/player_run_antiphase_decision_sheet.png"
const BUILDER := "res://tools/build_player_run_antiphase_decision_sheet.gd"
const GATE := "res://docs/review/player_run_antiphase_authoring_gate.md"
const REQUIRED := [
	"res://assets/art/player/elven_fighter_run_stride_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_run_stride_v4_safe_candidate_1254x1254.png",
]
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in REQUIRED:
		_check(_valid_source(path), "required run source/safe PNG is present and 1254x1254: " + path)
	_check(not FileAccess.file_exists("res://assets/art/player/elven_fighter_run_stride_v3_safe_candidate_1254x1254.png"), "v3 safe absence is represented explicitly, not silently substituted")
	_check(FileAccess.file_exists(BUILDER), "repeatable decision-sheet builder is present")
	_check(FileAccess.file_exists(BOARD), "decision-sheet artifact exists")
	if FileAccess.file_exists(BOARD):
		var image := Image.new()
		_check(image.load(ProjectSettings.globalize_path(BOARD)) == OK and image.get_size() == Vector2i(3200, 1562), "decision sheet is readable at 3200x1562")
	if FileAccess.file_exists(BUILDER):
		var script := FileAccess.get_file_as_string(BUILDER)
		_check(script.contains("fixed_canvas_scale=true") and script.contains("approval=none") and script.contains("integration=none"), "builder fixes comparison scale and cannot approve or integrate a pose")
		_check(script.contains("SAFE FIT PREVIEW (DERIVED IN MEMORY; NOT SAVED)") and script.contains("_make_safe_preview") and script.contains("LEFT FACING (MIRROR VIEW)"), "builder labels the derived, unsaved v3 safe preview and mirrored view")
	if FileAccess.file_exists(GATE):
		var gate := FileAccess.get_file_as_string(GATE)
		for token in ["화면 전방", "가까운 다리", "먼 다리", "전방 팔", "후방 팔", "골반", "지지발 후보", "미수용", "후방", "전방"]:
			_check(gate.contains(token), "authoring gate records field: " + token)
		_check(gate.contains("본편 `run` clip") and gate.contains("자동 판정"), "gate keeps candidates out of main clip and forbids automatic support-foot approval")
	if failures.is_empty():
		print("player_run_antiphase_decision_smoke: review inventory and no-approval contract verified")
		quit(0)
		return
	for failure in failures:
		push_error("player_run_antiphase_decision_smoke: " + failure)
	quit(1)

func _valid_source(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var image := Image.new()
	return image.load(ProjectSettings.globalize_path(path)) == OK and image.get_size() == Vector2i(1254, 1254)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
