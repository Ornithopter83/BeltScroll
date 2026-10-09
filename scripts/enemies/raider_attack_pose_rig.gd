extends Node2D
"""Procedural attack limb overlays; presentation is a rig animation, not new frame art."""

@onready var raider: CharacterBody2D = get_parent().get_parent() as CharacterBody2D
@onready var art: Sprite2D = raider.get_node("VisualRoot/RaiderArt") as Sprite2D
@onready var punch_arm: Node2D = $PunchArmPivot

var _home_position := Vector2(-113.0, -204.0)
var _home_rotation := 0.0
var _home_scale := Vector2.ONE

func _ready() -> void:
	# This rig uses the source illustration's pixel coordinate system, so the
	# overlays track its authored scale and mirror with VisualRoot's facing flip.
	position = art.position
	scale = art.scale
	_home_position = punch_arm.position
	_home_rotation = punch_arm.rotation
	_home_scale = punch_arm.scale

func apply_attack_pose(phase: String, remaining: float, windup_duration: float, active_duration: float, recovery_duration: float) -> void:
	_sync_to_artwork()
	var offset := Vector2.ZERO
	var angle := _home_rotation
	var fist_scale := _home_scale
	match phase:
		"windup":
			var progress := 1.0 - clampf(remaining / maxf(windup_duration, 0.001), 0.0, 1.0)
			var anticipation := sin(progress * PI * 0.5)
			# Pull the guard back from its resting silhouette before the strike.
			offset = Vector2(45.0, 12.0) * anticipation
			angle += 0.19 * anticipation
			fist_scale = _home_scale * Vector2.ONE.lerp(Vector2(0.92, 1.04), anticipation)
		"active":
			var progress := clampf(1.0 - remaining / maxf(active_duration, 0.001), 0.0, 1.0)
			# The arm reaches ahead of the source fist; the whole illustration is
			# tilted by VisualAnimator to make the torso drive through the hit.
			var thrust := sin(progress * PI * 0.5)
			offset = Vector2(-116.0, -13.0) * thrust
			angle -= 0.22 * thrust
			fist_scale = _home_scale * Vector2.ONE.lerp(Vector2(1.1, 0.92), thrust)
		"recovery":
			var recovery := 1.0 - clampf(remaining / maxf(recovery_duration, 0.001), 0.0, 1.0)
			var settle := 1.0 - recovery
			offset = Vector2(-116.0, -13.0) * settle
			angle -= 0.22 * settle
			fist_scale = _home_scale * Vector2.ONE.lerp(Vector2(1.1, 0.92), settle)

	punch_arm.position = _home_position + offset
	punch_arm.rotation = angle
	punch_arm.scale = fist_scale

func reset_pose() -> void:
	_sync_to_artwork()
	punch_arm.position = _home_position
	punch_arm.rotation = _home_rotation
	punch_arm.scale = _home_scale

func _sync_to_artwork() -> void:
	# The review sheet intentionally rescales the sprite; follow its transform so
	# the overlays stay registered at both authored and capture presentation sizes.
	position = art.position
	rotation = art.rotation
	scale = art.scale
