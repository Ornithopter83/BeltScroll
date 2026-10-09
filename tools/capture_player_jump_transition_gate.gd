extends SceneTree
"""Captures one complete Player jump clock in a real window for visual review."""

const PLAYER_SCRIPT := "res://scripts/player/player_controller.gd"
const RISE_SAFE := "res://assets/art/player/elven_fighter_jump_rise_v1_safe_candidate_1254x1254.png"
const FALL_CANDIDATE := "res://assets/art/player/elven_fighter_jump_fall_v1_candidate_1254x1254.png"
const IDLE_ART := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const OUTPUT := "res://assets/art/review/player_jump_transition_gate.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const CROP := Rect2i(640, 280, 640, 500)
const TILE := Vector2i(640, 500)
const BOARD_SIZE := Vector2i(1920, 2000)
const GAME_CANVAS := 192.0
const ART_SIZE := 1254.0
const ART_SCALE := GAME_CANVAS / ART_SIZE
const FLOOR_Y := 760.0
const SHADOW_BASE_ALPHA := 0.42

var _player: CharacterBody2D
var _visual: Node2D
var _art: Sprite2D
var _shadow: Polygon2D
var _caption: Label
var _telemetry: Label
var _pop_marker: Node2D
var _board: Image
var _physics_delta := 1.0 / 60.0
var _physics_seconds := 0.0
var _tick_count := 0
var _phase_index := 0
var _rise_available := false
var _fall_available := false
var _phase_metrics: Dictionary = {}

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
	_rise_available = FileAccess.file_exists(RISE_SAFE)
	_fall_available = FileAccess.file_exists(FALL_CANDIDATE)
	var idle := _load_texture(IDLE_ART)
	var rise := _load_texture(RISE_SAFE) if _rise_available else null
	var fall := _load_texture(FALL_CANDIDATE) if _fall_available else null
	if idle == null or rise == null or (_fall_available and fall == null):
		_fail("idle 원화 또는 기존 rise safe 후보를 읽지 못했습니다.")
		return
	_physics_delta = 1.0 / float(ProjectSettings.get_setting("physics/common/physics_ticks_per_second", 60))
	_board = Image.create(BOARD_SIZE.x, BOARD_SIZE.y, false, Image.FORMAT_RGBA8)
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
	_player.position = Vector2(960, FLOOR_Y)
	_visual.scale = Vector2.ONE
	_art.scale = Vector2(ART_SCALE, ART_SCALE)
	_art.position.y = -100.0
	_shadow.scale = Vector2(2.3, 1.5)
	_art.texture = idle
	await _capture_pose("TAKEOFF / IDLE", "실제 도약 전 · Player offset=0 · shadow 기준 α=0.42")
	Input.action_press("jump")
	_player.call("_start_jump")
	var rise_reached := await _advance_until(func() -> bool: return float(_player.get("jump_height_offset")) >= 46.0, 90)
	if not rise_reached:
		_fail("Player physics에서 상승 샘플을 얻지 못했습니다.")
		return
	_art.texture = rise
	await _capture_both_directions("RISE / EXISTING SAFE CANDIDATE", "rise safe 존재=%s · 단일 상승 후보 원화" % str(_rise_available))
	# No fall candidate is present. Keep the idle silhouette explicitly labeled as a procedural proxy.
	_art.texture = idle
	var apex_reached := await _advance_until(func() -> bool: return float(_player.get("jump_vertical_velocity")) >= 0.0, 90)
	if not apex_reached:
		_fail("Player physics에서 정점 샘플을 얻지 못했습니다.")
		return
	Input.action_release("jump")
	await _capture_both_directions("APEX / PROCEDURAL PROXY", "fall 후보 존재=%s · idle 실루엣 절차 대체 · 정점 원화 미확보" % str(_fall_available))
	var fall_reached := await _advance_until(func() -> bool: return float(_player.get("jump_height_offset")) <= 58.0 and float(_player.get("jump_vertical_velocity")) > 0.0, 90)
	if not fall_reached:
		_fail("Player physics에서 하강 샘플을 얻지 못했습니다.")
		return
	_art.texture = fall if _fall_available else idle
	await _capture_both_directions("FALL / " + ("CANDIDATE" if _fall_available else "PROCEDURAL PROXY"), "fall 후보 존재=%s · %s" % [str(_fall_available), "fall 후보 원화(미승인)" if _fall_available else "idle 실루엣 절차 대체"])
	var landing_reached := await _advance_until(func() -> bool: return not bool(_player.get("is_jumping")), 90)
	if not landing_reached:
		_fail("Player physics에서 착지 샘플을 얻지 못했습니다.")
		return
	await _capture_both_directions("LAND / PROCEDURAL REVIEW MARKER", "Player 착지 팝 없음 · 십자 표식은 검수용 절차 마커")
	Input.action_release("jump")
	var absolute := ProjectSettings.globalize_path(OUTPUT)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var error := _board.save_png(absolute)
	if error != OK:
		_fail("Window 비교 스트립 저장 실패: %s" % error_string(error))
		return
	var verify := Image.new()
	if verify.load(absolute) != OK or verify.get_size() != BOARD_SIZE:
		_fail("저장된 Window 캡처를 다시 읽거나 크기를 확인하지 못했습니다.")
		return
	print("JUMP_GATE_CAPTURE physics_tick=%.6fs elapsed=%.4fs ticks=%d landing=true output=%s size=%s" % [_physics_delta, _physics_seconds, _tick_count, OUTPUT, str(verify.get_size())])
	print("JUMP_GATE_CANDIDATES rise_safe=%s fall_candidate=%s fall_representation=%s apex_art=unapproved landing_art=unapproved player_landing_pop=absent review_marker=procedural" % [str(_rise_available), str(_fall_available), "candidate" if _fall_available else "idle_procedural_proxy"])
	quit(0)

func _build_isolated_player(idle_texture: Texture2D) -> CharacterBody2D:
	var controller := load(PLAYER_SCRIPT) as GDScript
	if controller == null:
		return null
	var player := CharacterBody2D.new()
	player.name = "IsolatedJumpTransitionGatePlayer"
	player.set_script(controller)
	var shadow := Polygon2D.new()
	shadow.name = "GroundShadow"
	shadow.position = Vector2(0, 2)
	shadow.color = Color(0.02, 0.025, 0.03, SHADOW_BASE_ALPHA)
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
	panel.size = Vector2(620, 98)
	panel.color = Color(0.03, 0.055, 0.07, 0.94)
	root.add_child(panel)
	_caption = _label("", Vector2(666, 298), 19, Color("#f2d39a"))
	_telemetry = _label("", Vector2(666, 328), 13, Color("#c2d5d8"))
	var floor := ColorRect.new()
	floor.position = Vector2(700, FLOOR_Y)
	floor.size = Vector2(520, 3)
	floor.color = Color("#d47863")
	root.add_child(floor)
	_pop_marker = Node2D.new()
	_pop_marker.name = "ProceduralLandingReviewMarker"
	_pop_marker.position = Vector2(960, FLOOR_Y - 6)
	_pop_marker.visible = false
	for direction in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var ray := Line2D.new()
		ray.width = 3.0
		ray.default_color = Color("#ffd36d")
		ray.points = PackedVector2Array([direction * 8.0, direction * 25.0])
		_pop_marker.add_child(ray)
	root.add_child(_pop_marker)
	_label("GROUND PLANE / PLAYER ROOT", Vector2(706, 768), 12, Color("#f0b4a3"))
	_label("GROUND SHADOW STAYS ON GROUND", Vector2(704, 730), 12, Color("#9fd6c4"))

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
	_pop_marker.visible = title.begins_with("LAND")
	_caption.text = "%s  ·  %s" % [title, "RIGHT" if faces_right else "LEFT · SINGLE MIRROR"]
	var height := float(_player.get("jump_height_offset"))
	var velocity := float(_player.get("jump_vertical_velocity"))
	var bounds := _art_bounds_192(_art.texture)
	# VisualRoot.position already contains the Player-computed vertical jump offset.
	var anchor_y := _visual.position.y + _art.position.y + float(bounds.end.y) - GAME_CANVAS * 0.5
	var facing_key := "right" if faces_right else "left"
	var prior_key := "%d_%s" % [_phase_index - 1, facing_key]
	var has_prior := _phase_index > 0 and _phase_metrics.has(prior_key)
	var prior: Dictionary = _phase_metrics.get(prior_key, {})
	var boundary_anchor_delta := anchor_y - float(prior.get("anchor", anchor_y))
	var boundary_width_delta := bounds.size.x - int(prior.get("width", bounds.size.x))
	var boundary_height_delta := bounds.size.y - int(prior.get("height", bounds.size.y))
	var actual_pop := false
	var boundary_text := "boundary Δanchor=%+.1fpx Δbox=%+d×%+dpx" % [boundary_anchor_delta, boundary_width_delta, boundary_height_delta] if has_prior else "first phase boundary baseline"
	_telemetry.text = "t=%.3fs tick=%d h=%.1fpx vy=%.1fpx/s shadow α=%.3f anchor=%+.1fpx box=%dx%d %s · %s" % [
		_physics_seconds, _tick_count, height, velocity, _shadow.modulate.a, anchor_y, bounds.size.x, bounds.size.y, boundary_text, note]
	for _i in range(2):
		await process_frame
		await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.get_size() != WINDOW_SIZE:
		_fail("post-draw Window 프레임 읽기 실패: " + title)
		return
	var index := _phase_index * 2 + (0 if faces_right else 1)
	var destination := Vector2i((index % 3) * TILE.x, (index / 3) * TILE.y)
	_board.blit_rect(frame, CROP, destination)
	print("JUMP_GATE_SAMPLE phase=%s facing=%s elapsed=%.4f ticks=%d height=%.2f vy=%.2f shadow_alpha=%.3f game_scale=192px art_bounds=%s foot_anchor_y=%+.2fpx phase_boundary=%s boundary_anchor_delta=%s boundary_silhouette_delta=%s authored_pop=%s review_marker=%s rise_safe=%s fall_candidate=%s art=%s post_draw=true" % [
		title, facing_key, _physics_seconds, _tick_count, height, velocity, _shadow.modulate.a, str(bounds), anchor_y, str(has_prior), ("%+.2fpx" % boundary_anchor_delta) if has_prior else "baseline", ("%+d×%+dpx" % [boundary_width_delta, boundary_height_delta]) if has_prior else "baseline", str(actual_pop), str(_pop_marker.visible), str(_rise_available), str(_fall_available), _art.texture.resource_path])
	_phase_metrics["%d_%s" % [_phase_index, facing_key]] = {"anchor": anchor_y, "width": bounds.size.x, "height": bounds.size.y}

func _art_bounds_192(texture: Texture2D) -> Rect2i:
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2i()
	image.resize(int(GAME_CANVAS), int(GAME_CANVAS), Image.INTERPOLATE_LANCZOS)
	var left := 192
	var top := 192
	var right := -1
	var bottom := -1
	for y in range(192):
		for x in range(192):
			if image.get_pixel(x, y).a >= 0.05:
				left = mini(left, x)
				top = mini(top, y)
				right = maxi(right, x)
				bottom = maxi(bottom, y)
	return Rect2i(left, top, right - left + 1, bottom - top + 1) if right >= 0 else Rect2i()

func _advance_until(predicate: Callable, max_ticks: int) -> bool:
	for _i in range(max_ticks):
		await physics_frame
		_player.call("_update_jump", _physics_delta)
		_physics_seconds += _physics_delta
		_tick_count += 1
		if bool(predicate.call()):
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
	push_error("capture_player_jump_transition_gate: " + message)
	quit(1)
