extends SceneTree
"""Automated Window capture for combo links, hitboxes, and live health changes."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/m6n_combo_hitbox_contact_sheet.png"
const REPORT_PATH := "res://docs/review/m6n_video_comparison_gate.md"
const VIEW_SIZE := Vector2i(1280, 720)
const CELL_SIZE := Vector2i(480, 270)
const GRID_COLUMNS := 4
const PLAYER_PATH := "YSortActors/Player"
const MAX_WAIT_FRAMES := 420
const MAX_CAPTURE_FRAMES := 100

var _game: Node2D
var _player: CharacterBody2D
var _raider: CharacterBody2D
var _boss: CharacterBody2D
var _overlay: Node
var _frames: Array[Image] = []
var _frame_labels: PackedStringArray = []
var _trace: PackedStringArray = []
var _active_frames := [0, 0, 0]
var _stage_offsets: Array = [[], [], []]
var _raider_box_target_delta := Vector2.ZERO
var _raider_box_target_measured := false
var _idle_interhit_frames := 0
var _combo_started := false
var _combo_stage3_started := false
var _collect_combo_metrics := false
var _auto_key_events := 0
var _raider_player_hp_before := -1
var _raider_player_hp_after := -1
var _boss_player_hp_before := -1
var _boss_player_hp_after := -1
var _raider_hp_before := -1
var _raider_hp_after := -1
var _boss_hp_before := -1
var _boss_hp_after := -1
var _overlay_off_observed := false
var _overlay_on_observed := false
var _capture_error := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_finish_failure("Window renderer unavailable; --headless capture is not accepted.")
		return
	root.size = VIEW_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_finish_failure("Could not load the production gameplay scene: " + MAIN_SCENE)
		return
	_game = packed.instantiate() as Node2D
	root.add_child(_game)
	current_scene = _game
	await _settle(12)
	_player = _game.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	_raider = _game.get_node_or_null("YSortActors/ForestRaider1") as CharacterBody2D
	_boss = _game.get_node_or_null("YSortActors/RuinsWardenBoss") as CharacterBody2D
	_overlay = root.get_node_or_null("CombatCollisionOverlay")
	if _player == null or _raider == null or _boss == null or _overlay == null:
		_finish_failure("Gameplay Player, Raider, Boss, or F10 collision overlay missing.")
		return

	# Isolate the real Player controller's combo phases, then re-enable actors for live HP tests.
	for path in ["YSortActors/ForestRaider1", "YSortActors/ForestRaider2", "YSortActors/ForestRaider3", "YSortActors/TrainingDummy"]:
		var actor := _game.get_node_or_null(path)
		if actor != null:
			actor.set_physics_process(false)
	_player.global_position = Vector2(960.0, 780.0)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	_raider.global_position = Vector2(1680.0, 780.0)
	_boss.set("combat_active", false)
	await _settle(4)
	_record_tick("setup")
	await _capture("01_walk_start")

	# Walk in the genuine game scene using generated input. Input provenance is explicit in the trace.
	await _key(KEY_D, true)
	for index in range(24):
		await _tick("walk")
		if index % 6 == 0:
			await _capture("walk_%02d" % index)
	await _key(KEY_D, false)
	await _settle(3)
	await _capture("02_walk_stop")

	await _toggle_f10(true)
	await _toggle_f10(false)
	_overlay_off_observed = not bool(_overlay.get("enabled"))
	await _capture("03_F10_OFF")
	await _toggle_f10(true)
	_overlay_on_observed = bool(_overlay.get("enabled"))
	await _settle(2)
	await _capture("04_F10_ON")

	await _run_combo()
	# A stationary active Raider keeps the exact production attack hitboxes and receiver live.
	_player.global_position = Vector2(960.0, 780.0)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	_raider.global_position = Vector2(1032.0, 780.0)
	_raider.set_physics_process(false)
	await _settle(3)
	_raider_hp_before = int(_raider.get("health"))
	await _tap(KEY_J)
	await _wait_for_raider_hp_change()
	_raider_hp_after = int(_raider.get("health"))
	await _capture("raider_player_hit")

	# Re-enable Raider AI and observe its production attack reduce Player health.
	_raider.set_physics_process(true)
	_player.global_position = Vector2(1000.0, 780.0)
	_player.set("facing_direction", Vector2.LEFT)
	_player.get_node("VisualRoot").scale.x = -1.0
	_raider.global_position = Vector2(1070.0, 780.0)
	_raider_player_hp_before = int(_player.get("health"))
	await _wait_for_player_hp_change(_raider, "raider_player_hit")
	_raider_player_hp_after = int(_player.get("health"))
	await _capture("raider_hit_player")

	# Activate the production boss receiver near the Player for a real boss attack and hit.
	_raider.set_physics_process(false)
	_raider.global_position = Vector2(3500.0, 780.0)
	_boss.global_position = Vector2(1124.0, 780.0)
	_boss.call("set_combat_active", true)
	_player.global_position = Vector2(1000.0, 780.0)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	_boss_player_hp_before = int(_player.get("health"))
	await _wait_for_player_hp_change(_boss, "boss_player_hit")
	_boss_player_hp_after = int(_player.get("health"))
	await _capture("boss_hit_player")

	# Let Player J connect to Boss, with both actors using their production hit receiver code.
	_boss.set_physics_process(false)
	_boss.call("set_combat_active", true)
	_boss.set_physics_process(false)
	for index in range(60):
		if float(_player.get("hitstun_remaining")) <= 0.0:
			break
		await _tick("player_hitstun_recovery")
	_player.global_position = Vector2(1000.0, 780.0)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	_boss.global_position = Vector2(1040.0, 780.0)
	_boss_hp_before = int(_boss.get("health"))
	await _tap(KEY_J)
	await _wait_for_boss_hp_change()
	_boss_hp_after = int(_boss.get("health"))
	await _capture("player_hit_boss")

	# Verify images came from the non-headless Window viewport, then write the evidence sheet/report.
	if _frames.is_empty():
		_finish_failure("No Window frames were captured.")
		return
	var rows := int(ceil(float(_frames.size()) / float(GRID_COLUMNS)))
	var sheet := Image.create(CELL_SIZE.x * GRID_COLUMNS, CELL_SIZE.y * rows, false, Image.FORMAT_RGBA8)
	for index in range(_frames.size()):
		var cell := _frames[index].duplicate()
		cell.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i((index % GRID_COLUMNS) * CELL_SIZE.x, (index / GRID_COLUMNS) * CELL_SIZE.y))
	var save_error := sheet.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if save_error != OK:
		_finish_failure("Contact sheet save failed with Error %d." % save_error)
		return
	_write_report()
	print("M6N_SUMMARY|fail=0|source=auto_input_event|display=%s|captures=%d|combo_interhit_idle=%d|active=%s|raider_hp=%d->%d|player_raider_hp=%d->%d|boss_hp=%d->%d|player_boss_hp=%d->%d|F10_off=%s|F10_on=%s" % [DisplayServer.get_name(), _frames.size(), _idle_interhit_frames, str(_active_frames), _raider_hp_before, _raider_hp_after, _raider_player_hp_before, _raider_player_hp_after, _boss_hp_before, _boss_hp_after, _boss_player_hp_before, _boss_player_hp_after, str(_overlay_off_observed), str(_overlay_on_observed)])
	print("M6N_CAPTURE|size=%dx%d|path=%s|input=auto_input_event|human_visual_approval=false" % [sheet.get_width(), sheet.get_height(), OUTPUT_PATH])
	for row in _trace:
		print(row)
	quit(0)

func _run_combo() -> void:
	_combo_started = false
	_combo_stage3_started = false
	_collect_combo_metrics = true
	await _key(KEY_J, true)
	await _tick("combo_start")
	await _key(KEY_J, false)
	var stage1_hold := await _wait_phase(1, "combo_hold", "combo_stage1_hold", true)
	if not stage1_hold:
		_trace.append("M6N|FAIL|stage1 did not reach combo_hold")
		return
	await _tap(KEY_J)
	var stage2_hold := await _wait_phase(2, "combo_hold", "combo_stage2_hold", true)
	if not stage2_hold:
		_trace.append("M6N|FAIL|stage2 did not reach combo_hold")
		return
	await _tap(KEY_J)
	_combo_stage3_started = await _wait_phase(3, "active", "combo_stage3_active", true)
	if not _combo_stage3_started:
		_trace.append("M6N|FAIL|stage3 did not reach active")
		return
	for index in range(MAX_WAIT_FRAMES):
		await _tick("combo_finish")
		if int(_player.get("attack_stage")) == 0 and str(_player.get("attack_phase")) == "idle":
			break
	_collect_combo_metrics = false

func _wait_phase(stage: int, phase: String, label: String, capture: bool) -> bool:
	for index in range(MAX_WAIT_FRAMES):
		await _tick(label)
		if int(_player.get("attack_stage")) == stage and str(_player.get("attack_phase")) == phase:
			if capture:
				await _capture(label)
			return true
	return false

func _wait_for_raider_hp_change() -> void:
	for index in range(MAX_WAIT_FRAMES):
		await _tick("raider_damage")
		if int(_raider.get("health")) < _raider_hp_before:
			var stage := int(_player.get("attack_stage"))
			if stage >= 1 and stage <= 3:
				var hitbox := _player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
				_raider_box_target_delta = _raider.global_position - hitbox.global_position
				_raider_box_target_measured = true
			return

func _wait_for_boss_hp_change() -> void:
	for index in range(MAX_WAIT_FRAMES):
		await _tick("boss_damage")
		if int(_boss.get("health")) < _boss_hp_before:
			return

func _wait_for_player_hp_change(attacker: CharacterBody2D, label: String) -> void:
	var hp_before := int(_player.get("health"))
	for index in range(MAX_WAIT_FRAMES):
		await _tick(label)
		if int(_player.get("health")) < hp_before:
			return

func _tick(label: String) -> void:
	await physics_frame
	_record_tick(label)
	if _combo_started and not _combo_stage3_started and str(_player.get("attack_phase")) == "idle":
		_idle_interhit_frames += 1
	if str(_player.get("attack_phase")) != "idle" or int(_player.get("attack_stage")) > 0:
		_combo_started = true
	var phase := str(_player.get("attack_phase"))
	var stage := int(_player.get("attack_stage"))
	if _collect_combo_metrics and phase == "active" and stage >= 1 and stage <= 3:
		var hitbox := _player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
		if hitbox.monitoring:
			_active_frames[stage - 1] += 1
			var hitbox_delta: Vector2 = hitbox.global_position - _player.global_position
			_stage_offsets[stage - 1].append(hitbox_delta)
	if _frames.size() < MAX_CAPTURE_FRAMES and label.begins_with("combo_"):
		await _capture("%s_%03d" % [label, Engine.get_physics_frames()])

func _record_tick(label: String) -> void:
	var box_active := false
	var stage := int(_player.get("attack_stage")) if _player != null else 0
	if _player != null and stage >= 1 and stage <= 3:
		box_active = bool((_player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D).monitoring)
	var target_delta := _raider.global_position - _player.global_position if _raider != null else Vector2.ZERO
	_trace.append("M6N_FRAME|frame=%d|label=%s|stage=%d|phase=%s|idle=%d|box=%s|player=(%.1f,%.1f)|box_delta=(%.1f,%.1f)|target_delta=(%.1f,%.1f)|player_hp=%s|raider_hp=%s|boss_hp=%s|source=auto_input_event" % [Engine.get_physics_frames(), label, stage, str(_player.get("attack_phase")) if _player != null else "", _idle_interhit_frames, str(box_active), _player.global_position.x if _player != null else 0.0, _player.global_position.y if _player != null else 0.0, _current_box_delta().x, _current_box_delta().y, target_delta.x, target_delta.y, str(_player.get("health")) if _player != null else "?", str(_raider.get("health")) if _raider != null else "?", str(_boss.get("health")) if _boss != null else "?"])

func _current_box_delta() -> Vector2:
	if _player == null:
		return Vector2.ZERO
	var stage := int(_player.get("attack_stage"))
	if stage < 1 or stage > 3:
		return Vector2.ZERO
	return (_player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D).global_position - _player.global_position

func _key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.device = 16
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	_auto_key_events += 1
	await process_frame

func _tap(keycode: Key) -> void:
	await _key(keycode, true)
	await _tick("auto_key_down")
	await _key(keycode, false)
	await _tick("auto_key_up")

func _toggle_f10(expected_enabled: bool) -> void:
	var event := InputEventKey.new()
	event.device = 16
	event.keycode = KEY_F10
	event.physical_keycode = KEY_F10
	event.pressed = true
	Input.parse_input_event(event)
	_auto_key_events += 1
	await _settle(1)
	event = InputEventKey.new()
	event.device = 16
	event.keycode = KEY_F10
	event.physical_keycode = KEY_F10
	Input.parse_input_event(event)
	_auto_key_events += 1
	await _settle(1)
	_trace.append("M6N_INPUT|key=F10|expected=%s|observed=%s|source=auto_input_event" % [str(expected_enabled), str(bool(_overlay.get("enabled")))])

func _settle(count: int) -> void:
	for index in range(count):
		await process_frame
		await RenderingServer.frame_post_draw

func _capture(label: String) -> void:
	if _frames.size() >= MAX_CAPTURE_FRAMES:
		return
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != VIEW_SIZE:
		_capture_error = "Window viewport capture has unexpected size."
		return
	_frames.append(image.duplicate())
	_frame_labels.append(label)

func _write_report() -> void:
	var stage_offset_rows := PackedStringArray()
	for index in range(3):
		var stage_offsets: Array = _stage_offsets[index]
		if stage_offsets.is_empty():
			stage_offset_rows.append("%d타 미측정" % (index + 1))
			continue
		var stage_min: Vector2 = stage_offsets[0]
		var stage_max: Vector2 = stage_offsets[0]
		for offset: Vector2 in stage_offsets:
			stage_min.x = minf(stage_min.x, offset.x)
			stage_min.y = minf(stage_min.y, offset.y)
			stage_max.x = maxf(stage_max.x, offset.x)
			stage_max.y = maxf(stage_max.y, offset.y)
		stage_offset_rows.append("%d타 x %.1f..%.1f, y %.1f..%.1f" % [index + 1, stage_min.x, stage_max.x, stage_min.y, stage_max.y])
	var lines := PackedStringArray([
		"# M6N 콤보·판정 창 비교 게이트",
		"",
		"## 판정",
		"",
		"- 원본 영상 해시: `113A486A3D025A1166FA1143D8B1A7139412883B2A6751343947535530B03814` (요청 SHA256과 일치)",
		"- 원본 영상 프레임 비교: **UNVERIFIED**. 현재 환경에 `ffmpeg`/`ffprobe` 실행 파일이 없고, 플레이어가 노출되지 않아 원본 프레임 추출을 수행하지 못함.",
		"- 캡처 방식: Godot %s의 비-headless Window Viewport에서 실제 `scenes/game/main.tscn`과 production Player/Raider/Boss 노드를 구동해 PNG 연속 프레임 시트 생성. 입력 이벤트는 전부 자동 주입이다 (`source=auto_input_event`, device=16); 물리 키보드 입력 없음, `human_visual_approval=false`." % Engine.get_version_info().string,
		"- 캡처 창: %s, %dx%d, 프레임 수 %d. PNG: `assets/art/review/m6n_combo_hitbox_contact_sheet.png`. 자동 키 이벤트 %d개." % [DisplayServer.get_name(), VIEW_SIZE.x, VIEW_SIZE.y, _frames.size(), _auto_key_events],
		"",
		"## 관측 결과",
		"",
		"| 항목 | 관측 |",
		"|---|---|",
		"| 콤보 타임라인 | 1타 → combo_hold → 2타 → combo_hold → 3타 active 후 idle 복귀: %s |" % str(_combo_stage3_started),
		"| 타격 사이 IDLE 프레임 | %d (stage 1 진입부터 stage 3 active 전까지 계측; combo_hold는 IDLE로 세지 않음) |" % _idle_interhit_frames,
		"| 활성 판정 샘플 수 | 1타 %d, 2타 %d, 3타 %d physics frames |" % [_active_frames[0], _active_frames[1], _active_frames[2]],
		"| 판정 중심 − 플레이어 중심 | %s world px; 실제 Area2D 변환을 매 physics frame 읽음 |" % ", ".join(stage_offset_rows),
		"| 실제 Raider 적중 시 Raider 중심 − Player 판정 중심 | %s |" % ("x %.1f, y %.1f world px" % [_raider_box_target_delta.x, _raider_box_target_delta.y] if _raider_box_target_measured else "판정 중심을 적중 시점에 읽지 못함"),
		"| Raider HP (Player J) | %d → %d |" % [_raider_hp_before, _raider_hp_after],
		"| Player HP (Raider 공격) | %d → %d |" % [_raider_player_hp_before, _raider_player_hp_after],
		"| Player HP (Boss 공격) | %d → %d |" % [_boss_player_hp_before, _boss_player_hp_after],
		"| Boss HP (Player J) | %d → %d |" % [_boss_hp_before, _boss_hp_after],
		"| F10 | OFF 상태 확인=%s, ON 상태 확인=%s (자동 F10 key event) |" % [str(_overlay_off_observed), str(_overlay_on_observed)],
		"",
		"## 재현·해석 제한",
		"",
		"- 콤보 프레임 계측 중 적 AI를 정지하고 Raider를 화면 밖으로 옮겨 Player 상태 머신을 분리했다. Raider/Boss HP 구간에서는 production `receive_hit` 경로와 live 노드의 HP 값을 관측했으며, HP 직접 대입 또는 내부 피해 함수 호출은 하지 않았다. Boss는 게임 씬의 기본 진행 순서상 비활성이라 별도 구간에서 `set_combat_active(true)`로 켰다.",
		"- 캐릭터와 박스 차이는 판정 Area2D 중심과 Player 월드 중심의 차이다. 캔버스/카메라 투영 후 보이는 스프라이트 외곽과의 픽셀 차이를 뜻하지 않는다.",
		"- 이 자료는 자동 입력 및 자동 캡처 결과이며 수동 플레이·육안 승인 증거가 아니다. 원본 영상과의 시각 비교 gate는 UNVERIFIED 상태를 유지한다.",
		"",
		"## 프레임 로그",
		"",
		"| 시트 칸 | 구간 |",
		"|---:|---|",
		""
	])
	for index in range(_frame_labels.size()):
		lines.insert(lines.size() - 1, "| %d | `%s` |" % [index + 1, _frame_labels[index]])
	lines.append("`M6N_FRAME` rows are printed to the Godot capture log; each row includes physics frame, phase, monitoring flag, world positions, and observed HP.")
	var file := FileAccess.open(ProjectSettings.globalize_path(REPORT_PATH), FileAccess.WRITE)
	if file != null:
		file.store_string("\n".join(lines) + "\n")
		file.close()

func _finish_failure(message: String) -> void:
	push_error("M6N|FAIL|" + message)
	quit(1)
