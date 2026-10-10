extends CharacterBody2D

signal attack_started(stage: int)
signal attack_hit(stage: int)
signal player_hit(stage: int)
signal player_ko
signal skill_started(skill_id: int)
signal skill_hit(skill_id: int)

@export var walk_speed: float = 280.0
@export var attack_damage: int = 1
@export var arena_bounds: Rect2 = Rect2(Vector2(237, 722), Vector2(1446, 258))
@export var jump_height: float = 120.0
@export var jump_velocity: float = 536.66
@export var jump_buffer_time: float = 0.12
@export var coyote_time: float = 0.10
@export var released_jump_gravity_multiplier: float = 2.4
@export var max_health: int = 5

@onready var visual_root: Node2D = $VisualRoot
@onready var attack_flash: Polygon2D = $VisualRoot/AttackFlash
@onready var player_art: Sprite2D = $VisualRoot/PlayerArt
@onready var ground_shadow: Polygon2D = $GroundShadow
@onready var camera: Camera2D = $Camera2D

const BODY_HALF_WIDTH := 13.0
const BODY_TOP_OFFSET := -38.0
const BODY_BOTTOM_OFFSET := 2.0
const VISUAL_BASE_Y := -18.0
const CAMERA_VERTICAL_FRAME_OFFSET := -360.0
const COMBO_COUNT := 3
const HIT_FLASH_COLOR := Color(1.0, 0.42, 0.36, 1.0)
const KO_COLOR := Color(0.62, 0.62, 0.62, 0.78)
const HIT_FLASH_DURATION := 0.12
const HITSTUN_DECELERATION := 900.0
const STARTUP := [0.075, 0.085, 0.10]
const ACTIVE := [0.105, 0.12, 0.14]
const RECOVERY := [0.20, 0.22, 0.28]
const LUNGE := [34.0, 52.0, 76.0]
const ATTACK_RANGE := [55.0, 72.0, 92.0]
const ATTACK_REACH_SCALE := 1.25
const BLOCK_DAMAGE_MULTIPLIER := 0.25
const BLOCK_KNOCKBACK_MULTIPLIER := 0.35
const BLOCK_HITSTUN_MULTIPLIER := 0.5
const KNOCKBACK := [210.0, 310.0, 440.0]
const HIT_STOP := [0.035, 0.055, 0.08]
const ATTACK_RECOIL_DURATION := [0.055, 0.07, 0.085]
const ATTACK_RECOIL_SPEED := [105.0, 135.0, 165.0]
const CAMERA_TRAUMA := [0.12, 0.22, 0.34]
# Keep an early combo tap alive through the longest basic attack phase. The
# buffer is consumed only when recovery opens the next stage.
const INPUT_BUFFER_TIME := 0.60
const COMBAT_IMPACT_SCENE := preload("res://scenes/vfx/combat_impact.tscn")
const GROUND_DUST_SCENE := preload("res://scenes/vfx/ground_dust.tscn")
const GROUND_DUST_STEP_DISTANCE := 72.0
const MAX_GROUND_DUST_INSTANCES := 4
const SKILL_STARTUP := [0.16, 0.22]
const SKILL_ACTIVE := [0.12, 0.18]
const SKILL_RECOVERY := [0.42, 0.55]
const SKILL_DAMAGE := [3, 2]
const SKILL_KNOCKBACK := [520.0, 360.0]
const SKILL_HIT_STUN := [0.42, 0.32]
const SKILL_COOLDOWN := [1.35, 1.8]
const SKILL_LUNGE := 120.0
const SKILL_RECOIL_DURATION := 0.08
const SKILL_RECOIL_SPEED := 175.0

var facing_direction := Vector2.DOWN
var jump_vertical_velocity := 0.0
var jump_height_offset := 0.0
var jump_buffer_remaining := 0.0
var coyote_remaining := 0.0
var is_jumping := false
var is_blocking := false
var is_ko := false
var health := 5
var attack_stage := 0
var attack_progress := 0.0
var attack_phase := "idle"
var attack_phase_remaining := 0.0
var attack_buffer_remaining := 0.0
var attack_elapsed := 0.0
var hitstun_remaining := 0.0
var hit_flash_remaining := 0.0
var camera_trauma := 0.0
var _attack_origin := Vector2.ZERO
var _hit_targets: Dictionary = {}
var _hit_stop_token := 0
var _saved_time_scale := 1.0
var _hit_stop_active := false
var _combat_impacts: Array[Node2D] = []
var _attack_hit_emitted := false
var attack_recoil_remaining := 0.0
var attack_recoil_velocity := Vector2.ZERO
var _ground_distance_since_dust := 0.0
var _ground_dust_instances: Array[Node2D] = []
var skill_id := 0
var skill_phase := "idle"
var skill_phase_remaining := 0.0
var skill_cooldowns := [0.0, 0.0]
var _skill_hit_targets: Dictionary = {}

func _ready() -> void:
	health = max_health
	# Keep the oversized alpha silhouette below the HUD; camera limits still
	# constrain the view to the full-size stage background.
	camera.position = Vector2(0.0, CAMERA_VERTICAL_FRAME_OFFSET)
	add_to_group("hit_receivers")
	_set_attack_stage_visual(0)
	_set_skill_hitboxes(false)

func _physics_process(delta: float) -> void:
	for index in range(2):
		skill_cooldowns[index] = maxf(0.0, skill_cooldowns[index] - delta)
	if is_ko:
		velocity = Vector2.ZERO
		move_and_slide()
		_apply_arena_bounds()
		_update_jump(delta)
		_update_attack(delta)
		_update_skill(delta)
		_update_hit_flash(delta)
		_update_camera_trauma(delta)
		return

	if Input.is_action_just_pressed("skill_1"):
		_request_skill(1)
	elif Input.is_action_just_pressed("skill_2"):
		_request_skill(2)
	elif Input.is_action_just_pressed("attack"):
		_request_attack()
	else:
		attack_buffer_remaining = maxf(0.0, attack_buffer_remaining - delta)

	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction.length_squared() > 0.0 and hitstun_remaining <= 0.0 and attack_phase == "idle" and skill_phase == "idle":
		facing_direction = input_direction.normalized()
		if absf(facing_direction.x) > 0.1:
			visual_root.scale.x = -1.0 if facing_direction.x < 0.0 else 1.0

	is_blocking = Input.is_action_pressed("block") and hitstun_remaining <= 0.0 and attack_phase == "idle" and skill_phase == "idle" and not is_jumping
	if Input.is_action_pressed("block") and skill_phase != "idle":
		_interrupt_skill_for_guard()
	if hitstun_remaining > 0.0:
		hitstun_remaining = maxf(0.0, hitstun_remaining - delta)
		velocity = velocity.move_toward(Vector2.ZERO, HITSTUN_DECELERATION * delta)
	elif attack_recoil_remaining > 0.0:
		attack_recoil_remaining = maxf(0.0, attack_recoil_remaining - delta)
		velocity = attack_recoil_velocity
		attack_recoil_velocity = attack_recoil_velocity.move_toward(Vector2.ZERO, 1200.0 * delta)
	elif attack_phase == "idle" and skill_phase == "idle" and not is_blocking:
		velocity = input_direction.normalized() * walk_speed if input_direction.length_squared() > 0.0 else Vector2.ZERO
	elif is_blocking:
		velocity = Vector2.ZERO
	else:
		velocity = Vector2.ZERO
		if skill_phase != "idle":
			_apply_skill_motion()
		else:
			_apply_attack_lunge()

	var floor_position_before_move := global_position
	move_and_slide()
	_apply_arena_bounds()
	var landed := _update_jump(delta)
	_update_ground_dust(floor_position_before_move, landed)
	_update_attack(delta)
	_update_skill(delta)
	_update_hit_flash(delta)
	_update_camera_trauma(delta)

func _apply_arena_bounds() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x + BODY_HALF_WIDTH, arena_bounds.end.x - BODY_HALF_WIDTH)
	global_position.y = clampf(global_position.y, arena_bounds.position.y - BODY_TOP_OFFSET, arena_bounds.end.y - BODY_BOTTOM_OFFSET)

func _update_jump(delta: float) -> bool:
	if is_ko:
		jump_buffer_remaining = 0.0
		coyote_remaining = 0.0
		jump_vertical_velocity = 0.0
		jump_height_offset = 0.0
		is_jumping = false
		visual_root.position.y = VISUAL_BASE_Y
		ground_shadow.modulate.a = 0.42
		return false
	var landed := false

	if Input.is_action_just_pressed("jump") and not is_blocking:
		jump_buffer_remaining = maxf(0.0, jump_buffer_time)
	else:
		jump_buffer_remaining = maxf(0.0, jump_buffer_remaining - delta)

	if is_jumping:
		var gravity := _jump_gravity()
		if jump_vertical_velocity < 0.0 and not Input.is_action_pressed("jump"):
			gravity *= maxf(1.0, released_jump_gravity_multiplier)
		jump_vertical_velocity += gravity * delta
		jump_height_offset = minf(jump_height, jump_height_offset - jump_vertical_velocity * delta)
		if jump_height_offset <= 0.0 and jump_vertical_velocity >= 0.0:
			jump_height_offset = 0.0
			jump_vertical_velocity = 0.0
			is_jumping = false
			landed = true

	if is_jumping:
		coyote_remaining = maxf(0.0, coyote_remaining - delta)
	else:
		coyote_remaining = maxf(0.0, coyote_time)

	if jump_buffer_remaining > 0.0 and (not is_jumping or coyote_remaining > 0.0) and hitstun_remaining <= 0.0 and not is_blocking and skill_phase == "idle" and attack_phase == "idle":
		_start_jump()

	visual_root.position.y = VISUAL_BASE_Y - jump_height_offset
	var height_ratio := jump_height_offset / maxf(jump_height, 0.001)
	ground_shadow.modulate.a = 0.42 - 0.20 * height_ratio
	return landed

func _update_ground_dust(floor_position_before_move: Vector2, landed: bool) -> void:
	if is_ko:
		return
	if landed:
		_ground_distance_since_dust = 0.0
		_spawn_ground_dust(true)
		return
	if is_jumping:
		return
	_ground_distance_since_dust += floor_position_before_move.distance_to(global_position)
	if _ground_distance_since_dust >= GROUND_DUST_STEP_DISTANCE:
		_ground_distance_since_dust = fmod(_ground_distance_since_dust, GROUND_DUST_STEP_DISTANCE)
		_spawn_ground_dust(false)

func _spawn_ground_dust(landing: bool) -> void:
	for index in range(_ground_dust_instances.size() - 1, -1, -1):
		if not is_instance_valid(_ground_dust_instances[index]):
			_ground_dust_instances.remove_at(index)
	if _ground_dust_instances.size() >= MAX_GROUND_DUST_INSTANCES:
		return
	var dust := GROUND_DUST_SCENE.instantiate() as Node2D
	if dust == null:
		return
	add_child(dust)
	dust.position = Vector2(0.0, 2.0)
	dust.call("configure", landing)
	_ground_dust_instances.append(dust)

func _clear_ground_dust() -> void:
	for dust in _ground_dust_instances:
		if is_instance_valid(dust):
			dust.free()
	_ground_dust_instances.clear()
	_ground_distance_since_dust = 0.0

func _start_jump() -> void:
	jump_buffer_remaining = 0.0
	coyote_remaining = 0.0
	is_jumping = true
	jump_height_offset = 0.0
	jump_vertical_velocity = -absf(jump_velocity)

func _jump_gravity() -> float:
	var height := maxf(jump_height, 0.001)
	var velocity_magnitude := absf(jump_velocity)
	return velocity_magnitude * velocity_magnitude / (2.0 * height)

func _request_attack() -> void:
	if is_ko or hitstun_remaining > 0.0 or is_blocking or is_jumping or skill_phase != "idle" or Input.is_action_pressed("block"):
		return
	if attack_phase == "idle":
		_begin_attack(1)
	else:
		attack_buffer_remaining = INPUT_BUFFER_TIME

func _begin_attack(stage: int) -> void:
	if skill_phase != "idle":
		return
	attack_stage = clampi(stage, 1, COMBO_COUNT)
	attack_phase = "startup"
	attack_phase_remaining = STARTUP[attack_stage - 1]
	attack_elapsed = 0.0
	attack_progress = 0.0
	_attack_origin = global_position
	_hit_targets.clear()
	_attack_hit_emitted = false
	attack_started.emit(attack_stage)
	_set_attack_stage_visual(attack_stage)
	_set_stage_hitbox(attack_stage, false)

func _update_attack(delta: float) -> void:
	if attack_phase == "idle":
		attack_flash.visible = false
		return
	var remaining_delta := delta
	while remaining_delta > 0.0 and attack_phase != "idle":
		var stage_index := attack_stage - 1
		var phase_step := minf(remaining_delta, attack_phase_remaining)
		if attack_phase == "active":
			_check_stage_hitbox(attack_stage)
		attack_elapsed += phase_step
		var phase_duration: float = STARTUP[stage_index] + ACTIVE[stage_index] + RECOVERY[stage_index]
		attack_progress = clampf(attack_elapsed / phase_duration, 0.0, 1.0)
		attack_phase_remaining -= phase_step
		remaining_delta -= phase_step
		if attack_phase_remaining > 0.000001:
			break
		match attack_phase:
			"startup":
				attack_phase = "active"
				attack_phase_remaining = ACTIVE[stage_index]
				_set_stage_hitbox(attack_stage, true)
			"active":
				_set_stage_hitbox(attack_stage, false)
				attack_phase = "recovery"
				attack_phase_remaining = RECOVERY[stage_index]
			"recovery":
				_set_attack_stage_visual(0)
				if attack_buffer_remaining > 0.0 and attack_stage < COMBO_COUNT:
					attack_buffer_remaining = 0.0
					_begin_attack(attack_stage + 1)
				else:
					attack_phase = "idle"
					attack_stage = 0
					attack_progress = 0.0
					attack_buffer_remaining = 0.0
					attack_flash.visible = false

func _set_stage_hitbox(stage: int, enabled: bool) -> void:
	for index in range(1, COMBO_COUNT + 1):
		var hitbox := get_node("Hitboxes/Hitbox%d" % index) as Area2D
		hitbox.monitoring = enabled and index == stage
		hitbox.position = facing_direction * (ATTACK_RANGE[index - 1] * ATTACK_REACH_SCALE * 0.58)
		hitbox.rotation = facing_direction.angle()

func _request_skill(requested_skill_id: int) -> void:
	if requested_skill_id < 1 or requested_skill_id > 2:
		return
	var index := requested_skill_id - 1
	if is_ko or hitstun_remaining > 0.0 or is_blocking or Input.is_action_pressed("block") or is_jumping:
		return
	if skill_phase != "idle" or attack_phase != "idle" or skill_cooldowns[index] > 0.0:
		return
	skill_id = requested_skill_id
	skill_phase = "startup"
	skill_phase_remaining = SKILL_STARTUP[index]
	skill_cooldowns[index] = SKILL_COOLDOWN[index]
	_skill_hit_targets.clear()
	skill_started.emit(skill_id)
	_set_skill_hitbox_transform()
	_set_skill_hitboxes(false)
	attack_flash.visible = true
	attack_flash.color = Color(0.35, 0.9, 1.0, 0.95) if skill_id == 1 else Color(0.95, 0.5, 1.0, 0.95)
	attack_flash.scale = Vector2(1.8, 1.5) if skill_id == 1 else Vector2(2.0, 2.0)

func _set_skill_hitbox_transform() -> void:
	var lunge_hitbox := get_node("Hitboxes/Skill1Hitbox") as Area2D
	var spin_hitbox := get_node("Hitboxes/Skill2Hitbox") as Area2D
	lunge_hitbox.position = facing_direction * 52.0
	lunge_hitbox.rotation = facing_direction.angle()
	spin_hitbox.position = Vector2.ZERO
	spin_hitbox.rotation = 0.0

func _set_skill_hitboxes(enabled: bool) -> void:
	get_node("Hitboxes/Skill1Hitbox").monitoring = enabled and skill_id == 1
	get_node("Hitboxes/Skill2Hitbox").monitoring = enabled and skill_id == 2

func _update_skill(delta: float) -> void:
	if skill_phase == "idle":
		return
	var remaining_delta := delta
	while remaining_delta > 0.0 and skill_phase != "idle":
		var phase_step := minf(remaining_delta, skill_phase_remaining)
		if skill_phase == "active":
			_check_skill_hitbox()
		skill_phase_remaining -= phase_step
		remaining_delta -= phase_step
		if skill_phase_remaining > 0.000001:
			break
		match skill_phase:
			"startup":
				skill_phase = "active"
				skill_phase_remaining = SKILL_ACTIVE[skill_id - 1]
				_set_skill_hitbox_transform()
				_set_skill_hitboxes(true)
			"active":
				_set_skill_hitboxes(false)
				skill_phase = "recovery"
				skill_phase_remaining = SKILL_RECOVERY[skill_id - 1]
			"recovery":
				_cancel_skill()

func _check_skill_hitbox() -> void:
	var area_name := "Skill1Hitbox" if skill_id == 1 else "Skill2Hitbox"
	var hitbox := get_node("Hitboxes/" + area_name) as Area2D
	for target in hitbox.get_overlapping_bodies():
		if target == self or not target.is_in_group("hit_receivers") or not target.has_method("receive_hit"):
			continue
		var target_id := target.get_instance_id()
		if _skill_hit_targets.has(target_id):
			continue
		_skill_hit_targets[target_id] = true
		var direction := (target.global_position - global_position).normalized()
		if direction == Vector2.ZERO:
			direction = facing_direction
		var combat_stage := 3 if skill_id == 1 else 2
		target.receive_hit({
			"damage": _skill_damage(skill_id),
			"direction": direction,
			"knockback": SKILL_KNOCKBACK[skill_id - 1],
			"hit_stun": SKILL_HIT_STUN[skill_id - 1],
			"attack_stage": combat_stage,
			"skill_id": skill_id,
		})
		_start_attack_recoil(direction, SKILL_RECOIL_DURATION, SKILL_RECOIL_SPEED)
		skill_hit.emit(skill_id)
		_spawn_combat_impact(target, combat_stage, direction, skill_id, SKILL_HIT_STUN[skill_id - 1])
		_trigger_hit_stop(0.06 if skill_id == 1 else 0.045)
		_add_camera_trauma(0.32 if skill_id == 1 else 0.24)

func _apply_skill_motion() -> void:
	if skill_id == 1 and skill_phase == "startup":
		velocity = facing_direction * (SKILL_LUNGE / SKILL_STARTUP[0])
	elif skill_id == 1 and skill_phase == "active":
		velocity = facing_direction * (SKILL_LUNGE * 0.25 / SKILL_ACTIVE[0])
	else:
		velocity = Vector2.ZERO

func _cancel_skill() -> void:
	_set_skill_hitboxes(false)
	skill_phase = "idle"
	skill_phase_remaining = 0.0
	skill_id = 0
	attack_flash.visible = false

func _interrupt_skill_for_guard() -> void:
	# Guard wins over an in-progress skill; activation cooldown is not refunded.
	_cancel_skill()

func _check_stage_hitbox(stage: int) -> void:
	var hitbox := get_node("Hitboxes/Hitbox%d" % stage) as Area2D
	for target in hitbox.get_overlapping_bodies():
		if target == self or not target.is_in_group("hit_receivers") or not target.has_method("receive_hit"):
			continue
		var target_id := target.get_instance_id()
		if _hit_targets.has(target_id):
			continue
		_hit_targets[target_id] = true
		var direction := (target.global_position - global_position).normalized()
		if direction == Vector2.ZERO:
			direction = facing_direction
		var hit := {
			"damage": _basic_attack_damage(stage),
			"direction": direction,
			"knockback": KNOCKBACK[stage - 1],
			"hit_stun": 0.14 + stage * 0.055,
			"attack_stage": stage,
		}
		target.receive_hit(hit)
		_start_attack_recoil(direction, ATTACK_RECOIL_DURATION[stage - 1], ATTACK_RECOIL_SPEED[stage - 1])
		if not _attack_hit_emitted:
			_attack_hit_emitted = true
			attack_hit.emit(stage)
		_spawn_combat_impact(target, stage, direction, 0, float(hit["hit_stun"]))
		_trigger_hit_stop(HIT_STOP[stage - 1])
		_add_camera_trauma(CAMERA_TRAUMA[stage - 1])

func _basic_attack_damage(stage: int) -> int:
	return maxi(0, attack_damage) + maxi(0, stage - 1)

func _skill_damage(selected_skill: int) -> int:
	if selected_skill < 1 or selected_skill > SKILL_DAMAGE.size():
		return 0
	return maxi(0, attack_damage) + SKILL_DAMAGE[selected_skill - 1] - 1

func _start_attack_recoil(hit_direction: Vector2, duration: float, speed: float) -> void:
	if is_ko or hitstun_remaining > 0.0:
		return
	var recoil_direction := -hit_direction.normalized()
	if recoil_direction == Vector2.ZERO:
		recoil_direction = -facing_direction
	attack_recoil_remaining = maxf(attack_recoil_remaining, duration)
	attack_recoil_velocity = recoil_direction * speed

func _spawn_combat_impact(target: Node2D, stage: int, direction: Vector2, selected_skill: int = 0, hit_stun: float = 0.2) -> void:
	if is_ko or not is_instance_valid(target) or not target.is_inside_tree():
		return
	if target.is_queued_for_deletion():
		return
	var impact := COMBAT_IMPACT_SCENE.instantiate() as Node2D
	if impact == null:
		return
	target.add_child(impact)
	impact.global_position = _combat_impact_position(target)
	impact.configure(stage, direction, selected_skill, hit_stun)
	for index in range(_combat_impacts.size() - 1, -1, -1):
		if not is_instance_valid(_combat_impacts[index]):
			_combat_impacts.remove_at(index)
	_combat_impacts.append(impact)

func _combat_impact_position(target: Node2D) -> Vector2:
	for path in ["VisualRoot/RaiderArt", "VisualRoot/PlayerArt", "VisualRoot/Body"]:
		var visual := target.get_node_or_null(path) as Node2D
		if visual != null:
			return visual.global_position
	var receive_area := target.get_node_or_null("ReceiveArea") as Node2D
	if receive_area != null:
		return receive_area.global_position
	var visual_root_node := target.get_node_or_null("VisualRoot") as Node2D
	if visual_root_node != null:
		return visual_root_node.global_position
	return target.global_position + Vector2(0.0, -20.0)

func _clear_combat_impacts() -> void:
	for impact in _combat_impacts:
		if is_instance_valid(impact):
			impact.queue_free()
	_combat_impacts.clear()

func _apply_attack_lunge() -> void:
	if attack_phase == "startup":
		velocity = facing_direction * (LUNGE[attack_stage - 1] / STARTUP[attack_stage - 1])
	elif attack_phase == "active":
		velocity = facing_direction * (LUNGE[attack_stage - 1] * 0.4 / ACTIVE[attack_stage - 1])

func _set_attack_stage_visual(stage: int) -> void:
	if stage == 0:
		attack_flash.visible = false
		attack_flash.color = Color(1.0, 0.8, 0.25, 0.95)
		return
	attack_flash.color = Color(1.0, 0.8, 0.25, 0.95)
	var stage_index := stage - 1
	attack_flash.visible = true
	attack_flash.position = Vector2(ATTACK_RANGE[stage_index] * ATTACK_REACH_SCALE * 0.45, -5)
	attack_flash.scale = Vector2(1.0 + stage_index * 0.18, 1.0 + stage_index * 0.12)

func receive_hit(hit: Dictionary) -> void:
	if is_ko:
		return
	if not hit.has("damage") or not hit.has("direction") or not hit.has("knockback") or not hit.has("hit_stun") or not hit.has("attack_stage"):
		return
	_cancel_skill()
	# A hit always breaks the current basic combo as well as a skill. Cooldowns
	# started at skill activation remain spent after interruption.
	attack_recoil_remaining = 0.0
	attack_recoil_velocity = Vector2.ZERO
	player_hit.emit(int(hit["attack_stage"]))
	var direction: Vector2 = hit["direction"]
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	var incoming_damage := int(hit["damage"])
	var incoming_knockback := float(hit["knockback"])
	var incoming_hitstun := float(hit["hit_stun"])
	if is_blocking:
		incoming_damage = maxi(1, int(ceil(float(incoming_damage) * BLOCK_DAMAGE_MULTIPLIER)))
		incoming_knockback *= BLOCK_KNOCKBACK_MULTIPLIER
		incoming_hitstun *= BLOCK_HITSTUN_MULTIPLIER
	health = maxi(0, health - incoming_damage)
	if health == 0:
		hit_flash_remaining = HIT_FLASH_DURATION
		_add_camera_trauma(0.14 + int(hit["attack_stage"]) * 0.04)
		_enter_ko()
		return
	velocity = direction * incoming_knockback
	hitstun_remaining = maxf(hitstun_remaining, incoming_hitstun)
	is_blocking = false
	attack_phase = "idle"
	attack_stage = 0
	attack_progress = 0.0
	attack_buffer_remaining = 0.0
	for index in range(1, COMBO_COUNT + 1):
		_set_stage_hitbox(index, false)
	_set_attack_stage_visual(0)
	hit_flash_remaining = maxf(hit_flash_remaining, HIT_FLASH_DURATION)
	player_art.modulate = HIT_FLASH_COLOR
	_add_camera_trauma(0.14 + int(hit["attack_stage"]) * 0.04)

func _enter_ko() -> void:
	player_ko.emit()
	_clear_combat_impacts()
	_clear_ground_dust()
	is_ko = true
	player_art.modulate = KO_COLOR
	velocity = Vector2.ZERO
	hitstun_remaining = 0.0
	is_blocking = false
	jump_buffer_remaining = 0.0
	coyote_remaining = 0.0
	jump_vertical_velocity = 0.0
	jump_height_offset = 0.0
	is_jumping = false
	attack_phase = "idle"
	_cancel_skill()
	attack_stage = 0
	attack_progress = 0.0
	attack_phase_remaining = 0.0
	attack_buffer_remaining = 0.0
	attack_elapsed = 0.0
	for index in range(1, COMBO_COUNT + 1):
		_set_stage_hitbox(index, false)
	_set_attack_stage_visual(0)

func _update_hit_flash(delta: float) -> void:
	if is_ko:
		player_art.modulate = KO_COLOR
		return
	if hit_flash_remaining > 0.0:
		hit_flash_remaining = maxf(0.0, hit_flash_remaining - delta)
		player_art.modulate = HIT_FLASH_COLOR
	else:
		player_art.modulate = Color.WHITE

func _trigger_hit_stop(duration: float) -> void:
	_hit_stop_token += 1
	var token := _hit_stop_token
	if not _hit_stop_active:
		_saved_time_scale = Engine.time_scale
		_hit_stop_active = true
	Engine.time_scale = minf(Engine.time_scale, 0.08)
	_restore_hit_stop_after(duration, token)

func _restore_hit_stop_after(duration: float, token: int) -> void:
	await get_tree().create_timer(duration, true, false, true).timeout
	if token == _hit_stop_token:
		Engine.time_scale = _saved_time_scale
		_saved_time_scale = 1.0
		_hit_stop_active = false

func _add_camera_trauma(amount: float) -> void:
	camera_trauma = minf(1.0, camera_trauma + amount)

func _update_camera_trauma(delta: float) -> void:
	camera_trauma = maxf(0.0, camera_trauma - delta * 1.8)
	var shake := camera_trauma * camera_trauma
	if shake <= 0.0001:
		camera.offset = Vector2.ZERO
	else:
		var t := Time.get_ticks_msec() * 0.001
		var shake_offset := Vector2(sin(t * 71.0), cos(t * 59.0)) * shake * 8.0
		camera.offset = Vector2.ZERO
		camera.offset = _clamp_camera_offset_to_background(shake_offset)

func _clamp_camera_offset_to_background(requested_offset: Vector2) -> Vector2:
	# Keep a one screen-pixel guard inside the stage so texture filtering and
	# fractional camera smoothing cannot reveal the clear color at a backdrop edge.
	var viewport_size := get_viewport_rect().size
	var half_view := viewport_size / camera.zoom * 0.5
	var guard := Vector2.ONE / camera.zoom
	var center := camera.get_screen_center_position()
	var min_center := Vector2(camera.limit_left, camera.limit_top) + half_view + guard
	var max_center := Vector2(camera.limit_right, camera.limit_bottom) - half_view - guard
	var min_offset := min_center - center
	var max_offset := max_center - center
	if max_offset.x < min_offset.x:
		min_offset.x = 0.0
		max_offset.x = 0.0
	if max_offset.y < min_offset.y:
		min_offset.y = 0.0
		max_offset.y = 0.0
	return Vector2(clampf(requested_offset.x, min_offset.x, max_offset.x), clampf(requested_offset.y, min_offset.y, max_offset.y))
