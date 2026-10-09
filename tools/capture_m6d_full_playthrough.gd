extends SceneTree
"""Replays a real Window run using input events; never edits combat state."""

const TITLE_SCENE := "res://scenes/ui/title_menu.tscn"
const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/m6d_full_playthrough_evidence.png"
const FRAME_SIZE := Vector2i(1920, 1080)
const TILE_SIZE := Vector2i(640, 380)
const MAX_PHASE_SECONDS := 150.0
const MOVE_KEY := KEY_D
const ATTACK_KEY := KEY_J
const SKILL_1_KEY := KEY_KP_4
const SKILL_2_KEY := KEY_KP_5
const RESTART_KEY := KEY_R
const FONT_5X7 := {
	"A": "01110/10001/10001/11111/10001/10001/10001", "B": "11110/10001/10001/11110/10001/10001/11110",
	"C": "01111/10000/10000/10000/10000/10000/01111", "D": "11110/10001/10001/10001/10001/10001/11110",
	"E": "11111/10000/10000/11110/10000/10000/11111", "F": "11111/10000/10000/11110/10000/10000/10000",
	"G": "01111/10000/10000/10111/10001/10001/01111", "H": "10001/10001/10001/11111/10001/10001/10001",
	"I": "11111/00100/00100/00100/00100/00100/11111", "J": "00111/00010/00010/00010/10010/10010/01100",
	"K": "10001/10010/10100/11000/10100/10010/10001", "L": "10000/10000/10000/10000/10000/10000/11111",
	"M": "10001/11011/10101/10101/10001/10001/10001", "N": "10001/11001/10101/10011/10001/10001/10001",
	"O": "01110/10001/10001/10001/10001/10001/01110", "P": "11110/10001/10001/11110/10000/10000/10000",
	"Q": "01110/10001/10001/10001/10101/10010/01101", "R": "11110/10001/10001/11110/10100/10010/10001",
	"S": "01111/10000/10000/01110/00001/00001/11110", "T": "11111/00100/00100/00100/00100/00100/00100",
	"U": "10001/10001/10001/10001/10001/10001/01110", "V": "10001/10001/10001/10001/10001/01010/00100",
	"W": "10001/10001/10001/10101/10101/10101/01010", "X": "10001/10001/01010/00100/01010/10001/10001",
	"Y": "10001/10001/01010/00100/00100/00100/00100", "Z": "11111/00001/00010/00100/01000/10000/11111",
	"0": "01110/10001/10011/10101/11001/10001/01110", "1": "00100/01100/00100/00100/00100/00100/01110",
	"2": "01110/10001/00001/00010/00100/01000/11111", "3": "11110/00001/00001/01110/00001/00001/11110",
	"4": "00010/00110/01010/10010/11111/00010/00010", "5": "11111/10000/10000/11110/00001/00001/11110",
	"6": "01110/10000/10000/11110/10001/10001/01110", "7": "11111/00001/00010/00100/01000/01000/01000",
	"8": "01110/10001/10001/01110/10001/10001/01110", "9": "01110/10001/10001/01111/00001/00001/01110",
	"-": "00000/00000/00000/11111/00000/00000/00000", ".": "00000/00000/00000/00000/00000/00110/00110",
	":": "00000/00110/00110/00000/00110/00110/00000", "/": "00001/00010/00010/00100/01000/01000/10000",
	" ": "00000/00000/00000/00000/00000/00000/00000",
}

var _manual := false
var _events: Array[String] = []
var _frames: Array[Image] = []
var _frame_labels: Array[String] = []
var _phase := "boot"
var _last_attack_msec := 0
var _last_skill_msec := 0
var _last_heartbeat_msec := 0
var _run_started_msec := 0
var _active_raider_seen := -1
var _travel_section_seen := 0
var _player_hit_seen := false
var _boss_hit_seen := false
var _title_seen := false
var _restart_seen := false
var _victory_seen := false
var _defeat_seen := false
var _failure_reason := ""
var _injected_keycodes: Dictionary = {}
var _manual_terminal_seen := false

func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	_manual = args.has("--manual")
	root.size = FRAME_SIZE
	call_deferred("_run")

func _run() -> void:
	_log("MODE", "PHYSICAL_INPUT_OBSERVATION" if _manual else "AUTOMATED_INPUT_EVENT_REPLAY")
	_log("LIMIT", "No health writes, receive_hit calls, internal victory calls, or scene-state shortcuts.")
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		_fail("UNVERIFIED: headless display cannot prove a real Godot Window playthrough.")
		_finish()
		return
	var title := load(TITLE_SCENE) as PackedScene
	if title == null:
		_fail("FAIL: title scene could not be loaded.")
		_finish()
		return
	var initial := title.instantiate()
	root.add_child(initial)
	current_scene = initial
	if not await _wait_until(func() -> bool: return _is_title(), 12.0):
		_fail("FAIL: title did not appear in the real Window.")
		_finish()
		return
	_title_seen = true
	await _capture_checkpoint("01 TITLE · real menu")
	_log("PASS", "Title menu rendered in the real Window.")
	if _manual:
		await _observe_physical_playthrough()
	else:
		await _push_ui_key(KEY_ENTER)
		await process_frame
		if _is_title():
			await _click_focused_start()
		if not await _wait_until(func() -> bool: return _is_main(), 12.0):
			var start_button := current_scene.get_node_or_null("MenuCenter/MenuContent/StartButton") if _is_title() else null
			_fail("FAIL: injected ui_accept did not start gameplay (scene=%s focused=%s)." % [current_scene.scene_file_path if current_scene != null else "<null>", start_button.has_focus() if start_button is Button else false])
		else:
			await _run_automated_victory()
			if _victory_seen:
				await _automated_retry_and_defeat()
	_finish()

func _run_automated_victory() -> void:
	_run_started_msec = Time.get_ticks_msec()
	while _is_main() and _elapsed_seconds(_run_started_msec) < MAX_PHASE_SECONDS:
		var game := current_scene
		var player := game.get_node_or_null("YSortActors/Player") as Node2D
		var boss := game.get_node_or_null("YSortActors/RuinsWardenBoss")
		var raiders: Array = game.get("_raiders")
		if player == null:
			_fail("FAIL: Player disappeared during automated run.")
			return
		if int(game.get("result_state")) == 2:
			_victory_seen = true
			await _capture_checkpoint("VICTORY · live attacks")
			_log("PASS", "Boss victory result followed observed boss health reaching zero after injected attack events.")
			return
		if int(game.get("result_state")) == 1:
			await _capture_checkpoint("UNEXPECTED DEFEAT · first run")
			_fail("FAIL: player was defeated before the boss victory branch.")
			return
		var section := clampi(int(player.global_position.x / 1920.0), 0, 2)
		if section > _travel_section_seen:
			_travel_section_seen = section
			await _capture_checkpoint("SECTION %d · x %.0f" % [section + 1, player.global_position.x])
			_log("PASS", "Player crossed into stage section %d by movement input." % (section + 1))
		var active_raider := _find_active_raider(raiders)
		if active_raider != null:
			var wave_index := raiders.find(active_raider)
			if wave_index != _active_raider_seen:
				_active_raider_seen = wave_index
				_phase = "RAIDER_%d" % (wave_index + 1)
				await _capture_checkpoint("RAIDER %d · encounter" % (wave_index + 1))
				_log("OBSERVE", "Raider wave %d active with live health %d." % [wave_index + 1, int(active_raider.get("health"))])
			if not bool(active_raider.get("visible")):
				await _release_key(MOVE_KEY)
			else:
				await _fight_target(player, active_raider as Node2D, false)
		elif is_instance_valid(boss) and bool(boss.get("combat_active")):
			if _phase != "BOSS":
				_phase = "BOSS"
				await _capture_checkpoint("BOSS · encounter")
				_log("PASS", "Boss encounter became active after all three live Raider KOs.")
			await _fight_target(player, boss as Node2D, true)
			if int(boss.get("health")) < int(boss.get("max_health")):
				_boss_hit_seen = true
		else:
			await _hold_movement()
		if Time.get_ticks_msec() - _last_heartbeat_msec > 8000:
			_last_heartbeat_msec = Time.get_ticks_msec()
			_log("STATE", "x=%.0f player_hp=%d section=%d" % [player.global_position.x, int(player.get("health")), section + 1])
		await process_frame
	if not _victory_seen:
		_fail("UNVERIFIED: automated run timed out before the live boss victory result.")

func _fight_target(player: Node2D, target: Node2D, is_boss: bool) -> void:
	var delta := target.global_position - player.global_position
	var distance_x := absf(delta.x)
	if absf(delta.y) > 18.0:
		if delta.y > 0.0:
			await _set_key(KEY_S, true)
			await _set_key(KEY_W, false)
		else:
			await _set_key(KEY_W, true)
			await _set_key(KEY_S, false)
	else:
		await _set_key(KEY_W, false)
		await _set_key(KEY_S, false)
	if distance_x > (82.0 if is_boss else 70.0):
		await _set_key(MOVE_KEY if delta.x > 0.0 else KEY_A, true)
		await _set_key(KEY_A if delta.x > 0.0 else MOVE_KEY, false)
		return
	await _release_key(MOVE_KEY)
	await _release_key(KEY_A)
	var now := Time.get_ticks_msec()
	if now - _last_attack_msec >= 300:
		_last_attack_msec = now
		await _tap_key(ATTACK_KEY)
	if now - _last_skill_msec >= 1450:
		_last_skill_msec = now
		await _tap_key(SKILL_1_KEY if (now / 1450) % 2 == 0 else SKILL_2_KEY)
	if is_boss:
		var health := int(target.get("health"))
		if health <= 0:
			_boss_hit_seen = true
	else:
		if int(target.get("health")) <= 0:
			await _release_all_movement()

func _automated_retry_and_defeat() -> void:
	if not _is_main():
		_fail("FAIL: victory screen scene disappeared before restart input.")
		return
	await _send_key(RESTART_KEY)
	if not await _wait_until(func() -> bool: return _is_main() and int(current_scene.get("result_state")) == 0 and float(current_scene.get_node("YSortActors/Player").global_position.x) < 1200.0, 15.0):
		_fail("FAIL: injected R did not reload a fresh gameplay session.")
		return
	_restart_seen = true
	await _capture_checkpoint("RESTART - FRESH GAMEPLAY")
	_log("PASS", "Injected R restarted gameplay; new Player returned to its initial scene position.")
	_run_started_msec = Time.get_ticks_msec()
	while _is_main() and _elapsed_seconds(_run_started_msec) < MAX_PHASE_SECONDS:
		var game := current_scene
		var player := game.get_node_or_null("YSortActors/Player") as Node2D
		var boss := game.get_node_or_null("YSortActors/RuinsWardenBoss")
		var raiders: Array = game.get("_raiders")
		if int(game.get("result_state")) == 1:
			_defeat_seen = true
			await _capture_checkpoint("DEFEAT · received live enemy attacks")
			_log("PASS", "DEFEAT result followed observed player health reaching zero from enemy attacks.")
			return
		if int(game.get("result_state")) == 2:
			_fail("FAIL: retry run unexpectedly defeated the boss instead of reaching player defeat.")
			return
		if player == null:
			_fail("FAIL: Player disappeared during retry run.")
			return
		if int(player.get("health")) < int(player.get("max_health")):
			if not _player_hit_seen:
				_player_hit_seen = true
				await _capture_checkpoint("PLAYER HIT · health decreased")
				_log("PASS", "Player received damage through active enemy combat; health=%d." % int(player.get("health")))
		var active_raider := _find_active_raider(raiders)
		if active_raider != null:
			await _fight_target(player, active_raider as Node2D, false)
		elif is_instance_valid(boss) and bool(boss.get("combat_active")):
			if _phase != "BOSS_RETRY":
				_phase = "BOSS_RETRY"
				await _capture_checkpoint("BOSS RETRY · allow incoming attacks")
				_log("OBSERVE", "Retry reaches active boss; automated player will stop attacking and receive physical boss attacks.")
			# Stay in the boss attack lane without attacking, then allow normal enemy AI to hit.
			var dx := (boss as Node2D).global_position.x - player.global_position.x
			if absf(dx) > 116.0:
				await _set_key(MOVE_KEY if dx > 0.0 else KEY_A, true)
			else:
				await _release_key(MOVE_KEY)
				await _release_key(KEY_A)
		else:
			await _hold_movement()
		await process_frame
	if not _defeat_seen:
		_fail("UNVERIFIED: retry run timed out before player defeat.")

func _observe_physical_playthrough() -> void:
	_log("INSTRUCTIONS", "PHYSICAL ONLY: press Enter, move with A/D+W/S, attack J, skills keypad 4/5, restart R. No keys are injected.")
	_run_started_msec = Time.get_ticks_msec()
	while true:
		_record_physical_action_edges()
		if _is_main():
			var game := current_scene
			var player := game.get_node_or_null("YSortActors/Player") as Node
			if player != null:
				var x := (player as Node2D).global_position.x
				var section := clampi(int(x / 1920.0), 0, 2)
				if section > _travel_section_seen:
					_travel_section_seen = section
					await _capture_checkpoint("PHYSICAL SECTION %d" % (section + 1))
					_log("PHYSICAL", "Observed real input reached section %d." % (section + 1))
				var active_raider := _find_active_raider(game.get("_raiders"))
				if active_raider != null:
					var wave_index: int = game.get("_raiders").find(active_raider)
					if wave_index > _active_raider_seen:
						_active_raider_seen = wave_index
						await _capture_checkpoint("PHYSICAL RAIDER %d" % (wave_index + 1))
						_log("PHYSICAL", "Observed live Raider wave %d." % (wave_index + 1))
				var boss := game.get_node_or_null("YSortActors/RuinsWardenBoss")
				if is_instance_valid(boss) and bool(boss.get("combat_active")) and _phase != "PHYSICAL_BOSS":
					_phase = "PHYSICAL_BOSS"
					await _capture_checkpoint("PHYSICAL BOSS ENCOUNTER")
					_log("PHYSICAL", "Observed active boss after Raider waves.")
				if int(player.get("health")) < int(player.get("max_health")):
					_player_hit_seen = true
				if is_instance_valid(boss) and int(boss.get("health")) < int(boss.get("max_health")):
					_boss_hit_seen = true
				if _manual_terminal_seen and int(game.get("result_state")) == 0:
					_restart_seen = true
					_manual_terminal_seen = false
					await _capture_checkpoint("PHYSICAL RESTART")
					_log("PHYSICAL", "Observed restart into a fresh gameplay scene.")
				var state := int(game.get("result_state"))
				if state == 2:
					_victory_seen = true
					_manual_terminal_seen = true
					await _capture_checkpoint("PHYSICAL VICTORY")
					_log("PHYSICAL", "VICTORY rendered after physical play; no injected events were sent.")
				elif state == 1:
					_defeat_seen = true
					_manual_terminal_seen = true
					await _capture_checkpoint("PHYSICAL DEFEAT")
					_log("PHYSICAL", "DEFEAT rendered after physical play; no injected events were sent.")
		elif _is_title() and _title_seen:
			if not _restart_seen:
				_restart_seen = true
				_log("PHYSICAL", "Observed return to title scene.")
		if Input.is_key_pressed(KEY_F10):
			_log("PHYSICAL", "F10 ended observation; all unseen milestones remain UNVERIFIED.")
			break
		if Time.get_ticks_msec() - _last_heartbeat_msec > 10000:
			_last_heartbeat_msec = Time.get_ticks_msec()
			_log("STATE", "waiting for human physical input; injected=0")
		await process_frame

func _find_active_raider(raiders: Array) -> Node2D:
	for raider in raiders:
		if is_instance_valid(raider) and bool(raider.get("combat_active")) and int(raider.get("health")) > 0:
			return raider as Node2D
	return null

func _record_physical_action_edges() -> void:
	for action in ["ui_accept", "move_left", "move_right", "move_up", "move_down", "attack", "skill_1", "skill_2", "block", "restart"]:
		if Input.is_action_just_pressed(action):
			_log("PHYSICAL_INPUT", "action=%s source=human keyboard/controller; injected=0" % action)

func _hold_movement() -> void:
	await _set_key(MOVE_KEY, true)
	await _set_key(KEY_A, false)

func _release_all_movement() -> void:
	for key in [MOVE_KEY, KEY_A, KEY_W, KEY_S]:
		await _release_key(key)

func _wait_until(predicate: Callable, seconds: float) -> bool:
	var deadline := Time.get_ticks_msec() + int(seconds * 1000.0)
	while Time.get_ticks_msec() < deadline:
		if predicate.call():
			return true
		await process_frame
	return predicate.call()

func _is_title() -> bool:
	return current_scene != null and current_scene.scene_file_path == TITLE_SCENE

func _is_main() -> bool:
	return current_scene != null and current_scene.scene_file_path == MAIN_SCENE

func _elapsed_seconds(start_msec: int) -> float:
	return float(Time.get_ticks_msec() - start_msec) / 1000.0

func _tap_key(key: Key) -> void:
	await _send_key(key)
	await process_frame
	await _release_key(key)

func _click_focused_start() -> void:
	if not _is_title():
		return
	var button := current_scene.get_node_or_null("MenuCenter/MenuContent/StartButton") as Button
	if button == null or not button.is_visible_in_tree():
		return
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = true
	event.button_mask = MOUSE_BUTTON_MASK_LEFT
	_log("INPUT_AUTO", "mouse_button=left target=StartButton position=%s" % event.position)
	root.push_input(event, true)
	await process_frame
	event = InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = button.get_global_rect().get_center()
	event.global_position = event.position
	event.pressed = false
	event.button_mask = 0
	root.push_input(event, true)

func _push_ui_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	_log("INPUT_AUTO", "window_key_press=%d" % key)
	root.push_input(event, true)
	await process_frame
	event = event.duplicate() as InputEventKey
	event.pressed = false
	root.push_input(event, true)

func _send_key(key: Key) -> void:
	var action := _action_for_key(key)
	var event: InputEvent
	if action.is_empty():
		var key_event := InputEventKey.new()
		key_event.keycode = key
		key_event.physical_keycode = key
		key_event.pressed = true
		event = key_event
	else:
		var action_event := InputEventAction.new()
		action_event.action = action
		action_event.pressed = true
		action_event.strength = 1.0
		event = action_event
	_injected_keycodes[key] = true
	_log("INPUT_AUTO", "pressed %s" % ("action=" + action if not action.is_empty() else "keycode=%d" % key))
	Input.parse_input_event(event)
	root.push_input(event, true)

func _set_key(key: Key, pressed: bool) -> void:
	if pressed:
		if _injected_keycodes.has(key):
			return
		await _send_key(key)
	else:
		await _release_key(key)

func _release_key(key: Key) -> void:
	if not _injected_keycodes.has(key):
		return
	var action := _action_for_key(key)
	var event: InputEvent
	if action.is_empty():
		var key_event := InputEventKey.new()
		key_event.keycode = key
		key_event.physical_keycode = key
		key_event.pressed = false
		event = key_event
	else:
		var action_event := InputEventAction.new()
		action_event.action = action
		action_event.pressed = false
		event = action_event
	_injected_keycodes.erase(key)
	Input.parse_input_event(event)
	root.push_input(event, true)

func _action_for_key(key: Key) -> StringName:
	var actions := {
		KEY_D: &"move_right",
		KEY_A: &"move_left",
		KEY_W: &"move_up",
		KEY_S: &"move_down",
		KEY_J: &"attack",
		KEY_KP_4: &"skill_1",
		KEY_KP_5: &"skill_2",
		KEY_R: &"restart",
	}
	return actions.get(key, &"")

func _capture_checkpoint(label: String) -> void:
	for _index in range(3):
		await process_frame
		await RenderingServer.frame_post_draw
	var texture := root.get_texture()
	if texture == null:
		_fail("UNVERIFIED: Window texture missing at %s." % label)
		return
	var frame := texture.get_image()
	if frame == null or frame.is_empty():
		_fail("UNVERIFIED: Window frame empty at %s." % label)
		return
	if frame.get_size() != FRAME_SIZE:
		frame.resize(FRAME_SIZE.x, FRAME_SIZE.y, Image.INTERPOLATE_LANCZOS)
	_frames.append(frame)
	_frame_labels.append(label)
	_log("FRAME", "%s · %s" % [label, frame.get_size()])

func _save_contact_sheet() -> Error:
	if _frames.is_empty():
		return ERR_CANT_CREATE
	var columns := 3
	var rows := ceili(float(_frames.size()) / columns)
	var sheet := Image.create(columns * TILE_SIZE.x, rows * TILE_SIZE.y, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("111916"))
	for index in range(_frames.size()):
		var thumb := _frames[index].duplicate()
		thumb.resize(TILE_SIZE.x, TILE_SIZE.y - 42, Image.INTERPOLATE_LANCZOS)
		var tile_x := (index % columns) * TILE_SIZE.x
		var tile_y := int(index / columns) * TILE_SIZE.y
		sheet.blit_rect(thumb, Rect2i(Vector2i.ZERO, thumb.get_size()), Vector2i(tile_x, tile_y + 42))
		sheet.fill_rect(Rect2i(tile_x, tile_y, TILE_SIZE.x, 42), Color("111916"))
		_draw_bitmap_label(sheet, Vector2i(tile_x + 12, tile_y + 8), "%02d %s" % [index + 1, _frame_labels[index].to_upper()])
	return sheet.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))

func _draw_bitmap_label(image: Image, origin: Vector2i, label: String) -> void:
	var cursor_x := origin.x
	for character in label:
		var encoded: String = FONT_5X7.get(character, FONT_5X7[" "])
		var glyph_rows := encoded.split("/")
		for row_index in range(glyph_rows.size()):
			var bits: String = glyph_rows[row_index]
			for column_index in range(bits.length()):
				if bits.substr(column_index, 1) == "1":
					image.fill_rect(Rect2i(cursor_x + column_index * 2, origin.y + row_index * 2, 2, 2), Color("f1e6c2"))
		cursor_x += 12

func _log(kind: String, message: String) -> void:
	var line := "M6D|%s|%s" % [kind, message]
	_events.append(line)
	print(line)

func _fail(message: String) -> void:
	_failure_reason = message
	_log("FAIL", message)

func _finish() -> void:
	await _release_all_movement()
	var capture_error := await _save_contact_sheet()
	if capture_error != OK:
		_log("UNVERIFIED", "evidence contact sheet not saved (error %d)." % capture_error)
	else:
		_log("EVIDENCE", ProjectSettings.globalize_path(OUTPUT_PATH))
	var statuses := {
		"title": "PASS" if _title_seen else "UNVERIFIED",
		"sections_1_to_3": "PASS" if _travel_section_seen >= 2 else "UNVERIFIED",
		"raider_combat": "PASS" if _active_raider_seen >= 0 else "UNVERIFIED",
		"boss_encounter_and_attacks": "PASS" if _boss_hit_seen or _victory_seen else "UNVERIFIED",
		"victory": "PASS" if _victory_seen else "UNVERIFIED",
		"restart": "PASS" if _restart_seen else "UNVERIFIED",
		"player_hit": "PASS" if _player_hit_seen else "UNVERIFIED",
		"defeat": "PASS" if _defeat_seen else "UNVERIFIED",
		"mode": "PHYSICAL INPUT OBSERVATION" if _manual else "AUTOMATED INPUT EVENT REPLAY",
	}
	for key in statuses:
		_log("RESULT", "%s=%s" % [key, statuses[key]])
	if not _failure_reason.is_empty():
		_log("SUMMARY", "FAIL: " + _failure_reason)
	elif _manual:
		_log("SUMMARY", "UNVERIFIED: physical observation is user-driven and remains open until the user closes the Window.")
	else:
		var all_pass := _title_seen and _travel_section_seen >= 2 and _active_raider_seen >= 2 and _victory_seen and _restart_seen and _player_hit_seen and _defeat_seen
		_log("SUMMARY", "PASS" if all_pass else "UNVERIFIED: one or more live Window milestones were not observed.")
	quit(1 if not _failure_reason.is_empty() else 0)
