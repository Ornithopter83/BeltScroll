extends SceneTree
"""Captures a real Window Viewport frame of the standalone combat art review."""

const REVIEW_SCENE := "res://scenes/review/combat_art_stage_review.tscn"
const DEFAULT_OUTPUT := "res://assets/art/review/combat_art_stage_review_capture.png"
const CAPTURE_SIZE := Vector2i(1920, 1080)

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Window Viewport 렌더러가 필요합니다. headless에서는 캡처할 수 없습니다.")
		return
	var arguments := OS.get_cmdline_user_args()
	if arguments.size() > 1:
		_fail("사용법: capture_combat_art_review [output.png]")
		return
	var output_path := DEFAULT_OUTPUT
	if not arguments.is_empty():
		output_path = arguments[0]
		if output_path.begins_with("-"):
			_fail("출력 경로는 명령행 옵션일 수 없습니다.")
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
	root.add_child(review)
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
	print("combat-art-stage-review-capture: saved real %dx%d Window Viewport PNG to %s" % [CAPTURE_SIZE.x, CAPTURE_SIZE.y, absolute_output])
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
	push_error("combat-art-stage-review-capture: " + message)
	quit(1)
