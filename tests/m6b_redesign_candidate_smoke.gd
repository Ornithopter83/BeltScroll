extends SceneTree

const BUILDER := preload("res://tools/prepare_m6b_redesign_candidate.gd")
const SOURCE := "res://assets/art/player/elven_fighter_dark_fantasy_redesign_v1_candidate_1254x1254.png"
const SAFE := "res://assets/art/player/elven_fighter_dark_fantasy_redesign_v1_safe_candidate_1254x1254.png"
const V8 := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const BOARD := "res://assets/art/review/m6b_redesign_candidate_comparison.png"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const SIZE := Vector2i(1254, 1254)
const EXPECTED_BOARD := Vector2i(1920, 1080)
const SAFE_MARGIN := 90

var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var source_path := ProjectSettings.globalize_path(SOURCE)
	var source_bytes := FileAccess.get_file_as_bytes(source_path)
	var source := _load(SOURCE)
	var candidate := _load(SAFE)
	var v8 := _load(V8)
	_check(source != null and candidate != null and v8 != null, "original, normalized candidate, and active v8 images load")
	if source == null or candidate == null or v8 == null:
		_finish()
		return
	_check(FileAccess.get_file_as_bytes(source_path) == source_bytes, "original redesign source remains byte-for-byte unchanged")
	_check(candidate.get_size() == SIZE and candidate.get_format() == Image.FORMAT_RGBA8, "candidate is 1254 square RGBA8")
	var bounds := BUILDER.alpha_bounds(candidate)
	var margins := Vector4i(bounds.position.x, bounds.position.y, SIZE.x - bounds.end.x, SIZE.y - bounds.end.y)
	_check(bounds.size.x > 0 and bounds.size.y > 0 and margins.x >= SAFE_MARGIN and margins.y >= SAFE_MARGIN and margins.z >= SAFE_MARGIN and margins.w == SAFE_MARGIN,
		"silhouette has at least 90px safe edge margin and exact 90px foot-anchor margin")
	_check(candidate.get_pixel(0, 0).a == 0.0 and candidate.get_pixel(SIZE.x - 1, SIZE.y - 1).a == 0.0, "canvas corners remain fully transparent")
	var normalized_again := BUILDER.normalize_image(source)
	_check(normalized_again.get_data() == candidate.get_data(), "normalization is deterministic and derived from the untouched source")
	var scene_text := FileAccess.get_file_as_string(ProjectSettings.globalize_path(PLAYER_SCENE))
	_check("elven_fighter_reference_v8_clean_candidate_1254x1254.png" in scene_text and "dark_fantasy_redesign" not in scene_text,
		"PlayerArt remains on v8; redesign remains review-only")
	_check(not scene_text.contains("dark_fantasy_redesign_v1_safe_candidate"), "normalized candidate is not wired into the player scene")
	var board := _load(BOARD)
	_check(board != null and board.get_size() == EXPECTED_BOARD, "review Window capture exists at 1920×1080")
	if board != null:
		_check(board.get_pixel(0, 0).a == 1.0 and board.get_pixel(1919, 1079).a == 1.0, "comparison capture has a complete opaque Window background")
	var utility_text := FileAccess.get_file_as_string(ProjectSettings.globalize_path("res://tools/prepare_m6b_redesign_candidate.gd"))
	_check("GAME_SPRITE_SCALE := 0.4469274" in utility_text and "CAMERA_ZOOM := 1.2" in utility_text, "comparison uses production Sprite2D scale and player camera zoom")
	_finish()

func _load(path: String) -> Image:
	var absolute := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute):
		return null
	var image := Image.new()
	if image.load(absolute) != OK or image.is_empty():
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6b_redesign_candidate_smoke: all checks passed")
		quit(0)
	else:
		for failure in _failures:
			push_error("m6b_redesign_candidate_smoke: " + failure)
		quit(1)
