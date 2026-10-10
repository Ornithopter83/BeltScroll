extends SceneTree
"""Rendered-window encounter trace with the authored main scene and live enemy AI."""

const MAIN_SCENE := "res://scenes/game/main.tscn"
const OBSERVE_SECONDS := 1.5
const RATES := [60, 15]

var failures: Array[String] = []
var samples: Array[Dictionary] = []
var _current_hits := 0
var _target_hit_events := 0
var _player_hits := 0
var _contact_queries := 0
var _enemy_phases: Array[String] = []
var _boss_kinds: Array[String] = []
var _attack_stages: Array[int] = []
var _skill_ids: Array[int] = []
var _trace_target: CharacterBody2D
var _target_reaction_observed := false
var _trace_player: CharacterBody2D
var _contact_events: Array[Dictionary] = []
var _target_hp_start := 0
var _player_hp_start := 0
var _input_attempts: Array[Dictionary] = []
var _started_actions: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("dedicated_server"):
		push_error("m6u_live_encounter_window_smoke requires a rendered Window")
		quit(1)
		return
	root.size = Vector2i(1280, 720)
	for rate in RATES:
		Engine.physics_ticks_per_second = rate
		Engine.max_fps = rate
		await _run_raider_case(rate, "approach_right", 1360.0, "move_right")
		await _run_raider_case(rate, "approach_left", 1600.0, "move_left")
		if rate == 15:
			# Retain the original interrupted-input sample, then independently try
			# the same left encounter after guarding until live AI recovery.
			await _run_raider_case(rate, "approach_left_recovery", 1600.0, "move_left", true)
		await _run_boss_case(rate)
		await _run_boss_case(rate, "approach_left")
	Engine.physics_ticks_per_second = 60
	Engine.max_fps = 0
	for row in samples:
		print("M6U|SAMPLE|" + JSON.stringify(row))
	var frame := root.get_texture().get_image()
	_check(frame != null and not frame.is_empty(), "live encounter trace was rendered by a Window")
	if failures.is_empty():
		print("M6U|SUMMARY|PASS|samples=%d" % samples.size())
		quit(0)
	else:
		for failure in failures:
			push_error("M6U|FAIL|" + failure)
		print("M6U|SUMMARY|FAIL|samples=%d|failures=%d" % [samples.size(), failures.size()])
		quit(1)

func _new_game() -> Node2D:
	var packed := load(MAIN_SCENE) as PackedScene
	if packed == null:
		_check(false, "authored scenes/game/main.tscn loads")
		return null
	var game := packed.instantiate() as Node2D
	root.add_child(game)
	current_scene = game
	await process_frame
	return game

func _run_raider_case(rate: int, label: String, player_x: float, move_action: String, guard_recovery: bool = false) -> void:
	var game := await _new_game()
	if game == null:
		return
	var player := game.get_node("YSortActors/Player") as CharacterBody2D
	var raider := game.get_node("YSortActors/ForestRaider1") as CharacterBody2D
	player.global_position = Vector2(player_x, 780.0)
	await physics_frame
	var ai_live := raider.is_physics_processing() and bool(raider.get("combat_active"))
	_check(ai_live, "%d FPS Raider %s starts with live AI" % [rate, label])
	_connect_receivers(player, raider)
	RenderingServer.frame_post_draw.connect(_observe_rendered_encounter)
	var start_player := player.global_position
	var start_target := raider.global_position
	await _hold_depth_approach(move_action, "move_down" if label == "approach_right" else "move_up", 0.05)
	await _hold("block", 1.40)
	if guard_recovery:
		await _guard_until_recovery(player, raider)
	await _tap("attack")
	await _wait_combo_or_idle(player, 1)
	await _tap("attack")
	await _wait_combo_or_idle(player, 2)
	await _tap("attack")
	await _wait_player_idle(player)
	await _hold("skill_1", 0.05)
	await _wait_seconds(0.65)
	await _hold("skill_2", 0.05)
	await _observe_for(player, OBSERVE_SECONDS)
	var row := _row("raider", label, rate, player, raider, start_player, start_target, ai_live)
	row["raider_ai_phases"] = _enemy_phases.duplicate()
	row["raider_hitstun_s"] = float(raider.get("hitstun_remaining"))
	row["raider_reaction_observed"] = _target_reaction_observed
	samples.append(row)
	_check(float(row["player_travel_px"]) > 10.0, "%d FPS Raider %s records actual player movement" % [rate, label])
	_check(float(row["depth_travel_px"]) > 5.0, "%d FPS Raider %s records depth-lane movement" % [rate, label])
	_check(int(row["target_hit_events"]) > 0, "%d FPS Raider %s receives at least one real hit" % [rate, label])
	_check(int(row["target_hp_end"]) < int(row["target_hp_start"]), "%d FPS Raider %s actually loses HP" % [rate, label])
	_check(_contact_events.size() == _target_hit_events, "every Raider receive signal has synchronous Shape evidence")
	_check(_target_reaction_observed, "%d FPS Raider %s shows hitstun or KO flash" % [rate, label])
	if guard_recovery:
		_check(not _attack_stages.is_empty(), "15 FPS left recovery retry records real basic-attack contact, not merely a skill KO")
	_check(int(row["player_hit_events"]) > 0, "%d FPS Raider %s records AI contact on Player" % [rate, label])
	_dispose_game(game)

func _run_boss_case(rate: int, label: String = "approach_right") -> void:
	var game := await _new_game()
	if game == null:
		return
	var player := game.get_node("YSortActors/Player") as CharacterBody2D
	var boss := game.get_node("YSortActors/RuinsWardenBoss") as CharacterBody2D
	# Use the same activation entry point as game_session wave progression. The
	# boss's own physics remains enabled throughout this encounter trace.
	game.set("_current_section", 2)
	boss.call("set_combat_active", true)
	# Boss spawns near the right arena wall. Seeding Player at boss.x+260 is
	# outside production bounds and gets clamped. Start inside the arena, lure
	# the live Boss left, and circle it using real movement for the left strike.
	player.global_position = Vector2(boss.global_position.x - 260.0, 780.0)
	await physics_frame
	var ai_live := boss.is_physics_processing() and bool(boss.get("combat_active"))
	_check(ai_live, "%d FPS boss activates with live AI" % rate)
	_connect_receivers(player, boss)
	RenderingServer.frame_post_draw.connect(_observe_rendered_encounter)
	var start_player := player.global_position
	var start_target := boss.global_position
	if label == "approach_left":
		await _hold("move_left", 0.90)
		await _hold("move_down", 0.28)
		await _circle_live_boss(player, boss)
		await _align_depth_lane(player, boss)
		# Actual horizontal input restores left facing after depth movement.
		await _hold("move_left", 0.025)
	else:
		await _hold("move_right", 0.38)
		await _hold("block", 1.50)
		await _hold("block", 0.45)
	await _wait_player_stun_end(player)
	await _tap("attack")
	await _wait_combo_or_idle(player, 1)
	await _tap("attack")
	await _wait_combo_or_idle(player, 2)
	await _tap("attack")
	await _wait_player_idle(player)
	await _hold("skill_1", 0.05)
	await _wait_seconds(0.75)
	await _hold("skill_2", 0.05)
	await _observe_for(player, OBSERVE_SECONDS)
	var row := _row("boss", label, rate, player, boss, start_player, start_target, ai_live)
	row["boss_attack_kinds_observed"] = _boss_kinds.duplicate()
	row["boss_ai_phases"] = _enemy_phases.duplicate()
	row["boss_attack_kind"] = str(boss.get("attack_kind"))
	row["boss_attack_phase"] = str(boss.get("attack_phase"))
	row["boss_hitstun_s"] = float(boss.get("hitstun_remaining"))
	row["boss_reaction_observed"] = _target_reaction_observed
	row["player_hit_stages"] = _attack_stages.duplicate()
	row["player_skill_hits"] = _skill_ids.duplicate()
	samples.append(row)
	_check(float(row["player_travel_px"]) > 40.0, "%d FPS Boss trace records player movement" % rate)
	_check(int(row["target_hit_events"]) > 0, "%d FPS live Boss receives real contact damage" % rate)
	_check(int(row["target_hp_end"]) < int(row["target_hp_start"]), "%d FPS live Boss actually loses HP" % rate)
	_check(_attack_stages.has(1) and _attack_stages.has(2) and _attack_stages.has(3) and _skill_ids.has(1) and _skill_ids.has(2), "%d FPS live Boss records J1/J2/J3 and both skill hit signals" % rate)
	_check(_contact_events.size() == _target_hit_events, "every Boss receive signal has synchronous Shape evidence")
	_check(_target_reaction_observed, "%d FPS Boss shows hitstun or KO flash" % rate)
	_check(_boss_kinds.has("slash") and _boss_kinds.has("slam"), "%d FPS Boss trace observes both slash and slam AI phases" % rate)
	_dispose_game(game)

func _connect_receivers(player: CharacterBody2D, target: CharacterBody2D) -> void:
	_current_hits = 0
	_target_hit_events = 0
	_player_hits = 0
	_contact_queries = 0
	_enemy_phases.clear()
	_boss_kinds.clear()
	_attack_stages.clear()
	_skill_ids.clear()
	_trace_target = target
	_trace_player = player
	_target_hp_start = int(target.get("health"))
	_player_hp_start = int(player.get("health"))
	_contact_events.clear()
	_input_attempts.clear()
	_started_actions.clear()
	player.attack_started.connect(func(stage: int) -> void: _started_actions.append("J%d" % stage))
	player.skill_started.connect(func(skill_id: int) -> void: _started_actions.append("Num%d" % (skill_id + 3)))
	_target_reaction_observed = false
	player.attack_hit.connect(func(stage: int) -> void:
		_current_hits += 1
		_attack_stages.append(stage)
		_capture_hit_result()
	)
	player.skill_hit.connect(func(skill_id: int) -> void:
		_current_hits += 1
		_skill_ids.append(skill_id)
		_capture_hit_result()
	)
	player.player_hit.connect(func(_stage: int) -> void: _player_hits += 1)
	for signal_name in ["raider_hit", "boss_hit"]:
		if target.has_signal(signal_name):
			target.connect(signal_name, _capture_receive_contact)

func _capture_receive_contact(stage: int) -> void:
	# Raider/Boss emit before HP reduction and before KO disables their receiver.
	# Inspect the shape already used by production; do not sync poses, move a
	# hitbox, manufacture contact, or invoke the damage path from this observer.
	_target_hit_events += 1
	var skill_id := int(_trace_player.get("skill_id"))
	var area_name := "Skill%dHitbox" % skill_id if str(_trace_player.get("skill_phase")) == "active" else "Hitbox%d" % int(_trace_player.get("attack_stage"))
	var hitbox := _trace_player.get_node("Hitboxes/" + area_name) as Area2D
	var attack_shape := hitbox.get_node("CollisionShape2D") as CollisionShape2D
	var receive_shape := _trace_target.get_node("ReceiveArea/CollisionShape2D") as CollisionShape2D
	var geometric_contact := attack_shape.shape.collide(attack_shape.global_transform, receive_shape.shape, receive_shape.global_transform)
	var queried: Array = _trace_player.call("_query_fist_targets", hitbox)
	var query_contact := queried.has(_trace_target)
	var row := {
		"physics_frame": Engine.get_physics_frames(), "stage": stage, "hitbox": area_name,
		"phase": str(_trace_player.get("skill_phase")) if area_name.begins_with("Skill") else str(_trace_player.get("attack_phase")),
		"shape_overlap": geometric_contact, "intersect_shape_target": query_contact,
		"hp_before": int(_trace_target.get("health")),
		"attack_origin": attack_shape.global_position, "receive_origin": receive_shape.global_position,
		"root_gap": _trace_target.global_position - _trace_player.global_position,
	}
	_contact_events.append(row)
	_check(geometric_contact and query_contact and row["phase"] == "active", "receive signal must have active geometric and intersect_shape contact")

func _capture_hit_result() -> void:
	if _contact_events.is_empty():
		return
	var row: Dictionary = _contact_events[-1]
	row["hp_after"] = int(_trace_target.get("health"))
	row["ko"] = int(_trace_target.get("health")) == 0
	row["hitstun_s"] = float(_trace_target.get("hitstun_remaining"))
	row["reaction_flash_s"] = float(_trace_target.get("hit_flash_remaining")) if _trace_target.has_signal("raider_hit") else float(_trace_target.get("_flash_remaining"))
	_check(int(row["hp_after"]) < int(row["hp_before"]), "receive signal results in real HP decrease")
	_target_reaction_observed = _target_reaction_observed or float(row["hitstun_s"]) > 0.0 or (bool(row["ko"]) and float(row["reaction_flash_s"]) > 0.0)

func _observe_rendered_encounter() -> void:
	if is_instance_valid(_trace_player):
		if int(_trace_player.get("health")) > 0 and int(_trace_target.get("health")) > 0:
			_check(_trace_player.is_physics_processing() and _trace_target.is_physics_processing(), "living Player and enemy physics remain live throughout the trace")
		_probe_contact(_trace_player)
		_capture_enemy_state()

func _hold(action: String, seconds: float) -> void:
	_record_input_attempt(action)
	Input.action_press(action)
	await _wait_seconds(seconds)
	Input.action_release(action)
	await physics_frame

func _hold_depth_approach(horizontal_action: String, depth_action: String, seconds: float) -> void:
	Input.action_press(horizontal_action)
	Input.action_press(depth_action)
	await _wait_seconds(seconds)
	Input.action_release(horizontal_action)
	Input.action_release(depth_action)
	await physics_frame

func _tap(action: String) -> void:
	_record_input_attempt(action)
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame

func _record_input_attempt(action: String) -> void:
	if not is_instance_valid(_trace_player) or action not in ["attack", "skill_1", "skill_2"]:
		return
	_input_attempts.append({
		"action": action, "physics_frame": Engine.get_physics_frames(),
		"hitstun_s": float(_trace_player.get("hitstun_remaining")), "is_blocking": bool(_trace_player.get("is_blocking")),
		"attack_phase": str(_trace_player.get("attack_phase")), "skill_phase": str(_trace_player.get("skill_phase")),
		"enemy_phase": str(_trace_target.get("attack_phase")), "target_hp": int(_trace_target.get("health")),
		"root_gap": _trace_target.global_position - _trace_player.global_position,
	})
func _wait_combo_or_idle(player: CharacterBody2D, stage: int) -> void:
	for _frame in range(90):
		_probe_contact(player)
		_capture_enemy_state()
		if str(player.get("attack_phase")) == "combo_hold" and int(player.get("attack_stage")) == stage:
			return
		if str(player.get("attack_phase")) == "idle":
			return
		await physics_frame

func _wait_player_idle(player: CharacterBody2D) -> void:
	for _frame in range(180):
		_probe_contact(player)
		_capture_enemy_state()
		if str(player.get("attack_phase")) == "idle" and str(player.get("skill_phase")) == "idle":
			return
		await physics_frame

func _wait_player_stun_end(player: CharacterBody2D) -> void:
	for _frame in range(90):
		_capture_enemy_state()
		if float(player.get("hitstun_remaining")) <= 0.0:
			return
		await physics_frame

func _guard_until_recovery(player: CharacterBody2D, target: CharacterBody2D) -> void:
	Input.action_press("block")
	var recovered := false
	for _frame in range(90):
		await physics_frame
		if str(target.get("attack_phase")) == "recovery" and float(player.get("hitstun_remaining")) <= 0.0:
			recovered = true
			break
	Input.action_release("block")
	await physics_frame
	_check(recovered, "live enemy reaches recovery while Player guards; no AI or attack state was injected")

func _align_depth_lane(player: CharacterBody2D, target: CharacterBody2D) -> void:
	for _frame in range(60):
		var depth := target.global_position.y - player.global_position.y
		if absf(depth) <= 8.0:
			return
		var action := "move_down" if depth > 0.0 else "move_up"
		Input.action_press(action)
		await physics_frame
		Input.action_release(action)
		await physics_frame
	_check(false, "real depth movement reaches the Boss lane")

func _circle_live_boss(player: CharacterBody2D, boss: CharacterBody2D) -> void:
	Input.action_press("move_right")
	var circled := false
	for _frame in range(180):
		await physics_frame
		if player.global_position.x - boss.global_position.x >= 150.0:
			circled = true
			break
		if int(player.get("health")) <= 0:
			break
	Input.action_release("move_right")
	await physics_frame
	_check(circled, "real input circled the pursuing Boss inside the production arena")

func _observe_for(player: CharacterBody2D, seconds: float) -> void:
	var frames := maxi(1, int(round(seconds * float(Engine.physics_ticks_per_second))))
	for _frame in range(frames):
		_probe_contact(player)
		_capture_enemy_state()
		await physics_frame

func _capture_enemy_state() -> void:
	if not is_instance_valid(_trace_target):
		return
	var phase := str(_trace_target.get("attack_phase"))
	if not phase.is_empty() and (_enemy_phases.is_empty() or _enemy_phases[-1] != phase):
		_enemy_phases.append(phase)
	if float(_trace_target.get("hitstun_remaining")) > 0.0:
		_target_reaction_observed = true
	if _trace_target.has_method("set_combat_active"):
		var kind := str(_trace_target.get("attack_kind"))
		if not kind.is_empty() and (_boss_kinds.is_empty() or _boss_kinds[-1] != kind):
			_boss_kinds.append(kind)

func _probe_contact(player: CharacterBody2D) -> void:
	if str(player.get("attack_phase")) == "active":
		var hitbox := player.get_node("Hitboxes/Hitbox%d" % int(player.get("attack_stage"))) as Area2D
		if hitbox.monitoring:
			var hits: Array = player.call("_query_fist_targets", hitbox)
			if not hits.is_empty():
				_contact_queries += 1
	elif str(player.get("skill_phase")) == "active":
		var skill_id := int(player.get("skill_id"))
		var hitbox := player.get_node("Hitboxes/Skill%dHitbox" % skill_id) as Area2D
		if hitbox.monitoring:
			var hits: Array = player.call("_query_fist_targets", hitbox)
			if not hits.is_empty():
				_contact_queries += 1

func _wait_seconds(seconds: float) -> void:
	var frames := maxi(1, int(round(seconds * float(Engine.physics_ticks_per_second))))
	for _frame in range(frames):
		_capture_enemy_state()
		await physics_frame

func _row(kind: String, label: String, rate: int, player: CharacterBody2D, target: CharacterBody2D, start_player: Vector2, start_target: Vector2, ai_live: bool) -> Dictionary:
	return {
		"encounter": kind, "case": label, "physics_fps": rate,
		"ai_live": ai_live, "player_physics_live": player.is_physics_processing(),
		"player_start": start_player, "player_end": player.global_position,
		"target_start": start_target, "target_end": target.global_position,
		"player_travel_px": start_player.distance_to(player.global_position),
		"depth_travel_px": absf(start_player.y - player.global_position.y),
		"target_travel_px": start_target.distance_to(target.global_position),
		"target_hp_start": _target_hp_start, "target_hp_end": int(target.get("health")),
		"player_hit_attack_signals": _current_hits, "target_hit_events": _target_hit_events, "player_hp_start": _player_hp_start,
		"player_hit_stages": _attack_stages.duplicate(), "player_skill_hits": _skill_ids.duplicate(),
		"player_hp_end": int(player.get("health")), "player_hp_lost": int(player.get("max_health")) - int(player.get("health")),
		"player_hit_events": _player_hits, "physical_contact_samples": _contact_queries,
		"synchronous_contact_events": _contact_events.duplicate(true),
		"input_attempts": _input_attempts.duplicate(true), "started_actions": _started_actions.duplicate(),
		"player_attack_phase": str(player.get("attack_phase")), "player_skill_phase": str(player.get("skill_phase")),
	}

func _dispose_game(game: Node) -> void:
	RenderingServer.frame_post_draw.disconnect(_observe_rendered_encounter)
	for action in ["move_right", "move_left", "move_up", "move_down", "block", "attack", "skill_1", "skill_2"]:
		Input.action_release(action)
	root.remove_child(game)
	game.free()
	current_scene = null
	await process_frame

func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
