extends SceneTree

const V8 := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const NUM4_SAFE := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png"
const NUM5_V1 := "res://assets/art/player/elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png"
const NUM5_V2_SOURCE := "res://assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png"
const NUM5_V2_SAFE := "res://assets/art/player/elven_fighter_skill2_spin_backfist_v2_safe_candidate_1254x1254.png"
const BOARD := "res://assets/art/review/player_skill2_spin_art_comparison.png"
const SIZE := Vector2i(1254, 1254)
const BOARD_SIZE := Vector2i(1780, 520)
const SAFE_INSET := 90

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in [V8, NUM4_SAFE, NUM5_V1, NUM5_V2_SOURCE, NUM5_V2_SAFE]:
		var image := _load(path)
		_check(image != null, "required source exists and decodes: " + path)
		if image == null:
			continue
		_check(image.get_size() == SIZE, "source retains 1254x1254 canvas: " + path)
		_check(image.get_format() == Image.FORMAT_RGBA8, "source is RGBA8: " + path)
		var bounds := _alpha_bounds(image)
		_check(bounds.size.x > 0 and bounds.size.y > 0, "source contains alpha artwork: " + path)
		if path == NUM5_V2_SAFE:
			var margins := _margins(bounds)
			_check(margins.x >= SAFE_INSET and margins.y >= SAFE_INSET and margins.z >= SAFE_INSET and margins.w >= SAFE_INSET, "v2 safe derivative has at least 90px alpha margin on all sides")
			_check(_transparent_border(image), "v2 safe derivative has a transparent outer border")
			_check(_isolated_count(image) == 0, "v2 safe derivative has no isolated alpha pixels")
	var board := _load(BOARD)
	_check(board != null, "comparison board exists and decodes")
	if board != null:
		_check(board.get_size() == BOARD_SIZE, "four-panel mirrored comparison board dimensions are correct")
		_check(not _all_transparent(board), "comparison board contains visible panel content")
	print("HUMAN REVIEW GATE: v2 is mechanically prepared, but rearward rotation, horizontal backfist, pivot foot, arm crossing, and identity need visual approval.")
	print("HUMAN REVIEW GATE: the displayed pose can read as a straight punch; if that reading remains, v2 is not accepted as a spin contact pose.")
	if failures.is_empty():
		print("player_skill2_spin_art_smoke: mechanical checks passed; no production registration without human approval")
		quit(0)
	else:
		for failure in failures:
			push_error("player_skill2_spin_art_smoke: " + failure)
		quit(1)

func _load(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute)) != OK or image.is_empty():
		return null
	return image

func _alpha_bounds(image: Image) -> Rect2i:
	var left := image.get_width()
	var top := image.get_height()
	var right := -1
	var bottom := -1
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

func _margins(bounds: Rect2i) -> Vector4i:
	return Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)

func _isolated_count(image: Image) -> int:
	var width := image.get_width()
	var height := image.get_height()
	var mask := PackedByteArray()
	mask.resize(width * height)
	for y in range(height):
		for x in range(width):
			mask[y * width + x] = 1 if image.get_pixel(x, y).a > 0.0 else 0
	var count := 0
	for y in range(height):
		for x in range(width):
			var index := y * width + x
			if mask[index] == 0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < width and ny < height and mask[ny * width + nx] != 0:
						neighbor = true
				if neighbor:
					break
			if not neighbor:
				count += 1
	return count

func _transparent_border(image: Image) -> bool:
	for x in range(image.get_width()):
		if image.get_pixel(x, 0).a != 0.0 or image.get_pixel(x, image.get_height() - 1).a != 0.0:
			return false
	for y in range(image.get_height()):
		if image.get_pixel(0, y).a != 0.0 or image.get_pixel(image.get_width() - 1, y).a != 0.0:
			return false
	return true

func _all_transparent(image: Image) -> bool:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a > 0.0:
				return false
	return true

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
