extends CharacterBody2D

@export var walk_speed: float = 280.0
@export var sit_speed_multiplier: float = 0.45
@export var arena_bounds: Rect2 = Rect2(Vector2(160, 100), Vector2(1600, 880))
@export var jump_height: float = 54.0
@export var jump_velocity: float = 360.0
@export var jump_buffer_time: float = 0.12
@export var coyote_time: float = 0.10
@export var released_jump_gravity_multiplier: float = 2.4

@onready var visual_root: Node2D = $VisualRoot
@onready var attack_flash: Polygon2D = $VisualRoot/AttackFlash
@onready var ground_shadow: Polygon2D = $GroundShadow

var facing_direction := Vector2.DOWN
var jump_vertical_velocity := 0.0
var jump_height_offset := 0.0
var jump_buffer_remaining := 0.0
var coyote_remaining := 0.0
var is_jumping := false
var attack_time := 0.0
var is_sitting := false

const BODY_HALF_WIDTH := 13.0
const BODY_TOP_OFFSET := -38.0
const BODY_BOTTOM_OFFSET := 2.0
const VISUAL_BASE_Y := -18.0
const VISUAL_BOTTOM := 15.0
const ATTACK_DURATION := 0.14

func _physics_process(delta: float) -> void:
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction.length_squared() > 0.0:
		facing_direction = input_direction.normalized()
		if absf(facing_direction.x) > 0.1:
			visual_root.scale.x = -1.0 if facing_direction.x < 0.0 else 1.0

	is_sitting = Input.is_action_pressed("sit")
	var visual_scale_y := 0.78 if is_sitting else 1.0
	visual_root.scale.y = visual_scale_y
	var speed := walk_speed * (sit_speed_multiplier if is_sitting else 1.0)
	velocity = input_direction.normalized() * speed if input_direction.length_squared() > 0.0 else Vector2.ZERO
	move_and_slide()
	_apply_arena_bounds()
	_update_jump(delta, visual_scale_y)
	_update_attack(delta)

func _apply_arena_bounds() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x + BODY_HALF_WIDTH, arena_bounds.end.x - BODY_HALF_WIDTH)
	global_position.y = clampf(global_position.y, arena_bounds.position.y - BODY_TOP_OFFSET, arena_bounds.end.y - BODY_BOTTOM_OFFSET)

func _update_jump(delta: float, visual_scale_y: float) -> void:
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

	# This arena has no ledges. Coyote time is tied only to the virtual ground
	# contact state, so walking around the flat arena never invents a fall.
	if is_jumping:
		coyote_remaining = maxf(0.0, coyote_remaining - delta)
	else:
		coyote_remaining = maxf(0.0, coyote_time)

	if jump_buffer_remaining > 0.0 and (not is_jumping or coyote_remaining > 0.0):
		_start_jump()

	# Keep the sprite's feet anchored when crouching, and offset only the visual
	# body during a jump. The CharacterBody2D and shadow stay on the floor plane.
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

func _update_attack(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		attack_time = ATTACK_DURATION
	if attack_time > 0.0:
		attack_time = maxf(0.0, attack_time - delta)
	attack_flash.visible = attack_time > 0.0
