extends SceneTree

const BUILDER := preload("res://tools/build_player_v10_comparison.gd")
const V8 := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const V9 := "res://assets/art/player/elven_fighter_reference_v9_fantasy_1254x1254.png"
const V10 := "res://assets/art/player/elven_fighter_reference_v10_fantasy_1254x1254.png"
const OUTPUT := "res://assets/art/review/player_v10_comparison.png"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var images: Array[Image] = []
	for path in [V8, V9, V10]:
		var image := _load(path)
		_check(image != null, path.get_file() + " loads as PNG")
		_check(BUILDER.png_header_valid(path), path.get_file() + " has 1254×1254 8-bit RGBA PNG header")
		if image != null:
			images.append(image)
	if images.size() == 3:
		var m8: Dictionary = BUILDER.measure(images[0])
		var m9: Dictionary = BUILDER.measure(images[1])
		var m10: Dictionary = BUILDER.measure(images[2])
		_check(m8.png_valid and m9.png_valid and m10.png_valid, "all inputs contain RGBA alpha silhouettes and have the required canvas")
		_check(m8.safe_margin and m8.margins == Vector4i(110, 90, 110, 90), "current v8 actual alpha bounds meet the 90px margin gate")
		_check(not m9.safe_margin and m9.margins == Vector4i(0, 9, 6, 0), "unapproved v9 edge contact is measured and remains visible as a failure")
		_check(not m10.safe_margin and m10.margins == Vector4i(24, 19, 16, 18), "v10 actual alpha bounds report the exact sub-90px margins")
		_check(m10.bounds == Rect2i(24, 19, 1214, 1217), "v10 alpha bounds are measured over nonzero-alpha pixels")
		_check(m8.opaque > 0 and m8.transparent > 0 and m9.opaque > 0 and m9.transparent > 0 and m10.opaque > 0 and m10.transparent > 0,
			"each source has both nonzero-alpha artwork and transparent pixels")
	var scene_text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(PLAYER_SCENE))
	_check("elven_fighter_reference_v8_clean_candidate_1254x1254.png" in scene_text and "v10_fantasy" not in scene_text,
		"player scene continues to use v8; v10 stays review-only")
	var board := _load(OUTPUT)
	_check(board != null, "comparison PNG exists and loads")
	if board != null:
		_check(board.get_width() == 3000 and board.get_height() > 6000, "comparison board retains uncropped 3x gameplay scale detail rows")
	_finish()

func _load(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute)) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("player_v10_art_review_smoke: all checks passed; visual approval is still pending")
		quit(0)
	else:
		for failure in failures:
			push_error("player_v10_art_review_smoke: " + failure)
		quit(1)
