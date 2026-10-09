extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const MENU_SCENE := "res://scenes/ui/title_menu.tscn"
const OUTPUT_PATH := "res://assets/art/review/m5c_playable_session_window.png"
const SIZE := Vector2i(1920, 1080)
const CELL := Vector2i(480, 270)
const COLS := 4
const MAX_STEPS := 16

var _game: Node2D
var _player: CharacterBody2D
var _raider: CharacterBody2D
var _failures: Array[String] = []
var _trace: Array[String] = []
var _frames: Array[Image] = []
var _captions: Array[String] = []
var _initial_health := 0
var _hit_count := 0
var _hitstop_seen: Dictionary = {1: false, 2: false, 3: false}
var _capture_label: Label

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(DisplayServer.get_name() != "headless", "Window renderer available")
	root.size = SIZE
	var capture_layer := CanvasLayer.new()
	capture_layer.name = "M5CReviewCaptureOverlay"
	root.add_child(capture_layer)
	_capture_label = Label.new()
	_capture_label.position = Vector2(22.0, 1000.0)
	_capture_label.size = Vector2(1860.0, 62.0)
	_capture_label.add_theme_font_size_override("font_size", 38)
	_capture_label.add_theme_color_override("font_color", Color.WHITE)
	_capture_label.add_theme_color_override("font_outline_color", Color(0.015, 0.025, 0.02, 0.98))
	_capture_label.add_theme_constant_override("outline_size", 8)
	capture_layer.add_child(_capture_label)
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "existing main.tscn loads")
	if packed == null:
		_finish()
		return
	_game = packed.instantiate() as Node2D
	root.add_child(_game)
	await process_frame
	_player = _game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	_raider = _game.get_node_or_null("YSortActors/ForestRaider1") as CharacterBody2D
	_check(_player != null and _raider != null, "live Player and ForestRaider instances")
	_check(_game.get_node_or_null("CombatHUD/Overlay/HealthPanel") != null, "Player health HUD exists")
	_check(_game.get_node_or_null("CombatHUD/Overlay/SkillsPanel") != null, "skill HUD exists")
	_check(_game.get_node_or_null("YSortActors/Player/Camera2D") != null, "Player Camera2D exists")
	_check(not _has_review_texture_visible(_game), "no review-directory artwork is visible in main.tscn")
	if _player == null or _raider == null:
		_finish()
		return
	_player.attack_hit.connect(_on_attack_hit)
	_player.skill_hit.connect(_on_skill_hit)
	_initial_health = int(_raider.get("health"))
	# Keep the production receiver/hitboxes active; position one Raider in the lane
	# for deterministic live attacks and move the other two outside the encounter.
	for index in range(1, 4):
		var other := _game.get_node_or_null("YSortActors/ForestRaider%d" % index) as CharacterBody2D
		if other != null:
			other.set("notice_range", 0.0)
			other.set("max_health", 8)
			other.set("health", 8)
			other.global_position = Vector2(1750.0, 100.0 + index * 300.0)
			other.raider_hit.connect(_on_raider_hit)
	_raider.global_position = _player.global_position + Vector2(-130.0, 0.0)
	await _physics(3)
	var overlay := _game.get_node("CombatHUD/Overlay") as Control
	var raider_health_indicators := overlay.find_children("RaiderHealth_*", "Control", true, false)
	var raider_health_bar_visible := false
	for indicator in raider_health_indicators:
		var health_bars := indicator.find_children("*", "ProgressBar", true, false)
		if indicator.is_visible_in_tree() and not health_bars.is_empty():
			raider_health_bar_visible = true
			break
	_check(raider_health_bar_visible, "ForestRaider health bar is visible in the live HUD")
	await _capture("01 MAIN START", "main.tscn · post-draw · initial state")

	var start_x := _player.global_position.x
	await _tap_action(&"move_right", 16)
	var right_ok: bool = _player.global_position.x > start_x + 10.0 and _player.facing_direction.x > 0.8
	_record("move_right", right_ok, "action=move_right x=%.1f to %.1f facing=%s physics=%d" % [start_x, _player.global_position.x, _player.facing_direction, Engine.get_physics_frames()])
	await _capture("02 MOVE RIGHT", "InputMap move_right · post-draw")
	var before_left := _player.global_position.x
	await _tap_action(&"move_left", 12)
	var left_ok: bool = _player.global_position.x < before_left - 10.0 and _player.facing_direction.x < -0.8
	_record("direction reversal", left_ok, "action=move_left x=%.1f to %.1f facing=%s physics=%d" % [before_left, _player.global_position.x, _player.facing_direction, Engine.get_physics_frames()])
	await _capture("03 TURN LEFT", "InputMap move_left · post-draw")

	_press_action(&"jump")
	await _physics(2)
	var jumped := bool(_player.get("is_jumping"))
	_release_action(&"jump")
	await _physics(8)
	_record("jump", jumped, "action=jump is_jumping=%s jump_v=%.1f height=%.1f physics=%d" % [jumped, float(_player.get("jump_vertical_velocity")), float(_player.get("jump_height_offset")), Engine.get_physics_frames()])
	await _capture("04 JUMP", "InputMap jump · state transition · post-draw")
	await _wait_landed(80)
	Input.action_press(&"block")
	await _physics(5)
	var blocked := bool(_player.get("is_blocking"))
	await _capture("05 BLOCK", "InputMap block pressed · post-draw")
	Input.action_release(&"block")
	await _physics(2)
	_record("block", blocked and not bool(_player.get("is_blocking")), "pressed is_blocking=%s; released is_blocking=%s physics=%d" % [blocked, _player.get("is_blocking"), Engine.get_physics_frames()])

	# Exercise the live combo state machine and real hitboxes. Each stage capture
	# is taken after its active phase is observed by physics, before advancing.
	await _physics(3)
	for stage in range(1, 4):
		var target := _game.get_node("YSortActors/ForestRaider%d" % stage) as CharacterBody2D
		for index in range(1, 4):
			var raider := _game.get_node("YSortActors/ForestRaider%d" % index) as CharacterBody2D
			raider.global_position = Vector2(1750.0, 100.0 + index * 300.0)
			raider.set("hitstun_remaining", 0.0)
		target.set("health", 8)
		target.global_position = _player.global_position + Vector2(_player.facing_direction.x * (28.0 if stage == 3 else 52.0), 0.0)
		target.set("velocity", Vector2.ZERO)
		var before_hits := _hit_count
		if stage == 1:
			_press_action(&"attack")
			await _physics(2)
			_release_action(&"attack")
		var active := await _wait_active_with_target(stage, target, 100)
		var box := _player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
		var monitored := box.monitoring if box != null else false
		await _capture("0%d ATTACK %d" % [5 + stage, stage], "synthetic InputMap attack · phase=%s · hitbox=%s · physics=%d" % [_player.get("attack_phase"), monitored, Engine.get_physics_frames()])
		var hit := await _wait_live_hit(stage, target, before_hits, 90)
		var target_health := int(target.get("health"))
		var hitstop := await _observe_hitstop(stage, 10)
		_record("basic attack stage %d" % stage, active and monitored and hit and target_health < 8 and hitstop, "action=attack stage=%d phase=%s hitbox=%s hit_signal=%s target_hp=8 to %d hitstun=%.3f hitstop_seen=%s camera_trauma=%.3f physics=%d" % [stage, _player.get("attack_phase"), monitored, hit, target_health, float(target.get("hitstun_remaining")), hitstop, float(_player.get("camera_trauma")), Engine.get_physics_frames()])
		if stage < 3:
			var recovery_seen := await _wait_phase(stage, "recovery", 100)
			_record("attack %d recovery" % stage, recovery_seen, "phase=%s frame=%d" % [_player.get("attack_phase"), Engine.get_physics_frames()])
			_press_action(&"attack")
			await _physics(2)
			_release_action(&"attack")
			var combo_started := await _wait_phase(stage + 1, "startup", 45)
			_record("combo buffer %d to %d" % [stage, stage + 1], combo_started, "attack_stage=%s phase=%s physics=%d" % [_player.get("attack_stage"), _player.get("attack_phase"), Engine.get_physics_frames()])
	await _physics(3)
	await _capture("09 HIT REACTION", "live hitstun · health bars · camera · post-draw")

	# Num4/Num5 are the configured physical-key bindings for skill_1/skill_2.
	# Send synthetic key events so InputMap resolves the same production actions.
	await _wait_player_idle(240)
	for index in range(2):
		var skill := index + 1
		await _wait_player_idle(240)
		var skill_name := StringName("skill_%d" % skill)
		var keycode := KEY_KP_4 if skill == 1 else KEY_KP_5
		var event := InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = true
		var mapped := InputMap.event_is_action(event, skill_name)
		Input.parse_input_event(event)
		await _physics(2)
		var entered := await _wait_skill_startup(skill, 15)
		var phase := str(_player.get("skill_phase"))
		var cooldown := float(_player.get("skill_cooldowns")[skill - 1])
		var key_name := "Num%d" % (skill + 3)
		_record("%s production skill input" % key_name, mapped and entered and cooldown > 0.0, "synthetic InputEventKey mapped=%s action=%s skill_id=%d phase=%s cooldown=%.3f source=production_input" % [mapped, skill_name, _player.get("skill_id"), phase, cooldown])
		await _capture("%s SKILL %d" % [key_name.to_upper(), skill], "synthetic keypad event · InputMap %s · phase=%s · HUD post-draw" % [skill_name, phase])
		event.pressed = false
		Input.parse_input_event(event)
		await _wait_player_idle(180)
	await _capture("14 COOLDOWN HUD", "production cooldown timers after skill phases return idle")

	# Distinct, explicitly non-input HUD preview: temporarily assign skill state
	# to verify active/cooldown presentation, then restore the game's state.
	var saved_id: Variant = _player.get("skill_id")
	var saved_phase: Variant = _player.get("skill_phase")
	var saved_remaining: Variant = _player.get("skill_phase_remaining")
	_player.set_physics_process(false)
	_player.set("skill_id", 1)
	_player.set("skill_phase", "active")
	_player.set("skill_phase_remaining", 0.09)
	await _physics(1)
	await _capture("13 DIRECT HUD PREVIEW", "harness direct state assignment · NOT live input or skill use")
	_player.set("skill_id", saved_id)
	_player.set("skill_phase", saved_phase)
	_player.set("skill_phase_remaining", saved_remaining)
	_player.set_physics_process(true)
	_trace.append("DIRECT_STATE_PREVIEW: skill_id/phase/remaining assigned by capture harness for HUD rendering only; excluded from live input pass.")

	var raider_hp_changed := false
	for index in range(1, 4):
		var checked_raider := _game.get_node_or_null("YSortActors/ForestRaider%d" % index)
		if checked_raider != null and int(checked_raider.get("health")) < 8:
			raider_hp_changed = true
	_check(raider_hp_changed, "live input path reduced Raider health")
	if not _failures.is_empty():
		await _capture("FAILURE FRAME", "last gameplay state · expected exit code 1 · state=" + _state_summary())

	# Verify the shipped title menu scene and capture its real rendered panel.
	_game.queue_free()
	await process_frame
	var menu_packed := load(MENU_SCENE) as PackedScene
	var menu := menu_packed.instantiate() as Control if menu_packed != null else null
	_check(menu != null, "production title menu scene instance")
	if menu != null:
		root.add_child(menu)
		await process_frame
		var title := menu.get_node_or_null("MenuCenter/MenuContent/GameTitle") as Label
		var start_button := menu.get_node_or_null("MenuCenter/MenuContent/StartButton") as Button
		_check(title != null and title.text == "BELT SCROLL" and start_button != null, "title and start button visible")
		await _capture("14 TITLE MENU", "production title_menu.tscn after gameplay sequence")
		var controls_button := menu.get_node_or_null("MenuCenter/MenuContent/ControlsButton") as Button
		if controls_button != null:
			controls_button.pressed.emit()
			await process_frame
			var controls_visible := bool(menu.get_node("ControlsOverlay").visible)
			_check(controls_visible, "controls menu opens from title scene")
			await _capture("15 MENU CONTROLS", "production controls overlay · menu scene UI transition")
			menu.call("_hide_controls")
			await process_frame
			_check(not bool(menu.get_node("ControlsOverlay").visible), "controls menu returns to title")
			await _capture("16 MENU RETURN", "controls overlay closed · title menu visible")
		menu.queue_free()

	_trace.append("ART_POLICY: main.tscn production textures are used; no assets/art/review texture is attached to gameplay actors.")
	_trace.append("PHYSICAL_KEYBOARD_MOUSE: NOT_TESTED; synthetic InputEventKey resolved through InputMap only.")
	_trace.append("cooldown_observation: cooldown values logged at Num4/Num5 production startup and in post-phase HUD capture.")
	await _write_montage()
	_finish()

func _on_attack_hit(stage: int) -> void:
	_hit_count += 1
	_trace.append("signal attack_hit stage=%d physics=%d hitstop=%.3f" % [stage, Engine.get_physics_frames(), Engine.time_scale])
	call_deferred("_sample_hitstop", stage)

func _sample_hitstop(stage: int) -> void:
	if Engine.time_scale < 0.99:
		_hitstop_seen[stage] = true
		_trace.append("hit-stop observed stage=%d physics=%d scale=%.3f" % [stage, Engine.get_physics_frames(), Engine.time_scale])

func _observe_hitstop(stage: int, frames: int) -> bool:
	for _index in range(frames):
		if bool(_hitstop_seen.get(stage, false)):
			return true
		await process_frame
	return bool(_hitstop_seen.get(stage, false))

func _on_skill_hit(skill: int) -> void:
	_trace.append("signal skill_hit skill=%d physics=%d" % [skill, Engine.get_physics_frames()])

func _tap_action(action: StringName, frames: int) -> void:
	_press_action(action)
	await _physics(frames)
	_release_action(action)
	await _physics(2)

func _press_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = true
	Input.parse_input_event(event)

func _release_action(action: StringName) -> void:
	var event := InputEventAction.new()
	event.action = action
	event.pressed = false
	Input.parse_input_event(event)

func _physics(count: int) -> void:
	for _index in range(count):
		await physics_frame

func _wait_phase(stage: int, phase: String, frames: int) -> bool:
	for _index in range(frames):
		if int(_player.get("attack_stage")) == stage and str(_player.get("attack_phase")) == phase:
			return true
		await physics_frame
	return int(_player.get("attack_stage")) == stage and str(_player.get("attack_phase")) == phase

func _wait_active_with_target(stage: int, target: CharacterBody2D, frames: int) -> bool:
	for _index in range(frames):
		if int(_player.get("attack_stage")) == stage and str(_player.get("attack_phase")) == "active":
			target.global_position = _player.global_position + Vector2(_player.facing_direction.x * 24.0, 0.0)
			target.set("velocity", Vector2.ZERO)
			return true
		target.global_position = _player.global_position + Vector2(_player.facing_direction.x * 24.0, 0.0)
		target.set("velocity", Vector2.ZERO)
		await physics_frame
	return int(_player.get("attack_stage")) == stage and str(_player.get("attack_phase")) == "active"

func _wait_hit_count(before: int, frames: int) -> bool:
	for _index in range(frames):
		if _hit_count > before:
			return true
		await physics_frame
	return _hit_count > before

func _wait_live_hit(stage: int, target: CharacterBody2D, before: int, frames: int) -> bool:
	for _index in range(frames):
		if _hit_count > before:
			return true
		if int(_player.get("attack_stage")) == stage and str(_player.get("attack_phase")) == "active":
			target.global_position = _player.global_position + Vector2(_player.facing_direction.x * 24.0, 0.0)
			target.set("velocity", Vector2.ZERO)
		await physics_frame
	return _hit_count > before

func _wait_player_idle(frames: int) -> void:
	for _index in range(frames):
		if str(_player.get("skill_phase")) == "idle" and str(_player.get("attack_phase")) == "idle":
			return
		await physics_frame

func _wait_skill_startup(skill: int, frames: int) -> bool:
	for _index in range(frames):
		if int(_player.get("skill_id")) == skill and str(_player.get("skill_phase")) == "startup":
			return true
		await physics_frame
	return int(_player.get("skill_id")) == skill and str(_player.get("skill_phase")) == "startup"

func _on_raider_hit(_stage: int) -> void:
	_trace.append("signal raider_hit physics=%d" % Engine.get_physics_frames())

func _wait_landed(frames: int) -> void:
	for _index in range(frames):
		if not bool(_player.get("is_jumping")):
			return
		await physics_frame

func _capture(title: String, subtitle: String) -> void:
	if _frames.size() >= MAX_STEPS:
		return
	if _capture_label != null:
		_capture_label.text = "%02d  %s" % [_frames.size() + 1, title]
	await process_frame
	await RenderingServer.frame_post_draw
	var image := root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != SIZE:
		_record(title, false, "post-draw frame invalid size=%s" % (image.get_size() if image != null else Vector2i.ZERO))
		return
	var thumb := image.duplicate()
	thumb.resize(CELL.x, CELL.y, Image.INTERPOLATE_LANCZOS)
	_frames.append(thumb)
	_captions.append("%02d %s | %s" % [_frames.size(), title, subtitle])
	_trace.append("POST_DRAW frame=%d title=%s physics=%d state=%s" % [_frames.size(), title, Engine.get_physics_frames(), _state_summary()])

func _write_montage() -> void:
	var board := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color("101916"))
	for index in range(_frames.size()):
		var pos := Vector2i((index % COLS) * CELL.x, (index / COLS) * CELL.y)
		board.blit_rect(_frames[index], Rect2i(Vector2i.ZERO, CELL), pos)
	var save_error := board.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	_check(save_error == OK and _frames.size() >= 8, "post-draw Window capture board saved (%d frames, err=%d)" % [_frames.size(), save_error])
	print("CAPTURE_PNG: %s" % ProjectSettings.globalize_path(OUTPUT_PATH))
	print("CAPTURE_COUNT: %d" % _frames.size())

func _has_review_texture_visible(scene: Node) -> bool:
	for child in scene.find_children("*", "Sprite2D", true, false):
		var sprite := child as Sprite2D
		if sprite == null or not sprite.is_visible_in_tree() or sprite.texture == null:
			continue
		var path := sprite.texture.resource_path.to_lower()
		_trace.append("ART_TEXTURE node=%s path=%s visible=true" % [sprite.get_path(), path])
		if path.contains("/art/review/"):
			return true
	return false

func _state_summary() -> String:
	if _player == null or not is_instance_valid(_player):
		return "player=unavailable"
	return "frame=%d pos=%s facing=%s jump=%s block=%s attack=%s/%s skill=%d/%s cooldowns=%s hp=%s raider_hp=%s camera_trauma=%.3f hitstop=%.3f" % [Engine.get_physics_frames(), _player.global_position, _player.get("facing_direction"), _player.get("is_jumping"), _player.get("is_blocking"), _player.get("attack_stage"), _player.get("attack_phase"), _player.get("skill_id"), _player.get("skill_phase"), _player.get("skill_cooldowns"), _player.get("health"), _raider.get("health") if is_instance_valid(_raider) else "gone", float(_player.get("camera_trauma")), Engine.time_scale]

func _record(name: String, passed: bool, detail: String) -> void:
	_trace.append("CHECK %s=%s | %s" % [name, "PASS" if passed else "FAIL", detail])
	_check(passed, name)

func _check(passed: bool, message: String) -> void:
	if passed:
		print("PASS: " + message)
	else:
		_failures.append(message)
		push_error("FAIL: %s | physics=%d | state=%s" % [message, Engine.get_physics_frames(), _state_summary()])

func _finish() -> void:
	for entry in _trace:
		print("TRACE: " + entry)
	if _failures.is_empty():
		print("m5c_playable_session: all checks passed")
		quit(0)
	else:
		print("FAILURE_EXIT_CODE: 1 failures=%d physics=%d state=%s" % [_failures.size(), Engine.get_physics_frames(), _state_summary()])
		quit(1)
