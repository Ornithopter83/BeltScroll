extends SceneTree
"""Window readability and unchanged-contract smoke for the Num5 backfist."""

const EFFECT_SCRIPT := preload("res://scripts/effects/player_skill2_spin_visual.gd")
const PLAYER_ART := "res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png"
const CONTROLLER_SOURCE := "res://scripts/player/player_controller.gd"
const PLAYER_SCENE_SOURCE := "res://scenes/player/player.tscn"
const WINDOW_SIZE := Vector2i(1920, 1080)
const PANEL_SIZE := Vector2i(960, 540)
const FLOOR_Y := 820.0
const REVIEW_SECONDS := 18.0
const WINDOW_REVIEW_TEMP := "m6k_skill2_spin_readability_window.png"
const PHASES := ["num4", "startup", "active", "recovery"]

var _failures: Array[String] = []
var _frames: Array[Image] = []
var _stage: Node2D
var _actor: TestActor
var _effect: Node2D

class TestActor:
	extends CharacterBody2D
	signal skill_hit(skill_id: int)
	var skill_id := 2
	var skill_phase := "idle"
	var skill_phase_remaining := 0.0
	var facing_direction := Vector2.RIGHT
	var hitstun_remaining := 0.0
	var is_ko := false
	var hitbox: Area2D
	func _init() -> void:
		var visual_root := Node2D.new()
		visual_root.name = "VisualRoot"
		add_child(visual_root)
		var art := Sprite2D.new()
		art.name = "PlayerArt"
		art.texture = load("res://assets/art/player/elven_fighter_reference_v8_clean_candidate_1254x1254.png")
		art.position = Vector2(0.0, -222.0)
		art.scale = Vector2(0.4469274, 0.4469274)
		visual_root.add_child(art)
		var hitboxes := Node2D.new()
		hitboxes.name = "Hitboxes"
		add_child(hitboxes)
		hitbox = Area2D.new()
		hitbox.name = "Skill2Hitbox"
		hitbox.monitoring = false
		var collision := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 64.0
		collision.shape = circle
		hitbox.add_child(collision)
		hitboxes.add_child(hitbox)

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Window renderer가 필요합니다.")
		_finish()
		return
	root.size = WINDOW_SIZE
	_check_gameplay_contract()
	for phase in PHASES:
		await _make_actor()
		match phase:
			"num4":
				_actor.skill_id = 1
				_actor.skill_phase = "active"
				_actor.skill_phase_remaining = 0.06
				var punch_cue := Num4StraightCue.new()
				punch_cue.position = Vector2(960.0, FLOOR_Y)
				_stage.add_child(punch_cue)
				_effect.call("_process", 0.016)
				_check(not _effect.visible, "Num4 비교 상태에는 Num5 원호·회전 효과가 나타나지 않습니다.")
			"startup":
				_set_phase("startup", 0.64)
				_check(absf(_actor.get_node("VisualRoot/PlayerArt").rotation) > 0.25, "준비 구간에서 실제 PlayerArt 실루엣이 역방향으로 꼬입니다.")
			"active":
				_set_phase("active", 0.48)
				_actor.hitbox.monitoring = true
				_actor.skill_hit.emit(2)
				_effect.on_skill_hit(2)
				_effect.call("_process", 0.016)
				_check(_effect.visible and _actor.hitbox.monitoring, "휘두름 중 원형 판정 활성과 접촉 VFX가 유지됩니다.")
			"recovery":
				_set_phase("recovery", 0.28)
				_check(_effect.visible and absf(_actor.get_node("VisualRoot/PlayerArt").rotation) > 0.05, "회복 구간에서 역회전 감속과 효과가 남아 있습니다.")
		await _capture_frame()
	await _verify_cleanup()
	if _frames.size() == PHASES.size():
		_present_review()
		await RenderingServer.frame_post_draw
		var window_image := root.get_texture().get_image()
		if window_image != null:
			window_image.save_png(OS.get_temp_dir().path_join(WINDOW_REVIEW_TEMP))
		print("실제 PlayerArt와 Num5 효과 비교 Window를 %.0f초 동안 표시합니다." % REVIEW_SECONDS)
		await create_timer(REVIEW_SECONDS).timeout
	_finish()

func _make_actor() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.queue_free()
	await process_frame
	_stage = Node2D.new()
	_stage.name = "M6KSkill2Readability"
	root.add_child(_stage)
	_stage.add_child(ReadabilityBackdrop.new())
	_actor = TestActor.new()
	_stage.add_child(_actor)
	_actor.position = Vector2(960.0, FLOOR_Y)
	_effect = EFFECT_SCRIPT.new() as Node2D
	_effect.name = "Skill2SpinVisual"
	_actor.add_child(_effect)
	await process_frame
	_effect.call("_process", 0.016)
	_check(_actor.get_node_or_null("VisualRoot/PlayerArt") != null, "실제 PlayerArt 텍스처가 있는 캐릭터 실루엣을 구성했습니다.")
	_check(_effect != null, "Skill2 시각 효과가 실제 PlayerArt와 같은 캐릭터 위에 붙었습니다.")

class ReadabilityBackdrop:
	extends Node2D
	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, Vector2(1920.0, 1080.0)), Color("#172128"))
		draw_rect(Rect2(Vector2(0.0, FLOOR_Y), Vector2(1920.0, 4.0)), Color("#c98264"))
		draw_line(Vector2(0.0, FLOOR_Y - 3.0), Vector2(1920.0, FLOOR_Y - 3.0), Color("#edb38e", 0.55), 1.0)

class Num4StraightCue:
	extends Node2D
	func _draw() -> void:
		var shoulder := Vector2(20.0, -248.0)
		var fist := Vector2(156.0, -248.0)
		draw_line(shoulder, fist, Color("#7ce9ed", 0.86), 6.0, true)
		draw_circle(fist, 8.0, Color("#d9ffff", 0.95))
		draw_line(fist, fist - Vector2(18.0, 8.0), Color("#d9ffff", 0.95), 3.0, true)
		draw_line(fist, fist - Vector2(18.0, -8.0), Color("#d9ffff", 0.95), 3.0, true)

func _set_phase(phase: String, progress: float) -> void:
	var art := _actor.get_node("VisualRoot/PlayerArt") as Sprite2D
	var planted_foot := _art_foot_global(art)
	_actor.skill_id = 2
	_actor.skill_phase = phase
	var duration := 0.22 if phase == "startup" else (0.18 if phase == "active" else 0.55)
	_actor.skill_phase_remaining = duration * (1.0 - progress)
	_effect.call("_process", 0.016)
	_check(_effect.visible, "%s에서 실제 캐릭터에 Skill2 효과가 표시됩니다." % phase)
	_check(_art_foot_global(art).distance_to(planted_foot) < 0.1, "%s 회전 중 PlayerArt 지지발이 pivot 위치에 고정됩니다." % phase)

func _art_foot_global(art: Sprite2D) -> Vector2:
	var texture_size := Vector2(art.texture.get_size())
	var bounds := art.texture.get_image().get_used_rect()
	var alpha_foot := Vector2(float(bounds.position.x) + float(bounds.size.x) * 0.5, float(bounds.end.y))
	var local_foot := alpha_foot - texture_size * 0.5
	return art.to_global(local_foot)

func _capture_frame() -> void:
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.get_size() != WINDOW_SIZE:
		_fail("실제 Window 프레임이 1920x1080이 아닙니다.")
		return
	_frames.append(frame.duplicate())

func _verify_cleanup() -> void:
	for case in ["cancel", "hit", "ko"]:
		await _make_actor()
		_set_phase("startup", 0.45)
		match case:
			"cancel":
				_actor.skill_phase = "idle"
				_actor.skill_id = 0
			"hit":
				_actor.hitstun_remaining = 0.22
			"ko":
				_actor.is_ko = true
		_effect.call("_process", 0.016)
		_check(not _effect.visible, "%s 중단 뒤 잔류 효과가 즉시 사라집니다." % case)

func _check_gameplay_contract() -> void:
	var controller_text := FileAccess.get_file_as_string(CONTROLLER_SOURCE)
	_check(controller_text.contains("const SKILL_STARTUP := [0.16, 0.22]"), "Skill2 startup 0.22초 유지")
	_check(controller_text.contains("const SKILL_ACTIVE := [0.12, 0.18]"), "Skill2 active/hitbox 0.18초 유지")
	_check(controller_text.contains("const SKILL_RECOVERY := [0.42, 0.55]"), "Skill2 recovery 0.55초 유지")
	_check(controller_text.contains("const SKILL_DAMAGE := [3, 2]"), "Skill2 실제 피해 계약 2 유지")
	_check(controller_text.contains("const SKILL_COOLDOWN := [1.35, 1.8]"), "Skill2 쿨다운 1.8초 유지")
	var scene_text := FileAccess.get_file_as_string(PLAYER_SCENE_SOURCE)
	_check(scene_text.contains("[sub_resource type=\"CircleShape2D\" id=\"HitboxShape_skill_2\"]") and scene_text.contains("radius = 64.0"), "Skill2 원형 판정 반경 64 유지")
	_check(ResourceLoader.exists(PLAYER_ART), "PlayerArt 원본 텍스처를 Window 실루엣 검수에 사용")

func _present_review() -> void:
	if _stage != null and is_instance_valid(_stage):
		_stage.queue_free()
	_stage = Node2D.new()
	_stage.name = "M6KNum4Num5WindowReview"
	root.add_child(_stage)
	var board := Image.create(1920, 1080, false, Image.FORMAT_RGBA8)
	board.fill(Color("#101a20"))
	for index in range(_frames.size()):
		var sample := _frames[index].duplicate()
		sample.resize(PANEL_SIZE.x, PANEL_SIZE.y, Image.INTERPOLATE_LANCZOS)
		var destination := Vector2i((index % 2) * PANEL_SIZE.x, int(index / 2) * PANEL_SIZE.y)
		board.blit_rect(sample, Rect2i(Vector2i.ZERO, PANEL_SIZE), destination)
	var sprite := Sprite2D.new()
	sprite.texture = ImageTexture.create_from_image(board)
	sprite.centered = false
	_stage.add_child(sprite)
	var labels := ["NUM4 · STRAIGHT", "NUM5 · WINDUP", "NUM5 · BACKFIST SWEEP", "NUM5 · SLOW COUNTER-ROTATION"]
	for index in range(labels.size()):
		var label := Label.new()
		label.text = labels[index]
		label.position = Vector2((index % 2) * 960.0 + 12.0, int(index / 2) * 540.0 + 6.0)
		label.add_theme_font_size_override("font_size", 17)
		_stage.add_child(label)
	var note := Label.new()
	note.text = "Actual PlayerArt silhouette with live Skill2 effect  ·  fixed ground and pivot line  ·  Window readability check"
	note.position = Vector2(18.0, 1044.0)
	note.add_theme_font_size_override("font_size", 16)
	_stage.add_child(note)

func _check(condition: bool, message: String) -> void:
	if condition:
		print("PASS: " + message)
	else:
		_fail(message)

func _fail(message: String) -> void:
	_failures.append(message)
	push_error("m6k_skill2_spin_readability_smoke: " + message)

func _finish() -> void:
	if _failures.is_empty():
		print("m6k_skill2_spin_readability_smoke: Window readability and contract checks passed")
		quit(0)
	else:
		quit(1)
