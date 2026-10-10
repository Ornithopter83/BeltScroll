extends Node2D
"""Standalone F6 review room for authored hand contact and live hit shapes."""

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RECEIVER_SCENE := preload("res://scenes/enemies/forest_raider.tscn")
const MOVE_NAMES := ["기본 1타", "기본 2타", "기본 3타", "Num4 돌진", "Num5 회전"]
const PHASE_NAMES := ["startup", "active", "recovery"]
const BASIC_DURATIONS := [[0.075, 0.105, 0.20], [0.085, 0.12, 0.22], [0.10, 0.14, 0.28]]
const SKILL_DURATIONS := [[0.16, 0.12, 0.42], [0.22, 0.18, 0.55]]
const SYMBOL_HAND := Color("#ffd54f")
const SYMBOL_HITBOX := Color("#ff4dba")
const SYMBOL_RECEIVE := Color("#45e6ff")
const FRAME_STEP := 1.0 / 60.0

var _player: CharacterBody2D
var _dummy: CharacterBody2D
var _status: Label
var _measurement: Label
var _coordinate_status: Label
var _move_index := 0
var _phase_index := 0
var _phase_time := 0.0
var _playing := false
var _looping := true
var _human_pins: Dictionary = {}
var _last_contact_result := "미측정"

func _ready() -> void:
	get_viewport().size = Vector2i(1920, 1080)
	_build_world()
	# The Player re-enables its own physics callback when its script enters the tree.
	# The review timeline owns every phase tick, so disable physics after insertion.
	_player.set_physics_process(false)
	_build_hud()
	_apply_timeline_state()

func _build_world() -> void:
	_player = PLAYER_SCENE.instantiate() as CharacterBody2D
	_player.name = "ContactLabPlayer"
	_player.position = Vector2(790.0, 720.0)
	_player.set("arena_bounds", Rect2(100.0, 620.0, 1700.0, 300.0))
	_player.set_physics_process(false)
	add_child(_player)
	var camera := _player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.enabled = true
		camera.position_smoothing_enabled = false
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = 1920
		camera.limit_bottom = 1080
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	_dummy = RECEIVER_SCENE.instantiate() as CharacterBody2D
	_dummy.name = "ContactLabReceiveTarget"
	_dummy.position = Vector2(860.0, 720.0)
	_dummy.set("arena_bounds", Rect2(100.0, 620.0, 1700.0, 300.0))
	_dummy.set("notice_range", 0.0)
	_dummy.set_physics_process(false)
	add_child(_dummy)

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var panel := PanelContainer.new()
	panel.position = Vector2(24.0, 22.0)
	panel.size = Vector2(1030.0, 226.0)
	layer.add_child(panel)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 7)
	panel.add_child(rows)
	var title := _label(rows, "M6R · 공격 접촉점 검수장", 25, Color.WHITE)
	_status = _label(rows, "", 17, Color("#e8f3fa"))
	_measurement = _label(rows, "", 16, Color("#ffd68a"))
	_coordinate_status = _label(rows, "", 15, Color("#c7d4df"))
	_label(rows, "←/→ 기술 · ↑/↓ 단계(startup/active/recovery) · Space 재생/정지 · . 한 단계 · L 반복 · F 좌우 반전 · C 카메라 이동", 14, Color("#c7d4df"))
	_label(rows, "마우스로 실제 주먹 끝을 클릭해 사람 확인 기준점을 기록 · T 접촉 검사 · G 주먹 밖 검사 · F10 실제 충돌 윤곽", 14, Color("#c7d4df"))
	_label(rows, "기호: ◆ 손 기준점(사람 확인)   ✚ 실제 공격 Shape 중심   ○ 적 ReceiveArea   |   점 좌표가 없으면 UNVERIFIED", 14, Color("#c7d4df"))
	_refresh_hud()

func _label(parent: Node, value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	match event.keycode:
		KEY_LEFT:
			_move_index = posmod(_move_index - 1, MOVE_NAMES.size())
			_phase_time = 0.0
			_apply_timeline_state()
		KEY_RIGHT:
			_move_index = posmod(_move_index + 1, MOVE_NAMES.size())
			_phase_time = 0.0
			_apply_timeline_state()
		KEY_UP, KEY_DOWN:
			_phase_index = posmod(_phase_index + (-1 if event.keycode == KEY_UP else 1), PHASE_NAMES.size())
			_phase_time = 0.0
			_apply_timeline_state()
		KEY_SPACE:
			_playing = not _playing
		KEY_PERIOD:
			_step_timeline(FRAME_STEP)
		KEY_COMMA:
			_step_timeline(-FRAME_STEP)
		KEY_L:
			_looping = not _looping
		KEY_F:
			_player.set("facing_direction", Vector2.LEFT if _player.get("facing_direction").x > 0.0 else Vector2.RIGHT)
			_player.get_node("VisualRoot").scale.x = -1.0 if _player.get("facing_direction").x < 0.0 else 1.0
			_apply_timeline_state()
		KEY_C:
			var camera := _player.get_node("Camera2D") as Camera2D
			camera.offset = Vector2(90.0, -36.0) if camera.offset == Vector2.ZERO else Vector2.ZERO
		KEY_T:
			_measure_contact()
		KEY_G:
			_measure_outside_punch()
		KEY_R:
			_reset_lab()
		KEY_BACKSPACE:
			_human_pins.clear()
	_apply_timeline_state()
	get_viewport().set_input_as_handled()
	_refresh_hud()

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.button_index != MOUSE_BUTTON_LEFT:
		return
	var sprite := _visible_attack_sprite()
	if sprite == null or sprite.texture == null:
		_last_contact_result = "UNVERIFIED · 표시 Sprite/텍스처를 찾을 수 없음"
		_refresh_hud()
		return
	var local_point: Vector2 = sprite.get_global_transform_with_canvas().affine_inverse() * event.position
	var texture_point := local_point + sprite.texture.get_size() * 0.5
	if sprite.flip_h:
		texture_point.x = sprite.texture.get_width() - texture_point.x
	if not Rect2(Vector2.ZERO, sprite.texture.get_size()).has_point(texture_point):
		return
	var pin_key := _pin_key()
	_human_pins[pin_key] = {"texture": sprite.texture.resource_path, "pixel": texture_point, "frame_size": sprite.texture.get_size()}
	_last_contact_result = "사람 확인 좌표 저장: 원화 픽셀 (%.1f, %.1f)" % [texture_point.x, texture_point.y]
	queue_redraw()
	_refresh_hud()
	get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if _playing:
		_step_timeline(delta)
	queue_redraw()

func _step_timeline(delta: float) -> void:
	var duration := _phase_duration()
	_phase_time += delta
	if _phase_time >= duration:
		if _looping:
			_phase_time = fposmod(_phase_time, duration)
		else:
			_phase_time = duration
			_playing = false
	elif _phase_time < 0.0:
		_phase_time = duration if _looping else 0.0
	_apply_timeline_state()
	_refresh_hud()

func _apply_timeline_state() -> void:
	if not is_instance_valid(_player):
		return
	var phase: String = PHASE_NAMES[_phase_index]
	if _move_index < 3:
		_player.set("attack_stage", _move_index + 1)
		_player.set("attack_phase", phase)
		_player.set("attack_phase_remaining", maxf(0.0001, _phase_duration() - _phase_time))
		_player.set("attack_elapsed", _phase_time)
		_player.set("attack_progress", _phase_time / _phase_duration())
		_player.set("skill_id", 0)
		_player.set("skill_phase", "idle")
		_player.call("_set_stage_hitbox", 1, false)
		_player.call("_set_skill_hitboxes", false)
		(_player.get_node("VisualRoot/AttackFlash") as CanvasItem).visible = false
	else:
		var skill_id := _move_index - 2
		_player.set("attack_stage", 0)
		_player.set("attack_phase", "idle")
		_player.call("_set_stage_hitbox", 1, false)
		_player.set("skill_id", skill_id)
		_player.set("skill_phase", phase)
		_player.set("skill_phase_remaining", maxf(0.0001, _phase_duration() - _phase_time))
		_player.set("skill_cooldowns", [0.0, 0.0])
	var animator := _player.get_node_or_null("VisualAnimator")
	if animator != null:
		animator.call("_process", 0.0)
	if _move_index < 3:
		_player.call("_set_attack_stage_visual", _move_index + 1)
		_player.call("_set_stage_hitbox", _move_index + 1, phase == "active")
	else:
		_player.call("_set_skill_hitbox_transform")
		_player.call("_set_skill_hitboxes", phase == "active")
	_refresh_hud()

func _phase_duration() -> float:
	if _move_index < 3:
		return BASIC_DURATIONS[_move_index][_phase_index]
	return SKILL_DURATIONS[_move_index - 3][_phase_index]

func _visible_attack_sprite() -> Sprite2D:
	var blender := _player.get_node_or_null("VisualRoot/PoseBlender")
	if blender != null:
		for node in blender.find_children("PoseSprite*", "Sprite2D", false, false):
			if node is Sprite2D and (node as Sprite2D).visible:
				return node as Sprite2D
	var art := _player.get_node_or_null("VisualRoot/PlayerArt") as Sprite2D
	return art if art != null and art.visible else null

func _active_shape() -> CollisionShape2D:
	var hitbox_name := "Hitbox%d" % (_move_index + 1) if _move_index < 3 else ("Skill1Hitbox" if _move_index == 3 else "Skill2Hitbox")
	return _player.get_node_or_null("Hitboxes/%s/CollisionShape2D" % hitbox_name) as CollisionShape2D

func _active_area() -> Area2D:
	var shape := _active_shape()
	return shape.get_parent() as Area2D if shape != null else null

func _receive_shape() -> CollisionShape2D:
	return _dummy.get_node_or_null("ReceiveArea/CollisionShape2D") as CollisionShape2D

func _pin_key() -> String:
	return "%d:%d" % [_move_index, _phase_index]

func _current_pin() -> Dictionary:
	return _human_pins.get(_pin_key(), {})

func _computed_pin_world() -> Variant:
	var pin := _current_pin()
	var sprite := _visible_attack_sprite()
	if pin.is_empty() or sprite == null or sprite.texture == null or str(pin.get("texture", "")) != sprite.texture.resource_path:
		return null
	var pixel: Vector2 = pin["pixel"]
	if sprite.flip_h:
		pixel.x = sprite.texture.get_width() - pixel.x
	var local := pixel - sprite.texture.get_size() * 0.5
	return sprite.to_global(local)

func _measure_contact() -> void:
	var hand: Variant = _computed_pin_world()
	var shape := _active_shape()
	var error_text := "UNVERIFIED · 손끝 원화 좌표 확인 필요"
	if hand != null and shape != null:
		var error_px: float = (hand as Vector2).distance_to(shape.global_position)
		var screen_error := _screen_contact_error(hand as Vector2, shape)
		error_text = "%s · 주먹-판정 오차 %.1f world / %.1f screen px" % ["PASS" if error_px <= 24.0 else "FAIL", error_px, screen_error]
	var active_area := _active_area()
	var receive_area := _dummy.get_node_or_null("ReceiveArea") as Area2D
	await get_tree().physics_frame
	var overlapped := active_area != null and receive_area != null and active_area.get_overlapping_areas().has(receive_area)
	var expected_active: bool = PHASE_NAMES[_phase_index] == "active"
	var actual_active := active_area != null and active_area.monitoring
	var timing_result := "PASS" if expected_active == actual_active else "FAIL"
	_last_contact_result = "%s · timing %s (monitoring %s) · 적 ReceiveArea %s" % [error_text, timing_result, "ON" if actual_active else "OFF", "겹침(적중 가능)" if overlapped else "비겹침(미적중)"]
	queue_redraw()
	_refresh_hud()

func _screen_contact_error(hand_world: Vector2, shape: CollisionShape2D) -> float:
	var hand_screen: Vector2 = get_viewport().get_canvas_transform() * hand_world
	var hit_screen: Vector2 = shape.get_global_transform_with_canvas().origin
	return hand_screen.distance_to(hit_screen)

func _measure_outside_punch() -> void:
	var area := _active_area()
	if area == null:
		return
	var target_offset := Vector2(150.0, 0.0) if _player.get("facing_direction").x > 0.0 else Vector2(-150.0, 0.0)
	_dummy.global_position = _player.global_position + target_offset
	_last_contact_result = "주먹 밖 검사 준비 · T 접촉 판정, actual ReceiveArea와 모니터링 확인"
	queue_redraw()
	_refresh_hud()

func _reset_lab() -> void:
	_playing = false
	_phase_time = 0.0
	_player.global_position = Vector2(790.0, 720.0)
	_dummy.global_position = Vector2(860.0, 720.0)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	var camera := _player.get_node("Camera2D") as Camera2D
	camera.offset = Vector2.ZERO
	_apply_timeline_state()

func _refresh_hud() -> void:
	if _status == null:
		return
	var phase: String = PHASE_NAMES[_phase_index]
	var active_area := _active_area()
	var monitor := active_area != null and active_area.monitoring
	_status.text = "%s · %s  |  %.3f / %.3f s  |  %s  |  반복 %s  |  F 좌우 · C 카메라" % [MOVE_NAMES[_move_index], phase, _phase_time, _phase_duration(), "재생" if _playing else "정지", "ON" if _looping else "OFF"]
	var hand: Variant = _computed_pin_world()
	var shape := _active_shape()
	var error_text := "UNVERIFIED · 원화 픽셀 직접 지정 전"
	if hand != null and shape != null:
		error_text = "%.1f world / %.1f screen px · hand=(%.1f, %.1f) · hit=(%.1f, %.1f)" % [(hand as Vector2).distance_to(shape.global_position), _screen_contact_error(hand as Vector2, shape), (hand as Vector2).x, (hand as Vector2).y, shape.global_position.x, shape.global_position.y]
	_measurement.text = "자동 계측: hand transform / 실제 CollisionShape2D 중심 오차 %s · monitoring=%s · 최근 %s" % [error_text, "ON" if monitor else "OFF", _last_contact_result]
	var pin := _current_pin()
	_coordinate_status.text = "사람 확인: %s" % ("%.1f, %.1f px @ %s" % [Vector2(pin.get("pixel", Vector2.ZERO)).x, Vector2(pin.get("pixel", Vector2.ZERO)).y, str(pin.get("texture", "" )).get_file()] if not pin.is_empty() else "UNVERIFIED / 표시 프레임을 클릭해 원화 픽셀 좌표 기록")

func _draw() -> void:
	if not is_instance_valid(_player) or not is_instance_valid(_dummy):
		return
	var hand: Variant = _computed_pin_world()
	if hand != null:
		_draw_diamond(to_local(hand as Vector2), SYMBOL_HAND, 12.0)
	var shape := _active_shape()
	if shape != null:
		var center := to_local(shape.global_position)
		_draw_cross(center, SYMBOL_HITBOX, 10.0)
		_draw_collision_outline(shape, SYMBOL_HITBOX)
	var receive := _receive_shape()
	if receive != null:
		_draw_collision_outline(receive, SYMBOL_RECEIVE)
		_draw_circle_marker(to_local(receive.global_position), SYMBOL_RECEIVE, 8.0)

func _draw_diamond(center: Vector2, color: Color, radius: float) -> void:
	var points := PackedVector2Array([center + Vector2(0, -radius), center + Vector2(radius, 0), center + Vector2(0, radius), center + Vector2(-radius, 0), center + Vector2(0, -radius)])
	draw_polyline(points, color, 3.0, true)

func _draw_cross(center: Vector2, color: Color, radius: float) -> void:
	draw_line(center + Vector2(-radius, 0), center + Vector2(radius, 0), color, 3.0, true)
	draw_line(center + Vector2(0, -radius), center + Vector2(0, radius), color, 3.0, true)

func _draw_circle_marker(center: Vector2, color: Color, radius: float) -> void:
	draw_arc(center, radius, 0.0, TAU, 32, color, 3.0, true)

func _draw_collision_outline(shape_node: CollisionShape2D, color: Color) -> void:
	if shape_node.shape == null:
		return
	var xform := get_global_transform().affine_inverse() * shape_node.global_transform
	var points := PackedVector2Array()
	if shape_node.shape is RectangleShape2D:
		var half: Vector2 = (shape_node.shape as RectangleShape2D).size * 0.5
		for point in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y), Vector2(-half.x, -half.y)]:
			points.append(xform * point)
	elif shape_node.shape is CircleShape2D:
		var circle := shape_node.shape as CircleShape2D
		for index in range(49):
			var angle := TAU * float(index) / 48.0
			points.append(xform * (Vector2(cos(angle), sin(angle)) * circle.radius))
	if points.size() > 1:
		draw_polyline(points, color, 2.5, true)
