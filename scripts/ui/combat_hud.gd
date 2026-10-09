extends CanvasLayer

const PANEL_COLOR := Color(0.035, 0.075, 0.065, 0.86)
const BORDER_COLOR := Color(0.72, 0.65, 0.39, 0.62)
const TEXT_COLOR := Color(0.94, 0.93, 0.84, 1.0)
const MUTED_COLOR := Color(0.69, 0.75, 0.66, 1.0)
const ACCENT_COLOR := Color(0.78, 0.72, 0.42, 1.0)
const PLAYER_BAR_SPEED := 7.0
const PLAYER_DAMAGE_DELAY := 0.42
const PLAYER_DAMAGE_BAR_SPEED := 2.0
const RAIDER_BAR_SPEED := 8.0
const RAIDER_DAMAGE_DELAY := 0.28
const RAIDER_DAMAGE_BAR_SPEED := 3.0
const RAIDER_INDICATOR_SIZE := Vector2(92.0, 29.0)
const RAIDER_HEAD_PADDING := 12.0
const HUD_TOP_CLEARANCE := 148.0
const SKILL_READY_COLOR := Color(0.38, 0.83, 0.63, 1.0)
const SKILL_COOLDOWN_COLOR := Color(0.88, 0.57, 0.29, 1.0)
const SKILL_ACTIVE_COLORS := [Color(0.30, 0.78, 0.96, 1.0), Color(0.86, 0.50, 0.96, 1.0)]
const SKILL_NAMES := ["돌진", "회전"]
const SKILL_COOLDOWN_MAX := [1.35, 1.8]

var health_value_label: Label
var health_bar: ProgressBar
var health_damage_bar: ProgressBar
var combo_value_label: Label
var raider_value_label: Label
var skill_slots: Array[Dictionary] = []
var _player: Node
var _player_bar_value := 5.0
var _player_damage_value := 5.0
var _player_damage_delay := 0.0
var _player_health_initialized := false
var _player_health_target := 5.0
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
		health_bar.max_value = maximum
		health_damage_bar.max_value = maximum
		if not _player_health_initialized:
			_player_health_initialized = true
			_player_bar_value = float(current)
			_player_damage_value = float(current)
			_player_health_target = float(current)
		elif float(current) != _player_health_target:
			if float(current) > _player_health_target:
				# Both layers must reach the healed value together. Otherwise the red
				# layer remains visible between the interpolating live bar and target.
				_player_bar_value = float(current)
				_player_damage_value = float(current)
				_player_damage_delay = 0.0
			else:
				_player_damage_delay = PLAYER_DAMAGE_DELAY
			_player_health_target = float(current)
		var stage := int(_player.get("attack_stage"))
		combo_value_label.text = "%d / 3" % stage if stage > 0 else "—"
		_update_skill_slots()
	else:
		health_value_label.text = "— / —"
		_player_health_target = 0.0
		combo_value_label.text = "—"
		_update_skill_slots()
	health_bar.value = _player_bar_value
	health_damage_bar.value = _player_damage_value

	var remaining := 0
	var live_ids: Dictionary = {}
	for raider in get_tree().get_nodes_in_group("forest_raiders"):
		if is_instance_valid(raider):
			var raider_id := raider.get_instance_id()
			live_ids[raider_id] = true
			_update_raider_indicator(raider, raider_id)
			if int(raider.get("health")) > 0:
				remaining += 1
	for raider_id in _raider_indicators.keys():
		if not live_ids.has(raider_id):
			var stale: Control = _raider_indicators[raider_id]["root"]
			if is_instance_valid(stale):
				stale.queue_free()
			_raider_indicators.erase(raider_id)
	raider_value_label.text = "%02d" % remaining
	_ensure_player_indicator_order()

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
	var health := maxi(0, int(raider.get("health")))
	var maximum := maxi(1, int(raider.get("max_health")))
	var target := float(health)
	indicator["label"].text = "%d / %d" % [health, maximum]
	indicator["bar"].max_value = maximum
	indicator["damage_bar"].max_value = maximum
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
	# Apply state changes before any visibility/placement early return so a
	# visible Raider that heals cannot retain the previous frame's red tail.
	indicator["bar"].value = float(indicator["bar_value"])
	indicator["damage_bar"].value = float(indicator["damage_value"])
	var root_control: Control = indicator["root"]
	if health <= 0:
		root_control.visible = false
		return
	root_control.visible = true
	var camera := get_viewport().get_camera_2d()
	if camera == null:
		root_control.visible = false
		return
	var raider_art := raider.get_node_or_null("VisualRoot/RaiderArt") as Sprite2D
	if raider_art == null or raider_art.texture == null:
		root_control.visible = false
		return
	# Re-read the alpha bounds each frame: an animated or edited texture can
	# change its silhouette while the Raider remains alive.
	var alpha_bounds := _texture_alpha_bounds(raider_art.texture)
	indicator["alpha_bounds"] = alpha_bounds
	if alpha_bounds.size == Vector2i.ZERO:
		root_control.visible = false
		return
	# This point is in sprite-local coordinates. The full canvas transform below
	# applies Sprite2D scale/flip, actor transforms, Camera2D zoom and rotation.
	var local_head := Vector2(
		float(alpha_bounds.position.x) + float(alpha_bounds.size.x) * 0.5,
		float(alpha_bounds.position.y)
		) - Vector2(raider_art.texture.get_size()) * 0.5
	var screen_head: Vector2 = raider_art.get_global_transform_with_canvas() * local_head
	var view_size: Vector2 = get_viewport().get_visible_rect().size
	var indicator_position := Vector2(
		screen_head.x - RAIDER_INDICATOR_SIZE.x * 0.5,
		screen_head.y - RAIDER_INDICATOR_SIZE.y - RAIDER_HEAD_PADDING
	)
	var viewport_rect := Rect2(Vector2.ZERO, view_size)
	# Never clamp an off-screen Raider to a viewport edge: that makes a remote
	# enemy look as if it were beside the player. Hide partially clipped bars too.
	indicator_position = _choose_raider_indicator_position(raider, indicator_position, viewport_rect)
	if indicator_position.x < 0.0:
		root_control.visible = false
		return
	root_control.position = indicator_position
	root_control.visible = true
	indicator["bar"].value = float(indicator["bar_value"])
	indicator["damage_bar"].value = float(indicator["damage_value"])

func _choose_raider_indicator_position(raider: Node2D, preferred: Vector2, viewport_rect: Rect2) -> Vector2:
	var blocker_bounds: Array[Rect2] = []
	var player := _find_player(get_tree().root)
	if is_instance_valid(player):
		for sprite in _visible_actor_sprites(player):
			var bounds := _sprite_alpha_screen_bounds(sprite)
			if bounds.get_area() > 0.0:
				blocker_bounds.append(bounds)
	for other in get_tree().get_nodes_in_group("forest_raiders"):
		if other == raider or not is_instance_valid(other):
			continue
		for sprite in _visible_actor_sprites(other):
			var bounds := _sprite_alpha_screen_bounds(sprite)
			if bounds.get_area() > 0.0:
				blocker_bounds.append(bounds)
	var best := Vector2(-1.0, -1.0)
	var best_score := INF
	var candidates: Array[Vector2] = []
	# Prefer the familiar position just above the alpha head. If that position is
	# clipped by the fixed HUD, try a readable row below the head; tall sprites can
	# otherwise lose their health indicator even while the Raider is on screen.
	var vertical_positions := [preferred.y, maxf(HUD_TOP_CLEARANCE + 4.0, preferred.y + 48.0)]
	for vertical_index in range(vertical_positions.size()):
		var candidate_y := float(vertical_positions[vertical_index])
		var offsets := [0.0, -56.0, 56.0, -112.0, 112.0, -168.0, 168.0, -224.0, 224.0, -280.0, 280.0, -336.0, 336.0, -392.0, 392.0, -448.0, 448.0]
		for offset in offsets:
			candidates.append(Vector2(preferred.x + float(offset), candidate_y))
	for candidate in candidates:
		var rect := Rect2(candidate, RAIDER_INDICATOR_SIZE)
		if not viewport_rect.encloses(rect):
			continue
		if _overlaps_fixed_hud(rect):
			continue
		var score := absf(candidate.x - preferred.x) * 2.0 + absf(candidate.y - preferred.y) * 3.0
		var actor_overlap := 0.0
		for actor_bounds in blocker_bounds:
			actor_overlap += rect.intersection(actor_bounds).get_area()
		# Prefer clear placements. If a large sprite fills all nearby choices,
		# keep the indicator readable at the least-overlapping on-screen position
		# instead of hiding it for a living Raider.
		score += actor_overlap * 100.0
		if score < best_score:
			best_score = score
			best = candidate
	return best

func _visible_actor_sprites(actor: Node) -> Array[Sprite2D]:
	var result: Array[Sprite2D] = []
	for child in actor.find_children("*", "Sprite2D", true, false):
		var sprite := child as Sprite2D
		if sprite != null and sprite.is_visible_in_tree() and sprite.texture != null:
			result.append(sprite)
	return result

func _sprite_alpha_screen_bounds(sprite: Sprite2D) -> Rect2:
	var alpha := _texture_alpha_bounds(sprite.texture)
	if alpha.size == Vector2i.ZERO:
		return Rect2()
	var half_size := Vector2(sprite.texture.get_size()) * 0.5
	var local_rect := Rect2(Vector2(alpha.position) - half_size, Vector2(alpha.size))
	var transform := sprite.get_global_transform_with_canvas()
	var points: Array[Vector2] = [transform * local_rect.position, transform * Vector2(local_rect.end.x, local_rect.position.y), transform * local_rect.end, transform * Vector2(local_rect.position.x, local_rect.end.y)]
	var left := points[0].x
	var top := points[0].y
	var right := points[0].x
	var bottom := points[0].y
	for point in points.slice(1):
		left = minf(left, point.x)
		top = minf(top, point.y)
		right = maxf(right, point.x)
		bottom = maxf(bottom, point.y)
	return Rect2(Vector2(left, top), Vector2(right - left, bottom - top))

func _create_raider_indicator(raider_id: int) -> Dictionary:
	var root_control := Control.new()
	root_control.name = "RaiderHealth_%d" % raider_id
	root_control.size = RAIDER_INDICATOR_SIZE
	root_control.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root_control.z_index = 5
	$Overlay.add_child(root_control)
	var raider := instance_from_id(raider_id) as Node2D
	var raider_art := raider.get_node_or_null("VisualRoot/RaiderArt") as Sprite2D if is_instance_valid(raider) else null
	var alpha_bounds := _texture_alpha_bounds(raider_art.texture) if raider_art != null and raider_art.texture != null else Rect2i()
	var label := Label.new()
	label.position = Vector2(0.0, 0.0)
	label.size = Vector2(RAIDER_INDICATOR_SIZE.x, 14.0)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 11)
	label.add_theme_color_override("font_color", TEXT_COLOR)
	root_control.add_child(label)
	var damage_bar := ProgressBar.new()
	damage_bar.position = Vector2(4.0, 16.0)
	damage_bar.size = Vector2(RAIDER_INDICATOR_SIZE.x - 8.0, 9.0)
	damage_bar.show_percentage = false
	damage_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_health_bar(damage_bar, Color(0.72, 0.25, 0.18, 1.0))
	root_control.add_child(damage_bar)
	var bar := ProgressBar.new()
	bar.position = damage_bar.position
	bar.size = damage_bar.size
	bar.show_percentage = false
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_health_bar(bar, Color(0.73, 0.77, 0.45, 1.0))
	_set_transparent_bar_background(bar)
	root_control.add_child(bar)
	return {"root": root_control, "label": label, "bar": bar, "damage_bar": damage_bar, "alpha_bounds": alpha_bounds,
		"bar_value": 0.0, "damage_value": 0.0, "damage_delay": 0.0, "target": 0.0, "initialized": false}

func _ensure_player_indicator_order() -> void:
	if health_damage_bar == null or health_bar == null:
		return
	health_damage_bar.value = _player_damage_value
	health_bar.value = _player_bar_value

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
	var health_bar_stack := Control.new()
	health_bar_stack.name = "HealthBarStack"
	health_bar_stack.custom_minimum_size = Vector2(0.0, 14.0)
	health_layout.add_child(health_bar_stack)
	health_damage_bar = ProgressBar.new()
	health_damage_bar.name = "HealthDamageBar"
	health_damage_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	health_damage_bar.show_percentage = false
	health_damage_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_health_bar(health_damage_bar, Color(0.72, 0.25, 0.18, 1.0))
	health_bar_stack.add_child(health_damage_bar)
	health_bar = ProgressBar.new()
	health_bar.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	health_bar.name = "HealthBar"
	health_bar.show_percentage = false
	health_bar.max_value = 5.0
	health_bar.value = 5.0
	health_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_style_health_bar(health_bar, Color(0.73, 0.77, 0.45, 1.0))
	_set_transparent_bar_background(health_bar)
	health_bar_stack.add_child(health_bar)

	var combo_panel := _make_panel("ComboPanel", Vector2(42.0, 162.0), Vector2(248.0, 94.0))
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

func _texture_alpha_bounds(texture: Texture2D) -> Rect2i:
	if texture == null:
		return Rect2i()
	var image := texture.get_image()
	if image == null or image.is_empty():
		return Rect2i()
	return image.get_used_rect()

func _overlaps_fixed_hud(indicator_rect: Rect2) -> bool:
	# Keep actor indicators clear of the persistent top HUD panels. The bars
	# remain tied to the actor and are hidden when there is no safe slot.
	var health_panel := Rect2(Vector2(42.0, 34.0), Vector2(330.0, 112.0))
	var skills_panel := Rect2(Vector2(650.0, 34.0), Vector2(620.0, 112.0))
	var raider_panel := Rect2(Vector2(1638.0, 34.0), Vector2(240.0, 94.0))
	return indicator_rect.intersects(health_panel) or indicator_rect.intersects(skills_panel) or indicator_rect.intersects(raider_panel)
