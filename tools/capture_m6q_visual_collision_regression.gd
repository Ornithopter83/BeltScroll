extends RefCounted
class_name M6QVisualCollisionCapture
"""Actual Window capture for the M6Q visual/collision regression sequence."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const VIDEO_PATH := "res://temp/ProjectHub/attachments/30319a1f00274afb8876fbb88d14dd9ahq/BeltScroll (DEBUG) 2026-10-10 16-01-49.mp4"
const EXPECTED_VIDEO_SHA256 := "391F5EA5CFB20245D90C44BDB3B8D565E708254A20EBEF2C828324F7411577D1"
const REPORT_PATH := "res://docs/review/m6q_user_video_regression_gate.md"
const SHEET_PATH := "res://assets/art/review/m6q_visual_collision_regression_sheet.png"
const SAMPLE_WIDTH := 640
const SAMPLE_HEIGHT := 360
const CAPTURE_LABELS := [
	"walk_before",
	"attack1_startup",
	"attack1_active_f10_on",
	"combo_hold",
	"attack2_active",
	"attack3_active",
	"walk_f10_off",
]

static func capture(tree: SceneTree) -> Dictionary:
	var result := {"ok": false, "error": "", "rows": 0, "video_sha256": ""}
	if DisplayServer.get_name() == "headless" or tree.root.size.x <= 0 or tree.root.size.y <= 0:
		result.error = "A real Godot Window renderer is required."
		return result
	var video_abs := ProjectSettings.globalize_path(VIDEO_PATH)
	if FileAccess.file_exists(VIDEO_PATH):
		result.video_sha256 = FileAccess.get_sha256(VIDEO_PATH).to_upper()
	else:
		result.video_sha256 = "MISSING"
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		result.error = "Could not load the live main scene."
		return result
	var game := packed.instantiate() as Node2D
	tree.root.add_child(game)
	tree.current_scene = game
	await tree.process_frame
	var player := game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	var raider := game.get_node_or_null("YSortActors/ForestRaider1") as CharacterBody2D
	var overlay := tree.root.get_node_or_null("CombatCollisionOverlay")
	if player == null or raider == null or overlay == null:
		result.error = "Live Player, Raider, or collision overlay is missing."
		game.queue_free()
		return result
	var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
	var walk_motion := player.get_node("WalkMotion")
	var walk_sprite := walk_motion.call("get_candidate_sprite") as Sprite2D
	var pose0 := player.get_node("VisualRoot/PoseBlender/PoseSprite0") as Sprite2D
	var pose1 := player.get_node("VisualRoot/PoseBlender/PoseSprite1") as Sprite2D
	var camera := player.get_node("Camera2D") as Camera2D
	if camera != null:
		camera.position_smoothing_enabled = false
		camera.make_current()
	# Keep the production actor/camera/render tree. Move the opponent safely beyond all hit shapes.
	raider.global_position = player.global_position + Vector2(640.0, 0.0)
	var frame_rows := PackedStringArray([_csv_header()])
	var samples: Array[Image] = []
	var sample_names := PackedStringArray()
	var sequence_clock := 0.0
	var sample_request := ""
	var f10_on_seen := false
	var f10_off_seen := false
	var frame_index := 0
	var max_frames := 900
	# Scripted input follows the live input actions; it is not a physical keyboard recording.
	Input.action_press("move_right")
	await _capture_for(tree, 0.55, "walk_before", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, sample_request, frame_index)
	Input.action_release("move_right")
	Input.action_press("attack")
	await _capture_for(tree, 0.035, "attack1_startup", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, sample_request, frame_index)
	Input.action_release("attack")
	await _until_phase(tree, "active", 1, "attack1_active_f10_on", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, frame_index, max_frames)
	_set_f10(overlay, true)
	f10_on_seen = bool(overlay.get("enabled"))
	await _capture_for(tree, 0.055, "attack1_active_f10_on", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, sample_request, frame_index)
	_set_f10(overlay, false)
	await _until_phase(tree, "combo_hold", 1, "combo_hold", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, frame_index, max_frames)
	Input.action_press("attack")
	await _capture_for(tree, 0.035, "attack2_startup", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, sample_request, frame_index)
	Input.action_release("attack")
	await _until_phase(tree, "active", 2, "attack2_active", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, frame_index, max_frames)
	await _until_phase(tree, "combo_hold", 2, "combo_hold_2", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, frame_index, max_frames)
	Input.action_press("attack")
	await _capture_for(tree, 0.035, "attack3_startup", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, sample_request, frame_index)
	Input.action_release("attack")
	await _until_phase(tree, "active", 3, "attack3_active", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, frame_index, max_frames)
	await _until_phase(tree, "idle", 0, "walk_f10_off", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, frame_index, max_frames)
	_set_f10(overlay, true)
	f10_on_seen = f10_on_seen or bool(overlay.get("enabled"))
	await _capture_for(tree, 0.12, "walk_f10_on", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, sample_request, frame_index)
	_set_f10(overlay, false)
	f10_off_seen = not bool(overlay.get("enabled"))
	Input.action_press("move_right")
	await _capture_for(tree, 0.30, "walk_f10_off", sample_names, samples, frame_rows, player, raider, art, walk_sprite, pose0, pose1, overlay, sequence_clock, sample_request, frame_index)
	Input.action_release("move_right")
	await RenderingServer.frame_post_draw
	var sheet_ok := _write_sheet(samples)
	var hash_ok := str(result.video_sha256) == EXPECTED_VIDEO_SHA256
	var body_sources_exclusive := _all_body_source_rows_exclusive(frame_rows)
	var report_ok := _write_report(frame_rows, sample_names, result.video_sha256, hash_ok, f10_on_seen, f10_off_seen, sheet_ok, body_sources_exclusive, tree)
	result.rows = frame_rows.size() - 1
	result.body_sources_exclusive = body_sources_exclusive
	result.ok = sheet_ok and report_ok and result.rows > 0 and body_sources_exclusive
	if not result.ok:
		result.error = "Capture outputs were incomplete or a frame did not have exactly one full-body source; see the report and console."
	game.queue_free()
	return result

static func _capture_for(tree: SceneTree, seconds: float, label: String, sample_names: PackedStringArray, samples: Array[Image], rows: PackedStringArray, player: CharacterBody2D, raider: CharacterBody2D, art: Sprite2D, walk: Sprite2D, pose0: Sprite2D, pose1: Sprite2D, overlay: Node, clock: float, sample_request: String, frame_index: int) -> void:
	var elapsed := 0.0
	var sampled := false
	while elapsed < seconds:
		await tree.process_frame
		var delta := maxf(tree.root.get_process_delta_time(), 1.0 / 240.0)
		elapsed += delta
		clock += delta
		frame_index += 1
		rows.append(_frame_row(rows.size(), float(Time.get_ticks_msec()) / 1000.0, label, player, raider, art, walk, pose0, pose1, overlay))
		if not sampled and (sample_request.is_empty() or sample_request == label):
			await RenderingServer.frame_post_draw
			samples.append(tree.root.get_texture().get_image())
			sample_names.append(label)
			sampled = true

static func _until_phase(tree: SceneTree, phase: String, stage: int, label: String, sample_names: PackedStringArray, samples: Array[Image], rows: PackedStringArray, player: CharacterBody2D, raider: CharacterBody2D, art: Sprite2D, walk: Sprite2D, pose0: Sprite2D, pose1: Sprite2D, overlay: Node, clock: float, frame_index: int, frame_limit: int) -> void:
	var count := 0
	var sampled := false
	while count < frame_limit:
		await tree.process_frame
		var delta := maxf(tree.root.get_process_delta_time(), 1.0 / 240.0)
		clock += delta
		count += 1
		frame_index += 1
		rows.append(_frame_row(rows.size(), float(Time.get_ticks_msec()) / 1000.0, label, player, raider, art, walk, pose0, pose1, overlay))
		if not sampled and str(player.get("attack_phase")) == phase and int(player.get("attack_stage")) == stage:
			await RenderingServer.frame_post_draw
			samples.append(tree.root.get_texture().get_image())
			sample_names.append(label)
			sampled = true
		if str(player.get("attack_phase")) == phase and int(player.get("attack_stage")) == stage:
			return
	push_warning("M6Q sequence did not reach %s/stage %d within %d frames." % [phase, stage, frame_limit])

static func _set_f10(overlay: Node, enabled: bool) -> void:
	if bool(overlay.get("enabled")) == enabled:
		return
	var event := InputEventKey.new()
	event.keycode = KEY_F10
	event.physical_keycode = KEY_F10
	event.pressed = true
	# Directly invoke the real overlay's F10 input handler; this is a rendered ON/OFF
	# check, not proof that a physical key press reached the application.
	overlay.call("_input", event)

static func _frame_row(index: int, seconds: float, label: String, player: CharacterBody2D, raider: CharacterBody2D, art: Sprite2D, walk: Sprite2D, pose0: Sprite2D, pose1: Sprite2D, overlay: Node) -> String:
	var fist := player.get_node("VisualRoot/AttackFlash") as Polygon2D
	var fist_world := fist.global_position
	var shapes := PackedStringArray()
	for stage in range(1, 4):
		var area := player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
		var collision := area.get_node("CollisionShape2D") as CollisionShape2D
		shapes.append("H%d[c=%s;s=%s;mon=%s]" % [stage, _vec(collision.global_position), _shape_size(collision.shape), str(area.monitoring)])
	return "%d,%.6f,%s,%s,%d,%.4f,%s,%.4f,%s,%.4f,%s,%.4f,%s,%s,%s,%s,%s,%.2f,%.2f,%s,%s,%s,%s,%d" % [
		index, seconds, label, str(player.get("attack_phase")), int(player.get("attack_stage")), float(player.get("attack_phase_remaining")),
		str(art.visible), _effective_alpha(art), str(walk.visible), _effective_alpha(walk), str(pose0.visible), _effective_alpha(pose0), str(pose1.visible), _effective_alpha(pose1),
		str(overlay.get("enabled")), _vec(fist_world), _vec(fist.position), fist_world.x, fist_world.y, _vec(player.global_position),
		";".join(shapes), str(raider.get("health")), str(player.get("health")), _full_body_source_count(art, walk, pose0, pose1)
	]

static func _csv_header() -> String:
	return "frame,monotonic_time_s,segment,attack_phase,attack_stage,phase_remaining_s,PlayerArt.visible,PlayerArt.effective_alpha,WalkMotionCandidate.visible,WalkMotionCandidate.effective_alpha,PoseSprite0.visible,PoseSprite0.effective_alpha,PoseSprite1.visible,PoseSprite1.effective_alpha,F10_overlay_enabled,fist_world_x_y,fist_local_x_y,fist_x,fist_y,player_world_center_x_y,Hitbox1_2_3_center_size_monitoring,raider_hp,player_hp,full_body_source_count"

static func _full_body_source_count(art: Sprite2D, walk: Sprite2D, pose0: Sprite2D, pose1: Sprite2D) -> int:
	var count := 0
	for sprite in [art, walk, pose0, pose1]:
		if sprite != null and sprite.texture != null and _effective_alpha(sprite) > 0.001:
			count += 1
	return count

static func _all_body_source_rows_exclusive(rows: PackedStringArray) -> bool:
	if rows.size() <= 1:
		return false
	var valid := true
	for index in range(1, rows.size()):
		var columns := rows[index].split(",")
		var count := int(columns[columns.size() - 1]) if not columns.is_empty() else 0
		if count != 1:
			valid = false
			push_warning("Full-body source exclusivity failed on captured frame %d: %d sources." % [index, count])
	return valid

static func _effective_alpha(node: CanvasItem) -> float:
	var alpha := 1.0
	var cursor: Node = node
	while cursor is CanvasItem:
		var item := cursor as CanvasItem
		if not item.visible:
			return 0.0
		alpha *= item.modulate.a * item.self_modulate.a
		cursor = cursor.get_parent()
	return clampf(alpha, 0.0, 1.0)

static func _shape_size(shape: Shape2D) -> String:
	if shape is RectangleShape2D:
		return _vec((shape as RectangleShape2D).size)
	if shape is CircleShape2D:
		var radius := (shape as CircleShape2D).radius
		return _vec(Vector2(radius * 2.0, radius * 2.0))
	if shape is CapsuleShape2D:
		var capsule := shape as CapsuleShape2D
		return _vec(Vector2(capsule.radius * 2.0, capsule.height))
	return "unknown"

static func _vec(value: Vector2) -> String:
	return "%.2f:%.2f" % [value.x, value.y]

static func _write_sheet(images: Array[Image]) -> bool:
	if images.is_empty():
		return false
	var columns := 3
	var rows := ceili(float(images.size()) / float(columns))
	var sheet := Image.create(SAMPLE_WIDTH * columns, SAMPLE_HEIGHT * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.035, 0.045, 0.065, 1.0))
	for index in range(images.size()):
		var frame := images[index].duplicate()
		frame.resize(SAMPLE_WIDTH, SAMPLE_HEIGHT, Image.INTERPOLATE_LANCZOS)
		sheet.blit_rect(frame, Rect2i(Vector2i.ZERO, frame.get_size()), Vector2i((index % columns) * SAMPLE_WIDTH, floori(float(index) / columns) * SAMPLE_HEIGHT))
	var error := sheet.save_png(ProjectSettings.globalize_path(SHEET_PATH))
	return error == OK

static func _write_report(rows: PackedStringArray, names: PackedStringArray, observed_hash: String, hash_ok: bool, f10_on: bool, f10_off: bool, sheet_ok: bool, body_sources_exclusive: bool, tree: SceneTree) -> bool:
	var lines := PackedStringArray([
		"# M6Q 사용자 영상 시각·충돌 회귀 게이트", "",
		"## 기준 영상", "",
		"- 파일: `%s`" % VIDEO_PATH.get_file(),
		"- 기대 SHA256: `%s`" % EXPECTED_VIDEO_SHA256,
		"- 관측 SHA256: `%s` (%s)" % [observed_hash, "MATCH" if hash_ok else "MISMATCH"],
		"- 비교 판정: **UNVERIFIED** — 이 실행 환경에서 ffprobe/ffmpeg를 찾지 못해 원본 MP4 프레임의 정확한 타임스탬프를 추출하지 못했다. 자동 캡처의 구간 시간으로 원본 프레임 타임스탬프를 추정하지 않는다.", "",
		"## 기준 영상에서 분리해 기록한 결함", "",
		"1. **걷기 캐릭터 중복**: `PlayerArt`와 `WalkMotion` 렌더 소유권이 겹쳐 두 실루엣이 보이는 결함.",
		"2. **1타 다중 실루엣**: 1타 전환/교차 페이드 중 `PlayerArt`, `WalkMotion`, `PoseSprite0/1` 가운데 복수 레이어가 유효 알파로 동시에 그려지는 결함.",
		"3. **지면의 공격 판정**: 공격 Shape2D가 실제 주먹 위치와 맞지 않고 지면 쪽에 놓이는 판정 결함.",
		"위 항목은 기준 영상에 대해 사용자 제보 결함으로 각각 등록했다. 아래 자동 계측은 재현 데이터이며 육안 승인이나 세 결함의 원본 타임스탬프 정합을 대신하지 않는다.", "",
		"## 현재 실제 Player Window 연속 캡처", "",
		"- 렌더러: `%s`; Window `%s`; viewport `%s`." % [DisplayServer.get_name(), DisplayServer.window_get_size(), tree.root.size],
		"- 순서: walk → J 1타 startup/active → combo_hold → J 2타 → combo_hold → J 3타 → walk. 실제 gameplay Player, 카메라, 게임 씬의 렌더 체인을 사용했다.",
		"- 입력은 캡처기가 `Input.action_press/release`로 발행했다. F10 ON/OFF 상태는 실제 overlay `_input` handler 직접 호출로 토글하고 Window 렌더를 캡처했다. 물리 키보드 조작/입력 라우팅 자체는 검증하지 않았다.",
		"- 매 렌더 프레임 기록: PlayerArt, WalkMotion이 소유한 실제 후보 Sprite2D, PoseSprite0/1 각각의 visible·실효 alpha 및 전신 소스 수, attack phase/stage/남은 시간, 1·2·3타의 실제 CollisionShape2D 전역 중심·기하 크기·Area2D.monitoring, AttackFlash 주먹 표시 전역/로컬 위치, Raider/Player HP, F10 상태.",
		"- 캡처한 모든 프레임 전신 소스 수 검사: `%s` (프레임당 정확히 1개여야 PASS)." % ("PASS" if body_sources_exclusive else "FAIL"),
		"- 자동 캡처 결과: %d 프레임; F10 ON 관측 `%s`; F10 OFF 관측 `%s`; 시트 `%s`. 자동 결과는 검토를 보조하며 사람의 육안 승인은 **PENDING**." % [rows.size() - 1, str(f10_on), str(f10_off), "생성" if sheet_ok else "실패"],
		"- PNG 시트 타일 순서: %s." % ", ".join(names),
		"", "## 매 프레임 원자료", "",
		"아래 CSV 행은 자동 계측값이다. `monotonic_time_s`는 Godot monotonic clock 초, `Hitbox1_2_3_center_size_monitoring`은 `Hn[global_center;size;monitoring]` 3개 항목이다. `effective_alpha`는 자기 자신과 모든 CanvasItem 조상 modulate/self_modulate alpha의 곱이며 숨겨진 노드는 0이다. `full_body_source_count`는 이 실효 alpha가 0.001보다 큰 전신 Sprite2D 수다.", "",
		"```csv"
	])
	lines.append_array(rows)
	lines.append_array(["```", "", "## 사람의 육안 승인", "", "- 상태: **PENDING**", "- 승인자: 미기록", "- 확인 항목: 걷기 캐릭터 중복, 1타 다중 실루엣, 공격 Shape2D와 주먹 표시점/지면의 정렬, F10 ON/OFF 화면 표시, 2·3타 전환.", "- 기준 영상과 비교한 최종 시각 판정은 정확한 원본 시각/프레임을 추출할 수 있을 때만 별도 갱신한다.", ""])
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string("\n".join(lines))
	file.close()
	return true
