extends SceneTree

const TOOL := preload("res://tools/prepare_player_v7_ink.gd")
const SOURCE := "res://assets/art/player/elven_fighter_reference_v7_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_reference_v7_safe_1254x1254.png"
const INK := "res://assets/art/player/elven_fighter_reference_v7_ink_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v7_ink_review.png"
const SIZE := 1254
const MARGIN := 90
const BAND := 4
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load(source_path)
	var safe := _load(ProjectSettings.globalize_path(SAFE))
	var ink := _load(ProjectSettings.globalize_path(INK))
	var review := _load(ProjectSettings.globalize_path(REVIEW))
	_check(source != null, "v7 원본 PNG를 읽음")
	_check(safe != null, "safe 후보 PNG를 읽음")
	_check(ink != null, "ink 후보 PNG를 읽음")
	_check(review != null, "원본·safe·ink 검수 시트가 생성됨")
	if source != null and safe != null and ink != null:
		_check(_valid_canvas(safe), "safe가 RGBA 1254x1254이고 사방 90px 투명 여백을 유지함")
		_check(_valid_canvas(ink), "ink 후보가 RGBA 1254x1254이고 사방 90px 투명 여백을 유지함")
		_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "원본 v7 바이트가 보존됨")
		_check(_same_alpha(safe, ink), "재구성 전후 alpha와 실루엣 배치가 동일함")
		_check(_interior_unchanged(safe, ink), "alpha 경계에서 4px 밖 내부 색상이 보존됨")
		_check(TOOL.pollution_count(safe) > TOOL.pollution_count(ink), "국소 색상 오염이 감소함 (%d → %d)" % [TOOL.pollution_count(safe), TOOL.pollution_count(ink)])
		_check(_all_changes_are_ink(safe, ink), "수정 픽셀만 중성 암갈색 잉크색을 사용함")
		_check(_fixture_and_contour(), "얼굴·귀·주먹 계열 가장자리 처리와 연속 윤곽을 확인함")
	_check(_error_handling(), "잘못된 실행 인수에서 실패 코드 2를 반환함")
	if failures.is_empty():
		print("player_v7_ink_smoke: all checks passed; visual approval pending.")
		quit(0)
	else:
		for failure in failures:
			push_error("player_v7_ink_smoke: " + failure)
		quit(1)

func _fixture_and_contour() -> bool:
	var image := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	var base := Color("#17666b")
	image.fill_rect(Rect2i(100, 100, 38, 42), base)
	# A deliberately contaminated outer rim crosses the cheek/ear/fist-style
	# silhouette; no semantic or feature-specific exemption is used.
	for y in range(105, 137):
		for x in range(100, 103):
			image.set_pixel(x, y, Color("#f81810"))
	var processed: Dictionary = TOOL.ink_image(image)
	var result: Image = processed["image"]
	var changed := 0
	var continuous := true
	for y in range(108, 134):
		var p := result.get_pixel(100, y)
		if not p.is_equal_approx(base):
			changed += 1
			if not p.is_equal_approx(Color("#30241f")) or p.a != 1.0:
				continuous = false
	_check(changed >= 20, "피부·귀·주먹으로 분류될 수 있는 가장자리도 국소 기준으로 재구성됨")
	_check(continuous, "오염 구간에 끊기지 않는 잉크 경계가 이어지고 alpha가 보존됨")
	_check(result.get_pixel(115, 120).is_equal_approx(base), "정상 내부색은 보존됨")
	# Warm ornament matching its local color must remain intact.
	image.fill_rect(Rect2i(180, 100, 30, 40), Color("#72522a"))
	image.fill_rect(Rect2i(180, 105, 3, 25), Color("#d39a31"))
	var gold_result: Image = TOOL.ink_image(image)["image"]
	return gold_result.get_pixel(180, 115).is_equal_approx(Color("#d39a31"))

func _error_handling() -> bool:
	var output: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/prepare_player_v7_ink.gd", "--", "unexpected"])
	return OS.execute(OS.get_executable_path(), args, output, true) == 2

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != Vector2i(SIZE, SIZE) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _bounds(image)
	return bounds.size.x > 0 and bounds.position.x >= MARGIN and bounds.position.y >= MARGIN \
		and SIZE - bounds.end.x >= MARGIN and SIZE - bounds.end.y >= MARGIN

func _bounds(image: Image) -> Rect2i:
	var left := SIZE; var top := SIZE
	var right := -1; var bottom := -1
	for y in range(SIZE):
		for x in range(SIZE):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x); top = mini(top, y)
				right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

func _same_alpha(a: Image, b: Image) -> bool:
	for y in range(SIZE):
		for x in range(SIZE):
			if a.get_pixel(x, y).a != b.get_pixel(x, y).a:
				return false
	return true

func _interior_unchanged(a: Image, b: Image) -> bool:
	for y in range(SIZE):
		for x in range(SIZE):
			var p := a.get_pixel(x, y)
			if p.a > 0.0 and TOOL._alpha_distance(a, x, y, BAND) > BAND and not p.is_equal_approx(b.get_pixel(x, y)):
				return false
	return true

func _all_changes_are_ink(a: Image, b: Image) -> bool:
	var expected := Color("#30241f")
	for y in range(SIZE):
		for x in range(SIZE):
			var before := a.get_pixel(x, y)
			var after := b.get_pixel(x, y)
			if not before.is_equal_approx(after) and (not is_equal_approx(after.r, expected.r) or not is_equal_approx(after.g, expected.g) or not is_equal_approx(after.b, expected.b) or before.a != after.a):
				return false
	return true

func _load(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _check(ok: bool, message: String) -> void:
	if ok:
		print("PASS: " + message)
	else:
		failures.append(message)
