extends SceneTree
"""Capture the player motion gate from the real gameplay Window Viewport."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/m6k_motion_contact_sheet.png"
const VIEW_SIZE := Vector2i(1280, 720)
const CELL_SIZE := Vector2i(640, 360)
const GRID_SIZE := Vector2i(4, 4)
const PLAYER_PATH := "YSortActors/Player"
const FRAME_WAIT_LIMIT := 240

var _frames: Array[Image] = []
var _labels := PackedStringArray()
var _physics_frames: Array[int] = []
var _failures: Array[String] = []
var _player: CharacterBody2D
var _game: Node2D
var _held_keys: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Window 렌더러가 필요합니다. --headless에서는 캡처할 수 없습니다.")
		return
	root.size = VIEW_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("실제 gameplay 씬을 읽을 수 없습니다: " + MAIN_SCENE)
		return
	_game = packed.instantiate() as Node2D
	root.add_child(_game)
	await process_frame
	_player = _game.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	if _player == null:
		_fail("실제 gameplay 씬에서 Player를 찾지 못했습니다.")
		return
	for path in ["YSortActors/ForestRaider1", "YSortActors/ForestRaider2", "YSortActors/ForestRaider3", "YSortActors/RuinsWardenBoss", "YSortActors/TrainingDummy"]:
		var actor := _game.get_node_or_null(path)
		if actor != null:
			actor.set_physics_process(false)
	_player.global_position = Vector2(960.0, 780.0)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	await _settle(18)
	await _capture("01_idle")

	await _hold_key(KEY_D, true)
	await _settle(30)
	await _capture("02_walk")
	await _hold_key(KEY_D, false)
	await _settle(12)

	for stage in [1, 2, 3]:
		if stage == 1:
			await _tap_key(KEY_J)
		var reached := await _wait_attack_stage_active(stage)
		_check(reached, "기본 공격 %d단계 active 포즈에 도달" % stage)
		if reached:
			await _capture("0%d_attack_%d" % [stage + 2, stage])
		if stage < 3:
			await _tap_key(KEY_J)
	var combo_returned := await _wait_attack_idle()
	_check(combo_returned, "1·2·3타 후 기본 공격 idle로 복귀")
	await _hold_key(KEY_D, true)
	await _settle(24)
	await _hold_key(KEY_D, false)
	await _settle(12)
	await _capture("06_walk_return")

	for skill_id in [1, 2]:
		await _wait_skill_cooldown(skill_id)
		await _tap_key(KEY_KP_4 if skill_id == 1 else KEY_KP_5)
		for phase in ["startup", "active", "recovery"]:
			var reached_phase := await _wait_skill_phase(skill_id, phase)
			_check(reached_phase, "Num%d %s 단계 관찰" % [skill_id + 3, _phase_ko(phase)])
			if reached_phase:
				await _capture("num%d_%s" % [skill_id + 3, phase])
		var returned := await _wait_skill_idle()
		_check(returned, "Num%d 기술 회복 후 idle 복귀" % (skill_id + 3))

	for skill_id in [1, 2]:
		await _wait_skill_cooldown(skill_id)
		await _tap_key(KEY_KP_4 if skill_id == 1 else KEY_KP_5)
		var started := await _wait_skill_phase(skill_id, "startup")
		_check(started, "Num%d 중단 재현 startup 시작" % (skill_id + 3))
		if started:
			await _capture("num%d_interrupt_before" % (skill_id + 3))
			var x_before_cancel := _player.global_position.x
			await _hold_key(KEY_KP_3, true)
			var cancelled := await _wait_skill_idle(12)
			await _hold_key(KEY_KP_3, false)
			_check(cancelled, "Num%d 가드 입력 뒤 기술 즉시 중단" % (skill_id + 3))
			await _hold_key(KEY_D, true)
			await _settle(12)
			await _hold_key(KEY_D, false)
			var moved_after_cancel := _player.global_position.x > x_before_cancel + 8.0
			_check(moved_after_cancel, "Num%d 중단 뒤 이동 입력을 받아 locomotion 복귀" % (skill_id + 3))
			await _capture("num%d_interrupt_return" % (skill_id + 3))

	_check(_frames.size() == 16, "16개 상태를 동일 크기의 Window 프레임으로 캡처")
	if _frames.size() == 16:
		var sheet := Image.create(CELL_SIZE.x * GRID_SIZE.x, CELL_SIZE.y * GRID_SIZE.y, false, Image.FORMAT_RGBA8)
		for index in range(_frames.size()):
			var cell := _frames[index].duplicate()
			cell.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i((index % GRID_SIZE.x) * CELL_SIZE.x, (index / GRID_SIZE.x) * CELL_SIZE.y))
		var save_error := sheet.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		_check(save_error == OK, "비교용 4×4 contact sheet PNG 저장")
		if save_error == OK:
			print("M6K_CAPTURE|size=%dx%d|cells=%d|path=%s" % [sheet.get_width(), sheet.get_height(), _frames.size(), OUTPUT_PATH])
	for index in range(_labels.size()):
		print("M6K_FRAME|%02d|%s|physics_frame=%d|viewport=%dx%d" % [index + 1, _labels[index], _physics_frames[index], VIEW_SIZE.x, VIEW_SIZE.y])
	_finish()

func _capture(label: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != VIEW_SIZE:
		_failures.append("%s: 유효한 %dx%d Window Viewport 프레임이 아닙니다." % [label, VIEW_SIZE.x, VIEW_SIZE.y])
		return
	_frames.append(image.duplicate())
	_labels.append(label)
	_physics_frames.append(Engine.get_physics_frames())

func _tap_key(keycode: Key) -> void:
	await _hold_key(keycode, true)
	await _settle(1)
	await _hold_key(keycode, false)
	await _settle(1)

func _hold_key(keycode: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.device = 16
	event.keycode = keycode
	event.physical_keycode = keycode
	event.pressed = pressed
	Input.parse_input_event(event)
	if pressed:
		_held_keys[keycode] = true
	else:
		_held_keys.erase(keycode)
	await process_frame

func _settle(frame_count: int) -> void:
	for _index in range(frame_count):
		await process_frame
		await RenderingServer.frame_post_draw

func _wait_attack_stage_active(stage: int) -> bool:
	for _index in range(FRAME_WAIT_LIMIT):
		await physics_frame
		if int(_player.get("attack_stage")) == stage and str(_player.get("attack_phase")) == "active":
			await RenderingServer.frame_post_draw
			return true
	return false

func _wait_attack_idle() -> bool:
	for _index in range(FRAME_WAIT_LIMIT):
		await physics_frame
		if str(_player.get("attack_phase")) == "idle":
			return true
	return false

func _wait_skill_phase(skill_id: int, phase: String) -> bool:
	for _index in range(FRAME_WAIT_LIMIT):
		await physics_frame
		if int(_player.get("skill_id")) == skill_id and str(_player.get("skill_phase")) == phase:
			await RenderingServer.frame_post_draw
			return true
	return false

func _wait_skill_idle(max_frames: int = FRAME_WAIT_LIMIT) -> bool:
	for _index in range(max_frames):
		await physics_frame
		if str(_player.get("skill_phase")) == "idle":
			return true
	return false

func _wait_skill_cooldown(skill_id: int) -> void:
	for _index in range(FRAME_WAIT_LIMIT * 4):
		var cooldowns: Array = _player.get("skill_cooldowns")
		if str(_player.get("skill_phase")) == "idle" and float(cooldowns[skill_id - 1]) <= 0.0:
			return
		await physics_frame
	_failures.append("Num%d 쿨다운이 제한 시간 안에 끝나지 않았습니다." % (skill_id + 3))

func _phase_ko(phase: String) -> String:
	return {"startup": "준비", "active": "접촉", "recovery": "회복"}.get(phase, phase)

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

func _fail(message: String) -> void:
	_failures.append(message)
	_finish()

func _finish() -> void:
	for keycode in _held_keys.keys():
		await _hold_key(int(keycode), false)
	if _failures.is_empty():
		print("M6K_SUMMARY|fail=0|frames=%d|visual_signoff=pending" % _frames.size())
		quit(0)
		return
	for failure in _failures:
		push_error("m6k_motion_capture: " + failure)
	print("M6K_SUMMARY|fail=%d|frames=%d|visual_signoff=pending" % [_failures.size(), _frames.size()])
	quit(1)
