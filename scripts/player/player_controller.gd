extends CharacterBody2D

@export var walk_speed: float = 280.0
@export var sit_speed_multiplier: float = 0.45
@export var arena_bounds: Rect2 = Rect2(Vector2(160, 100), Vector2(1600, 880))
@export var jump_height: float = 54.0
@export var jump_velocity: float = 360.0
@export var jump_buffer_time: float = 0.12
@export var coyote_time: float = 0.10
@export var released_jump_gravity_multiplier: float = 2.4
@export var max_health: int = 5

@onready var visual_root: Node2D = $VisualRoot
@onready var attack_flash: Polygon2D = $VisualRoot/AttackFlash
@onready var body_stage_1: Polygon2D = $VisualRoot/BodyStage1
@onready var body_stage_2: Polygon2D = $VisualRoot/BodyStage2
@onready var body_stage_3: Polygon2D = $VisualRoot/BodyStage3
@onready var ground_shadow: Polygon2D = $GroundShadow
@onready var camera: Camera2D = $Camera2D

const BODY_HALF_WIDTH := 13.0
const BODY_TOP_OFFSET := -38.0
const BODY_BOTTOM_OFFSET := 2.0
const VISUAL_BASE_Y := -18.0
const VISUAL_BOTTOM := 15.0
const COMBO_COUNT := 3
const STARTUP := [0.075, 0.085, 0.10]
const ACTIVE := [0.105, 0.12, 0.14]
const RECOVERY := [0.20, 0.22, 0.28]
const LUNGE := [34.0, 52.0, 76.0]
const ATTACK_RANGE := [55.0, 72.0, 92.0]
const KNOCKBACK := [210.0, 310.0, 440.0]
const HIT_STOP := [0.035, 0.055, 0.08]
const CAMERA_TRAUMA := [0.12, 0.22, 0.34]
const INPUT_BUFFER_TIME := 0.24

var facing_direction := Vector2.DOWN
var jump_vertical_velocity := 0.0
var jump_height_offset := 0.0
var jump_buffer_remaining := 0.0
var coyote_remaining := 0.0
var is_jumping := false
var is_sitting := false
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

func _ready() -> void:
	health = max_health
	add_to_group("hit_receivers")
	_set_attack_stage_visual(0)

func _physics_process(delta: float) -> void:
	if is_ko:
		velocity = Vector2.ZERO
		move_and_slide()
		_apply_arena_bounds()
		_update_jump(delta, 1.0)
		_update_attack(delta)
		_update_hit_flash(delta)
		_update_camera_trauma(delta)
		return

	if Input.is_action_just_pressed("attack"):
		_request_attack()
	else:
		attack_buffer_remaining = maxf(0.0, attack_buffer_remaining - delta)

	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction.length_squared() > 0.0 and hitstun_remaining <= 0.0 and attack_phase == "idle":
		facing_direction = input_direction.normalized()
		if absf(facing_direction.x) > 0.1:
			visual_root.scale.x = -1.0 if facing_direction.x < 0.0 else 1.0

	is_sitting = Input.is_action_pressed("sit") and hitstun_remaining <= 0.0
	var visual_scale_y := 0.78 if is_sitting else 1.0
	visual_root.scale.y = visual_scale_y
	if hitstun_remaining > 0.0:
		hitstun_remaining = maxf(0.0, hitstun_remaining - delta)
		velocity = velocity.move_toward(Vector2.ZERO, 900.0 * delta)
	elif attack_phase == "idle":
		var speed := walk_speed * (sit_speed_multiplier if is_sitting else 1.0)
		velocity = input_direction.normalized() * speed if input_direction.length_squared() > 0.0 else Vector2.ZERO
	else:
		velocity = Vector2.ZERO
		_apply_attack_lunge()

	move_and_slide()
	_apply_arena_bounds()
	_update_jump(delta, visual_scale_y)
	_update_attack(delta)
	_update_hit_flash(delta)
	_update_camera_trauma(delta)

func _apply_arena_bounds() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x + BODY_HALF_WIDTH, arena_bounds.end.x - BODY_HALF_WIDTH)
	global_position.y = clampf(global_position.y, arena_bounds.position.y - BODY_TOP_OFFSET, arena_bounds.end.y - BODY_BOTTOM_OFFSET)

func _update_jump(delta: float, visual_scale_y: float) -> void:
	if is_ko:
		jump_buffer_remaining = 0.0
		coyote_remaining = 0.0
		jump_vertical_velocity = 0.0
		jump_height_offset = 0.0
		is_jumping = false
		visual_root.position.y = VISUAL_BASE_Y + (1.0 - visual_scale_y) * VISUAL_BOTTOM
		ground_shadow.modulate.a = 0.42
		return

	if Input.is_action_just_pressed("jump"):
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

	if is_jumping:
		coyote_remaining = maxf(0.0, coyote_remaining - delta)
	else:
		coyote_remaining = maxf(0.0, coyote_time)

	if jump_buffer_remaining > 0.0 and (not is_jumping or coyote_remaining > 0.0) and hitstun_remaining <= 0.0:
		_start_jump()

	visual_root.position.y = VISUAL_BASE_Y - jump_height_offset + (1.0 - visual_scale_y) * VISUAL_BOTTOM
	var height_ratio := jump_height_offset / maxf(jump_height, 0.001)
	ground_shadow.modulate.a = 0.42 - 0.20 * height_ratio

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
	if is_ko or hitstun_remaining > 0.0:
		return
	if attack_phase == "idle":
		_begin_attack(1)
	else:
		attack_buffer_remaining = INPUT_BUFFER_TIME

func _begin_attack(stage: int) -> void:
	attack_stage = clampi(stage, 1, COMBO_COUNT)
	attack_phase = "startup"
	attack_phase_remaining = STARTUP[attack_stage - 1]
	attack_elapsed = 0.0
	attack_progress = 0.0
	_attack_origin = global_position
	_hit_targets.clear()
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
		hitbox.position = facing_direction * (ATTACK_RANGE[index - 1] * 0.58)
		hitbox.rotation = facing_direction.angle()

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
			"damage": 1 + (stage - 1),
			"direction": direction,
			"knockback": KNOCKBACK[stage - 1],
			"hit_stun": 0.14 + stage * 0.055,
			"attack_stage": stage,
		}
		target.receive_hit(hit)
		_trigger_hit_stop(HIT_STOP[stage - 1])
		_add_camera_trauma(CAMERA_TRAUMA[stage - 1])

func _apply_attack_lunge() -> void:
	if attack_phase == "startup":
		velocity = facing_direction * (LUNGE[attack_stage - 1] / STARTUP[attack_stage - 1])
	elif attack_phase == "active":
		velocity = facing_direction * (LUNGE[attack_stage - 1] * 0.4 / ACTIVE[attack_stage - 1])

func _set_attack_stage_visual(stage: int) -> void:
	body_stage_1.visible = stage == 1
	body_stage_2.visible = stage == 2
	body_stage_3.visible = stage == 3
	if stage == 0:
		body_stage_1.visible = true
		attack_flash.visible = false
		return
	var stage_index := stage - 1
	attack_flash.visible = true
	attack_flash.position = Vector2(ATTACK_RANGE[stage_index] * 0.45, -5)
	attack_flash.scale = Vector2(1.0 + stage_index * 0.18, 1.0 + stage_index * 0.12)

func receive_hit(hit: Dictionary) -> void:
	if is_ko:
		return
	if not hit.has("damage") or not hit.has("direction") or not hit.has("knockback") or not hit.has("hit_stun") or not hit.has("attack_stage"):
		return
	var direction: Vector2 = hit["direction"]
	if direction.length_squared() > 0.0:
		direction = direction.normalized()
	health = maxi(0, health - int(hit["damage"]))
	if health == 0:
		hit_flash_remaining = 0.12
		_add_camera_trauma(0.14 + int(hit["attack_stage"]) * 0.04)
		_enter_ko()
		return
	velocity = direction * float(hit["knockback"])
	hitstun_remaining = maxf(hitstun_remaining, float(hit["hit_stun"]))
	is_sitting = false
	attack_phase = "idle"
	attack_stage = 0
	attack_progress = 0.0
	attack_buffer_remaining = 0.0
	for index in range(1, COMBO_COUNT + 1):
		_set_stage_hitbox(index, false)
	_set_attack_stage_visual(0)
	hit_flash_remaining = 0.12
	_add_camera_trauma(0.14 + int(hit["attack_stage"]) * 0.04)

func _enter_ko() -> void:
	is_ko = true
	velocity = Vector2.ZERO
	hitstun_remaining = 0.0
	is_sitting = false
	jump_buffer_remaining = 0.0
	coyote_remaining = 0.0
	jump_vertical_velocity = 0.0
	jump_height_offset = 0.0
	is_jumping = false
	attack_phase = "idle"
	attack_stage = 0
	attack_progress = 0.0
	attack_phase_remaining = 0.0
	attack_buffer_remaining = 0.0
	attack_elapsed = 0.0
	for index in range(1, COMBO_COUNT + 1):
		_set_stage_hitbox(index, false)
	_set_attack_stage_visual(0)

func _update_hit_flash(delta: float) -> void:
	if hit_flash_remaining > 0.0:
		hit_flash_remaining = maxf(0.0, hit_flash_remaining - delta)
		body_stage_1.color = Color(1.0, 0.42, 0.36, 1.0)
		body_stage_2.color = Color(1.0, 0.42, 0.36, 1.0)
		body_stage_3.color = Color(1.0, 0.42, 0.36, 1.0)
	else:
		body_stage_1.color = Color(0.28, 0.68, 0.73, 1.0)
		body_stage_2.color = Color(0.38, 0.76, 0.72, 1.0)
		body_stage_3.color = Color(0.48, 0.83, 0.78, 1.0)

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
		var half_view := get_viewport_rect().size / camera.zoom * 0.5
		var center := camera.get_screen_center_position()
		var min_center := Vector2(camera.limit_left, camera.limit_top) + half_view
		var max_center := Vector2(camera.limit_right, camera.limit_bottom) - half_view
		var min_offset := min_center - center
		var max_offset := max_center - center
		if max_offset.x < min_offset.x:
			min_offset.x = 0.0
			max_offset.x = 0.0
		if max_offset.y < min_offset.y:
			min_offset.y = 0.0
			max_offset.y = 0.0
		camera.offset = Vector2(clampf(shake_offset.x, min_offset.x, max_offset.x), clampf(shake_offset.y, min_offset.y, max_offset.y))
