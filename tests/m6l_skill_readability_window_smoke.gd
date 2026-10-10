extends SceneTree
"""Runtime smoke for the F6 skill readability lab and its real Player state."""

const LAB_SCENE := "res://scenes/review/m6l_skill_readability_lab.tscn"
const PLAYER_SCRIPT := "res://scripts/player/player_controller.gd"
const CANDIDATE_4 := "res://assets/art/player/elven_fighter_skill1_rush_contact_v1_candidate_1254x1254.png"
const CANDIDATE_5 := "res://assets/art/player/elven_fighter_skill2_spin_backfist_v2_candidate_1254x1254.png"

var _failures: Array[String] = []
var _lab: Node2D
var _players: Array = []
var _dummies: Array = []
var _max_num5_rotation_abs := 0.0
var _max_num5_rotation_step := 0.0
var _last_num5_rotation := NAN

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	_check(ResourceLoader.exists(LAB_SCENE), "F6 review scene exists")
	_check(ResourceLoader.exists(CANDIDATE_4) and ResourceLoader.exists(CANDIDATE_5), "separate unapproved art references exist")
	var packed := load(LAB_SCENE) as PackedScene
	if packed == null:
		_finish()
		return
	_lab = packed.instantiate() as Node2D
	root.add_child(_lab)
	await process_frame
	await physics_frame
	_players = _lab.call("get_review_players")
	_dummies = _lab.call("get_review_dummies")
	_check(_players.size() == 2, "lab builds a side-by-side pair")
	if _players.size() != 2:
		_finish()
		return
	for index in range(2):
		var player: CharacterBody2D = _players[index]
		_check(player.get_script().resource_path.ends_with(PLAYER_SCRIPT), "lane %d uses production Player controller" % (index + 1))
		_check(player.get_node_or_null("VisualRoot/PlayerArt") is Sprite2D, "lane %d shows production Player silhouette" % (index + 1))
		_check(player.get_node_or_null("Skill1DashVisual") != null and player.get_node_or_null("Skill2SpinVisual") != null, "lane %d installs production skill VFX" % (index + 1))
	_check(_shape_size(_players[0], "Skill1Hitbox") == Vector2(108.0, 58.0), "Num4 displays the actual straight hitbox shape")
	_check(_shape_size(_players[1], "Skill2Hitbox") == Vector2(64.0, 64.0), "Num5 displays the actual circular hitbox shape")

	var num4_start_x: float = _players[0].global_position.x
	_lab.call("_play_skill", 0, 1)
	_check(str(_players[0].get("skill_phase")) == "startup", "Num4 starts the real Player startup")
	var num4_active := await _wait_for_phase(_players[0], "active", 70)
	_check(num4_active, "Num4 advances to its active phase")
	_check((_players[0].get_node("Hitboxes/Skill1Hitbox") as Area2D).monitoring, "Num4 actual hitbox turns on during active")
	_check(_players[0].global_position.x > num4_start_x + 70.0, "Num4 actual Player lunges forward")
	var num4_hit := await _wait_for_target_hit(0, 45)
	_check(num4_hit, "Num4 actual rectangle hitbox reaches its live target")
	var num4_finished := await _wait_for_phase(_players[0], "idle", 90)
	_check(num4_finished, "Num4 completes recovery")
	await process_frame
	await RenderingServer.frame_post_draw
	_check(not bool(_players[0].get_node("Skill1DashVisual").get("visible")), "Num4 VFX clears after completion")

	var num5_start: Vector2 = _players[1].global_position
	_lab.call("_play_skill", 1, 2)
	_check(str(_players[1].get("skill_phase")) == "startup", "Num5 starts the real Player startup")
	var num5_active := await _wait_for_phase(_players[1], "active", 80)
	_check(num5_active, "Num5 advances to its active phase")
	_check((_players[1].get_node("Hitboxes/Skill2Hitbox") as Area2D).monitoring, "Num5 actual hitbox turns on during active")
	_check(_players[1].global_position.distance_to(num5_start) < 8.0, "Num5 stays planted while rotating")
	_check(bool(_players[1].get_node("Skill2SpinVisual").get("visible")), "Num5 body rotation and orbit cue are visible")
	var num5_hit := await _wait_for_target_hit(1, 45)
	_check(num5_hit, "Num5 actual circular hitbox reaches its live target")
	var num5_finished := await _wait_for_phase(_players[1], "idle", 100)
	_check(num5_finished, "Num5 completes recovery")
	await process_frame
	await RenderingServer.frame_post_draw
	_check(not bool(_players[1].get_node("Skill2SpinVisual").get("visible")), "Num5 VFX clears after completion")
	print("M6L_SKILL_ROTATION|max_abs=%.5f|max_step=%.5f|final=%.5f" % [_max_num5_rotation_abs, _max_num5_rotation_step, (_players[1].get_node("VisualRoot/PlayerArt") as Sprite2D).rotation])
	_check(_max_num5_rotation_abs < 1.0, "Num5 keeps its full-body silhouette within a readable pivoted turn")
	_check(_max_num5_rotation_step < 0.8, "Num5 rotation remains continuous through active-to-recovery")

	for interruption in ["cancel", "hit", "ko"]:
		_lab.call("_reset_lab")
		_lab.call("_play_skill", 0, 1)
		await process_frame
		match interruption:
			"cancel": _lab.call("_cancel_skills")
			"hit": _lab.call("_interrupt_players", false)
			"ko": _lab.call("_interrupt_players", true)
		await process_frame
		_check(not bool(_players[0].get_node("Skill1DashVisual").get("visible")), "Num4 effect clears after %s" % interruption)
		_check(not bool(_players[1].get_node("Skill2SpinVisual").get("visible")), "Num5 effect clears after %s" % interruption)
	_lab.queue_free()
	_finish()

func _wait_for_phase(player: CharacterBody2D, phase: String, frames: int) -> bool:
	for _frame in range(frames):
		if str(player.get("skill_phase")) == phase:
			return true
		await physics_frame
		if _players.size() > 1 and player == _players[1]:
			var art := player.get_node("VisualRoot/PlayerArt") as Sprite2D
			var rotation := art.rotation
			if absf(rotation) > 0.7:
				print("M6L_SKILL_ROTATION_SAMPLE|%s|%.5f|remaining=%.5f" % [str(player.get("skill_phase")), rotation, float(player.get("skill_phase_remaining"))])
			_max_num5_rotation_abs = maxf(_max_num5_rotation_abs, absf(rotation))
			if is_finite(_last_num5_rotation):
				_max_num5_rotation_step = maxf(_max_num5_rotation_step, absf(rotation - _last_num5_rotation))
			_last_num5_rotation = rotation
	return str(player.get("skill_phase")) == phase

func _wait_for_target_hit(index: int, frames: int) -> bool:
	for _frame in range(frames):
		if _has_target_hit(index):
			return true
		await physics_frame
	return _has_target_hit(index)

func _has_target_hit(index: int) -> bool:
	var hit: Dictionary = _dummies[index].get("last_hit")
	return not hit.is_empty()

func _shape_size(player: CharacterBody2D, name: String) -> Vector2:
	var collision := player.get_node("Hitboxes/%s/CollisionShape2D" % name) as CollisionShape2D
	if collision.shape is RectangleShape2D:
		return (collision.shape as RectangleShape2D).size
	if collision.shape is CircleShape2D:
		var radius := (collision.shape as CircleShape2D).radius
		return Vector2(radius, radius)
	return Vector2.ZERO

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
		push_error("m6l_skill_readability_window_smoke: " + description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6l_skill_readability_window_smoke: PASS")
		quit(0)
	else:
		quit(1)
