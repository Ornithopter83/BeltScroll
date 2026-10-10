extends SceneTree

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const COMBO_LINK_WINDOW := 0.45
const STARTUP := [0.075, 0.085, 0.10]
const ACTIVE := [0.105, 0.12, 0.14]
const RECOVERY := [0.20, 0.22, 0.28]

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

	# Let stage one run its unchanged startup/active/recovery clock with no link input.
	player.call("_begin_attack", 1)
	player.call("_update_attack", STARTUP[0])
	_check(player.get("attack_phase") == "active" and player.get_node("Hitboxes/Hitbox1").monitoring, "stage 1 active window begins at its original startup boundary")
	player.call("_update_attack", ACTIVE[0])
	_check(player.get("attack_phase") == "recovery" and not player.get_node("Hitboxes/Hitbox1").monitoring, "stage 1 damage window closes at its original active boundary")
	player.call("_update_attack", RECOVERY[0])
	_check(player.get("attack_phase") == "combo_hold" and player.get("attack_stage") == 1, "stage 1 enters contact-pose link hold after full recovery")
	_check(is_equal_approx(float(player.get("combo_link_remaining")), COMBO_LINK_WINDOW), "link timer starts only after recovery completes")
	_check(_all_basic_hitboxes_off(), "all basic hitboxes stay off throughout link hold")
	_check(player.get("attack_progress") == 1.0, "held contact pose retains a completed phase clock")

	# A link press at the hold boundary starts the next startup immediately.
	player.call("_request_attack")
	_check(player.get("attack_stage") == 2 and player.get("attack_phase") == "startup", "J during hold enters stage 2 startup without an idle state")
	_check(is_equal_approx(float(player.get("attack_phase_remaining")), STARTUP[1]), "stage 2 startup timing remains unchanged")
	player.call("_update_attack", STARTUP[1])
	_check(player.get("attack_phase") == "active", "stage 2 active window begins at its original startup boundary")
	player.call("_update_attack", ACTIVE[1])
	_check(player.get("attack_phase") == "recovery", "stage 2 active window retains its original duration")
	player.call("_update_attack", RECOVERY[1])
	_check(player.get("attack_phase") == "combo_hold" and player.get("attack_stage") == 2, "stage 2 also retains its contact pose for a link")
	_check(_all_basic_hitboxes_off(), "stage 2 hold has no damaging hitboxes")

	# A buffered J on recovery is consumed at the exact phase boundary.
	player.call("_begin_attack", 1)
	player.call("_update_attack", STARTUP[0] + ACTIVE[0])
	player.set("attack_buffer_remaining", 0.60)
	player.call("_update_attack", RECOVERY[0])
	_check(player.get("attack_stage") == 2 and player.get("attack_phase") == "startup", "prebuffered J advances stage 1 directly into stage 2")
	_check(is_equal_approx(float(player.get("attack_phase_remaining")), STARTUP[1]), "stage 2 startup timing remains unchanged")
	player.call("_update_attack", STARTUP[1] + ACTIVE[1] + RECOVERY[1])
	_check(player.get("attack_stage") == 2 and player.get("attack_phase") == "combo_hold", "stage 2 ends in hold when no third input was queued")
	player.call("_request_attack")
	_check(player.get("attack_stage") == 3 and player.get("attack_phase") == "startup", "J during stage 2 hold immediately enters stage 3 startup")
	player.call("_update_attack", STARTUP[2] + ACTIVE[2] + RECOVERY[2])
	_check(player.get("attack_phase") == "idle" and player.get("attack_stage") == 0, "stage 3 recovery returns to normal idle")

	# No-input expiry, guard, skill, incoming hit and KO all release the hold safely.
	player.call("_begin_attack", 1)
	player.call("_update_attack", STARTUP[0] + ACTIVE[0] + RECOVERY[0])
	player.call("_update_attack", COMBO_LINK_WINDOW)
	_check(player.get("attack_phase") == "idle" and player.get("attack_buffer_remaining") == 0.0, "link expiry clears held pose and buffered input")
	player.call("_begin_attack", 1)
	player.call("_update_attack", STARTUP[0] + ACTIVE[0] + RECOVERY[0])
	Input.action_press("block")
	player.call("_physics_process", 1.0 / 60.0)
	Input.action_release("block")
	_check(player.get("attack_phase") == "idle" and player.get("is_blocking"), "guard cancels hold and can enter block on the same frame")
	player.set("is_blocking", false)
	player.call("_begin_attack", 1)
	player.call("_update_attack", STARTUP[0] + ACTIVE[0] + RECOVERY[0])
	player.call("_request_skill", 1)
	_check(player.get("attack_phase") == "idle" and player.get("skill_phase") == "startup", "skill transition clears hold and its input buffer")
	player.call("_cancel_skill")
	player.call("_begin_attack", 1)
	player.call("_update_attack", STARTUP[0] + ACTIVE[0] + RECOVERY[0])
	player.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.1, "attack_stage": 1})
	_check(player.get("attack_phase") == "idle" and player.get("attack_buffer_remaining") == 0.0, "incoming hit clears hold and buffered input")
	player.set("health", 1)
	player.set("hitstun_remaining", 0.0)
	player.call("_begin_attack", 1)
	player.call("_update_attack", STARTUP[0] + ACTIVE[0] + RECOVERY[0])
	player.receive_hit({"damage": 1, "direction": Vector2.LEFT, "knockback": 0.0, "hit_stun": 0.1, "attack_stage": 1})
	_check(player.get("is_ko") and player.get("attack_phase") == "idle" and player.get("combo_link_remaining") == 0.0, "KO clears hold and link timer")
	_check(_all_basic_hitboxes_off(), "hold interruptions leave every basic hitbox disabled")
	_finish()

func _all_basic_hitboxes_off() -> bool:
	for index in range(1, 4):
		if player.get_node("Hitboxes/Hitbox%d" % index).monitoring:
			return false
	return true

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		failures.append(description)

func _finish() -> void:
	if failures.is_empty():
		print("m6n_combo_link_window_smoke: all checks passed")
		quit(0)
		return
	for failure in failures:
		push_error("m6n_combo_link_window_smoke: " + failure)
	quit(1)
