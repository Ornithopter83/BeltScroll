extends SceneTree

const TOOL := preload("res://tools/reconstruct_player_v7_outline.gd")
const ORIGINAL := "res://assets/art/player/elven_fighter_reference_v7_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_reference_v7_safe_1254x1254.png"
const INK := "res://assets/art/player/elven_fighter_reference_v7_ink_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/player/elven_fighter_reference_v7_outline_candidate_1254x1254.png"
const REVIEW := "res://assets/art/review/player_v7_outline_comparison.png"
const SIZE := 1254
const MARGIN := 90
const EDGE := 8
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var original_path := ProjectSettings.globalize_path(ORIGINAL)
	var safe_path := ProjectSettings.globalize_path(SAFE)
	var ink_path := ProjectSettings.globalize_path(INK)
	var original_bytes := FileAccess.get_file_as_bytes(original_path)
	var safe_bytes := FileAccess.get_file_as_bytes(safe_path)
	var ink_bytes := FileAccess.get_file_as_bytes(ink_path)
	var before := _load(ink_path)
	var after := _load(ProjectSettings.globalize_path(OUTPUT))
	var review := _load(ProjectSettings.globalize_path(REVIEW))
	_check(before != null, "v7 ink 입력 PNG를 읽음")
	_check(after != null, "outline 후보 PNG를 읽음")
	_check(review != null, "전후 비교 검수판 PNG를 읽음")
	if before != null and after != null:
		_check(_valid_canvas(after), "후보 RGBA 1254×1254, 사방 90px 투명 여백")
		_check(_same_alpha(before, after), "반투명·불투명 alpha와 실루엣 위치 보존")
		_check(_interior_unchanged(before, after), "경계 8px 바깥 전경색 보존")
		_check(TOOL.pollution_count(before) > TOOL.pollution_count(after), "경계 잔상 감소 (%d → %d)" % [TOOL.pollution_count(before), TOOL.pollution_count(after)])
		_check(_changes_preserve_alpha(before, after), "복원 색 변경이 투명도에 영향을 주지 않음")
		_check(_fixture_coverage(), "연결된 빨강·노랑 오염, 반투명/불투명 경계, 피부·금색 보호")
	_check(FileAccess.get_file_as_bytes(original_path) == original_bytes, "원본 v7 바이트 보존")
	_check(FileAccess.get_file_as_bytes(safe_path) == safe_bytes, "safe 입력 바이트 보존")
	_check(FileAccess.get_file_as_bytes(ink_path) == ink_bytes, "ink 입력 바이트 보존")
	_check(_error_handling(), "null·잘못된 규격·잘못된 CLI 인수 거부")
	if failures.is_empty():
		print("player_v7_outline_smoke: all checks passed; visual approval pending.")
		quit(0)
	else:
		for failure in failures:
			push_error("player_v7_outline_smoke: " + failure)
		quit(1)

func _fixture_coverage() -> bool:
	var fixture := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBA8)
	fixture.fill(Color.TRANSPARENT)
	var skin := Color("#e6ad86")
	fixture.fill_rect(Rect2i(200, 200, 50, 50), skin)
	# Two connected warm contamination runs cross an opaque and a translucent edge.
	for x in range(200, 204):
		fixture.set_pixel(x, 214, Color("#ff1b12"))
		fixture.set_pixel(x, 215, Color("#ffd02b"))
		fixture.set_pixel(x, 216, Color("#ff1b12", 0.50))
	var processed: Dictionary = TOOL.reconstruct(fixture)
	var fixed: Image = processed["image"]
	var opaque_fixed := fixed.get_pixel(200, 214)
	var translucent_fixed := fixed.get_pixel(200, 216)
	var opaque_changed := opaque_fixed != fixture.get_pixel(200, 214)
	var translucent_changed := translucent_fixed != fixture.get_pixel(200, 216)
	var alpha_kept := is_equal_approx(translucent_fixed.a, fixture.get_pixel(200, 216).a)
	var skin_kept := fixed.get_pixel(225, 225).is_equal_approx(skin)
	# A warm gold ornament is safe when the local foreground also identifies gold.
	fixture.fill_rect(Rect2i(300, 200, 35, 40), Color("#72522a"))
	fixture.fill_rect(Rect2i(300, 204, 8, 28), Color("#d39a31"))
	var gold_fixed: Image = TOOL.reconstruct(fixture)["image"]
	var gold_kept := gold_fixed.get_pixel(301, 214).is_equal_approx(Color("#d39a31"))
	return opaque_changed and translucent_changed and alpha_kept and skin_kept and gold_kept

func _error_handling() -> bool:
	var null_result: Dictionary = TOOL.reconstruct(null)
	var invalid := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	var invalid_result: Dictionary = TOOL.reconstruct(invalid)
	var output: Array = []
	var args := PackedStringArray(["--headless", "--path", ProjectSettings.globalize_path("res://"), "--script", "res://tools/reconstruct_player_v7_outline.gd", "--", "unexpected"])
	var code := OS.execute(OS.get_executable_path(), args, output, true)
	return null_result["image"] == null and invalid_result["image"] == null and code == 2

func _valid_canvas(image: Image) -> bool:
	if image.get_size() != Vector2i(SIZE, SIZE) or image.get_format() != Image.FORMAT_RGBA8:
		return false
	var bounds := _bounds(image)
	return bounds.size.x > 0 and bounds.position.x >= MARGIN and bounds.position.y >= MARGIN \
		and SIZE - bounds.end.x >= MARGIN and SIZE - bounds.end.y >= MARGIN

func _bounds(image: Image) -> Rect2i:
	var left := SIZE; var top := SIZE; var right := -1; var bottom := -1
	for y in range(SIZE):
		for x in range(SIZE):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x); top = mini(top, y); right = maxi(right, x); bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

func _same_alpha(a: Image, b: Image) -> bool:
	for y in range(SIZE):
		for x in range(SIZE):
			if a.get_pixel(x, y).a != b.get_pixel(x, y).a:
				return false
	return true

func _interior_unchanged(a: Image, b: Image) -> bool:
	var distances := TOOL._edge_distances(a, EDGE)
	for y in range(SIZE):
		for x in range(SIZE):
			var before := a.get_pixel(x, y)
			if before.a > 0.0 and distances[y * SIZE + x] > EDGE and not before.is_equal_approx(b.get_pixel(x, y)):
				return false
	return true

func _changes_preserve_alpha(a: Image, b: Image) -> bool:
	for y in range(SIZE):
		for x in range(SIZE):
			var old := a.get_pixel(x, y)
			var fixed := b.get_pixel(x, y)
			if not old.is_equal_approx(fixed) and old.a != fixed.a:
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
