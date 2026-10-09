extends SceneTree
"""Windowed integration gate: a live ForestRaider AttackArea interrupts each Player skill phase."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const EVIDENCE_PATH := "res://assets/art/review/player_skill_interruption_window.png"
const REPORT_PATH := "res://docs/review/player_skill_interruption_gate.md"
const PLAYER_PATH := "YSortActors/Player"
const PHASES := ["startup", "active", "recovery"]

class PhaseProbe:
	extends Node
	var player: Node
	var observed_phase := "idle"
	func _physics_process(_delta: float) -> void:
		observed_phase = str(player.get("skill_phase"))

var failures: Array[String] = []
var records: Array[String] = []
var event_stamp := ""

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Window 렌더러가 필요합니다.")
		return
	root.size = Vector2i(1920, 1080)
	for skill_id in [1, 2]:
		for phase in PHASES:
			for facing in [1, -1]:
				await _run_interruption(skill_id, phase, facing)
	await _run_guard_regression()
	await _run_ko_regression()
	await _run_hit_stop_regression()
	await _run_restart_regression()
	_save_directional_evidence()
	_write_report()
	if failures.is_empty():
		print("player_skill_interruption_window: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("player_skill_interruption_window: " + failure)
		quit(1)

func _new_game() -> Dictionary:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("본편 게임 장면 로드")
		return {}
	var game := packed.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	var evidence_layer := CanvasLayer.new()
	evidence_layer.name = "SkillInterruptionEvidence"
	evidence_layer.layer = 50
	game.add_child(evidence_layer)
	var evidence_panel := PanelContainer.new()
	evidence_panel.name = "EvidencePanel"
	evidence_panel.anchor_left = 0.04
	evidence_panel.anchor_top = 0.56
	evidence_panel.anchor_right = 0.96
	evidence_panel.anchor_bottom = 0.96
	evidence_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	evidence_layer.add_child(evidence_panel)
	var evidence_label := Label.new()
	evidence_label.name = "EventLabel"
	evidence_label.text = "상대 공격 피격 중단 검수 대기"
	evidence_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	evidence_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	evidence_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	evidence_label.add_theme_font_size_override("font_size", 28)
	evidence_label.add_theme_color_override("font_color", Color(0.94, 0.93, 0.84, 1.0))
	evidence_panel.add_child(evidence_label)
	game.set_meta("skill_interruption_evidence_label", evidence_label)
	await process_frame
	var player := game.get_node_or_null(PLAYER_PATH)
	var raiders: Array = game.get_node("YSortActors").get_children().filter(func(child): return child.is_in_group("forest_raiders"))
	if player == null or raiders.is_empty():
		_fail("본편 Player와 ForestRaider가 존재")
		return {}
	for raider_index in range(raiders.size()):
		var raider: Node = raiders[raider_index]
		raider.set_physics_process(false)
		(raider.get_node("AttackArea") as Area2D).monitoring = false
		if raider_index > 0:
			raider.global_position = Vector2(180.0 if raider_index == 1 else 1740.0, 120.0)
	return {"game": game, "player": player, "raider": raiders[0]}

func _run_interruption(skill_id: int, wanted_phase: String, facing_sign: int) -> Dictionary:
	var actors := await _new_game()
	if actors.is_empty():
		return {}
	var game: Node = actors.game
	var player: CharacterBody2D = actors.player
	var raider: CharacterBody2D = actors.raider
	player.global_position = Vector2(960.0, 790.0)
	player.set("facing_direction", Vector2(float(facing_sign), 0.0))
	player.get_node("VisualRoot").scale.x = float(facing_sign)
	raider.global_position = Vector2(960.0 - facing_sign * 330.0, 790.0)
	raider.set("arena_bounds", Rect2(Vector2(120.0, 100.0), Vector2(1680.0, 880.0)))
	await _frames(2)
	var skill_action := "skill_1" if skill_id == 1 else "skill_2"
	Input.action_press(skill_action)
	await physics_frame
	Input.action_release(skill_action)
	var phase_reached := await _wait_skill_phase(player, skill_id, wanted_phase, 30)
	_check(phase_reached, "Num%d %s 실제 스킬 단계 진입 (%s)" % [skill_id + 3, wanted_phase, _direction_name(facing_sign)])
	if not phase_reached:
		game.queue_free()
		await process_frame
		return {}
	var cooldown_before := float(player.get("skill_cooldowns")[skill_id - 1])
	# Window rendering can introduce uneven frame pacing. Hold the already reached
	# live phase long enough for the Raider's real AI windup to land deterministically.
	player.set("skill_phase_remaining", maxf(float(player.get("skill_phase_remaining")), 0.30))
	# Zero-time windup makes the authored AI transition into active on the next
	# physics tick, keeping the hit inside the requested Player phase.
	raider.set("windup_duration", 0.0)
	raider.process_physics_priority = 1
	var phase_probe := PhaseProbe.new()
	phase_probe.player = player
	phase_probe.process_physics_priority = -1
	game.add_child(phase_probe)
	# Keep the raider behind the dash/spin direction so Player's active skill hitbox
	# cannot stun the attacker before its live AttackArea reaches Player.
	raider.global_position = player.global_position + Vector2(float(facing_sign) * 30.0, 0.0)
	# This gate is about incoming attacks. Keep the raider a live hit receiver for
	# Raider AttackArea while excluding it from Player skill hitbox targeting.
	raider.collision_layer = 0
	raider.set("attack_phase", "idle")
	raider.set_physics_process(true)
	var receive_observations: Array[Dictionary] = []
	player.player_hit.connect(func(stage): receive_observations.append({"stage": stage, "phase": phase_probe.observed_phase, "physics_frame": Engine.get_physics_frames(), "ticks_msec": Time.get_ticks_msec()}))
	raider.attack_windup_started.connect(func(): records.append("- 적 공격 시작: skill=%d phase=%s dir=%s physics_frame=%d ticks_msec=%d" % [skill_id, wanted_phase, _direction_name(facing_sign), Engine.get_physics_frames(), Time.get_ticks_msec()]))
	var was_in_raider_attack := await _wait_until_hit(player, raider, receive_observations, 55)
	if was_in_raider_attack:
		var observation: Dictionary = receive_observations[0]
		event_stamp = "player_hit: phase=%s physics_frame=%d ticks_msec=%d" % [observation.phase, observation.physics_frame, observation.ticks_msec]
		_check(observation.phase == wanted_phase, "실제 Player.player_hit가 요청 단계 %s에서 발생 (%s향)" % [wanted_phase, _direction_name(facing_sign)])
		_check(player.get("skill_phase") == "idle" and int(player.get("skill_id")) == 0, "receive_hit 경로가 Num%d를 취소" % (skill_id + 3))
		_check(float(player.get("hitstun_remaining")) > 0.0, "피격 후 hitstun 유지")
		_check(not (player.get_node("Hitboxes/Skill1Hitbox") as Area2D).monitoring and not (player.get_node("Hitboxes/Skill2Hitbox") as Area2D).monitoring, "Skill1/2Hitbox 모두 OFF")
		_check(not (player.get_node("VisualRoot/AttackFlash") as Polygon2D).visible, "스킬 VFX AttackFlash 제거")
		_check(int(player.get("health")) < int(player.get("max_health")), "실제 적 공격으로 체력 감소")
		_check(float(player.get("skill_cooldowns")[skill_id - 1]) > 0.0 and float(player.get("skill_cooldowns")[skill_id - 1]) <= cooldown_before, "중단 후 시작된 쿨다운 유지")
		var evidence_label := game.get_meta("skill_interruption_evidence_label") as Label
		evidence_label.text = "Num%d  ·  %s  ·  %s\n실제 ForestRaider AttackArea 피격 / Player.receive_hit\nphysics_frame %d   ·   ticks_msec %d" % [skill_id + 3, wanted_phase, _direction_name(facing_sign), observation.physics_frame, observation.ticks_msec]
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		_check(image != null and not image.is_empty(), "실제 Window frame_post_draw 이미지 (%s향)" % _direction_name(facing_sign))
		var moved_before := player.global_position.x
		await _wait_hitstun_end(player, 80)
		Input.action_press("move_right" if facing_sign > 0 else "move_left")
		await _frames(6)
		Input.action_release("move_right" if facing_sign > 0 else "move_left")
		_check(absf(player.global_position.x - moved_before) > 4.0, "hitstun 뒤 이동 입력 복귀")
		records.append("- 피격 확인: skill=%d wanted_phase=%s observed_phase=%s dir=%s event={%s} render_frame=%d render_ticks_msec=%d cooldown=%.3f" % [skill_id, wanted_phase, observation.phase, _direction_name(facing_sign), event_stamp, Engine.get_frames_drawn(), Time.get_ticks_msec(), float(player.get("skill_cooldowns")[skill_id - 1])])
		if image != null and not image.is_empty():
			if not has_meta("directional_images"):
				set_meta("directional_images", {})
			var saved: Dictionary = get_meta("directional_images")
			if not saved.has(facing_sign):
				saved[facing_sign] = image
			set_meta("directional_images", saved)
	else:
		_check(false, "ForestRaider AttackArea가 실제 receive_hit을 발생 (%s %s)" % [skill_id, wanted_phase])
	game.queue_free()
	await process_frame
	return {"hit": was_in_raider_attack}

func _wait_until_hit(player: Node, raider: Node, observations: Array[Dictionary], max_frames: int) -> bool:
	for _i in range(max_frames):
		if not observations.is_empty():
			return true
		await physics_frame
	return not observations.is_empty()

func _wait_skill_phase(player: Node, skill_id: int, phase: String, max_frames: int) -> bool:
	for _i in range(max_frames):
		if int(player.get("skill_id")) == skill_id and str(player.get("skill_phase")) == phase:
			return true
		await physics_frame
	return int(player.get("skill_id")) == skill_id and str(player.get("skill_phase")) == phase

func _wait_hitstun_end(player: Node, max_frames: int) -> void:
	for _i in range(max_frames):
		if float(player.get("hitstun_remaining")) <= 0.0:
			return
		await physics_frame

func _run_guard_regression() -> void:
	var actors := await _new_game()
	if actors.is_empty(): return
	var player: Node = actors.player
	var raider: Node = actors.raider
	player.global_position = Vector2(960, 790)
	raider.global_position = Vector2(1035, 790)
	raider.set("windup_duration", 0.04)
	raider.set("attack_phase", "idle")
	raider.set_physics_process(true)
	Input.action_press("block")
	var initial_health := int(player.get("health"))
	var blocked := await _wait_until_health_changes(player, initial_health, 50)
	Input.action_release("block")
	_check(blocked and int(player.get("health")) == initial_health - 1 and float(player.get("hitstun_remaining")) <= 0.13, "가드 시 실제 상대 피격의 피해량·경직 감소 회귀")
	await _dispose_game(actors.game)

func _run_ko_regression() -> void:
	var actors := await _new_game()
	if actors.is_empty(): return
	var player: Node = actors.player
	var raider: Node = actors.raider
	player.set("health", 1)
	player.global_position = Vector2(960, 790)
	raider.global_position = Vector2(1035, 790)
	raider.set("windup_duration", 0.04)
	raider.set("attack_phase", "idle")
	raider.set_physics_process(true)
	var ko := await _wait_player_ko(player, 50)
	_check(ko and bool(player.get("is_ko")) and player.get("skill_phase") == "idle", "실제 상대 공격 KO와 스킬 정리 회귀")
	await _dispose_game(actors.game)

func _run_hit_stop_regression() -> void:
	var actors := await _new_game()
	if actors.is_empty(): return
	var player: Node = actors.player
	var raider: Node = actors.raider
	player.global_position = Vector2(960, 790)
	player.set("facing_direction", Vector2.RIGHT)
	player.get_node("VisualRoot").scale.x = 1.0
	raider.global_position = Vector2(1015, 790)
	Input.action_press("attack")
	var attack_hit := false
	for _i in range(60):
		await physics_frame
		if int(raider.get("health")) < int(raider.get("max_health")):
			attack_hit = true
			break
	Input.action_release("attack")
	var stopped := bool(player.get("_hit_stop_active")) or float(Engine.time_scale) < 1.0
	_check(attack_hit and stopped, "본편 Player 공격 적중이 기존 hit-stop을 발생")
	Engine.time_scale = 1.0
	player.set("_hit_stop_active", false)
	await _dispose_game(actors.game)

func _run_restart_regression() -> void:
	var actors := await _new_game()
	if actors.is_empty(): return
	var game: Node = actors.game
	var player: Node = actors.player
	player.set("_hit_stop_active", true)
	Engine.time_scale = 0.08
	game.call("_restart_session")
	for _i in range(5): await process_frame
	_check(not paused and is_equal_approx(Engine.time_scale, 1.0), "게임 재시작이 pause/hit-stop time scale 정리")
	_check(current_scene != game and current_scene != null, "게임 재시작이 본편 세션을 다시 로드")
	Engine.time_scale = 1.0
	if current_scene != null:
		current_scene.queue_free()
		await process_frame

func _wait_until_health_changes(player: Node, initial: int, max_frames: int) -> bool:
	for _i in range(max_frames):
		await physics_frame
		if int(player.get("health")) != initial: return true
	return false

func _wait_player_ko(player: Node, max_frames: int) -> bool:
	for _i in range(max_frames):
		await physics_frame
		if bool(player.get("is_ko")): return true
	return bool(player.get("is_ko"))

func _frames(count: int) -> void:
	for _i in range(count): await physics_frame

func _dispose_game(game: Node) -> void:
	if is_instance_valid(game): game.queue_free()
	await process_frame

func _save_directional_evidence() -> void:
	var saved: Dictionary = get_meta("directional_images", {})
	if not saved.has(1) or not saved.has(-1):
		_check(false, "우향·좌향 실제 frame_post_draw 증거 수집")
		return
	var right: Image = saved[1]
	var left: Image = saved[-1]
	var evidence := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	evidence.fill(Color(0.025, 0.035, 0.04, 1.0))
	var thumb_right := right.duplicate()
	var thumb_left := left.duplicate()
	thumb_right.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	thumb_left.resize(960, 540, Image.INTERPOLATE_LANCZOS)
	evidence.blit_rect(thumb_right, Rect2i(Vector2i.ZERO, thumb_right.get_size()), Vector2i(0, 0))
	evidence.blit_rect(thumb_left, Rect2i(Vector2i.ZERO, thumb_left.get_size()), Vector2i(960, 0))
	var path := ProjectSettings.globalize_path(EVIDENCE_PATH)
	var err := evidence.save_png(path)
	_check(err == OK, "우향·좌향 실제 Window post-draw 캡처 저장")
	records.append("- evidence_png=%s; left_source=%s; right_source=%s" % [path, left.get_size(), right.get_size()])

func _write_report() -> void:
	var path := ProjectSettings.globalize_path(REPORT_PATH)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("검수 보고서 기록")
		return
	file.store_line("# Player 스킬 피격 중단 검수")
	file.store_line("")
	file.store_line("- 실행 방식: 본편 `scenes/game/main.tscn`의 Player와 ForestRaider를 사용한 실제 Window 통합 검수")
	file.store_line("- 상대 타격: ForestRaider AI의 windup → AttackArea monitoring → Player.receive_hit 경로. `_cancel_skill` 직접 호출 없음. 검수 중 스킬의 공격 대상 등록만 끄기 위해 Raider collision_layer를 0으로 두고 Raider의 공격 Area는 정상 실행했습니다.")
	file.store_line("- 동기화 설정: 실제 입력으로 목표 스킬 단계에 진입한 뒤 frame sync 동안 해당 단계가 유지되도록 남은 phase timer를 최소 0.30초로 맞췄습니다. ForestRaider의 windup_duration은 0초로 설정해 본편 AI의 windup → active 전환을 다음 physics tick에 실행했습니다.")
	file.store_line("- 공간 설정: 다른 Raider는 physics 처리에서 제외하고 arena 가장자리로 옮겨 separation이 피격을 막지 않게 했습니다. 공격하는 ForestRaider는 계속 hit_receivers 그룹과 본편 AttackArea/receive_hit 경로를 사용했습니다.")
	file.store_line("- 방향 캡처: 두 우향/좌향 이미지 모두 실제 `RenderingServer.frame_post_draw` 이후 Window Viewport에서 획득. 원본 프레임을 좌우로 배치했습니다.")
	file.store_line("")
	for record in records: file.store_line(record)
	file.store_line("")
	file.store_line("## 회귀 및 결과")
	file.store_line("- 검수 케이스 12개: Num4/Num5 × startup/active/recovery × 우향/좌향")
	file.store_line("- 피격 콜백은 `player_hit` signal에서 실제 피격 단계, physics frame, monotonic tick을 기록합니다.")
	file.store_line("- 추가 회귀: 가드 피해·경직 감소, 실제 공격 KO, Player 공격 hit-stop, 세션 재시작 time scale 복구")
	file.store_line("- 결과: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	if not failures.is_empty():
		file.store_line("- 실패: " + "; ".join(failures))
	file.close()

func _direction_name(sign_value: int) -> String:
	return "우향" if sign_value > 0 else "좌향"

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _fail(description: String) -> void:
	failures.append(description)
