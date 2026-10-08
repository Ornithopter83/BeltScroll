extends SceneTree

const TOOL := preload("res://tools/refine_player_attack1_matte.gd")
const INPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_clean_candidate_1254x1254.png"
const ORIGINAL := "res://assets/art/player/elven_fighter_attack1_reference_v1_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_attack1_reference_v1_safe_1254x1254.png"
const V8 := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack1_final_gate.png"
const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var original_bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(ORIGINAL))
	var safe_bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(SAFE))
	var input_bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(INPUT))
	var source := _load(INPUT)
	var safe := _load(SAFE)
	var clean := _load(OUTPUT)
	var reference := _load(V8)
	var review := _load(REVIEW)
	_check(source != null and safe != null and clean != null and reference != null, "원본·safe·기존 clean·v8 및 새 후보 PNG 로드")
	_check(review != null and review.get_size() == Vector2i(1500, 2650), "4 배경·3 확대 영역·192px 비교판 규격과 로드")
	if source != null and clean != null:
		_check(_valid_canvas(clean), "1254×1254 RGBA8 및 사방 90px 이상 여백")
		_check(_same_alpha(source, clean), "alpha 및 발 anchor를 포함한 전체 실루엣 위치 보존")
		var stain_before := _residual_count(source)
		var stain_after := _residual_count(clean)
		_check(stain_before > 0 and stain_after < stain_before, "반투명/불투명 윤곽 붉은 RGB 잔상 감소 (%d → %d)" % [stain_before, stain_after])
		_check(_changes_are_local_rgb_only(source, clean), "edge RGB만 제한 복원되고 alpha·내부 전경 보존")
		_check(_fixture_checks(), "독립 반투명 edge·불투명 붉은 stain 복원 및 따뜻한 전경색 보존")
	_check(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(ORIGINAL)) == original_bytes, "공격 원본 바이트 보존")
	_check(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(SAFE)) == safe_bytes, "safe 바이트 보존")
	_check(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(INPUT)) == input_bytes, "기존 clean 후보 바이트 보존")
	_check(TOOL.refine_file("res://assets/art/player/__missing_attack1_test.png", ProjectSettings.globalize_path(OUTPUT)) == ERR_FILE_NOT_FOUND, "누락 입력에 ERR_FILE_NOT_FOUND 반환")
	_check(TOOL.refine_file(ProjectSettings.globalize_path(INPUT), ProjectSettings.globalize_path(INPUT)) == ERR_INVALID_PARAMETER, "입력 덮어쓰기 시 ERR_INVALID_PARAMETER 반환")
	_check(TOOL.refine_file(ProjectSettings.globalize_path(REVIEW), ProjectSettings.globalize_path(OUTPUT)) == ERR_INVALID_DATA, "잘못된 캔버스에 ERR_INVALID_DATA 반환")
	if failures.is_empty():
		print("player_attack1_final_matte_smoke: all checks passed")
		quit(0)
	else:
		for item in failures:
			push_error("player_attack1_final_matte_smoke: " + item)
		quit(1)

func _residual_count(image: Image) -> int:
	var count := 0
	var bounds := TOOL._alpha_bounds(image)
	for y in range(maxi(1, bounds.position.y - 1), mini(image.get_height() - 1, bounds.end.y + 1)):
		for x in range(maxi(1, bounds.position.x - 1), mini(image.get_width() - 1, bounds.end.x + 1)):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0 or not TOOL._near_alpha_edge(image, x, y):
				continue
			var evidence := TOOL._local_foreground_medoid(image, x, y, 6)
			if not evidence.valid:
				continue
			var reference: Color = evidence.color
			var distance := Vector3(pixel.r - reference.r, pixel.g - reference.g, pixel.b - reference.b).length()
			if pixel.a < 0.995 and TOOL._is_partial_red_spill(pixel, reference, distance):
				count += 1
			elif pixel.a >= 0.995 and TOOL._is_opaque_red_spill(pixel, reference, distance):
				count += 1
	return count

func _changes_are_local_rgb_only(before: Image, after: Image) -> bool:
	var changed := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if a.a != b.a:
				return false
			if not a.is_equal_approx(b):
				changed += 1
				if not TOOL._near_alpha_edge(before, x, y) or changed > 40000:
					return false
	return changed > 0

func _fixture_checks() -> bool:
	var fixture := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	var skin := Color("#e9b28e")
	fixture.fill_rect(Rect2i(100, 100, 120, 100), skin)
	fixture.set_pixel(100, 125, Color("#ff1712")) # opaque spill at exposed contour
	fixture.set_pixel(99, 160, Color(1.0, 0.05, 0.02, 0.42)) # contaminated soft edge
	fixture.fill_rect(Rect2i(250, 100, 35, 35), Color("#704a30"))
	fixture.fill_rect(Rect2i(251, 101, 5, 30), Color("#d39a31"))
	var result := TOOL.refine_image(fixture)
	var opaque_fixed := result.get_pixel(100, 125).r < 0.95
	var translucent_fixed := result.get_pixel(99, 160).r < 0.95 and is_equal_approx(result.get_pixel(99, 160).a, fixture.get_pixel(99, 160).a)
	var gold_kept := result.get_pixel(252, 120).is_equal_approx(Color("#d39a31"))
	var inner_kept := result.get_pixel(115, 115).is_equal_approx(skin)
	return opaque_fixed and translucent_fixed and gold_kept and inner_kept

func _same_alpha(a: Image, b: Image) -> bool:
	if a.get_size() != b.get_size():
		return false
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			if a.get_pixel(x, y).a != b.get_pixel(x, y).a:
				return false
	return true

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := TOOL._alpha_bounds(image)
	return bounds.size.x > 0 and bounds.position.x >= MIN_MARGIN and bounds.position.y >= MIN_MARGIN \
		and SIZE.x - bounds.end.x >= MIN_MARGIN and SIZE.y - bounds.end.y >= MIN_MARGIN

func _load(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute)) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
