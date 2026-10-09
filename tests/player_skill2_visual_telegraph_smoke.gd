extends SceneTree
"""Live Window capture and phase/contact lifecycle smoke for Num5 VFX."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CAPTURE_PATH := "res://assets/art/review/player_skill2_visual_telegraph_window.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const SAMPLE_SIZE := Vector2i(960, 540)
const SHEET_SIZE := Vector2i(1920, 3240)
const FLOOR_Y := 820.0
const CAPTURE_CASES := ["startup", "contact", "recovery", "cancelled", "hitstun", "ko"]

var _failures: Array[String] = []
var _frames: Array[Image] = []
var _stage: Node2D
var _overlay: CaptureOverlay
var _player: CharacterBody2D
var _player_scene: PackedScene
var _skill_hit_received := false

class CaptureBackdrop:
	extends Node2D
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1920, 1080)), Color("#172128"))
		draw_rect(Rect2(Vector2(0, 820), Vector2(1920, 4)), Color("#c98264"))
		draw_line(Vector2(0, 817), Vector2(1920, 817), Color("#edb38e", 0.5), 1.0)

class CaptureOverlay:
	extends Node2D
	var title := ""
	var detail := ""
	func _draw() -> void:
		var font := ThemeDB.fallback_font
		draw_rect(Rect2(Vector2(34, 30), Vector2(1060, 94)), Color("#101a20", 0.88))
		draw_string(font, Vector2(58, 72), title, HORIZONTAL_ALIGNMENT_LEFT, 1000, 28, Color("#f3dfaf"))
		draw_string(font, Vector2(58, 105), detail, HORIZONTAL_ALIGNMENT_LEFT, 1000, 17, Color("#b6ced5"))
		draw_line(Vector2(40, 820), Vector2(1880, 820), Color("#fff0d6", 0.62), 1.0)
		draw_string(font, Vector2(1660, 810), "GROUND ANCHOR", HORIZONTAL_ALIGNMENT_LEFT, 200, 16, Color("#fff0d6"))

class SpinReceiver:
	extends StaticBody2D
	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group("hit_receivers")
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 16.0
		collision.shape = shape
		add_child(collision)
	func receive_hit(_hit: Dictionary) -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Window renderer가 필요합니다.")
		return
	root.size = WINDOW_SIZE
	_player_scene = load(PLAYER_SCENE) as PackedScene
	if _player_scene == null:
		_fail("실제 Player 장면을 불러오지 못했습니다.")
		return
	for facing_right in [true, false]:
		for capture_case in CAPTURE_CASES:
			await _capture_case(facing_right, capture_case)
	if _frames.size() != 12:
		_fail("우향·좌향 12개 Window 프레임 중 %d개를 확보했습니다." % _frames.size())
	if _frames.size() == 12 and (not _actor_regions_differ(_frames[1], _frames[3]) or not _actor_regions_differ(_frames[7], _frames[9])):
		_fail("실제 접촉 VFX와 해제된 취소 상태가 충분히 구분되지 않습니다.")
	if _frames.size() == 12:
		var sheet := Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
		for index in range(_frames.size()):
			var sample := _frames[index].duplicate()
			sample.resize(SAMPLE_SIZE.x, SAMPLE_SIZE.y, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(sample, Rect2i(Vector2i.ZERO, SAMPLE_SIZE), Vector2i((index % 2) * SAMPLE_SIZE.x, int(index / 2) * SAMPLE_SIZE.y))
		var save_error := sheet.save_png(ProjectSettings.globalize_path(CAPTURE_PATH))
		if save_error != OK:
			_fail("검토 Window 캡처 저장 실패: error=%d" % save_error)
	var check := Image.new()
	if check.load(ProjectSettings.globalize_path(CAPTURE_PATH)) != OK or check.get_size() != SHEET_SIZE:
		_fail("1920x3240 Num5 검토 Window 시트가 없습니다.")
	if _failures.is_empty():
		print("player_skill2_visual_telegraph_smoke: 우향·좌향 12개 실제 Window phase contact cleanup 확인 완료")
		print("SKILL2_WINDOW_SMOKE_PASS")
		quit(0)
		return
	for message in _failures:
		push_error("player_skill2_visual_telegraph_smoke: " + message)
	quit(1)

func _capture_case(facing_right: bool, capture_case: String) -> void:
	await _cleanup()
	_stage = Node2D.new()
	_stage.name = "Skill2SpinWindowCapture"
	root.add_child(_stage)
	_stage.add_child(CaptureBackdrop.new())
	_overlay = CaptureOverlay.new()
	_stage.add_child(_overlay)
	_player = _player_scene.instantiate() as CharacterBody2D
	_stage.add_child(_player)
	_player.global_position = Vector2(960.0, FLOOR_Y)
	_player.set("facing_direction", Vector2.RIGHT if facing_right else Vector2.LEFT)
	_player.get_node("VisualRoot").scale.x = 1.0 if facing_right else -1.0
	(_player.get_node("Camera2D") as Camera2D).enabled = false
	_skill_hit_received = false
	_player.skill_hit.connect(_on_skill_hit)
	await process_frame
	var spin_visual := _player.get_node_or_null("Skill2SpinVisual") as Node2D
	if spin_visual == null:
		_fail("Player 시각 트리에 Skill2SpinVisual이 생성되지 않았습니다.")
	_player.call("_request_skill", 2)
	match capture_case:
		"startup":
			await _wait_for_phase_progress("startup", 0.48)
		"contact":
			var receiver := SpinReceiver.new()
			receiver.position = Vector2(960.0, FLOOR_Y - 64.0)
			_stage.add_child(receiver)
			await _wait_for_skill_hit()
			if not _skill_hit_received or not bool(_player.get_node("Hitboxes/Skill2Hitbox").monitoring):
				_fail("%s 방향 접촉이 실제 Skill2Hitbox와 skill_hit(2)에서 오지 않았습니다." % _facing_name(facing_right))
		"recovery":
			await _wait_for_phase_progress("recovery", 0.20)
		"cancelled":
			await _wait_for_phase_progress("startup", 0.38)
			_player.call("_cancel_skill")
			await _wait_cleanup_frame()
			if spin_visual != null and spin_visual.visible:
				_fail("취소 후 Num5 VFX가 즉시 숨겨지지 않았습니다.")
		"hitstun":
			await _wait_for_phase_progress("startup", 0.38)
			_player.call("receive_hit", {"damage": 1, "direction": Vector2.LEFT if facing_right else Vector2.RIGHT, "knockback": 80.0, "hit_stun": 0.22, "attack_stage": 1})
			await _wait_cleanup_frame()
			if spin_visual != null and spin_visual.visible:
				_fail("피격 후 Num5 VFX가 즉시 숨겨지지 않았습니다.")
		"ko":
			await _wait_for_phase_progress("startup", 0.38)
			_player.call("_enter_ko")
			await _wait_cleanup_frame()
			if spin_visual != null and spin_visual.visible:
				_fail("KO 후 Num5 VFX가 즉시 숨겨지지 않았습니다.")
	if capture_case == "startup" and str(_player.get("skill_phase")) != "startup":
		_fail("%s startup 캡처 시 실제 phase가 바뀌었습니다." % _facing_name(facing_right))
	if capture_case == "recovery" and str(_player.get("skill_phase")) != "recovery":
		_fail("%s recovery 캡처 시 실제 phase가 바뀌었습니다." % _facing_name(facing_right))
	_overlay.title = "NUM5  ·  %s  ·  %s" % [_facing_name(facing_right).to_upper(), capture_case.to_upper()]
	_overlay.detail = _detail(capture_case)
	_overlay.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.get_size() != WINDOW_SIZE:
		_fail("%s/%s 실제 Window 프레임이 1920x1080이 아닙니다." % [_facing_name(facing_right), capture_case])
	else:
		_frames.append(frame.duplicate())

func _wait_for_phase_progress(phase: String, target: float) -> void:
	for _attempt in range(240):
		await physics_frame
		await process_frame
		if str(_player.get("skill_phase")) == phase and _phase_progress(phase) >= target:
			await RenderingServer.frame_post_draw
			return
	_fail("%s phase %.2f 지점 대기 시간 초과." % [phase, target])

func _wait_for_skill_hit() -> void:
	for _attempt in range(240):
		await physics_frame
		await process_frame
		if _skill_hit_received:
			await RenderingServer.frame_post_draw
			return
	_fail("active 동안 Skill2Hitbox의 실제 접촉 신호 대기 시간 초과.")

func _wait_cleanup_frame() -> void:
	await physics_frame
	await process_frame
	await RenderingServer.frame_post_draw

func _phase_progress(phase: String) -> float:
	var duration := 0.22 if phase == "startup" else (0.18 if phase == "active" else 0.55)
	return clampf((duration - float(_player.get("skill_phase_remaining"))) / duration, 0.0, 1.0)

func _on_skill_hit(skill_id: int) -> void:
	if skill_id == 2:
		_skill_hit_received = true

func _detail(capture_case: String) -> String:
	var phase := str(_player.get("skill_phase"))
	var remaining := float(_player.get("skill_phase_remaining"))
	var hitbox := bool(_player.get_node("Hitboxes/Skill2Hitbox").monitoring)
	return "phase=%s remaining=%.3fs  ·  Skill2Hitbox=%s  ·  event=%s" % [phase, remaining, "ON" if hitbox else "OFF", "skill_hit(2)" if _skill_hit_received else capture_case]

func _facing_name(facing_right: bool) -> String:
	return "right" if facing_right else "left"

func _actor_regions_differ(first: Image, second: Image) -> bool:
	var different_pixels := 0
	for y in range(230, 820, 5):
		for x in range(480, 1450, 5):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			if absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) > 0.34:
				different_pixels += 1
				if different_pixels >= 120:
					return true
	return false

func _cleanup() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.queue_free()
	_stage = null
	_player = null
	await process_frame
	Engine.time_scale = 1.0
	paused = false

func _fail(message: String) -> void:
	_failures.append(message)
	push_error("player_skill2_visual_telegraph_smoke: " + message)
