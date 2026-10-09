extends SceneTree
"""Checks the review artifact wiring only; it does not judge or approve artwork."""

const PACKET := "res://assets/art/review/pending_animation_review_packet.png"
const ALLOWLIST := "res://data/art/reviewed_frame_allowlist.json"
const TEMPLATE := "res://docs/review/records/REVIEW_TEMPLATE.md"
const EXPECTED_SOURCES := [
	"elven_fighter_reference_v8_clean_candidate_1254x1254.png",
	"elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png",
	"elven_fighter_attack2_reference_v4_ink_final_candidate_1254x1254.png",
	"elven_fighter_attack3_reference_v2_contour_candidate_1254x1254.png",
	"elven_fighter_attack1_startup_v1_candidate_1254x1254.png",
	"elven_fighter_attack3_startup_v1_candidate_1254x1254.png",
	"elven_fighter_run_stride_v1_candidate_1254x1254.png",
	"elven_fighter_run_stride_v2_opposite_candidate_1254x1254.png",
	"elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png",
	"elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png",
	"elven_fighter_run_stride_v4_safe_candidate_1254x1254.png",
	"elven_fighter_jump_rise_v1_candidate_1254x1254.png",
	"elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png"
]

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packet := Image.new()
	_check(FileAccess.file_exists(PACKET), "review packet PNG exists")
	if FileAccess.file_exists(PACKET):
		_check(packet.load_png_from_buffer(FileAccess.get_file_as_bytes(PACKET)) == OK, "review packet PNG decodes")
		_check(packet.get_width() == 3160 and packet.get_height() >= 4993, "review packet page fits all fixed cards with dynamic height")
	_check(FileAccess.file_exists(TEMPLATE), "manual review record template exists")
	var allowlist := JSON.parse_string(FileAccess.get_file_as_string(ALLOWLIST)) as Dictionary
	_check(allowlist != null and allowlist.get("entries", []).is_empty(), "review packet work adds zero approved registry entries")
	for filename in EXPECTED_SOURCES:
		_check(FileAccess.file_exists("res://assets/art/player/" + filename), "packet source exists: " + filename)
	var builder := FileAccess.get_file_as_string("res://tools/build_pending_animation_review_packet.gd")
	_check(builder.contains("elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png"), "run v4 selects the actual stride candidate")
	_check(builder.contains("elven_fighter_run_stride_v4_safe_candidate_1254x1254.png"), "run v4 safe is included for comparison")
	_check(not builder.contains("elven_fighter_reference_v4_1254x1254.png"), "run v4 is not confused with the unrelated reference v4")
	_check(builder.contains("_find_optional_num5_candidates") and builder.contains("lower.contains(\"num5\") or lower.contains(\"skill2\")"), "Num5 candidates are included only when candidate PNG files exist")
	_check(builder.contains("ceili(float(visible_items.size()) / COLS) * ROW_STEP"), "packet height grows with candidate count")
	_check(builder.contains("out.resize(target, target, Image.INTERPOLATE_LANCZOS)"), "game view scales the full shared 1254x1254 canvas")
	_check(builder.contains("alpha 재정규화가 아니며 게임 실측 비교가 아님"), "packet disclaims alpha-normalized art as in-game measurement")
	_check(builder.contains("지지발 미판정") and builder.contains("동일 보폭"), "run support-foot uncertainty and existing same-stride verdict are explicit")
	if _failures.is_empty():
		print("pending_animation_review_packet_smoke: artifact wiring passed; no human approval performed")
		quit(0)
		return
	for failure in _failures:
		push_error("pending_animation_review_packet_smoke: " + failure)
	quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
