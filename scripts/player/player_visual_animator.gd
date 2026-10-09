extends Node
"""Sprite-only pose layer driven by the owning Player's existing state."""

const FOLLOW_SPEED := 16.0
const WALK_SPEED_REFERENCE := 280.0
const HIT_FLASH_DURATION := 0.12
const ATTACK_STARTUP := [0.075, 0.085, 0.10]
const ATTACK_ACTIVE := [0.105, 0.12, 0.14]
const ATTACK_RECOVERY := [0.20, 0.22, 0.28]
const ATTACK_TEMPORARY_MOTION_FRAMES := 5

@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var art: Sprite2D = player.get_node("VisualRoot/PlayerArt") as Sprite2D
@onready var visual_root: Node2D = player.get_node("VisualRoot") as Node2D
@onready var pose_blender: PlayerPoseBlender = player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender

var _base_position := Vector2.ZERO
var _base_scale := Vector2.ONE
var _base_rotation := 0.0
var _foot_anchor := Vector2.ZERO
var _alpha_foot_from_center := Vector2.ZERO
var _pose_rotation := 0.0
var _pose_scale := Vector2.ONE
var _stride_phase := 0.0
var _landing_remaining := 0.0
var _was_jumping := false
var _animation_state := "idle"
var _state_elapsed := 0.0
var _state_frame := 0
var _state_frame_count := 1

## These timing tables drive temporary transform poses only. They do not claim
## that missing walk/jump/hit/landing art has been approved as sprite frames.
const TEMPORARY_STATE_DURATIONS := {
	"idle": 0.8,
	"walk": 0.12,
	"jump_rise": 0.16,
	"jump_fall": 0.16,
	"landing": 0.14,
	"hit": 0.12,
	"ko": 1.0,
	"attack1_startup": 0.075,
	"attack1_contact": 0.105,
	"attack1_recovery": 0.20,
	"attack2_startup": 0.085,
	"attack2_contact": 0.12,
	"attack2_recovery": 0.22,
	"attack3_startup": 0.10,
	"attack3_contact": 0.14,
	"attack3_recovery": 0.28,
}

func _ready() -> void:
	if art == null or art.texture == null:
		return
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
	_foot_anchor = _base_position + _alpha_foot_from_center.rotated(_base_rotation)
	_pose_scale = _base_scale
	_was_jumping = player.get("is_jumping") == true

func _process(delta: float) -> void:
	if player == null or art == null or not is_instance_valid(player) or art.texture == null:
		return
	var target_rotation := _base_rotation
	var target_scale := _base_scale
	var jumping: bool = player.get("is_jumping") == true
	if _was_jumping and not jumping:
		_landing_remaining = 0.14
	_was_jumping = jumping
	_landing_remaining = maxf(0.0, _landing_remaining - maxf(delta, 0.0))
	var facing_sign := -1.0 if visual_root.scale.x < 0.0 else 1.0
	_update_animation_clock(_resolve_animation_state(jumping), delta)

	if player.get("is_ko") == true:
		# Settle into a restrained defeated lean, then keep it still.
		target_rotation += facing_sign * 0.12
		target_scale *= Vector2(1.035, 0.91)
	elif float(player.get("hit_flash_remaining")) > 0.0 or float(player.get("hitstun_remaining")) > 0.0:
		var flash := clampf(float(player.get("hit_flash_remaining")) / HIT_FLASH_DURATION, 0.0, 1.0)
		var impulse := signf(player.velocity.x)
		if is_zero_approx(impulse):
			impulse = -facing_sign
		target_rotation -= impulse * (0.10 + flash * 0.08)
		target_scale *= Vector2(1.035 + flash * 0.015, 0.91 + (1.0 - flash) * 0.05)
	elif str(player.get("attack_phase")) != "idle":
		_apply_attack_pose(facing_sign)
		target_rotation = _attack_rotation
		target_scale = _attack_scale
	elif player.get("is_blocking") == true:
		target_rotation -= facing_sign * 0.025
		target_scale *= Vector2(0.975, 1.025)
	elif jumping:
		var vertical_speed := float(player.get("jump_vertical_velocity"))
		if vertical_speed < -1.0:
			target_rotation -= facing_sign * 0.045
			target_scale *= Vector2(0.985, 1.045)
		else:
			target_rotation += facing_sign * 0.055
			target_scale *= Vector2(1.025, 0.955)
	elif _landing_remaining > 0.0:
		var landing := _landing_remaining / 0.14
		var squash := sin(landing * PI)
		target_scale *= Vector2(1.0 + squash * 0.055, 1.0 - squash * 0.075)
		target_rotation += facing_sign * squash * 0.025
	else:
		var speed := player.velocity.length()
		if speed > 10.0:
			var speed_factor := clampf(speed / WALK_SPEED_REFERENCE, 0.35, 1.2)
			_stride_phase = fposmod(_stride_phase + delta * (7.0 + 5.0 * speed_factor), TAU)
			var stride := sin(_stride_phase)
			target_rotation += stride * 0.032 * speed_factor * facing_sign
			target_scale *= Vector2(1.0 - absf(stride) * 0.008, 1.0 + absf(stride) * 0.012)
		else:
			var breath := sin(_state_elapsed * TAU / TEMPORARY_STATE_DURATIONS["idle"])
			target_rotation += breath * 0.004
			target_scale *= Vector2(1.0 + breath * 0.002, 1.0 + breath * 0.003)
	if _animation_state.begins_with("attack") and _state_frame_count > 1:
		# Small timed transform keys are an explicitly temporary stand-in until
		# approved artwork exists for this action's missing in-between frames.
		var frame_wave := sin(TAU * float(_state_frame) / float(_state_frame_count))
		var motion_weight := 1.0 if is_current_pose_temporary() else 0.45
		target_rotation += frame_wave * 0.009 * facing_sign * motion_weight
		target_scale *= Vector2(1.0 + frame_wave * 0.004 * motion_weight, 1.0 - frame_wave * 0.004 * motion_weight)

	var blend := 1.0 - exp(-FOLLOW_SPEED * maxf(delta, 0.0))
	_pose_rotation = lerpf(_pose_rotation, target_rotation, blend)
	_pose_scale = _pose_scale.lerp(target_scale, blend)
	art.rotation = _pose_rotation
	art.scale = _pose_scale
	_keep_foot_anchor()
	_update_approved_attack_pose()

func get_animation_state() -> String:
	return _animation_state

func get_state_elapsed() -> float:
	return _state_elapsed

func get_state_frame() -> int:
	return _state_frame

func get_state_frame_count() -> int:
	return _state_frame_count

func is_current_pose_temporary() -> bool:
	return not _animation_state.begins_with("attack") or not _animation_state.ends_with("_contact")

func get_pose_art_status() -> String:
	if _animation_state.begins_with("attack") and _animation_state.ends_with("_contact"):
		return "approved contact keypose; temporary transform motion"
	if _animation_state.begins_with("attack"):
		return "temporary transform; approved intermediate art unavailable"
	return "temporary transform; approved frame art unavailable"

func _resolve_animation_state(jumping: bool) -> String:
	if player.get("is_ko") == true:
		return "ko"
	if float(player.get("hit_flash_remaining")) > 0.0 or float(player.get("hitstun_remaining")) > 0.0:
		return "hit"
	var phase := str(player.get("attack_phase"))
	var stage := clampi(int(player.get("attack_stage")), 1, 3)
	if phase in ["startup", "active", "recovery"]:
		return "attack%d_%s" % [stage, "contact" if phase == "active" else phase]
	if jumping:
		return "jump_rise" if float(player.get("jump_vertical_velocity")) < -1.0 else "jump_fall"
	if _landing_remaining > 0.0:
		return "landing"
	return "walk" if player.velocity.length() > 10.0 else "idle"

func _update_animation_clock(next_state: String, delta: float) -> void:
	if next_state != _animation_state:
		_animation_state = next_state
		_state_elapsed = 0.0
		_state_frame = 0
		_state_frame_count = 1 if next_state == "ko" else (4 if next_state == "walk" else (ATTACK_TEMPORARY_MOTION_FRAMES if next_state.begins_with("attack") else 2))
	else:
		_state_elapsed += maxf(delta, 0.0)
	var duration: float = TEMPORARY_STATE_DURATIONS.get(_animation_state, 0.16)
	if _animation_state.begins_with("attack"):
		# The combat controller owns this timer. Deriving elapsed time from its
		# remaining value keeps pose keys and the real hitbox window in lockstep,
		# including hit-stop and variable render frame rates.
		var phase_remaining := maxf(0.0, float(player.get("attack_phase_remaining")))
		_state_elapsed = clampf(duration - phase_remaining, 0.0, duration)
	_state_frame = posmod(int(floor(_state_elapsed / maxf(duration / float(_state_frame_count), 0.001))), _state_frame_count)

func _update_approved_attack_pose() -> void:
	if pose_blender == null or player == null or art == null:
		return
	var stage := int(player.get("attack_stage"))
	var phase := str(player.get("attack_phase"))
	var special_attack: bool = player.get("is_ko") != true \
		and float(player.get("hitstun_remaining")) <= 0.0 \
		and (stage >= 1 and stage <= 3) \
		and ["startup", "active", "recovery"].has(phase)
	if not special_attack:
		if pose_blender.visible:
			pose_blender.interrupt_to_idle()
		pose_blender.visible = false
		art.visible = true
		return
	var action := "attack%d" % stage
	var pose_phase := "contact" if phase == "active" else phase
	pose_blender.sync_from_art(art)
	var fade_duration := 0.055
	if pose_phase == "contact":
		fade_duration = [0.060, 0.095, 0.075][stage - 1]
	elif pose_phase == "recovery":
		fade_duration = [0.075, 0.085, 0.10][stage - 1]
	pose_blender.set_pose(action, pose_phase, fade_duration)
	pose_blender.visible = true
	art.visible = false

var _attack_rotation := 0.0
var _attack_scale := Vector2.ONE

func _apply_attack_pose(facing_sign: float) -> void:
	var stage := clampi(int(player.get("attack_stage")), 1, 3)
	var index := stage - 1
	var phase := str(player.get("attack_phase"))
	var remaining := maxf(0.0, float(player.get("attack_phase_remaining")))
	var amount := 0.0
	var rotation_offset := 0.0
	var scale_factor := Vector2.ONE
	match phase:
		"startup":
			var progress := _attack_phase_progress(index, phase, remaining)
			amount = _ease_in_out(progress)
			rotation_offset = facing_sign * [0.045, 0.075, 0.12][index] * amount
			scale_factor = Vector2(1.0 - [0.025, 0.045, 0.075][index] * amount, 1.0 + [0.018, 0.035, 0.065][index] * amount)
		"active":
			var progress := _attack_phase_progress(index, phase, remaining)
			var contact_blend := 1.0 if index != 1 else _ease_in_out(clampf(progress / 0.42, 0.0, 1.0))
			rotation_offset = lerpf(facing_sign * [0.045, 0.075, 0.12][index], -facing_sign * [0.11, 0.19, 0.31][index], contact_blend)
			scale_factor = Vector2.ONE.lerp(Vector2(1.0 + [0.04, 0.075, 0.12][index], 1.0 - [0.035, 0.065, 0.105][index]), contact_blend)
		"recovery":
			amount = _ease_out(clampf(remaining / ATTACK_RECOVERY[index], 0.0, 1.0))
			var recovery_fraction: float = [0.34, 0.30, 0.26][index]
			rotation_offset = -facing_sign * [0.11, 0.19, 0.31][index] * amount * recovery_fraction
			scale_factor = Vector2.ONE.lerp(Vector2(1.0 + [0.04, 0.075, 0.12][index], 1.0 - [0.035, 0.065, 0.105][index]), amount * recovery_fraction)
	_attack_rotation = _base_rotation + rotation_offset
	_attack_scale = _base_scale * scale_factor

func _attack_phase_progress(index: int, phase: String, remaining: float) -> float:
	var duration: float = ATTACK_STARTUP[index] if phase == "startup" else (ATTACK_ACTIVE[index] if phase == "active" else ATTACK_RECOVERY[index])
	return clampf((duration - remaining) / duration, 0.0, 1.0)

func _ease_in_out(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _ease_out(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)

func _keep_foot_anchor() -> void:
	var scaled_foot := Vector2(
		_alpha_foot_from_center.x * (_pose_scale.x / _base_scale.x),
		_alpha_foot_from_center.y * (_pose_scale.y / _base_scale.y)
	)
	art.position = _foot_anchor - scaled_foot.rotated(_pose_rotation - _base_rotation)
