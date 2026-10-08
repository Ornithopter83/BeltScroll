extends SceneTree

const TOOL := preload("res://tools/inspect_player_keyposes.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var normal := _fixture()
	var good := TOOL.inspect_image(normal)
	_check(good["valid"], "192px RGBA 2×2 시트 통과")
	_check(good["cells"].size() == 4, "셀별 네 개 독립 검사 결과")
	_check(TOOL.exit_code_for(good) == 0, "정상 입력 종료 코드 0")
	_check(_has_check(good["cells"][0]["checks"], "alpha_bounds"), "셀 alpha 경계 검사")
	_check(_has_check(good["cells"][0]["checks"], "cell_intrusion"), "셀 침범 검사")
	_check(_has_check(good["cells"][0]["checks"], "clipping"), "잘림 검사")
	_check(_has_check(good["cells"][0]["checks"], "foot_anchor"), "발 기준선 검사")
	_check(not TOOL.inspect_image(null)["valid"], "빈 입력 오류")
	_check(TOOL.exit_code_for(TOOL.inspect_image(null)) == 1, "검수 오류 종료 코드 1")
	var odd := Image.create(385, 384, false, Image.FORMAT_RGBA8)
	odd.fill(Color.TRANSPARENT)
	_check(not TOOL.inspect_image(odd)["valid"], "짝수가 아닌 전체 시트 크기 거부")
	var wrong_cells := Image.create(400, 400, false, Image.FORMAT_RGBA8)
	wrong_cells.fill(Color.TRANSPARENT)
	_add_rectangles(wrong_cells, 200, 200, 10, 10, 180, 180)
	var wrong_size_report := TOOL.inspect_image(wrong_cells)
	_check(not wrong_size_report["valid"] and not wrong_size_report["cells"][0]["valid"], "셀 크기 오류 독립 검출")
	var margin_report := TOOL.inspect_image(normal, [], 20)
	_check(not margin_report["valid"] and not _cell_check(margin_report["cells"][0], "alpha_margin"), "여백 부족 검출")
	var anchor_report := TOOL.inspect_image(normal, [150, 177, 177, 177], 2, 0)
	_check(not anchor_report["valid"] and not _cell_check(anchor_report["cells"][0], "foot_anchor"), "셀별 발 anchor 오차 검출")
	var edge := _fixture()
	edge.set_pixel(0, 80, Color.WHITE)
	var edge_report := TOOL.inspect_image(edge)
	_check(not edge_report["valid"] and not _cell_check(edge_report["cells"][0], "cell_intrusion"), "분할선 침범 검출")
	_check(not _cell_check(edge_report["cells"][0], "clipping"), "경계 접촉 잘림 검출")
	var contact := TOOL.build_contact_sheet(normal, _reference_fixture(), good)
	_check(contact.get_size() == Vector2i(832, 576), "192px 키포즈와 v8 비교 contact sheet 생성")
	if failures.is_empty():
		print("player_keypose_pipeline_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_keypose_pipeline_smoke: " + failure)
		quit(1)

func _fixture() -> Image:
	var image := Image.create(384, 384, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_add_rectangles(image, 192, 192, 10, 10, 180, 178)
	return image

func _add_rectangles(image: Image, cell_w: int, cell_h: int, x: int, y: int, right: int, bottom: int) -> void:
	for i in range(4):
		var origin := Vector2i((i % 2) * cell_w, (i / 2) * cell_h)
		image.fill_rect(Rect2i(origin.x + x, origin.y + y, right - x, bottom - y), Color("#79b6dd"))

func _reference_fixture() -> Image:
	var image := Image.create(192, 192, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(40, 12, 112, 168), Color("#c99971"))
	return image

func _has_check(checks: Array, name: String) -> bool:
	return _find_check(checks, name) != null

func _cell_check(cell: Dictionary, name: String) -> bool:
	var check = _find_check(cell["checks"], name)
	return check != null and check["ok"]

func _find_check(checks: Array, name: String):
	for check in checks:
		if check["name"] == name:
			return check
	return null

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
