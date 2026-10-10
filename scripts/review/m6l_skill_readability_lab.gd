extends Node2D
"""F6 side-by-side readability lab using the production Player and hitboxes."""

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const DUMMY_SCENE := preload("res://scenes/combat/training_dummy.tscn")
const ART_CANDIDATES := [
	"res://assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png",
	"res://assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png",
]

const VIEW_SIZE := Vector2(1920.0, 1080.0)
const FLOOR_Y := 824.0
const PLAYER_STARTS := [Vector2(220.0, FLOOR_Y), Vector2(1400.0, FLOOR_Y)]
const DUMMY_STARTS := [Vector2(430.0, FLOOR_Y), Vector2(1470.0, FLOOR_Y)]
const CYAN := Color("#72e8ee")
const PINK := Color("#ff82bf")
const GOLD := Color("#ffd68a")

var _players: Array[CharacterBody2D] = []
var _dummies: Array[CharacterBody2D] = []
var _status_labels: Array[Label] = []
var _result_label: Label
var _review_overlay: SkillLabOverlay
var _last_action := "준비 · Num4와 Num5를 차례로 또는 함께 재생하세요."

func _ready() -> void:
	get_viewport().size = Vector2i(1920, 1080)
	_build_lab()

func _build_lab() -> void:
	for index in range(2):
		var player := PLAYER_SCENE.instantiate() as CharacterBody2D
		player.name = "Num4Player" if index == 0 else "Num5Player"
		player.position = PLAYER_STARTS[index]
		player.set("arena_bounds", Rect2(34.0, 700.0, 1852.0, 220.0))
		add_child(player)
		# The controller's own keyboard polling is paused so each real Player can
		# demonstrate a different skill at the same time. This lab advances its
		# actual skill state machine and movement below.
		player.set_physics_process(false)
		var camera := player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			camera.enabled = false
		player.set("facing_direction", Vector2.RIGHT)
		player.get_node("VisualRoot").scale.x = 1.0
		_players.append(player)

		var dummy := DUMMY_SCENE.instantiate() as CharacterBody2D
		dummy.name = "Num4TrainingTarget" if index == 0 else "Num5TrainingTarget"
		dummy.position = DUMMY_STARTS[index]
		dummy.set("arena_bounds", Rect2(34.0, 700.0, 1852.0, 220.0))
		dummy.set("max_health", 9999.0)
		add_child(dummy)
		dummy.set_physics_process(false)
		_dummies.append(dummy)

	_review_overlay = SkillLabOverlay.new()
	_review_overlay.name = "SilhouetteAxisAndHitboxGuides"
	_review_overlay.lab = self
	_review_overlay.z_index = 20
	add_child(_review_overlay)
	_build_hud()
	queue_redraw()

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 30
	add_child(layer)
	var title := _make_label(layer, Vector2(32.0, 18.0), Vector2(1856.0, 42.0), "M6L · NUM4 돌진 / NUM5 제자리 회전 — 기술 가독성 비교장", 27, Color.WHITE)
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	_make_label(layer, Vector2(34.0, 64.0), Vector2(1848.0, 48.0), "Num4 4 / 키패드4 · Num5 5 / 키패드5 · Space 함께 재생 · R 초기화 · X 취소 · H 피격 중단 · K KO · 각 Player의 실기술 상태와 실제 히트박스를 관찰", 17, Color("#d4e2e8"))
	_make_label(layer, Vector2(38.0, 116.0), Vector2(880.0, 36.0), "NUM4 · 직선 돌진   |   전진 거리 · 주먹 방향 · 직선 Skill1Hitbox", 21, CYAN)
	_make_label(layer, Vector2(998.0, 116.0), Vector2(880.0, 36.0), "NUM5 · 제자리 회전   |   지지축 · 상체 비틀기 · 원형 Skill2Hitbox", 21, PINK)
	_status_labels.append(_make_label(layer, Vector2(40.0, 160.0), Vector2(860.0, 30.0), "Num4 대기", 17, Color.WHITE))
	_status_labels.append(_make_label(layer, Vector2(1000.0, 160.0), Vector2(860.0, 30.0), "Num5 대기", 17, Color.WHITE))
	_result_label = _make_label(layer, Vector2(36.0, 874.0), Vector2(1844.0, 30.0), _last_action, 17, GOLD)
	_make_label(layer, Vector2(32.0, 924.0), Vector2(1848.0, 28.0), "미승인 스킬 원화 참고 패널 — 아래 후보는 비교용이며 게임 플레이어/애니메이션/승인 자산으로 적용하지 않습니다.", 15, Color("#ffc8a2"))
	var candidate_strip := HBoxContainer.new()
	candidate_strip.position = Vector2(34.0, 954.0)
	candidate_strip.size = Vector2(1850.0, 110.0)
	candidate_strip.add_theme_constant_override("separation", 28)
	layer.add_child(candidate_strip)
	for index in range(2):
		var panel := HBoxContainer.new()
		panel.custom_minimum_size = Vector2(900.0, 104.0)
		panel.add_theme_constant_override("separation", 12)
		candidate_strip.add_child(panel)
		var texture_rect := TextureRect.new()
		texture_rect.custom_minimum_size = Vector2(100.0, 100.0)
		texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		texture_rect.texture = load(ART_CANDIDATES[index]) as Texture2D
		panel.add_child(texture_rect)
		var caption := Label.new()
		caption.custom_minimum_size = Vector2(760.0, 96.0)
		caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		caption.add_theme_font_size_override("font_size", 14)
		caption.add_theme_color_override("font_color", Color("#ffd8c4"))
		var candidate_name := "Num4 돌진 접촉 후보" if index == 0 else "Num5 회전 백핸드 후보"
		caption.text = "참고 · %s\n%s" % [candidate_name, ART_CANDIDATES[index].get_file()]
		panel.add_child(caption)

func _make_label(parent: Node, at: Vector2, size: Vector2, value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.position = at
	label.size = size
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _unhandled_key_input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	var code: int = event.keycode
	if code == KEY_4 or code == KEY_KP_4:
		_play_skill(0, 1)
	elif code == KEY_5 or code == KEY_KP_5:
		_play_skill(1, 2)
	elif code == KEY_SPACE:
		_play_skill(0, 1)
		_play_skill(1, 2)
	elif code == KEY_R:
		_reset_lab()
	elif code == KEY_X:
		_cancel_skills()
	elif code == KEY_H:
		_interrupt_players(false)
	elif code == KEY_K:
		_interrupt_players(true)
	get_viewport().set_input_as_handled()

func _play_skill(index: int, skill_id: int) -> void:
	var player := _players[index]
	if bool(player.get("is_ko")) or float(player.get("hitstun_remaining")) > 0.0:
		_last_action = "중단 상태 · R로 초기화한 뒤 다시 재생하세요."
		_refresh_readout()
		return
	var cooldowns: Array = player.get("skill_cooldowns")
	cooldowns[skill_id - 1] = 0.0
	player.set("skill_cooldowns", cooldowns)
	player.set("facing_direction", Vector2.RIGHT)
	player.call("_request_skill", skill_id)
	_last_action = "Num%d 실기술 재생 · 준비 → 활성(실제 히트박스) → 회복" % (skill_id + 3)
	_refresh_readout()

func _physics_process(delta: float) -> void:
	for player in _players:
		var cooldowns: Array = player.get("skill_cooldowns")
		for index in range(cooldowns.size()):
			cooldowns[index] = maxf(0.0, float(cooldowns[index]) - delta)
		player.set("skill_cooldowns", cooldowns)
		if str(player.get("skill_phase")) != "idle" and not bool(player.get("is_ko")):
			player.call("_apply_skill_motion")
			player.move_and_slide()
		else:
			player.velocity = Vector2.ZERO
		player.call("_update_skill", delta)
		player.call("_update_hit_flash", delta)
		player.call("_update_camera_trauma", delta)
	_refresh_readout()
	_review_overlay.queue_redraw()

func _cancel_skills() -> void:
	for player in _players:
		player.call("_cancel_skill")
	_last_action = "검증 · 취소 직후 양쪽 스킬 효과와 판정 잔류 여부를 확인하세요."
	_refresh_readout()

func _interrupt_players(force_ko: bool) -> void:
	for player in _players:
		if force_ko:
			var remaining_health := maxi(1, int(player.get("health")))
			player.call("receive_hit", {"damage": remaining_health, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.25, "attack_stage": 3})
		else:
			player.call("receive_hit", {"damage": 1, "direction": Vector2.LEFT, "knockback": 100.0, "hit_stun": 0.25, "attack_stage": 2})
	_last_action = "검증 · KO 후 잔류 효과 소거 확인하세요." if force_ko else "검증 · 피격 취소 후 잔류 효과 소거 확인하세요."
	_refresh_readout()

func _reset_lab() -> void:
	for index in range(_players.size()):
		var player := _players[index]
		player.call("_cancel_skill")
		player.set("is_ko", false)
		player.set("health", int(player.get("max_health")))
		player.set("hitstun_remaining", 0.0)
		player.set("hit_flash_remaining", 0.0)
		player.get_node("VisualRoot/PlayerArt").modulate = Color.WHITE
		player.global_position = PLAYER_STARTS[index]
		player.velocity = Vector2.ZERO
		player.set("facing_direction", Vector2.RIGHT)
		player.set("skill_cooldowns", [0.0, 0.0])
		player.call("_set_skill_hitboxes", false)
		var dummy := _dummies[index]
		dummy.global_position = DUMMY_STARTS[index]
		dummy.set("health", 9999.0)
	_last_action = "초기화 완료 · 실제 Player와 실제 판정 대기 중"
	_refresh_readout()

func _refresh_readout() -> void:
	if _status_labels.size() != 2:
		return
	for index in range(2):
		var player := _players[index]
		var skill_id := int(player.get("skill_id"))
		var phase := str(player.get("skill_phase"))
		var remain := float(player.get("skill_phase_remaining"))
		var active_hitbox := player.get_node("Hitboxes/Skill%dHitbox" % skill_id) as Area2D if skill_id > 0 else null
		var state := "대기" if phase == "idle" else "%s · %.2f초" % [_phase_label(phase), remain]
		var hitbox_text := "판정 OFF" if active_hitbox == null or not active_hitbox.monitoring else "실제 판정 ON"
		var distance := player.global_position.distance_to(_dummies[index].global_position)
		_status_labels[index].text = "실제 Player · %s · %s · 대상까지 %.0fpx · 실루엣 회전 %.2f rad" % [state, hitbox_text, distance, (player.get_node("VisualRoot/PlayerArt") as Sprite2D).rotation]
	if _result_label != null:
		_result_label.text = _last_action

func _phase_label(phase: String) -> String:
	match phase:
		"startup": return "준비"
		"active": return "활성 / 히트박스"
		"recovery": return "회복"
		_: return phase

func get_review_players() -> Array[CharacterBody2D]:
	return _players

func get_review_dummies() -> Array[CharacterBody2D]:
	return _dummies

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, VIEW_SIZE), Color("#111b22"))
	draw_rect(Rect2(Vector2(0.0, 104.0), Vector2(960.0, 805.0)), Color("#17262e"))
	draw_rect(Rect2(Vector2(960.0, 104.0), Vector2(960.0, 805.0)), Color("#211d2a"))
	draw_line(Vector2(960.0, 106.0), Vector2(960.0, 910.0), Color("#60717a"), 2.0, true)
	draw_rect(Rect2(Vector2(0.0, FLOOR_Y), Vector2(1920.0, 4.0)), Color("#bd967b"))
	draw_line(Vector2(0.0, FLOOR_Y + 6.0), Vector2(1920.0, FLOOR_Y + 6.0), Color("#eed0a2", 0.32), 1.0)
	draw_rect(Rect2(Vector2(18.0, 914.0), Vector2(1884.0, 158.0)), Color("#281f20"))
	draw_rect(Rect2(Vector2(18.0, 914.0), Vector2(1884.0, 2.0)), Color("#8f6958"))

class SkillLabOverlay:
	extends Node2D
	var lab: Node2D
	var _alpha_foot_y: Array[float] = []
	func _ready() -> void:
		var players: Array = lab.call("get_review_players")
		for player: CharacterBody2D in players:
			var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
			var bounds := art.texture.get_image().get_used_rect()
			_alpha_foot_y.append(float(bounds.end.y) - float(art.texture.get_height()) * 0.5)

	func _draw() -> void:
		if lab == null:
			return
		var players: Array = lab.call("get_review_players")
		for index in range(players.size()):
			var player: CharacterBody2D = players[index]
			var facing: Vector2 = player.get("facing_direction")
			var color: Color = Color("#72e8ee") if index == 0 else Color("#ff82bf")
			var anchor := player.global_position
			var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
			var foot := art.to_global(Vector2(0.0, _alpha_foot_y[index]))
			var shoulder := art.to_global(Vector2(0.0, -55.0))
			draw_line(to_local(anchor + Vector2(0.0, -208.0)), to_local(anchor), Color("#ffd68a", 0.52), 1.4, true)
			draw_line(to_local(anchor + Vector2(-40.0, 0.0)), to_local(anchor + Vector2(40.0, 0.0)), Color("#ffd68a", 0.9), 2.0, true)
			draw_line(to_local(anchor + Vector2(0.0, -16.0)), to_local(anchor + Vector2(0.0, 18.0)), Color("#ffd68a", 0.9), 2.0, true)
			draw_circle(to_local(anchor), 5.0, Color("#ffd68a"))
			draw_circle(to_local(foot), 6.0, Color.WHITE)
			draw_line(to_local(anchor + facing * 24.0 + Vector2(0.0, -208.0)), to_local(anchor + facing * 132.0 + Vector2(0.0, -208.0)), Color(color, 0.58), 2.0, true)
			draw_circle(to_local(shoulder), 5.0, Color("#ffd68a", 0.95))
			var skill_id := index + 1
			var hitbox := player.get_node("Hitboxes/Skill%dHitbox" % skill_id) as Area2D
			_draw_hitbox(hitbox, color, hitbox.monitoring)
			if index == 0:
				var fist_from := anchor + Vector2(34.0, -218.0)
				var fist_to := anchor + Vector2(176.0, -218.0)
				draw_line(to_local(fist_from), to_local(fist_to), Color("#72e8ee", 0.9), 4.0, true)
				draw_circle(to_local(fist_to), 8.0, Color.WHITE)
			else:
				draw_circle(to_local(anchor + Vector2(0.0, -8.0)), 8.0, Color("#ff82bf", 0.95))
				draw_line(to_local(anchor + Vector2(-35.0, -8.0)), to_local(anchor + Vector2(35.0, -8.0)), Color("#ffd68a", 0.8), 2.0, true)

	func _draw_hitbox(area: Area2D, color: Color, active: bool) -> void:
		var collision := area.get_node_or_null("CollisionShape2D") as CollisionShape2D
		if collision == null or collision.shape == null:
			return
		var points := PackedVector2Array()
		if collision.shape is RectangleShape2D:
			var rect := collision.shape as RectangleShape2D
			var half := rect.size * 0.5
			for point in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
				points.append(to_local(collision.to_global(point)))
			points.append(points[0])
			draw_polyline(points, Color(color, 1.0 if active else 0.45), 3.0 if active else 1.6, true)
		elif collision.shape is CircleShape2D:
			var circle := collision.shape as CircleShape2D
			var center := to_local(collision.global_position)
			draw_arc(center, circle.radius, 0.0, TAU, 48, Color(color, 1.0 if active else 0.45), 3.0 if active else 1.6, true)
