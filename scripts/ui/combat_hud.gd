extends CanvasLayer

const PANEL_COLOR := Color(0.035, 0.075, 0.065, 0.86)
const BORDER_COLOR := Color(0.72, 0.65, 0.39, 0.62)
const TEXT_COLOR := Color(0.94, 0.93, 0.84, 1.0)
const MUTED_COLOR := Color(0.69, 0.75, 0.66, 1.0)
const ACCENT_COLOR := Color(0.78, 0.72, 0.42, 1.0)
const PLAYER_BAR_SPEED := 2.0
const PLAYER_DAMAGE_DELAY := 0.42
const PLAYER_DAMAGE_BAR_SPEED := 1.2
const RAIDER_BAR_SPEED := 3.0
const RAIDER_DAMAGE_DELAY := 0.28
const RAIDER_DAMAGE_BAR_SPEED := 1.5
const RAIDER_INDICATOR_SIZE := Vector2(300.0, 46.0)
const RAIDER_ROW_GAP := 0.0
const SKILL_READY_COLOR := Color(0.38, 0.83, 0.63, 1.0)
const SKILL_COOLDOWN_COLOR := Color(0.88, 0.57, 0.29, 1.0)
const SKILL_ACTIVE_COLORS := [Color(0.30, 0.78, 0.96, 1.0), Color(0.86, 0.50, 0.96, 1.0)]
const SKILL_NAMES := ["돌진", "회전"]
const SKILL_COOLDOWN_MAX := [1.35, 1.8]

var health_value_label: Label
var health_caption_label: Label
var health_bar: ProgressBar
var health_damage_bar: ProgressBar
var combo_value_label: Label
var raider_value_label: Label
var skill_slots: Array[Dictionary] = []
var _player: Node
var _player_bar_value := 1.0
var _player_damage_value := 1.0
var _player_damage_delay := 0.0
var _player_health_initialized := false
var _player_health_target := 1.0
var _raider_indicators: Dictionary = {}

func _ready() -> void:
	_build_hud()
	refresh()

func _process(delta: float) -> void:
	_advance_health_bars(delta)
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
		health_bar.max_value = 1.0
		health_damage_bar.max_value = 1.0
		var target_ratio := float(current) / float(maximum)
		health_caption_label.text = "PLAYER  ·  KO" if current == 0 else "PLAYER  /  VITALS"
		if not _player_health_initialized:
			_player_health_initialized = true
			_player_bar_value = target_ratio
			_player_damage_value = target_ratio
			_player_health_target = target_ratio
		elif not is_equal_approx(target_ratio, _player_health_target):
			if target_ratio > _player_health_target:
				# Both layers must reach the healed value together. Otherwise the red
				# layer remains visible between the interpolating live bar and target.
				_player_bar_value = target_ratio
				_player_damage_value = target_ratio
				_player_damage_delay = 0.0
			else:
				_player_damage_delay = PLAYER_DAMAGE_DELAY
			_player_health_target = target_ratio
		var stage := int(_player.get("attack_stage"))
		combo_value_label.text = "%d / 3" % stage if stage > 0 else "—"
		_update_skill_slots()
	else:
		health_value_label.text = "— / —"
		health_caption_label.text = "PLAYER  /  VITALS"
		_player_health_target = 0.0
		combo_value_label.text = "—"
		_update_skill_slots()
	health_bar.value = _player_bar_value
	health_damage_bar.value = _player_damage_value

	var remaining := 0
	var live_ids: Dictionary = {}
	for raider in get_tree().get_nodes_in_group("forest_raiders"):
		if is_instance_valid(raider):
			var health := int(raider.get("health"))
			var combat_active := bool(raider.get("combat_active"))
			if health > 0:
				remaining += 1
			if not combat_active and health > 0:
				continue
			var raider_id := raider.get_instance_id()
			live_ids[raider_id] = true
			_update_raider_indicator(raider, raider_id)
			var indicator: Dictionary = _raider_indicators[raider_id]
			var row_index := live_ids.size() - 1
			indicator["root"].position = Vector2(57.0, 190.0 + row_index * (RAIDER_INDICATOR_SIZE.y + RAIDER_ROW_GAP))
			indicator["root"].visible = true
	for raider_id in _raider_indicators.keys():
		if not live_ids.has(raider_id):
			var stale: Control = _raider_indicators[raider_id]["root"]
			if is_instance_valid(stale):
				stale.queue_free()
			_raider_indicators.erase(raider_id)
	raider_value_label.text = "%02d" % remaining

func _advance_health_bars(delta: float) -> void:
	if not _player_health_initialized:
		return
	_player_bar_value = move_toward(_player_bar_value, _player_health_target, PLAYER_BAR_SPEED * delta)
	if _player_damage_delay > 0.0:
		_player_damage_delay = maxf(0.0, _player_damage_delay - delta)
	elif _player_damage_value > _player_health_target:
		_player_damage_value = move_toward(_player_damage_value, _player_health_target, PLAYER_DAMAGE_BAR_SPEED * delta)
	else:
		_player_damage_value = _player_bar_value
	for indicator in _raider_indicators.values():
		var target := float(indicator["target"])
		indicator["bar_value"] = move_toward(float(indicator["bar_value"]), target, RAIDER_BAR_SPEED * delta)
		if float(indicator["damage_delay"]) > 0.0:
			indicator["damage_delay"] = maxf(0.0, float(indicator["damage_delay"]) - delta)
		elif float(indicator["damage_value"]) > target:
			indicator["damage_value"] = move_toward(float(indicator["damage_value"]), target, RAIDER_DAMAGE_BAR_SPEED * delta)
		else:
			indicator["damage_value"] = float(indicator["bar_value"])
		indicator["bar"].value = float(indicator["bar_value"])
		indicator["damage_bar"].value = float(indicator["damage_value"])

func _update_raider_indicator(raider: Node2D, raider_id: int) -> void:
	var indicator: Dictionary
	if _raider_indicators.has(raider_id):
		indicator = _raider_indicators[raider_id]
	else:
		indicator = _create_raider_indicator(raider_id)
		_raider_indicators[raider_id] = indicator
	var health := clampi(int(raider.get("health")), 0, maxi(1, int(raider.get("max_health"))))
	var maximum := maxi(1, int(raider.get("max_health")))
	var target := float(health) / float(maximum)
	var raider_name := str(raider.name).replace("_", " ")
	indicator["label"].text = "%s%s  %d / %d" % [raider_name, "  ·  KO" if health <= 0 else "", health, maximum]
	indicator["bar"].max_value = 1.0
	indicator["damage_bar"].max_value = 1.0
	indicator["bar"].value = float(indicator["bar_value"])
	indicator["damage_bar"].value = float(indicator["damage_value"])
	if not bool(indicator["initialized"]):
		indicator["bar_value"] = target
		indicator["damage_value"] = target
		indicator["target"] = target
		indicator["initialized"] = true
	elif target != float(indicator["target"]):
		if target > float(indicator["target"]):
			indicator["bar_value"] = target
			indicator["damage_value"] = target
			indicator["damage_delay"] = 0.0
		else:
			indicator["damage_delay"] = RAIDER_DAMAGE_DELAY
		indicator["target"] = target
	# Apply state changes so recovery never leaves a red damage tail visible.
	indicator["bar"].value = float(indicator["bar_value"])
	indicator["damage_bar"].value = float(indicator["damage_value"])

func _create_raider_indicator(raider_id: int) -> Dictionary:
	var root_control := Control.new()
	root_control.name = "RaiderHealth_%d" % raider_id
	root_control.size = RAIDER_INDICATOR_SIZE
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.z_index = 5
	$Overlay.add_child(root_control)
	var label := Label.new()
	label.position = Vector2(0.0, 0.0)
	label.size = Vector2(RAIDER_INDICATOR_SIZE.x, 16.0)
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	root_control.add_child(label)
	var damage_bar := ProgressBar.new()
	damage_bar.position = Vector2(0.0, 19.0)
	damage_bar.size = Vector2(RAIDER_INDICATOR_SIZE.x, 9.0)
	damage_bar.show_percentage = false
	damage_bar.step = 0.000001
	damage_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_health_bar(damage_bar, Color(0.88, 0.12, 0.10, 1.0))
	root_control.add_child(damage_bar)
	var bar := ProgressBar.new()
	bar.position = damage_bar.position
	bar.size = damage_bar.size
	bar.show_percentage = false
	bar.step = 0.000001
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_health_bar(bar, Color(1.0, 0.86, 0.08, 1.0))
	_set_transparent_bar_background(bar)
	root_control.add_child(bar)
	return {"root": root_control, "label": label, "bar": bar, "damage_bar": damage_bar,
		"bar_value": 0.0, "damage_value": 0.0, "damage_delay": 0.0, "target": 0.0, "initialized": false}

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
	health_caption_label = _make_caption("PLAYER  /  VITALS")
	health_layout.add_child(health_caption_label)
	health_value_label = _make_value("5 / 5", 23)
	health_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	health_layout.add_child(health_value_label)
	var health_bar_stack := Control.new()
	health_bar_stack.name = "HealthBarStack"
	health_bar_stack.custom_minimum_size = Vector2(0.0, 14.0)
	health_layout.add_child(health_bar_stack)
	health_damage_bar = ProgressBar.new()
	health_damage_bar.name = "HealthDamageBar"
	health_damage_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	health_damage_bar.show_percentage = false
	health_damage_bar.step = 0.000001
	health_damage_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_health_bar(health_damage_bar, Color(0.88, 0.12, 0.10, 1.0))
	health_bar_stack.add_child(health_damage_bar)
	health_bar = ProgressBar.new()
	health_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	health_bar.name = "HealthBar"
	health_bar.show_percentage = false
	health_bar.max_value = 1.0
	health_bar.step = 0.000001
	health_bar.value = 1.0
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_health_bar(health_bar, Color(1.0, 0.86, 0.08, 1.0))
	_set_transparent_bar_background(health_bar)
	health_bar_stack.add_child(health_bar)

	var raiders_panel := _make_panel("ActiveRaidersPanel", Vector2(42.0, 158.0), Vector2(330.0, 178.0))
	overlay.add_child(raiders_panel)
	var raiders_layout := _make_layout()
	raiders_layout.add_child(_make_caption("ACTIVE RAIDERS  /  VITALS"))
	raiders_panel.add_child(raiders_layout)
	var combo_panel := _make_panel("ComboPanel", Vector2(42.0, 336.0), Vector2(248.0, 94.0))
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

	var skills_panel := _make_panel("SkillsPanel", Vector2(650.0, 34.0), Vector2(620.0, 112.0))
	skills_panel.name = "SkillsPanel"
	overlay.add_child(skills_panel)
	var skills_layout := HBoxContainer.new()
	skills_layout.add_theme_constant_override("separation", 14)
	skills_panel.add_child(skills_layout)
	for index in range(2):
		var slot := _create_skill_slot(index)
		skill_slots.append(slot)
		skills_layout.add_child(slot["root"])
	_update_skill_slots()

func _create_skill_slot(index: int) -> Dictionary:
	var root_control := VBoxContainer.new()
	root_control.name = "Skill%dSlot" % (index + 1)
	root_control.custom_minimum_size = Vector2(270.0, 82.0)
	root_control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root_control.add_theme_constant_override("separation", 5)
	var title := Label.new()
	title.text = "NUM%d  /  %s" % [index + 4, SKILL_NAMES[index]]
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", TEXT_COLOR)
	root_control.add_child(title)
	var status := Label.new()
	status.add_theme_font_size_override("font_size", 12)
	status.add_theme_color_override("font_color", SKILL_READY_COLOR)
	root_control.add_child(status)
	var meter := ProgressBar.new()
	meter.custom_minimum_size = Vector2(0.0, 9.0)
	meter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	meter.show_percentage = false
	meter.max_value = 1.0
	meter.value = 1.0
	meter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_health_bar(meter, SKILL_READY_COLOR)
	root_control.add_child(meter)
	return {"root": root_control, "title": title, "status": status, "meter": meter, "last_color": Color.TRANSPARENT}

func _update_skill_slots() -> void:
	if skill_slots.size() != 2:
		return
	var phase := str(_player.get("skill_phase")) if is_instance_valid(_player) else "idle"
	var active_skill := int(_player.get("skill_id")) if is_instance_valid(_player) else 0
	var phase_remaining := float(_player.get("skill_phase_remaining")) if is_instance_valid(_player) else 0.0
	var cooldowns: Array = _player.get("skill_cooldowns") if is_instance_valid(_player) else [0.0, 0.0]
	for index in range(2):
		var slot: Dictionary = skill_slots[index]
		var status: Label = slot["status"]
		var meter: ProgressBar = slot["meter"]
		var color := SKILL_READY_COLOR
		var fraction := 1.0
		if phase != "idle" and active_skill == index + 1:
			color = SKILL_ACTIVE_COLORS[index]
			var phase_name := "준비 동작" if phase == "startup" else ("사용 중" if phase == "active" else "회복")
			status.text = "%s  ·  %.1f초" % [phase_name, maxf(0.0, phase_remaining)]
			var phase_max := 0.22 if index == 1 else 0.16
			fraction = clampf(phase_remaining / phase_max, 0.0, 1.0)
		elif index < cooldowns.size() and float(cooldowns[index]) > 0.001:
			color = SKILL_COOLDOWN_COLOR
			var remaining := float(cooldowns[index])
			status.text = "재사용 대기  ·  %.1f초" % remaining
			fraction = clampf(1.0 - remaining / _skill_cooldown_limit(index), 0.0, 1.0)
		else:
			status.text = "사용 가능"
		meter.value = fraction
		if slot["last_color"] != color:
			var fill := StyleBoxFlat.new()
			fill.bg_color = color
			fill.set_corner_radius_all(5)
			meter.add_theme_stylebox_override("fill", fill)
			slot["last_color"] = color

func _skill_cooldown_limit(index: int) -> float:
	if is_instance_valid(get_parent()):
		var configured: Array = get_parent().get("_player_skill_cooldowns")
		if index < configured.size() and float(configured[index]) > 0.0:
			return float(configured[index])
	return SKILL_COOLDOWN_MAX[index]

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

func _style_health_bar(bar: ProgressBar, fill_color: Color) -> void:
	var bar_background := StyleBoxFlat.new()
	bar_background.bg_color = Color(0.13, 0.19, 0.15, 1.0)
	bar_background.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("background", bar_background)
	var bar_fill := StyleBoxFlat.new()
	bar_fill.bg_color = fill_color
	bar_fill.set_corner_radius_all(5)
	bar.add_theme_stylebox_override("fill", bar_fill)

func _set_transparent_bar_background(bar: ProgressBar) -> void:
	var transparent_background := StyleBoxFlat.new()
	transparent_background.bg_color = Color(0.0, 0.0, 0.0, 0.0)
	bar.add_theme_stylebox_override("background", transparent_background)

func _find_player(node: Node) -> Node:
	if node is CharacterBody2D and node.name == "Player" and node.get("health") != null:
		return node
	for child in node.get_children():
		var found := _find_player(child)
		if found != null:
			return found
	return null
