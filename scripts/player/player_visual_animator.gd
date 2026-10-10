extends Node
"""Sprite-only pose layer driven by the owning Player's existing state."""

const ANIMATION_BANK_SCRIPT := preload("res://scripts/player/player_animation_bank.gd")
const BODY_MESH_SCRIPT := preload("res://scripts/player/player_body_mesh.gd")
const SKILL1_DASH_VISUAL_SCRIPT := preload("res://scripts/effects/player_skill1_dash_visual.gd")
const SKILL2_SPIN_VISUAL_SCRIPT := preload("res://scripts/effects/player_skill2_spin_visual.gd")

const FOLLOW_SPEED := 16.0
const WALK_SPEED_REFERENCE := 280.0
const WALK_STRIDE_LENGTH := 235.2
const HIT_FLASH_DURATION := 0.12
const TURN_DURATION := 0.13
const TURN_WINDUP_DURATION := 0.04
const TURN_COMPRESS_DURATION := 0.025
const ATTACK_STARTUP := [0.075, 0.085, 0.10]
const ATTACK_ACTIVE := [0.105, 0.12, 0.14]
const ATTACK_RECOVERY := [0.20, 0.22, 0.28]
const ATTACK_TEMPORARY_MOTION_FRAMES := 5
const SKILL_STARTUP := [0.16, 0.22]
const SKILL_ACTIVE := [0.12, 0.18]
const SKILL_RECOVERY := [0.42, 0.55]
const SKILL_TEMPORARY_MOTION_FRAMES := 6

@onready var player: CharacterBody2D = get_parent() as CharacterBody2D
@onready var art: Sprite2D = player.get_node("VisualRoot/PlayerArt") as Sprite2D
@onready var visual_root: Node2D = player.get_node("VisualRoot") as Node2D
@onready var pose_blender: PlayerPoseBlender = player.get_node("VisualRoot/PoseBlender") as PlayerPoseBlender
@onready var walk_motion: Node = player.get_node_or_null("WalkMotion")

var _base_position := Vector2.ZERO
var _base_scale := Vector2.ONE
var _base_rotation := 0.0
var _combat_anchor := Vector2.ZERO
var _idle_reference_from_center := Vector2.ZERO
var _pose_rotation := 0.0
var _pose_scale := Vector2.ONE
var _pose_translation := Vector2.ZERO
var _stride_phase := 0.0
var _pose_blender_weight := 0.0
var _pose_blender_target_weight := 0.0
var _pose_blender_blend_from := 0.0
var _pose_blender_blend_elapsed := 0.0
var _landing_remaining := 0.0
var _was_jumping := false
var _animation_state := "idle"
var _state_elapsed := 0.0
var _state_frame := 0
var _state_frame_count := 1
var _animation_bank: RefCounted
var _applied_facing_sign := 1.0
var _turn_target_sign := 1.0
var _turn_elapsed := TURN_DURATION
var _turn_flip_applied := false
var _skill1_dash_visual: Node2D
var _skill2_spin_visual: Node2D
var _art_base_modulate := Color.WHITE
var _art_bounds_texture: Texture2D
var _art_alpha_bounds := Rect2i()
var _pose_sprites: Array[Sprite2D] = []
var _pose_bounds: Dictionary = {}
var _body_mesh := BODY_MESH_SCRIPT.new()

## These timing tables drive temporary transform poses only. They do not claim
## that missing walk/jump/hit/landing art has been approved as sprite frames.
const TEMPORARY_STATE_DURATIONS := {
	"idle": 0.8,
	"walk": 0.12,
	"jump_rise": 0.16,
	"jump_fall": 0.16,
	"landing": 0.14,
	"hit": 0.12,
	"ko": 1.10,
	"attack1_startup": 0.075,
	"attack1_inbetween": 0.035,
	"attack1_contact": 0.105,
	"attack1_recovery": 0.20,
	"attack2_startup": 0.085,
	"attack2_inbetween": 0.050,
	"attack2_contact": 0.12,
	"attack2_recovery": 0.22,
	"attack3_startup": 0.10,
	"attack3_inbetween": 0.060,
	"attack3_contact": 0.14,
	"attack3_recovery": 0.28,
	"skill1_startup": 0.16,
	"skill1_contact": 0.12,
	"skill1_recovery": 0.42,
	"skill2_startup": 0.22,
	"skill2_contact": 0.18,
	"skill2_recovery": 0.55,
}

func _ready() -> void:
	# WalkMotion updates its candidate state first; this node resolves the one
	# full-body source that may render for the upcoming frame.
	set_process_priority(2)
	_skill1_dash_visual = SKILL1_DASH_VISUAL_SCRIPT.new()
	_skill1_dash_visual.name = "Skill1DashVisual"
	player.add_child.call_deferred(_skill1_dash_visual)
	if player.has_signal("skill_hit"):
		player.skill_hit.connect(_skill1_dash_visual.on_skill_hit)
	_skill2_spin_visual = SKILL2_SPIN_VISUAL_SCRIPT.new()
	_skill2_spin_visual.name = "Skill2SpinVisual"
	player.add_child.call_deferred(_skill2_spin_visual)
	if player.has_signal("skill_hit"):
		player.skill_hit.connect(_skill2_spin_visual.on_skill_hit)
	if player.has_signal("player_hit"):
		player.player_hit.connect(_skill2_spin_visual.clear_effects)
	if player.has_signal("player_ko"):
		player.player_ko.connect(_skill2_spin_visual.clear_effects)
	_animation_bank = ANIMATION_BANK_SCRIPT.new()
	_animation_bank.load_and_register(pose_blender)
	# Approved contact drawings use pose-specific support candidates. These
	# normalized points select the planted lead shoe in each approved drawing;
	# the sprite mirror selects its counterpart for the opposite facing.
	pose_blender.set_ground_candidate("attack1", "contact", Vector2(0.85, 0.91))
	pose_blender.set_ground_candidate("attack2", "contact", Vector2(0.86, 0.91))
	pose_blender.set_ground_candidate("attack3", "contact", Vector2(0.80, 0.91))
	if art == null or art.texture == null:
		return
	_art_bounds_texture = art.texture
	_art_alpha_bounds = art.texture.get_image().get_used_rect()
	for child in pose_blender.find_children("PoseSprite*", "Sprite2D", false, false):
		var sprite := child as Sprite2D
		if sprite != null:
			_pose_sprites.append(sprite)
	_base_position = art.position
	_base_scale = art.scale
	_base_rotation = art.rotation
	_art_base_modulate = art.modulate
	var texture_size := Vector2(art.texture.get_size())
	var alpha_foot := Vector2(
		float(_art_alpha_bounds.position.x) + float(_art_alpha_bounds.size.x) * 0.5,
		float(_art_alpha_bounds.end.y)
	)
	_idle_reference_from_center = (alpha_foot - texture_size * 0.5) * _base_scale
	_combat_anchor = _base_position + _idle_reference_from_center.rotated(_base_rotation)
	_pose_scale = _base_scale
	_was_jumping = player.get("is_jumping") == true
	_applied_facing_sign = -1.0 if visual_root.scale.x < 0.0 else 1.0
	_turn_target_sign = _applied_facing_sign

func _process(delta: float) -> void:
	if player == null or art == null or not is_instance_valid(player) or art.texture == null:
		return
	if _skill2_spin_visual != null and (
		player.get("is_ko") == true
		or float(player.get("hitstun_remaining")) > 0.0
		or str(player.get("skill_phase")) == "idle"
		or int(player.get("skill_id")) != 2
	):
		_skill2_spin_visual.clear_effects()
	var target_rotation := _base_rotation
	var target_scale := _base_scale
	_pose_translation = Vector2.ZERO
	var jumping: bool = player.get("is_jumping") == true
	if _was_jumping and not jumping:
		_landing_remaining = 0.14
	_was_jumping = jumping
	_landing_remaining = maxf(0.0, _landing_remaining - maxf(delta, 0.0))
	var next_state := _resolve_animation_state(jumping)
	var previous_state := _animation_state
	_update_animation_clock(next_state, delta)
	if previous_state == "walk" and (next_state.begins_with("attack") or next_state.begins_with("skill")):
		_pose_rotation = _base_rotation
		_pose_scale = _base_scale
	if next_state == "walk" and previous_state != "walk":
		_stride_phase = 0.0
	if next_state == "walk" and player.velocity.length() > 10.0:
		_advance_stride_phase(player.velocity.length(), delta)
	var ordinary_motion: bool = next_state in ["idle", "walk"] and player.get("is_blocking") != true
	var turning := _advance_facing_turn(delta, ordinary_motion)
	# VisualRoot performs the mirror once; pose transforms stay in artwork space.
	var facing_sign := 1.0

	if player.get("is_ko") == true:
		# Temporary three-beat fall: stagger, collapse, then a stable side-down.
		# The sprite stays tied to its alpha-foot anchor throughout the movement.
		var fall_progress := clampf(_state_elapsed / TEMPORARY_STATE_DURATIONS["ko"], 0.0, 1.0)
		if fall_progress < 0.18:
			var stagger := _ease_out(fall_progress / 0.18)
			target_rotation += -facing_sign * 0.16 * stagger
			target_scale *= Vector2(0.985, 0.99)
		elif fall_progress < 0.58:
			var collapse := _ease_in_out((fall_progress - 0.18) / 0.40)
			target_rotation += lerpf(-facing_sign * 0.16, facing_sign * 1.28, collapse)
			target_scale *= Vector2(1.0 - collapse * 0.035, 1.0 - collapse * 0.02)
		else:
			var settle := _ease_out((fall_progress - 0.58) / 0.42)
			target_rotation += lerpf(facing_sign * 1.28, facing_sign * 1.38, settle)
			target_scale *= Vector2(0.965, 0.98)
	elif float(player.get("hit_flash_remaining")) > 0.0 or float(player.get("hitstun_remaining")) > 0.0:
		var flash := clampf(float(player.get("hit_flash_remaining")) / HIT_FLASH_DURATION, 0.0, 1.0)
		var impulse := signf(player.velocity.x)
		if is_zero_approx(impulse):
			impulse = -facing_sign
		var stun_ratio := clampf(float(player.get("hitstun_remaining")) / 0.45, 0.0, 1.0)
		target_rotation -= impulse * (0.075 + flash * 0.07 + stun_ratio * 0.045)
		target_scale *= Vector2(1.0 + flash * 0.012, 1.0 - flash * 0.018)
	elif str(player.get("skill_phase")) != "idle":
		_apply_skill_pose(facing_sign)
		target_rotation = _skill_rotation
		target_scale = _skill_scale
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
	elif turning:
		var progress := clampf(_turn_elapsed / TURN_DURATION, 0.0, 1.0)
		if progress < TURN_WINDUP_DURATION / TURN_DURATION:
			var windup := _ease_in_out(progress * TURN_DURATION / TURN_WINDUP_DURATION)
			target_rotation -= _turn_target_sign * 0.105 * windup
			target_scale *= Vector2(1.0 - 0.075 * windup, 1.0 + 0.085 * windup)
		elif progress < (TURN_WINDUP_DURATION + TURN_COMPRESS_DURATION) / TURN_DURATION:
			var compression := _ease_in_out((progress * TURN_DURATION - TURN_WINDUP_DURATION) / TURN_COMPRESS_DURATION)
			target_rotation = _base_rotation + _turn_target_sign * 0.035 * (1.0 - compression)
			target_scale *= Vector2(1.0 - 0.14 * compression, 1.0 + 0.12 * compression)
		else:
			var settle := _ease_out((progress * TURN_DURATION - TURN_WINDUP_DURATION - TURN_COMPRESS_DURATION) / (TURN_DURATION - TURN_WINDUP_DURATION - TURN_COMPRESS_DURATION))
			target_rotation += _turn_target_sign * 0.075 * (1.0 - settle)
			target_scale *= Vector2(1.035 - 0.035 * settle, 0.965 + 0.035 * settle)
	else:
		var speed := player.velocity.length()
		if speed > 10.0:
			var gait := _locomotion_pose(facing_sign, speed)
			target_rotation += float(gait.x)
			target_scale *= Vector2(gait.y, gait.z)
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

	var pose_follow_speed := 42.0 if turning else FOLLOW_SPEED
	var blend := 1.0 - exp(-pose_follow_speed * maxf(delta, 0.0))
	# Combat is already interpolated by the controller phase progress and the
	# local limb rig. A second render-delta filter made physical reach depend on
	# how many Window frames happened during the short active phase.
	if next_state.begins_with("attack") or next_state.begins_with("skill"):
		blend = 1.0
	_pose_rotation = lerpf(_pose_rotation, target_rotation, blend)
	_pose_scale = _pose_scale.lerp(target_scale, blend)
	art.rotation = _pose_rotation
	art.scale = _pose_scale
	_keep_combat_anchor()
	art.position += _pose_translation
	_update_approved_animation_pose(turning)
	_align_pose_support_anchor()
	_update_pose_source_blend(delta)
	var body_phase := str(player.get("skill_phase")) if next_state.begins_with("skill") else str(player.get("attack_phase"))
	var body_stage := int(player.get("skill_id")) if next_state.begins_with("skill") else int(player.get("attack_stage"))
	_body_mesh.apply(_get_visible_combat_sprite(), next_state, body_phase, body_stage, get_state_phase_progress(), _stride_phase)
	for area_name in ["Hitbox1", "Hitbox2", "Hitbox3", "Skill1Hitbox", "Skill2Hitbox"]:
		var area := player.get_node("Hitboxes/" + area_name) as Area2D
		if area.monitoring:
			player.call("_update_fist_hitbox", area)

func get_animation_state() -> String:
	return _animation_state

func sync_combat_pose_for_physics() -> void:
	# Preserve missing-source failure semantics while resolving phase/facing
	# changes that occurred between rendered frames. No animation time advances.
	if _get_visible_combat_sprite() != null:
		_process(0.0)

func get_turn_progress() -> float:
	return clampf(_turn_elapsed / TURN_DURATION, 0.0, 1.0) if _turn_elapsed < TURN_DURATION else 1.0

func is_turning() -> bool:
	return _turn_elapsed < TURN_DURATION

func is_pose_blender_dominant() -> bool:
	return _pose_blender_weight >= 0.5

func get_pose_blender_weight() -> float:
	return _pose_blender_weight

## World-space fist contact from the currently visible Sprite2D. Coordinates
## are authored against the 1254px pose drawings and transformed by the live
## sprite/visual-root transforms, including the horizontal mirror.
func get_fist_contact_global() -> Variant:
	var sprite := _get_visible_combat_sprite()
	if sprite == null or sprite.texture == null:
		return null
	var source_point := _body_mesh.sample_rendered_point(_fist_source_point() + Vector2(627, 627)) - Vector2(627, 627)
	if sprite.flip_h:
		source_point.x = -source_point.x
	var local_point := source_point * (Vector2(sprite.texture.get_size()) / Vector2(1254.0, 1254.0))
	return sprite.to_global(local_point)

func get_articulated_point_global(pixel: Vector2) -> Variant:
	var sprite := _get_visible_combat_sprite()
	if sprite == null or sprite.texture == null:
		return null
	return sprite.to_global((_body_mesh.sample_rendered_point(pixel) - Vector2(627, 627)) * Vector2(sprite.texture.get_size()) / 1254.0)

func _get_visible_combat_sprite() -> Sprite2D:
	if pose_blender != null and pose_blender.is_visible_in_tree() and is_pose_blender_dominant():
		var pose_sprite := pose_blender.get_current_sprite()
		if pose_sprite != null:
			return pose_sprite
	return art if art != null and art.visible else null

func _fist_source_point() -> Vector2:
	var attack_phase := str(player.get("attack_phase"))
	var skill_phase := str(player.get("skill_phase"))
	if attack_phase in ["startup", "active", "recovery", "combo_hold"]:
		var stage := clampi(int(player.get("attack_stage")), 1, 3)
		match stage:
			1:
				return Vector2(510.0, -253.0)
			2:
				return Vector2(430.0, -160.0)
			3:
				return Vector2(319.0, -491.0)
	if skill_phase in ["startup", "active", "recovery"]:
		return Vector2(190.0, -254.0)
	return Vector2(190.0, -254.0)

func _quadratic_point(start: Vector2, control: Vector2, finish: Vector2, progress: float) -> Vector2:
	var t := clampf(progress, 0.0, 1.0)
	return start * (1.0 - t) * (1.0 - t) + control * 2.0 * (1.0 - t) * t + finish * t * t

func _advance_facing_turn(delta: float, allow_turn: bool) -> bool:
	var desired_sign := _applied_facing_sign
	var facing: Vector2 = player.get("facing_direction")
	if absf(facing.x) > 0.1:
		desired_sign = -1.0 if facing.x < 0.0 else 1.0
	if not allow_turn:
		_turn_elapsed = TURN_DURATION
		_turn_flip_applied = false
		_turn_target_sign = desired_sign
		_applied_facing_sign = desired_sign
		visual_root.scale.x = desired_sign
		return false
	if not is_equal_approx(desired_sign, _turn_target_sign) and (is_turning() or not is_equal_approx(desired_sign, _applied_facing_sign)):
		_turn_target_sign = desired_sign
		_turn_elapsed = 0.0
		_turn_flip_applied = false
	if not is_turning() and not is_equal_approx(desired_sign, _applied_facing_sign):
		_turn_target_sign = desired_sign
		_turn_elapsed = 0.0
		_turn_flip_applied = false
	if is_turning():
		var flip_time := TURN_WINDUP_DURATION + TURN_COMPRESS_DURATION
		var next_elapsed := minf(TURN_DURATION, _turn_elapsed + maxf(delta, 0.0))
		if not _turn_flip_applied and _turn_elapsed < flip_time and next_elapsed >= flip_time:
			_applied_facing_sign = _turn_target_sign
			_turn_flip_applied = true
		_turn_elapsed = next_elapsed
		visual_root.scale.x = _applied_facing_sign
		return true
	_applied_facing_sign = desired_sign
	visual_root.scale.x = _applied_facing_sign
	return false

func get_state_elapsed() -> float:
	return _state_elapsed

func is_final_down_settled() -> bool:
	return _animation_state == "ko" and _state_elapsed >= float(TEMPORARY_STATE_DURATIONS["ko"])

func get_state_frame() -> int:
	return _state_frame

func get_state_frame_count() -> int:
	return _state_frame_count

func get_state_frame_label() -> String:
	if _animation_state.begins_with("skill"):
		return _animation_state.trim_prefix("skill%d_" % int(player.get("skill_id")))
	if not _animation_state.begins_with("attack"):
		return _animation_state
	var phase := _animation_state.trim_prefix("attack%d_" % int(player.get("attack_stage")))
	if phase == "contact" and int(player.get("attack_stage")) == 2 and get_state_phase_progress() < 0.42:
		return "inbetween"
	return phase

func get_state_phase_progress() -> float:
	if _animation_state.begins_with("skill") and player != null:
		var skill_index := clampi(int(player.get("skill_id")) - 1, 0, 1)
		var phase := str(player.get("skill_phase"))
		return _skill_phase_progress(skill_index, phase, maxf(0.0, float(player.get("skill_phase_remaining"))))
	if not _animation_state.begins_with("attack") or player == null:
		return 0.0
	var phase := str(player.get("attack_phase"))
	var stage_index := clampi(int(player.get("attack_stage")) - 1, 0, 2)
	return _attack_phase_progress(stage_index, phase, maxf(0.0, float(player.get("attack_phase_remaining"))))

func get_state_frame_duration() -> float:
	var phase_duration := float(TEMPORARY_STATE_DURATIONS.get(_animation_state, 0.16))
	return phase_duration / float(maxi(_state_frame_count, 1))

func get_state_frame_elapsed() -> float:
	var frame_duration := get_state_frame_duration()
	return clampf(_state_elapsed - float(_state_frame) * frame_duration, 0.0, frame_duration)

func get_state_frame_status() -> String:
	if _animation_state.begins_with("skill"):
		return "temporary procedural skill motion; approved skill animation art unavailable"
	if get_state_frame_label() == "inbetween":
		if pose_blender != null and pose_blender.get_current_pose_key() == "attack2_inbetween":
			return pose_blender.get_pose_art_status()
		return "approved contact keypose; temporary inbetween transform"
	if _animation_state.begins_with("attack"):
		return get_pose_art_status()
	if is_current_pose_temporary():
		return "temporary transform frame; approved animation frame unavailable"
	return pose_blender.get_current_frame_status() if pose_blender != null else "approved contact keypose"

func get_displayed_texture_path() -> String:
	if pose_blender != null and is_pose_blender_dominant():
		return pose_blender.get_current_texture_path()
	return art.texture.resource_path if art != null and art.texture != null else ""

func get_art_frame_index() -> int:
	return pose_blender.get_current_registered_frame() if pose_blender != null and is_pose_blender_dominant() else 0

func get_art_frame_count() -> int:
	return pose_blender.get_current_registered_frame_count() if pose_blender != null and is_pose_blender_dominant() else 1

func get_art_frame_duration() -> float:
	return pose_blender.get_current_registered_frame_duration() if pose_blender != null and is_pose_blender_dominant() else get_state_frame_duration()

func get_art_frame_elapsed() -> float:
	return pose_blender.get_current_registered_frame_elapsed() if pose_blender != null and is_pose_blender_dominant() else get_state_frame_elapsed()

func get_art_frame_label() -> String:
	return pose_blender.get_current_registered_frame_label() if pose_blender != null and is_pose_blender_dominant() else "temporary transform"

func is_current_pose_temporary() -> bool:
	if _approved_pose_is_displayed("turn", "turn"):
		return false
	if _animation_state.begins_with("skill"):
		return not _approved_pose_is_displayed("skill%d" % int(player.get("skill_id")), _normalized_phase(str(player.get("skill_phase"))))
	if _animation_state == "walk":
		return not _approved_pose_is_displayed("run", "stride")
	if _animation_state == "jump_rise":
		return not _approved_pose_is_displayed("jump_rise", "rise")
	if _animation_state == "jump_fall":
		return not _approved_pose_is_displayed("jump_fall", "fall")
	if _animation_state == "hit":
		return not _approved_pose_is_displayed("hit", "reaction")
	if _animation_state.begins_with("attack") and pose_blender != null and is_pose_blender_dominant():
		var stage := int(player.get("attack_stage"))
		var raw_phase := str(player.get("attack_phase"))
		var phase := "contact" if raw_phase in ["active", "combo_hold"] else raw_phase
		var expected_key := "attack%d_%s" % [stage, phase]
		if pose_blender.get_current_pose_key() == expected_key and pose_blender.get_current_frame_status().begins_with("approved"):
			return false
		return true
	return true

func get_pose_art_status() -> String:
	if _approved_pose_is_displayed("turn", "turn"):
		return pose_blender.get_pose_art_status()
	if _animation_state.begins_with("skill"):
		return _current_art_status("skill%d" % int(player.get("skill_id")), _normalized_phase(str(player.get("skill_phase"))), "temporary procedural skill motion; approved skill animation art unavailable")
	if _animation_state == "walk":
		return _current_art_status("run", "stride", "temporary procedural stride; approved run frames unavailable")
	if _animation_state in ["jump_rise", "jump_fall", "hit"]:
		var action := "jump_rise" if _animation_state == "jump_rise" else ("jump_fall" if _animation_state == "jump_fall" else "hit")
		var phase := "rise" if _animation_state == "jump_rise" else ("fall" if _animation_state == "jump_fall" else "reaction")
		return _current_art_status(action, phase, "temporary procedural %s; approved frames unavailable" % _animation_state)
	if _animation_state.begins_with("attack") and _animation_state.ends_with("_contact"):
		if _approved_pose_is_displayed("attack%d" % int(player.get("attack_stage")), "contact"):
			return "approved contact keypose with temporary procedural transform; not an approved frame sequence"
		return "temporary procedural contact transform; approved contact keypose unavailable"
	if _animation_state.begins_with("attack"):
		return "temporary procedural transform; approved intermediate frame unavailable"
	return "temporary transform; approved frame art unavailable"

func _resolve_animation_state(jumping: bool) -> String:
	if player.get("is_ko") == true:
		return "ko"
	if float(player.get("hit_flash_remaining")) > 0.0 or float(player.get("hitstun_remaining")) > 0.0:
		return "hit"
	var skill_phase := str(player.get("skill_phase"))
	if skill_phase in ["startup", "active", "recovery"]:
		var skill_id := clampi(int(player.get("skill_id")), 1, 2)
		return "skill%d_%s" % [skill_id, "contact" if skill_phase == "active" else skill_phase]
	var phase := str(player.get("attack_phase"))
	var stage := clampi(int(player.get("attack_stage")), 1, 3)
	if phase in ["startup", "active", "recovery", "combo_hold"]:
		return "attack%d_%s" % [stage, "contact" if phase in ["active", "combo_hold"] else phase]
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
		_state_frame_count = 3 if next_state == "ko" else (SKILL_TEMPORARY_MOTION_FRAMES if next_state.begins_with("skill") else (4 if next_state == "walk" else (ATTACK_TEMPORARY_MOTION_FRAMES if next_state.begins_with("attack") else 2)))
	else:
		_state_elapsed += maxf(delta, 0.0)
	var duration: float = TEMPORARY_STATE_DURATIONS.get(_animation_state, 0.16)
	if _animation_state.begins_with("attack"):
		# The combat controller owns this timer. Deriving elapsed time from its
		# remaining value keeps pose keys and the real hitbox window in lockstep,
		# including hit-stop and variable render frame rates.
		var phase := str(player.get("attack_phase"))
		var phase_remaining := maxf(0.0, float(player.get("attack_phase_remaining")))
		if phase == "combo_hold":
			_state_elapsed = duration
		else:
			_state_elapsed = clampf(duration - phase_remaining, 0.0, duration)
	elif _animation_state.begins_with("skill"):
		# The skill controller owns this timer; use it directly so visual frames
		# stay aligned with startup, active hitbox, and recovery transitions.
		var skill_index := clampi(int(player.get("skill_id")) - 1, 0, 1)
		var skill_phase := str(player.get("skill_phase"))
		var skill_duration := _skill_phase_duration(skill_index, skill_phase)
		_state_elapsed = clampf(skill_duration - maxf(0.0, float(player.get("skill_phase_remaining"))), 0.0, skill_duration)
	_state_frame = posmod(int(floor(_state_elapsed / maxf(duration / float(_state_frame_count), 0.001))), _state_frame_count)

func _update_approved_animation_pose(turning := false) -> void:
	if pose_blender == null or player == null or art == null:
		return
	# The integrated blender is a child of VisualRoot, whose negative X scale
	# already mirrors the pose. Keep its local sprite unflipped to avoid doubling it.
	pose_blender.set_facing_left(false)
	var action := ""
	var pose_phase := ""
	var phase_elapsed := 0.0
	var phase_duration := 0.0
	var fade_duration := 0.055
	var looping := false
	# _resolve_animation_state is the single priority authority. Re-checking raw
	# controller fields here used to let an attack pose win over the hit-flash
	# state for a render frame after hitstun expired (and while the hit flash was
	# still visible). That made the interrupted pose briefly reappear.
	var stage := int(player.get("attack_stage"))
	var attack_phase := str(player.get("attack_phase"))
	var skill_phase := str(player.get("skill_phase"))
	if _animation_state.begins_with("attack") and stage in [1, 2, 3] and attack_phase in ["startup", "active", "recovery", "combo_hold"]:
		action = "attack%d" % stage
		# Keep each attack's distinct approved contact drawing through startup,
		# impact, link hold, and recovery. Missing phase art must not show the idle
		# still while the attack state owns the body.
		pose_phase = "contact"
		if stage == 2 and attack_phase == "active" and _attack_phase_progress(stage - 1, attack_phase, float(player.get("attack_phase_remaining"))) < 0.42 and pose_blender.get_registered_frame_count(action, "inbetween") > 0:
			pose_phase = "inbetween"
		phase_duration = _attack_phase_duration(stage - 1, attack_phase)
		phase_elapsed = phase_duration if attack_phase == "combo_hold" else maxf(0.0, phase_duration - float(player.get("attack_phase_remaining")))
		if pose_phase == "startup":
			fade_duration = [0.060, 0.105, 0.115][stage - 1]
		elif pose_phase == "contact":
			fade_duration = [0.060, 0.125, 0.105][stage - 1]
		elif pose_phase == "recovery":
			fade_duration = [0.075, 0.12, 0.135][stage - 1]
	elif _animation_state.begins_with("skill") and skill_phase in ["startup", "active", "recovery"]:
		var skill_id := clampi(int(player.get("skill_id")), 1, 2)
		action = "skill%d" % skill_id
		pose_phase = _normalized_phase(skill_phase)
		phase_duration = _skill_phase_duration(skill_id - 1, skill_phase)
		phase_elapsed = maxf(0.0, phase_duration - float(player.get("skill_phase_remaining")))
	elif _animation_state == "hit":
		action = "hit"
		pose_phase = "reaction"
		phase_duration = float(TEMPORARY_STATE_DURATIONS["hit"])
		phase_elapsed = _state_elapsed
	elif turning and _animation_state in ["idle", "walk"]:
		action = "turn"
		pose_phase = "turn"
		phase_duration = TURN_DURATION
		phase_elapsed = minf(_turn_elapsed, TURN_DURATION)
	elif _animation_state == "walk":
		action = "run"
		pose_phase = "stride"
		phase_duration = _animation_bank.get_phase_duration(action, pose_phase, 0.0) if _animation_bank != null else 0.0
		phase_elapsed = _state_elapsed
		looping = true
	elif _animation_state == "jump_rise":
		action = "jump_rise"
		pose_phase = "rise"
		phase_duration = float(TEMPORARY_STATE_DURATIONS["jump_rise"])
		phase_elapsed = _state_elapsed
	elif _animation_state == "jump_fall":
		action = "jump_fall"
		pose_phase = "fall"
		phase_duration = float(TEMPORARY_STATE_DURATIONS["jump_fall"])
		phase_elapsed = _state_elapsed
	if action.is_empty() or pose_blender.get_registered_frame_count(action, pose_phase) == 0:
		_set_pose_blender_target(0.0)
		return
	pose_blender.sync_from_art(art)
	if attack_phase == "combo_hold" and action.begins_with("attack") and pose_phase == "contact":
		pose_blender.hold_phase_end_pose(action, pose_phase, 0.0)
	else:
		pose_blender.set_timed_pose(action, pose_phase, phase_elapsed, maxf(phase_duration, 0.001), fade_duration, looping)
	_set_pose_blender_target(1.0)

func _set_pose_blender_target(weight: float) -> void:
	if is_equal_approx(_pose_blender_target_weight, weight):
		return
	_pose_blender_blend_from = _pose_blender_weight
	_pose_blender_blend_elapsed = 0.0
	_pose_blender_target_weight = weight

func _update_pose_source_blend(delta: float) -> void:
	if pose_blender == null or art == null:
		return
	# A full-body drawing is an exclusive source. Changing state is an atomic
	# silhouette swap; opacity is never used to blend separate bodies.
	_pose_blender_weight = _pose_blender_target_weight
	_pose_blender_blend_from = _pose_blender_weight
	_pose_blender_blend_elapsed = 0.0
	var pose_selected := _pose_blender_target_weight >= 0.5
	var walk_sprite: Sprite2D
	var debug_walk_selected := false
	if walk_motion != null and walk_motion.has_method("get_candidate_sprite"):
		walk_sprite = walk_motion.call("get_candidate_sprite") as Sprite2D
		debug_walk_selected = (
			OS.is_debug_build()
			and _animation_state == "walk"
			and walk_motion.has_method("is_candidate_active")
			and bool(walk_motion.call("is_candidate_active"))
			and walk_sprite != null
			and walk_sprite.texture != null
		)
	if walk_sprite != null:
		walk_sprite.visible = debug_walk_selected
	pose_blender.visible = pose_selected and not debug_walk_selected
	art.visible = not pose_selected and not debug_walk_selected
	pose_blender.set_external_blend_weight(1.0)
	var art_modulate := _art_base_modulate
	art.modulate = art_modulate

func _align_pose_support_anchor() -> void:
	if pose_blender == null or art == null or art.texture == null:
		return
	if art.texture != _art_bounds_texture:
		_art_bounds_texture = art.texture
		_art_alpha_bounds = art.texture.get_image().get_used_rect()
	if _art_alpha_bounds.size == Vector2i.ZERO:
		return
	var bounds := _art_alpha_bounds
	var art_foot_local := Vector2(
		float(bounds.position.x) + float(bounds.size.x) * 0.5,
		float(bounds.end.y)
	) - Vector2(art.texture.get_size()) * 0.5
	if art.flip_h:
		art_foot_local.x = -art_foot_local.x
	var art_foot_global := art.to_global(art_foot_local)
	for sprite in _pose_sprites:
		if sprite == null or sprite.texture == null:
			continue
		var action := ""
		for candidate_action in PlayerPoseBlender.APPROVED_ATTACK_POSES:
			if sprite.texture.resource_path == str(PlayerPoseBlender.APPROVED_ATTACK_POSES[candidate_action]):
				action = candidate_action
				break
		if action.is_empty():
			continue
		var support := pose_blender.get_ground_candidate(action, "contact")
		if support.x < 0.0 or support.y < 0.0:
			continue
		# Root represents the stance centre, not the lead shoe. Pinning the forward
		# shoe to root used to put the actual hand behind the collision capsule.
		var texture_key := sprite.texture.get_instance_id()
		if not _pose_bounds.has(texture_key):
			_pose_bounds[texture_key] = sprite.texture.get_image().get_used_rect()
		var pose_bounds: Rect2i = _pose_bounds[texture_key]
		var support_local := Vector2(float(pose_bounds.position.x) + float(pose_bounds.size.x) * 0.5, support.y * sprite.texture.get_height()) - Vector2(sprite.texture.get_size()) * 0.5
		if sprite.flip_h:
			support_local.x = -support_local.x
		var scaled_support := Vector2(support_local.x * sprite.scale.x, support_local.y * sprite.scale.y).rotated(sprite.rotation)
		# Preserve drawing height at the shared stance centre. Individual shoes
		# retain their authored lateral offsets instead of moving the whole body
		# backwards to put the lead shoe at root.
		sprite.position = pose_blender.to_local(art_foot_global) - scaled_support

func progress_is_complete() -> bool:
	return true

func _advance_stride_phase(speed: float, delta: float) -> void:
	# A full cycle is one left/right step pair. Cadence follows traveled distance,
	# while the procedural transform remains explicitly temporary artwork.
	_stride_phase = fposmod(_stride_phase + maxf(delta, 0.0) * speed / WALK_STRIDE_LENGTH * TAU, TAU)

func _locomotion_pose(facing_sign: float, speed: float) -> Vector3:
	var speed_weight := clampf(speed / WALK_SPEED_REFERENCE, 0.25, 1.25)
	var stride := sin(_stride_phase)
	var contact := absf(cos(_stride_phase))
	# Alternating half-cycle weight shifts make each planted side read distinctly;
	# the alpha-foot anchor is reapplied after the transform below.
	var alternating_lean := stride * 0.046 * speed_weight * facing_sign
	var torso_recoil := signf(cos(_stride_phase)) * 0.012 * speed_weight * facing_sign
	# The two passing peaks between alternating contacts lift the pelvis through
	# vertical stretch; alpha-foot re-anchoring keeps the support point planted.
	var vertical_bounce := absf(stride) * 0.032 * speed_weight
	var planted_compression := contact * 0.018 * speed_weight
	return Vector3(alternating_lean + torso_recoil, 1.0 - planted_compression, 1.0 + vertical_bounce)

func _approved_pose_is_displayed(action: String, phase: String) -> bool:
	return pose_blender != null and is_pose_blender_dominant() and pose_blender.get_current_pose_key() == action + "_" + phase and pose_blender.get_current_frame_status().begins_with("approved")

func _current_art_status(action: String, phase: String, fallback: String) -> String:
	return pose_blender.get_pose_art_status() if _approved_pose_is_displayed(action, phase) else fallback

func _normalized_phase(phase: String) -> String:
	return "contact" if phase == "active" else phase

var _attack_rotation := 0.0
var _attack_scale := Vector2.ONE
var _skill_rotation := 0.0
var _skill_scale := Vector2.ONE

func _apply_skill_pose(facing_sign: float) -> void:
	var skill_index := clampi(int(player.get("skill_id")) - 1, 0, 1)
	var phase := str(player.get("skill_phase"))
	var remaining := maxf(0.0, float(player.get("skill_phase_remaining")))
	var progress := _skill_phase_progress(skill_index, phase, remaining)
	var rotation_offset := 0.0
	var scale_factor := Vector2.ONE
	if skill_index == 0:
		# Num4 dash: brace and shift weight forward, accelerate into contact,
		# recoil from impact when hit-stop/knockback is active, then recover.
		match phase:
			"startup":
				var brace := _ease_in_out(progress)
				rotation_offset = facing_sign * 0.18 * brace
				scale_factor = Vector2(1.0 - 0.035 * brace, 1.0 + 0.045 * brace)
				_pose_translation.x = -facing_sign * 5.0 * brace
			"active":
				var acceleration := _ease_in_out(progress)
				rotation_offset = facing_sign * lerpf(0.08, 0.15, acceleration)
				scale_factor = Vector2(1.02 + 0.045 * acceleration, 1.0 - 0.035 * acceleration)
				_pose_translation.x = facing_sign * lerpf(7.0, 22.0, acceleration)
				if float(player.get("attack_recoil_remaining")) > 0.0:
					var recoil := clampf(float(player.get("attack_recoil_remaining")) / 0.08, 0.0, 1.0)
					rotation_offset -= facing_sign * 0.30 * recoil
					scale_factor *= Vector2(0.98, 1.02)
			"recovery":
				var return_blend := _ease_in_out(progress)
				rotation_offset = facing_sign * 0.18 * (1.0 - return_blend)
				scale_factor = Vector2(0.975, 1.025).lerp(Vector2.ONE, return_blend)
				_pose_translation.x = facing_sign * 9.0 * (1.0 - return_blend)
	else:
		# Num5 backfist: counter-twist through the strike and step the upper-body
		# silhouette through a bounded arc. The single full-body source cannot
		# articulate the torso independently, so recovery unwinds before the legs
		# rotate past a readable upright pose.
		match phase:
			"startup":
				var windup := _ease_in_out(progress)
				rotation_offset = facing_sign * 0.16 * windup
				scale_factor = Vector2(1.0 - 0.03 * windup, 1.0 + 0.04 * windup)
				_pose_translation = Vector2(-facing_sign * 4.0, 2.0) * windup
			"active":
				rotation_offset = facing_sign * lerpf(0.16, -0.32, _ease_in_out(progress))
				var pulse := sin(progress * PI)
				scale_factor = Vector2(1.0 + 0.035 * pulse, 1.0 - 0.03 * pulse)
				_pose_translation = Vector2(facing_sign * (9.0 + 9.0 * pulse), -3.0 * pulse)
			"recovery":
				var unwind := _ease_in_out(progress)
				rotation_offset = facing_sign * lerpf(-0.32, 0.0, unwind)
				scale_factor = Vector2(1.012, 0.988).lerp(Vector2.ONE, _ease_in_out(progress))
				_pose_translation = Vector2(facing_sign * 8.0 * (1.0 - unwind), -2.0 * (1.0 - unwind))
	_skill_rotation = _base_rotation + rotation_offset
	_skill_scale = _base_scale * scale_factor

func _skill_phase_progress(index: int, phase: String, remaining: float) -> float:
	var duration := _skill_phase_duration(index, phase)
	return clampf((duration - remaining) / duration, 0.0, 1.0)

func _skill_phase_duration(index: int, phase: String) -> float:
	if phase == "startup":
		return SKILL_STARTUP[index]
	if phase == "active":
		return SKILL_ACTIVE[index]
	return SKILL_RECOVERY[index]

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
			rotation_offset = facing_sign * [0.07, 0.11, 0.17][index] * amount
			scale_factor = Vector2(1.0 - [0.02, 0.028, 0.04][index] * amount, 1.0 + [0.025, 0.035, 0.05][index] * amount)
			_pose_translation = Vector2(-facing_sign * [5.0, 8.0, 11.0][index] * amount, 2.0 * amount)
		"active":
			var progress := _attack_phase_progress(index, phase, remaining)
			var contact_blend := 1.0 if index != 1 else _ease_in_out(clampf(progress / 0.42, 0.0, 1.0))
			rotation_offset = lerpf(facing_sign * [0.07, 0.11, 0.17][index], -facing_sign * [0.19, 0.30, 0.25][index], contact_blend)
			scale_factor = Vector2.ONE.lerp(Vector2(1.0 + [0.025, 0.04, 0.055][index], 1.0 - [0.02, 0.035, 0.05][index]), contact_blend)
			_pose_translation = Vector2(facing_sign * [8.0, 12.0, 17.0][index] * contact_blend, -2.0 * contact_blend)
		"recovery":
			var recovery_progress := 1.0 - clampf(remaining / ATTACK_RECOVERY[index], 0.0, 1.0)
			var return_blend := _ease_in_out(recovery_progress)
			rotation_offset = -facing_sign * [0.19, 0.30, 0.25][index] * (1.0 - return_blend)
			scale_factor = Vector2(1.0 + [0.025, 0.04, 0.055][index], 1.0 - [0.02, 0.035, 0.05][index]).lerp(Vector2.ONE, return_blend)
			_pose_translation = Vector2(facing_sign * [11.0, 15.0, 20.0][index] * (1.0 - return_blend), 0.0)
		"combo_hold":
			rotation_offset = 0.0
			scale_factor = Vector2.ONE
			_pose_translation = Vector2.ZERO
	_attack_rotation = _base_rotation + rotation_offset
	_attack_scale = _base_scale * scale_factor

func _attack_phase_progress(index: int, phase: String, remaining: float) -> float:
	var duration := _attack_phase_duration(index, phase)
	return clampf((duration - remaining) / duration, 0.0, 1.0)

func _attack_phase_duration(index: int, phase: String) -> float:
	# Gameplay owns these phase boundaries. Registered frame durations are mapped
	# across this live window, so adding reviewed art cannot shift startup, the
	# active hitbox, or recovery away from the controller's timers.
	return ATTACK_STARTUP[index] if phase == "startup" else (ATTACK_ACTIVE[index] if phase in ["active", "combo_hold"] else ATTACK_RECOVERY[index])

func _ease_in_out(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _ease_out(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)

func _keep_combat_anchor() -> void:
	var scaled_foot := Vector2(
		_idle_reference_from_center.x * (_pose_scale.x / _base_scale.x),
		_idle_reference_from_center.y * (_pose_scale.y / _base_scale.y)
	)
	art.position = _combat_anchor - scaled_foot.rotated(_pose_rotation - _base_rotation)
