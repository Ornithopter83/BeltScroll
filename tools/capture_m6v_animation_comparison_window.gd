extends SceneTree
"""Continuously records production animation states from the main Window scene."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_IMAGE := "res://assets/art/review/m6v_animation_quality_contact_sheet.png"
const OUTPUT_REPORT := "res://docs/review/m6v_animation_visual_acceptance_matrix.md"
const PLAYER_PATH := "YSortActors/Player"
const STEP := 1.0 / 60.0
const COLUMNS := 4
const TILE := Vector2i(320, 360)
const CROP := Rect2i(680, 250, 560, 600)
const ACTOR_NAMES := ["TrainingDummy", "ForestRaider1", "ForestRaider2", "ForestRaider3", "RuinsWardenBoss"]

var _game: Node2D
var _player: CharacterBody2D
var _animator: Node
var _overlay: Node
var _samples: Array[Dictionary] = []
var _timeline_rows := PackedStringArray()
var _capture_sequence := 0
var _visual_seconds := 0.0
var _capture_error := ""
var _segment_elapsed := 0.0
var _segment_walk_phase := -1

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Godot Window 렌더러가 필요합니다. headless 캡처는 증거가 아닙니다.")
		return
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 60
	root.size = Vector2i(1920, 1080)
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("본편 scenes/game/main.tscn을 불러오지 못했습니다.")
		return
	_game = packed.instantiate() as Node2D
	_game.name = "Main"
	root.add_child(_game)
	current_scene = _game
	await process_frame
	_player = _game.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	_overlay = root.get_node_or_null("CombatCollisionOverlay")
	if _player == null or _overlay == null:
		_fail("본편 Player 또는 F10 충돌 오버레이를 찾지 못했습니다.")
		return
	_animator = _player.get_node("VisualAnimator")
	_player.set_physics_process(false)
	_player.set_process(false)
	for name in ACTOR_NAMES:
		var actor := _game.get_node_or_null("YSortActors/" + name)
		if actor != null:
			actor.set_physics_process(false)
			actor.set_process(false)
	_player.global_position = Vector2(960, 780)
	var camera := _player.get_node("Camera2D") as Camera2D
	camera.position_smoothing_enabled = false
	camera.zoom = Vector2.ONE
	camera.make_current()
	var f10_event := InputEventKey.new()
	f10_event.keycode = KEY_F10
	f10_event.pressed = true
	_overlay.call("_input", f10_event)
	if not bool(_overlay.get("enabled")):
		_fail("실제 F10 입력 경로로 충돌 오버레이를 켜지 못했습니다.")
		return
	await _settle(3)
	_timeline_rows.append("sequence,wall_timestamp,visual_seconds,window_frame,physics_frame,segment,state,pose_frame,pose_frame_count,pose_frame_label,body_source,body_source_count,facing,foot_anchor_world,hand_anchor_world,f10_box_screen,f10_monitoring")
	await _capture_baselines()
	await _capture_walk()
	await _capture_jump_and_reactions()
	for stage in [1, 2, 3]:
		for phase in ["startup", "active", "combo_hold", "recovery"]:
			if phase == "combo_hold" and stage == 3:
				await _capture_unavailable("J3 combo_hold", "실제 컨트롤러는 3타에서 combo_hold를 열지 않음")
				continue
			var duration := _attack_duration(stage, phase)
			await _capture_phase("J%d %s" % [stage, phase], "attack", stage, phase, duration, phase == "active")
	for skill_id in [1, 2]:
		for phase in ["startup", "active", "recovery"]:
			await _capture_phase("Num%d %s" % [skill_id + 3, phase], "skill", skill_id, phase, _skill_duration(skill_id, phase), phase == "active")
	await _capture_sheet_and_report()
	if not _capture_error.is_empty():
		_fail(_capture_error)
		return
	print("M6V_CAPTURE_COMPLETE|samples=%d|frames=%d|image=%s|report=%s" % [_samples.size(), _capture_sequence, ProjectSettings.globalize_path(OUTPUT_IMAGE), ProjectSettings.globalize_path(OUTPUT_REPORT)])
	quit(0)

func _capture_baselines() -> void:
	_reset_actor()
	await _segment("정지·우향", "idle", 0.10, 3)
	_reset_actor()
	_set_facing(-1.0)
	await _segment("정지·좌향 반전", "mirror_left", 0.10, 3)
	_reset_actor()
	_set_facing(1.0)
	await _segment("정지·우향 반전 복귀", "mirror_right", 0.10, 3)

func _capture_walk() -> void:
	_reset_actor()
	_player.velocity = Vector2(280, 0)
	for index in range(4):
		var phases := ["left_contact", "left_passing", "right_contact", "right_passing"]
		_segment_walk_phase = index
		_animator.set("_stride_phase", (float(index) + 0.5) * PI * 0.5)
		await _segment("4위상 보행·" + phases[index], "walk", 0.08, 3)
	_segment_walk_phase = -1

func _capture_jump_and_reactions() -> void:
	_reset_actor()
	_player.set("is_jumping", true)
	_player.set("jump_vertical_velocity", -536.66)
	_player.set("jump_height_offset", 74.0)
	_player.get_node("VisualRoot").position.y = -18.0 - 74.0
	await _segment("점프 상승", "jump_rise", 0.14, 3)
	_player.set("jump_vertical_velocity", 180.0)
	await _segment("점프 하강", "jump_fall", 0.14, 3)
	# A real transition edge starts the landing pose timer in VisualAnimator.
	_player.set("is_jumping", false)
	_player.set("jump_height_offset", 0.0)
	_player.get_node("VisualRoot").position.y = -18.0
	_animator.set("_was_jumping", true)
	await _segment("착지", "landing", 0.08, 3)
	_reset_actor()
	_player.velocity = Vector2(-80, 0)
	_player.set("hitstun_remaining", 0.20)
	_player.set("hit_flash_remaining", 0.12)
	await _segment("피격", "hit", 0.12, 3)
	_reset_actor()
	_player.set("is_ko", true)
	for row in [{"label":"KO·비틀림", "duration":0.16}, {"label":"KO·붕괴", "duration":0.40}, {"label":"KO·정착", "duration":0.50}]:
		await _segment(str(row.label), "ko", float(row.duration), 3)

func _capture_phase(label: String, family: String, index: int, phase: String, duration: float, active: bool) -> void:
	_reset_actor()
	if family == "attack":
		_player.set("attack_stage", index)
		_player.set("attack_phase", phase)
		_player.set("attack_phase_remaining", duration)
		_player.set("attack_progress", 0.5 if phase == "active" else 0.0)
		if phase == "combo_hold":
			_player.set("combo_link_remaining", duration)
			_player.set("attack_progress", 1.0)
		var area := _player.get_node("Hitboxes/Hitbox%d" % index) as Area2D
		if active:
			_animator.call("_process", 0.0)
			_player.call("_update_fist_hitbox", area)
			area.monitoring = true
	else:
		_player.set("skill_id", index)
		_player.set("skill_phase", phase)
		_player.set("skill_phase_remaining", duration)
		var area := _player.get_node("Hitboxes/Skill%dHitbox" % index) as Area2D
		if active:
			_animator.call("_process", 0.0)
			_player.call("_update_fist_hitbox", area)
			area.monitoring = true
	var flash := _player.get_node("VisualRoot/AttackFlash") as Polygon2D
	flash.visible = active
	await _segment(label, "%s%d_%s" % [family, index, "contact" if phase == "active" else phase], duration, 3)

func _segment(label: String, forced_state: String, duration: float, sample_limit: int) -> void:
	var total_frames := maxi(1, int(ceil(duration / STEP)))
	_segment_elapsed = 0.0
	var capture_indices: Array[int] = []
	for requested in [0, int(total_frames / 2), total_frames - 1]:
		if not capture_indices.has(requested):
			capture_indices.append(requested)
	for frame_index in range(total_frames):
		if _segment_walk_phase >= 0:
			var walk_rate := TAU * 280.0 / 235.2
			_animator.set("_stride_phase", (float(_segment_walk_phase) + 0.5) * PI * 0.5 - walk_rate * _segment_elapsed)
		if str(_player.get("attack_phase")) != "idle":
			_player.set("attack_phase_remaining", maxf(0.0, float(_player.get("attack_phase_remaining")) - STEP))
		elif str(_player.get("skill_phase")) != "idle":
			_player.set("skill_phase_remaining", maxf(0.0, float(_player.get("skill_phase_remaining")) - STEP))
		_visual_seconds += STEP
		_animator.call("_process", STEP)
		for hitbox_name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
			var area := _player.get_node("Hitboxes/" + hitbox_name) as Area2D
			if area.monitoring:
				_player.call("_update_fist_hitbox", area)
		await RenderingServer.frame_post_draw
		_capture_sequence += 1
		if capture_indices.has(frame_index) and _samples.size() < 128:
			var state := forced_state
			if forced_state == "landing":
				state = str(_animator.call("get_animation_state"))
			_record(label, state)
		_record_timeline(label, forced_state)
		await process_frame
		_segment_elapsed += STEP
		if _capture_error.is_empty() == false:
			return

func _record(label: String, forced_state: String) -> void:
	var image := root.get_texture().get_image()
	if image == null or image.is_empty():
		_capture_error = "Window 프레임 이미지를 읽을 수 없습니다 (%s)." % label
		return
	var crop := image.get_region(CROP)
	crop.resize(TILE.x - 20, TILE.y - 58, Image.INTERPOLATE_LANCZOS)
	_samples.append({"label":label, "state":forced_state, "image":crop, "sequence":_capture_sequence, "visual_seconds":_visual_seconds, "wall":Time.get_datetime_string_from_system(false, true), "window_frame":Engine.get_frames_drawn(), "physics_frame":Engine.get_physics_frames(), "pose_frame":int(_animator.call("get_state_frame")), "pose_count":int(_animator.call("get_state_frame_count")), "pose_label":str(_animator.call("get_state_frame_label")), "source":str(_animator.call("get_displayed_texture_path")), "foot":_foot_anchor(), "hand":_hand_anchor(), "box":_f10_box(), "monitoring":_active_f10_monitoring(), "source_count":_visible_body_count(), "facing":"좌향" if _player.get_node("VisualRoot").scale.x < 0.0 else "우향"})

func _record_timeline(label: String, forced_state: String) -> void:
	var measured_state := str(_animator.call("get_animation_state")) if forced_state == "landing" else forced_state
	var values := _sample_values(label, measured_state)
	var columns := PackedStringArray([
		str(_capture_sequence), Time.get_datetime_string_from_system(false, true), "%.4f" % _visual_seconds,
		str(Engine.get_frames_drawn()), str(Engine.get_physics_frames()), label, measured_state,
		str(_animator.call("get_state_frame")), str(_animator.call("get_state_frame_count")),
		str(_animator.call("get_state_frame_label")), str(_animator.call("get_displayed_texture_path")),
		str(_visible_body_count()), "left" if _player.get_node("VisualRoot").scale.x < 0.0 else "right",
		values.foot, values.hand, values.box, _active_f10_monitoring(),
	])
	for index in range(columns.size()):
		columns[index] = _csv_quote(columns[index])
	_timeline_rows.append(",".join(columns))

func _csv_quote(value: String) -> String:
	return "\"" + value.replace("\"", "\"\"") + "\""

func _sample_values(_label: String, _state: String) -> Dictionary:
	return {"foot":_foot_anchor(), "hand":_hand_anchor(), "box":_f10_box()}

func _reset_actor() -> void:
	_player.velocity = Vector2.ZERO
	_player.set("is_ko", false)
	_player.set("is_jumping", false)
	_player.set("jump_vertical_velocity", 0.0)
	_player.set("jump_height_offset", 0.0)
	_player.set("attack_stage", 0)
	_player.set("attack_phase", "idle")
	_player.set("attack_phase_remaining", 0.0)
	_player.set("attack_progress", 0.0)
	_player.set("combo_link_remaining", 0.0)
	_player.set("skill_id", 0)
	_player.set("skill_phase", "idle")
	_player.set("skill_phase_remaining", 0.0)
	_player.set("hitstun_remaining", 0.0)
	_player.set("hit_flash_remaining", 0.0)
	_player.get_node("VisualRoot/AttackFlash").visible = false
	for name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		(_player.get_node("Hitboxes/" + name) as Area2D).monitoring = false
	_player.get_node("VisualRoot").scale.x = 1.0
	_player.set("facing_direction", Vector2.RIGHT)
	_player.global_position = Vector2(960, 780)
	_animator.call("_process", 0.0)

func _foot_anchor() -> String:
	var sprite := _visible_sprite()
	if sprite == null or sprite.texture == null:
		return "미확인"
	var bounds := sprite.texture.get_image().get_used_rect()
	var local := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y)) - Vector2(sprite.texture.get_size()) * 0.5
	var point := sprite.to_global(local)
	return "%.1f,%.1f" % [point.x, point.y]

func _hand_anchor() -> String:
	var point: Variant = _animator.call("get_fist_contact_global")
	return "미확인" if typeof(point) != TYPE_VECTOR2 else "%.1f,%.1f" % [point.x, point.y]

func _f10_box() -> String:
	var boxes: Array[String] = []
	for name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		var area := _player.get_node("Hitboxes/" + name) as Area2D
		var shape_node := area.get_node("CollisionShape2D") as CollisionShape2D
		var center := shape_node.get_global_transform_with_canvas().origin
		if shape_node.shape is CircleShape2D:
			var radius := (shape_node.shape as CircleShape2D).radius * shape_node.global_scale.x
			boxes.append("%s[%s %.1f,%.1f %.1fx%.1f]" % [name, "on" if area.monitoring else "off", center.x - radius, center.y - radius, radius * 2.0, radius * 2.0])
	return "; ".join(boxes)

func _set_facing(sign: float) -> void:
	_player.set("facing_direction", Vector2(sign, 0.0))
	_player.get_node("VisualRoot").scale.x = sign
	_animator.set("_applied_facing_sign", sign)
	_animator.set("_turn_target_sign", sign)
	_animator.set("_turn_elapsed", 0.13)
	_animator.set("_turn_flip_applied", true)
	_animator.call("_process", 0.0)

func _active_f10_monitoring() -> String:
	var enabled: Array[String] = []
	for name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		if (_player.get_node("Hitboxes/" + name) as Area2D).monitoring:
			enabled.append(name)
	return ",".join(enabled) if not enabled.is_empty() else "none"

func _visible_sprite() -> Sprite2D:
	var pose := _player.get_node("VisualRoot/PoseBlender")
	if pose.visible and float(_animator.call("get_pose_blender_weight")) >= 0.5:
		return pose.call("get_current_sprite") as Sprite2D
	return _player.get_node("VisualRoot/PlayerArt") as Sprite2D

func _visible_body_count() -> int:
	var count := 0
	var art := _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var pose := _player.get_node("VisualRoot/PoseBlender")
	if art.visible and art.modulate.a > 0.01:
		count += 1
	if pose.visible and float(_animator.call("get_pose_blender_weight")) >= 0.5:
		count += 1
	var walk := _player.get_node_or_null("WalkMotion")
	if walk != null and walk.call("is_candidate_active"):
		count += 1
	return count

func _capture_unavailable(label: String, reason: String) -> void:
	_samples.append({"label":label, "state":"UNAVAILABLE", "image":Image.create(TILE.x - 20, TILE.y - 58, false, Image.FORMAT_RGBA8), "sequence":_capture_sequence, "visual_seconds":_visual_seconds, "wall":Time.get_datetime_string_from_system(false, true), "window_frame":Engine.get_frames_drawn(), "physics_frame":Engine.get_physics_frames(), "pose_frame":0, "pose_count":0, "pose_label":reason, "source":"N/A", "foot":"N/A", "hand":"N/A", "box":"N/A", "monitoring":"none", "source_count":0, "facing":"N/A"})

func _capture_sheet_and_report() -> void:
	_overlay.set("enabled", false)
	_overlay.get_node("CollisionShapes").visible = false
	_game.queue_free()
	await process_frame
	var columns := COLUMNS
	var rows := int(ceil(float(_samples.size()) / columns))
	root.size = Vector2i(columns * TILE.x, rows * TILE.y)
	var sheet := Control.new()
	sheet.name = "M6VContactSheet"
	sheet.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(sheet)
	for index in range(_samples.size()):
		var sample: Dictionary = _samples[index]
		var x := (index % columns) * TILE.x
		var y := (index / columns) * TILE.y
		var bg := ColorRect.new()
		bg.position = Vector2(x, y)
		bg.size = Vector2(TILE)
		bg.color = Color("#172226") if index % 2 == 0 else Color("#202d31")
		sheet.add_child(bg)
		var texture := ImageTexture.create_from_image(sample.image as Image)
		var rect := TextureRect.new()
		rect.position = Vector2(x + 10, y + 48)
		rect.size = Vector2(TILE.x - 20, TILE.y - 58)
		rect.texture = texture
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_SCALE
		sheet.add_child(rect)
		_add_label(sheet, "#%03d %s" % [index + 1, sample.label], Vector2(x + 8, y + 4), 14, Color.WHITE)
		_add_label(sheet, "%s  frame %d  t=%.3fs" % [sample.wall, sample.window_frame, sample.visual_seconds], Vector2(x + 8, y + 25), 10, Color("#e6d797"))
	await process_frame
	await RenderingServer.frame_post_draw
	var output := root.get_texture().get_image()
	var absolute_image := ProjectSettings.globalize_path(OUTPUT_IMAGE)
	DirAccess.make_dir_recursive_absolute(absolute_image.get_base_dir())
	if output.save_png(absolute_image) != OK:
		_capture_error = "접촉 시트 PNG 저장에 실패했습니다."
		return
	_write_report(columns, rows)

func _add_label(parent: Control, text: String, position: Vector2, size: int, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.position = position
	label.size = Vector2(TILE.x - 16, 22)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_shadow_color", Color.BLACK)
	label.add_theme_constant_override("shadow_offset_x", 1)
	label.add_theme_constant_override("shadow_offset_y", 1)
	parent.add_child(label)

func _write_report(columns: int, rows: int) -> void:
	var lines := PackedStringArray()
	lines.append("# M6V 애니메이션 시각 검수 매트릭스")
	lines.append("")
	lines.append("- 수집 시각: %s (Godot 시스템 로컬 시각, Asia/Seoul 환경)" % Time.get_datetime_string_from_system(false, true))
	lines.append("- 대상: `scenes/game/main.tscn`의 production Player, 실제 Godot Window Viewport 캡처")
	lines.append("- 접촉 시트: `assets/art/review/m6v_animation_quality_contact_sheet.png` (%d×%d px, %d열 × %d행, 모든 카드 동일한 1.0 카메라 줌과 동일 crop)" % [columns * TILE.x, rows * TILE.y, columns, rows])
	lines.append("- 연속 수집: %d Window draw ticks, 간격 1/60초, 모션 시퀀스 %.3f초. 시트에는 각 구간의 시작·중간·끝 대표 프레임을 싣고, 상태 telemetry는 매 Window draw frame을 기록한다." % [_capture_sequence, _visual_seconds])
	lines.append("- 측정: 발 anchor는 표시 전신 텍스처 alpha 하단 중심의 world point, 손 anchor는 animator의 실제 주먹 접촉 point, F10 박스는 실제 CollisionShape2D canvas bounds와 monitoring을 기록한다. F10 오버레이는 녹화 중 켜져 있었다.")
	lines.append("- 프레임 번호는 Godot `Engine.get_frames_drawn()` Window draw counter다. visual t는 시퀀스 시작 이후 60Hz 고정 샘플 누적 시간이다. 표본은 wall-clock ISO 시각도 함께 저장한다.")
	lines.append("- 실제 본편 카메라와 배경 위에서 상태를 결정적으로 고정해 순서대로 재생했다. 공격/스킬 상태는 production animator가 소비하는 controller phase 필드를 지정하고 실제 hitbox monitoring/transform을 읽었다. 점프·히트·KO 변형은 production Player/Animator 경로다.")
	lines.append("")
	lines.append("## 연속 상태 기록")
	lines.append("")
	lines.append("연속 draw-frame telemetry를 아래 CSV에 전부 기록했다. 접촉 시트의 시작/중간/끝 카드는 각 구간의 대표 프레임이며 상세 측정값은 위 표에 있다.")
	lines.append("")
	lines.append("| seq | wall timestamp | visual t | window frame | 상태 / 구간 | pose frame | 발 anchor world | 손 anchor world | F10 box screen / monitoring | 전신 source |")
	lines.append("|---:|---|---:|---:|---|---:|---|---|---|---|")
	for sample in _samples:
		lines.append("| %d | %s | %.3fs | %d | %s / %s | %d/%d %s | %s | %s | %s / %s | `%s` (%d) |" % [sample.sequence, sample.wall, sample.visual_seconds, sample.window_frame, sample.label, sample.state, sample.pose_frame, sample.pose_count, sample.pose_label, sample.foot, sample.hand, sample.box, sample.monitoring, sample.source, sample.source_count])
	lines.append("")
	lines.append("## 시각 검수 판정")
	lines.append("")
	lines.append("PASS는 이 접촉 시트에서 사람이 육안으로 확인한 항목만 의미한다. 현재 자동 캡처/anchor 데이터는 형태 평가를 대체하지 않으므로 관절·얼굴·복장·연속성·주먹과 판정 정합성은 육안 승인 전까지 UNVERIFIED로 둔다. 자동 픽셀 측정으로 PASS를 만들지 않았다.")
	lines.append("")
	lines.append("| 상태 | 관절 변형 | 체형·얼굴·복장 일관성 | 프레임 연결 | 주먹·F10 판정 위치 | 결과 / 검토 메모 |")
	lines.append("|---|---|---|---|---|---|")
	for label in _unique_labels():
		var disposition := "UNVERIFIED"
		var note := "육안 품질 승인 대기; 카드와 실제 F10 표시를 함께 확인할 것"
		if label == "J3 combo_hold":
			disposition = "UNVERIFIED"
			note = "본편 규칙상 J3 다음 combo_hold가 없어 재현 불가"
		lines.append("| %s | %s | %s | %s | %s | %s: %s |" % [label, disposition, disposition, disposition, disposition, disposition, note])
	lines.append("")
	lines.append("## 해석 범위와 한계")
	lines.append("")
	lines.append("- 본편 걷기 4위상은 procedural mesh gait의 `left_contact`, `left_passing`, `right_contact`, `right_passing` phase clock에서 채집했다. 임시 보행은 승인된 4장의 연속 애니메이션 원화가 아니다.")
	lines.append("- J1/J2는 실제 `combo_hold` link window를 포함한다. 컨트롤러는 J3에서 combo_hold를 제공하지 않으므로 해당 칸은 UNVERIFIED/N/A로 기록했다.")
	lines.append("- Num4/Num5의 production phase는 startup/active/recovery다. 별도 combo_hold 상태는 없다.")
	lines.append("- 한 장의 검수 시트와 수치 telemetry는 육안 승인, 원화 일관성 보증, 실제 상대에게 접촉했을 때의 적중 보증을 대신하지 않는다.")
	lines.append("")
	lines.append("## 원본 연속 telemetry")
	lines.append("")
	lines.append("```csv")
	lines.append("\n".join(_timeline_rows))
	lines.append("```")
	var absolute_report := ProjectSettings.globalize_path(OUTPUT_REPORT)
	DirAccess.make_dir_recursive_absolute(absolute_report.get_base_dir())
	var file := FileAccess.open(absolute_report, FileAccess.WRITE)
	if file == null:
		_capture_error = "검수 매트릭스 문서를 열지 못했습니다."
		return
	file.store_string("\n".join(lines) + "\n")
	file.close()

func _unique_labels() -> PackedStringArray:
	var labels := PackedStringArray()
	for sample in _samples:
		var label := str(sample.label)
		if not labels.has(label):
			labels.append(label)
	return labels

func _attack_duration(stage: int, phase: String) -> float:
	var index := stage - 1
	var durations := {"startup":[0.075, 0.085, 0.10], "active":[0.105, 0.12, 0.14], "recovery":[0.20, 0.22, 0.28], "combo_hold":[0.45, 0.45, 0.0]}
	return float(durations[phase][index])

func _skill_duration(skill_id: int, phase: String) -> float:
	var index := skill_id - 1
	var durations := {"startup":[0.16, 0.22], "active":[0.12, 0.18], "recovery":[0.42, 0.55]}
	return float(durations[phase][index])

func _settle(frames: int) -> void:
	for _index in range(frames):
		await process_frame
		await RenderingServer.frame_post_draw

func _fail(message: String) -> void:
	push_error("m6v_animation_comparison: " + message)
	quit(1)
