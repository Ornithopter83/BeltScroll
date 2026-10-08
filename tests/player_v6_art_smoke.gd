extends SceneTree

const TOOL := preload("res://tools/prepare_player_v6.gd")
const SOURCE := "res://assets/art/player/elven_fighter_reference_v6_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_reference_v6_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_reference_v6_clean_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v6_comparison.png"
const TARGET := Vector2i(1254, 1254)
const MIN_MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var safe_path := ProjectSettings.globalize_path(SAFE)
	var clean_path := ProjectSettings.globalize_path(CLEAN)
	var original_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	var safe := _load_png(safe_path)
	var clean := _load_png(clean_path)
	_check(source != null, "원본 v6 PNG를 읽음")
	_check(safe != null, "safe 후보 PNG를 읽음")
	_check(clean != null, "clean 후보 PNG를 읽음")
	_check(FileAccess.file_exists(ProjectSettings.globalize_path(REVIEW)), "비교 이미지 PNG가 생성됨")
	if source != null and safe != null and clean != null:
		_check(_valid_canvas(safe), "safe가 RGBA 1254x1254이며 사방 90px 이상 투명 여백을 유지함")
		_check(_valid_canvas(clean), "clean이 RGBA 1254x1254이며 사방 90px 이상 투명 여백을 유지함")
		_check(FileAccess.get_file_as_bytes(source_path) == original_bytes, "원본 v6 바이트가 보존됨")
		_check(_same_alpha(safe, clean), "clean에서 alpha와 실루엣 배치가 보존됨")
		var before := TOOL.pollution_count(safe)
		var after := TOOL.pollution_count(clean)
		_check(before > after, "알파 경계의 붉고 노란 잔상이 감소함 (%d → %d)" % [before, after])
		_check(_interior_unchanged(safe, clean), "외곽 경계 분석 범위 밖의 색상과 형태가 보존됨")
		_check(_features_unchanged(safe, clean), "얼굴·포니테일·귀·주먹·금색 장식·손발 내부 색상이 보존됨")
		_check(TOOL.normalize_image(source).get_size() == TARGET, "정규화 결과가 목표 캔버스 크기임")
	_check(_protection_fixture(), "합성 피부·머리카락·금색 장식·손발 계열 색상을 보호함")
	_check(_error_handling(), "잘못된 실행 인수에서 종료 코드 2를 반환함")
	if failures.is_empty():
		print("player_v6_art_smoke: 모든 기계 검증 통과. 원화의 시각 승인은 별도 검수 대상.")
		print("player_v6_art_smoke: all checks passed; visual approval pending.")
		quit(0)
	else:
		for failure in failures:
			push_error("player_v6_art_smoke: " + failure)
		quit(1)

func _protection_fixture() -> bool:
	var image := Image.create(TARGET.x, TARGET.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(100, 100, 35, 35), Color("#17666b"))
	image.fill_rect(Rect2i(98, 105, 2, 25), Color("#ff1810"))
	image.fill_rect(Rect2i(200, 100, 30, 35), Color("#c58b28"))
	image.fill_rect(Rect2i(198, 105, 2, 25), Color("#d39a31"))
	image.fill_rect(Rect2i(300, 100, 30, 35), Color("#ca735d"))
	image.fill_rect(Rect2i(398, 105, 2, 25), Color("#bd8c4e"))
	image.fill_rect(Rect2i(400, 100, 30, 35), Color("#46352a"))
	var result: Dictionary = TOOL.clean_image(image)
	var output: Image = result["image"]
	return int(result["changed"]) > 0 \
		and TOOL.pollution_count(output) < TOOL.pollution_count(image) \
		and output.get_pixel(198, 110).is_equal_approx(image.get_pixel(198, 110)) \
		and output.get_pixel(298, 110).is_equal_approx(image.get_pixel(298, 110)) \
		and output.get_pixel(398, 110).is_equal_approx(image.get_pixel(398, 110)) \
		and output.get_pixel(99, 110).a == image.get_pixel(99, 110).a

func _features_unchanged(a: Image, b: Image) -> bool:
	var bounds := TOOL._alpha_bounds(a)
	var points := [Vector2(0.48, 0.10), Vector2(0.28, 0.28), Vector2(0.51, 0.25), Vector2(0.72, 0.31), Vector2(0.42, 0.42), Vector2(0.56, 0.62)]
	for relative in points:
		var center := bounds.position + Vector2i(roundi(relative.x * bounds.size.x), roundi(relative.y * bounds.size.y))
		var best := Vector2i(-1, -1)
		var distance := INF
		for y in range(maxi(bounds.position.y, center.y - 48), mini(bounds.end.y, center.y + 49)):
			for x in range(maxi(bounds.position.x, center.x - 48), mini(bounds.end.x, center.x + 49)):
				if a.get_pixel(x, y).a < 0.8 or TOOL._alpha_distance(a, x, y, 9) <= 8:
					continue
				var candidate_distance := Vector2(float(x - center.x), float(y - center.y)).length()
				if candidate_distance < distance:
					distance = candidate_distance
					best = Vector2i(x, y)
		if best.x < 0 or not a.get_pixelv(best).is_equal_approx(b.get_pixelv(best)):
			return false
	return true

func _error_handling() -> bool:
	var output: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/prepare_player_v6.gd", "--", "unexpected"])
	return OS.execute(OS.get_executable_path(), args, output, true) == 2

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != TARGET or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := TOOL._alpha_bounds(image)
	return bounds.size.x > 0 and bounds.size.y > 0 \
		and bounds.position.x >= MIN_MARGIN and bounds.position.y >= MIN_MARGIN \
		and TARGET.x - bounds.end.x >= MIN_MARGIN and TARGET.y - bounds.end.y >= MIN_MARGIN

func _same_alpha(a: Image, b: Image) -> bool:
	for y in range(TARGET.y):
		for x in range(TARGET.x):
			if a.get_pixel(x, y).a != b.get_pixel(x, y).a:
				return false
	return true

func _interior_unchanged(a: Image, b: Image) -> bool:
	for y in range(TARGET.y):
		for x in range(TARGET.x):
			var pixel := a.get_pixel(x, y)
			if pixel.a > 0.0 and TOOL._alpha_distance(a, x, y, EDGE_RADIUS_TEST) > EDGE_RADIUS_TEST and not pixel.is_equal_approx(b.get_pixel(x, y)):
				return false
	return true

func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

const EDGE_RADIUS_TEST := 8
