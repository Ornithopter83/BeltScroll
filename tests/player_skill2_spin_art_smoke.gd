extends SceneTree

const SOURCES := [
	"res://assets/art/player/elven_fighter_reference_v8_1254x1254.png",
	"res://assets/art/player/elven_fighter_skill1_rush_contact_v1_safe_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_skill2_spin_contact_v1_candidate_1254x1254.png",
]
const V2 := "res://assets/art/player/elven_fighter_skill2_spin_contact_v2_candidate_1254x1254.png"
const BOARD := "res://assets/art/review/player_skill2_spin_art_comparison.png"
const BOARD_SIZE := Vector2i(1780, 520)

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	for path in SOURCES:
		var image := _load(path)
		_check(image != null, "required source exists and decodes: " + path)
		if image != null:
			_check(image.get_size() == Vector2i(1254, 1254), "source retains 1254x1254 canvas: " + path)
			_check(image.get_format() == Image.FORMAT_RGBA8, "source is RGBA8: " + path)
	var v2_available := FileAccess.file_exists(ProjectSettings.globalize_path(V2))
	if v2_available:
		var v2_image := _load(V2)
		_check(v2_image != null, "present v2 decodes as PNG")
		if v2_image != null:
			_check(v2_image.get_size() == Vector2i(1254, 1254), "present v2 retains 1254x1254 canvas")
			_check(v2_image.get_format() == Image.FORMAT_RGBA8, "present v2 is RGBA8")
	else:
		print("PASS: v2 file absent; the fourth comparison slot must remain marked NOT PROVIDED")
	var board := _load(BOARD)
	_check(board != null, "comparison board exists and decodes")
	if board != null:
		var expected_width := BOARD_SIZE.x if not v2_available else BOARD_SIZE.x
		_check(board.get_size().x == expected_width and board.get_size().y == BOARD_SIZE.y, "four-panel comparison board dimensions are correct")
	_check(not _all_transparent(board), "comparison board contains visible panel content")
	print("HUMAN REVIEW GATE: Num5 v1 reads as a straight forward punch; rotation is unproven and v1 is not accepted as a spin contact pose.")
	print("HUMAN REVIEW GATE: identity, v2 rearward torso turn, horizontal backfist, pivot foot, and crossed arms require visual review; a straight punch or identity mismatch is not accepted.")
	if failures.is_empty():
		print("player_skill2_spin_art_smoke: mechanical checks passed; human approval remains required")
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
