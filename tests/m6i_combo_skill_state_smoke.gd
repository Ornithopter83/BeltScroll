extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const CONTROLLER_SOURCE := "res://scripts/player/player_controller.gd"

var failures: Array[String] = []
var player: CharacterBody2D

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "Player scene loads")
	if packed == null:
		_finish()
		return
	player = packed.instantiate() as CharacterBody2D
	root.add_child(player)
	await physics_frame

	# Verify hitboxes follow the phase boundaries exactly when phase time is
	# stepped without frame-sized approximation.
	player.call("_begin_attack", 1)
	player.call("_update_attack", 0.075)
	_check(player.get("attack_phase") == "active", "basic attack enters active at startup boundary")
	_check(player.get_node("Hitboxes/Hitbox1").monitoring, "basic hitbox enables with active phase")
	player.call("_update_attack", 0.105)
	_check(player.get("attack_phase") == "recovery", "basic attack enters recovery at active boundary")
	_check(not player.get_node("Hitboxes/Hitbox1").monitoring, "basic hitbox disables with recovery phase")
	player.call("_update_attack", 0.20)
	_check(player.get("attack_phase") == "combo_hold" and player.get("attack_stage") == 1, "recovery completion holds combo stage for the M6N link window")
	_check(player.get("combo_link_remaining") > 0.0 and not player.get_node("Hitboxes/Hitbox1").monitoring, "combo hold keeps its link timer without enabling damage")

	# An early tap remains queued until recovery opens the next stage.
	player.call("_begin_attack", 1)
	player.set("attack_buffer_remaining", 0.60)
	player.call("_update_attack", 0.075 + 0.105 + 0.20)
	_check(player.get("attack_stage") == 2 and player.get("attack_phase") == "startup", "early queued input advances 1→2 instead of resetting")
	player.set("attack_buffer_remaining", 0.60)
	player.call("_update_attack", 0.085 + 0.12 + 0.22)
	_check(player.get("attack_stage") == 3 and player.get("attack_phase") == "startup", "queued input advances 2→3")
	player.call("_update_attack", 0.10 + 0.14 + 0.28)
	_check(player.get("attack_phase") == "idle" and player.get("attack_stage") == 0, "third recovery clears combo state")
	player.call("_request_attack")
	_check(player.get("attack_stage") == 1, "rapid follow-up after completion starts a fresh combo")

	# Skill activation, cooldown, and interruption contracts.
	player.set("attack_phase", "idle")
	player.set("attack_stage", 0)
	player.call("_request_skill", 1)
	var cooldowns: Array = player.get("skill_cooldowns")
	var cooldown_after_start: float = cooldowns[0]
	_check(player.get("skill_phase") == "startup" and cooldown_after_start > 0.0, "Num4 skill starts and spends cooldown at activation")
	player.call("_request_attack")
	_check(player.get("skill_phase") == "startup" and player.get("attack_phase") == "idle", "basic input during a skill is ignored")
	player.call("_update_skill", 0.16)
	_check(player.get("skill_phase") == "active" and player.get_node("Hitboxes/Skill1Hitbox").monitoring, "Num4 hitbox enables at active boundary")
	player.call("_update_skill", 0.12)
	_check(player.get("skill_phase") == "recovery" and not player.get_node("Hitboxes/Skill1Hitbox").monitoring, "Num4 hitbox disables at recovery boundary")
	player.call("_update_skill", 0.42)
	_check(player.get("skill_phase") == "idle", "Num4 recovery returns control")
	_check(cooldowns[0] == cooldown_after_start, "completed skill keeps cooldown until its timer expires")
	cooldowns[0] = 0.0
	player.call("_request_skill", 1)
	player.call("_update_skill", 0.16)
	player.call("_interrupt_skill_for_guard")
	_check(player.get("skill_phase") == "idle" and not player.get_node("Hitboxes/Skill1Hitbox").monitoring and cooldowns[0] > 0.0, "guard interrupts skill and keeps spent cooldown")
	player.call("_request_skill", 2)
	player.call("_update_skill", 0.22)
	_check(player.get("skill_phase") == "active" and player.get_node("Hitboxes/Skill2Hitbox").monitoring, "Num5 hitbox enables at active boundary")
	player.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.08, "attack_stage": 1})
	_check(player.get("skill_phase") == "idle" and not player.get_node("Hitboxes/Skill2Hitbox").monitoring, "incoming hit cancels skill and disables its hitbox")
	_check(player.get("hitstun_remaining") > 0.0, "incoming hit enters recoverable hitstun")
	for _frame in range(10):
		await physics_frame
	_check(player.get("hitstun_remaining") == 0.0, "hitstun timer expires")
	player.call("_request_attack")
	_check(player.get("attack_phase") == "startup", "attack input works again after hitstun")

	var source := FileAccess.get_file_as_string(CONTROLLER_SOURCE)
	_check(source.contains("if _skill_hit_targets.has(target_id):") and source.contains("_skill_hit_targets[target_id] = true"), "each skill can hit an individual receiver once")
	_check(source.contains("KEY_KP_4") == false, "input binding remains owned by project InputMap")
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("m6i_combo_skill_state_smoke: PASS")
		quit(0)
		return
	for failure in failures:
		push_error("m6i_combo_skill_state_smoke: " + failure)
	quit(1)
