extends SceneTree
"""Isolated real-Window review of the safe rise art against the Player jump clock."""

const PLAYER_SCRIPT := "res://scripts/player/player_controller.gd"
const JUMP_ART := "res://assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png"
const IDLE_ART := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/review/player_jump_motion_strip.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const TILE := Vector2i(640, 500)
const OUTPUT_SIZE := Vector2i(1920, 2000)
const CROP := Rect2i(640, 280, 640, 500)
var _player: CharacterBody2D
var _visual: Node2D
var _art: Sprite2D
var _shadow: Polygon2D
var _caption: Label
var _telemetry: Label
var _landing_pop: Node2D
var _board: Image
var _failures: Array[String] = []
var _physics_delta := 1.0 / 60.0
var _physics_seconds := 0.0
var _tick_count := 0
var _phase_index := 0

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Godot Window가 필요합니다. headless 렌더링은 캡처 근거로 사용하지 않습니다.")
		return
	root.mode = Window.MODE_WINDOWED
	root.size = WINDOW_SIZE
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	DisplayServer.window_set_size(WINDOW_SIZE)
	for _i in range(3):
		await process_frame
	if root.size != WINDOW_SIZE or DisplayServer.window_get_size() != WINDOW_SIZE:
		_fail("1920×1080 Window 확인 실패: viewport=%s window=%s" % [str(root.size), str(DisplayServer.window_get_size())])
		return
	var idle := _load_texture(IDLE_ART)
	var rise := _load_texture(JUMP_ART)
	if idle == null or rise == null:
		_fail("idle 승인 원화 또는 jump rise safe 후보를 읽지 못했습니다.")
		return
	_physics_delta = 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	_board = Image.create(OUTPUT_SIZE.x, OUTPUT_SIZE.y, false, Image.FORMAT_RGBA8)
	_board.fill(Color("#111820"))
	_build_stage()
	_player = _build_isolated_player(idle)
	if _player == null:
		_fail("격리용 PlayerController rig를 준비하지 못했습니다.")
		return
	root.add_child(_player)
	await process_frame
	_player.set_physics_process(false)
	_player.set_process(false)
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = false
	_visual = _player.get_node("VisualRoot") as Node2D
	_art = _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	_shadow = _player.get_node("GroundShadow") as Polygon2D
	if _visual == null or _art == null or _shadow == null:
		_fail("Player visual root, art 또는 실제 GroundShadow가 없습니다.")
		return
	_player.position = Vector2(960, 760)
	_visual.scale = Vector2.ONE
	_art.scale = Vector2(0.20, 0.20)
	_art.position.y = -100.0
	_shadow.scale = Vector2(2.3, 1.5)
	_shadow.color = Color("#394b50")
	_art.texture = idle
	await _capture_pose("TAKEOFF / APPROVED IDLE", "shadow α=0.42 · no jump offset")
	_art.texture = rise
	Input.action_press("jump")
	_player.call("_start_jump")
	var rise_reached := await _advance_until(func() -> bool: return float(_player.get("jump_height_offset")) >= 46.0, 90)
	if not rise_reached:
		_fail("Player physics에서 상승 샘플을 얻지 못했습니다.")
		return
	await _capture_both_directions("RISE / SAFE CANDIDATE ART", "art fixed · rising offset from Player physics")
	# Rise is the only jump drawing. Later poses deliberately switch to an idle
	# silhouette proxy so the missing apex/fall art cannot read as completed art.
	_art.texture = idle
	var apex_reached := await _advance_until(func() -> bool: return float(_player.get("jump_vertical_velocity")) >= 0.0, 90)
	if not apex_reached:
		_fail("Player physics에서 정점 샘플을 얻지 못했습니다.")
		return
	Input.action_release("jump")
	await _capture_both_directions("APEX / PROCEDURAL PROXY", "idle art proxy · apex drawing not implemented")
	var fall_reached := await _advance_until(func() -> bool: return float(_player.get("jump_height_offset")) <= 58.0 and float(_player.get("jump_vertical_velocity")) > 0.0, 90)
	if not fall_reached:
		_fail("Player physics에서 하강 샘플을 얻지 못했습니다.")
		return
	await _capture_both_directions("FALL / PROCEDURAL PROXY", "idle art proxy · fall drawing not implemented")
	var landing_reached := await _advance_until(func() -> bool: return not bool(_player.get("is_jumping")), 90)
	if not landing_reached:
		_fail("Player physics에서 착지 샘플을 얻지 못했습니다.")
		return
	await _capture_both_directions("LAND / PROCEDURAL POP", "idle art proxy · no authored landing pop")
	if not _failures.is_empty():
		return
	var absolute := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := _board.save_png(absolute)
	if error != OK:
		_fail("Window 비교 스트립 저장 실패: %s" % error_string(error))
		return
	var verify := Image.new()
	if verify.load(absolute) != OK or verify.get_size() != OUTPUT_SIZE:
		_fail("저장된 Window 캡처를 다시 읽거나 크기를 확인하지 못했습니다.")
		return
	print("JUMP_MOTION_CAPTURE physics_tick=%.6fs elapsed=%.4fs ticks=%d landing=true output=%s size=%s" % [_physics_delta, _physics_seconds, _tick_count, OUTPUT, str(verify.get_size())])
	print("JUMP_MOTION_GATES art=rise_safe_only apex=procedural fall=procedural landing_pop=procedural mirror=visual_root_scale_once ground_shadow=real_Player_node")
	quit(0)

func _build_isolated_player(idle_texture: Texture2D) -> CharacterBody2D:
	var controller := load(PLAYER_SCRIPT) as GDScript
	if controller == null:
		return null
	var player := CharacterBody2D.new()
	player.name = "IsolatedJumpPhysicsPlayer"
	player.set_script(controller)
	var shadow := Polygon2D.new()
	shadow.name = "GroundShadow"
	shadow.position = Vector2(0, 2)
	shadow.color = Color(0.02, 0.025, 0.03, 0.42)
	shadow.polygon = PackedVector2Array([-19, 0, -16, -7, -9, -11, 0, -12, 9, -11, 16, -7, 19, 0, 16, 7, 9, 11, 0, 12, -9, 11, -16, 7])
	player.add_child(shadow)
	var visual := Node2D.new()
	visual.name = "VisualRoot"
	visual.position.y = -18
	player.add_child(visual)
	var sprite := Sprite2D.new()
	sprite.name = "PlayerArt"
	sprite.position.y = -222
	sprite.scale = Vector2(0.4469274, 0.4469274)
	sprite.texture = idle_texture
	visual.add_child(sprite)
	var flash := Polygon2D.new()
	flash.name = "AttackFlash"
	flash.visible = false
	visual.add_child(flash)
	var hitboxes := Node2D.new()
	hitboxes.name = "Hitboxes"
	player.add_child(hitboxes)
	for hitbox_name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		var hitbox := Area2D.new()
		hitbox.name = hitbox_name
		hitbox.monitoring = false
		hitbox.monitorable = false
		hitboxes.add_child(hitbox)
	var camera := Camera2D.new()
	camera.name = "Camera2D"
	camera.enabled = false
	player.add_child(camera)
	return player

func _build_stage() -> void:
	var background := ColorRect.new()
	background.position = Vector2(CROP.position)
	background.size = Vector2(CROP.size)
	background.color = Color("#1a2730")
	root.add_child(background)
	var panel := ColorRect.new()
	panel.position = Vector2(650, 290)
	panel.size = Vector2(620, 88)
	panel.color = Color(0.03, 0.055, 0.07, 0.94)
	root.add_child(panel)
	_caption = _label("", Vector2(666, 299), 21, Color("#f2d39a"))
	_telemetry = _label("", Vector2(666, 330), 14, Color("#c2d5d8"))
	var floor := ColorRect.new()
	floor.position = Vector2(700, 760)
	floor.size = Vector2(520, 3)
	floor.color = Color("#d47863")
	root.add_child(floor)
	_landing_pop = Node2D.new()
	_landing_pop.name = "ProceduralLandingPop"
	_landing_pop.position = Vector2(960, 754)
	_landing_pop.visible = false
	for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var ray := Line2D.new()
		ray.width = 3.0
		ray.default_color = Color("#ffd36d")
		ray.points = PackedVector2Array([direction * 8.0, direction * 25.0])
		_landing_pop.add_child(ray)
	root.add_child(_landing_pop)
	_label("GROUND PLANE / PLAYER ROOT", Vector2(706, 768), 12, Color("#f0b4a3"))
	_label("GROUND SHADOW IS NOT LIFTED WITH THE SPRITE", Vector2(704, 730), 12, Color("#9fd6c4"))

func _label(value: String, at: Vector2, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.position = at
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	label.size = Vector2(602, 40)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	root.add_child(label)
	return label

func _capture_pose(title: String, note: String) -> void:
	_phase_index = 0
	await _capture_direction(title, note, true)
	await _capture_direction(title, note, false)

func _capture_both_directions(title: String, note: String) -> void:
	_phase_index += 1
	await _capture_direction(title, note, true)
	await _capture_direction(title, note, false)

func _capture_direction(title: String, note: String, faces_right: bool) -> void:
	_visual.scale.x = 1.0 if faces_right else -1.0
	_landing_pop.visible = title.begins_with("LAND")
	_caption.text = "%s  ·  %s" % [title, "RIGHT" if faces_right else "LEFT · SINGLE MIRROR"]
	_telemetry.text = "t=%.3fs  tick=%d  height=%.1fpx  vy=%.1fpx/s  shadow α=%.2f  ·  %s" % [
		_physics_seconds, _tick_count, float(_player.get("jump_height_offset")), float(_player.get("jump_vertical_velocity")), _shadow.modulate.a, note]
	for _i in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.get_size() != WINDOW_SIZE:
		_fail("post-draw Window 프레임 읽기 실패: %s" % title)
		return
	var index := _phase_index * 2 + (0 if faces_right else 1)
	var destination := Vector2i((index % 3) * TILE.x, (index / 3) * TILE.y)
	_board.blit_rect(frame, CROP, destination)
	print("JUMP_SAMPLE phase=%s facing=%s elapsed=%.4f ticks=%d height=%.2f vy=%.2f shadow_alpha=%.3f post_draw=true art=%s" % [title, "right" if faces_right else "left", _physics_seconds, _tick_count, float(_player.get("jump_height_offset")), float(_player.get("jump_vertical_velocity")), _shadow.modulate.a, _art.texture.resource_path])

func _advance_until(predicate: Callable, max_ticks: int) -> bool:
	for _i in range(max_ticks):
		await physics_frame
		_player.call("_update_jump", _physics_delta)
		_physics_seconds += _physics_delta
		_tick_count += 1
		var matched := bool(predicate.call())
		if matched:
			return true
	return false

func _load_texture(path: String) -> Texture2D:
	if not FileAccess.file_exists(path):
		return null
	var image := Image.new()
	if image.load(ProjectSettings.globalize_path(path)) != OK:
		return null
	return ImageTexture.create_from_image(image)

func _fail(message: String) -> void:
	_failures.append(message)
	push_error("capture_player_jump_motion_review: " + message)
	quit(1)
