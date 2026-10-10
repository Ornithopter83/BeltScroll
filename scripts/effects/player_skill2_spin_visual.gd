extends Node2D
"""Temporary procedural Num5 spin telegraph and contact VFX."""

const STARTUP_DURATION := 0.22
const ACTIVE_DURATION := 0.18
const RECOVERY_DURATION := 0.55
const VIOLET := Color("#e8a4ff")
const PINK := Color("#ff76bc")
const WHITE := Color("#fff4ff")
const IMPACT := Color("#ffd58a")
const AXIS := Color("#fff0c7")
const HIT_FLASH_DURATION := 0.20

var _player: CharacterBody2D
var _player_art: Sprite2D
var _hit_flash_remaining := 0.0
var _silhouette_rotation_offset := 0.0
var _silhouette_position_offset := Vector2.ZERO
var _art_support_from_center := Vector2.ZERO

func _ready() -> void:
	_player = get_parent() as CharacterBody2D
	_player_art = _player.get_node_or_null("VisualRoot/PlayerArt") as Sprite2D if _player != null else null
	if is_instance_valid(_player_art) and _player_art.texture != null:
		var texture_size := Vector2(_player_art.texture.get_size())
		var alpha_bounds := _player_art.texture.get_image().get_used_rect()
		var alpha_foot := Vector2(float(alpha_bounds.position.x) + float(alpha_bounds.size.x) * 0.5, float(alpha_bounds.end.y))
		_art_support_from_center = (alpha_foot - texture_size * 0.5) * _player_art.scale
	process_priority = 1
	z_index = 4
	visible = false

func _process(delta: float) -> void:
	if not is_instance_valid(_player):
		clear_effects()
		return
	var phase := str(_player.get("skill_phase"))
	var interrupted: bool = _player.get("is_ko") == true or float(_player.get("hitstun_remaining")) > 0.0
	var valid_phase := int(_player.get("skill_id")) == 2 and phase in ["startup", "active", "recovery"]
	if interrupted or not valid_phase:
		_restore_silhouette_rotation(true)
		_hit_flash_remaining = 0.0
		visible = false
		queue_redraw()
		return
	_update_silhouette_rotation(phase)
	_hit_flash_remaining = maxf(0.0, _hit_flash_remaining - maxf(delta, 0.0))
	visible = true
	queue_redraw()

func on_skill_hit(skill_id: int) -> void:
	if skill_id != 2 or not is_instance_valid(_player):
		return
	var actual_hitbox := _player.get_node_or_null("Hitboxes/Skill2Hitbox") as Area2D
	if actual_hitbox == null or not actual_hitbox.monitoring:
		return
	_hit_flash_remaining = HIT_FLASH_DURATION
	queue_redraw()

func clear_effects(_unused: Variant = null) -> void:
	_restore_silhouette_rotation()
	_hit_flash_remaining = 0.0
	visible = false
	queue_redraw()

func _update_silhouette_rotation(phase: String) -> void:
	if not is_instance_valid(_player_art):
		return
	var animator_controls_pose := _player.get_node_or_null("VisualAnimator") != null
	if animator_controls_pose:
		# PlayerVisualAnimator owns the full PlayerArt transform when present.
		# Re-applying this effect's previous offset here accumulates another turn
		# every frame and can rotate the fighter upside down during recovery.
		_silhouette_rotation_offset = 0.0
		_silhouette_position_offset = Vector2.ZERO
		return
	_player_art.rotation -= _silhouette_rotation_offset
	_player_art.position -= _silhouette_position_offset
	_silhouette_rotation_offset = 0.0
	_silhouette_position_offset = Vector2.ZERO
	var base_rotation := _player_art.rotation
	var base_position := _player_art.position
	var facing := -1.0 if float(_player.get("facing_direction").x) < 0.0 else 1.0
	var remaining := maxf(0.0, float(_player.get("skill_phase_remaining")))
	var progress := 0.0
	match phase:
		"startup":
			progress = clampf((STARTUP_DURATION - remaining) / STARTUP_DURATION, 0.0, 1.0)
			_silhouette_rotation_offset = -facing * 0.48 * _smooth(progress)
		"active":
			progress = clampf((ACTIVE_DURATION - remaining) / ACTIVE_DURATION, 0.0, 1.0)
			# Counter-twist first, then drive the shoulder line through the radial strike.
			_silhouette_rotation_offset = -facing * (0.42 + 0.52 * sin(progress * PI))
		"recovery":
			progress = clampf((RECOVERY_DURATION - remaining) / RECOVERY_DURATION, 0.0, 1.0)
			_silhouette_rotation_offset = -facing * 0.48 * (1.0 - _smooth(progress))
	var support_before := base_position + _art_support_from_center.rotated(base_rotation)
	var support_after := base_position + _art_support_from_center.rotated(base_rotation + _silhouette_rotation_offset)
	_silhouette_position_offset = support_before - support_after
	_player_art.rotation = base_rotation + _silhouette_rotation_offset
	_player_art.position = base_position + _silhouette_position_offset

func _restore_silhouette_rotation(animator_refreshed := false) -> void:
	if is_instance_valid(_player_art):
		var animator_controls_pose := is_instance_valid(_player) and _player.get_node_or_null("VisualAnimator") != null
		if not animator_refreshed or not animator_controls_pose:
			_player_art.rotation -= _silhouette_rotation_offset
			_player_art.position -= _silhouette_position_offset
	_silhouette_rotation_offset = 0.0
	_silhouette_position_offset = Vector2.ZERO

func _draw() -> void:
	if not visible or not is_instance_valid(_player):
		return
	var phase := str(_player.get("skill_phase"))
	var facing := -1.0 if float(_player.get("facing_direction").x) < 0.0 else 1.0
	var duration := STARTUP_DURATION if phase == "startup" else (ACTIVE_DURATION if phase == "active" else RECOVERY_DURATION)
	var progress := clampf((duration - maxf(0.0, float(_player.get("skill_phase_remaining")))) / duration, 0.0, 1.0)
	match phase:
		"startup":
			_draw_startup(facing, progress)
		"active":
			_draw_active(facing, progress)
		"recovery":
			_draw_recovery(facing, progress)
	if _hit_flash_remaining > 0.0:
		_draw_contact_impact()

func _draw_startup(facing: float, progress: float) -> void:
	var load := _smooth(progress)
	var center := Vector2(0.0, -208.0)
	var radius := 78.0 + 17.0 * load
	# The shoulders visibly load against the facing direction while the pivot stays over the planted feet.
	var twist := -facing * lerpf(0.04, 0.52, load)
	_draw_torso_axis(center, twist, Color(WHITE, 0.24 + load * 0.48), 3.0)
	_draw_arc(center, radius, -facing * 0.06 * PI, -facing * (0.18 + 0.48 * load) * PI, Color(VIOLET, 0.35 + load * 0.48), 4.0)
	_draw_arc(center, radius - 11.0, -facing * 0.05 * PI, -facing * (0.12 + 0.38 * load) * PI, Color(WHITE, 0.20 + load * 0.36), 1.8)
	var shoulder := center + Vector2(-facing * 18.0, -31.0)
	var elbow := center + Vector2(-facing * (42.0 + 13.0 * load), 4.0)
	var fist_angle := -facing * lerpf(0.12 * PI, 0.58 * PI, load)
	var fist := center + Vector2(cos(fist_angle), sin(fist_angle)) * (radius + 10.0)
	_draw_backfist_arm(shoulder, elbow, fist, Color(PINK, 0.42 + load * 0.44), 5.0)
	_draw_direction_arrow(center, radius, -facing, Color(PINK, 0.86))
	# Ground pivot remains fixed as the shoulder/arm cue winds backward.
	draw_arc(Vector2(0.0, -8.0), 38.0 + 8.0 * load, 0.0, TAU, 32, Color(VIOLET, 0.30 + load * 0.40), 2.5, true)
	draw_circle(Vector2(0.0, -8.0), 4.0, Color(AXIS, 0.65))

func _draw_active(facing: float, progress: float) -> void:
	var center := Vector2(0.0, -208.0)
	var eased := _ease_out(progress)
	var radius := 104.0
	# Start behind the shoulder and sweep across the front at torso height, matching the radial hitbox.
	var rotation := facing * lerpf(PI, TAU, eased)
	var sweep := lerpf(0.26 * PI, 0.72 * PI, eased)
	_draw_arc(center, radius + 15.0, rotation - facing * sweep * 0.90, rotation, Color(VIOLET, 0.30), 3.0)
	_draw_arc(center, radius, rotation - facing * sweep, rotation, Color(PINK, 0.92), 6.0)
	_draw_arc(center, radius - 10.0, rotation - facing * sweep * 0.56, rotation, Color(WHITE, 0.80), 2.2)
	_draw_torso_axis(center, facing * lerpf(0.35, -0.50, eased), Color(WHITE, 0.56), 3.2)
	var shoulder := center + Vector2(facing * 17.0, -31.0)
	var elbow_angle := rotation - facing * 0.26 * PI
	var elbow := center + Vector2(cos(elbow_angle), sin(elbow_angle)) * 45.0
	var fist := center + Vector2(cos(rotation), sin(rotation)) * radius
	_draw_backfist_arm(shoulder, elbow, fist, Color(PINK, 0.92), 7.0)
	# Knuckle bars are tangent to the hand's travel, identifying the strike as a backfist rather than a jab.
	var tangent := Vector2(-sin(rotation), cos(rotation)) * -facing
	draw_line(fist - tangent * 10.0, fist + tangent * 10.0, Color(WHITE, 0.98), 3.0, true)
	draw_circle(fist, 8.0, Color(WHITE, 0.92))
	draw_circle(fist, 4.0, Color(PINK, 0.98))
	_draw_direction_arrow(center, radius + 2.0, facing, Color(WHITE, 0.92))
	# Elliptical perspective keeps the pivot under the body while the arm traces a broad horizontal orbit.
	draw_arc(Vector2(0.0, -8.0), 57.0 + 8.0 * sin(progress * PI), -facing * 0.10 * PI, facing * 1.90 * PI, 40, Color(VIOLET, 0.58), 3.2, true)
	draw_line(Vector2(-14.0, -8.0), Vector2(14.0, -8.0), Color(AXIS, 0.86), 2.4, true)
	draw_circle(Vector2.ZERO, 4.5, Color(AXIS, 0.92))

func _draw_recovery(facing: float, progress: float) -> void:
	var ease := _smooth(progress)
	var fade := 1.0 - ease
	var center := Vector2(0.0, -208.0)
	# Counter-rotate through a shrinking angle and shrinking radius so both spin and deceleration read.
	var unwind := facing * lerpf(0.76 * PI, 0.035 * PI, ease)
	var radius := lerpf(112.0, 61.0, ease)
	_draw_arc(center, radius, unwind - facing * lerpf(0.58 * PI, 0.10 * PI, ease), unwind, Color(PINK, 0.86 * fade), 5.0 * fade + 0.55)
	_draw_arc(center, radius - 12.0, unwind - facing * lerpf(0.38 * PI, 0.06 * PI, ease), unwind, Color(WHITE, 0.62 * fade), 2.2 * fade + 0.35)
	_draw_torso_axis(center, -facing * lerpf(0.42, 0.02, ease), Color(WHITE, 0.42 * fade), 2.8)
	var shoulder := center + Vector2(facing * 17.0, -31.0)
	var fist := center + Vector2(cos(unwind), sin(unwind)) * radius
	var elbow := center.lerp(fist, 0.53) + Vector2(0.0, -10.0)
	_draw_backfist_arm(shoulder, elbow, fist, Color(PINK, 0.62 * fade), 5.0 * fade + 0.5)
	_draw_direction_arrow(center, radius, -facing, Color(WHITE, 0.58 * fade))
	var ring_radius := lerpf(66.0, 35.0, ease)
	draw_arc(Vector2(0.0, -8.0), ring_radius, 0.0, TAU, 40, Color(VIOLET, 0.68 * fade), 3.0 * fade + 0.35, true)
	draw_arc(Vector2(0.0, -8.0), ring_radius + 8.0, -facing * 0.08 * PI, facing * lerpf(1.25, 0.30, ease) * PI, 30, Color(PINK, 0.42 * fade), 2.1 * fade + 0.3, true)
	draw_circle(Vector2.ZERO, 4.0, Color(AXIS, 0.48 * fade))

func _draw_contact_impact() -> void:
	var fade := clampf(_hit_flash_remaining / HIT_FLASH_DURATION, 0.0, 1.0)
	var progress := 1.0 - fade
	var center := Vector2(0.0, -205.0)
	var radius := 18.0 + progress * 37.0
	draw_arc(center, radius, 0.0, TAU, 32, Color(IMPACT, fade * 0.95), 3.5 * fade + 0.5, true)
	draw_arc(center, radius * 0.68, 0.0, TAU, 28, Color(WHITE, fade * 0.72), 1.7 * fade + 0.4, true)
	for index in range(8):
		var angle := TAU * float(index) / 8.0
		var direction := Vector2(cos(angle), sin(angle))
		draw_line(center + direction * (radius + 3.0), center + direction * (radius + 10.0), Color(IMPACT, fade), 2.0, true)

func _draw_arc(center: Vector2, radius: float, start_angle: float, end_angle: float, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	var segment_count := 28
	for index in range(segment_count + 1):
		var ratio := float(index) / float(segment_count)
		var angle := lerpf(start_angle, end_angle, ratio)
		points.append(center + Vector2(cos(angle), sin(angle)) * radius)
	draw_polyline(points, color, width, true)

func _draw_backfist_arm(shoulder: Vector2, elbow: Vector2, fist: Vector2, color: Color, width: float) -> void:
	# Draw over the sprite silhouette: shoulder -> bent elbow -> knuckles ties the trail to the actual fighter.
	draw_line(shoulder, elbow, Color(VIOLET, color.a * 0.82), width + 3.0, true)
	draw_line(elbow, fist, color, width, true)
	draw_circle(shoulder, 6.0, Color(WHITE, color.a * 0.74))
	draw_circle(elbow, 5.0, Color(VIOLET, color.a * 0.88))

func _draw_torso_axis(center: Vector2, angle: float, color: Color, width: float) -> void:
	var axis := Vector2(cos(angle), sin(angle))
	var across := Vector2(-axis.y, axis.x)
	var shoulder_mid := center + Vector2(0.0, -37.0)
	var shoulder_span := 28.0
	var shoulder_axis := across.rotated(angle * 0.8)
	var pelvis_axis := Vector2.RIGHT
	draw_line(shoulder_mid - shoulder_axis * shoulder_span, shoulder_mid + shoulder_axis * shoulder_span, color, width, true)
	draw_line(center + Vector2(0.0, -2.0) - pelvis_axis * 21.0, center + Vector2(0.0, -2.0) + pelvis_axis * 21.0, Color(VIOLET, color.a * 0.85), width, true)
	draw_line(shoulder_mid, center + Vector2(0.0, -2.0), Color(WHITE, color.a * 0.72), maxf(1.0, width - 1.2), true)
	draw_circle(center + Vector2(0.0, -2.0), 3.5, color)

func _draw_direction_arrow(center: Vector2, radius: float, direction: float, color: Color) -> void:
	var angle := direction * 0.22 * PI
	var point := center + Vector2(cos(angle), sin(angle)) * radius
	var tangent := Vector2(-sin(angle), cos(angle)) * direction
	draw_line(point - tangent * 12.0, point + tangent * 12.0, color, 3.0, true)
	draw_line(point + tangent * 12.0, point + tangent * 12.0 - tangent.rotated(-direction * 0.72) * 8.0, color, 2.4, true)

func _smooth(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return t * t * (3.0 - 2.0 * t)

func _ease_out(value: float) -> float:
	var t := clampf(value, 0.0, 1.0)
	return 1.0 - (1.0 - t) * (1.0 - t)
