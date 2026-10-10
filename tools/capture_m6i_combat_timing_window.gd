extends SceneTree
"""Measure combat timing through live gameplay input and physics in a Godot Window."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/m6i_combat_timing_matrix.png"
const REPORT_PATH := "res://docs/review/m6i_combat_timing_window_gate.md"
const WINDOW_SIZE := Vector2i(1920, 1080)
const CELL_SIZE := Vector2i(640, 360)
const MAX_WAIT_MSEC := 4000

class InputObserver extends Node:
	var host: SceneTree
	func _input(event: InputEvent) -> void:
		if event is InputEventKey and event.pressed and not event.echo:
			var key := event as InputEventKey
			var source := "auto_input_event" if key.device == 16 or bool(host.call("_is_injected_key", key.physical_keycode)) else "physical_keyboard"
			host.call("_record_input", source, key.physical_keycode, Engine.get_physics_frames())

var _game: Node2D
var _player: CharacterBody2D
var _raiders: Array[CharacterBody2D] = []
var _cells: Array[Image] = []
var _events: Array[String] = []
var _results: Array[Dictionary] = []
var _observer: InputObserver
var _failures := 0
var _unverified := 0
var _combo_hits := {1: false, 2: false, 3: false}
var _skill_hits := {1: 0, 2: 0}
var _player_hit_frame := -1
var _injected_keys: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_record("UNVERIFIED", "Godot Window 캡처: 활성 디스플레이 서버가 headless")
		_finish()
		return
	root.size = WINDOW_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_record("FAIL", "실제 게임 씬을 읽지 못함: " + MAIN_SCENE)
		_finish()
		return
	_game = packed.instantiate() as Node2D
	root.add_child(_game)
	await process_frame
	_player = _game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	for i in range(1, 4):
		var raider := _game.get_node_or_null("YSortActors/ForestRaider%d" % i) as CharacterBody2D
		if raider != null:
			_raiders.append(raider)
	if _player == null or _raiders.size() < 3:
		_record("FAIL", "실제 플레이어 또는 세 ForestRaider를 찾지 못함")
		_finish()
		return
	_observer = InputObserver.new()
	_observer.host = self
	root.add_child(_observer)
	_player.attack_started.connect(_on_attack_started)
	_player.attack_hit.connect(_on_attack_hit)
	_player.skill_hit.connect(_on_skill_hit)
	_player.player_hit.connect(_on_player_hit)
	_player.global_position = Vector2(960, 780)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	# Only arrange live actors in a clear lane. Health, damage and combat receivers stay production-authored.
	for i in range(_raiders.size()):
		_raiders[i].global_position = Vector2(1650 + i * 20, 780 + i * 100)
	await _physics_frames(3)
	await _capture("00 · 실제 전투 씬", "입력 전 · 실제 Window")

	# Three ordinary J taps advance the game's buffered 1→2→3 combo.
	var combo_target := _raiders[0]
	combo_target.global_position = _player.global_position + Vector2(62, 0)
	await _physics_frames(2)
	var hp_before_combo := int(combo_target.get("health"))
	await _tap_key(KEY_J)
	var combo_ok := true
	for stage in range(1, 4):
		var startup_ok := await _wait_attack(stage, "startup")
		if not startup_ok:
			_record("FAIL", "기본 %d타 startup 진입 미관찰" % stage)
			combo_ok = false
			break
		await _capture("기본 %d타" % stage, "선딜 · hp=%d" % int(combo_target.get("health")))
		var active_ok := await _wait_attack(stage, "active")
		if not active_ok:
			_record("FAIL", "기본 %d타 active 진입 미관찰" % stage)
			combo_ok = false
			break
		var hitbox := _player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
		_record("OBSERVED", "기본 %d타 active frame=%d hitbox.monitoring=%s overlap=%d" % [stage, Engine.get_physics_frames(), hitbox.monitoring, hitbox.get_overlapping_bodies().size()])
		await _capture("기본 %d타" % stage, "명중 윈도우 · hitbox=%s" % str(hitbox.monitoring))
		if stage < 3:
			await _tap_key(KEY_J)
		var recovery_ok := await _wait_attack(stage, "recovery")
		if not recovery_ok:
			_record("FAIL", "기본 %d타 recovery 진입 미관찰" % stage)
			combo_ok = false
			break
		await _capture("기본 %d타" % stage, "후딜 · hp=%d" % int(combo_target.get("health")))
	var idle_ok := await _wait_idle()
	_record("OBSERVED" if idle_ok else "FAIL", "기본 콤보 종료 및 이동 가능 시점 frame=%d phase=%s" % [Engine.get_physics_frames(), str(_player.get("attack_phase"))])
	if int(combo_target.get("health")) < hp_before_combo:
		_record("OBSERVED", "기본 콤보 실피해 hp=%d→%d" % [hp_before_combo, int(combo_target.get("health"))])
	else:
		_record("FAIL", "기본 콤보 대상의 실제 체력 감소 미관찰")
	if not combo_ok:
		_record("UNVERIFIED", "기본 콤보의 이후 단계는 앞 단계 전투 실패로 미관찰")

	# Num4/Num5 (keypad physical codes) use the same InputEventKey path as J.
	for skill_index in range(2):
		var target := _raiders[skill_index + 1]
		if int(target.get("health")) <= 0:
			_record("UNVERIFIED", "Num%d 대상이 앞선 실제 전투에서 KO되어 스킬 시험 생략" % (skill_index + 4))
			continue
		target.global_position = _player.global_position + Vector2(68, 0)
		await _physics_frames(2)
		var hp_before := int(target.get("health"))
		var skill_key := KEY_KP_4 if skill_index == 0 else KEY_KP_5
		await _tap_key(skill_key)
		var expected_id := skill_index + 1
		var skill_label := "Num%d" % (skill_index + 4)
		var startup_ok := await _wait_skill(expected_id, "startup")
		_record("OBSERVED" if startup_ok else "FAIL", "%s 선딜 phase=%s cooldown=%.3f" % [skill_label, str(_player.get("skill_phase")), float(_player.get("skill_cooldowns")[skill_index])])
		if startup_ok:
			await _capture(skill_label, "선딜 · cooldown=%.2f" % float(_player.get("skill_cooldowns")[skill_index]))
		var active_ok := await _wait_skill(expected_id, "active")
		_record("OBSERVED" if active_ok else "FAIL", "%s 명중 윈도우 phase=%s hitbox=%s" % [skill_label, str(_player.get("skill_phase")), str(_skill_hitbox(expected_id).monitoring)])
		if active_ok:
			await _capture(skill_label, "명중 윈도우 · hitbox=%s" % str(_skill_hitbox(expected_id).monitoring))
		var recovery_ok := await _wait_skill(expected_id, "recovery")
		_record("OBSERVED" if recovery_ok else "FAIL", "%s 후딜 진입=%s cooldown=%.3f" % [skill_label, str(recovery_ok), float(_player.get("skill_cooldowns")[skill_index])])
		if recovery_ok:
			await _capture(skill_label, "후딜 · cooldown=%.2f" % float(_player.get("skill_cooldowns")[skill_index]))
		var skill_idle := await _wait_skill_idle()
		_record("OBSERVED" if skill_idle else "FAIL", "%s 종료/이동 가능 frame=%d" % [skill_label, Engine.get_physics_frames()])
		_record("OBSERVED" if _skill_hits[expected_id] > 0 else "FAIL", "%s production skill_hit signal count=%d" % [skill_label, _skill_hits[expected_id]])
		_record("OBSERVED" if int(target.get("health")) < hp_before else "FAIL", "%s 실제 피해 hp=%d→%d" % [skill_label, hp_before, int(target.get("health"))])
	await _verify_movement("기본 콤보·Num4·Num5 이후")

	# Observe enemy windup/active/contact and the real Player hit reaction and recovery.
	var counter_target: CharacterBody2D = null
	for candidate in _raiders:
		if int(candidate.get("health")) > 0:
			counter_target = candidate
			break
	if counter_target == null:
		_record("UNVERIFIED", "생존 적이 없어 적 반격→플레이어 경직 재현 불가")
	else:
		counter_target.global_position = _player.global_position + Vector2(74, 0)
		await _physics_frames(2)
		var counter_windup := await _wait_enemy_phase(counter_target, "windup")
		_record("OBSERVED" if counter_windup else "UNVERIFIED", "적 반격 선딜=%s frame=%d" % [str(counter_windup), Engine.get_physics_frames()])
		if counter_windup:
			await _capture("적 반격", "선딜")
		var counter_active := await _wait_enemy_phase(counter_target, "active")
		_record("OBSERVED" if counter_active else "UNVERIFIED", "적 반격 active=%s" % str(counter_active))
		if counter_active:
			await _capture("적 반격", "명중 윈도우")
		var hit_deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
		while _player_hit_frame < 0 and Time.get_ticks_msec() < hit_deadline:
			await physics_frame
		var hitstun := float(_player.get("hitstun_remaining")) > 0.0
		_record("OBSERVED" if hitstun else "UNVERIFIED", "플레이어 피격/경직 frame=%d hitstun=%.3f hp=%d" % [Engine.get_physics_frames(), float(_player.get("hitstun_remaining")), int(_player.get("health"))])
		if hitstun:
			await _capture("플레이어 피격", "경직 · hitstun=%.2f" % float(_player.get("hitstun_remaining")))
			var recovery_deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
			while float(_player.get("hitstun_remaining")) > 0.0 and Time.get_ticks_msec() < recovery_deadline:
				await physics_frame
			_record("OBSERVED" if float(_player.get("hitstun_remaining")) <= 0.0 else "FAIL", "플레이어 경직 회복 frame=%d remaining=%.3f" % [Engine.get_physics_frames(), float(_player.get("hitstun_remaining"))])
			await _verify_movement("플레이어 경직 회복")
			await _capture("플레이어 피격", "회복 완료")
		else:
			_record("UNVERIFIED", "실제 적 공격에 의한 플레이어 경직 캡처 미관찰")

	if _cells.is_empty():
		_record("FAIL", "실제 Window 캡처 프레임이 없음")
	else:
		var rows := ceili(float(_cells.size()) / 3.0)
		var board := Image.create(CELL_SIZE.x * 3, CELL_SIZE.y * rows, false, Image.FORMAT_RGBA8)
		for i in range(_cells.size()):
			var cell := _cells[i]
			cell.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_LANCZOS)
			board.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i((i % 3) * CELL_SIZE.x, (i / 3) * CELL_SIZE.y))
		var error := board.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		_record("OBSERVED" if error == OK else "FAIL", "Godot Window 캡처 매트릭스 저장=%s frames=%d" % [str(error == OK), _cells.size()])
	_finish()

func _record_input(source: String, keycode: int, frame: int) -> void:
	var name := "J" if keycode == KEY_J else ("Num4" if keycode == KEY_KP_4 else ("Num5" if keycode == KEY_KP_5 else ("A" if keycode == KEY_A else str(keycode))))
	var line := "INPUT|source=%s|key=%s|physics_frame=%d|ticks_usec=%d" % [source, name, frame, Time.get_ticks_usec()]
	_events.append(line)
	print(line)

func _tap_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.device = 16
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	_injected_keys[keycode] = true
	Input.parse_input_event(event)
	await _physics_frames(1)
	var action := "attack" if keycode == KEY_J else ("skill_1" if keycode == KEY_KP_4 else "skill_2")
	_record("TRACE", "synthetic InputEventKey keycode=%d action=%s" % [keycode, action])
	event = InputEventKey.new()
	event.device = 16
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = false
	Input.parse_input_event(event)
	_injected_keys.erase(keycode)
	await _physics_frames(1)

func _is_injected_key(keycode: int) -> bool:
	return _injected_keys.has(keycode)

func _on_attack_started(stage: int) -> void:
	_record("OBSERVED", "basic_%d startup frame=%d" % [stage, Engine.get_physics_frames()])

func _on_attack_hit(stage: int) -> void:
	_combo_hits[stage] = true
	_record("OBSERVED", "basic_%d actual_attack_hit frame=%d" % [stage, Engine.get_physics_frames()])

func _on_skill_hit(skill_id: int) -> void:
	_skill_hits[skill_id] += 1
	_record("OBSERVED", "skill_%d actual_skill_hit frame=%d" % [skill_id, Engine.get_physics_frames()])

func _on_player_hit(stage: int) -> void:
	_player_hit_frame = Engine.get_physics_frames()
	_record("OBSERVED", "player_hit stage=%d frame=%d hitstun=%.3f" % [stage, _player_hit_frame, float(_player.get("hitstun_remaining"))])

func _wait_attack(stage: int, phase: String) -> bool:
	return await _wait_property("attack_stage", stage, "attack_phase", phase)

func _wait_skill(skill: int, phase: String) -> bool:
	return await _wait_property("skill_id", skill, "skill_phase", phase)

func _wait_property(id_property: String, id_value: int, phase_property: String, phase_value: String) -> bool:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if int(_player.get(id_property)) == id_value and str(_player.get(phase_property)) == phase_value:
			return true
	return false

func _wait_idle() -> bool:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if int(_player.get("attack_stage")) == 0 and str(_player.get("attack_phase")) == "idle":
			return true
	return false

func _wait_skill_idle() -> bool:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if str(_player.get("skill_phase")) == "idle":
			return true
	return false

func _wait_enemy_phase(enemy: Node, phase: String) -> bool:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if str(enemy.get("attack_phase")) == phase:
			return true
	return false

func _skill_hitbox(skill_id: int) -> Area2D:
	return _player.get_node("Hitboxes/Skill%dHitbox" % skill_id) as Area2D

func _physics_frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func _verify_movement(label: String) -> void:
	var before := _player.global_position
	var event := InputEventKey.new()
	event.device = 16
	event.physical_keycode = KEY_A
	event.keycode = KEY_A
	event.pressed = true
	_injected_keys[KEY_A] = true
	Input.parse_input_event(event)
	await _physics_frames(6)
	event = InputEventKey.new()
	event.device = 16
	event.physical_keycode = KEY_A
	event.keycode = KEY_A
	event.pressed = false
	Input.parse_input_event(event)
	_injected_keys.erase(KEY_A)
	await _physics_frames(1)
	var moved := _player.global_position.distance_to(before) > 1.0
	_record("OBSERVED" if moved else "FAIL", "%s 실제 이동 입력으로 조작 재개=%s 이동량=%.1fpx" % [label, str(moved), _player.global_position.distance_to(before)])

func _capture(label: String, beat: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.is_empty():
		_record("FAIL", "%s %s Window image readback 실패" % [label, beat])
		return
	_cells.append(frame)
	_record("CAPTURE", "%s · %s · physics_frame=%d player_hp=%d attack=%s/%s skill=%s/%s hitstun=%.3f" % [label, beat, Engine.get_physics_frames(), int(_player.get("health")), str(_player.get("attack_stage")), str(_player.get("attack_phase")), str(_player.get("skill_id")), str(_player.get("skill_phase")), float(_player.get("hitstun_remaining"))])

func _record(status: String, message: String) -> void:
	if status == "FAIL":
		_failures += 1
	elif status == "UNVERIFIED":
		_unverified += 1
	var ticks := Time.get_ticks_usec()
	var line := "M6I|%s|ticks_usec=%d|%s" % [status, ticks, message]
	_results.append({"status": status, "message": message, "ticks_usec": ticks})
	print(line)

func _finish() -> void:
	_write_report()
	print("M6I_SUMMARY|fail=%d|unverified=%d|captures=%d" % [_failures, _unverified, _cells.size()])
	quit(1 if _failures > 0 else 0)

func _write_report() -> void:
	var lines := PackedStringArray([
		"# M6I Combat Timing Window Gate",
		"",
		"Godot Window의 `scenes/game/main.tscn`에서 실제 플레이어·ForestRaider 노드를 실행해 기록했습니다. 측정시각은 `Time.get_ticks_usec()`와 물리 프레임 번호를 사용합니다.",
		"",
		"## 입력 출처",
		"",
		"이 자동 실행에서 `Input.parse_input_event(InputEventKey)`로 보낸 J, Num4, Num5는 자동 이벤트 표식과 device 16으로 `auto_input_event`에 분류합니다. 나머지 실제 Window 키 입력은 `physical_keyboard`로 별도 기록합니다. 이번 캡처 실행에서 물리 키 입력이 없으면 그 사실을 UNVERIFIED로 표시합니다.",
		"",
		"## 판정",
		"",
		"FAIL/UNVERIFIED는 관찰 실패를 성공으로 치환하지 않습니다. 배우 위치만 장면 준비를 위해 배치했으며 체력, 피해, 적의 공격 결과를 직접 수정하거나 전투 내부 시작/명중/승리 함수를 호출하지 않았습니다.",
		"",
		"| 상태 | 시각(usec) | 관찰 |",
		"|---|---:|---|"
	])
	for row in _results:
		var message := str(row["message"]).replace("|", "\\|").replace("\n", " ")
		lines.append("| %s | %d | %s |" % [row["status"], int(row["ticks_usec"]), message])
	var physical_seen := false
	for line in _events:
		var parts := line.split("|")
		var source := "unclassified"
		var key := "?"
		var frame := "?"
		var ticks := "0"
		for part in parts:
			if part.begins_with("source="):
				source = part.trim_prefix("source=")
			elif part.begins_with("key="):
				key = part.trim_prefix("key=")
			elif part.begins_with("physics_frame="):
				frame = part.trim_prefix("physics_frame=")
			elif part.begins_with("ticks_usec="):
				ticks = part.trim_prefix("ticks_usec=")
		lines.append("| INPUT:%s | %s | key=%s physics_frame=%s |" % [source, ticks, key, frame])
		if source == "physical_keyboard":
			physical_seen = true
	if not physical_seen:
		lines.append("| UNVERIFIED | %d | 실제 물리 키보드 이벤트는 이 자동 Window 실행에서 관찰되지 않음 |" % Time.get_ticks_usec())
	lines.append("")
	lines.append("## 캡처")
	lines.append("")
	lines.append("실제 Window 프레임 매트릭스: `assets/art/review/m6i_combat_timing_matrix.png` (%d frame(s))." % _cells.size())
	lines.append("")
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("M6I report write failed: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string("\n".join(lines) + "\n")
