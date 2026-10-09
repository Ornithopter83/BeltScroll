extends SceneTree
"""Captures the production Player turn clock in an isolated review window."""

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const OUTPUT_PATH := "res://assets/art/review/player_turn_candidate_window.png"
const TURN_ART_CANDIDATE_PATH := "res://assets/art/player/elven_fighter_turn_rear_mid_v1_candidate_1254x1254.png"
const WINDOW_SIZE := Vector2i(1920, 1080)
const COLUMNS := 4
const ROWS := 2
const TILE_SIZE := Vector2i(WINDOW_SIZE.x / COLUMNS, WINDOW_SIZE.y / ROWS)

var _stage := Node2D.new()
var _player: CharacterBody2D
var _animator: Node
var _player_art: Sprite2D
var _idle_texture: Texture2D
var _turn_art_candidate: Texture2D
var _caption: Label
var _status: Label
var _frames: Array[Image] = []
var _capture_notes: Array[String] = []

func _initialize() -> void:
	root.size = WINDOW_SIZE
	DisplayServer.window_set_size(WINDOW_SIZE)
	root.mode = Window.MODE_WINDOWED
	root.title = "Player turn candidate review · Godot 4.7.2"
	call_deferred("_run_capture")

func _run_capture() -> void:
	root.mode = Window.MODE_WINDOWED
	await process_frame
	root.size = WINDOW_SIZE
	DisplayServer.window_set_size(WINDOW_SIZE)
	await process_frame
	_stage.name = "TurnCandidateReview"
	root.add_child(_stage)
	_stage.add_child(_make_background())
	_player = PLAYER_SCENE.instantiate() as CharacterBody2D
	_player.name = "ReviewPlayer"
	_player.position = Vector2(960.0, 790.0)
	_player.get_node("Camera2D").enabled = false
	_player.set_physics_process(false)
	_stage.add_child(_player)
	_animator = _player.get_node("VisualAnimator")
	_animator.set_process(false)
	_player_art = _player.get_node("VisualRoot/PlayerArt")
	_idle_texture = _player_art.texture
	if FileAccess.file_exists(TURN_ART_CANDIDATE_PATH):
		var candidate_image := Image.new()
		if candidate_image.load(ProjectSettings.globalize_path(TURN_ART_CANDIDATE_PATH)) == OK:
			_turn_art_candidate = ImageTexture.create_from_image(candidate_image)
	_add_overlay()
	await process_frame
	await RenderingServer.frame_post_draw

	await _set_facing_and_sample(1.0)
	await _capture("IDLE · right facing", "대기 원화 · 우향 · turn clock idle")
	await _start_turn(-1.0)
	await _advance_clock(0.020)
	await _sample_after("ANTICIPATION · R→L", "0.02 s · anticipation / compression lead")
	await _advance_clock(0.035)
	if _turn_art_candidate != null:
		_player_art.texture = _turn_art_candidate
		await _sample_after("MID TURN · RAW CANDIDATE", "0.055 s · candidate art shown temporarily in review Sprite")
		_player_art.texture = _idle_texture
	else:
		await _sample_after("MID TURN · PROCEDURAL", "0.055 s · turn source absent; procedural pose comparison")
	await _advance_clock(0.020)
	await _sample_after("FACING FLIP · R→L", "0.075 s · facing flip just applied")
	await _advance_clock(0.055)
	await _sample_after("SETTLE · R→L", "0.13 s · production turn clock complete")

	await _set_facing_and_sample(-1.0)
	await _start_turn(1.0)
	await _advance_clock(0.075)
	await _sample_after("MID TURN · L→R", "0.075 s · opposite direction / after facing flip")

	await _set_facing_and_sample(-1.0)
	await _start_turn(1.0)
	await _advance_clock(0.035)
	_player.set("facing_direction", Vector2.LEFT)
	await _advance_clock(0.035)
	await _sample_after("FAST REVERSE · L→R→L", "0.07 s · reverse input retargets the in-flight turn")

	await _set_facing_and_sample(1.0)
	await _start_turn(-1.0)
	await _advance_clock(0.025)
	_player.set("hitstun_remaining", 0.12)
	_player.set("hit_flash_remaining", 0.12)
	await _advance_clock(1.0 / 60.0)
	await _sample_after("HIT CANCEL", "0.03 s · hitstun cancels turn clock")

	var final_image := _compose_montage()
	var save_error := final_image.save_png(ProjectSettings.globalize_path(OUTPUT_PATH))
	if save_error != OK:
		push_error("Could not save turn candidate window: %s" % error_string(save_error))
		quit(1)
		return
	print("Godot %s | window %dx%d | framebuffer %s | PNG %s" % [Engine.get_version_info().string, DisplayServer.window_get_size().x, DisplayServer.window_get_size().y, str(_frames[0].get_size()), OUTPUT_PATH])
	for note in _capture_notes:
		print(note)
	print("Capture complete: %d samples, frame_post_draw synchronization per sample." % _frames.size())
	quit(0)

func _make_background() -> ColorRect:
	var background := ColorRect.new()
	background.size = Vector2(WINDOW_SIZE)
	background.color = Color("#121a22")
	return background

func _add_overlay() -> void:
	var overlay := CanvasLayer.new()
	_stage.add_child(overlay)
	var panel := PanelContainer.new()
	panel.position = Vector2(650, 24)
	panel.size = Vector2(620, 142)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.045, 0.06, 0.94)
	style.border_color = Color("#6d9794")
	style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	overlay.add_child(panel)
	var stack := VBoxContainer.new()
	stack.add_theme_constant_override("separation", 7)
	panel.add_child(stack)
	_caption = _make_label("", 38, Color("#f4dfb2"))
	_status = _make_label("", 28, Color("#b8d0cf"))
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(_caption)
	stack.add_child(_status)

func _make_label(value: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

func _set_facing_and_sample(sign: float) -> void:
	_player.set("facing_direction", Vector2(sign, 0.0))
	_player.set("hitstun_remaining", 0.0)
	_player.set("hit_flash_remaining", 0.0)
	_animator.set("_applied_facing_sign", sign)
	_animator.set("_turn_target_sign", sign)
	_animator.set("_turn_elapsed", 0.13)
	_animator.set("_turn_flip_applied", false)
	_player.get_node("VisualRoot").scale.x = sign
	await process_frame
	await process_frame

func _start_turn(sign: float) -> void:
	_player.set("facing_direction", Vector2(sign, 0.0))
	await process_frame

func _advance_clock(seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.000001:
		var step := minf(remaining, 1.0 / 60.0)
		_animator.call("_process", step)
		remaining -= step
		await process_frame

func _sample_after(title: String, detail: String) -> void:
	await _capture(title, detail)

func _capture(title: String, detail: String) -> void:
	_caption.text = title
	_status.text = detail
	await process_frame
	await RenderingServer.frame_post_draw
	_frames.append(root.get_texture().get_image())
	var progress := float(_animator.call("get_turn_progress"))
	var turning := bool(_animator.call("is_turning"))
	var applied_facing := "left" if _player.get_node("VisualRoot").scale.x < 0.0 else "right"
	_capture_notes.append("%s | turn_progress=%.3f turning=%s applied_facing=%s texture=%s rotation=%.4f scale=(%.4f,%.4f) foot_anchor=(%.1f,%.1f)" % [title, progress, str(turning), applied_facing, _player_art.texture.resource_path.get_file(), _player_art.rotation, _player_art.scale.x, _player_art.scale.y, _player.global_position.x, _player.global_position.y + 2.0])

func _compose_montage() -> Image:
	var montage := Image.create(WINDOW_SIZE.x, WINDOW_SIZE.y, false, Image.FORMAT_RGBA8)
	montage.fill(Color("#0b1015"))
	for index in mini(_frames.size(), COLUMNS * ROWS):
		var destination := Rect2i(Vector2i((index % COLUMNS) * TILE_SIZE.x, (index / COLUMNS) * TILE_SIZE.y), TILE_SIZE)
		var frame := _frames[index]
		var crop_width := int(float(frame.get_height()) * float(TILE_SIZE.x) / float(TILE_SIZE.y))
		var crop_x := clampi(int(float(frame.get_width()) * 0.5) - crop_width / 2, 0, frame.get_width() - crop_width)
		var crop := frame.get_region(Rect2i(crop_x, 0, crop_width, frame.get_height()))
		crop.resize(TILE_SIZE.x, TILE_SIZE.y, Image.INTERPOLATE_LANCZOS)
		montage.blit_rect(crop, Rect2i(Vector2i.ZERO, TILE_SIZE), destination.position)
	for column in range(1, COLUMNS):
		montage.fill_rect(Rect2i(column * TILE_SIZE.x - 1, 0, 2, WINDOW_SIZE.y), Color("#6d9794"))
	montage.fill_rect(Rect2i(0, TILE_SIZE.y - 1, WINDOW_SIZE.x, 2), Color("#6d9794"))
	return montage
