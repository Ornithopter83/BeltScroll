extends SceneTree
"""Renders the existing Raider VisualAnimator into a labeled comparison sheet."""

const RAIDER_SCENE := "res://scenes/enemies/forest_raider.tscn"
const FOREST_TEXTURE := "res://assets/art/stage/forest_ruins_v1_1920x1080.png"
const DEFAULT_OUTPUT := "res://assets/art/review/raider_motion_states_capture.png"
const VIEW_SIZE := Vector2i(1920, 1080)
const COLUMNS := 4
const ROWS := 2
const CELL_SIZE := Vector2i(VIEW_SIZE.x / COLUMNS, VIEW_SIZE.y / ROWS)
const DISPLAY_HEIGHT := 192.0
const FOOT_MARGIN := 112.0

const STATES := [
	{"key": "idle", "label": "대기 · 오른쪽", "facing": 1, "kind": "idle"},
	{"key": "tracking", "label": "추적 · 왼쪽", "facing": -1, "kind": "tracking"},
	{"key": "windup", "label": "공격 준비 · 오른쪽", "facing": 1, "kind": "windup"},
	{"key": "active", "label": "공격 활성 · 왼쪽", "facing": -1, "kind": "active"},
	{"key": "recovery", "label": "회복 · 오른쪽", "facing": 1, "kind": "recovery"},
	{"key": "hit", "label": "피격 경직 · 왼쪽", "facing": -1, "kind": "hit"},
	{"key": "ko", "label": "KO · 오른쪽", "facing": 1, "kind": "ko"},
	{"key": "skill_hit", "label": "강한 스킬 피격 · 오른쪽", "facing": 1, "kind": "skill_hit"},
]

var _root_node: Node2D
var _raider: CharacterBody2D
var _animator: Node
var _art: Sprite2D
var _sheet: Image

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Window Viewport 렌더러가 필요합니다. headless에서는 캡처할 수 없습니다.")
		return
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 or (not args.is_empty() and args[0].begins_with("-")):
		_fail("사용법: capture_raider_motion_sheet [output.png]")
		return
	var output_path := DEFAULT_OUTPUT if args.is_empty() else args[0]
	root.size = VIEW_SIZE
	var forest := load(FOREST_TEXTURE) as Texture2D
	var packed := load(RAIDER_SCENE) as PackedScene
	if forest == null or packed == null:
		_fail("Forest Ruins 배경 또는 Raider 검수 씬을 불러오지 못했습니다.")
		return
	_root_node = Node2D.new()
	_root_node.name = "RaiderMotionCapture"
	root.add_child(_root_node)
	_build_board(forest)
	_raider = packed.instantiate() as CharacterBody2D
	if _raider == null:
		_fail("Forest Raider 검수 씬을 인스턴스화하지 못했습니다.")
		return
	_raider.set_physics_process(false)
	_art = _raider.get_node("VisualRoot/RaiderArt") as Sprite2D
	_animator = _raider.get_node_or_null("VisualAnimator")
	if _art == null or _art.texture == null or _animator == null:
		_fail("기존 RaiderArt 또는 VisualAnimator가 검수 씬에 없습니다.")
		return
	var alpha_bounds := _art.texture.get_image().get_used_rect()
	if alpha_bounds.size.y <= 0:
		_fail("Raider 원화에서 표시할 불투명 실루엣을 찾지 못했습니다.")
		return
	var authored_scale := _art.scale
	_art.scale = Vector2.ONE * (DISPLAY_HEIGHT / float(alpha_bounds.size.y))
	_art.set_meta("capture_authored_scale", authored_scale)
	_root_node.add_child(_raider)
	for _frame in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	_sheet = root.get_texture().get_image()
	if _sheet == null or _sheet.is_empty() or _sheet.get_size() != VIEW_SIZE:
		_fail("검수 보드의 Window Viewport 프레임을 읽지 못했습니다.")
		return
	for index in range(STATES.size()):
		_apply_state(STATES[index])
		var cell := _cell_rect(index)
		_raider.position = Vector2(cell.position.x + cell.size.x * 0.5, cell.end.y - FOOT_MARGIN)
		for _frame in range(24):
			_animator.call("_process", 1.0 / 60.0)
			await process_frame
		await RenderingServer.frame_post_draw
		var rendered := root.get_texture().get_image()
		if rendered == null or rendered.is_empty() or rendered.get_size() != VIEW_SIZE:
			_fail("상태 %s의 Window Viewport 프레임을 읽지 못했습니다." % STATES[index].key)
			return
		_sheet.blit_rect(rendered, cell, cell.position)
		print("raider-motion-capture: rendered %s (%s)" % [STATES[index].key, STATES[index].label])
	_raider.queue_free()
	await process_frame
	var abs_output := ProjectSettings.globalize_path(output_path)
	var dir_error := DirAccess.make_dir_recursive_absolute(abs_output.get_base_dir())
	if dir_error != OK:
		_fail("출력 디렉터리를 만들지 못했습니다: %s (오류 %d)" % [abs_output.get_base_dir(), dir_error])
		return
	var save_error := _sheet.save_png(abs_output)
	if save_error != OK:
		_fail("모션 비교판 PNG 저장 실패: %s (오류 %d)" % [abs_output, save_error])
		return
	var saved := Image.new()
	var load_error := saved.load(abs_output)
	if load_error != OK or saved.get_size() != VIEW_SIZE:
		_fail("저장한 모션 비교판을 다시 읽지 못했거나 크기가 잘못되었습니다.")
		return
	print("raider-motion-capture: saved real %dx%d Window Viewport state captures to %s" % [VIEW_SIZE.x, VIEW_SIZE.y, abs_output])
	quit(0)

func _build_board(forest: Texture2D) -> void:
	for index in range(COLUMNS * ROWS):
		var cell := _cell_rect(index)
		var backdrop := Sprite2D.new()
		backdrop.name = "ForestRuinsBackdrop_%d" % index
		backdrop.texture = forest
		backdrop.region_enabled = true
		backdrop.region_rect = Rect2(Vector2(700, 250), Vector2(CELL_SIZE))
		backdrop.position = Vector2(cell.position) + Vector2(CELL_SIZE) * 0.5
		backdrop.z_index = -20
		_root_node.add_child(backdrop)
	var overlay := CanvasLayer.new()
	overlay.layer = 5
	_root_node.add_child(overlay)
	var board := Control.new()
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(board)
	_label(board, "RAIDER VISUALANIMATOR · 상태별 실제 Window Viewport 캡처", Vector2(28, 12), 27, Color.WHITE)
	_label(board, "합성된 상태 비교 시트 · 실제 연속 플레이 영상이 아닙니다", Vector2(32, 47), 18, Color("#ffe1a6"))
	for index in range(COLUMNS * ROWS):
		var cell := _cell_rect(index)
		var shade := ColorRect.new()
		shade.position = cell.position
		shade.size = cell.size
		shade.color = Color(0.025, 0.035, 0.04, 0.34)
		board.add_child(shade)
		var heading_text: String = STATES[index].label if index < STATES.size() else "검수 범위"
		var heading := _label(board, heading_text, Vector2(cell.position) + Vector2(16, 77), 21, Color.WHITE)
		heading.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
		heading.add_theme_constant_override("shadow_offset_x", 1)
		heading.add_theme_constant_override("shadow_offset_y", 1)
		var hud := ColorRect.new()
		hud.position = Vector2(cell.position) + Vector2(16, 111)
		hud.size = Vector2(cell.size.x - 32, 22)
		hud.color = Color(0.015, 0.025, 0.03, 0.82)
		board.add_child(hud)
		_label(board, "RAIDER   ♥ ♥ ♥", Vector2(cell.position) + Vector2(24, 112), 14, Color("#f2e6cf"))
		if index < STATES.size():
			var baseline := ColorRect.new()
			baseline.position = Vector2(cell.position.x + 20, cell.end.y - FOOT_MARGIN)
			baseline.size = Vector2(cell.size.x - 40, 1.0)
			baseline.color = Color(0.95, 0.83, 0.52, 0.9)
			board.add_child(baseline)
			_label(board, "발 anchor · 표시 높이 192 px", Vector2(cell.position.x + 16, cell.end.y - 101), 14, Color("#f2dfab"))
		else:
			_label(board, "• 상태별 실제 Window Viewport 프레임", Vector2(cell.position.x + 18, cell.position.y + 155), 16, Color.WHITE)
			_label(board, "• 좌우 방향을 번갈아 배치", Vector2(cell.position.x + 18, cell.position.y + 190), 16, Color.WHITE)
			_label(board, "• HUD 표식과 발 기준선으로 가림 확인", Vector2(cell.position.x + 18, cell.position.y + 225), 16, Color.WHITE)
			_label(board, "• AI / 물리 업데이트 없이 시각 상태 재현", Vector2(cell.position.x + 18, cell.position.y + 260), 16, Color.WHITE)
			_label(board, "합성 비교판 · 연속 플레이 영상 아님", Vector2(cell.position.x + 18, cell.position.y + 318), 16, Color("#ffe1a6"))
		var border := ReferenceRect.new()
		border.position = cell.position
		border.size = cell.size
		border.border_color = Color(0.85, 0.9, 0.85, 0.5)
		border.border_width = 1.0
		border.editor_only = false
		board.add_child(border)
	_label(board, "Forest Ruins · HUD와 실루엣의 겹침 및 좌우 방향 확인", Vector2(32, VIEW_SIZE.y - 28), 16, Color.WHITE)

func _label(parent: Control, value: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)
	return label

func _apply_state(state: Dictionary) -> void:
	_raider.set("health", 3)
	_raider.velocity = Vector2.ZERO
	_raider.set("facing_direction", Vector2(float(state.facing), 0.0))
	_raider.get_node("VisualRoot").scale.x = -float(state.facing)
	_raider.set("attack_phase", "idle")
	_raider.set("attack_phase_remaining", 0.0)
	_raider.set("hitstun_remaining", 0.0)
	_raider.set("hit_flash_remaining", 0.0)
	_art.modulate = Color.WHITE
	match state.kind:
		"tracking":
			_raider.velocity = Vector2(-118.0, 0.0)
		"windup":
			_raider.set("attack_phase", "windup")
			_raider.set("attack_phase_remaining", float(_raider.get("windup_duration")) * 0.2)
		"active":
			_raider.set("attack_phase", "active")
			_raider.set("attack_phase_remaining", float(_raider.get("active_duration")) * 0.5)
			_raider.get_node("VisualRoot/AttackFlash").visible = true
		"recovery":
			_raider.set("attack_phase", "recovery")
			_raider.set("attack_phase_remaining", float(_raider.get("recovery_duration")) * 0.55)
		"hit":
			_raider.velocity = Vector2(80.0, 0.0)
			_raider.set("hitstun_remaining", 0.2)
			_raider.set("hit_flash_remaining", 0.11)
			_raider.set("hit_reaction_direction", Vector2.RIGHT)
			_raider.set("hit_reaction_strength", 0.72)
			_art.modulate = Color(1.0, 0.78, 0.58, 1.0)
		"skill_hit":
			_raider.velocity = Vector2(170.0, 0.0)
			_raider.set("hitstun_remaining", 0.34)
			_raider.set("hit_flash_remaining", 0.16)
			_raider.set("hit_reaction_direction", Vector2.RIGHT)
			_raider.set("hit_reaction_strength", 1.32)
			_art.modulate = Color(1.0, 0.72, 0.5, 1.0)
		"ko":
			_raider.set("health", 0)
			_art.modulate = Color(0.62, 0.62, 0.62, 0.78)
	_raider.get_node("VisualRoot/AttackFlash").visible = state.kind in ["windup", "active"]

func _cell_rect(index: int) -> Rect2i:
	return Rect2i(Vector2i((index % COLUMNS) * CELL_SIZE.x, (index / COLUMNS) * CELL_SIZE.y), CELL_SIZE)

func _fail(message: String) -> void:
	push_error("raider-motion-capture: " + message)
	quit(1)
