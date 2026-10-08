extends SceneTree

const TARGET_WIDTH := 1920
const TARGET_HEIGHT := 1080
const DEFAULT_IMAGE := "res://assets/art/stages/stage.png"
const ARENA_RECT := Rect2(160.0, 100.0, 1600.0, 880.0)

var image_path := DEFAULT_IMAGE

func _initialize() -> void:
	call_deferred("_start")

func _start() -> void:
	var args := OS.get_cmdline_user_args()
	var check_only := args.has("--check")
	for arg in args:
		if arg != "--check" and not arg.begins_with("--"):
			image_path = arg
			break
	image_path = _resolve_path(image_path)
	var result := inspect_png(image_path)
	_print_report(result)
	if check_only:
		quit(0 if result.passed else 1)
		return
	_show_review(result)

static func inspect_png(path: String) -> Dictionary:
	var result := {"path": path, "passed": false, "width": 0, "height": 0, "errors": [], "image": null}
	if not FileAccess.file_exists(path):
		result.errors.append("이미지 파일을 찾을 수 없습니다.")
		return result
	var bytes := FileAccess.get_file_as_bytes(path)
	if not _has_png_signature(bytes):
		result.errors.append("올바른 PNG 파일이 아닙니다.")
		return result
	var image := Image.new()
	var error := image.load_png_from_buffer(bytes)
	if error != OK or image.is_empty():
		result.errors.append("PNG 디코딩에 실패했습니다: %s" % error_string(error))
		return result
	result.width = image.get_width()
	result.height = image.get_height()
	result.image = image
	if result.width != TARGET_WIDTH or result.height != TARGET_HEIGHT:
		result.errors.append("정확한 크기 %dx%d가 필요합니다 (현재 %dx%d)." % [TARGET_WIDTH, TARGET_HEIGHT, result.width, result.height])
	result.passed = result.errors.is_empty()
	return result

static func _has_png_signature(bytes: PackedByteArray) -> bool:
	var signature := [137, 80, 78, 71, 13, 10, 26, 10]
	if bytes.size() < signature.size():
		return false
	for index in range(signature.size()):
		if bytes[index] != signature[index]:
			return false
	return true

func _resolve_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.is_absolute_path():
		return path
	return ProjectSettings.globalize_path("res://" + path)

func _print_report(result: Dictionary) -> void:
	print("stage-review-check: %s" % ("PASS" if result.passed else "FAIL"))
	print("image: %s" % result.path)
	if result.width > 0:
		print("size: %dx%d (required %dx%d)" % [result.width, result.height, TARGET_WIDTH, TARGET_HEIGHT])
	for message in result.errors:
		push_error("stage-review: " + message)

func _show_review(result: Dictionary) -> void:
	var ui := Control.new()
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(ui)
	var heading := Label.new()
	heading.text = "스테이지 배경 검수"
	heading.position = Vector2(30, 18)
	heading.add_theme_font_size_override("font_size", 26)
	ui.add_child(heading)
	var status := Label.new()
	status.text = "크기 검사: %s    상단 40%% / 하단 60%% / Arena 영역 확인" % ("통과" if result.passed else "실패")
	status.position = Vector2(30, 56)
	status.add_theme_color_override("font_color", Color(0.55, 1.0, 0.58) if result.passed else Color(1.0, 0.48, 0.42))
	ui.add_child(status)
	var path_label := Label.new()
	path_label.text = result.path
	path_label.position = Vector2(30, 82)
	ui.add_child(path_label)
	if result.image == null:
		var details := Label.new()
		details.text = "\n".join(result.errors)
		details.position = Vector2(40, 140)
		ui.add_child(details)
		return
	var preview_rect := Rect2(Vector2(40, 130), Vector2(960, 540))
	var image_texture := ImageTexture.create_from_image(result.image)
	var preview := TextureRect.new()
	preview.position = preview_rect.position
	preview.size = preview_rect.size
	preview.texture = image_texture
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_SCALE
	ui.add_child(preview)
	_add_overlay(ui, preview_rect, Rect2(0, 0, 1, 0.4), Color(0.15, 0.65, 1.0, 0.20), "상단 40%")
	_add_overlay(ui, preview_rect, Rect2(0, 0.4, 1, 0.6), Color(1.0, 0.55, 0.12, 0.18), "하단 60%")
	var arena := Rect2(preview_rect.position + Vector2(ARENA_RECT.position.x / TARGET_WIDTH * preview_rect.size.x, ARENA_RECT.position.y / TARGET_HEIGHT * preview_rect.size.y), Vector2(ARENA_RECT.size.x / TARGET_WIDTH * preview_rect.size.x, ARENA_RECT.size.y / TARGET_HEIGHT * preview_rect.size.y))
	var outline := ReferenceRect.new()
	outline.position = arena.position
	outline.size = arena.size
	outline.border_color = Color(0.25, 1.0, 0.4, 0.95)
	outline.border_width = 3
	outline.editor_only = false
	ui.add_child(outline)
	var arena_label := Label.new()
	arena_label.text = "현재 Arena (160, 100)–(1760, 980)"
	arena_label.position = arena.position + Vector2(8, 8)
	arena_label.add_theme_color_override("font_color", Color(0.25, 1.0, 0.4))
	ui.add_child(arena_label)
	var guide := Label.new()
	guide.text = "파란 영역: 상단 40%   주황 영역: 하단 60%   녹색 테두리: 현재 게임 Arena"
	guide.position = Vector2(40, 685)
	ui.add_child(guide)

func _add_overlay(parent: Control, preview_rect: Rect2, normalized: Rect2, color: Color, caption: String) -> void:
	var panel := ColorRect.new()
	panel.position = preview_rect.position + Vector2(normalized.position.x * preview_rect.size.x, normalized.position.y * preview_rect.size.y)
	panel.size = Vector2(normalized.size.x * preview_rect.size.x, normalized.size.y * preview_rect.size.y)
	panel.color = color
	parent.add_child(panel)
	var label := Label.new()
	label.text = caption
	label.position = panel.position + Vector2(8, 6)
	label.add_theme_color_override("font_color", Color.WHITE)
	parent.add_child(label)
