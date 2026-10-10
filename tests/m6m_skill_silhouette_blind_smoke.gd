extends SceneTree
"""Smoke checks for the M6M effect-free silhouette review controls."""

const LAB_SCENE := "res://scenes/review/m6l_skill_readability_lab.tscn"
var _failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var packed := load(LAB_SCENE) as PackedScene
	_check(packed != null, "existing M6L F6 lab scene loads")
	if packed == null:
		_finish()
		return
	var lab := packed.instantiate() as Node2D
	root.add_child(lab)
	await process_frame
	await process_frame
	var players: Array = lab.call("get_review_players")
	var overlay = lab.get_node_or_null("SilhouetteAxisAndHitboxGuides")
	_check(players.size() == 2, "Num4 and Num5 share one comparison lab")
	_check(get_root().get_viewport().size == Vector2i(1920, 1080), "comparison keeps a fixed 1920×1080 viewport")
	_check(overlay != null, "motion guide overlay exists")
	if players.size() != 2 or overlay == null:
		lab.queue_free()
		_finish()
		return

	var title_nodes: Array = lab.get("_skill_name_labels")
	_check(title_nodes.size() >= 4, "all technical name and candidate caption controls are tracked")
	_press(lab, KEY_E)
	_check(not bool(lab.get("_effects_visible")), "E hides both production skill effects")
	for player: CharacterBody2D in players:
		for effect_name in ["Skill1DashVisual", "Skill2SpinVisual"]:
			var effect := player.get_node_or_null(effect_name) as CanvasItem
			_check(effect == null or is_zero_approx(effect.modulate.a), "%s is hidden with effects" % effect_name)
	_press(lab, KEY_N)
	_check(not bool(lab.get("_names_visible")), "N hides technical skill labels")
	for node: Control in title_nodes:
		_check(not node.visible, "tracked skill name or candidate caption is hidden")
	_press(lab, KEY_B)
	_check(not bool(overlay.get("hitbox_outline_visible")), "B hides both judgment outlines")
	for key in [KEY_1, KEY_2, KEY_3, KEY_0]:
		var field := _guide_field(key)
		var before := bool(overlay.get(field))
		_press(lab, key)
		_check(bool(overlay.get(field)) != before, "%s guide toggles independently" % field)
	_press(lab, KEY_3)
	_check(bool(overlay.get("guide_fist_visible")) and not bool(overlay.get("hitbox_outline_visible")), "Num5 fist arc can show while its circular hitbox outline stays hidden")

	_press(lab, KEY_4)
	_check(str((players[0] as CharacterBody2D).get("skill_phase")) == "startup", "Num4 starts at prepare phase")
	_press(lab, KEY_P)
	_check(bool(lab.get("_paused")) and paused, "P pauses the review")
	_press(lab, KEY_P)
	_check(not bool(lab.get("_paused")) and not paused, "P resumes the review")
	_press(lab, KEY_R)
	_press(lab, KEY_5)
	_check(str((players[1] as CharacterBody2D).get("skill_phase")) == "startup", "Num5 can be replayed after reset")
	var art := (players[1] as CharacterBody2D).get_node("VisualRoot/PlayerArt") as Sprite2D
	_check(is_finite(art.rotation), "Num5 body rotation can be inspected independently")

	lab.queue_free()
	_finish()

func _press(lab: Node, key: int) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.pressed = true
	lab.call("_unhandled_key_input", event)

func _guide_field(key: int) -> String:
	match key:
		KEY_1: return "guide_distance_visible"
		KEY_2: return "guide_torso_visible"
		KEY_3: return "guide_fist_visible"
		KEY_0: return "guide_pivot_visible"
	return ""

func _check(condition: bool, description: String) -> void:
	if condition:
		print("PASS: " + description)
	else:
		_failures.append(description)
		push_error("m6m_skill_silhouette_blind_smoke: " + description)

func _finish() -> void:
	if _failures.is_empty():
		print("m6m_skill_silhouette_blind_smoke: PASS")
		quit(0)
	else:
		quit(1)
