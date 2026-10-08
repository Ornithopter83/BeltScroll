extends RefCounted
"""Captures validated gameplay frames from the active Window Viewport."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OUTPUT_PATH := "res://assets/art/review/gameplay_window_render_gate.png"
const EXPECTED_SIZE := Vector2i(1920, 1080)
const PANEL_SIZE := Vector2i(960, 540)
const PANEL_ORIGINS := [Vector2i(0, 0), Vector2i(960, 0), Vector2i(0, 540), Vector2i(960, 540)]
const PANEL_LABELS := ["IDLE", "MOVE", "ATTACK", "HIT"]

var _failures: Array[String] = []

func capture(tree: SceneTree) -> Dictionary:
	_failures.clear()
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		return _failure("GWR-001", "A Window renderer is required; the active display server is headless.")
	if ProjectSettings.get_setting("rendering/renderer/rendering_method", "") not in ["gl_compatibility", "mobile", "forward_plus"]:
		return _failure("GWR-002", "The active Godot renderer is unsupported or unidentified.")

	tree.root.size = EXPECTED_SIZE
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		return _failure("GWR-003", "Could not load %s." % MAIN_SCENE)
	var game := packed.instantiate() as Node2D
	if game == null:
		return _failure("GWR-003", "main.tscn did not instantiate as Node2D.")
	tree.root.add_child(game)
	await tree.process_frame

	var stage := game.get_node_or_null("StageBackground") as Sprite2D
	var actors := game.get_node_or_null("YSortActors") as Node2D
	var player := game.get_node_or_null("YSortActors/Player") as CharacterBody2D
	var camera := game.get_node_or_null("YSortActors/Player/Camera2D") as Camera2D
	var hud := game.get_node_or_null("CombatHUD")
	var raiders := game.get_tree().get_nodes_in_group("forest_raiders")
	if stage == null or actors == null or player == null or camera == null or hud == null or raiders.size() != 3:
		game.queue_free()
		return _failure("GWR-004", "Expected Forest Ruins, YSort, Player, active camera, HUD, and exactly 3 raiders.")
	if stage.texture == null or stage.texture.get_size() != Vector2(EXPECTED_SIZE):
		game.queue_free()
		return _failure("GWR-005", "Forest Ruins texture is missing or is not 1920x1080.")
	if not actors.y_sort_enabled or not camera.enabled or not camera.is_current():
		game.queue_free()
		return _failure("GWR-006", "YSort or the active Player camera is not enabled.")
	var player_art := player.get_node_or_null("VisualRoot/PlayerArt") as Sprite2D
	if player_art == null or player_art.texture == null or player_art.texture.get_size().x <= 0:
		game.queue_free()
		return _failure("GWR-005", "Player v8 Sprite texture is missing.")
	for raider in raiders:
		var raider_art := raider.get_node_or_null("VisualRoot/RaiderArt") as Sprite2D
		if raider_art == null or raider_art.texture == null or raider_art.texture.get_size().x <= 0:
			game.queue_free()
			return _failure("GWR-005", "A Forest Raider sprite texture is missing.")

	var frames: Array[Image] = []
	# The first image is the real idle frame after drawing the complete main scene.
	var idle := await _capture_viewport(tree)
	if not _validate_frame(idle, "idle"):
		game.queue_free()
		return _failure("GWR-007", "Idle Window Viewport frame is empty, black, or has the wrong size.")
	frames.append(idle)

	Input.action_press("move_right")
	for _frame in range(12):
		await tree.process_frame
	Input.action_release("move_right")
	var moved := await _capture_viewport(tree)
	if not _validate_frame(moved, "move"):
		game.queue_free()
		return _failure("GWR-007", "Move Window Viewport frame is empty, black, or has the wrong size.")
	if player.global_position.x <= 960.0:
		game.queue_free()
		return _failure("GWR-008", "Move state did not move the Player to the right.")
	frames.append(moved)

	player.call("_begin_attack", 1)
	await tree.process_frame
	var attack := await _capture_viewport(tree)
	if not _validate_frame(attack, "attack") or not bool(player.get_node("VisualRoot/AttackFlash").visible):
		game.queue_free()
		return _failure("GWR-009", "Attack frame is invalid or the real Player attack flash is absent.")
	frames.append(attack)

	player.call("receive_hit", {"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.4, "attack_stage": 1})
	var hit := await _capture_viewport(tree)
	if not _validate_frame(hit, "hit") or player.get("health") != 4:
		game.queue_free()
		return _failure("GWR-010", "Hit frame is invalid or the real Player receive_hit state did not apply.")
	frames.append(hit)
	if not _frames_differ(frames):
		game.queue_free()
		return _failure("GWR-011", "Representative gameplay frames did not produce distinct rendered states.")

	var board := Image.create(EXPECTED_SIZE.x, EXPECTED_SIZE.y, false, Image.FORMAT_RGBA8)
	board.fill(Color(0.025, 0.035, 0.03, 1.0))
	for index in range(frames.size()):
		var panel := frames[index].duplicate()
		panel.resize(PANEL_SIZE.x, PANEL_SIZE.y, Image.INTERPOLATE_LANCZOS)
		board.blit_rect(panel, Rect2i(Vector2i.ZERO, PANEL_SIZE), PANEL_ORIGINS[index])
		board.fill_rect(Rect2i(PANEL_ORIGINS[index].x, PANEL_ORIGINS[index].y, PANEL_SIZE.x, 32), Color(0.025, 0.035, 0.03, 0.92))
		_draw_label(board, PANEL_ORIGINS[index] + Vector2i(18, 8), PANEL_LABELS[index])
	var output_file := ProjectSettings.globalize_path(OUTPUT_PATH)
	var save_result := board.save_png(output_file)
	game.queue_free()
	if save_result != OK:
		return _failure("GWR-012", "Could not write comparison PNG (Image.save_png error %d)." % save_result)
	print("gameplay-window-render-gate: saved 1920x1080 four-state comparison PNG to %s" % output_file)
	print("gameplay-window-render-gate: verified Forest Ruins, Player v8 Sprite, 3 Raiders, HUD, YSort, and current camera")
	print("gameplay-window-render-gate: all checks passed")
	return {"ok": true, "path": output_file, "states": PANEL_LABELS.duplicate()}

func _capture_viewport(tree: SceneTree) -> Image:
	await tree.process_frame
	await RenderingServer.frame_post_draw
	var texture := tree.root.get_texture()
	if texture == null:
		return Image.new()
	return texture.get_image()

func _validate_frame(image: Image, label: String) -> bool:
	if image == null or image.is_empty() or image.get_size() != EXPECTED_SIZE:
		push_error("GWR-007 [%s]: viewport image missing or size != 1920x1080." % label)
		return false
	var varied := 0
	var brightest := 0.0
	var darkest := 1.0
	for y in range(24, image.get_height(), 48):
		for x in range(24, image.get_width(), 48):
			var color := image.get_pixel(x, y)
			var luminance: float = color.r * 0.2126 + color.g * 0.7152 + color.b * 0.0722
			brightest = maxf(brightest, luminance)
			darkest = minf(darkest, luminance)
			if luminance > 0.025:
				varied += 1
	if varied < 100 or brightest - darkest < 0.08:
		push_error("GWR-007 [%s]: rendered frame is blank or black." % label)
		return false
	return true

func _frames_differ(frames: Array[Image]) -> bool:
	var differences := 0
	for index in range(1, frames.size()):
		var changed := 0
		for y in range(80, EXPECTED_SIZE.y, 80):
			for x in range(80, EXPECTED_SIZE.x, 80):
				if frames[index].get_pixel(x, y).is_equal_approx(frames[0].get_pixel(x, y)):
					continue
				changed += 1
		if changed >= 5:
			differences += 1
	return differences >= 2

func _draw_label(image: Image, origin: Vector2i, label: String) -> void:
	const GLYPHS := {
		"A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
		"C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
		"D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
		"E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
		"H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
		"I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
		"K": ["10001", "10010", "10100", "11000", "10100", "10010", "10001"],
		"L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
		"M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
		"O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
		"T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
		"V": ["10001", "10001", "10001", "10001", "10001", "01010", "00100"]
	}
	var cursor_x := origin.x
	for character in label:
		for row in range(7):
			var bits: String = GLYPHS[character][row]
			for column in range(5):
				if bits.substr(column, 1) == "1":
					image.fill_rect(Rect2i(cursor_x + column * 2, origin.y + row * 2, 2, 2), Color(0.95, 0.9, 0.72, 1.0))
		cursor_x += 12

func _failure(code: String, message: String) -> Dictionary:
	push_error("%s: %s" % [code, message])
	return {"ok": false, "code": code, "message": message}
