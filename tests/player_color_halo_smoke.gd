extends SceneTree

const HALO := preload("res://tools/repair_player_color_halo.gd")
const SOURCE := "res://assets/art/player/elven_fighter_reference_v4_matte_v3_1254x1254.png"
const CANDIDATE := "res://assets/art/player/elven_fighter_reference_v4_matte_v4_1254x1254.png"
const TARGET := Vector2i(1254, 1254)
const MIN_MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var candidate_path := ProjectSettings.globalize_path(CANDIDATE)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load_png(source_path)
	var candidate := _load_png(candidate_path)
	_check(source != null, "v4_matte_v3 원본 PNG를 읽음")
	_check(candidate != null, "v4_matte_v4 후보 PNG를 읽음")
	_check(_valid_canvas(candidate), "후보가 1254x1254 RGBA이며 alpha와 90px 여백을 유지함")
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "v4_matte_v3 원본 바이트가 변경되지 않음")
	if source != null and candidate != null:
		_check(_same_alpha(source, candidate), "전체 alpha 값과 실루엣 위치가 보존됨")
		var before_count := HALO.pollution_count(source)
		var after_count := HALO.pollution_count(candidate)
		_check(before_count > after_count, "가장자리 빨강/노랑 오염 수가 감소함 (%d → %d)" % [before_count, after_count])
		_check(_opaque_interior_unchanged(source, candidate), "투명 경계에서 떨어진 불투명 내부 픽셀이 보존됨")
		print("보정 픽셀: %d; 감지 오염: %d → %d" % [HALO.repair_image(source)["changed"], before_count, after_count])

	var synthetic := _synthetic_edges()
	var processed: Dictionary = HALO.repair_image(synthetic)
	var repaired: Image = processed["image"]
	_check(int(processed["changed"]) >= 2, "반투명 및 불투명 합성 빨강 외곽을 모두 복구함")
	_check(_distance(repaired.get_pixel(99, 110), Color("#1f646d")) < _distance(synthetic.get_pixel(99, 110), Color("#1f646d")), "불투명 외곽이 인접 의상색으로 이동함")
	_check(_distance(repaired.get_pixel(99, 130), Color("#1f646d")) < _distance(synthetic.get_pixel(99, 130), Color("#1f646d")), "반투명 외곽이 인접 의상색으로 이동함")
	_check(is_equal_approx(repaired.get_pixel(99, 130).a, synthetic.get_pixel(99, 130).a), "복구 시 alpha가 유지됨")
	_check(_distance(repaired.get_pixel(599, 110), Color("#1f646d")) < _distance(synthetic.get_pixel(599, 110), Color("#1f646d")), "연속 오염띠 안쪽의 불투명 외곽도 인접 의상색으로 이동함")
	_check(repaired.get_pixel(199, 110).is_equal_approx(synthetic.get_pixel(199, 110)), "지역색과 맞는 실제 금색 장식이 보존됨")
	_check(repaired.get_pixel(299, 110).is_equal_approx(synthetic.get_pixel(299, 110)), "지역색과 맞는 입술·피부 톤이 보존됨")
	_check(repaired.get_pixel(399, 110).is_equal_approx(synthetic.get_pixel(399, 110)), "지역색과 맞는 머리카락 결이 보존됨")
	_check(repaired.get_pixel(499, 110).is_equal_approx(synthetic.get_pixel(499, 110)), "지역색과 맞는 피부 하이라이트가 보존됨")

	var temp_dir := ProjectSettings.globalize_path("res://temp/player_color_halo_smoke")
	DirAccess.make_dir_recursive_absolute(temp_dir)
	var bad_path := temp_dir.path_join("malformed.png")
	var bad := FileAccess.open(bad_path, FileAccess.WRITE)
	if bad != null:
		bad.store_buffer(PackedByteArray([137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2]))
		bad.close()
	_check(HALO.repair_file(temp_dir.path_join("missing.png"), temp_dir.path_join("no-output.png")) == ERR_FILE_NOT_FOUND, "없는 입력은 file-not-found 오류를 반환함")
	_check(HALO.repair_file(bad_path, temp_dir.path_join("no-output.png")) != OK, "손상된 PNG는 오류를 반환함")
	_check(HALO.repair_file(source_path, source_path) == ERR_INVALID_PARAMETER, "원본 덮어쓰기를 거부함")
	var wrong := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	var wrong_path := temp_dir.path_join("wrong-size.png")
	wrong.save_png(wrong_path)
	_check(HALO.repair_file(wrong_path, temp_dir.path_join("no-output.png")) == ERR_INVALID_DATA, "잘못된 캔버스 크기는 invalid-data 오류를 반환함")
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "오류 입력 이후에도 원본 바이트가 동일함")
	for path in [bad_path, wrong_path, temp_dir.path_join("no-output.png")]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
	if DirAccess.dir_exists_absolute(temp_dir):
		DirAccess.remove_absolute(temp_dir)
	if failures.is_empty():
		print("player_color_halo_smoke: 모든 기계 검증 통과. 원화 승인은 별도 검수 필요.")
		quit(0)
	else:
		for failure in failures:
			push_error("player_color_halo_smoke: " + failure)
		quit(1)

func _valid_canvas(image: Image) -> bool:
	if image == null or image.get_size() != TARGET or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := HALO._alpha_bounds(image)
	var margins := [bounds.position.x, bounds.position.y, TARGET.x - bounds.end.x, TARGET.y - bounds.end.y]
	return bounds.size.x > 0 and bounds.size.y > 0 and margins.min() >= MIN_MARGIN and image.get_pixel(0, 0).a == 0.0

func _same_alpha(first: Image, second: Image) -> bool:
	for y in range(TARGET.y):
		for x in range(TARGET.x):
			if first.get_pixel(x, y).a != second.get_pixel(x, y).a:
				return false
	return true

func _opaque_interior_unchanged(first: Image, second: Image) -> bool:
	for y in range(TARGET.y):
		for x in range(TARGET.x):
			var pixel := first.get_pixel(x, y)
			if pixel.a >= 0.985 and not HALO._near_transparency(first, x, y, 6) and not pixel.is_equal_approx(second.get_pixel(x, y)):
				return false
	return true

func _synthetic_edges() -> Image:
	var image := Image.create(TARGET.x, TARGET.y, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	image.fill_rect(Rect2i(100, 100, 30, 50), Color("#1f646d"))
	image.set_pixel(99, 110, Color("#ff1010"))
	image.set_pixel(99, 130, Color(1.0, 0.04, 0.02, 0.62))
	image.fill_rect(Rect2i(200, 100, 30, 50), Color("#ca8f24"))
	image.set_pixel(199, 110, Color("#d59b30"))
	image.fill_rect(Rect2i(300, 100, 30, 50), Color("#cb735d"))
	image.set_pixel(299, 110, Color("#d47c65"))
	image.fill_rect(Rect2i(400, 100, 30, 50), Color("#bd8c4e"))
	image.set_pixel(399, 110, Color("#c99b5b"))
	image.fill_rect(Rect2i(500, 100, 30, 50), Color("#cf7859"))
	image.set_pixel(499, 110, Color("#e28e70"))
	image.fill_rect(Rect2i(596, 100, 4, 50), Color("#ff1710"))
	image.fill_rect(Rect2i(600, 100, 30, 50), Color("#1f646d"))
	return image

func _distance(a: Color, b: Color) -> float:
	return Vector3(a.r, a.g, a.b).distance_to(Vector3(b.r, b.g, b.b))

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
