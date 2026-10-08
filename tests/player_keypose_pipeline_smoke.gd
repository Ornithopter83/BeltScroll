extends SceneTree

const TOOL := preload("res://tools/inspect_player_keyposes.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for cell_size in [192, 627, 1024]:
		var sheet := _fixture(cell_size)
		var report := TOOL.inspect_image(sheet)
		_check(report["valid"], "%dpx 셀 2×2 시트 통과" % cell_size)
		_check(report["cells"].size() == 4, "%dpx 셀 독립 검사 결과 네 개" % cell_size)
		_check(report["cell_size"] == Vector2i(cell_size, cell_size), "%dpx 실제 셀 크기 보고" % cell_size)
		_check(_cell_check(report["cells"][0], "cell_size"), "%dpx 실제 셀 크기 판정" % cell_size)
		_check(_has_check(report["cells"][0]["checks"], "alpha_bounds"), "%dpx 셀 alpha 경계 검사" % cell_size)
		_check(_has_check(report["cells"][0]["checks"], "alpha_margin"), "%dpx 셀 투명 여백 검사" % cell_size)
		_check(_has_check(report["cells"][0]["checks"], "cell_intrusion"), "%dpx 셀 격자 침범 검사" % cell_size)
		_check(_has_check(report["cells"][0]["checks"], "foot_anchor"), "%dpx 셀 발 기준선 검사" % cell_size)
		_check(TOOL.exit_code_for(report) == 0, "%dpx 정상 입력 종료 코드 0" % cell_size)
	_check(_has_code(TOOL.inspect_image(null), "INPUT_MISSING"), "입력 부재 실패 코드")
	_check(TOOL.exit_code_for(TOOL.inspect_image(null)) == 1, "검수 오류 종료 코드 1")
	var odd := Image.create(1255, 1254, false, Image.FORMAT_RGBA8)
	odd.fill(Color.TRANSPARENT)
	_check(_has_code(TOOL.inspect_image(odd), "INVALID_DIMENSIONS"), "잘못된 차원 실패 코드")
	var nonsquare := Image.create(400, 402, false, Image.FORMAT_RGBA8)
	nonsquare.fill(Color.TRANSPARENT)
	_check(_has_code(TOOL.inspect_image(nonsquare), "INVALID_DIMENSIONS"), "비정사각형 입력 차원 거부")
	var normal := _fixture(192)
	var margin_report := TOOL.inspect_image(normal, [], 20)
	_check(not margin_report["valid"] and not _cell_check(margin_report["cells"][0], "alpha_margin"), "투명 여백 부족 검출")
	var anchor_report := TOOL.inspect_image(normal, [150, 177, 177, 177], 2, 0)
	_check(_has_code(anchor_report, "FOOT_BASELINE_ERROR") and not _cell_check(anchor_report["cells"][0], "foot_anchor"), "발 기준선 오차 실패 코드")
	var edge := _fixture(192)
	edge.set_pixel(0, 80, Color.WHITE)
	var edge_report := TOOL.inspect_image(edge)
	_check(_has_code(edge_report, "GRID_INTRUSION"), "격자 침범 실패 코드")
	_check(not _cell_check(edge_report["cells"][0], "clipping"), "경계 접촉 잘림 검출")
	var contact := TOOL.build_contact_sheet(_fixture(627), _reference_fixture(), TOOL.inspect_image(_fixture(627)))
	_check(contact.get_size() == Vector2i(832, 576), "627px 키포즈와 v8 clean을 동일한 192px 타일로 비교")
	if failures.is_empty():
		print("player_keypose_pipeline_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_keypose_pipeline_smoke: " + failure)
		quit(1)

func _fixture(cell_size: int) -> Image:
	var image := Image.create(cell_size * 2, cell_size * 2, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	_add_rectangles(image, cell_size)
	return image

func _add_rectangles(image: Image, cell_size: int) -> void:
	for i in range(4):
		var origin := Vector2i((i % 2) * cell_size, (i / 2) * cell_size)
		image.fill_rect(Rect2i(origin.x + 10, origin.y + 10, cell_size - 20, cell_size - 24), Color("#79b6dd"))

func _reference_fixture() -> Image:
	var image := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(40, 12, 112, 168), Color("#c99971"))
	return image

func _has_check(checks: Array, name: String) -> bool:
	return _find_check(checks, name) != null

func _cell_check(cell: Dictionary, name: String) -> bool:
	var check = _find_check(cell["checks"], name)
	return check != null and check["ok"]

func _has_code(report: Dictionary, code: String) -> bool:
	return report.get("failure_codes", []).has(code)

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
