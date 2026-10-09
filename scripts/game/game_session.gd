extends Node2D
"""Owns the arena result flow separately from the combat HUD and fighters."""

enum ResultState { PLAYING, DEFEAT, VICTORY }

const EXPECTED_RAIDER_COUNT := 3
const OVERLAY_LAYER := 20
const HELP_LAYER := 10
const PANEL_VIEWPORT_MARGIN := 24.0
const SECTION_WIDTH := 1920.0
const WORLD_WIDTH := 5760.0
const DEFEAT_RESULT_DELAY := 1.25
const SECTION_NAMES := ["THE GREENWAY", "THE VEIL PASS", "THE RUIN GATE"]
const SECTION_TINTS := [Color(0.98, 0.82, 0.54, 0.11), Color(0.42, 0.77, 0.86, 0.21), Color(0.52, 0.44, 0.74, 0.23)]
const TITLE_SCENE := "res://scenes/ui/title_menu.tscn"
const MAIN_SCENE := "res://scenes/game/main.tscn"
const PLAYER_ID := "Player"
const RAIDER_ID := "ForestRaider"
const STAGE_ID := "ForestRuins"
const DATA_LOADER := preload("res://scripts/game/editor_data_loader.gd")

var result_state: ResultState = ResultState.PLAYING
var result_overlay: CanvasLayer
var result_label: Label
var restart_label: Label
var pause_overlay: CanvasLayer
var help_panel: PanelContainer
var _paused := false
var _transition_pending := false
var _player: Node
var _player_skill_cooldowns: Array = []
var _raiders: Array[Node] = []
var _wave_order: Array[Node] = []
var _raider_collision_states: Array[Dictionary] = []
var _next_raider_wave := 0
var _current_section := 0
var _boss: Node
var _pause_resume_button: Button
var _pause_restart_button: Button
var _pause_title_button: Button
var _result_restart_button: Button
var _result_title_button: Button
var _pause_panel: PanelContainer
var _result_panel: PanelContainer

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for child in get_children():
		child.process_mode = Node.PROCESS_MODE_PAUSABLE
	_player = get_node_or_null("YSortActors/Player")
	if is_instance_valid(_player) and _player.has_signal("skill_started"):
		_player.skill_started.connect(_on_player_skill_started)
	_raiders.clear()
	for raider in get_tree().get_nodes_in_group("forest_raiders"):
		if raider is Node and raider.get_parent() == get_node_or_null("YSortActors"):
			_raiders.append(raider)
	_boss = get_node_or_null("YSortActors/RuinsWardenBoss")
	if is_instance_valid(_boss) and _boss.has_signal("boss_ko"):
		_boss.boss_ko.connect(_on_boss_ko)
	_apply_editor_overrides()
	_initialize_raider_waves()
	_configure_continuous_stage()
	_build_stage_dressing()
	_build_result_overlay()
	_build_pause_overlay()
	_build_help_overlay()

func _apply_editor_overrides() -> void:
	var data: Dictionary = DATA_LOADER.load_data()
	var player_values := _find_override(data.get("characters", []), PLAYER_ID, "characters")
	_player_skill_cooldowns = player_values.get("skill_cooldowns", [])
	var raider_values := _find_override(data.get("enemies", []), RAIDER_ID, "enemies")
	var stage_values := _find_override(data.get("stages", []), STAGE_ID, "stages")
	if is_instance_valid(_player):
		var previous_max := int(_player.get("max_health"))
		DATA_LOADER.apply_properties(_player, player_values, ["max_health", "walk_speed", "attack_damage"])
		if player_values.has("max_health") and int(_player.get("max_health")) != previous_max:
			_player.set("health", int(_player.get("max_health")))
			_player.set_meta("editor_id", PLAYER_ID)
	for raider in get_tree().get_nodes_in_group("forest_raiders"):
		if not is_instance_valid(raider):
			continue
		DATA_LOADER.apply_properties(raider, raider_values, ["max_health", "walk_speed", "attack_damage", "attack_knockback", "attack_hit_stun", "attack_range", "recovery_duration", "windup_duration", "active_duration"])
		if raider_values.has("max_health"):
			raider.set("health", int(raider.get("max_health")))
		if raider_values.has("ai"):
			DATA_LOADER.apply_properties(raider, raider_values.ai, ["notice_range", "attack_depth_tolerance", "separation_radius", "separation_strength"])
		if raider_values.has("attack_range"):
			var attack_shape := raider.get_node_or_null("AttackArea/CollisionShape2D") as CollisionShape2D
			if attack_shape != null and attack_shape.shape is RectangleShape2D:
				var rect := attack_shape.shape.duplicate() as RectangleShape2D
				rect.size.x = maxf(24.0, float(raider_values.attack_range) * 0.82)
				attack_shape.shape = rect
		if stage_values.has("left") or stage_values.has("top") or stage_values.has("right") or stage_values.has("bottom"):
			var bounds: Rect2 = raider.get("arena_bounds")
			var left := float(stage_values.get("left", bounds.position.x))
			var top := float(stage_values.get("top", bounds.position.y))
			var right := float(stage_values.get("right", bounds.end.x))
			var bottom := float(stage_values.get("bottom", bounds.end.y))
			raider.set("arena_bounds", Rect2(Vector2(left, top), Vector2(right - left, bottom - top)))
	_apply_stage_to_player(stage_values)
	_apply_spawns(stage_values)

func _on_player_skill_started(skill_id: int) -> void:
	var index := skill_id - 1
	if not is_instance_valid(_player) or index < 0 or index >= _player_skill_cooldowns.size():
		return
	var cooldowns: Array = _player.get("skill_cooldowns")
	if index >= cooldowns.size():
		return
	cooldowns[index] = float(_player_skill_cooldowns[index])
	_player.set("skill_cooldowns", cooldowns)

func _apply_stage_to_player(stage_values: Dictionary) -> void:
	var player_bounds: Dictionary = stage_values.get("player_bounds", {})
	if not is_instance_valid(_player) or player_bounds.is_empty():
		return
	var bounds: Rect2 = _player.get("arena_bounds")
	var left := float(player_bounds.get("left", bounds.position.x))
	var top := float(player_bounds.get("top", bounds.position.y))
	var right := float(player_bounds.get("right", bounds.end.x))
	var bottom := float(player_bounds.get("bottom", bounds.end.y))
	_player.set("arena_bounds", Rect2(Vector2(left, top), Vector2(right - left, bottom - top)))

func _apply_spawns(stage_values: Dictionary) -> void:
	var actors := {PLAYER_ID: _player}
	for index in range(_raiders.size()):
		actors[RAIDER_ID if index == 0 else "%s%d" % [RAIDER_ID, index + 1]] = _raiders[index]
	for spawn in stage_values.get("spawns", []):
		var actor := actors.get(String(spawn.get("actor_id", ""))) as Node2D
		if is_instance_valid(actor):
			actor.global_position = Vector2(float(spawn.x), float(spawn.y))

func _initialize_raider_waves() -> void:
	_wave_order = _raiders.duplicate()
	_wave_order.sort_custom(func(left: Node, right: Node) -> bool: return (left as Node2D).global_position.x < (right as Node2D).global_position.x)
	_raider_collision_states.clear()
	for raider in _wave_order:
		var attack_area := raider.get_node_or_null("AttackArea") as Area2D
		var receive_area := raider.get_node_or_null("ReceiveArea") as Area2D
		_raider_collision_states.append({
			"collision_layer": int(raider.get("collision_layer")),
			"collision_mask": int(raider.get("collision_mask")),
			"attack_layer": attack_area.collision_layer if attack_area != null else 0,
			"attack_mask": attack_area.collision_mask if attack_area != null else 0,
			"receive_layer": receive_area.collision_layer if receive_area != null else 0,
			"receive_mask": receive_area.collision_mask if receive_area != null else 0,
			"receive_monitorable": receive_area.monitorable if receive_area != null else false,
		})
		_set_raider_active(raider, false)
	_next_raider_wave = 0
	_current_section = 0
	if not _wave_order.is_empty():
		_set_raider_active(_wave_order[0], true)
	if is_instance_valid(_boss) and _boss.has_method("set_combat_active"):
		_boss.call("set_combat_active", false)

func _configure_continuous_stage() -> void:
	var bounds := Rect2(237.0, 722.0, WORLD_WIDTH - 474.0, 258.0)
	if is_instance_valid(_player):
		_player.set("arena_bounds", bounds)
		var camera := _player.get_node_or_null("Camera2D") as Camera2D
		if camera != null:
			camera.limit_left = 0
			camera.limit_right = int(WORLD_WIDTH)
			camera.limit_top = 0
			camera.limit_bottom = 1080
	for raider in _raiders:
		if is_instance_valid(raider):
			raider.set("arena_bounds", Rect2(160.0, 100.0, WORLD_WIDTH - 320.0, 880.0))
	if is_instance_valid(_boss):
		_boss.set("arena_bounds", Rect2(160.0, 100.0, WORLD_WIDTH - 320.0, 880.0))

func _build_stage_dressing() -> void:
	var dressing := get_node_or_null("StageDressing") as Node2D
	if dressing == null:
		return
	for section in range(3):
		var left := float(section) * SECTION_WIDTH
		var tint := ColorRect.new()
		tint.name = "SectionTint%d" % (section + 1)
		tint.position = Vector2(left, 0.0)
		tint.size = Vector2(SECTION_WIDTH, 1080.0)
		tint.color = SECTION_TINTS[section]
		tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
		dressing.add_child(tint)
		_add_section_title(dressing, section, left)
		_add_section_landmarks(dressing, section, left)

func _add_section_title(parent: Node2D, section: int, left: float) -> void:
	var title := Label.new()
	title.name = "SectionTitle%d" % (section + 1)
	title.text = "%02d   %s" % [section + 1, SECTION_NAMES[section]]
	title.position = Vector2(left + 660.0, 365.0)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", Color(0.95, 0.91, 0.73, 0.96))
	title.add_theme_color_override("font_shadow_color", Color(0.025, 0.055, 0.05, 0.96))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 3)
	parent.add_child(title)

func _add_section_landmarks(parent: Node2D, section: int, left: float) -> void:
	var stone_colors: Array[Color] = [Color("857957"), Color("617b7a"), Color("5d5968")]
	var stone: Color = stone_colors[section]
	var landmark_x := left + 1540.0
	var base_y := 748.0
	# Each section ends at a distinct landmark; the arrow points to the next encounter.
	if section == 0:
		_add_polygon(parent, "BrokenPillar1", [Vector2(left + 1490, 610), Vector2(left + 1545, 610), Vector2(left + 1556, 766), Vector2(left + 1484, 766)], stone.darkened(0.32))
		_add_polygon(parent, "BrokenPillarCap1", [Vector2(left + 1477, 598), Vector2(left + 1553, 598), Vector2(left + 1568, 619), Vector2(left + 1486, 625)], stone.lightened(0.12))
		_add_polygon(parent, "RootSweep1", [Vector2(left + 1260, 861), Vector2(left + 1370, 825), Vector2(left + 1460, 850), Vector2(left + 1590, 818), Vector2(left + 1700, 862), Vector2(left + 1670, 886), Vector2(left + 1510, 871), Vector2(left + 1400, 892)], Color(0.19, 0.22, 0.12, 0.9))
		_add_polygon(parent, "GreenwayRootForeground", [Vector2(left, 1005), Vector2(left + 255, 962), Vector2(left + 486, 986), Vector2(left + 735, 945), Vector2(left + 1010, 989), Vector2(left + 1256, 951), Vector2(left + 1510, 995), Vector2(left + 1712, 954), Vector2(left + SECTION_WIDTH, 988), Vector2(left + SECTION_WIDTH, 1080), Vector2(left, 1080)], Color(0.10, 0.16, 0.075, 0.86))
	elif section == 1:
		_add_polygon(parent, "VeilArchLeft", [Vector2(left + 1420, 762), Vector2(left + 1444, 530), Vector2(left + 1470, 520), Vector2(left + 1492, 762)], stone.darkened(0.24))
		_add_polygon(parent, "VeilArchTop", [Vector2(left + 1433, 540), Vector2(left + 1450, 503), Vector2(left + 1612, 497), Vector2(left + 1635, 527), Vector2(left + 1617, 547)], stone.lightened(0.08))
		_add_polygon(parent, "VeilArchRight", [Vector2(left + 1592, 762), Vector2(left + 1616, 526), Vector2(left + 1647, 530), Vector2(left + 1662, 762)], stone.darkened(0.28))
		_add_polygon(parent, "VeilMist", [Vector2(left + 150, 540), Vector2(left + 420, 518), Vector2(left + 780, 544), Vector2(left + 1090, 523), Vector2(left + 1410, 546), Vector2(left + 1770, 522), Vector2(left + 1900, 540), Vector2(left + 1880, 640), Vector2(left + 1560, 654), Vector2(left + 1330, 635), Vector2(left + 960, 663), Vector2(left + 620, 642), Vector2(left + 320, 670), Vector2(left + 140, 647)], Color(0.72, 0.89, 0.92, 0.31))
		_add_polygon(parent, "VeilMistLow", [Vector2(left + 20, 716), Vector2(left + 420, 690), Vector2(left + 800, 714), Vector2(left + 1240, 689), Vector2(left + 1660, 716), Vector2(left + 1900, 700), Vector2(left + 1880, 773), Vector2(left + 1430, 786), Vector2(left + 980, 758), Vector2(left + 480, 790), Vector2(left + 40, 768)], Color(0.80, 0.91, 0.91, 0.14))
	else:
		_add_polygon(parent, "GatePillarLeft", [Vector2(left + 1380, 770), Vector2(left + 1400, 397), Vector2(left + 1480, 360), Vector2(left + 1515, 770)], stone.darkened(0.24))
		_add_polygon(parent, "GateLintel", [Vector2(left + 1394, 408), Vector2(left + 1430, 346), Vector2(left + 1694, 346), Vector2(left + 1732, 410)], stone.lightened(0.08))
		_add_polygon(parent, "GatePillarRight", [Vector2(left + 1655, 770), Vector2(left + 1686, 394), Vector2(left + 1740, 410), Vector2(left + 1770, 770)], stone.darkened(0.32))
		_add_polygon(parent, "GateRune", [Vector2(left + 1548, 474), Vector2(left + 1580, 434), Vector2(left + 1612, 474), Vector2(left + 1580, 522)], Color(0.78, 0.68, 0.93, 0.46))
		_add_polygon(parent, "RuinGateHaze", [Vector2(left + 1280, 520), Vector2(left + 1370, 478), Vector2(left + 1530, 500), Vector2(left + 1710, 470), Vector2(left + 1820, 522), Vector2(left + 1780, 724), Vector2(left + 1320, 730)], Color(0.40, 0.34, 0.61, 0.18))
		_add_polygon(parent, "RuinForeground", [Vector2(left, 976), Vector2(left + 225, 930), Vector2(left + 438, 971), Vector2(left + 690, 926), Vector2(left + 904, 966), Vector2(left + 1115, 937), Vector2(left + 1392, 981), Vector2(left + 1600, 934), Vector2(left + SECTION_WIDTH, 969), Vector2(left + SECTION_WIDTH, 1080), Vector2(left, 1080)], Color(0.12, 0.11, 0.17, 0.92))
	# A visible route marker sits in the distant scenery and never participates in collisions.
	_add_polygon(parent, "TrailMarkerStem%d" % (section + 1), [Vector2(landmark_x, base_y - 98), Vector2(landmark_x + 16, base_y - 98), Vector2(landmark_x + 20, base_y), Vector2(landmark_x - 4, base_y)], stone.darkened(0.22))
	_add_polygon(parent, "TrailMarkerArrow%d" % (section + 1), [Vector2(landmark_x - 34, base_y - 88), Vector2(landmark_x + 27, base_y - 88), Vector2(landmark_x + 27, base_y - 108), Vector2(landmark_x + 62, base_y - 78), Vector2(landmark_x + 27, base_y - 48), Vector2(landmark_x + 27, base_y - 68), Vector2(landmark_x - 34, base_y - 68)], stone.lightened(0.2))

func _add_polygon(parent: Node2D, polygon_name: String, points: Array[Vector2], color: Color) -> void:
	var shape := Polygon2D.new()
	shape.name = polygon_name
	shape.polygon = PackedVector2Array(points)
	shape.color = color
	parent.add_child(shape)

func _set_raider_active(raider: Node, active: bool) -> void:
	var index := _wave_order.find(raider)
	if index < 0 or index >= _raider_collision_states.size():
		return
	var state: Dictionary = _raider_collision_states[index]
	raider.set("combat_active", active)
	var attack_area := raider.get_node_or_null("AttackArea") as Area2D
	var receive_area := raider.get_node_or_null("ReceiveArea") as Area2D
	if active:
		raider.visible = true
		raider.set("collision_layer", int(state.collision_layer))
		raider.set("collision_mask", int(state.collision_mask))
		if attack_area != null:
			attack_area.collision_layer = int(state.attack_layer)
			attack_area.collision_mask = int(state.attack_mask)
		if receive_area != null:
			receive_area.collision_layer = int(state.receive_layer)
			receive_area.collision_mask = int(state.receive_mask)
			receive_area.monitorable = bool(state.receive_monitorable)
		raider.set_physics_process(true)
	else:
		_cancel_raider_attack(raider)
		if attack_area != null:
			attack_area.monitoring = false
			attack_area.collision_layer = 0
			attack_area.collision_mask = 0
		if receive_area != null:
			receive_area.monitoring = false
			receive_area.monitorable = false
			receive_area.collision_layer = 0
			receive_area.collision_mask = 0
		raider.set("collision_layer", 0)
		raider.set("collision_mask", 0)
		raider.set_physics_process(false)
		raider.velocity = Vector2.ZERO
		raider.visible = false

func _update_raider_waves() -> void:
	if not is_instance_valid(_player):
		return
	var player := _player as Node2D
	var section_right := float(_current_section + 1) * SECTION_WIDTH
	player.global_position.x = minf(player.global_position.x, section_right - 38.0)
	if _next_raider_wave < _wave_order.size():
		var active_raider := _wave_order[_next_raider_wave]
		if is_instance_valid(active_raider) and int(active_raider.get("health")) <= 0:
			_next_raider_wave += 1
			if _next_raider_wave < _wave_order.size():
				_current_section = mini(_current_section + 1, 2)
				_set_raider_active(_wave_order[_next_raider_wave], true)
			else:
				_current_section = 2
				if is_instance_valid(_boss) and _boss.has_method("set_combat_active"):
					_boss.call("set_combat_active", true)

func _on_boss_ko() -> void:
	if result_state == ResultState.PLAYING:
		_finish_session(ResultState.VICTORY)

func _find_override(records: Array, id: String, kind: String) -> Dictionary:
	for index in range(records.size()):
		var record: Dictionary = DATA_LOADER.validate_record(records[index], kind, index)
		if String(record.get("id", "")) == id:
			return record
	return {}

func _process(_delta: float) -> void:
	if result_state != ResultState.PLAYING or _paused or _transition_pending:
		return
	if not is_instance_valid(_player):
		_player = get_node_or_null("YSortActors/Player")
	_update_raider_waves()
	if is_instance_valid(_player) and int(_player.get("health")) <= 0:
		_finish_session(ResultState.DEFEAT)
		return
	# Raider KOs unlock the route; the boss signal is the only victory path.

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
		_position_panel_away_from_actors(_pause_panel)
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
	var camera := _player.get_node_or_null("Camera2D") as Camera2D if is_instance_valid(_player) else null
	if camera != null:
		camera.zoom = Vector2.ONE
		camera.reset_smoothing()
	result_label.text = "DEFEAT" if result == ResultState.DEFEAT else "VICTORY"
	if result == ResultState.DEFEAT:
		_show_defeat_result_after_ko()
	else:
		_show_result_overlay()

func _show_defeat_result_after_ko() -> void:
	var settle_timeout := get_tree().create_timer(DEFEAT_RESULT_DELAY, true, false, true)
	var animator := _player.get_node_or_null("VisualAnimator") if is_instance_valid(_player) else null
	while is_inside_tree() and result_state == ResultState.DEFEAT and not _transition_pending:
		if animator != null and animator.has_method("is_final_down_settled") and animator.is_final_down_settled():
			break
		if settle_timeout.time_left <= 0.0:
			break
		await get_tree().process_frame
	if not is_inside_tree() or result_state != ResultState.DEFEAT or _transition_pending:
		return
	_show_result_overlay()

func _show_result_overlay() -> void:
	_position_panel_away_from_actors(_result_panel)
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
	if is_instance_valid(_boss):
		if not active:
			_boss.velocity = Vector2.ZERO
			if _boss.has_method("_cancel_attack"):
				_boss.call("_cancel_attack")
			# Let the boss finish its short collapse after KO while combat is frozen.
			if int(_boss.get("health")) > 0:
				_boss.set_physics_process(false)

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
	_pause_panel = PanelContainer.new()
	_pause_panel.name = "PausePanel"
	_pause_panel.anchor_right = 0.0
	_pause_panel.anchor_bottom = 0.0
	_pause_panel.custom_minimum_size = Vector2(430.0, 320.0)
	_pause_panel.size = _pause_panel.custom_minimum_size
	_pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	pause_overlay.add_child(_pause_panel)
	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 10)
	_pause_panel.add_child(layout)
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
	help_text.text = "조작 도움말  ·  H / Select 닫기\nWASD / 방향키 / 왼쪽 스틱: 이동\nSpace / 남쪽 버튼: 점프\nJ / 마우스 / 서쪽 버튼: 공격\n방어: 왼쪽 Shift / 동쪽 버튼\nNum1~Num9: 스킬 슬롯 (현재 예약)\nESC / Start: 일시정지\nR / 북쪽 버튼: 결과 화면에서 재시작"
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
	backdrop.color = Color(0.015, 0.025, 0.02, 0.18)
	backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	result_overlay.add_child(backdrop)

	_result_panel = PanelContainer.new()
	_result_panel.name = "ResultPanel"
	_result_panel.anchor_right = 0.0
	_result_panel.anchor_bottom = 0.0
	_result_panel.custom_minimum_size = Vector2(420.0, 228.0)
	_result_panel.size = _result_panel.custom_minimum_size
	_result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.075, 0.065, 0.88)
	panel_style.border_color = Color(0.78, 0.72, 0.42, 0.82)
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(14)
	panel_style.content_margin_left = 24.0
	panel_style.content_margin_right = 24.0
	panel_style.content_margin_top = 16.0
	panel_style.content_margin_bottom = 16.0
	_result_panel.add_theme_stylebox_override("panel", panel_style)
	result_overlay.add_child(_result_panel)

	var layout := VBoxContainer.new()
	layout.alignment = BoxContainer.ALIGNMENT_CENTER
	layout.add_theme_constant_override("separation", 7)
	_result_panel.add_child(layout)

	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.text = ""
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.add_theme_font_size_override("font_size", 40)
	result_label.add_theme_color_override("font_color", Color(0.94, 0.93, 0.84, 1.0))
	layout.add_child(result_label)

	restart_label = Label.new()
	restart_label.name = "RestartLabel"
	restart_label.text = "R 키 / 북쪽 버튼으로 재시작"
	restart_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	restart_label.add_theme_font_size_override("font_size", 16)
	restart_label.add_theme_color_override("font_color", Color(0.78, 0.72, 0.42, 1.0))
	layout.add_child(restart_label)
	_result_restart_button = _make_result_button("재도전")
	_result_restart_button.name = "RetryButton"
	_result_restart_button.pressed.connect(_restart_session)
	layout.add_child(_result_restart_button)
	_result_title_button = _make_result_button("타이틀로 돌아가기")
	_result_title_button.name = "TitleButton"
	_result_title_button.pressed.connect(_return_to_title)
	layout.add_child(_result_title_button)
	_result_restart_button.focus_neighbor_bottom = _result_restart_button.get_path_to(_result_title_button)
	_result_title_button.focus_neighbor_top = _result_title_button.get_path_to(_result_restart_button)

func _make_result_button(caption: String) -> Button:
	var button := _make_menu_button(caption)
	button.custom_minimum_size = Vector2(340.0, 44.0)
	button.add_theme_font_size_override("font_size", 18)
	return button

func _position_panel_away_from_actors(panel: PanelContainer) -> void:
	if panel == null:
		return
	var viewport_size := get_viewport_rect().size
	var panel_size := panel.custom_minimum_size
	var max_x := maxf(PANEL_VIEWPORT_MARGIN, viewport_size.x - panel_size.x - PANEL_VIEWPORT_MARGIN)
	var max_y := maxf(PANEL_VIEWPORT_MARGIN, viewport_size.y - panel_size.y - PANEL_VIEWPORT_MARGIN)
	var actor_bounds: Array[Rect2] = []
	if is_instance_valid(_player):
		var player_art := _player.get_node_or_null("VisualRoot/PlayerArt") as Sprite2D
		if player_art != null and player_art.is_visible_in_tree():
			actor_bounds.append(_sprite_screen_bounds(player_art))
	for raider in _raiders:
		if not is_instance_valid(raider):
			continue
		var raider_art := raider.get_node_or_null("VisualRoot/RaiderArt") as Sprite2D
		if raider_art != null and raider_art.is_visible_in_tree():
			actor_bounds.append(_sprite_screen_bounds(raider_art))
	var hud_bounds: Array[Rect2] = []
	var hud := get_node_or_null("CombatHUD/Overlay") as Control
	if hud != null:
		for child_name in ["HealthPanel", "ComboPanel", "RaiderPanel"]:
			var hud_panel := hud.get_node_or_null(child_name) as Control
			if hud_panel != null and hud_panel.is_visible_in_tree():
				hud_bounds.append(hud_panel.get_global_rect().abs())
	var x_values: Array[float] = []
	var y_values: Array[float] = []
	var candidate_step := 16.0
	for x in range(int(PANEL_VIEWPORT_MARGIN), int(max_x) + 1, int(candidate_step)):
		x_values.append(float(x))
	for y in range(int(PANEL_VIEWPORT_MARGIN), int(max_y) + 1, int(candidate_step)):
		y_values.append(float(y))
	x_values.append(max_x)
	y_values.append(max_y)
	var best_position := Vector2(PANEL_VIEWPORT_MARGIN, PANEL_VIEWPORT_MARGIN)
	var best_score := INF
	for y in y_values:
		for x in x_values:
			var candidate := Rect2(Vector2(x, y), panel_size)
			var score := 0.0
			for actor_bounds_rect in actor_bounds:
				var overlap := candidate.intersection(actor_bounds_rect)
				score += overlap.get_area() * 12.0
				# Keep a small visual buffer around silhouettes, even without overlap.
				var expanded := actor_bounds_rect.grow(28.0)
				if candidate.intersects(expanded):
					score += 250000.0
			for hud_rect in hud_bounds:
				if candidate.intersects(hud_rect):
					score += candidate.intersection(hud_rect).get_area() * 1000.0 + 1000000.0
			if score < best_score:
				best_score = score
				best_position = candidate.position
	panel.position = best_position

func _sprite_screen_bounds(sprite: Sprite2D) -> Rect2:
	var texture_size := Vector2(sprite.texture.get_size())
	var alpha_bounds := sprite.texture.get_image().get_used_rect()
	if alpha_bounds.size == Vector2i.ZERO:
		return Rect2()
	var local_rect := Rect2(
		Vector2(alpha_bounds.position) - texture_size * 0.5,
		Vector2(alpha_bounds.size)
	)
	var transform := sprite.get_global_transform_with_canvas()
	var corners: Array[Vector2] = [transform * local_rect.position, transform * Vector2(local_rect.end.x, local_rect.position.y), transform * local_rect.end, transform * Vector2(local_rect.position.x, local_rect.end.y)]
	var bounds := Rect2(corners[0], Vector2.ZERO)
	for corner in corners.slice(1):
		bounds = bounds.expand(corner)
	return bounds
