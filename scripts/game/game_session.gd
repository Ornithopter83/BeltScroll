extends Node2D
"""Owns the arena result flow separately from the combat HUD and fighters."""

enum ResultState { PLAYING, DEFEAT, VICTORY }

const EXPECTED_RAIDER_COUNT := 3
const OVERLAY_LAYER := 20

var result_state: ResultState = ResultState.PLAYING
var result_overlay: CanvasLayer
var result_label: Label
var restart_label: Label
var _player: Node
var _raiders: Array[Node] = []

func _ready() -> void:
	_player = get_node_or_null("YSortActors/Player")
	_raiders.clear()
	for raider in get_tree().get_nodes_in_group("forest_raiders"):
		if raider is Node and raider.get_parent() == get_node_or_null("YSortActors"):
			_raiders.append(raider)
	_build_result_overlay()

func _process(_delta: float) -> void:
	if result_state != ResultState.PLAYING:
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
	if result_state == ResultState.PLAYING or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if key_event.pressed and not key_event.echo and key_event.physical_keycode == KEY_R:
		_restart_session()

func _finish_session(result: ResultState) -> void:
	if result_state != ResultState.PLAYING:
		return
	if result != ResultState.DEFEAT and result != ResultState.VICTORY:
		return
	result_state = result
	Engine.time_scale = 1.0
	_set_combat_active(false)
	result_label.text = "DEFEAT" if result == ResultState.DEFEAT else "VICTORY"
	result_overlay.visible = true

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
	Engine.time_scale = 1.0
	get_tree().reload_current_scene()

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
	panel.custom_minimum_size = Vector2(480.0, 220.0)
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
	restart_label.text = "R 키를 눌러 다시 시작"
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.add_theme_font_size_override("font_size", 20)
	restart_label.add_theme_color_override("font_color", Color(0.78, 0.72, 0.42, 1.0))
	layout.add_child(restart_label)
