extends CharacterBody2D

@export var walk_speed: float = 280.0
@export var sit_speed_multiplier: float = 0.45
@export var arena_bounds: Rect2 = Rect2(Vector2(160, 100), Vector2(1600, 880))
@export var jump_height: float = 54.0
@export var jump_duration: float = 0.42

@onready var visual_root: Node2D = $VisualRoot
@onready var attack_flash: Polygon2D = $VisualRoot/AttackFlash
@onready var ground_shadow: Polygon2D = $GroundShadow

var facing_direction := Vector2.DOWN
var jump_time := 0.0
var attack_time := 0.0
var is_sitting := false

const BODY_HALF_WIDTH := 13.0
const BODY_TOP_OFFSET := -38.0
const BODY_BOTTOM_OFFSET := 2.0
const ATTACK_DURATION := 0.14

func _physics_process(delta: float) -> void:
	var input_direction := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	if input_direction.length_squared() > 0.0:
		facing_direction = input_direction.normalized()
		visual_root.scale.x = -1.0 if facing_direction.x < -0.1 else 1.0

	is_sitting = Input.is_action_pressed("sit")
	visual_root.scale.y = 0.78 if is_sitting else 1.0
	var speed := walk_speed * (sit_speed_multiplier if is_sitting else 1.0)
	velocity = input_direction.normalized() * speed if input_direction.length_squared() > 0.0 else Vector2.ZERO
	move_and_slide()
	_apply_arena_bounds()
	_update_jump(delta)
	_update_attack(delta)

func _apply_arena_bounds() -> void:
	global_position.x = clampf(global_position.x, arena_bounds.position.x + BODY_HALF_WIDTH, arena_bounds.end.x - BODY_HALF_WIDTH)
	global_position.y = clampf(global_position.y, arena_bounds.position.y - BODY_TOP_OFFSET, arena_bounds.end.y - BODY_BOTTOM_OFFSET)

func _update_jump(delta: float) -> void:
	if Input.is_action_just_pressed("jump") and jump_time <= 0.0:
		jump_time = jump_duration

	if jump_time > 0.0:
		jump_time = maxf(0.0, jump_time - delta)
		var progress := 1.0 - jump_time / jump_duration
		var height := 4.0 * jump_height * progress * (1.0 - progress)
		visual_root.position.y = -18.0 - height
		ground_shadow.modulate.a = 0.42 - 0.2 * progress
	else:
		visual_root.position.y = -18.0
		ground_shadow.modulate.a = 0.42

func _update_attack(delta: float) -> void:
	if Input.is_action_just_pressed("attack"):
		attack_time = ATTACK_DURATION
	if attack_time > 0.0:
		attack_time = maxf(0.0, attack_time - delta)
	attack_flash.visible = attack_time > 0.0
