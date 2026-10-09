extends SceneTree
"""Checks the v4 safe integrity, retained v1-v3 finding and comparison artifact."""

const V1_SAFE := "res://assets/art/player/elven_fighter_run_stride_v1_safe_candidate_1254x1254.png"
const V2_SAFE := "res://assets/art/player/elven_fighter_run_stride_v2_safe_candidate_1254x1254.png"
const V3_CANDIDATE := "res://assets/art/player/elven_fighter_run_stride_v3_left_lead_candidate_1254x1254.png"
const V4_SOURCE := "res://assets/art/player/elven_fighter_run_stride_v4_opposite_contact_candidate_1254x1254.png"
const V4_SAFE := "res://assets/art/player/elven_fighter_run_stride_v4_safe_candidate_1254x1254.png"
const PREPARE := "res://tools/prepare_player_run_v4_safe.gd"
const REVIEW := "res://assets/art/review/player_run_v4_opposition_comparison.png"
const GATE := "res://docs/review/player_run_v4_opposition_gate.md"
const V4_SOURCE_SHA256 := "d3248a8c24cdf11379f7074bcaa6cda4adbf2ccb30fbbe92f92a066765a9bb40"

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(_valid_png(V1_SAFE), "v1 safe exists as a valid 1254x1254 RGBA8 PNG")
	_check(_valid_png(V2_SAFE), "v2 safe exists as a valid 1254x1254 RGBA8 PNG")
	_check(_valid_png(V3_CANDIDATE), "v3 candidate exists as a valid 1254x1254 RGBA8 PNG")
	_check(_valid_png(V4_SOURCE), "v4 opposite-contact source is present as a valid 1254x1254 RGBA8 PNG")
	_check(_valid_png(V4_SAFE), "separate v4 safe exists as a valid 1254x1254 RGBA8 PNG")
	if FileAccess.file_exists(V4_SOURCE):
		_check(_sha256(_bytes(V4_SOURCE)) == V4_SOURCE_SHA256, "v4 source bytes match the recorded original SHA-256")
	_check(FileAccess.file_exists(PREPARE), "conditional safe-preparation and comparison tool exists")
	_check(FileAccess.file_exists(REVIEW), "existing-candidate comparison image exists")
	_check(FileAccess.file_exists(GATE), "v4 opposition gate record exists")
	if FileAccess.file_exists(REVIEW):
		var review := Image.new()
		_check(review.load(ProjectSettings.globalize_path(REVIEW)) == OK and review.get_size() == Vector2i(1680, 1100), "comparison image is a readable 1680x1100 PNG")
	var safe := _load(V4_SAFE)
	if safe != null:
		var bounds := _alpha_bounds(safe)
		var margins := Vector4i(bounds.position.x, bounds.position.y, 1254 - bounds.end.x, 1254 - bounds.end.y)
		_check(margins.x >= 90 and margins.y >= 90 and margins.z >= 90 and margins.w >= 90, "v4 safe alpha margins are at least 90px on all sides: %s" % str(margins))
		_check(_isolated_count(safe) == 0, "v4 safe has no isolated alpha pixels")
		_check(_transparent_rgb_is_zero(safe), "v4 fully transparent pixels have zero RGB")
	if FileAccess.file_exists(PREPARE):
		var source := FileAccess.get_file_as_string(PREPARE)
		_check(source.contains("_hash(source_bytes)") and source.contains("_read_bytes(V4_SOURCE) != source_bytes"), "conditional v4 safe path checks source-byte preservation")
		_check(source.contains("MIN_MARGIN := 90") and source.contains("_isolated_count(safe)"), "conditional safe path checks 90px alpha margins and isolated pixels")
		_check(source.contains("acceptance=not_granted") and source.contains("integration=none"), "tool does not approve or register a candidate")
	if FileAccess.file_exists(GATE):
		var gate := FileAccess.get_file_as_string(GATE)
		_check(gate.contains("v1~v3") and gate.contains("동일 보폭"), "the existing v1-v3 same-stride judgment is retained")
		_check(gate.contains("미수용") and gate.contains("승인") and gate.contains("본편"), "the gate records rejection status and prohibits approval and integration")
	if failures.is_empty():
		print("player_run_v4_safe_smoke: v4 safe integrity and preserved v1-v3 finding verified; no approval or integration")
		quit(0)
		return
	for failure in failures:
		push_error("player_run_v4_safe_smoke: " + failure)
	quit(1)

func _valid_png(path: String) -> bool:
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else PackedByteArray()
	if bytes.is_empty():
		return false
	var image := Image.new()
	return image.load_png_from_buffer(bytes) == OK and image.get_size() == Vector2i(1254, 1254) and image.get_format() == Image.FORMAT_RGBA8

func _bytes(path: String) -> PackedByteArray:
	return FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else PackedByteArray()

func _sha256(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK or context.update(bytes) != OK:
		return "hash_error"
	return context.finish().hex_encode()

func _load(path: String) -> Image:
	var bytes := FileAccess.get_file_as_bytes(ProjectSettings.globalize_path(path)) if FileAccess.file_exists(path) else PackedByteArray()
	if bytes.is_empty():
		return null
	var image := Image.new()
	return image if image.load_png_from_buffer(bytes) == OK else null

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
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= left else Rect2i()

func _isolated_count(image: Image) -> int:
	var count := 0
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if image.get_pixel(x, y).a <= 0.0:
				continue
			var neighbor := false
			for oy in range(-1, 2):
				for ox in range(-1, 2):
					var nx := x + ox
					var ny := y + oy
					if (ox != 0 or oy != 0) and nx >= 0 and ny >= 0 and nx < image.get_width() and ny < image.get_height() and image.get_pixel(nx, ny).a > 0.0:
						neighbor = true
			if not neighbor:
				count += 1
	return count

func _transparent_rgb_is_zero(image: Image) -> bool:
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var pixel := image.get_pixel(x, y)
			if pixel.a <= 0.0 and (pixel.r != 0.0 or pixel.g != 0.0 or pixel.b != 0.0):
				return false
	return true

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		failures.append(message)
