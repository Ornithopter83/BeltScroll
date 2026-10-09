extends RefCounted
"""Captures result, pause, and title screens from a real Window Viewport."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const TITLE_SCENE := "res://scenes/ui/title_menu.tscn"
const OUTPUT_PATH := "res://assets/art/review/gameplay_endings_window.png"
const FRAME_SIZE := Vector2i(1920, 1080)
const HALF_SIZE := Vector2i(960, 540)
const HIT := {"damage": 999, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1}
const STATE_LABELS := ["VICTORY · receive_hit contract outcome (not live play)", "DEFEAT · receive_hit contract outcome", "PAUSE · live main scene", "TITLE · returned from pause"]

var _failures: Array[String] = []
var _frames: Array[Image] = []

func capture(tree: SceneTree) -> Dictionary:
	_failures.clear()
	_frames.clear()
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return _failure("GEW-001", "A visible Window renderer is required.")
	tree.root.size = FRAME_SIZE
	var main := load(MAIN_SCENE) as PackedScene
	if main == null:
		return _failure("GEW-002", "Could not load the normal main.tscn scene.")
	var game := await _start_main(tree, main)
	if game == null:
		return _failure("GEW-002", "main.tscn did not start in the Window Viewport.")
	if not _check_main_content(game):
		return _failure("GEW-003", "Main scene is missing the stage, HUD, Player, or 3 Raiders.")
	# Move only the review staging positions into the clear lower band. The result
	# itself is still reached through receive_hit and the game's normal evaluator.
	_stage_actors(game)
	for raider in game.get("_raiders"):
		raider.call("receive_hit", HIT)
	await _wait_frames(tree, 3)
	if int(game.get("result_state")) != 2 or not bool(game.get("result_overlay").visible):
		return _failure("GEW-004", "Raider receive_hit calls did not produce the evaluated VICTORY result.")
	_check_result_controls(game, "VICTORY")
	var retry := game.get("_result_restart_button") as Button
	var title_button := game.get("_result_title_button") as Button
	if retry == null or title_button == null or not _focus_inside(retry) or not _in_viewport(retry.get_global_rect()):
		return _failure("GEW-005", "Victory result buttons are absent, unfocused, or outside the viewport.")
	if _overlaps(retry.get_global_rect(), title_button.get_global_rect()):
		return _failure("GEW-006", "Victory result buttons overlap and obscure each other.")
	if not await _capture_frame(tree, "VICTORY", game, [retry, title_button]):
		return _failure("GEW-007", "Victory frame or its Player/Raider artwork failed Window validation.")
	# Verify keyboard navigation to the title action before exercising retry.
	retry.grab_focus()
	await tree.process_frame
	_send_key(tree, KEY_DOWN)
	await tree.process_frame
	_release_key(KEY_DOWN)
	await tree.process_frame
	if not _focus_inside(title_button):
		return _failure("GEW-008", "Keyboard navigation did not focus the victory title button.")
	var audio := game.get_node("CombatAudio")
	var voice := audio.get_child(0) as AudioStreamPlayer2D
	voice.stream = audio.call("_stream_for", "attack_1")
	voice.play()
	Engine.time_scale = 0.25
	retry.emit_signal("pressed")
	var victory_audio_stopped := not voice.playing
	await _wait_for_scene(tree, MAIN_SCENE, 60)
	game = tree.current_scene
	if not _restored(tree, game, victory_audio_stopped):
		return _failure("GEW-009", "Retry did not restore paused=false, time_scale=1, and stopped CombatAudio.")
	if not _check_main_content(game):
		return _failure("GEW-003", "Restarted main scene is missing expected combat content.")
	_stage_actors(game)
	var player := game.get_node("YSortActors/Player")
	player.call("receive_hit", HIT)
	await _wait_frames(tree, 3)
	if int(game.get("result_state")) != 1 or not bool(game.get("result_overlay").visible):
		return _failure("GEW-010", "Player receive_hit did not produce the evaluated DEFEAT result.")
	_check_result_controls(game, "DEFEAT")
	retry = game.get("_result_restart_button") as Button
	title_button = game.get("_result_title_button") as Button
	if not _focus_inside(retry) or not _in_viewport(retry.get_global_rect()) or _overlaps(retry.get_global_rect(), title_button.get_global_rect()):
		return _failure("GEW-006", "Defeat result buttons are unfocused, offscreen, or overlapping.")
	if not await _capture_frame(tree, "DEFEAT", game, [retry, title_button]):
		return _failure("GEW-011", "Defeat frame or its Player/Raider artwork failed Window validation.")
	# A second restart proves the same restoration path after a defeat result.
	var defeat_audio := game.get_node("CombatAudio")
	var defeat_voice := defeat_audio.get_child(0) as AudioStreamPlayer2D
	defeat_voice.stream = defeat_audio.call("_stream_for", "attack_1")
	defeat_voice.play()
	Engine.time_scale = 0.4
	retry.emit_signal("pressed")
	var defeat_audio_stopped := not defeat_voice.playing
	await _wait_for_scene(tree, MAIN_SCENE, 60)
	game = tree.current_scene
	if not _restored(tree, game, defeat_audio_stopped):
		return _failure("GEW-009", "Defeat retry did not restore paused=false, time_scale=1, and stopped CombatAudio.")
	_stage_actors(game, 770.0)
	# Pause through the production key handler, then exercise synthetic gamepad
	# focus navigation before activating the focused title Button.
	_send_key(tree, KEY_ESCAPE)
	await tree.process_frame
	var pause_layer := game.get("pause_overlay") as CanvasLayer
	var resume := game.get("_pause_resume_button") as Button
	var pause_restart := game.get("_pause_restart_button") as Button
	title_button = game.get("_pause_title_button") as Button
	var pause_audio := game.get_node("CombatAudio")
	var pause_voice := pause_audio.get_child(0) as AudioStreamPlayer2D
	if not tree.paused or pause_layer == null or not pause_layer.visible or not _focus_inside(resume):
		return _failure("GEW-012", "ESC did not show PAUSE and focus its first action.")
	pause_voice.stream = pause_audio.call("_stream_for", "attack_1")
	pause_voice.play()
	if not _in_viewport(resume.get_global_rect()) or not _in_viewport(pause_restart.get_global_rect()) or not _in_viewport(title_button.get_global_rect()):
		return _failure("GEW-013", "A pause action button is outside the viewport.")
	if _overlaps(resume.get_global_rect(), pause_restart.get_global_rect()) or _overlaps(resume.get_global_rect(), title_button.get_global_rect()) or _overlaps(pause_restart.get_global_rect(), title_button.get_global_rect()):
		return _failure("GEW-006", "Pause buttons overlap and obscure each other.")
	if not await _capture_frame(tree, "PAUSE", game, [resume, pause_restart, title_button]):
		return _failure("GEW-014", "Pause frame or its Player/Raider artwork failed Window validation.")
	_send_joypad_button(tree, JOY_BUTTON_DPAD_DOWN)
	await tree.process_frame
	_release_joypad_button(tree, JOY_BUTTON_DPAD_DOWN)
	await tree.process_frame
	_send_joypad_button(tree, JOY_BUTTON_DPAD_DOWN)
	await tree.process_frame
	_release_joypad_button(tree, JOY_BUTTON_DPAD_DOWN)
	await tree.process_frame
	if not _focus_inside(title_button):
		return _failure("GEW-015", "Synthetic gamepad navigation did not focus the pause title button.")
	# Trigger the focused production Button signal synchronously so the stop_all
	# postcondition is measured before its old scene and voices are freed.
	title_button.emit_signal("pressed")
	var title_audio_stopped := not pause_voice.playing
	await _wait_for_scene(tree, TITLE_SCENE, 60)
	if tree.paused or not is_equal_approx(Engine.time_scale, 1.0) or not title_audio_stopped:
		return _failure("GEW-016", "Returning to title left pause=%s time_scale=%.3f audio_stopped=%s scene=%s." % [tree.paused, Engine.time_scale, title_audio_stopped, tree.current_scene.scene_file_path if tree.current_scene != null else "<null>"])
	if not await _capture_frame(tree, "TITLE", null, []):
		return _failure("GEW-017", "Title return frame is empty, offscreen, or not 1920x1080.")
	var save_error := await _build_comparison(tree)
	if save_error != OK:
		return _failure("GEW-018", "Could not save 1920x1080 final-screen comparison (error %d)." % save_error)
	print("gameplay-endings-window-gate: victory came from Raider receive_hit calls; this is not labeled live-combat victory")
	print("gameplay-endings-window-gate: validated evaluated VICTORY/DEFEAT, PAUSE, title return, controls, HUD, Player/3 Raiders, and restored globals")
	print("gameplay-endings-window-gate: saved %s" % OUTPUT_PATH)
	return {"ok": _failures.is_empty(), "path": ProjectSettings.globalize_path(OUTPUT_PATH), "failures": _failures.duplicate()}

func _start_main(tree: SceneTree, packed: PackedScene) -> Node:
	Engine.time_scale = 1.0
	tree.paused = false
	var game := packed.instantiate()
	tree.root.add_child(game)
	tree.current_scene = game
	await _wait_frames(tree, 2)
	return game

func _check_main_content(game: Node) -> bool:
	if game == null or not is_instance_valid(game):
		return false
	var stage := game.get_node_or_null("StageBackground") as Sprite2D
	var actors := game.get_node_or_null("YSortActors") as Node2D
	var player := game.get_node_or_null("YSortActors/Player")
	var hud := game.get_node_or_null("CombatHUD")
	var camera := game.get_node_or_null("YSortActors/Player/Camera2D") as Camera2D
	var raiders: Array = game.get("_raiders")
	if stage == null or stage.texture == null or stage.texture.get_size() != Vector2(FRAME_SIZE) or actors == null or not actors.y_sort_enabled or player == null or hud == null or raiders.size() != 3 or camera == null or not camera.is_current():
		return false
	if not _valid_sprite(player.get_node_or_null("VisualRoot/PlayerArt")):
		return false
	for raider in raiders:
		if not _valid_sprite(raider.get_node_or_null("VisualRoot/RaiderArt")):
			return false
	return true

func _valid_sprite(node: Node) -> bool:
	return node is Sprite2D and (node as Sprite2D).texture != null and (node as Sprite2D).texture.get_size().x > 0 and node.is_visible_in_tree()

func _stage_actors(game: Node, floor_y: float = 680.0) -> void:
	var player := game.get_node("YSortActors/Player")
	player.global_position = Vector2(960.0, floor_y)
	var raiders: Array = game.get("_raiders")
	var review_positions := [360.0, 700.0, 1460.0]
	for index in range(raiders.size()):
		raiders[index].global_position = Vector2(review_positions[index], floor_y)
	var camera := player.get_node_or_null("Camera2D") as Camera2D
	if camera != null:
		camera.position_smoothing_enabled = false
		camera.make_current()
		camera.reset_smoothing()
		camera.force_update_scroll()

func _check_result_controls(game: Node, state: String) -> void:
	var overlay := game.get("result_overlay") as CanvasLayer
	var restart := game.get("_result_restart_button") as Button
	var title := game.get("_result_title_button") as Button
	if overlay == null or not overlay.visible or restart == null or title == null:
		_failures.append("%s result does not show both actions." % state)
		return
	if not _focus_inside(restart):
		_failures.append("%s result does not focus its keyboard/gamepad restart action." % state)
	if not _in_viewport(restart.get_global_rect()) or not _in_viewport(title.get_global_rect()):
		_failures.append("%s result action is outside the Window Viewport." % state)
	if restart.get_global_rect().intersects(title.get_global_rect()):
		_failures.append("%s result actions overlap." % state)

func _capture_frame(tree: SceneTree, state: String, game: Node, buttons: Array) -> bool:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var viewport := tree.root.get_texture()
	if viewport == null:
		_failures.append("%s Window Viewport texture is missing." % state)
		return false
	var image := viewport.get_image()
	if image == null or image.is_empty() or image.get_size() != FRAME_SIZE or not _image_has_scene_content(image):
		_failures.append("%s actual Window frame is empty, black, or not 1920x1080." % state)
		return false
	for button in buttons:
		if not is_instance_valid(button) or not button.is_visible_in_tree() or not _in_viewport(button.get_global_rect()):
			_failures.append("%s action is hidden or clipped by the Window edge." % state)
			return false
		if not await _button_is_rendered(tree, image, button, state):
			return false
	if game != null:
		if not await _hud_is_rendered(tree, image, game, state):
			return false
		if state == "VICTORY" or state == "DEFEAT":
			if not await _result_panel_is_rendered(tree, image, game, state):
				return false
		if not await _all_actor_art_reaches_viewport(tree, image, game, state):
			return false
	_frames.append(image)
	return true

func _button_is_rendered(tree: SceneTree, captured: Image, button: Button, state: String) -> bool:
	var bounds := button.get_global_rect()
	var was_visible := button.visible
	var had_focus := button.has_focus()
	button.visible = false
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var without_button := tree.root.get_texture().get_image()
	button.visible = was_visible
	if had_focus:
		button.grab_focus()
	await tree.process_frame
	await RenderingServer.frame_post_draw
	if _changed_pixels(captured, without_button, bounds) < 12:
		_failures.append("%s action is not changing rendered pixels; it may be obscured." % state)
		return false
	return true

func _hud_is_rendered(tree: SceneTree, captured: Image, game: Node, state: String) -> bool:
	var hud := game.get_node_or_null("CombatHUD") as CanvasLayer
	if hud == null or not hud.visible:
		_failures.append("%s CombatHUD is hidden." % state)
		return false
	var panels: Array[Control] = []
	for name in ["HealthPanel", "ComboPanel", "RaiderPanel"]:
		var panel := hud.get_node_or_null("Overlay/" + name) as Control
		if panel == null or not panel.is_visible_in_tree() or not _in_viewport(panel.get_global_rect()):
			_failures.append("%s HUD panel %s is absent, clipped, or offscreen." % [state, name])
			return false
		panels.append(panel)
	hud.visible = false
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var without_hud := tree.root.get_texture().get_image()
	hud.visible = true
	await tree.process_frame
	await RenderingServer.frame_post_draw
	for panel in panels:
		if _changed_pixels(captured, without_hud, panel.get_global_rect()) < 8:
			_failures.append("%s HUD panel %s has no visible rendered pixels." % [state, panel.name])
			return false
	return true

func _result_panel_is_rendered(tree: SceneTree, captured: Image, game: Node, state: String) -> bool:
	var panel := game.get_node_or_null("SessionResult/Center/ResultPanel") as Control
	var hud := game.get_node_or_null("CombatHUD/Overlay") as Control
	if panel == null or not panel.is_visible_in_tree() or hud == null:
		_failures.append("%s result panel or HUD bounds are missing." % state)
		return false
	var panel_bounds := panel.get_global_rect().abs()
	var combo := hud.get_node_or_null("ComboPanel") as Control
	if combo == null or panel_bounds.position.y < combo.get_global_rect().end.y + 12.0 or panel_bounds.position.y < 760.0 or panel_bounds.end.y > 1050.0:
		_failures.append("%s result panel is outside the lower safe band below the HUD and actor art." % state)
		return false
	var was_visible := panel.visible
	panel.visible = false
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var without_panel := tree.root.get_texture().get_image()
	panel.visible = was_visible
	await tree.process_frame
	await RenderingServer.frame_post_draw
	if _changed_pixels(captured, without_panel, panel_bounds) < 100:
		_failures.append("%s result panel has no visible rendered pixels." % state)
		return false
	return true

func _all_actor_art_reaches_viewport(tree: SceneTree, captured: Image, game: Node, state: String) -> bool:
	var sprites: Array[Sprite2D] = [game.get_node("YSortActors/Player/VisualRoot/PlayerArt")]
	for raider in game.get("_raiders"):
		sprites.append(raider.get_node("VisualRoot/RaiderArt"))
	for sprite in sprites:
		var bounds := _sprite_bounds(sprite)
		if (state != "PAUSE" and not _in_viewport(bounds)) or not sprite.is_visible_in_tree():
			_failures.append("%s contains offscreen or hidden actor art at %s." % [state, bounds])
			return false
		if state == "VICTORY" or state == "DEFEAT":
			var panel := game.get_node("SessionResult/Center/ResultPanel") as Control
			var intersection := bounds.intersection(panel.get_global_rect().abs())
			var actor_area: float = maxf(1.0, bounds.get_area())
			var covered_fraction: float = intersection.get_area() / actor_area
			if covered_fraction > 0.02:
				_failures.append("%s result panel geometrically covers %.1f%% of %s actor art." % [state, covered_fraction * 100.0, sprite.get_path()])
				return false
		var was_visible := sprite.visible
		sprite.visible = false
		await tree.process_frame
		await RenderingServer.frame_post_draw
		var without_sprite := tree.root.get_texture().get_image()
		sprite.visible = was_visible
		await tree.process_frame
		await RenderingServer.frame_post_draw
		if _changed_pixels(captured, without_sprite, bounds) < 24:
			_failures.append("%s Player/Raider texture is blank or obscured: %s." % [state, sprite.get_path()])
			return false
	if state == "VICTORY" or state == "DEFEAT":
		print("gameplay-endings-window-gate: %s result panel/actor bounds overlap is below 2%% for Player and all Raiders" % state)
	return true

func _changed_pixels(first: Image, second: Image, bounds: Rect2) -> int:
	if second == null or second.is_empty() or second.get_size() != first.get_size():
		return 0
	var area := bounds.abs().intersection(Rect2(Vector2.ZERO, Vector2(FRAME_SIZE)))
	var count := 0
	var step_x := maxi(1, int(area.size.x / 180.0))
	var step_y := maxi(1, int(area.size.y / 180.0))
	for y in range(maxi(0, int(area.position.y)), mini(FRAME_SIZE.y, int(area.end.y)), step_y):
		for x in range(maxi(0, int(area.position.x)), mini(FRAME_SIZE.x, int(area.end.x)), step_x):
			if first.get_pixel(x, y) != second.get_pixel(x, y):
				count += 1
	return count

func _sprite_bounds(sprite: Sprite2D) -> Rect2:
	var local := sprite.get_rect()
	var transform := sprite.get_global_transform_with_canvas()
	var points: Array[Vector2] = [transform * local.position, transform * Vector2(local.end.x, local.position.y), transform * local.end, transform * Vector2(local.position.x, local.end.y)]
	var left: float = points[0].x
	var right: float = points[0].x
	var top: float = points[0].y
	var bottom: float = points[0].y
	for point in points:
		left = minf(left, point.x)
		right = maxf(right, point.x)
		top = minf(top, point.y)
		bottom = maxf(bottom, point.y)
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))

func _image_has_scene_content(image: Image) -> bool:
	var varied := 0
	var brightest := 0.0
	var darkest := 1.0
	for y in range(24, FRAME_SIZE.y, 48):
		for x in range(24, FRAME_SIZE.x, 48):
			var color := image.get_pixel(x, y)
			var luma := color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			brightest = maxf(brightest, luma)
			darkest = minf(darkest, luma)
			if luma > 0.025:
				varied += 1
	return varied >= 100 and brightest - darkest >= 0.08

func _build_comparison(tree: SceneTree) -> Error:
	var board := Control.new()
	board.name = "GameplayEndingsComparison"
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	tree.root.add_child(board)
	for index in range(_frames.size()):
		var x := (index % 2) * HALF_SIZE.x
		var y := int(index / 2) * HALF_SIZE.y
		var panel_image := _frames[index].duplicate()
		panel_image.resize(HALF_SIZE.x, HALF_SIZE.y, Image.INTERPOLATE_LANCZOS)
		var texture := TextureRect.new()
		texture.texture = ImageTexture.create_from_image(panel_image)
		texture.position = Vector2(x, y)
		texture.size = Vector2(HALF_SIZE)
		texture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		texture.stretch_mode = TextureRect.STRETCH_SCALE
		board.add_child(texture)
		var header := ColorRect.new()
		header.position = Vector2(x, y)
		header.size = Vector2(HALF_SIZE.x, 34)
		header.color = Color(0.015, 0.025, 0.02, 0.92)
		board.add_child(header)
		var label := Label.new()
		label.text = STATE_LABELS[index]
		label.position = Vector2(x + 12, y + 3)
		label.size = Vector2(HALF_SIZE.x - 24, 28)
		label.add_theme_font_size_override("font_size", 18)
		label.add_theme_color_override("font_color", Color(0.95, 0.9, 0.72, 1.0))
		board.add_child(label)
	await tree.process_frame
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var image := tree.root.get_texture().get_image()
	if image == null or image.is_empty() or image.get_size() != FRAME_SIZE:
		return ERR_INVALID_DATA
	return image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))

func _restored(tree: SceneTree, game: Node, prior_audio_stopped: bool) -> bool:
	if game == null or not is_instance_valid(game):
		return false
	var new_audio := game.get_node_or_null("CombatAudio")
	return not tree.paused and is_equal_approx(Engine.time_scale, 1.0) and prior_audio_stopped and new_audio != null and new_audio.can_process()

func _wait_for_scene(tree: SceneTree, path: String, max_frames: int) -> void:
	for _index in range(max_frames):
		await tree.process_frame
		if tree.current_scene != null and tree.current_scene.scene_file_path == path:
			await _wait_frames(tree, 2)
			return

func _wait_frames(tree: SceneTree, count: int) -> void:
	for _index in range(count):
		await tree.process_frame

func _send_key(tree: SceneTree, key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = true
	Input.parse_input_event(event)

func _release_key(key: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = false
	Input.parse_input_event(event)

func _send_joypad_button(tree: SceneTree, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)

func _release_joypad_button(tree: SceneTree, button: JoyButton) -> void:
	var event := InputEventJoypadButton.new()
	event.device = 0
	event.button_index = button
	event.pressed = false
	Input.parse_input_event(event)

func _focus_inside(button: Button) -> bool:
	return button != null and button.is_visible_in_tree() and button.has_focus() and button.focus_mode == Control.FOCUS_ALL

func _in_viewport(rect: Rect2) -> bool:
	var bounds := rect.abs()
	return bounds.size.x > 0.0 and bounds.size.y > 0.0 and bounds.position.x >= -0.5 and bounds.position.y >= -0.5 and bounds.end.x <= FRAME_SIZE.x + 0.5 and bounds.end.y <= FRAME_SIZE.y + 0.5

func _overlaps(first: Rect2, second: Rect2) -> bool:
	return first.abs().intersects(second.abs())

func _failure(code: String, message: String) -> Dictionary:
	push_error("%s: %s" % [code, message])
	return {"ok": false, "code": code, "message": message, "failures": _failures.duplicate()}
