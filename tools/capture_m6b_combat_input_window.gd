extends SceneTree
"""Captures live combat states from the gameplay Window into a review contact sheet."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/m6b_combat_input_window.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const CELL_SIZE := Vector2i(640, 360)
const CASES := ["1타", "2타", "3타", "Num4 돌진 주먹", "Num5 회전 백피스트", "피격 경직", "final-down"]
const STAGE_STARTUP := [0.075, 0.085, 0.10]
const SKILL_STARTUP := [0.16, 0.22]
const SKILL_ACTIVE := [0.12, 0.18]
const SKILL_RECOVERY := [0.42, 0.55]

var _player: Node2D
var _game: Node2D
var _animator: Node
var _cells: Array[Image] = []
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("활성 디스플레이 서버가 headless입니다. 실제 Window 캡처가 필요합니다.")
		return
	root.size = WINDOW_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("게임 플레이 장면을 읽을 수 없습니다: " + MAIN_SCENE)
		return
	_game = packed.instantiate() as Node2D
	root.add_child(_game)
	await process_frame
	_player = _game.get_node_or_null("YSortActors/Player") as Node2D
	_animator = _player.get_node_or_null("VisualAnimator") if _player != null else null
	if _player == null or _animator == null:
		_fail("실제 게임 Player 또는 VisualAnimator가 없습니다.")
		return
	_player.global_position = Vector2(960, 780)
	_player.set("facing_direction", Vector2.RIGHT)
	_player.get_node("VisualRoot").scale.x = 1.0
	await _settle(0.12)

	for stage in range(1, 4):
		_player.call("_begin_attack", stage)
		await _capture_case_start("기본 %d타" % stage)
		await _wait_for_value("attack_phase", "active", "%d타 접촉(active) 진입" % stage)
		await _capture_current("기본 %d타" % stage, "접촉")
		await _wait_for_value("attack_phase", "recovery", "%d타 회복(recovery) 진입" % stage)
		await _wait_for_value("attack_phase", "idle", "%d타 종료(idle) 진입" % stage)
		await _capture_current("기본 %d타" % stage, "종료")

	for skill in range(1, 3):
		_player.call("_request_skill", skill)
		await _capture_case_start("Num%d 스킬" % (skill + 3))
		await _wait_for_value("skill_phase", "active", "Num%d 스킬 접촉(active) 진입" % (skill + 3))
		await _capture_current("Num%d 스킬" % (skill + 3), "접촉")
		await _wait_for_value("skill_phase", "recovery", "Num%d 스킬 회복(recovery) 진입" % (skill + 3))
		await _wait_for_value("skill_phase", "idle", "Num%d 스킬 종료(idle) 진입" % (skill + 3))
		await _capture_current("Num%d 스킬" % (skill + 3), "종료")

	_player.call("receive_hit", {"damage": 1, "direction": Vector2.LEFT, "knockback": 90.0, "hit_stun": 0.42, "attack_stage": 1})
	_check(float(_player.get("hitstun_remaining")) > 0.0, "피격 시 경직 타이머 활성")
	await _capture_current("피격 경직", "시작")
	await _settle(0.12)
	await _capture_current("피격 경직", "접촉")
	await _settle(0.36)
	await _capture_current("피격 경직", "종료")
	_check(float(_player.get("hitstun_remaining")) <= 0.0, "피격 경직 종료")

	_player.set("health", 1)
	_player.call("receive_hit", {"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 3})
	_check(_player.get("is_ko") == true, "final-down 진입 및 KO 상태")
	await _capture_current("final-down", "시작")
	await _settle(0.32)
	await _capture_current("final-down", "접촉")
	await _settle(0.90)
	await _capture_current("final-down", "종료")
	_check(bool(_animator.call("is_final_down_settled")), "final-down 안정 상태 도달")
	
	if _cells.size() != CASES.size() * 3:
		_failures.append("캡처 프레임 수가 21장이 아닙니다: %d" % _cells.size())
	else:
		var sheet := Image.create(CELL_SIZE.x * 3, CELL_SIZE.y * CASES.size(), false, Image.FORMAT_RGBA8)
		for index in range(_cells.size()):
			var cell := _cells[index]
			cell.resize(CELL_SIZE.x, CELL_SIZE.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(cell, Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i((index % 3) * CELL_SIZE.x, (index / 3) * CELL_SIZE.y))
		var error := sheet.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
		_check(error == OK, "실제 Window 21프레임 contact sheet 저장")
	if _failures.is_empty():
		print("m6b-window-capture: PASS; 21 real Window frames saved to %s" % OUTPUT_PATH)
		quit(0)
		return
	for failure in _failures:
		push_error("m6b-window-capture: " + failure)
	quit(1)

func _capture_case_start(label: String) -> void:
	await _capture_current(label, "시작")

func _capture_current(label: String, beat: String) -> void:
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.is_empty() or frame.get_size() != WINDOW_SIZE:
		_failures.append("%s %s: 1920x1080 Window 프레임을 얻지 못했습니다." % [label, beat])
		return
	_cells.append(frame)
	_print_measurement(label, beat)

func _print_measurement(label: String, beat: String) -> void:
	var visual_root := _player.get_node("VisualRoot") as Node2D
	var art := _player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var hitbox_path := "Hitboxes/Hitbox%d" % maxi(1, int(_player.get("attack_stage")))
	var hand_proxy := _player.get_node(hitbox_path) as Node2D
	if int(_player.get("skill_id")) == 1:
		hand_proxy = _player.get_node("Hitboxes/Skill1Hitbox")
	elif int(_player.get("skill_id")) == 2:
		hand_proxy = _player.get_node("Hitboxes/Skill2Hitbox")
	var arm_screen := hand_proxy.get_global_transform_with_canvas().origin
	var foot_anchor := art.to_global(Vector2(0, art.texture.get_height() * 0.47)) if art.texture != null else visual_root.global_position
	var phase := str(_player.get("attack_phase")) if int(_player.get("attack_stage")) > 0 else str(_player.get("skill_phase"))
	if float(_player.get("hitstun_remaining")) > 0.0:
		phase = "hitstun"
	if _player.get("is_ko") == true:
		phase = "final-down"
	print("M6B_METRIC|%s|%s|state=%s|hand_proxy_px=(%.1f,%.1f)|upper_rotation_deg=%.2f|silhouette_scale=(%.4f,%.4f)|foot_y=%.1f|vertical_from_floor=%.1f|visual=%s" % [
		_case_id(label), _beat_id(beat), phase, arm_screen.x, arm_screen.y,
		rad_to_deg(art.rotation),
		visual_root.scale.x * art.scale.x, visual_root.scale.y * art.scale.y,
		foot_anchor.y, foot_anchor.y - _player.global_position.y,
		str(_animator.call("get_current_art_status")) if _animator.has_method("get_current_art_status") else "실루엣은 화면 프레임에 포함"
	])

func _case_id(label: String) -> String:
	if label.begins_with("기본 1타"):
		return "attack_1"
	if label.begins_with("기본 2타"):
		return "attack_2"
	if label.begins_with("기본 3타"):
		return "attack_3"
	if label.begins_with("Num4"):
		return "num4_rush"
	if label.begins_with("Num5"):
		return "num5_backfist"
	if label == "피격 경직":
		return "hitstun"
	return "final_down"

func _beat_id(beat: String) -> String:
	match beat:
		"시작": return "start"
		"접촉": return "contact"
		"진행": return "mid"
		"종료": return "end"
		"안정": return "settled"
	return "unknown"

func _settle(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func _wait_for_value(property: String, expected: String, description: String) -> void:
	var waited_frames := 0
	while str(_player.get(property)) != expected and waited_frames < 90:
		await process_frame
		waited_frames += 1
	_check(str(_player.get(property)) == expected, description)

func _check(condition: bool, description: String) -> void:
	if not condition:
		_failures.append(description)

func _fail(message: String) -> void:
	push_error("m6b-window-capture: " + message)
	quit(1)
