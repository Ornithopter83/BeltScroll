extends SceneTree

const BUILDER := preload("res://tools/build_player_v9_comparison.gd")
const V8 := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const V9 := "res://assets/art/player/elven_fighter_reference_v9_fantasy_1254x1254.png"
const OUTPUT := "res://assets/art/review/player_v9_comparison.png"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const GAME_DISPLAY_HEIGHT := 576
const THREE_X_HEIGHT := GAME_DISPLAY_HEIGHT * 3
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var v8 := _load(V8)
	var v9 := _load(V9)
	_check(v8 != null and v9 != null, "v8/v9 PNG assets load")
	if v8 == null or v9 == null:
		_finish()
		return
	_check(BUILDER.png_header_valid(V8), "current v8 file has a 1254x1254, 8-bit RGBA PNG IHDR")
	_check(BUILDER.png_header_valid(V9), "v9 file has a 1254x1254, 8-bit RGBA PNG IHDR")
	var metrics8: Dictionary = BUILDER.measure(v8)
	var metrics9: Dictionary = BUILDER.measure(v9)
	_check(metrics8.png_valid, "current v8 RGBA PNG is 1254x1254 and contains an alpha silhouette")
	_check(metrics9.png_valid, "v9 RGBA PNG is 1254x1254 and contains an alpha silhouette")
	_check(metrics8.safe_margin, "current v8 alpha silhouette retains at least 90px on every canvas edge")
	_check(not metrics9.safe_margin, "v9 edge-contact is reported for human review instead of silently normalized")
	_check(metrics9.margins == Vector4i(0, 9, 6, 0), "v9 alpha silhouette edge margins are measured precisely")
	_check(int(metrics8.opaque) > 0 and int(metrics8.transparent) > 0, "v8 silhouette has both foreground and transparent pixels")
	_check(int(metrics9.opaque) > 0 and int(metrics9.transparent) > 0, "v9 silhouette has both foreground and transparent pixels")
	_check(float(metrics8.occupancy) > 0.05 and float(metrics8.occupancy) < 0.90, "v8 alpha occupancy forms a bounded figure silhouette")
	_check(float(metrics9.occupancy) > 0.05 and float(metrics9.occupancy) < 0.90, "v9 alpha occupancy forms a bounded figure silhouette")
	_check(metrics8.bounds.size.x > 0 and metrics8.bounds.size.y > 0 and metrics9.bounds.size.x > 0 and metrics9.bounds.size.y > 0,
		"both alpha silhouettes have measurable bounds for baseline alignment")
	_check(THREE_X_HEIGHT == 1728, "anchor crops render at three times the 576px in-game display height")
	var scene_text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(PLAYER_SCENE))
	_check("elven_fighter_reference_v8_clean_candidate_1254x1254.png" in scene_text and "v9_fantasy" not in scene_text,
		"player scene remains on v8; v9 stays review-only")
	var output := _load(OUTPUT)
	_check(output != null, "comparison PNG exists and loads")
	if output != null:
		_check(output.get_size() == Vector2i(1920, 2280), "comparison board includes full viewport and four paired anchor crops")
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
		print("player_v9_art_review_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_v9_art_review_smoke: " + failure)
		quit(1)
