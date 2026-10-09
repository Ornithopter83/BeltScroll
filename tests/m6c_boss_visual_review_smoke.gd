extends SceneTree

const REVIEW := preload("res://tools/build_m6c_boss_visual_review.gd")

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var reference := _make_warrior(Color("#a34a36"), false)
	var candidate := _make_warrior(Color("#356f9f"), true)
	var report := REVIEW.inspect_images(reference, candidate)
	_check(report.candidate_present, "synthetic candidate detected")
	_check(report.candidate.has_alpha and report.candidate.has_transparency, "RGBA alpha and transparency measured")
	_check(_has_check(report, "candidate_rgba", true), "RGBA source format check passes for synthetic PNG input")
	_check(not report.candidate.touches_edge and report.candidate.margin_min >= 2, "candidate clear margin and no clipping")
	_check(report.silhouette_iou > 0.45, "normalized silhouette comparison computed")
	_check(report.foot_delta == 0.0, "foot anchor alignment computed")
	_check(report.face_delta >= 0.0 and report.armor_delta >= 0.0, "face and armor visual deltas computed")
	_check(report.checks.size() >= 8, "candidate checks populated")
	var missing := REVIEW.inspect_images(reference, null)
	_check(missing.valid and not missing.candidate_present, "missing candidate remains a valid reference-only review")
	var clipped := _make_warrior(Color("#356f9f"), true)
	clipped.fill_rect(Rect2i(0, 36, 6, 48), Color("#356f9f"))
	var clipped_report := REVIEW.inspect_images(reference, clipped)
	_check(clipped_report.candidate.touches_edge and not clipped_report.valid, "clipped synthetic candidate fails review")
	var board := REVIEW.build_review_board(reference, candidate, report, "synthetic://boss_candidate.png")
	_check(board.get_size() == Vector2i(1500, 900), "comparison board dimensions are stable")
	var board_path := ProjectSettings.globalize_path("res://temp/m6c_boss_visual_review_smoke.png")
	var save_error := board.save_png(board_path)
	_check(save_error == OK, "synthetic comparison board saved")
	var reopened := Image.new()
	_check(reopened.load(board_path) == OK and reopened.get_size() == board.get_size(), "saved PNG reopens at expected size")
	if failures.is_empty():
		print("M6C boss visual review smoke: PASS")
		quit(0)
	else:
		for failure in failures:
			printerr("FAIL: %s" % failure)
		quit(1)

func _make_warrior(armor: Color, slight_variant: bool) -> Image:
	var image := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	image.fill(Color(0, 0, 0, 0))
	var dx := 2 if slight_variant else 0
	image.fill_rect(Rect2i(52 + dx, 12, 24, 25), Color("#d8b48d"))
	image.fill_rect(Rect2i(42 + dx, 38, 44, 39), armor)
	image.fill_rect(Rect2i(30 + dx, 44, 12, 35), Color("#4d5962"))
	image.fill_rect(Rect2i(86 + dx, 44, 12, 35), Color("#4d5962"))
	image.fill_rect(Rect2i(44 + dx, 75, 18, 39), Color("#343a44"))
	image.fill_rect(Rect2i(66 + dx, 75, 18, 39), Color("#343a44"))
	image.fill_rect(Rect2i(38 + dx, 109, 28, 7), Color("#654c38"))
	image.fill_rect(Rect2i(62 + dx, 109, 28, 7), Color("#654c38"))
	return image

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)

func _has_check(report: Dictionary, name: String, expected: bool) -> bool:
	for check in report.checks:
		if check.name == name:
			return check.ok == expected
	return false
