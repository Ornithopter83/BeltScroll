extends Node2D

const CAMERA_ZOOM := Vector2(1.2, 1.2)
const TARGET_SCREEN_HEIGHT := 192.0
const FOOT_BASELINE_WORLD_Y := 850.0
const PLAYER_PATH := "res://assets/art/player/elven_fighter_reference_v4_matte_v4_1254x1254.png"
const RAIDER_PATH := "res://assets/art/enemies/forest_raider_reference_v1_safe_1254x1254.png"
const CANDIDATE_PLAYER_PATH := "res://assets/art/player/elven_fighter_reference_v5_clean_1254x1254.png"
const CANDIDATE_RAIDER_PATH := "res://assets/art/enemies/forest_raider_reference_v1_clean_1254x1254.png"
const FOREST_PATH := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"

var zoom_factor := 1.0
var facing_right := true
var raider_facing_right := true
@export var overlap_review_mode := false
@export var candidate_review_mode := false
var candidate_overlap_mode := false
var _player_sprite: Sprite2D
var _raider_sprite: Sprite2D
var _status_label: Label
var _camera: Camera2D

@onready var _player_anchor: Node2D = $ReviewActors/PlayerCandidate
@onready var _raider_anchor: Node2D = $ReviewActors/RaiderCandidate
@onready var _player_front_anchor: Node2D = $ReviewActors/PlayerFrontCandidate
@onready var _raider_front_anchor: Node2D = $ReviewActors/RaiderFrontCandidate
@onready var _review_canvas: CanvasLayer = $ReviewCanvas

func _ready() -> void:
	_camera = $Camera2D
	_camera.zoom = CAMERA_ZOOM
	if overlap_review_mode:
		_configure_overlap_positions()
	var player_path := CANDIDATE_PLAYER_PATH if candidate_review_mode else PLAYER_PATH
	var raider_path := CANDIDATE_RAIDER_PATH if candidate_review_mode else RAIDER_PATH
	_player_sprite = _build_candidate(_player_anchor, player_path, "PlayerArt")
	_raider_sprite = _build_candidate(_raider_anchor, raider_path, "RaiderArt")
	if overlap_review_mode:
		_build_candidate(_player_front_anchor, PLAYER_PATH, "PlayerArt")
		_build_candidate(_raider_front_anchor, RAIDER_PATH, "RaiderArt")
	_build_overlay()
	_update_view_controls()

func _configure_overlap_positions() -> void:
	# Both pairs share X; the larger Y anchor is rendered in front by ReviewActors YSort.
	_player_anchor.position = Vector2(650, 850)
	_raider_anchor.position = Vector2(650, 890)
	_player_front_anchor.position = Vector2(1270, 890)
	_raider_front_anchor.position = Vector2(1270, 850)
	_player_front_anchor.visible = true
	_raider_front_anchor.visible = true

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT, KEY_A:
			facing_right = false
			_update_view_controls()
			get_viewport().set_input_as_handled()
		KEY_RIGHT, KEY_D:
			facing_right = true
			_update_view_controls()
			get_viewport().set_input_as_handled()
		KEY_EQUAL, KEY_KP_ADD, KEY_PLUS:
			zoom_factor = minf(zoom_factor * 1.2, 3.0)
			_update_view_controls()
			get_viewport().set_input_as_handled()
		KEY_MINUS, KEY_KP_SUBTRACT:
			zoom_factor = maxf(zoom_factor / 1.2, 0.5)
			_update_view_controls()
			get_viewport().set_input_as_handled()
		KEY_0:
			zoom_factor = 1.0
			_update_view_controls()
			get_viewport().set_input_as_handled()
		KEY_P when candidate_review_mode:
			facing_right = not facing_right
			_update_view_controls()
			get_viewport().set_input_as_handled()
		KEY_R when candidate_review_mode:
			raider_facing_right = not raider_facing_right
			_update_view_controls()
			get_viewport().set_input_as_handled()
		KEY_O when candidate_review_mode:
			candidate_overlap_mode = not candidate_overlap_mode
			_configure_candidate_positions()
			_refresh_overlay()
			get_viewport().set_input_as_handled()
		KEY_C when not overlap_review_mode:
			candidate_review_mode = not candidate_review_mode
			candidate_overlap_mode = false
			_configure_candidate_positions()
			_rebuild_candidate_sprites()
			_refresh_overlay()
			_update_view_controls()
			get_viewport().set_input_as_handled()

func _rebuild_candidate_sprites() -> void:
	if _player_sprite != null:
		_player_sprite.free()
	if _raider_sprite != null:
		_raider_sprite.free()
	var player_path := CANDIDATE_PLAYER_PATH if candidate_review_mode else PLAYER_PATH
	var raider_path := CANDIDATE_RAIDER_PATH if candidate_review_mode else RAIDER_PATH
	_player_sprite = _build_candidate(_player_anchor, player_path, "PlayerArt")
	_raider_sprite = _build_candidate(_raider_anchor, raider_path, "RaiderArt")

func _refresh_overlay() -> void:
	var old_overlay := _review_canvas.get_node_or_null("ReviewOverlay")
	if old_overlay != null:
		old_overlay.free()
	_build_overlay()

func _configure_candidate_positions() -> void:
	if candidate_overlap_mode:
		_player_anchor.position = Vector2(960, 850)
		_raider_anchor.position = Vector2(960, 890)
	else:
		_player_anchor.position = Vector2(650, FOOT_BASELINE_WORLD_Y)
		_raider_anchor.position = Vector2(1270, FOOT_BASELINE_WORLD_Y)

func _build_candidate(anchor: Node2D, texture_path: String, node_name: String) -> Sprite2D:
	var source_texture := load(texture_path) as Texture2D
	if source_texture == null:
		push_error("검수 원화를 불러오지 못했습니다: " + texture_path)
		return null
	var source_image := source_texture.get_image()
	if source_image == null or source_image.is_empty():
		push_error("검수 원화가 비어 있습니다: " + texture_path)
		return null
	var bounds := _find_alpha_bounds(source_image)
	if bounds.size.x <= 0 or bounds.size.y <= 0:
		push_error("원화에서 불투명 실루엣을 찾지 못했습니다: " + texture_path)
		return null
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = ImageTexture.create_from_image(source_image.get_region(bounds))
	sprite.centered = true
	sprite.position = Vector2(0.0, -TARGET_SCREEN_HEIGHT / CAMERA_ZOOM.y * 0.5)
	sprite.scale = Vector2.ONE * (TARGET_SCREEN_HEIGHT / CAMERA_ZOOM.y / float(bounds.size.y))
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	anchor.add_child(sprite)
	return sprite

func _build_overlay() -> void:
	var overlay := Control.new()
	overlay.name = "ReviewOverlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_review_canvas.add_child(overlay)
	if candidate_review_mode:
		_make_label(overlay, "전투 아트 후보 검수 · 실제 Window Viewport 렌더", Vector2(44, 26), 32, Color.WHITE, "ReviewHeading")
		_make_label(overlay, "PLAYER: v5_clean (미승인)    RAIDER: v1_clean (미승인)", Vector2(48, 72), 20, Color("#ffe1a6"), "AssetNames")
		_make_label(overlay, "192 px 화면 높이 · 발 anchor 정렬 · 카메라 zoom 1.2× · O 겹침 배치 전환", Vector2(48, 106), 18, Color("#d2dfd7"), "ScaleNote")
	elif overlap_review_mode:
		_make_label(overlay, "OVERLAP DEPTH REVIEW · 실제 Window Viewport 렌더", Vector2(44, 26), 32, Color.WHITE, "ReviewHeading")
		_make_label(overlay, "PLAYER: v4_matte_v4    RAIDER: v1_safe    두 쌍은 동일 X, 서로 반대 Y 순서", Vector2(48, 72), 20, Color("#e5e8df"), "AssetNames")
		_make_label(overlay, "192 px 화면 높이 · 각 발 기준선 표시 · 카메라 zoom 1.2× · YSort 깊이 가림", Vector2(48, 106), 18, Color("#d2dfd7"), "ScaleNote")
	else:
		_make_label(overlay, "전투 아트 · Forest Ruins 검수", Vector2(44, 26), 32, Color.WHITE, "ReviewHeading")
		_make_label(overlay, "왼쪽: v4_matte_v4    오른쪽: forest_raider_reference_v1_safe", Vector2(48, 72), 20, Color("#e5e8df"), "AssetNames")
		_make_label(overlay, "192 px 화면 높이 · 동일 발 기준 · 카메라 기본 확대 1.2×", Vector2(48, 106), 18, Color("#d2dfd7"), "ScaleNote")
	_status_label = _make_label(overlay, "", Vector2(48, 142), 17, Color("#ffd17a"), "ViewStatus")
	if candidate_review_mode:
		_make_label(overlay, "C: 후보 모드 전환     P: PLAYER 방향     R: RAIDER 방향     O: 겹침 배치     + / - 확대     0 기본 배율", Vector2(48, 176), 16, Color.WHITE, "Controls")
	else:
		var legacy_controls := "← / A 왼쪽 보기     → / D 오른쪽 보기     + / - 확대 비교     0 기본 배율"
		if not overlap_review_mode:
			legacy_controls = "C: v5_clean 후보 모드     " + legacy_controls
		_make_label(overlay, legacy_controls, Vector2(48, 176), 16, Color.WHITE, "Controls")
	if candidate_review_mode:
		if candidate_overlap_mode:
			_add_baseline(overlay, 850.0, 960.0, "PLAYER 뒤 발 기준선")
			_add_baseline(overlay, 890.0, 960.0, "RAIDER 앞 발 기준선")
			_make_label(overlay, "YSort 깊이 겹침 비교", Vector2(790, 218), 18, Color("#ffd1c9"), "CandidateOverlapTag")
		else:
			var candidate_baseline_y := 540.0 + (FOOT_BASELINE_WORLD_Y - 540.0) * CAMERA_ZOOM.y
			var candidate_baseline := ColorRect.new()
			candidate_baseline.name = "FootBaseline"
			candidate_baseline.position = Vector2(350, candidate_baseline_y)
			candidate_baseline.size = Vector2(1220, 2)
			candidate_baseline.color = Color("#ff665c")
			overlay.add_child(candidate_baseline)
			_make_label(overlay, "PLAYER · 미승인 후보", Vector2(590, 870), 16, Color("#ffe1a6"), "PlayerTag")
			_make_label(overlay, "RAIDER · 미승인 후보", Vector2(1210, 870), 16, Color("#ffe1a6"), "RaiderTag")
	elif overlap_review_mode:
		_add_baseline(overlay, 850.0, 420.0, "후면 PLAYER 발 기준선")
		_add_baseline(overlay, 890.0, 420.0, "전면 RAIDER 발 기준선")
		_add_baseline(overlay, 890.0, 1040.0, "전면 PLAYER 발 기준선")
		_add_baseline(overlay, 850.0, 1040.0, "후면 RAIDER 발 기준선")
		_make_label(overlay, "PLAYER 뒤 · RAIDER 앞", Vector2(470, 218), 18, Color("#ffd1c9"), "PairOneTag")
		_make_label(overlay, "RAIDER 뒤 · PLAYER 앞", Vector2(1090, 218), 18, Color("#ffd1c9"), "PairTwoTag")
	else:
		var baseline_y := 540.0 + (FOOT_BASELINE_WORLD_Y - 540.0) * CAMERA_ZOOM.y
		var baseline := ColorRect.new()
		baseline.name = "FootBaseline"
		baseline.position = Vector2(350, baseline_y)
		baseline.size = Vector2(1220, 2)
		baseline.color = Color("#ff665c")
		overlay.add_child(baseline)
		_make_label(overlay, "공통 발 기준선", Vector2(1580, baseline_y - 25), 15, Color("#ffd1c9"), "BaselineLabel")
		_make_label(overlay, "PLAYER", Vector2(590, 870), 16, Color("#f1e7c8"), "PlayerTag")
		_make_label(overlay, "RAIDER", Vector2(1210, 870), 16, Color("#f1e7c8"), "RaiderTag")

func _add_baseline(parent: Control, world_y: float, center_x: float, baseline_name: String) -> void:
	var screen_y := 540.0 + (world_y - 540.0) * CAMERA_ZOOM.y
	var baseline := ColorRect.new()
	baseline.name = "FootBaseline_%s" % baseline_name.replace(" ", "_")
	baseline.position = Vector2(center_x - 210.0, screen_y)
	baseline.size = Vector2(420, 2)
	baseline.color = Color("#ff665c")
	parent.add_child(baseline)
	_make_label(parent, baseline_name, Vector2(center_x - 210.0, screen_y - 23.0), 14, Color("#ffd1c9"), baseline.name + "Label")

func _update_view_controls() -> void:
	if _camera != null:
		_camera.zoom = CAMERA_ZOOM * zoom_factor
	if _player_sprite != null:
		_player_sprite.flip_h = not facing_right
	if _raider_sprite != null:
		_raider_sprite.flip_h = not (raider_facing_right if candidate_review_mode else facing_right)
	if _status_label != null:
		if candidate_review_mode:
			_status_label.text = "PLAYER: %s    RAIDER: %s    배치: %s    비교 확대: %.2f×" % ["오른쪽" if facing_right else "왼쪽", "오른쪽" if raider_facing_right else "왼쪽", "겹침" if candidate_overlap_mode else "기본", zoom_factor]
		else:
			_status_label.text = "방향: %s    비교 확대: %.2f×" % ["오른쪽" if facing_right else "왼쪽", zoom_factor]

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

func _make_label(parent: Control, text: String, label_position: Vector2, font_size: int, color: Color, node_name: String) -> Label:
	var label := Label.new()
	label.name = node_name
	label.text = text
	label.position = label_position
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label
