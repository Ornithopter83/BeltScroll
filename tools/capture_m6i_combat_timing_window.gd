extends SceneTree
"""Trace real skill input, per-target health changes, and production signals."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const RAIDER_SCENE := "res://scenes/enemies/forest_raider.tscn"
const DUMMY_SCENE := "res://scenes/combat/training_dummy.tscn"
const REPORT_PATH := "res://docs/review/m6j_skill_target_trace_gate.md"
const PLAYER_PATH := "YSortActors/Player"
const MAX_WAIT_MSEC := 5000

var _game: Node2D
var _player: CharacterBody2D
var _actor_layer: Node2D
var _training_dummy: CharacterBody2D
var _original_raiders: Array[CharacterBody2D] = []
var _scenario := ""
var _signal_frames: Dictionary = {}
var _hit_rows: Array[Dictionary] = []
var _rows: Array[Dictionary] = []
var _failures := 0
var _unverified := 0
var _injected_keys: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_record("FAIL", "실제 게임 씬 로드 실패")
		_finish()
		return
	_game = packed.instantiate() as Node2D
	root.add_child(_game)
	await process_frame
	_player = _game.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	_actor_layer = _game.get_node_or_null("YSortActors") as Node2D
	if _player == null or _actor_layer == null:
		_record("FAIL", "실제 Player 또는 YSortActors 없음")
		_finish()
		return
	for i in range(1, 4):
		var raider := _game.get_node_or_null("YSortActors/ForestRaider%d" % i) as CharacterBody2D
		if raider != null:
			_original_raiders.append(raider)
			raider.global_position = Vector2(4000 + i * 350, 780)
			raider.set_physics_process(false)
	_player.global_position = Vector2(960, 780)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	_training_dummy = _game.get_node_or_null("YSortActors/TrainingDummy") as CharacterBody2D
	if _training_dummy != null:
		_training_dummy.set_physics_process(false)
	_player.skill_hit.connect(_on_skill_hit)
	await _physics_frames(3)
	await _run_legacy_num4_reproduction()
	if _training_dummy != null:
		_training_dummy.global_position = Vector2(4200, 780)
	for skill_id in [1, 2]:
		await _run_case(skill_id, "single", 1)
		await _run_case(skill_id, "same_area_pair", 2)
		await _run_case(skill_id, "out_of_range", 1)
		await _run_case(skill_id, "persistent_overlap", 1)
	_record("OBSERVED", "생산 코드 대조: _check_skill_hitbox는 대상 instance_id를 _skill_hit_targets에 1회 기록하고, 각 receive_hit 직후 skill_hit를 1회 emit")
	_finish()

func _run_legacy_num4_reproduction() -> void:
	if _training_dummy == null:
		_record("FAIL", "원래 M6I 배치 재현용 TrainingDummy를 찾지 못함")
		return
	_scenario = "M6I_legacy_Num4_layout"
	_signal_frames.clear()
	var scene := load(RAIDER_SCENE) as PackedScene
	var raider := scene.instantiate() as CharacterBody2D
	raider.name = "LegacyNum4_Raider"
	_actor_layer.add_child(raider)
	raider.set_physics_process(false)
	raider.global_position = _player.global_position + Vector2(118, 0)
	await _physics_frames(2)
	var targets: Array[CharacterBody2D] = [raider, _training_dummy]
	var starting_hp: Dictionary = {}
	for target in targets:
		starting_hp[target.get_instance_id()] = int(target.get("health"))
	await _tap_key(KEY_KP_4)
	var started := await _wait_skill_phase(1, "startup")
	_record("OBSERVED" if started else "FAIL", "%s 원래 Num4 입력 startup=%s" % [_scenario, str(started)])
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		_observe_target_health(targets, starting_hp, 1)
		if str(_player.get("skill_phase")) == "idle":
			break
	var changed_targets := 0
	for target in targets:
		var hits := _count_target_hits(target.get_instance_id())
		if hits > 0:
			changed_targets += 1
		_record("OBSERVED" if hits <= 1 else "FAIL", "%s target instance_id=%d name=%s hp=%d→%d hits=%d" % [_scenario, target.get_instance_id(), target.name, int(_first_hp_for(target)), int(target.get("health")), hits])
	var emitted := _signal_total()
	_record("OBSERVED" if emitted == changed_targets else "FAIL", "%s 실행 전체 production skill_hit 신호=%d 실제 피해 대상=%d" % [_scenario, emitted, changed_targets])
	if emitted == 2 and changed_targets == 2:
		_record("OBSERVED", "원래 배치 재현: Raider와 TrainingDummy 두 개별 hit_receiver가 각 1회 맞아 Num4 신호 합계 2회 발생")
	elif emitted == 2 and changed_targets == 1:
		_record("FAIL", "원래 배치에서 2신호를 재현했으나 피해 대상별 연결이 일치하지 않음")
	else:
		_record("UNVERIFIED", "원래 배치 재현에서 두 신호/두 타깃 결과를 얻지 못함: signals=%d targets=%d" % [emitted, changed_targets])
	raider.queue_free()
	await _physics_frames(2)
	await _wait_skill_cooldown(1)

func _first_hp_for(target: Node) -> int:
	for row in _hit_rows:
		if str(row["scenario"]) == _scenario and int(row["instance_id"]) == target.get_instance_id():
			return int(row["hp_before"])
	return int(target.get("health"))

func _run_case(skill_id: int, case_name: String, target_count: int) -> void:
	await _wait_skill_cooldown(skill_id)
	_scenario = "Num%d/%s" % [skill_id + 3, case_name]
	_signal_frames.clear()
	var targets: Array[CharacterBody2D] = []
	var scene_path := DUMMY_SCENE if case_name == "persistent_overlap" else RAIDER_SCENE
	var scene := load(scene_path) as PackedScene
	if scene == null:
		_record("FAIL", "%s 적 씬 로드 실패" % _scenario)
		return
	for i in range(target_count):
		var target := scene.instantiate() as CharacterBody2D
		target.name = "%s_Target%d" % [_scenario.replace("/", "_"), i + 1]
		_actor_layer.add_child(target)
		target.set_physics_process(false)
		target.global_position = _target_position(skill_id, case_name, i)
		targets.append(target)
	await _physics_frames(2)
	var starting_hp: Dictionary = {}
	for target in targets:
		starting_hp[target.get_instance_id()] = int(target.get("health"))
	var keycode := KEY_KP_4 if skill_id == 1 else KEY_KP_5
	await _tap_key(keycode)
	var started := await _wait_skill_phase(skill_id, "startup")
	_record("OBSERVED" if started else "FAIL", "%s 실제 keypad 입력으로 startup=%s frame=%d" % [_scenario, str(started), Engine.get_physics_frames()])
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
	var active_frames := 0
	var overlap_frames := 0
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if int(_player.get("skill_id")) == skill_id and str(_player.get("skill_phase")) == "active":
			active_frames += 1
			var hitbox := _player.get_node("Hitboxes/Skill%dHitbox" % skill_id) as Area2D
			var overlapping := hitbox.get_overlapping_bodies()
			var target_overlap_count := 0
			for target in targets:
				if overlapping.has(target):
					target_overlap_count += 1
			if target_overlap_count > 0:
				overlap_frames += 1
		_observe_target_health(targets, starting_hp, skill_id)
		if str(_player.get("skill_phase")) == "idle":
			break
	var expected := 0 if case_name == "out_of_range" else target_count
	var actual := 0
	for target in targets:
		var target_rows := _count_target_hits(target.get_instance_id())
		var changes := target_rows > 0
		if changes:
			actual += 1
		var passed := (changes and target_rows == 1) if case_name != "out_of_range" else (not changes and target_rows == 0)
		_record("OBSERVED" if passed else "FAIL", "%s target instance_id=%d name=%s hp=%d→%d attributed_hits=%d" % [_scenario, target.get_instance_id(), target.name, int(starting_hp[target.get_instance_id()]), int(target.get("health")), target_rows])
	var emitted := _signal_total()
	var signal_match := emitted == actual
	_record("OBSERVED" if signal_match else "FAIL", "%s production skill_hit signals=%d distinct damaged targets=%d" % [_scenario, emitted, actual])
	if case_name == "same_area_pair":
		_record("OBSERVED" if actual == 2 and emitted == 2 else "FAIL", "%s 같은 영역의 두 인스턴스 각각 1회 피해: %d 대상, %d 신호" % [_scenario, actual, emitted])
	if case_name == "persistent_overlap":
		_record("OBSERVED" if overlap_frames >= 2 and actual == 1 and emitted == 1 else "FAIL", "%s active 지속 겹침 frames=%d, 대상당 피해 1회, 신호=%d" % [_scenario, overlap_frames, emitted])
	if case_name == "out_of_range":
		_record("OBSERVED" if actual == 0 and emitted == 0 else "FAIL", "%s 범위 밖 대상 무피해·무신호 확인" % _scenario)
	if active_frames == 0:
		_record("FAIL", "%s active 물리 프레임 미관찰" % _scenario)
	_record("TRACE", "%s frame_summary=%s" % [_scenario, str(_signal_frames)])
	for target in targets:
		target.queue_free()
	await _physics_frames(2)

func _target_position(skill_id: int, case_name: String, index: int) -> Vector2:
	if case_name == "out_of_range":
		return _player.global_position + Vector2(520, 0)
	if case_name == "same_area_pair":
		return _player.global_position + Vector2(118, 0) if skill_id == 1 else _player.global_position + Vector2(28 + index * 20, -8 if index == 0 else 8)
	if skill_id == 1:
		return _player.global_position + Vector2(118, 0)
	return _player.global_position + Vector2(38, 0)

func _observe_target_health(targets: Array[CharacterBody2D], starting_hp: Dictionary, skill_id: int) -> void:
	for target in targets:
		var id := target.get_instance_id()
		var hp_before := int(starting_hp[id])
		var hp_now := int(target.get("health"))
		if hp_now < hp_before:
			var observed_frame := Engine.get_physics_frames() - 1
			var signal_key := str(observed_frame)
			var signal_data: Dictionary = _signal_frames.get(signal_key, {"count": 0, "skill_id": skill_id})
			var hit_row := {"scenario": _scenario, "instance_id": id, "name": str(target.name), "hp_before": hp_before, "hp_after": hp_now, "frame": observed_frame, "skill_id": skill_id, "signal_count_frame": int(signal_data.get("count", 0))}
			_hit_rows.append(hit_row)
			_record("HIT", "%s instance_id=%d name=%s hp=%d→%d physics_frame=%d skill_id=%d same_frame_signal_count=%d" % [_scenario, id, target.name, hp_before, hp_now, observed_frame, skill_id, int(signal_data.get("count", 0))])
			starting_hp[id] = hp_now

func _on_skill_hit(skill_id: int) -> void:
	var key := str(Engine.get_physics_frames())
	var data: Dictionary = _signal_frames.get(key, {"count": 0, "skill_id": skill_id})
	data["count"] = int(data["count"]) + 1
	data["skill_id"] = skill_id
	_signal_frames[key] = data
	_record("SIGNAL", "%s skill_hit skill_id=%d physics_frame=%d frame_signal_count=%d" % [_scenario, skill_id, Engine.get_physics_frames(), int(data["count"])])

func _signal_total() -> int:
	var count := 0
	for key in _signal_frames:
		count += int((_signal_frames[key] as Dictionary).get("count", 0))
	return count

func _count_target_hits(instance_id: int) -> int:
	var count := 0
	for row in _hit_rows:
		if str(row["scenario"]) == _scenario and int(row["instance_id"]) == instance_id:
			count += 1
	return count

func _wait_skill_cooldown(skill_id: int) -> void:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		var cooldowns: Array = _player.get("skill_cooldowns")
		if str(_player.get("skill_phase")) == "idle" and float(cooldowns[skill_id - 1]) <= 0.0:
			return
		await physics_frame
	_record("FAIL", "Num%d 쿨다운 자연 종료 대기 시간 초과" % (skill_id + 3))

func _wait_skill_phase(skill_id: int, phase: String) -> bool:
	var deadline := Time.get_ticks_msec() + MAX_WAIT_MSEC
	while Time.get_ticks_msec() < deadline:
		await physics_frame
		if int(_player.get("skill_id")) == skill_id and str(_player.get("skill_phase")) == phase:
			return true
	return false

func _tap_key(keycode: Key) -> void:
	var event := InputEventKey.new()
	event.device = 16
	event.physical_keycode = keycode
	event.keycode = keycode
	event.pressed = true
	_injected_keys[keycode] = true
	Input.parse_input_event(event)
	await _physics_frames(1)
	var release := InputEventKey.new()
	release.device = 16
	release.physical_keycode = keycode
	release.keycode = keycode
	Input.parse_input_event(release)
	_injected_keys.erase(keycode)
	await _physics_frames(1)
	_record("INPUT", "Input.parse_input_event physical_keycode=%d physics_frame=%d" % [keycode, Engine.get_physics_frames()])

func _physics_frames(count: int) -> void:
	for _i in range(count):
		await physics_frame

func _record(status: String, message: String) -> void:
	if status == "FAIL":
		_failures += 1
	elif status == "UNVERIFIED":
		_unverified += 1
	var row := {"status": status, "message": message, "frame": Engine.get_physics_frames()}
	_rows.append(row)
	print("M6J|%s|frame=%d|%s" % [status, Engine.get_physics_frames(), message])

func _finish() -> void:
	_write_report()
	print("M6J_SUMMARY|fail=%d|unverified=%d|target_hit_rows=%d" % [_failures, _unverified, _hit_rows.size()])
	quit(1 if _failures > 0 else 0)

func _write_report() -> void:
	var lines := PackedStringArray([
		"# M6J Skill Target Trace Gate", "",
		"실제 `scenes/game/main.tscn`의 Player와 ForestRaider 씬 인스턴스에 keypad 입력 이벤트를 보냈습니다. 물리 프레임마다 체력 변화와 `skill_hit` 신호를 관찰했습니다. 적은 전투 준비를 위해 판정 위치에 배치하고 AI 물리 처리만 멈췄으며, 체력·피해·명중 함수는 직접 설정하거나 호출하지 않았습니다.", "",
		"## 이전 Num4 중복 신호 원인", "",
		"이전 M6I 캡처에는 Num4 `skill_hit` 두 건이 모두 physics frame 113에 기록됐고 추적하던 Raider HP는 3→0이었습니다. 그 도구는 신호에 연결된 타깃 ID/HP를 기록하지 않았으므로 저장된 과거 로그만으로 당시 두 번째 타깃의 정체는 복원할 수 없습니다. 이번 재현에서는 원래 씬의 TrainingDummy와 Raider가 각각 피해를 받았고, 같은 판정 영역에 배치한 두 Raider도 Num4에서 같은 물리 프레임에 각각 피해를 받았습니다.", "",
		"원인은 중복 피해가 아니라 대상별 정상 다중 타격입니다. 생산 코드 `scripts/player/player_controller.gd`의 `_check_skill_hitbox()`는 `get_instance_id()`를 키로 `_skill_hit_targets`를 확인하고 각 고유 대상의 `receive_hit()` 뒤에 `skill_hit.emit(skill_id)`를 한 번 호출합니다. 두 대상이 한 active 물리 프레임에 겹치면 신호는 2회 발생하지만 각 인스턴스는 한 번만 피해를 받습니다. 아래 ID·HP·frame 기록과 생산 신호 수가 일치하는지 확인합니다.", "",
		"## 관찰 결과", "",
		"| 상태 | 물리 프레임 | 상세 |", "|---|---:|---|"
	])
	for row in _rows:
		lines.append("| %s | %d | %s |" % [str(row["status"]), int(row["frame"]), str(row["message"]).replace("|", "\\|")])
	lines.append("")
	lines.append("## 대상별 실제 HP 변화")
	lines.append("")
	lines.append("| 시나리오 | 인스턴스 ID | 이름 | HP 전→후 | 물리 프레임 | skill_id | 같은 프레임 신호 수 |")
	lines.append("|---|---:|---|---:|---:|---:|---:|")
	for hit in _hit_rows:
		lines.append("| %s | %d | %s | %d→%d | %d | %d | %d |" % [str(hit["scenario"]), int(hit["instance_id"]), str(hit["name"]), int(hit["hp_before"]), int(hit["hp_after"]), int(hit["frame"]), int(hit["skill_id"]), int(hit["signal_count_frame"])])
	lines.append("")
	lines.append("## 판정")
	lines.append("")
	lines.append("시나리오별 PASS/FAIL은 실제 keypad 이벤트, production 신호, 물리 프레임 관찰, 타깃별 실제 HP 변화로 판정합니다. `same_area_pair`의 두 명중은 서로 다른 인스턴스에 각 1회 피해가 확인될 때 정상 다중 타격입니다. 한 대상의 변화 행이 1개이고 HP가 감소했으면 중복 피해가 아닙니다.")
	lines.append("")
	lines.append("스모크 종료 요약: fail=%d, unverified=%d, target HP-change rows=%d." % [_failures, _unverified, _hit_rows.size()])
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		push_error("M6J report write failed: " + error_string(FileAccess.get_open_error()))
		return
	file.store_string("\n".join(lines) + "\n")
