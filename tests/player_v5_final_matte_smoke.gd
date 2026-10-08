extends SceneTree

const TOOL := preload("res://tools/finalize_player_v5_matte.gd")
const SOURCE := "res://assets/art/player/elven_fighter_reference_v5_clean_1254x1254.png"
const CANDIDATE := "res://assets/art/player/elven_fighter_reference_v5_final_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v5_final_matte_review.png"
const SIZE := Vector2i(1254, 1254)
const MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var candidate_path := ProjectSettings.globalize_path(CANDIDATE)
	var review_path := ProjectSettings.globalize_path(REVIEW)
	var original_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	var candidate := _load_png(candidate_path)
	var review := _load_png(review_path)
	_check(source != null and candidate != null, "원본과 최종 후보 PNG를 읽음")
	_check(review != null, "전후 검토 이미지가 생성됨")
	if source != null and candidate != null:
		_check(_valid_canvas(candidate), "후보가 RGBA 1254x1254이며 사방 90px 여백을 유지함")
		_check(FileAccess.get_file_as_bytes(source_path) == original_bytes, "v5_clean 원본 바이트가 보존됨")
		_check(_same_alpha(source, candidate), "재구성 가능한 색상 잔상 정리에서 알파 실루엣이 보존됨")
		_check(_interior_unchanged(source, candidate), "알파 경계에서 먼 전경 내부는 픽셀 단위로 보존됨")
		_check(_protected_head_unchanged(source, candidate), "얼굴·귀·포니테일 금색 장식 보호 구역이 보존됨")
		_check(_changed_rgb_count(source, candidate) > 0, "알파 경계와 내부 빈틈의 오염 후보 색상이 교정됨")
		_check(_spill_score(candidate) < _spill_score(source), "극외곽 색 번짐 점수가 증가하지 않고 감소함")
	if review != null:
		_check(review.get_size() == Vector2i(2200, 2080), "흰색·검정·체커보드·Forest Ruins에서 전신·얼굴·포니테일·192px 패널을 생성함")
	_check(_protected_color_fixture(), "합성 정상 금색·피부·머리카락과 실루엣 알파를 보호함")
	_check(TOOL.finalize_file("res://missing_player_v5.png", candidate_path) == ERR_FILE_NOT_FOUND, "없는 입력에서 파일 오류를 반환함")
	_check(TOOL.finalize_file(source_path, source_path) == ERR_INVALID_PARAMETER, "원본 덮어쓰기 요청을 거부함")
	_check(_failure_exit_code() == 2, "잘못된 CLI 인수에서 종료 코드 2를 반환함")
	if failures.is_empty():
		print("player_v5_final_matte_smoke: 모든 기계 검증 통과. 시각 최종 승인은 별도 검수 대상.")
		print("player_v5_final_matte_smoke: all checks passed; visual approval pending.")
		quit(0)
	else:
		for failure in failures:
			push_error("player_v5_final_matte_smoke: " + failure)
		quit(1)

func _protected_color_fixture() -> bool:
	var image := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(100, 100, 24, 50), Color("#236b72"))
	image.fill_rect(Rect2i(97, 100, 3, 50), Color("#ff1810"))
	image.fill_rect(Rect2i(200, 100, 24, 50), Color("#c58b28"))
	image.set_pixel(199, 110, Color("#d39a31"))
	image.fill_rect(Rect2i(300, 100, 24, 50), Color("#ca735d"))
	image.set_pixel(299, 110, Color("#d47c65"))
	image.fill_rect(Rect2i(400, 100, 24, 50), Color("#bd8c4e"))
	image.set_pixel(399, 110, Color("#c99b5b"))
	var clean := TOOL.refine_image(image)
	return clean.get_pixel(98, 110).a == image.get_pixel(98, 110).a \
		and clean.get_pixel(199, 110).is_equal_approx(image.get_pixel(199, 110)) \
		and clean.get_pixel(299, 110).is_equal_approx(image.get_pixel(299, 110)) \
		and clean.get_pixel(399, 110).is_equal_approx(image.get_pixel(399, 110)) \
		and clean.get_pixel(110, 110).is_equal_approx(image.get_pixel(110, 110))

func _spill_score(image: Image) -> int:
	var count := 0
	for y in range(1, image.get_height() - 1):
		for x in range(1, image.get_width() - 1):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.08 or not TOOL._near_transparent_boundary(image, x, y, 2):
				continue
			var evidence := TOOL._foreground_medoid(image, x, y, 6)
			if evidence.valid and TOOL._is_supported_warm_outlier(pixel, evidence.color, Vector3(pixel.r, pixel.g, pixel.b).distance_to(Vector3(evidence.color.r, evidence.color.g, evidence.color.b)), evidence.support):
				count += 1
	return count

func _changed_rgb_count(a: Image, b: Image) -> int:
	var count := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var p := a.get_pixel(x, y)
			var q := b.get_pixel(x, y)
			if p.r != q.r or p.g != q.g or p.b != q.b:
				count += 1
	return count

func _same_alpha(a: Image, b: Image) -> bool:
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if a.get_pixel(x, y).a != b.get_pixel(x, y).a:
				return false
	return true

func _interior_unchanged(a: Image, b: Image) -> bool:
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var pixel := a.get_pixel(x, y)
			if pixel.a > 0.0 and not TOOL._near_transparent_boundary(a, x, y, 8) and not pixel.is_equal_approx(b.get_pixel(x, y)):
				return false
	return true

func _protected_head_unchanged(a: Image, b: Image) -> bool:
	var bounds := TOOL._alpha_bounds(a)
	for y in range(bounds.position.y, bounds.end.y):
		for x in range(bounds.position.x, bounds.end.x):
			var relative := Vector2(float(x - bounds.position.x) / bounds.size.x, float(y - bounds.position.y) / bounds.size.y)
			if Rect2(0.36, 0.035, 0.36, 0.235).has_point(relative) and not a.get_pixel(x, y).is_equal_approx(b.get_pixel(x, y)):
				return false
	return true

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := TOOL._alpha_bounds(image)
	return bounds.size.x > 0 and bounds.size.y > 0 and bounds.position.x >= MARGIN and bounds.position.y >= MARGIN \
		and SIZE.x - bounds.end.x >= MARGIN and SIZE.y - bounds.end.y >= MARGIN

func _load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _failure_exit_code() -> int:
	var output: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/finalize_player_v5_matte.gd", "--", "unexpected"])
	return OS.execute(OS.get_executable_path(), args, output, true)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
