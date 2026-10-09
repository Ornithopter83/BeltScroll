extends SceneTree

const TOOL := preload("res://tools/repair_player_attack1_contour.gd")
const INPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_edge_v2_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_contour_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack1_contour_gate.png"
const PROTECTED := [
	"res://assets/art/player/elven_fighter_attack1_reference_v1_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png",
	INPUT
]
const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var saved: Array[PackedByteArray] = []
	for path in PROTECTED:
		saved.append(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)))
	var before := _load(INPUT)
	var after := _load(OUTPUT)
	var review := _load(REVIEW)
	_check(before != null and after != null, "기존 edge_v2와 contour 후보 PNG 로드")
	_check(review != null and review.get_size() == Vector2i(1500, 2680), "4 배경·3 확대 영역·192px 비교판 생성")
	if before != null and after != null:
		_check(after.get_size() == SIZE and after.get_format() == Image.FORMAT_RGBA8, "1254×1254 RGBA8 형식")
		_check(TOOL.has_clear_margins(after), "사방 투명 여백 90px 이상")
		_check(TOOL.count_contour_red_outliers(before) > 0 and TOOL.count_contour_red_outliers(after) < TOOL.count_contour_red_outliers(before), "alpha 1~4px 내부 띠의 붉은 잔상 감소")
		_check(_morphology_is_protected(before, after), "신체 실루엣 및 발 anchor 보호, alpha 변화는 소량 외곽에 제한")
		_check(_rgb_changes_are_edge_local(before, after), "RGB 복원은 alpha 경계 4px 안쪽에 제한")
		_check(_fixture_checks(), "바깥 alpha 제거·내부 불투명 복원·따뜻한 색/금색 보호")
	for i in range(PROTECTED.size()):
		_check(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(PROTECTED[i])) == saved[i], "입력/기존 후보 바이트 보존: " + PROTECTED[i].get_file())
	_check(TOOL.repair_file("res://assets/art/player/__missing_attack1_contour.png", ProjectSettings.globalize_path(OUTPUT)) == ERR_FILE_NOT_FOUND, "누락 입력은 ERR_FILE_NOT_FOUND")
	_check(TOOL.repair_file(ProjectSettings.globalize_path(INPUT), ProjectSettings.globalize_path(INPUT)) == ERR_INVALID_PARAMETER, "입력 덮어쓰기는 ERR_INVALID_PARAMETER")
	_check(TOOL.repair_file(ProjectSettings.globalize_path(REVIEW), ProjectSettings.globalize_path(OUTPUT)) == ERR_INVALID_DATA, "1254 규격이 아닌 PNG는 ERR_INVALID_DATA")
	_check(TOOL.repair_file(ProjectSettings.globalize_path("res://project.godot"), ProjectSettings.globalize_path(OUTPUT)) == ERR_FILE_UNRECOGNIZED, "PNG가 아닌 입력은 ERR_FILE_UNRECOGNIZED")
	if failures.is_empty():
		print("player_attack1_contour_smoke: all checks passed")
		quit(0)
	else:
		for item in failures:
			push_error("player_attack1_contour_smoke: " + item)
		quit(1)

func _morphology_is_protected(before: Image, after: Image) -> bool:
	var before_bounds := TOOL._alpha_bounds(before)
	var after_bounds := TOOL._alpha_bounds(after)
	if before_bounds.end.y != after_bounds.end.y or before_bounds.position != after_bounds.position:
		return false
	var removed := 0
	var added := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y).a
			var b := after.get_pixel(x, y).a
			if a == b: continue
			if b > a: added += 1
			else:
				removed += 1
				if a >= 0.20 or b != 0.0 or not _near_edge(before, x, y, 1):
					return false
	return added == 0 and removed <= 101

func _rgb_changes_are_edge_local(before: Image, after: Image) -> bool:
	var changes := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if a.is_equal_approx(b): continue
			changes += 1
			if a.a == b.a and not _near_edge(before, x, y, 4): return false
	return changes > 0 and changes <= 20000

func _near_edge(image: Image, x: int, y: int, radius: int) -> bool:
	for ny in range(maxi(0, y - radius), mini(SIZE.y, y + radius + 1)):
		for nx in range(maxi(0, x - radius), mini(SIZE.x, x + radius + 1)):
			if image.get_pixel(nx, ny).a < 0.02: return true
	return false

func _fixture_checks() -> bool:
	var fixture := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	fixture.fill_rect(Rect2i(100, 100, 40, 40), Color("#254c4b"))
	fixture.set_pixel(100, 120, Color("#ff1712"))
	fixture.set_pixel(99, 120, Color(1.0, 0.04, 0.02, 0.12))
	fixture.fill_rect(Rect2i(200, 100, 18, 18), Color("#704a30"))
	fixture.fill_rect(Rect2i(203, 101, 3, 9), Color("#d39a31"))
	fixture.fill_rect(Rect2i(300, 100, 18, 18), Color("#8a5438"))
	fixture.fill_rect(Rect2i(300, 104, 4, 1), Color("#b96d4a"))
	var result: Dictionary = TOOL.repair_image(fixture)
	var output: Image = result.image
	var opaque_restored := output.get_pixel(100, 120).g > fixture.get_pixel(100, 120).g
	var external_removed := output.get_pixel(99, 120).a == 0.0
	var gold_preserved := output.get_pixel(204, 105).is_equal_approx(fixture.get_pixel(204, 105))
	var warm_skin_preserved := output.get_pixel(300, 104).is_equal_approx(fixture.get_pixel(300, 104))
	var interior_unchanged := output.get_pixel(115, 115).is_equal_approx(fixture.get_pixel(115, 115))
	return opaque_restored and external_removed and gold_preserved and warm_skin_preserved and interior_unchanged

func _load(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute): return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute)) != OK or image.is_empty(): return null
	if image.get_format() != Image.FORMAT_RGBA8: image.convert(Image.FORMAT_RGBA8)
	return image

func _check(condition: bool, message: String) -> void:
	if condition: print("PASS: " + message)
	else: failures.append(message)
