extends SceneTree

const RELAYOUT := preload("res://tools/rebuild_player_keyposes_v2.gd")
const INSPECTOR := preload("res://tools/inspect_player_keyposes.gd")
const SOURCE := "res://assets/art/player/elven_fighter_attack_keyposes_v2_1254x1254.png"
const CANDIDATE := "res://assets/art/player/elven_fighter_attack_keyposes_v2_relayout_1254x1254.png"
const CONTACT := "res://assets/art/review/player_keyposes_v2_relayout_contact.png"
const CELL := 627
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load(SOURCE)
	var candidate := _load(CANDIDATE)
	var contact := _load(CONTACT)
	_check(source != null and source.get_size() == Vector2i(1254, 1254), "원본 v2 키포즈 PNG 존재 및 크기")
	_check(candidate != null and candidate.get_size() == Vector2i(1254, 1254), "relayout 후보가 원본과 같은 1254×1254 캔버스")
	_check(contact != null and contact.get_size() == Vector2i(1254, 600), "192px 전후/v8 비교판 생성")
	_check(not source_bytes.is_empty() and source_bytes == FileAccess.get_file_as_bytes(source_path), "v2 원본 파일 바이트 보존")
	if candidate != null:
		var report := INSPECTOR.inspect_image(candidate, [610, 610, 610, 610], 16, 2)
		_check(report["cells"].size() == 4, "네 셀 독립 기하 검사")
		_check(report["valid"], "각 셀 16px 이상 투명 여백과 공통 발 기준선 ±2px")
		var actual_feet: Array[int] = []
		for cell in report["cells"]:
			actual_feet.append(cell["foot_y"])
		_check(actual_feet.max() - actual_feet.min() <= 2, "후보 발 기준선 편차 2px 이하")
	var source_second := source.get_region(Rect2i(CELL, 0, CELL, CELL)) if source != null else null
	if source_second != null:
		var components := RELAYOUT._remove_small_detached_components(source_second)
		_check(components["removed_pixels"] >= 645, "2번 셀의 분리된 작은 주먹 조각/부유 파편 제거 규칙 확인")
	var source_third := source.get_region(Rect2i(0, CELL, CELL, CELL)) if source != null else null
	var source_fourth := source.get_region(Rect2i(CELL, CELL, CELL, CELL)) if source != null else null
	if source_third != null and source_fourth != null:
		_check(RELAYOUT._touches_source_edge(RELAYOUT._alpha_bounds(source_third)), "3번 원본 경계 접촉은 미해결로 검출")
		_check(RELAYOUT._touches_source_edge(RELAYOUT._alpha_bounds(source_fourth)), "4번 원본 경계/잘림은 미해결로 검출")
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(CANDIDATE)) and FileAccess.file_exists(ProjectSettings.globalize_path(CONTACT)), "후보와 검토 비교판 파일 저장")
	if failures.is_empty():
		print("player_keypose_relayout_smoke: all checks passed; source-edge clipping remains a visual review issue")
		quit(0)
	else:
		for failure in failures:
			push_error("player_keypose_relayout_smoke: " + failure)
		quit(1)

func _load(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute)) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
