extends Node
"""Sprite-only pose layer driven by the owning Player's existing state."""

const ANIMATION_BANK_SCRIPT := preload("res://scripts/player/player_animation_bank.gd")
const SKILL1_DASH_VISUAL_SCRIPT := preload("res://scripts/effects/player_skill1_dash_visual.gd")
const SKILL2_SPIN_VISUAL_SCRIPT := preload("res://scripts/effects/player_skill2_spin_visual.gd")

const FOLLOW_SPEED := 16.0
const WALK_SPEED_REFERENCE := 280.0
const WALK_STRIDE_LENGTH := 76.0
const POSE_SOURCE_BLEND_DURATION := 0.105
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

var _base_position := Vector2.ZERO
var _base_scale := Vector2.ONE
var _base_rotation := 0.0
var _combat_anchor := Vector2.ZERO
var _idle_reference_from_center := Vector2.ZERO
var _pose_rotation := 0.0
var _pose_scale := Vector2.ONE
var _stride_phase := 0.0
var _pose_blender_weight := 0.0
var _pose_blender_target_weight := 0.0
var _pose_blender_blend_from := 0.0
var _pose_blender_blend_elapsed := POSE_SOURCE_BLEND_DURATION
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
	var jumping: bool = player.get("is_jumping") == true
	if _was_jumping and not jumping:
		_landing_remaining = 0.14
	_was_jumping = jumping
	_landing_remaining = maxf(0.0, _landing_remaining - maxf(delta, 0.0))
	var next_state := _resolve_animation_state(jumping)
	_update_animation_clock(next_state, delta)
	if player.velocity.length() > 10.0 and next_state not in ["ko", "hit", "jump_rise", "jump_fall", "landing"] and not next_state.begins_with("skill"):
		_advance_stride_phase(player.velocity.length(), delta)
	var ordinary_motion: bool = next_state in ["idle", "walk"] and player.get("is_blocking") != true
	var turning := _advance_facing_turn(delta, ordinary_motion)
	var facing_sign := _applied_facing_sign

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
	_pose_rotation = lerpf(_pose_rotation, target_rotation, blend)
	_pose_scale = _pose_scale.lerp(target_scale, blend)
	art.rotation = _pose_rotation
	art.scale = _pose_scale
	_keep_combat_anchor()
	_update_approved_animation_pose(turning)
	_align_pose_support_anchor()
	_update_pose_source_blend(delta)

func get_animation_state() -> String:
	return _animation_state

func get_turn_progress() -> float:
	return clampf(_turn_elapsed / TURN_DURATION, 0.0, 1.0) if _turn_elapsed < TURN_DURATION else 1.0

func is_turning() -> bool:
	return _turn_elapsed < TURN_DURATION

func is_pose_blender_dominant() -> bool:
	return _pose_blender_weight >= 0.5

func get_pose_blender_weight() -> float:
	return _pose_blender_weight

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
		var phase := "contact" if str(player.get("attack_phase")) == "active" else str(player.get("attack_phase"))
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
		_state_frame_count = 3 if next_state == "ko" else (SKILL_TEMPORARY_MOTION_FRAMES if next_state.begins_with("skill") else (4 if next_state == "walk" else (ATTACK_TEMPORARY_MOTION_FRAMES if next_state.begins_with("attack") else 2)))
	else:
		_state_elapsed += maxf(delta, 0.0)
	var duration: float = TEMPORARY_STATE_DURATIONS.get(_animation_state, 0.16)
	if _animation_state.begins_with("attack"):
		# The combat controller owns this timer. Deriving elapsed time from its
		# remaining value keeps pose keys and the real hitbox window in lockstep,
		# including hit-stop and variable render frame rates.
		var phase_remaining := maxf(0.0, float(player.get("attack_phase_remaining")))
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
	if _animation_state.begins_with("attack") and stage in [1, 2, 3] and attack_phase in ["startup", "active", "recovery"]:
		action = "attack%d" % stage
		pose_phase = "contact" if attack_phase == "active" else attack_phase
		if stage == 2 and attack_phase == "active" and _attack_phase_progress(stage - 1, attack_phase, float(player.get("attack_phase_remaining"))) < 0.42 and pose_blender.get_registered_frame_count(action, "inbetween") > 0:
			pose_phase = "inbetween"
		phase_duration = _attack_phase_duration(stage - 1, attack_phase)
		phase_elapsed = maxf(0.0, phase_duration - float(player.get("attack_phase_remaining")))
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
	if not is_equal_approx(_pose_blender_weight, _pose_blender_target_weight):
		_pose_blender_blend_elapsed = minf(POSE_SOURCE_BLEND_DURATION, _pose_blender_blend_elapsed + maxf(delta, 0.0))
		var progress := clampf(_pose_blender_blend_elapsed / POSE_SOURCE_BLEND_DURATION, 0.0, 1.0)
		# Keep the layer opacity change proportional to elapsed render time. A
		# cubic curve concentrates the 105 ms handoff into fewer visible steps
		# when Window rendering runs below 60 fps.
		_pose_blender_weight = lerpf(_pose_blender_blend_from, _pose_blender_target_weight, progress)
	if progress_is_complete():
		_pose_blender_weight = _pose_blender_target_weight
	var weight := clampf(_pose_blender_weight, 0.0, 1.0)
	pose_blender.visible = weight > 0.001 or _pose_blender_target_weight > 0.0
	art.visible = weight < 0.999
	pose_blender.set_external_blend_weight(weight)
	var art_modulate := _art_base_modulate
	art_modulate.a *= 1.0 - weight
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
		var support_local := support * Vector2(sprite.texture.get_size()) - Vector2(sprite.texture.get_size()) * 0.5
		if sprite.flip_h:
			support_local.x = -support_local.x
		var scaled_support := Vector2(support_local.x * sprite.scale.x, support_local.y * sprite.scale.y).rotated(sprite.rotation)
		# The pose-specific shoe point is the intended planted support point. Keep
		# it at the same world anchor as PlayerArt while preserving the outgoing
		# and incoming sprites in the blender's internal crossfade.
		sprite.position = pose_blender.to_local(art_foot_global) - scaled_support

func progress_is_complete() -> bool:
	return _pose_blender_blend_elapsed >= POSE_SOURCE_BLEND_DURATION

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
	var vertical_bounce := absf(stride) * 0.018 * speed_weight
	var planted_compression := contact * 0.012 * speed_weight
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
				rotation_offset = facing_sign * 0.15 * brace
				scale_factor = Vector2(1.0 - 0.025 * brace, 1.0 + 0.03 * brace)
			"active":
				var acceleration := _ease_in_out(progress)
				rotation_offset = facing_sign * lerpf(0.22, 0.38, acceleration)
				scale_factor = Vector2(1.015 + 0.035 * acceleration, 1.0 - 0.025 * acceleration)
				if float(player.get("attack_recoil_remaining")) > 0.0:
					var recoil := clampf(float(player.get("attack_recoil_remaining")) / 0.08, 0.0, 1.0)
					rotation_offset -= facing_sign * 0.30 * recoil
					scale_factor *= Vector2(0.98, 1.02)
			"recovery":
				var return_blend := _ease_in_out(progress)
				rotation_offset = facing_sign * 0.16 * (1.0 - return_blend)
				scale_factor = Vector2(0.985, 1.015).lerp(Vector2.ONE, return_blend)
	else:
		# Num5 backfist: keep the support pivot planted and counter-twist through
		# the strike. The single full-body source cannot articulate the torso, so
		# use a bounded lean instead of rotating the entire silhouette through a
		# full turn and sending the legs upside down during recovery.
		match phase:
			"startup":
				var windup := _ease_in_out(progress)
				rotation_offset = facing_sign * 0.14 * windup
				scale_factor = Vector2(1.0 - 0.02 * windup, 1.0 + 0.025 * windup)
			"active":
				rotation_offset = facing_sign * lerpf(0.14, -0.62, _ease_in_out(progress))
				var pulse := sin(progress * PI)
				scale_factor = Vector2(1.0 + 0.025 * pulse, 1.0 - 0.02 * pulse)
			"recovery":
				var unwind := _ease_in_out(progress)
				rotation_offset = facing_sign * lerpf(-0.62, 0.0, unwind)
				scale_factor = Vector2(1.012, 0.988).lerp(Vector2.ONE, _ease_in_out(progress))
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
			rotation_offset = facing_sign * [0.045, 0.075, 0.12][index] * amount
			scale_factor = Vector2(1.0 - [0.012, 0.018, 0.025][index] * amount, 1.0 + [0.01, 0.014, 0.018][index] * amount)
		"active":
			var progress := _attack_phase_progress(index, phase, remaining)
			var contact_blend := 1.0 if index != 1 else _ease_in_out(clampf(progress / 0.42, 0.0, 1.0))
			rotation_offset = lerpf(facing_sign * [0.045, 0.075, 0.12][index], -facing_sign * [0.14, 0.24, 0.38][index], contact_blend)
			scale_factor = Vector2.ONE.lerp(Vector2(1.0 + [0.015, 0.025, 0.035][index], 1.0 - [0.012, 0.02, 0.028][index]), contact_blend)
		"recovery":
			var recovery_progress := 1.0 - clampf(remaining / ATTACK_RECOVERY[index], 0.0, 1.0)
			var return_blend := _ease_in_out(recovery_progress)
			rotation_offset = -facing_sign * [0.14, 0.24, 0.38][index] * (1.0 - return_blend)
			scale_factor = Vector2(1.0 + [0.015, 0.025, 0.035][index], 1.0 - [0.012, 0.02, 0.028][index]).lerp(Vector2.ONE, return_blend)
	var gait_weight := 0.0
	if player.velocity.length() > 10.0:
		match phase:
			"startup":
				gait_weight = 1.0 - _ease_in_out(_attack_phase_progress(index, phase, remaining))
			"active":
				gait_weight = 1.0 - _ease_in_out(clampf(_attack_phase_progress(index, phase, remaining) / 0.18, 0.0, 1.0))
			"recovery":
				gait_weight = _ease_in_out(clampf((1.0 - remaining / ATTACK_RECOVERY[index]) / 0.55, 0.0, 1.0))
	if gait_weight > 0.0:
		var gait := _locomotion_pose(facing_sign, player.velocity.length())
		rotation_offset += float(gait.x) * gait_weight
		scale_factor *= Vector2.ONE.lerp(Vector2(gait.y, gait.z), gait_weight)
	_attack_rotation = _base_rotation + rotation_offset
	_attack_scale = _base_scale * scale_factor

func _attack_phase_progress(index: int, phase: String, remaining: float) -> float:
	var duration := _attack_phase_duration(index, phase)
	return clampf((duration - remaining) / duration, 0.0, 1.0)

func _attack_phase_duration(index: int, phase: String) -> float:
	# Gameplay owns these phase boundaries. Registered frame durations are mapped
	# across this live window, so adding reviewed art cannot shift startup, the
	# active hitbox, or recovery away from the controller's timers.
	return ATTACK_STARTUP[index] if phase == "startup" else (ATTACK_ACTIVE[index] if phase == "active" else ATTACK_RECOVERY[index])

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
