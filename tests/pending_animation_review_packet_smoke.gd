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
	"elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png",
	"elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png",
	"elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png",
	"elven_fighter_skill2_spin_backfist_v2_safe_candidate_1254x1254.png"
]

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packet := Image.new()
	_check(FileAccess.file_exists(PACKET), "review packet PNG exists")
	if FileAccess.file_exists(PACKET):
		_check(packet.load_png_from_buffer(FileAccess.get_file_as_bytes(PACKET)) == OK, "review packet PNG decodes")
		var item_count := 14 + _optional_hit_reaction_count()
		var rows := ceili(float(item_count) / 2.0)
		_check(packet.get_width() == 3160 and packet.get_height() >= 185 + rows * 796 + 32, "review packet page fits required and optional cards with dynamic height")
	_check(FileAccess.file_exists(TEMPLATE), "manual review record template exists")
	var allowlist := JSON.parse_string(FileAccess.get_file_as_string(ALLOWLIST)) as Dictionary
	_check(allowlist != null and allowlist.get("entries", []).is_empty(), "review packet work adds zero approved registry entries")
	var builder := FileAccess.get_file_as_string("res://tools/build_pending_animation_review_packet.gd")
	_check(builder.contains("기준 · 승인 idle v8") and builder.contains("기존 승인 정지 원화"), "existing approved idle status is preserved")
	_check(builder.contains("기준 · 승인 attack1 contact") and builder.contains("기존 승인 접촉 1/3"), "existing approved attack1 contact is preserved")
	_check(builder.contains("기준 · 승인 attack2 contact") and builder.contains("기존 승인 접촉 2/3"), "existing approved attack2 contact is preserved")
	_check(builder.contains("기준 · 승인 attack3 contact") and builder.contains("기존 승인 접촉 3/3"), "existing approved attack3 contact is preserved")
	for filename in EXPECTED_SOURCES:
		_check(FileAccess.file_exists("res://assets/art/player/" + filename), "packet source exists: " + filename)
	_check(builder.contains("elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png"), "run v4 selects the actual stride candidate")
	_check(builder.contains("elven_fighter_run_stride_v4_safe_candidate_1254x1254.png"), "run v4 safe is included for comparison")
	_check(not builder.contains("elven_fighter_reference_v4_1254x1254.png"), "run v4 is not confused with the unrelated reference v4")
	_check(builder.contains("elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png") and builder.contains("회전 접촉 원화 미수용"), "Num5 v1 file and rejected rotation verdict are explicit")
	_check(builder.contains("elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png") and builder.contains("원본 파일 확보 · 회전 접촉 원화 미수용"), "Num5 v2 file acquisition and rejected rotation verdict are explicit")
	_check(builder.contains("_find_optional_hit_reaction_candidates") and builder.contains("lower.contains(\"hit\") and lower.contains(\"reaction\")"), "hit reaction is an optional separate card only when an original candidate PNG exists")
	_check(_optional_hit_reaction_count() == 0 or builder.contains("미승인 후보 · hit reaction 원본"), "present hit reaction originals receive a separate unapproved card")
	_check(builder.contains("ceili(float(visible_items.size()) / COLS) * ROW_STEP"), "packet height grows with candidate count")
	_check(builder.contains("out.resize(target, target, Image.INTERPOLATE_LANCZOS)"), "game view scales the full shared 1254x1254 canvas")
	_check(builder.contains("alpha 재정규화가 아니며 게임 실측 비교가 아님"), "packet disclaims alpha-normalized art as in-game measurement")
	_check(builder.contains("지지발 미판정") and builder.contains("v1~v4 동일 보폭 · 반대 보폭 미수용"), "run support-foot uncertainty and same-stride rejection are explicit")
	_check(builder.contains("신규 승인 0건") and builder.contains("좌우 미러"), "packet preserves the approval boundary and mirrored comparison")
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

func _optional_hit_reaction_count() -> int:
	var count := 0
	var directory := DirAccess.open("res://assets/art/player/")
	if directory == null:
		return count
	directory.list_dir_begin()
	var filename := directory.get_next()
	while not filename.is_empty():
		var lower := filename.to_lower()
		if not directory.current_is_dir() and lower.ends_with(".png") and lower.contains("candidate") and lower.contains("hit") and lower.contains("reaction"):
			count += 1
		filename = directory.get_next()
	directory.list_dir_end()
	return count
