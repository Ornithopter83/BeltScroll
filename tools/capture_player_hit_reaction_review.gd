extends SceneTree
"""Window-isolated live hit review. The safe candidate is swapped for capture only."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const SAFE_CANDIDATE := "res://assets/art/player/elven_fighter_hit_reaction_v1_safe_candidate_1254x1254.png"
const OUTPUT_PATH := "res://assets/art/review/player_hit_reaction_motion_strip.png"
const REPORT_PATH := "res://docs/review/player_hit_reaction_motion_gate.md"
const PLAYER_PATH := "YSortActors/Player"
const CAPTURE_SIZE := Vector2i(1920, 1080)
const CELL_SIZE := Vector2i(600, 700)
const DIRECTIONS := [1, -1]
const COLUMN_LABELS := ["IDLE BEFORE", "SAFE CANDIDATE (ISOLATED)", "LIVE PROCEDURAL HIT", "RECOVERY / IDLE"]

var failures: Array[String] = []
var records: Array[String] = []
var cells: Array[Image] = []
var _label: Label
var _hit_observed := false

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("실제 Window 렌더러가 필요합니다.")
		return
	root.size = CAPTURE_SIZE
	root.mode = Window.MODE_MAXIMIZED
	await create_timer(0.25).timeout
	for facing_sign in DIRECTIONS:
		await _capture_direction(facing_sign)
	if cells.size() == DIRECTIONS.size() * COLUMN_LABELS.size():
		_save_strip()
	_write_report()
	if failures.is_empty():
		print("player_hit_reaction_motion_review: actual Window captures saved; safe candidate remained isolated")
		await create_timer(3.0).timeout
		quit(0)
		return
	for failure in failures:
		push_error("player_hit_reaction_motion_review: " + failure)
	quit(1)

func _capture_direction(facing_sign: int) -> void:
	var actors := await _new_game()
	if actors.is_empty():
		return
	var game: Node = actors.game
	var player: CharacterBody2D = actors.player
	var raider: CharacterBody2D = actors.raider
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var animator: Node = player.get_node("VisualAnimator")
	var original_texture: Texture2D = art.texture
	_hit_observed = false
	player.global_position = Vector2(960.0, 790.0)
	player.velocity = Vector2.ZERO
	player.set("facing_direction", Vector2(float(facing_sign), 0.0))
	player.get_node("VisualRoot").scale.x = float(facing_sign)
	raider.global_position = player.global_position + Vector2(-float(facing_sign) * 86.0, 0.0)
	raider.set("facing_direction", Vector2(float(facing_sign), 0.0))
	raider.get_node("VisualRoot").scale.x = float(facing_sign)
	raider.set("windup_duration", 0.16)
	raider.set("attack_range", 118.0)
	raider.set("active_duration", 0.12)
	raider.set("attack_knockback", 190.0)
	raider.set("attack_hit_stun", 0.36)
	await _frames(3)
	await _capture_cell(player, art, original_texture, "%s · IDLE" % _direction_name(facing_sign), facing_sign)
	var health_before := int(player.get("health"))
	var receive_time := -1
	var receive_hit_stop := false
	var receive_time_scale := 1.0
	player.player_hit.connect(func(_stage):
		_hit_observed = true
		receive_time = Time.get_ticks_msec()
		receive_hit_stop = bool(player.get("_hit_stop_active"))
		receive_time_scale = Engine.time_scale
	)
	raider.attack_windup_started.connect(func(): records.append("- %s ForestRaider windup: physics_frame=%d" % [_direction_name(facing_sign), Engine.get_physics_frames()]))
	# Start the real Raider AI attack state; its active AttackArea remains enabled and
	# calls the Player's actual receive_hit callback through the normal body overlap.
	raider.call("_begin_attack")
	var hit := await _wait_for_player_hit(player, raider, 70)
	_check(hit and _hit_observed and int(player.get("health")) < health_before, "%s ForestRaider AttackArea → Player.receive_hit 실제 적중 (phase=%s, monitoring=%s, overlaps=%d, health=%d)" % [_direction_name(facing_sign), str(raider.get("attack_phase")), str((raider.get_node("AttackArea") as Area2D).monitoring), (raider.get_node("AttackArea") as Area2D).get_overlapping_bodies().size(), int(player.get("health"))])
	if not hit:
		game.queue_free()
		await process_frame
		return
	_check(float(player.get("hitstun_remaining")) > 0.0, "%s hitstun 상태 진입" % _direction_name(facing_sign))
	_check(player.velocity.x * float(facing_sign) > 0.0, "%s 반동 방향 knockback 발생" % _direction_name(facing_sign))
	var candidate := load(SAFE_CANDIDATE) as Texture2D
	_check(candidate != null, "격리 safe 후보 텍스처 로드")
	if candidate != null:
		art.texture = candidate
		await _capture_cell(player, art, candidate, "%s · SAFE 후보 / 피격" % _direction_name(facing_sign), facing_sign)
		art.texture = original_texture
		await _capture_cell(player, art, original_texture, "%s · 현행 절차 피격" % _direction_name(facing_sign), facing_sign)
		var elapsed_ms := Time.get_ticks_msec() - receive_time
		records.append("- %s receive_hit 시점 hit-stop 관찰: active=%s, time_scale=%.2f, 첫 Window 캡처까지=%dms" % [_direction_name(facing_sign), str(receive_hit_stop), receive_time_scale, elapsed_ms])
		_check(not receive_hit_stop and receive_time_scale >= 0.99, "%s ForestRaider 수신 피격 시 Player 공격 hit-stop 비활성 확인 (elapsed=%dms)" % [_direction_name(facing_sign), elapsed_ms])
		_check(absf(float(player.get("hitstun_remaining"))) <= 0.36, "%s hitstun 시간은 본편 상태 타이머에서 진행" % _direction_name(facing_sign))
	var recovered := await _wait_for_recovery(player, 100)
	_check(recovered, "%s knockback/hitstun 회복 후 idle 복귀" % _direction_name(facing_sign))
	if recovered:
		await _capture_cell(player, art, original_texture, "%s · 회복 / IDLE" % _direction_name(facing_sign), facing_sign)
	player.set_physics_process(false)
	animator.set_process(false)
	game.queue_free()
	await process_frame

func _new_game() -> Dictionary:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_fail("본편 게임 장면 로드 실패")
		return {}
	var game := packed.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	var evidence := CanvasLayer.new()
	evidence.name = "HitReactionReviewOverlay"
	evidence.layer = 50
	game.add_child(evidence)
	var panel := PanelContainer.new()
	panel.position = Vector2(500.0, 35.0)
	panel.size = Vector2(540.0, 62.0)
	evidence.add_child(panel)
	_label = Label.new()
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 18)
	_label.add_theme_color_override("font_color", Color("#f3ead4"))
	panel.add_child(_label)
	await process_frame
	var player := game.get_node_or_null(PLAYER_PATH) as CharacterBody2D
	var raiders: Array = game.get_node("YSortActors").get_children().filter(func(child): return child.is_in_group("forest_raiders"))
	if player == null or raiders.is_empty():
		_fail("본편 Player와 ForestRaider가 존재해야 합니다")	
		return {}
	var active_raider: CharacterBody2D = raiders[0]
	for index in raiders.size():
		var raider: CharacterBody2D = raiders[index]
		raider.set_physics_process(false)
		(raider.get_node("AttackArea") as Area2D).monitoring = false
		if index > 0:
			raider.global_position = Vector2(190.0 + index * 40.0, 120.0)
	active_raider.set_physics_process(true)
	return {"game": game, "player": player, "raider": active_raider}

func _capture_cell(player: CharacterBody2D, art: Sprite2D, expected_texture: Texture2D, title: String, facing_sign: int) -> void:
	_label.text = title
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	if frame == null or frame.is_empty() or frame.get_width() < CELL_SIZE.x or frame.get_height() < CELL_SIZE.y:
		_fail("%s 실제 Window frame 캡처 실패 (image=%s, root.size=%s, display=%s)" % [title, str(frame.get_size()) if frame != null else "null", str(root.size), DisplayServer.get_name()])
		return
	var center := player.get_global_transform_with_canvas().origin
	var panel := _label.get_parent() as Control
	panel.position = Vector2(center.x - panel.size.x * 0.5, center.y - 500.0)
	var crop_position := Vector2i(roundi(center.x - CELL_SIZE.x * 0.5), roundi(center.y - CELL_SIZE.y * 0.76))
	var crop_rect := Rect2i(crop_position, CELL_SIZE)
	if crop_rect.position.x < 0 or crop_rect.position.y < 0 or crop_rect.end.x > frame.get_width() or crop_rect.end.y > frame.get_height():
		_fail("%s Window crop 경계 벗어남: %s" % [title, str(crop_rect)])
		return
	var cell := Image.create(CELL_SIZE.x, CELL_SIZE.y, false, Image.FORMAT_RGBA8)
	cell.blit_rect(frame, crop_rect, Vector2i.ZERO)
	cells.append(cell)
	_check(art.texture == expected_texture, "%s 렌더 텍스처 확인" % title)
	var visual_animator: Node = player.get_node("VisualAnimator")
	var base_sign := -1.0 if player.get_node("VisualRoot").scale.x < 0.0 else 1.0
	_check(is_equal_approx(base_sign, float(facing_sign)), "%s 방향 유지" % title)
	records.append("- %s 캡처: Window post-draw, player_center=%s, health=%d, hitstun=%.3f, velocity=%s, animation=%s, texture=%s" % [title, str(center), int(player.get("health")), float(player.get("hitstun_remaining")), str(player.velocity), str(visual_animator.call("get_animation_state")), expected_texture.resource_path])

func _wait_for_player_hit(player: CharacterBody2D, raider: CharacterBody2D, max_frames: int) -> bool:
	for _i in max_frames:
		await physics_frame
		if int(player.get("health")) < int(player.get("max_health")):
			return true
	return false

func _wait_for_recovery(player: CharacterBody2D, max_frames: int) -> bool:
	for _i in max_frames:
		await physics_frame
		if float(player.get("hitstun_remaining")) <= 0.0 and player.velocity.length() < 4.0 and not bool(player.get("is_ko")):
			await _frames(2)
			return true
	return false

func _frames(count: int) -> void:
	for _i in count:
		await physics_frame

func _save_strip() -> void:
	var strip := Image.create(CELL_SIZE.x * COLUMN_LABELS.size(), CELL_SIZE.y * DIRECTIONS.size(), false, Image.FORMAT_RGBA8)
	strip.fill(Color("#171b25"))
	for index in cells.size():
		strip.blit_rect(cells[index], Rect2i(Vector2i.ZERO, CELL_SIZE), Vector2i((index % COLUMN_LABELS.size()) * CELL_SIZE.x, (index / COLUMN_LABELS.size()) * CELL_SIZE.y))
	var path := ProjectSettings.globalize_path(OUTPUT_PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	_check(strip.save_png(path) == OK, "우향/좌향 실제 Window 프레임 스트립 저장")

func _write_report() -> void:
	var path := ProjectSettings.globalize_path(REPORT_PATH)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_fail("검수 게이트 문서 작성 실패")
		return
	file.store_line("# Player 피격 동작 Window 격리 검수")
	file.store_line("")
	file.store_line("## 실행 방식")
	file.store_line("")
	file.store_line("본편 `scenes/game/main.tscn`을 실제 Window로 실행하고, 본편 Player와 ForestRaider를 사용했습니다. ForestRaider의 AI windup → active, 실제 AttackArea overlap → `Player.receive_hit` 경로에서 health 감소와 `player_hit` 신호를 확인했습니다. 방향마다 idle, safe 후보를 임시로 표시한 실제 hit 순간, 원래 텍스처를 복원한 procedural hit, hitstun/knockback 이후 idle 회복을 캡처했습니다. 각 패널은 `RenderingServer.frame_post_draw` 뒤의 Window viewport 이미지입니다.")
	file.store_line("")
	file.store_line("safe 텍스처는 캡처 스크립트의 로컬 Sprite2D에 그 순간만 대입하고 즉시 복원합니다. Player, animation bank, manifest, allowlist에는 등록하지 않았습니다. 이는 safe 원화의 실제 hit 애니메이션 승인 또는 통합을 뜻하지 않습니다.")
	file.store_line("")
	file.store_line("## 캡처 스트립")
	file.store_line("")
	file.store_line("![우향·좌향 본편 Window 피격 비교](../../assets/art/review/player_hit_reaction_motion_strip.png)")
	file.store_line("")
	file.store_line("두 행은 우향과 좌향입니다. 각 행은 idle before → safe candidate / real hit → current procedural / real hit → recovery / idle 순서입니다. 런타임 공격 단계와 경직 시간은 본편 상태 전이를 사용했습니다.")
	file.store_line("")
	file.store_line("## 관찰 항목")
	file.store_line("")
	file.store_line("- safe 게이트의 측정값: 후보 하단 alpha anchor y=1253→1147, 공통 192px 기준 약 −16.23px 이동. 실제 본편 표시에서는 idle 기준과 발 접지 차이를 육안 확인해야 합니다.")
	file.store_line("- 크기 비교 수치: safe alpha 높이 1042/1254px, idle 1074/1254px로 safe가 32 asset px, 약 4.90/192px(2.98%) 짧습니다. 캡처에서는 큰 크기 팝은 없지만 후보가 약간 작고 하단 anchor가 올라가 발이 뜰 위험이 보입니다.")
	file.store_line("- 얼굴·귀·복장 연속성, 두 발 지지와 접지 여부는 캡처에서 사람이 검토합니다. 스크립트는 자동 승인하지 않습니다.")
	file.store_line("- 1차 캡처 육안 관찰: safe 후보의 검정·적색 의상과 idle의 청록·녹색 복장 사이에 큰 차이가 보입니다. 얼굴·귀 세부 연속성은 패널에서 추가 판정이 필요하며, 후보의 연속성은 승인되지 않았습니다.")
	file.store_line("- 크기 팝은 후보/절차 표현과 idle의 실루엣 크기를 비교해 사람이 확인합니다. 절차 표현의 실제 변형은 PlayerVisualAnimator가 계산합니다.")
	file.store_line("- hit-stop 확인: ForestRaider가 Player를 때리는 수신 피격은 Player 공격의 hit-stop 발동 경로를 호출하지 않아야 합니다. 해당 구간의 `_hit_stop_active`/time scale을 기록합니다. 시각적 프레임 정지는 캡처에서 별도로 확인합니다.")
	file.store_line("")
	file.store_line("## 측정 기록")
	file.store_line("")
	file.store_line("- safe 후보 표시 크기/anchor 산정의 기준은 기존 `player_hit_reaction_safe_gate.md`의 1254px asset → 192px game canvas입니다. 후보는 IDLE와 동일한 Sprite2D transform을 사용해 런타임의 위치 변화를 가리지 않습니다.")
	for record in records:
		file.store_line(record)
	file.store_line("")
	file.store_line("## 결과")
	file.store_line("")
	file.store_line("- 자동 통합 게이트: %s" % ("PASS" if failures.is_empty() else "FAIL"))
	file.store_line("- 사람 검토: 얼굴·귀·복장 연속성, 양발 접지, 크기 팝, 반동 판독은 캡처 확인이 필요합니다.")
	file.store_line("- 판정 범위: safe 원화는 검수 후보이며, 승인된 전용 hit 애니메이션이 아닙니다. manifest와 allowlist를 변경하지 않았습니다.")
	if not failures.is_empty():
		file.store_line("- 자동 실패: " + "; ".join(failures))
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
