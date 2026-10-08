extends Node2D
"""Owns the arena result flow separately from the combat HUD and fighters."""

enum ResultState { PLAYING, DEFEAT, VICTORY }

const EXPECTED_RAIDER_COUNT := 3
const OVERLAY_LAYER := 20
const HELP_LAYER := 10
const TITLE_SCENE := "res://scenes/ui/title_menu.tscn"
const MAIN_SCENE := "res://scenes/game/main.tscn"

var result_state: ResultState = ResultState.PLAYING
var result_overlay: CanvasLayer
var result_label: Label
var restart_label: Label
var pause_overlay: CanvasLayer
var help_panel: PanelContainer
var _paused := false
var _transition_pending := false
var _player: Node
var _raiders: Array[Node] = []
var _pause_resume_button: Button
var _pause_restart_button: Button
var _pause_title_button: Button
var _result_restart_button: Button
var _result_title_button: Button

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_PAUSABLE
	_player = get_node_or_null("YSortActors/Player")
	_raiders.clear()
	for raider in get_tree().get_nodes_in_group("forest_raiders"):
		if raider is Node and raider.get_parent() == get_node_or_null("YSortActors"):
			_raiders.append(raider)
	_build_result_overlay()
	_build_pause_overlay()
	_build_help_overlay()

func _process(_delta: float) -> void:
	if result_state != ResultState.PLAYING or _paused or _transition_pending:
		return
	if not is_instance_valid(_player):
		_player = get_node_or_null("YSortActors/Player")
	if is_instance_valid(_player) and int(_player.get("health")) <= 0:
		_finish_session(ResultState.DEFEAT)
		return
	if _raiders.size() == EXPECTED_RAIDER_COUNT:
		for raider in _raiders:
			if is_instance_valid(raider) and int(raider.get("health")) > 0:
				return
		_finish_session(ResultState.VICTORY)

func _unhandled_input(event: InputEvent) -> void:
	if _transition_pending:
		var pending_viewport := get_viewport()
		if pending_viewport != null:
			pending_viewport.set_input_as_handled()
		return
	if result_state == ResultState.PLAYING and event.is_action_pressed("pause"):
		_set_paused(not _paused)
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return
	if result_state == ResultState.PLAYING and not _paused and event.is_action_pressed("help"):
		help_panel.visible = not help_panel.visible
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()
		return
	if not _transition_pending and result_state != ResultState.PLAYING and event.is_action_pressed("restart"):
		_restart_session()
		var viewport := get_viewport()
		if viewport != null:
			viewport.set_input_as_handled()

func _set_paused(paused: bool) -> void:
	if result_state != ResultState.PLAYING or _paused == paused or _transition_pending:
		return
	_paused = paused
	if paused:
		_cancel_hit_stop_for_pause()
		Engine.time_scale = 1.0
		pause_overlay.visible = true
		get_tree().paused = true
		_pause_resume_button.grab_focus.call_deferred()
	else:
		get_tree().paused = false
		pause_overlay.visible = false

func _cancel_hit_stop_for_pause() -> void:
	if is_instance_valid(_player) and bool(_player.get("_hit_stop_active")):
		_player.set("_hit_stop_token", int(_player.get("_hit_stop_token")) + 1)
		_player.set("_hit_stop_active", false)
		_player.set("_saved_time_scale", 1.0)

func _finish_session(result: ResultState) -> void:
	if result_state != ResultState.PLAYING or _transition_pending:
		return
	if result != ResultState.DEFEAT and result != ResultState.VICTORY:
		return
	result_state = result
	if _paused:
		_paused = false
		get_tree().paused = false
		pause_overlay.visible = false
	Engine.time_scale = 1.0
	_clear_combat_impacts()
	_set_combat_active(false)
	result_label.text = "DEFEAT" if result == ResultState.DEFEAT else "VICTORY"
	result_overlay.visible = true
	_result_restart_button.grab_focus.call_deferred()

func _clear_combat_impacts() -> void:
	for impact in get_tree().get_nodes_in_group("combat_impacts"):
		if is_instance_valid(impact):
			impact.queue_free()

func _set_combat_active(active: bool) -> void:
	if is_instance_valid(_player):
		_player.set_physics_process(active)
		if not active:
			_player.velocity = Vector2.ZERO
			_cancel_player_attack()
	for raider in _raiders:
		if is_instance_valid(raider):
			raider.set_physics_process(active)
			if not active:
				raider.velocity = Vector2.ZERO
			_cancel_raider_attack(raider)

func _cancel_player_attack() -> void:
	if bool(_player.get("_hit_stop_active")):
		_player.set("_hit_stop_token", int(_player.get("_hit_stop_token")) + 1)
		_player.set("_hit_stop_active", false)
		_player.set("_saved_time_scale", 1.0)
	for index in range(1, 4):
		var hitbox := _player.get_node_or_null("Hitboxes/Hitbox%d" % index) as Area2D
		if hitbox != null:
			hitbox.monitoring = false
	var attack_flash := _player.get_node_or_null("VisualRoot/AttackFlash") as Polygon2D
	if attack_flash != null:
		attack_flash.visible = false

func _cancel_raider_attack(raider: Node) -> void:
	var attack_area := raider.get_node_or_null("AttackArea") as Area2D
	if attack_area != null:
		attack_area.monitoring = false
	var attack_flash := raider.get_node_or_null("VisualRoot/AttackFlash") as Polygon2D
	if attack_flash != null:
		attack_flash.visible = false

func _restart_session() -> void:
	if _transition_pending or not is_inside_tree():
		return
	_transition_pending = true
	_paused = false
	_set_combat_active(false)
	_restore_global_combat_state()
	get_tree().call_deferred("reload_current_scene")

func _return_to_title() -> void:
	if _transition_pending or not is_inside_tree():
		return
	_transition_pending = true
	_paused = false
	_set_combat_active(false)
	_restore_global_combat_state()
	get_tree().call_deferred("change_scene_to_file", TITLE_SCENE)

func _restore_global_combat_state() -> void:
	var tree := get_tree()
	if tree != null:
		tree.paused = false
	Engine.time_scale = 1.0
	_cancel_hit_stop_for_pause()
	if is_instance_valid(_player):
		_player.set("_saved_time_scale", 1.0)
	var combat_audio := get_node_or_null("CombatAudio")
	if is_instance_valid(combat_audio) and combat_audio.has_method("stop_all"):
		combat_audio.call("stop_all")

func _build_pause_overlay() -> void:
	pause_overlay = CanvasLayer.new()
	pause_overlay.name = "SessionPause"
	pause_overlay.layer = OVERLAY_LAYER - 1
	pause_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	pause_overlay.visible = false
	add_child(pause_overlay)
	var shade := ColorRect.new()
	shade.name = "PauseDimmer"
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.015, 0.025, 0.02, 0.58)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pause_overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(500.0, 360.0)
	center.add_child(panel)
	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 10)
	panel.add_child(layout)
	var title := Label.new()
	title.text = "일시정지"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	layout.add_child(title)
	_pause_resume_button = _make_menu_button("계속하기")
	_pause_resume_button.name = "ResumeButton"
	_pause_resume_button.pressed.connect(_on_resume_pressed)
	layout.add_child(_pause_resume_button)
	_pause_restart_button = _make_menu_button("재시작")
	_pause_restart_button.name = "RestartButton"
	_pause_restart_button.pressed.connect(_restart_session)
	layout.add_child(_pause_restart_button)
	_pause_title_button = _make_menu_button("타이틀로 돌아가기")
	_pause_title_button.name = "TitleButton"
	_pause_title_button.pressed.connect(_return_to_title)
	layout.add_child(_pause_title_button)

func _on_resume_pressed() -> void:
	_set_paused(false)

func _make_menu_button(caption: String) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(390.0, 52.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 20)
	button.add_theme_color_override("font_color", Color(0.94, 0.93, 0.84, 1.0))
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_focus_color", Color(0.94, 0.93, 0.84, 1.0))
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.035, 0.085, 0.073, 0.96)
	normal.border_color = Color(0.78, 0.72, 0.42, 0.8)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	button.add_theme_stylebox_override("normal", normal)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.10, 0.20, 0.16, 1.0)
	hover.border_color = Color(0.47, 0.73, 0.65, 1.0)
	button.add_theme_stylebox_override("hover", hover)
	button.add_theme_stylebox_override("focus", hover)
	button.add_theme_stylebox_override("pressed", hover)
	return button

func _build_help_overlay() -> void:
	var help_layer := CanvasLayer.new()
	help_layer.name = "SessionHelp"
	help_layer.layer = HELP_LAYER
	help_layer.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(help_layer)
	help_panel = PanelContainer.new()
	help_panel.name = "HelpPanel"
	help_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	help_panel.position = Vector2(-24.0, 24.0)
	help_panel.custom_minimum_size = Vector2(300.0, 0.0)
	help_panel.visible = false
	help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.075, 0.065, 0.88)
	style.border_color = Color(0.78, 0.72, 0.42, 0.8)
	style.set_border_width_all(1)
	style.set_corner_radius_all(8)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 12.0
	style.content_margin_bottom = 12.0
	help_panel.add_theme_stylebox_override("panel", style)
	help_layer.add_child(help_panel)
	var help_text := Label.new()
	help_text.text = "조작 도움말  ·  H / Select 닫기\nWASD / 방향키 / 왼쪽 스틱: 이동\nSpace / 남쪽 버튼: 점프\nC / 동쪽 버튼: 앉기\nJ / 마우스 / 서쪽 버튼: 공격\nESC / Start: 일시정지\nR / 북쪽 버튼: 결과 화면에서 재시작"
	help_text.add_theme_font_size_override("font_size", 16)
	help_text.add_theme_color_override("font_color", Color(0.94, 0.93, 0.84, 1.0))
	help_panel.add_child(help_text)

func _build_result_overlay() -> void:
	result_overlay = CanvasLayer.new()
	result_overlay.name = "SessionResult"
	result_overlay.layer = OVERLAY_LAYER
	result_overlay.visible = false
	add_child(result_overlay)

	var backdrop := ColorRect.new()
	backdrop.name = "ResultDimmer"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.color = Color(0.015, 0.025, 0.02, 0.76)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	result_overlay.add_child(backdrop)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	result_overlay.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ResultPanel"
	panel.custom_minimum_size = Vector2(560.0, 330.0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.075, 0.065, 0.97)
	panel_style.border_color = Color(0.78, 0.72, 0.42, 0.9)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(16)
	panel_style.content_margin_left = 32.0
	panel_style.content_margin_right = 32.0
	panel_style.content_margin_top = 24.0
	panel_style.content_margin_bottom = 24.0
	panel.add_theme_stylebox_override("panel", panel_style)
	center.add_child(panel)

	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 12)
	panel.add_child(layout)

	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.text = ""
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 48)
	result_label.add_theme_color_override("font_color", Color(0.94, 0.93, 0.84, 1.0))
	layout.add_child(result_label)

	restart_label = Label.new()
	restart_label.name = "RestartLabel"
	restart_label.text = "R 키 / 북쪽 버튼으로 재시작할 수 있습니다"
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.add_theme_font_size_override("font_size", 20)
	restart_label.add_theme_color_override("font_color", Color(0.78, 0.72, 0.42, 1.0))
	layout.add_child(restart_label)
	_result_restart_button = _make_menu_button("재도전")
	_result_restart_button.name = "RetryButton"
	_result_restart_button.pressed.connect(_restart_session)
	layout.add_child(_result_restart_button)
	_result_title_button = _make_menu_button("타이틀로 돌아가기")
	_result_title_button.name = "TitleButton"
	_result_title_button.pressed.connect(_return_to_title)
	layout.add_child(_result_title_button)
