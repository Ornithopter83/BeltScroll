extends SceneTree
"""Captures the current player visual states from the real Window Viewport."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const DEFAULT_OUTPUT := "res://assets/art/review/player_animation_state_matrix.png"
const VIEW_SIZE := Vector2i(1920, 1080)
const COLUMNS := 4
const ROWS := 3
const CELL_SIZE := Vector2i(480, 360)
const DISPLAY_SCALE := 0.48
const PLAYER_STATES := [
	{"id":"idle", "title":"IDLE  ·  대기", "state":"idle", "facing":1, "kind":"idle", "source":"승인 원화 · v8 정지 1장", "timing":"manifest 0.800 s · 반복 프레임 아님"},
	{"id":"run", "title":"RUN  ·  달리기", "state":"walk", "facing":1, "kind":"run", "source":"v8 정지 원화 + 절차적 보폭", "timing":"임시 transform 단계 · 0.120 s 주기"},
	{"id":"turn", "title":"TURN  ·  좌향 전환", "state":"idle", "facing":-1, "kind":"turn", "source":"idle 원화 좌우 flip · 전용 turn clip 없음", "timing":"별도 turn 시간/프레임 없음"},
	{"id":"jump_rise", "title":"JUMP  ·  상승", "state":"jump_rise", "facing":1, "kind":"rise", "source":"v8 정지 원화 + 절차적 기울기", "timing":"임시 상태 0.160 s · 물리가 실제 점프 시간 결정"},
	{"id":"jump_fall", "title":"JUMP  ·  하강", "state":"jump_fall", "facing":-1, "kind":"fall", "source":"v8 정지 원화 + 절차적 기울기", "timing":"임시 상태 0.160 s · 발 기준은 지면 anchor"},
	{"id":"hit", "title":"HIT  ·  피격", "state":"hit", "facing":-1, "kind":"hit", "source":"v8 정지 원화 + knockback/flash 변형", "timing":"임시 상태 0.120 s · hitstun은 전투 데이터"},
	{"id":"attack1", "title":"ATTACK 1  ·  접촉", "state":"attack1_contact", "facing":1, "kind":"attack1", "source":"승인 원화 · attack1 contact 1장", "timing":"hitbox 동기 0.105 s · 좌우 root flip"},
	{"id":"attack2", "title":"ATTACK 2  ·  접촉", "state":"attack2_contact", "facing":-1, "kind":"attack2", "source":"승인 원화 · attack2 contact 1장", "timing":"hitbox 동기 0.120 s · 앞 42%는 임시 연결"},
	{"id":"attack3", "title":"ATTACK 3  ·  접촉", "state":"attack3_contact", "facing":1, "kind":"attack3", "source":"승인 원화 · attack3 contact 1장", "timing":"hitbox 동기 0.140 s · 좌우 root flip"},
	{"id":"num4", "title":"NUM4  ·  전방 돌진 스킬", "state":"skill1_contact", "facing":1, "kind":"skill1", "source":"v8 원화 + 절차적 스킬 포즈 · 전용 원화 미구현", "timing":"0.160 / 0.120 / 0.420 s · cooldown 1.350 s"},
	{"id":"num5", "title":"NUM5  ·  주변 범위 스킬", "state":"skill2_contact", "facing":-1, "kind":"skill2", "source":"v8 원화 + 절차적 스킬 포즈 · 전용 원화 미구현", "timing":"0.220 / 0.180 / 0.550 s · cooldown 1.800 s"},
	{"id":"ko", "title":"KO  ·  전투 불능", "state":"ko", "facing":-1, "kind":"ko", "source":"v8 정지 원화 + 회색/lean 변형", "timing":"임시 변형 · 정지 유지 · hitbox 중단"},
]

var _board: Control
var _player: CharacterBody2D
var _art: Sprite2D
var _animator: Node
var _image: Image

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("Window Viewport 렌더링이 필요합니다. headless 캡처는 검수 증거가 아닙니다.")
		return
	var args := OS.get_cmdline_user_args()
	if args.size() > 1 or (not args.is_empty() and args[0].begins_with("-")):
		_fail("사용법: capture_player_animation_state_matrix [output.png]")
		return
	var output_path := DEFAULT_OUTPUT if args.is_empty() else args[0]
	root.size = VIEW_SIZE
	_board = Control.new()
	_board.name = "PlayerAnimationStateMatrixBoard"
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_board)
	_build_board()
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		_fail("플레이어 장면을 열 수 없습니다.")
		return
	_player = packed.instantiate() as CharacterBody2D
	_player.name = "PlayerUnderReview"
	_player.set_physics_process(false)
	_player.set_process(false)
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = false
	_art = _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_animator = _player.get_node_or_null("VisualAnimator")
	if _art == null or _art.texture == null or _animator == null:
		_fail("PlayerArt 또는 VisualAnimator를 찾지 못했습니다.")
		return
	root.add_child(_player)
	await process_frame
	_player.set_physics_process(false)
	_player.set_process(false)
	var active_camera := _player.get_node_or_null("Camera2D") as Camera2D
	if active_camera != null:
		active_camera.position = Vector2(960.0, 540.0)
		active_camera.zoom = Vector2.ONE
		active_camera.enabled = true
		active_camera.make_current()
	for _frame in range(4):
		await process_frame
		await RenderingServer.frame_post_draw
	for index in range(PLAYER_STATES.size()):
		var spec: Dictionary = PLAYER_STATES[index]
		_apply_state(spec, index)
		for _frame in range(10):
			await process_frame
			_animator.call("_process", 1.0 / 60.0)
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		if frame == null or frame.is_empty() or frame.get_size() != VIEW_SIZE:
			_fail("상태 %s Window Viewport 화면 캡처에 실패했습니다." % spec.id)
			return
		_image.blit_rect(frame, _cell_rect(index), _cell_rect(index).position)
		print("player-state-matrix: Window 캡처 %s / %s / %s" % [spec.id, _animator.call("get_animation_state"), _animator.call("get_pose_art_status")])
	var abs_output := ProjectSettings.globalize_path(output_path)
	var dir_error := DirAccess.make_dir_recursive_absolute(abs_output.get_base_dir())
	if dir_error != OK:
		_fail("출력 폴더를 만들지 못했습니다: %s (%d)" % [abs_output.get_base_dir(), dir_error])
		return
	var save_error := _image.save_png(abs_output)
	if save_error != OK:
		_fail("비교판 PNG 저장 실패: %s (%d)" % [abs_output, save_error])
		return
	var saved := Image.new()
	if saved.load(abs_output) != OK or saved.get_size() != VIEW_SIZE:
		_fail("저장 PNG의 재로드 또는 크기 확인에 실패했습니다.")
		return
	print("player-state-matrix: saved %dx%d real Window Viewport captures to %s" % [VIEW_SIZE.x, VIEW_SIZE.y, abs_output])
	quit(0)

func _build_board() -> void:
	_image = Image.create(VIEW_SIZE.x, VIEW_SIZE.y, false, Image.FORMAT_RGBA8)
	_image.fill(Color("#101a20"))
	for index in range(PLAYER_STATES.size()):
		var cell := _cell_rect(index)
		var bg := ColorRect.new()
		bg.position = Vector2(cell.position)
		bg.size = Vector2(cell.size)
		bg.color = Color("#19282c") if index % 2 == 0 else Color("#203034")
		bg.z_index = -20
		_board.add_child(bg)
		var floor := ColorRect.new()
		floor.position = Vector2(cell.position.x + 18, cell.end.y - 28)
		floor.size = Vector2(cell.size.x - 36, 2)
		floor.color = Color("#d5bb78")
		_board.add_child(floor)
		var baseline := Label.new()
		baseline.text = "지면 / 기본 발 anchor 기준선"
		baseline.position = Vector2(cell.position.x + 22, cell.end.y - 18)
		baseline.add_theme_font_size_override("font_size", 12)
		baseline.add_theme_color_override("font_color", Color("#dfcc9b"))
		_board.add_child(baseline)
		var spec: Dictionary = PLAYER_STATES[index]
		_label(str(spec.title), Vector2(cell.position) + Vector2(16, 12), 20, Color.WHITE)
		_label(str(spec.source), Vector2(cell.position) + Vector2(18, 40), 13, Color("#f1d997"))
		_label(str(spec.timing), Vector2(cell.position) + Vector2(18, 61), 12, Color("#c4d3d2"))
		var border := ReferenceRect.new()
		border.position = Vector2(cell.position)
		border.size = Vector2(cell.size)
		border.border_color = Color("#91a19b")
		border.border_width = 1.0
		_board.add_child(border)

func _label(value: String, at: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	_board.add_child(label)

func _apply_state(spec: Dictionary, index: int) -> void:
	_player.velocity = Vector2.ZERO
	_player.set("is_ko", false)
	_player.set("is_jumping", false)
	_player.set("jump_vertical_velocity", 0.0)
	_player.set("jump_height_offset", 0.0)
	_player.set("attack_stage", 0)
	_player.set("attack_phase", "idle")
	_player.set("attack_phase_remaining", 0.0)
	_player.set("skill_id", 0)
	_player.set("skill_phase", "idle")
	_player.set("skill_phase_remaining", 0.0)
	_player.set("hitstun_remaining", 0.0)
	_player.set("hit_flash_remaining", 0.0)
	(_player.get_node("VisualRoot/AttackFlash") as Polygon2D).visible = false
	_player.get_node("Hitboxes/Skill1Hitbox").monitoring = false
	_player.get_node("Hitboxes/Skill2Hitbox").monitoring = false
	for stage in range(1, 4):
		_player.get_node("Hitboxes/Hitbox%d" % stage).monitoring = false
	var visual_root := _player.get_node("VisualRoot") as Node2D
	visual_root.position.y = -18.0
	visual_root.scale = Vector2(DISPLAY_SCALE * float(spec.facing), DISPLAY_SCALE)
	_art.modulate = Color.WHITE
	var ground_y := _cell_rect(index).end.y - 28.0
	_player.position = Vector2(_cell_rect(index).position.x + CELL_SIZE.x * 0.5, ground_y)
	match str(spec.kind):
		"run":
			_player.velocity = Vector2(280.0, 0.0)
		"rise":
			_player.set("is_jumping", true)
			_player.set("jump_vertical_velocity", -220.0)
			_player.set("jump_height_offset", 55.0)
			visual_root.position.y -= 55.0
		"fall":
			_player.set("is_jumping", true)
			_player.set("jump_vertical_velocity", 160.0)
			_player.set("jump_height_offset", 55.0)
			visual_root.position.y -= 55.0
		"hit":
			_player.velocity = Vector2(-80.0, 0.0)
			_player.set("hitstun_remaining", 0.2)
			_player.set("hit_flash_remaining", 0.08)
			_art.modulate = Color(1.0, 0.42, 0.36, 1.0)
		"attack1", "attack2", "attack3":
			var stage := int(str(spec.kind).trim_prefix("attack"))
			var active: float = [0.105, 0.12, 0.14][stage - 1]
			_player.set("attack_stage", stage)
			_player.set("attack_phase", "active")
			_player.set("attack_phase_remaining", active * 0.5)
			_player.get_node("Hitboxes/Hitbox%d" % stage).monitoring = true
		"skill1", "skill2":
			var skill_id := 1 if spec.kind == "skill1" else 2
			_player.set("skill_id", skill_id)
			_player.set("skill_phase", "active")
			_player.set("skill_phase_remaining", [0.12, 0.18][skill_id - 1] * 0.5)
			_player.get_node("Hitboxes/Skill%dHitbox" % skill_id).monitoring = true
			var flash := _player.get_node("VisualRoot/AttackFlash") as Polygon2D
			flash.visible = true
			flash.color = Color("#59e4f0") if skill_id == 1 else Color("#dd74f2")
			flash.scale = Vector2(1.8, 1.5) if skill_id == 1 else Vector2(2.0, 2.0)
		"ko":
			_player.set("is_ko", true)
			_art.modulate = Color(0.62, 0.62, 0.62, 0.78)

func _cell_rect(index: int) -> Rect2i:
	return Rect2i(Vector2i((index % COLUMNS) * CELL_SIZE.x, (index / COLUMNS) * CELL_SIZE.y), CELL_SIZE)

func _fail(message: String) -> void:
	push_error("player-animation-state-matrix: " + message)
	quit(1)
