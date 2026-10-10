extends SceneTree
"""Checks that Num4's VFX follows its real straight hitbox and clears safely."""

const PLAYER_SCENE := "res://scenes/player/player.tscn"
const EFFECT_SCRIPT := "res://scripts/effects/player_skill1_dash_visual.gd"
const CONTROLLER_SCRIPT := "res://scripts/player/player_controller.gd"

var _failures: Array[String] = []
var _player: CharacterBody2D
var _effect: Node2D
var _hit_received := false

class HitReceiver:
	extends StaticBody2D
	func _init() -> void:
		collision_layer = 2
		collision_mask = 0
		add_to_group("hit_receivers")
		var collision := CollisionShape2D.new()
		var shape := CircleShape2D.new()
		shape.radius = 18.0
		collision.shape = shape
		add_child(collision)
	func receive_hit(_hit: Dictionary) -> void:
		pass

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var effect_source := FileAccess.get_file_as_string(EFFECT_SCRIPT)
	var controller_source := FileAccess.get_file_as_string(CONTROLLER_SCRIPT)
	_check(effect_source.contains("Hitboxes/Skill1Hitbox") and effect_source.contains("box.rotation"), "direction comes from Skill1Hitbox transform")
	_check(effect_source.contains("_actual_contact_point") and effect_source.contains("box.get_overlapping_bodies()"), "hit pop uses the real accepted receiver position")
	_check(effect_source.contains("hitstun_remaining") and effect_source.contains("clear_effects") and effect_source.contains("player_hit"), "interruption and player hit clear transient VFX")
	_check(effect_source.contains("_draw_startup") and effect_source.contains("_draw_active") and effect_source.contains("_draw_recovery"), "all three skill phases have distinct straight-line cues")
	_check(not effect_source.contains("draw_arc") and not effect_source.contains("draw_circle(center"), "Num4 impact remains linear rather than radial")
	_check(controller_source.contains("skill_hit.emit(skill_id)") and controller_source.contains("_check_skill_hitbox()"), "visual signal remains downstream of the real skill overlap")
	var packed := load(PLAYER_SCENE) as PackedScene
	_check(packed != null, "real Player scene loads")
	if packed == null:
		_finish()
		return
	_player = packed.instantiate() as CharacterBody2D
	root.add_child(_player)
	_player.global_position = Vector2(900.0, 820.0)
	_player.set("facing_direction", Vector2.RIGHT)
	var receiver := HitReceiver.new()
	receiver.global_position = _player.global_position + Vector2(198.0, 0.0)
	root.add_child(receiver)
	_player.skill_hit.connect(_on_skill_hit)
	await process_frame
	await process_frame
	_effect = _player.get_node_or_null("Skill1DashVisual") as Node2D
	_check(_effect != null, "player visual animator installs Skill1DashVisual")
	var hitbox := _player.get_node("Hitboxes/Skill1Hitbox") as Area2D
	var shape_node := hitbox.get_node("CollisionShape2D") as CollisionShape2D
	var rect := shape_node.shape as RectangleShape2D
	_check(rect != null and rect.size == Vector2(108.0, 58.0), "dash VFX reads the existing 108x58 straight hitbox")
	_player.call("_request_skill", 1)
	await process_frame
	if _effect != null:
		_check(_effect.visible, "startup telegraph appears for Num4")
		for _attempt in range(180):
			if _hit_received:
				break
			await physics_frame
			await process_frame
		_check(_hit_received, "real Skill1Hitbox overlap emits skill_hit(1)")
		_check(float(_effect.get("_hit_flash_remaining")) > 0.0, "accepted hit signal produces the contact flash")
		_player.call("_cancel_skill")
		await process_frame
		_check(not _effect.visible, "skill cancellation leaves no residual trail")
		_player.set("skill_cooldowns", [0.0, 0.0])
		_player.call("_request_skill", 1)
		await process_frame
		_player.set("hitstun_remaining", 0.1)
		await process_frame
		_check(not _effect.visible, "hitstun immediately clears the dash trail")
	_finish()

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6k_skill1_dash_readability_smoke: PASS")
		quit(0)
		return
	for failure in _failures:
		push_error("m6k_skill1_dash_readability_smoke: " + failure)
	quit(1)

func _on_skill_hit(skill_id: int) -> void:
	if skill_id == 1:
		_hit_received = true
