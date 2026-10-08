extends SceneTree

const TOOL := preload("res://tools/prepare_player_v5.gd")
const SOURCE := "res://assets/art/player/elven_fighter_reference_v5_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_reference_v5_safe_1254x1254.png"
const CLEAN := "res://assets/art/player/elven_fighter_reference_v5_clean_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v5_clean_comparison.png"
const TARGET := Vector2i(1254, 1254)
const MIN_MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var safe_path := ProjectSettings.globalize_path(SAFE)
	var clean_path := ProjectSettings.globalize_path(CLEAN)
	var review_path := ProjectSettings.globalize_path(REVIEW)
	var original_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	var safe := _load_png(safe_path)
	var clean := _load_png(clean_path)
	_check(source != null, "v5 원본 PNG를 읽음")
	_check(safe != null, "safe 후보 PNG를 읽음")
	_check(clean != null, "clean 후보 PNG를 읽음")
	_check(FileAccess.file_exists(review_path), "비교 이미지가 생성됨")
	if source != null and safe != null and clean != null:
		_check(_valid_canvas(safe), "safe가 RGBA 1254x1254이며 사방 90px 이상 투명 여백을 유지함")
		_check(_valid_canvas(clean), "clean이 RGBA 1254x1254이며 사방 90px 이상 투명 여백을 유지함")
		_check(FileAccess.get_file_as_bytes(source_path) == original_bytes, "원본 v5 바이트가 보존됨")
		_check(_same_alpha(safe, clean), "clean 생성에서 alpha와 실루엣 배치가 정확히 보존됨")
		_check(TOOL._alpha_bounds(safe).size.y == TOOL._alpha_bounds(clean).size.y, "safe와 clean의 전신 실루엣 높이가 같음")
		var before_count := TOOL.pollution_count(safe)
		var after_count := TOOL.pollution_count(clean)
		_check(before_count > after_count, "연결된 고채도 붉은 외곽 오염이 감소함 (%d → %d)" % [before_count, after_count])
		_check(_interior_unchanged(safe, clean), "외곽 분석 거리 밖의 정상 색상과 체형이 보존됨")
		_check(_named_features_unchanged(safe, clean), "머리카락·귀·얼굴·주먹·금색 장식·부츠 색상이 보존됨")
		print("v5 붉은 외곽 오염 픽셀 수: %d → %d" % [before_count, after_count])
	_check(_protected_color_fixture(), "합성 금색 장식·피부·머리카락 가장자리 색상을 보호함")
	_check(_failure_exit_code() == 2, "잘못된 실행 인수에서 비정상 성공 없이 종료 코드 2를 반환함")
	if failures.is_empty():
		print("player_v5_art_smoke: 모든 기계 검증 통과. 원화의 최종 승인은 별도 검수 대상.")
		quit(0)
	else:
		for failure in failures:
			push_error("player_v5_art_smoke: " + failure)
		quit(1)

func _protected_color_fixture() -> bool:
	var image := Image.create(TARGET.x, TARGET.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(100, 100, 30, 50), Color("#17666b"))
	image.fill_rect(Rect2i(97, 100, 3, 50), Color("#ff1610"))
	image.fill_rect(Rect2i(200, 100, 30, 50), Color("#c58b28"))
	image.set_pixel(199, 110, Color("#d39a31"))
	image.fill_rect(Rect2i(300, 100, 30, 50), Color("#ca735d"))
	image.set_pixel(299, 110, Color("#d47c65"))
	image.fill_rect(Rect2i(400, 100, 30, 50), Color("#bd8c4e"))
	image.set_pixel(399, 110, Color("#c99b5b"))
	var result := TOOL.clean_image(image)
	var output: Image = result["image"]
	return int(result["changed"]) >= 2 \
		and TOOL.pollution_count(output) < TOOL.pollution_count(image) \
		and output.get_pixel(199, 110).is_equal_approx(image.get_pixel(199, 110)) \
		and output.get_pixel(299, 110).is_equal_approx(image.get_pixel(299, 110)) \
		and output.get_pixel(399, 110).is_equal_approx(image.get_pixel(399, 110)) \
		and is_equal_approx(output.get_pixel(98, 110).a, image.get_pixel(98, 110).a)

func _named_features_unchanged(a: Image, b: Image) -> bool:
	var bounds := TOOL._alpha_bounds(a)
	var feature_points := [Vector2(0.35, 0.36), Vector2(0.48, 0.24), Vector2(0.55, 0.22), Vector2(0.65, 0.33), Vector2(0.51, 0.32), Vector2(0.32, 0.82), Vector2(0.71, 0.83)]
	for feature_index in range(feature_points.size()):
		var relative: Vector2 = feature_points[feature_index]
		var center := bounds.position + Vector2i(roundi(relative.x * bounds.size.x), roundi(relative.y * bounds.size.y))
		var best := Vector2i(-1, -1)
		var best_distance := INF
		for y in range(maxi(bounds.position.y, center.y - 12), mini(bounds.end.y, center.y + 13)):
			for x in range(maxi(bounds.position.x, center.x - 12), mini(bounds.end.x, center.x + 13)):
				if a.get_pixel(x, y).a < 0.8:
					continue
				var distance := Vector2(float(x - center.x), float(y - center.y)).length()
				if distance < best_distance:
					best_distance = distance
					best = Vector2i(x, y)
		if best.x < 0 or not a.get_pixelv(best).is_equal_approx(b.get_pixelv(best)):
			return false
	return true

func _failure_exit_code() -> int:
	var output: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/prepare_player_v5.gd", "--", "unexpected"])
	return OS.execute(OS.get_executable_path(), args, output, true)

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
			if pixel.a > 0.0 and TOOL._alpha_distance(a, x, y, 8) > 7 and not pixel.is_equal_approx(b.get_pixel(x, y)):
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
