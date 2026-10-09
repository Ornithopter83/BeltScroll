extends Node
"""Small sprite-only pose layer driven by the owning Raider's existing combat state."""

const POSE_FOLLOW_SPEED := 12.0
const WALK_SPEED_REFERENCE := 118.0
const HIT_FLASH_DURATION := 0.14

@onready var raider: CharacterBody2D = get_parent() as CharacterBody2D
@onready var art: Sprite2D = raider.get_node("VisualRoot/RaiderArt") as Sprite2D

var _base_position := Vector2.ZERO
var _base_scale := Vector2.ONE
var _base_rotation := 0.0
var _foot_anchor := Vector2.ZERO
var _alpha_foot_from_center := Vector2.ZERO
var _stride_phase := 0.0
var _pose_rotation := 0.0
var _pose_scale := Vector2.ONE

func _ready() -> void:
	_base_position = art.position
	_base_scale = art.scale
	_base_rotation = art.rotation
	var texture_size := Vector2(art.texture.get_size())
	var alpha_bounds := art.texture.get_image().get_used_rect()
	var alpha_foot := Vector2(
		float(alpha_bounds.position.x) + float(alpha_bounds.size.x) * 0.5,
		float(alpha_bounds.end.y)
	)
	_alpha_foot_from_center = (alpha_foot - texture_size * 0.5) * _base_scale
	_foot_anchor = _base_position + _alpha_foot_from_center
	_pose_scale = _base_scale

func _process(delta: float) -> void:
	if raider == null or not is_instance_valid(raider) or art == null:
		return
	var target_rotation := _base_rotation
	var target_scale := _base_scale
	var health := int(raider.get("health"))
	if health <= 0:
		# A single quiet defeated pose; no idle or stride oscillator after KO.
		target_rotation += 0.075
		target_scale *= Vector2(1.025, 0.94)
	elif float(raider.get("hit_flash_remaining")) > 0.0:
		var flash := clampf(float(raider.get("hit_flash_remaining")) / HIT_FLASH_DURATION, 0.0, 1.0)
		var impulse: Vector2 = raider.get("hit_reaction_direction")
		var strength := clampf(float(raider.get("hit_reaction_strength")), 0.65, 1.4)
		var impulse_x := signf(impulse.x)
		if is_zero_approx(impulse_x):
			impulse_x = -1.0 if raider.velocity.x < 0.0 else 1.0
		# Recoil leans away from impact and compresses the body before settling.
		target_rotation += -impulse_x * 0.18 * strength * flash
		target_scale *= Vector2(1.025 + 0.035 * strength * flash, 0.91 + 0.09 * (1.0 - flash))
	elif float(raider.get("hitstun_remaining")) > 0.0:
		var impulse: Vector2 = raider.get("hit_reaction_direction")
		var impulse_x := signf(impulse.x)
		var strength := clampf(float(raider.get("hit_reaction_strength")), 0.65, 1.4)
		var wobble := sin((1.0 - clampf(float(raider.get("hitstun_remaining")) / 0.42, 0.0, 1.0)) * TAU)
		target_rotation += -impulse_x * (0.085 + 0.018 * wobble) * strength
		target_scale *= Vector2(1.0 + 0.015 * strength, 0.965)
	else:
		var phase := str(raider.get("attack_phase"))
		var speed := raider.velocity.length()
		if phase == "windup":
			var windup_duration := maxf(0.001, float(raider.get("windup_duration")))
			var progress := 1.0 - clampf(float(raider.get("attack_phase_remaining")) / windup_duration, 0.0, 1.0)
			var facing: Vector2 = raider.get("facing_direction")
			var facing_sign := -1.0 if facing.x < 0.0 else 1.0
			var anticipation := sin(progress * PI * 0.5)
			target_rotation += facing_sign * (0.035 + 0.12 * anticipation)
			target_scale *= Vector2(1.0 - 0.06 * anticipation, 1.0 - 0.12 * anticipation)
		elif phase == "active":
			var facing: Vector2 = raider.get("facing_direction")
			var facing_sign := -1.0 if facing.x < 0.0 else 1.0
			target_rotation += -facing_sign * 0.18
			target_scale *= Vector2(1.12, 0.86)
		elif phase == "recovery":
			var recovery_duration := maxf(0.001, float(raider.get("recovery_duration")))
			var recovery := clampf(float(raider.get("attack_phase_remaining")) / recovery_duration, 0.0, 1.0)
			var facing: Vector2 = raider.get("facing_direction")
			var facing_sign := -1.0 if facing.x < 0.0 else 1.0
			target_rotation += facing_sign * 0.07 * recovery
			target_scale *= Vector2(1.0 + 0.02 * recovery, 1.0 - 0.035 * recovery)
		elif speed > 10.0:
			var speed_factor := clampf(speed / WALK_SPEED_REFERENCE, 0.35, 1.3)
			_stride_phase = fposmod(_stride_phase + delta * (7.0 + 4.0 * speed_factor), TAU)
			var stride := sin(_stride_phase)
			target_rotation += stride * 0.025 * speed_factor
			target_scale *= Vector2(1.0 - absf(stride) * 0.006, 1.0 + absf(stride) * 0.009)
		else:
			# Subtle breathing remains small enough to read as life, not idle bobbing.
			var breath := sin(float(Time.get_ticks_msec()) * 0.0018)
			target_rotation += breath * 0.004
			target_scale *= Vector2(1.0 + breath * 0.002, 1.0 + breath * 0.004)

	var blend := 1.0 - exp(-POSE_FOLLOW_SPEED * maxf(delta, 0.0))
	_pose_rotation = lerpf(_pose_rotation, target_rotation, blend)
	_pose_scale = _pose_scale.lerp(target_scale, blend)
	art.rotation = _pose_rotation
	art.scale = _pose_scale
	# Keep the center of the artwork's bottom alpha edge fixed while it scales or tilts.
	var scaled_foot := Vector2(
		_alpha_foot_from_center.x * (_pose_scale.x / _base_scale.x),
		_alpha_foot_from_center.y * (_pose_scale.y / _base_scale.y)
	)
	art.position = _foot_anchor - scaled_foot.rotated(_pose_rotation - _base_rotation)
