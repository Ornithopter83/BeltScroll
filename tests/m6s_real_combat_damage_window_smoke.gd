extends SceneTree
"""Live combat damage gate using normal encounter spacing and Window input."""

const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const RAIDER_SCENE := preload("res://scenes/enemies/forest_raider.tscn")
const BOSS_SCENE := preload("res://scenes/enemies/ruins_warden_boss.tscn")
const ENCOUNTER_GAP := 120.0
const BASIC_DAMAGE := [1, 2, 3]
const SKILL_DAMAGE := [3, 2]
const BASIC_ACTIVE := [0.105, 0.12, 0.14]
const SKILL_ACTIVE := [0.12, 0.18]

var failures: Array[String] = []
var window_samples: Array[String] = []
var _hits_in_current_case := 0
var _overlap_query_samples := 0
var _first_active_remaining: Dictionary = {}

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("m6s_real_combat_damage_window_smoke requires a real Window")
		quit(1)
		return
	root.size = Vector2i(960, 540)
	for target_kind in ["Raider", "active Boss"]:
		await _check_basic_combo(target_kind)
		await _check_skill(target_kind, 1)
		await _check_skill(target_kind, 2)
		await _check_miss_cases(target_kind)
		if not OS.get_cmdline_user_args().has("--normal-only"):
			await _check_all_attack_misses_and_mirror(target_kind)
	await process_frame
	await RenderingServer.frame_post_draw
	var frame := root.get_texture().get_image()
	_check(frame != null and not frame.is_empty() and frame.get_size() == Vector2i(960, 540), "damage samples came from the live Window viewport")
	for sample in window_samples:
		print("m6s-window-sample: " + sample)
	if failures.is_empty():
		print("m6s_real_combat_damage_window_smoke: PASS")
		quit(0)
	else:
		for failure in failures:
			push_error("m6s_real_combat_damage_window_smoke: " + failure)
		quit(1)

func _check_basic_combo(target_kind: String) -> void:
	var pair := await _make_pair(target_kind)
	var player: CharacterBody2D = pair[0]
	var target: CharacterBody2D = pair[1]
	_hits_in_current_case = 0
	_overlap_query_samples = 0
	_first_active_remaining.clear()
	player.attack_hit.connect(_on_attack_hit)
	var initial_health := int(target.get("health"))
	await _tap_action("attack")
	await _wait_for_state(player, "combo_hold", 1)
	_check(initial_health - int(target.get("health")) == BASIC_DAMAGE[0], "%s J1 applies its own authored damage" % target_kind)
	await _tap_action("attack")
	await _wait_for_state(player, "combo_hold", 2)
	_check(initial_health - int(target.get("health")) == BASIC_DAMAGE[0] + BASIC_DAMAGE[1], "%s J2 applies its own authored damage" % target_kind)
	await _tap_action("attack")
	await _wait_for_idle(player)
	var expected: int = BASIC_DAMAGE[0] + BASIC_DAMAGE[1] + BASIC_DAMAGE[2]
	_check(initial_health - int(target.get("health")) == expected, "%s J 1-3 deal %d real HP damage at %.0fpx spacing" % [target_kind, expected, ENCOUNTER_GAP])
	_check(_hits_in_current_case == 3, "%s J 1-3 each produce one physical-contact hit" % target_kind)
	_check(_overlap_query_samples > 0, "%s basic strikes reached the actual ReceiveArea in intersect_shape" % target_kind)
	for stage in range(1, 4):
		var observed := float(_first_active_remaining.get("basic_%d" % stage, 0.0))
		_check(observed > 0.0 and absf(observed - BASIC_ACTIVE[stage - 1]) <= 1.0 / 30.0, "%s J%d active time retains its authored duration" % [target_kind, stage])
	window_samples.append(_sample_row("%s_J123" % target_kind, player, target, initial_health))
	_dispose_pair(player, target)

func _check_skill(target_kind: String, skill_id: int) -> void:
	var pair := await _make_pair(target_kind)
	var player: CharacterBody2D = pair[0]
	var target: CharacterBody2D = pair[1]
	_hits_in_current_case = 0
	_overlap_query_samples = 0
	_first_active_remaining.clear()
	player.skill_hit.connect(_on_skill_hit)
	var initial_health := int(target.get("health"))
	await _tap_action("skill_%d" % skill_id)
	await _wait_for_idle(player)
	var expected: int = SKILL_DAMAGE[skill_id - 1]
	_check(initial_health - int(target.get("health")) == expected, "%s Num%d deals %d real HP damage at %.0fpx spacing" % [target_kind, skill_id + 3, expected, ENCOUNTER_GAP])
	_check(_hits_in_current_case == 1, "%s Num%d produces exactly one physical-contact hit" % [target_kind, skill_id + 3])
	_check(_overlap_query_samples > 0, "%s Num%d reached the actual ReceiveArea in intersect_shape" % [target_kind, skill_id + 3])
	var observed := float(_first_active_remaining.get("skill_%d" % skill_id, 0.0))
	_check(observed > 0.0 and absf(observed - SKILL_ACTIVE[skill_id - 1]) <= 1.0 / 30.0, "%s Num%d active time retains its authored duration" % [target_kind, skill_id + 3])
	window_samples.append(_sample_row("%s_Num%d" % [target_kind, skill_id + 3], player, target, initial_health))
	_dispose_pair(player, target)

func _make_pair(target_kind: String) -> Array:
	var player := PLAYER_SCENE.instantiate() as CharacterBody2D
	player.set("arena_bounds", Rect2(0, 0, 2400, 2400))
	player.global_position = Vector2(400, 500)
	player.set("facing_direction", Vector2.RIGHT)
	player.get_node("VisualRoot").scale.x = 1.0
	root.add_child(player)
	var target: CharacterBody2D
	if target_kind == "Raider":
		target = RAIDER_SCENE.instantiate() as CharacterBody2D
		target.set("max_health", 20)
		root.add_child(target)
		await process_frame
		target.set_physics_process(false)
	else:
		target = BOSS_SCENE.instantiate() as CharacterBody2D
		root.add_child(target)
		await process_frame
		target.call("set_combat_active", true)
		target.set_physics_process(false)
	target.global_position = player.global_position + Vector2(ENCOUNTER_GAP, 0)
	await physics_frame
	_check(bool(target.get("combat_active")), "%s receiver is combat-active during input simulation" % target_kind)
	return [player, target]

func _tap_action(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame

func _wait_for_state(player: CharacterBody2D, phase: String, stage: int) -> void:
	for _frame in range(120):
		_probe_active_contact(player)
		if str(player.get("attack_phase")) == phase and int(player.get("attack_stage")) == stage:
			return
		await physics_frame
	_check(false, "input simulation reached attack stage %d %s" % [stage, phase])

func _wait_for_idle(player: CharacterBody2D) -> void:
	for _frame in range(180):
		_probe_active_contact(player)
		if str(player.get("attack_phase")) == "idle" and str(player.get("skill_phase")) == "idle":
			return
		await physics_frame
	_check(false, "input simulation returned to idle")

func _probe_active_contact(player: CharacterBody2D) -> void:
	var basic_phase := str(player.get("attack_phase"))
	var skill_phase := str(player.get("skill_phase"))
	var hitbox: Area2D
	if basic_phase == "active":
		var stage := int(player.get("attack_stage"))
		var key := "basic_%d" % stage
		if not _first_active_remaining.has(key):
			_first_active_remaining[key] = float(player.get("attack_phase_remaining"))
		hitbox = player.get_node("Hitboxes/Hitbox%d" % stage) as Area2D
	elif skill_phase == "active":
		var skill_id := int(player.get("skill_id"))
		var key := "skill_%d" % skill_id
		if not _first_active_remaining.has(key):
			_first_active_remaining[key] = float(player.get("skill_phase_remaining"))
		hitbox = player.get_node("Hitboxes/Skill%dHitbox" % skill_id) as Area2D
	if hitbox == null:
		return
	player.call("_update_fist_hitbox", hitbox)
	var targets: Array = player.call("_query_fist_targets", hitbox)
	if not targets.is_empty():
		_overlap_query_samples += 1

func _on_attack_hit(_stage: int) -> void:
	_hits_in_current_case += 1

func _on_skill_hit(_skill_id: int) -> void:
	_hits_in_current_case += 1

func _sample_row(label: String, player: CharacterBody2D, target: CharacterBody2D, initial_health: int) -> String:
	return JSON.stringify({
		"sample": label,
		"input": "Input.action_press",
		"target": target.name,
		"distance_px": ENCOUNTER_GAP,
		"initial_hp": initial_health,
		"final_hp": int(target.get("health")),
		"damage": initial_health - int(target.get("health")),
		"active_intersect_shape_samples": _overlap_query_samples,
		"root_depth_delta_px": absf(target.global_position.y - player.global_position.y),
		"receiver_path": "ReceiveArea/CollisionShape2D",
	})

func _check_miss_cases(target_kind: String) -> void:
	var rear_pair := await _make_pair(target_kind)
	var rear_player: CharacterBody2D = rear_pair[0]
	var rear_target: CharacterBody2D = rear_pair[1]
	rear_target.global_position = rear_player.global_position + Vector2(-120, 0)
	var rear_hp := int(rear_target.get("health"))
	_hits_in_current_case = 0
	await _tap_action("attack")
	await _wait_for_idle(rear_player)
	_check(int(rear_target.get("health")) == rear_hp and _hits_in_current_case == 0, "%s rear-side J swing misses" % target_kind)
	_dispose_pair(rear_player, rear_target)

	var deep_pair := await _make_pair(target_kind)
	var deep_player: CharacterBody2D = deep_pair[0]
	var deep_target: CharacterBody2D = deep_pair[1]
	deep_target.global_position = deep_player.global_position + Vector2(ENCOUNTER_GAP, 60)
	var receive_area := deep_target.get_node("ReceiveArea") as Area2D
	receive_area.position.y -= 60.0
	await physics_frame
	var deep_hp := int(deep_target.get("health"))
	_hits_in_current_case = 0
	_overlap_query_samples = 0
	deep_player.skill_hit.connect(_on_skill_hit)
	await _tap_action("skill_2")
	await _wait_for_idle(deep_player)
	_check(_overlap_query_samples > 0, "%s deep Num5 decoy physically overlaps the fist query" % target_kind)
	_check(int(deep_target.get("health")) == deep_hp and _hits_in_current_case == 0, "%s Num5 rejects a receiver 60px beyond belt depth" % target_kind)
	_dispose_pair(deep_player, deep_target)

	var air_pair := await _make_pair(target_kind)
	var air_player: CharacterBody2D = air_pair[0]
	var air_target: CharacterBody2D = air_pair[1]
	air_target.global_position = air_player.global_position + Vector2(400, 0)
	var air_hp := int(air_target.get("health"))
	_hits_in_current_case = 0
	await _tap_action("attack")
	await _wait_for_idle(air_player)
	_check(int(air_target.get("health")) == air_hp and _hits_in_current_case == 0, "%s J swing misses when the opponent is outside fist reach" % target_kind)
	_dispose_pair(air_player, air_target)

func _dispose_pair(player: Node, target: Node) -> void:
	Input.action_release("attack")
	Input.action_release("skill_1")
	Input.action_release("skill_2")
	root.remove_child(player)
	root.remove_child(target)
	player.free()
	target.free()

func _drive_attack(player: CharacterBody2D, action: String) -> void:
	await _tap_action(action)
	if action == "attack":
		await _wait_for_state(player, "combo_hold", 1)
		await _tap_action(action)
		await _wait_for_state(player, "combo_hold", 2)
		await _tap_action(action)
	await _wait_for_idle(player)

func _check_all_attack_misses_and_mirror(target_kind: String) -> void:
	for action in ["attack", "skill_1", "skill_2"]:
		# A full combo/Num4 can travel into contact from 400px. 700px stays
		# beyond the entire physical lunge + visible hand trajectory + receiver.
		for offset in [Vector2(-120,0), Vector2(120,60), Vector2(700,0)]:
			var pair := await _make_pair(target_kind)
			var player: CharacterBody2D = pair[0]
			var target: CharacterBody2D = pair[1]
			target.global_position = player.global_position + offset
			await physics_frame
			var initial_hp := int(target.get("health"))
			await _drive_attack(player, action)
			_check(int(target.get("health")) == initial_hp, "%s %s misses at rear/depth/air offset %s" % [target_kind,action,offset])
			_dispose_pair(player,target)
		var left_pair := await _make_pair(target_kind)
		var left_player: CharacterBody2D = left_pair[0]
		var left_target: CharacterBody2D = left_pair[1]
		left_player.set("facing_direction", Vector2.LEFT)
		left_player.get_node("VisualRoot").scale.x = -1.0
		left_target.global_position = left_player.global_position + Vector2(-ENCOUNTER_GAP,0)
		await physics_frame
		var left_hp := int(left_target.get("health"))
		await _drive_attack(left_player,action)
		_check(left_hp - int(left_target.get("health")) == (6 if action == "attack" else (3 if action == "skill_1" else 2)), "%s mirrored %s deals authored damage at 120px" % [target_kind,action])
		_dispose_pair(left_player,left_target)

func _check(condition: bool, description: String) -> void:
	if not condition:
		failures.append(description)
		push_error("FAIL: " + description)
