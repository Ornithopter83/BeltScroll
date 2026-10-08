extends SceneTree

const REVIEWER := preload("res://tools/reconstruct_player_v7_outline.gd")
const BEFORE := "res://assets/art/player/elven_fighter_reference_v7_outline_candidate_1254x1254.png"
const AFTER := "res://assets/art/player/elven_fighter_reference_v8_1254x1254.png"
const FOREST := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const OUTPUT := "res://assets/art/review/player_v7_outline_v8_comparison.png"

func _initialize() -> void:
	call_deferred("_build")

func _build() -> void:
	var before := _load_image(BEFORE)
	var after := _load_image(AFTER)
	var forest := _load_image(FOREST)
	var error := REVIEWER.build_review(before, after, forest, ProjectSettings.globalize_path(OUTPUT))
	if error != OK:
		push_error("player v7/v8 comparison generation failed: %s" % error_string(error))
		quit(1)
		return
	print("player v7/v8 comparison generated: white, dark, checkerboard, Forest Ruins, enlarged face and ponytail crops, and 192px samples.")
	quit(0)

func _load_image(path: String) -> Image:
	var absolute_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(absolute_path):
		return null
	var image := Image.new()
	if image.load_png_from_buffer(FileAccess.get_file_as_bytes(absolute_path)) != OK:
		return null
	if image.get_format() != Image.FORMAT_RGBA8:
		image.convert(Image.FORMAT_RGBA8)
	return image
