extends Control

signal quit_requested

const MAIN_SCENE := "res://scenes/game/main.tscn"
const GOLD := Color("d7bd72")
const PALE_GOLD := Color("f1e6c2")
const MUTED := Color("c0c9bc")
const TEAL := Color("78b9a6")
const INK := Color("10211e")

var _menu_content: VBoxContainer
var _controls_layer: Control
var _controls_close_button: Button
var _quit_button: Button
var _controls_return_focus: Control

func _ready() -> void:
	_build_menu()
	_build_controls_panel()

func _build_menu() -> void:
	var center := CenterContainer.new()
	center.name = "MenuCenter"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_menu_content = VBoxContainer.new()
	_menu_content.name = "MenuContent"
	_menu_content.custom_minimum_size = Vector2(520.0, 0.0)
	_menu_content.add_theme_constant_override("separation", 0)
	_menu_content.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(_menu_content)

	var ornament := HBoxContainer.new()
	ornament.alignment = BoxContainer.ALIGNMENT_CENTER
	ornament.add_theme_constant_override("separation", 14)
	_menu_content.add_child(ornament)
	ornament.add_child(_rule())
	var crest := _label("✦  FOREST RUINS  ✦", 15, TEAL)
	crest.add_theme_constant_override("outline_size", 2)
	ornament.add_child(crest)
	ornament.add_child(_rule())

	var title := _label("BELT SCROLL", 64, PALE_GOLD)
	title.name = "GameTitle"
	title.add_theme_color_override("font_shadow_color", Color(0.01, 0.02, 0.015, 0.85))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 4)
	title.add_theme_constant_override("outline_size", 2)
	title.add_theme_color_override("font_outline_color", Color(0.03, 0.07, 0.055, 0.9))
	title.add_theme_constant_override("line_spacing", 8)
	title.add_theme_constant_override("margin_top", 15)
	_menu_content.add_child(title)

	var subtitle := _label("WARRIORS OF THE LOST GROVE", 15, MUTED)
	subtitle.add_theme_constant_override("margin_top", 5)
	_menu_content.add_child(subtitle)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0.0, 38.0)
	_menu_content.add_child(spacer)

	var start_button := _make_button("게임 시작", true)
	start_button.name = "StartButton"
	start_button.pressed.connect(_start_game)
	_menu_content.add_child(start_button)

	var controls_button := _make_button("조작 안내", false)
	controls_button.name = "ControlsButton"
	controls_button.pressed.connect(_show_controls)
	_menu_content.add_child(controls_button)

	_quit_button = _make_button("종료", false)
	_quit_button.name = "QuitButton"
	_quit_button.pressed.connect(_request_quit)
	_menu_content.add_child(_quit_button)

	var footer := _label("WASD / 방향키 / 스틱 / 십자키 이동  ·  Enter / 남쪽 버튼 선택", 13, Color(0.72, 0.79, 0.73, 0.82))
	footer.add_theme_constant_override("margin_top", 18)
	_menu_content.add_child(footer)

	start_button.grab_focus.call_deferred()

func _build_controls_panel() -> void:
	_controls_layer = Control.new()
	_controls_layer.name = "ControlsOverlay"
	_controls_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_controls_layer.visible = false
	add_child(_controls_layer)

	var dimmer := ColorRect.new()
	dimmer.name = "ControlsDimmer"
	dimmer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dimmer.color = Color(0.008, 0.018, 0.016, 0.78)
	dimmer.mouse_filter = Control.MOUSE_FILTER_STOP
	_controls_layer.add_child(dimmer)

	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_controls_layer.add_child(center)

	var panel := PanelContainer.new()
	panel.name = "ControlsPanel"
	panel.custom_minimum_size = Vector2(520.0, 0.0)
	panel.add_theme_stylebox_override("panel", _panel_style())
	center.add_child(panel)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 16)
	panel.add_child(layout)

	var heading := _label("조작 안내", 32, PALE_GOLD)
	heading.name = "ControlsHeading"
	layout.add_child(heading)
	var divider := ColorRect.new()
	divider.custom_minimum_size = Vector2(0.0, 2.0)
	divider.color = Color(GOLD, 0.72)
	layout.add_child(divider)

	var controls := _label("이동     WASD / 방향키 / 왼쪽 스틱 / 십자키\n점프     Space / 남쪽 버튼\n앉기     C / 동쪽 버튼\n공격     J / 왼쪽 마우스 / 서쪽 버튼\n메뉴 선택  Enter / 남쪽 버튼\n돌아가기  Esc / 동쪽 버튼", 18, MUTED)
	controls.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	controls.add_theme_constant_override("line_spacing", 7)
	layout.add_child(controls)

	_controls_close_button = _make_button("돌아가기", true)
	_controls_close_button.name = "ControlsCloseButton"
	_controls_close_button.pressed.connect(_hide_controls)
	layout.add_child(_controls_close_button)

func _label(text_value: String, size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text_value
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	return label

func _rule() -> Control:
	var line := ColorRect.new()
	line.custom_minimum_size = Vector2(66.0, 1.0)
	line.color = Color(GOLD, 0.68)
	return line

func _make_button(caption: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = caption
	button.custom_minimum_size = Vector2(360.0, 58.0)
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_color_override("font_color", PALE_GOLD if primary else MUTED)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", PALE_GOLD)
	button.add_theme_color_override("font_focus_color", PALE_GOLD)
	button.add_theme_stylebox_override("normal", _button_style(primary, false))
	button.add_theme_stylebox_override("hover", _button_style(primary, true))
	button.add_theme_stylebox_override("pressed", _button_style(primary, true, true))
	button.add_theme_stylebox_override("focus", _focus_style())
	return button

func _button_style(primary: bool, hovered: bool, pressed: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.035, 0.085, 0.073, 0.82) if primary else Color(0.025, 0.055, 0.05, 0.58)
	if hovered:
		style.bg_color = Color(0.10, 0.20, 0.16, 0.96)
	if pressed:
		style.bg_color = Color(0.06, 0.14, 0.12, 0.98)
	style.border_color = TEAL if hovered else (Color(GOLD, 0.9) if primary else Color(GOLD, 0.42))
	style.set_border_width_all(1)
	style.border_width_left = 3 if hovered or primary else 1
	style.set_corner_radius_all(5)
	style.content_margin_left = 18.0
	style.content_margin_right = 18.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	return style

func _focus_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_color = Color(TEAL, 0.95)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	return style

func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(INK, 0.97)
	style.border_color = Color(GOLD, 0.85)
	style.set_border_width_all(2)
	style.set_corner_radius_all(9)
	style.content_margin_left = 34.0
	style.content_margin_right = 34.0
	style.content_margin_top = 28.0
	style.content_margin_bottom = 24.0
	return style

func _start_game() -> void:
	get_tree().change_scene_to_file(MAIN_SCENE)

func _show_controls() -> void:
	_controls_return_focus = get_node_or_null("MenuCenter/MenuContent/ControlsButton") as Control
	_controls_layer.visible = true
	_controls_close_button.grab_focus()

func _hide_controls() -> void:
	_controls_layer.visible = false
	if is_instance_valid(_controls_return_focus):
		_controls_return_focus.grab_focus()
	else:
		get_node("MenuCenter/MenuContent/StartButton").grab_focus()

func _unhandled_input(event: InputEvent) -> void:
	if _controls_layer == null or not _controls_layer.visible:
		return
	if event.is_action_pressed("ui_cancel"):
		_hide_controls()
		get_viewport().set_input_as_handled()

func _request_quit() -> void:
	quit_requested.emit()

func _quit_tree() -> void:
	get_tree().quit()

func _enter_tree() -> void:
	quit_requested.connect(_quit_tree)
