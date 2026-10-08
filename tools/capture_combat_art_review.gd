extends SceneTree
"""Captures a real Window Viewport frame of the standalone combat art review."""

const REVIEW_SCENE := "res://scenes/review/combat_art_stage_review.tscn"
const DEFAULT_OUTPUT := "res://assets/art/review/combat_art_v5_clean_capture.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Window Viewport 렌더러가 필요합니다. headless에서는 캡처할 수 없습니다.")
		return
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() > 2:
		_fail("사용법: capture_combat_art_review [output.png] [--overlap | --legacy]")
		return
	var output_path := DEFAULT_OUTPUT
	var overlap_mode := false
	var legacy_mode := false
	var output_specified := false
	for argument in arguments:
		if argument == "--overlap":
			overlap_mode = true
		elif argument == "--legacy":
			legacy_mode = true
		elif argument.begins_with("-"):
			_fail("알 수 없는 옵션입니다: " + argument)
			return
		elif not output_specified:
			output_path = argument
			output_specified = true
		else:
			_fail("출력 경로는 하나만 지정할 수 있습니다.")
			return
	if overlap_mode and legacy_mode:
		_fail("--overlap과 --legacy 옵션은 함께 사용할 수 없습니다.")
		return
	root.size = CAPTURE_SIZE
	var packed := load(REVIEW_SCENE) as PackedScene
	if packed == null:
		_fail("독립 검수 장면을 불러오지 못했습니다: " + REVIEW_SCENE)
		return
	var review := packed.instantiate() as Node2D
	if review == null:
		_fail("검수 장면을 Node2D로 인스턴스화하지 못했습니다.")
		return
	review.set("candidate_review_mode", not legacy_mode)
	if legacy_mode:
		review.set("overlap_review_mode", false)
	root.add_child(review)
	if overlap_mode:
		review.set("candidate_overlap_mode", true)
		review.call("_configure_candidate_positions")
	for _frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	var viewport_image := root.get_texture().get_image()
	if viewport_image == null or viewport_image.is_empty():
		_fail("Window Viewport가 빈 이미지를 반환했습니다.")
		return
	if viewport_image.get_size() != CAPTURE_SIZE:
		_fail("Window Viewport 크기 %s가 목표 %s와 다릅니다." % [viewport_image.get_size(), CAPTURE_SIZE])
		return
	if not _has_rendered_content(viewport_image):
		_fail("Window Viewport가 비어 있거나 장면이 렌더링되지 않았습니다.")
		return
	var absolute_output := ProjectSettings.globalize_path(output_path)
	var save_error := viewport_image.save_png(absolute_output)
	if save_error != OK:
		_fail("실제 Window Viewport PNG 저장 실패: %s (오류 %d)" % [absolute_output, save_error])
		return
	var saved_image := Image.new()
	var load_error := saved_image.load(absolute_output)
	if load_error != OK or saved_image.get_size() != CAPTURE_SIZE:
		_fail("저장한 캡처를 다시 읽지 못했거나 크기가 잘못되었습니다: %s" % absolute_output)
		return
	var mode_name := "v4/safe baseline" if legacy_mode else ("YSort overlap" if overlap_mode else "default candidate layout")
	print("combat-art-review-capture: saved real %dx%d Window Viewport PNG (%s) to %s" % [CAPTURE_SIZE.x, CAPTURE_SIZE.y, mode_name, absolute_output])
	quit(0)

func _has_rendered_content(image: Image) -> bool:
	var first_color := image.get_pixel(0, 0)
	var varied_samples := 0
	for y in range(40, CAPTURE_SIZE.y, 80):
		for x in range(40, CAPTURE_SIZE.x, 80):
			if _color_distance_squared(image.get_pixel(x, y), first_color) > 0.0025:
				varied_samples += 1
	return varied_samples >= 12

func _color_distance_squared(left: Color, right: Color) -> float:
	var difference := left - right
	return difference.r * difference.r + difference.g * difference.g + difference.b * difference.b

func _fail(message: String) -> void:
	push_error("combat-art-review-capture: " + message)
	quit(1)
