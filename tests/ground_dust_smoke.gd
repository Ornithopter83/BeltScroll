extends SceneTree

const MAIN_SCENE := "res://scenes/game/main.tscn"
const PLAYER_PATH := "YSortActors/Player"
const GROUND_DUST_SCRIPT := preload("res://scripts/vfx/ground_dust.gd")
const HIT := {"damage": 99, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.0, "attack_stage": 1}

var failures: Array[String] = []
var main: Node
var player: CharacterBody2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(MAIN_SCENE) as PackedScene
	_check(packed != null, "main scene with Player loads")
	if packed == null:
		_finish()
		return
	main = packed.instantiate()
	main.get_node("CombatAudio").free()
	root.add_child(main)
	for raider_name in ["ForestRaider1", "ForestRaider2", "ForestRaider3"]:
		main.get_node("YSortActors").get_node(raider_name).free()
	await physics_frame
	player = main.get_node(PLAYER_PATH) as CharacterBody2D
	_check(player != null and player.has_method("_update_ground_dust"), "Player owns the ground dust controller")
	if player == null:
		_finish()
		return
	_check(is_equal_approx(float(player.get("GROUND_DUST_STEP_DISTANCE")), 72.0), "footstep distance threshold is bounded to a deliberate stride")
	_check(is_equal_approx(float(player.get("MAX_GROUND_DUST_INSTANCES")), 4.0), "simultaneous effect limit is four")

	await _reset_player()
	for _frame in range(8):
		player.call("_update_ground_dust", player.global_position, false)
		await physics_frame
	_check(_effects().is_empty(), "standing still does not emit dust")
	for _step in range(14):
		var before := player.global_position
		player.global_position += Vector2(5.0, 0.0)
		player.call("_update_ground_dust", before, false)
	_check(_effects().is_empty(), "sub-threshold ground travel does not emit dust")
	var before_step := player.global_position
	player.global_position += Vector2(5.0, 0.0)
	player.call("_update_ground_dust", before_step, false)
	_check(not _effects().is_empty(), "ground movement distance emits a footstep effect")
	_check(_count_landing_effects() == 0, "footstep effect is not marked as a landing burst")
	if not _effects().is_empty():
		var effect := _effects()[0]
		_check(is_equal_approx(float(effect.get("LIFETIME")), 0.48), "ground dust lifetime is short")
	await _frames(35)
	_check(_effects().is_empty(), "footstep effect expires after its lifetime")

	await _reset_player()
	player.set("is_jumping", true)
	for _step in range(20):
		var before := player.global_position
		player.global_position += Vector2(5.0, 0.0)
		player.call("_update_ground_dust", before, false)
	_check(_effects().is_empty(), "airborne floor travel does not emit footstep dust")
	player.set("jump_height_offset", 0.1)
	player.set("jump_vertical_velocity", 100.0)
	var landed: bool = player.call("_update_jump", 1.0 / 60.0, 1.0)
	player.call("_update_ground_dust", player.global_position, landed)
	_check(_count_landing_effects() == 1, "jump landing emits one landing burst")
	_check(landed and player.get("is_jumping") == false, "landing effect follows the actual jump landing state")

	player.call("_clear_ground_dust")
	for index in range(10):
		player.call("_spawn_ground_dust", index % 2 == 0)
	_check(_effects().size() <= int(player.get("MAX_GROUND_DUST_INSTANCES")), "effect instance cap is enforced")
	player.call("_clear_ground_dust")
	await process_frame
	_check(_effects().is_empty(), "explicit cleanup removes all tracked effects")

	player.call("_spawn_ground_dust", false)
	var paused_effect := _effects()[0]
	var paused_elapsed := float(paused_effect.get("elapsed"))
	paused = true
	await _frames(12)
	_check(is_equal_approx(float(paused_effect.get("elapsed")), paused_elapsed), "effects do not age while the tree is paused")
	paused = false
	await _frames(35)
	_check(_effects().is_empty(), "paused effect resumes its lifetime after unpausing")

	player.call("_spawn_ground_dust", false)
	_check(_effects().size() == 1, "effect exists before Player KO cleanup")
	player.receive_hit(HIT)
	_check(_effects().is_empty(), "Player KO clears active ground effects immediately")
	await process_frame
	main.queue_free()
	await process_frame
	_check(not is_instance_valid(player), "scene teardown frees Player and its remaining child effects")
	var restarted := packed.instantiate()
	restarted.get_node("CombatAudio").free()
	root.add_child(restarted)
	await process_frame
	var restarted_player := restarted.get_node(PLAYER_PATH)
	_check(restarted_player.get("_ground_dust_instances").is_empty(), "fresh restarted scene has no carried-over effects")
	restarted.queue_free()
	await process_frame
	_finish()

func _reset_player() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("jump")
	player.call("_clear_ground_dust")
	player.global_position = Vector2(960.0, 540.0)
	player.velocity = Vector2.ZERO
	player.set("is_jumping", false)
	player.set("jump_height_offset", 0.0)
	player.set("jump_vertical_velocity", 0.0)
	player.set("jump_buffer_remaining", 0.0)
	player.set("coyote_remaining", 0.0)
	player.set("_ground_distance_since_dust", 0.0)
	await physics_frame

func _effects() -> Array[Node2D]:
	var effects: Array[Node2D] = []
	for child in player.get_children():
		if child is Node2D and child.get_script() == GROUND_DUST_SCRIPT:
			effects.append(child)
	return effects

func _count_landing_effects() -> int:
	var count := 0
	for effect in _effects():
		if bool(effect.get("is_landing")):
			count += 1
	return count

func _frames(count: int) -> void:
	for _frame in range(count):
		await physics_frame

func _finish() -> void:
	Input.action_release("move_left")
	Input.action_release("move_right")
	Input.action_release("move_up")
	Input.action_release("move_down")
	Input.action_release("jump")
	paused = false
	if failures.is_empty():
		print("ground_dust_smoke: all checks passed")
		quit(0)
	else:
		for failure in failures:
			push_error("ground_dust_smoke: " + failure)
		push_error("ground_dust_smoke: %d check(s) failed" % failures.size())
		quit(1)

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)
