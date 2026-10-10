extends SceneTree
"""Window capture and live-physics gate for M6O Boss attack ranges."""

const BOSS_SCENE := "res://scenes/enemies/ruins_warden_boss.tscn"
const PLAYER_SCENE := "res://scenes/player/player.tscn"
const REPORT_PATH := "res://docs/review/m6o_boss_overlap_window_gate.md"
const VIEW_SIZE := Vector2i(1280, 720)
const BOSS_POSITION := Vector2(640.0, 360.0)
const MAX_WAIT_FRAMES := 150

var _stage: Node2D
var _boss: CharacterBody2D
var _player: CharacterBody2D
var _extra_area: Area2D
var _overlay: Node
var _rows := PackedStringArray()
var _failures := PackedStringArray()
var _captures := 0
var _f10_on := false
var _windup_f10_off: Image
var _windup_f10_on: Image

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_finish("A rendered Window is required for this collision capture.")
		return
	root.size = VIEW_SIZE
	_overlay = root.get_node_or_null("CombatCollisionOverlay")
	if _overlay == null:
		_finish("CombatCollisionOverlay autoload is missing.")
		return
	await _setup("slash", 1.0, 0.0)
	if not await _wait_for_phase("windup", "slash"):
		_finish("Right slash did not naturally enter windup.")
		return
	_record("slash_right", "windup", false)
	_check(not _boss.attack_area.monitoring, "slash windup leaves AttackArea monitoring off")
	await _capture_frame("slash_windup_F10_OFF")
	await _toggle_f10(true)
	await _capture_frame("slash_windup_F10")
	_check(_windup_f10_off != null and _windup_f10_on != null and _windup_f10_off.get_data() != _windup_f10_on.get_data(), "F10 ON Window frame differs from OFF frame, showing rendered collision outlines")
	await _check_slash_target(Vector2(86.0, 0.0), true, "slash_right_inner")
	await _teardown()

	await _setup("slash", -1.0, 0.0)
	if not await _wait_for_phase("windup", "slash"):
		_finish("Left slash did not naturally enter windup.")
		return
	await _check_slash_target(Vector2(-86.0, 0.0), true, "slash_left_inner")
	await _teardown()

	await _setup("slash", 1.0, 0.0)
	if not await _wait_for_phase("windup", "slash"):
		_finish("Outside-range slash did not naturally enter windup.")
		return
	await _check_slash_target(Vector2(220.0, 0.0), false, "slash_outside_circle")
	await _teardown()

	await _setup("slash", 1.0, 0.0)
	if not await _wait_for_phase("windup", "slash"):
		_finish("Slash depth-limit scenario did not naturally enter windup.")
		return
	_extra_area = _add_overlap_probe(_player, Vector2(0.0, -47.0), 4.0, "SlashDepthProbe")
	await _check_slash_target(Vector2(86.0, 67.0), false, "slash_overlap_beyond_66_depth")
	await _teardown()

	await _setup("slam", -1.0, 0.0)
	if not await _wait_for_phase("windup", "slam"):
		_finish("Slam did not naturally enter windup at medium range.")
		return
	await _check_slam_target(Vector2(0.0, 0.0), true, "slam_inner")
	await _teardown()

	await _setup("slam", -1.0, 0.0)
	if not await _wait_for_phase("windup", "slam"):
		_finish("Depth-limit slam did not naturally enter windup.")
		return
	await _check_slam_target(Vector2(0.0, 106.0), false, "slam_overlap_beyond_105_depth")
	await _teardown()

	await _setup("slash", 1.0, 0.0)
	if not await _wait_for_phase("windup", "slash"):
		_finish("Duplicate-overlap slash did not naturally enter windup.")
		return
	_extra_area = _add_overlap_probe(_player, Vector2.ZERO, 12.0, "DuplicateReceiverOverlapProbe")
	await _check_slash_target(Vector2(86.0, 0.0), true, "duplicate_body_and_area_overlap")
	await _teardown()

	await _check_boss_ko_via_player_attack()
	if _failures.is_empty():
		_rows.append("- Boss 런타임 코드는 수정하지 않았다. F10 윤곽과 실제 overlap/HP 사이에서 재현된 불일치가 없다.")
	_write_report()
	if _failures.is_empty():
		print("M6O|SUMMARY|PASS|display=%s|captures=%d|f10=%s|human_window_approval=PENDING" % [DisplayServer.get_name(), _captures, str(_f10_on)])
		quit(0)
	else:
		_write_report()
		for failure in _failures:
			push_error("M6O|FAIL|" + failure)
		quit(1)

func _setup(kind: String, side: float, y_offset: float) -> void:
	_stage = Node2D.new()
	_stage.name = "M6OBossOverlapWindowStage"
	root.add_child(_stage)
	current_scene = _stage
	_boss = (load(BOSS_SCENE) as PackedScene).instantiate() as CharacterBody2D
	_boss.global_position = BOSS_POSITION
	_stage.add_child(_boss)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as CharacterBody2D
	_player.name = "Player"
	_player.global_position = BOSS_POSITION + Vector2(side * (100.0 if kind == "slash" else 180.0), y_offset)
	_stage.add_child(_player)
	_player.set_physics_process(false)
	_boss.call("set_combat_active", true)
	# Keep the boss body from physically displacing the stationary probe. AttackArea
	# keeps its production collision mask and remains the sole damage authority.
	_boss.collision_mask = 0
	await physics_frame

func _wait_for_phase(phase: String, kind: String) -> bool:
	for _frame in range(MAX_WAIT_FRAMES):
		await physics_frame
		if str(_boss.get("attack_kind")) == kind and str(_boss.get("attack_phase")) == phase:
			return true
	return false

func _check_slash_target(relative_position: Vector2, expect_hit: bool, label: String) -> void:
	var hp_before := int(_player.get("health"))
	_player.global_position = BOSS_POSITION + relative_position
	if not await _wait_for_phase("active", "slash"):
		_check(false, label + ": slash never became active")
		return
	await physics_frame
	var body_overlap: bool = _boss.attack_area.get_overlapping_bodies().has(_player)
	var area_overlap: bool = _boss.attack_area.get_overlapping_areas().has(_extra_area) if is_instance_valid(_extra_area) else false
	var hp_delta := hp_before - int(_player.get("health"))
	var radius := (_boss.attack_shape.shape as CircleShape2D).radius
	var overlap_observed: bool = body_overlap or area_overlap
	_rows.append("| %s | %s | (%.1f, %.1f) | r=%.1f, 중심 Δy=%.1f | body=%s / area=%s | %d→%d | %s |" % [label, str(_boss.get("attack_phase")), _player.global_position.x - BOSS_POSITION.x, _player.global_position.y - BOSS_POSITION.y, radius, absf(_player.global_position.y - BOSS_POSITION.y), str(body_overlap), str(area_overlap), hp_before, int(_player.get("health")), "기대대로" if (hp_delta > 0) == expect_hit else "불일치"])
	_record(label, "active", overlap_observed)
	if label == "slash_overlap_beyond_66_depth":
		_check(not body_overlap and area_overlap, label + ": real target Area2D overlaps the circle while CharacterBody center exceeds the 66 px depth gate")
	else:
		_check(body_overlap == expect_hit, label + ": physical body overlap matches the expected circle inclusion")
	if expect_hit:
		_check(hp_delta == int(_boss.get("attack_damage")), label + ": actual Player HP decreases once by production attack_damage")
		await _wait_for_phase("recovery", "slash")
		_check(str(_boss.get("attack_phase")) == "recovery" and not _boss.attack_area.monitoring, label + ": recovery disables the attack Area2D")
	else:
		await _wait_for_phase("recovery", "slash")
		_check(int(_player.get("health")) == hp_before, label + ": rejected overlap leaves Player HP unchanged")
	if label == "duplicate_body_and_area_overlap":
		_check(body_overlap and area_overlap, label + ": both CharacterBody and child Area2D are in the active overlap lists")
	await _capture_frame(label)

func _check_slam_target(relative_position: Vector2, expect_hit: bool, label: String) -> void:
	var hp_before := int(_player.get("health"))
	_player.global_position = BOSS_POSITION + relative_position
	if not await _wait_for_phase("active", "slam"):
		_check(false, label + ": slam never became active")
		return
	await physics_frame
	var body_overlap: bool = _boss.attack_area.get_overlapping_bodies().has(_player)
	var hp_delta := hp_before - int(_player.get("health"))
	var radius := (_boss.attack_shape.shape as CircleShape2D).radius
	var depth := absf(_player.global_position.y - _boss.global_position.y)
	_rows.append("| %s | %s | (%.1f, %.1f) | r=%.1f, 중심 Δy=%.1f (제한 105) | body=%s / area=false | %d→%d | %s |" % [label, str(_boss.get("attack_phase")), relative_position.x, relative_position.y, radius, depth, str(body_overlap), hp_before, int(_player.get("health")), "기대대로" if (hp_delta > 0) == expect_hit else "불일치"])
	_record(label, "active", body_overlap)
	_check(body_overlap, label + ": Area2D reports a real body overlap for depth-gate observation")
	if expect_hit:
		_check(hp_delta == int(_boss.get("attack_damage")), label + ": actual Player HP decreases once by production attack_damage")
	else:
		_check(depth > 105.0 and hp_delta == 0, label + ": overlap beyond 105 px depth is rejected without HP loss")
	await _wait_for_phase("recovery", "slam")
	_check(str(_boss.get("attack_phase")) == "recovery" and not _boss.attack_area.monitoring, label + ": slam recovery disables the attack Area2D")
	await _capture_frame(label)

func _check_boss_ko_via_player_attack() -> void:
	_stage = Node2D.new()
	_stage.name = "M6OBossKOStage"
	root.add_child(_stage)
	current_scene = _stage
	_boss = (load(BOSS_SCENE) as PackedScene).instantiate() as CharacterBody2D
	_boss.set("max_health", 1)
	_boss.global_position = BOSS_POSITION
	_stage.add_child(_boss)
	_player = (load(PLAYER_SCENE) as PackedScene).instantiate() as CharacterBody2D
	_player.name = "Player"
	_player.global_position = BOSS_POSITION + Vector2(-70.0, 0.0)
	_player.set("arena_bounds", Rect2(0.0, 0.0, 1280.0, 720.0))
	_stage.add_child(_player)
	_boss.call("set_combat_active", true)
	_boss.set_physics_process(false)
	_boss.collision_mask = 0
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	var ko_signals := [0]
	_boss.boss_ko.connect(func() -> void: ko_signals[0] += 1)
	var hp_before := int(_boss.get("health"))
	var input := InputEventKey.new()
	input.device = 16
	input.keycode = 0
	input.physical_keycode = KEY_J
	input.pressed = true
	Input.parse_input_event(input)
	for _frame in range(MAX_WAIT_FRAMES):
		await physics_frame
		if int(_boss.get("health")) == 0:
			break
	input = InputEventKey.new()
	input.device = 16
	input.keycode = 0
	input.physical_keycode = KEY_J
	input.pressed = false
	Input.parse_input_event(input)
	await process_frame
	_rows.append("| boss_KO_by_Player_J | 피격 경로 | Player J | production Hitbox1 Area2D | Boss HP %d→%d, boss_ko=%d | 직접 피격 호출 없음 | 실제 Player 공격 |" % [hp_before, int(_boss.get("health")), ko_signals[0]])
	_check(int(_boss.get("health")) == 0 and ko_signals[0] == 1, "Boss KO follows a real Player attack overlap and emits boss_ko exactly once")
	_check(not _boss.attack_area.monitoring and not bool(_boss.get("combat_active")), "KO cancels any attack window and deactivates Boss combat")
	await _capture_frame("boss_KO")
	await _teardown()

func _toggle_f10(enabled: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = KEY_F10
	event.physical_keycode = KEY_F10
	event.pressed = true
	Input.parse_input_event(event)
	await process_frame
	event = InputEventKey.new()
	event.keycode = KEY_F10
	event.physical_keycode = KEY_F10
	event.pressed = false
	Input.parse_input_event(event)
	await process_frame
	_f10_on = bool(_overlay.get("enabled"))
	_check(_f10_on == enabled, "F10 overlay toggles to " + str(enabled) + " through a Window key event")

func _add_overlap_probe(parent: Node2D, local_position: Vector2, radius: float, probe_name: String) -> Area2D:
	var probe := Area2D.new()
	probe.name = probe_name
	probe.position = local_position
	probe.collision_layer = 1
	probe.collision_mask = 0
	probe.monitorable = true
	var probe_shape := CollisionShape2D.new()
	var probe_circle := CircleShape2D.new()
	probe_circle.radius = radius
	probe_shape.shape = probe_circle
	probe.add_child(probe_shape)
	parent.add_child(probe)
	return probe

func _capture_frame(label: String) -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and not frame.is_empty() and frame.get_size() == VIEW_SIZE, label + ": rendered Window viewport frame captured at 1280x720")
	if label == "slash_windup_F10_OFF":
		_windup_f10_off = frame.duplicate()
	elif label == "slash_windup_F10":
		_windup_f10_on = frame.duplicate()
	_captures += 1
	print("M6O|FRAME|%s|display=%s|size=%s|F10=%s|source=auto_input_event" % [label, DisplayServer.get_name(), str(frame.get_size()) if frame != null else "none", str(_f10_on)])

func _record(label: String, phase: String, overlap: bool) -> void:
	print("M6O|OBS|%s|phase=%s|kind=%s|monitoring=%s|overlap_body=%s|HP=%d|depth=%.1f|source=live_Area2D" % [label, phase, str(_boss.get("attack_kind")), str(_boss.attack_area.monitoring), str(overlap), int(_player.get("health")), absf(_player.global_position.y - _boss.global_position.y)])

func _teardown() -> void:
	if is_instance_valid(_stage):
		_stage.queue_free()
		_stage = null
	await process_frame
	await physics_frame

func _check(condition: bool, description: String) -> void:
	if condition:
		print("M6O|PASS|" + description)
	else:
		_failures.append(description)

func _write_report() -> void:
	var lines := PackedStringArray([
		"# M6O Boss 겹침·F10 Window 검증 게이트", "",
		"## 실행 증거", "",
		"- 실행 방식: production Player/Boss 씬을 비-headless Godot Window에서 실행하고, 실제 물리 프레임의 `AttackArea.get_overlapping_bodies()`와 Player/Boss HP를 관찰했다. 공격은 Boss AI가 위치를 보고 시작했다.",
		"- 입력 출처: `source=auto_input_event`; 물리 키보드 검증은 아니다. 캡처된 Window: %s, 1280×720, %d 프레임. F10 ON 관측=%s, 같은 windup Window의 OFF/ON 프레임 차이 확인=%s." % [DisplayServer.get_name(), _captures, str(_f10_on), str(_windup_f10_off != null and _windup_f10_on != null and _windup_f10_off.get_data() != _windup_f10_on.get_data())],
		"- 직접 `receive_hit` 호출 또는 HP 대입으로 타격/KO를 만들지 않았다. KO는 Player J 공격의 production Area2D overlap으로 확인했다.", "",
		"## 실측", "",
		"| 시나리오 | 상태 | Player 기준 위치 | 범위 및 깊이 | 실제 overlap | HP | 판정 |",
		"|---|---|---:|---|---|---:|---|"
	])
	lines.append_array(_rows)
	lines.append_array(["", "## 상태 및 판정", "", "- `windup`: AttackArea monitoring OFF 확인. `active`: 실제 overlap과 HP 판정. `recovery`: monitoring OFF 확인.", "- 중복 검증은 동일 Player CharacterBody와 child Area2D가 Boss Area2D에 동시에 겹치도록 구성했으며, production attack_damage 한 번만 HP에서 차감되는지 검사했다.", "- slash F10 outline은 AttackArea의 실제 CircleShape2D를 그린다. slam도 실제 CircleShape2D(반지름 125)를 그린다. 측정 결과 위반 시에만 런타임 코드 변경이 필요하다.", "- 자동 검증 결과는 사람의 Window 육안 승인이 아니다. **사람 Window 승인: PENDING** (`human_window_approval=PENDING`).", "", "## 결과", "", "- " + ("PASS" if _failures.is_empty() else "FAIL: " + "; ".join(_failures)), ""])
	var file := FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if file == null:
		push_error("Could not write M6O review report: " + str(FileAccess.get_open_error()))
		return
	file.store_string("\n".join(lines))
	file.close()

func _finish(message: String) -> void:
	_failures.append(message)
	_write_report()
	push_error("M6O|FAIL|" + message)
	quit(1)
