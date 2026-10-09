extends SceneTree
"""Window capture gate for temporary, live Num4 dash telegraph rendering."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CAPTURE_PATH := "res://assets/art/review/player_skill1_visual_telegraph_window.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const SHEET_SIZE := Vector2i(1920, 3240)
const FLOOR_Y := 820.0
const SAMPLE_SIZE := Vector2i(960, 540)
const FACING_CASES := [true, false]
const CAPTURE_CASES := ["startup", "contact", "recovery", "interrupted", "ko", "num5_reference"]

var _failures: Array[String] = []
var _frames: Array[Image] = []
var _labels: Array[String] = []
var _stage: Node2D
var _overlay: CaptureOverlay
var _player: CharacterBody2D
var _player_scene: PackedScene
var _hit_received := false

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
		draw_rect(Rect2(Vector2(34, 30), Vector2(900, 94)), Color("#101a20", 0.86))
		draw_string(font, Vector2(58, 72), title, HORIZONTAL_ALIGNMENT_LEFT, 850, 28, Color("#f3dfaf"))
		draw_string(font, Vector2(58, 105), detail, HORIZONTAL_ALIGNMENT_LEFT, 850, 17, Color("#b6ced5"))
		draw_line(Vector2(40, 820), Vector2(1880, 820), Color("#fff0d6", 0.62), 1.0)
		draw_string(font, Vector2(1660, 810), "GROUND ANCHOR", HORIZONTAL_ALIGNMENT_LEFT, 200, 16, Color("#fff0d6"))

class HitReceiver:
	extends StaticBody2D
	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group("hit_receivers")
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 18.0
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
		_fail("Player 장면을 불러오지 못했습니다.")
		return
	for facing_right in FACING_CASES:
		for capture_case in CAPTURE_CASES:
			await _capture_case(facing_right, capture_case)
	if _frames.size() != 12:
		_fail("우향/좌향 12개 Window 프레임 중 %d개만 확보했습니다." % _frames.size())
	if _frames.size() == 12:
		if not _actor_regions_differ(_frames[1], _frames[5]) or not _actor_regions_differ(_frames[7], _frames[11]):
			_fail("Num4 접촉과 Num5 회전 참조의 실제 렌더링이 충분히 구별되지 않습니다.")
	if _frames.size() == 12:
		var sheet := Image.create(SHEET_SIZE.x, SHEET_SIZE.y, false, Image.FORMAT_RGBA8)
		for index in range(_frames.size()):
			var sample := _frames[index].duplicate()
			sample.resize(SAMPLE_SIZE.x, SAMPLE_SIZE.y, Image.INTERPOLATE_LANCZOS)
			var x := (index % 2) * SAMPLE_SIZE.x
			var y := int(index / 2) * SAMPLE_SIZE.y
			sheet.blit_rect(sample, Rect2i(Vector2i.ZERO, SAMPLE_SIZE), Vector2i(x, y))
		var save_error := sheet.save_png(ProjectSettings.globalize_path(CAPTURE_PATH))
		if save_error != OK:
			_fail("검토 Window 이미지를 저장하지 못했습니다. error=%d" % save_error)
	var check_image := Image.new()
	if check_image.load(ProjectSettings.globalize_path(CAPTURE_PATH)) != OK or check_image.get_size() != SHEET_SIZE:
		_fail("최종 1920x3240 Window 검토 이미지가 없거나 크기가 다릅니다.")
	if _failures.is_empty():
		print("player_skill1_visual_telegraph_smoke: 우향·좌향 12개 Window phase 프레임 확인 완료")
		print("SKILL1_WINDOW_SMOKE_PASS")
		quit(0)
		return
	for message in _failures:
		push_error("player_skill1_visual_telegraph_smoke: " + message)
	quit(1)

func _capture_case(facing_right: bool, capture_case: String) -> void:
	await _cleanup()
	_stage = Node2D.new()
	_stage.name = "Skill1TelegraphWindowCapture"
	root.add_child(_stage)
	_stage.add_child(CaptureBackdrop.new())
	_overlay = CaptureOverlay.new()
	_stage.add_child(_overlay)
	_player = _player_scene.instantiate() as CharacterBody2D
	_player.name = "Num4Right" if facing_right else "Num4Left"
	_stage.add_child(_player)
	_player.global_position = Vector2(960.0, FLOOR_Y)
	_player.set("facing_direction", Vector2.RIGHT if facing_right else Vector2.LEFT)
	_player.get_node("VisualRoot").scale.x = 1.0 if facing_right else -1.0
	(_player.get_node("Camera2D") as Camera2D).enabled = false
	_hit_received = false
	_player.skill_hit.connect(_on_skill_hit)
	await process_frame
	if _player.get_node_or_null("Skill1DashVisual") == null:
		_fail("Player 시각 트리에 Skill1DashVisual 노드가 연결되지 않았습니다.")
	var start_x := _player.global_position.x
	match capture_case:
		"startup":
			_player.call("_request_skill", 1)
			await _wait_for_phase_progress("startup", 0.48)
		"contact":
			var receiver := HitReceiver.new()
			receiver.position = Vector2(start_x + (198.0 if facing_right else -198.0), FLOOR_Y)
			_stage.add_child(receiver)
			_player.call("_request_skill", 1)
			await _wait_for_hit()
			if not _hit_received:
				_fail("%s 방향 Num4가 실제 Skill1Hitbox 접촉/skill_hit 신호에 도달하지 못했습니다." % _facing_name(facing_right))
		"recovery":
			_player.call("_request_skill", 1)
			await _wait_for_phase_progress("recovery", 0.20)
		"interrupted":
			_player.call("_request_skill", 1)
			await _wait_for_phase_progress("startup", 0.42)
			_player.call("_cancel_skill")
		"ko":
			_player.call("_request_skill", 1)
			await _wait_for_phase_progress("startup", 0.40)
			_player.set("is_ko", true)
		"num5_reference":
			_player.call("_request_skill", 2)
			await _wait_for_phase_progress("active", 0.48)
	if capture_case == "startup" and str(_player.get("skill_phase")) != "startup":
		_fail("%s 방향 startup 캡처 시 phase가 벗어났습니다." % _facing_name(facing_right))
	if capture_case == "recovery" and str(_player.get("skill_phase")) != "recovery":
		_fail("%s 방향 recovery 캡처 시 phase가 벗어났습니다." % _facing_name(facing_right))
	if capture_case == "interrupted" and str(_player.get("skill_phase")) != "idle":
		_fail("취소 후 Num4 phase가 종료되지 않았습니다.")
	_overlay.title = "%s  ·  %s" % [_facing_name(facing_right).to_upper(), capture_case.to_upper()]
	_overlay.detail = _detail(capture_case)
	_overlay.queue_redraw()
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.get_size() != WINDOW_SIZE:
		_fail("%s/%s post-draw Window frame 크기가 1920x1080이 아닙니다." % [_facing_name(facing_right), capture_case])
	else:
		_frames.append(frame.duplicate())
		_labels.append("%s/%s" % [_facing_name(facing_right), capture_case])

func _wait_for_phase_progress(phase: String, target: float) -> void:
	for _attempt in range(240):
		await physics_frame
		await process_frame
		if str(_player.get("skill_phase")) == phase and _phase_progress(phase) >= target:
			await RenderingServer.frame_post_draw
			return
	_fail("%s phase %.2f 시각 지점 대기 시간 초과." % [phase, target])

func _wait_for_hit() -> void:
	for _attempt in range(240):
		await physics_frame
		await process_frame
		if _hit_received:
			await RenderingServer.frame_post_draw
			return

func _phase_progress(phase: String) -> float:
	var duration := 0.16 if phase == "startup" else (0.12 if phase == "active" else (0.42 if phase == "recovery" else 0.22))
	return clampf((duration - float(_player.get("skill_phase_remaining"))) / duration, 0.0, 1.0)

func _on_skill_hit(skill_id: int) -> void:
	if skill_id == 1:
		_hit_received = true

func _detail(capture_case: String) -> String:
	var phase := str(_player.get("skill_phase"))
	var clock := float(_player.get("skill_phase_remaining"))
	var active_box := bool(_player.get_node("Hitboxes/Skill1Hitbox").monitoring)
	return "phase=%s remaining=%.3fs  ·  Skill1Hitbox=%s  ·  foot y=%.1f" % [phase, clock, "ON" if active_box else "OFF", _player.global_position.y]

func _facing_name(facing_right: bool) -> String:
	return "right" if facing_right else "left"

func _actor_regions_differ(first: Image, second: Image) -> bool:
	var different_pixels := 0
	# Compare the actor/effect viewport while excluding the changing caption and floor guide.
	for y in range(230, 820, 5):
		for x in range(480, 1450, 5):
			var a := first.get_pixel(x, y)
			var b := second.get_pixel(x, y)
			var delta := absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b)
			if delta > 0.34:
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
	push_error("player_skill1_visual_telegraph_smoke: " + message)
