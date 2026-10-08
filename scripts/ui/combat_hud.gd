extends CanvasLayer

const PANEL_COLOR := Color(0.035, 0.075, 0.065, 0.86)
const BORDER_COLOR := Color(0.72, 0.65, 0.39, 0.62)
const TEXT_COLOR := Color(0.94, 0.93, 0.84, 1.0)
const MUTED_COLOR := Color(0.69, 0.75, 0.66, 1.0)
const ACCENT_COLOR := Color(0.78, 0.72, 0.42, 1.0)

var health_value_label: Label
var health_bar: ProgressBar
var combo_value_label: Label
var raider_value_label: Label
var _player: Node

func _ready() -> void:
	_build_hud()
	refresh()

func _process(_delta: float) -> void:
	refresh()

func refresh() -> void:
	if not is_instance_valid(health_value_label):
		return
	if not is_instance_valid(_player):
		_player = _find_player(get_tree().root)
	if is_instance_valid(_player):
		var maximum := maxi(1, int(_player.get("max_health")))
		var current := clampi(int(_player.get("health")), 0, maximum)
		health_value_label.text = "%d / %d" % [current, maximum]
		health_bar.max_value = maximum
		health_bar.value = current
		var stage := int(_player.get("attack_stage"))
		combo_value_label.text = "%d / 3" % stage if stage > 0 else "—"
	else:
		health_value_label.text = "— / —"
		health_bar.value = 0.0
		combo_value_label.text = "—"

	var remaining := 0
	for raider in get_tree().get_nodes_in_group("forest_raiders"):
		if is_instance_valid(raider) and int(raider.get("health")) > 0:
			remaining += 1
	raider_value_label.text = "%02d" % remaining

func _build_hud() -> void:
	var overlay := Control.new()
	overlay.name = "Overlay"
	overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(overlay)

	var health_panel := _make_panel("HealthPanel", Vector2(42.0, 34.0), Vector2(330.0, 112.0))
	overlay.add_child(health_panel)
	var health_layout := _make_layout()
	health_panel.add_child(health_layout)
	health_layout.add_child(_make_caption("PLAYER  /  VITALS"))
	health_value_label = _make_value("5 / 5", 23)
	health_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_layout.add_child(health_value_label)
	health_bar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.custom_minimum_size = Vector2(0.0, 10.0)
	health_bar.show_percentage = false
	health_bar.max_value = 5.0
	health_bar.value = 5.0
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color(0.13, 0.19, 0.15, 1.0)
	bar_background.set_corner_radius_all(5)
	health_bar.add_theme_stylebox_override("background", bar_background)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = Color(0.73, 0.77, 0.45, 1.0)
	bar_fill.set_corner_radius_all(5)
	health_bar.add_theme_stylebox_override("fill", bar_fill)
	health_layout.add_child(health_bar)

	var combo_panel := _make_panel("ComboPanel", Vector2(836.0, 34.0), Vector2(248.0, 94.0))
	overlay.add_child(combo_panel)
	var combo_layout := _make_layout()
	combo_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	combo_panel.add_child(combo_layout)
	combo_layout.add_child(_make_caption("COMBO  /  STAGE"))
	combo_value_label = _make_value("—", 27)
	combo_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_layout.add_child(combo_value_label)

	var raider_panel := _make_panel("RaiderPanel", Vector2(1638.0, 34.0), Vector2(240.0, 94.0))
	overlay.add_child(raider_panel)
	var raider_layout := _make_layout()
	raider_layout.alignment = BoxContainer.ALIGNMENT_CENTER
	raider_panel.add_child(raider_layout)
	raider_layout.add_child(_make_caption("FOREST RAIDERS  /  LEFT"))
	raider_value_label = _make_value("00", 27)
	raider_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	raider_layout.add_child(raider_value_label)

func _make_panel(node_name: String, at: Vector2, size: Vector2) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	panel.position = at
	panel.size = size
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL_COLOR
	style.border_color = BORDER_COLOR
	style.set_border_width_all(1)
	style.set_corner_radius_all(12)
	style.content_margin_left = 15.0
	style.content_margin_right = 15.0
	style.content_margin_top = 9.0
	style.content_margin_bottom = 9.0
	panel.add_theme_stylebox_override("panel", style)
	return panel

func _make_layout() -> VBoxContainer:
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 4)
	return layout

func _make_caption(caption: String) -> Label:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", MUTED_COLOR)
	return label

func _make_value(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", ACCENT_COLOR if value == "—" else TEXT_COLOR)
	return label

func _find_player(node: Node) -> Node:
	if node is CharacterBody2D and node.name == "Player" and node.get("health") != null:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
