extends Node2D

const CAMERA_ZOOM := Vector2(1.2, 1.2)
const TARGET_SCREEN_HEIGHT := 192.0
const FOOT_BASELINE_WORLD_Y := 850.0
const V3_SAFE_PATH := "res://assets/art/player/elven_fighter_reference_v3_safe_1254x1254.png"
const V4_SAFE_PATH := "res://assets/art/player/elven_fighter_reference_v4_safe_1254x1254.png"
const CANDIDATE_PATHS := [V3_SAFE_PATH, V4_SAFE_PATH]
const PREVIEW_REGIONS := {
	"PreviewFaceEar": Rect2(0.40, 0.00, 0.55, 0.38),
	"PreviewHands": Rect2(0.12, 0.27, 0.72, 0.27),
	"PreviewLeftFoot": Rect2(0.03, 0.53, 0.52, 0.30),
	"PreviewRightFoot": Rect2(0.46, 0.64, 0.52, 0.34),
}
const PREVIEW_LAYOUT := {
	"PreviewFaceEar": {"title": "얼굴 · 귀", "position": Vector2(970, 166)},
	"PreviewHands": {"title": "손 · 손목", "position": Vector2(1410, 166)},
	"PreviewLeftFoot": {"title": "왼발 · 부츠", "position": Vector2(970, 500)},
	"PreviewRightFoot": {"title": "오른발 · 부츠", "position": Vector2(1410, 500)},
}

var selected_candidate := 0
var _alpha_bounds := Rect2i()
var _candidate_title: Label
var _approval_status: Label
var _preview_textures: Dictionary = {}

@onready var _candidate_sprite: Sprite2D = $CandidateSprite
@onready var _review_canvas: CanvasLayer = $ReviewCanvas

func _ready() -> void:
	_build_review_ui()
	_select_candidate(0)

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_1 or event.physical_keycode == KEY_1:
		_select_candidate(0)
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_2 or event.physical_keycode == KEY_2:
		_select_candidate(1)
		get_viewport().set_input_as_handled()

func _select_candidate(index: int) -> void:
	selected_candidate = clampi(index, 0, CANDIDATE_PATHS.size() - 1)
	var candidate_path: String = CANDIDATE_PATHS[selected_candidate]
	var source_texture := load(candidate_path) as Texture2D
	if source_texture == null:
		push_error("Player 원화 파일을 불러오지 못했습니다: " + candidate_path)
		return
	var source_image := source_texture.get_image()
	if source_image == null or source_image.is_empty():
		push_error("Player 원화 이미지가 비어 있습니다: " + candidate_path)
		return
	_alpha_bounds = _find_alpha_bounds(source_image)
	if _alpha_bounds.size.y <= 0:
		push_error("Player 원화에서 전신 실루엣을 찾지 못했습니다: " + candidate_path)
		return
	var silhouette := source_image.get_region(_alpha_bounds)
	_candidate_sprite.texture = ImageTexture.create_from_image(silhouette)
	var sprite_scale := TARGET_SCREEN_HEIGHT / CAMERA_ZOOM.y / float(_alpha_bounds.size.y)
	_candidate_sprite.scale = Vector2.ONE * sprite_scale
	_candidate_sprite.position = Vector2(600, FOOT_BASELINE_WORLD_Y - TARGET_SCREEN_HEIGHT / CAMERA_ZOOM.y * 0.5)
	_candidate_title.text = "후보 %d  ·  %s" % [selected_candidate + 1, candidate_path.get_file()]
	_approval_status.text = "미승인 · 시각 검수 필요"
	_update_previews(source_image)

func _build_review_ui() -> void:
	var root := Control.new()
	root.name = "ReviewOverlay"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_review_canvas.add_child(root)

	var header := _make_label(root, "Player 원화 시각 검수", Vector2(48, 26), 34, Color.WHITE)
	header.name = "ReviewHeading"
	_candidate_title = _make_label(root, "", Vector2(50, 76), 22, Color("#d9e6e4"))
	_candidate_title.name = "CandidateName"
	_approval_status = _make_label(root, "미승인 · 시각 검수 필요", Vector2(50, 111), 21, Color("#ffd17a"))
	_approval_status.name = "ApprovalStatus"
	_make_label(root, "1 / v3_safe       2 / v4_safe       ·       자동 승인 없음", Vector2(50, 146), 17, Color("#e0e7e8"))
	_make_label(root, "전신 실루엣 · 발 기준선", Vector2(355, 606), 18, Color.WHITE)

	var baseline := ColorRect.new()
	baseline.name = "FootBaseline"
	baseline.position = Vector2(270, _world_to_screen_y(FOOT_BASELINE_WORLD_Y))
	baseline.size = Vector2(430, 3)
	baseline.color = Color("#f05c4f")
	root.add_child(baseline)
	var baseline_caption := _make_label(root, "기준선", Vector2(710, _world_to_screen_y(FOOT_BASELINE_WORLD_Y) - 13), 14, Color("#ffc1b9"))
	baseline_caption.name = "FootBaselineLabel"

	for preview_name in PREVIEW_LAYOUT:
		var entry: Dictionary = PREVIEW_LAYOUT[preview_name]
		_add_preview_panel(root, preview_name, entry.title, entry.position)

func _add_preview_panel(parent: Control, preview_name: String, title: String, panel_position: Vector2) -> void:
	var panel := PanelContainer.new()
	panel.name = preview_name + "Panel"
	panel.position = panel_position
	panel.size = Vector2(400, 292)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.055, 0.065, 0.88)
	style.border_color = Color("#8aa9a3")
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 6)
	panel.add_child(content)
	var heading := Label.new()
	heading.text = title
	heading.add_theme_font_size_override("font_size", 18)
	heading.add_theme_color_override("font_color", Color("#e5d1a4"))
	content.add_child(heading)
	var preview := TextureRect.new()
	preview.name = preview_name
	preview.custom_minimum_size = Vector2(372, 246)
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	content.add_child(preview)
	_preview_textures[preview_name] = preview

func _update_previews(source_image: Image) -> void:
	for preview_name in PREVIEW_REGIONS:
		var region: Rect2 = PREVIEW_REGIONS[preview_name]
		var x := _alpha_bounds.position.x + int(floor(region.position.x * _alpha_bounds.size.x))
		var y := _alpha_bounds.position.y + int(floor(region.position.y * _alpha_bounds.size.y))
		var right := _alpha_bounds.position.x + int(ceil((region.position.x + region.size.x) * _alpha_bounds.size.x))
		var bottom := _alpha_bounds.position.y + int(ceil((region.position.y + region.size.y) * _alpha_bounds.size.y))
		var crop_rect := Rect2i(x, y, maxi(1, right - x), maxi(1, bottom - y)).intersection(Rect2i(Vector2i.ZERO, source_image.get_size()))
		var crop := source_image.get_region(crop_rect)
		(_preview_textures[preview_name] as TextureRect).texture = ImageTexture.create_from_image(crop)

func _find_alpha_bounds(source: Image) -> Rect2i:
	var min_x := source.get_width()
	var min_y := source.get_height()
	var max_x := -1
	var max_y := -1
	for y in range(source.get_height()):
		for x in range(source.get_width()):
			if source.get_pixel(x, y).a > 0.0:
				min_x = mini(min_x, x)
				min_y = mini(min_y, y)
				max_x = maxi(max_x, x)
				max_y = maxi(max_y, y)
	return Rect2i(min_x, min_y, max_x - min_x + 1, max_y - min_y + 1) if max_x >= min_x else Rect2i()

func _world_to_screen_y(world_y: float) -> float:
	return 540.0 + (world_y - 540.0) * CAMERA_ZOOM.y

func _make_label(parent: Control, text: String, label_position: Vector2, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.position = label_position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
