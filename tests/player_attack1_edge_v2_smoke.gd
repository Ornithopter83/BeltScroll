extends SceneTree

const TOOL := preload("res://tools/refine_player_attack1_edge_v2.gd")
const INPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_final_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_attack1_reference_v1_edge_v2_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_attack1_edge_v2_gate.png"
const ORIGINALS := [
	"res://assets/art/player/elven_fighter_attack1_reference_v1_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_safe_1254x1254.png",
	"res://assets/art/player/elven_fighter_attack1_reference_v1_clean_candidate_1254x1254.png",
	INPUT
]
const SIZE := Vector2i(1254, 1254)
const MIN_MARGIN := 90
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var protected_bytes: Array[PackedByteArray] = []
	for path in ORIGINALS:
		protected_bytes.append(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)))
	var before := _load(INPUT)
	var after := _load(OUTPUT)
	var review := _load(REVIEW)
	_check(before != null and after != null, "기존 final과 별도 v2 후보 PNG 로드")
	_check(review != null and review.get_size() == Vector2i(1500, 2650), "흰색·검정·체커보드·숲 및 확대·192px 비교판 규격")
	if before != null and after != null:
		_check(_valid_canvas(after), "1254×1254 RGBA8 및 사방 90px 이상 투명 여백")
		_check(_alpha_damage_is_external_only(before, after), "alpha 변경은 낮은 alpha의 외부 오염에 한정")
		_check(_same_foot_anchor(before, after), "불투명 발 anchor와 전체 alpha 실루엣 손상 제한")
		var red_before := TOOL.count_red_edge_outliers(before)
		var red_after := TOOL.count_red_edge_outliers(after)
		_check(red_before >= 1 and red_after < red_before, "붉은 경계 잔상 감소 (%d → %d)" % [red_before, red_after])
		_check(_changed_pixels_are_edge_local(before, after), "RGB 재합성은 alpha 경계에 국한되고 내부 색상 보존")
		_check(_fixture_checks(), "피부·머리카락·금색 보존, 오염 경계 재합성 및 외부 alpha 처리")
	for i in range(ORIGINALS.size()):
		_check(FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(ORIGINALS[i])) == protected_bytes[i], "기존 원본·후보 바이트 보존: " + ORIGINALS[i].get_file())
	_check(TOOL.refine_file("res://assets/art/player/__missing_attack1_edge_v2.png", ProjectSettings.globalize_path(OUTPUT)) == ERR_FILE_NOT_FOUND, "누락 입력은 ERR_FILE_NOT_FOUND")
	_check(TOOL.refine_file(ProjectSettings.globalize_path(INPUT), ProjectSettings.globalize_path(INPUT)) == ERR_INVALID_PARAMETER, "입력 덮어쓰기는 ERR_INVALID_PARAMETER")
	_check(TOOL.refine_file(ProjectSettings.globalize_path(REVIEW), ProjectSettings.globalize_path(OUTPUT)) == ERR_INVALID_DATA, "잘못된 캔버스 크기는 ERR_INVALID_DATA")
	_check(TOOL.refine_file(ProjectSettings.globalize_path("res://project.godot"), ProjectSettings.globalize_path(OUTPUT)) == ERR_FILE_UNRECOGNIZED, "PNG가 아닌 입력은 ERR_FILE_UNRECOGNIZED")
	if failures.is_empty():
		print("player_attack1_edge_v2_smoke: all checks passed")
		quit(0)
	else:
		for item in failures:
			push_error("player_attack1_edge_v2_smoke: " + item)
		quit(1)

func _alpha_damage_is_external_only(before: Image, after: Image) -> bool:
	var cleared := 0
	var gained := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if a.a == b.a:
				continue
			if b.a > a.a:
				gained += 1
				continue
			cleared += 1
			if a.a >= 0.24 or b.a != 0.0 or not TOOL._near_alpha_edge(before, x, y, 3):
				return false
			var evidence := TOOL._foreground_medoid(before, x, y, 6)
			if not evidence.valid or not TOOL._is_red_outlier(a, evidence.color, TOOL._rgb_distance(a, evidence.color), int(evidence.support)):
				return false
			if not TOOL._external_low_alpha_island(before, x, y, evidence.color):
				return false
	return gained == 0 and cleared <= 101

func _same_foot_anchor(before: Image, after: Image) -> bool:
	var before_bounds := TOOL._alpha_bounds(before)
	var after_bounds := TOOL._alpha_bounds(after)
	if before_bounds.end.y != after_bounds.end.y:
		return false
	var losses := 0
	var gains := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y).a
			var b := after.get_pixel(x, y).a
			if a >= 0.5 and b < 0.5: losses += 1
			elif a < 0.5 and b >= 0.5: gains += 1
	return losses <= 101 and gains == 0

func _changed_pixels_are_edge_local(before: Image, after: Image) -> bool:
	var changed := 0
	for y in range(SIZE.y):
		for x in range(SIZE.x):
			var a := before.get_pixel(x, y)
			var b := after.get_pixel(x, y)
			if not a.is_equal_approx(b):
				changed += 1
				if not TOOL._near_alpha_edge(before, x, y, 3):
					return false
	return changed > 0 and changed <= 40000

func _fixture_checks() -> bool:
	var fixture := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	fixture.fill_rect(Rect2i(100, 100, 40, 40), Color("#254c4b"))
	fixture.set_pixel(100, 120, Color("#ff1712"))
	fixture.set_pixel(99, 100, Color(1.0, 0.04, 0.02, 0.16))
	fixture.fill_rect(Rect2i(200, 100, 12, 12), Color("#704a30"))
	fixture.fill_rect(Rect2i(203, 101, 3, 9), Color("#d39a31"))
	fixture.fill_rect(Rect2i(300, 100, 10, 10), Color("#8a5438"))
	fixture.set_pixel(300, 104, Color("#b96d4a"))
	fixture.fill_rect(Rect2i(350, 100, 16, 16), Color("#704a30"))
	fixture.set_pixel(349, 105, Color(0.54, 0.33, 0.22, 0.45))
	var result: Dictionary = TOOL.refine_image(fixture)
	var refined: Image = result.image
	var opaque_repaired := refined.get_pixel(100, 120).g > fixture.get_pixel(100, 120).g
	var alpha_removed := refined.get_pixel(99, 100).a == 0.0
	var gold_preserved := refined.get_pixel(204, 105).is_equal_approx(fixture.get_pixel(204, 105))
	var skin_preserved := refined.get_pixel(300, 104).is_equal_approx(fixture.get_pixel(300, 104))
	var hair_preserved := refined.get_pixel(349, 105).is_equal_approx(fixture.get_pixel(349, 105))
	var alpha_otherwise_preserved := refined.get_pixel(100, 119).a == fixture.get_pixel(100, 119).a
	return opaque_repaired and alpha_removed and gold_preserved and skin_preserved and hair_preserved and alpha_otherwise_preserved

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != SIZE or image.get_format() != Image.FORMAT_RGBA8:
		return false
	return TOOL.has_clear_margins(image)

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
